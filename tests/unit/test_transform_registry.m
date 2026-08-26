function tests = test_transform_registry
tests = functiontests({ ...
    @testRegisteredTransformsApplyExpectedConversions, ...
    @testUnknownAndInvalidTransformsReturnStructuredIssues, ...
    @testProfileValidationRejectsUnknownTransform});
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

clear cleanupPath
end

function testProfileValidationRejectsUnknownTransform(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profilePath = temporaryYaml(join([
    "profile:"
    "  id: synthetic.unknown.transform"
    "  name: Synthetic unknown transform"
    "  kind: extractor_output"
    "  profile_schema_version: 0.1-draft"
    "extractor:"
    "  name: SyntheticExtractor"
    "  version_scope:"
    "    preferred: '1'"
    "field_mapping_source:"
    "  artifact_key: synthetic_table"
    "field_mappings:"
    "  - source_field: Value"
    "    target_level: event_measurement"
    "    canonical_field: value"
    "    data_type: float"
    "    transform: shell_out"
    ], newline));
cleanupProfile = onCleanup(@() deleteIfExists(profilePath));

verifyError(testCase, ...
    @() vawlume.source_mapping.loadProfile(profilePath, ExpectedKind="extractor_output"), ...
    "vawlume:source_mapping:UnknownTransform");

clear cleanupPath cleanupProfile
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
