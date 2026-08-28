function tests = test_project_entity_ingest
tests = functiontests({ ...
    @testEntityPlanUsesRecordScopeAndDefersRecordingEdge, ...
    @testEntityGraphApplyIsIdempotent, ...
    @testEntityGraphApplyRollsBackLateFailure, ...
    @testEntityTypeSemanticCollisionIsConflict, ...
    @testContradictoryRelationshipIsConflict});
end

function testEntityPlanUsesRecordScopeAndDefersRecordingEdge(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

result = vawlume.ingest.project(conn, entityIR(), projectSpec());

verifyEqual(testCase, height(result.plan.entity_types), 3);
verifyEqual(testCase, result.plan.entity_types.native_name, ...
    ["animal"; "session"; "study"]);
verifyEqual(testCase, height(result.plan.entities), 3);
verifyEqual(testCase, height(result.plan.entity_records), 3);
verifyEqual(testCase, height(result.plan.relationships), 2);
verifyEqual(testCase, height(result.plan.relationship_evidence), 2);
verifyEqual(testCase, height(result.plan.deferred_relationships), 1);
verifyEqual(testCase, ...
    result.plan.deferred_relationships.defer_reason, "non_entity_endpoint");
verifyFalse(testCase, any(result.plan.entity_types.native_name == "recording"));
verifyEqual(testCase, unique(result.plan.relationships.relationship_type), ...
    "contains");
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM projects"), 0);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testEntityGraphApplyIsIdempotent(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = entityIR();

first = vawlume.ingest.project(conn, ir, projectSpec(), Apply=true);
countsAfterFirst = graphCounts(conn);
second = vawlume.ingest.project(conn, ir, projectSpec(), Apply=true);
countsAfterSecond = graphCounts(conn);

verifyEqual(testCase, first.status, "completed");
verifyTrue(testCase, first.committed);
verifyEqual(testCase, first.project_id, ...
    scalar(conn, "SELECT project_id AS n FROM projects"));
verifyEqual(testCase, first.applied_counts.projects, 1);
verifyEqual(testCase, first.applied_counts.entity_types, 3);
verifyEqual(testCase, first.applied_counts.entities, 3);
verifyEqual(testCase, first.applied_counts.entity_relationships, 2);
verifyEqual(testCase, first.applied_counts.source_files, 1);
verifyEqual(testCase, first.applied_counts.recordings, 1);
verifyEqual(testCase, first.applied_counts.recording_entity_links, 2);
verifyEqual(testCase, height(first.entity_ids), 3);
verifyTrue(testCase, all(~isnan(first.entity_ids.entity_id)));
verifyEqual(testCase, second.status, "completed");
verifyTrue(testCase, second.committed);
verifyEqual(testCase, second.applied_counts.reused_projects, 1);
verifyEqual(testCase, second.applied_counts.reused_entity_types, 3);
verifyEqual(testCase, second.applied_counts.reused_entities, 3);
verifyEqual(testCase, second.applied_counts.reused_entity_relationships, 2);
verifyEqual(testCase, second.applied_counts.reused_source_files, 1);
verifyEqual(testCase, second.applied_counts.reused_recordings, 1);
verifyEqual(testCase, second.applied_counts.reused_recording_entity_links, 2);
verifyEqual(testCase, countsAfterFirst, struct( ...
    projects=1, entity_types=3, entities=3, relationships=2, ...
    source_files=1, recordings=1, recording_links=2, ingestion_runs=1));
verifyEqual(testCase, countsAfterSecond, struct( ...
    projects=1, entity_types=3, entities=3, relationships=2, ...
    source_files=1, recordings=1, recording_links=2, ingestion_runs=2));
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testEntityGraphApplyRollsBackLateFailure(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
execute(conn, "CREATE TRIGGER force_entity_relationship_failure " + ...
    "BEFORE INSERT ON entity_relationships BEGIN " + ...
    "SELECT RAISE(ABORT, 'forced relationship failure'); END");

didThrow = false;
try
    vawlume.ingest.project(conn, entityIR(), projectSpec(), Apply=true);
catch exception
    didThrow = true;
    verifyTrue(testCase, contains(string(exception.message), ...
        "forced relationship failure"));
end

verifyTrue(testCase, didThrow);
verifyEqual(testCase, string(conn.AutoCommit), "on");
verifyEqual(testCase, graphCounts(conn), struct( ...
    projects=0, entity_types=0, entities=0, relationships=0, ...
    source_files=0, recordings=0, recording_links=0, ingestion_runs=0));
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testEntityTypeSemanticCollisionIsConflict(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
projectId = insertProject(conn, projectSpec());
execute(conn, "INSERT INTO entity_types(" + ...
    "project_id, native_name, canonical_role) VALUES (" + ...
    string(projectId) + ", 'animal', 'incompatible_role')");

result = vawlume.ingest.project(conn, entityIR(), projectSpec(), Apply=true);

verifyEqual(testCase, result.status, "conflict");
verifyFalse(testCase, result.committed);
animal = result.plan.entity_types(result.plan.entity_types.native_name == "animal", :);
verifyEqual(testCase, animal.action, "conflict");
verifyTrue(testCase, any(result.issues.code == "ENTITY_TYPE_CONFLICT"));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM experimental_entities"), 0);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testContradictoryRelationshipIsConflict(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = entityIR();
vawlume.ingest.project(conn, ir, projectSpec(), Apply=true);
ir.relationships.canonical_relationship(1) = "associated_with";

result = vawlume.ingest.project(conn, ir, projectSpec(), Apply=true);

verifyEqual(testCase, result.status, "conflict");
verifyFalse(testCase, result.committed);
verifyTrue(testCase, any(result.issues.code == ...
    "ENTITY_RELATIONSHIP_CONFLICT"));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM entity_relationships"), 2);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function ir = entityIR()
sourceKey = "source:audio/session_01/call.wav";
checksum = string(repmat('a', 1, 64));
ir = struct();
ir.profile = struct( ...
    profile_key="example.project.entity.test", ...
    profile_name="Project entity test profile", ...
    profile_kind="project_input", ...
    profile_version="0.1.0", ...
    profile_schema_version="0.2-draft", ...
    profile_content_format="json", ...
    profile_path="config/project_entity_test.json", ...
    profile_runtime_path="C:/repo/config/project_entity_test.json", ...
    profile_checksum=checksum);
ir.sources = table( ...
    sourceKey, "C:/runtime/project/audio/session_01/call.wav", ...
    "audio/session_01/call.wav", "call.wav", "project_file", ...
    "rule.audio", "recording_audio", "mapped", "", ...
    VariableNames=["source_key", "runtime_path", "relative_path", ...
    "filename", "source_type", "discovery_rule", "artifact_type", ...
    "status", "checksum_sha256"]);
ir.records = table( ...
    [sourceKey + "|record:study"; sourceKey + "|record:animal"; ...
    sourceKey + "|record:session"; sourceKey + "|record:recording"], ...
    repmat(sourceKey, 4, 1), ...
    ["study"; "animal"; "session"; "recording"], ...
    ["study"; "subject"; "session"; "recording"], ...
    ["study_01"; "A01"; "S01"; "audio/session_01/call.wav"], ...
    ["entity"; "entity"; "entity"; "source_recording"], ...
    strings(4, 1), ...
    ["rule.study"; "rule.animal"; "rule.session"; "rule.recording"], ...
    repmat("mapped", 4, 1), ...
    VariableNames=["record_key", "source_key", "native_level", ...
    "canonical_level", "native_identifier", "record_scope", "role_label", ...
    "mapping_rule", "status"]);
ir.relationships = table( ...
    [sourceKey + "|relationship:study_animal"; ...
    sourceKey + "|relationship:animal_session"; ...
    sourceKey + "|relationship:session_recording"], ...
    repmat(sourceKey, 3, 1), ...
    [sourceKey + "|record:study"; sourceKey + "|record:animal"; ...
    sourceKey + "|record:session"], ...
    [sourceKey + "|record:animal"; sourceKey + "|record:session"; ...
    sourceKey + "|record:recording"], ...
    repmat("parent", 3, 1), repmat("contains", 3, 1), ...
    strings(3, 1), ["rule.rel.1"; "rule.rel.2"; "rule.rel.3"], ...
    repmat("mapped", 3, 1), ...
    VariableNames=["relationship_key", "source_key", "from_record_key", ...
    "to_record_key", "native_relationship", "canonical_relationship", ...
    "role_label", "mapping_rule", "status"]);
ir.valid_for_ingest = true;
end

function value = projectSpec()
value = struct(project_key="entity_test_project", ...
    project_name="Entity test project", description="Entity graph test.");
end

function [conn, dbFile, repoRoot] = createDisposableDatabase()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
end

function id = insertProject(conn, spec)
execute(conn, "INSERT INTO projects(project_key, project_name, description) VALUES (" + ...
    sqlText(spec.project_key) + ", " + sqlText(spec.project_name) + ", " + ...
    sqlText(spec.description) + ")");
id = scalar(conn, "SELECT last_insert_rowid() AS n");
end

function counts = graphCounts(conn)
counts = struct( ...
    projects=scalar(conn, "SELECT COUNT(*) AS n FROM projects"), ...
    entity_types=scalar(conn, "SELECT COUNT(*) AS n FROM entity_types"), ...
    entities=scalar(conn, "SELECT COUNT(*) AS n FROM experimental_entities"), ...
    relationships=scalar(conn, "SELECT COUNT(*) AS n FROM entity_relationships"), ...
    source_files=scalar(conn, "SELECT COUNT(*) AS n FROM source_files"), ...
    recordings=scalar(conn, "SELECT COUNT(*) AS n FROM recordings"), ...
    recording_links=scalar(conn, ...
    "SELECT COUNT(*) AS n FROM recording_entity_links"), ...
    ingestion_runs=scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_runs"));
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.n(1));
end

function value = sqlText(value)
value = "'" + replace(string(value), "'", "''") + "'";
end

function cleanupDatabase(conn, dbFile)
if isopen(conn)
    close(conn);
end
deleteIfExists(dbFile);
deleteIfExists(dbFile + "-journal");
deleteIfExists(dbFile + "-wal");
deleteIfExists(dbFile + "-shm");
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
