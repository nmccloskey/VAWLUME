function metadata = loadMetadata(options)
%LOADMETADATA Read VAWLUME's authored schema semantics.
%
%   METADATA = VAWLUME.SCHEMA.LOADMETADATA() reads
%   schema/schema_metadata.json, validates it against the grammar, and returns
%   one documented struct. It is the ONLY interpreter of that document: no
%   exporter, projection, or documentation path may parse it again.
%
%   Name-value arguments:
%     Path      - the semantic document (default:
%                 <RepoRoot>/schema/schema_metadata.json)
%     RepoRoot  - repository root (default: derived from this file's location,
%                 never from `pwd`)
%
%   Returned fields:
%     metadata_version   the document's own grammar/content version
%     schema_version     the schema.sql version these semantics describe
%     complete_domains   table: domain, object_count -- the domains the
%                        document CLAIMS are fully described
%     objects            table: object_name, object_kind, domain, description
%     columns            table: object_name, column_name, description,
%                        same_as, description_source
%     relationships      table: source_table, source_columns, target_table,
%                        target_columns, description, relationship_key
%     source_path        where it was read from
%
%   All three tables are returned in DOCUMENT ORDER, which `jsondecode`
%   preserves (measured across all 618 schema identifiers). Order is not
%   semantic and consumers should not rely on it beyond determinism.
%
%   WHAT THIS FUNCTION DOES NOT DO. It knows nothing about the actual schema.
%   Every check here is about the document's own well-formedness: grammar,
%   field sets, duplicates, identifier shape, and whether prose is real prose.
%   Whether `detections` exists, whether it has a `detection_score` column, and
%   whether anything is MISSING are all questions for
%   VAWLUME.SCHEMA.VALIDATEMETADATA, which is the layer that has the structural
%   representation to answer them.
%
%   The split matters: everything this function accepts is well-formed, so
%   validation only ever has to reason about identity and absence, never about
%   shape.
%
%   See also VAWLUME.SCHEMA.VALIDATEMETADATA, VAWLUME.SCHEMA.REPOSITORYVERSION.

arguments
    options.Path (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

metadataPath = options.Path;
if metadataPath == ""
    repoRoot = options.RepoRoot;
    if repoRoot == ""
        repoRoot = schemaRepositoryRoot();
    end
    metadataPath = fullfile(repoRoot, "schema", "schema_metadata.json");
end

if ~isfile(metadataPath)
    error("vawlume:schema:MetadataNotFound", ...
        "Authored schema metadata not found: %s", metadataPath);
end

try
    text = fileread(metadataPath);
catch exception
    error("vawlume:schema:MetadataNotFound", ...
        "Could not read %s: %s", metadataPath, exception.message);
end

try
    document = jsondecode(text);
catch exception
    error("vawlume:schema:MetadataInvalidJson", ...
        "%s is not valid JSON: %s", metadataPath, exception.message);
end

schemaCheckFields(document, "<document>", ...
    ["metadata_version"; "schema_version"; "coverage"; "objects"; "relationships"]);

metadata = struct();
metadata.source_path = metadataPath;
metadata.metadata_version = readRequiredText(document, "metadata_version", "metadata_version");
metadata.schema_version = readRequiredText(document, "schema_version", "schema_version");
metadata.complete_domains = readCoverage(document.coverage);
[metadata.objects, metadata.columns] = readObjects(document.objects);
metadata.relationships = readRelationships(document.relationships);
end

% ---------------------------------------------------------------------------
% Coverage
% ---------------------------------------------------------------------------

function completeDomains = readCoverage(coverage)
schemaCheckFields(coverage, "coverage", "complete_domains");

entries = schemaToEntryCell(coverage.complete_domains);
domain = strings(numel(entries), 1);
objectCount = zeros(numel(entries), 1);

for k = 1:numel(entries)
    path = sprintf("coverage.complete_domains[%d]", k);
    schemaCheckFields(entries{k}, path, ["domain"; "object_count"]);

    domain(k) = readRequiredText(entries{k}, "domain", path + ".domain");
    if ~ismember(domain(k), schemaDomainVocabulary())
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s.domain is ""%s"", which is not a known domain. Known: %s.", ...
            path, domain(k), strjoin(schemaDomainVocabulary(), ", "));
    end

    count = entries{k}.object_count;
    if ~isnumeric(count) || ~isscalar(count) || count < 0 || mod(count, 1) ~= 0
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s.object_count must be a non-negative whole number.", path);
    end
    objectCount(k) = double(count);
end

