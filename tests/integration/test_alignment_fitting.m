function tests = test_alignment_fitting
%TEST_ALIGNMENT_FITTING Phase 7 transform fitting, residual evidence, and QC.
%
% The fixture registers a synthetic session whose anchor times are generated from
% two known transforms, so every recovered coefficient is checked against ground
% truth the test constructed rather than against whatever the fitter returned.
%
% Those known parameters are test ground truth. They are not a claim that real
% device clocks drift this way.
tests = functiontests({ ...
    @testKnownTransformsAreRecoveredAndPersisted, ...
    @testResidualsNameTheObservationsTheyCameFrom, ...
    @testHeldOutAnchorGetsAResidualWithoutMovingCoefficients, ...
    @testReplicateObservationsArePreservedNotAveraged, ...
    @testAnchorMissingAReferenceObservationIsNeverNearestMatched, ...
    @testPlanningWritesNothingAndRefitIsIdempotent, ...
    @testCompletedTransformIsNotRewrittenInPlace, ...
    @testInducedFailureRollsBackEverySegmentAndResidual, ...
    @testStoredTransformIsAppliedWithoutRefitting, ...
    @testApplyRefusesUnfittedRejectedAndPiecewiseRuns, ...
    @testFittingLeavesEveryNativeTimestampUnchanged, ...
    @testReportReadsBackWhatWasPersisted});
end

% ---------------------------------------------------- recovery and storage ---

function testKnownTransformsAreRecoveredAndPersisted(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);

verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);
verifyFalse(testCase, result.has_conflicts);
verifyEqual(testCase, height(result.transforms), 2);

audio = transformFor(result, "audio_native");
video = transformFor(result, "video_native");

% Both clocks recover the transform the fixture generated them from.
verifyEqual(testCase, audio.scale, fixture.audio_scale, RelTol=1e-9);
verifyEqual(testCase, audio.offset_s, fixture.audio_offset, AbsTol=1e-6);
verifyEqual(testCase, video.scale, fixture.video_scale, RelTol=1e-9);
verifyEqual(testCase, video.offset_s, fixture.video_offset, AbsTol=1e-6);

% Exact anchors leave essentially no residual.
verifyLessThan(testCase, audio.rmse_s, 1e-6);
verifyLessThan(testCase, video.max_abs_residual_s, 1e-6);
verifyEqual(testCase, audio.n_anchors_used, 4);

% One segment per run, carrying the coefficients, and the summaries agree.
verifyEqual(testCase, count(fixture.conn, "alignment_segments", "1=1"), 2);
verifyEqual(testCase, count(fixture.conn, "alignment_segments", ...
    "segment_index = 1"), 2);
verifyEqual(testCase, count(fixture.conn, "time_alignment_runs", ...
    "status = 'estimated' AND n_anchors_used = 4"), 2);

% A solved fit is estimated, never validated.
verifyEqual(testCase, count(fixture.conn, "time_alignment_runs", ...
    "status = 'validated'"), 0);
verifyEqual(testCase, count(fixture.conn, "alignment_sets", ...
    "status = 'fitted'"), 1);
verifyTrue(testCase, contains(result.validation_note, "never validated"));
verifyTrue(testCase, contains(result.uncertainty_note, "not used as a fit weight"));

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
clear cleanup
end

function testResidualsNameTheObservationsTheyCameFrom(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);

% Every residual points at two real observations, on the two clocks its own
% transform relates, so a reader can recompute it by hand.
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals", "1=1"), 8);
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals res " + ...
    "JOIN alignment_anchor_observations src " + ...
    "ON src.anchor_observation_id = res.source_observation_id " + ...
    "JOIN alignment_anchor_observations ref " + ...
    "ON ref.anchor_observation_id = res.reference_observation_id " + ...
    "JOIN time_alignment_runs r ON r.alignment_run_id = res.alignment_run_id", ...
    "src.timebase_id = r.source_timebase_id " + ...
    "AND ref.timebase_id = r.target_timebase_id"), 8);

