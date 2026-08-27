function tests = test_transform_registry
tests = functiontests({ ...
    @testRegisteredTransformsApplyExpectedConversions, ...
    @testEveryShippedTransformReferenceIsExecutable, ...
    @testUnknownAndInvalidTransformsReturnStructuredIssues, ...
    @testProfileValidationRejectsUnknownTransform});
end

function testEveryShippedTransformReferenceIsExecutable(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profiles = ["deepsqueak", "mupet"];
referenced = strings(0, 1);

for profileIndex = 1:numel(profiles)
    name = profiles(profileIndex);
    path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
        "extractors", name, name + "_output_mapping_profile.json");
    loaded = vawlume.source_mapping.loadProfile(path, ...
        ExpectedKind="extractor_output", RepoRoot=repoRoot);
    for mappingIndex = 1:numel(loaded.field_mappings)
        mapping = loaded.field_mappings{mappingIndex};
        if isfield(mapping, "transform") && strlength(string(mapping.transform)) > 0
            referenced(end + 1, 1) = string(mapping.transform); %#ok<AGROW>
        end
    end
end

referenced = sort(unique(referenced));
verifyNotEmpty(testCase, referenced);
for transformIndex = 1:numel(referenced)
    [~, report] = vawlume.source_mapping.applyTransform(1, referenced(transformIndex));
    verifyTrue(testCase, report.is_valid, ...
        "Shipped transform must be executable: " + referenced(transformIndex));
end

clear cleanupPath
end

function testRegisteredTransformsApplyExpectedConversions(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[hz, report] = vawlume.source_mapping.applyTransform(55.25, "kHz_to_Hz");
verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, hz, 55250);

[slope, report] = vawlume.source_mapping.applyTransform(2.5, "kHz_per_s_to_Hz_per_s");
verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, slope, 2500);

[seconds, report] = vawlume.source_mapping.applyTransform("48", "ms_to_s");
verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, seconds, 0.048, AbsTol=1e-12);

[same, report] = vawlume.source_mapping.applyTransform("native", "identity");
verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, same, "native");

clear cleanupPath
end

function testUnknownAndInvalidTransformsReturnStructuredIssues(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[value, report] = vawlume.source_mapping.applyTransform(1, "not_registered");
verifyEmpty(testCase, value);
verifyFalse(testCase, report.is_valid);
verifyEqual(testCase, string(report.issue_table.code), "TRANSFORM_UNKNOWN");

[value, report] = vawlume.source_mapping.applyTransform("abc", "kHz_to_Hz");
verifyEmpty(testCase, value);
verifyFalse(testCase, report.is_valid);
verifyEqual(testCase, string(report.issue_table.code), "TRANSFORM_INPUT_NOT_NUMERIC");

[value, report] = vawlume.source_mapping.applyTransform(missing, "kHz_to_Hz");
verifyEmpty(testCase, value);
verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, report.status, "missing");
verifyEqual(testCase, string(report.issue_table.code), "TRANSFORM_INPUT_MISSING");

clear cleanupPath
end

function testProfileValidationRejectsUnknownTransform(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryJsonDocument(syntheticUnknownTransformProfile());
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:UnknownTransform");

clear cleanupPath cleanupProfile
end

function document = syntheticUnknownTransformProfile()
document = struct();
document.profile = struct( ...
    id="synthetic.unknown.transform", ...
    name="Synthetic unknown transform", ...
    kind="extractor_output", ...
    profile_schema_version="0.1-draft");
document.extractor = struct( ...
    name="SyntheticExtractor", ...
    version_scope=struct(preferred="1"));
document.field_mapping_source = struct(artifact_key="synthetic_table");
document.field_mappings = {struct( ...
    source_field="Value", ...
    target_level="event_measurement", ...
    canonical_field="value", ...
    data_type="float", ...
    transform="shell_out")};
end

function path = temporaryJsonDocument(document)
path = string(tempname) + ".json";
writeText(path, jsonencode(document));
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
