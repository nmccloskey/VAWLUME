function tests = test_alignment_intake
%TEST_ALIGNMENT_INTAKE Phase 7 alignment manifest intake and registration.
%
% Registration only. These tests assert that a session manifest materializes the
% normalized alignment ontology and that nothing here fabricates a transform: no
% segment, residual, or aligned timestamp may appear.
tests = functiontests({ ...
    @testManifestRegistersTheWholeSessionAtomically, ...
    @testPlanningWritesNothing, ...
    @testIdenticalManifestIsIdempotent, ...
    @testChangedReferenceTimebaseConflicts, ...
    @testChangedSourceContentIsRejected, ...
    @testMissingDeclaredSourceFailsBeforeAnyWrite, ...
    @testUnknownAnchorTimebaseFailsBeforeAnyWrite, ...
    @testUnresolvedEventReferenceBlocksApply, ...
    @testUnresolvedDuplicateObservationsAreKeptButNotFitReady, ...
    @testInducedFailureRollsBackEveryRegisteredRow, ...
    @testNativeTimebaseIsEnsuredOnceForAPreExistingRecording, ...
    @testSuppliedTablesBypassFileReadingWithoutChangingSemantics});
end

% ------------------------------------------------------------ registration ---

function testManifestRegistersTheWholeSessionAtomically(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = applyManifest(fixture);

verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);
verifyTrue(testCase, result.valid_for_ingest);
verifyFalse(testCase, result.transforms_fitted);

% Three declared clocks, exactly one of them the recording's native audio clock.
verifyEqual(testCase, height(result.timebases), 3);
verifyEqual(testCase, nnz(result.timebases.recording_native), 1);
verifyEqual(testCase, count(fixture.conn, "timebases", "is_recording_native = 1"), 1);

% Two logical streams on their own clocks, with source and profile provenance.
verifyEqual(testCase, sort(result.streams.stream_key), ...
    ["neural_ttl"; "video_behavior"]);
verifyEqual(testCase, count(fixture.conn, "external_stream_sources", "1=1"), 2);
verifyEqual(testCase, count(fixture.conn, "external_stream_sources", ...
    "mapping_profile_version_id IS NOT NULL"), 2);

% Events keep their native identity and gain a normalized operational key.
verifyEqual(testCase, count(fixture.conn, "external_events", "1=1"), 6);
verifyEqual(testCase, count(fixture.conn, "external_events", ...
    "native_event_label = 'Intruder enters' AND event_type = 'female_entry'"), 1);
verifyEqual(testCase, count(fixture.conn, "external_event_attributes", "1=1"), 9);
verifyEqual(testCase, count(fixture.conn, "external_stream_coverage", "1=1"), 3);

% The source left b2's end cell empty. Source mapping resolved that to a point
% event at the start, and registration stores that decision rather than
% reinterpreting it as an unknown or open-ended interval.
verifyEqual(testCase, count(fixture.conn, "external_events", ...
    "native_event_id = 'b2' AND end_time_native = start_time_native"), 1);

% One alignment set owning one reference clock, with the manifest as evidence.
verifyEqual(testCase, count(fixture.conn, "alignment_sets", "1=1"), 1);
verifyEqual(testCase, count(fixture.conn, "alignment_sets", ...
    "manifest_source_file_id IS NOT NULL AND status = 'draft'"), 1);
verifyEqual(testCase, result.reference_timebase.timebase_key, "neural_native");
verifyEqual(testCase, count(fixture.conn, "analysis_runs", ...
    "run_type = 'temporal_alignment' AND status = 'completed'"), 1);

% Three logical anchors, each observed on all three clocks.
verifyEqual(testCase, result.anchor_summary.anchor_count, 3);
verifyEqual(testCase, result.anchor_summary.observation_count, 9);
verifyEqual(testCase, sort(result.observations_by_timebase.observation_count), ...
    [3; 3; 3]);
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_observations", ...
    "external_event_id IS NOT NULL"), 3);

% One registered transform per non-reference clock, and nothing fitted.
verifyEqual(testCase, sort(result.transform_runs.source_timebase_key), ...
    ["audio_native"; "video_native"]);
