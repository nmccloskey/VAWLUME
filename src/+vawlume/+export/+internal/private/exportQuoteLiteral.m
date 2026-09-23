function quoted = exportQuoteLiteral(value)
%EXPORTQUOTELITERAL Quote a value as an SQLite string literal.
%
% Used where SQLite takes a name as a string argument rather than an
% identifier, as in pragma_table_info('<object>').

arguments
    value string
end

quoted = "'" + replace(value, "'", "''") + "'";
end
