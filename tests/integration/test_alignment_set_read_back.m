function tests = test_alignment_set_read_back
%TEST_ALIGNMENT_SET_READ_BACK Phase 3 multi-clock sets and diagnostics read-back.
%
% The fixture aligns two source clocks to one chosen reference. The audio clock
% changes drift regime at a known instant and is fitted piecewise; the video
% clock is affine. Both known transforms are ground truth the test constructed.
%
% The load-bearing assertions are the ones about independence and honesty: that
% one clock failing leaves the others intact, that a set holding a failure does
% not call itself fitted, and that coverage the transform was never anchored over
% stays distinguishable from coverage it was.
tests = functiontests({ ...
    @testSeveralSourceClocksFitIndependentlyAgainstOneReference, ...
    @testOneClockFailingLeavesTheOthersIntact, ...
    @testClockWithAnchorsButNoTransformIsVisibleFromTheReadSide, ...
    @testReportSurfacesSegmentsBreakpointsAndPerSegmentEvidence, ...
    @testReportSurfacesDispersionDiagnosticsAndWithheldAnchors, ...
    @testReportIsReadOnlyAndRefitsNothing, ...
    @testCoverageKeepsObservedUnobservedAndExtrapolatedApart});
end

% ------------------------------------------------------------- multi-clock ---

