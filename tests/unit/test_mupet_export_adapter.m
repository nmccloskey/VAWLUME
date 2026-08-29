function tests = test_mupet_export_adapter
tests = functiontests({ ...
    @testNominalCsvProducesValidExtractorOutputIR, ...
    @testNativeHeadersAndLexicalMissingTokenSurvive, ...
    @testDurationAndFrequencyTransformsStayInSourceMapping, ...
    @testMissingHeaderIsNotRepaired, ...
    @testAdapterRejectsMissingWrongFormatEmptyAndWrongDelimiter, ...
    @testVersionScopeComesFromProfile, ...
    @testPortableIdentityIsRootIndependent, ...
    @testValidConfigCsvProducesFaithfulSettingsCapture, ...
    @testSettingsUnknownMissingAndDuplicateKeysAreVisible, ...
    @testChangedSettingChangesArtifactAndStructuredIdentity, ...
    @testSettingsAreRequiredLaterButOptionalForInspection, ...
    @testAdapterIsDatabaseIndependentAndHasNoSemanticDictionary});
end

function testNominalCsvProducesValidExtractorOutputIR(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, configPath, cleanupFiles] = writeNominalFiles(); %#ok<ASGLU>

result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=configPath);

verifyTrue(testCase, result.valid_for_ingest);
verifyEqual(testCase, result.artifact.artifact_key, "per_syllable_csv");
verifyEqual(testCase, result.artifact.file_format, "csv");
verifyEqual(testCase, result.artifact.row_count, 4);
verifyEqual(testCase, result.artifact.column_count, 13);
verifyMatches(testCase, result.artifact.checksum_sha256, "^[0-9a-f]{64}$");
verifyEqual(testCase, result.ir.profile.profile_key, "vawlume.mupet.output.v2_1");
verifyEqual(testCase, result.ir.profile.profile_version, "0.1.0");
verifyEqual(testCase, result.ir.profile.profile_schema_version, "0.2-draft");
verifyEqual(testCase, result.ir.profile.extractor_name, "MUPET");
verifyEqual(testCase, height(result.ir.records), 4);
verifyEqual(testCase, string(result.ir.records.native_identifier), ["1";"2";"3";"4"]);
verifyEqual(testCase, height(result.ir.values), 52);
verifyTrue(testCase, result.ir.valid_for_ingest);

preview = vawlume.source_mapping.preview(result.ir);
verifyEqual(testCase, preview.verdict, "READY FOR INGEST");

clear cleanupFiles
end

function testNativeHeadersAndLexicalMissingTokenSurvive(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, configPath, cleanupFiles] = writeNominalFiles(); %#ok<ASGLU>
result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1.3", SettingsConfigPath=configPath);

expected = string(nominalHeaders());
verifyEqual(testCase, string(result.table.Properties.VariableNames)', expected(:));
verifyEqual(testCase, result.artifact.source_columns, expected(:));
verifyEqual(testCase, result.artifact.lexical_columns, ...
    "inter-syllable interval (sec)");
verifyTrue(testCase, isstring(result.table.("inter-syllable interval (sec)")));
verifyEqual(testCase, result.table.("inter-syllable interval (sec)")(4), "NA");

interval = valueFor(result.ir, 4, "inter-syllable interval (sec)");
verifyEqual(testCase, interval.raw_value, "NA");
verifyEqual(testCase, interval.native_value_type, "missing");
verifyEqual(testCase, interval.normalized_value_type, "missing");
verifyEqual(testCase, interval.status, "missing");
verifyTrue(testCase, isnan(interval.native_value_real));
verifyFalse(testCase, interval.raw_value == "0");

clear cleanupFiles
end

function testDurationAndFrequencyTransformsStayInSourceMapping(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, configPath, cleanupFiles] = writeNominalFiles(); %#ok<ASGLU>
result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=configPath);

duration = valueFor(result.ir, 2, "syllable duration (msec)");
verifyEqual(testCase, duration.native_value_real, 34.7, AbsTol=1e-12);
verifyEqual(testCase, duration.native_unit, "ms");
verifyEqual(testCase, duration.normalized_value_real, 0.0347, AbsTol=1e-12);
verifyEqual(testCase, duration.canonical_unit, "s");
verifyEqual(testCase, duration.transform_key, "ms_to_s");
verifyEqual(testCase, duration.operational_variant, "pre_noise_reduction");

