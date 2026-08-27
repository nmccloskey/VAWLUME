function tests = test_mapping_profile_loading
tests = functiontests({ ...
    @testLoadsEveryShippedMappingProfile, ...
    @testProfileChecksumsAreStable, ...
    @testKindSpecificStructureIsRequired, ...
    @testExplicitProfileContentVersionsArePreserved, ...
    @testRejectsMalformedJson, ...
    @testRejectsDuplicateJsonMembers, ...
    @testRejectsMissingProfileIdentity, ...
    @testRejectsUnsupportedSchemaVersion, ...
    @testRejectsInvalidRegex, ...
    @testRejectsPythonStyleNamedCapture, ...
    @testRejectsInheritanceDeclarations});
end

function testProfileChecksumsAreStable(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");

first = vawlume.source_mapping.loadProfile(profilePath, RepoRoot=repoRoot);
second = vawlume.source_mapping.loadProfile(profilePath, RepoRoot=repoRoot);

verifyEqual(testCase, first.checksum_sha256, second.checksum_sha256);
verifyEqual(testCase, strlength(first.checksum_sha256), 64);

clear cleanupPath
end

function testKindSpecificStructureIsRequired(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

extractor = struct();
extractor.profile = profileEnvelope("missing.extractor.mappings", "extractor_output");
extractor.extractor = struct(name="SyntheticExtractor");
extractor.field_mapping_source = struct(artifact_key="events");
extractorReport = vawlume.source_mapping.validateProfile( ...
    extractor, ExpectedKind="extractor_output");
verifyFalse(testCase, extractorReport.is_valid);
verifyTrue(testCase, any(issueCodes(extractorReport) == "PROFILE_MISSING_FIELD"));

project = struct();
project.profile = profileEnvelope("missing.project.structure", "project_input");
project.source = struct(root="<PROJECT_ROOT>", include=struct(glob="*.wav"));
projectReport = vawlume.source_mapping.validateProfile( ...
    project, ExpectedKind="project_input");
verifyFalse(testCase, projectReport.is_valid);
verifyTrue(testCase, any(issueCodes(projectReport) == "PROFILE_MISSING_FIELD"));

clear cleanupPath
end

function testLoadsEveryShippedMappingProfile(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

extractorProfiles = [
    "config/01_mapping_profiles/extractors/deepsqueak/deepsqueak_output_mapping_profile.json"
    "config/01_mapping_profiles/extractors/mupet/mupet_output_mapping_profile.json"
];

for index = 1:numel(extractorProfiles)
    [loaded, report] = vawlume.source_mapping.loadProfile( ...
        fullfile(repoRoot, extractorProfiles(index)), ...
        ExpectedKind="extractor_output", ...
        RepoRoot=repoRoot);
    verifyTrue(testCase, report.is_valid);
    verifyEqual(testCase, report.error_count, 0);
    verifyEqual(testCase, loaded.profile_count, 1);
    verifyEqual(testCase, loaded.profile_kinds, "extractor_output");
    verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
    verifyEqual(testCase, loaded.relative_path, replace(extractorProfiles(index), filesep, "/"));
    verifyEqual(testCase, strlength(loaded.checksum_sha256), 64);
    verifyGreaterThan(testCase, numel(loaded.field_mappings), 0);
    verifyFalse(testCase, any(issueCodes(report) == "PROFILE_VERSION_DERIVED_FROM_EXTRACTOR"));
end

projectPath = fullfile(repoRoot, ...
    "config", "01_mapping_profiles", "project_inputs", ...
    "project_input_source_mapping_examples.json");
[loaded, report] = vawlume.source_mapping.loadProfile( ...
    projectPath, ExpectedKind="project_input", RepoRoot=repoRoot);

verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, report.error_count, 0);
verifyEqual(testCase, loaded.profile_count, 3);
verifyEqual(testCase, numel(loaded.profiles), 3);
verifyTrue(testCase, all(loaded.profile_kinds == "project_input"));
verifyTrue(testCase, all(loaded.profile_version_labels == "0.1.0"));
verifyEqual(testCase, loaded.profile_ids(1), ...
    "example.project.mouse_courtship.folder_driven");
verifyFalse(testCase, any(issueCodes(report) == ...
    "PROFILE_REGEX_PYTHON_NAMED_CAPTURE_COMPATIBILITY"));

clear cleanupPath
end

function testExplicitProfileContentVersionsArePreserved(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = fullfile(repoRoot, ...
    "config", "01_mapping_profiles", "extractors", "deepsqueak", ...
    "deepsqueak_output_mapping_profile.json");
[loaded, report] = vawlume.source_mapping.loadProfile( ...
    profilePath, ExpectedKind="extractor_output", RepoRoot=repoRoot);

verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
verifyEqual(testCase, string(loaded.document.extractor.version_scope.preferred), "3.2.x");
verifyFalse(testCase, any(issueCodes(report) == ...
    "PROFILE_VERSION_DERIVED_FROM_EXTRACTOR"));
verifyFalse(testCase, any(issueCodes(report) == "PROFILE_VERSION_MISSING"));
verifyEmpty(testCase, loaded.warnings);

clear cleanupPath
end

function testRejectsMalformedJson(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryJsonText('{"profile": [unterminated');
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath), ...
    "vawlume:source_mapping:ProfileLoadFailed");

clear cleanupPath cleanupProfile
end

function testRejectsDuplicateJsonMembers(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryJsonText('{"profile":{"id":"first","id":"second"}}');
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath), ...
    "vawlume:source_mapping:ProfileLoadFailed");

clear cleanupPath cleanupProfile
end

function testRejectsMissingProfileIdentity(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

document = validExtractorDocument("0.1-draft");
document.profile = rmfield(document.profile, "id");
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:MissingProfileField");

clear cleanupPath cleanupProfile
end

function testRejectsUnsupportedSchemaVersion(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryJsonDocument(validExtractorDocument("9.9-future"));
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:UnsupportedProfileSchemaVersion");

clear cleanupPath cleanupProfile
end

function testRejectsInvalidRegex(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

entry = struct();
entry.profile = profileEnvelope("bad.regex.project", "project_input");
entry.source = struct(root="<PROJECT_ROOT>", include=struct(glob={{"*.wav"}}));
entry.hierarchy = struct(levels={{struct( ...
    native_name="recording", canonical_role="recording")}});
entry.mappings = {struct( ...
    target_level="recording", ...
    source_type="filename", ...
    filename_regex="[", ...
    captures=struct(recording=struct(canonical_field="recording_id")))};
document = struct(profiles={{entry}});
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="project_input"), ...
    "vawlume:source_mapping:InvalidProfileRegex");

clear cleanupPath cleanupProfile
end

function testRejectsPythonStyleNamedCapture(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

entry = minimalProjectEntry("bad.python.regex.project");
entry.mappings = {struct( ...
    target_level="recording", ...
    source_type="filename", ...
    filename_regex="^(?P<recording>\d+)\.wav$", ...
    captures=struct(recording=struct(canonical_field="recording_id")))};
document = struct(profiles={{entry}});
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="project_input"), ...
    "vawlume:source_mapping:InvalidProfileRegex");

clear cleanupPath cleanupProfile
end

function testRejectsInheritanceDeclarations(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

entry = minimalProjectEntry("bad.inherit.project");
entry.extends = "base.project.profile";
entry.mappings = {struct( ...
    target_level="recording", source_type="literal", value="rec1")};
document = struct(profiles={{entry}});
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="project_input"), ...
    "vawlume:source_mapping:UnsupportedProfileInheritance");

