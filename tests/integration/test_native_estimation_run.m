function tests = test_native_estimation_run
%TEST_NATIVE_ESTIMATION_RUN Phase 6.9: the native run, written and reconstructed.
%
% The session is 6.5's (test_identity_candidate_geometry): a piecewise audio
% clock, an affine video clock, a neural reference, and two native tracks whose
% snouts move linearly. Added here: real two-channel audio at 1000 Hz in which
% channel 2's gain is half channel 1's for every source; two noise references
% for the response estimate; and the 6.6/6.7 acoustic chain run per call.
%
% Participants are A and B. Targets:
%   detection 1 (300.0 s)   track0 is A, track1 is B, whole call. The call is
%                           generated from A's own midpoint distances under the
%                           method's spherical assumption: SELF-CONSISTENCY
%   detection 3 (600.0 s)   claims exist, but the tracking has no samples here
%   detection 5 (1100.0 s)  the tracks swap identities during the call
%
% The fixture is a copy of 6.5's, extended; see the handoff for why it was not
% made a shared helper.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
[fixture, cleanup] = setUpSession();
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ======================================================= plan and apply ===

function testPlanWritesNothingAndApplyWritesExactlyThePlan(testCase)
f = testCase.TestData.fixture;
before = counts(f.conn);
plan = vawlume.estimator.attributeCallers(f.conn, struct(recording_id=1), ...
    runSpec(f, "native-plan-apply"), RepoRoot=f.repo_root);
verifyEqual(testCase, plan.status, "planned");
verifyEqual(testCase, counts(f.conn), before, "Planning writes nothing.");
verifyEqual(testCase, numel(plan.targets), 3);

applied = vawlume.estimator.attributeCallers(f.conn, struct(recording_id=1), ...
    runSpec(f, "native-plan-apply"), Apply=true, RepoRoot=f.repo_root);
verifyEqual(testCase, applied.status, "applied");
verifyEqual(testCase, string(f.conn.AutoCommit), "on", "AutoCommit is restored.");
after = counts(f.conn);
delta = after - before;
p = plan.planned_counts;
verifyEqual(testCase, delta, [p.attribution_runs, p.attribution_targets, ...
    p.attribution_candidates, p.attribution_evidence, ...
    p.attribution_run_declared_inputs], "Apply writes exactly the planned rows.");
verifyEqual(testCase, p.attribution_candidates, 6, "One candidate per participant per target.");

verifyError(testCase, @() vawlume.estimator.attributeCallers(f.conn, ...
    struct(recording_id=1), runSpec(f, "native-plan-apply"), Apply=true, ...
    RepoRoot=f.repo_root), "vawlume:estimator:RunAlreadyApplied");
verifyEqual(testCase, counts(f.conn), after);
end

function testTheScoredTargetRanksTheTrueCallerFirst(testCase)
% Self-consistency, not accuracy: the call was generated from A's position.
f = testCase.TestData.fixture;
applied = apply(f, "native-scores");
target = applied.targets([applied.targets.event_id] == 1);
c = target.method.candidates;
verifyEqual(testCase, c.status, ["scored"; "scored"]);
a = c.entity_id == f.A;
verifyGreaterThan(testCase, c.score(a), c.score(~a));
verifyGreaterThan(testCase, c.score(a), -0.05, "A fits its own call to within quantization.");
log(testCase, 1, sprintf("Detection 1 scores: A %.6f dB, B %.6f dB; observed %.4f dB; " + ...
    "predicted A %.4f dB, B %.4f dB", c.score(a), c.score(~a), c.observed_difference_db(1), ...
    c.predicted_difference_db(a), c.predicted_difference_db(~a)));
stored = fetch(f.conn, "SELECT ac.entity_id, ac.score, ac.score_semantics, " + ...
    "IFNULL(ac.probability,-99) AS probability FROM attribution_candidates ac " + ...
    "JOIN attribution_targets t ON t.attribution_target_id=ac.attribution_target_id " + ...
    "WHERE t.attribution_target_id=" + string(target.attribution_target_id) + ...
    " ORDER BY ac.entity_id");
verifyEqual(testCase, double(stored.score), c.score(argsort(c.entity_id)));
verifyTrue(testCase, all(double(stored.probability) == -99), "No probability is ever stored.");
verifyTrue(testCase, all(contains(string(stored.score_semantics), "not a probability")));
end

function testAFailureLateInTheRunLeavesNoRowOfIt(testCase)
% Itinerary 6.9a: a native run is ONE transaction. The failure is injected
% AFTER createRun and addCandidates have written, by a trigger that aborts the
% insert of a pose-confidence evidence row (written last, per candidate). If
% any write had committed on its own, the run, its targets or candidates would
% survive here.
f = testCase.TestData.fixture;
tables = ["analysis_runs", "attribution_runs", "attribution_targets", ...
    "attribution_candidates", "attribution_evidence", ...
    "attribution_run_declared_inputs", "analysis_run_sources", ...
    "analysis_run_profiles"];