frequency = valueFor(result.ir, 1, "starting frequency (kHz)");
verifyEqual(testCase, frequency.native_value_real, 45);
verifyEqual(testCase, frequency.native_unit, "kHz");
verifyEqual(testCase, frequency.normalized_value_real, 45000);
verifyEqual(testCase, frequency.canonical_unit, "Hz");
verifyEqual(testCase, frequency.transform_key, "kHz_to_Hz");

clear cleanupFiles
end

function testMissingHeaderIsNotRepaired(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
cells = nominalExport();
cells(:, strcmp(cells(1,:), 'mean frequency (kHz)')) = [];
csvPath = writeCsv(tempname + ".csv", cells);
cleanupFile = onCleanup(@() deleteIfExists(csvPath));

result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1");
missing = result.ir.issues(result.ir.issues.code == "COLUMN_MISSING", :);
verifyEqual(testCase, height(missing), 1);
verifyFalse(testCase, result.ir.valid_for_ingest);
verifyFalse(testCase, result.valid_for_ingest);
verifyFalse(testCase, ismember("mean frequency (kHz)", ...
    string(result.table.Properties.VariableNames)));
end

function testAdapterRejectsMissingWrongFormatEmptyAndWrongDelimiter(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
verifyError(testCase, ...
    @() vawlume.ingest.mupetExport(tempname + ".csv", RepoRoot=repoRoot), ...
    "vawlume:ingest:MupetArtifactNotFound");

txtPath = tempname + ".txt";
writeText(txtPath, "not,csv");
cleanupTxt = onCleanup(@() deleteIfExists(txtPath));
verifyError(testCase, ...
    @() vawlume.ingest.mupetExport(txtPath, RepoRoot=repoRoot), ...
    "vawlume:ingest:MupetArtifactUnsupported");

emptyPath = tempname + ".csv";
writeText(emptyPath, "");
cleanupEmpty = onCleanup(@() deleteIfExists(emptyPath));
verifyError(testCase, ...
    @() vawlume.ingest.mupetExport(emptyPath, RepoRoot=repoRoot), ...
    "vawlume:ingest:MupetArtifactUnreadable");

wrongDelimiter = tempname + ".csv";
writeText(wrongDelimiter, "a;b;c" + newline + "1;2;3" + newline);
cleanupWrong = onCleanup(@() deleteIfExists(wrongDelimiter));
verifyError(testCase, ...
    @() vawlume.ingest.mupetExport(wrongDelimiter, RepoRoot=repoRoot), ...
    "vawlume:ingest:MupetArtifactUnsupported");
end

function testVersionScopeComesFromProfile(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, ~, cleanupFiles] = writeNominalFiles(); %#ok<ASGLU>

for version = ["2.1", "2.1.0", "2.1.7"]
    result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
        ExtractorVersion=version);
    verifyEqual(testCase, result.extractor_version.status, "preferred");
end
for version = ["2", "2.0", "2.2", "3.0"]
    result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
        ExtractorVersion=version);
    verifyEqual(testCase, result.extractor_version.status, "incompatible");
end
absent = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot);
verifyEqual(testCase, absent.extractor_version.status, "missing_required");
verifyEqual(testCase, absent.extractor_version.declared_version, "");

clear cleanupFiles
end

