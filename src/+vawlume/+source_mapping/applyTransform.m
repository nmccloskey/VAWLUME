function [transformed, report] = applyTransform(value, transformKey)
%APPLYTRANSFORM Apply a whitelisted source_mapping transform to one value.
%
% Transform keys are stable profile declarations. This function never
% dispatches arbitrary function names from profile text.

arguments
    value
    transformKey (1,1) string
end

transformKey = normalizeTransformKey(transformKey);
report = emptyTransformReport(transformKey);
transformed = [];

if ~ismember(transformKey, supportedTransformKeys())
    report = addTransformIssue(report, "error", "TRANSFORM_UNKNOWN", ...
        "transform", "Unknown source_mapping transform key: " + transformKey + ".");
    report = finalizeTransformReport(report);
    return
end

if transformKey == "identity"
    transformed = value;
    report.status = "ok";
    report.output_value = value;
    report = finalizeTransformReport(report);
    return
end

[numericValue, status, message] = numericScalar(value);
if status == "missing"
    report.status = "missing";
    report = addTransformIssue(report, "info", "TRANSFORM_INPUT_MISSING", ...
        "value", "Transform input is explicitly missing.");
    report = finalizeTransformReport(report);
    return
elseif status ~= "ok"
    report.status = "invalid";
    report = addTransformIssue(report, "error", "TRANSFORM_INPUT_NOT_NUMERIC", ...
        "value", message);
    report = finalizeTransformReport(report);
    return
end

switch transformKey
    case {"kHz_to_Hz", "kHz_per_s_to_Hz_per_s"}
        transformed = numericValue * 1000;
    case "ms_to_s"
        transformed = numericValue / 1000;
end

report.status = "ok";
report.output_value = transformed;
report = finalizeTransformReport(report);
end

function key = normalizeTransformKey(key)
key = string(key);
if strlength(key) == 0
    key = "identity";
end
end

function report = emptyTransformReport(transformKey)
report = struct();
report.transform_key = string(transformKey);
report.status = "not_run";
report.output_value = [];
report.issues = emptyIssueArray();
report.issue_table = sourceMappingIssuesToTable(report.issues);
report.warning_count = 0;
report.error_count = 0;
report.is_valid = false;
end

function report = addTransformIssue(report, severity, code, profileLocation, message)
issue = makeIssue(severity, code, profileLocation, message);
if isempty(report.issues)
    report.issues = issue;
else
    report.issues(numel(report.issues) + 1) = issue;
end
end

function report = finalizeTransformReport(report)
report.issue_table = sourceMappingIssuesToTable(report.issues);
report.warning_count = issueCount(report.issues, "warning");
report.error_count = issueCount(report.issues, "error");
report.is_valid = report.error_count == 0;
end

function count = issueCount(issues, severity)
count = 0;
for index = 1:numel(issues)
    if string(issues(index).severity) == severity
        count = count + 1;
    end
end
end

function [number, status, message] = numericScalar(value)
number = NaN;
status = "ok";
message = "";

if isempty(value)
    status = "missing";
    return
end

try
    if ismissing(value)
        status = "missing";
        return
    end
catch
end

if isnumeric(value) || islogical(value)
    if ~isscalar(value)
        status = "invalid";
        message = "Transform input must be a scalar numeric value.";
        return
    end
    if isnan(double(value))
        status = "missing";
        return
    end
    number = double(value);
    return
end

if isstring(value) || ischar(value) || iscellstr(value)
    text = string(value);
    if ~isscalar(text) || ismissing(text) || strlength(strtrim(text)) == 0
        status = "missing";
        return
    end
    number = str2double(text);
    if isnan(number)
        status = "invalid";
        message = "Transform input text could not be converted to a numeric scalar: " + text + ".";
    end
    return
end

status = "invalid";
message = "Transform input type is not supported for numeric unit conversion.";
end
