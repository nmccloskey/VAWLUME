function tests = test_export_package
% The public export API end to end: vawlume.export.database and the package it
% publishes.
%
% What is asserted:
%   - the exact package tree, the exact metadata projection schemas (contract
%     §G.2), and that the files agree with each other and with the result;
%   - descriptions come from the semantic JSON, including inherited view
%     columns, and the projections describe the whole schema whatever was
%     selected (§B.7);
%   - schema-only mode reads no database, writes no csv/, and cannot be taken
%     for a data export (§H);
%   - the README is rendered from the package record: changing a fact changes
%     the README;
%   - unsupported formats and invalid options fail before anything exists;
%   - the destination rules (§F) and atomic publication: an injected failure
%     after the data files are written leaves the destination absent or holding
%     its previous package, byte for byte, and leaves no staging behind.
%
% Metadata files are read with an RFC 4180 reader local to this test that keeps
% the quoted/unquoted distinction, so a blank field (not applicable) and an
% empty text value cannot be confused.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
testCase.addTeardown(@() rmpath(fullfile(repoRoot, "src")));
workspace = string(tempname);
mkdir(workspace);
testCase.addTeardown(@() rmdir(workspace, "s"));
mkdir(fullfile(workspace, "db"));
fixture = fullfile(workspace, "db", "fixture.sqlite");
[conn, ~] = vawlume.db.createPhase1FixtureDatabase(fixture, repoRoot);
close(conn);
testCase.TestData.repoRoot = repoRoot;
testCase.TestData.workspace = workspace;
testCase.TestData.fixture = fixture;
testCase.TestData.structure = vawlume.schema.loadStructure(RepoRoot=repoRoot);
testCase.TestData.metadata = vawlume.schema.loadMetadata(RepoRoot=repoRoot);
end

function setup(testCase)
area = fullfile(testCase.TestData.workspace, "t_" + string(java.util.UUID.randomUUID));
mkdir(area);
testCase.TestData.area = area;
end

% --- the normal package -----------------------------------------------------------

function testTheNormalPackageHasTheExactTree(testCase)
output = fullfile(testCase.TestData.area, "vawlume_export");
result = vawlume.export.database(testCase.TestData.fixture, Output=output);

tables = testCase.TestData.structure.objects;
tables = sortrows(tables(tables.object_kind == "table", :), "position");
expected = ["README.md"; "meta/columns.csv"; "meta/manifest.csv"; ...
    "meta/relationships.csv"; "meta/tables.csv"; "csv/" + tables.object_name + ".csv"];
verifyEqual(testCase, sort(packageFiles(output)), sort(expected));
verifyEqual(testCase, sort(result.files), sort(expected));
verifyEqual(testCase, result.output_dir, string(java.io.File(char(output)).getCanonicalPath()));
verifyEqual(testCase, result.mode, "normal");
verifyEqual(testCase, result.format, "csv");
verifyEqual(testCase, result.exported_object_count, height(tables));
verifyEmpty(testCase, siblingsLeftBehind(testCase.TestData.area), ...
    "Publication must leave no staging or previous-package directory behind.");
end

function testTablesCsvAgreesWithTheResultAndTheFiles(testCase)
output = fullfile(testCase.TestData.area, "pkg");
result = vawlume.export.database(testCase.TestData.fixture, Output=output, IncludeViews=true);
tablesCsv = readCsv(fullfile(output, "meta", "tables.csv"));

verifyEqual(testCase, tablesCsv.header, ["object_name", "object_kind", "description", ...
    "exported", "row_count", "filename"]);
objects = sortrows(testCase.TestData.structure.objects, "position");
verifyEqual(testCase, tablesCsv.column("object_name"), objects.object_name);
verifyEqual(testCase, tablesCsv.column("object_kind"), objects.object_kind);
verifyEqual(testCase, tablesCsv.column("exported"), repmat("true", height(objects), 1));
verifyEqual(testCase, str2double(tablesCsv.column("row_count")), result.objects.row_count);
verifyEqual(testCase, tablesCsv.column("filename"), "csv/" + objects.object_name + ".csv");
for k = 1:height(objects)
    rows = readCsv(fullfile(output, "csv", objects.object_name(k) + ".csv"));
    verifyEqual(testCase, rows.count, result.objects.row_count(k), ...
        "Data file rows for " + objects.object_name(k));
