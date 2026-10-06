function [value, ok] = attributionNumericCell(tbl, field, row)
%ATTRIBUTIONNUMERICCELL One finite number exactly as the source carried it.
%
% A numeric cell is passed through unchanged. A text cell is parsed once, by
% str2double, and nothing else happens to it: no rounding, rescaling or
% clamping. Absent, empty, non-numeric and non-finite cells read as not present
% (NaN, false), never as 0.
value = NaN;
ok = false;
name = string(field);
if ~ismember(name, string(tbl.Properties.VariableNames))
    return
end
raw = tbl.(name)(row);
if isnumeric(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
ok = ~isnan(value) && isfinite(value);
end
