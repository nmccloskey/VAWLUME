function [nativeValue, secondsValue, issue] = normalizeTimeValue(value, nativeUnit, location)
%NORMALIZETIMEVALUE Validate a finite native timestamp and normalize to seconds.
nativeValue = NaN;
secondsValue = NaN;
issue = [];

if isnumeric(value) || islogical(value)
    candidate = double(value);
elseif isstring(value) || ischar(value) || iscellstr(value)
    candidate = str2double(string(value));
else
    candidate = NaN;
end
if ~isscalar(candidate) || ~isfinite(candidate)
    issue = makeIssue("error", "TIMESTAMP_INVALID", location, ...
        "Timestamp must be a finite numeric scalar; received '" + sourceRawToken(value) + "'.");
    return
end

nativeValue = candidate;
switch lower(string(nativeUnit))
    case {"s", "sec", "second", "seconds"}
        secondsValue = candidate;
    case {"ms", "millisecond", "milliseconds"}
        [secondsValue, report] = vawlume.source_mapping.applyTransform(candidate, "ms_to_s");
        if ~report.is_valid
            issue = makeIssue("error", "TIME_UNIT_UNSUPPORTED", location, ...
                "Timestamp could not be normalized from unit " + string(nativeUnit) + ".");
        end
    otherwise
        issue = makeIssue("error", "TIME_UNIT_UNSUPPORTED", location, ...
            "Unsupported native time unit: " + string(nativeUnit) + ".");
end
end
