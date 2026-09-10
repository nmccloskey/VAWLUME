function tests = test_usvseg_export_adapter
tests = functiontests({ ...
    @testNominalExportProducesValidatedExtractorIR, ...
    @testLiteralHeaderAndLexicalTokensSurvive, ...
    @testHeaderOnlyExportIsValidZeroDetectionResult, ...
    @testMissingRequiredFieldIsNotRepaired, ...
    @testUndeclaredMissingTokenIsPreservedAndRejected, ...
    @testNonfiniteNumericTokenIsPreservedAndWarned, ...
    @testVersionScopeComesFromProfile, ...
    @testExtraColumnRemainsRecoverableAndWarns, ...
    @testPathFormatAndPortableIdentityGuards, ...
    @testAdapterIsDatabaseIndependentAndHasNoSemanticDictionary});
end

function testNominalExportProducesValidatedExtractorIR(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, cleanupFile] = writeNominalExport(); %#ok<ASGLU>

result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");

verifyTrue(testCase, result.valid_for_ingest);
verifyEqual(testCase, result.artifact.artifact_key, "usvseg_dat_csv");
verifyEqual(testCase, result.artifact.file_format, "csv");
verifyEqual(testCase, result.artifact.row_count, 2);
verifyEqual(testCase, result.artifact.column_count, 8);
verifyMatches(testCase, result.artifact.checksum_sha256, "^[0-9a-f]{64}$");
verifyEqual(testCase, result.ir.profile.profile_key, ...
    "vawlume.usvseg.output.v0_9r2");
verifyEqual(testCase, result.ir.profile.profile_version, "0.1.0");
verifyEqual(testCase, result.ir.profile.extractor_name, "USVSEG");
verifyEqual(testCase, height(result.ir.records), 2);
verifyEqual(testCase, string(result.ir.records.native_identifier), ["1"; "2"]);
verifyEqual(testCase, height(result.ir.values), 16);

onset = valueFor(result.ir, 1, "start");
verifyEqual(testCase, onset.native_value_real, 0.1, AbsTol=1e-12);
verifyEqual(testCase, onset.normalized_value_real, 0.1, AbsTol=1e-12);
verifyEqual(testCase, onset.canonical_field, "call_start_time");

offset = valueFor(result.ir, 1, "end");
verifyEqual(testCase, offset.normalized_value_real, 0.145, AbsTol=1e-12);
duration = valueFor(result.ir, 1, "duration");
verifyEqual(testCase, duration.native_value_real, 45, AbsTol=1e-12);
verifyEqual(testCase, duration.normalized_value_real, 0.045, AbsTol=1e-12);
verifyEqual(testCase, duration.transform_key, "ms_to_s");

peak = valueFor(result.ir, 1, "maxfreq");
verifyEqual(testCase, peak.native_value_real, 72.5, AbsTol=1e-12);
verifyEqual(testCase, peak.normalized_value_real, 72500, AbsTol=1e-9);
verifyEqual(testCase, peak.transform_key, "kHz_to_Hz");
verifyEqual(testCase, vawlume.source_mapping.preview(result.ir).verdict, ...
    "READY FOR INGEST");
end

function testLiteralHeaderAndLexicalTokensSurvive(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, cleanupFile] = writeNominalExport(); %#ok<ASGLU>
result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");