% The stored prediction is the stored coefficients applied to the stored source
% time, and the residual is the stored difference.
rows = fetch(fixture.conn, "SELECT res.observed_source_time, " + ...
    "res.observed_reference_time, res.predicted_reference_time, " + ...
    "res.residual_s, seg.scale, seg.offset_s " + ...
    "FROM alignment_anchor_residuals res " + ...
    "JOIN alignment_segments seg ON seg.alignment_run_id = res.alignment_run_id");
predicted = double(rows.scale) .* double(rows.observed_source_time) + ...
    double(rows.offset_s);
verifyEqual(testCase, double(rows.predicted_reference_time), predicted, AbsTol=1e-9);
verifyEqual(testCase, double(rows.residual_s), ...
    double(rows.observed_reference_time) - predicted, AbsTol=1e-9);

clear cleanup
end

% ------------------------------------------------------- inclusion handling ---

function testHeldOutAnchorGetsAResidualWithoutMovingCoefficients(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
baseline = vawlume.alignment.fit(fixture.conn, alignmentRef());

% Withhold one audio anchor observation from the fit. It still pairs
% unambiguously, so it should be evaluated but must not influence the answer.
execute(fixture.conn, "UPDATE alignment_anchor_observations " + ...
    "SET included_in_fit = 0, observation_role = 'excluded' " + ...
    "WHERE anchor_observation_id = " + string(audioObservationId(fixture, "sync04")));

result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
audio = transformFor(result, "audio_native");
baselineAudio = transformFor(baseline, "audio_native");

% Three exact anchors still determine the same transform.
verifyEqual(testCase, audio.n_anchors_used, 3);
verifyEqual(testCase, audio.scale, baselineAudio.scale, RelTol=1e-9);
verifyEqual(testCase, audio.offset_s, baselineAudio.offset_s, AbsTol=1e-6);

% The held-out anchor is still evaluated, marked, and given a reason.
heldOut = result.anchors(result.anchors.anchor_key == "sync04" & ...
    result.anchors.source_timebase_key == "audio_native", :);
verifyEqual(testCase, height(heldOut), 1);
verifyEqual(testCase, heldOut.included_in_fit, 0);
verifyLessThan(testCase, abs(heldOut.residual_s), 1e-6);
verifyGreaterThan(testCase, strlength(heldOut.exclusion_reason), 0);

verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals", ...
    "included_in_fit = 0 AND exclusion_reason IS NOT NULL"), 1);

clear cleanup
end

function testReplicateObservationsArePreservedNotAveraged(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
baseline = vawlume.alignment.fit(fixture.conn, alignmentRef());

% A redundant audio reading of sync02, 40 ms late, kept as evidence but not in
% the fit. Averaging it into the primary would shift the transform.
execute(fixture.conn, "INSERT INTO alignment_anchor_observations(" + ...
    "alignment_anchor_id, timebase_id, observed_time_native, " + ...
    "observation_role, included_in_fit, uncertainty_s, notes) VALUES (" + ...
    string(anchorId(fixture, "sync02")) + ", " + string(fixture.audio_timebase_id) + ...
    ", " + string(audioTime(fixture, "sync02") + 0.04) + ...
    ", 'replicate', 0, 0.004, 'Redundant TTL channel.')");

result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
audio = transformFor(result, "audio_native");
baselineAudio = transformFor(baseline, "audio_native");

verifyEqual(testCase, audio.scale, baselineAudio.scale, RelTol=1e-9);
verifyEqual(testCase, audio.offset_s, baselineAudio.offset_s, AbsTol=1e-6);
verifyEqual(testCase, audio.n_anchors_used, 4);

% The replicate row survives untouched, and the fit selected the included one.
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_observations", ...
    "observation_role = 'replicate' AND included_in_fit = 0"), 1);
