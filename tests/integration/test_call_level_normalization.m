function tests = test_call_level_normalization
%TEST_CALL_LEVEL_NORMALIZATION Phase 6.7: normalized levels and the level difference.
%
% One synthetic two-channel WAV, 1000 Hz, 4 s, 24-bit. Channel 2's gain is half
% channel 1's for every source, so the channels deliberately disagree about the
% same sound by a factor of 4 in power (6.02 dB):
%
%   detection 1  [0.2, 0.6)  250 Hz call, ch1 0.4, ch2 0.2   (one source, both channels)
%   noise-1      [1.0, 1.4)  tones 220/240/260/280 Hz, each 0.1 on ch1, 0.05 on ch2
%   noise-2      [1.4, 1.8)  identical to noise-1
%   noise-3      [1.8, 2.2)  the same tones at 1.5x (for a divergent family)
%   tone-1       [2.2, 2.6)  250 Hz, ch1 0.3, ch2 0.15
%   detection 2  [2.6, 3.0)  ch1 1.5 x sine clipped to [-1, 1]; ch2 0.2
%   detection 3  [3.8, 4.3)  ch1 0.3, ch2 0.15; the file ends at 4.0 s
%
% Every reference declares the band [200, 300] Hz. Band powers are exact: the
% noise family has 4 x 0.1^2 / 2 = 0.02 on ch1 and 0.005 on ch2, and the call
% has 0.08 and 0.02, so both channels normalize to 4 and the normalized
% difference is 0 dB.
tests = functiontests(localfunctions);
end

% ------------------------------------------------- normalization works ---

function testUnequalGainsNormalizeToEqualLevels(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");
result = vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=f.call_runs.d1), struct(analysis_run_id=response), ...
    RepoRoot=f.repo_root);
verifyEqual(testCase, result.status, "completed");
verifyEqual(testCase, result.outcomes.status, ["normalized"; "normalized"]);
verifyEqual(testCase, result.outcomes.unit, ["ratio_to_channel_response"; ...
    "ratio_to_channel_response"]);
verifyEqual(testCase, result.outcomes.value, [4; 4], AbsTol=1e-6);
verifyEqual(testCase, result.outcomes.response_value, [0.02; 0.005], AbsTol=1e-7);

raw = 10 * log10(result.outcomes.source_value(1) / result.outcomes.source_value(2));
verifyEqual(testCase, raw, 10 * log10(4), ...
    "The raw channels disagree by the gain ratio.", AbsTol=1e-5);
difference = vawlume.acoustic.levelDifference(result.outcomes(1, :), ...
    result.outcomes(2, :), true);
verifyEqual(testCase, difference.status, "computed");
verifyEqual(testCase, difference.value, 0, ...
    "Normalization removes the channels' own response difference.", AbsTol=1e-5);
verifyEqual(testCase, difference.unit, "dB");
clear cleanup
end

function testTheShippedPolicyIsDeclaredUncalibrated(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
policy = jsondecode(fileread(fullfile(f.repo_root, "config", ...
    "09_acoustic_normalization_policies", "band_matched_noise_reference_v1.json")));
verifyEqual(testCase, string(policy.profile.kind), "analysis_settings");
verifyEqual(testCase, string(policy.calibration_status.state), "uncalibrated");
verifyEqual(testCase, string(policy.extractor_reported_power.state), "not_used");
verifyEqual(testCase, string(policy.comparability.scope), "within_recording");
verifyNotEmpty(testCase, policy.what_this_is_not);
verifyTrue(testCase, any(contains(string(policy.what_this_is_not), "not an absolute level")));
verifyTrue(testCase, any(contains(string(policy.what_this_is_not), "calibration")));
verifyTrue(testCase, any(contains(string(policy.what_this_is_not), "across recordings")));
statuses = string(fieldnames(policy.response_qc_status_handling));
verifyTrue(testCase, all(ismember(["ok" "divergent" "source_qc_warning" ...
    "insufficient_evidence" "not_comparable"], statuses)));
clear cleanup
end

% ------------------------------------------------------------ refusals ---

function testAnotherRecordingsEstimateIsRefusedByName(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
foreign = foreignRecordingEstimate(f);
verifyError(testCase, @() vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=f.call_runs.d1), struct(analysis_run_id=foreign), ...
    RepoRoot=f.repo_root), "vawlume:acoustic:NormalizationRecordingMismatch");
clear cleanup
end

