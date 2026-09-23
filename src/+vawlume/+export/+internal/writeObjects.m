function record = writeObjects(dbPath, stagingRoot, options)
%WRITEOBJECTS Export selected relational objects as canonical CSV into staging.
%
%   RECORD = vawlume.export.internal.writeObjects(DBPATH, STAGINGROOT, ...)
%
%   The CSV export core. It opens the VAWLUME database at DBPATH read-only,
%   resolves the selection against the committed schema, and writes one CSV
%   per selected object to <STAGINGROOT>/csv/<object_name>.csv. It returns the
%   per-object record the package layer projects, so nothing already counted is
%   recounted later.
%
%   This is not the public API. vawlume.export.database wraps it, and that
%   wrapper owns format dispatch, the destination, the package metadata, and
%   publication. The core writes only inside a staging root the caller already
%   created and owns, and it never publishes anything.
%
%   Name-value arguments:
%     Tables                      "all" (default) or exact object names
%     IncludeViews                whether "all" also selects the views (default false)
%     AllowSchemaVersionMismatch  record a warning instead of failing when the
%                                 source's schema_info version differs from
%                                 schema.sql (default false)
%     RepoRoot                    repository root (default: derived from this file)
%     AfterObjectFcn              TEST SEAM. Called as fcn(objectName) after each
%                                 object is written, inside the change guard; it
%                                 lets a test inject a failure or a concurrent
%                                 write mid-export. Empty by default
%
%   SOURCE SAFETY (contract §E.6). There is one read-only connection for the
%   whole export; a write through it is refused by SQLite. A path that does not
%   exist is refused before anything is opened, and read-only mode cannot create
%   a file in any case. There is no read transaction: in MATLAB's driver one
%   leaves the connection unclosable and blocks concurrent writers. Instead,
%   PRAGMA data_version is read before the first object and after the last. If
%   it changed, the export fails with vawlume:export:SourceChangedDuringExport.
%   That is DETECTION, not isolation. The guarantee is one coherent database
%   state or no export, not a serialized snapshot.
%
%   STAGING SAFETY. <STAGINGROOT>/csv must not already exist. The core creates
%   it, and on ANY failure removes it and everything in it before rethrowing, so
%   a failed export leaves the staging root as it found it. It never deletes
%   anything it did not create.
%
%   VERSION AND STRUCTURE (contract §§B.8, I layer 3). The source's
%   schema_info version must equal schema.sql's, or the export fails with
%   vawlume:export:SchemaVersionMismatch. With AllowSchemaVersionMismatch=true
%   it proceeds with a warning, and each object is read with the source's own
%   columns, so the export stays faithful to the database that was actually
%   given. Any difference from the committed columns is then a warning. At a
%   matching version the columns must agree exactly, or the export fails with
%   vawlume:export:SourceStructureMismatch. A selected object absent from the
%   source is always vawlume:export:SourceObjectMissing.
%
%   RECORD fields:
%     status                      "exported"
%     staging_root, csv_dir       absolute paths
%     source                      struct: path, filename, bytes, schema_version,
%                                 user_version, data_version
%     repository_schema_version
%     supported_object_count      every object in the committed structure
%     selected_object_count, exported_object_count, exported_row_total
%     objects                     table: object_name, object_kind,
%                                 schema_position, filename, row_count,
%                                 column_count, columns -- in schema order
%     files                       package-relative paths, in schema order
%     warnings                    table: code, object_name, message
%     large_object_row_threshold  the advisory row count (contract §E.7)
%
%   See also VAWLUME.EXPORT.INTERNAL.RESOLVESELECTION,
%   VAWLUME.EXPORT.INTERNAL.READOBJECT, VAWLUME.EXPORT.INTERNAL.WRITECSV,
%   VAWLUME.SCHEMA.LOADSTRUCTURE.

arguments
    dbPath (1,1) string
    stagingRoot (1,1) string
    options.Tables = "all"
    options.IncludeViews (1,1) logical = false
    options.AllowSchemaVersionMismatch (1,1) logical = false
    options.RepoRoot (1,1) string = ""
    options.AfterObjectFcn = []
end

% An advisory tripwire extrapolated from a 100,000-row measurement, not a
% validated limit (contract §E.7). It warns and never fails.
largeObjectRows = 5000000;

repoRoot = options.RepoRoot;
if repoRoot == ""
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath")))))));
end

% Everything a caller can get wrong is refused before the source is opened or
% the staging root is touched.
structure = vawlume.schema.loadStructure(RepoRoot=repoRoot);
repositoryVersion = vawlume.schema.repositoryVersion(RepoRoot=repoRoot);
selection = vawlume.export.internal.resolveSelection( ...
    structure, options.Tables, options.IncludeViews);