end
end

function testManifestRowsAreExactInNormalMode(testCase)
output = fullfile(testCase.TestData.area, "pkg");
result = vawlume.export.database(testCase.TestData.fixture, Output=output, ...
    Tables=["projects", "v_detection_core"]);
manifest = readCsv(fullfile(output, "meta", "manifest.csv"));
verifyEqual(testCase, manifest.header, ["key", "value", "detail"]);
verifyEqual(testCase, manifest.column("key"), manifestKeys());

value = @(key) manifest.values(manifest.column("key") == key, 2);
detail = @(key) manifest.values(manifest.column("key") == key, 3);
isBlank = @(key) ~manifest.quoted(find(manifest.column("key") == key, 1), 2);
verifyEqual(testCase, value("package_format"), "vawlume_csv_export");
verifyEqual(testCase, value("export_mode"), "normal");
verifyEqual(testCase, value("export_format"), "csv");
verifyMatches(testCase, value("exported_at_utc"), "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$");
verifyEqual(testCase, value("source_database_filename"), "fixture.sqlite");
verifyFalse(testCase, contains(value("source_database_filename"), ["\", "/"]), ...
    "The manifest must record a filename, never a path.");
listing = dir(testCase.TestData.fixture);
verifyEqual(testCase, value("source_database_bytes"), string(listing.bytes));
verifyEqual(testCase, value("source_schema_version"), result.source.schema_version);
verifyEqual(testCase, value("repository_schema_version"), ...
    vawlume.schema.repositoryVersion(RepoRoot=testCase.TestData.repoRoot));
verifyEqual(testCase, value("metadata_version"), testCase.TestData.metadata.metadata_version);
verifyTrue(testCase, isBlank("vawlume_version"));
verifyEqual(testCase, detail("vawlume_version"), "not_available");
verifyEqual(testCase, value("supported_object_count"), "107");
verifyEqual(testCase, value("selected_object_count"), "2");
verifyEqual(testCase, value("exported_object_count"), "2");
verifyEqual(testCase, value("exported_row_total"), string(result.exported_row_total));
verifyEqual(testCase, value("data_file_count"), "2");
verifyEqual(testCase, value("null_representation"), "empty_unquoted_field");
verifyEqual(testCase, value("real_representation"), "printf_%!.17g");
verifyEqual(testCase, value("line_terminator"), "CRLF");
verifyEqual(testCase, value("warning_count"), "0");
end

function testDescriptionsComeFromTheSemanticJson(testCase)
output = fullfile(testCase.TestData.area, "pkg");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=output, Tables="projects");
metadata = testCase.TestData.metadata;

tablesCsv = readCsv(fullfile(output, "meta", "tables.csv"));
names = tablesCsv.column("object_name");
[~, at] = ismember(names, metadata.objects.object_name);
verifyEqual(testCase, tablesCsv.column("description"), metadata.objects.description(at));

columnsCsv = readCsv(fullfile(output, "meta", "columns.csv"));
verifyEqual(testCase, columnsCsv.header, ["object_name", "column_name", ...
    "column_position", "description", "description_source"]);
verifyEqual(testCase, columnsCsv.count, height(testCase.TestData.structure.columns));
% A view column that points at a base column shows that column's description
% and says where it came from.
pointer = columnsCsv.column("object_name") == "v_detection_core" & ...
    columnsCsv.column("column_name") == "detection_id";
verifyEqual(testCase, columnsCsv.values(pointer, 5), "inherited:detections.detection_id");
target = columnsCsv.column("object_name") == "detections" & ...
    columnsCsv.column("column_name") == "detection_id";
verifyEqual(testCase, columnsCsv.values(pointer, 4), columnsCsv.values(target, 4));
verifyEqual(testCase, columnsCsv.values(target, 5), "authored");
verifyGreaterThan(testCase, sum(startsWith(columnsCsv.column("description_source"), "inherited:")), 0);
verifyFalse(testCase, any(columnsCsv.column("description") == "" | ...
    ismissing(columnsCsv.column("description"))), "Every column must have a description.");
% Columns in declared order within schema order.
verifyEqual(testCase, columnsCsv.values(1, 1:3), ["schema_info", "schema_version", "1"]);

relationships = readCsv(fullfile(output, "meta", "relationships.csv"));
verifyEqual(testCase, relationships.header, ["source_table", "source_column", ...
    "target_table", "target_column", "description"]);
verifyEqual(testCase, relationships.count, height(testCase.TestData.structure.relations));
% Child to parent: detections holds the key to extraction_runs.
childToParent = relationships.column("source_table") == "detections" & ...
    relationships.column("target_table") == "extraction_runs";
verifyEqual(testCase, relationships.values(childToParent, 2), "extraction_run_id");
verifyFalse(testCase, any(relationships.column("source_table") == "extraction_runs" & ...
    relationships.column("target_table") == "detections"));
end

function testSelectionSurvivesFromApiToDataAndMetadata(testCase)
output = fullfile(testCase.TestData.area, "pkg");
result = vawlume.export.database(testCase.TestData.fixture, Output=output, ...
    Tables=["v_detection_core", "detections"], IncludeViews=false);

verifyEqual(testCase, sort(packageFiles(fullfile(output, "csv"))), ...
    ["detections.csv"; "v_detection_core.csv"]);
tablesCsv = readCsv(fullfile(output, "meta", "tables.csv"));
exported = tablesCsv.column("exported") == "true";
verifyEqual(testCase, tablesCsv.column("object_name", exported), ["detections"; "v_detection_core"]);
verifyEqual(testCase, tablesCsv.column("object_kind", exported), ["table"; "view"]);
% Unexported objects: false, with row_count and filename blank (not "").
verifyEqual(testCase, unique(tablesCsv.column("exported", ~exported)), "false");
verifyFalse(testCase, any(tablesCsv.quoted(~exported, 5)) || any(tablesCsv.quoted(~exported, 6)));
verifyEqual(testCase, result.objects.exported, exported);
% The metadata still describes the whole schema.
verifyEqual(testCase, tablesCsv.count, 107);
verifyEqual(testCase, readCsv(fullfile(output, "meta", "relationships.csv")).count, ...
    height(testCase.TestData.structure.relations));
end

% --- schema-only --------------------------------------------------------------------

function testSchemaOnlyWritesNoDataAndClaimsNone(testCase)
output = fullfile(testCase.TestData.area, "schema_reference");
result = vawlume.export.database(Output=output, SchemaOnly=true);

verifyEqual(testCase, sort(packageFiles(output)), sort(["README.md"; ...
    "meta/columns.csv"; "meta/manifest.csv"; "meta/relationships.csv"; "meta/tables.csv"]));
verifyFalse(testCase, isfolder(fullfile(output, "csv")), "Not even an empty csv/.");
verifyEqual(testCase, result.mode, "schema_only");
verifyEmpty(testCase, result.source);
verifyEqual(testCase, [result.selected_object_count, result.exported_object_count, ...
    result.exported_row_total], [0 0 0]);

tablesCsv = readCsv(fullfile(output, "meta", "tables.csv"));
verifyEqual(testCase, tablesCsv.count, 107);
verifyEqual(testCase, unique(tablesCsv.column("exported")), "false");
verifyFalse(testCase, any(tablesCsv.quoted(:, 5)) || any(tablesCsv.quoted(:, 6)), ...
    "No row count or filename may appear in schema-only mode.");

manifest = readCsv(fullfile(output, "meta", "manifest.csv"));
verifyEqual(testCase, manifest.column("key"), manifestKeys());
rowOf = @(key) find(manifest.column("key") == key, 1);
verifyEqual(testCase, manifest.values(rowOf("export_mode"), 2), "schema_only");
for key = ["source_database_filename", "source_database_bytes", ...
        "source_schema_version", "source_user_version"]
    verifyFalse(testCase, manifest.quoted(rowOf(key), 2), key + " must be blank.");
    verifyEqual(testCase, manifest.values(rowOf(key), 3), "not_applicable");
end
verifyEqual(testCase, manifest.values(rowOf("selected_object_count"), 2:3), ["0", "schema_only"]);
for key = ["exported_object_count", "exported_row_total", "data_file_count"]
    verifyEqual(testCase, manifest.values(rowOf(key), 2), "0");
end

readme = fileread(fullfile(output, "README.md"));
verifySubstring(testCase, readme, "It contains no experimental data");
verifyFalse(testCase, contains(readme, "Source database"));
end

function testSchemaOnlyMetadataIsIdenticalToNormalMode(testCase)
% The projections are not selection-scoped (contract §B.7), so the schema
% description a recipient reads does not depend on what was exported.
normal = fullfile(testCase.TestData.area, "normal");
reference = fullfile(testCase.TestData.area, "reference");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=normal, Tables="projects");
[~] = vawlume.export.database(Output=reference, SchemaOnly=true);
for file = ["columns.csv", "relationships.csv"]
    verifyEqual(testCase, readBytes(fullfile(reference, "meta", file)), ...
        readBytes(fullfile(normal, "meta", file)), file);
