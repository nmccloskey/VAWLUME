function result = parse(profilePath, sourceRoot, options)
%PARSE Interpret project sources into the unified source-mapping IR.
%
% RESULT contains profile provenance plus sources, logical records, mapped
% values, relationships, structured issues, a summary, and derived
% valid_for_ingest. This function performs no database access or writes.

arguments
    profilePath (1,1) string
    sourceRoot (1,1) string
    options.ProfileId (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.PythonExecutable (1,1) string = ""
end

[loaded, ~] = vawlume.source_mapping.loadProfile( ...
    profilePath, ExpectedKind="project_input", RepoRoot=options.RepoRoot, ...
    PythonExecutable=options.PythonExecutable);
[profile, profileEntry, profileLocation] = profileProvenance(loaded, options.ProfileId);
result = emptyIntermediateRepresentation(profile);

profileIssues = selectedProfileIssues(loaded.issues, profileLocation);
result.issues = [result.issues; normalizeIssuesForIR(profileIssues)];

[sources, ~] = vawlume.source_mapping.discoverSources( ...
    loaded, sourceRoot, ProfileId=options.ProfileId);
if isempty(sources)
    issue = struct( ...
        severity="error", ...
        code="SOURCE_NOT_FOUND", ...
        profile_location=profileLocation + ".source.include", ...
        message="No source files matched the selected profile under the supplied source root.");
    result.issues = [result.issues; normalizeIssuesForIR(issue)];
end
for sourceIndex = 1:numel(sources)
    source = sources(sourceIndex);
    parsed = vawlume.source_mapping.parsePath( ...
        source, loaded, ProfileId=options.ProfileId);

    [records, values, relationships] = projectRows( ...
        source, parsed, profileEntry, profileLocation);
    result.records = [result.records; records];
    result.values = [result.values; values];
    result.relationships = [result.relationships; relationships];

    sourceIssues = normalizeIssuesForIR(source.issues, SourceKey=source.source_key);
    parsedIssues = normalizeIssuesForIR( ...
        withoutPathConflictIssues(parsed.issues), SourceKey=source.source_key);
    result.issues = [result.issues; sourceIssues; parsedIssues];

    status = "mapped";
    if parsed.error_count > 0
        status = "invalid";
    elseif parsed.warning_count > 0 || ~isempty(source.issues)
        status = "mapped_with_warnings";
    end
    result.sources(end + 1, :) = { ...
        string(source.source_key), string(source.runtime_path), ...
        string(source.relative_path), string(source.filename), ...
        "project_file", string(source.discovery_rule_id), ...
        string(source.artifact_type), status, NaN, ""};
end

result = finalizeIntermediateRepresentation(result);
end

function [records, values, relationships] = projectRows( ...
        source, parsed, profileEntry, profileLocation)
emptyResult = emptyIntermediateRepresentation(struct());
records = emptyResult.records;
values = emptyResult.values;
relationships = emptyResult.relationships;
semanticRows = parsed.record_table;

levels = normalizeMappingSequence(profileEntry.hierarchy.levels);
for levelIndex = 1:numel(levels)
    declaration = levels{levelIndex};
    nativeLevel = string(declaration.native_name);
    canonicalLevel = string(declaration.canonical_role);
    matches = string(semanticRows.target_level) == nativeLevel & ...
        strlength(string(semanticRows.membership_level)) == 0;
    isRecording = canonicalLevel == "recording";
    if ~any(matches) && ~isRecording
        continue
    end

    [identifier, status, mappingRule] = levelIdentifier( ...
        semanticRows(matches, :), source, isRecording);
    recordKey = ordinaryRecordKey(source.source_key, nativeLevel);
    scope = "entity";
    if isRecording
        scope = "source_recording";
    end
    records(end + 1, :) = {recordKey, string(source.source_key), ...
        nativeLevel, canonicalLevel, identifier, scope, NaN, "", ...
        mappingRule, status}; %#ok<AGROW>
end

membershipLevels = {};
if hasProfileField(profileEntry.hierarchy, "membership_levels")
    membershipLevels = normalizeMappingSequence(profileEntry.hierarchy.membership_levels);
end
for declarationIndex = 1:numel(membershipLevels)
    declaration = membershipLevels{declarationIndex};
    nativeLevel = string(declaration.native_name);
    canonicalLevel = string(declaration.canonical_role);
    rows = semanticRows(string(semanticRows.membership_level) == nativeLevel, :);
    if isempty(rows)
        continue
    end
    keys = string(rows.relation_role) + "|" + string(rows.normalized_value);
    [~, firstRows] = unique(keys, "stable");
    for rowIndex = 1:numel(firstRows)
        row = rows(firstRows(rowIndex), :);
        identifier = string(row.normalized_value);
        role = string(row.relation_role);
        recordKey = membershipRecordKey(source.source_key, nativeLevel, role, identifier);
        records(end + 1, :) = {recordKey, string(source.source_key), ...
            nativeLevel, canonicalLevel, identifier, "membership", NaN, role, ...
            string(row.rule_id), "mapped"}; %#ok<AGROW>
    end
end

for rowIndex = 1:height(semanticRows)
    row = semanticRows(rowIndex, :);
    recordKey = recordForSemanticRow(records, row);
    values(end + 1, :) = projectValueRow(source, row, recordKey, rowIndex); %#ok<AGROW>
end

for levelIndex = 1:numel(levels)
    declaration = levels{levelIndex};
    parentLevel = optionalText(declaration, "parent");
    if strlength(parentLevel) == 0
        continue
    end
    childLevel = string(declaration.native_name);
    parentKey = ordinaryRecordForLevel(records, parentLevel);
    childKey = ordinaryRecordForLevel(records, childLevel);
    if strlength(parentKey) == 0 || strlength(childKey) == 0
        continue
    end
    rule = profileLocation + ".hierarchy.levels(" + levelIndex + ").parent";
    relationships(end + 1, :) = relationshipRow(source.source_key, ...
        parentKey, childKey, "parent", "contains", "", rule); %#ok<AGROW>
end

for declarationIndex = 1:numel(membershipLevels)
    declaration = membershipLevels{declarationIndex};
    relationTo = string(declaration.relation_to);
    parentKey = ordinaryRecordForLevel(records, relationTo);
    if strlength(parentKey) == 0
        continue
    end
    memberRows = find(string(records.native_level) == string(declaration.native_name) & ...
        string(records.record_scope) == "membership");
    for rowIndex = 1:numel(memberRows)
        member = records(memberRows(rowIndex), :);
        rule = profileLocation + ".hierarchy.membership_levels(" + ...
            declarationIndex + ").relation_to";
        relationships(end + 1, :) = relationshipRow(source.source_key, ...
            parentKey, string(member.record_key), "membership", "has_member", ...
            string(member.role_label), rule); %#ok<AGROW>
    end
end
end

function row = projectValueRow(source, semanticRow, recordKey, rowIndex)
rawValue = string(semanticRow.raw_value);
normalizedValue = string(semanticRow.normalized_value);
dataType = string(semanticRow.data_type);

nativeType = "text";
nativeReal = NaN;
nativeInteger = NaN;
nativeText = rawValue;
nativeBoolean = NaN;
normalizedType = "text";
normalizedReal = NaN;
normalizedInteger = NaN;
normalizedText = normalizedValue;
normalizedBoolean = NaN;
if dataType == "integer"
    nativeType = "integer";
    nativeInteger = str2double(rawValue);
    nativeText = "";
    normalizedType = "integer";
    normalizedInteger = str2double(normalizedValue);
    normalizedText = "";
end

nativeField = string(semanticRow.capture_name);
if strlength(nativeField) == 0
    nativeField = string(semanticRow.target_level);
end
transformKey = "";
if strlength(string(semanticRow.normalization_source)) > 0
    transformKey = "value_mapping";
end

evidenceGroup = projectEvidenceGroup(source.source_key, semanticRow);
valueKey = string(source.source_key) + "|path_value:" + ...
    compose("%04d", rowIndex);
row = {valueKey, evidenceGroup, recordKey, string(source.source_key), ...
    nativeField, string(semanticRow.source_fragment), rawValue, nativeType, ...
    nativeReal, nativeInteger, nativeText, nativeBoolean, "", ...
    string(semanticRow.canonical_field), normalizedReal, normalizedInteger, ...
    normalizedText, normalizedBoolean, normalizedType, "", transformKey, ...
    string(semanticRow.rule_id), string(semanticRow.profile_location), NaN, ...
    "", "", "", "", "", "", "", "", 1, "mapped"};
end

function group = projectEvidenceGroup(sourceKey, row)
sourceKey = string(sourceKey);
membershipLevel = string(row.membership_level);
canonicalField = string(row.canonical_field);
if strlength(membershipLevel) > 0
    group = sourceKey + "|membership:" + membershipLevel + "|role:" + ...
        string(row.relation_role) + "|field:" + canonicalField;
elseif strlength(canonicalField) > 0
    group = sourceKey + "|field:" + canonicalField;
else
    group = sourceKey + "|level:" + string(row.target_level);
end
end

function [identifier, status, mappingRule] = levelIdentifier(rows, source, isRecording)
if isRecording
    identifier = string(source.relative_path);
    status = "mapped";
    mappingRule = "source.relative_path";
    return
end
if isempty(rows)
    identifier = "";
    status = "unresolved";
    mappingRule = "";
    return
end

fields = string(rows.canonical_field);
candidates = rows(strlength(fields) == 0 | endsWith(fields, "_id"), :);
if isempty(candidates)
    candidates = rows;
end
identifiers = unique(string(candidates.normalized_value));
identifiers = sort(identifiers);
mappingRule = strjoin(unique(string(candidates.rule_id)), ";");
if isscalar(identifiers)
    identifier = identifiers;
    status = "mapped";
else
    identifier = "";
    status = "conflict";
end
end

function key = recordForSemanticRow(records, row)
if strlength(string(row.membership_level)) > 0
    matches = string(records.native_level) == string(row.membership_level) & ...
        string(records.role_label) == string(row.relation_role) & ...
        string(records.native_identifier) == string(row.normalized_value);
else
    matches = string(records.native_level) == string(row.target_level) & ...
        string(records.record_scope) ~= "membership";
end
key = "";
if any(matches)
    key = string(records.record_key(find(matches, 1)));
end
end

function key = ordinaryRecordForLevel(records, level)
matches = string(records.native_level) == string(level) & ...
    string(records.record_scope) ~= "membership";
key = "";
if any(matches)
    key = string(records.record_key(find(matches, 1)));
end
end

function key = ordinaryRecordKey(sourceKey, level)
key = string(sourceKey) + "|record:" + string(level);
end

function key = membershipRecordKey(sourceKey, level, role, identifier)
key = string(sourceKey) + "|member:" + string(level) + ...
    "|role:" + string(role) + "|id:" + string(identifier);
end

function row = relationshipRow(sourceKey, fromKey, toKey, native, canonical, role, rule)
key = string(sourceKey) + "|relationship:" + string(canonical) + ...
    "|from:" + string(fromKey) + "|to:" + string(toKey) + "|role:" + string(role);
row = {key, string(sourceKey), string(fromKey), string(toKey), ...
    string(native), string(canonical), string(role), string(rule), "mapped"};
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

function issues = withoutPathConflictIssues(allIssues)
issues = allIssues([]);
for index = 1:numel(allIssues)
    if string(allIssues(index).code) ~= "PATH_CAPTURE_CONFLICT"
        issues(end + 1) = allIssues(index); %#ok<AGROW>
    end
end
end
