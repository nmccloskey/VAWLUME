function tests = test_call_window_measurement
%TEST_CALL_WINDOW_MEASUREMENT Phase 6.6: call windows measured per channel.
%
% The fixture is one synthetic two-channel WAV, 1000 Hz, 2 s, 24-bit, written
% with the multimodal demo's recipe. Signals are 250 Hz sinusoids, so every
% window holds whole cycles, every sample lands on a quarter cycle, the peak is
% the amplitude exactly, and all power falls in the bins at +/-250 Hz:
%
%   detection 1   [0.2, 0.6)   ch1 amplitude 0.4, ch2 amplitude 0.1
%   detection 2   [1.8, 2.3)   amplitude 0.3 on both; the file ends at 2.0 s
%   detection 3   [2.5, 2.7)   wholly after the file
%   detection 4   [1.0, 1.4)   ch1 1.5 x sine clipped to [-1, 1]; ch2 amplitude 0.2
%   detection 5   [0.8, 0.8)   zero length
%   consensus 1   [0.2, 0.6)   the same interval as detection 1
%
% So RMS = a/sqrt(2), peak = a and band power over [200, 300] Hz = a^2/2.
tests = functiontests(localfunctions);
end

% -------------------------------------------------- known input, output ---

function testKnownAmplitudesGiveKnownLevelsPerChannel(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root);

verifyEqual(testCase, result.status, "completed");
verifyEqual(testCase, result.target_kind, "detection");
verifyEqual(testCase, result.event_interval_s, [0.2 0.6]);
verifyEqual(testCase, [result.channels.status], ["completed" "completed"]);
verifyEqual(testCase, [result.channels.coverage_status], ...
    ["covered_populated" "covered_populated"]);
verifyEqual(testCase, [result.channels.band_state], ["computed" "computed"]);
amplitudes = [0.4 0.1];
for channel = 1:2
    m = result.channels(channel).metrics;
    verifyEqual(testCase, m.metric_key, ...
        ["call_rms_amplitude"; "call_peak_abs_amplitude"; "call_band_power"]);
    verifyEqual(testCase, m.unit, ...
        ["full_scale_ratio"; "full_scale_ratio"; "full_scale_ratio_squared"]);
    a = amplitudes(channel);
    verifyEqual(testCase, m.value(1), a / sqrt(2), AbsTol=1e-6);
    verifyEqual(testCase, m.value(2), a, AbsTol=1e-6);
    verifyEqual(testCase, m.value(3), a ^ 2 / 2, AbsTol=1e-6);
    window = result.channels(channel).audio_window;
    verifyEqual(testCase, window.requested_interval_s, [0.2 0.6]);
    verifyEqual(testCase, window.sample_count, 400);
end
verifyEqual(testCase, height(result.measurements), 6);
verifyTrue(testCase, all(isnan(result.measurements.derived_measurement_id)));
clear cleanup
end

function testTheCoreIsTheReferenceMethodsCore(testCase)
% A reference over the call's interval, on the same channel, with the same
% band, must give bit-identical numbers: one core, two metric vocabularies.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
reference = vawlume.acoustic.registerReference(fixture.conn, ...
    struct(recording_id=1), struct(reference_key="same-window", ...
    reference_type="synthetic", start_time_s=0.2, end_time_s=0.6, ...
    frequency_min_hz=200, frequency_max_hz=300));
for channel = 1:2
    ref = vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
        struct(acoustic_reference_id=reference.acoustic_reference_id), channel, ...
        SourceRoot=fixture.source_root);
    call = vawlume.acoustic.measureCallWindow(fixture.conn, ...
        struct(detection_id=1), channel, BandHz=[200 300], ...
        SourceRoot=fixture.source_root);
    verifyEqual(testCase, typecast(call.channels.metrics.value, "uint64"), ...
        typecast(ref.metrics.value, "uint64"));
    verifyEqual(testCase, extractAfter(call.channels.metrics.metric_key, "call_"), ...
        extractAfter(ref.metrics.metric_key, "acoustic_"));
end
clear cleanup
end

function testAConsensusEventIsMeasuredOnItsOwnInterval(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(consensus_event_id=1), [1 2], BandHz=[200 300], ...
    SourceRoot=fixture.source_root, Apply=true, RunKey="call-consensus-1");
