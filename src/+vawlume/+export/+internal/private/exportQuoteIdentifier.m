function quoted = exportQuoteIdentifier(name)
%EXPORTQUOTEIDENTIFIER Quote an SQLite identifier for interpolation into SQL.
%
% Every identifier the exporter interpolates goes through here: wrapped in
% double quotes, with any embedded double quote doubled. Object names are also
% refused upstream unless they match ^[A-Za-z][A-Za-z0-9_]*$, so for them this
% is a second line of defence. Column names come from the committed structure
% rather than from a caller, and quoting keeps a keyword or an unusual column
% name from being read as SQL.

arguments
    name string
end

quoted = """" + replace(name, """", """""") + """";
end
