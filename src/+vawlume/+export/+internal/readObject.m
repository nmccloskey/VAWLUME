function data = readObject(conn, objectName, columns)
%READOBJECT Read one relational object faithfully, every value as text.
%
%   DATA = vawlume.export.internal.readObject(CONN, OBJECTNAME, COLUMNS)
%
%   Returns a table whose variables are COLUMNS, in that order and named
%   exactly, and whose every value is a string: the value's exact text, "" for
%   empty text or a zero-length BLOB, and <missing> for SQL NULL.
%
%   WHY EVERY COLUMN GOES THROUGH A TEXT PROJECTION. MATLAB's fetch throws when
%   a result column is NULL in every returned row, and a plain SELECT * was
%   measured to fail on half the populated objects of the repository's own
%   fixture (contract §E.1). Each column is therefore read as
%
%     IFNULL('V' || <text of the value>, 'N')
%
%   so nothing NULL or empty ever reaches MATLAB. 'N' means NULL; 'V' followed
%   by the text means that text (contract §E.2). The marker must be non-empty
%   because SQLite's empty string also returns as <missing>. The text of a value
%   depends on its storage class:
%
%     REAL     printf('%!.17g') -- bit-exact; CAST loses precision at 15 digits
%     BLOB     uppercase hex()  -- a natively fetched BLOB makes writetable
%              invent columns
%     INTEGER, TEXT  CAST AS TEXT -- exact
%
%   Columns are aliased c1..cN and mapped back by position, so a column name
%   that MATLAB would alter, or that is an SQL keyword, cannot change the
%   result. COLUMNS comes from the committed structure, never from a caller, and
%   every identifier is quoted.
%
%   A zero-row object returns a zero-row table with the same variables. The
%   header comes from COLUMNS, not from the fetched result, because fetch
%   reports a zero-row result as double columns.

arguments
    conn
    objectName (1,1) string
    columns (1,:) string
end

count = numel(columns);
if count == 0
    error("vawlume:export:NoColumns", "%s has no columns to read.", objectName);
end

projections = strings(1, count);
for k = 1:count
    column = exportQuoteIdentifier(columns(k));
    projections(k) = "IFNULL('V' || CASE typeof(" + column + ") " + ...
        "WHEN 'real' THEN printf('%!.17g', " + column + ") " + ...
        "WHEN 'blob' THEN hex(" + column + ") " + ...
        "ELSE CAST(" + column + " AS TEXT) END, 'N') AS c" + k;
end
sql = "SELECT " + strjoin(projections, ", ") + " FROM " + exportQuoteIdentifier(objectName);

fetched = fetch(conn, sql);

rowCount = height(fetched);
values = strings(rowCount, count);
for k = 1:count
    if rowCount == 0
        break
    end
    raw = string(fetched.("c" + k));
    decoded = extractAfter(raw, 1);
    decoded(raw == "N") = missing;
    values(:, k) = decoded;
end

data = table('Size', [rowCount, count], ...
    'VariableTypes', repmat("string", 1, count), ...
    'VariableNames', cellstr(columns));
for k = 1:count
    data.(k) = values(:, k);
end
end