before = tableCounts(f.conn, tables);
execute(f.conn, "CREATE TRIGGER zz_abort_pose_confidence BEFORE INSERT ON " + ...
    "attribution_evidence WHEN NEW.evidence_kind='bodypoint_pose_confidence' " + ...
    "BEGIN SELECT RAISE(ABORT, 'injected failure for 6.9a'); END");
dropTrigger = onCleanup(@() execute(f.conn, "DROP TRIGGER IF EXISTS zz_abort_pose_confidence"));
failed = false;
try
    apply(f, "native-atomic");
catch failure
    failed = true;
    verifySubstring(testCase, failure.message, "injected failure for 6.9a", ...
        "The original error is rethrown unchanged.");
end
verifyTrue(testCase, failed, "The injected failure must surface.");
verifyEqual(testCase, tableCounts(f.conn, tables), before, ...
    "No row of the failed run survives in any table it writes.");
verifyEqual(testCase, string(f.conn.AutoCommit), "on", "AutoCommit is restored.");
clear dropTrigger
% The failed apply left nothing behind, so the same key is still unused.
verifyEqual(testCase, apply(f, "native-atomic").status, "applied");
end

% ===================================================== reconstruction ===

function testEveryStoredScoreIsReconstructedFromStorage(testCase)
% THE TEST OF CONDITION 4 (contract 06 invariant 23). After Apply, everything
% below is read back from the database: the stored evidence rows, the rows they
% cite, and the stored settings profile version. Nothing is carried over from the
% run. Each scored candidate's score is recomputed by the pure method and must
% equal the stored score; each unscored candidate's reason must be recovered.
f = testCase.TestData.fixture;
apply(f, "native-reconstruct");
conn = f.conn;
run = fetch(conn, "SELECT attribution_run_id, settings_profile_version_id " + ...
    "FROM attribution_runs WHERE run_key='native-reconstruct'");
profile = fetch(conn, "SELECT content_uri, checksum_sha256 FROM config_profile_versions " + ...
    "WHERE profile_version_id=" + string(double(run.settings_profile_version_id)));
settings = vawlume.estimator.loadSettings(string(profile.content_uri), RepoRoot=f.repo_root);
verifyEqual(testCase, settings.checksum_sha256, string(profile.checksum_sha256));
p = settings.parameters;

targets = fetch(conn, "SELECT attribution_target_id FROM attribution_targets " + ...
    "WHERE attribution_run_id=" + string(double(run.attribution_run_id)));
scoredSeen = 0;
for t = double(targets.attribution_target_id)'
    candidates = fetch(conn, "SELECT attribution_candidate_id, entity_id, " + ...
        "IFNULL(score,-1e308) AS score, IFNULL(notes,'') AS notes " + ...
        "FROM attribution_candidates WHERE attribution_target_id=" + string(t) + ...
        " ORDER BY entity_id");
    difference = storedDifference(conn, t, p);
    [entities, geometry] = storedGeometry(conn, candidates, p);
    recomputed = vawlume.estimator.levelDifferenceConsistency(entities, geometry, ...
        difference, settings).candidates;
    for k = 1:height(candidates)
        storedScore = double(candidates.score(k));
        if storedScore > -1e307
            scoredSeen = scoredSeen + 1;
            verifyEqual(testCase, recomputed.score(k), storedScore, ...
                sprintf("target %d entity %d", t, candidates.entity_id(k)), AbsTol=1e-12);
        else
            verifyEqual(testCase, "no_score_reason=" + recomputed.no_score_reason(k), ...
                string(candidates.notes(k)), sprintf("target %d entity %d", t, ...
                candidates.entity_id(k)));
        end
    end
end
verifyEqual(testCase, scoredSeen, 2, "Both candidates of detection 1 were reconstructed.");
end

% ================================================= unscored but evidenced ===

function testASwapAndATrackingGapAreUnscoredWithTheirEvidence(testCase)
f = testCase.TestData.fixture;
applied = apply(f, "native-unscored");
swap = applied.targets([applied.targets.event_id] == 5);
verifyEqual(testCase, swap.method.candidates.no_score_reason, ...
    ["identity_changes_within_window"; "identity_changes_within_window"]);
verifyTrue(testCase, all(isnan(swap.method.candidates.score)), "No default score.");
gap = applied.targets([applied.targets.event_id] == 3);
verifyTrue(testCase, all(ismember(gap.method.candidates.no_score_reason, ...
    ["track_covered_empty", "track_not_covered"])));
log(testCase, 1, "Detection 3 (tracking gap) reasons: " + ...
    strjoin(gap.method.candidates.no_score_reason, ", "));

for target = [swap, gap]
    rows = storedEvidence(f.conn, target.attribution_target_id);
    % The acoustic evidence that WAS available is written regardless.
    verifyEqual(testCase, sum(rows.evidence_kind == "call_band_power_normalized"), 2);
    verifyEqual(testCase, sum(rows.evidence_kind == "normalized_level_difference"), 1);
    verifyEqual(testCase, sum(rows.evidence_kind == "call_clock_placement"), ...
        sum(target.target_evidence.evidence_dimension == "temporal_alignment"));
    verifyGreaterThanOrEqual(testCase, sum(rows.evidence_kind == "call_clock_placement"), 1, ...
        "The audio clock placement exists even where tracking does not.");
    candidates = fetch(f.conn, "SELECT IFNULL(score,-1e308) AS score, notes FROM " + ...
        "attribution_candidates WHERE attribution_target_id=" + ...
        string(target.attribution_target_id));
    verifyTrue(testCase, all(double(candidates.score) < -1e307));
    verifyTrue(testCase, all(startsWith(string(candidates.notes), "no_score_reason=")));
