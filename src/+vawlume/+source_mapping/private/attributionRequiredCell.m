function [value, ok] = attributionRequiredCell(tbl, field, row)
%ATTRIBUTIONREQUIREDCELL One trimmed text cell, and whether it is present.
%
% A column the table does not have, a missing value and an empty string all read
% as not present. The value is never invented.
value = "";
ok = false;
name = string(field);
if ~ismember(name, string(tbl.Properties.VariableNames))
    return
end
raw = tbl.(name)(row);
value = strtrim(string(raw));
ok = strlength(value) > 0 && ~ismissing(value);
end
