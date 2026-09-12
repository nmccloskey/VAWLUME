function tests = test_alignment_piecewise_fitting
%TEST_ALIGNMENT_PIECEWISE_FITTING Phase 3 piecewise persistence and tiling.
%
% The fixture registers a synthetic session whose audio clock changes drift
% regime at a known instant, so every recovered coefficient is checked against
% ground truth the test constructed. Those known parameters are test ground
% truth, not a claim that real device clocks behave this way.
%
% The load-bearing assertions are the ones about tiling, boundary ownership, and
% refit identity: a segmentation that gaps, or a fitter and an applier that
% disagree about which segment owns a breakpoint instant, would be silent.
tests = functiontests({ ...
    @testDeclaredPiecewiseFitPersistsSegmentsAndBreakpoints, ...
    @testStoredSegmentsTileAndOwnTheirBoundaries, ...
    @testTilingIsEnforcedOnWriteNotMerelyDocumented, ...
    @testPerSegmentEvidenceIsStoredWithDeclaredSemantics, ...
    @testRunSummariesAgreeWithStoredResiduals, ...
    @testStoredBreakpointsAreReusedAndADifferentSetConflicts, ...
    @testPiecewiseWithoutBreakpointsFailsAndIsRecorded, ...
    @testTrackingReportsAFittedPiecewiseRunAsUnusableForNow});
end

% ------------------------------------------------------------ persistence ---

function testDeclaredPiecewiseFitPersistsSegmentsAndBreakpoints(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

plan = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot);

% Planning writes nothing.
verifyEqual(testCase, plan.status, "planned");
verifyEqual(testCase, rowCount(fixture.conn, "alignment_segments"), 0);
verifyEqual(testCase, rowCount(fixture.conn, "alignment_run_breakpoints"), 0);

audio = transformFor(plan, "audio_native");
verifyEqual(testCase, audio.method, "piecewise_affine");
verifyEqual(testCase, audio.segment_count, 2);

% A piecewise transform has no single slope.
verifyTrue(testCase, isnan(audio.scale));
verifyTrue(testCase, isnan(audio.offset_s));

segments = segmentsFor(plan, "audio_native");
verifyEqual(testCase, segments.scale, fixture.scale, RelTol=1e-9);
verifyEqual(testCase, segments.offset_s, fixture.offset, AbsTol=1e-9);

applied = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);
verifyEqual(testCase, applied.status, "committed");
verifyEqual(testCase, applied.applied_counts.alignment_segments, 2);
verifyEqual(testCase, applied.applied_counts.alignment_run_breakpoints, 1);

verifyEqual(testCase, runStatus(fixture.conn, "audio_native"), "estimated");
stored = storedSegments(fixture.conn, "audio_native");
verifyEqual(testCase, height(stored), 2);
verifyEqual(testCase, stored.scale, fixture.scale, RelTol=1e-9);

% The declared segmentation is part of the model's identity, so it is stored
% rather than left as a call the database has no record of.
knots = storedBreakpoints(fixture.conn, "audio_native");
verifyEqual(testCase, knots, fixture.knot);

clear cleanup
end

function testStoredSegmentsTileAndOwnTheirBoundaries(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);

stored = storedSegments(fixture.conn, "audio_native");

% The first segment is open below and the last open above, so every finite
% source time falls in exactly one of them.
verifyTrue(testCase, isnan(stored.source_start(1)));
verifyEqual(testCase, stored.source_end(1), fixture.knot);
verifyEqual(testCase, stored.source_start(2), fixture.knot);
verifyTrue(testCase, isnan(stored.source_end(2)));

% No gap and no overlap: one segment ends exactly where the next begins.
verifyEqual(testCase, stored.source_start(2), stored.source_end(1));

% An anchor exactly on the breakpoint belongs to the segment beginning there.
% The fixture places one there on purpose.
onBoundary = fixture.audio_times == fixture.knot;
verifyEqual(testCase, nnz(onBoundary), 1);
verifyEqual(testCase, rowCount(fixture.conn, ...
    "alignment_anchor_residuals r JOIN time_alignment_runs t " + ...
    "ON t.alignment_run_id = r.alignment_run_id JOIN timebases tb " + ...
    "ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = 'audio_native'"), numel(fixture.audio_times));

