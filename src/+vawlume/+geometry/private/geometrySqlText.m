function value = geometrySqlText(raw)
%GEOMETRYSQLTEXT Quote one text value for inline SQL.
raw = string(raw);
if ~isscalar(raw) || ismissing(raw)
    error("vawlume:geometry:InvalidSelector", ...
        "SQL text selectors must be present scalar strings.");
end
value = "'" + replace(raw, "'", "''") + "'";
end