verifyEqual(testCase, result.target_kind, "consensus_event");
verifyEqual(testCase, result.consensus_event_id, 1);
verifyTrue(testCase, isnan(result.detection_id));
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM derived_measurements " + ...
    "WHERE consensus_event_id=1 AND detection_id IS NULL");
verifyEqual(testCase, double(rows.n), 6);
verifyEqual(testCase, result.measurements.value(1), 0.4 / sqrt(2), AbsTol=1e-6);
clear cleanup
end

% ---------------------------------------------------------------- QC ---

function testAPartialWindowGivesAValueWithAnExplicitWarning(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=2), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root);
verifyEqual(testCase, result.status, "completed_with_warnings");
for channel = result.channels
    verifyEqual(testCase, channel.status, "completed_with_warnings");
    verifyEqual(testCase, channel.coverage_status, "partial_populated");
    verifyTrue(testCase, any(channel.qc_flags == "incomplete_audio_coverage"));
    verifyEqual(testCase, channel.audio_window.requested_interval_s, [1.8 2.3]);
    verifyEqual(testCase, channel.audio_window.covered_interval_s, [1.8 2.0]);
    verifyEqual(testCase, channel.metrics.value(1), 0.3 / sqrt(2), AbsTol=1e-6);
    verifyEqual(testCase, channel.derivation_details.covered_interval_s, [1.8 2.0]);
end
clear cleanup
end

function testAWindowWhollyOutsideTheFileGivesNoNumber(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=3), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root);
verifyEqual(testCase, result.status, "failed");
verifyEqual(testCase, [result.channels.coverage_status], ["not_covered" "not_covered"]);
verifyEqual(testCase, [result.channels.band_state], ["no_samples" "no_samples"]);
verifyTrue(testCase, all(arrayfun(@(c) any(c.qc_flags == "empty_window"), result.channels)));
verifyEqual(testCase, height(result.measurements), 0);

applied = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=3), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="call-outside");
verifyEqual(testCase, scalar(fixture.conn, "SELECT COUNT(*) AS n FROM derived_measurements"), 0);
verifyEqual(testCase, scalar(fixture.conn, "SELECT COUNT(*) AS n FROM analysis_runs " + ...
    "WHERE analysis_run_id=" + string(applied.analysis_run_id) + " AND status='failed'"), 1);
clear cleanup
end

function testAZeroLengthWindowGivesNoNumber(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=5), 1, BandHz=[200 300], SourceRoot=fixture.source_root);
verifyEqual(testCase, result.status, "failed");
verifyEqual(testCase, result.channels.coverage_status, "covered_empty");
verifyTrue(testCase, any(result.channels.qc_flags == "zero_length_window"));
verifyTrue(testCase, any(result.channels.qc_flags == "empty_window"));
verifyEqual(testCase, height(result.channels.metrics), 0);
clear cleanup
end

function testClippingIsFlaggedOnTheClippedChannelOnly(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=4), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="call-clipped");
clipped = result.channels(1);
clean = result.channels(2);
verifyEqual(testCase, clipped.status, "completed_with_warnings");
verifyTrue(testCase, any(clipped.qc_flags == "clipped_samples"));
verifyGreaterThan(testCase, clipped.clipped_sample_count, 0);
verifyEqual(testCase, height(clipped.metrics), 3, ...
    "A clipped channel still has a value: a lower bound, flagged, not withheld.");
verifyEqual(testCase, clean.status, "completed");
verifyEmpty(testCase, clean.qc_flags);
verifyEqual(testCase, clean.metrics.value(1), 0.2 / sqrt(2), AbsTol=1e-6);
verifyEqual(testCase, result.status, "completed_with_warnings");

% The flag reaches the persisted method evidence, where 6.7 will read it.
details = fetch(fixture.conn, "SELECT DISTINCT recording_channel_id, " + ...
    "derivation_details_json AS d FROM derived_measurements " + ...
    "WHERE detection_id=4 ORDER BY recording_channel_id");
first = jsondecode(char(details.d(1)));
second = jsondecode(char(details.d(2)));
verifyTrue(testCase, any(string(first.qc_flags) == "clipped_samples"));
verifyGreaterThan(testCase, first.clipped_sample_count, 0);
verifyEmpty(testCase, second.qc_flags);
verifyEqual(testCase, second.clipped_sample_count, 0);
clear cleanup
end

