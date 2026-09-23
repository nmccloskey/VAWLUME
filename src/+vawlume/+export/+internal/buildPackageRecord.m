function record = buildPackageRecord(mode, structure, metadata, exportRecord, facts)
%BUILDPACKAGERECORD Combine everything one export package states into one record.
%
%   RECORD = vawlume.export.internal.buildPackageRecord(MODE, STRUCTURE, METADATA, ...
%       EXPORTRECORD, FACTS)
%
%   MODE          "normal" or "schema_only"
%   STRUCTURE     vawlume.schema.loadStructure(): identities and order
%   METADATA      vawlume.schema.loadMetadata(): descriptions (stable semantics)
%   EXPORTRECORD  vawlume.export.internal.writeObjects()'s record in normal mode;
%                 [] in schema-only mode
%   FACTS         struct of this call's facts: format, exported_at_utc,
%                 source_identifier, vawlume_version, repository_schema_version
%
%   Every file in the package -- the three metadata CSVs, the manifest, and the
%   README -- is rendered from this record and nothing else (contract §G.1). No
%   renderer reopens the database or reads the semantic document again, so the
%   README cannot disagree with the manifest or with the data files.
%
%   PURE. It reads no file and opens no database.
%
%   Stable schema semantics and export-instance facts stay separate (boundary
%   4). Descriptions come only from METADATA. Row counts, filenames, the source,
%   the timestamp, and warnings come only from EXPORTRECORD and FACTS.
%
%   The metadata projections are not selection-scoped (contract §B.7): all
%   supported objects, columns, and relationships appear in every mode, so
%   normal-mode and schema-only metadata are identical.
%
%   Returned fields:
%     mode, format, package_format, package_format_version, exported_at_utc
%     supported_object_count, selected_object_count, exported_object_count,
%       exported_row_total, data_file_count
%     source                     struct (normal) or [] (schema-only)
%     source_identifier          what the manifest records for the source
%     repository_schema_version, metadata_version, metadata_schema_version,
%       vawlume_version
%     objects                    one row per supported object, numeric, for the
%                                public result
%     tables_csv, columns_csv, relationships_csv, manifest_csv
%                                all-string tables in their exact §G.2 schemas,
%                                <missing> for a blank field
%     warnings                   table: code, object_name, message
%     data_files                 package-relative data file paths
%     files                      every package-relative path the package holds

arguments
    mode (1,1) string {mustBeMember(mode, ["normal", "schema_only"])}
    structure (1,1) struct
    metadata (1,1) struct
    exportRecord
    facts (1,1) struct
end

normal = mode == "normal";
if normal == isempty(exportRecord)
    error("vawlume:export:PackageRecordInvalid", ...
        "A %s package %s an export record.", mode, ...
        ternary(normal, "requires", "must not have"));
end

objects = sortrows(structure.objects, "position");
supported = height(objects);

% --- objects and tables.csv ------------------------------------------------
exported = false(supported, 1);
rowCount = NaN(supported, 1);
filename = strings(supported, 1);
filename(:) = missing;
columnCount = zeros(supported, 1);
for k = 1:supported
    columnCount(k) = sum(structure.columns.object_name == objects.object_name(k));
end
warnings = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["code", "object_name", "message"]);

if normal
    [present, where] = ismember(objects.object_name, exportRecord.objects.object_name);
    exported(present) = true;
    rowCount(present) = exportRecord.objects.row_count(where(present));
    filename(present) = exportRecord.objects.filename(where(present));
    columnCount(present) = exportRecord.objects.column_count(where(present));
    warnings = exportRecord.warnings;
end

objectDescriptions = lookup(objects.object_name, metadata.objects.object_name, ...
    metadata.objects.description, "object");

tablesCsv = table(objects.object_name, objects.object_kind, objectDescriptions, ...
    ternaryText(exported, "true", "false"), countText(rowCount), filename, ...
    VariableNames=["object_name", "object_kind", "description", "exported", ...
        "row_count", "filename"]);

publicObjects = table(objects.object_name, objects.object_kind, exported, rowCount, ...
    columnCount, filename, VariableNames=["object_name", "object_kind", "exported", ...
        "row_count", "column_count", "filename"]);

% --- columns.csv -------------------------------------------------------------
columnRows = cell(supported, 1);
for k = 1:supported
    columns = structure.columns(structure.columns.object_name == objects.object_name(k), :);
    columnRows{k} = sortrows(columns, "position");
end
columns = vertcat(columnRows{:});
columnKey = columns.object_name + "." + columns.column_name;
semanticKey = metadata.columns.object_name + "." + metadata.columns.column_name;
[found, at] = ismember(columnKey, semanticKey);
if ~all(found)
    error("vawlume:export:MetadataIncomplete", ...
        "No semantic entry for column(s): %s.", strjoin(columnKey(~found), ", "));
end
descriptionSource = metadata.columns.description_source(at);
description = metadata.columns.description(at);
pointers = find(~ismissing(metadata.columns.same_as(at)));
for index = pointers(:)'
    % A pointer is resolved here, once, so the package shows the borrowed
    % meaning and says where it was borrowed from (description_source).
    target = metadata.columns.same_as(at(index));
    targetRow = semanticKey == target;
    description(index) = metadata.columns.description(targetRow);
end
columnsCsv = table(columns.object_name, columns.column_name, string(columns.position), ...
    description, descriptionSource, VariableNames=["object_name", "column_name", ...
        "column_position", "description", "description_source"]);

