function tests = test_mapping_validation
tests = functiontests({ ...
    @testRequiredAndOptionalColumnPoliciesDriveValidity, ...
    @testConflictDiagnosticsAreDeterministic, ...
    @testPreviewRejectsNonIRInput});
end

function testRequiredAndOptionalColumnPoliciesDriveValidity(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
tbl = table(1, VariableNames="Other");

required = syntheticMapping("Required", true);
requiredResult = vawlume.source_mapping.mapTableToIR( ...
    tbl, syntheticExtractorProfile({required}));
verifyFalse(testCase, requiredResult.valid_for_ingest);
verifyEqual(testCase, string(requiredResult.issues.code), "COLUMN_MISSING");
verifyEqual(testCase, string(requiredResult.issues.severity), "error");
verifyTrue(testCase, requiredResult.issues.affects_validity);

optional = syntheticMapping("Optional", false);
optionalResult = vawlume.source_mapping.mapTableToIR( ...
    tbl, syntheticExtractorProfile({optional}));
verifyTrue(testCase, optionalResult.valid_for_ingest);
verifyEqual(testCase, string(optionalResult.issues.code), "OPTIONAL_COLUMN_MISSING");
verifyEqual(testCase, string(optionalResult.issues.severity), "info");
verifyFalse(testCase, optionalResult.issues.affects_validity);

clear cleanupPath
end

function testConflictDiagnosticsAreDeterministic(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profile = syntheticExtractorProfile({ ...
    syntheticMapping("A", true), syntheticMapping("B", true)});
tbl = table(1, 2, VariableNames=["A", "B"]);

first = vawlume.source_mapping.mapTableToIR(tbl, profile);
second = vawlume.source_mapping.mapTableToIR(tbl, profile);

verifyFalse(testCase, first.valid_for_ingest);
verifyEqual(testCase, sum(first.issues.code == "VALUE_CONFLICT"), 1);
verifyEqual(testCase, first.issues, second.issues);
verifyEqual(testCase, first.values, second.values);
verifyEqual(testCase, sort(first.values.raw_value), ["1"; "2"]);
verifyEqual(testCase, unique(first.values.consolidation_status), "conflict");

clear cleanupPath
end

function testPreviewRejectsNonIRInput(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

verifyError(testCase, @() vawlume.source_mapping.preview(struct()), ...
    "vawlume:source_mapping:InvalidIntermediateRepresentation");

clear cleanupPath
end

function mapping = syntheticMapping(sourceField, required)
mapping = struct( ...
    source_field=string(sourceField), ...
    aliases={{}}, ...
    target_level="event_measurement", ...
    canonical_field="value", ...
    data_type="float", ...
    native_unit="", ...
    canonical_unit="", ...
    transform="identity", ...
    required=required, ...
    preserve_raw=true);
end

function profile = syntheticExtractorProfile(mappings)
profile = struct();
profile.profile = struct( ...
    id="synthetic.validation.profile", ...
    name="Synthetic validation profile", ...
    kind="extractor_output", ...
    profile_schema_version="0.1-draft");
profile.extractor = struct(name="SyntheticExtractor");
profile.field_mapping_source = struct(artifact_key="synthetic_table");
profile.field_mappings = mappings;
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