end
end

function testSchemaOnlyRefusesASourceOrASelection(testCase)
output = fullfile(testCase.TestData.area, "never");
fixture = testCase.TestData.fixture;
verifyError(testCase, @() vawlume.export.database(fixture, Output=output, SchemaOnly=true), ...
    "vawlume:export:SchemaOnlyWithSource");
verifyError(testCase, @() vawlume.export.database(Output=output, SchemaOnly=true, ...
    SourceIdentifier="study-1"), "vawlume:export:SchemaOnlyWithSource");
verifyError(testCase, @() vawlume.export.database(Output=output, SchemaOnly=true, ...
    AllowSchemaVersionMismatch=true), "vawlume:export:SchemaOnlyWithSource");
verifyError(testCase, @() vawlume.export.database(Output=output, SchemaOnly=true, ...
    Tables="projects"), "vawlume:export:SchemaOnlyWithSelection");
verifyError(testCase, @() vawlume.export.database(Output=output, SchemaOnly=true, ...
    IncludeViews=true), "vawlume:export:SchemaOnlyWithSelection");
verifyError(testCase, @() vawlume.export.database(Output=output), ...
    "vawlume:export:SourceRequired");
verifyFalse(testCase, isfolder(output));
end

% --- format and options ----------------------------------------------------------------