end
% The swap still records the associations each candidate was resolved through,
% and no distance: there is no single track to measure from.
swapRows = storedEvidence(f.conn, swap.attribution_target_id);
verifyEqual(testCase, sum(swapRows.evidence_kind == "bodypoint_microphone_distance"), 0);
end

% ======================================================= evidence shape ===

function testEveryRowIsOneDimensionWithACitationAndAProducer(testCase)
f = testCase.TestData.fixture;
applied = apply(f, "native-evidence");
scored = applied.targets([applied.targets.event_id] == 1);
rows = storedEvidence(f.conn, scored.attribution_target_id);
verifyTrue(testCase, all(contains(rows.value_semantics, "producer=")));
kinds = unique(rows.evidence_kind);
verifyEqual(testCase, sort(kinds), sort(["call_clock_placement"; ...
    "call_band_power_normalized"; "normalized_level_difference"; ...
    "track_entity_association_used"; "bodypoint_microphone_distance"; ...
    "bodypoint_pose_confidence"]));
perChannel = rows(rows.evidence_kind == "call_band_power_normalized", :);
verifyTrue(testCase, all(~isnan(perChannel.derived_measurement_id)), "P4-3 citation.");
verifyTrue(testCase, all(~isnan(perChannel.recording_channel_id)));
clock = rows(rows.evidence_kind == "call_clock_placement", :);
verifyEqual(testCase, height(clock), 2, "One row per alignment run used: audio and tracking.");
verifyTrue(testCase, all(~isnan(clock.alignment_run_id)));
verifyTrue(testCase, all(contains(clock.value_semantics, "uncalibrated")));
identity = rows(rows.evidence_kind == "track_entity_association_used", :);
verifyEqual(testCase, height(identity), 2);
verifyTrue(testCase, all(identity.identity_statement_kind == "identity_association"));
distances = rows(rows.evidence_kind == "bodypoint_microphone_distance", :);
verifyTrue(testCase, all(distances.value_units == "cm"));
verifyTrue(testCase, all(~isnan(distances.tracking_identity_association_id) & ...
    ~isnan(distances.recording_channel_id)));
verifyTrue(testCase, all(rows.evidence_dimension ~= "source_localization"));
declared = fetch(f.conn, "SELECT input_dimension, declaration FROM " + ...
    "attribution_run_declared_inputs WHERE attribution_run_id=" + ...
    string(applied.attribution_run_id));
verifyEqual(testCase, height(declared), 4, "No undeclared dimension.");
end

function testReportReadsTheNativeRunThroughItsUsualFields(testCase)
% Extend, do not replace: the native run reads back through report's existing
% field set (report.m is not edited in 6.9). What report cannot yet show is
% recorded, not fixed: the P4-3 citation column (6.10 adds it, contract D15).
f = testCase.TestData.fixture;
applied = apply(f, "native-report");
value = vawlume.attribution.report(f.conn, struct(attribution_run_id=applied.attribution_run_id));
verifyEqual(testCase, height(value.targets), 3);
verifyEqual(testCase, height(value.candidates), 6);
verifyEqual(testCase, height(value.declared_inputs), 4);
verifyEqual(testCase, height(value.evidence), applied.planned_counts.attribution_evidence);
verifyFalse(testCase, ismember("derived_measurement_id", ...
    string(value.evidence.Properties.VariableNames)), ...
    "If this fails, report learned the P4-3 column: update the 6.10 notes.");
end

% ============================================================ refusals ===

function testEachRefusalFiresBeforeAnyWrite(testCase)
f = testCase.TestData.fixture;
before = counts(f.conn);
try_ = @(spec, id) verifyError(testCase, @() vawlume.estimator.attributeCallers( ...
    f.conn, struct(recording_id=1), spec, Apply=true, RepoRoot=f.repo_root), id);

mixed = runSpec(f, "refused");
mixed.target_set = struct(detection_ids=[1 8]);
try_(mixed, "vawlume:attribution:TargetSetMixed");

foreignTarget = runSpec(f, "refused");
foreignTarget.target_set = struct(detection_ids=9);
try_(foreignTarget, "vawlume:attribution:TargetSetCrossesRecording");

stranger = runSpec(f, "refused");
stranger.participating_entity_ids = [f.A f.unlinked];
try_(stranger, "vawlume:attribution:EntityNotInRecording");

foreignStream = runSpec(f, "refused");
foreignStream.tracking.stream = struct(external_stream_id=f.foreign_stream);
try_(foreignStream, "vawlume:estimator:InputRecordingMismatch");

foreignNormalization = runSpec(f, "refused");
foreignNormalization.normalization_runs.analysis_run_id(1) = f.foreign_normalization_run;
try_(foreignNormalization, "vawlume:estimator:InputRecordingMismatch");

