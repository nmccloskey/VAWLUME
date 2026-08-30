function result = mapTableToIR(tbl, profileInput, options)
%MAPTABLETOIR Map an in-memory source table into the unified IR contract.
%
% PROFILEINPUT may be a loaded profile bundle, one decoded table-mapping
% profile document, or a JSON profile path. Extractor-output, external-stream,
% and alignment-anchor profiles share this entry point. Artifact reading and
% every database operation remain outside this function.

arguments
    tbl table
    profileInput
    options.ProfileId (1,1) string = ""
    options.SourceKey (1,1) string = "source:in_memory_table"
    options.ArtifactKey (1,1) string = ""
    options.RuntimePath (1,1) string = ""
    options.RelativePath (1,1) string = ""
    options.Filename (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.EventContext (1,1) struct = struct()
end

if ischar(profileInput) || (isstring(profileInput) && isscalar(profileInput))
    loaded = vawlume.source_mapping.loadProfile( ...
        string(profileInput), RepoRoot=options.RepoRoot);
else
    loaded = profileInput;
end

[profile, profileEntry, profileLocation] = profileProvenance(loaded, options.ProfileId);
result = emptyIntermediateRepresentation(profile);
if isstruct(loaded) && hasProfileField(loaded, "issues")
    issues = selectedProfileIssues(loaded.issues, profileLocation);
    result.issues = [result.issues; normalizeIssuesForIR(issues)];
end

switch string(profile.profile_kind)
    case "external_stream_mapping"
        result = mapExternalStreamTableToIR( ...
            tbl, result, profileEntry, profileLocation, options);
        return
    case "alignment_anchor_mapping"
        result = mapAlignmentAnchorTableToIR( ...
            tbl, result, profileEntry, profileLocation, options);
        return
    case "extractor_output"
        % Continue through the inherited generic extractor field mapper.
    otherwise
        error("vawlume:source_mapping:UnexpectedProfileKind", ...
            "mapTableToIR does not map profile kind %s.", profile.profile_kind);
end

sourceKey = options.SourceKey;
if strlength(sourceKey) == 0
    sourceKey = "source:in_memory_table";
end
mapped = vawlume.source_mapping.mapTableFields( ...
    tbl, loaded, ProfileId=options.ProfileId, SourceKey=sourceKey, ...
    ArtifactKey=options.ArtifactKey);

filename = options.Filename;
if strlength(filename) == 0
    candidate = options.RelativePath;
    if strlength(candidate) == 0
        candidate = options.RuntimePath;
    end
    if strlength(candidate) > 0
        [~, stem, extension] = fileparts(candidate);
        filename = string(stem) + string(extension);
    end
end

sourceStatus = "mapped";
if ~mapped.is_valid
    sourceStatus = "invalid";
elseif mapped.warning_count > 0
    sourceStatus = "mapped_with_warnings";
end
result.sources(end + 1, :) = {sourceKey, options.RuntimePath, ...
    replace(options.RelativePath, "\", "/"), filename, "extractor_table", ...
    "supplied_table", mapped.source_artifact_type, sourceStatus, height(tbl), ""};

for rowIndex = 1:height(tbl)
    rowRecords = mapped.record_table(mapped.record_table.source_row == rowIndex, :);
    identifier = eventIdentifier(rowRecords);
    recordKey = sourceKey + "|record:event|row:" + compose("%08d", rowIndex);
    recordStatus = "mapped";
    if any(string(rowRecords.status) == "invalid")
        recordStatus = "invalid";
    elseif any(string(rowRecords.status) == "missing")
        recordStatus = "mapped_with_missing";
    end
    result.records(end + 1, :) = {recordKey, sourceKey, "event", "event", ...
        identifier, "source_table_row", rowIndex, "", "table_row", recordStatus};
end

for valueIndex = 1:height(mapped.record_table)
    record = mapped.record_table(valueIndex, :);
    recordKey = sourceKey + "|record:event|row:" + ...
        compose("%08d", record.source_row);
    valueKey = sourceKey + "|table_value:row:" + ...
        compose("%08d", record.source_row) + "|mapping:" + ...
        compose("%04d", record.mapping_index);
    evidenceGroup = recordKey + "|field:" + string(record.canonical_field);
    result.values(end + 1, :) = { ...
        valueKey, evidenceGroup, recordKey, sourceKey, ...
        string(record.native_field_name), string(record.actual_source_field), ...
        string(record.native_raw_token), string(record.native_value_type), ...
        record.native_value_real, record.native_value_integer, ...
        string(record.native_value_text), record.native_value_boolean, ...
        string(record.native_unit), string(record.canonical_field), ...
        record.canonical_value_real, record.canonical_value_integer, ...
        string(record.canonical_value_text), record.canonical_value_boolean, ...
        string(record.canonical_value_type), string(record.canonical_unit), ...
        string(record.transform_key), string(record.mapping_rule_id), ...
        string(record.profile_location), record.source_row, ...
        string(record.derivation_stage), string(record.operational_variant), ...
        string(record.operational_definition), string(record.equivalence_class), ...
        string(record.cross_extractor_relationship), string(record.consilience_role), ...
        string(record.semantic_role), "", 1, string(record.status)};
end

result.issues = [result.issues; normalizeIssuesForIR( ...
    mapped.issues, SourceKey=sourceKey)];
result = finalizeIntermediateRepresentation(result);
end

function identifier = eventIdentifier(records)
identifier = "";
if isempty(records)
    return
end
matches = string(records.canonical_field) == "native_event_id";
if ~any(matches)
    return
end
record = records(find(matches, 1), :);
switch string(record.canonical_value_type)
    case {"missing", "invalid"}
        % An absent or uninterpretable identifier stays absent. Falling back to
        % the raw token here would publish a fabricated identity such as "NaN"
        % or a missing sentinel as though the source had supplied one.
        identifier = "";
    case "integer"
        identifier = string(record.canonical_value_integer);
    case "real"
        identifier = string(record.canonical_value_real);
    case "text"
        identifier = string(record.canonical_value_text);
    otherwise
        identifier = string(record.native_raw_token);
end
end

function issues = selectedProfileIssues(allIssues, location)
issues = allIssues([]);
for index = 1:numel(allIssues)
    issueLocation = string(allIssues(index).profile_location);
    if startsWith(issueLocation, location)
        issues(end + 1) = allIssues(index); %#ok<AGROW>
    end
end
end