function testUnsupportedFormatsAndBadOptionsFailBeforeAnythingExists(testCase)
area = testCase.TestData.area;
output = fullfile(area, "never");
fixture = testCase.TestData.fixture;
before = sha256(fixture);
for format = ["xlsx", "parquet", "CSV", "json"]
    verifyError(testCase, @() vawlume.export.database(fixture, Output=output, Format=format), ...
        "vawlume:export:UnsupportedFormat", "Format " + format);
end
verifyError(testCase, @() vawlume.export.database(fixture, Output=output, Format=5), ...
    "vawlume:export:InvalidOption");
verifyError(testCase, @() vawlume.export.database(fixture), "vawlume:export:OutputRequired");
verifyError(testCase, @() vawlume.export.database(fixture, Output=""), "vawlume:export:OutputRequired");
verifyError(testCase, @() vawlume.export.database(fixture, Output=output, IncludeViews="yes"), ...
    "vawlume:export:InvalidOption");
verifyError(testCase, @() vawlume.export.database(fixture, Output=output, Tables="nonesuch"), ...
    "vawlume:export:UnknownObject");
verifyError(testCase, @() vawlume.export.database(fixture, Output=output, ...
    Tables="projects; DROP TABLE projects"), "vawlume:export:UnsafeObjectName");
verifyError(testCase, @() vawlume.export.database(fullfile(area, "absent.sqlite"), ...
    Output=output), "vawlume:export:SourceNotFound");

verifyFalse(testCase, isfolder(output));
verifyEmpty(testCase, packageFiles(area), "Nothing may be created by a refused call.");
verifyEqual(testCase, sha256(fixture), before);
end