wrongEvent = runSpec(f, "refused");
wrongEvent.normalization_runs.analysis_run_id(1:2) = ...
    wrongEvent.normalization_runs.analysis_run_id([2 1]);
try_(wrongEvent, "vawlume:estimator:NormalizationRunInvalid");

wrongKind = runSpec(f, "refused");
wrongKind.settings_profile_version_id = f.wrong_kind_profile;
try_(wrongKind, "vawlume:estimator:SettingsProfileKindInvalid");

unconnected = runSpec(f, "refused");
unconnected.tracking.alignment_run_id = f.audio_run;
try_(unconnected, "vawlume:tracking:ClockDeclarationInvalid");

verifyEqual(testCase, counts(f.conn), before, "Nothing was written by any refusal.");
end

% ======================================================= static checks ===

function testTheEstimatorPackageWritesNoSql(testCase)
% Tripwire 3 and contract 06 invariant 30: every native write goes through
% +attribution/'s public functions. String literals are KEPT, so SQL text is seen.
root = fullfile(testCase.TestData.fixture.repo_root, "src", "+vawlume", "+estimator");
files = [dir(fullfile(root, "*.m")); dir(fullfile(root, "private", "*.m"))];
pattern = "\<(INSERT|UPDATE|DELETE|REPLACE)\>|\<(sqlwrite|sqlupdate|sqlinsert)\s*\(";
hits = strings(0, 1);
for file = files'
    for line = splitlines(string(fileread(fullfile(file.folder, file.name))))'
        code = regexprep(line, "%.*$", "");
        if ~isempty(regexp(code, pattern, "once"))
            hits(end + 1, 1) = file.name + ": " + strtrim(code); %#ok<AGROW>
        end
    end
end
verifyEmpty(testCase, hits, strjoin(hits, newline));
verifyNotEmpty(testCase, regexp("x = ""INSERT INTO t VALUES (1)"";", pattern, "once"));
end

% ============================================================= helpers ===

function result = apply(f, runKey)
result = vawlume.estimator.attributeCallers(f.conn, struct(recording_id=1), ...
    runSpec(f, runKey), Apply=true, RepoRoot=f.repo_root);
end

function spec = runSpec(f, runKey)
spec = struct(run_key=runKey, settings_profile_version_id=f.settings_version, ...
    target_set=struct(detection_ids=[1 3 5]), participating_entity_ids=[f.A f.B], ...
    clock=audioClock(f), ...
    tracking=struct(stream=streamRef(), alignment_run_id=f.video_run, ...
        source_root=f.workspace), ...
    normalization_runs=table([1; 3; 5], f.normalization_runs(:), ...
        VariableNames=["detection_id", "analysis_run_id"]));
end

function value = counts(conn)
names = ["attribution_runs", "attribution_targets", "attribution_candidates", ...
    "attribution_evidence", "attribution_run_declared_inputs"];
value = zeros(1, numel(names));
for k = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(k));
    value(k) = double(rows.n(1));
end
end

function value = tableCounts(conn, tables)
value = zeros(1, numel(tables));
for k = 1:numel(tables)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tables(k));
    value(k) = double(rows.n(1));
end
end

function rows = storedEvidence(conn, targetId)
% Every evidence row of a target, target-level and candidate-level.
rows = fetch(conn, "SELECT ev.evidence_dimension, ev.evidence_kind, " + ...
    "IFNULL(ev.value_real,-1e308) AS value_real, IFNULL(ev.value_units,'') AS value_units, " + ...
    "IFNULL(ev.value_semantics,'') AS value_semantics, " + ...
    "IFNULL(ev.identity_statement_kind,'') AS identity_statement_kind, " + ...
    "IFNULL(ev.tracking_identity_association_id,-1) AS tracking_identity_association_id, " + ...
    "IFNULL(ev.alignment_run_id,-1) AS alignment_run_id, " + ...
    "IFNULL(ev.recording_channel_id,-1) AS recording_channel_id, " + ...
    "IFNULL(ev.derived_measurement_id,-1) AS derived_measurement_id, " + ...
    "IFNULL(ac.entity_id,-1) AS entity_id " + ...
    "FROM attribution_evidence ev LEFT JOIN attribution_candidates ac " + ...
    "ON ac.attribution_candidate_id=ev.attribution_candidate_id " + ...
    "WHERE ev.attribution_target_id=" + string(targetId));
for name = ["evidence_dimension", "evidence_kind", "value_units", "value_semantics", ...
        "identity_statement_kind"]
    rows.(name) = string(rows.(name));
end
value = double(rows.value_real);
value(value < -1e307) = NaN;
rows.value_real = value;
for name = ["tracking_identity_association_id", "alignment_run_id", ...
        "recording_channel_id", "derived_measurement_id", "entity_id"]
    value = double(rows.(name));
    value(value == -1) = NaN;
    rows.(name) = value;
end
end

