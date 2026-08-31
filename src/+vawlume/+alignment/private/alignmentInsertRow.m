function id = alignmentInsertRow(conn, tableName, values, idColumn)
%ALIGNMENTINSERTROW Insert one scalar structured row and optionally return its ID.

if nargin < 4
    idColumn = "";
end
names = string(fieldnames(values));
for name = names'
    value = values.(name);
    if (isstring(value) || ischar(value)) && strlength(string(value)) == 0
        values = rmfield(values, char(name));
    end
end
names = fieldnames(values);
row = struct();
for index = 1:numel(names)
    value = values.(names{index});
    if isstring(value) || ischar(value) || iscellstr(value)
        row.(names{index}) = {char(string(value))};
    else
        row.(names{index}) = double(value);
    end
end
sqlwrite(conn, char(tableName), struct2table(row, "AsArray", true));
if strlength(idColumn) == 0
    id = NaN;
    return
end
stored = fetch(conn, "SELECT last_insert_rowid() AS " + idColumn);
id = double(stored.(idColumn)(1));
end
