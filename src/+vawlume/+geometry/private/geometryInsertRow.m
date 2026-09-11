function id = geometryInsertRow(conn, tableName, values, idColumn)
%GEOMETRYINSERTROW Insert one scalar structured row and return its SQLite ID.
%
% Empty optional text is omitted from the insert rather than written as '', so
% an unsupplied description stores NULL. That matches insertIntakeRow's rule in
% the ingest layer, and it is why every read in this package wraps nullable text
% in IFNULL before fetching: MATLAB's Database Toolbox raises "Unexpected NULL"
% while building a result set, before any MATLAB-side normalization could run.
%
% Numeric fields are written as supplied. A caller that wants a NULL number omits
% the field entirely rather than passing NaN, because NaN would be written as a
% value.

if nargin < 4
    idColumn = "";
end

values = stripEmptyOptionalText(values);
names = fieldnames(values);
rowStruct = struct();
for index = 1:numel(names)
    value = values.(names{index});
    if isstring(value) || ischar(value) || iscellstr(value)
        rowStruct.(names{index}) = {char(string(value))};
    elseif islogical(value)
        rowStruct.(names{index}) = double(value);
    else
        rowStruct.(names{index}) = double(value);
    end
end

sqlwrite(conn, char(tableName), struct2table(rowStruct, "AsArray", true));
if strlength(idColumn) == 0
    id = NaN;
    return
end
result = fetch(conn, "SELECT last_insert_rowid() AS " + idColumn);
id = double(result.(idColumn)(1));
end

function values = stripEmptyOptionalText(values)
names = string(fieldnames(values));
for name = names'
    value = values.(name);
    if (isstring(value) || ischar(value)) && strlength(string(value)) == 0
        values = rmfield(values, char(name));
    end
end
end
