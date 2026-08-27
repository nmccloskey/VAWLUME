function tests = test_table_field_mapping
tests = functiontests({ ...
    @testMapsDeepSqueakTableWithAliasesAndValueMappings, ...
    @testMapsMupetTableWithSentinelAndOperationalMetadata, ...
    @testColumnResolutionReportsAmbiguityAndMissingRequiredness, ...
    @testInvalidNumericValuePreservesRawToken});
end

function testMapsDeepSqueakTableWithAliasesAndValueMappings(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadExtractorProfile(repoRoot, "deepsqueak");
tbl = deepSqueakTable();
mapped = vawlume.source_mapping.mapTableFields(tbl, loaded, SourceKey="ds:synthetic");

verifyTrue(testCase, mapped.is_valid);
verifyEqual(testCase, mapped.mapped_record_count, height(tbl) * numel(loaded.field_mappings));
verifyEqual(testCase, mapped.source_artifact_type, "event_stats_excel");

frequency = recordFor(mapped, "contour_median_frequency", 1);
verifyEqual(testCase, frequency.native_field_name, "Principle Frequency (kHz)");
verifyEqual(testCase, frequency.actual_source_field, "Principal Frequency (kHz)");
verifyEqual(testCase, frequency.column_resolution, "alias");
verifyEqual(testCase, frequency.native_value_real, 55);
verifyEqual(testCase, frequency.canonical_value_real, 55000);
verifyEqual(testCase, frequency.transform_key, "kHz_to_Hz");
verifyEqual(testCase, frequency.derivation_stage, "contour_derived");
verifyEqual(testCase, frequency.cross_extractor_relationship, ...
    "comparable_not_equivalent_to_MUPET_mean_frequency");

accepted = recordFor(mapped, "native_review_status", 1);
verifyEqual(testCase, accepted.native_value_integer, 1);
verifyEqual(testCase, accepted.canonical_value_type, "text");
verifyEqual(testCase, accepted.canonical_value_text, "accepted");
verifyEqual(testCase, accepted.transform_status, "value_mapping");

clear cleanupPath
end

function testMapsMupetTableWithSentinelAndOperationalMetadata(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = loadExtractorProfile(repoRoot, "mupet");
tbl = mupetTable();
mapped = vawlume.source_mapping.mapTableFields(tbl, loaded, SourceKey="mupet:synthetic");

verifyTrue(testCase, mapped.is_valid);
verifyTrue(testCase, any(string(mapped.issue_table.code) == "FIELD_VALUE_EXPLICIT_MISSING"));

duration = recordFor(mapped, "call_duration", 1);
verifyEqual(testCase, duration.native_value_real, 48);
verifyEqual(testCase, duration.canonical_value_real, 0.048, AbsTol=1e-12);
verifyEqual(testCase, duration.transform_key, "ms_to_s");
verifyEqual(testCase, duration.operational_variant, "pre_noise_reduction");
verifyEqual(testCase, duration.cross_extractor_relationship, "comparable_not_metric_equivalent");

interval = recordFor(mapped, "inter_call_interval", 2);
verifyEqual(testCase, interval.status, "missing");
verifyEqual(testCase, interval.native_raw_token, "NA");
verifyEqual(testCase, interval.native_value_type, "missing");
verifyEqual(testCase, interval.canonical_value_type, "missing");

energy = recordFor(mapped, "total_energy", 1);
verifyEqual(testCase, energy.native_value_real, 12.5);
verifyEqual(testCase, energy.canonical_value_real, 12.5);
verifyEqual(testCase, energy.canonical_unit, "dB");
verifyEqual(testCase, energy.cross_extractor_relationship, ...
    "related_not_equivalent_to_DeepSqueak_mean_PSD");

clear cleanupPath
end

function testColumnResolutionReportsAmbiguityAndMissingRequiredness(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profile = syntheticExtractorProfile();
ambiguousTable = table([1; 2], [3; 4], VariableNames=["Alias A", "Alias B"]);
ambiguous = vawlume.source_mapping.mapTableFields(ambiguousTable, profile);
verifyFalse(testCase, ambiguous.is_valid);
verifyEqual(testCase, string(ambiguous.issue_table.code), "FIELD_MAPPING_COLUMN_AMBIGUOUS");
verifyEqual(testCase, ambiguous.mapped_record_count, 0);

missingTable = table([1; 2], VariableNames="Other");
missing = vawlume.source_mapping.mapTableFields(missingTable, profile);
verifyFalse(testCase, missing.is_valid);
verifyEqual(testCase, string(missing.issue_table.code), "FIELD_MAPPING_COLUMN_MISSING");

optionalProfile = profile;
optionalProfile.field_mappings{1}.required = false;
optional = vawlume.source_mapping.mapTableFields(missingTable, optionalProfile);
verifyTrue(testCase, optional.is_valid);
verifyEqual(testCase, string(optional.issue_table.code), "FIELD_MAPPING_OPTIONAL_COLUMN_MISSING");
verifyEqual(testCase, optional.mapped_record_count, 0);

clear cleanupPath
end

function testInvalidNumericValuePreservesRawToken(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

profile = syntheticExtractorProfile();
profile.field_mappings{1}.source_field = "Value";
profile.field_mappings{1}.aliases = {};
tbl = table("abc", VariableNames="Value");

mapped = vawlume.source_mapping.mapTableFields(tbl, profile);
record = mapped.records(1);

verifyFalse(testCase, mapped.is_valid);
verifyEqual(testCase, string(mapped.issue_table.code), "FIELD_VALUE_COERCION_FAILED");
verifyEqual(testCase, record.status, "invalid");
verifyEqual(testCase, record.native_raw_token, "abc");
verifyEqual(testCase, record.native_value_type, "invalid");

clear cleanupPath
end

function tbl = deepSqueakTable()
tbl = table( ...
    ["calls_001.mat"; "calls_001.mat"], ...
    [1; 2], ...
    ["USV"; "Noise"], ...
    [1; 0], ...
    [0.95; 0.10], ...
    [0.100; 0.200], ...
    [0.148; 0.245], ...
    [0.048; 0.045], ...
    [55; 60], ...
    [40; 42], ...
    [80; 82], ...
    [40; 40], ...
    [4.5; 4.7], ...
    [2.1; 2.2], ...
    [76; 77], ...
    [1.2; 1.3], ...
    [-35; -33], ...
    [0.8; 0.6], ...
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
    [1; 2], ...
    [0.100; 0.200], ...
    [0.148; 0.250], ...
    ["0.052"; "NA"], ...
    [48; 50], ...
    [45; 46], ...
    [60; 61], ...
    [40; 41], ...
    [75; 76], ...
    [55; 56], ...
    [35; 35], ...
    [12.5; 13.0], ...
    [-18; -17], ...
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

function profile = syntheticExtractorProfile()
mapping = struct( ...
    source_field="Exact Missing", ...
    aliases={{"Alias A", "Alias B"}}, ...
    target_level="event_measurement", ...
    canonical_field="value", ...
    data_type="float", ...
    native_unit="kHz", ...
    canonical_unit="Hz", ...
    transform="kHz_to_Hz", ...
    preserve_raw=true);
profile = struct();
profile.profile = struct( ...
    id="synthetic.table.profile", ...
    name="Synthetic table profile", ...
    kind="extractor_output", ...
    profile_schema_version="0.1-draft");
profile.extractor = struct(name="SyntheticExtractor");
profile.field_mapping_source = struct(artifact_key="synthetic_table");
profile.field_mappings = {mapping};
end

function loaded = loadExtractorProfile(repoRoot, extractorName)
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", extractorName, extractorName + "_output_mapping_profile.json");
loaded = vawlume.source_mapping.loadProfile(profilePath, ...
    ExpectedKind="extractor_output", RepoRoot=repoRoot);
end

function record = recordFor(mapped, canonicalField, sourceRow)
records = mapped.record_table;
matches = string(records.canonical_field) == canonicalField & records.source_row == sourceRow;
record = table2struct(records(find(matches, 1), :));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
