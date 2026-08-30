function tests = test_schema_creation
tests = functiontests({ ...
    @testFreshSchemaCreatesCoreObjects, ...
    @testFreshSchemaRejectsBasicInvalidRows});
end

function testFreshSchemaCreatesCoreObjects(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

summary = vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

verifyGreaterThan(testCase, summary.statements_executed, 0);
verifyEqual(testCase, string(firstValue(conn, "SELECT schema_version FROM schema_info")), "0.3-draft");
verifyEqual(testCase, double(firstValue(conn, "PRAGMA user_version")), 3);
verifyEqual(testCase, double(firstValue(conn, "PRAGMA foreign_keys")), 1);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

expectedTables = [
    "projects"
    "config_profiles"
    "config_profile_versions"
    "source_files"
    "entity_types"
    "experimental_entities"
    "recordings"
    "extractors"
    "extractor_versions"
    "extraction_runs"
    "extraction_run_inputs"
    "canonical_features"
    "extractor_features"
    "feature_mappings"
    "feature_relationships"
    "detections"
    "event_measurements"
    "candidate_pairs"
    "match_groups"
    "consensus_events"
    "consilience_assessments"
    "manual_reviews"
    "manual_reference_events"
    "agreement_statistics"
    "timebases"
    "external_streams"
    "external_stream_sources"
    "external_events"
    "external_event_attributes"
    "external_stream_coverage"
    "alignment_sets"
    "time_alignment_runs"
    "alignment_anchors"
    "alignment_anchor_observations"
    "alignment_anchor_residuals"
    "alignment_segments"
    "aligned_external_events"
];
expectedViews = [
    "v_detection_core"
    "v_recording_entity_context"
    "v_event_measurements_long"
    "v_match_group_members"
    "v_cross_extractor_feature_pairs"
    "v_external_events_aligned"
    "v_sequence_members"
];

verifyTrue(testCase, all(ismember(expectedTables, sqliteObjects(conn, "table"))));
verifyTrue(testCase, all(ismember(expectedViews, sqliteObjects(conn, "view"))));

clear cleanupPath cleanupDb summary
end

function testFreshSchemaRejectsBasicInvalidRows(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

execute(conn, "INSERT INTO projects(project_key, project_name) VALUES ('schema_test_project', 'Schema test project')");

verifySqlFails(testCase, conn, ...
    "INSERT INTO config_profiles(project_id, profile_key, profile_name, profile_kind) " + ...
    "VALUES (1, 'bad_profile', 'Bad profile', 'not_a_profile_kind')");

verifySqlFails(testCase, conn, ...
    "INSERT INTO config_profile_versions(profile_id, version_label, content_format, content_uri) " + ...
    "VALUES (9999, '1', 'yaml', 'missing.yaml')");

verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupPath cleanupDb
end

function [conn, dbFile] = createDisposableDatabase()
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
end

function value = firstValue(conn, sql)
rows = fetch(conn, sql);
column = rows.(rows.Properties.VariableNames{1});
if iscell(column)
    value = column{1};
else
    value = column(1);
end
end

function names = sqliteObjects(conn, objectType)
rows = fetch(conn, ...
    "SELECT name FROM sqlite_master WHERE type = " + sqlText(objectType) + " ORDER BY name");
if height(rows) == 0
    names = strings(0, 1);
else
    names = string(rows.name);
end
end

function verifySqlFails(testCase, conn, sql)
didFail = false;
try
    execute(conn, sql);
catch
    didFail = true;
end
verifyTrue(testCase, didFail, "Expected SQL statement to fail: " + sql);
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
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