% --- relationships.csv -----------------------------------------------------------
relations = structure.relations;
relationDescriptions = lookup(relations.relationship_key, ...
    metadata.relationships.relationship_key, metadata.relationships.description, ...
    "relationship");
relationshipsCsv = table(relations.source_table, relations.source_columns, ...
    relations.target_table, relations.target_columns, relationDescriptions, ...
    VariableNames=["source_table", "source_column", "target_table", ...
        "target_column", "description"]);

% --- counts and files ---------------------------------------------------------------
if normal
    selectedCount = exportRecord.selected_object_count;
    exportedCount = exportRecord.exported_object_count;
    rowTotal = exportRecord.exported_row_total;
    dataFiles = exportRecord.files(:);
    source = exportRecord.source;
else
    selectedCount = 0;
    exportedCount = 0;
    rowTotal = 0;
    dataFiles = strings(0, 1);
    source = [];
end
metaFiles = ["meta/tables.csv"; "meta/columns.csv"; "meta/relationships.csv"; ...
    "meta/manifest.csv"];

record = struct();
record.mode = mode;
record.format = facts.format;
record.package_format = "vawlume_csv_export";
record.package_format_version = "1";
record.exported_at_utc = facts.exported_at_utc;
record.supported_object_count = supported;
record.selected_object_count = selectedCount;
record.exported_object_count = exportedCount;
record.exported_row_total = rowTotal;
record.data_file_count = numel(dataFiles);
record.source = source;
record.source_identifier = sourceIdentifier(normal, source, facts);
record.repository_schema_version = facts.repository_schema_version;
record.metadata_version = metadata.metadata_version;
record.metadata_schema_version = metadata.schema_version;
record.vawlume_version = facts.vawlume_version;
record.objects = publicObjects;
record.tables_csv = tablesCsv;
record.columns_csv = columnsCsv;
record.relationships_csv = relationshipsCsv;
record.warnings = warnings;
record.data_files = dataFiles;
record.files = ["README.md"; metaFiles; dataFiles];
record.manifest_csv = manifest(record);
end

% ---------------------------------------------------------------------------

function rows = manifest(record)
%MANIFEST The key/value/detail rows of meta/manifest.csv (contract §G.2).
normal = record.mode == "normal";
rows = strings(0, 3);
    function add(key, value, detail)
        rows(end + 1, :) = [key, value, detail];
    end
none = string(missing);

add("package_format", record.package_format, none);
add("package_format_version", record.package_format_version, none);
add("export_format", record.format, none);
add("export_mode", record.mode, none);
add("exported_at_utc", record.exported_at_utc, none);
if normal
    add("source_database_filename", record.source_identifier.value, record.source_identifier.detail);
    add("source_database_bytes", string(record.source.bytes), none);
    add("source_schema_version", record.source.schema_version, none);
    add("source_user_version", string(record.source.user_version), none);
else
    for key = ["source_database_filename", "source_database_bytes", ...
            "source_schema_version", "source_user_version"]
        add(key, none, "not_applicable");
    end
end
add("repository_schema_version", record.repository_schema_version, none);
add("metadata_version", record.metadata_version, none);
add("metadata_schema_version", record.metadata_schema_version, none);
if record.vawlume_version == ""
    add("vawlume_version", none, "not_available");
else
    add("vawlume_version", record.vawlume_version, "caller_supplied");
end
add("supported_object_count", string(record.supported_object_count), none);
add("selected_object_count", string(record.selected_object_count), ...
    ternary(normal, none, "schema_only"));
add("exported_object_count", string(record.exported_object_count), none);
add("exported_row_total", string(record.exported_row_total), none);
add("data_file_count", string(record.data_file_count), none);
add("null_representation", "empty_unquoted_field", none);
add("text_quoting", "rfc4180_all_values_quoted", none);
add("real_representation", "printf_%!.17g", none);
add("blob_representation", "uppercase_hex", none);
add("character_encoding", "UTF-8", none);
add("line_terminator", "CRLF", none);
add("warning_count", string(height(record.warnings)), none);
for k = 1:height(record.warnings)
    add("warning", record.warnings.code(k), record.warnings.message(k));
end
rows = table(rows(:, 1), rows(:, 2), rows(:, 3), VariableNames=["key", "value", "detail"]);
end

function identifier = sourceIdentifier(normal, source, facts)
identifier = struct(value=string(missing), detail="not_applicable");
if ~normal
    return
end
if facts.source_identifier ~= ""
    % The caller chose what to disclose: a study code, a dataset DOI.
    identifier = struct(value=facts.source_identifier, detail="caller_supplied");
else
    % Filename only, never the path: a path discloses the exporter's username
    % and directory layout in a package made to be shared (contract §G.3).
    identifier = struct(value=source.filename, detail=string(missing));
end
end

function values = lookup(keys, knownKeys, knownValues, what)
[found, at] = ismember(keys, knownKeys);
if ~all(found)
    error("vawlume:export:MetadataIncomplete", ...
        "No semantic description for %s(s): %s.", what, strjoin(keys(~found), ", "));
end
values = knownValues(at);
end

function text = countText(values)
text = string(values);
text(isnan(values)) = missing;
end

function text = ternaryText(condition, whenTrue, whenFalse)
text = repmat(string(whenFalse), size(condition));
text(condition) = whenTrue;
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end