function testPortableIdentityIsRootIndependent(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
rootA = fullfile(tempdir, "vawlume_mupet_a");
rootB = fullfile(tempdir, "vawlume_mupet_b");
pathA = fullfile(rootA, "audio", "set1", "CSV", "REC_A.csv");
pathB = fullfile(rootB, "audio", "set1", "CSV", "REC_A.csv");
makeParent(pathA);
makeParent(pathB);
writeCsv(pathA, nominalExport());
writeCsv(pathB, nominalExport());
cleanupRoots = onCleanup(@() removeFolders([string(rootA), string(rootB)]));

first = vawlume.ingest.mupetExport(pathA, RepoRoot=repoRoot, ...
    ArtifactRoot=rootA, ExtractorVersion="2.1");
second = vawlume.ingest.mupetExport(pathB, RepoRoot=repoRoot, ...
    ArtifactRoot=rootB, ExtractorVersion="2.1");
verifyEqual(testCase, first.artifact.relative_path, "audio/set1/CSV/REC_A.csv");
verifyEqual(testCase, second.artifact.relative_path, first.artifact.relative_path);
verifyEqual(testCase, second.source_key, first.source_key);
verifyEqual(testCase, second.artifact.checksum_sha256, first.artifact.checksum_sha256);
verifyNotEqual(testCase, second.artifact.runtime_path, first.artifact.runtime_path);

verifyError(testCase, ...
    @() vawlume.ingest.mupetExport(pathA, RepoRoot=repoRoot, ...
    RelativePath="../REC_A.csv"), ...
    "vawlume:ingest:MupetArtifactNotPortable");
end

function testValidConfigCsvProducesFaithfulSettingsCapture(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, configPath, cleanupFiles] = writeNominalFiles(); %#ok<ASGLU>
result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=configPath, ...
    SettingsRelativePath="mupet/config.csv");

settings = result.settings;
verifyEqual(testCase, settings.status, "captured");
verifyTrue(testCase, settings.complete);
verifyEqual(testCase, height(settings.entries), 11);
verifyTrue(testCase, all(settings.entries.declared));
verifyEmpty(testCase, settings.missing_required_keys);
verifyMatches(testCase, settings.source_checksum_sha256, "^[0-9a-f]{64}$");
verifyMatches(testCase, settings.structured_capture_checksum_sha256, "^[0-9a-f]{64}$");
verifyEqual(testCase, settings.lineage.source_checksum_sha256, ...
    settings.source_checksum_sha256);
verifyEqual(testCase, settings.source_artifact.relative_path, "mupet/config.csv");
verifyEqual(testCase, settings.source_artifact.artifact_key, "settings_config");

row = settings.entries(settings.entries.native_name == "minimum-syllable-duration", :);
verifyEqual(testCase, row.raw_value, "008");
verifyEqual(testCase, row.canonical_setting, "minimum_syllable_duration");
verifyEqual(testCase, row.native_unit, "ms");
verifyTrue(testCase, result.valid_for_ingest);

clear cleanupFiles
end

function testSettingsUnknownMissingAndDuplicateKeysAreVisible(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
csvPath = writeCsv(tempname + ".csv", nominalExport());
base = nominalConfigLines();
configPath = tempname + ".csv";
lines = [base(1:end-1); "noise-reduction,6"; "future-setting,abc"];
writeText(configPath, strjoin(lines, newline) + newline);
cleanupFiles = onCleanup(@() deleteMany([csvPath, configPath]));

result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=configPath);
verifyEqual(testCase, result.settings.status, "incomplete");
verifyFalse(testCase, result.settings.complete);
verifyTrue(testCase, any(result.settings.issues.code == "MUPET_SETTINGS_KEY_DUPLICATE"));
verifyTrue(testCase, any(result.settings.issues.code == "MUPET_SETTINGS_KEY_UNRECOGNIZED"));
verifyTrue(testCase, any(result.settings.issues.code == "MUPET_SETTINGS_REQUIRED_KEY_MISSING"));
verifyTrue(testCase, any(result.settings.entries.native_name == "future-setting"));
verifyTrue(testCase, any(result.settings.missing_required_keys == "filterbank-type"));
verifyFalse(testCase, result.valid_for_ingest);
end

function testChangedSettingChangesArtifactAndStructuredIdentity(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
csvPath = writeCsv(tempname + ".csv", nominalExport());
firstPath = tempname + ".csv";
secondPath = tempname + ".csv";
lines = nominalConfigLines();
writeText(firstPath, strjoin(lines, newline) + newline);
lines(1) = "noise-reduction,6";
writeText(secondPath, strjoin(lines, newline) + newline);
cleanupFiles = onCleanup(@() deleteMany([csvPath, firstPath, secondPath]));

first = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=firstPath);
second = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=secondPath);
verifyNotEqual(testCase, first.settings.source_checksum_sha256, ...
    second.settings.source_checksum_sha256);
verifyNotEqual(testCase, first.settings.structured_capture_checksum_sha256, ...
    second.settings.structured_capture_checksum_sha256);
end