sync02 = result.anchors(result.anchors.anchor_key == "sync02" & ...
    result.anchors.source_timebase_key == "audio_native", :);
verifyEqual(testCase, height(sync02), 1);
verifyEqual(testCase, sync02.included_in_fit, 1);
verifyEqual(testCase, sync02.observed_source_time, ...
    audioTime(fixture, "sync02"), AbsTol=1e-9);
verifyEqual(testCase, sync02.source_observation_count, 2);

% Uncertainty is carried through but never used as a weight.
verifyEqual(testCase, sync02.source_uncertainty_s, 0.002, AbsTol=1e-12);

clear cleanup
end

function testAnchorMissingAReferenceObservationIsNeverNearestMatched(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Remove sync03's neural reading. The anchor cannot pair, and the fitter must
% drop it rather than borrowing the nearest neural timestamp.
execute(fixture.conn, "DELETE FROM alignment_anchor_observations " + ...
    "WHERE anchor_observation_id = " + ...
    string(observationId(fixture, "sync03", fixture.neural_timebase_id)));

result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
audio = transformFor(result, "audio_native");

verifyEqual(testCase, audio.n_anchors_used, 3);
verifyFalse(testCase, any(result.anchors.anchor_key == "sync03"));
verifyEqual(testCase, audio.scale, fixture.audio_scale, RelTol=1e-9);
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals", "1=1"), 6);

clear cleanup
end

% ------------------------------------------------- identity and transaction ---

function testPlanningWritesNothingAndRefitIsIdempotent(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

planned = vawlume.alignment.fit(fixture.conn, alignmentRef());
verifyEqual(testCase, planned.status, "planned");
verifyFalse(testCase, planned.committed);
verifyEqual(testCase, count(fixture.conn, "alignment_segments", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "time_alignment_runs", ...
    "status = 'registered'"), 2);

vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
before = fitRowTotal(fixture.conn);

again = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
verifyEqual(testCase, again.status, "reused");
verifyTrue(testCase, again.committed);
verifyEqual(testCase, fitRowTotal(fixture.conn), before);

clear cleanup
end

function testCompletedTransformIsNotRewrittenInPlace(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
before = fitRowTotal(fixture.conn);

% Changing which anchors are included changes the answer. That is a different
% alignment, not a correction to this one.
execute(fixture.conn, "UPDATE alignment_anchor_observations " + ...
    "SET observed_time_native = observed_time_native + 5 " + ...
    "WHERE anchor_observation_id = " + string(audioObservationId(fixture, "sync01")));

result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
verifyEqual(testCase, result.status, "conflict");
verifyTrue(testCase, result.has_conflicts);
verifyFalse(testCase, result.committed);
verifyTrue(testCase, any(contains(result.conflicts, "new alignment identity")));
verifyEqual(testCase, fitRowTotal(fixture.conn), before);

clear cleanup
end

function testInducedFailureRollsBackEverySegmentAndResidual(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "CREATE TRIGGER trg_alignment_fit_failure " + ...
    "BEFORE INSERT ON alignment_anchor_residuals FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT,'induced fit failure'); END");
dropper = onCleanup(@() dropTrigger(fixture.conn));

verifyError(testCase, ...
    @() vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true), ...
    ?MException);

% The segment written before the failing residual must not survive, and no run
% may be left claiming an estimate.
verifyEqual(testCase, count(fixture.conn, "alignment_segments", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "time_alignment_runs", ...
    "status = 'registered'"), 2);
verifyEqual(testCase, count(fixture.conn, "alignment_sets", "status = 'draft'"), 1);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

clear dropper
recovered = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
verifyEqual(testCase, recovered.status, "committed");

clear cleanup
end

% ---------------------------------------------------- transform application ---

function testStoredTransformIsAppliedWithoutRefitting(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
runId = transformFor(result, "audio_native").alignment_run_id;

[aligned, transform] = vawlume.alignment.applyTransform(fixture.conn, runId, 0);
verifyEqual(testCase, aligned, fixture.audio_offset, AbsTol=1e-6);
verifyEqual(testCase, transform.source_timebase_key, "audio_native");
verifyEqual(testCase, transform.reference_timebase_key, "neural_native");
verifyEqual(testCase, transform.status, "estimated");
verifyTrue(testCase, contains(transform.source, "not refitted"));

% A vector keeps its shape, and the values match the known transform.
native = [0; 100; 500; 1200];
expected = fixture.audio_scale * native + fixture.audio_offset;
verifyEqual(testCase, vawlume.alignment.applyTransform(fixture.conn, runId, native), ...
    expected, AbsTol=1e-6);
row = native';
verifyEqual(testCase, size(vawlume.alignment.applyTransform(fixture.conn, runId, row)), ...
    size(row));

% Applying must read what is stored. Rewriting the stored coefficients changes
% the answer, which proves the value is not being recomputed from anchors.
execute(fixture.conn, "UPDATE alignment_segments SET offset_s = 0, scale = 2 " + ...
    "WHERE alignment_run_id = " + string(runId));
verifyEqual(testCase, vawlume.alignment.applyTransform(fixture.conn, runId, 10), 20, ...
    AbsTol=1e-12);

clear cleanup
end

function testApplyRefusesUnfittedRejectedAndPiecewiseRuns(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = registeredRunId(fixture, fixture.audio_timebase_id);

verifyError(testCase, ...
    @() vawlume.alignment.applyTransform(fixture.conn, runId, 10), ...
    "vawlume:alignment:TransformNotFitted");
verifyError(testCase, ...
    @() vawlume.alignment.applyTransform(fixture.conn, 99999, 10), ...
    "vawlume:alignment:TransformRunNotFound");

vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
execute(fixture.conn, "UPDATE time_alignment_runs SET status = 'rejected' " + ...
    "WHERE alignment_run_id = " + string(runId));
verifyError(testCase, ...
    @() vawlume.alignment.applyTransform(fixture.conn, runId, 10), ...
    "vawlume:alignment:TransformNotUsable");

% A second stored segment means piecewise, which is representable but not
% implemented. Applying one segment everywhere would be wrong outside its range.
execute(fixture.conn, "UPDATE time_alignment_runs SET status = 'estimated' " + ...
    "WHERE alignment_run_id = " + string(runId));
execute(fixture.conn, "INSERT INTO alignment_segments(alignment_run_id, " + ...
    "segment_index, source_start, source_end, scale, offset_s) VALUES (" + ...
    string(runId) + ", 2, 1000, 2000, 1.0, 0.0)");
verifyError(testCase, ...
    @() vawlume.alignment.applyTransform(fixture.conn, runId, 10), ...
    "vawlume:alignment:PiecewiseNotImplemented");

clear cleanup
end

% ------------------------------------------------------------- immutability ---

function testFittingLeavesEveryNativeTimestampUnchanged(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = nativeTimeFingerprint(fixture.conn);

vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
runId = registeredRunId(fixture, fixture.audio_timebase_id);
vawlume.alignment.applyTransform(fixture.conn, runId, [0; 100; 500]);
vawlume.alignment.report(fixture.conn, alignmentRef());

% Fitting is derived analysis. External event, anchor observation, and detection
% native times must all read exactly as before.
verifyEqual(testCase, nativeTimeFingerprint(fixture.conn), before);
verifyEqual(testCase, count(fixture.conn, "aligned_external_events", "1=1"), 0);

clear cleanup
end

function testReportReadsBackWhatWasPersisted(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
empty = vawlume.alignment.report(fixture.conn, alignmentRef());
verifyEqual(testCase, empty.set_status, "draft");
verifyEqual(testCase, height(empty.transforms), 2);
verifyEqual(testCase, unique(empty.transforms.status), "registered");
verifyTrue(testCase, all(isnan(empty.transforms.scale)));
verifyEqual(testCase, height(empty.residuals), 0);

fitted = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
value = vawlume.alignment.report(fixture.conn, alignmentRef());

verifyEqual(testCase, value.set_status, "fitted");
verifyEqual(testCase, value.reference_timebase.timebase_key, "neural_native");
verifyEqual(testCase, unique(value.transforms.status), "estimated");
verifyEqual(testCase, unique(value.transforms.segment_count), 1);
verifyEqual(testCase, height(value.residuals), 8);

% The report agrees with what the fit returned, because both describe the same
% persisted rows.
reported = value.transforms(value.transforms.source_timebase_key == "audio_native", :);
verifyEqual(testCase, reported.scale, transformFor(fitted, "audio_native").scale, ...
    RelTol=1e-12);
verifyEqual(testCase, reported.offset_s, ...
    transformFor(fitted, "audio_native").offset_s, AbsTol=1e-9);

clear cleanup
end

% ----------------------------------------------------------------- fixture ---

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE Register a synthetic session whose anchors follow known transforms.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_alignment_fit_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "alignment_fit.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedRecording(conn);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
    audio_scale=1.0015, audio_offset=117.25, ...
    video_scale=0.9992, video_offset=53.40);

% Choose audio times, carry them to the neural clock through the known audio
% transform, then back to the video clock through the known video transform, so
% one shared neural time is consistent with both.
fixture.audio_times = [10; 400; 900; 1500];
fixture.neural_times = fixture.audio_scale * fixture.audio_times + fixture.audio_offset;
fixture.video_times = (fixture.neural_times - fixture.video_offset) / fixture.video_scale;
fixture.anchor_keys = ["sync01"; "sync02"; "sync03"; "sync04"];

writeTableFile(workspace, "video_events.csv", behaviorTable());
writeTableFile(workspace, "neural_events.csv", neuralTable(fixture));
writeTableFile(workspace, "sync_anchors.csv", anchorTable(fixture));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
fixture.manifest_path = string(manifestPath);

vawlume.ingest.alignment(conn, fixture.manifest_path, RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);

fixture.audio_timebase_id = timebaseId(conn, "audio_native");
fixture.video_timebase_id = timebaseId(conn, "video_native");
fixture.neural_timebase_id = timebaseId(conn, "neural_native");
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

function seedRecording(conn)
execute(conn, "INSERT INTO projects(project_key, project_name) " + ...
    "VALUES ('synthetic_alignment_session', 'Synthetic alignment session')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, relative_path) " + ...
    "VALUES (1, 'recording_audio', 'synthetic/session01.wav', 'session01.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, " + ...
    "native_recording_id, sample_rate_hz) " + ...
    "VALUES (1, 1, 'REC_SESSION_01', 250000)");
end

function tbl = behaviorTable()
tbl = table(["b1"; "b2"; "b3"], ...
    ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    ["10"; "20"; "30"], ["12"; missing; "30"], ["F01"; "M01"; ""], ...
    ["door"; "center"; "sync"], ...
    VariableNames=["event_id", "event", "start_time_s", "end_time_s", ...
    "subject", "zone"]);
end

function tbl = neuralTable(fixture)
% The TTL pulses are the neural-clock readings of the same synchronization
% markers, expressed in milliseconds as the neural profile declares.
ids = "n" + string(1:numel(fixture.neural_times))';
tbl = table(ids, repmat("TTL1_HIGH", numel(ids), 1), ...
    compose("%.9f", fixture.neural_times * 1000), ...
    repmat("5", numel(ids), 1), repmat("1", numel(ids), 1), ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
end

function tbl = anchorTable(fixture)
count = numel(fixture.anchor_keys);
markers = repelem(fixture.anchor_keys, 3);
streams = repmat(["audio"; "video"; "neural"], count, 1);
timestamps = strings(3 * count, 1);
eventIds = strings(3 * count, 1);
for index = 1:count
    base = (index - 1) * 3;
    timestamps(base + 1) = compose("%.9f", fixture.audio_times(index));
    timestamps(base + 2) = compose("%.9f", fixture.video_times(index));
    timestamps(base + 3) = compose("%.9f", fixture.neural_times(index));
    eventIds(base + 3) = "n" + string(index);
end
tbl = table(markers, streams, timestamps, repmat("primary", 3 * count, 1), ...
    repmat("true", 3 * count, 1), repmat("0.002", 3 * count, 1), eventIds, ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
end

% ----------------------------------------------------------------- helpers ---

function value = alignmentRef()
value = struct(run_key="synthetic_session_01_alignment");
end

function value = transformFor(result, sourceKey)
selected = result.transforms.source_timebase_key == sourceKey;
assert(nnz(selected) == 1, "Expected one transform for " + sourceKey);
value = table2struct(result.transforms(selected, :));
end

function value = timebaseId(conn, timebaseKey)
rows = fetch(conn, "SELECT timebase_id FROM timebases WHERE timebase_name = '" + ...
    timebaseKey + "'");
value = double(rows.timebase_id(1));
end

function value = anchorId(fixture, anchorKey)
rows = fetch(fixture.conn, "SELECT alignment_anchor_id FROM alignment_anchors " + ...
    "WHERE anchor_key = '" + anchorKey + "'");
value = double(rows.alignment_anchor_id(1));
end

function value = observationId(fixture, anchorKey, timebaseId)
rows = fetch(fixture.conn, "SELECT anchor_observation_id " + ...
    "FROM alignment_anchor_observations WHERE alignment_anchor_id = " + ...
    string(anchorId(fixture, anchorKey)) + " AND timebase_id = " + string(timebaseId));
value = double(rows.anchor_observation_id(1));
end

function value = audioObservationId(fixture, anchorKey)
value = observationId(fixture, anchorKey, fixture.audio_timebase_id);
end

function value = audioTime(fixture, anchorKey)
index = find(fixture.anchor_keys == anchorKey, 1);
value = fixture.audio_times(index);
end

function value = registeredRunId(fixture, sourceTimebaseId)
rows = fetch(fixture.conn, "SELECT alignment_run_id FROM time_alignment_runs " + ...
    "WHERE source_timebase_id = " + string(sourceTimebaseId));
value = double(rows.alignment_run_id(1));
end

function value = nativeTimeFingerprint(conn)
%NATIVETIMEFINGERPRINT Every native timestamp fitting must not touch.
value = struct( ...
    events=fetch(conn, "SELECT external_event_id, start_time_native, " + ...
        "IFNULL(end_time_native, -1) AS end_time_native FROM external_events " + ...
        "ORDER BY external_event_id"), ...
    observations=fetch(conn, "SELECT anchor_observation_id, " + ...
        "observed_time_native, included_in_fit FROM alignment_anchor_observations " + ...
        "ORDER BY anchor_observation_id"), ...
    coverage=fetch(conn, "SELECT external_stream_coverage_id, " + ...
        "start_time_native, end_time_native FROM external_stream_coverage " + ...
        "ORDER BY external_stream_coverage_id"), ...
    detections=fetch(conn, "SELECT COUNT(*) AS n FROM detections"));
end

function value = fitRowTotal(conn)
value = count(conn, "alignment_segments", "1=1") + ...
    count(conn, "alignment_anchor_residuals", "1=1");
end

function value = count(conn, fromClause, whereClause)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + fromClause + ...
    " WHERE " + whereClause);
value = double(rows.n(1));
end

function writeTableFile(workspace, name, tbl)
path = fullfile(workspace, name);
if isfile(path)
    delete(path);
end
writetable(tbl, path, QuoteStrings="minimal");
end

function dropTrigger(conn)
try
    execute(conn, "DROP TRIGGER IF EXISTS trg_alignment_fit_failure");
catch
end
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