function testABandAboveNyquistGivesNoBandPower(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], BandHz=[400 600], SourceRoot=fixture.source_root);
verifyEqual(testCase, result.status, "completed_with_warnings");
for channel = result.channels
    verifyEqual(testCase, channel.band_state, "above_nyquist");
    verifyTrue(testCase, any(channel.qc_flags == "call_band_above_nyquist"));
    verifyFalse(testCase, any(channel.metrics.metric_key == "call_band_power"));
    verifyEqual(testCase, height(channel.metrics), 2);
end
clear cleanup
end

function testAnUndeclaredBandIsNotInferred(testCase)
% The detection carries no frequency bounds here, but even where an event does,
% v1 never reads them (contract 06 D6): the band comes from BandHz or nowhere.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="call-no-band");
verifyEqual(testCase, result.status, "completed");
verifyEqual(testCase, [result.channels.band_state], ["not_declared" "not_declared"]);
verifyFalse(testCase, any(result.measurements.metric_key == "call_band_power"));
verifyEqual(testCase, height(result.measurements), 4);
details = jsondecode(char(fetch(fixture.conn, "SELECT derivation_details_json AS d " + ...
    "FROM derived_measurements LIMIT 1").d(1)));
verifyEqual(testCase, string(details.band_source), "none");
verifyEmpty(testCase, details.frequency_band_hz);
verifyEqual(testCase, string(details.band_state), "not_declared");
clear cleanup
end

function testIncompleteAndInvalidBandsCarryDoc27States(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
incomplete = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, BandHz=[200 NaN], SourceRoot=fixture.source_root);
verifyTrue(testCase, any(incomplete.channels.qc_flags == "incomplete_call_band"));
invalid = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, BandHz=[300 200], SourceRoot=fixture.source_root);
verifyTrue(testCase, any(invalid.channels.qc_flags == "invalid_call_band"));
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, BandHz=[100 200 300], SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:CallBandInvalid");
clear cleanup
end

% ---------------------------------------------- targets and channels ---

function testAnAgreementGroupIsRefusedByName(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(agreement_group_id=1), [1 2], SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:AgreementGroupTargetUnsupported");
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1, agreement_group_id=1), [1 2], SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:AgreementGroupTargetUnsupported");
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1, consensus_event_id=1), 1, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:EventRefInvalid");
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=99), 1, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:EventNotFound");
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 1], SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:ChannelSetInvalid");
clear cleanup
end

function testAnUnreadableChannelFailsAloneAndTheOthersAreMeasured(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 3 2], BandHz=[200 300], ...
    SourceRoot=fixture.source_root, Apply=true, RunKey="call-unreadable");
verifyEqual(testCase, [result.channels.channel_index], [1 3 2]);
verifyEqual(testCase, [result.channels.status], ["completed" "failed" "completed"]);
missing = result.channels(2);
verifyEqual(testCase, missing.error_identifier, "vawlume:acoustic:ChannelNotFound");
verifyEqual(testCase, missing.coverage_status, "unreadable");
verifyEqual(testCase, missing.qc_flags, "channel_unreadable");
verifyTrue(testCase, isnan(missing.recording_channel_id));
verifyEqual(testCase, result.status, "completed_with_warnings");
verifyEqual(testCase, scalar(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM derived_measurements"), 6);
% The surviving rows record what was asked for, so the missing channel is
% visible as requested-but-absent rather than never requested.
details = jsondecode(char(fetch(fixture.conn, "SELECT derivation_details_json AS d " + ...
    "FROM derived_measurements LIMIT 1").d(1)));
verifyEqual(testCase, details.requested_channel_indices(:)', [1 3 2]);
clear cleanup
end

function testABrokenRecordingLinkIsRaisedNotPerChannel(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE source_files SET path_or_uri='audio/missing.wav', " + ...
    "relative_path='audio/missing.wav' WHERE source_file_id=1");
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:AudioArtifactMissing");
clear cleanup
end

function testNothingComparesOneChannelWithAnother(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root);
verifyEqual(testCase, sort(string(fieldnames(result)))', sort(["target_kind", ...
    "detection_id", "consensus_event_id", "recording_id", "event_interval_s", ...
    "band_hz", "status", "channels", "measurements", "method_key", ...
    "method_version", "run_type", "analysis_run_id", "action"]));
verifyEqual(testCase, string(result.measurements.Properties.VariableNames), ...
    ["channel_index", "recording_channel_id", "metric_key", "value", "unit", ...
    "derived_measurement_id"]);
verifyEqual(testCase, unique(result.measurements.metric_key)', ...
    ["call_band_power" "call_peak_abs_amplitude" "call_rms_amplitude"]);
source = string(fileread(fullfile(fixture.repo_root, "src", "+vawlume", ...
    "+acoustic", "measureCallWindow.m")));
% A level difference is 10*log10 of a ratio (contract 06 D6); it is 6.7's.
verifyFalse(testCase, contains(source, "log10"));
clear cleanup
end

% ----------------------------------------------------------- persistence ---

function testPlanWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root);
verifyEqual(testCase, result.action, "planned");
verifyTrue(testCase, isnan(result.analysis_run_id));
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

