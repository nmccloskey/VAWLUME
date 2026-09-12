function tests = test_alignment_transform_application
%TEST_ALIGNMENT_TRANSFORM_APPLICATION Phase 3 segment dispatch and intervals.
%
% The fixture registers a synthetic session whose audio clock changes drift
% regime at a known instant, so every applied value is checked against ground
% truth the test constructed rather than against whatever the applier returned.
%
% The load-bearing assertions are the ones about boundary agreement between the
% fitter and the applier, about an extrapolated value staying distinguishable
% from a supported one, and about duration not being preserved across a
% breakpoint. Each of those would otherwise be silently wrong.
tests = functiontests({ ...
    @testSegmentDispatchAgreesWithTheFitterAtABreakpoint, ...
    @testExtrapolatedTimesAreFlaggedAndCanBeEscalated, ...
    @testMetadataIsReadableWithoutTransformingAnything, ...
    @testIntervalsReportSegmentsCrossedAndDurationChange, ...
    @testOpenAndReversedIntervals, ...
    @testPropagatedUncertaintyIsDeclaredAndUncalibrated, ...
    @testOffsetAndAffineApplicationIsUnchanged});
end

% ----------------------------------------------------------- point dispatch ---

function testSegmentDispatchAgreesWithTheFitterAtABreakpoint(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = fitPiecewise(fixture);

times = [500; fixture.knot - eps(fixture.knot); fixture.knot; 1200];
[aligned, transform] = vawlume.alignment.applyTransform(fixture.conn, runId, times);

% A segment covers [source_start, source_end), so the instant exactly at the
% breakpoint belongs to the segment beginning there. The fitter said the same:
% the residual it stored for the anchor at that instant was predicted by the
% second segment.
verifyEqual(testCase, transform.segment_index, [1; 1; 2; 2]);

expected = fixture.scale(transform.segment_index) .* times + ...
    fixture.offset(transform.segment_index);
verifyEqual(testCase, aligned, expected, AbsTol=1e-9);

% Shape is preserved, so a caller keeps its own association.
row = vawlume.alignment.applyTransform(fixture.conn, runId, times');
verifyEqual(testCase, size(row), size(times'));

% A segmented transform has no single slope; reporting the first segment's would
% be a plausible-looking number for the whole clock.
verifyTrue(testCase, isnan(transform.scale));
verifyTrue(testCase, isnan(transform.offset_s));
verifyEqual(testCase, height(transform.segments), 2);
verifyEqual(testCase, transform.source, ...
    "stored alignment_segments coefficients; not refitted");

clear cleanup
end

function testExtrapolatedTimesAreFlaggedAndCanBeEscalated(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = fitPiecewise(fixture);

% The anchors ran from 10 s to 1500 s. Outside that the transform still
% evaluates — the contract is a value per input — but it was never anchored
% there, and the result says so.
[aligned, transform] = vawlume.alignment.applyTransform(fixture.conn, runId, ...
    [0; 500; 1500; 2000]);

verifyTrue(testCase, transform.anchored_range_known);
verifyEqual(testCase, transform.anchored_range_start, min(fixture.audio_times));
verifyEqual(testCase, transform.anchored_range_end, max(fixture.audio_times));
verifyEqual(testCase, transform.extrapolated, [true; false; false; true]);

% Flagged, not withheld: every input still has a value.
verifyEqual(testCase, numel(aligned), 4);
verifyTrue(testCase, all(isfinite(aligned)));

% A caller that must not extrapolate can say so.
verifyError(testCase, @() vawlume.alignment.applyTransform( ...
    fixture.conn, runId, [0; 500], ErrorOnExtrapolation=true), ...
    "vawlume:alignment:ExtrapolatedTime");

% Inside the anchored range the same call is fine, so the option is not simply
% refusing everything.
vawlume.alignment.applyTransform(fixture.conn, runId, [500; 1200], ...
    ErrorOnExtrapolation=true);

% Extrapolation and coverage are different statements: this one says the
% transform was not anchored there, not that the stream was unobserved.
clear cleanup
end

function testMetadataIsReadableWithoutTransformingAnything(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = fitPiecewise(fixture);

% Asking a transform to describe itself should not require inventing a time for
% it to place. A dummy instant would be flagged as extrapolated whenever it fell
% outside the anchored range, warning about a moment nobody asked about.
[aligned, transform] = vawlume.alignment.applyTransform(fixture.conn, runId);

verifyEmpty(testCase, aligned);
verifyEmpty(testCase, transform.segment_index);
verifyEmpty(testCase, transform.extrapolated);
verifyEqual(testCase, height(transform.segments), 2);
verifyEqual(testCase, transform.status, "estimated");
verifyEqual(testCase, transform.method, "piecewise_affine");

clear cleanup
end

% --------------------------------------------------------------- intervals ---

function testIntervalsReportSegmentsCrossedAndDurationChange(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = fitPiecewise(fixture);

starts = [100; 800; 1000];
ends = [200; 1000; 1100];
intervals = vawlume.alignment.applyTransformInterval(fixture.conn, runId, ...
    starts, ends);

verifyEqual(testCase, intervals.start_segment_index, [1; 1; 2]);
verifyEqual(testCase, intervals.end_segment_index, [1; 2; 2]);
verifyEqual(testCase, intervals.segments_crossed, [1; 2; 1]);
verifyEqual(testCase, intervals.crosses_breakpoint, [false; true; false]);

% Endpoints transform independently, so a clock that changed rate changes the
% duration. That is what a rate change means, and a caller assuming otherwise
% would be wrong exactly when drift matters most.
verifyEqual(testCase, intervals.native_duration_s, [100; 200; 100]);
verifyEqual(testCase, intervals.aligned_duration_s(1), ...
    100 * fixture.scale(1), AbsTol=1e-9);
verifyEqual(testCase, intervals.aligned_duration_s(3), ...
    100 * fixture.scale(2), AbsTol=1e-9);
verifyEqual(testCase, intervals.duration_change_s, ...
    intervals.aligned_duration_s - intervals.native_duration_s, AbsTol=1e-12);

% The interval that crosses is stretched by one factor at its start and another
% at its end, so its change lies between the two pure-segment changes.
verifyGreaterThan(testCase, intervals.duration_change_s(2), ...
    intervals.duration_change_s(3));
verifyLessThan(testCase, intervals.duration_change_s(2), ...
    intervals.duration_change_s(1));

% The endpoints agree with the point API, which is the same code path.
pointStarts = vawlume.alignment.applyTransform(fixture.conn, runId, starts);
verifyEqual(testCase, intervals.start_aligned, pointStarts);

clear cleanup
end

function testOpenAndReversedIntervals(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = fitPiecewise(fixture);

% An open interval stays open rather than acquiring an invented end.
open = vawlume.alignment.applyTransformInterval(fixture.conn, runId, ...
    [100; 800], [NaN; Inf]);
verifyTrue(testCase, all(~isfinite(open.end_aligned)));
verifyTrue(testCase, all(isnan(open.segments_crossed)));
verifyEqual(testCase, open.crosses_breakpoint, [false; false]);
verifyTrue(testCase, all(isfinite(open.start_aligned)));

% An interval that ends before it starts is not an interval.
verifyError(testCase, @() vawlume.alignment.applyTransformInterval( ...
    fixture.conn, runId, 500, 400), "vawlume:alignment:AlignedIntervalInvalid");

verifyError(testCase, @() vawlume.alignment.applyTransformInterval( ...
    fixture.conn, runId, [100; 200], 300), ...
    "vawlume:alignment:AnchorPairMismatch");

clear cleanup
end

% ------------------------------------------------------------- uncertainty ---

function testPropagatedUncertaintyIsDeclaredAndUncalibrated(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = fitPiecewise(fixture);

[~, transform] = vawlume.alignment.applyTransform(fixture.conn, runId, ...
    [500; 1200]);

% Every anchor records uncertainty_s = 0.002 on both clocks, so each segment's
% bound is the larger of that reading carried over by the segment scale and the
% reference reading, which is already on the reference clock.
expected = max(fixture.scale * 0.002, 0.002);
verifyEqual(testCase, transform.uncertainty_s, expected, AbsTol=1e-12);
verifyEqual(testCase, transform.uncertainty_semantics, ...
    repmat("max_contributing_anchor_uncertainty_s", 2, 1));

% Said in words as well as in a column, because a number a caller might mistake
% for a confidence interval needs to deny being one.
verifyTrue(testCase, contains(transform.uncertainty_note, "uncalibrated"));
verifyTrue(testCase, contains(transform.uncertainty_note, "not a confidence interval"));
verifyTrue(testCase, contains(transform.uncertainty_note, "never combined with rmse_s"));

% Fit residual and reading precision are different quantities and stay apart.
verifyFalse(testCase, isnan(transform.rmse_s));
verifyNotEqual(testCase, transform.rmse_s, transform.uncertainty_s(1));

% Absence propagates as absence. With the anchors' uncertainty removed and the
% fit redone under a new identity, the segments carry no bound at all - not zero,
% which would claim perfect knowledge.
execute(fixture.conn, "UPDATE alignment_anchor_observations SET uncertainty_s = NULL");
execute(fixture.conn, "DELETE FROM alignment_segments");
execute(fixture.conn, "DELETE FROM alignment_run_breakpoints");
execute(fixture.conn, "DELETE FROM alignment_anchor_residuals");
execute(fixture.conn, "UPDATE time_alignment_runs SET status='registered'");
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);

[~, bare] = vawlume.alignment.applyTransform(fixture.conn, runId, [500; 1200]);
verifyTrue(testCase, all(isnan(bare.uncertainty_s)));
verifyEqual(testCase, nnz(bare.uncertainty_s == 0), 0);

clear cleanup
end

function testOffsetAndAffineApplicationIsUnchanged(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="video_native", Apply=true);
runId = runIdFor(fixture.conn, "video_native");

[aligned, transform] = vawlume.alignment.applyTransform(fixture.conn, runId, ...
    [100; 500; 1000]);

% One segment, open at both ends, and the scalar coefficients still populated:
% a caller written before segments existed reads exactly what it always did.
verifyEqual(testCase, height(transform.segments), 1);
verifyEqual(testCase, transform.segment_index, [1; 1; 1]);
verifyFalse(testCase, isnan(transform.scale));
verifyFalse(testCase, isnan(transform.offset_s));
verifyEqual(testCase, aligned, ...
    transform.scale * [100; 500; 1000] + transform.offset_s, AbsTol=1e-12);
verifyEqual(testCase, transform.method, "affine");

clear cleanup
end

% ------------------------------------------------------------------ setup ---

function value = fitPiecewise(fixture)
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);
value = runIdFor(fixture.conn, "audio_native");
end

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE A synthetic session whose audio clock changes drift regime once.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_apply_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "apply.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedRecording(conn);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), knot=900, ...
    video_scale=0.9992, video_offset=53.40);

fixture.scale = [1.0015; 0.9990];
fixture.offset = [117.25; (1.0015 - 0.9990) * fixture.knot + 117.25];

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

function value = runIdFor(conn, timebaseKey)
rows = fetch(conn, "SELECT t.alignment_run_id FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = double(rows.alignment_run_id(1));
end

function writeTableFile(workspace, name, tbl)
writetable(tbl, fullfile(workspace, name));
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