function testMetricFamilyAndBandMismatchesAreRefusedPerChannel(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
% Metric: an estimate of RMS only.
rms = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-rms", Metric="acoustic_rms_amplitude");
verifyEqual(testCase, normalizeWith(f, f.call_runs.d1, rms).outcomes.reason, ...
    ["response_metric_mismatch"; "response_metric_mismatch"]);
% Family: a tone estimate is never substituted for the declared noise family.
tone = estimate(f, "tone-1", [1 2], "resp-tone", MinReferences=1, Types="tone");
result = normalizeWith(f, f.call_runs.d1, tone);
verifyEqual(testCase, result.outcomes.reason, ...
    ["response_family_mismatch"; "response_family_mismatch"]);
verifyTrue(testCase, all(isnan(result.outcomes.value)));
verifyEqual(testCase, result.status, "failed");
% Band: a call measured over [210, 300] does not match a [200, 300] estimate.
ok = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");
narrow = vawlume.acoustic.measureCallWindow(f.conn, struct(detection_id=1), [1 2], ...
    BandHz=[210 300], SourceRoot=f.source_root, Apply=true, RunKey="call-d1-narrow");
verifyEqual(testCase, normalizeWith(f, narrow.analysis_run_id, ok).outcomes.reason, ...
    ["response_band_mismatch"; "response_band_mismatch"]);
clear cleanup
end

function testAChannelWithNoEstimateHasNoValueAndAReason(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
onlyFirst = estimate(f, ["noise-1" "noise-2"], 1, "resp-ch1");
result = normalizeWith(f, f.call_runs.d1, onlyFirst);
verifyEqual(testCase, result.outcomes.status, ["normalized"; "not_normalized"]);
verifyEqual(testCase, result.outcomes.reason(2), "no_response_estimate");
verifyTrue(testCase, isnan(result.outcomes.value(2)));
verifyEqual(testCase, result.outcomes.unit(2), "", ...
    "An unnormalized channel is never labelled with the normalized unit.");
verifyEqual(testCase, result.status, "completed_with_warnings");
difference = vawlume.acoustic.levelDifference(result.outcomes(1, :), ...
    result.outcomes(2, :), true);
verifyEqual(testCase, difference.status, "refused");
verifyEqual(testCase, difference.reason, "b_missing");
verifyEqual(testCase, difference.reason_b, "no_response_estimate");
clear cleanup
end

function testEachResponseQcStatusIsHandledAsThePolicyDeclares(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
% divergent -> used, flagged.
divergent = estimate(f, ["noise-1" "noise-3"], [1 2], "resp-divergent");
result = normalizeWith(f, f.call_runs.d1, divergent);
verifyEqual(testCase, result.outcomes.response_qc_status, ["divergent"; "divergent"]);
verifyEqual(testCase, result.outcomes.status, ["normalized"; "normalized"]);
verifyTrue(testCase, all(cellfun(@(c) any(c == "response_divergent"), result.outcomes.qc_flags)));
verifyEqual(testCase, result.status, "completed_with_warnings");

% insufficient_evidence -> excluded, with the policy's reason code.
insufficient = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-insufficient", MinReferences=3);
result = normalizeWith(f, f.call_runs.d1, insufficient);
verifyEqual(testCase, result.outcomes.response_qc_status, ...
    ["insufficient_evidence"; "insufficient_evidence"]);
verifyEqual(testCase, result.outcomes.reason, ...
    ["response_insufficient_evidence"; "response_insufficient_evidence"]);
verifyTrue(testCase, all(isnan(result.outcomes.value)));

% not_comparable -> excluded. Channel 2 saw only one of channel 1's references.
ids = [referenceIds(f, ["noise-1" "noise-2"], 1); referenceIds(f, "noise-1", 2)];
unpaired = vawlume.acoustic.estimateChannelResponse(f.conn, struct(recording_id=1), ...
    ids, RequiredReferenceTypes="noise", MinReferences=1, Apply=true, ...
    RunKey="resp-unpaired").analysis_run_id;
result = normalizeWith(f, f.call_runs.d1, unpaired);
verifyEqual(testCase, result.outcomes.response_qc_status, ["not_comparable"; "not_comparable"]);
verifyEqual(testCase, result.outcomes.reason, ...
    ["response_not_comparable"; "response_not_comparable"]);

% source_qc_warning -> used, flagged. The estimate deliberately retained a
% reference measurement whose run warned.
execute(f.conn, "UPDATE analysis_runs SET status='completed_with_warnings' " + ...
    "WHERE run_key IN ('ref-noise-2-ch1','ref-noise-2-ch2')");
warned = vawlume.acoustic.estimateChannelResponse(f.conn, struct(recording_id=1), ...
    referenceIds(f, ["noise-1" "noise-2"], [1 2]), RequiredReferenceTypes="noise", ...
    MinReferences=2, IncludeWarningSources=true, Apply=true, ...
    RunKey="resp-warned").analysis_run_id;
result = normalizeWith(f, f.call_runs.d1, warned);
verifyEqual(testCase, result.outcomes.response_qc_status, ...
    ["source_qc_warning"; "source_qc_warning"]);
verifyEqual(testCase, result.outcomes.status, ["normalized"; "normalized"]);
verifyTrue(testCase, all(cellfun(@(c) any(c == "response_source_qc_warning"), ...
    result.outcomes.qc_flags)));
clear cleanup
end

function testAPolicyMustDeclareEveryStatusAndStayUncalibrated(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");
shipped = jsondecode(fileread(f.policy_path));

partial = shipped;
partial.response_qc_status_handling = rmfield(partial.response_qc_status_handling, "divergent");
verifyError(testCase, @() normalizeWith(f, f.call_runs.d1, response, ...
    writePolicy(f, partial, "partial.json")), "vawlume:acoustic:NormalizationPolicyInvalid");

calibrated = shipped;
calibrated.calibration_status.state = "calibrated";
verifyError(testCase, @() normalizeWith(f, f.call_runs.d1, response, ...
    writePolicy(f, calibrated, "calibrated.json")), "vawlume:acoustic:NormalizationPolicyInvalid");

refusing = shipped;
refusing.response_qc_status_handling.ok.action = "refuse_run";
verifyError(testCase, @() normalizeWith(f, f.call_runs.d1, response, ...
    writePolicy(f, refusing, "refusing.json")), "vawlume:acoustic:NormalizationRefusedByPolicy");

verifyError(testCase, @() vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=response), struct(analysis_run_id=response), ...
    RepoRoot=f.repo_root), "vawlume:acoustic:NormalizationSourceKindInvalid");
clear cleanup
end

% --------------------------------------------------------- propagation ---

function testClippingAndPartialCoveragePropagate(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");

clipped = normalizeWith(f, f.call_runs.d2, response);
verifyEqual(testCase, clipped.outcomes.status, ["normalized"; "normalized"], ...
    "A clipped level is normalized and flagged, not withheld or repaired.");
verifyTrue(testCase, any(clipped.outcomes.qc_flags{1} == "clipped_samples"));
verifyFalse(testCase, any(clipped.outcomes.qc_flags{2} == "clipped_samples"));
verifyEqual(testCase, clipped.status, "completed_with_warnings");
refused = vawlume.acoustic.levelDifference(clipped.outcomes(1, :), clipped.outcomes(2, :), true);
verifyEqual(testCase, refused.status, "refused");
verifyEqual(testCase, refused.reason, "a_clipped");
verifyTrue(testCase, isnan(refused.value));
allowed = vawlume.acoustic.levelDifference(clipped.outcomes(1, :), clipped.outcomes(2, :), false);
verifyEqual(testCase, allowed.status, "computed");
verifyTrue(testCase, any(allowed.flags == "a:clipped_samples"));

partial = normalizeWith(f, f.call_runs.d3, response);
verifyEqual(testCase, partial.outcomes.status, ["normalized"; "normalized"]);
verifyTrue(testCase, all(cellfun(@(c) any(c == "incomplete_audio_coverage"), ...
    partial.outcomes.qc_flags)));
difference = vawlume.acoustic.levelDifference(partial.outcomes(1, :), ...
    partial.outcomes(2, :), true);
verifyEqual(testCase, difference.status, "computed");
verifyTrue(testCase, any(difference.flags == "a:incomplete_audio_coverage"));
clear cleanup
end

function testAFailedSourceChannelIsReportedNotSkipped(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");
withMissing = vawlume.acoustic.measureCallWindow(f.conn, struct(detection_id=1), ...
    [1 3 2], BandHz=[200 300], SourceRoot=f.source_root, Apply=true, RunKey="call-d1-ch3");
result = normalizeWith(f, withMissing.analysis_run_id, response);
verifyEqual(testCase, result.outcomes.channel_index, [1; 3; 2]);
verifyEqual(testCase, result.outcomes.reason(2), "source_measurement_absent");
verifyEqual(testCase, result.outcomes.status, ["normalized"; "not_normalized"; "normalized"]);
clear cleanup
end

% --------------------------------------------------------- persistence ---

function testPlanWritesNothingAndApplyRecordsLineage(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");
before = counts(f.conn);
planned = normalizeWith(f, f.call_runs.d1, response);
verifyEqual(testCase, planned.action, "planned");
verifyEqual(testCase, counts(f.conn), before);

applied = vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=f.call_runs.d1), struct(analysis_run_id=response), ...
    RepoRoot=f.repo_root, Apply=true, RunKey="norm-d1", VawlumeVersion="test");
verifyEqual(testCase, applied.action, "created");
runId = applied.analysis_run_id;
verifyEqual(testCase, string(fetch(f.conn, "SELECT run_type FROM analysis_runs " + ...
    "WHERE analysis_run_id=" + string(runId)).run_type), "acoustic_call_level_normalization");

sources = fetch(f.conn, "SELECT source_analysis_run_id, dependency_role FROM " + ...
    "analysis_run_sources WHERE analysis_run_id=" + string(runId) + " ORDER BY dependency_role");
verifyEqual(testCase, string(sources.dependency_role), ...
    ["call_window_measurement"; "channel_response_estimate"]);
verifyEqual(testCase, double(sources.source_analysis_run_id), [f.call_runs.d1; response]);

profile = fetch(f.conn, "SELECT arp.assignment_role, cp.profile_key, cp.profile_kind, " + ...
    "cpv.version_label, cpv.checksum_sha256, cpv.content_uri FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id=arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE arp.analysis_run_id=" + string(runId));
verifyEqual(testCase, string(profile.assignment_role), "call_level_normalization_policy");
verifyEqual(testCase, string(profile.profile_kind), "analysis_settings");
verifyEqual(testCase, string(profile.version_label), "1.0.0");
verifyEqual(testCase, string(profile.checksum_sha256), applied.policy.checksum_sha256);
verifyEqual(testCase, string(profile.content_uri), ...
    "config/09_acoustic_normalization_policies/band_matched_noise_reference_v1.json");

rows = fetch(f.conn, "SELECT dm.derived_measurement_id, dm.detection_id, " + ...
    "dm.recording_channel_id, md.metric_key, md.derivation_family, dm.value_real, dm.unit, " + ...
    "dm.derivation_details_json FROM derived_measurements dm JOIN metric_definitions md " + ...
    "ON md.metric_definition_id=dm.metric_definition_id WHERE dm.analysis_run_id=" + ...
    string(runId) + " ORDER BY dm.recording_channel_id");
verifyEqual(testCase, height(rows), 2);
verifyTrue(testCase, all(string(rows.metric_key) == "call_band_power_normalized"));
verifyTrue(testCase, all(string(rows.derivation_family) == "acoustic_call_level_normalization"));
verifyTrue(testCase, all(double(rows.detection_id) == 1));
verifyTrue(testCase, all(string(rows.unit) == "ratio_to_channel_response"));
estimates = vawlume.acoustic.readChannelResponse(f.conn, ...
    struct(analysis_run_id=response)).estimates;
callRows = fetch(f.conn, "SELECT dm.derived_measurement_id, dm.recording_channel_id, " + ...
    "dm.value_real FROM derived_measurements dm JOIN metric_definitions md " + ...
    "ON md.metric_definition_id=dm.metric_definition_id WHERE dm.analysis_run_id=" + ...
    string(f.call_runs.d1) + " AND md.metric_key='call_band_power' ORDER BY dm.recording_channel_id");
for index = 1:2
    details = jsondecode(char(rows.derivation_details_json(index)));
    channelId = double(rows.recording_channel_id(index));
    verifyEqual(testCase, details.source_derived_measurement_id, ...
        double(callRows.derived_measurement_id(index)));
    estimateRow = estimates(estimates.recording_channel_id == channelId & ...
        estimates.metric_key == "acoustic_band_power", :);
    verifyEqual(testCase, details.channel_response_estimate_id, ...
        estimateRow.channel_response_estimate_id);
    verifyEqual(testCase, string(details.reference_type), "noise");
    verifyEqual(testCase, details.source_band_hz(:)', [200 300]);
    verifyEqual(testCase, details.response_band_hz(:)', [200 300]);
    verifyEqual(testCase, string(details.response_qc_status), "ok");
    verifyEqual(testCase, string(details.calibration_status), "uncalibrated");
    verifyEqual(testCase, string(details.comparability_scope), "within_recording");
    verifyEqual(testCase, string(details.policy_checksum_sha256), applied.policy.checksum_sha256);
    % The row is exactly the quotient of the two rows it names.
    verifyEqual(testCase, double(rows.value_real(index)), ...
        double(callRows.value_real(index)) / estimateRow.value_real);
end
clear cleanup
end

function testReapplyReusesAndAChangeConflicts(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-2"], [1 2], "resp-ok");
apply = @(varargin) vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=f.call_runs.d1), struct(analysis_run_id=response), ...
    "RepoRoot", f.repo_root, "Apply", true, "RunKey", "norm-d1", varargin{:});
first = apply();
second = apply();
verifyEqual(testCase, second.action, "reused");
verifyEqual(testCase, second.outcomes.derived_measurement_id, ...
    first.outcomes.derived_measurement_id);
verifyError(testCase, @() apply("RunLabel", "changed"), ...
    "vawlume:acoustic:NormalizationRunConflict");

changedPolicy = jsondecode(fileread(f.policy_path));
changedPolicy.profile.profile_version = "1.0.1-test";
verifyError(testCase, @() apply("PolicyPath", writePolicy(f, changedPolicy, "v101.json")), ...
    "vawlume:acoustic:NormalizationRunConflict");

other = estimate(f, ["noise-1" "noise-3"], [1 2], "resp-divergent");
verifyError(testCase, @() vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=f.call_runs.d1), struct(analysis_run_id=other), ...
    RepoRoot=f.repo_root, Apply=true, RunKey="norm-d1"), ...
    "vawlume:acoustic:NormalizationRunConflict");
verifyEqual(testCase, scalar(f.conn, "SELECT COUNT(*) AS n FROM derived_measurements dm " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=dm.analysis_run_id " + ...
    "WHERE ar.run_type='acoustic_call_level_normalization'"), 2);
clear cleanup
end

% ---------------------------------------------------- level difference ---

function testTheLevelDifferenceSignConvention(testCase)
cleanup = onSourcePath(); %#ok<NASGU>
a = side(1, 10);
b = side(2, 1);
forward = vawlume.acoustic.levelDifference(a, b, true);
verifyEqual(testCase, forward.value, 10, "Channel a louder is positive.", AbsTol=1e-12);
verifyEqual(testCase, forward.sign_convention, ...
    "positive when channel a is louder than channel b");
verifyEqual(testCase, forward.formula, "10*log10(P_a/P_b)");
backward = vawlume.acoustic.levelDifference(b, a, true);
verifyEqual(testCase, backward.value, -forward.value, "Swapping the pair negates it exactly.");
verifyEqual(testCase, [backward.channel_index_a backward.channel_index_b], [2 1]);
equal = vawlume.acoustic.levelDifference(side(1, 3), side(2, 3), true);
verifyEqual(testCase, equal.value, 0);
end

function testTheLevelDifferenceRefusesRatherThanComputes(testCase)
cleanup = onSourcePath(); %#ok<NASGU>
missing = side(2, NaN);
missing.status = "not_normalized";
missing.reason = "response_family_mismatch";
r = vawlume.acoustic.levelDifference(side(1, 2), missing, true);
verifyEqual(testCase, [r.status r.reason r.reason_b], ...
    ["refused" "b_missing" "response_family_mismatch"]);
verifyTrue(testCase, isnan(r.value));

both = vawlume.acoustic.levelDifference(missing, missing2(), true);
verifyEqual(testCase, both.reasons, ["a_missing"; "b_missing"]);

zero = vawlume.acoustic.levelDifference(side(1, 0), side(2, 1), true);
verifyEqual(testCase, zero.reason, "a_nonpositive");

clippedB = side(2, 1);
clippedB.qc_flags = {"clipped_samples"};
verifyEqual(testCase, vawlume.acoustic.levelDifference(side(1, 2), clippedB, true).reason, ...
    "b_clipped");
verifyEqual(testCase, vawlume.acoustic.levelDifference(side(1, 2), clippedB, false).status, ...
    "computed");

id = "vawlume:acoustic:LevelDifferenceInputInvalid";
verifyError(testCase, @() vawlume.acoustic.levelDifference(side(1, 2), side(1, 3), true), id);
otherEvent = side(2, 1);
otherEvent.target_id = 99;
verifyError(testCase, @() vawlume.acoustic.levelDifference(side(1, 2), otherEvent, true), id);
raw = side(2, 1);
raw.normalized_metric = "call_band_power";
raw.unit = "full_scale_ratio_squared";
verifyError(testCase, @() vawlume.acoustic.levelDifference(raw, ...
    setfield(raw, "channel_index", 1), true), id);
verifyError(testCase, @() vawlume.acoustic.levelDifference(side(1, 2), raw, true), id);
verifyError(testCase, @() vawlume.acoustic.levelDifference(side(1, 2), side(2, 1)), ...
    "MATLAB:minrhs");
end

function testTheDifferenceIsReconstructibleFromTheTwoCitedRows(testCase)
[f, cleanup] = setUpFixture(); %#ok<ASGLU>
response = estimate(f, ["noise-1" "noise-3"], [1 2], "resp-divergent");
applied = vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=f.call_runs.d2), struct(analysis_run_id=response), ...
    RepoRoot=f.repo_root, Apply=true, RunKey="norm-d2");
