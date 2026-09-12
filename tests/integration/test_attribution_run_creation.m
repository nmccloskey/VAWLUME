function tests = test_attribution_run_creation
%TEST_ATTRIBUTION_RUN_CREATION Phase 4.4 run, target, and provenance path.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repoRoot = repoRoot;
end

function setup(testCase)
file = string(tempname) + ".sqlite";
conn = sqlite(char(file), "create");
vawlume.db.applySchema(conn, fullfile(testCase.TestData.repoRoot, ...
    "schema", "schema.sql"));
seedFixture(conn);
testCase.TestData.conn = conn;
testCase.TestData.file = file;
end

function teardown(testCase)
if isfield(testCase.TestData, "conn")
    close(testCase.TestData.conn);
end
if isfield(testCase.TestData, "file") && isfile(testCase.TestData.file)
    delete(testCase.TestData.file);
end
end

function testDetectionRunPersistsIdentitySourcesParticipantsAndTargets(testCase)
conn = testCase.TestData.conn;
result = vawlume.attribution.createRun(conn, recordingRef(), ...
    nominalSpec("att-detection", struct(detection_ids=[1 2])), Apply=true);

verifyEqual(testCase, result.status, "created");
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.target_count, 2);
verifyEqual(testCase, result.event_set.kind, "detections");
verifyEqual(testCase, result.event_set.source_kind, "extraction_run");
verifyEqual(testCase, result.event_set.source_id, 1);
verifyEqual(testCase, result.participating_entity_ids, [1; 2]);

analysis = fetch(conn, "SELECT run_type, status FROM analysis_runs " + ...
    "WHERE run_key='att-detection'");
verifyEqual(testCase, string(analysis.run_type), "caller_attribution");
verifyEqual(testCase, string(analysis.status), "started");
run = fetch(conn, "SELECT attribution_path, method, " + ...
    "settings_profile_version_id, status, notes FROM attribution_runs");
verifyEqual(testCase, string(run.attribution_path), "imported");
verifyEqual(testCase, string(run.method), "External caller system 2.0");
verifyEqual(testCase, double(run.settings_profile_version_id), 1);
verifyEqual(testCase, string(run.status), "planned");
provenance = jsondecode(string(run.notes));
verifyEqual(testCase, string(provenance.schema), ...
    "vawlume.attribution.run_provenance.v1");
verifyEqual(testCase, double(provenance.participating_entity_ids(:)), [1; 2]);
verifyEqual(testCase, double(provenance.recording_entity_link_ids(:)), [1; 2]);
verifyEqual(testCase, double(provenance.source_file_ids), 4);
verifyEqual(testCase, double(provenance.artifact_ids), 1);
verifyEqual(testCase, double(provenance.external_stream_ids), 1);
verifyEqual(testCase, string(provenance.target_kind), "detections");
verifyEqual(testCase, double(provenance.target_ids(:)), [1; 2]);

profile = fetch(conn, "SELECT profile_version_id, assignment_role " + ...
    "FROM analysis_run_profiles");
verifyEqual(testCase, double(profile.profile_version_id), 1);
verifyEqual(testCase, string(profile.assignment_role), "attribution_settings");
input = fetch(conn, "SELECT extraction_run_id, input_role " + ...
    "FROM analysis_run_extraction_inputs WHERE analysis_run_id=" + ...
    string(result.analysis.analysis_run_id));
verifyEqual(testCase, double(input.extraction_run_id), 1);
verifyEqual(testCase, string(input.input_role), "target_event_set");
targets = fetch(conn, "SELECT detection_id FROM attribution_targets " + ...
    "ORDER BY detection_id");
verifyEqual(testCase, double(targets.detection_id), [1; 2]);
verifyNoScoringRows(testCase, conn);
end

function testConsensusRunAndPublicResolutionRecoverEventSetIdentity(testCase)
conn = testCase.TestData.conn;
target = struct(consensus_event_ids=[10 11]);
result = vawlume.attribution.createRun(conn, recordingRef(), ...
    nominalSpec("att-consensus", target), Apply=true);

