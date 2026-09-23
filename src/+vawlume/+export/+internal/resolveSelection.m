function selection = resolveSelection(structure, tables, includeViews)
%RESOLVESELECTION Resolve an export selection against the supported schema.
%
%   SELECTION = vawlume.export.internal.resolveSelection(STRUCTURE, TABLES, INCLUDEVIEWS)
%
%   STRUCTURE     the committed structure, as vawlume.schema.loadStructure
%                 returns it. Every object in it is supported (contract §B.2);
%                 there is no exclusion class.
%   TABLES        "all", or the exact SQLite names of tables and/or views.
%   INCLUDEVIEWS  whether "all" also selects the views. It never removes a view
%                 that TABLES names explicitly (contract §B.6).
%
%   Returns one row per selected object in SCHEMA ORDER, which is creation
%   order, whatever order the request used (contract §D.4):
%
%     object_name, object_kind, schema_position, filename, column_count,
%     columns (cell, each a string row vector in declared order)
%
%   filename is package-relative, "csv/<object_name>.csv" (contract §F.5).
%
%   PURE. It opens no database and reads no file. Every refusal happens here,
%   before any SQL exists, so no caller-supplied string ever reaches a query:
%
%     vawlume:export:InvalidSelection  TABLES is not text
%     vawlume:export:EmptySelection    an explicit selection names nothing
%     vawlume:export:UnsafeObjectName  a name fails the identifier and filename
%                                      guard, for example an injection-shaped
%                                      string or a reserved device name
%     vawlume:export:DuplicateObject   a name is requested twice
%     vawlume:export:UnknownObject     names every unknown request, flags a
%                                      case-only mismatch, and names the
%                                      available set
%
%   Matching is exact and case-sensitive. "Projects" is not "projects": the
%   error says so rather than folding case silently.

arguments
    structure (1,1) struct
    tables
    includeViews (1,1) logical
end

objects = sortrows(structure.objects, "position");
requested = normalizeRequest(tables);

if isscalar(requested) && requested == "all"
    chosen = objects.object_kind == "table" | ...
        (includeViews & objects.object_kind == "view");
    picked = objects(chosen, :);
else
    picked = explicitSelection(objects, requested);
end

selection = describe(picked, structure.columns);
end

% ---------------------------------------------------------------------------

function requested = normalizeRequest(tables)
if isempty(tables) && ~ischar(tables)
    % Tables=[] and Tables=string.empty are both a mistake, not a request to
    % export nothing (contract §D.3). An empty char '' is a name, refused below
    % as unsafe.
    requested = strings(1, 0);
elseif ischar(tables) || iscellstr(tables) || isstring(tables)
    requested = string(tables);
    requested = requested(:)';
else
    error("vawlume:export:InvalidSelection", ...
        "Tables must be ""all"" or a string array of object names; got a %s.", ...
        class(tables));
end
if isempty(requested)
    error("vawlume:export:EmptySelection", ...
        "Tables names no object. An empty selection is a mistake, not a " + ...
        "request to export nothing; pass ""all"" or at least one name.");
end
end

function picked = explicitSelection(objects, requested)
unsafe = exportUnsafeObjectNames(requested);
if ~isempty(unsafe)
    shown = unsafe;
    shown(ismissing(shown)) = "<missing>";
    error("vawlume:export:UnsafeObjectName", ...
        "Refusing unsafe object name(s): %s. A selectable name must match " + ...
        "^[A-Za-z][A-Za-z0-9_]*$ and must not be a reserved device name.", ...
        strjoin("""" + shown + """", ", "));
end

[unique_, ~, index] = unique(requested, "stable");
counts = accumarray(index(:), 1);
duplicated = unique_(counts > 1);
if ~isempty(duplicated)
    error("vawlume:export:DuplicateObject", ...
        "Object(s) requested more than once: %s. Each object is exported once; " + ...
        "remove the repetition.", strjoin(duplicated, ", "));
end

known = objects.object_name;
unknown = requested(~ismember(requested, known));
if ~isempty(unknown)
    hints = strings(size(unknown));
    for k = 1:numel(unknown)
        match = known(lower(known) == lower(unknown(k)));
        if isempty(match)
            hints(k) = """" + unknown(k) + """";
        else
            hints(k) = """" + unknown(k) + """ (names are case-sensitive; did you mean """ + ...
                match(1) + """?)";
        end
    end
    error("vawlume:export:UnknownObject", ...
        "Unknown object(s): %s.\nAvailable objects: %s.", ...
        strjoin(hints, ", "), strjoin(known', ", "));
end

picked = objects(ismember(known, requested), :);
end

function selection = describe(picked, columns)
count = height(picked);
columnLists = cell(count, 1);
columnCounts = zeros(count, 1);
for k = 1:count
    rows = columns(columns.object_name == picked.object_name(k), :);
    rows = sortrows(rows, "position");
    columnLists{k} = rows.column_name(:)';
    columnCounts(k) = height(rows);
end
selection = table(picked.object_name, picked.object_kind, picked.position, ...
    "csv/" + picked.object_name + ".csv", columnCounts, columnLists, ...
    VariableNames=["object_name", "object_kind", "schema_position", ...
        "filename", "column_count", "columns"]);
end