verifyEqual(testCase, unique(result.transform_runs.status), "registered");
verifyEqual(testCase, result.transform_runs.fit_eligible_anchor_count, [3; 3]);
verifyEqual(testCase, count(fixture.conn, "time_alignment_runs", ...
    "status = 'registered'"), 2);
verifyEqual(testCase, count(fixture.conn, "alignment_segments", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "alignment_anchor_residuals", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "aligned_external_events", "1=1"), 0);

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
clear cleanup
end

function testPlanningWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = alignmentRowTotal(fixture.conn);
result = planManifest(fixture);

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyTrue(testCase, result.valid_for_ingest);
verifyEqual(testCase, alignmentRowTotal(fixture.conn), before);

% The plan still explains what it would do, without any database identity.
verifyEqual(testCase, unique(result.timebases.action), "create");
verifyTrue(testCase, all(isnan(result.streams.external_stream_id)));
verifyEqual(testCase, result.anchor_summary.anchor_count, 3);

clear cleanup
end

% --------------------------------------------------- idempotency and conflict ---

function testIdenticalManifestIsIdempotent(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = applyManifest(fixture);
before = alignmentRowTotal(fixture.conn);

second = applyManifest(fixture);
verifyEqual(testCase, second.status, "reused");
verifyTrue(testCase, second.committed);
verifyEqual(testCase, second.analysis.analysis_run_id, first.analysis.analysis_run_id);
verifyEqual(testCase, second.analysis.alignment_set_id, first.analysis.alignment_set_id);
verifyEqual(testCase, alignmentRowTotal(fixture.conn), before);

clear cleanup
end

function testChangedReferenceTimebaseConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyManifest(fixture);

% Same alignment key, different reference clock. Rewriting the earlier set in
% place would silently change what every later fit was expressed in.
fixture = rewriteManifest(fixture, '"reference_timebase": "neural_native"', ...
    '"reference_timebase": "video_native"');
result = planManifest(fixture);
verifyEqual(testCase, result.status, "conflict");
verifyTrue(testCase, result.has_conflicts);
verifyTrue(testCase, any(contains(result.conflicts, "reference timebase")));

applied = applyManifest(fixture);
verifyFalse(testCase, applied.committed);
verifyEqual(testCase, count(fixture.conn, "alignment_sets", "1=1"), 1);

clear cleanup
end

function testChangedSourceContentIsRejected(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyManifest(fixture);

% The same declared file now hashes differently, so it is not the input the
% registered alignment was built from.
writeTableFile(fixture.workspace, "video_events.csv", editedBehaviorTable());
verifyError(testCase, @() planManifest(fixture), ...
    "vawlume:ingest:AlignmentSourceChanged");

clear cleanup
end

function testMissingDeclaredSourceFailsBeforeAnyWrite(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
delete(fullfile(fixture.workspace, "neural_events.csv"));

verifyError(testCase, @() applyManifest(fixture), ...
    "vawlume:ingest:AlignmentSourceNotFound");
verifyEqual(testCase, alignmentRowTotal(fixture.conn), 0);

clear cleanup
end

function testUnknownAnchorTimebaseFailsBeforeAnyWrite(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The manifest stops declaring the audio clock the anchor table observes.
fixture = rewriteManifest(fixture, ...
    ['    {' newline '      "timebase_key": "audio_native",' newline ...
    '      "timebase_kind": "audio_sample_clock",' newline ...
    '      "recording_native": true,' newline '      "native_unit": "s",' newline ...
    '      "origin_description": "Recording file time zero."' newline '    },' newline], "");
verifyError(testCase, @() applyManifest(fixture), ...
    "vawlume:ingest:AlignmentTimebaseUndeclared");
verifyEqual(testCase, alignmentRowTotal(fixture.conn), 0);

clear cleanup
end

function testUnresolvedEventReferenceBlocksApply(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
anchors = anchorTable();
anchors.event_id(anchors.stream == "neural") = ["n1"; "n2"; "missing_pulse"];
writeTableFile(fixture.workspace, "sync_anchors.csv", anchors);

result = planManifest(fixture);
verifyFalse(testCase, result.valid_for_ingest);
verifyTrue(testCase, any(result.issues.code == "EVENT_REFERENCE_UNRESOLVED"));

verifyError(testCase, @() applyManifest(fixture), "vawlume:ingest:AlignmentNotReady");
verifyEqual(testCase, alignmentRowTotal(fixture.conn), 0);

clear cleanup
end

function testUnresolvedDuplicateObservationsAreKeptButNotFitReady(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
anchors = anchorTable();
duplicate = anchors(2, :);
duplicate.timestamp_s = "67.837";
duplicate.role = "primary";
duplicate.include = "true";
writeTableFile(fixture.workspace, "sync_anchors.csv", [anchors; duplicate]);

result = planManifest(fixture);
verifyFalse(testCase, result.valid_for_ingest);
verifyTrue(testCase, any(result.issues.code == "ANCHOR_PRIMARY_AMBIGUOUS"));

% The evidence is not discarded; it is simply not fit-ready.
verifyEqual(testCase, result.anchor_summary.observation_count, 10);
verifyError(testCase, @() applyManifest(fixture), "vawlume:ingest:AlignmentNotReady");

clear cleanup
end

% ------------------------------------------------------------- transaction ---

function testInducedFailureRollsBackEveryRegisteredRow(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "CREATE TRIGGER trg_alignment_failure " + ...
    "BEFORE INSERT ON alignment_anchor_observations FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT,'induced alignment failure'); END");
dropper = onCleanup(@() dropTrigger(fixture.conn));

verifyError(testCase, @() applyManifest(fixture), ?MException);

% The failure happens after sources, profiles, timebases, the analysis run, the
% alignment set, streams, events, and anchors are all inserted. None may survive.
verifyEqual(testCase, alignmentRowTotal(fixture.conn), 0);
verifyEqual(testCase, count(fixture.conn, "analysis_runs", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "config_profiles", "1=1"), 0);
verifyEqual(testCase, count(fixture.conn, "source_files", "file_role LIKE 'external%'"), 0);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

clear dropper
recovered = applyManifest(fixture);
verifyEqual(testCase, recovered.status, "committed");

clear cleanup
end

% --------------------------------------------------------- native timebase ---

function testNativeTimebaseIsEnsuredOnceForAPreExistingRecording(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The recording predates Phase 7 and has no clock of its own.
verifyEqual(testCase, count(fixture.conn, "timebases", "1=1"), 0);
applyManifest(fixture);

% Intake creates exactly one, inheriting the recording's sample rate.
verifyEqual(testCase, count(fixture.conn, "timebases", ...
    "is_recording_native = 1 AND nominal_rate_hz = 250000"), 1);

% A second alignment over the same recording reuses it rather than attempting a
% second native clock, which the schema would refuse outright.
fixture = rewriteManifest(fixture, '"alignment_key": "synthetic_session_01_alignment"', ...
    '"alignment_key": "synthetic_session_01_alignment_v2"');
second = applyManifest(fixture);
verifyEqual(testCase, second.status, "committed");
verifyEqual(testCase, count(fixture.conn, "timebases", "is_recording_native = 1"), 1);
verifyEqual(testCase, count(fixture.conn, "alignment_sets", "1=1"), 2);
nativeRow = second.timebases(second.timebases.recording_native, :);
verifyEqual(testCase, nativeRow.action, "reuse");

clear cleanup
end

function testSuppliedTablesBypassFileReadingWithoutChangingSemantics(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
tables = struct(video_behavior=behaviorTable(), neural_ttl=neuralTable(), ...
    anchors=anchorTable());
result = vawlume.ingest.alignment(fixture.conn, fixture.manifest_path, ...
    RepoRoot=fixture.repo_root, SourceRoot=fixture.workspace, ...
    Tables=tables, Apply=true);

verifyEqual(testCase, result.status, "committed");
verifyEqual(testCase, count(fixture.conn, "external_events", "1=1"), 6);
verifyEqual(testCase, result.anchor_summary.observation_count, 9);

% An in-memory table has no file identity, so only the manifest is registered as
% a source rather than three files.
verifyEqual(testCase, height(result.sources), 1);
verifyEqual(testCase, result.sources.role, "manifest");
verifyEqual(testCase, count(fixture.conn, "external_stream_sources", "1=1"), 0);

clear cleanup
end

% ----------------------------------------------------------------- fixture ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_alignment_intake_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "alignment_intake.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedRecording(conn);
writeTableFile(workspace, "video_events.csv", behaviorTable());
writeTableFile(workspace, "neural_events.csv", neuralTable());
writeTableFile(workspace, "sync_anchors.csv", anchorTable());

manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);

fixture = struct(conn=conn, workspace=string(workspace), revision=0, ...
    repo_root=string(repoRoot), manifest_path=string(manifestPath));
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
execute(conn, "INSERT INTO entity_types(project_id, native_name, canonical_role) " + ...
    "VALUES (1, 'subject', 'subject')");
execute(conn, "INSERT INTO experimental_entities(project_id, entity_type_id, native_id) " + ...
    "VALUES (1, 1, 'F01')");
end

% -------------------------------------------------------- synthetic tables ---

function tbl = behaviorTable()
tbl = table(["b1"; "b2"; "b3"], ...
    ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    ["10"; "20"; "30"], ["12"; missing; "30"], ["F01"; "M01"; ""], ...
    ["door"; "center"; "sync"], ...
    VariableNames=["event_id", "event", "start_time_s", "end_time_s", ...
    "subject", "zone"]);
end

function tbl = editedBehaviorTable()
tbl = behaviorTable();
tbl.start_time_s(1) = "11";
end

function tbl = neuralTable()
tbl = table(["n1"; "n2"; "n3"], repmat("TTL1_HIGH", 3, 1), ...
    ["121482"; "602911"; "1017000"], ["5"; "4.8"; "5.1"], ["1"; "1"; "1"], ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
end

function tbl = anchorTable()
markers = repelem(["sync01"; "sync02"; "sync03"], 3);
streams = repmat(["audio"; "video"; "neural"], 3, 1);
timestamps = ["4.216"; "67.833"; "121.482"; "485.638"; "549.275"; "602.911"; ...
    "900.000"; "963.000"; "1017.000"];
eventIds = strings(9, 1);
eventIds(streams == "neural") = ["n1"; "n2"; "n3"];
tbl = table(markers, streams, timestamps, repmat("primary", 9, 1), ...
    repmat("true", 9, 1), repmat("0.002", 9, 1), eventIds, ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
end

% ----------------------------------------------------------------- helpers ---

function result = planManifest(fixture)
result = vawlume.ingest.alignment(fixture.conn, fixture.manifest_path, ...
    RepoRoot=fixture.repo_root, SourceRoot=fixture.workspace);
end

function result = applyManifest(fixture)
result = vawlume.ingest.alignment(fixture.conn, fixture.manifest_path, ...
    RepoRoot=fixture.repo_root, SourceRoot=fixture.workspace, Apply=true);
end

function writeTableFile(workspace, name, tbl)
path = fullfile(workspace, name);
if isfile(path)
    delete(path);
end
writetable(tbl, path, QuoteStrings="minimal");
end

function fixture = rewriteManifest(fixture, oldText, newText)
%REWRITEMANIFEST Produce a revised manifest at a new path.
%
% The revision is written beside the original rather than over it. A manifest is
% registered as a source file with its checksum, so rewriting one in place would
% be a provenance conflict about the file rather than the identity question each
% test is actually asking.
text = string(fileread(fixture.manifest_path));
text = replace(text, sprintf("\r\n"), newline);
assert(contains(text, oldText), "Manifest edit target not found.");
text = replace(text, oldText, newText);
revision = fixture.revision + 1;
path = fullfile(fixture.workspace, "alignment_manifest_v" + string(revision) + ".json");
fileId = fopen(path, "w");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
clear cleaner
fixture.manifest_path = string(path);
fixture.revision = revision;
end

function value = count(conn, tableName, whereClause)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName + " WHERE " + whereClause);
value = double(rows.n(1));
end

function value = alignmentRowTotal(conn)
value = 0;
names = ["timebases", "external_streams", "external_stream_sources", ...
    "external_stream_coverage", "external_events", "external_event_attributes", ...
    "alignment_sets", "time_alignment_runs", "alignment_anchors", ...
    "alignment_anchor_observations", "analysis_runs"];
for name = names
    value = value + count(conn, name, "1=1");
end
end

function dropTrigger(conn)
try
    execute(conn, "DROP TRIGGER IF EXISTS trg_alignment_failure");
catch
end
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