difference = vawlume.acoustic.levelDifference(applied.outcomes(2, :), ...
    applied.outcomes(1, :), false);
verifyEqual(testCase, [difference.derived_measurement_id_a difference.derived_measurement_id_b], ...
    applied.outcomes.derived_measurement_id([2 1])');
stored = fetch(f.conn, "SELECT derived_measurement_id, value_real FROM derived_measurements " + ...
    "WHERE derived_measurement_id IN (" + strjoin(string(applied.outcomes.derived_measurement_id), ",") + ")");
valueOf = @(id) double(stored.value_real(double(stored.derived_measurement_id) == id));
verifyEqual(testCase, difference.value, 10 * log10( ...
    valueOf(difference.derived_measurement_id_a) / valueOf(difference.derived_measurement_id_b)));
clear cleanup
end

% ------------------------------------------------------------ boundary ---

function testNoAcousticFunctionTakesAPositionDistanceEntityOrCandidate(testCase)
% Tripwire 3. Reads every +acoustic/ function's declared inputs: the signature
% and every arguments block. A level difference that took a distance would
% have started to combine dimensions, which belongs to +estimator/.
root = fullfile(repositoryRoot(), "src", "+vawlume", "+acoustic");
files = [dir(fullfile(root, "*.m")); dir(fullfile(root, "private", "*.m"))];
verifyGreaterThan(testCase, numel(files), 10);
forbidden = "position|distance|entity|candidate|coordinate|track";
for file = files'
    lines = string(splitlines(fileread(fullfile(file.folder, file.name))));
    inputs = strings(0, 1);
    inBlock = false;
    for line = lines'
        text = strtrim(line);
        if startsWith(text, "function ")
            inputs(end + 1, 1) = extractAfter(text, "("); %#ok<AGROW>
        elseif text == "arguments"
            inBlock = true;
        elseif inBlock && text == "end"
            inBlock = false;
        elseif inBlock
            inputs(end + 1, 1) = text; %#ok<AGROW>
        end
    end
    hits = inputs(~cellfun(@isempty, regexpi(cellstr(inputs), forbidden, "once")));
    verifyEmpty(testCase, hits, file.name + " declares a forbidden input: " + ...
        strjoin(hits, " | "));
end
end

% --------------------------------------------------------------- helpers ---

function cleanup = onSourcePath()
% The pure-function tests need src/ but no database.
source = fullfile(repositoryRoot(), "src");
addpath(source);
cleanup = onCleanup(@() rmpath(source));
end

function value = side(channel, level)
value = struct(target_kind="detection", target_id=1, channel_index=channel, ...
    normalized_metric="call_band_power_normalized", unit="ratio_to_channel_response", ...
    status="normalized", reason="", value=level, qc_flags={strings(0, 1)}, ...
    derived_measurement_id=100 + channel);
end

function value = missing2()
value = side(3, NaN);
value.status = "not_normalized";
value.reason = "source_measurement_absent";
end

function result = normalizeWith(f, callRun, responseRun, policyPath)
if nargin < 4
    policyPath = "";
end
result = vawlume.acoustic.normalizeCallLevels(f.conn, ...
    struct(analysis_run_id=callRun), struct(analysis_run_id=responseRun), ...
    RepoRoot=f.repo_root, PolicyPath=policyPath);
end

function runId = estimate(f, referenceKeys, channels, runKey, options)
arguments
    f
    referenceKeys (1,:) string
    channels (1,:) double
    runKey (1,1) string
    options.Metric (1,1) string = "acoustic_band_power"
    options.MinReferences (1,1) double = 2
    options.Types (1,1) string = "noise"
end
runId = vawlume.acoustic.estimateChannelResponse(f.conn, struct(recording_id=1), ...
    referenceIds(f, referenceKeys, channels, options.Metric), ...
    RequiredReferenceTypes=options.Types, MinReferences=options.MinReferences, ...
    Apply=true, RunKey=runKey).analysis_run_id;
end

function ids = referenceIds(f, referenceKeys, channels, metric)
if nargin < 4
    metric = "acoustic_band_power";
end
mask = ismember(f.reference_rows.reference_key, referenceKeys) & ...
    ismember(f.reference_rows.channel_index, channels) & ...
    f.reference_rows.metric_key == metric;
ids = f.reference_rows.derived_measurement_id(mask);
end

function path = writePolicy(f, document, name)
path = fullfile(f.source_root, name);
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document, PrettyPrint=true));
fclose(fileId);
path = string(path);
end