function testApplyWritesCitableRowsWithFullMethodEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="call-d1", RunLabel="synthetic call", ...
    VawlumeVersion="test", SourceCommit="abc123");
verifyEqual(testCase, result.action, "created");
verifyEqual(testCase, numel(unique(result.measurements.derived_measurement_id)), 6);

run = fetch(fixture.conn, "SELECT run_type, status, run_key FROM analysis_runs " + ...
    "WHERE analysis_run_id=" + string(result.analysis_run_id));
verifyEqual(testCase, string(run.run_type), "acoustic_call_window_response");
verifyEqual(testCase, string(run.status), "completed");

rows = fetch(fixture.conn, "SELECT dm.derived_measurement_id, dm.detection_id, " + ...
    "IFNULL(dm.consensus_event_id,-1) AS consensus_event_id, " + ...
    "IFNULL(dm.acoustic_reference_id,-1) AS acoustic_reference_id, " + ...
    "dm.recording_channel_id, md.metric_key, md.derivation_family, dm.value_real, " + ...
    "dm.unit, dm.derivation_details_json FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "WHERE dm.analysis_run_id=" + string(result.analysis_run_id) + ...
    " ORDER BY dm.derived_measurement_id");
verifyEqual(testCase, height(rows), 6);
verifyTrue(testCase, all(double(rows.detection_id) == 1));
verifyTrue(testCase, all(double(rows.consensus_event_id) == -1));
verifyTrue(testCase, all(double(rows.acoustic_reference_id) == -1));
verifyEqual(testCase, double(rows.recording_channel_id), [1;1;1;2;2;2]);
verifyTrue(testCase, all(string(rows.derivation_family) == "acoustic_call_window_response"));
verifyEqual(testCase, double(rows.value_real), result.measurements.value);
verifyEqual(testCase, double(rows.derived_measurement_id), ...
    result.measurements.derived_measurement_id);

