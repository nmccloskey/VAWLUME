function tests = test_source_discovery
tests = functiontests({ ...
    @testNormalizeRelativePathPreservesRootIndependentSlashPath, ...
    @testNormalizeRelativePathRejectsOutsideRoot, ...
    @testDiscoverSourcesSortsDeduplicatesAndIgnoresExtras, ...
    @testDiscoveryRelativeIdentityIsStableAcrossRoots});
end

function testNormalizeRelativePathPreservesRootIndependentSlashPath(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

root = temporaryRoot("VAWLUME source root spaces");
cleanupRoot = onCleanup(@() removeTree(root));
audioPath = fullfile(root, "control", "mouse_001", "baseline", "001_baseline_1.wav");
touchFile(audioPath);

info = vawlume.source_mapping.normalizeRelativePath(audioPath, root);

verifyTrue(testCase, info.is_inside_root);
verifyEqual(testCase, info.relative_path, "control/mouse_001/baseline/001_baseline_1.wav");
verifyEqual(testCase, info.filename, "001_baseline_1.wav");
verifyEqual(testCase, info.extension, ".wav");
verifyFalse(testCase, contains(info.relative_path, "\"));
verifyNotEqual(testCase, info.runtime_path, info.relative_path);
if ispc
    verifyNotEmpty(testCase, regexp(char(info.source_root), '^[A-Za-z]:\\', 'once'));
end

clear cleanupPath cleanupRoot
end

function testNormalizeRelativePathRejectsOutsideRoot(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

root = temporaryRoot("VAWLUME source inside");
outsideRoot = temporaryRoot("VAWLUME source outside");
cleanupRoot = onCleanup(@() removeTree(root));
cleanupOutside = onCleanup(@() removeTree(outsideRoot));
outsideFile = fullfile(outsideRoot, "outside.wav");
touchFile(outsideFile);

verifyError(testCase, ...
    @() vawlume.source_mapping.normalizeRelativePath(outsideFile, root), ...
    "vawlume:source_mapping:PathOutsideRoot");

info = vawlume.source_mapping.normalizeRelativePath(outsideFile, root, ...
    MustBeInsideRoot=false);
verifyFalse(testCase, info.is_inside_root);
verifyEqual(testCase, string(info.issues(1).code), "SOURCE_PATH_OUTSIDE_ROOT");

clear cleanupPath cleanupRoot cleanupOutside
end

function testDiscoverSourcesSortsDeduplicatesAndIgnoresExtras(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadProjectProfiles(repoRoot);
profile = profileById(loaded, "example.project.rat_self_admin.filename_driven");
root = temporaryRoot("VAWLUME filename discovery");
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "OXY_PS_R11_SA09_001.wav"));
touchFile(fullfile(root, "nested", "OXY_PR_R03_SA07_002.wav"));
touchFile(fullfile(root, "OXY_PR_R03_SA07_001.wav"));
touchFile(fullfile(root, "ignored.txt"));

[sources, report] = vawlume.source_mapping.discoverSources(profile, root);

verifyEqual(testCase, [sources.relative_path]', [
    "OXY_PR_R03_SA07_001.wav"
    "OXY_PS_R11_SA09_001.wav"
    "nested/OXY_PR_R03_SA07_002.wav"
    ]);
verifyEqual(testCase, report.source_count, 3);
verifyEqual(testCase, report.scanned_file_count, 4);
verifyEqual(testCase, sources(1).duplicate_rule_count, 2);
verifyTrue(testCase, any(string(report.issue_table.code) == "SOURCE_DUPLICATE_DISCOVERY"));
verifyFalse(testCase, any(contains([sources.relative_path]', "ignored")));

clear cleanupPath cleanupRoot
end

function testDiscoveryRelativeIdentityIsStableAcrossRoots(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadProjectProfiles(repoRoot);
profile = profileById(loaded, "example.project.mouse_courtship.folder_driven");
rootA = temporaryRoot("VAWLUME root A");
rootB = temporaryRoot("VAWLUME root B");
cleanupA = onCleanup(@() removeTree(rootA));
cleanupB = onCleanup(@() removeTree(rootB));
relativePath = fullfile("control", "mouse_001", "courtship", "001_courtship_1.wav");
touchFile(fullfile(rootA, relativePath));
touchFile(fullfile(rootB, relativePath));

sourcesA = vawlume.source_mapping.discoverSources(profile, rootA);
sourcesB = vawlume.source_mapping.discoverSources(profile, rootB);

verifyEqual(testCase, sourcesA.relative_path, sourcesB.relative_path);
verifyNotEqual(testCase, sourcesA.runtime_path, sourcesB.runtime_path);
verifyEqual(testCase, sourcesA.source_key, sourcesB.source_key);

clear cleanupPath cleanupA cleanupB
end

function loaded = loadProjectProfiles(repoRoot)
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
loaded = vawlume.source_mapping.loadProfile(profilePath, ...
    ExpectedKind="project_input", RepoRoot=repoRoot);
end

function profile = profileById(loaded, profileId)
matches = loaded.profile_ids == profileId;
profile = loaded.profile_documents{find(matches, 1)};
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

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
