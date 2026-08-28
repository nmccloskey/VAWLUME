function tests = test_project_intake_entities
tests = functiontests({ ...
    @testAllProjectProfilesMaterializeEntityGraphs, ...
    @testRepeatedSourcesDeduplicateEntitiesAndPreserveEvidence});
end

function testAllProjectProfilesMaterializeEntityGraphs(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = projectProfilePath(repoRoot);
cases = {
    "example.project.mouse_courtship.folder_driven", ...
        fullfile("control", "mouse_001", "baseline", "001_baseline_1.wav"), ...
        4, 4, 3
    "example.project.rat_self_admin.filename_driven", ...
        "OXY_PR_R03_SA07_001.wav", 4, 4, 3
    "example.project.social_dyad.multi_subject", ...
        fullfile("cohort_01", "dyad_004", ...
        "D004_M012_F031_courtship.wav"), 5, 6, 5
    };

for caseIndex = 1:size(cases, 1)
    root = temporaryRoot();
    cleanupRoot = onCleanup(@() removeTree(root));
    touchFile(fullfile(root, cases{caseIndex, 2}));
    [conn, dbFile] = createDisposableDatabase(repoRoot);
    cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
    ir = vawlume.source_mapping.parse(profilePath, root, ...
        ProfileId=cases{caseIndex, 1}, RepoRoot=repoRoot);
    spec = struct( ...
        project_key="entity_integration_" + string(caseIndex), ...
        project_name="Entity integration " + string(caseIndex), ...
        description="Phase 3 entity integration case.");

    result = vawlume.ingest.project(conn, ir, spec, Apply=true);

    verifyEqual(testCase, result.status, "entity_graph_committed");
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM entity_types"), ...
        cases{caseIndex, 3});
    verifyEqual(testCase, scalar(conn, ...
        "SELECT COUNT(*) AS n FROM experimental_entities"), cases{caseIndex, 4});
    verifyEqual(testCase, scalar(conn, ...
        "SELECT COUNT(*) AS n FROM entity_relationships"), cases{caseIndex, 5});
    verifyEqual(testCase, result.relationship_summary.deferred, 1);
    verifyEqual(testCase, scalar(conn, ...
        "SELECT COUNT(*) AS n FROM entity_types WHERE hierarchy_order IS NOT NULL " + ...
        "OR is_biological_unit <> 0 OR is_subject_like <> 0"), 0);
    verifyEqual(testCase, scalar(conn, ...
        "SELECT COUNT(*) AS n FROM entity_relationships " + ...
        "WHERE source_locator IS NULL OR mapping_rule_key IS NULL"), 0);
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM source_files"), 0);
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM recordings"), 0);
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_runs"), 0);
    verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

    if cases{caseIndex, 1} == "example.project.social_dyad.multi_subject"
        memberships = fetch(conn, ...
            "SELECT er.relationship_type, er.role_label, child.native_id " + ...
            "FROM entity_relationships er " + ...
            "JOIN experimental_entities child ON child.entity_id = er.child_entity_id " + ...
            "WHERE er.relationship_type = 'has_member' ORDER BY er.role_label");
        verifyEqual(testCase, string(memberships.role_label), ...
            ["female_partner"; "male_partner"]);
        verifyEqual(testCase, string(memberships.native_id), ["F031"; "M012"]);
    end

    clear cleanupDb cleanupRoot
end
clear cleanupPath
end

function testRepeatedSourcesDeduplicateEntitiesAndPreserveEvidence(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
root = temporaryRoot();
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "control", "mouse_001", "baseline", ...
    "001_baseline_1.wav"));
touchFile(fullfile(root, "control", "mouse_001", "courtship", ...
    "001_courtship_1.wav"));
[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = vawlume.source_mapping.parse(projectProfilePath(repoRoot), root, ...
    ProfileId="example.project.mouse_courtship.folder_driven", ...
    RepoRoot=repoRoot);
spec = struct(project_key="cross_source_entity_test", ...
    project_name="Cross-source entity test", description="");

first = vawlume.ingest.project(conn, ir, spec, Apply=true);
second = vawlume.ingest.project(conn, ir, spec, Apply=true);

verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM entity_types"), 4);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM experimental_entities"), 5);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM entity_relationships"), 4);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM experimental_entities ee " + ...
    "JOIN entity_types et ON et.entity_type_id = ee.entity_type_id " + ...
    "WHERE et.native_name = 'animal' AND ee.native_id = '001'"), 1);
verifyEqual(testCase, height(first.entity_ids), 8);
animalIds = first.entity_ids.entity_id(contains(first.entity_ids.record_key, ...
    "|record:animal"));
verifyEqual(testCase, numel(unique(animalIds)), 1);
verifyEqual(testCase, first.relationship_summary.deferred, 2);
verifyTrue(testCase, any(first.plan.relationships.evidence_count == 2));
verifyTrue(testCase, all(strlength(first.plan.relationships.source_locator( ...
    first.plan.relationships.evidence_count > 1)) == 0));
verifyEqual(testCase, second.applied_counts.reused_entity_types, 4);
verifyEqual(testCase, second.applied_counts.reused_entities, 5);
verifyEqual(testCase, second.applied_counts.reused_entity_relationships, 4);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupPath cleanupRoot cleanupDb
end

function [conn, dbFile] = createDisposableDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
end

function root = temporaryRoot()
root = string(tempname);
mkdir(root);
end

function touchFile(path)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
fileId = fopen(path, "w");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "");
clear cleaner
end

function removeTree(root)
if isfolder(root)
    rmdir(root, "s");
end
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

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.n(1));
end

function path = projectProfilePath(repoRoot)
path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
