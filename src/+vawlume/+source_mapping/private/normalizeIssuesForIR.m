function tableValue = normalizeIssuesForIR(rawIssues, options)
%NORMALIZEISSUESFORIR Project component diagnostics into the IR issue schema.

arguments
    rawIssues
    options.SourceKey (1,1) string = ""
    options.RecordKey (1,1) string = ""
end

empty = emptyIntermediateRepresentation(struct()).issues;
if isempty(rawIssues)
    tableValue = empty;
    return
end
if istable(rawIssues)
    rawIssues = table2struct(rawIssues);
end

count = numel(rawIssues);
severity = strings(count, 1);
code = strings(count, 1);
sourceKey = repmat(options.SourceKey, count, 1);
recordKey = repmat(options.RecordKey, count, 1);
location = strings(count, 1);
fieldOrRule = strings(count, 1);
message = strings(count, 1);
affectsValidity = false(count, 1);

for index = 1:count
    raw = rawIssues(index);
    rawCode = fieldText(raw, "code");
    code(index) = canonicalCode(rawCode);
    severity(index) = policySeverity(code(index), fieldText(raw, "severity"));
    location(index) = firstNonempty( ...
        fieldText(raw, "location"), fieldText(raw, "profile_location"));
    fieldOrRule(index) = fieldText(raw, "field_or_rule");
    if strlength(fieldOrRule(index)) == 0
        fieldOrRule(index) = location(index);
    end
    message(index) = fieldText(raw, "message");
    affectsValidity(index) = ismember(severity(index), ["error", "fatal"]);
end

tableValue = table(strings(count, 1), severity, code, sourceKey, recordKey, ...
    location, fieldOrRule, message, affectsValidity, ...
    VariableNames=empty.Properties.VariableNames);
end

function code = canonicalCode(code)
code = string(code);
switch code
    case "PATH_CAPTURE_CONFLICT"
        code = "VALUE_CONFLICT";
    case "PATH_CAPTURE_CORROBORATED"
        code = "VALUE_CORROBORATED";
    case "PATH_RULE_NO_MATCH"
        code = "REGEX_NO_MATCH";
    case "PATH_RULE_OPTIONAL_NO_MATCH"
        code = "OPTIONAL_REGEX_NO_MATCH";
    case "PATH_RULE_AMBIGUOUS_MATCH"
        code = "REGEX_MULTIPLE_MATCH";
    case "PATH_CAPTURE_MISSING"
        code = "REQUIRED_VALUE_MISSING";
    case "FIELD_MAPPING_COLUMN_MISSING"
        code = "COLUMN_MISSING";
    case "FIELD_MAPPING_OPTIONAL_COLUMN_MISSING"
        code = "OPTIONAL_COLUMN_MISSING";
    case "FIELD_MAPPING_COLUMN_AMBIGUOUS"
        code = "COLUMN_AMBIGUOUS";
    case "FIELD_MAPPING_SOURCE_COLUMN_UNMAPPED"
        code = "SOURCE_COLUMN_UNMAPPED";
    case "FIELD_VALUE_COERCION_FAILED"
        code = "TYPE_COERCION_FAILED";
    case {"FIELD_VALUE_EXPLICIT_MISSING", "FIELD_VALUE_MISSING"}
        code = "MISSING_TOKEN_NORMALIZED";
    case "TRANSFORM_INPUT_NOT_NUMERIC"
        code = "TRANSFORM_FAILED";
    case "SOURCE_PATH_OUTSIDE_ROOT"
        code = "SOURCE_OUTSIDE_ROOT";
end
end

function severity = policySeverity(code, fallback)
errorCodes = [ ...
    "COLUMN_AMBIGUOUS", "COLUMN_MISSING", "PROFILE_INVALID_REGEX", ...
    "REGEX_MULTIPLE_MATCH", "REGEX_NO_MATCH", "REQUIRED_VALUE_MISSING", ...
    "SOURCE_NOT_FOUND", "SOURCE_OUTSIDE_ROOT", "TRANSFORM_FAILED", ...
    "TRANSFORM_UNKNOWN", "TYPE_COERCION_FAILED", "VALUE_CONFLICT"];
warningCodes = "SOURCE_DUPLICATE_DISCOVERY";
infoCodes = ["MISSING_TOKEN_NORMALIZED", "OPTIONAL_COLUMN_MISSING", ...
    "OPTIONAL_REGEX_NO_MATCH", "VALUE_CORROBORATED"];

% SOURCE_COLUMN_UNMAPPED is deliberately absent from all three lists so that the
% profile's declared mapping_policy.unknown_fields decides its severity instead
% of a fixed central rule.

if ismember(code, errorCodes)
    severity = "error";
elseif ismember(code, warningCodes)
    severity = "warning";
elseif ismember(code, infoCodes)
    severity = "info";
else
    severity = lower(string(fallback));
    if ~ismember(severity, ["info", "warning", "error", "fatal"])
        severity = "error";
    end
end
end

function value = fieldText(container, field)
value = "";
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
try
    candidate = string(container.(char(field)));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = candidate;
end
end

function value = firstNonempty(first, second)
value = string(first);
if strlength(value) == 0
    value = string(second);
end
end
