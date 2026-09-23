function tests = test_export_csv_fidelity
% The CSV representation contract (contract §E), proved by reading the written
% bytes back.
%
% Files are read with a small RFC 4180 parser local to this test, not with
% readtable. The parser keeps what readtable cannot: whether a field was quoted.
% That is the whole NULL/empty distinction. SQL NULL is a bare empty field and
% empty text is "". A reader that folded them together could not tell a passing
% exporter from a failing one.
%
% Every value is written as text. The guarantee is the value's exact text plus
% the stated representation, not a SQLite type (§E.5). REALs are therefore
% checked by parsing the text back to a double and comparing bit patterns
% against the value SQLite holds.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
testCase.addTeardown(@() rmpath(fullfile(repoRoot, "src")));
end

function setup(testCase)
workspace = string(tempname);
mkdir(workspace);
testCase.addTeardown(@() rmdir(workspace, "s"));
dbFile = fullfile(workspace, "probe.sqlite");
conn = sqlite(char(dbFile), "create");
execute(conn, 'CREATE TABLE probe (id INTEGER PRIMARY KEY, t TEXT, r REAL, i INTEGER, b BLOB)');
execute(conn, 'CREATE TABLE awkward ("end" TEXT, "col with space" TEXT, "we""ird" TEXT, "a,b" TEXT)');
execute(conn, 'CREATE TABLE empty_object (alpha TEXT, beta REAL)');
execute(conn, 'CREATE TABLE all_null (id INTEGER PRIMARY KEY, note TEXT, score REAL)');
execute(conn, 'INSERT INTO all_null (id) VALUES (1), (2)');
execute(conn, 'INSERT INTO awkward VALUES (''x'', ''y'', ''z'', ''w'')');
close(conn);
testCase.TestData.workspace = workspace;
testCase.TestData.dbFile = dbFile;
end

% --- text ---------------------------------------------------------------------

function testTextSurvivesExactly(testCase)
values = [ ...
    "plain"; "comma, inside"; "quote "" inside"; "line" + newline + "feed"; ...
    "carriage" + char([13 10]) + "return"; "tab" + char(9) + "inside"; ...
    "  padded  "; "é μ 漢字 😀"; "N"; "V"; "007"; "1e5"; ...
    "{""rule"":""one_to_one_temporal_overlap"",""n"":[1,2]}"];
rows = insertText(testCase, values);
[header, records] = exportAndParse(testCase, "probe");
verifyEqual(testCase, [header.text], ["id", "t", "r", "i", "b"]);
for k = 1:numel(values)
    field = records{rows(k)}(2);
    verifyTrue(testCase, field.quoted, "Text must be quoted: " + values(k));
    verifyEqual(testCase, field.text, values(k));
end
end