verifyEqual(testCase, result.event_set.kind, "consensus_events");
verifyEqual(testCase, result.event_set.source_id, 10);
source = fetch(conn, "SELECT source_analysis_run_id, dependency_role " + ...
    "FROM analysis_run_sources");
verifyEqual(testCase, double(source.source_analysis_run_id), 10);
verifyEqual(testCase, string(source.dependency_role), "target_event_set");
inputs = fetch(conn, "SELECT COUNT(*) AS n FROM analysis_run_extraction_inputs " + ...
    "WHERE analysis_run_id=" + string(result.analysis.analysis_run_id));
verifyEqual(testCase, double(inputs.n), 0);

resolved = vawlume.attribution.resolveTargets(conn, ...
    struct(project_key="p1", run_key="att-consensus"), target);
verifyTrue(testCase, resolved.matches_stored);
verifyEqual(testCase, resolved.event_set.source_kind, "analysis_run");
verifyEqual(testCase, resolved.target_count, 2);
verifyEqual(testCase, resolved.targets.consensus_event_id, [10; 11]);
verifyEqual(testCase, resolved.run.participating_entity_ids, [1; 2]);
end

function testAgreementGroupRunRecordsChosenExtent(testCase)
conn = testCase.TestData.conn;
target = struct(agreement_group_ids=20, ...
    agreement_extent_method="intersection_boundary_of_members");
result = vawlume.attribution.createRun(conn, recordingRef(), ...
    nominalSpec("att-agreement", target), Apply=true);

verifyEqual(testCase, result.event_set.kind, "agreement_groups");
verifyEqual(testCase, result.event_set.source_id, 13);
verifyEqual(testCase, result.event_set.agreement_extent_method, ...
    "intersection_boundary_of_members");
stored = fetch(conn, "SELECT agreement_group_id, agreement_extent_method " + ...
    "FROM attribution_targets");
verifyEqual(testCase, double(stored.agreement_group_id), 20);
verifyEqual(testCase, string(stored.agreement_extent_method), ...
    "intersection_boundary_of_members");
end

function testPlanningWritesNothing(testCase)
conn = testCase.TestData.conn;
before = attributionCounts(conn);
result = vawlume.attribution.createRun(conn, recordingRef(), ...
    nominalSpec("att-plan", struct(detection_ids=[1 2])));

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyEqual(testCase, attributionCounts(conn), before);
end

function testIdenticalApplyReusesAndChangedTargetConflicts(testCase)
conn = testCase.TestData.conn;
spec = nominalSpec("att-reuse", struct(detection_ids=[1 2]));
first = vawlume.attribution.createRun(conn, recordingRef(), spec, Apply=true);
before = attributionCounts(conn);
again = vawlume.attribution.createRun(conn, recordingRef(), spec, Apply=true);

verifyEqual(testCase, again.status, "reused");
verifyEqual(testCase, again.run.attribution_run_id, ...
    first.run.attribution_run_id);
verifyEqual(testCase, attributionCounts(conn), before);

changed = spec;
changed.target_set = struct(detection_ids=1);
conflict = vawlume.attribution.createRun(conn, recordingRef(), changed);
verifyEqual(testCase, conflict.status, "conflict");
verifyTrue(testCase, conflict.has_conflicts);
verifyEqual(testCase, attributionCounts(conn), before);
end

function testTargetSetCrossingRecordingIsRefusedForThatReason(testCase)
verifyNamedError(testCase, @() vawlume.attribution.createRun( ...
    testCase.TestData.conn, recordingRef(), nominalSpec("cross-recording", ...
    struct(detection_ids=[1 3]))), ...
    "vawlume:attribution:TargetSetCrossesRecording");
end

function testTargetSetCrossingProjectIsRefusedForThatReason(testCase)
verifyNamedError(testCase, @() vawlume.attribution.createRun( ...
    testCase.TestData.conn, recordingRef(), nominalSpec("cross-project", ...
    struct(detection_ids=[1 4]))), ...
    "vawlume:attribution:TargetSetCrossesRecording");