function runId = foreignRecordingEstimate(f)
% A second recording of the same file, with its own references and estimate.
copyfile(f.audio_path, fullfile(f.source_root, "audio", "copy.wav"));
info = dir(fullfile(f.source_root, "audio", "copy.wav"));
execute(f.conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri," + ...
    "relative_path,filename,file_format,size_bytes) VALUES (2,1,'recording_audio'," + ...
    "'audio/copy.wav','audio/copy.wav','copy.wav','wav'," + string(info.bytes) + ")");
execute(f.conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "sample_rate_hz,channel_count) VALUES (2,1,2,1000,2)");
execute(f.conn, "INSERT INTO recording_channels(recording_channel_id,recording_id,channel_index) " + ...
    "VALUES (3,2,1),(4,2,2)");
ids = zeros(0, 1);
for key = ["noise-1" "noise-2"]
    interval = f.intervals.(replace(key, "-", "_"));
    ref = vawlume.acoustic.registerReference(f.conn, struct(recording_id=2), struct( ...
        reference_key="foreign-" + key, reference_type="noise", start_time_s=interval(1), ...
        end_time_s=interval(2), frequency_min_hz=200, frequency_max_hz=300));
    for channel = 1:2
        measured = vawlume.acoustic.measureReferenceResponse(f.conn, ...
            struct(acoustic_reference_id=ref.acoustic_reference_id), channel, ...
            SourceRoot=f.source_root, Apply=true, ...
            RunKey="foreign-" + key + "-ch" + string(channel));
        ids(end + 1, 1) = measured.derived_measurement_ids( ...
            measured.metrics.metric_key == "acoustic_band_power"); %#ok<AGROW>
    end