details = jsondecode(char(rows.derivation_details_json(1)));
verifyEqual(testCase, string(details.method_key), "vawlume.acoustic.call_window_response");
verifyEqual(testCase, string(details.method_version), "1.0.0");
verifyEqual(testCase, string(details.target_kind), "detection");
verifyEqual(testCase, details.detection_id, 1);
verifyEmpty(testCase, details.consensus_event_id);
verifyEqual(testCase, details.event_interval_s(:)', [0.2 0.6]);
verifyEqual(testCase, details.recording_id, 1);
verifyEqual(testCase, details.recording_channel_id, 1);
verifyEqual(testCase, details.channel_index, 1);
verifyEqual(testCase, details.source_file_id, 1);
verifyEqual(testCase, string(details.source_checksum_sha256), "synthetic-sha256");
verifyEqual(testCase, details.requested_interval_s(:)', [0.2 0.6]);
verifyEqual(testCase, details.covered_interval_s(:)', [0.2 0.6]);
verifyEqual(testCase, details.read_interval_s(:)', [0.2 0.6]);
verifyEqual(testCase, [details.first_sample details.last_sample], [201 600]);
verifyEqual(testCase, details.sample_rate_hz, 1000);
verifyEqual(testCase, string(details.band_source), "explicit");
verifyEqual(testCase, details.frequency_band_hz(:)', [200 300]);
verifyEqual(testCase, string(details.coverage_status), "covered_populated");
verifyTrue(testCase, contains(string(details.window_semantics), "no padding"));
clear cleanup
end

function testReapplyReusesAndAChangedApplyConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply = @(varargin) vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), [1 2], "SourceRoot", fixture.source_root, ...
    "Apply", true, "RunKey", "call-d1", "VawlumeVersion", "test", varargin{:});
first = apply(BandHz=[200 300]);
second = apply(BandHz=[200 300]);
verifyEqual(testCase, second.action, "reused");
verifyEqual(testCase, second.analysis_run_id, first.analysis_run_id);
verifyEqual(testCase, second.measurements.derived_measurement_id, ...
    first.measurements.derived_measurement_id);
verifyEqual(testCase, scalar(fixture.conn, "SELECT COUNT(*) AS n FROM derived_measurements"), 6);

% A changed band changes the method evidence of every row.
verifyError(testCase, @() apply(BandHz=[210 300]), "vawlume:acoustic:MeasurementRunConflict");
% Changed provenance.
verifyError(testCase, @() apply(BandHz=[200 300], RunLabel="changed"), ...
    "vawlume:acoustic:MeasurementRunConflict");
% A different channel set.
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, BandHz=[200 300], SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="call-d1", VawlumeVersion="test"), ...
    "vawlume:acoustic:MeasurementRunConflict");
% A different event under the same key.
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(consensus_event_id=1), [1 2], BandHz=[200 300], SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="call-d1", VawlumeVersion="test"), ...
    "vawlume:acoustic:MeasurementRunConflict");
% A reference run's key is not a call run's key.
reference = vawlume.acoustic.registerReference(fixture.conn, struct(recording_id=1), ...
    struct(reference_key="r", reference_type="synthetic", start_time_s=0, end_time_s=1));
vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
    struct(acoustic_reference_id=reference.acoustic_reference_id), 1, ...
    SourceRoot=fixture.source_root, Apply=true, RunKey="shared-key");
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, SourceRoot=fixture.source_root, ...
    Apply=true, RunKey="shared-key"), "vawlume:acoustic:MeasurementRunConflict");
verifyEqual(testCase, scalar(fixture.conn, "SELECT COUNT(*) AS n FROM derived_measurements " + ...
    "WHERE detection_id IS NOT NULL"), 6);
