function parsed = parsePath(source, profileInput, options)
%PARSEPATH Parse one discovered source with project-input mapping rules.
%
% The parser preserves raw captures, normalized values, rule provenance,
% source-relative location, and structured non-match/ambiguity/conflict
% diagnostics. It performs no database writes and allocates no database IDs.

arguments
    source (1,1) struct
    profileInput
    options.ProfileId (1,1) string = ""
end

[profileEntry, profileLocation] = selectProjectInputProfile(profileInput, options.ProfileId);
records = emptySemanticRecord();
issues = emptyIssueArray();

if ~isfield(source, "relative_path") || strlength(string(source.relative_path)) == 0
    error("vawlume:source_mapping:MissingSourceRelativePath", ...
        "Source record must include a nonempty relative_path.");
end

relativePath = replace(string(source.relative_path), "\", "/");
filename = sourceFilename(source, relativePath);
pathComponents = split(relativePath, "/");
if numel(pathComponents) > 1
    pathComponents = pathComponents(1:end - 1);
else
    pathComponents = strings(0, 1);
end

mappings = normalizeMappingSequence(profileEntry.mappings);
for mappingIndex = 1:numel(mappings)
    mapping = mappings{mappingIndex};
    mappingLocation = profileLocation + ".mappings(" + mappingIndex + ")";
    sourceType = optionalText(mapping, "source_type");
    switch sourceType
        case "literal"
            [records, issues] = parseLiteralMapping(records, issues, source, ...
                profileEntry, mapping, mappingIndex, mappingLocation);
        case "path_component"
            [records, issues] = parsePathComponentMapping(records, issues, ...
                source, profileEntry, mapping, mappingIndex, mappingLocation, ...
                pathComponents);
        case "filename"
            [records, issues] = parseFilenameMapping(records, issues, source, ...
                profileEntry, mapping, mappingIndex, mappingLocation, filename);
        otherwise
            issue = makeIssue("error", "PATH_RULE_UNSUPPORTED_SOURCE_TYPE", ...
                mappingLocation + ".source_type", ...
                "Unsupported project-input mapping source_type during parsing: " + sourceType + ".");
            issues = appendIssue(issues, issue);
    end
end

parsed = struct();
parsed.source = source;
parsed.profile_id = string(profileEntry.profile.id);
parsed.profile_kind = string(profileEntry.profile.kind);
parsed.relative_path = relativePath;
parsed.records = records;
parsed.record_table = semanticRecordsToTable(records);
parsed.issues = issues;
parsed.issue_table = sourceMappingIssuesToTable(issues);
parsed.error_count = issueCount(issues, "error");
parsed.warning_count = issueCount(issues, "warning");
parsed.info_count = issueCount(issues, "info");
parsed.conflict_count = issueCodeCount(issues, "PATH_CAPTURE_CONFLICT");
parsed.is_valid = parsed.error_count == 0;
parsed.case_sensitive_matching = true;
parsed.symlink_policy = "relative path supplied by discovery; discovery canonicalizes existing runtime paths";
end

function [records, issues] = parseLiteralMapping(records, issues, source, ...
        profileEntry, mapping, mappingIndex, mappingLocation)
rawValue = string(mapping.value);
record = baseRecord(source, profileEntry, mapping, mappingIndex, mappingLocation, ...
    "literal", "", "", "", rawValue, rawValue);
record.normalization_source = "literal";
[records, issues] = appendSemanticRecord(records, issues, record);
end

function [records, issues] = parsePathComponentMapping(records, issues, source, ...
        profileEntry, mapping, mappingIndex, mappingLocation, pathComponents)
profileRegex = string(mapping.path_component_regex);
[matchCount, matchIndex, matchNames, matchTokens, issue] = matchPathComponents( ...
    pathComponents, profileRegex, mappingLocation + ".path_component_regex");

if ~isempty(issue)
    issues(end + 1) = issue;
    return
end
if matchCount == 0
    issues(end + 1) = noMatchIssue(mapping, mappingLocation, "PATH_RULE_NO_MATCH", ...
        "Required path_component mapping did not match any path component.");
    return
end
if matchCount > 1
    issues(end + 1) = makeIssue("error", "PATH_RULE_AMBIGUOUS_MATCH", ...
        mappingLocation + ".path_component_regex", ...
        "Path_component mapping matched more than one component or occurrence.");
    return
end

[rawValue, ok, message] = captureValue(mapping.capture_group, matchNames, matchTokens);
if ~ok
    issues(end + 1) = makeIssue("error", "PATH_CAPTURE_MISSING", ...
        mappingLocation + ".capture_group", message);
    return
end

record = baseRecord(source, profileEntry, mapping, mappingIndex, mappingLocation, ...
    "path_component", profileRegex, string(mapping.capture_group), ...
    pathComponents(matchIndex), rawValue, rawValue);
record.path_component_index = matchIndex;
[records, issues] = appendSemanticRecord(records, issues, record);
end

function [records, issues] = parseFilenameMapping(records, issues, source, ...
        profileEntry, mapping, mappingIndex, mappingLocation, filename)
profileRegex = string(mapping.filename_regex);
[matchCount, matchNames, ~, issue] = matchSubject(filename, profileRegex, ...
    mappingLocation + ".filename_regex");

if ~isempty(issue)
    issues(end + 1) = issue;
    return
end
if matchCount == 0
    issues(end + 1) = noMatchIssue(mapping, mappingLocation, "PATH_RULE_NO_MATCH", ...
        "Required filename mapping did not match the source filename.");
    return
end
if matchCount > 1
    issues(end + 1) = makeIssue("error", "PATH_RULE_AMBIGUOUS_MATCH", ...
        mappingLocation + ".filename_regex", ...
        "Filename mapping matched more than once.");
    return
end

captureNames = string(fieldnames(mapping.captures));
for captureIndex = 1:numel(captureNames)
    captureName = captureNames(captureIndex);
    captureLocation = mappingLocation + ".captures." + captureName;
    if ~isfield(matchNames, char(captureName))
        issue = makeIssue("error", "PATH_CAPTURE_MISSING", ...
            captureLocation, ...
            "Capture declaration was not produced by the filename regex: " + captureName + ".");
        issues = appendIssue(issues, issue);
        continue
    end

    declaration = mapping.captures.(char(captureName));
    rawValue = string(matchNames.(char(captureName)));
    [normalizedValue, normalizationSource] = normalizedCaptureValue(rawValue, declaration, ...
        captureLocation + ".normalize");
    record = baseRecord(source, profileEntry, mapping, mappingIndex, mappingLocation, ...
        "filename", profileRegex, captureName, filename, rawValue, normalizedValue);
    record.target_level = fallbackText(declaration, "target_level", record.target_level);
    record.canonical_field = fallbackText(declaration, "canonical_field", record.canonical_field);
    record.membership_level = optionalText(declaration, "membership_level");
    record.relation_role = optionalText(declaration, "relation_role");
    record.capture_name = captureName;
    record.data_type = optionalText(declaration, "data_type");
    record.normalization_source = normalizationSource;
    [records, issues] = appendSemanticRecord(records, issues, record);
end
end

function [matchCount, matchIndex, matchNames, matchTokens, issue] = matchPathComponents( ...
        pathComponents, pattern, profileLocation)
matchCount = 0;
matchIndex = 0;
matchNames = struct();
matchTokens = {};
issue = [];

for index = 1:numel(pathComponents)
    [count, names, tokens, localIssue] = matchSubject(pathComponents(index), pattern, profileLocation);
    if ~isempty(localIssue)
        issue = localIssue;
        return
    end
    if count > 0
        matchCount = matchCount + count;
        if matchIndex == 0
            matchIndex = index;
            matchNames = names;
            matchTokens = tokens;
        end
    end
end
end

function [matchCount, matchNames, matchTokens, issue] = matchSubject(subject, pattern, profileLocation)
matchNames = struct();
matchTokens = {};
issue = [];
syntaxMessage = basicRegexSyntaxMessage(pattern);
if strlength(syntaxMessage) > 0
    matchCount = 0;
    issue = makeIssue("error", "PATH_RULE_INVALID_REGEX", profileLocation, syntaxMessage);
    return
end
try
    names = regexp(char(subject), char(pattern), "names");
    tokens = regexp(char(subject), char(pattern), "tokens");
catch exception
    matchCount = 0;
    issue = makeIssue("error", "PATH_RULE_INVALID_REGEX", profileLocation, ...
        "Regex could not be evaluated by MATLAB regexp: " + string(exception.message));
    return
end

matchCount = max(numel(names), numel(tokens));
if matchCount >= 1
    if numel(names) >= 1
        matchNames = names(1);
    end
    if numel(tokens) >= 1
        matchTokens = tokens{1};
    end
end
end

function [rawValue, ok, message] = captureValue(captureGroup, matchNames, matchTokens)
rawValue = "";
ok = true;
message = "";

if isnumeric(captureGroup)
    captureIndex = double(captureGroup);
    if captureIndex < 1 || captureIndex > numel(matchTokens)
        ok = false;
        message = "Numeric capture_group was not produced by the regex.";
    else
        rawValue = string(matchTokens{captureIndex});
    end
    return
end

captureName = string(captureGroup);
if isfield(matchNames, char(captureName))
    rawValue = string(matchNames.(char(captureName)));
else
    ok = false;
    message = "Named capture_group was not produced by the regex: " + captureName + ".";
end
end

function issue = noMatchIssue(mapping, mappingLocation, code, message)
severity = "error";
if hasProfileField(mapping, "required")
    try
        if ~logical(mapping.required)
            severity = "info";
            code = "PATH_RULE_OPTIONAL_NO_MATCH";
        end
    catch
    end
end
issue = makeIssue(severity, code, mappingLocation, message);
end

function [records, issues] = appendSemanticRecord(records, issues, record)
for index = 1:numel(records)
    if semanticKey(records(index)) == semanticKey(record)
        if records(index).normalized_value == record.normalized_value
            issue = makeIssue("info", "PATH_CAPTURE_CORROBORATED", ...
                record.profile_location, ...
                "Repeated target concept captured the same normalized value: " + semanticKey(record) + ".");
            issues = appendIssue(issues, issue);
        else
            issue = makeIssue("error", "PATH_CAPTURE_CONFLICT", ...
                record.profile_location, ...
                "Repeated target concept captured conflicting normalized values for " + semanticKey(record) + ".");
            issues = appendIssue(issues, issue);
        end
    end
end
records(end + 1) = record;
end

function issues = appendIssue(issues, issue)
if isempty(issues)
    issues = issue;
else
    issues(numel(issues) + 1) = issue;
end
end

function key = semanticKey(record)
if strlength(record.membership_level) > 0
    key = "membership|" + record.membership_level + "|" + ...
        record.relation_role + "|" + record.canonical_field;
elseif strlength(record.canonical_field) > 0
    key = "field|" + record.canonical_field;
else
    key = "level|" + record.target_level;
end
end

function record = baseRecord(source, profileEntry, mapping, mappingIndex, mappingLocation, ...
        mappingSourceType, regexText, captureName, sourceFragment, rawValue, normalizedValue)
record = blankSemanticRecord();
record.source_key = string(source.source_key);
record.relative_path = replace(string(source.relative_path), "\", "/");
record.filename = sourceFilename(source, record.relative_path);
record.profile_id = string(profileEntry.profile.id);
record.target_level = optionalText(mapping, "target_level");
record.canonical_field = optionalText(mapping, "canonical_field");
record.membership_level = "";
record.relation_role = "";
record.raw_value = string(rawValue);
record.normalized_value = string(normalizedValue);
record.mapping_source_type = string(mappingSourceType);
record.rule_index = mappingIndex;
record.rule_id = "mappings(" + string(mappingIndex) + ")";
record.profile_location = mappingLocation;
record.capture_name = string(captureName);
record.source_fragment = string(sourceFragment);
record.path_component = string(sourceFragment);
record.path_component_index = NaN;
record.regex = string(regexText);
record.data_type = optionalText(mapping, "data_type");
record.normalization_source = "";
record.provenance = mappingLocation;
end

function [value, source] = normalizedCaptureValue(rawValue, declaration, location)
value = string(rawValue);
source = "";
if ~hasProfileField(declaration, "normalize") || ~isstruct(declaration.normalize)
    return
end

normalizeKeys = string(fieldnames(declaration.normalize));
for index = 1:numel(normalizeKeys)
    key = normalizeKeys(index);
    if key == rawValue
        value = string(declaration.normalize.(char(key)));
        source = location + "." + key;
        return
    end
end
end

function filename = sourceFilename(source, relativePath)
if isfield(source, "filename") && strlength(string(source.filename)) > 0
    filename = string(source.filename);
    return
end
[~, stem, extension] = fileparts(relativePath);
filename = string(stem) + string(extension);
end

function value = fallbackText(container, field, fallback)
value = optionalText(container, field);
if strlength(value) == 0
    value = string(fallback);
end
end

function count = issueCount(issues, severity)
count = 0;
for index = 1:numel(issues)
    if string(issues(index).severity) == severity
        count = count + 1;
    end
end
end

function count = issueCodeCount(issues, code)
count = 0;
for index = 1:numel(issues)
    if string(issues(index).code) == code
        count = count + 1;
    end
end
end

function tableValue = semanticRecordsToTable(records)
if isempty(records)
    tableValue = table( ...
        strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), NaN(0, 1), ...
        strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
        VariableNames=["source_key", "relative_path", "filename", "profile_id", ...
        "target_level", "canonical_field", "membership_level", "relation_role", ...
        "raw_value", "normalized_value", "mapping_source_type", "rule_index", ...
        "rule_id", "profile_location", "capture_name", "normalization_source"]);
else
    tableValue = struct2table(records);
end
end

function record = emptySemanticRecord()
record = blankSemanticRecord();
record = record([]);
end

function record = blankSemanticRecord()
record = struct( ...
    "source_key", "", ...
    "relative_path", "", ...
    "filename", "", ...
    "profile_id", "", ...
    "target_level", "", ...
    "canonical_field", "", ...
    "membership_level", "", ...
    "relation_role", "", ...
    "raw_value", "", ...
    "normalized_value", "", ...
    "mapping_source_type", "", ...
    "rule_index", NaN, ...
    "rule_id", "", ...
    "profile_location", "", ...
    "capture_name", "", ...
    "source_fragment", "", ...
    "path_component", "", ...
    "path_component_index", NaN, ...
    "regex", "", ...
    "data_type", "", ...
    "normalization_source", "", ...
    "provenance", "");
end

function issues = emptyIssueArray()
issues = struct("severity", {}, "code", {}, "profile_location", {}, "message", {});
end
