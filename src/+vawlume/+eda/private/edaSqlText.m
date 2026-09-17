function value = edaSqlText(raw)
%EDASQLTEXT Quote one scalar string for inclusion in a SQL literal.
raw = string(raw);
if ~isscalar(raw) || ismissing(raw) || strlength(strtrim(raw)) == 0
    error("vawlume:eda:SelectorInvalid", ...
        "SQL text selectors must be nonempty present scalar strings.");
end
value = "'" + replace(strtrim(raw), "'", "''") + "'";
end
