function tests = test_schema_documentation
% Guards the generator that turns schema/schema.sql into schema/schema.json.
%
% The generated artifact is only trustworthy if two things hold: it is
% reproducible from the authoritative schema, and a run that goes wrong cannot
% quietly leave a plausible-looking wrong artifact behind. Both are asserted
% here, and the second is asserted by injecting each failure rather than by
% confirming the happy path.
%
% tbls is a development dependency. When it is absent these tests SKIP with an
% actionable message; they never pass silently, because a test that reports
% success for work it could not do is worse than one that fails.
tests = functiontests({ ...
    @testGenerationProducesValidJson, ...
    @testGenerationIsDeterministicAcrossRunsAndDirectories, ...
    @testExportAccountsForEveryDatabaseObject, ...
    @testGenerationLeavesNoTemporaryArtifacts, ...
    @testMissingTblsRaisesAnActionableError, ...
    @testSchemaInitializationFailureExportsNothing, ...
    @testAFailedRunLeavesAValidArtifactUntouched, ...
    @testAPartialExportIsRefusedAndNamesWhatIsMissing, ...
    @testAnUnparsableExportIsRefused, ...
    @testACgoLessTblsIsReportedAsIncapable, ...
    @testCheckModeIsNotImplementedYet});
end

% ---------------------------------------------------------------------------
% Generation
% ---------------------------------------------------------------------------

function testGenerationProducesValidJson(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

report = generateOrSkip(testCase, RepoRoot=repoRoot, OutputPath=outputPath, Print=false);

verifyTrue(testCase, isfile(outputPath));
verifyEqual(testCase, report.mode, "generate");
verifyTrue(testCase, report.written);
verifyGreaterThan(testCase, report.bytes, 0);

data = jsondecode(fileread(outputPath));
for field = ["name", "tables", "relations", "driver"]
    verifyTrue(testCase, isfield(data, field), ...
        "Export is missing top-level field " + field + ".");
end

% tbls records the temporary database's filename here. It is stabilized by
% construction rather than by canonicalization, so it must be the fixed name.
verifyEqual(testCase, string(data.name), "vawlume.sqlite");
end

function testGenerationIsDeterministicAcrossRunsAndDirectories(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);

first = fullfile(workspace, "first.json");
second = fullfile(workspace, "second.json");
elsewhere = fullfile(workspace, "elsewhere.json");

generateOrSkip(testCase, RepoRoot=repoRoot, OutputPath=first, Print=false);
generateOrSkip(testCase, RepoRoot=repoRoot, OutputPath=second, Print=false);

% Two runs from one directory is weaker evidence than it looks: a path leaking
% into the output is the most likely volatile field, and it would agree with
% itself all day.
originalDirectory = pwd;
testCase.addTeardown(@() cd(originalDirectory));
cd(workspace);
generateOrSkip(testCase, RepoRoot=repoRoot, OutputPath=elsewhere, Print=false);
cd(originalDirectory);

firstBytes = readBytes(first);
verifyEqual(testCase, readBytes(second), firstBytes, ...
    "Two generations from an unchanged schema differ.");
verifyEqual(testCase, readBytes(elsewhere), firstBytes, ...
    "A generation from a different working directory differs.");
end

function testExportAccountsForEveryDatabaseObject(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
addSourcePath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

report = generateOrSkip(testCase, RepoRoot=repoRoot, OutputPath=outputPath, Print=false);

% The expectation is derived from the authoritative schema, here and in the
% tool. A written-down list of table names would be a second schema definition
% and would rot the first time the schema changed.
expectedNames = sort(databaseObjectNames(testCase, repoRoot, workspace));
verifyGreaterThan(testCase, numel(expectedNames), 0, ...
    "The expectation itself is empty, so this test would pass vacuously.");

data = jsondecode(fileread(outputPath));
exportedNames = sort(exportedEntryNames(data.tables));

verifyEmpty(testCase, setdiff(expectedNames, exportedNames), ...
    "Objects present in the database but absent from the export.");
verifyEqual(testCase, report.database_objects, numel(expectedNames));
verifyEqual(testCase, report.exported_tables, numel(exportedNames));
verifyGreaterThan(testCase, report.relations, 0);
end

function testGenerationLeavesNoTemporaryArtifacts(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

before = numel(dir(fullfile(tempdir, "VAWLUME_schema_documentation_*")));
generateOrSkip(testCase, RepoRoot=repoRoot, OutputPath=outputPath, Print=false);
after = numel(dir(fullfile(tempdir, "VAWLUME_schema_documentation_*")));

verifyEqual(testCase, after, before, ...
    "A temporary generation workspace was left behind.");
verifyEmpty(testCase, dir(fullfile(workspace, "*.generating")), ...
    "A staged artifact was left beside the destination.");
end

% ---------------------------------------------------------------------------
% Failure behaviour, each injected rather than reasoned about
% ---------------------------------------------------------------------------

function testMissingTblsRaisesAnActionableError(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
absent = fullfile(workspace, "no_tbls_here.exe");

exception = captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, TblsPath=absent, ...
        OutputPath=fullfile(workspace, "schema.json"), Print=false), ...
    "vawlume:schema:TblsNotFound");

% "Command failed" is not actionable. The message must name the tool, the
% pinned version, and where to get it.
message = string(exception.message);
verifyTrue(testCase, contains(message, "tbls"), message);
verifyTrue(testCase, contains(message, "v1."), message);
verifyTrue(testCase, contains(message, "github.com/k1LoW/tbls/releases"), message);
verifyTrue(testCase, contains(message, "VAWLUME_TBLS"), message);
end

function testSchemaInitializationFailureExportsNothing(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

% A database that never initialized is the case the non-empty check exists for:
% tbls introspects it happily and produces plausible, well-formed, empty JSON.
emptySchema = writeTextFile(fullfile(workspace, "empty_schema.sql"), ...
    "-- no statements" + newline);

exception = captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, SchemaPath=emptySchema, ...
        OutputPath=outputPath, Print=false), ...
    "vawlume:schema:SchemaInitializationFailed", true);

verifyTrue(testCase, contains(string(exception.message), "no tables or views"));
verifyFalse(testCase, isfile(outputPath), ...
    "A failed initialization still wrote an artifact.");
end

function testAFailedRunLeavesAValidArtifactUntouched(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

% This is the failure that does damage quietly. Every other one is loud.
sentinel = "{""name"":""previously valid artifact""}";
writeTextFile(outputPath, sentinel);

emptySchema = writeTextFile(fullfile(workspace, "empty_schema.sql"), ...
    "-- no statements" + newline);
captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, SchemaPath=emptySchema, ...
        OutputPath=outputPath, Print=false), ...
    "vawlume:schema:SchemaInitializationFailed", true);