function testDefaultAndExplicitCsvProduceTheSamePackage(testCase)
implicit = fullfile(testCase.TestData.area, "implicit");
explicit = fullfile(testCase.TestData.area, "explicit");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=implicit, Tables="detections");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=explicit, Tables="detections", Format="csv");
files = packageFiles(implicit);
verifyEqual(testCase, files, packageFiles(explicit));
for file = files'
    a = withoutTimestamp(readBytes(fullfile(implicit, file)));
    b = withoutTimestamp(readBytes(fullfile(explicit, file)));
    verifyEqual(testCase, a, b, file);
end
end

function testAnInjectedTimestampMakesThePackageByteDeterministic(testCase)
first = runInternal(testCase, fullfile(testCase.TestData.area, "first"), ...
    exported_at_utc="2026-09-22T14:03:11.472Z");
second = runInternal(testCase, fullfile(testCase.TestData.area, "second"), ...
    exported_at_utc="2026-09-22T14:03:11.472Z");
files = packageFiles(first.output_dir);
verifyEqual(testCase, files, packageFiles(second.output_dir));
for file = files'
    verifyEqual(testCase, readBytes(fullfile(first.output_dir, file)), ...
        readBytes(fullfile(second.output_dir, file)), file);
end
end

function testSourceIdentifierAndVawlumeVersionAreRecordedAsSupplied(testCase)
output = fullfile(testCase.TestData.area, "pkg");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=output, Tables="projects", ...
    SourceIdentifier="study-42 cohort A", VawlumeVersion="0.2.0-dev");
manifest = readCsv(fullfile(output, "meta", "manifest.csv"));
rowOf = @(key) find(manifest.column("key") == key, 1);
verifyEqual(testCase, manifest.values(rowOf("source_database_filename"), 2:3), ...
    ["study-42 cohort A", "caller_supplied"]);
verifyEqual(testCase, manifest.values(rowOf("vawlume_version"), 2:3), ["0.2.0-dev", "caller_supplied"]);
end

function testWarningsReachTheManifestTheReadmeAndTheResult(testCase)
copy = fullfile(testCase.TestData.area, "old.sqlite");
copyfile(testCase.TestData.fixture, copy);
conn = sqlite(char(copy));
execute(conn, "UPDATE schema_info SET schema_version = '0.9-draft'");
close(conn);
output = fullfile(testCase.TestData.area, "pkg");
result = vawlume.export.database(copy, Output=output, Tables="projects", ...
    AllowSchemaVersionMismatch=true);
verifyEqual(testCase, numel(result.warnings), 1);
verifyTrue(testCase, startsWith(result.warnings, "schema_version_mismatch: "));
manifest = readCsv(fullfile(output, "meta", "manifest.csv"));
rowOf = @(key) find(manifest.column("key") == key, 1);
verifyEqual(testCase, manifest.values(rowOf("warning_count"), 2), "1");
verifyEqual(testCase, manifest.values(rowOf("warning"), 2), "schema_version_mismatch");
verifySubstring(testCase, fileread(fullfile(output, "README.md")), "schema_version_mismatch");
end

% --- README from the record ------------------------------------------------------------

function testTheReadmeIsRenderedFromThePackageRecord(testCase)
% Changing a fact in the record changes the README. A README that merely
% agreed with the manifest once could not pass this.
staging = fullfile(testCase.TestData.area, "stage");
mkdir(staging);
exportRecord = vawlume.export.internal.writeObjects(testCase.TestData.fixture, staging, ...
    Tables=["projects", "detections"], RepoRoot=testCase.TestData.repoRoot);
record = vawlume.export.internal.buildPackageRecord("normal", testCase.TestData.structure, ...
    testCase.TestData.metadata, exportRecord, facts("2026-09-22T14:03:11.472Z"));
original = vawlume.export.internal.renderReadme(record);
verifySubstring(testCase, original, "| Rows exported, all objects | " + record.exported_row_total + " |");
verifySubstring(testCase, original, "| Source database | fixture.sqlite |");