expected = headerNames();
verifyEqual(testCase, string(result.table.Properties.VariableNames)', expected);
verifyEqual(testCase, result.artifact.source_columns, expected);
verifyEqual(testCase, result.artifact.lexical_columns, expected);
verifyTrue(testCase, all(varfun(@isstring, result.table, OutputFormat="uniform")));
verifyEqual(testCase, result.table.("#")(1), "1");
verifyEqual(testCase, result.table.start(1), "0.1000");
verifyEqual(testCase, result.table.duration(1), "45.0");
verifyEqual(testCase, valueFor(result.ir, 1, "start").raw_value, "0.1000");
verifyEqual(testCase, valueFor(result.ir, 1, "maxfreq").raw_value, "72.500");
end

function testHeaderOnlyExportIsValidZeroDetectionResult(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
csvPath = temporaryExportPath();
writeText(csvPath, strjoin(headerNames(), ",") + newline);
cleanupFile = onCleanup(@() deleteIfExists(csvPath));

result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
verifyTrue(testCase, result.valid_for_ingest);
verifyEqual(testCase, result.artifact.row_count, 0);
verifyEqual(testCase, result.artifact.column_count, 8);
verifyEmpty(testCase, result.ir.records);
verifyEmpty(testCase, result.ir.values);
verifyEmpty(testCase, result.issues);
verifyEqual(testCase, height(result.ir.sources), 1);
verifyEqual(testCase, result.ir.sources.status, "mapped");
end

function testMissingRequiredFieldIsNotRepaired(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
lines = nominalLines();
lines = erase(lines, ",meanfreq");
lines(2:end) = regexprep(lines(2:end), ",61\.250,", ",");
lines(3:end) = regexprep(lines(3:end), ",63\.125,", ",");
csvPath = temporaryExportPath();
writeText(csvPath, strjoin(lines, newline) + newline);
cleanupFile = onCleanup(@() deleteIfExists(csvPath));

result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
verifyFalse(testCase, result.valid_for_ingest);
verifyTrue(testCase, any(result.ir.issues.code == "COLUMN_MISSING"));
verifyFalse(testCase, ismember("meanfreq", ...
    string(result.table.Properties.VariableNames)));
end

function testUndeclaredMissingTokenIsPreservedAndRejected(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
lines = nominalLines();
lines(2) = replace(lines(2), ",0.1234", ",NA");
csvPath = temporaryExportPath();
writeText(csvPath, strjoin(lines, newline) + newline);
cleanupFile = onCleanup(@() deleteIfExists(csvPath));

result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
value = valueFor(result.ir, 1, "cvfreq");
verifyEqual(testCase, value.raw_value, "NA");
verifyEqual(testCase, value.native_value_type, "invalid");
verifyEqual(testCase, value.normalized_value_type, "invalid");
verifyFalse(testCase, result.valid_for_ingest);
verifyTrue(testCase, any(result.ir.issues.code == "TYPE_COERCION_FAILED"));
verifyTrue(testCase, any(result.issues.code == "USVSEG_NUMERIC_TOKEN_NONFINITE"));
end

function testNonfiniteNumericTokenIsPreservedAndWarned(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
lines = nominalLines();
lines(2) = replace(lines(2), ",61.250,", ",Inf,");
csvPath = temporaryExportPath();
writeText(csvPath, strjoin(lines, newline) + newline);
cleanupFile = onCleanup(@() deleteIfExists(csvPath));

result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
value = valueFor(result.ir, 1, "meanfreq");
verifyEqual(testCase, value.raw_value, "Inf");
verifyEqual(testCase, value.native_value_real, Inf);
verifyTrue(testCase, result.valid_for_ingest);
verifyTrue(testCase, any(result.issues.code == "USVSEG_NUMERIC_TOKEN_NONFINITE"));
verifyEqual(testCase, result.adapter_warning_count, 1);
end

function testVersionScopeComesFromProfile(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
[csvPath, cleanupFile] = writeNominalExport(); %#ok<ASGLU>

preferred = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
verifyEqual(testCase, preferred.extractor_version.status, "preferred");

missing = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot);
verifyEqual(testCase, missing.extractor_version.status, "missing_required");
verifyTrue(testCase, any(missing.issues.code == ...
    "EXTRACTOR_VERSION_MISSING_REQUIRED"));

incompatible = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.8r7");
verifyEqual(testCase, incompatible.extractor_version.status, "incompatible");
verifyTrue(testCase, any(incompatible.issues.code == ...
    "EXTRACTOR_VERSION_INCOMPATIBLE"));
verifyTrue(testCase, incompatible.valid_for_ingest);
end

function testExtraColumnRemainsRecoverableAndWarns(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
lines = nominalLines();
lines(1) = lines(1) + ",future_metric";
lines(2) = lines(2) + ",0007.50";
lines(3) = lines(3) + ",0008.25";
csvPath = temporaryExportPath();
writeText(csvPath, strjoin(lines, newline) + newline);
cleanupFile = onCleanup(@() deleteIfExists(csvPath));

result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
verifyTrue(testCase, result.valid_for_ingest);
verifyTrue(testCase, ismember("future_metric", ...
    string(result.table.Properties.VariableNames)));
verifyEqual(testCase, result.table.future_metric, ["0007.50"; "0008.25"]);
unmapped = result.ir.issues(result.ir.issues.code == "SOURCE_COLUMN_UNMAPPED", :);
verifyEqual(testCase, height(unmapped), 1);
verifyEqual(testCase, unmapped.severity, "warning");
verifyTrue(testCase, contains(unmapped.message, "future_metric"));
end

function testPathFormatAndPortableIdentityGuards(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
verifyError(testCase, ...
    @() vawlume.ingest.usvsegExport(temporaryExportPath(), RepoRoot=repoRoot), ...
    "vawlume:ingest:UsvsegArtifactNotFound");

txtPath = string(tempname) + "_dat.txt";
writeText(txtPath, "not,csv" + newline);
cleanupTxt = onCleanup(@() deleteIfExists(txtPath));
verifyError(testCase, ...
    @() vawlume.ingest.usvsegExport(txtPath, RepoRoot=repoRoot), ...
    "vawlume:ingest:UsvsegArtifactUnsupported");

wrongDelimiter = temporaryExportPath();
writeText(wrongDelimiter, "#;start;end" + newline + "1;0.1;0.2" + newline);
cleanupWrongDelimiter = onCleanup(@() deleteIfExists(wrongDelimiter));
verifyError(testCase, ...
    @() vawlume.ingest.usvsegExport(wrongDelimiter, RepoRoot=repoRoot), ...
    "vawlume:ingest:UsvsegArtifactUnsupported");

rootA = string(tempname);
rootB = string(tempname);
pathA = fullfile(rootA, "exports", "REC_A_dat.csv");
pathB = fullfile(rootB, "exports", "REC_A_dat.csv");
makeParent(pathA);
makeParent(pathB);
writeText(pathA, strjoin(nominalLines(), newline) + newline);
writeText(pathB, strjoin(nominalLines(), newline) + newline);
cleanupRoots = onCleanup(@() removeFolders([rootA, rootB]));

first = vawlume.ingest.usvsegExport(pathA, RepoRoot=repoRoot, ...
    ArtifactRoot=rootA, ExtractorVersion="0.9r2");
second = vawlume.ingest.usvsegExport(pathB, RepoRoot=repoRoot, ...
    ArtifactRoot=rootB, ExtractorVersion="0.9r2");
verifyEqual(testCase, first.artifact.relative_path, "exports/REC_A_dat.csv");
verifyEqual(testCase, second.source_key, first.source_key);
verifyEqual(testCase, second.artifact.checksum_sha256, ...
    first.artifact.checksum_sha256);
verifyNotEqual(testCase, second.artifact.runtime_path, first.artifact.runtime_path);

verifyError(testCase, ...
    @() vawlume.ingest.usvsegExport(pathA, RepoRoot=repoRoot, ...
    RelativePath="../REC_A_dat.csv"), ...
    "vawlume:ingest:UsvsegArtifactNotPortable");
end

function testAdapterIsDatabaseIndependentAndHasNoSemanticDictionary(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>
files = [
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "usvsegExport.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", ...
        "usvsegExportArtifactSpec.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", ...
        "usvsegPortableLocation.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", ...
        "usvsegReadExportTable.m")];
text = "";
for index = 1:numel(files)
    text = text + newline + string(fileread(files(index)));
end
for forbidden = ["sqlite(", "database(", "execute(", "fetch(", "commit(", ...
        "rollback(", "INSERT ", "SELECT ", "applySchema"]
    verifyFalse(testCase, contains(text, forbidden));
end
for semantic = ["call_start_time", "call_end_time", "call_duration", ...
        "peak_frequency", "peak_amplitude", "frequency_center", ...
        "frequency_cv", "ms_to_s", "kHz_to_Hz"]
    verifyFalse(testCase, contains(text, semantic), ...
        "USVSEG adapter must not restate profile field semantics.");
end

[csvPath, cleanupFile] = writeNominalExport(); %#ok<ASGLU>
result = vawlume.ingest.usvsegExport(csvPath, RepoRoot=repoRoot, ...
    ExtractorVersion="0.9r2");
verifyEqual(testCase, vawlume.source_mapping.preview(result.ir).verdict, ...
    "READY FOR INGEST");
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

function [path, cleaner] = writeNominalExport()
path = temporaryExportPath();
writeText(path, strjoin(nominalLines(), newline) + newline);
cleaner = onCleanup(@() deleteIfExists(path));
end

function names = headerNames()
names = ["#"; "start"; "end"; "duration"; "maxfreq"; "maxamp"; ...
    "meanfreq"; "cvfreq"];
end

function lines = nominalLines()
lines = [
    strjoin(headerNames(), ",")
    "1,0.1000,0.1450,45.0,72.500,-18.25,61.250,0.1234"
    "2,0.3000,0.3325,32.5,75.125,-20.50,63.125,0.0875"
    ];
end

function path = temporaryExportPath()
path = string(tempname) + "_dat.csv";
end

function value = valueFor(ir, sourceRow, nativeField)
matches = ir.values.source_row == sourceRow & ir.values.native_field == nativeField;
assert(nnz(matches) == 1);
value = table2struct(ir.values(matches, :));
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

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end