function testNullAndEmptyTextStayDistinct(testCase)
execute(openWritable(testCase), "INSERT INTO probe (id, t) VALUES (1, NULL), (2, '')");
[~, records] = exportAndParse(testCase, "probe");
verifyFalse(testCase, records{1}(2).quoted, "NULL must be a bare empty field.");
verifyEqual(testCase, records{1}(2).text, "");
verifyTrue(testCase, records{2}(2).quoted, "Empty text must be written as """".");
verifyEqual(testCase, records{2}(2).text, "");
% Every NULL column of the row is bare, not only the text one.
verifyFalse(testCase, any([records{1}(3:5).quoted]));
end

function testAColumnNullInEveryRowIsRead(testCase)
% The defect that governs the design (contract §E.1): fetch throws on a column
% that is NULL in every row. The projection must read it anyway.
[header, records] = exportAndParse(testCase, "all_null");
verifyEqual(testCase, [header.text], ["id", "note", "score"]);
verifyEqual(testCase, numel(records), 2);
for k = 1:2
    verifyFalse(testCase, any([records{k}(2:3).quoted]));
end
end

% --- numbers -----------------------------------------------------------------

function testIntegersAreExactAcrossTheInt64Range(testCase)
execute(openWritable(testCase), "INSERT INTO probe (id, i) VALUES " + ...
    "(1, 9223372036854775807), (2, -9223372036854775808), (3, 0), (4, -1)");
[~, records] = exportAndParse(testCase, "probe");
expected = ["9223372036854775807", "-9223372036854775808", "0", "-1"];
for k = 1:4
    verifyEqual(testCase, records{k}(4).text, expected(k));
end
end

function testRealsRoundTripBitExactly(testCase)
% CAST(real AS TEXT) keeps 15 significant digits and loses precision;
% printf('%!.17g') does not (contract §E.3). Compared bit for bit against the
% double SQLite hands MATLAB natively.
literals = ["0.1", "1.2345678901234567e-5", "1e308", "4.9406564584124654e-324", ...
    "-2.5", "3.0", "123456789.12345678", "2.2250738585072014e-308"];
conn = openWritable(testCase);
for k = 1:numel(literals)
    execute(conn, "INSERT INTO probe (id, r) VALUES (" + k + ", " + literals(k) + ")");
end
native = fetch(conn, "SELECT r FROM probe ORDER BY id");
[~, records] = exportAndParse(testCase, "probe");
for k = 1:numel(literals)
    parsed = str2double(records{k}(3).text);
    verifyEqual(testCase, typecast(parsed, "uint64"), typecast(double(native.r(k)), "uint64"), ...
        "REAL " + literals(k) + " was written as " + records{k}(3).text);
end
end

function testNegativeZeroLosesItsSignAsDocumented(testCase)
% Accepted limitation (contract §E.3): no VAWLUME column gives the sign of zero
% any meaning. Asserted so a change in behaviour is noticed either way.
execute(openWritable(testCase), "INSERT INTO probe (id, r) VALUES (1, -0.0)");
[~, records] = exportAndParse(testCase, "probe");
verifyEqual(testCase, str2double(records{1}(3).text), 0);
end

% --- BLOB ----------------------------------------------------------------------

function testBlobsAreUppercaseHex(testCase)
execute(openWritable(testCase), "INSERT INTO probe (id, b) VALUES " + ...
    "(1, X'00FF10ab'), (2, X''), (3, NULL)");
% A BLOB stored in a TEXT column is still a BLOB: storage class, not declared
% type, decides.
execute(openWritable(testCase), "INSERT INTO probe (id, t) VALUES (4, X'CAFE')");
[~, records] = exportAndParse(testCase, "probe");
verifyEqual(testCase, records{1}(5).text, "00FF10AB");
verifyTrue(testCase, records{2}(5).quoted, "A zero-length BLOB is written as """".");
verifyEqual(testCase, records{2}(5).text, "");
verifyFalse(testCase, records{3}(5).quoted);
verifyEqual(testCase, records{4}(2).text, "CAFE");
end

% --- shape ----------------------------------------------------------------------

function testAZeroRowObjectWritesItsHeaderAndNothingElse(testCase)
path = exportOnly(testCase, "empty_object");
verifyEqual(testCase, readBytes(path), uint8(['alpha,beta' 13 10]));
end

function testAwkwardColumnNamesArePreservedInTheHeader(testCase)
[header, records] = exportAndParse(testCase, "awkward");
verifyEqual(testCase, [header.text], ["end", "col with space", "we""ird", "a,b"]);
verifyEqual(testCase, [records{1}.text], ["x", "y", "z", "w"]);
end

function testEncodingIsUtf8WithoutBomAndRecordsEndInCrlf(testCase)
insertText(testCase, "é" + newline + "μ");
bytes = readBytes(exportOnly(testCase, "probe"));
verifyFalse(testCase, numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191])), ...
    "No byte-order mark.");
verifyEqual(testCase, bytes(end - 1:end), uint8([13 10]));
% é and μ as UTF-8, with the embedded LF kept as a bare LF inside the quotes.
verifyNotEmpty(testCase, strfind(bytes, uint8([34 195 169 10 206 188 34])));
end