function d = storedDifference(conn, targetId, p)
% The observed difference, recomputed from the two stored per-channel rows and
% the measurements they cite. Nothing from the run is used.
rows = storedEvidence(conn, targetId);
perChannel = rows(rows.evidence_kind == "call_band_power_normalized", :);
sides = repmat(struct(target_kind="detection", target_id=targetId, channel_index=NaN, ...
    normalized_metric="call_band_power_normalized", unit="", status="not_normalized", ...
    reason="not_stored", value=NaN, qc_flags=strings(0, 1), ...
    derived_measurement_id=NaN), 1, 2);
for k = 1:2
    sides(k).channel_index = p.channel_pair(k);
    channelId = channelIdOf(conn, p.channel_pair(k));
    row = perChannel(perChannel.recording_channel_id == channelId, :);
    if height(row) == 1
        cited = fetch(conn, "SELECT value_real, unit, derivation_details_json " + ...
            "FROM derived_measurements WHERE derived_measurement_id=" + ...
            string(row.derived_measurement_id));
        details = jsondecode(char(cited.derivation_details_json(1)));
        sides(k).status = "normalized";
        sides(k).reason = "";
        sides(k).value = row.value_real;
        sides(k).unit = row.value_units;
        sides(k).derived_measurement_id = row.derived_measurement_id;
        sides(k).qc_flags = string(details.qc_flags(:));
        assert(double(cited.value_real(1)) == row.value_real, ...
            "The evidence row reports exactly the measurement it cites.");
    end
end
d = vawlume.acoustic.levelDifference(sides(1), sides(2), p.refuse_clipped_channels);
end

function [entities, geometry] = storedGeometry(conn, candidates, p)
% Each candidate's distances on the primary basis, read from its stored rows.
count = height(candidates);
entities = table(double(candidates.entity_id), true(count, 1), strings(count, 1), ...
    VariableNames=["entity_id", "has_geometry", "reason"]);
geometry = table();
for k = 1:count
    notes = string(candidates.notes(k));
    rows = fetch(conn, "SELECT value_real, value_units, value_semantics, " + ...
        "recording_channel_id FROM attribution_evidence WHERE attribution_candidate_id=" + ...
        string(double(candidates.attribution_candidate_id(k))) + ...
        " AND evidence_kind='bodypoint_microphone_distance'");
    semantics = string(rows.value_semantics);
    primary = contains(semantics, "instant_basis=" + p.primary_instant_basis + ";");
    if startsWith(notes, "no_score_reason=") && sum(primary) < 2
        % No usable distance pair was stored, so the reason is the stored one.
        entities.has_geometry(k) = false;
        entities.reason(k) = extractAfter(notes, "no_score_reason=");
        continue
    end
    for r = find(primary)'
        geometry = [geometry; table(entities.entity_id(k), ...
            channelIndexOf(conn, double(rows.recording_channel_id(r))), ...
            p.primary_instant_basis, double(rows.value_real(r)), ...
            string(rows.value_units(r)), "computed", "", ...
            field(semantics(r), "event_extrapolated") == "true", ...
            field(semantics(r), "bracket_extrapolated") == "true", ...
            VariableNames=["entity_id", "channel_index", "instant_basis", "distance", ...
            "unit", "status", "reason", "event_extrapolated", ...
            "bracket_extrapolated"])]; %#ok<AGROW>
    end
end
if isempty(geometry)
    geometry = table(zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), false(0, 1), false(0, 1), ...
        VariableNames=["entity_id", "channel_index", "instant_basis", "distance", ...
        "unit", "status", "reason", "event_extrapolated", "bracket_extrapolated"]);
end
end

function value = field(semantics, key)
token = regexp(semantics, "(^|; )" + key + "=([^;]*)", "tokens", "once");
value = string(token{2});
end

function id = channelIdOf(conn, channelIndex)
rows = fetch(conn, "SELECT recording_channel_id FROM recording_channels " + ...
    "WHERE recording_id=1 AND channel_index=" + string(channelIndex));
id = double(rows.recording_channel_id(1));
end

function index = channelIndexOf(conn, channelId)
rows = fetch(conn, "SELECT channel_index FROM recording_channels " + ...
    "WHERE recording_channel_id=" + string(channelId));
index = double(rows.channel_index(1));
end

function order = argsort(values)
[~, order] = sort(values);
end

function value = audioClock(fixture)
value = struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
    audio_alignment_run_id=fixture.audio_run);
end

function value = streamRef()
value = struct(project_key="synthetic_alignment_session", stream_name="arena_tracking");
end

function [x, y] = truePosition(track, videoTime)
if track == "track0"
    x = 10 + 0.01 * videoTime;
    y = 20 + 0 * videoTime;
else
    x = 50 + 0 * videoTime;
    y = 20 + 0.005 * videoTime;
end
end

% ============================================================= fixture ===

function [fixture, cleanup] = setUpSession()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
workspace = string(fullfile(tempdir, "vawlume_native_run_" + ...
    string(java.util.UUID.randomUUID)));
mkdir(workspace);
mkdir(fullfile(workspace, "audio"));
conn = sqlite(char(fullfile(workspace, "session.sqlite")), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);

