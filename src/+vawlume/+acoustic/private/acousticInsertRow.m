function id = acousticInsertRow(conn, tableName, values, idColumn)
%ACOUSTICINSERTROW Insert one scalar structured row and return its SQLite ID.

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
rows = fetch(conn, "SELECT last_insert_rowid() AS " + idColumn);
id = double(rows.(idColumn)(1));
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
