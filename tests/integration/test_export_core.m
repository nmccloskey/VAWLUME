function tests = test_export_core
% The CSV export core against a real VAWLUME database: the Phase 1 fixture.
%
% What is asserted, and against what:
%   - every selected object produces exactly one CSV, whose header is the
%     object's canonical columns and whose row count is SQLite's COUNT(*);
%   - every SQL NULL in the source is a bare empty field in the file, column by
%     column, so no NULL was lost and none was invented;
%   - the source is unchanged, by SHA-256 of the file and by data_version, not
%     merely because it still opens;
%   - an absent or non-database path creates nothing;
%   - a failure or a concurrent write mid-export leaves no csv directory behind.
%
% The fixture is built once. A test that must alter a database works on its own
% copy, so the shared one also stands as evidence that exporting it changed
% nothing.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
testCase.addTeardown(@() rmpath(fullfile(repoRoot, "src")));
workspace = string(tempname);
mkdir(workspace);
testCase.addTeardown(@() rmdir(workspace, "s"));
fixture = fullfile(workspace, "fixture.sqlite");
[conn, ~] = vawlume.db.createPhase1FixtureDatabase(fixture, repoRoot);
close(conn);
testCase.TestData.repoRoot = repoRoot;
testCase.TestData.workspace = workspace;
testCase.TestData.fixture = fixture;
testCase.TestData.fixtureDigest = sha256(fixture);
end

% --- selection and shape -----------------------------------------------------

function testDefaultExportWritesEveryTableAndNoView(testCase)
[record, staging] = exportTo(testCase, testCase.TestData.fixture);

structure = vawlume.schema.loadStructure(RepoRoot=testCase.TestData.repoRoot);
tables = sortrows(structure.objects(structure.objects.object_kind == "table", :), "position");
verifyEqual(testCase, record.objects.object_name, tables.object_name);
verifyEqual(testCase, record.exported_object_count, height(tables));
verifyEqual(testCase, record.supported_object_count, height(structure.objects));

