function tests = test_alignment_anchor_qc
%TEST_ALIGNMENT_ANCHOR_QC Phase 3 anchor QC, replicate dispersion, exclusion.
%
% The fixture registers a synthetic session whose anchor times are generated from
% two known transforms, so every recovered coefficient is checked against ground
% truth the test constructed. Those known parameters are test ground truth, not a
% claim that real device clocks drift this way.
%
% The load-bearing assertions here are the negative ones: that replicate spread
% is evidence and not an extra anchor, that a diagnostic changes no coefficient,
% and that nothing excludes an anchor unless a caller says so.
tests = functiontests({ ...
    @testReplicateSpreadIsDerivedAndIsNotAnExtraAnchor, ...
    @testAnchorConfigurationDiagnosticsDescribeTheAnchorSet, ...
    @testLeaveOneOutInfluenceIsReportedAndChangesNothing, ...
    @testExclusionIsDeclaredWithAReasonAndStaysVisible, ...
    @testExclusionRefusesUnexplainedAndUnsafeChanges, ...
    @testUnpairableAnchorsAreReportedRatherThanSkipped, ...
    @testTooFewAnchorsFailsWithANamedCode, ...
    @testClockWithAnchorsButNoTransformIsReported});
end

% ------------------------------------------------------ replicate evidence ---