sourcePath = absolutePath(dbPath);
if ismissing(dbPath) || strlength(strtrim(dbPath)) == 0 || ~isfile(sourcePath)
    error("vawlume:export:SourceNotFound", ...
        "No database file at ""%s"". The exporter opens an existing database " + ...
        "read-only and never creates one.", dbPath);
end

stagingRoot = absolutePath(stagingRoot);
if ~isfolder(stagingRoot)
    error("vawlume:export:StagingMissing", ...
        "The staging root ""%s"" does not exist. The caller creates and owns it.", ...
        stagingRoot);
end
csvDir = fullfile(stagingRoot, "csv");
if isfolder(csvDir) || isfile(csvDir)
    error("vawlume:export:StagingNotEmpty", ...
        "The staging root already contains ""csv"". The core writes only into " + ...
        "a csv directory it creates, so it can remove that directory on failure " + ...
        "without touching anything it did not make.");
end

listing = dir(sourcePath);
source = struct(path=sourcePath, filename=string(listing.name), ...
    bytes=double(listing.bytes), schema_version="", user_version=NaN, data_version="");

try
    conn = sqlite(char(sourcePath), "readonly");
catch exception
    wrapped = MException("vawlume:export:SourceUnreadable", ...
        "Could not open ""%s"" read-only as an SQLite database.", sourcePath);
    throw(addCause(wrapped, exception));
end
closer = onCleanup(@() closeQuietly(conn));

try
    dataVersionBefore = scalarText(conn, ...
        "SELECT CAST(data_version AS TEXT) AS v FROM pragma_data_version()");
    source.user_version = str2double(scalarText(conn, ...
        "SELECT CAST(user_version AS TEXT) AS v FROM pragma_user_version()"));
    hasSchemaInfo = scalarText(conn, "SELECT CAST(COUNT(*) AS TEXT) AS v " + ...
        "FROM sqlite_master WHERE type = 'table' AND name = 'schema_info'") == "1";