execute(conn, "INSERT INTO projects(project_key, project_name) VALUES " + ...
    "('synthetic_alignment_session', 'Synthetic alignment session')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, " + ...
    "relative_path) VALUES (1, 'recording_audio', 'audio/session.wav', " + ...
    "'audio/session.wav'),(1, 'recording_audio', 'audio/other.wav', 'audio/other.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, native_recording_id, " + ...
    "sample_rate_hz, channel_count) VALUES (1, 1, 'REC_SESSION_01', 1000, 2)," + ...
    "(1, 2, 'REC_OTHER', 1000, 2)");

fixture = struct(conn=conn, workspace=workspace, repo_root=repoRoot, knot=900, ...
    video_scale=0.9992, video_offset=53.40, mics=[0 0; 100 0], gains=[1 0.5]);
fixture.scale = [1.0015; 0.9990];
fixture.offset = [117.25; (1.0015 - 0.9990) * fixture.knot + 117.25];
audioTimes = [10; 400; 900; 1200; 1500];
segment = 1 + double(audioTimes >= fixture.knot);
neuralTimes = fixture.scale(segment) .* audioTimes + fixture.offset(segment);
videoTimes = (neuralTimes - fixture.video_offset) / fixture.video_scale;
writetable(behaviorTable(), fullfile(workspace, "video_events.csv"));
writetable(neuralTable(neuralTimes), fullfile(workspace, "neural_events.csv"));
writetable(anchorTable(audioTimes, videoTimes, neuralTimes), ...
    fullfile(workspace, "sync_anchors.csv"));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
vawlume.ingest.alignment(conn, string(manifestPath), RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);
execute(conn, "UPDATE time_alignment_runs SET method='piecewise_affine' " + ...
    "WHERE source_timebase_id = (SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='audio_native')");
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="video_native", Apply=true);
fixture.audio_run = runIdFor(conn, "audio_native");
fixture.video_run = runIdFor(conn, "video_native");

execute(conn, "INSERT INTO extractors(extractor_id, extractor_key, extractor_name) " + ...
    "VALUES (90,'synthetic','Synthetic')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id, extractor_id, " + ...
    "version_label) VALUES (90,90,'v')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id, project_id, " + ...
    "extractor_version_id, run_key) VALUES (1, 1, 90, 'calls'), (2, 1, 90, 'other-calls')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id, recording_id) " + ...
    "VALUES (1, 1), (2, 1), (1, 2)");
% Detection 8 is a second event set on the same recording; detection 9 is on
% another recording.
execute(conn, "INSERT INTO detections(detection_id, extraction_run_id, recording_id, " + ...
    "start_time_s, end_time_s) VALUES (1,1,1,300.0,300.1),(3,1,1,600.0,600.1)," + ...
    "(5,1,1,1100.0,1100.2),(8,2,1,300.0,300.1),(9,1,2,300.0,300.1)");

execute(conn, "INSERT INTO entity_types(project_id, native_name) VALUES (1, 'subject')");
execute(conn, "INSERT INTO experimental_entities(entity_id, project_id, entity_type_id, " + ...
    "native_id) VALUES (1,1,1,'A'),(2,1,1,'B'),(5,1,1,'X')");
execute(conn, "INSERT INTO recording_entity_links(recording_id, entity_id) VALUES (1,1),(1,2)");
fixture.A = 1; fixture.B = 2; fixture.unlinked = 5;

vawlume.geometry.registerCoordinateSystem(conn, struct(project_id=1), struct( ...
    coordinate_system_key="arena_2d", coordinate_system_name="Arena floor plane", ...
    dimensionality=2, unit="cm"));
for channel = 1:2
    vawlume.geometry.registerRecordingChannel(conn, struct(recording_id=1), ...
        struct(channel_index=channel));
    vawlume.geometry.registerChannelPlacement(conn, struct(recording_id=1), struct( ...
        channel_index=channel, coordinate_system_key="arena_2d", ...
        position_x=fixture.mics(channel, 1), position_y=fixture.mics(channel, 2)));
end