end
runId = vawlume.acoustic.estimateChannelResponse(f.conn, struct(recording_id=2), ids, ...
    RequiredReferenceTypes="noise", Apply=true, RunKey="resp-foreign").analysis_run_id;
end

function [f, cleanup] = setUpFixture()
repoRoot = repositoryRoot();
addpath(fullfile(repoRoot, "src"));
sourceRoot = string(tempname);
mkdir(fullfile(sourceRoot, "audio"));
audioPath = fullfile(sourceRoot, "audio", "session.wav");
sampleRate = 1000;
total = 4 * sampleRate;
time = (0:total - 1)' / sampleRate;
source = zeros(total, 1);
intervals = struct(d1=[0.2 0.6], noise_1=[1.0 1.4], noise_2=[1.4 1.8], ...
    noise_3=[1.8 2.2], tone_1=[2.2 2.6], d2=[2.6 3.0], d3=[3.8 4.0]);
noise = zeros(total, 1);
for frequency = [220 240 260 280]
    noise = noise + 0.1 * sin(2 * pi * frequency * time);
end
tone = sin(2 * pi * 250 * time);
source = place(source, 0.4 * tone, intervals.d1, sampleRate);
source = place(source, noise, intervals.noise_1, sampleRate);
source = place(source, noise, intervals.noise_2, sampleRate);
source = place(source, 1.5 * noise, intervals.noise_3, sampleRate);
source = place(source, 0.3 * tone, intervals.tone_1, sampleRate);
source = place(source, 0.3 * tone, intervals.d3, sampleRate);
% Channel 2 hears every source at half channel 1's amplitude: the deliberate
% gain difference normalization must remove.
left = source;
right = 0.5 * source;
% Detection 2 is the exception: channel 1 overloads, channel 2 does not.
left = place(left, min(max(1.5 * tone, -1), 1), intervals.d2, sampleRate);
right = place(right, 0.2 * tone, intervals.d2, sampleRate);
audiowrite(char(audioPath), [left right], sampleRate, BitsPerSample=24);
fileInfo = dir(audioPath);

dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() cleanUpFixture(conn, dbFile, sourceRoot, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES (1,'norm-test','Normalization test')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path,filename,file_format,size_bytes,checksum_sha256) " + ...
    "VALUES (1,1,'recording_audio','audio/session.wav','audio/session.wav'," + ...
    "'session.wav','wav'," + string(fileInfo.bytes) + ",'synthetic-sha256')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id,sample_rate_hz,channel_count,duration_s) " + ...
    "VALUES (1,1,1,'session',1000,2,4)");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index,channel_label) VALUES (1,1,1,'left'),(2,1,2,'right')");
versionId = scalar(conn, "SELECT MIN(extractor_version_id) AS n FROM extractor_versions");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES (1,1," + string(versionId) + ",'synthetic')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES (1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s) VALUES " + ...
    "(1,1,1,'d1',0.2,0.6),(2,1,1,'d2',2.6,3.0),(3,1,1,'d3',3.8,4.3)");

referenceRows = table();
for key = ["noise-1" "noise-2" "noise-3" "tone-1"]
    interval = intervals.(replace(key, "-", "_"));
    ref = vawlume.acoustic.registerReference(conn, struct(recording_id=1), struct( ...
        reference_key=key, reference_type=extractBefore(key, "-"), ...
        start_time_s=interval(1), end_time_s=interval(2), ...
        frequency_min_hz=200, frequency_max_hz=300));
    for channel = 1:2
        measured = vawlume.acoustic.measureReferenceResponse(conn, ...
            struct(acoustic_reference_id=ref.acoustic_reference_id), channel, ...
            SourceRoot=sourceRoot, Apply=true, RunKey="ref-" + key + "-ch" + string(channel));
        count = height(measured.metrics);
        referenceRows = [referenceRows; table(repmat(key, count, 1), ...
            repmat(channel, count, 1), measured.metrics.metric_key, ...
            measured.derived_measurement_ids(:), VariableNames=["reference_key", ...
            "channel_index", "metric_key", "derived_measurement_id"])]; %#ok<AGROW>
    end
