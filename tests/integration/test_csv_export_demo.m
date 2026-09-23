function tests = test_csv_export_demo
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
sourcePath = fullfile(repoRoot, "src");
examplePath = fullfile(repoRoot, "examples");
addpath(sourcePath, examplePath);

testCase.TestData.repoRoot = repoRoot;
testCase.TestData.sourcePath = sourcePath;
testCase.TestData.examplePath = examplePath;
testCase.TestData.statusBefore = gitStatus(repoRoot);
testCase.TestData.demonstration = csv_export_demo( ...
    Print=false, RepoRoot=repoRoot, RetainArtifacts=true);
end

function teardownOnce(testCase)
workspace = testCase.TestData.demonstration.workspace_root;
if isfolder(workspace)
    rmdir(workspace, "s");
end
verifyFalse(testCase, isfolder(workspace), ...
    "The integration suite left its disposable workspace behind.");
verifyEqual(testCase, gitStatus(testCase.TestData.repoRoot), ...
    testCase.TestData.statusBefore, ...
    "The CSV export demonstration changed the repository working tree.");
rmpath(testCase.TestData.examplePath, testCase.TestData.sourcePath);
end

function testAllThreePackagesHaveExactTreesAndFidelity(testCase)
value = testCase.TestData.demonstration;
normal = value.normal;
selective = value.selective;
schemaOnly = value.schema_only;

exported = normal.result.objects(normal.result.objects.exported, :);
expectedNormal = ["README.md"; "meta/columns.csv"; "meta/manifest.csv"; ...
    "meta/relationships.csv"; "meta/tables.csv"; ...
    "csv/" + exported.object_name + ".csv"];
verifyEqual(testCase, normal.files, sort(expectedNormal));
verifyEqual(testCase, sort(normal.result.files), sort(expectedNormal));

expectedSelective = sort(["README.md"; "meta/columns.csv"; ...
    "meta/manifest.csv"; "meta/relationships.csv"; "meta/tables.csv"; ...
    "csv/detections.csv"; "csv/v_detection_core.csv"]);
verifyEqual(testCase, selective.files, expectedSelective);
verifyEqual(testCase, sort(selective.result.files), expectedSelective);
verifyEqual(testCase, selective.result.objects.object_name( ...
    selective.result.objects.exported), ["detections"; "v_detection_core"]);
verifyEqual(testCase, selective.result.objects.object_kind( ...
    selective.result.objects.exported), ["table"; "view"]);

expectedSchema = sort(["README.md"; "meta/columns.csv"; ...
    "meta/manifest.csv"; "meta/relationships.csv"; "meta/tables.csv"]);
verifyEqual(testCase, schemaOnly.files, expectedSchema);
verifyFalse(testCase, isfolder(fullfile(schemaOnly.output_dir, "csv")));

conn = sqlite(char(value.database_path), "readonly");
cleanupConnection = onCleanup(@() close(conn));
for index = 1:height(exported)
    objectName = exported.object_name(index);
    csv = readCsv(fullfile(normal.output_dir, "csv", objectName + ".csv"));
    count = fetch(conn, "SELECT COUNT(*) AS n FROM " + objectName);
    columns = fetch(conn, "SELECT CAST(name AS TEXT) AS name " + ...
        "FROM pragma_table_info('" + objectName + "') ORDER BY cid");
    verifyEqual(testCase, csv.count, double(count.n(1)), ...
        "Row count differs for " + objectName);
    verifyEqual(testCase, csv.header, string(columns.name)', ...
        "Header differs for " + objectName);
end
clear cleanupConnection
close(conn);

zeroRows = exported.object_name(exported.row_count == 0);
verifyNotEmpty(testCase, zeroRows, "The fixture must exercise a header-only table.");
emptyCsv = readCsv(fullfile(normal.output_dir, "csv", zeroRows(1) + ".csv"));
verifyEqual(testCase, emptyCsv.count, 0);

quoted = readCsv(fullfile(normal.output_dir, "csv", "curation_events.csv"));
notes = quoted.column("notes");
requiresQuoting = contains(notes, ",");
verifyTrue(testCase, any(requiresQuoting));
verifyTrue(testCase, all(quoted.quoted(requiresQuoting, ...
    quoted.header == "notes")));

