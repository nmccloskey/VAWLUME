function values = normalizeTextSequence(rawValue)
%NORMALIZETEXTSEQUENCE Normalize text scalar/list values to a string column.
if iscell(rawValue)
    values = strings(numel(rawValue), 1);
    for index = 1:numel(rawValue)
        values(index) = string(rawValue{index});
    end
elseif isstring(rawValue) || ischar(rawValue) || iscellstr(rawValue)
    values = string(rawValue(:));
else
    values = strings(0, 1);
end
values(ismissing(values)) = "";
values = values(strlength(values) > 0);
end