end

function testMixedTargetKindsAreRefusedForThatReason(testCase)
mixed = struct(detection_ids=1, consensus_event_ids=10);
verifyNamedError(testCase, @() vawlume.attribution.createRun( ...
    testCase.TestData.conn, recordingRef(), nominalSpec("mixed-kind", mixed)), ...
    "vawlume:attribution:TargetSetMixed");
end

function testTwoDetectionEventSetsAreRefusedAsMixed(testCase)
verifyNamedError(testCase, @() vawlume.attribution.createRun( ...
    testCase.TestData.conn, recordingRef(), nominalSpec("mixed-source", ...
    struct(detection_ids=[1 5]))), ...
    "vawlume:attribution:TargetSetMixed");
end

function testUnlinkedParticipatingEntityIsRefusedForThatReason(testCase)
spec = nominalSpec("unlinked-entity", struct(detection_ids=1));
spec.participating_entity_ids = [1 3];
verifyNamedError(testCase, @() vawlume.attribution.createRun( ...
    testCase.TestData.conn, recordingRef(), spec), ...
    "vawlume:attribution:EntityNotInRecording");
end

function testEmptyTargetSetIsRefusedForThatReason(testCase)
verifyNamedError(testCase, @() vawlume.attribution.createRun( ...
    testCase.TestData.conn, recordingRef(), nominalSpec("empty-target", ...
    struct(detection_ids=[]))), ...
    "vawlume:attribution:TargetSetEmpty");
end

function testInducedTargetFailureRollsBackTheWholeRun(testCase)
conn = testCase.TestData.conn;
execute(conn, "CREATE TRIGGER trg_induced_attribution_failure " + ...
    "BEFORE INSERT ON attribution_targets FOR EACH ROW " + ...
    "WHEN NEW.detection_id=1 BEGIN " + ...
    "SELECT RAISE(ABORT,'induced attribution target failure'); END");

failed = false;
try
    vawlume.attribution.createRun(conn, recordingRef(), ...
        nominalSpec("atomic-failure", struct(detection_ids=[1 2])), Apply=true);
catch exception
    failed = contains(string(exception.message), ...
        "induced attribution target failure");
end
verifyTrue(testCase, failed, ...
    "The trigger must be reached and fail for its declared reason.");
verifyEqual(testCase, attributionCounts(conn), emptyCounts());
verifyEqual(testCase, string(conn.AutoCommit), "on");
end

% ---------------------------------------------------------------- helpers ---

function value = recordingRef()
value = struct(recording_id=1);
end

function value = nominalSpec(runKey, targetSet)
value = struct(run_key=runKey, attribution_path="imported", ...
    method="External caller system 2.0", ...
    settings_profile_version_id=1, target_set=targetSet, ...
    participating_entity_ids=[1 2], sources=struct( ...
        source_file_ids=4, artifact_ids=1, external_stream_ids=1), ...
    run_label="Synthetic attribution run", vawlume_version="prototype-v2", ...
    source_commit="fixture", notes="Synthetic Phase 4.4 fixture.");
end

function verifyNamedError(testCase, operation, identifier)
try
    operation();
    verifyFail(testCase, "Expected refusal " + identifier + ".");
catch exception
    verifyEqual(testCase, string(exception.identifier), identifier, ...
        "Refused, but not for its own reason: " + string(exception.message));
end
end

function verifyNoScoringRows(testCase, conn)
for tableName = ["attribution_candidates", "attribution_evidence", ...
        "attribution_decisions", "attribution_decision_candidates"]
    verifyEqual(testCase, countOf(conn, tableName), 0, tableName);
end
end

function value = attributionCounts(conn)
value = struct();
for tableName = ["analysis_runs", "analysis_run_profiles", ...
        "analysis_run_extraction_inputs", "analysis_run_sources", ...
        "attribution_runs", "attribution_targets"]
    value.(tableName) = countOf(conn, tableName);