verifyTrue(testCase, value.source_unchanged);
verifyEqual(testCase, value.source_sha256_after, sha256(value.database_path));
verifyGreaterThan(testCase, value.strict_read.null_count, 0);
verifyGreaterThan(testCase, value.strict_read.empty_text_count, 0);
verifyEqual(testCase, value.strict_read.row_count, ...
    normal.result.objects.row_count( ...
    normal.result.objects.object_name == "detections"));
end

function testMetadataManifestAndReadmeAgreeWithThePackages(testCase)
value = testCase.TestData.demonstration;
metadata = vawlume.schema.loadMetadata(RepoRoot=testCase.TestData.repoRoot);

tablesHeader = ["object_name", "object_kind", "description", ...
    "exported", "row_count", "filename"];
columnsHeader = ["object_name", "column_name", "column_position", ...
    "description", "description_source"];
relationshipsHeader = ["source_table", "source_column", "target_table", ...
    "target_column", "description"];
manifestHeader = ["key", "value", "detail"];

for package = [value.normal, value.selective, value.schema_only]
    root = package.output_dir;
    verifyEqual(testCase, readCsv(fullfile(root, "meta", "tables.csv")).header, ...
        tablesHeader);
    verifyEqual(testCase, readCsv(fullfile(root, "meta", "columns.csv")).header, ...
        columnsHeader);
    verifyEqual(testCase, readCsv(fullfile(root, "meta", ...
        "relationships.csv")).header, relationshipsHeader);
    verifyEqual(testCase, readCsv(fullfile(root, "meta", "manifest.csv")).header, ...
        manifestHeader);
end

tables = readCsv(fullfile(value.selective.output_dir, "meta", "tables.csv"));
projectRow = tables.column("object_name") == "projects";
sourceProjectRow = metadata.objects.object_name == "projects";
verifyEqual(testCase, tables.column("description", projectRow), ...
    metadata.objects.description(sourceProjectRow));

columns = readCsv(fullfile(value.selective.output_dir, "meta", "columns.csv"));
startRow = columns.column("object_name") == "detections" & ...
    columns.column("column_name") == "start_time_s";
sourceStartRow = metadata.columns.object_name == "detections" & ...
    metadata.columns.column_name == "start_time_s";
verifyEqual(testCase, columns.column("description", startRow), ...
    metadata.columns.description(sourceStartRow));

relationships = readCsv(fullfile(value.selective.output_dir, "meta", ...
    "relationships.csv"));
relation = relationships.column("source_table") == "detections" & ...
    relationships.column("source_column") == "extraction_run_id" & ...
    relationships.column("target_table") == "extraction_runs" & ...
    relationships.column("target_column") == "extraction_run_id";
verifyEqual(testCase, sum(relation), 1);
verifyTrue(testCase, strlength(relationships.column("description", relation)) > 0);

assertPackageFacts(testCase, value.normal, "normal");
assertPackageFacts(testCase, value.selective, "normal");
assertPackageFacts(testCase, value.schema_only, "schema_only");

schemaManifest = readCsv(fullfile(value.schema_only.output_dir, "meta", ...
    "manifest.csv"));
manifestValue = @(key) schemaManifest.values( ...
    schemaManifest.column("key") == key, 2);
manifestDetail = @(key) schemaManifest.values( ...
    schemaManifest.column("key") == key, 3);
for key = ["source_database_filename", "source_database_bytes", ...
        "source_schema_version", "source_user_version"]
    verifyEqual(testCase, manifestValue(key), "");
    verifyEqual(testCase, manifestDetail(key), "not_applicable");
end
readme = string(fileread(fullfile(value.schema_only.output_dir, "README.md")));
verifyTrue(testCase, contains(lower(readme), "no database was read"));
verifyFalse(testCase, contains(readme, value.database_path));
end

function testUnsupportedFormatLeavesNothingAndEverythingIsDisposable(testCase)
value = testCase.TestData.demonstration;
output = fullfile(value.workspace_root, "unsupported_format");
sourceBefore = sha256(value.database_path);
verifyError(testCase, @() vawlume.export.database(value.database_path, ...
    Output=output, Format="xlsx"), "vawlume:export:UnsupportedFormat");
verifyFalse(testCase, isfolder(output));
verifyEqual(testCase, sha256(value.database_path), sourceBefore);
verifyEqual(testCase, gitStatus(testCase.TestData.repoRoot), ...
    testCase.TestData.statusBefore);