clear cleanupPath cleanupProfile
end

function entry = minimalProjectEntry(id)
entry = struct();
entry.profile = profileEnvelope(id, "project_input");
entry.source = struct(root="<PROJECT_ROOT>", include=struct(glob={{"*.wav"}}));
entry.hierarchy = struct(levels={{struct( ...
    native_name="recording", canonical_role="recording")}});
end

function document = validExtractorDocument(schemaVersion)
document = struct();
document.profile = profileEnvelope("synthetic.extractor.output", "extractor_output");
document.profile.profile_schema_version = schemaVersion;
document.extractor = struct( ...
    name="SyntheticExtractor", ...
    version_scope=struct(preferred="1"));
document.field_mapping_source = struct(artifact_key="event_table");
document.field_mappings = {struct( ...
    source_field="Value", ...
    target_level="event_measurement", ...
    canonical_field="value", ...
    data_type="float")};
end

function profile = profileEnvelope(id, kind)
profile = struct( ...
    id=string(id), ...
    name="Synthetic profile", ...
    kind=string(kind), ...
    profile_schema_version="0.1-draft");
end

function codes = issueCodes(report)
if isempty(report.issue_table)
    codes = strings(0, 1);
else
    codes = string(report.issue_table.code);
end
end

function path = temporaryJsonDocument(document)
path = temporaryJsonText(jsonencode(document));
end

function path = temporaryJsonText(text)
path = string(tempname) + ".json";
writeText(path, text);
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
