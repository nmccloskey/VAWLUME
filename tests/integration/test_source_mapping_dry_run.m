function tests = test_source_mapping_dry_run
tests = functiontests({ ...
    @testProjectPreviewShowsHierarchyRolesAndVerdict, ...
    @testExtractorPreviewsSummarizeShippedMappings, ...
    @testInvalidIRProducesNotReadyVerdict, ...
    @testDryRunIsDeterministicAndPortableAcrossRoots, ...
    @testDryRunDoesNotWriteToPhase1Database});
end

function testProjectPreviewShowsHierarchyRolesAndVerdict(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
root = temporaryRoot("VAWLUME dry run dyad");
cleanupRoot = onCleanup(@() removeTree(root));
relativePath = fullfile("cohort_01", "dyad_004", ...
    "D004_M012_F031_courtship.wav");
touchFile(fullfile(root, relativePath));

ir = vawlume.source_mapping.parse(projectProfilePath(repoRoot), root, ...
    ProfileId="example.project.social_dyad.multi_subject", RepoRoot=repoRoot);
before = ir;
report = vawlume.source_mapping.preview(ir);

verifyEqual(testCase, ir, before);
verifyEqual(testCase, report.verdict, "READY FOR INGEST");
verifyTrue(testCase, report.ir_derived);
verifyEqual(testCase, report.header.profile_key, ...
    "example.project.social_dyad.multi_subject");
verifyEqual(testCase, report.discovery.source_count, 1);
verifyTrue(testCase, isnan(report.discovery.ignored_source_count));
verifyEqual(testCase, height(report.project_hierarchy), 1);
verifyTrue(testCase, ismember("subject__male_partner", ...
    string(report.project_hierarchy.Properties.VariableNames)));
verifyTrue(testCase, ismember("subject__female_partner", ...
    string(report.project_hierarchy.Properties.VariableNames)));
verifyEqual(testCase, report.project_hierarchy.subject__male_partner, "M012");
verifyEqual(testCase, report.project_hierarchy.subject__female_partner, "F031");
verifyTrue(testCase, contains(report.text, "role=male_partner"));
verifyTrue(testCase, contains(report.text, "VERDICT: READY FOR INGEST"));

printed = evalc("vawlume.source_mapping.preview(ir, Print=true);");
verifyTrue(testCase, contains(string(printed), "VAWLUME SOURCE-MAPPING DRY RUN"));

clear cleanupPath cleanupRoot
end

function testExtractorPreviewsSummarizeShippedMappings(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

deepSqueak = vawlume.source_mapping.mapTableToIR( ...
    deepSqueakTable(), extractorProfilePath(repoRoot, "deepsqueak"), ...
    SourceKey="extractor:deepsqueak:dry_run", ...
    RelativePath="exports/calls_001_Stats.xlsx", RepoRoot=repoRoot);
deepSqueakReport = vawlume.source_mapping.preview(deepSqueak);
verifyEqual(testCase, deepSqueakReport.verdict, "READY FOR INGEST");
verifyEqual(testCase, height(deepSqueakReport.table_mapping), 1);
verifyEqual(testCase, deepSqueakReport.table_mapping.source_rows, 2);
verifyGreaterThan(testCase, deepSqueakReport.table_mapping.fields_found, 0);
verifyTrue(testCase, contains(deepSqueakReport.table_mapping.transforms_applied, ...
    "kHz_to_Hz"));
verifyTrue(testCase, contains(deepSqueakReport.table_mapping.canonical_fields, ...
    "contour_median_frequency"));

mupet = vawlume.source_mapping.mapTableToIR( ...
    mupetTable(), extractorProfilePath(repoRoot, "mupet"), ...
    SourceKey="extractor:mupet:dry_run", ...
    RelativePath="audio/dataset/CSV/recording.csv", RepoRoot=repoRoot);
mupetReport = vawlume.source_mapping.preview(mupet);
verifyEqual(testCase, mupetReport.verdict, "READY FOR INGEST");
verifyEqual(testCase, mupetReport.table_mapping.missing_value_normalizations, 1);
verifyTrue(testCase, contains(mupetReport.table_mapping.transforms_applied, "ms_to_s"));
verifyTrue(testCase, any(mupetReport.issue_summary.code == "MISSING_TOKEN_NORMALIZED"));
verifyTrue(testCase, contains(mupetReport.text, "TABLE MAPPING"));

clear cleanupPath
end

function testInvalidIRProducesNotReadyVerdict(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
root = temporaryRoot("VAWLUME dry run empty");
cleanupRoot = onCleanup(@() removeTree(root));

ir = vawlume.source_mapping.parse(projectProfilePath(repoRoot), root, ...
    ProfileId="example.project.mouse_courtship.folder_driven", RepoRoot=repoRoot);
report = vawlume.source_mapping.preview(ir);

verifyFalse(testCase, ir.valid_for_ingest);
verifyEqual(testCase, report.verdict, "NOT READY FOR INGEST");
verifyEqual(testCase, report.discovery.unmatched_count, 1);
verifyTrue(testCase, any(report.issue_summary.code == "SOURCE_NOT_FOUND" & ...
    report.issue_summary.count == 1));
verifyTrue(testCase, contains(report.text, "VERDICT: NOT READY FOR INGEST"));

clear cleanupPath cleanupRoot
end

function testDryRunIsDeterministicAndPortableAcrossRoots(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
rootA = temporaryRoot("VAWLUME portable A");
rootB = temporaryRoot("VAWLUME portable B");
cleanupA = onCleanup(@() removeTree(rootA));
cleanupB = onCleanup(@() removeTree(rootB));
relativePath = fullfile("control", "mouse_001", "baseline", ...
    "001_baseline_1.wav");
touchFile(fullfile(rootA, relativePath));
touchFile(fullfile(rootB, relativePath));
profilePath = projectProfilePath(repoRoot);

first = vawlume.source_mapping.parse(profilePath, rootA, ...
    ProfileId="example.project.mouse_courtship.folder_driven", RepoRoot=repoRoot);
repeat = vawlume.source_mapping.parse(profilePath, rootA, ...
    ProfileId="example.project.mouse_courtship.folder_driven", RepoRoot=repoRoot);
relocated = vawlume.source_mapping.parse(profilePath, rootB, ...
    ProfileId="example.project.mouse_courtship.folder_driven", RepoRoot=repoRoot);

verifyEqual(testCase, first, repeat);
firstPortable = withoutRuntimePaths(first);
relocatedPortable = withoutRuntimePaths(relocated);
verifyEqual(testCase, firstPortable, relocatedPortable);
verifyEqual(testCase, vawlume.source_mapping.preview(first).text, ...
    vawlume.source_mapping.preview(relocated).text);

clear cleanupPath cleanupA cleanupB
end

function testDryRunDoesNotWriteToPhase1Database(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
[conn, dbFile] = createFixtureDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
root = temporaryRoot("VAWLUME no database write");
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "OXY_PR_R03_SA07_001.wav"));

beforeCounts = databaseCounts(conn);
beforeForeignKeys = fetch(conn, "PRAGMA foreign_key_check");
ir = vawlume.source_mapping.parse(projectProfilePath(repoRoot), root, ...
    ProfileId="example.project.rat_self_admin.filename_driven", RepoRoot=repoRoot);
report = vawlume.source_mapping.preview(ir);
afterCounts = databaseCounts(conn);
afterForeignKeys = fetch(conn, "PRAGMA foreign_key_check");

verifyEqual(testCase, report.verdict, "READY FOR INGEST");
verifyEqual(testCase, afterCounts, beforeCounts);
verifyEqual(testCase, afterForeignKeys, beforeForeignKeys);
verifyEmpty(testCase, afterForeignKeys);

clear cleanupPath cleanupDb cleanupRoot
end

function ir = withoutRuntimePaths(ir)
ir.sources.runtime_path(:) = "";
end

function counts = databaseCounts(conn)
rows = fetch(conn, ...
    "SELECT name FROM sqlite_master WHERE type = 'table' " + ...
    "AND name NOT LIKE 'sqlite_%' ORDER BY name");
names = string(rows.name);
values = NaN(numel(names), 1);
for index = 1:numel(names)
    result = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(index));
    values(index) = double(result.n(1));
end
counts = table(names, values, VariableNames=["table_name", "row_count"]);
end

function [conn, dbFile] = createFixtureDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
[conn, ~] = vawlume.db.createPhase1FixtureDatabase(dbFile, repoRoot);
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

function path = projectProfilePath(repoRoot)
path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
end

function path = extractorProfilePath(repoRoot, name)
path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", name, name + "_output_mapping_profile.json");
end

function tbl = deepSqueakTable()
tbl = table( ...
    ["calls_001.mat"; "calls_001.mat"], [1; 2], ["USV"; "Noise"], [1; 0], ...
    [0.95; 0.10], [0.100; 0.200], [0.148; 0.245], [0.048; 0.045], ...
    [55; 60], [40; 42], [80; 82], [40; 40], [4.5; 4.7], [2.1; 2.2], ...
    [76; 77], [1.2; 1.3], [-35; -33], [0.8; 0.6], ...
    VariableNames=[
    "File"
    "ID"
    "Label"
    "Accepted"
    "Score"
    "Begin Time (s)"
    "End Time (s)"
    "Call Length (s)"
    "Principal Frequency (kHz)"
    "Low Freq (kHz)"
    "High Freq (kHz)"
    "Delta Freq (kHz)"
    "Frequency Standard Deviation (kHz)"
    "Slope (kHz/s)"
    "Peak Freq (kHz)"
    "Sinuosity"
    "Mean Power (dB/Hz)"
    "Tonality"
    ]);
end

function tbl = mupetTable()
tbl = table( ...
    [1; 2], [0.100; 0.200], [0.148; 0.250], ["0.052"; "NA"], ...
    [48; 50], [45; 46], [60; 61], [40; 41], [75; 76], [55; 56], ...
    [35; 35], [12.5; 13.0], [-18; -17], ...
    VariableNames=[
    "Syllable number"
    "Syllable start time (sec)"
    "Syllable end time (sec)"
    "inter-syllable interval (sec)"
    "syllable duration (msec)"
    "starting frequency (kHz)"
    "final frequency (kHz)"
    "minimum frequency (kHz)"
    "maximum frequency (kHz)"
    "mean frequency (kHz)"
    "frequency bandwidth (kHz)"
    "total syllable energy (dB)"
    "peak syllable amplitude (dB)"
    ]);
end

function root = temporaryRoot(label)
root = fullfile(tempdir, char(label + " " + string(java.util.UUID.randomUUID)));
mkdir(root);
end

function touchFile(path)
folder = fileparts(path);
if ~isfolder(folder)
    mkdir(folder);
end
fileId = fopen(path, "w");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "");
clear cleaner
end

function removeTree(path)
if isfolder(path)
    rmdir(path, "s");
end
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