written = dir(fullfile(staging, "csv", "*.csv"));
verifyEqual(testCase, sort(string({written.name}')), sort(tables.object_name + ".csv"), ...
    "The csv directory must hold exactly one file per selected object.");
verifyEqual(testCase, record.files, "csv/" + tables.object_name + ".csv");
end

function testHeadersAndRowCountsMatchSqlite(testCase)
[record, staging] = exportTo(testCase, testCase.TestData.fixture, IncludeViews=true);
conn = sqlite(char(testCase.TestData.fixture), "readonly");
closer = onCleanup(@() close(conn));

for k = 1:height(record.objects)
    name = record.objects.object_name(k);
    expectedColumns = fetch(conn, "SELECT CAST(name AS TEXT) AS name FROM " + ...
        "pragma_table_info('" + name + "') ORDER BY cid");
    expectedColumns = string(expectedColumns.name)';
    records = parseCsv(readBytes(fullfile(staging, record.objects.filename(k))));

    verifyEqual(testCase, [records{1}.text], expectedColumns, "Header of " + name);
    verifyEqual(testCase, record.objects.columns{k}, expectedColumns);
    verifyEqual(testCase, record.objects.column_count(k), numel(expectedColumns));

    counted = fetch(conn, "SELECT COUNT(*) AS n FROM """ + name + """");
    verifyEqual(testCase, record.objects.row_count(k), double(counted.n(1)), "Rows of " + name);
    verifyEqual(testCase, numel(records) - 1, record.objects.row_count(k), ...
        "Records in the file for " + name);
end
verifyEqual(testCase, record.exported_row_total, sum(record.objects.row_count));
end

function testEveryNullIsABareFieldAndNothingElseIs(testCase)
% Column by column across every object, tables and views: the number of bare
% empty fields equals SQLite's own count of NULLs. A NULL written as "" would
% lower the count; a value collapsed to a bare field would raise it.
[record, staging] = exportTo(testCase, testCase.TestData.fixture, IncludeViews=true);
conn = sqlite(char(testCase.TestData.fixture), "readonly");
closer = onCleanup(@() close(conn));

totalNulls = 0;
for k = 1:height(record.objects)
    name = record.objects.filename(k);
    records = parseCsv(readBytes(fullfile(staging, name)));
    columns = record.objects.columns{k};
    for j = 1:numel(columns)
        expected = fetch(conn, "SELECT COUNT(*) AS n FROM """ + ...
            record.objects.object_name(k) + """ WHERE """ + columns(j) + """ IS NULL");
        bare = 0;
        for r = 2:numel(records)
            field = records{r}(j);
            bare = bare + (~field.quoted && field.text == "");
        end
        verifyEqual(testCase, bare, double(expected.n(1)), ...
            "NULLs in " + record.objects.object_name(k) + "." + columns(j));
        totalNulls = totalNulls + bare;
    end
end
verifyGreaterThan(testCase, totalNulls, 0, "The fixture must exercise NULLs for this to mean anything.");
end

function testRealValuesRoundTripBitExactly(testCase)
[~, staging] = exportTo(testCase, testCase.TestData.fixture, Tables="detections");
conn = sqlite(char(testCase.TestData.fixture), "readonly");
closer = onCleanup(@() close(conn));
native = fetch(conn, "SELECT start_time_s, end_time_s FROM detections ORDER BY rowid");

records = parseCsv(readBytes(fullfile(staging, "csv", "detections.csv")));
header = [records{1}.text];
startColumn = header == "start_time_s";
endColumn = header == "end_time_s";
verifyEqual(testCase, numel(records) - 1, height(native));
for r = 1:height(native)
    verifyEqual(testCase, typecast(str2double(records{r + 1}(startColumn).text), "uint64"), ...
        typecast(double(native.start_time_s(r)), "uint64"));
    verifyEqual(testCase, typecast(str2double(records{r + 1}(endColumn).text), "uint64"), ...
        typecast(double(native.end_time_s(r)), "uint64"));
end
end

function testAnExplicitViewExportsAsAView(testCase)
[record, staging] = exportTo(testCase, testCase.TestData.fixture, ...
    Tables=["v_detection_core", "detections"], IncludeViews=false);
verifyEqual(testCase, record.objects.object_name, ["detections"; "v_detection_core"]);
verifyEqual(testCase, record.objects.object_kind, ["table"; "view"]);
verifyTrue(testCase, isfile(fullfile(staging, "csv", "v_detection_core.csv")));
end

function testAZeroRowObjectKeepsItsHeader(testCase)
[record, staging] = exportTo(testCase, testCase.TestData.fixture, Tables="ingestion_runs");
verifyEqual(testCase, record.objects.row_count, 0);
records = parseCsv(readBytes(fullfile(staging, "csv", "ingestion_runs.csv")));
verifyEqual(testCase, numel(records), 1);
verifyEqual(testCase, [records{1}.text], record.objects.columns{1});
verifyGreaterThan(testCase, record.objects.column_count, 0);
end

% --- source safety -------------------------------------------------------------

function testTheSourceIsUnchangedByExport(testCase)
% Proved by the file's bytes, not by data_version: data_version is meaningful
% only within one connection, so comparing values read on two connections would
% prove nothing.
fixture = testCase.TestData.fixture;
exportTo(testCase, fixture, IncludeViews=true);
verifyEqual(testCase, sha256(fixture), testCase.TestData.fixtureDigest, ...
    "Exporting changed the source database's bytes.");
verifyFalse(testCase, isfile(fixture + "-journal"));
verifyFalse(testCase, isfile(fixture + "-wal"));
record = exportTo(testCase, fixture, Tables="projects");
verifyNotEmpty(testCase, record.source.data_version);
verifyEqual(testCase, record.source.schema_version, ...
    vawlume.schema.repositoryVersion(RepoRoot=testCase.TestData.repoRoot));
conn = sqlite(char(fixture), "readonly");
userVersion = fetch(conn, "SELECT CAST(user_version AS TEXT) AS v FROM pragma_user_version()");
close(conn);
verifyEqual(testCase, record.source.user_version, str2double(string(userVersion.v(1))));
end

function testAnAbsentSourceIsRefusedAndNotCreated(testCase)
absent = fullfile(testCase.TestData.workspace, "absent.sqlite");
staging = stagingRoot(testCase);
verifyError(testCase, @() vawlume.export.internal.writeObjects(absent, staging), ...
    "vawlume:export:SourceNotFound");
verifyFalse(testCase, isfile(absent), "Export must never create a database.");
verifyFalse(testCase, isfolder(fullfile(staging, "csv")));
end

function testANonDatabaseFileIsRefusedAndUntouched(testCase)
bogus = fullfile(testCase.TestData.workspace, "bogus.sqlite");
writeText(bogus, "this is not a database" + newline);
digest = sha256(bogus);
verifyError(testCase, @() vawlume.export.internal.writeObjects(bogus, stagingRoot(testCase)), ...
    "vawlume:export:SourceUnreadable");
verifyEqual(testCase, sha256(bogus), digest);

empty = fullfile(testCase.TestData.workspace, "empty.sqlite");
writeText(empty, "");
verifyError(testCase, @() vawlume.export.internal.writeObjects(empty, stagingRoot(testCase)), ...
    "vawlume:export:NotAVawlumeDatabase");
listing = dir(empty);
verifyEqual(testCase, listing.bytes, 0, "An empty file must not be initialized as a database.");
end

function testAnInvalidSelectionTouchesNothing(testCase)
staging = stagingRoot(testCase);
verifyError(testCase, @() vawlume.export.internal.writeObjects(testCase.TestData.fixture, ...
    staging, Tables="projects; DROP TABLE projects"), "vawlume:export:UnsafeObjectName");
verifyError(testCase, @() vawlume.export.internal.writeObjects(testCase.TestData.fixture, ...
    staging, Tables="nonesuch"), "vawlume:export:UnknownObject");
verifyFalse(testCase, isfolder(fullfile(staging, "csv")));
verifyEqual(testCase, sha256(testCase.TestData.fixture), testCase.TestData.fixtureDigest);
end

% --- version and structure -------------------------------------------------------

function testAVersionMismatchFailsUnlessAllowed(testCase)
copy = copyFixture(testCase);
conn = sqlite(char(copy));
execute(conn, "UPDATE schema_info SET schema_version = '0.9-draft'");
close(conn);

staging = stagingRoot(testCase);
exception = captureError(testCase, @() vawlume.export.internal.writeObjects(copy, staging, ...
    Tables="projects"), "vawlume:export:SchemaVersionMismatch");
verifySubstring(testCase, exception.message, "0.9-draft");
verifyFalse(testCase, isfolder(fullfile(staging, "csv")));

record = vawlume.export.internal.writeObjects(copy, staging, Tables="projects", ...
    AllowSchemaVersionMismatch=true);
verifyEqual(testCase, record.warnings.code, "schema_version_mismatch");
verifyEqual(testCase, record.source.schema_version, "0.9-draft");
end

function testAStructureDifferenceAtTheSameVersionFails(testCase)
copy = copyFixture(testCase);
conn = sqlite(char(copy));
execute(conn, "ALTER TABLE projects ADD COLUMN unexpected TEXT");
close(conn);
verifyError(testCase, @() vawlume.export.internal.writeObjects(copy, stagingRoot(testCase), ...
    Tables="projects"), "vawlume:export:SourceStructureMismatch");
end

function testUnderAnAcceptedMismatchTheSourceColumnsAreExported(testCase)
% A database of another version is exported as it is, not forced into the
% current schema's shape, and the difference is recorded.
copy = copyFixture(testCase);
conn = sqlite(char(copy));
execute(conn, "UPDATE schema_info SET schema_version = '0.9-draft'");
execute(conn, "ALTER TABLE projects ADD COLUMN unexpected TEXT");
close(conn);

[record, staging] = exportTo(testCase, copy, Tables="projects", AllowSchemaVersionMismatch=true);
verifyTrue(testCase, ismember("source_structure_differs", record.warnings.code));
verifyEqual(testCase, record.objects.columns{1}(end), "unexpected");
records = parseCsv(readBytes(fullfile(staging, "csv", "projects.csv")));
verifyEqual(testCase, [records{1}.text], record.objects.columns{1});
end

function testAMissingSourceObjectIsReportedByName(testCase)
copy = copyFixture(testCase);
conn = sqlite(char(copy));
execute(conn, "UPDATE schema_info SET schema_version = '0.9-draft'");
execute(conn, "DROP VIEW v_attribution_window_correspondences");
close(conn);
exception = captureError(testCase, @() vawlume.export.internal.writeObjects(copy, ...
    stagingRoot(testCase), Tables="v_attribution_window_correspondences", ...
    AllowSchemaVersionMismatch=true), "vawlume:export:SourceObjectMissing");
verifySubstring(testCase, exception.message, "v_attribution_window_correspondences");
end

% --- failure mid-export ------------------------------------------------------------

function testAFailureMidExportLeavesNoCsvDirectory(testCase)
staging = stagingRoot(testCase);
calls = 0;
    function failOnThird(~)
        calls = calls + 1;
        if calls == 3
            error("test:export:Injected", "Injected failure after two objects.");
        end
    end
verifyError(testCase, @() vawlume.export.internal.writeObjects(testCase.TestData.fixture, ...
    staging, AfterObjectFcn=@failOnThird), "test:export:Injected");
verifyEqual(testCase, calls, 3, "The failure must come after earlier objects were written.");
verifyFalse(testCase, isfolder(fullfile(staging, "csv")), ...
    "No partial csv directory may survive a failed export.");
verifyTrue(testCase, isfolder(staging), "The caller's staging root is left in place.");
verifyEmpty(testCase, dir(fullfile(staging, "*.csv")));
end

function testAConcurrentWriteIsDetectedAndNothingIsKept(testCase)
% A second connection commits a row after the first object has been read. The
% change guard must see it, fail the export, and remove what was written.
copy = copyFixture(testCase);
staging = stagingRoot(testCase);
wrote = false;
    function writeOnce(~)
        if ~wrote
            writer = sqlite(char(copy));
            execute(writer, "INSERT INTO projects(project_key, project_name) " + ...
                "VALUES('concurrent', 'Written mid-export')");
            close(writer);
            wrote = true;
        end
    end
verifyError(testCase, @() vawlume.export.internal.writeObjects(copy, staging, ...
    AfterObjectFcn=@writeOnce), "vawlume:export:SourceChangedDuringExport");
verifyTrue(testCase, wrote);
verifyFalse(testCase, isfolder(fullfile(staging, "csv")));
end

function testStagingPreconditionsProtectExistingContent(testCase)
missing = fullfile(testCase.TestData.workspace, "no_such_staging");
verifyError(testCase, @() vawlume.export.internal.writeObjects(testCase.TestData.fixture, ...
    missing), "vawlume:export:StagingMissing");
verifyFalse(testCase, isfolder(missing));

staging = stagingRoot(testCase);
mkdir(fullfile(staging, "csv"));
keep = fullfile(staging, "csv", "keep.txt");
writeText(keep, "not ours");
verifyError(testCase, @() vawlume.export.internal.writeObjects(testCase.TestData.fixture, ...
    staging), "vawlume:export:StagingNotEmpty");
verifyTrue(testCase, isfile(keep), "An existing csv directory must never be deleted.");
end

% --- helpers --------------------------------------------------------------------------

function [record, staging] = exportTo(testCase, source, varargin)
staging = stagingRoot(testCase);
record = vawlume.export.internal.writeObjects(source, staging, varargin{:});
end

function staging = stagingRoot(testCase)
staging = fullfile(testCase.TestData.workspace, "staging_" + string(java.util.UUID.randomUUID));
mkdir(staging);
end

function copy = copyFixture(testCase)
copy = fullfile(testCase.TestData.workspace, "copy_" + string(java.util.UUID.randomUUID) + ".sqlite");
copyfile(testCase.TestData.fixture, copy);
end

function digest = sha256(path)
engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(typecast(readBytes(path), "int8"));
digest = string(sprintf("%02x", typecast(engine.digest(), "uint8")));
end

function exception = captureError(testCase, action, identifier)
exception = [];
try
    action();
catch exception
end
verifyNotEmpty(testCase, exception, "Expected an error: " + identifier);
if ~isempty(exception)
    verifyEqual(testCase, string(exception.identifier), identifier);
else
    exception = MException("test:none", "no error");
end
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

function records = parseCsv(bytes)
% RFC 4180 with CRLF record terminators; each field keeps whether it was quoted,
% because that flag is the only thing separating NULL from "".
text = native2unicode(bytes, "UTF-8");
records = {};
fields = struct("text", {}, "quoted", {});
field = "";
inQuotes = false;
wasQuoted = false;
k = 1;
n = numel(text);
while k <= n
    ch = text(k);
    if inQuotes
        if ch == '"' && k < n && text(k + 1) == '"'
            field = field + '"';
            k = k + 2;
        elseif ch == '"'
            inQuotes = false;
            k = k + 1;
        else
            field = field + ch;
            k = k + 1;
        end
    elseif ch == '"'
        inQuotes = true;
        wasQuoted = true;
        k = k + 1;
    elseif ch == ','
        fields(end + 1) = struct("text", field, "quoted", wasQuoted); %#ok<AGROW>
        field = "";
        wasQuoted = false;
        k = k + 1;
    elseif ch == char(13) && k < n && text(k + 1) == newline
        fields(end + 1) = struct("text", field, "quoted", wasQuoted); %#ok<AGROW>
        records{end + 1} = fields; %#ok<AGROW>
        fields = struct("text", {}, "quoted", {});
        field = "";
        wasQuoted = false;
        k = k + 2;
    else
        field = field + ch;
        k = k + 1;
    end
end
if inQuotes || ~isempty(fields) || strlength(field) > 0
    error("test:parse:UnterminatedRecord", "The file does not end with a complete CRLF-terminated record.");
end
end
