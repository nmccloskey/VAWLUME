function demonstration = csv_export_demo(options)
%CSV_EXPORT_DEMO Demonstrate self-describing CSV database export.
%
% DEMONSTRATION = CSV_EXPORT_DEMO() builds the production Phase 1 fixture in
% a disposable workspace, exports it in the three supported workflows, reads
% one data CSV back with every variable forced to string, and removes the
% workspace before returning.
%
% The workflows are:
%   1. default export of every base table;
%   2. explicit export of one table and one view;
%   3. schema-only reference generation without a database argument.
%
% RetainArtifacts=true is intended for inspection and integration testing.
% The caller then owns removing DEMONSTRATION.workspace_root.

arguments
    options.Print (1,1) logical = true
    options.RepoRoot (1,1) string = ""
    options.WorkspaceRoot (1,1) string = ""
    options.RetainArtifacts (1,1) logical = false
end

repoRoot = normalizedRepoRoot(options.RepoRoot);
sourcePath = fullfile(repoRoot, "src");
removeSourcePath = ~pathContains(sourcePath);
if removeSourcePath
    addpath(sourcePath);
end
cleanupPath = onCleanup(@() restoreSourcePath(sourcePath, removeSourcePath));

workspaceRoot = options.WorkspaceRoot;
if strlength(workspaceRoot) == 0
    workspaceRoot = fullfile(tempdir, ...
        "VAWLUME CSV export demo " + string(java.util.UUID.randomUUID));
else
    workspaceRoot = canonicalPath(workspaceRoot);
end
if isfile(workspaceRoot) || isfolder(workspaceRoot)
    error("vawlume:examples:WorkspaceExists", ...
        "The CSV export demonstration workspace already exists: %s", workspaceRoot);
end
parent = string(fileparts(workspaceRoot));
if ~isfolder(parent)
    error("vawlume:examples:WorkspaceParentMissing", ...
        "The CSV export demonstration workspace parent does not exist: %s", parent);
end
mkdir(workspaceRoot);
if ~options.RetainArtifacts
    cleanupWorkspace = onCleanup(@() removeTree(workspaceRoot));
end

databasePath = fullfile(workspaceRoot, "phase1_fixture.sqlite");
[conn, fixtureSummary] = vawlume.db.createPhase1FixtureDatabase(databasePath, repoRoot);
cleanupConnection = onCleanup(@() closeConnection(conn));

% The production fixture already contains NULL optional fields. Add one empty
% TEXT value to the same column so the exported CSV visibly distinguishes an
% empty quoted field ("") from a bare NULL field without creating a second
% demonstration-only database.
execute(conn, ...
    "UPDATE detections SET notes = '' " + ...
    "WHERE detection_id = (SELECT MIN(detection_id) FROM detections)");
execute(conn, ...
    "UPDATE detections SET notes = NULL " + ...
    "WHERE detection_id = (SELECT detection_id FROM detections " + ...
    "ORDER BY detection_id LIMIT 1 OFFSET 1)");
close(conn);
clear cleanupConnection

sourceSha256Before = sha256(databasePath);
normalOutput = fullfile(workspaceRoot, "normal_export");
selectiveOutput = fullfile(workspaceRoot, "selective_export");
schemaOutput = fullfile(workspaceRoot, "schema_reference");

normal = vawlume.export.database(databasePath, Output=normalOutput);
selective = vawlume.export.database(databasePath, Output=selectiveOutput, ...
    Tables=["detections", "v_detection_core"]);
schemaOnly = vawlume.export.database(Output=schemaOutput, SchemaOnly=true);
sourceSha256After = sha256(databasePath);

strictPath = fullfile(normalOutput, "csv", "detections.csv");
importOptions = detectImportOptions(strictPath, Delimiter=",", TextType="string");
importOptions = setvartype(importOptions, "string");
strictRows = readtable(strictPath, importOptions);
notes = strictRows.notes;
strictRead = struct( ...
    file="csv/detections.csv", ...
    header=string(strictRows.Properties.VariableNames), ...
    row_count=height(strictRows), ...
    null_count=sum(ismissing(notes)), ...
    empty_text_count=sum(~ismissing(notes) & strlength(notes) == 0));

demonstration = struct( ...
    architecture=[ ...
        "production Phase 1 fixture"; ...
        "vawlume.export.database"; ...
        "self-describing CSV packages"; ...
        "strict all-string CSV read-back"], ...
    fixture_summary=fixtureSummary, ...
    normal=packageSummary(normalOutput, normal), ...
    selective=packageSummary(selectiveOutput, selective), ...
    schema_only=packageSummary(schemaOutput, schemaOnly), ...
    strict_read=strictRead, ...
    source_sha256_before=sourceSha256Before, ...
    source_sha256_after=sourceSha256After, ...
    source_unchanged=sourceSha256Before == sourceSha256After, ...
    workspace_root=workspaceRoot, ...
    database_path=databasePath, ...
    retained=options.RetainArtifacts, ...
    temporary_artifacts_removed=false);

if options.Print
    printDemonstration(demonstration);
end

if ~options.RetainArtifacts
    clear cleanupWorkspace
end
demonstration.temporary_artifacts_removed = ~isfolder(workspaceRoot);
clear cleanupPath
end

function value = packageSummary(output, result)
value = struct( ...
    output_dir=string(output), ...
    result=result, ...
    files=packageFiles(output));
end

function files = packageFiles(root)
listing = dir(fullfile(root, "**", "*"));
listing = listing(~[listing.isdir]);
files = strings(numel(listing), 1);
prefix = strlength(canonicalPath(root)) + 2;
for index = 1:numel(listing)
    full = canonicalPath(fullfile(listing(index).folder, listing(index).name));
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
if fileId < 0
    error("vawlume:examples:FileReadFailed", "Could not read %s.", path);
end
cleanupFile = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "uint8=>uint8")';
clear cleanupFile
end

function root = normalizedRepoRoot(root)
if strlength(root) == 0
    root = fileparts(fileparts(mfilename("fullpath")));
end
root = canonicalPath(root);
end

function value = canonicalPath(value)
try
    value = string(java.io.File(char(value)).getCanonicalPath());
catch
    value = string(value);
end
end

function value = pathContains(target)
entries = split(string(path), pathsep);
value = any(entries == string(target));
end

function restoreSourcePath(sourcePath, shouldRemove)
if shouldRemove && pathContains(sourcePath)
    rmpath(sourcePath);
end
end

function closeConnection(conn)
try
    if isopen(conn)
        close(conn);
    end
catch
end
end

function removeTree(root)
if isfolder(root)
    rmdir(root, "s");
end
end

function printDemonstration(value)
disp("VAWLUME CSV EXPORT DEMONSTRATION")
disp(strjoin(value.architecture, " -> "))
fprintf("Default export:   %d tables, %d rows\n", ...
    value.normal.result.exported_object_count, ...
    value.normal.result.exported_row_total);
fprintf("Selective export: %s\n", strjoin( ...
    value.selective.result.objects.object_name( ...
    value.selective.result.objects.exported), ", "));
fprintf("Schema reference: %d described objects, no data files\n", ...
    value.schema_only.result.supported_object_count);
fprintf("Strict read:      %d rows, %d NULL notes, %d empty-text notes\n", ...
    value.strict_read.row_count, value.strict_read.null_count, ...
    value.strict_read.empty_text_count);
fprintf("Source unchanged: %d\n", value.source_unchanged);
if value.retained
    fprintf("Retained at:      %s\n", value.workspace_root);
else
    fprintf("Temporary artifacts removed: %d\n", ...
        value.temporary_artifacts_removed);
end
end