function testTheWriterRefusesDataThatIsNotTheCanonicalHeader(testCase)
data = table(["a"; "b"], VariableNames="x");
verifyError(testCase, @() vawlume.export.internal.writeCsv(data, "y", ...
    fullfile(testCase.TestData.workspace, "refused.csv")), "vawlume:export:HeaderMismatch");
verifyError(testCase, @() vawlume.export.internal.writeCsv(table([1; 2], VariableNames="x"), ...
    "x", fullfile(testCase.TestData.workspace, "refused.csv")), "vawlume:export:HeaderMismatch");
verifyFalse(testCase, isfile(fullfile(testCase.TestData.workspace, "refused.csv")));
end

% --- helpers ----------------------------------------------------------------------

function rows = insertText(testCase, values)
conn = openWritable(testCase);
rows = zeros(numel(values), 1);
for k = 1:numel(values)
    execute(conn, "INSERT INTO probe (id, t) VALUES (" + k + ", '" + ...
        replace(values(k), "'", "''") + "')");
    rows(k) = k;
end
end

function conn = openWritable(testCase)
if ~isfield(testCase.TestData, "conn")
    testCase.TestData.conn = sqlite(char(testCase.TestData.dbFile));
    testCase.addTeardown(@() closeWritable(testCase));
end
conn = testCase.TestData.conn;
end

function closeWritable(testCase)
if isfield(testCase.TestData, "conn")
    close(testCase.TestData.conn);
    testCase.TestData = rmfield(testCase.TestData, "conn");
end
end

function path = exportOnly(testCase, objectName)
% The writable connection is closed first, so the export reads through its own
% read-only connection exactly as the core does.
closeWritable(testCase);
conn = sqlite(char(testCase.TestData.dbFile), "readonly");
closer = onCleanup(@() close(conn));
columns = fetch(conn, "SELECT CAST(name AS TEXT) AS name FROM pragma_table_info('" + ...
    objectName + "') ORDER BY cid");
columns = string(columns.name)';
data = vawlume.export.internal.readObject(conn, objectName, columns);
path = fullfile(testCase.TestData.workspace, objectName + ".csv");
vawlume.export.internal.writeCsv(data, columns, path);
end

function [header, records] = exportAndParse(testCase, objectName)
parsed = parseCsv(readBytes(exportOnly(testCase, objectName)));
header = parsed{1};
records = parsed(2:end);
end

function bytes = readBytes(path)
fid = fopen(path, "r");
closer = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "uint8=>uint8")';
end

function records = parseCsv(bytes)
% RFC 4180 with CRLF record terminators. Each field records its text and
% whether it was quoted; only that flag separates NULL from "".
text = native2unicode(bytes, "UTF-8");
records = {};
fields = struct("text", {}, "quoted", {});
field = "";
inQuotes = false;
wasQuoted = false;
k = 1;
n = numel(text);
while k <= n
    ch = text(k);
    if inQuotes
        if ch == '"' && k < n && text(k + 1) == '"'
            field = field + '"';
            k = k + 2;
        elseif ch == '"'
            inQuotes = false;
            k = k + 1;
        else
            field = field + ch;
            k = k + 1;
        end
    elseif ch == '"'
        inQuotes = true;
        wasQuoted = true;
        k = k + 1;
    elseif ch == ','
        fields(end + 1) = struct("text", field, "quoted", wasQuoted); %#ok<AGROW>
        field = "";
        wasQuoted = false;
        k = k + 1;
    elseif ch == char(13) && k < n && text(k + 1) == newline
        fields(end + 1) = struct("text", field, "quoted", wasQuoted); %#ok<AGROW>
        records{end + 1} = fields; %#ok<AGROW>
        fields = struct("text", {}, "quoted", {});
        field = "";
        wasQuoted = false;
        k = k + 2;
    else
        field = field + ch;
        k = k + 1;
    end
end
if inQuotes || ~isempty(fields) || strlength(field) > 0
    error("test:parse:UnterminatedRecord", "The file does not end with a complete CRLF-terminated record.");
end
end
