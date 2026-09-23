function structural = schemaLoadStructural(structuralPath)
%SCHEMALOADSTRUCTURAL Read the committed structural representation.
%
% Reads schema/schema.json -- the generated tbls export -- and returns the
% object, column, and relationship identities it declares, as tables.
%
% This reads the COMMITTED artifact. It never runs tbls, never opens a
% database, and never calls schema_documentation. Structural freshness is that
% tool's job; this is a consumer of its output.
%
% Only identity is taken: names, kinds, positions, and relationship endpoints.
% Types, nullability, keys, constraints, indexes and DDL are deliberately left
% behind, because the semantic document must never acquire a second opinion
% about them.
%
% `referenced_tables` is NOT read. Measured during Part 1: tbls records
% common-table-expression names in that field as though they were relational
% objects -- `possible_pairs`, `edge_support`, `extremes` and others appear
% there and none is a table. Nothing may key on it.

arguments
    structuralPath (1,1) string
end

if ~isfile(structuralPath)
    error("vawlume:schema:StructuralArtifactMissing", ...
        "The committed structural representation is missing: %s\n" + ...
        "Run `addpath(""tools""); schema_documentation` to generate it.", ...
        structuralPath);
end

try
    document = jsondecode(fileread(structuralPath));
catch exception
    error("vawlume:schema:StructuralArtifactMissing", ...
        "The committed structural representation at %s is not valid JSON: %s", ...
        structuralPath, exception.message);
end

for field = ["tables", "relations"]
    if ~isfield(document, field)
        error("vawlume:schema:StructuralArtifactMissing", ...
            "The structural representation at %s has no top-level `%s`.", ...
            structuralPath, field);
    end
end

entries = schemaToEntryCell(document.tables);

objectName = strings(numel(entries), 1);
objectKind = strings(numel(entries), 1);
objectPosition = (1:numel(entries))';

columnObject = strings(0, 1);
columnName = strings(0, 1);
columnPosition = zeros(0, 1);

for k = 1:numel(entries)
    entry = entries{k};
    objectName(k) = string(entry.name);
    objectKind(k) = string(entry.type);

    columnEntries = schemaToEntryCell(entry.columns);
    for j = 1:numel(columnEntries)
        columnObject(end + 1, 1) = objectName(k); %#ok<AGROW>
        columnName(end + 1, 1) = string(columnEntries{j}.name); %#ok<AGROW>
        columnPosition(end + 1, 1) = j; %#ok<AGROW>
    end
end

relationEntries = schemaToEntryCell(document.relations);
sourceTable = strings(numel(relationEntries), 1);
sourceColumns = strings(numel(relationEntries), 1);
targetTable = strings(numel(relationEntries), 1);
targetColumns = strings(numel(relationEntries), 1);

for k = 1:numel(relationEntries)
    relation = relationEntries{k};
    sourceTable(k) = string(relation.table);
    sourceColumns(k) = schemaJoinColumns(schemaToStringColumn(relation.columns));
    targetTable(k) = string(relation.parent_table);
    targetColumns(k) = schemaJoinColumns(schemaToStringColumn(relation.parent_columns));
end

structural = struct();
structural.source_path = structuralPath;
structural.objects = table(objectName, objectKind, objectPosition, ...
    VariableNames=["object_name", "object_kind", "position"]);
structural.columns = table(columnObject, columnName, columnPosition, ...
    VariableNames=["object_name", "column_name", "position"]);
structural.relations = table(sourceTable, sourceColumns, targetTable, targetColumns, ...
    schemaRelationshipKey(sourceTable, sourceColumns, targetTable, targetColumns), ...
    VariableNames=["source_table", "source_columns", "target_table", ...
        "target_columns", "relationship_key"]);
end
