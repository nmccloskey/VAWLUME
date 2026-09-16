function report = schema_documentation(options)
%SCHEMA_DOCUMENTATION Generate VAWLUME's committed schema representation.
%
%   REPORT = SCHEMA_DOCUMENTATION() builds a clean temporary SQLite database
%   from schema/schema.sql, exports it with tbls as JSON, validates the export
%   against the database it was taken from, and writes the result to
%   schema/schema.json. It returns a report struct.
%
%   SCHEMA_DOCUMENTATION() with no output argument prints the report.
%
%   REPORT = SCHEMA_DOCUMENTATION(Mode="check") regenerates the same way into a
%   temporary location and compares the result against the committed artifact
%   byte for byte, writing nothing. `report.fresh` is the verdict and
%   `report.differences` names every difference found rather than only the
%   first. With no output argument a stale artifact raises
%   `vawlume:schema:ArtifactStale`, so the check is usable as a command.
%
%   The two contributor-facing forms are:
%
%       addpath("tools"); schema_documentation                % regenerate
%       addpath("tools"); schema_documentation(Mode="check")  % verify
%
%   Name-value arguments:
%     Mode        - "generate" (default) or "check"
%     RepoRoot    - repository root (default: the parent of this file's folder)
%     SchemaPath  - authoritative schema (default: <RepoRoot>/schema/schema.sql)
%     OutputPath  - the artifact: written by "generate", read by "check"
%                   (default: <RepoRoot>/schema/schema.json)
%     TblsPath    - explicit tbls executable; otherwise discovered (see below)
%     Print       - print the report (default: true when nargout == 0)
%
%   schema/schema.sql is authoritative. schema.json is generated output and is
%   never hand-edited; if the generated file is wrong, this generator is wrong.
%
%   Both modes reach the artifact through one code path. A check that
%   regenerated differently from the generator would not be a check: it would be
%   a second generator that agrees with the first by coincidence until it does
%   not.
%
%   DETERMINISM. The export is byte-identical across runs and across working
%   directories with no canonicalization step at all. That holds because of two
%   properties of this function, not of tbls:
%
%     * the temporary database has a FIXED filename inside a UUID-named
%       directory. tbls records the database's filename in the export's `name`
%       field, so a tempname-derived filename would change the artifact on every
%       run. Stabilizing it by construction is why no post-processing step
%       exists.
%     * tbls runs with its working directory set to that temporary directory.
%       tbls reads `.tbls.yml` from the working directory. The repository has
%       none today, and this keeps a future one from silently changing the
%       artifact.
%
%   Nothing in the export is rewritten. A normalization that reached tables,
%   columns, keys or relationships would have become a second, hand-maintained
%   schema representation.
%
%   `driver.database_version` in the export reports the SQLite version bundled
%   inside the tbls binary -- not VAWLUME's, not MATLAB's, and not the schema's.
%   It is left exactly as tbls reports it, so that a tbls upgrade shows up as an
%   honest one-line diff rather than being hidden by normalization.
%
%   TBLS DISCOVERY, in order: the TblsPath argument, the VAWLUME_TBLS
%   environment variable, `tbls` on PATH, then conventional install locations.
%   Presence is never treated as capability: a tbls built by `go install`
%   without cgo answers `tbls version` correctly and then cannot open a SQLite
%   database at all, so capability is established by running the real export and
%   interpreting the failure.
%
%   tbls is a development dependency. No VAWLUME runtime path calls this
%   function, and an ordinary user analyzing data never needs tbls installed.
%
%   See also CHECK_REPOSITORY_SELF_DESCRIPTION, VAWLUME.DB.APPLYSCHEMA.

arguments
    options.Mode (1,1) string {mustBeMember(options.Mode, ["generate", "check"])} = "generate"
    options.RepoRoot (1,1) string = ""
    options.SchemaPath (1,1) string = ""
    options.OutputPath (1,1) string = ""
    options.TblsPath (1,1) string = ""
    options.Print = []
end

repoRoot = options.RepoRoot;
if repoRoot == ""
    repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
end
repoRoot = absolutePath(repoRoot);

schemaPath = options.SchemaPath;
if schemaPath == ""
    schemaPath = fullfile(repoRoot, "schema", "schema.sql");
end
if ~isfile(schemaPath)
    error("vawlume:schema:SchemaFileNotFound", ...
        "Authoritative schema not found: %s", schemaPath);
end

outputPath = options.OutputPath;
if outputPath == ""
    outputPath = fullfile(repoRoot, "schema", "schema.json");
end
outputPath = absolutePath(outputPath);

if options.Mode == "check" && ~isfile(outputPath)
    % Fail before spending four seconds regenerating something there is nothing
    % to compare against. A missing artifact is not a stale artifact: it is a
    % check that cannot run, and saying so is more useful than saying "differs".
    error("vawlume:schema:ArtifactMissing", ...
        "There is no committed schema representation at %s, so there is " + ...
        "nothing to check.\nRun `%s` to generate it.", outputPath, remedyCommand());
end

doPrint = options.Print;
if isempty(doPrint)
    doPrint = (nargout == 0);
end

tbls = resolveTbls(options.TblsPath);

sourcePath = fullfile(repoRoot, "src");
removeSourcePath = ~pathContains(sourcePath);
if removeSourcePath, addpath(sourcePath); end
cleanupPath = onCleanup(@() restoreSourcePath(sourcePath, removeSourcePath));

% Fixed database filename inside a UUID-named directory: see DETERMINISM above.
workspace = fullfile(tempdir, "VAWLUME_schema_documentation_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
cleanupWorkspace = onCleanup(@() removeTree(workspace));

databasePath = fullfile(workspace, "vawlume.sqlite");
exportPath = fullfile(workspace, "schema.json");

expected = buildCleanDatabase(databasePath, schemaPath);

runTblsExport(tbls, databasePath, exportPath, workspace);
summary = validateExport(exportPath, expected, tbls);

report = struct();
report.mode = options.Mode;
report.repo_root = repoRoot;
report.schema_path = string(schemaPath);
report.output_path = outputPath;
report.tbls_path = tbls.path;
report.tbls_version = tbls.version;
report.tbls_pinned_version = pinnedVersion();
report.database_objects = numel(expected.object_names);
report.database_tables = expected.table_count;
report.database_views = expected.view_count;
report.exported_tables = summary.exported_tables;
report.relations = summary.relations;
report.remedy = remedyCommand();

if options.Mode == "generate"
    report.bytes = publishArtifact(exportPath, outputPath);
    report.artifact_bytes = report.bytes;
    report.fresh = true;
    report.differences = strings(0, 1);
    report.written = true;
else
    comparison = compareArtifact(exportPath, outputPath);
    report.bytes = comparison.regenerated_bytes;
    report.artifact_bytes = comparison.artifact_bytes;
    report.fresh = comparison.fresh;
    report.differences = comparison.differences;
    report.written = false;
end

if doPrint
    printReport(report);
end

if nargout == 0 && ~report.fresh
    % Same convention as CHECK_REPOSITORY_SELF_DESCRIPTION: called as a command
    % a stale artifact is an error; asked for a value the caller inspects
    % `fresh` and `differences` itself.
    error("vawlume:schema:ArtifactStale", ...
        "%s is stale: it is not what schema/schema.sql now generates.\n%s\n" + ...
        "Run `%s` to regenerate it, and commit the result.\n%s", ...
        outputPath, strjoin("  - " + report.differences, newline), ...
        remedyCommand(), tblsVersionCaveat(tbls));
end
end

% ---------------------------------------------------------------------------
% Pins
% ---------------------------------------------------------------------------

function value = pinnedVersion()
% The official release binary. A `go install` build without cgo carries this
% same version number and cannot read SQLite, so the version is a label, not a
% capability claim.
value = "v1.96.0";
end

function value = releaseUrl()
value = "https://github.com/k1LoW/tbls/releases";
end

function value = remedyCommand()
% What a contributor actually types, from the repository root. The person who
% hits a stale-artifact failure is usually not the person who wrote this tool,
% so the failure names the command rather than describing it.
value = "addpath(""tools""); schema_documentation";
end

function value = tblsVersionCaveat(tbls)
value = sprintf("Regenerated with tbls %s at %s (VAWLUME pins %s). " + ...
    "If the only difference is driver.database_version, the tbls binary " + ...
    "changed rather than the schema.", tbls.version, tbls.path, pinnedVersion());
end

% ---------------------------------------------------------------------------
% tbls discovery
% ---------------------------------------------------------------------------

function tbls = resolveTbls(explicitPath)
% Four tiers, most explicit first. Capability is not established here -- see
% RUNTBLSEXPORT.
attempts = strings(0, 1);

if strlength(explicitPath) > 0
    if ~isfile(explicitPath)
        % Still the full actionable message: somebody who passed a wrong path
        % needs the pinned version and the download location as much as
        % somebody who installed nothing.
        raiseTblsNotFound("TblsPath=" + explicitPath + " (not a file)");
    end
    tbls = describeTbls(absolutePath(explicitPath), "TblsPath argument");
    return
end

environmentPath = string(getenv("VAWLUME_TBLS"));
if strlength(environmentPath) > 0
    if isfile(environmentPath)
        tbls = describeTbls(absolutePath(environmentPath), "VAWLUME_TBLS");
        return
    end
    attempts(end+1) = "VAWLUME_TBLS=" + environmentPath + " (not a file)";
end

pathHit = findOnSearchPath(executableName());
if strlength(pathHit) > 0
    tbls = describeTbls(pathHit, "PATH");
    return
end
attempts(end+1) = executableName() + " on PATH";

for candidate = conventionalLocations()'
    if isfile(candidate)
        tbls = describeTbls(absolutePath(candidate), "conventional location");
        return
    end
end
attempts(end+1) = "conventional locations (" + ...
    strjoin(conventionalPatterns(), ", ") + ")";

raiseTblsNotFound(attempts);
end

function raiseTblsNotFound(attempts)
error("vawlume:schema:TblsNotFound", ...
    "tbls was not found, so the schema representation cannot be generated.\n" + ...
    "VAWLUME pins tbls %s, the official release binary, from %s.\n" + ...
    "Install it and then do one of: put it on PATH, set the VAWLUME_TBLS " + ...
    "environment variable to its full path, or pass TblsPath.\n" + ...
    "Searched: %s", pinnedVersion(), releaseUrl(), strjoin(attempts, "; "));
end

function name = executableName()
if ispc
    name = "tbls.exe";
else
    name = "tbls";
end
end

function patterns = conventionalPatterns()
% `go install` puts binaries in ~/go/bin. The official release archive extracts
% into a version-named directory instead, so wherever it was unzipped the
% executable sits one level below that directory rather than in it. Both places
% it is normally unzipped are searched: beside the Go binaries, and the home
% directory itself.
home = userHome();
patterns = [ ...
    fullfile(home, "go", "bin", executableName()); ...
    fullfile(home, "go", "bin", "tbls_*", executableName()); ...
    fullfile(home, "tbls_*", executableName()); ...
    fullfile(home, "bin", executableName())];
end

function locations = conventionalLocations()
patterns = conventionalPatterns();
locations = strings(0, 1);
for k = 1:numel(patterns)
    entries = dir(patterns(k));
    for e = 1:numel(entries)
        if ~entries(e).isdir
            locations(end+1) = string(fullfile(entries(e).folder, entries(e).name)); %#ok<AGROW>
        end
    end
end
end

function home = userHome()
home = string(getenv("USERPROFILE"));
if strlength(home) == 0
    home = string(getenv("HOME"));
end
if strlength(home) == 0
    home = string(java.lang.System.getProperty("user.home"));
end
end

function hit = findOnSearchPath(name)
hit = "";
if ispc
    command = "where " + name;
else
    command = "which " + name;
end
[status, output] = system(command);
if status ~= 0
    return
end
lines = splitlines(strtrim(string(output)));
lines = lines(strlength(strtrim(lines)) > 0);
if isempty(lines)
    return
end
candidate = strtrim(lines(1));
if isfile(candidate)
    hit = absolutePath(candidate);
end
end

function tbls = describeTbls(path, source)
tbls = struct("path", string(path), "source", string(source), "version", "unknown");
% Recorded for the report and for diagnosing an unexpected artifact diff. It is
% deliberately not enforced and deliberately not trusted: the broken cgo-less
% build answers this correctly.
[status, output] = system("""" + path + """ version");
if status == 0
    reported = strtrim(string(output));
    reported = splitlines(reported);
    if ~isempty(reported) && strlength(strtrim(reported(1))) > 0
        tbls.version = strtrim(reported(1));
    end
end
end

% ---------------------------------------------------------------------------
% Clean database
% ---------------------------------------------------------------------------

function expected = buildCleanDatabase(databasePath, schemaPath)
% Build from the authoritative schema through the production code path, then
% read back what the database actually contains. The expectation the export is
% measured against is derived here, from the live database, and never from a
% list written down somewhere -- a written list would be a second schema
% definition and would rot silently.
%
% `registerBuiltinSemantics` is deliberately not called. It inserts seed rows
% and creates no schema objects: sqlite_master is identical with and without it,
% verified rather than assumed.
conn = sqlite(char(databasePath), "create");
cleanupConnection = onCleanup(@() closeConnection(conn));

try
    vawlume.db.applySchema(conn, schemaPath);
catch exception
    error("vawlume:schema:SchemaInitializationFailed", ...
        "Applying %s to a clean database failed, so nothing was exported: %s", ...
        schemaPath, exception.message);
end

rows = fetch(conn, ...
    "SELECT type, name FROM sqlite_master " + ...
    "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' " + ...
    "ORDER BY name");

if height(rows) == 0
    error("vawlume:schema:SchemaInitializationFailed", ...
        "Applying %s produced a database with no tables or views. " + ...
        "tbls would have exported a plausible but empty representation, " + ...
        "so nothing was exported.", schemaPath);
end

types = string(rows.type);
expected = struct();
expected.object_names = string(rows.name);
expected.table_count = sum(types == "table");
expected.view_count = sum(types == "view");
end

% ---------------------------------------------------------------------------
% Export
% ---------------------------------------------------------------------------

function runTblsExport(tbls, databasePath, exportPath, workingDirectory)
% Backslashes break tbls DSN parsing: the drive-letter colon is read as a port
% separator (`invalid port ":\Users\..." after host`). Forward slashes work.
dsn = "sqlite://" + replace(string(databasePath), "\", "/");

% Working directory pinned to the temporary directory: tbls reads `.tbls.yml`
% from the working directory, and the artifact must not depend on where the
% generator happened to be run from.
originalDirectory = pwd;
cleanupDirectory = onCleanup(@() cd(originalDirectory));
cd(workingDirectory);

command = """" + tbls.path + """ out -t json --dsn """ + dsn + """ -o """ + ...
    exportPath + """";
[status, output] = system(command);

if status == 0
    return
end

output = strtrim(string(output));
if contains(output, "CGO_ENABLED=0") || contains(output, "requires cgo")
    error("vawlume:schema:TblsNotCapable", ...
        "tbls at %s reports version %s but cannot read SQLite databases.\n" + ...
        "This is the signature of a `go install` build made without cgo: it " + ...
        "answers `tbls version` correctly and then fails on every SQLite DSN.\n" + ...
        "Replace it with the official release binary for tbls %s from %s.\n" + ...
        "tbls said: %s", tbls.path, tbls.version, pinnedVersion(), releaseUrl(), output);
end

error("vawlume:schema:TblsExportFailed", ...
    "tbls at %s failed to export the schema (exit status %d). " + ...
    "No artifact was written.\ntbls said: %s", tbls.path, status, output);
end

% ---------------------------------------------------------------------------
% Validation
% ---------------------------------------------------------------------------

function summary = validateExport(exportPath, expected, tbls)
% An export is refused unless it accounts for every table and view the database
% actually has. The point is not tidiness: tbls introspecting a database that
% failed to initialize produces well-formed, plausible, nearly-empty JSON, and
% that is exactly the artifact that must never replace a valid one.
if ~isfile(exportPath)
    error("vawlume:schema:ExportInvalid", ...
        "tbls at %s exited successfully but wrote no file to %s.", ...
        tbls.path, exportPath);
end

text = fileread(exportPath);
try
    data = jsondecode(text);
catch exception
    error("vawlume:schema:ExportInvalid", ...
        "The tbls export at %s is not valid JSON: %s", exportPath, exception.message);
end

requiredFields = ["name", "tables", "relations", "driver"];
missingFields = requiredFields(~isfield(data, requiredFields));
if ~isempty(missingFields)
    error("vawlume:schema:ExportInvalid", ...
        "The tbls export is missing top-level field(s): %s. " + ...
        "Expected %s.", strjoin(missingFields, ", "), strjoin(requiredFields, ", "));
end

exportedNames = entryNames(data.tables);
missingObjects = setdiff(expected.object_names, exportedNames);
if ~isempty(missingObjects)
    % Report every missing object, not the first: one run should name all of it.
    error("vawlume:schema:ExportIncomplete", ...
        "The tbls export accounts for %d of the %d tables and views in the " + ...
        "database, so it is partial and was not published.\nMissing: %s", ...
        numel(exportedNames), numel(expected.object_names), ...
        strjoin(missingObjects, ", "));
end

summary = struct();
summary.exported_tables = numel(exportedNames);
summary.relations = countEntries(data.relations);
end

function names = entryNames(entries)
% jsondecode yields a struct array when every entry has the same fields and a
% cell array when they differ, and tbls entries differ. Handle both.
if isstruct(entries)
    if isfield(entries, "name")
        names = string({entries.name});
    else
        names = strings(0, 1);
    end
elseif iscell(entries)
    names = strings(numel(entries), 1);
    for k = 1:numel(entries)
        entry = entries{k};
        if isstruct(entry) && isfield(entry, "name")
            names(k) = string(entry.name);
        end
    end
else
    names = strings(0, 1);
end
names = names(:);
end

function count = countEntries(entries)
if isstruct(entries) || iscell(entries)
    count = numel(entries);
else
    count = 0;
end
end

% ---------------------------------------------------------------------------
% Comparison
% ---------------------------------------------------------------------------

function comparison = compareArtifact(regeneratedPath, artifactPath)
% The verdict is byte for byte. That was chosen deliberately over a normalizing
% comparison because normalizing in the comparator would hide a real class of
% difference, and a freshness check that cannot see a difference is not one.
%
% Everything below the verdict is diagnosis rather than judgement. "The files
% differ" is a true and useless answer about a 660 KB artifact, so the causes
% are localized and every one of them is reported -- not the first.
regenerated = readAllBytes(regeneratedPath);
artifact = readAllBytes(artifactPath);

comparison = struct();
comparison.regenerated_bytes = numel(regenerated);
comparison.artifact_bytes = numel(artifact);
comparison.fresh = isequal(regenerated, artifact);
comparison.differences = strings(0, 1);

if comparison.fresh
    return
end

differences = strings(0, 1);

% Line endings first: it is the one cause whose diff is enormous and whose
% meaning has nothing to do with the schema. Note that the comparison itself
% stays byte for byte -- only the explanation knows what CRLF is.
ending = lineEndingDifference(regenerated, artifact);
if strlength(ending) > 0
    differences(end+1, 1) = ending;
end

artifactText = string(fileread(artifactPath));
regeneratedText = string(fileread(regeneratedPath));

differences = [differences; structuralDifferences(artifactText, regeneratedText)];
differences = [differences; lineDifferences(artifactText, regeneratedText)];

if comparison.artifact_bytes ~= comparison.regenerated_bytes
    differences(end+1, 1) = sprintf( ...
        "size: the committed artifact is %d bytes, regeneration produces %d", ...
        comparison.artifact_bytes, comparison.regenerated_bytes);
end

if isempty(differences)
    % No known cause reaches here. But a check that says "stale" and then names
    % nothing would be least trustworthy exactly where it matters most, so it
    % says that instead of saying nothing.
    differences = "the files differ byte for byte, but no readable difference " + ...
        "could be localized; compare them directly";
end

comparison.differences = differences;
end

function message = lineEndingDifference(regenerated, artifact)
% True only when line endings explain the whole difference.
message = "";
if ~isequal(stripCarriageReturns(regenerated), stripCarriageReturns(artifact))
    return
end
message = sprintf("line endings: the committed artifact (%s) and the " + ...
    "regenerated one (%s) are identical apart from line endings, so nothing " + ...
    "about the schema changed. Check that .gitattributes marks " + ...
    "schema/schema.json -text, so git stores and checks it out verbatim, " + ...
    "and verify with: git ls-files --eol -- schema/schema.json", ...
    endingStyle(artifact), endingStyle(regenerated));
end

function style = endingStyle(bytes)
lineFeeds = sum(bytes == 10);
carriageReturns = sum(bytes == 13);
if carriageReturns == 0
    style = "LF";
elseif carriageReturns == lineFeeds
    style = "CRLF";
else
    style = "mixed";
end
end

function differences = structuralDifferences(artifactText, regeneratedText)
% Named objects rather than byte offsets, because "table recordings changed" is
% a sentence a reader can act on and "byte 412905" is not.
differences = strings(0, 1);

artifact = decodeQuietly(artifactText);
regenerated = decodeQuietly(regeneratedText);

if isempty(artifact)
    differences(end+1, 1) = "content: the committed artifact is not valid JSON, " + ...
        "so it cannot be compared structurally. It is generated output and is " + ...
        "never hand-edited; regenerate it.";
    return
end
if isempty(regenerated)
    return
end
artifact = artifact{1};
regenerated = regenerated{1};

if isfield(artifact, "name") && isfield(regenerated, "name") ...
        && string(artifact.name) ~= string(regenerated.name)
    differences(end+1, 1) = sprintf("name: the committed artifact was taken " + ...
        "from a database called %s, regeneration produces %s", ...
        string(artifact.name), string(regenerated.name));
end

if isfield(artifact, "driver") && isfield(regenerated, "driver")
    differences = [differences; ...
        driverVersionDifference(artifact.driver, regenerated.driver)];
end

if isfield(artifact, "tables") && isfield(regenerated, "tables")
    differences = [differences; tableDifferences(artifact.tables, regenerated.tables)];
end

if isfield(artifact, "relations") && isfield(regenerated, "relations")
    artifactCount = countEntries(artifact.relations);
    regeneratedCount = countEntries(regenerated.relations);
    if artifactCount ~= regeneratedCount
        differences(end+1, 1) = sprintf("relations: the committed artifact has " + ...
            "%d, regeneration produces %d", artifactCount, regeneratedCount);
    end
end
end

function differences = driverVersionDifference(artifactDriver, regeneratedDriver)
% This field reports the SQLite version bundled inside the tbls binary -- not
% VAWLUME's, not MATLAB's, and not the schema's. It is the one field that moves
% with no schema change behind it, so it is named rather than left to be
% discovered in a line diff.
differences = strings(0, 1);
if ~isfield(artifactDriver, "database_version") ...
        || ~isfield(regeneratedDriver, "database_version")
    return
end
before = string(artifactDriver.database_version);
after = string(regeneratedDriver.database_version);
if before == after
    return
end
differences = sprintf("driver.database_version: %s -> %s. That is the SQLite " + ...
    "version bundled inside the tbls binary, so this difference means tbls " + ...
    "changed rather than the schema. A diff that is only this line is not a " + ...
    "schema change; regenerating and committing resolves it.", before, after);
end

function differences = tableDifferences(artifactTables, regeneratedTables)
differences = strings(0, 1);
artifactNames = entryNames(artifactTables);
regeneratedNames = entryNames(regeneratedTables);

differences = [differences; namedListDifference( ...
    "objects the schema now has that the committed artifact does not", ...
    setdiff(regeneratedNames, artifactNames))];
differences = [differences; namedListDifference( ...
    "objects in the committed artifact that the schema no longer has", ...
    setdiff(artifactNames, regeneratedNames))];

shared = intersect(artifactNames, regeneratedNames);
changed = strings(0, 1);
for k = 1:numel(shared)
    before = entryNamed(artifactTables, shared(k));
    after = entryNamed(regeneratedTables, shared(k));
    if ~isequal(jsonencode(before), jsonencode(after))
        changed(end+1, 1) = shared(k); %#ok<AGROW>
    end
end
differences = [differences; namedListDifference( ...
    "objects whose exported definition changed", changed)];
end

function difference = namedListDifference(label, names)
difference = strings(0, 1);
if isempty(names)
    return
end
limit = 20;
names = names(:);
shown = strjoin(names(1:min(numel(names), limit)), ", ");
if numel(names) > limit
    shown = shown + sprintf(", and %d more", numel(names) - limit);
end
difference = sprintf("%s (%d): %s", label, numel(names), shown);
end

function differences = lineDifferences(artifactText, regeneratedText)
% Line numbers, so a reader can open both files and look. This is a positional
% comparison rather than a real diff: one inserted line shifts everything after
% it and reads as many differences. That is acceptable for a generated
% artifact, where the answer is always "regenerate" and never "merge".
differences = strings(0, 1);
artifactLines = splitlines(artifactText);
regeneratedLines = splitlines(regeneratedText);

limit = 10;
shown = 0;
total = 0;
for k = 1:min(numel(artifactLines), numel(regeneratedLines))
    if artifactLines(k) == regeneratedLines(k)
        continue
    end
    total = total + 1;
    if shown < limit
        shown = shown + 1;
        differences(end+1, 1) = sprintf("line %d: committed %s, regenerated %s", ...
            k, excerpt(artifactLines(k)), excerpt(regeneratedLines(k))); %#ok<AGROW>
    end
end

if total > shown
    differences(end+1, 1) = sprintf("... and %d further differing line(s)", ...
        total - shown);
end

if numel(artifactLines) ~= numel(regeneratedLines)
    differences(end+1, 1) = sprintf("line count: the committed artifact has %d " + ...
        "lines, regeneration produces %d", numel(artifactLines), numel(regeneratedLines));
end
end

function value = excerpt(line)
line = strtrim(line);
if strlength(line) == 0
    value = "(blank)";
    return
end
limit = 60;
if strlength(line) > limit
    line = extractBefore(line, limit + 1) + "...";
end
% Single quotes: every line of the artifact is JSON and starts with a double
% quote of its own, so delimiting with one more would be unreadable.
value = "'" + line + "'";
end

function entry = entryNamed(entries, name)
entry = [];
if isstruct(entries)
    index = find(string({entries.name}) == name, 1);
    if ~isempty(index)
        entry = entries(index);
    end
elseif iscell(entries)
    for k = 1:numel(entries)
        candidate = entries{k};
        if isstruct(candidate) && isfield(candidate, "name") ...
                && string(candidate.name) == name
            entry = candidate;
            return
        end
    end
end
end

function value = decodeQuietly(text)
% A cell, so that "failed to decode" and "decoded to something empty" stay
% distinguishable.
try
    value = {jsondecode(text)};
catch
    value = {};
end
end

function bytes = readAllBytes(filePath)
fileId = fopen(filePath, "r");
if fileId < 0
    error("vawlume:schema:ArtifactMissing", ...
        "Could not open %s for reading.", filePath);
end
cleanupFile = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8");
end

function bytes = stripCarriageReturns(bytes)
bytes = bytes(bytes ~= 13);
end

% ---------------------------------------------------------------------------
% Publication
% ---------------------------------------------------------------------------

function bytes = publishArtifact(exportPath, outputPath)
% A failed run must never replace a valid artifact with an empty or partial one.
% Every failure above this line happens before the destination is touched at
% all; this last step stages beside the destination and renames, so a failure
% during the copy itself cannot leave a truncated file in place either.
destinationFolder = fileparts(outputPath);
if strlength(destinationFolder) > 0 && ~isfolder(destinationFolder)
    mkdir(destinationFolder);
end

stagedPath = outputPath + ".generating";
cleanupStaged = onCleanup(@() deleteIfExists(stagedPath));

[copied, message] = copyfile(exportPath, stagedPath, "f");
if ~copied
    error("vawlume:schema:ExportPublishFailed", ...
        "The export could not be staged at %s: %s. %s was left untouched.", ...
        stagedPath, message, outputPath);
end

[moved, message] = movefile(stagedPath, outputPath, "f");
if ~moved
    error("vawlume:schema:ExportPublishFailed", ...
        "The staged export could not be moved into place at %s: %s.", ...
        outputPath, message);
end

info = dir(outputPath);
bytes = info(1).bytes;
end

% ---------------------------------------------------------------------------
% Utilities
% ---------------------------------------------------------------------------

function path = absolutePath(path)
path = string(path);
if strlength(path) == 0
    return
end
try
    path = string(java.io.File(char(path)).getCanonicalPath());
catch
    path = string(path);
end
end

function value = pathContains(target)
value = any(split(string(path), pathsep) == string(target));
end

function restoreSourcePath(sourcePath, shouldRemove)
if shouldRemove && pathContains(sourcePath), rmpath(sourcePath); end
end

function closeConnection(conn)
try
    if isopen(conn), close(conn); end
catch
end
end

function deleteIfExists(path)
try
    if isfile(path), delete(path); end
catch
end
end

function removeTree(root)
% Tolerant because this runs as an onCleanup destructor on error paths too,
% where Windows may still hold the database file briefly after close.
try
    if isfolder(root), rmdir(root, "s"); end
catch
end
end

function printReport(report)
fprintf("VAWLUME schema documentation (%s)\n", report.mode);
fprintf("  tbls        %s\n", report.tbls_path);
fprintf("  version     %s (pinned %s)\n", report.tbls_version, report.tbls_pinned_version);
fprintf("  schema      %s\n", report.schema_path);
fprintf("  database    %d tables + %d views = %d objects\n", ...
    report.database_tables, report.database_views, report.database_objects);
fprintf("  export      %d entries, %d relations\n", ...
    report.exported_tables, report.relations);

if report.mode == "generate"
    fprintf("  written     %s (%.0f KB)\n", report.output_path, report.bytes / 1024);
    return
end

fprintf("  artifact    %s (%.0f KB)\n", report.output_path, report.artifact_bytes / 1024);
if report.fresh
    fprintf("\n  FRESH: the committed representation is what schema.sql generates.\n");
    return
end

fprintf("\n  STALE: the committed representation is not what schema.sql generates.\n");
for k = 1:numel(report.differences)
    fprintf("    - %s\n", report.differences(k));
end
fprintf("\n  Run `%s` to regenerate it, and commit the result.\n", report.remedy);
end