verifyTrue(testCase, startsWith(value.workspace_root, string(tempdir)));
end

function assertPackageFacts(testCase, package, mode)
manifest = readCsv(fullfile(package.output_dir, "meta", "manifest.csv"));
value = @(key) manifest.values(manifest.column("key") == key, 2);
result = package.result;
verifyEqual(testCase, value("package_format"), "vawlume_csv_export");
verifyEqual(testCase, value("export_mode"), mode);
verifyEqual(testCase, value("supported_object_count"), ...
    string(result.supported_object_count));
verifyEqual(testCase, value("selected_object_count"), ...
    string(result.selected_object_count));
verifyEqual(testCase, value("exported_object_count"), ...
    string(result.exported_object_count));
verifyEqual(testCase, value("exported_row_total"), ...
    string(result.exported_row_total));
verifyEqual(testCase, value("data_file_count"), ...
    string(sum(startsWith(package.files, "csv/"))));

tables = readCsv(fullfile(package.output_dir, "meta", "tables.csv"));
verifyEqual(testCase, sum(tables.column("exported") == "true"), ...
    result.exported_object_count);
verifyEqual(testCase, sum(str2double(tables.column("row_count")), "omitmissing"), ...
    result.exported_row_total);

readme = string(fileread(fullfile(package.output_dir, "README.md")));
verifyTrue(testCase, contains(readme, "`" + mode + "`"));
verifyTrue(testCase, contains(readme, ...
    "| Objects in the schema | " + string(result.supported_object_count) + " |"));
verifyTrue(testCase, contains(readme, ...
    "| Objects exported | " + string(result.exported_object_count) + " |"));
end

function files = packageFiles(root)
listing = dir(fullfile(root, "**", "*"));
listing = listing(~[listing.isdir]);
files = strings(numel(listing), 1);
prefix = strlength(string(java.io.File(char(root)).getCanonicalPath())) + 2;
for index = 1:numel(listing)
    full = string(java.io.File(char(fullfile( ...
        listing(index).folder, listing(index).name))).getCanonicalPath());
    files(index) = replace(extractAfter(full, prefix - 1), "\", "/");
end
files = sort(files);
end

function digest = sha256(path)
engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(typecast(readBytes(path), "int8"));
digest = string(sprintf("%02x", typecast(engine.digest(), "uint8")));
end

function bytes = readBytes(path)
fileId = fopen(path, "rb");
cleanupFile = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "uint8=>uint8")';
clear cleanupFile
end

function csv = readCsv(path)
text = native2unicode(readBytes(path), "UTF-8");
tokens = regexp(text, '("(?:[^"]|"")*"|[^,"\r\n]*)(,|\r\n)', "tokens");
total = sum(cellfun(@(token) numel(token{1}) + numel(token{2}), tokens));
assert(total == numel(text), "Malformed CSV: " + path);
records = {};
values = strings(1, 0);
quoted = false(1, 0);
for index = 1:numel(tokens)
    field = string(tokens{index}{1});
    isQuoted = startsWith(field, '"');
    if isQuoted
        field = replace(extractBetween(field, 2, strlength(field) - 1), '""', '"');
    end
    values(end + 1) = field; %#ok<AGROW>
    quoted(end + 1) = isQuoted; %#ok<AGROW>
    if string(tokens{index}{2}) == sprintf("\r\n")
        records{end + 1} = struct(values=values, quoted=quoted); %#ok<AGROW>
        values = strings(1, 0);
        quoted = false(1, 0);
    end
end
header = records{1}.values;
body = records(2:end);
csv = struct(header=header, count=numel(body), ...
    values=strings(numel(body), numel(header)), ...
    quoted=false(numel(body), numel(header)));
for row = 1:numel(body)
    csv.values(row, :) = body{row}.values;
    csv.quoted(row, :) = body{row}.quoted;
end
csv.column = @(name, varargin) selectColumn(csv, name, varargin{:});
end

function values = selectColumn(csv, name, rows)
values = csv.values(:, csv.header == name);
if nargin > 2
    values = values(rows);
end
end

function value = gitStatus(repoRoot)
[status, output] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
if status ~= 0
    value = "(git unavailable)";
    return
end
value = sort(strtrim(splitlines(string(output))));
value = value(strlength(value) > 0);
end