verifyEqual(testCase, string(fileread(outputPath)), sentinel, ...
    "A failed initialization overwrote a valid artifact.");

stub = stubTblsOrSkip(testCase, workspace, "fail", "");
captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, TblsPath=stub, ...
        OutputPath=outputPath, Print=false), ...
    "vawlume:schema:TblsExportFailed");
verifyEqual(testCase, string(fileread(outputPath)), sentinel, ...
    "A failed export overwrote a valid artifact.");
end

function testAPartialExportIsRefusedAndNamesWhatIsMissing(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
addSourcePath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

sentinel = "{""name"":""previously valid artifact""}";
writeTextFile(outputPath, sentinel);

% Inject the defect the check targets: a tbls that succeeds and returns a
% well-formed export listing no tables at all. A validation that has only ever
% seen good input has not been tested.
payload = writeTextFile(fullfile(workspace, "empty_export.json"), ...
    "{""name"":""vawlume.sqlite"",""tables"":[]," + ...
    """relations"":[],""driver"":{""name"":""sqlite""}}");
stub = stubTblsOrSkip(testCase, workspace, "payload", payload);

exception = captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, TblsPath=stub, ...
        OutputPath=outputPath, Print=false), ...
    "vawlume:schema:ExportIncomplete");

% It must fail for its own reason: the report names the objects that went
% missing, not merely that a count disagreed.
message = string(exception.message);
expectedNames = databaseObjectNames(testCase, repoRoot, workspace);
verifyTrue(testCase, contains(message, expectedNames(1)), message);
verifyTrue(testCase, contains(message, "partial"), message);

verifyEqual(testCase, string(fileread(outputPath)), sentinel, ...
    "A partial export overwrote a valid artifact.");
end

function testAnUnparsableExportIsRefused(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);
outputPath = fullfile(workspace, "schema.json");

payload = writeTextFile(fullfile(workspace, "truncated.json"), ...
    "{""name"":""vawlume.sqlite"",""tables"":[");
stub = stubTblsOrSkip(testCase, workspace, "payload", payload);

captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, TblsPath=stub, ...
        OutputPath=outputPath, Print=false), ...
    "vawlume:schema:ExportInvalid");
verifyFalse(testCase, isfile(outputPath));
end

function testACgoLessTblsIsReportedAsIncapable(testCase)
repoRoot = repoRootForTest();
addToolsPath(testCase, repoRoot);
workspace = workspaceForTest(testCase);

% A tbls built by `go install` without cgo answers `tbls version` correctly and
% then cannot open a SQLite database. Presence is not capability, so this is a
% distinct diagnosis rather than a generic export failure.
stub = stubTblsOrSkip(testCase, workspace, "cgo", "");

exception = captureError(testCase, ...
    @() schema_documentation(RepoRoot=repoRoot, TblsPath=stub, ...
        OutputPath=fullfile(workspace, "schema.json"), Print=false), ...
    "vawlume:schema:TblsNotCapable");

message = string(exception.message);
verifyTrue(testCase, contains(message, "cgo"), message);
verifyTrue(testCase, contains(message, "official release binary"), message);
end

function testCheckModeIsNotImplementedYet(testCase)
addToolsPath(testCase, repoRootForTest());
% The freshness check regenerates through this same function rather than
% reimplementing generation. Until it exists, asking for it must say so.
verifyError(testCase, @() schema_documentation(Mode="check"), ...
    "vawlume:schema:ModeNotImplemented");
end

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

function report = generateOrSkip(testCase, varargin)
try
    report = schema_documentation(varargin{:});
catch exception
    skipIfToolchainAbsent(testCase, exception);
    rethrow(exception);
end
end

function exception = captureError(testCase, fcn, identifier, skipIfAbsent)
% Like verifyError, but hands back the MException so a test can assert that the
% message is actually actionable rather than only that something was raised.
%
% `skipIfAbsent` is for cases that resolve tbls before they fail for their own
% reason: without a toolchain those would fail spuriously, so they skip instead.
% It is off by default, because the test that asserts the missing-tbls error
% must not turn its own expected failure into a skip.
if nargin < 4
    skipIfAbsent = false;
end

exception = MException.empty;
try
    fcn();
catch caught
    exception = caught;
end

if isempty(exception)
    verifyFail(testCase, "Expected " + identifier + " but no error was raised.");
    exception = MException(identifier, "no error was raised");
    return
end

if skipIfAbsent
    skipIfToolchainAbsent(testCase, exception);
end

verifyEqual(testCase, string(exception.identifier), string(identifier), ...
    "Raised " + exception.identifier + ": " + exception.message);
end

function skipIfToolchainAbsent(testCase, exception)
if any(string(exception.identifier) == ...
        ["vawlume:schema:TblsNotFound", "vawlume:schema:TblsNotCapable"])
    assumeFail(testCase, "Skipped: a working tbls is not available. " + ...
        exception.message);
end
end

function stub = stubTblsOrSkip(testCase, workspace, behaviour, payload)
% A stand-in tbls, so each export failure can be injected rather than argued
% for. Windows only; elsewhere these cases skip rather than pretend.
assumeTrue(testCase, ispc, ...
    "Skipped: the tbls stub used to inject export failures is Windows-only.");

% A batch file needs CRLF: an LF-only multi-line block is parsed unreliably.
eol = sprintf("\r\n");

switch behaviour
    case "payload"
        % %~7 is the -o argument of `out -t json --dsn <dsn> -o <path>`.
        action = "copy /y """ + payload + """ ""%~7"" >nul" + eol + "exit /b 0";
    case "cgo"
        action = "echo Binary was compiled with 'CGO_ENABLED=0', " + ...
            "go-sqlite3 requires cgo to work. This is a stub 1>&2" + eol + ...
            "exit /b 1";
    otherwise
        action = "echo tbls stub failure 1>&2" + eol + "exit /b 3";
end

stub = fullfile(workspace, "tbls_stub_" + behaviour + ".cmd");
writeTextFile(stub, ...
    "@echo off" + eol + ...
    "if ""%~1""==""version"" (" + eol + ...
    "  echo 1.96.0" + eol + ...
    "  exit /b 0" + eol + ...
    ")" + eol + ...
    action + eol);
end

function names = databaseObjectNames(testCase, repoRoot, workspace)
% Built from the authoritative schema, in the test, independently of the tool.
addSourcePath(testCase, repoRoot);
databasePath = fullfile(workspace, "expectation_" + ...
    string(java.util.UUID.randomUUID) + ".sqlite");
conn = sqlite(char(databasePath), "create");
closer = onCleanup(@() closeQuietly(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
rows = fetch(conn, ...
    "SELECT name FROM sqlite_master " + ...
    "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name");
names = string(rows.name);
clear closer
end

function names = exportedEntryNames(entries)
if isstruct(entries)
    names = string({entries.name});
elseif iscell(entries)
    names = strings(numel(entries), 1);
    for k = 1:numel(entries)
        names(k) = string(entries{k}.name);
    end
else
    names = strings(0, 1);
end
names = names(:);
end

function bytes = readBytes(filePath)
fileId = fopen(filePath, "r");
closer = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8");
clear closer
end

function filePath = writeTextFile(filePath, text)
fileId = fopen(filePath, "w");
closer = onCleanup(@() fclose(fileId));
fwrite(fileId, char(text));
clear closer
end

function closeQuietly(conn)
try
    if isopen(conn), close(conn); end
catch
end
end

function workspace = workspaceForTest(testCase)
% Deliberately not prefixed "VAWLUME_schema_documentation_": that glob is what
% the leftover-workspace test counts, and a fixture matching it would mask a
% real leak.
workspace = fullfile(tempdir, "VAWLUME_schemadoc_fixture_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
testCase.addTeardown(@() removeTree(workspace));
end

function removeTree(root)
try
    if isfolder(root), rmdir(root, "s"); end
catch
end
end

function addToolsPath(testCase, repoRoot)
addFolderOnce(testCase, fullfile(repoRoot, "tools"));
end

function addSourcePath(testCase, repoRoot)
addFolderOnce(testCase, fullfile(repoRoot, "src"));
end

function addFolderOnce(testCase, folder)
if any(split(string(path), pathsep) == string(folder))
    return
end
addpath(folder);
testCase.addTeardown(@() rmpath(folder));
end

function repoRoot = repoRootForTest()
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