changed = record;
changed.exported_row_total = 987654;
changed.source_identifier.value = "study-xyz";
changed.objects.row_count(changed.objects.object_name == "detections") = 4242;
changed.exported_at_utc = "2030-01-01T00:00:00.000Z";
rendered = vawlume.export.internal.renderReadme(changed);
verifySubstring(testCase, rendered, "| Rows exported, all objects | 987654 |");
verifySubstring(testCase, rendered, "| Source database | study-xyz |");
verifySubstring(testCase, rendered, "| `detections` | table | 4242 | `csv/detections.csv` |");
verifySubstring(testCase, rendered, "2030-01-01T00:00:00.000Z");
verifyFalse(testCase, contains(rendered, "fixture.sqlite"));

schemaOnly = vawlume.export.internal.buildPackageRecord("schema_only", ...
    testCase.TestData.structure, testCase.TestData.metadata, [], facts("2026-09-22T14:03:11.472Z"));
verifySubstring(testCase, vawlume.export.internal.renderReadme(schemaOnly), "schema-only");
end

function testMetadataCsvEscapingRoundTrips(testCase)
% Descriptions with commas, quotes, Unicode, and newlines survive the metadata
% writer exactly, and a blank field stays distinct from empty text.
record = vawlume.export.internal.buildPackageRecord("schema_only", ...
    testCase.TestData.structure, testCase.TestData.metadata, [], facts("2026-09-22T14:03:11.472Z"));
awkward = "Commas, ""quotes"", é μ 漢字 😀," + newline + "a second line" + ...
    char([13 10]) + "and a CRLF.";
record.tables_csv.description(1) = awkward;
record.columns_csv.description(2) = "";
record.relationships_csv.description(3) = awkward;
staging = fullfile(testCase.TestData.area, "meta_only");
mkdir(staging);
vawlume.export.internal.writePackageFiles(record, staging);

tablesCsv = readCsv(fullfile(staging, "meta", "tables.csv"));
verifyEqual(testCase, tablesCsv.values(1, 3), awkward);
verifyEqual(testCase, tablesCsv.count, 107);
columnsCsv = readCsv(fullfile(staging, "meta", "columns.csv"));
verifyTrue(testCase, columnsCsv.quoted(2, 4));
verifyEqual(testCase, columnsCsv.values(2, 4), "");
relationships = readCsv(fullfile(staging, "meta", "relationships.csv"));
verifyEqual(testCase, relationships.values(3, 5), awkward);
end

% --- destination policy -------------------------------------------------------------------

function testAnEmptyExistingDirectoryIsAccepted(testCase)
output = fullfile(testCase.TestData.area, "empty");
mkdir(output);
[~] = vawlume.export.database(testCase.TestData.fixture, Output=output, Tables="projects");
verifyTrue(testCase, isfile(fullfile(output, "meta", "manifest.csv")));
end

function testANonEmptyDirectoryIsNeverReplaced(testCase)
output = fullfile(testCase.TestData.area, "precious");
mkdir(output);
writeText(fullfile(output, "notes.txt"), "keep me");
verifyError(testCase, @() vawlume.export.database(testCase.TestData.fixture, Output=output), ...
    "vawlume:export:DestinationExists");
verifyError(testCase, @() vawlume.export.database(testCase.TestData.fixture, Output=output, ...
    Overwrite=true), "vawlume:export:DestinationUnsafe");
verifyEqual(testCase, packageFiles(output), "notes.txt");
verifyEmpty(testCase, siblingsLeftBehind(testCase.TestData.area));
end

function testAPreviousPackageIsReplacedOnlyWithOverwrite(testCase)
output = fullfile(testCase.TestData.area, "pkg");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=output, Tables="projects");
verifyError(testCase, @() vawlume.export.database(testCase.TestData.fixture, Output=output, ...
    Tables="detections"), "vawlume:export:DestinationExists");
result = vawlume.export.database(testCase.TestData.fixture, Output=output, ...
    Tables="detections", Overwrite=true);
verifyEqual(testCase, packageFiles(fullfile(output, "csv")), "detections.csv", ...
    "The replacement is a new package, not a merge with the old one.");