duplicated = domain(schemaFirstDuplicate(domain));
if ~isempty(duplicated)
    error("vawlume:schema:MetadataDuplicateEntry", ...
        "coverage.complete_domains declares ""%s"" more than once.", duplicated(1));
end

completeDomains = table(domain, objectCount, VariableNames=["domain", "object_count"]);
end

% ---------------------------------------------------------------------------
% Objects and columns
% ---------------------------------------------------------------------------

function [objects, columns] = readObjects(objectMap)
if ~isstruct(objectMap) || ~isscalar(objectMap)
    error("vawlume:schema:MetadataInvalidValue", ...
        "objects must be a JSON object keyed by relational object name.");
end

names = string(fieldnames(objectMap));

duplicated = schemaDuplicateFromRename(names, names);
if duplicated ~= ""
    error("vawlume:schema:MetadataDuplicateEntry", ...
        "objects declares ""%s"" more than once.", duplicated);
end

objectName = strings(numel(names), 1);
objectKind = strings(numel(names), 1);
objectDomain = strings(numel(names), 1);
objectDescription = strings(numel(names), 1);

columnObject = strings(0, 1);
columnName = strings(0, 1);
columnDescription = strings(0, 1);
columnSameAs = strings(0, 1);
columnSource = strings(0, 1);

for k = 1:numel(names)
    name = names(k);
    path = "objects." + name;
    entry = objectMap.(name);

    if ~schemaIsPlainIdentifier(name)
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s is not a plain identifier. Object names must match " + ...
            "[A-Za-z][A-Za-z0-9_]* so that JSON keys survive decoding unmangled.", path);
    end

    schemaCheckFields(entry, path, ["kind"; "domain"; "description"; "columns"]);

    objectName(k) = name;
    objectKind(k) = readRequiredText(entry, "kind", path + ".kind");
    if ~ismember(objectKind(k), ["table", "view"])
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s.kind is ""%s""; it must be ""table"" or ""view"".", path, objectKind(k));
    end

    objectDomain(k) = readRequiredText(entry, "domain", path + ".domain");
    if ~ismember(objectDomain(k), schemaDomainVocabulary())
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s.domain is ""%s"", which is not a known domain. Known: %s.", ...
            path, objectDomain(k), strjoin(schemaDomainVocabulary(), ", "));
    end

    objectDescription(k) = readDescription(entry, path + ".description", name);

    [names_, descriptions_, sameAs_, sources_] = readColumns( ...
        entry.columns, path + ".columns", name, objectKind(k));

    columnObject = [columnObject; repmat(name, numel(names_), 1)]; %#ok<AGROW>
    columnName = [columnName; names_]; %#ok<AGROW>
    columnDescription = [columnDescription; descriptions_]; %#ok<AGROW>
    columnSameAs = [columnSameAs; sameAs_]; %#ok<AGROW>
    columnSource = [columnSource; sources_]; %#ok<AGROW>
end

objects = table(objectName, objectKind, objectDomain, objectDescription, ...
    VariableNames=["object_name", "object_kind", "domain", "description"]);
columns = table(columnObject, columnName, columnDescription, columnSameAs, columnSource, ...
    VariableNames=["object_name", "column_name", "description", "same_as", "description_source"]);
end

function [names, descriptions, sameAs, sources] = readColumns(columnMap, path, objectName, objectKind)
if ~isstruct(columnMap) || ~isscalar(columnMap)
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s must be a JSON object keyed by column name.", path);
end

names = string(fieldnames(columnMap));

duplicated = schemaDuplicateFromRename(names, names);
if duplicated ~= ""
    error("vawlume:schema:MetadataDuplicateEntry", ...
        "%s declares ""%s"" more than once.", path, duplicated);
end

descriptions = strings(numel(names), 1);
sameAs = strings(numel(names), 1);
sources = strings(numel(names), 1);

