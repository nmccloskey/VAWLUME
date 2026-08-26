function tests = test_seed_registration
tests = functiontests({ ...
    @testRegisterBuiltinSemanticsIsIdempotent, ...
    @testRegisterBuiltinSemanticsRejectsConflicts});
end

function testRegisterBuiltinSemanticsIsIdempotent(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

first = vawlume.db.registerBuiltinSemantics(conn, repoRoot);
countsAfterFirst = semanticCounts(conn);
second = vawlume.db.registerBuiltinSemantics(conn, repoRoot);
countsAfterSecond = semanticCounts(conn);

verifyEqual(testCase, countsAfterFirst, countsAfterSecond);
verifyGreaterThan(testCase, first.inserted, 0);
verifyEqual(testCase, second.inserted, 0);
verifyGreaterThan(testCase, second.reused_existing, 0);
verifyEqual(testCase, tableValue(fetch(conn, "PRAGMA foreign_key_check"), "table"), string.empty(0, 1));

verifyEqual(testCase, countsAfterFirst.config_profiles, 2);
verifyEqual(testCase, countsAfterFirst.config_profile_versions, 2);
verifyEqual(testCase, countsAfterFirst.extractors, 2);
verifyEqual(testCase, countsAfterFirst.extractor_versions, 2);
verifyEqual(testCase, countsAfterFirst.canonical_features, 20);
verifyEqual(testCase, countsAfterFirst.extractor_features, 26);
verifyEqual(testCase, countsAfterFirst.feature_mappings, 26);
verifyEqual(testCase, countsAfterFirst.feature_relationships, 9);

clear cleanupPath cleanupDb first second
end

function testRegisterBuiltinSemanticsRejectsConflicts(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
countsBeforeConflict = semanticCounts(conn);

sourceProfile = fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.yaml");
conflictingProfile = fullfile(tempdir, "deepsqueak_output_mapping_profile_conflict.yaml");
text = fileread(sourceProfile);
text = replace(text, ...
    'name: "DeepSqueak v3.2 extractor-output mapping"', ...
    'name: "Conflicting DeepSqueak profile name"');
writeText(conflictingProfile, text);
cleanupProfile = onCleanup(@() deleteIfExists(conflictingProfile));

verifyError(testCase, ...
    @() vawlume.db.registerBuiltinSemantics(conn, repoRoot, ProfilePaths=conflictingProfile), ...
    "vawlume:db:SemanticConflict");
verifyEqual(testCase, semanticCounts(conn), countsBeforeConflict);

clear cleanupPath cleanupDb cleanupProfile
end

function [conn, dbFile] = createDisposableDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
executeSchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
end

function executeSchema(conn, schemaPath)
vawlume.db.applySchema(conn, schemaPath);
end

function counts = semanticCounts(conn)
tables = [
    "config_profiles"
    "config_profile_versions"
    "extractors"
    "extractor_versions"
    "canonical_features"
    "extractor_features"
    "feature_mappings"
    "feature_relationships"
];
counts = struct();
for tableName = tables'
    result = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
    counts.(tableName) = double(result.n(1));
end
end

function value = tableValue(tableData, variableName)
if height(tableData) == 0
    value = string.empty(0, 1);
else
    value = string(tableData.(variableName));
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

function writeText(path, text)
fileId = fopen(path, "w");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
clear cleaner
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