verifyEqual(testCase, result.exported_object_count, 1);
verifyEmpty(testCase, siblingsLeftBehind(testCase.TestData.area));
end

function testUnsafeDestinationsAreRefusedOutright(testCase)
fixture = testCase.TestData.fixture;
repoRoot = testCase.TestData.repoRoot;
unsafe = [string(fileparts(fixture)), string(fileparts(fileparts(fixture))), repoRoot, ...
    string(fileparts(repoRoot)), string(getenv("USERPROFILE")), "C:\", ...
    string(fileparts(string(getenv("USERPROFILE"))))];
unsafe = unsafe(unsafe ~= "");
for output = unsafe
    verifyError(testCase, @() vawlume.export.database(fixture, Output=output, Overwrite=true), ...
        "vawlume:export:DestinationUnsafe", "Output " + output);
end
file = fullfile(testCase.TestData.area, "a_file");
writeText(file, "x");
verifyError(testCase, @() vawlume.export.database(fixture, Output=file), ...
    "vawlume:export:DestinationUnsafe");
verifyError(testCase, @() vawlume.export.database(fixture, ...
    Output=fullfile(testCase.TestData.area, "no_parent", "pkg")), ...
    "vawlume:export:DestinationParentMissing");
verifyFalse(testCase, isfolder(fullfile(testCase.TestData.area, "no_parent")));
end

% --- atomic publication --------------------------------------------------------------------------

function testAFailureAfterTheDataLeavesAnAbsentDestinationAbsent(testCase)
output = fullfile(testCase.TestData.area, "pkg");
verifyError(testCase, @() runInternal(testCase, output, ...
    before_publish_fcn=@(~) error("test:export:Injected", "Injected before publication.")), ...
    "test:export:Injected");
verifyFalse(testCase, isfolder(output));
verifyEmpty(testCase, siblingsLeftBehind(testCase.TestData.area), "Staging must be removed.");
end

function testAFailureMidExportLeavesThePreviousPackageByteForByte(testCase)
output = fullfile(testCase.TestData.area, "pkg");
[~] = vawlume.export.database(testCase.TestData.fixture, Output=output, Tables="projects");
before = packageDigests(output);

% After the data files are written but before the metadata is complete.
verifyError(testCase, @() runInternal(testCase, output, overwrite=true, ...
    tables=["projects", "detections"], ...
    after_object_fcn=failAfter(2)), "test:export:Injected");
verifyEqual(testCase, packageDigests(output), before);

% After the whole package is staged and validated, immediately before the rename.
verifyError(testCase, @() runInternal(testCase, output, overwrite=true, ...
    before_publish_fcn=@(~) error("test:export:Injected", "Injected before publication.")), ...
    "test:export:Injected");
verifyEqual(testCase, packageDigests(output), before);
verifyEmpty(testCase, siblingsLeftBehind(testCase.TestData.area));
end

function testCallingWithoutAnOutputArgumentPrintsASummary(testCase)
output = fullfile(testCase.TestData.area, "pkg"); %#ok<NASGU> used inside evalc
printed = evalc("vawlume.export.database(testCase.TestData.fixture, Output=output, Tables=""projects"")");
verifySubstring(testCase, printed, "VAWLUME CSV export written");
verifySubstring(testCase, printed, "1 of 107 objects");
end

% --- helpers --------------------------------------------------------------------------------------

function keys = manifestKeys()
keys = ["package_format"; "package_format_version"; "export_format"; "export_mode"; ...
    "exported_at_utc"; "source_database_filename"; "source_database_bytes"; ...
    "source_schema_version"; "source_user_version"; "repository_schema_version"; ...
    "metadata_version"; "metadata_schema_version"; "vawlume_version"; ...
    "supported_object_count"; "selected_object_count"; "exported_object_count"; ...
    "exported_row_total"; "data_file_count"; "null_representation"; "text_quoting"; ...
    "real_representation"; "blob_representation"; "character_encoding"; ...
    "line_terminator"; "warning_count"];
end

function value = facts(timestamp)
value = struct(format="csv", exported_at_utc=timestamp, source_identifier="", ...
    vawlume_version="", repository_schema_version=vawlume.schema.repositoryVersion());
