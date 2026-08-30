function tbl = alignmentReadSourceTable(path)
%ALIGNMENTREADSOURCETABLE Read one declared external event or anchor table.
%
% Every column is read as text and left exactly as written. Type interpretation
% belongs to the mapping profile, which knows which column is a timestamp and
% what unit it is in; guessing here would silently reinterpret a source the
% profile is responsible for.

[~, ~, extension] = fileparts(string(path));
extension = lower(extension);
if ~ismember(extension, [".csv", ".txt", ".tsv"])
    error("vawlume:ingest:AlignmentSourceUnsupported", ...
        ['Alignment intake reads delimited text tables (.csv, .tsv, .txt); ' ...
        'received %s. Supply the table through the Tables option instead.'], path);
end

options = detectImportOptions(path, TextType="string");
options = setvartype(options, options.VariableNames, "string");
options.ExtraColumnsRule = "addvars";
try
    tbl = readtable(path, options);
catch exception
    error("vawlume:ingest:AlignmentSourceUnreadable", ...
        "Could not read alignment source table %s: %s", path, exception.message);
end
if height(tbl) == 0
    error("vawlume:ingest:AlignmentSourceEmpty", ...
        "Alignment source table %s contains no rows.", path);
end
end