for k = 1:numel(names)
    name = names(k);
    columnPath = path + "." + name;
    entry = columnMap.(name);

    if ~schemaIsPlainIdentifier(name)
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s is not a plain identifier.", columnPath);
    end

    % Exactly one of the two, never both and never neither. A column that
    % carried a description AND a pointer would have two answers to one
    % question, which is the drift the pointer exists to prevent.
    %
    % An empty JSON object decodes to a struct with no fields, which is a
    % column entry that says nothing rather than a malformed one; it is
    % reported as the missing field it actually is.
    if isstruct(entry) && isempty(fieldnames(entry))
        error("vawlume:schema:MetadataMissingField", ...
            "%s must have either `description` or `same_as`.", columnPath);
    end

    schemaCheckFields(entry, columnPath, strings(0, 1), ["description"; "same_as"]);
    hasDescription = isfield(entry, "description");
    hasSameAs = isfield(entry, "same_as");

    if hasDescription && hasSameAs
        error("vawlume:schema:MetadataInvalidValue", ...
            "%s has both `description` and `same_as`; it must have exactly one.", columnPath);
    end
    if ~hasDescription && ~hasSameAs
        error("vawlume:schema:MetadataMissingField", ...
            "%s must have either `description` or `same_as`.", columnPath);
    end

    if hasDescription
        descriptions(k) = readDescription(entry, columnPath + ".description", name);
        sameAs(k) = string(missing);
        sources(k) = "authored";
    else
        if objectKind ~= "view"
            error("vawlume:schema:MetadataSameAsNotPermitted", ...
                "%s uses `same_as`, but %s is a %s. A base-table column must " + ...
                "carry its own description; only a view column may point at one.", ...
                columnPath, objectName, objectKind);
        end
        sameAs(k) = readRequiredText(entry, "same_as", columnPath + ".same_as");
        if isempty(regexp(sameAs(k), "^[A-Za-z][A-Za-z0-9_]*\.[A-Za-z][A-Za-z0-9_]*$", "once"))
            error("vawlume:schema:MetadataInvalidValue", ...
                "%s.same_as is ""%s""; it must be ""<table>.<column>"".", ...
                columnPath, sameAs(k));
        end
        descriptions(k) = string(missing);
        sources(k) = "inherited:" + sameAs(k);
    end
end
end

% ---------------------------------------------------------------------------
% Relationships
% ---------------------------------------------------------------------------

function relationships = readRelationships(relationshipArray)
entries = schemaToEntryCell(relationshipArray);

sourceTable = strings(numel(entries), 1);
sourceColumns = strings(numel(entries), 1);
targetTable = strings(numel(entries), 1);
targetColumns = strings(numel(entries), 1);
description = strings(numel(entries), 1);

for k = 1:numel(entries)
    path = sprintf("relationships[%d]", k);
    entry = entries{k};

    schemaCheckFields(entry, path, ["source_table"; "source_columns"; ...
        "target_table"; "target_columns"; "description"]);

    sourceTable(k) = readRequiredIdentifier(entry, "source_table", path);
    targetTable(k) = readRequiredIdentifier(entry, "target_table", path);
    sourceColumns(k) = schemaJoinColumns(readColumnList(entry.source_columns, path + ".source_columns"));
    targetColumns(k) = schemaJoinColumns(readColumnList(entry.target_columns, path + ".target_columns"));

    description(k) = readDescription(entry, path + ".description");
end

key = schemaRelationshipKey(sourceTable, sourceColumns, targetTable, targetColumns);

duplicated = key(schemaFirstDuplicate(key));
if ~isempty(duplicated)
    error("vawlume:schema:MetadataDuplicateEntry", ...
        "relationships declares %s more than once.", duplicated(1));
end

relationships = table(sourceTable, sourceColumns, targetTable, targetColumns, description, key, ...
    VariableNames=["source_table", "source_columns", "target_table", ...
        "target_columns", "description", "relationship_key"]);
end

function columns = readColumnList(value, path)
columns = schemaToStringColumn(value);
if isempty(columns)
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s must name at least one column.", path);
end
invalid = columns(~schemaIsPlainIdentifier(columns));
if ~isempty(invalid)
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s contains a name that is not a plain identifier: %s.", path, invalid(1));
end
end

% ---------------------------------------------------------------------------
% Scalars
% ---------------------------------------------------------------------------

function value = readDescription(entry, path, identifier)
% Every rule about what makes acceptable prose lives in schemaDescriptionIssue,
% including emptiness. Letting the generic empty-string check fire first would
% report an empty description as a malformed value rather than as the
% unacceptable description it is, and would split one rule across two places.
arguments
    entry
    path (1,1) string
    identifier (1,1) string = ""
end

raw = entry.description;
if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s must be a JSON string.", path);
end

value = strtrim(string(raw));
issue = schemaDescriptionIssue(value, identifier);
if issue ~= ""
    error("vawlume:schema:MetadataPlaceholderDescription", "%s %s.", path, issue);
end
end

function value = readRequiredText(entry, field, path)
raw = entry.(field);
if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s must be a JSON string.", path);
end
value = strtrim(string(raw));
if ismissing(value) || strlength(value) == 0
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s must not be empty.", path);
end
end

function value = readRequiredIdentifier(entry, field, path)
value = readRequiredText(entry, field, path + "." + field);
if ~schemaIsPlainIdentifier(value)
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s.%s is ""%s"", which is not a plain identifier.", path, field, value);
end
end