end

callRuns = struct();
for detection = 1:3
    measured = vawlume.acoustic.measureCallWindow(conn, struct(detection_id=detection), ...
        [1 2], BandHz=[200 300], SourceRoot=sourceRoot, Apply=true, ...
        RunKey="call-d" + string(detection));
    callRuns.("d" + string(detection)) = measured.analysis_run_id;
end

f = struct(conn=conn, repo_root=repoRoot, source_root=sourceRoot, ...
    audio_path=string(audioPath), intervals=intervals, reference_rows=referenceRows, ...
    call_runs=callRuns, policy_path=fullfile(repoRoot, "config", ...
    "09_acoustic_normalization_policies", "band_matched_noise_reference_v1.json"));
end

function signal = place(signal, values, interval, sampleRate)
selected = (round(interval(1) * sampleRate) + 1:round(interval(2) * sampleRate))';
signal(selected) = values(selected);
end

function value = counts(conn)
value = [scalar(conn, "SELECT COUNT(*) AS n FROM analysis_runs"), ...
    scalar(conn, "SELECT COUNT(*) AS n FROM derived_measurements"), ...
    scalar(conn, "SELECT COUNT(*) AS n FROM analysis_run_sources"), ...
    scalar(conn, "SELECT COUNT(*) AS n FROM analysis_run_profiles"), ...
    scalar(conn, "SELECT COUNT(*) AS n FROM config_profiles")];
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.n(1));
end

function cleanUpFixture(conn, dbFile, sourceRoot, repoRoot)
if isopen(conn)
    close(conn);
end
for suffix = ["", "-journal", "-wal", "-shm"]
    path = dbFile + suffix;
    if isfile(path)
        delete(path);
    end
end
if isfolder(sourceRoot)
    rmdir(sourceRoot, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function root = repositoryRoot()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