residual = storedResidualFor(fixture.conn, "sync03");
predictedBySecond = stored.scale(2) * fixture.knot + stored.offset_s(2);
verifyEqual(testCase, residual.predicted_reference_time, predictedBySecond, ...
    AbsTol=1e-9);

clear cleanup
end

function testTilingIsEnforcedOnWriteNotMerelyDocumented(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanup = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

% `11_temporal_alignment_schema.md` lists segment tiling as an obligation the
% database cannot express and application code therefore owes. This is the guard
% that discharges it, and nothing reaches alignment_segments without passing it.
% These probes fail if the enforcement is ever removed.
guard = @(segments) vawlume.alignment.internal.assertSegmentsTile( ...
    segments, "audio_native");

% A gap leaves source times with no transform at all.
verifyError(testCase, @() guard(segmentTable([1; 2], [NaN; 700], [600; NaN])), ...
    "vawlume:alignment:SegmentTilingInvalid");

% An overlap gives one source time two transforms.
verifyError(testCase, @() guard(segmentTable([1; 2], [NaN; 500], [600; NaN])), ...
    "vawlume:alignment:SegmentTilingInvalid");

% A bounded first or last segment leaves times outside the anchored span with
% nowhere to fall.
verifyError(testCase, @() guard(segmentTable([1; 2], [0; 600], [600; NaN])), ...
    "vawlume:alignment:SegmentTilingInvalid");
verifyError(testCase, @() guard(segmentTable([1; 2], [NaN; 600], [600; 1500])), ...
    "vawlume:alignment:SegmentTilingInvalid");

verifyError(testCase, @() guard(segmentTable([1; 3], [NaN; 600], [600; NaN])), ...
    "vawlume:alignment:SegmentTilingInvalid");
verifyError(testCase, @() guard(segmentTable(zeros(0, 1), zeros(0, 1), zeros(0, 1))), ...
    "vawlume:alignment:SegmentTilingInvalid");

% A well-formed segmentation passes, so the guard is not simply refusing
% everything handed to it.
guard(segmentTable([1; 2], [NaN; 600], [600; NaN]));
guard(segmentTable(1, NaN, NaN));

% The evaluator and the guard agree about which segment owns a boundary: a time
% exactly at a breakpoint belongs to the segment beginning there.
[~, index] = vawlume.alignment.internal.evaluateSegments( ...
    segmentTable([1; 2], [NaN; 600], [600; NaN]), [599.9; 600; 600.1]);
verifyEqual(testCase, index, [1; 2; 2]);
end

function testPerSegmentEvidenceIsStoredWithDeclaredSemantics(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);

stored = storedSegments(fixture.conn, "audio_native");

% Every anchor in the fixture records uncertainty_s = 0.002 on both clocks. The
% bound is the largest of them expressed on the reference clock, so the source
% reading is carried over by the segment scale and the reference reading is
% already there. For a segment that runs slow the reference reading is larger.
for index = 1:height(stored)
    verifyEqual(testCase, stored.uncertainty_s(index), ...
        max(stored.scale(index) * 0.002, 0.002), AbsTol=1e-12);
    verifyEqual(testCase, stored.uncertainty_semantics(index), ...
        "max_contributing_anchor_uncertainty_s");
    verifyGreaterThanOrEqual(testCase, stored.rmse_s(index), 0);
end

% A number without stated semantics is not stored, and the schema enforces it.
verifyEqual(testCase, nnz(ismissing(stored.uncertainty_semantics)), 0);

clear cleanup
end

function testRunSummariesAgreeWithStoredResiduals(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);

% `11_temporal_alignment_schema.md` leaves this agreement to application code.
% The schema stores both numbers and cannot compute one from the other.
residuals = fetch(fixture.conn, "SELECT residual_s, included_in_fit " + ...
    "FROM alignment_anchor_residuals r JOIN time_alignment_runs t " + ...
    "ON t.alignment_run_id = r.alignment_run_id " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = 'audio_native'");
included = double(residuals.residual_s(double(residuals.included_in_fit) == 1));

summary = fetch(fixture.conn, "SELECT n_anchors_used, fit_rmse_s, max_error_s " + ...
    "FROM time_alignment_runs t JOIN timebases tb " + ...
    "ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = 'audio_native'");

verifyEqual(testCase, double(summary.n_anchors_used(1)), numel(included));
verifyEqual(testCase, double(summary.fit_rmse_s(1)), ...
    sqrt(mean(included .^ 2)), AbsTol=1e-12);
verifyEqual(testCase, double(summary.max_error_s(1)), ...
    max(abs(included)), AbsTol=1e-12);

clear cleanup
end

% -------------------------------------------------------------- identity ---

function testStoredBreakpointsAreReusedAndADifferentSetConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);

% Refitting without restating the breakpoints reuses the stored declaration, so
% the fit stays reconstructable from the database alone.
again = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native");
verifyEqual(testCase, transformFor(again, "audio_native").action, "reuse");
verifyFalse(testCase, again.has_conflicts);

% Restating the same set is also a reuse.
same = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot);
verifyEqual(testCase, transformFor(same, "audio_native").action, "reuse");

