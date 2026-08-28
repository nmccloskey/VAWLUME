function tests = test_intermediate_representation
tests = functiontests({ ...
    @testMapsExtractorTablesIntoUnifiedContract, ...
    @testConflictingTableEvidenceIsPreserved, ...
    @testOptionalColumnIssueDoesNotInvalidate});
end

function testMapsExtractorTablesIntoUnifiedContract(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

deepSqueakProfile = loadExtractorProfile(repoRoot, "deepsqueak");
deepSqueak = vawlume.source_mapping.mapTableToIR( ...
    deepSqueakTable(), deepSqueakProfile, ...
    SourceKey="extractor:deepsqueak:synthetic", ...
    RelativePath="exports/calls_001_Stats.xlsx");

verifyUnifiedShape(testCase, deepSqueak);
verifyTrue(testCase, deepSqueak.valid_for_ingest);
verifyEqual(testCase, deepSqueak.profile.profile_version, "0.1.0");
verifyEqual(testCase, deepSqueak.profile.profile_version_source, ...
    "profile.profile_version");
verifyEqual(testCase, deepSqueak.profile.profile_schema_version, "0.2-draft");
verifyEqual(testCase, deepSqueak.profile.extractor_version_scope_preferred, "3.2.x");
verifyEqual(testCase, height(deepSqueak.records), 2);
verifyEqual(testCase, deepSqueak.records.native_identifier, ["1"; "2"]);
frequency = valueFor(deepSqueak, "contour_median_frequency", 1);
verifyEqual(testCase, frequency.raw_value, "55");
verifyEqual(testCase, frequency.normalized_value_real, 55000);
verifyEqual(testCase, frequency.transform_key, "kHz_to_Hz");

mupetProfile = loadExtractorProfile(repoRoot, "mupet");
mupet = vawlume.source_mapping.mapTableToIR( ...
    mupetTable(), mupetProfile, ...
    SourceKey="extractor:mupet:synthetic", ...
    RelativePath="audio/dataset/CSV/recording.csv");

verifyUnifiedShape(testCase, mupet);
verifyTrue(testCase, mupet.valid_for_ingest);
interval = valueFor(mupet, "inter_call_interval", 2);
verifyEqual(testCase, interval.raw_value, "NA");
verifyEqual(testCase, interval.native_value_type, "missing");
verifyEqual(testCase, interval.normalized_value_type, "missing");
verifyTrue(testCase, any(mupet.issues.code == "MISSING_TOKEN_NORMALIZED"));
verifyEmpty(testCase, mupet.relationships);

clear cleanupPath
end

function testConflictingTableEvidenceIsPreserved(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

mappingA = syntheticMapping("A");
mappingB = syntheticMapping("B");
profile = syntheticExtractorProfile({mappingA, mappingB});
tbl = table(1, 2, VariableNames=["A", "B"]);

result = vawlume.source_mapping.mapTableToIR(tbl, profile);

verifyFalse(testCase, result.valid_for_ingest);
verifyEqual(testCase, result.summary.conflict_count, 1);
verifyEqual(testCase, sum(result.issues.code == "VALUE_CONFLICT"), 1);
verifyEqual(testCase, result.values.raw_value, ["1"; "2"]);
verifyEqual(testCase, unique(result.values.consolidation_status), "conflict");
verifyEqual(testCase, unique(result.values.evidence_count), 2);

clear cleanupPath
end

function testOptionalColumnIssueDoesNotInvalidate(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

mapping = syntheticMapping("Optional");
mapping.required = false;
profile = syntheticExtractorProfile({mapping});
tbl = table(1, VariableNames="Other");

result = vawlume.source_mapping.mapTableToIR(tbl, profile);

verifyTrue(testCase, result.valid_for_ingest);
verifyEqual(testCase, string(result.issues.code), "OPTIONAL_COLUMN_MISSING");
verifyEqual(testCase, string(result.issues.severity), "info");
verifyFalse(testCase, result.issues.affects_validity);
verifyEmpty(testCase, result.values);
verifyEqual(testCase, height(result.records), 1);

clear cleanupPath
end

function verifyUnifiedShape(testCase, result)
verifyEqual(testCase, string(fieldnames(result)), [
    "ir_schema_version"
    "profile"
    "sources"
    "records"
    "values"
    "relationships"
    "issues"
    "summary"
    "valid_for_ingest"
    ]);
verifyEqual(testCase, result.ir_schema_version, "0.1-draft");
verifyTrue(testCase, istable(result.sources));
verifyTrue(testCase, istable(result.records));
verifyTrue(testCase, istable(result.values));
verifyTrue(testCase, istable(result.relationships));
verifyTrue(testCase, istable(result.issues));
end

function record = valueFor(result, canonicalField, sourceRow)
matches = result.values.canonical_field == canonicalField & ...
    result.values.source_row == sourceRow;
record = table2struct(result.values(find(matches, 1), :));
end

function loaded = loadExtractorProfile(repoRoot, extractorName)
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", extractorName, extractorName + "_output_mapping_profile.json");
loaded = vawlume.source_mapping.loadProfile(profilePath, ...
    ExpectedKind="extractor_output", RepoRoot=repoRoot);
end

function mapping = syntheticMapping(sourceField)
mapping = struct( ...
    source_field=string(sourceField), ...
    aliases={{}}, ...
    target_level="event_measurement", ...
    canonical_field="value", ...
    data_type="float", ...
    native_unit="", ...
    canonical_unit="", ...
    transform="identity", ...
    preserve_raw=true);
end

function profile = syntheticExtractorProfile(mappings)
profile = struct();
profile.profile = struct( ...
    id="synthetic.table.profile", ...
    name="Synthetic table profile", ...
    kind="extractor_output", ...
    profile_schema_version="0.2-draft", ...
    profile_version="0.1.0");
profile.extractor = struct(name="SyntheticExtractor");
profile.field_mapping_source = struct(artifact_key="synthetic_table");
profile.field_mappings = mappings;
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

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