verifyError(testCase, @() vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, Apply=true, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:RunKeyRequired");
clear cleanup
end

function testTheChannelScopeTriggerRefusesAForeignChannel(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES (2,1,'recording_audio','other.wav')");
execute(fixture.conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) VALUES (2,1,2)");
execute(fixture.conn, "INSERT INTO recording_channels(recording_channel_id,recording_id,channel_index) " + ...
    "VALUES (9,2,1)");
result = vawlume.acoustic.measureCallWindow(fixture.conn, ...
    struct(detection_id=1), 1, SourceRoot=fixture.source_root, Apply=true, RunKey="k");
metricId = scalar(fixture.conn, "SELECT metric_definition_id AS n FROM metric_definitions " + ...
    "WHERE metric_key='call_rms_amplitude'");
for target = ["detection_id", "consensus_event_id"]
    message = sqlFailure(fixture.conn, "INSERT INTO derived_measurements(" + ...
        "analysis_run_id,metric_definition_id," + target + ",recording_channel_id,value_real) " + ...
        "VALUES (" + string(result.analysis_run_id) + "," + string(metricId) + ",1,9,0.1)");
    verifySubstring(testCase, message, ...
        "Derived measurement channel belongs to a different recording than its target");
end
message = sqlFailure(fixture.conn, "UPDATE derived_measurements SET recording_channel_id=9 " + ...
    "WHERE derived_measurement_id=" + string(result.measurements.derived_measurement_id(1)));
verifySubstring(testCase, message, ...
    "Derived measurement channel belongs to a different recording than its target");
clear cleanup
end

function testCallMetricsAreDistinctBuiltInDefinitions(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
rows = fetch(fixture.conn, "SELECT metric_key, canonical_unit, allowed_scope, " + ...
    "derivation_family FROM metric_definitions WHERE metric_key LIKE 'call\_%' ESCAPE '\' " + ...
    "ORDER BY metric_key");
verifyEqual(testCase, string(rows.metric_key), ...
    ["call_band_power"; "call_peak_abs_amplitude"; "call_rms_amplitude"]);
verifyEqual(testCase, string(rows.canonical_unit), ...
    ["full_scale_ratio_squared"; "full_scale_ratio"; "full_scale_ratio"]);
verifyTrue(testCase, all(string(rows.allowed_scope) == ...
    "detection;consensus_event;recording_channel"));
verifyTrue(testCase, all(string(rows.derivation_family) == "acoustic_call_window_response"));
% Registration is idempotent with the new rows present.
summary = vawlume.db.registerBuiltinSemantics(fixture.conn, fixture.repo_root);
verifyEqual(testCase, summary.metric_definitions_inserted, 0);
clear cleanup
end

% --------------------------------------------------------------- fixture ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repositoryRoot();
addpath(fullfile(repoRoot, "src"));
sourceRoot = string(tempname);
mkdir(fullfile(sourceRoot, "audio"));
audioPath = fullfile(sourceRoot, "audio", "calls.wav");
sampleRate = 1000;
total = 2 * sampleRate;
time = (0:total - 1)' / sampleRate;
tone = sin(2 * pi * 250 * time);
left = zeros(total, 1);
right = zeros(total, 1);
[left, right] = place(left, right, tone, [0.2 0.6], 0.4, 0.1, sampleRate);
[left, right] = place(left, right, tone, [1.8 2.0], 0.3, 0.3, sampleRate);
[left, right] = place(left, right, tone, [1.0 1.4], 1.5, 0.2, sampleRate);
left = min(max(left, -1), 1);
audiowrite(char(audioPath), [left right], sampleRate, BitsPerSample=24);
fileInfo = dir(audioPath);

dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() cleanUpFixture(conn, dbFile, sourceRoot, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES (1,'call-test','Call test')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path,filename,file_format,size_bytes,checksum_sha256) " + ...
    "VALUES (1,1,'recording_audio','audio/calls.wav','audio/calls.wav'," + ...
    "'calls.wav','wav'," + string(fileInfo.bytes) + ",'synthetic-sha256')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id,sample_rate_hz,channel_count,duration_s) " + ...
    "VALUES (1,1,1,'calls',1000,2,2)");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index,channel_label) VALUES (1,1,1,'left'),(2,1,2,'right')");
versionId = scalar(conn, "SELECT MIN(extractor_version_id) AS n FROM extractor_versions");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES (1,1," + string(versionId) + ",'synthetic')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES (1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s) VALUES " + ...
    "(1,1,1,'d1',0.2,0.6),(2,1,1,'d2',1.8,2.3),(3,1,1,'d3',2.5,2.7)," + ...
    "(4,1,1,'d4',1.0,1.4),(5,1,1,'d5',0.8,0.8)");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES (100,1,'consensus','synthetic-consensus')");
execute(conn, "INSERT INTO consensus_events(consensus_event_id,analysis_run_id," + ...
    "recording_id,start_time_s,end_time_s,derivation_method) " + ...
    "VALUES (1,100,1,0.2,0.6,'synthetic')");
fixture = struct(conn=conn, db_file=dbFile, repo_root=repoRoot, ...
    source_root=sourceRoot, audio_path=string(audioPath));
end

function [left, right] = place(left, right, tone, interval, leftAmplitude, ...
        rightAmplitude, sampleRate)
% Half-open [start,end) in seconds as one-based sample indices, as in the demo.
selected = (round(interval(1) * sampleRate) + 1:round(interval(2) * sampleRate))';
left(selected) = leftAmplitude * tone(selected);
right(selected) = rightAmplitude * tone(selected);
end

function counts = tableCounts(conn)
counts = [scalar(conn, "SELECT COUNT(*) AS n FROM analysis_runs"), ...
    scalar(conn, "SELECT COUNT(*) AS n FROM derived_measurements")];
end

function message = sqlFailure(conn, sql)
message = "";
try
    execute(conn, sql);
catch exception
    message = string(exception.message);
end
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

function repoRoot = repositoryRoot()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