end

function result = runInternal(testCase, output, varargin)
request = struct(db_path=string(testCase.TestData.fixture), output=output, format="csv", ...
    schema_only=false, tables="all", include_views=false, overwrite=false, ...
    allow_schema_version_mismatch=false, source_identifier="", vawlume_version="", ...
    repo_root="", exported_at_utc="", before_publish_fcn=[], after_object_fcn=[]);
for k = 1:2:numel(varargin)
    request.(varargin{k}) = varargin{k + 1};
end
result = vawlume.export.internal.runExport(request);
end

function fcn = failAfter(count)
calls = 0;
fcn = @step;
    function step(~)
        calls = calls + 1;
        if calls == count
            error("test:export:Injected", "Injected after %d data files.", count);
        end
    end
end

function files = packageFiles(root)
listing = dir(fullfile(root, "**", "*"));
listing = listing(~[listing.isdir]);
files = strings(numel(listing), 1);
prefix = strlength(string(java.io.File(char(root)).getCanonicalPath())) + 2;
for k = 1:numel(listing)
    full = string(java.io.File(char(fullfile(listing(k).folder, listing(k).name))).getCanonicalPath());
    files(k) = replace(extractAfter(full, prefix - 1), "\", "/");
end
files = sort(files);
end

function names = siblingsLeftBehind(area)
listing = dir(area);
names = string({listing.name});
names = names(endsWith(names, [".partial", ".previous"]));
end

function digests = packageDigests(root)
files = packageFiles(root);
digests = files + " " + arrayfun(@(f) sha256(fullfile(root, f)), files);
end

function bytes = withoutTimestamp(bytes)
% Removes the one intentionally variable fact, wherever it appears.
text = native2unicode(bytes, "UTF-8");
text = regexprep(text, "\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z", "<timestamp>");
bytes = unicode2native(text, "UTF-8");
end

function digest = sha256(path)
engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(typecast(readBytes(path), "int8"));
digest = string(sprintf("%02x", typecast(engine.digest(), "uint8")));
end

function writeText(path, text)
fid = fopen(path, "w");
closer = onCleanup(@() fclose(fid));
fwrite(fid, char(text));
end

function bytes = readBytes(path)
fid = fopen(path, "r");
closer = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "uint8=>uint8")';
end

function csv = readCsv(path)
% RFC 4180 with CRLF records. Returns the header, every value, and whether each
% field was quoted; column(name, rows) returns one column.
text = native2unicode(readBytes(path), "UTF-8");
[tokens] = regexp(text, '("(?:[^"]|"")*"|[^,"\r\n]*)(,|\r\n)', "tokens");
total = sum(cellfun(@(t) numel(t{1}) + numel(t{2}), tokens));
assert(total == numel(text), "Malformed CSV: " + path);
records = {};
values = strings(1, 0);
quoted = false(1, 0);
for k = 1:numel(tokens)
    field = string(tokens{k}{1});
    isQuoted = startsWith(field, '"');
    if isQuoted
        field = replace(extractBetween(field, 2, strlength(field) - 1), '""', '"');
    end
    values(end + 1) = field; %#ok<AGROW>
    quoted(end + 1) = isQuoted; %#ok<AGROW>
    if string(tokens{k}{2}) == sprintf("\r\n")
        records{end + 1} = struct(values=values, quoted=quoted); %#ok<AGROW>
        values = strings(1, 0);
        quoted = false(1, 0);
    end
end
header = records{1}.values;
body = records(2:end);
csv = struct();
csv.header = header;
csv.count = numel(body);
csv.values = strings(numel(body), numel(header));
csv.quoted = false(numel(body), numel(header));
for r = 1:numel(body)
    csv.values(r, :) = body{r}.values;
    csv.quoted(r, :) = body{r}.quoted;
end
csv.column = @(name, varargin) selectColumn(csv, name, varargin{:});
end

function values = selectColumn(csv, name, rows)
values = csv.values(:, csv.header == name);
if nargin > 2
    values = values(rows);
end
end