% A different segmentation is a different alignment, not a correction to this
% one, even where the anchors are identical.
different = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=800);
verifyTrue(testCase, different.has_conflicts);
verifyTrue(testCase, any(contains(different.conflicts, "different segmentation")));
blocked = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=800, Apply=true);
verifyEqual(testCase, blocked.status, "conflict");
verifyFalse(testCase, blocked.committed);

% Nothing was rewritten.
verifyEqual(testCase, storedBreakpoints(fixture.conn, "audio_native"), fixture.knot);
verifyEqual(testCase, height(storedSegments(fixture.conn, "audio_native")), 2);

clear cleanup
end

function testPiecewiseWithoutBreakpointsFailsAndIsRecorded(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

result = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native");

% VAWLUME does not search for a breakpoint, so a piecewise transform with none
% declared cannot be fitted. It says so rather than degrading to affine.
verifyFalse(testCase, result.has_conflicts);
verifyTrue(testCase, result.has_failures);
audio = transformFor(result, "audio_native");
verifyEqual(testCase, audio.action, "not_fit_ready");
verifyEqual(testCase, audio.failure_code, "BreakpointsRequired");

applied = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Apply=true);
verifyEqual(testCase, applied.applied_counts.alignment_runs_failed, 1);
verifyEqual(testCase, runStatus(fixture.conn, "audio_native"), "failed");
verifyEqual(testCase, rowCount(fixture.conn, "alignment_segments"), 0);

% Breakpoints describe one clock, so declaring them without naming the transform
% they belong to is refused rather than broadcast across the set.
verifyError(testCase, @() vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    Breakpoints=600), "vawlume:alignment:BreakpointsInvalid");

clear cleanup
end

function testTrackingReportsAFittedPiecewiseRunAsUnusableForNow(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);

% A fitted piecewise transform is not yet applicable: applyTransform still
% refuses more than one stored segment, which is the applier's pass to change.
% The refusal must stay a refusal — never a plausible-looking number.
runId = runIdFor(fixture.conn, "audio_native");
verifyError(testCase, @() vawlume.alignment.applyTransform( ...
    fixture.conn, runId, 100), "vawlume:alignment:PiecewiseNotImplemented");

clear cleanup
end

% ------------------------------------------------------------------ setup ---

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE A synthetic session whose audio clock changes drift regime once.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_piecewise_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "piecewise.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedRecording(conn);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), knot=900, ...
    video_scale=0.9992, video_offset=53.40);

% Two regimes, meeting at 900 s. The second offset is derived from continuity
% rather than chosen, so the fixture cannot describe a transform with a step.
fixture.scale = [1.0015; 0.9990];
fixture.offset = [117.25; ...
    (1.0015 - 0.9990) * fixture.knot + 117.25];

fixture.audio_times = [10; 400; 900; 1200; 1500];
fixture.anchor_keys = ["sync01"; "sync02"; "sync03"; "sync04"; "sync05"];
segment = 1 + double(fixture.audio_times >= fixture.knot);
fixture.neural_times = fixture.scale(segment) .* fixture.audio_times + ...
    fixture.offset(segment);
fixture.video_times = (fixture.neural_times - fixture.video_offset) / ...
    fixture.video_scale;

writeTableFile(workspace, "video_events.csv", behaviorTable());
writeTableFile(workspace, "neural_events.csv", neuralTable(fixture));
writeTableFile(workspace, "sync_anchors.csv", anchorTable(fixture));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
fixture.manifest_path = string(manifestPath);

vawlume.ingest.alignment(conn, fixture.manifest_path, RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);

