function value = sourceTableValue(tbl, columnName, rowIndex)
%SOURCETABLEVALUE Return one scalar-like value from a MATLAB table column.
column = tbl.(char(columnName));
if iscell(column)
    value = column{rowIndex};
else
    value = column(rowIndex, :);
end
if iscategorical(value)
    value = string(value);
end
end