regions = [videoAround(fixture, 300.5, 1.5); videoAround(fixture, 1100.1, 1)];
writeTrackingCsv(fullfile(workspace, "arena_tracking.csv"), regions);
profilePath = fullfile(workspace, "tracking_profile.json");
writelines(string(fileread(fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "tracking", "generic_tracking_mapping_profile.json"))), profilePath);
vawlume.tracking.register(conn, struct(recording_id=1), struct( ...
    artifact_path="arena_tracking.csv", profile_path=profilePath, ...
    timebase_key="video_native", stream_name="arena_tracking"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=workspace);
registerIdentity(fixture);
% A tracking stream of the other recording, for the refusal.
execute(conn, "INSERT INTO timebases(project_id, recording_id, timebase_name, " + ...
    "timebase_kind, native_unit) VALUES (1, 2, 'other_video', 'video_clock', 's')");
execute(conn, "INSERT INTO external_streams(project_id, recording_id, timebase_id, " + ...
    "stream_name, stream_kind) VALUES (1, 2, (SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='other_video'), 'other_tracking', 'tracking')");
fixture.foreign_stream = double(fetch(conn, "SELECT external_stream_id AS id FROM " + ...
    "external_streams WHERE stream_name='other_tracking'").id);

settings = vawlume.estimator.loadSettings(RepoRoot=repoRoot);
fixture.settings_version = vawlume.db.registerProfileVersion(conn, struct(project_id=1), ...
    struct(profile_key=settings.profile_key, profile_name=settings.profile_name, ...
    version_label=settings.version_label, content_path=settings.path, ...
    profile_kind=settings.profile_kind, ...
    profile_schema_version=settings.profile_schema_version), ...
    RepoRoot=repoRoot).profile_version_id;
fixture.wrong_kind_profile = vawlume.db.registerProfileVersion(conn, struct(project_id=1), ...
    struct(profile_key="noise-policy", profile_name="Normalization policy", ...
    version_label="1.0.0", content_path=fullfile(repoRoot, "config", ...
    "09_acoustic_normalization_policies", "band_matched_noise_reference_v1.json"), ...
    profile_kind="analysis_settings"), RepoRoot=repoRoot).profile_version_id;

% The call at detection 1 is generated from A's own midpoint distances, read
% through the same geometry the estimator will use: self-consistency.
geometry = vawlume.estimator.candidateGeometry(conn, struct(detection_id=1), ...
    audioClock(fixture), struct(stream=streamRef(), bodypart=settings.parameters.bodypart, ...
    max_gap_s=settings.parameters.max_interpolation_gap_s, ...
    alignment_run_id=fixture.video_run, source_root=workspace, repo_root=repoRoot), ...
    [fixture.A fixture.B], [1 2]);
g = geometry.geometry;
at = g(g.entity_id == fixture.A & g.instant_basis == "midpoint", :);
distanceA = [at.distance(at.channel_index == 1), at.distance(at.channel_index == 2)];
fixture.true_distances = distanceA;
writeAudio(fixture, fullfile(workspace, "audio", "session.wav"), distanceA);

fixture.normalization_runs = acousticChain(fixture, workspace);
fixture.foreign_normalization_run = foreignNormalization(conn);
end

function writeAudio(fixture, path, distanceA)
% Channel k hears every source at gain(k). Calls are 250 Hz; the noise family is
% four tones in the declared band [200, 300] Hz. Every window holds whole cycles.
rate = 1000;
total = 1102 * rate;
time = (0:total - 1)' / rate;
source = zeros(total, 2);
noise = zeros(total, 1);
for frequency = [220 240 260 280]
    noise = noise + 0.05 * sin(2 * pi * frequency * time);
end
tone = sin(2 * pi * 250 * time);
for channel = 1:2
    g = fixture.gains(channel);
    source = place(source, channel, g * noise, [50.0 50.4], rate);
    source = place(source, channel, g * noise, [50.4 50.8], rate);
    % Spherical spreading from A: amplitude ~ 1/d, so power ~ 1/d^2.
    source = place(source, channel, g * (10 / distanceA(channel)) * tone, [300.0 300.1], rate);
    source = place(source, channel, g * 0.2 * tone, [600.0 600.1], rate);
    source = place(source, channel, g * 0.3 * tone, [1100.0 1100.2], rate);
end
audiowrite(char(path), source, rate, BitsPerSample=24);
end

function signal = place(signal, channel, values, interval, rate)
selected = (round(interval(1) * rate) + 1:round(interval(2) * rate))';
signal(selected, channel) = values(selected);
end

function runs = acousticChain(fixture, workspace)
% 6.6 and 6.7, through their public functions: references, a response estimate,
% then per call a measurement and a normalization.
conn = fixture.conn;
ids = zeros(0, 1);
for k = 1:2
    interval = [50.0 50.4] + 0.4 * (k - 1);
    ref = vawlume.acoustic.registerReference(conn, struct(recording_id=1), struct( ...
        reference_key="noise-" + k, reference_type="noise", start_time_s=interval(1), ...
        end_time_s=interval(2), frequency_min_hz=200, frequency_max_hz=300));
    for channel = 1:2
        measured = vawlume.acoustic.measureReferenceResponse(conn, ...
            struct(acoustic_reference_id=ref.acoustic_reference_id), channel, ...
            SourceRoot=workspace, Apply=true, RunKey="ref-" + k + "-ch" + channel);
        ids(end + 1, 1) = measured.derived_measurement_ids( ...
            measured.metrics.metric_key == "acoustic_band_power"); %#ok<AGROW>
    end
end
response = vawlume.acoustic.estimateChannelResponse(conn, struct(recording_id=1), ids, ...
    RequiredReferenceTypes="noise", MinReferences=2, Apply=true, ...
    RunKey="response").analysis_run_id;
runs = zeros(1, 3);
detections = [1 3 5];
for k = 1:3
    call = vawlume.acoustic.measureCallWindow(conn, struct(detection_id=detections(k)), ...
        [1 2], BandHz=[200 300], SourceRoot=workspace, Apply=true, ...
        RunKey="call-d" + detections(k));
    normalized = vawlume.acoustic.normalizeCallLevels(conn, ...
        struct(analysis_run_id=call.analysis_run_id), struct(analysis_run_id=response), ...
        RepoRoot=fixture.repo_root, Apply=true, RunKey="norm-d" + detections(k));
    runs(k) = normalized.analysis_run_id;
end
end

function runId = foreignNormalization(conn)
% A normalization run whose call-window parent measured detection 9, an event of
% the other recording. Written by SQL: only its lineage matters to the refusal.
execute(conn, "INSERT INTO recording_channels(recording_id, channel_index) VALUES (2, 1)");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id, project_id, run_type, run_key, " + ...
    "status) VALUES (900, 1, 'acoustic_call_window_response', 'foreign-call', 'completed')," + ...
    "(901, 1, 'acoustic_call_level_normalization', 'foreign-norm', 'completed')");
