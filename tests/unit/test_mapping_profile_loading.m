function tests = test_mapping_profile_loading
tests = functiontests({ ...
    @testLoadsEveryShippedMappingProfile, ...
    @testProfileChecksumsAreStable, ...
    @testKindSpecificStructureIsRequired, ...
    @testExplicitProfileContentVersionsArePreserved, ...
    @testUsvsegProfileMatchesItsVerifiedOutputContract, ...
    @testRequiresExplicitProfileContentVersion, ...
    @testRejectsMalformedJson, ...
    @testRejectsDuplicateJsonMembers, ...
    @testRejectsMissingProfileIdentity, ...
    @testRejectsMissingProfileSchemaVersion, ...
    @testRejectsUnsupportedSchemaVersion, ...
    @testRejectsDuplicateValueMapEntries, ...
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
    "config/01_mapping_profiles/extractors/usvseg/usvseg_output_mapping_profile.json"
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
    verifyEqual(testCase, loaded.profile_schema_versions, "0.2-draft");
    verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
    verifyEqual(testCase, loaded.relative_path, replace(extractorProfiles(index), filesep, "/"));
    verifyEqual(testCase, strlength(loaded.checksum_sha256), 64);
    verifyGreaterThan(testCase, numel(loaded.field_mappings), 0);
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
verifyTrue(testCase, all(loaded.profile_schema_versions == "0.2-draft"));
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
verifyEqual(testCase, loaded.profile_schema_versions, "0.2-draft");
verifyEqual(testCase, string(loaded.document.extractor.version_scope.preferred), "3.2.x");
verifyFalse(testCase, any(issueCodes(report) == "PROFILE_VERSION_MISSING"));
verifyEmpty(testCase, loaded.warnings);

clear cleanupPath
end

function testUsvsegProfileMatchesItsVerifiedOutputContract(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", "usvseg", "usvseg_output_mapping_profile.json");
[loaded, report] = vawlume.source_mapping.loadProfile( ...
    profilePath, ExpectedKind="extractor_output", RepoRoot=repoRoot);

verifyTrue(testCase, report.is_valid);
verifyEmpty(testCase, loaded.warnings);
verifyEqual(testCase, loaded.profile_ids, "vawlume.usvseg.output.v0_9r2");
verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
verifyEqual(testCase, string(loaded.document.extractor.name), "USVSEG");
verifyEqual(testCase, string(loaded.document.extractor.version_scope.preferred), "0.9r2");

% USVSEG writes no version into any output, so the caller must declare one.
verifyTrue(testCase, loaded.document.extractor.version_required_at_ingest);

% The mapped fields are exactly the eight columns the summary CSV exports, in
% export order: nothing dropped and nothing invented.
verifyEqual(testCase, mappedSourceFields(loaded), ...
    ["#"; "start"; "end"; "duration"; "maxfreq"; "maxamp"; "meanfreq"; "cvfreq"]);
verifyEqual(testCase, ...
    string(loaded.document.field_mapping_source.artifact_key), "usvseg_dat_csv");

% Detection geometry reaches the shared importer only through equivalence
% classes, and USVSEG exports onset and offset directly, so neither boundary is
% derived from duration.
verifyEqual(testCase, mappedValues(loaded, "equivalence_class"), ...
    [""; "vocalization_start_time"; "vocalization_end_time"; ...
     "vocalization_duration"; "vocalization_peak_frequency"; ...
     "vocalization_amplitude_like_quantity"; "vocalization_frequency_center"; ...
     "vocalization_frequency_cv"]);
for boundary = ["start", "end"]
    mapping = mappingFor(loaded, boundary);
    verifyEqual(testCase, string(mapping.native_unit), "s");
    verifyEqual(testCase, string(mapping.canonical_unit), "s");
    verifyEqual(testCase, string(mapping.transform), "identity");
end
verifyEqual(testCase, string(mappingFor(loaded, "start").canonical_field), ...
    "call_start_time");
verifyEqual(testCase, string(mappingFor(loaded, "end").canonical_field), ...
    "call_end_time");

% Duration is exported in milliseconds and needs the registered conversion.
duration = mappingFor(loaded, "duration");
verifyEqual(testCase, string(duration.native_unit), "ms");
verifyEqual(testCase, string(duration.canonical_unit), "s");
verifyEqual(testCase, string(duration.transform), "ms_to_s");

% Every transform is already executable; the profile introduces no new key.
transforms = mappedValues(loaded, "transform");
verifyTrue(testCase, all(ismember(transforms(strlength(transforms) > 0), ...
    ["identity"; "kHz_to_Hz"; "ms_to_s"])));

% The identifier column is literally '#', in both the mapping and the event
% identity declaration.
verifyEqual(testCase, string(mappingFor(loaded, "#").semantic_role), "identifier");
verifyEqual(testCase, ...
    string(loaded.document.event_identity.native_id.source_field), "#");
verifyFalse(testCase, loaded.document.event_identity.stable_cross_artifact_identifier);

% Native values are preserved rather than collapsed into canonical ones.
for index = 1:numel(loaded.field_mappings)
    verifyTrue(testCase, loaded.field_mappings{index}.preserve_raw);
end
verifyTrue(testCase, loaded.document.provenance.never_overwrite_native_values);

% No fabricated frequency bounds, detector score, or annotation evidence:
% USVSEG exports none of them, so none is mapped.
canonicalFields = mappedValues(loaded, "canonical_field");
verifyFalse(testCase, any(ismember(canonicalFields, ...
    ["frequency_min"; "frequency_max"; "frequency_bandwidth"; "frequency_slope"; ...
     "native_detection_score"; "native_review_status"; "native_call_label"])));
policy = loaded.document.mapping_policy;
verifyTrue(testCase, policy.exports_no_frequency_bounds);
verifyTrue(testCase, policy.exports_no_curation_state);
verifyTrue(testCase, policy.exports_no_native_class_or_manual_label);
verifyTrue(testCase, policy.do_not_synthesize_absent_features);

% Intentionally noncomparable semantics stay noncomparable. The amplitude value
% is uncalibrated decibels and the frequency CV is a mean-normalized ratio.
verifyEqual(testCase, string(mappingFor(loaded, "maxamp").consilience_role), ...
    "none_by_default");
verifyEqual(testCase, string(mappingFor(loaded, "cvfreq").consilience_role), ...
    "none_by_default");

% A normalized ratio must not join DeepSqueak's absolute frequency spread.
verifyNotEqual(testCase, ...
    string(mappingFor(loaded, "cvfreq").equivalence_class), "vocalization_frequency_sd");

% Mean frequency shares the central-frequency class so the pair is discoverable,
% while declaring a distinct operational variant so neither the shared class nor
% the shared canonical name can be read as method equivalence.
meanFrequency = mappingFor(loaded, "meanfreq");
verifyEqual(testCase, string(meanFrequency.canonical_field), "frequency_center");
verifyEqual(testCase, string(meanFrequency.operational_variant), ...
    "mean_of_primary_peak_frequency_trace");
verifySubstring(testCase, ...
    string(meanFrequency.cross_extractor_relationship), "not_equivalent");

% Settings are optional because USVSEG writes none beside its event export, and
% what it does write is application-scoped rather than run-scoped.
settings = loaded.document.settings_capture;
verifyFalse(testCase, settings.required_for_apply);
verifyEqual(testCase, string(settings.evidence_strength), "weak_not_run_scoped");

% The declared checks a later import adapter must enforce.
checkIds = strings(numel(loaded.document.validation.checks), 1);
for index = 1:numel(loaded.document.validation.checks)
    checkIds(index) = string(loaded.document.validation.checks{index}.id);
end
verifyTrue(testCase, all(ismember( ...
    ["identifier_column_preserved"; "no_synthesized_frequency_bounds"; ...
     "no_unsupported_annotation_evidence"; ...
     "extractor_version_declared_by_caller"], checkIds)));

clear cleanupPath
end

function names = mappedSourceFields(loaded)
names = mappedValues(loaded, "source_field");
end

function values = mappedValues(loaded, fieldName)
values = strings(numel(loaded.field_mappings), 1);
for index = 1:numel(loaded.field_mappings)
    mapping = loaded.field_mappings{index};
    if isfield(mapping, char(fieldName))
        values(index) = string(mapping.(char(fieldName)));
    end
end
end

function mapping = mappingFor(loaded, sourceField)
index = find(mappedSourceFields(loaded) == sourceField, 1);
assert(~isempty(index), "No USVSEG mapping for source field %s.", sourceField);
mapping = loaded.field_mappings{index};
end

function testRequiresExplicitProfileContentVersion(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

document = validExtractorDocument("0.2-draft");
document.profile = rmfield(document.profile, "profile_version");
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:MissingProfileVersion");

clear cleanupPath cleanupProfile
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

document = validExtractorDocument("0.2-draft");
document.profile = rmfield(document.profile, "id");
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:MissingProfileField");

clear cleanupPath cleanupProfile
end

function testRejectsMissingProfileSchemaVersion(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

document = validExtractorDocument("0.2-draft");
document.profile = rmfield(document.profile, "profile_schema_version");
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

function testRejectsDuplicateValueMapEntries(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

document = validExtractorDocument("0.2-draft");
mapping = document.field_mappings{1};
mapping.data_type = "integer";
mapping.value_map = [
    struct(native_value=1, canonical_value="one")
    struct(native_value=1, canonical_value="uno")
    ];
document.field_mappings = {mapping};
profilePath = temporaryJsonDocument(document);
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:InvalidProfileValueMap");

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
    profile_schema_version="0.2-draft", ...
    profile_version="0.1.0");
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