function testReplicateSpreadIsDerivedAndIsNotAnExtraAnchor(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

baseline = vawlume.alignment.fit(fixture.conn, alignmentRef());
audioBefore = transformFor(baseline, "audio_native");

% A second reading of the same marker on the same clock, 6 ms later. It is
% preserved as QC evidence and excluded from the fit, which is the only shape
% the schema permits.
addReplicate(fixture, "sync01", fixture.audio_timebase_id, ...
    audioTime(fixture, "sync01") + 0.006);

result = vawlume.alignment.fit(fixture.conn, alignmentRef());
row = anchorRow(result, "audio_native", "sync01");

% The spread is reported with both readings accounted for.
verifyEqual(testCase, row.source_observation_count, 2);
verifyEqual(testCase, row.source_spread_s, 0.006, AbsTol=1e-12);
verifyEqual(testCase, row.source_max_deviation_s, 0.006, AbsTol=1e-12);

% An anchor read once has no dispersion. That is an absence, not agreement.
other = anchorRow(result, "audio_native", "sync02");
verifyEqual(testCase, other.source_observation_count, 1);
verifyTrue(testCase, isnan(other.source_spread_s));
verifyTrue(testCase, isnan(other.source_max_deviation_s));

% The replicate is evidence, never a second statistical anchor: the anchor count
% and both coefficients are unchanged by its arrival.
audioAfter = transformFor(result, "audio_native");
verifyEqual(testCase, audioAfter.n_anchors_used, audioBefore.n_anchors_used);
verifyEqual(testCase, audioAfter.scale, audioBefore.scale);
verifyEqual(testCase, audioAfter.offset_s, audioBefore.offset_s);

% One row per logical anchor, not one per reading.
audioRows = result.anchors(result.anchors.source_timebase_key == "audio_native", :);
verifyEqual(testCase, height(audioRows), 4);

verifyTrue(testCase, contains(result.dispersion_note, "never stored"));

clear cleanup
end

% ----------------------------------------------------------- diagnostics ---

function testAnchorConfigurationDiagnosticsDescribeTheAnchorSet(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

result = vawlume.alignment.fit(fixture.conn, alignmentRef());
audio = diagnosticsFor(result, "audio_native");

verifyEqual(testCase, audio.paired_anchor_count, 4);
verifyEqual(testCase, audio.included_anchor_count, 4);
verifyEqual(testCase, audio.withheld_anchor_count, 0);
verifyEqual(testCase, audio.unpaired_anchor_count, 0);

% Anchors at 10, 400, 900 and 1500 s on the audio clock.
verifyEqual(testCase, audio.source_range_start, 10, AbsTol=1e-12);
verifyEqual(testCase, audio.source_range_end, 1500, AbsTol=1e-12);
verifyEqual(testCase, audio.source_span_s, 1490, AbsTol=1e-12);
verifyEqual(testCase, audio.largest_gap_fraction, 600 / 1490, AbsTol=1e-12);

% Withholding the middle anchor leaves the same span with a wider hole in it,
% which is what a reader needs to see before trusting a slope.
vawlume.alignment.setAnchorInclusion(fixture.conn, ...
    audioObservationId(fixture, "sync02"), false, ...
    Reason="marker edge ambiguous on the audio channel");

clustered = vawlume.alignment.fit(fixture.conn, alignmentRef());
after = diagnosticsFor(clustered, "audio_native");

verifyEqual(testCase, after.included_anchor_count, 3);
verifyEqual(testCase, after.withheld_anchor_count, 1);
verifyEqual(testCase, after.source_span_s, 1490, AbsTol=1e-12);
verifyEqual(testCase, after.largest_gap_fraction, 890 / 1490, AbsTol=1e-12);
verifyGreaterThan(testCase, after.largest_gap_fraction, audio.largest_gap_fraction);

clear cleanup
end

function testLeaveOneOutInfluenceIsReportedAndChangesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Anchors consistent with one transform: no reading carries the fit.
consistent = vawlume.alignment.fit(fixture.conn, alignmentRef());
for key = ["sync01", "sync02", "sync03", "sync04"]
    row = anchorRow(consistent, "audio_native", key);
    verifyLessThan(testCase, abs(row.loo_scale_delta), 1e-9);
    verifyFalse(testCase, isnan(row.loo_offset_delta_s));
end
before = anchorRow(consistent, "audio_native", "sync03");

% Move one marker 40 ms, as a mis-read edge would. The fit still succeeds, and
% the diagnostic is what shows that this reading now moves the answer.
execute(fixture.conn, "UPDATE alignment_anchor_observations " + ...
    "SET observed_time_native = observed_time_native + 0.040 " + ...
    "WHERE anchor_observation_id = " + ...
    string(audioObservationId(fixture, "sync03")));

skewed = vawlume.alignment.fit(fixture.conn, alignmentRef());
after = anchorRow(skewed, "audio_native", "sync03");

% The honest comparison is the same anchor before and after, not one anchor
% against another. Influence mixes leverage with residual, so an endpoint
% anchor can outrank a mis-read middle one on a well-behaved set.
verifyGreaterThan(testCase, abs(after.loo_scale_delta), ...
    abs(before.loo_scale_delta) * 1e3);
verifyGreaterThan(testCase, abs(after.loo_offset_delta_s), 1e-6);

% The diagnostic reports; it decides nothing. Every anchor is still in the fit,
% and nothing was excluded on its own initiative.
verifyEqual(testCase, nnz(skewed.anchors.included_in_fit == 0), 0);
audio = transformFor(skewed, "audio_native");
verifyEqual(testCase, audio.n_anchors_used, 4);
verifyTrue(testCase, contains(skewed.influence_note, "never acted on"));

clear cleanup
end

% ------------------------------------------------------ declared exclusion ---

function testExclusionIsDeclaredWithAReasonAndStaysVisible(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
observationId = audioObservationId(fixture, "sync04");
timeBefore = observedTime(fixture.conn, observationId);

outcome = vawlume.alignment.setAnchorInclusion(fixture.conn, observationId, ...
    false, Reason="operator logged a false trigger on this pulse");

verifyEqual(testCase, outcome.action, "withheld");
verifyEqual(testCase, outcome.previous_included_in_fit, 1);
verifyEqual(testCase, outcome.included_in_fit, 0);
verifyEqual(testCase, outcome.observation_role, "excluded");

% The decision is recorded where a later reader will find it, and the reading's
% own evidence is untouched.
verifyTrue(testCase, contains(noteOf(fixture.conn, observationId), ...
    "withheld_from_fit: operator logged a false trigger"));
verifyEqual(testCase, observedTime(fixture.conn, observationId), timeBefore);

% A withheld anchor is still evaluated: it receives a residual against the
% transform it did not help produce.
result = vawlume.alignment.fit(fixture.conn, alignmentRef());
row = anchorRow(result, "audio_native", "sync04");
verifyEqual(testCase, row.included_in_fit, 0);
verifyFalse(testCase, isnan(row.residual_s));
verifyTrue(testCase, strlength(row.exclusion_reason) > 0);
verifyEqual(testCase, diagnosticsFor(result, "audio_native").withheld_anchor_count, 1);

% Restoring is a decision too, and is recorded beside the first one.
restored = vawlume.alignment.setAnchorInclusion(fixture.conn, observationId, ...
    true, Reason="operator log corrected; the pulse was genuine");
verifyEqual(testCase, restored.action, "restored");
verifyEqual(testCase, restored.observation_role, "primary");
notes = noteOf(fixture.conn, observationId);
verifyTrue(testCase, contains(notes, "withheld_from_fit"));
verifyTrue(testCase, contains(notes, "restored_to_fit"));

% Repeating a decision already in force writes nothing.
again = vawlume.alignment.setAnchorInclusion(fixture.conn, observationId, ...
    true, Reason="no change intended");
verifyEqual(testCase, again.action, "unchanged");
verifyEqual(testCase, noteOf(fixture.conn, observationId), notes);

clear cleanup
end

function testExclusionRefusesUnexplainedAndUnsafeChanges(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
observationId = audioObservationId(fixture, "sync01");

% An unexplained change to which evidence counts is not auditable.
verifyError(testCase, @() vawlume.alignment.setAnchorInclusion( ...
    fixture.conn, observationId, false), ...
    "vawlume:alignment:ExclusionReasonRequired");
verifyError(testCase, @() vawlume.alignment.setAnchorInclusion( ...
    fixture.conn, observationId, false, Reason="   "), ...
    "vawlume:alignment:ExclusionReasonRequired");

verifyError(testCase, @() vawlume.alignment.setAnchorInclusion( ...
    fixture.conn, observationId, false, Reason="why", Role="probably_bad"), ...
    "vawlume:alignment:ObservationRoleUnsupported");

verifyError(testCase, @() vawlume.alignment.setAnchorInclusion( ...
    fixture.conn, 99999, false, Reason="why"), ...
    "vawlume:alignment:AnchorObservationNotFound");

% Restoring a replicate while the primary is still included would give one
% anchor two included readings on one clock.
replicateId = addReplicate(fixture, "sync01", fixture.audio_timebase_id, ...
    audioTime(fixture, "sync01") + 0.006);
verifyError(testCase, @() vawlume.alignment.setAnchorInclusion( ...
    fixture.conn, replicateId, true, Reason="prefer the second reading"), ...
    "vawlume:alignment:AnchorObservationAmbiguous");

% Withholding the primary first makes the same restore legal, which is how a
% caller chooses between two readings explicitly rather than by row order.
vawlume.alignment.setAnchorInclusion(fixture.conn, observationId, false, ...
    Reason="superseded by the corrected reading");
outcome = vawlume.alignment.setAnchorInclusion(fixture.conn, replicateId, ...
    true, Reason="corrected reading from the second pass");
verifyEqual(testCase, outcome.action, "restored");

clear cleanup
end

% ------------------------------------------------------- explicit failures ---

function testUnpairableAnchorsAreReportedRatherThanSkipped(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Two readings on the audio clock with neither included: which one is meant is
% genuinely unknown, so the anchor cannot pair.
addReplicate(fixture, "sync02", fixture.audio_timebase_id, ...
    audioTime(fixture, "sync02") + 0.01);
vawlume.alignment.setAnchorInclusion(fixture.conn, ...
    audioObservationId(fixture, "sync02"), false, ...
    Reason="two candidate edges, neither confirmed");

result = vawlume.alignment.fit(fixture.conn, alignmentRef());

unpaired = result.unpaired_anchors( ...
    result.unpaired_anchors.source_timebase_key == "audio_native", :);
verifyEqual(testCase, height(unpaired), 1);
verifyEqual(testCase, unpaired.anchor_key(1), "sync02");
verifyEqual(testCase, unpaired.source_observation_count(1), 2);
verifyTrue(testCase, contains(unpaired.reason(1), "unresolved"));

% It is absent from the paired anchors rather than quietly counted as one.
audioRows = result.anchors(result.anchors.source_timebase_key == "audio_native", :);
verifyEqual(testCase, height(audioRows), 3);
verifyEqual(testCase, nnz(audioRows.anchor_key == "sync02"), 0);
verifyEqual(testCase, diagnosticsFor(result, "audio_native").unpaired_anchor_count, 1);

clear cleanup
end

function testTooFewAnchorsFailsWithANamedCode(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% An affine fit needs two distinct source times. Leave it one.
for key = ["sync02", "sync03", "sync04"]
    vawlume.alignment.setAnchorInclusion(fixture.conn, ...
        audioObservationId(fixture, key), false, ...
        Reason="withheld to leave the model underdetermined");
end

result = vawlume.alignment.fit(fixture.conn, alignmentRef());

verifyTrue(testCase, result.has_conflicts);
verifyTrue(testCase, any(contains(result.conflicts, "audio_native")));
audio = transformFor(result, "audio_native");
verifyEqual(testCase, audio.action, "not_fit_ready");

% The video clock is untouched and still fits: one clock's missing evidence does
% not take the others down with it.
video = transformFor(result, "video_native");
verifyEqual(testCase, video.action, "create");

clear cleanup
end

function testClockWithAnchorsButNoTransformIsReported(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% A clock whose readings were registered but whose transform never was. It is
% legal, and it is equally often a manifest that forgot a transform, so it is
% reported rather than raised or ignored.
execute(fixture.conn, "INSERT INTO timebases(project_id, timebase_name, " + ...
    "timebase_kind) VALUES (1, 'controller_native', 'controller_clock')");
strayId = timebaseId(fixture.conn, "controller_native");
execute(fixture.conn, "INSERT INTO alignment_anchor_observations(" + ...
    "alignment_anchor_id, timebase_id, observed_time_native) VALUES (" + ...
    string(anchorId(fixture, "sync01")) + ", " + string(strayId) + ", 4.25)");

result = vawlume.alignment.fit(fixture.conn, alignmentRef());

stray = result.anchors_without_transform;
verifyEqual(testCase, height(stray), 1);
verifyEqual(testCase, stray.timebase_key(1), "controller_native");
verifyEqual(testCase, stray.observation_count(1), 1);

% Reporting it is not failing over it: both real transforms still fit.
verifyFalse(testCase, result.has_conflicts);
verifyEqual(testCase, height(result.transforms), 2);

% The reference clock is never listed: every anchor is read on it by definition.
verifyEqual(testCase, nnz(stray.timebase_key == "neural_native"), 0);

clear cleanup
end

% ------------------------------------------------------------------ setup ---

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE Register a synthetic session whose anchors follow known transforms.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_anchor_qc_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "anchor_qc.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedRecording(conn);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
    audio_scale=1.0015, audio_offset=117.25, ...
    video_scale=0.9992, video_offset=53.40);

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
% The shipped manifest names this project and recording, so the fixture must
% establish them before alignment intake can resolve it.
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

% ---------------------------------------------------------------- helpers ---

function value = alignmentRef()
value = struct(run_key="synthetic_session_01_alignment");
end

function value = transformFor(result, sourceKey)
selected = result.transforms.source_timebase_key == sourceKey;
assert(nnz(selected) == 1, "Expected one transform for " + sourceKey);
value = table2struct(result.transforms(selected, :));
end

function value = diagnosticsFor(result, sourceKey)
selected = result.anchor_diagnostics.source_timebase_key == sourceKey;
assert(nnz(selected) == 1, "Expected one diagnostics row for " + sourceKey);
value = table2struct(result.anchor_diagnostics(selected, :));
end

function value = anchorRow(result, sourceKey, anchorKey)
selected = result.anchors.source_timebase_key == sourceKey & ...
    result.anchors.anchor_key == anchorKey;
assert(nnz(selected) == 1, "Expected one anchor row for " + anchorKey);
value = table2struct(result.anchors(selected, :));
end

function value = addReplicate(fixture, anchorKey, timebaseId, observedTime)
%ADDREPLICATE A second reading of one marker on one clock, kept out of the fit.
execute(fixture.conn, "INSERT INTO alignment_anchor_observations(" + ...
    "alignment_anchor_id, timebase_id, observed_time_native, " + ...
    "observation_role, included_in_fit) VALUES (" + ...
    string(anchorId(fixture, anchorKey)) + ", " + string(timebaseId) + ", " + ...
    compose("%.9f", observedTime) + ", 'replicate', 0)");
rows = fetch(fixture.conn, "SELECT MAX(anchor_observation_id) AS id " + ...
    "FROM alignment_anchor_observations");
value = double(rows.id(1));
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

function value = audioObservationId(fixture, anchorKey)
rows = fetch(fixture.conn, "SELECT anchor_observation_id " + ...
    "FROM alignment_anchor_observations WHERE alignment_anchor_id = " + ...
    string(anchorId(fixture, anchorKey)) + " AND timebase_id = " + ...
    string(fixture.audio_timebase_id) + " AND observation_role <> 'replicate' " + ...
    "ORDER BY anchor_observation_id");
value = double(rows.anchor_observation_id(1));
end

function value = audioTime(fixture, anchorKey)
index = find(fixture.anchor_keys == anchorKey, 1);
value = fixture.audio_times(index);
end

function value = observedTime(conn, observationId)
rows = fetch(conn, "SELECT observed_time_native FROM " + ...
    "alignment_anchor_observations WHERE anchor_observation_id = " + ...
    string(observationId));
value = double(rows.observed_time_native(1));
end

function value = noteOf(conn, observationId)
rows = fetch(conn, "SELECT IFNULL(notes,'') AS notes FROM " + ...
    "alignment_anchor_observations WHERE anchor_observation_id = " + ...
    string(observationId));
column = rows.notes;
if iscell(column)
    value = string(column{1});
else
    value = string(column(1));
end
end

function writeTableFile(workspace, name, tbl)
writetable(tbl, fullfile(workspace, name));
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