end
% Subtract the four source analysis rows seeded for target fixtures.
value.analysis_runs = value.analysis_runs - 4;
% The agreement source records its participating extraction run.
value.analysis_run_extraction_inputs = ...
    value.analysis_run_extraction_inputs - 1;
end

function value = emptyCounts()
value = struct(analysis_runs=0, analysis_run_profiles=0, ...
    analysis_run_extraction_inputs=0, analysis_run_sources=0, ...
    attribution_runs=0, attribution_targets=0);
end

function value = countOf(conn, tableName)
row = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(row.n(1));
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES" + ...
    "(1,'p1','Project 1'),(2,'p2','Project 2')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES" + ...
    "(1,1,'recording_audio','r1.wav','r1.wav')," + ...
    "(2,1,'recording_audio','r2.wav','r2.wav')," + ...
    "(3,2,'recording_audio','r3.wav','r3.wav')," + ...
    "(4,1,'attribution_output','caller.csv','caller.csv')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1'),(2,1,2,'R2'),(3,2,3,'R3')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1),(2,2,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES" + ...
    "(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'C'),(4,2,2,'D')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES" + ...
    "(1,1,1,'participant'),(2,1,2,'participant')," + ...
    "(3,2,3,'participant'),(4,3,4,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key," + ...
    "profile_name,profile_kind) VALUES" + ...
    "(1,1,'caller-input','Caller input mapping','attribution_input_mapping')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id," + ...
    "version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1.0.0','json','config/caller.json'," + ...
    "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1)");
execute(conn, "INSERT INTO artifacts(artifact_id,project_id,source_file_id," + ...
    "artifact_type,path_or_uri,is_native) VALUES" + ...
    "(1,1,4,'attribution_output','caller.csv',1)");
execute(conn, "INSERT INTO timebases(timebase_id,project_id,timebase_name," + ...
    "timebase_kind,native_unit) VALUES(1,1,'video','external_clock','s')");
execute(conn, "INSERT INTO external_streams(external_stream_id,project_id," + ...
    "recording_id,timebase_id,stream_name,stream_kind) VALUES" + ...
    "(1,1,1,1,'tracking','tracking')");

execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak'),(2,'mu','MUPET')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1'),(2,2,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES" + ...
    "(1,1,1,'det-r1'),(2,1,1,'det-r2')," + ...
    "(3,2,1,'det-r3'),(4,1,2,'det-r1-other')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(1,1),(2,2),(3,3),(4,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES" + ...
    "(1,1,1,1,1.1),(2,1,1,2,2.1),(3,2,2,1,1.1)," + ...
    "(4,3,3,1,1.1),(5,4,1,3,3.1)");

execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type," + ...
    "run_key,status) VALUES" + ...
    "(10,1,'cross_extractor_matching','cons-r1','completed')," + ...
    "(11,1,'cross_extractor_matching','cons-r2','completed')," + ...
    "(12,1,'cross_extractor_matching','cons-r1-other','completed')," + ...
    "(13,1,'multi_extractor_agreement','agree-r1','completed')");
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
    "extraction_run_id,input_role) VALUES(13,1,'source')");
execute(conn, "INSERT INTO consensus_events(consensus_event_id,analysis_run_id," + ...
    "recording_id,start_time_s,end_time_s,derivation_method) VALUES" + ...
    "(10,10,1,1,1.1,'mean'),(11,10,1,2,2.1,'mean')," + ...
    "(12,11,2,1,1.1,'mean'),(13,12,1,3,3.1,'mean')");
execute(conn, "INSERT INTO agreement_groups(agreement_group_id,analysis_run_id," + ...
    "recording_id,group_key,derivation_method) VALUES" + ...
    "(20,13,1,'g20','connected_component')");
execute(conn, "INSERT INTO agreement_group_members(agreement_group_id,detection_id) " + ...
    "VALUES(20,1)");
end