% The audio clock is the one that changed regime, so its transform declares the
% piecewise method. Intake registers every transform as affine by default.
execute(conn, "UPDATE time_alignment_runs SET method='piecewise_affine' " + ...
    "WHERE source_timebase_id = (SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='audio_native')");
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
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, " + ...
    "relative_path) VALUES (1, 'recording_audio', " + ...
    "'synthetic/session01.wav', 'session01.wav')");
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

% ---------------------------------------------------------------- helpers ---

function value = alignmentRef()
value = struct(run_key="synthetic_session_01_alignment");
end

function value = transformFor(result, sourceKey)
selected = result.transforms.source_timebase_key == sourceKey;
assert(nnz(selected) == 1, "Expected one transform for " + sourceKey);
value = table2struct(result.transforms(selected, :));
end

function value = segmentsFor(result, sourceKey)
value = result.segments(result.segments.source_timebase_key == sourceKey, :);
end

function value = segmentTable(index, starts, ends)
%SEGMENTTABLE A segmentation shaped like a fitted one, for guard probes.
count = numel(index);
value = table(index(:), starts(:), ends(:), ones(count, 1), zeros(count, 1), ...
    nan(count, 1), nan(count, 1), nan(count, 1), ...
    VariableNames=["segment_index", "source_start", "source_end", "scale", ...
    "offset_s", "anchor_count", "rmse_s", "uncertainty_s"]);
end

function value = storedSegments(conn, timebaseKey)
%STOREDSEGMENTS Read back the persisted segmentation.
%
% Every nullable column is wrapped. The Database Toolbox raises
% 'Unexpected NULL' while building a result set that contains SQL NULL, and an
% open segment bound is exactly that. The sentinels are converted back to NaN
% here so the assertions read in terms of openness rather than magic numbers.
value = fetch(conn, "SELECT s.segment_index, " + ...
    "IFNULL(s.source_start, 1e308) AS source_start, " + ...
    "IFNULL(s.source_end, 1e308) AS source_end, s.scale, s.offset_s, " + ...
    "IFNULL(s.rmse_s, -1) AS rmse_s, " + ...
    "IFNULL(s.uncertainty_s, -1) AS uncertainty_s, " + ...
    "IFNULL(s.uncertainty_semantics,'') AS uncertainty_semantics " + ...
    "FROM alignment_segments s JOIN time_alignment_runs t " + ...
    "ON t.alignment_run_id = s.alignment_run_id " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "' ORDER BY s.segment_index");
value.uncertainty_semantics = string(value.uncertainty_semantics);
value.source_start = openToNaN(double(value.source_start));
value.source_end = openToNaN(double(value.source_end));
value.rmse_s = absentToNaN(double(value.rmse_s));
value.uncertainty_s = absentToNaN(double(value.uncertainty_s));
end

function value = openToNaN(value)
value(value >= 1e307) = NaN;
end

function value = absentToNaN(value)
value(value < 0) = NaN;
end

function value = storedBreakpoints(conn, timebaseKey)
rows = fetch(conn, "SELECT b.source_time FROM alignment_run_breakpoints b " + ...
    "JOIN time_alignment_runs t ON t.alignment_run_id = b.alignment_run_id " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "' ORDER BY b.breakpoint_index");
value = double(rows.source_time);
end

function value = storedResidualFor(conn, anchorKey)
rows = fetch(conn, "SELECT r.observed_source_time, r.predicted_reference_time, " + ...
    "r.residual_s FROM alignment_anchor_residuals r " + ...
    "JOIN alignment_anchors a ON a.alignment_anchor_id = r.alignment_anchor_id " + ...
    "WHERE a.anchor_key = '" + anchorKey + "'");
value = struct( ...
    observed_source_time=double(rows.observed_source_time(1)), ...
    predicted_reference_time=double(rows.predicted_reference_time(1)), ...
    residual_s=double(rows.residual_s(1)));
end

function value = runStatus(conn, timebaseKey)
rows = fetch(conn, "SELECT t.status FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = string(rows.status(1));
end

function value = runIdFor(conn, timebaseKey)
rows = fetch(conn, "SELECT t.alignment_run_id FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = double(rows.alignment_run_id(1));
end

function value = rowCount(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function writeTableFile(workspace, name, tbl)
writetable(tbl, fullfile(workspace, name));
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
