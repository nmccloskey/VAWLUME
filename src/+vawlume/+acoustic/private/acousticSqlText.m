function value = acousticSqlText(raw)
%ACOUSTICSQLTEXT Quote one present scalar text value for inline SQL.
raw = string(raw);
if ~isscalar(raw) || ismissing(raw)
    error("vawlume:acoustic:InvalidSelector", ...
        "SQL text selectors must be present scalar strings.");
end
value = "'" + replace(raw, "'", "''") + "'";
end
