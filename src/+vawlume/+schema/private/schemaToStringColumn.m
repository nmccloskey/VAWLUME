function values = schemaToStringColumn(value)
%SCHEMATOSTRINGCOLUMN Normalize a decoded JSON string array to a string column.
%
% `jsondecode` returns a JSON array of strings as a cell array of char vectors,
% a single-element array as a 1x1 cell, and an empty array as an empty double.
% A bare JSON string decodes to a char vector with no array wrapper at all.

if isstring(value)
    values = value(:);
elseif ischar(value)
    values = string(value);
elseif iscell(value)
    values = strings(numel(value), 1);
    for k = 1:numel(value)
        values(k) = string(value{k});
    end
elseif isempty(value)
    values = strings(0, 1);
else
    values = string(value(:));
end
end
