function writeCsv(data, columns, path)
%WRITECSV Write one object's values as a canonical CSV file.
%
%   vawlume.export.internal.writeCsv(DATA, COLUMNS, PATH)
%
%   DATA is what vawlume.export.internal.readObject returns: all-string columns
%   with <missing> for SQL NULL. COLUMNS is the canonical header, in order. The
%   writer checks that DATA carries exactly those columns and never rediscovers
%   the schema itself.
%
%   Representation (contract §§E.3-E.4):
%
%     every non-NULL value  double-quoted, inner quotes doubled (RFC 4180)
%     empty text            ""
%     SQL NULL              a bare empty field, so it stays distinct from ""
%     encoding              UTF-8, no byte-order mark
%     record terminator     CRLF; a newline inside a value is kept verbatim
%     header                the canonical column names, quoted only where
%                           RFC 4180 requires it
%
%   QuoteStrings="all" is mandatory. With the default, measured in Part 1, a
%   value containing a newline but no comma is written unquoted and splits its
%   record, and "" and NULL collapse to the same bare field. The line ending is
%   pinned rather than left to the platform, so the file is the same on every OS.
%
%   A zero-row object writes its header and nothing else.

arguments
    data table
    columns (1,:) string
    path (1,1) string
end

actual = string(data.Properties.VariableNames);
if ~isequal(actual, columns)
    error("vawlume:export:HeaderMismatch", ...
        "Refusing to write %s: its data carries columns [%s], not the canonical [%s].", ...
        path, strjoin(actual, ", "), strjoin(columns, ", "));
end
for k = 1:width(data)
    if ~isstring(data.(k))
        error("vawlume:export:HeaderMismatch", ...
            "Refusing to write %s: column ""%s"" is %s, not string.", ...
            path, columns(k), class(data.(k)));
    end
end

writetable(data, path, FileType="text", Delimiter=",", ...
    QuoteStrings="all", Encoding="UTF-8", LineEnding="\r\n", WriteVariableNames=true);
end