catch exception
    wrapped = MException("vawlume:export:SourceUnreadable", ...
        """%s"" could not be read as an SQLite database.", sourcePath);
    throw(addCause(wrapped, exception));
end
source.data_version = dataVersionBefore;

if ~hasSchemaInfo
    error("vawlume:export:NotAVawlumeDatabase", ...
        """%s"" has no schema_info table, so it is not a VAWLUME database.", sourcePath);
end
% 'V' || ... for the same reason as the object projection: SQLite's empty
% string returns to MATLAB as <missing>, so a marker keeps "absent" readable.
versions = fetch(conn, "SELECT IFNULL('V' || CAST(schema_version AS TEXT), 'N') AS v " + ...
    "FROM schema_info ORDER BY applied_at_utc DESC, rowid DESC LIMIT 1");
if height(versions) == 1 && startsWith(string(versions.v(1)), "V")
    source.schema_version = extractAfter(string(versions.v(1)), 1);
end
if source.schema_version == ""
    error("vawlume:export:NotAVawlumeDatabase", ...
        """%s"" records no schema version in schema_info.", sourcePath);
end

warnings = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["code", "object_name", "message"]);

versionMatches = source.schema_version == repositoryVersion;
if ~versionMatches
    message = sprintf("The source database is schema %s but schema.sql is %s. " + ...
        "The descriptions this repository ships are written for %s.", ...
        source.schema_version, repositoryVersion, repositoryVersion);
    if ~options.AllowSchemaVersionMismatch
        error("vawlume:export:SchemaVersionMismatch", "%s Pass " + ...
            "AllowSchemaVersionMismatch=true to export anyway, with a recorded warning.", ...
            message);
    end
    warnings(end + 1, :) = {"schema_version_mismatch", "", string(message)};
end

[selection, structureWarnings] = reconcileWithSource(conn, selection, versionMatches);
warnings = [warnings; structureWarnings];

count = height(selection);
rowCounts = zeros(count, 1);

mkdir(csvDir);
try
    for k = 1:count
        name = selection.object_name(k);
        columns = selection.columns{k};
        try
            data = vawlume.export.internal.readObject(conn, name, columns);
            counted = str2double(scalarText(conn, "SELECT CAST(COUNT(*) AS TEXT) AS v FROM " + ...
                exportQuoteIdentifier(name)));
            if counted ~= height(data)
                error("vawlume:export:RowCountMismatch", ...
                    "%s returned %d rows but COUNT(*) reports %d.", ...
                    name, height(data), counted);
            end
            vawlume.export.internal.writeCsv(data, columns, ...
                fullfile(stagingRoot, selection.filename(k)));
        catch exception
            if startsWith(exception.identifier, "vawlume:export:")
                rethrow(exception);
            end
            wrapped = MException("vawlume:export:ObjectExportFailed", ...
                "Exporting %s failed: %s", name, exception.message);
            throw(addCause(wrapped, exception));
        end

        rowCounts(k) = height(data);
        if rowCounts(k) > largeObjectRows
            warnings(end + 1, :) = {"large_object", name, string(sprintf( ...
                "%s has %d rows, above the advisory %d-row threshold. It was " + ...
                "exported in full; the threshold is extrapolated, not a limit.", ...
                name, rowCounts(k), largeObjectRows))}; %#ok<AGROW>
        end

        if ~isempty(options.AfterObjectFcn)
            options.AfterObjectFcn(name);
        end
    end

    dataVersionAfter = scalarText(conn, ...
        "SELECT CAST(data_version AS TEXT) AS v FROM pragma_data_version()");
    if dataVersionAfter ~= dataVersionBefore
        error("vawlume:export:SourceChangedDuringExport", ...
            "The source database changed while it was being exported " + ...
            "(data_version %s before, %s after), so the objects may not describe " + ...
            "one database state. Nothing was kept; export again when no other " + ...
            "process is writing to it.", dataVersionBefore, dataVersionAfter);
    end
catch exception
    removeCreatedDirectory(csvDir);
    rethrow(exception);
end

objects = removevars(selection, "columns");
objects.row_count = rowCounts;
objects.columns = selection.columns;
objects = objects(:, ["object_name", "object_kind", "schema_position", "filename", ...
    "row_count", "column_count", "columns"]);

record = struct();
record.status = "exported";
record.staging_root = stagingRoot;
record.csv_dir = string(csvDir);
record.source = source;
record.repository_schema_version = repositoryVersion;
record.supported_object_count = height(structure.objects);
record.selected_object_count = count;
record.exported_object_count = count;
record.exported_row_total = sum(rowCounts);
record.objects = objects;
record.files = objects.filename;
record.warnings = warnings;
record.large_object_row_threshold = largeObjectRows;
end

% ---------------------------------------------------------------------------

function [selection, warnings] = reconcileWithSource(conn, selection, versionMatches)
%RECONCILEWITHSOURCE Check each selected object against the source database.
warnings = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["code", "object_name", "message"]);
missingObjects = strings(0, 1);
disagreements = strings(0, 1);

for k = 1:height(selection)
    name = selection.object_name(k);
    literal = exportQuoteLiteral(name);
    kinds = fetch(conn, "SELECT CAST(type AS TEXT) AS kind FROM sqlite_master " + ...
        "WHERE name = " + literal + " AND type IN ('table', 'view')");
    if height(kinds) == 0
        missingObjects(end + 1, 1) = name; %#ok<AGROW>
        continue
    end
    sourceKind = string(kinds.kind(1));
    sourceColumns = fetch(conn, "SELECT CAST(name AS TEXT) AS name " + ...
        "FROM pragma_table_info(" + literal + ") ORDER BY cid");
    if height(sourceColumns) == 0
        sourceColumns = strings(1, 0);
    else
        sourceColumns = string(sourceColumns.name)';
    end

    committed = selection.columns{k};
    if sourceKind == selection.object_kind(k) && isequal(sourceColumns, committed)
        continue
    end

    detail = sprintf("%s is a %s with columns [%s] in the source, but the committed " + ...
        "schema declares a %s with [%s].", name, sourceKind, strjoin(sourceColumns, ", "), ...
        selection.object_kind(k), strjoin(committed, ", "));
    if versionMatches
        disagreements(end + 1, 1) = string(detail); %#ok<AGROW>
    else
        % Under an accepted version mismatch, export what the database actually
        % holds rather than forcing it into the current schema's shape.
        selection.columns{k} = sourceColumns;
        selection.column_count(k) = numel(sourceColumns);
        selection.object_kind(k) = sourceKind;
        warnings(end + 1, :) = {"source_structure_differs", name, string(detail)}; %#ok<AGROW>
    end
end

if ~isempty(missingObjects)
    error("vawlume:export:SourceObjectMissing", ...
        "The source database has no object named: %s. Narrow Tables to objects it holds.", ...
        strjoin(missingObjects, ", "));
end
if ~isempty(disagreements)
    error("vawlume:export:SourceStructureMismatch", ...
        "The source database claims the repository's schema version but differs " + ...
        "from its committed structure:\n  %s", strjoin(disagreements, newline + "  "));
end
end

function value = scalarText(conn, sql)
rows = fetch(conn, sql);
value = string(rows.(rows.Properties.VariableNames{1})(1));
end

function path = absolutePath(path)
if ismissing(path) || strlength(path) == 0
    return
end
path = string(java.io.File(char(path)).getAbsolutePath());
end

function removeCreatedDirectory(csvDir)
if isfolder(csvDir)
    rmdir(csvDir, "s");
end
end

function closeQuietly(conn)
try
    close(conn);
catch
end
end
