function tests = test_mapping_profile_loading
tests = functiontests({ ...
    @testLoadsEveryShippedMappingProfile, ...
    @testProfileChecksumsAreStable, ...
    @testKindSpecificStructureIsRequired, ...
    @testExtractorProfileVersionFallbackIsReported, ...
    @testRejectsMalformedYaml, ...
    @testRejectsMissingProfileIdentity, ...
    @testRejectsUnsupportedSchemaVersion, ...
    @testRejectsInvalidRegex, ...
    @testRejectsInheritanceDeclarations});
end

function testProfileChecksumsAreStable(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.yaml");

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
    "config/01_mapping_profiles/extractors/deepsqueak/deepsqueak_output_mapping_profile.yaml"
    "config/01_mapping_profiles/extractors/mupet/mupet_output_mapping_profile.yaml"
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
    verifyEqual(testCase, loaded.relative_path, replace(extractorProfiles(index), filesep, "/"));
    verifyEqual(testCase, strlength(loaded.checksum_sha256), 64);
    verifyGreaterThan(testCase, numel(loaded.field_mappings), 0);
end

projectPath = fullfile(repoRoot, ...
    "config", "01_mapping_profiles", "project_inputs", ...
    "project_input_source_mapping_examples.yaml");
[loaded, report] = vawlume.source_mapping.loadProfile( ...
    projectPath, ExpectedKind="project_input", RepoRoot=repoRoot);

verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, report.error_count, 0);
verifyEqual(testCase, loaded.profile_count, 3);
verifyEqual(testCase, numel(loaded.profiles), 3);
verifyTrue(testCase, all(loaded.profile_kinds == "project_input"));
verifyEqual(testCase, loaded.profile_ids(1), ...
    "example.project.mouse_courtship.folder_driven");
verifyTrue(testCase, any(issueCodes(report) == ...
    "PROFILE_REGEX_PYTHON_NAMED_CAPTURE_COMPATIBILITY"));

clear cleanupPath
end

function testExtractorProfileVersionFallbackIsReported(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = fullfile(repoRoot, ...
    "config", "01_mapping_profiles", "extractors", "deepsqueak", ...
    "deepsqueak_output_mapping_profile.yaml");
[loaded, report] = vawlume.source_mapping.loadProfile( ...
    profilePath, ExpectedKind="extractor_output", RepoRoot=repoRoot);

verifyEqual(testCase, loaded.profile_version_labels, "3.2.x");
verifyTrue(testCase, any(issueCodes(report) == ...
    "PROFILE_VERSION_DERIVED_FROM_EXTRACTOR"));
verifyTrue(testCase, any(contains(loaded.warnings, ...
    "extractor.version_scope.preferred")));

clear cleanupPath
end

function testRejectsMalformedYaml(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryYaml("profile: [unterminated");
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath), ...
    "vawlume:source_mapping:YamlLoadFailed");

clear cleanupPath cleanupProfile
end

function testRejectsMissingProfileIdentity(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryYaml(join([
    "profile:"
    "  name: Missing identity"
    "  kind: extractor_output"
    "  profile_schema_version: 0.1-draft"
    "extractor:"
    "  name: SyntheticExtractor"
    "  version_scope:"
    "    preferred: '1'"
    "field_mapping_source:"
    "  artifact_key: event_table"
    "field_mappings:"
    "  - source_field: Value"
    "    target_level: event_measurement"
    "    canonical_field: value"
    "    data_type: float"
    ], newline));
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

profilePath = temporaryYaml(validExtractorYaml("9.9-future"));
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

profilePath = temporaryYaml(join([
    "profiles:"
    "  - profile:"
    "      id: bad.regex.project"
    "      name: Bad regex project"
    "      kind: project_input"
    "      profile_schema_version: 0.1-draft"
    "    source:"
    "      root: <PROJECT_ROOT>"
    "      include:"
    "        glob: ['*.wav']"
    "    hierarchy:"
    "      levels:"
    "        - {native_name: recording, canonical_role: recording}"
    "    mappings:"
    "      - target_level: recording"
    "        source_type: filename"
    "        filename_regex: '['"
    "        captures:"
    "          recording: {canonical_field: recording_id}"
    ], newline));
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

profilePath = temporaryYaml(join([
    "profiles:"
    "  - profile:"
    "      id: bad.inherit.project"
    "      name: Unsupported inheritance project"
    "      kind: project_input"
    "      profile_schema_version: 0.1-draft"
    "    extends: base.project.profile"
    "    source:"
    "      root: <PROJECT_ROOT>"
    "      include:"
    "        glob: ['*.wav']"
    "    hierarchy:"
    "      levels:"
    "        - {native_name: recording, canonical_role: recording}"
    "    mappings:"
    "      - {target_level: recording, source_type: literal, value: rec1}"
    ], newline));
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="project_input"), ...
    "vawlume:source_mapping:UnsupportedProfileInheritance");

clear cleanupPath cleanupProfile
end

function yamlText = validExtractorYaml(schemaVersion)
yamlText = join([
    "profile:"
    "  id: synthetic.extractor.output"
    "  name: Synthetic extractor output"
    "  kind: extractor_output"
    "  profile_schema_version: " + schemaVersion
    "extractor:"
    "  name: SyntheticExtractor"
    "  version_scope:"
    "    preferred: '1'"
    "field_mapping_source:"
    "  artifact_key: event_table"
    "field_mappings:"
    "  - source_field: Value"
    "    target_level: event_measurement"
    "    canonical_field: value"
    "    data_type: float"
    ], newline);
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

function path = temporaryYaml(text)
path = string(tempname) + ".yaml";
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
