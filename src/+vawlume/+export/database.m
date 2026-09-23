function result = database(dbPath, options)
%DATABASE Export a VAWLUME database as a self-describing CSV package.
%
%   RESULT = vawlume.export.database(DBPATH, Output=DIR)
%   RESULT = vawlume.export.database(DBPATH, Output=DIR, Tables=["detections", ...])
%   RESULT = vawlume.export.database(Output=DIR, SchemaOnly=true)
%
%   Writes a package to DIR:
%
%     DIR/
%       README.md              what this package is and how to read it
%       meta/manifest.csv      facts about this export (written last)
%       meta/tables.csv        every table and view of the schema
%       meta/columns.csv       every column, with its description
%       meta/relationships.csv every foreign key, child to parent
%       csv/<object>.csv       one file per exported table or view
%
%   The database is opened read-only and is never changed. The package is built
%   beside DIR and published by a single rename, so DIR either receives a
%   complete package or is left as it was.
%
%   Always call this fully qualified. Never write `import vawlume.export.*`: it
%   would shadow MATLAB's own `export` and `database` functions.
%
%   Name-value arguments:
%     Output                      destination directory. REQUIRED; there is no
%                                 default. Its parent must exist.
%     Format                      "csv" (default), the only implemented format.
%                                 Any other value fails before anything is read
%                                 or written.
%     Tables                      "all" (default) or exact, case-sensitive table
%                                 and view names
%     IncludeViews                whether "all" also exports the 14 views
%                                 (default false). A view named in Tables is
%                                 always exported.
%     SchemaOnly                  true to write only README.md and meta/, with no
%                                 database: omit DBPATH, Tables, IncludeViews,
%                                 SourceIdentifier, and
%                                 AllowSchemaVersionMismatch (default false)
%     Overwrite                   replace DIR if it is a previous VAWLUME export
%                                 package (default false). A non-empty directory
%                                 that is not one is never replaced.
%     AllowSchemaVersionMismatch  export a database of another schema version,
%                                 recording a warning (default false)
%     SourceIdentifier            what the manifest records for the source
%                                 (default: the database's filename, never its path)
%     VawlumeVersion              VAWLUME version to record (default: not
%                                 recorded; it is never guessed)
%
%   RESULT fields: output_dir, mode ("normal" | "schema_only"), format,
%   exported_at_utc, source (filename, bytes, schema_version, user_version; []
%   in schema-only mode), supported_object_count, selected_object_count,
%   exported_object_count, exported_row_total, objects (one row per supported
%   object: object_name, object_kind, exported, row_count, column_count,
%   filename), files (package-relative paths), warnings ("code: message"),
%   metadata_version, package_format_version.
%
%   With no output argument, prints a short summary instead of returning.
%
%   Needs only MATLAB and the committed schema files; no tbls, Node, or
%   network. Errors are raised as vawlume:export:* identifiers; see
%   vawlume.export.internal.writeObjects and checkDestination for the list.
%
%   See also VAWLUME.SCHEMA.LOADMETADATA, VAWLUME.SCHEMA.VALIDATEMETADATA.

arguments
    dbPath = []
    options.Output = []
    options.Format = "csv"
    options.Tables = missing
    options.IncludeViews = []
    options.SchemaOnly (1,1) logical = false
    options.Overwrite (1,1) logical = false
    options.AllowSchemaVersionMismatch = []
    options.SourceIdentifier = []
    options.VawlumeVersion = []
end

% Format first: an unsupported format must fail before anything else is
% considered, let alone read or written.
format = textOption(options.Format, "Format");
if format ~= "csv"
    error("vawlume:export:UnsupportedFormat", ...
        "Format ""%s"" is not implemented. The only supported format is ""csv"".", format);
end

tablesGiven = ~isa(options.Tables, "missing");
includeViewsGiven = ~isempty(options.IncludeViews);
allowGiven = ~isempty(options.AllowSchemaVersionMismatch);
identifierGiven = ~isempty(options.SourceIdentifier);
sourceGiven = ~isempty(dbPath);

if options.SchemaOnly
    if sourceGiven || identifierGiven || allowGiven
        error("vawlume:export:SchemaOnlyWithSource", ...
            "SchemaOnly=true reads no database, so a database path, " + ...
            "SourceIdentifier, and AllowSchemaVersionMismatch do not apply. " + ...
            "Call vawlume.export.database(Output=DIR, SchemaOnly=true).");
    end
    if tablesGiven || includeViewsGiven
        error("vawlume:export:SchemaOnlyWithSelection", ...
            "SchemaOnly=true always describes the whole schema; Tables and " + ...
            "IncludeViews do not apply.");
    end
elseif ~sourceGiven
    error("vawlume:export:SourceRequired", ...
        "A database path is required. For a schema reference without a database, " + ...
        "pass SchemaOnly=true.");
end

request = struct();
request.db_path = "";
if sourceGiven
    request.db_path = textOption(dbPath, "the database path");
end
request.output = options.Output;
request.format = format;
request.schema_only = options.SchemaOnly;
request.tables = "all";
if tablesGiven
    request.tables = options.Tables;
end
request.include_views = logicalOption(options.IncludeViews, false, "IncludeViews");
request.overwrite = options.Overwrite;
request.allow_schema_version_mismatch = logicalOption( ...
    options.AllowSchemaVersionMismatch, false, "AllowSchemaVersionMismatch");
request.source_identifier = "";
if identifierGiven
    request.source_identifier = textOption(options.SourceIdentifier, "SourceIdentifier");
end
request.vawlume_version = "";
if ~isempty(options.VawlumeVersion)
    request.vawlume_version = textOption(options.VawlumeVersion, "VawlumeVersion");
end
request.repo_root = "";
request.exported_at_utc = "";
request.before_publish_fcn = [];
request.after_object_fcn = [];

outcome = vawlume.export.internal.runExport(request);

if nargout == 0
    printSummary(outcome);
else
    result = outcome;
end
end

% ---------------------------------------------------------------------------

function value = textOption(value, name)
if ~(isstring(value) || ischar(value)) || ~isscalar(string(value)) || ...
        ismissing(string(value)) || strlength(strtrim(string(value))) == 0
    error("vawlume:export:InvalidOption", "%s must be non-empty text.", name);
end
value = string(value);
end

function value = logicalOption(value, default, name)
if isempty(value)
    value = default;
    return
end
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) || ...
        ~(value == 0 || value == 1)
    error("vawlume:export:InvalidOption", "%s must be true or false.", name);
end
value = logical(value);
end

function printSummary(result)
if result.mode == "schema_only"
    fprintf("VAWLUME schema reference written (no database read)\n");
else
    fprintf("VAWLUME CSV export written\n");
    fprintf("  source:    %s (schema %s)\n", result.source.filename, ...
        result.source.schema_version);
    fprintf("  exported:  %d of %d objects, %d rows\n", result.exported_object_count, ...
        result.supported_object_count, result.exported_row_total);
end
fprintf("  package:   %s\n", result.output_dir);
fprintf("  metadata:  %d objects described (metadata %s)\n", ...
    result.supported_object_count, result.metadata_version);
if isempty(result.warnings)
    fprintf("  warnings:  none\n");
else
    fprintf("  warnings:  %d\n", numel(result.warnings));
    fprintf("    %s\n", result.warnings);
end
end
