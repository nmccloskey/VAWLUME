function tests = test_deepsqueak_export_adapter
tests = functiontests({ ...
    @testNominalExportProducesValidExtractorOutputIR, ...
    @testNativeColumnLabelsSurviveWithoutAdapterRenaming, ...
    @testDeclaredAliasStillResolvesThroughProfile, ...
    @testBlankCellIsExplicitMissingWithoutFabricatedToken, ...
    @testMissingRequiredColumnIsDiagnosedBySourceMapping, ...
    @testUnmappedColumnIsWarnedByProfilePolicy, ...
    @testRepeatedHeaderLabelFailsInAdapter, ...
    @testUnreadableAndUnsupportedWorkbooksFailInAdapter, ...
    @testSheetSelectionIsDeterministic, ...
    @testExtractorVersionScopeIsEvaluatedFromProfile, ...
    @testPortableArtifactIdentityIsRootIndependent, ...
    @testDeclaredArtifactIdentityMustBePortable, ...
    @testAdapterPathTouchesNoDatabase});
end

function testNominalExportProducesValidExtractorOutputIR(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

exportPath = writeExport(tempname + ".xlsx", nominalExport());
result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

verifyEqual(testCase, result.artifact.row_count, 3);
verifyEqual(testCase, result.artifact.artifact_key, "event_stats_excel");
verifyEqual(testCase, result.artifact.file_format, "xlsx");
verifyEqual(testCase, result.artifact.native_artifact_type, ...
    "DeepSqueak Excel call-statistics export");
verifyMatches(testCase, result.artifact.checksum_sha256, "^[0-9a-f]{64}$");

ir = result.ir;
verifyEqual(testCase, ir.profile.profile_kind, "extractor_output");
verifyEqual(testCase, ir.profile.extractor_name, "DeepSqueak");
verifyEqual(testCase, ir.profile.profile_key, "vawlume.deepsqueak.output.v3_2");
verifyEqual(testCase, ir.profile.profile_version, "0.1.0");
verifyEqual(testCase, ir.profile.profile_schema_version, "0.2-draft");
verifyEqual(testCase, string(ir.sources.artifact_type(1)), "event_stats_excel");
verifyEqual(testCase, ir.sources.source_row_count(1), 3);
verifyEqual(testCase, height(ir.records), 3);
verifyEqual(testCase, string(ir.records.record_scope), repmat("source_table_row", 3, 1));
verifyEqual(testCase, string(ir.records.native_identifier), ["1"; "2"; "3"]);
verifyTrue(testCase, ir.valid_for_ingest);
verifyTrue(testCase, result.valid_for_ingest);

% Native evidence and the profile-declared canonical result travel together.
start = valueFor(ir, 1, "Begin Time (s)");
verifyEqual(testCase, start.canonical_field, "call_start_time");
verifyEqual(testCase, start.native_value_real, 10.0);
verifyEqual(testCase, start.normalized_value_real, 10.0);
verifyEqual(testCase, start.native_unit, "s");
verifyEqual(testCase, start.canonical_unit, "s");

% A declared transform is applied by source_mapping, never by the adapter.
frequency = valueFor(ir, 1, "Principle Frequency (kHz)");
verifyEqual(testCase, frequency.canonical_field, "contour_median_frequency");
verifyEqual(testCase, frequency.native_value_real, 62.4);
verifyEqual(testCase, frequency.normalized_value_real, 62400);
verifyEqual(testCase, frequency.native_unit, "kHz");
verifyEqual(testCase, frequency.canonical_unit, "Hz");
verifyEqual(testCase, frequency.transform_key, "kHz_to_Hz");

% A declared value map produces the canonical review vocabulary.
accepted = valueFor(ir, 1, "Accepted");
verifyEqual(testCase, accepted.canonical_field, "native_review_status");
verifyEqual(testCase, accepted.raw_value, "1");
verifyEqual(testCase, accepted.normalized_value_text, "accepted");
verifyEqual(testCase, valueFor(ir, 3, "Accepted").normalized_value_text, "rejected");

report = vawlume.source_mapping.preview(ir);
verifyEqual(testCase, report.verdict, "READY FOR INGEST");

clear cleanupExport
end

function testNativeColumnLabelsSurviveWithoutAdapterRenaming(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

exportPath = writeExport(tempname + ".xlsx", nominalExport());
cleanupExport = onCleanup(@() deleteIfExists(exportPath));
result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");

% Headers carrying spaces, parentheses, and slashes must reach source_mapping
% exactly as DeepSqueak wrote them. MATLAB's default naming rule would mangle
% every one of these, and no adapter rename dictionary compensates for it.
expected = string(nominalHeaders());
verifyEqual(testCase, string(result.table.Properties.VariableNames)', expected(:));
verifyEqual(testCase, result.artifact.source_columns, expected(:));
verifyTrue(testCase, ismember("Begin Time (s)", expected));
verifyTrue(testCase, ismember("Mean Power (dB/Hz)", expected));
verifyTrue(testCase, ismember("Slope (kHz/s)", expected));

% Profile resolution succeeded against those exact labels.
verifyTrue(testCase, result.ir.valid_for_ingest);
verifyEqual(testCase, valueFor(result.ir, 1, "Mean Power (dB/Hz)").actual_source_field, ...
    "Mean Power (dB/Hz)");

clear cleanupExport
end

function testDeclaredAliasStillResolvesThroughProfile(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

cells = nominalExport();
cells{1, strcmp(cells(1, :), 'Principle Frequency (kHz)')} = 'Principal Frequency (kHz)';
exportPath = writeExport(tempname + ".xlsx", cells);
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");

% The alternate spelling is resolved by the profile's declared alias, not by an
% adapter-side rename.
frequency = valueFor(result.ir, 1, "Principle Frequency (kHz)");
verifyEqual(testCase, frequency.actual_source_field, "Principal Frequency (kHz)");
verifyEqual(testCase, frequency.canonical_field, "contour_median_frequency");
verifyTrue(testCase, result.ir.valid_for_ingest);

clear cleanupExport
end

function testBlankCellIsExplicitMissingWithoutFabricatedToken(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

exportPath = writeExport(tempname + ".xlsx", nominalExport());
cleanupExport = onCleanup(@() deleteIfExists(exportPath));
result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");

% The DeepSqueak profile declares no lexical missing sentinel, so missingness is
% blank-only. A blank cell must become explicit missingness whose raw token is
% empty: reporting MATLAB's "NaN" would fabricate source evidence.
tonality = valueFor(result.ir, 2, "Tonality");
verifyEqual(testCase, tonality.native_value_type, "missing");
verifyEqual(testCase, tonality.normalized_value_type, "missing");
verifyEqual(testCase, tonality.raw_value, "");
verifyEqual(testCase, tonality.status, "missing");
verifyTrue(testCase, isnan(tonality.native_value_real));

% Explicit missingness is informational and does not block ingest.
verifyTrue(testCase, result.ir.valid_for_ingest);
missingIssues = result.ir.issues(result.ir.issues.code == "MISSING_TOKEN_NORMALIZED", :);
verifyEqual(testCase, height(missingIssues), 1);
verifyEqual(testCase, string(missingIssues.severity), "info");

% A row whose identifier is absent must not publish a fabricated identity.
blankIdPath = writeExport(tempname + ".xlsx", exportWithBlankIdentifier());
cleanupBlank = onCleanup(@() deleteIfExists(blankIdPath));
blank = vawlume.ingest.deepsqueakExport(blankIdPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");
verifyEqual(testCase, string(blank.ir.records.native_identifier(1)), "");
verifyEqual(testCase, string(blank.ir.records.status(1)), "mapped_with_missing");

clear cleanupExport cleanupBlank
end

function testMissingRequiredColumnIsDiagnosedBySourceMapping(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

cells = nominalExport();
cells(:, strcmp(cells(1, :), 'Tonality')) = [];
exportPath = writeExport(tempname + ".xlsx", cells);
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

% The workbook itself is perfectly readable; the fault is semantic and must be
% reported by the mapping layer rather than by the adapter.
result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");
verifyEqual(testCase, result.artifact.row_count, 3);
verifyEqual(testCase, result.adapter_error_count, 0);

columnIssues = result.ir.issues(result.ir.issues.code == "COLUMN_MISSING", :);
verifyEqual(testCase, height(columnIssues), 1);
verifyEqual(testCase, string(columnIssues.severity), "error");
verifyTrue(testCase, columnIssues.affects_validity);
verifyFalse(testCase, result.ir.valid_for_ingest);
verifyFalse(testCase, result.valid_for_ingest);

report = vawlume.source_mapping.preview(result.ir);
verifyEqual(testCase, report.verdict, "NOT READY FOR INGEST");

clear cleanupExport
end

function testUnmappedColumnIsWarnedByProfilePolicy(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

cells = nominalExport();
cells(:, end + 1) = [{'Unexpected Export Column'}; {'a'}; {'b'}; {'c'}];
exportPath = writeExport(tempname + ".xlsx", cells);
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");

% The profile declares mapping_policy.unknown_fields = preserve_and_warn, so an
% undeclared column is a warning rather than a silent drop or a hard failure.
unmapped = result.ir.issues(result.ir.issues.code == "SOURCE_COLUMN_UNMAPPED", :);
verifyEqual(testCase, height(unmapped), 1);
verifyEqual(testCase, string(unmapped.severity), "warning");
verifyFalse(testCase, unmapped.affects_validity);
verifySubstring(testCase, string(unmapped.message), "Unexpected Export Column");
verifyTrue(testCase, result.ir.valid_for_ingest);

clear cleanupExport
end

function testRepeatedHeaderLabelFailsInAdapter(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

cells = nominalExport();
cells(:, end + 1) = [{'Tonality'}; {0.1}; {0.2}; {0.3}];
exportPath = writeExport(tempname + ".xlsx", cells);
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

% MATLAB silently uniquifies repeated variable names, which would hide a
% genuinely ambiguous export behind an invented label. The adapter rejects the
% workbook instead, leaving source_mapping's ambiguity policy authoritative for
% the cases it can actually see.
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(exportPath, RepoRoot=repoRoot), ...
    "vawlume:ingest:DeepSqueakArtifactUnsupported");

clear cleanupExport
end

function testUnreadableAndUnsupportedWorkbooksFailInAdapter(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(tempname + ".xlsx", RepoRoot=repoRoot), ...
    "vawlume:ingest:DeepSqueakArtifactNotFound");

malformedPath = tempname + ".xlsx";
writeText(malformedPath, "this is not a workbook");
cleanupMalformed = onCleanup(@() deleteIfExists(malformedPath));
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(malformedPath, RepoRoot=repoRoot), ...
    "vawlume:ingest:DeepSqueakArtifactUnreadable");

% The profile declares this artifact as xlsx, so another container is refused
% before any semantic mapping is attempted.
csvPath = tempname + ".csv";
writecell(nominalExport(), csvPath);
cleanupCsv = onCleanup(@() deleteIfExists(csvPath));
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(csvPath, RepoRoot=repoRoot), ...
    "vawlume:ingest:DeepSqueakArtifactUnsupported");

clear cleanupMalformed cleanupCsv
end

function testSheetSelectionIsDeterministic(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

exportPath = tempname + ".xlsx";
cleanupExport = onCleanup(@() deleteIfExists(exportPath));
writecell(nominalExport(), exportPath, Sheet="Call Statistics");
writecell({'unrelated'}, exportPath, Sheet="Notes");

% With no override, the profile's declared first_sheet rule decides, and the
% extra sheet is reported rather than silently ignored.
byProfile = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");
verifyEqual(testCase, byProfile.artifact.sheet_index, 1);
verifyEqual(testCase, byProfile.artifact.sheet_name, "Call Statistics");
verifyEqual(testCase, byProfile.artifact.sheet_selection_rule, "profile_first_sheet");
verifyTrue(testCase, any(byProfile.issues.code == "WORKBOOK_MULTIPLE_SHEETS"));

bySheet = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, Sheet="Call Statistics", ExtractorVersion="3.2.1");
verifyEqual(testCase, bySheet.artifact.sheet_selection_rule, "caller_supplied_sheet");
verifyEqual(testCase, bySheet.ir.valid_for_ingest, byProfile.ir.valid_for_ingest);

verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(exportPath, RepoRoot=repoRoot, Sheet="Absent"), ...
    "vawlume:ingest:DeepSqueakArtifactUnsupported");

clear cleanupExport
end

function testExtractorVersionScopeIsEvaluatedFromProfile(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

exportPath = writeExport(tempname + ".xlsx", nominalExport());
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

% The shipped profile declares preferred 3.2.x within compatible family 3.x.
% Compatibility is read from those declarations, not from a release list.
preferred = versionResult(repoRoot, exportPath, "3.2.1");
verifyEqual(testCase, preferred.extractor_version.status, "preferred");
verifyEqual(testCase, preferred.extractor_version.preferred_scope, "3.2.x");
verifyEqual(testCase, preferred.extractor_version.compatible_family, "3.x");
verifyEmpty(testCase, preferred.issues);

family = versionResult(repoRoot, exportPath, "3.1.4");
verifyEqual(testCase, family.extractor_version.status, "compatible_family");
verifyEqual(testCase, family.extractor_version.severity, "info");

incompatible = versionResult(repoRoot, exportPath, "2.9.0");
verifyEqual(testCase, incompatible.extractor_version.status, "incompatible");
verifyEqual(testCase, incompatible.extractor_version.severity, "warning");
verifyTrue(testCase, any(incompatible.issues.code == "EXTRACTOR_VERSION_INCOMPATIBLE"));

% The workbook encodes no trustworthy version, so an absent one is reported
% rather than invented. The profile declares version_required_at_ingest, which
% makes this a warning here and a blocking condition for the database importer.
absent = versionResult(repoRoot, exportPath, "");
verifyEqual(testCase, absent.extractor_version.status, "missing_required");
verifyTrue(testCase, absent.extractor_version.required_at_ingest);
verifyEqual(testCase, absent.extractor_version.severity, "warning");
verifyEqual(testCase, absent.extractor_version.declared_version, "");

% Reading stays possible for inspection in every case above.
verifyTrue(testCase, absent.ir.valid_for_ingest);
verifyTrue(testCase, incompatible.ir.valid_for_ingest);

clear cleanupExport
end

function testPortableArtifactIdentityIsRootIndependent(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

firstRoot = fullfile(tempdir, "vawlume_ds_root_a");
secondRoot = fullfile(tempdir, "vawlume_ds_root_b");
firstPath = fullfile(firstRoot, "exports", "day1", "REC_A_Stats.xlsx");
secondPath = fullfile(secondRoot, "exports", "day1", "REC_A_Stats.xlsx");
makeParentFolder(firstPath);
makeParentFolder(secondPath);
writeExport(firstPath, nominalExport());
writeExport(secondPath, nominalExport());
cleanupRoots = onCleanup(@() removeFolders([firstRoot, secondRoot]));

first = vawlume.ingest.deepsqueakExport(firstPath, ...
    RepoRoot=repoRoot, ArtifactRoot=firstRoot, ExtractorVersion="3.2.1");
second = vawlume.ingest.deepsqueakExport(secondPath, ...
    RepoRoot=repoRoot, ArtifactRoot=secondRoot, ExtractorVersion="3.2.1");

% The same artifact under a different absolute root keeps one portable identity
% and one source key, which is what later ingest must rely on to avoid false
% duplication. Runtime paths remain visible but are not that identity.
verifyEqual(testCase, first.artifact.relative_path, "exports/day1/REC_A_Stats.xlsx");
verifyEqual(testCase, first.artifact.relative_path_source, "artifact_root");
verifyEqual(testCase, second.artifact.relative_path, first.artifact.relative_path);
verifyEqual(testCase, second.source_key, first.source_key);
verifyEqual(testCase, second.artifact.checksum_sha256, first.artifact.checksum_sha256);
verifyNotEqual(testCase, second.artifact.runtime_path, first.artifact.runtime_path);
verifyFalse(testCase, contains(first.source_key, firstRoot));

% An explicitly declared portable path takes precedence over root derivation.
declared = vawlume.ingest.deepsqueakExport(firstPath, RepoRoot=repoRoot, ...
    RelativePath="extractor_outputs/REC_A_Stats.xlsx", ExtractorVersion="3.2.1");
verifyEqual(testCase, declared.artifact.relative_path_source, "declared");
verifyEqual(testCase, declared.artifact.relative_path, ...
    "extractor_outputs/REC_A_Stats.xlsx");

% With no declared root the adapter reports the location as unavailable rather
% than presenting a runtime path as though it were portable.
orphanPath = writeExport(tempname + ".xlsx", nominalExport());
cleanupOrphan = onCleanup(@() deleteIfExists(orphanPath));
orphan = vawlume.ingest.deepsqueakExport(orphanPath, ...
    ProfilePath=trackedProfilePath(repoRoot), ExtractorVersion="3.2.1");
verifyEqual(testCase, orphan.artifact.relative_path, "");
verifyEqual(testCase, orphan.artifact.relative_path_source, "unavailable");
verifyFalse(testCase, contains(orphan.source_key, tempdir));

clear cleanupRoots cleanupOrphan
end

function testDeclaredArtifactIdentityMustBePortable(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

exportPath = writeExport(tempname + ".xlsx", nominalExport());
cleanupExport = onCleanup(@() deleteIfExists(exportPath));

% A caller-declared identity bypasses root containment, so absolute and
% parent-traversing values must be refused rather than persisted as though they
% were portable.
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(exportPath, RepoRoot=repoRoot, ...
    RelativePath=string(exportPath), ExtractorVersion="3.2.1"), ...
    "vawlume:ingest:DeepSqueakArtifactNotPortable");
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(exportPath, RepoRoot=repoRoot, ...
    RelativePath="../exports/REC_A_Stats.xlsx", ExtractorVersion="3.2.1"), ...
    "vawlume:ingest:DeepSqueakArtifactNotPortable");
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueakExport(exportPath, RepoRoot=repoRoot, ...
    RelativePath="/exports/REC_A_Stats.xlsx", ExtractorVersion="3.2.1"), ...
    "vawlume:ingest:DeepSqueakArtifactNotPortable");

normalized = vawlume.ingest.deepsqueakExport(exportPath, RepoRoot=repoRoot, ...
    RelativePath="exports\\day1\\.\\REC_A_Stats.xlsx", ...
    ExtractorVersion="3.2.1");
verifyEqual(testCase, normalized.artifact.relative_path, ...
    "exports/day1/REC_A_Stats.xlsx");

clear cleanupExport
end

function testAdapterPathTouchesNoDatabase(testCase)
[repoRoot, cleanupPath] = setUpPath(); %#ok<ASGLU>

% Static boundary: the DeepSqueak adapter reads artifacts and delegates
% semantics. It must not open a database, execute SQL, or carry a
% native-to-canonical dictionary of its own.
adapterFiles = [ ...
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "deepsqueakExport.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "deepsqueakExportArtifactSpec.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "deepsqueakPortableLocation.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "deepsqueakReadExportTable.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "deepsqueakVersionCompatibility.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "extractorArtifactSpec.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "extractorPortableLocation.m")
    fullfile(repoRoot, "src", "+vawlume", "+ingest", "private", "extractorVersionCompatibility.m")];

text = "";
for index = 1:numel(adapterFiles)
    verifyTrue(testCase, isfile(adapterFiles(index)));
    text = text + newline + string(fileread(adapterFiles(index)));
end

for forbidden = ["sqlite(", "database(", "execute(", "fetch(", "commit(", ...
        "rollback(", "INSERT ", "SELECT ", "applySchema"]
    verifyFalse(testCase, contains(text, forbidden), ...
        "The DeepSqueak adapter must not perform database access.");
end

% Canonical field names belong to the tracked profile. Their appearance in the
% adapter would mean a second semantic dictionary had been created.
for canonicalName = ["call_start_time", "call_end_time", "call_duration", ...
        "contour_median_frequency", "frequency_min", "frequency_max", ...
        "native_review_status", "native_detection_score", "kHz_to_Hz"]
    verifyFalse(testCase, contains(text, canonicalName), ...
        "The DeepSqueak adapter must not restate profile field semantics.");
end

% Runtime boundary: a complete read plus preview needs no connection at all.
exportPath = writeExport(tempname + ".xlsx", nominalExport());
cleanupExport = onCleanup(@() deleteIfExists(exportPath));
result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion="3.2.1");
report = vawlume.source_mapping.preview(result.ir);
verifyEqual(testCase, report.verdict, "READY FOR INGEST");
verifyTrue(testCase, report.ir_derived);

clear cleanupExport
end

% ---------------------------------------------------------------- helpers ---

function [repoRoot, cleanupPath] = setUpPath()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

function path = trackedProfilePath(repoRoot)
path = fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", ...
    "deepsqueak", "deepsqueak_output_mapping_profile.json");
end

function headers = nominalHeaders()
% Exact DeepSqueak v3.2 call-statistics export labels, including the software's
% own "Principle" spelling and its parenthesised units.
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
end

function cells = nominalExport()
% Three deterministic synthetic calls: two accepted and one rejected, distinct
% native identifiers, a transform-exercising frequency, and one blank optional
% measurement. No research data is involved.
detectionFile = 'C:\deepsqueak\detections\REC_A_deepsqueak.mat';
cells = [
    nominalHeaders()
    {detectionFile, 1, '22kHz-Call', 1, 0.9134, 10.000, 10.050, 0.050, ...
        62.4, 45.1, 80.2, 35.1, 3.2, -120.5, 1.12, -71.4, 0.78, 63.0}
    {detectionFile, 2, 'USV', 1, 0.8021, 20.000, 20.040, 0.040, ...
        61.0, 50.0, 72.0, 22.0, 2.1, 15.0, 1.05, -70.1, [], 61.5}
    {detectionFile, 3, 'Noise', 0, 0.2107, 40.000, 40.100, 0.100, ...
        63.5, 42.0, 84.0, 42.0, 4.4, -8.25, 1.40, -69.3, 0.69, 64.2}
];
end

function cells = exportWithBlankIdentifier()
cells = nominalExport();
cells = cells(1:2, :);
cells{2, 2} = [];
end

function path = writeExport(path, cells)
path = string(path);
deleteIfExists(path);
% Cell-based writing keeps header labels byte-exact, including spaces,
% parentheses, and slashes that table variable naming would otherwise touch.
writecell(cells, path);
end

function value = valueFor(ir, sourceRow, nativeField)
matches = ir.values.source_row == sourceRow & ir.values.native_field == nativeField;
assert(nnz(matches) == 1, "Expected one IR value for row %d field %s, found %d.", ...
    sourceRow, nativeField, nnz(matches));
value = table2struct(ir.values(matches, :));
end

function result = versionResult(repoRoot, exportPath, declaredVersion)
result = vawlume.ingest.deepsqueakExport(exportPath, ...
    RepoRoot=repoRoot, ExtractorVersion=declaredVersion);
end

function verifySubstring(testCase, actual, expected)
verifyTrue(testCase, contains(actual, expected), ...
    "Expected '" + actual + "' to contain '" + expected + "'.");
end

function makeParentFolder(path)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
end

function removeFolders(folders)
for index = 1:numel(folders)
    if isfolder(folders(index))
        rmdir(folders(index), "s");
    end
end
end

function writeText(path, text)
fileId = fopen(path, "w");
assert(fileId >= 0, "Could not open %s for writing.", path);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end
