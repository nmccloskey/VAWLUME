function tests = test_path_parsing
tests = functiontests({ ...
    @testFolderDrivenProfileParsesLiteralsPathFilenameAndCorroboration, ...
    @testFilenameDrivenProfileNormalizesCapturedValue, ...
    @testDyadProfileEmitsSubjectRoles, ...
    @testWindowsAndPosixSeparatorsParseEquivalently, ...
    @testParserReportsNoMatchAmbiguityAndConflicts});
end

function testWindowsAndPosixSeparatorsParseEquivalently(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
loaded = loadProjectProfiles(repoRoot);
profile = profileById(loaded, "example.project.mouse_courtship.folder_driven");
posixSource = syntheticSource( ...
    "control/mouse_001/baseline/001_baseline_1.wav");
windowsSource = posixSource;
windowsSource.relative_path = replace( ...
    posixSource.relative_path, "/", string(char(92)));

posix = vawlume.source_mapping.parsePath(posixSource, profile);
windows = vawlume.source_mapping.parsePath(windowsSource, profile);

verifyEqual(testCase, windows.relative_path, posix.relative_path);
verifyEqual(testCase, windows.record_table, posix.record_table);
verifyEqual(testCase, windows.issue_table, posix.issue_table);

clear cleanupPath
end

function testFolderDrivenProfileParsesLiteralsPathFilenameAndCorroboration(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadProjectProfiles(repoRoot);
profile = profileById(loaded, "example.project.mouse_courtship.folder_driven");
root = temporaryRoot("VAWLUME folder parse");
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "control", "mouse_001", "courtship", "001_courtship_12.wav"));

source = vawlume.source_mapping.discoverSources(profile, root);
parsed = vawlume.source_mapping.parsePath(source, profile);
records = parsed.record_table;

verifyTrue(testCase, parsed.is_valid);
verifyEqual(testCase, valueFor(records, "study", ""), "courtship_pilot");
verifyEqual(testCase, valueFor(records, "group", ""), "control");
verifyEqual(testCase, valueFor(records, "animal", "subject_id"), "001");
verifyEqual(testCase, valueFor(records, "recording", "recording_take"), "12");
verifyTrue(testCase, any(string(parsed.issue_table.code) == "PATH_CAPTURE_CORROBORATED"));
verifyEqual(testCase, parsed.relative_path, "control/mouse_001/courtship/001_courtship_12.wav");

clear cleanupPath cleanupRoot
end

function testFilenameDrivenProfileNormalizesCapturedValue(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadProjectProfiles(repoRoot);
profile = profileById(loaded, "example.project.rat_self_admin.filename_driven");
root = temporaryRoot("VAWLUME filename parse");
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "OXY_PR_R03_SA07_001.wav"));

source = vawlume.source_mapping.discoverSources(profile, root);
parsed = vawlume.source_mapping.parsePath(source, profile);
records = parsed.record_table;

verifyTrue(testCase, parsed.is_valid);
verifyEqual(testCase, valueFor(records, "phenotype", "group_id"), "punishment_resistant");
verifyEqual(testCase, rawValueFor(records, "phenotype", "group_id"), "PR");
verifyTrue(testCase, contains(normalizationFor(records, "phenotype", "group_id"), ...
    ".value_map(1)"));
verifyEqual(testCase, valueFor(records, "recording", "segment_index"), "001");

clear cleanupPath cleanupRoot
end

function testDyadProfileEmitsSubjectRoles(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadProjectProfiles(repoRoot);
profile = profileById(loaded, "example.project.social_dyad.multi_subject");
root = temporaryRoot("VAWLUME dyad parse");
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "cohort_01", "dyad_004", "D004_M012_F031_courtship.wav"));

source = vawlume.source_mapping.discoverSources(profile, root);
parsed = vawlume.source_mapping.parsePath(source, profile);
records = parsed.record_table;

verifyTrue(testCase, parsed.is_valid);
verifyEqual(testCase, valueFor(records, "dyad", "interaction_unit_id"), "004");
verifyEqual(testCase, membershipValue(records, "male_partner"), "M012");
verifyEqual(testCase, membershipValue(records, "female_partner"), "F031");
verifyEqual(testCase, sort(string(records.relation_role(strlength(string(records.relation_role)) > 0))), ...
    ["female_partner"; "male_partner"]);

clear cleanupPath cleanupRoot
end

