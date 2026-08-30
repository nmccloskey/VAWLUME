function [mapped, issues] = mapTypedSourceValue(value, rule, location)
%MAPTYPEDSOURCEVALUE Map one declared scalar while preserving its raw token.

mapped = struct( ...
    raw_value=sourceRawToken(value), ...
    value_type="", ...
    value_real=NaN, ...
    value_integer=NaN, ...
    value_text="", ...
    value_boolean=NaN, ...
    native_unit=ruleText(rule, "native_unit"), ...
    normalized_unit=ruleText(rule, "normalized_unit"), ...
    transform_key=ruleText(rule, "transform"), ...
    status="mapped");
issues = emptyIssueArray();

if isMissingValue(value, rule)
    mapped.value_type = "missing";
    mapped.status = "missing";
    issues = appendIssue(issues, makeIssue("info", "MISSING_TOKEN_NORMALIZED", ...
        location, "Source value is explicitly missing; raw token was preserved."));
    return
end

dataType = lower(ruleText(rule, "data_type"));
if strlength(dataType) == 0
    dataType = "string";
end
switch dataType
    case {"float", "float_or_missing"}
        [number, ok] = finiteNumber(value);
        if ~ok
            [mapped, issues] = invalidValue(mapped, issues, location, ...
                "Source value must be a finite numeric scalar.");
            return
        end
        mapped.value_type = "real";
        mapped.value_real = number;
    case "integer"
        [number, ok] = finiteNumber(value);
        if ~ok || fix(number) ~= number
            [mapped, issues] = invalidValue(mapped, issues, location, ...
                "Source value must be a finite integer scalar.");
            return
        end
        mapped.value_type = "integer";
        mapped.value_integer = number;
    case "boolean"
        [logicalValue, ok] = logicalScalar(value);
        if ~ok
            [mapped, issues] = invalidValue(mapped, issues, location, ...
                "Source value must be one of true/false, yes/no, or 1/0.");
            return
        end
        mapped.value_type = "boolean";
        mapped.value_boolean = double(logicalValue);
    case "string"
        mapped.value_type = "text";
        mapped.value_text = mapped.raw_value;
    otherwise
        [mapped, issues] = invalidValue(mapped, issues, location, ...
            "Unsupported declared data_type: " + dataType + ".");
        return
end

transformKey = mapped.transform_key;
if strlength(transformKey) == 0 || transformKey == "identity"
    if strlength(transformKey) == 0
        mapped.transform_key = "identity";
    end
    return
end
if ~ismember(transformKey, supportedTransformKeys())
    mapped.status = "invalid";
    issues = appendIssue(issues, makeIssue("error", "TIME_UNIT_UNSUPPORTED", ...
        location, "Transform key is not registered: " + transformKey + "."));
    return
end
if ~ismember(mapped.value_type, ["real", "integer"])
    mapped.status = "invalid";
    issues = appendIssue(issues, makeIssue("error", "TRANSFORM_FAILED", ...
        location, "A numeric transform cannot be applied to value type " + ...
        mapped.value_type + "."));
    return
end
numericValue = mapped.value_real;
if mapped.value_type == "integer"
    numericValue = mapped.value_integer;
end
[normalized, report] = vawlume.source_mapping.applyTransform(numericValue, transformKey);
if ~report.is_valid || ~isfinite(double(normalized))
    mapped.status = "invalid";
    issues = appendIssue(issues, makeIssue("error", "TRANSFORM_FAILED", ...
        location, "Declared transform failed for source value."));
    return
end
mapped.value_type = "real";
mapped.value_real = double(normalized);
mapped.value_integer = NaN;
end

function [mapped, issues] = invalidValue(mapped, issues, location, message)
mapped.value_type = "invalid";
mapped.status = "invalid";
issues = appendIssue(issues, makeIssue("error", "TYPE_COERCION_FAILED", ...
    location, message + " Received '" + mapped.raw_value + "'."));
end

function [number, ok] = finiteNumber(value)
if isnumeric(value) || islogical(value)
    number = double(value);
elseif isstring(value) || ischar(value) || iscellstr(value)
    number = str2double(string(value));
else
    number = NaN;
end
ok = isscalar(number) && isfinite(number);
end

function [value, ok] = logicalScalar(raw)
value = false;
ok = true;
if islogical(raw) && isscalar(raw)
    value = raw;
elseif isnumeric(raw) && isscalar(raw) && ismember(double(raw), [0, 1])
    value = logical(raw);
else
    token = lower(strtrim(sourceRawToken(raw)));
    if ismember(token, ["true", "yes", "1"])
        value = true;
    elseif ismember(token, ["false", "no", "0"])
        value = false;
    else
        ok = false;
    end
end
end

function tf = isMissingValue(value, rule)
tf = isempty(value);
if ~tf
    try
        mask = ismissing(value);
        tf = isscalar(mask) && mask;
    catch
    end
end
if ~tf && isnumeric(value) && isscalar(value)
    tf = isnan(value);
end
if tf || ~isstruct(rule) || ~isfield(rule, "missing_value_policy")
    return
end
policy = rule.missing_value_policy;
token = strtrim(sourceRawToken(value));
if isfield(policy, "blank_is_missing") && logical(policy.blank_is_missing) && ...
        strlength(token) == 0
    tf = true;
    return
end
if ~isfield(policy, "missing_tokens")
    return
end
tokens = normalizeText(policy.missing_tokens);
caseSensitive = true;
if isfield(policy, "case_sensitive")
    caseSensitive = logical(policy.case_sensitive);
end
if ~caseSensitive
    token = lower(token);
    tokens = lower(tokens);
end
tf = ismember(token, tokens);
end

function values = normalizeText(raw)
if iscell(raw)
    values = strings(numel(raw), 1);
    for index = 1:numel(raw)
        values(index) = string(raw{index});
    end
else
    values = string(raw(:));
end
end

function value = ruleText(rule, field)
value = "";
if isstruct(rule) && isfield(rule, char(field)) && ~isempty(rule.(char(field)))
    try
        candidate = string(rule.(char(field)));
        if isscalar(candidate) && ~ismissing(candidate)
            value = candidate;
        end
    catch
    end
end
end

function issues = appendIssue(issues, issue)
if isempty(issues)
    issues = issue;
else
    issues(end + 1) = issue;
end
end