execute(conn, "INSERT INTO derived_measurements(analysis_run_id, metric_definition_id, " + ...
    "detection_id, value_real) VALUES (900, (SELECT metric_definition_id FROM " + ...
    "metric_definitions WHERE metric_key='call_band_power'), 9, 0.1)");
execute(conn, "INSERT INTO analysis_run_sources(analysis_run_id, source_analysis_run_id, " + ...
    "dependency_role) VALUES (901, 900, 'call_window_measurement')");
runId = 901;
end

function registerIdentity(fixture)
v = @(audioTime) videoTimeOf(fixture, audioTime);
claim = @(track, entity, startAudio, endAudio) ...
    vawlume.tracking.registerIdentityAssociation(fixture.conn, streamRef(), struct( ...
    native_track_id=track, entity_id=entity, start_time_native=v(startAudio), ...
    end_time_native=v(endAudio), assignment_state="assigned", ...
    evidence_kind="manual_assertion"));
claim("track0", fixture.A, 299.0, 302.0);
claim("track1", fixture.B, 299.0, 302.0);
claim("track0", fixture.A, 590, 610);
claim("track1", fixture.B, 590, 610);
claim("track0", fixture.A, 1099, 1100.15);
claim("track0", fixture.B, 1100.15, 1101.2);
claim("track1", fixture.B, 1099, 1100.15);
claim("track1", fixture.A, 1100.15, 1101.2);
end

function value = videoTimeOf(fixture, audioTime)
reference = vawlume.alignment.applyTransform(fixture.conn, fixture.audio_run, audioTime);
value = (reference - fixture.video_offset) / fixture.video_scale;
end

function region = videoAround(fixture, audioTime, halfWidth)
center = videoTimeOf(fixture, audioTime);
region = [center - halfWidth, center + halfWidth];
end

function writeTrackingCsv(path, regions)
lines = "time_s,subject,bodypart,x,y,likelihood";
for r = 1:height(regions)
    times = (ceil(regions(r, 1) * 30):floor(regions(r, 2) * 30))' / 30;
    for t = times'
        for track = ["track0", "track1"]
            [x, y] = truePosition(track, t);
            for part = ["snout", "tail_base"]
                lines(end + 1, 1) = compose("%.9f", t) + "," + track + "," + part + ...
                    "," + compose("%.9f", x) + "," + compose("%.9f", y) + ",0.95"; %#ok<AGROW>
            end
        end
    end
end
writelines(lines, path);
end

function tbl = behaviorTable()
tbl = table(["b1"; "b2"; "b3"], ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    ["10"; "20"; "30"], ["12"; missing; "30"], ["F01"; "M01"; ""], ...
    ["door"; "center"; "sync"], VariableNames=["event_id", "event", ...
    "start_time_s", "end_time_s", "subject", "zone"]);
end

function tbl = neuralTable(neuralTimes)
ids = "n" + string(1:numel(neuralTimes))';
tbl = table(ids, repmat("TTL1_HIGH", numel(ids), 1), ...
    compose("%.9f", neuralTimes * 1000), repmat("5", numel(ids), 1), ...
    repmat("1", numel(ids), 1), ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
end

function tbl = anchorTable(audioTimes, videoTimes, neuralTimes)
keys = "sync0" + string(1:numel(audioTimes))';
markers = repelem(keys, 3);
streams = repmat(["audio"; "video"; "neural"], numel(keys), 1);
timestamps = strings(3 * numel(keys), 1);
eventIds = strings(3 * numel(keys), 1);
for index = 1:numel(keys)
    base = (index - 1) * 3;
    timestamps(base + 1) = compose("%.9f", audioTimes(index));
    timestamps(base + 2) = compose("%.9f", videoTimes(index));
    timestamps(base + 3) = compose("%.9f", neuralTimes(index));
    eventIds(base + 3) = "n" + string(index);
end
tbl = table(markers, streams, timestamps, repmat("primary", 3 * numel(keys), 1), ...
    repmat("true", 3 * numel(keys), 1), repmat("0.002", 3 * numel(keys), 1), eventIds, ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
end

function value = runIdFor(conn, timebaseKey)
rows = fetch(conn, "SELECT t.alignment_run_id FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = double(rows.alignment_run_id(1));
end

function tearDown(conn, workspace, sourcePath)
if isopen(conn)
    close(conn);
end
if isfolder(workspace)
    rmdir(workspace, "s");
end
rmpath(sourcePath);
end

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
