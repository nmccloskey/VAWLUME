function data = exportReadCsv(path)
%EXPORTREADCSV Read a CSV this package wrote, exactly, as an all-string table.
%
% The inverse of writeCsv's representation: RFC 4180 fields, CRLF records, a
% quoted field is text (possibly empty), and an unquoted empty field is NULL,
% returned as <missing>. A newline inside a quoted field stays inside the value.
%
% Used to check a staged package and to recognize a previous package before it
% is replaced. readtable is not used, because it re-types values and does not
% keep the quoted/unquoted distinction that separates "" from NULL.
%
% Every field is matched, with the delimiter that ends it, by one regular
% expression. The matches must tile the whole file exactly, or the file is
% refused as malformed, so nothing between two matches can be skipped silently.

arguments
    path (1,1) string
end

fid = fopen(path, "r");
if fid < 0
    error("vawlume:export:PackageInvalid", "Cannot read %s.", path);
end
closer = onCleanup(@() fclose(fid));
text = native2unicode(fread(fid, Inf, "uint8=>uint8")', "UTF-8");
clear closer

pattern = '("(?:[^"]|"")*"|[^,"\r\n]*)(,|\r\n)';
[matches, tokens] = regexp(text, pattern, "match", "tokens");
if isempty(matches) || sum(cellfun(@numel, matches)) ~= numel(text)
    error("vawlume:export:PackageInvalid", "%s is not a well-formed CRLF-terminated CSV.", path);
end

values = strings(1, numel(matches));
delimiters = strings(1, numel(matches));
for k = 1:numel(matches)
    field = string(tokens{k}{1});
    delimiters(k) = string(tokens{k}{2});
    if startsWith(field, '"')
        values(k) = replace(extractBetween(field, 2, strlength(field) - 1), '""', '"');
    elseif field == ""
        values(k) = missing;
    else
        values(k) = field;
    end
end
ends = find(delimiters == sprintf("\r\n"));

starts = [1, ends(1:end - 1) + 1];
header = values(starts(1):ends(1));
width = numel(header);
rows = strings(numel(ends) - 1, width);
for r = 2:numel(ends)
    record = values(starts(r):ends(r));
    if numel(record) ~= width
        error("vawlume:export:PackageInvalid", "%s: record %d has %d fields, not %d.", ...
            path, r, numel(record), width);
    end
    rows(r - 1, :) = record;
end
data = array2table(rows, VariableNames=cellstr(header));
end