function testSettingsAreRequiredLaterButOptionalForInspection(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
csvPath = writeCsv(tempname + ".csv", nominalExport());
cleanupFile = onCleanup(@() deleteIfExists(csvPath));
result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1");

verifyEqual(testCase, result.settings.status, "not_supplied");
verifyFalse(testCase, result.settings.complete);
verifyTrue(testCase, any(result.issues.code == "MUPET_SETTINGS_NOT_SUPPLIED"));
verifyTrue(testCase, result.ir.valid_for_ingest);
verifyTrue(testCase, result.valid_for_ingest);
end

function testAdapterIsDatabaseIndependentAndHasNoSemanticDictionary(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
files = [
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "mupetExport.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "mupetExportArtifactSpec.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "mupetReadExportTable.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "mupetCaptureSettings.m")];
text = "";
for index = 1:numel(files)
    text = text + newline + string(fileread(files(index)));
end
for forbidden = ["sqlite(", "database(", "execute(", "fetch(", "commit(", ...
        "rollback(", "INSERT ", "SELECT ", "applySchema"]
    verifyFalse(testCase, contains(text, forbidden));
end
for semantic = ["call_start_time", "call_end_time", "call_duration", ...
        "frequency_center", "frequency_bandwidth", "total_energy", ...
        "peak_amplitude", "ms_to_s", "kHz_to_Hz"]
    verifyFalse(testCase, contains(text, semantic), ...
        "MUPET adapter must not restate profile field semantics.");
end

[csvPath, configPath, cleanupFiles] = writeNominalFiles(); %#ok<ASGLU>
result = vawlume.ingest.mupetExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="2.1", SettingsConfigPath=configPath);
verifyEqual(testCase, vawlume.source_mapping.preview(result.ir).verdict, ...
    "READY FOR INGEST");
clear cleanupFiles
end

% ---------------------------------------------------------------- helpers ---

function [repoRoot, cleanupPath] = setUpPath()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
end

function root = repoRootForTest()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

function [csvPath, configPath, cleaner] = writeNominalFiles()
csvPath = writeCsv(tempname + ".csv", nominalExport());
configPath = tempname + ".csv";
writeText(configPath, strjoin(nominalConfigLines(), newline) + newline);
cleaner = onCleanup(@() deleteMany([csvPath, configPath]));
end

function headers = nominalHeaders()
headers = {'Syllable number', 'Syllable start time (sec)', ...
    'Syllable end time (sec)', 'inter-syllable interval (sec)', ...
    'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', ...
    'maximum frequency (kHz)', 'mean frequency (kHz)', ...
    'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
end

function cells = nominalExport()
cells = [
    nominalHeaders()
    {1, 0.100, 0.148, 0.052, 48.0, 45, 60, 40, 75, 55, 35, 12.5, -18}
    {2, 0.200, 0.235, 0.065, 34.7, 46, 59, 41, 74, 54, 33, 11.5, -19}
    {3, 0.300, 0.351, 0.049, 50.2, 47, 61, 42, 76, 56, 34, 10.5, -20}
    {4, 0.400, 0.445, 'NA', 44.9, 48, 62, 43, 77, 57, 34, 9.5, -21}
    ];
end

function lines = nominalConfigLines()
% Native MUPET v2.1 create_configfile.m format: no header, key,value rows.
lines = [
    "noise-reduction,5"
    "minimum-syllable-duration,008"
    "maximum-syllable-duration,200"
    "minimum-syllable-total-energy,-15"
    "minimum-syllable-peak-amplitude,-25"
    "minimum-syllable-distance,5"
    "sample-frequency,250000"
    "minimum-usv-frequency,30000"
    "maximum-usv-frequency,120000"
    "number-filterbank-filters,64"
    "filterbank-type,1"
    ];
end

function path = writeCsv(path, cells)
path = string(path);
deleteIfExists(path);
writecell(cells, path);
end

function value = valueFor(ir, sourceRow, nativeField)
matches = ir.values.source_row == sourceRow & ir.values.native_field == nativeField;
assert(nnz(matches) == 1);
value = table2struct(ir.values(matches,:));
end

function writeText(path, text)
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function makeParent(path)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
end

function removeFolders(folders)
for folder = folders
    if isfolder(folder)
        rmdir(folder, "s");
    end
end
end

function deleteMany(paths)
for path = paths
    deleteIfExists(path);
end
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end