function testSeveralSourceClocksFitIndependentlyAgainstOneReference(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
fitBoth(fixture);

qc = vawlume.alignment.report(fixture.conn, alignmentRef());

% One transform per source clock, both expressed in the one chosen reference.
verifyEqual(testCase, height(qc.transforms), 2);
verifyEqual(testCase, sort(qc.transforms.source_timebase_key), ...
    ["audio_native"; "video_native"]);
verifyTrue(testCase, all(qc.transforms.reference_timebase_key == "neural_native"));
verifyEqual(testCase, qc.reference_timebase.timebase_key, "neural_native");

% The clocks are fitted independently and differently: one piecewise, one
% affine, each recovering its own known transform.
audio = transformFor(qc, "audio_native");
video = transformFor(qc, "video_native");
verifyEqual(testCase, audio.method, "piecewise_affine");
verifyEqual(testCase, video.method, "affine");
verifyEqual(testCase, audio.segment_count, 2);
verifyEqual(testCase, video.segment_count, 1);

% A segmented transform has no single slope, so the transform row says so and
% the segments table carries the real coefficients.
verifyTrue(testCase, isnan(audio.scale));
verifyEqual(testCase, video.scale, fixture.video_scale, RelTol=1e-6);

audioSegments = segmentsFor(qc, "audio_native");
verifyEqual(testCase, audioSegments.scale, fixture.scale, RelTol=1e-9);

verifyEqual(testCase, qc.set_status, "fitted");

clear cleanup
end

function testOneClockFailingLeavesTheOthersIntact(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Leave the audio clock one included anchor, which its declared model cannot
% support, and fit the whole set.
for key = ["sync02", "sync03", "sync04", "sync05"]
    vawlume.alignment.setAnchorInclusion(fixture.conn, ...
        audioObservationId(fixture, key), false, ...
        Reason="withheld to leave the audio model underdetermined");
end

result = vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
verifyEqual(testCase, result.status, "committed");

qc = vawlume.alignment.report(fixture.conn, alignmentRef());
audio = transformFor(qc, "audio_native");
video = transformFor(qc, "video_native");

% The failure is recorded on the transform it belongs to.
verifyEqual(testCase, audio.status, "failed");
verifyGreaterThan(testCase, strlength(audio.failure_code), 0);
verifyGreaterThan(testCase, strlength(audio.failure_reason), 0);
verifyEqual(testCase, height(qc.failures), 1);
verifyEqual(testCase, qc.failures.source_timebase_key(1), "audio_native");

% The other clock is untouched: it fitted, stored a segment, and recovered its
% known transform. One clock's missing evidence does not take a session down.
verifyEqual(testCase, video.status, "estimated");
verifyEqual(testCase, video.segment_count, 1);
verifyEqual(testCase, video.scale, fixture.video_scale, RelTol=1e-6);

% A set holding a failed transform is not a fitted set. Saying otherwise would
% let a partial outcome read as a complete one.
verifyEqual(testCase, qc.set_status, "draft");

% Nothing was written for the failed clock.
verifyEqual(testCase, height(segmentsFor(qc, "audio_native")), 0);

clear cleanup
end

function testClockWithAnchorsButNoTransformIsVisibleFromTheReadSide(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
fitBoth(fixture);

execute(fixture.conn, "INSERT INTO timebases(project_id, timebase_name, " + ...
    "timebase_kind) VALUES (1, 'controller_native', 'controller_clock')");
strayId = timebaseId(fixture.conn, "controller_native");
execute(fixture.conn, "INSERT INTO alignment_anchor_observations(" + ...
    "alignment_anchor_id, timebase_id, observed_time_native) VALUES (" + ...
    string(anchorId(fixture, "sync01")) + ", " + string(strayId) + ", 4.25)");

qc = vawlume.alignment.report(fixture.conn, alignmentRef());

% Reported, not raised: registering a clock before its transform is legal, and
% a manifest that forgot a transform looks identical from the database.
verifyEqual(testCase, height(qc.clocks_without_transform), 1);
verifyEqual(testCase, qc.clocks_without_transform.timebase_key(1), ...
    "controller_native");
verifyEqual(testCase, qc.clocks_without_transform.observation_count(1), 1);

% The reference clock is never listed: every anchor is read on it by definition.
verifyEqual(testCase, nnz(qc.clocks_without_transform.timebase_key == ...
    "neural_native"), 0);

clear cleanup
end

% ------------------------------------------------------------- diagnostics ---

function testReportSurfacesSegmentsBreakpointsAndPerSegmentEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
fitBoth(fixture);

qc = vawlume.alignment.report(fixture.conn, alignmentRef());

% Every stored segment, with the bounds that make it tile and the per-segment
% evidence the fit produced.
audioSegments = segmentsFor(qc, "audio_native");
verifyEqual(testCase, height(audioSegments), 2);
verifyEqual(testCase, audioSegments.segment_index, [1; 2]);
verifyTrue(testCase, isnan(audioSegments.source_start(1)));
verifyEqual(testCase, audioSegments.source_end(1), fixture.knot);
verifyEqual(testCase, audioSegments.source_start(2), fixture.knot);
verifyTrue(testCase, isnan(audioSegments.source_end(2)));
verifyTrue(testCase, all(audioSegments.rmse_s >= 0));
verifyTrue(testCase, all(audioSegments.uncertainty_semantics == ...
    "max_contributing_anchor_uncertainty_s"));

% Offset and affine contribute one segment open at both ends, so a reader sees
% one shape whatever the method was.
videoSegments = segmentsFor(qc, "video_native");
verifyEqual(testCase, height(videoSegments), 1);
verifyTrue(testCase, isnan(videoSegments.source_start(1)));
verifyTrue(testCase, isnan(videoSegments.source_end(1)));

% The declared segmentation is readable, so a fit stays reconstructable from the
% database alone.
verifyEqual(testCase, height(qc.breakpoints), 1);
verifyEqual(testCase, qc.breakpoints.source_timebase_key(1), "audio_native");
verifyEqual(testCase, qc.breakpoints.source_time(1), fixture.knot);
verifyEqual(testCase, qc.breakpoints.declared_by(1), "caller");

verifyTrue(testCase, contains(qc.uncertainty_note, "uncalibrated"));

clear cleanup
end

function testReportSurfacesDispersionDiagnosticsAndWithheldAnchors(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% A redundant reading 6 ms after the one used, and one anchor withheld.
execute(fixture.conn, "INSERT INTO alignment_anchor_observations(" + ...
    "alignment_anchor_id, timebase_id, observed_time_native, " + ...
    "observation_role, included_in_fit) VALUES (" + ...
    string(anchorId(fixture, "sync01")) + ", " + ...
    string(fixture.audio_timebase_id) + ", 10.006, 'replicate', 0)");
vawlume.alignment.setAnchorInclusion(fixture.conn, ...
    audioObservationId(fixture, "sync04"), false, ...
    Reason="marker edge ambiguous on the audio channel");

fitBoth(fixture);
qc = vawlume.alignment.report(fixture.conn, alignmentRef());

% Dispersion is derived on read from the observations, not from a stored copy.
row = qc.anchor_dispersion(qc.anchor_dispersion.anchor_key == "sync01" & ...
    qc.anchor_dispersion.timebase_key == "audio_native", :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.observation_count(1), 2);
verifyEqual(testCase, row.spread_s(1), 0.006, AbsTol=1e-9);

% An anchor read once has no dispersion and appears in no row at all.
verifyEqual(testCase, nnz(qc.anchor_dispersion.anchor_key == "sync02"), 0);
verifyTrue(testCase, contains(qc.dispersion_note, "never stored"));

% The withheld anchor still has a residual it did not influence, with its reason.
withheld = qc.residuals(qc.residuals.source_timebase_key == "audio_native" & ...
    qc.residuals.anchor_key == "sync04", :);
verifyEqual(testCase, height(withheld), 1);
verifyEqual(testCase, withheld.included_in_fit(1), 0);
verifyGreaterThan(testCase, strlength(withheld.exclusion_reason(1)), 0);
verifyFalse(testCase, isnan(withheld.residual_s(1)));

% Anchor configuration, derived from the same residuals the fitter used.
diagnostics = diagnosticsFor(qc, "audio_native");
verifyEqual(testCase, diagnostics.paired_anchor_count, 5);
verifyEqual(testCase, diagnostics.included_anchor_count, 4);
verifyEqual(testCase, diagnostics.withheld_anchor_count, 1);
verifyEqual(testCase, diagnostics.source_range_start, 10);
verifyEqual(testCase, diagnostics.source_range_end, 1500);
verifyEqual(testCase, diagnostics.source_span_s, 1490);
% Included anchors are 10, 400, 900, 1500: the largest gap is 600.
verifyEqual(testCase, diagnostics.largest_gap_fraction, 600 / 1490, AbsTol=1e-12);

clear cleanup
end

function testReportIsReadOnlyAndRefitsNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
fitBoth(fixture);

before = databaseFingerprint(fixture.conn);
qc = vawlume.alignment.report(fixture.conn, alignmentRef());
after = databaseFingerprint(fixture.conn);
verifyEqual(testCase, after, before);

% It reports the fit of record rather than recomputing one. Corrupting a stored
% coefficient is visible in the report, which it would not be if report refitted.
stored = segmentsFor(qc, "audio_native");
execute(fixture.conn, "UPDATE alignment_segments SET scale = 2.0 " + ...
    "WHERE alignment_run_id = " + string(stored.alignment_run_id(1)) + ...
    " AND segment_index = 1");

reread = segmentsFor(vawlume.alignment.report(fixture.conn, alignmentRef()), ...
    "audio_native");
verifyEqual(testCase, reread.scale(1), 2.0);

clear cleanup
end

% ---------------------------------------------------------------- coverage ---

function testCoverageKeepsObservedUnobservedAndExtrapolatedApart(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
fitBoth(fixture);

value = vawlume.alignment.commonTime(fixture.conn, alignmentRef(), ...
    IncludeExternal=true, ErrorOnOutsideCoverage=false);

% Coverage is the stream's own statement that it was observed. It survives
% projection unchanged: nothing here decides a stream was unobserved because a
% transform was uncertain there.
verifyTrue(testCase, all(value.coverage.observation_status == "observed"));

% projection_status is the separate statement about the transform that placed
% it. Both are present, because a segment can be observed and extrapolated at
% once and collapsing them would destroy both.
verifyTrue(testCase, ismember("projection_status", ...
    value.coverage.Properties.VariableNames));
verifyTrue(testCase, all(ismember(value.coverage.projection_status, ...
    ["anchored", "extrapolated"])));

% Both statuses must actually occur, or the distinction is decorative.
verifyGreaterThan(testCase, nnz(value.coverage.projection_status == "anchored"), 0);
verifyGreaterThan(testCase, nnz(value.coverage.projection_status == "extrapolated"), 0);
verifyGreaterThan(testCase, nnz(value.events.aligned_extrapolated), 0);
verifyGreaterThan(testCase, nnz(~value.events.aligned_extrapolated), 0);

% The video stream's coverage runs from 0 s, before its first anchor, so its
% projection is extrapolated at the low end while the stream is still observed.
video = value.coverage(value.coverage.source_timebase_key == "video_native", :);
verifyGreaterThan(testCase, height(video), 0);
verifyTrue(testCase, any(video.projection_status == "extrapolated"));
verifyTrue(testCase, all(video.observation_status == "observed"));

% Events carry the same distinction per row.
verifyTrue(testCase, ismember("aligned_extrapolated", ...
    value.events.Properties.VariableNames));
verifyTrue(testCase, islogical(value.events.aligned_extrapolated));

% An interval crossing the audio breakpoint is projected through the interval
% path, so its aligned duration differs from its native duration by the amount
% the two segments' scales imply.
crossing = vawlume.alignment.applyTransformInterval(fixture.conn, ...
    runIdFor(fixture.conn, "audio_native"), 800, 1000);
verifyTrue(testCase, crossing.crosses_breakpoint(1));
verifyNotEqual(testCase, crossing.aligned_duration_s(1), ...
    crossing.native_duration_s(1));

clear cleanup
end

% ------------------------------------------------------------------ setup ---

function fitBoth(fixture)
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);
vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="video_native", Apply=true);
end

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE Two source clocks against one chosen reference.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_set_readback_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "readback.sqlite");
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

fixture.audio_timebase_id = timebaseId(conn, "audio_native");
fixture.video_timebase_id = timebaseId(conn, "video_native");
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
    "native_recording_id, sample_rate_hz, duration_s) " + ...
    "VALUES (1, 1, 'REC_SESSION_01', 250000, 1600.0)");
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

function value = transformFor(qc, sourceKey)
selected = qc.transforms.source_timebase_key == sourceKey;
assert(nnz(selected) == 1, "Expected one transform for " + sourceKey);
value = table2struct(qc.transforms(selected, :));
end

function value = segmentsFor(qc, sourceKey)
value = qc.segments(qc.segments.source_timebase_key == sourceKey, :);
end

function value = diagnosticsFor(qc, sourceKey)
selected = qc.anchor_diagnostics.source_timebase_key == sourceKey;
assert(nnz(selected) == 1, "Expected one diagnostics row for " + sourceKey);
value = table2struct(qc.anchor_diagnostics(selected, :));
end

function value = timebaseId(conn, timebaseKey)
rows = fetch(conn, "SELECT timebase_id FROM timebases WHERE timebase_name = '" + ...
    timebaseKey + "'");
value = double(rows.timebase_id(1));
end

function value = runIdFor(conn, timebaseKey)
rows = fetch(conn, "SELECT t.alignment_run_id FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = double(rows.alignment_run_id(1));
end

function value = anchorId(fixture, anchorKey)
rows = fetch(fixture.conn, "SELECT alignment_anchor_id FROM alignment_anchors " + ...
    "WHERE anchor_key = '" + anchorKey + "'");
value = double(rows.alignment_anchor_id(1));
end

function value = audioObservationId(fixture, anchorKey)
rows = fetch(fixture.conn, "SELECT anchor_observation_id " + ...
    "FROM alignment_anchor_observations WHERE alignment_anchor_id = " + ...
    string(anchorId(fixture, anchorKey)) + " AND timebase_id = " + ...
    string(fixture.audio_timebase_id) + " AND observation_role <> 'replicate' " + ...
    "ORDER BY anchor_observation_id");
value = double(rows.anchor_observation_id(1));
end

function value = databaseFingerprint(conn)
%DATABASEFINGERPRINT Row counts for every table a report could plausibly touch.
value = struct();
for name = ["alignment_segments", "alignment_run_breakpoints", ...
        "alignment_anchor_residuals", "alignment_anchor_observations", ...
        "time_alignment_runs", "alignment_sets", "aligned_external_events"]
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + name);
    value.(name) = double(rows.n(1));
end
rows = fetch(conn, "SELECT IFNULL(SUM(scale),0) AS s, " + ...
    "IFNULL(SUM(offset_s),0) AS o FROM alignment_segments");
value.coefficient_sum = double(rows.s(1)) + double(rows.o(1));
end

function writeTableFile(workspace, name, tbl)
writetable(tbl, fullfile(workspace, name));
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