function testParserReportsNoMatchAmbiguityAndConflicts(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadProjectProfiles(repoRoot);
baseProfile = profileById(loaded, "example.project.mouse_courtship.folder_driven");

conflictRoot = temporaryRoot("VAWLUME conflict parse");
cleanupConflict = onCleanup(@() removeTree(conflictRoot));
touchFile(fullfile(conflictRoot, "control", "mouse_001", "courtship", "002_courtship_1.wav"));
conflictSource = vawlume.source_mapping.discoverSources(baseProfile, conflictRoot);
conflictParsed = vawlume.source_mapping.parsePath(conflictSource, baseProfile);
verifyTrue(testCase, any(string(conflictParsed.issue_table.code) == "PATH_CAPTURE_CONFLICT"));
verifyFalse(testCase, conflictParsed.is_valid);

missingSource = syntheticSource("orphan/001_baseline_1.wav");
missingParsed = vawlume.source_mapping.parsePath(missingSource, baseProfile);
verifyTrue(testCase, any(string(missingParsed.issue_table.code) == "PATH_RULE_NO_MATCH"));
verifyFalse(testCase, missingParsed.is_valid);

optionalProfile = baseProfile;
optionalProfile = setMappingField(optionalProfile, 2, "required", false);
optionalParsed = vawlume.source_mapping.parsePath(missingSource, optionalProfile);
verifyTrue(testCase, any(string(optionalParsed.issue_table.code) == "PATH_RULE_OPTIONAL_NO_MATCH"));

ambiguousProfile = baseProfile;
ambiguousProfile = setMappingField(ambiguousProfile, 2, "path_component_regex", "(mouse)");
ambiguousProfile = setMappingField(ambiguousProfile, 2, "capture_group", 1);
ambiguousSource = syntheticSource("mouse_mouse/mouse_001/courtship/001_courtship_1.wav");
ambiguousParsed = vawlume.source_mapping.parsePath(ambiguousSource, ambiguousProfile);
verifyTrue(testCase, any(string(ambiguousParsed.issue_table.code) == "PATH_RULE_AMBIGUOUS_MATCH"));
verifyFalse(testCase, ambiguousParsed.is_valid);

invalidRegexProfile = baseProfile;
invalidRegexProfile = setMappingField(invalidRegexProfile, 2, "path_component_regex", "(mouse");
invalidParsed = vawlume.source_mapping.parsePath( ...
    syntheticSource("control/mouse_001/courtship/001_courtship_1.wav"), ...
    invalidRegexProfile);
verifyTrue(testCase, any(string(invalidParsed.issue_table.code) == "PATH_RULE_INVALID_REGEX"));
verifyFalse(testCase, invalidParsed.is_valid);

clear cleanupPath cleanupConflict
end

function source = syntheticSource(relativePath)
relativePath = replace(string(relativePath), "\", "/");
[~, stem, extension] = fileparts(relativePath);
source = struct( ...
    source_key="source:" + relativePath, ...
    runtime_path=relativePath, ...
    relative_path=relativePath, ...
    filename=string(stem) + string(extension), ...
    extension=string(extension), ...
    declared_source_type="project_input", ...
    artifact_type="source_audio", ...
    discovery_rule_id="synthetic", ...
    discovery_rules="synthetic", ...
    discovery_globs="synthetic", ...
    duplicate_rule_count=1, ...
    issues=struct("severity", {}, "code", {}, "profile_location", {}, "message", {}));
end

function profile = setMappingField(profile, mappingIndex, field, value)
if iscell(profile.mappings)
    mapping = profile.mappings{mappingIndex};
    mapping.(char(field)) = value;
    profile.mappings{mappingIndex} = mapping;
else
    profile.mappings(mappingIndex).(char(field)) = value;
end
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

function value = valueFor(records, targetLevel, canonicalField)
matches = string(records.target_level) == targetLevel & ...
    string(records.canonical_field) == canonicalField;
value = string(records.normalized_value(find(matches, 1)));
end

function value = rawValueFor(records, targetLevel, canonicalField)
matches = string(records.target_level) == targetLevel & ...
    string(records.canonical_field) == canonicalField;
value = string(records.raw_value(find(matches, 1)));
end

function value = normalizationFor(records, targetLevel, canonicalField)
matches = string(records.target_level) == targetLevel & ...
    string(records.canonical_field) == canonicalField;
value = string(records.normalization_source(find(matches, 1)));
end

function value = membershipValue(records, relationRole)
matches = string(records.membership_level) == "animal" & ...
    string(records.relation_role) == relationRole & ...
    string(records.canonical_field) == "subject_id";
value = string(records.normalized_value(find(matches, 1)));
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
