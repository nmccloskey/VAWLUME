function tests = test_null_sentinel_convention
%TEST_NULL_SENTINEL_CONVENTION No integer IFNULL sentinel on a REAL column.
%
% VAWLUME reads nullable columns through an IFNULL sentinel, because the Database
% Toolbox raises on any SQL NULL in a result set. The sentinel's TYPE matters:
% the toolbox types a fetched column from its first row, so an integer sentinel
% on a REAL column returns integers for every row in that column whenever the
% first row is the sentinel. A stored 0.001998 then reads back as 0.
%
% That is worse than an error. Zero is a plausible number, and for an uncertainty
% it is the claim of perfect knowledge that "absence propagates as absence, not
% zero" exists to forbid. The defect was found at 4.2, as P4-1, and had been live
% since the alignment layer was written.
%
% This check is non-executing: it reads the schema and the sources and runs no
% query. Its behavioural counterpart is
% test_alignment_transform_application/testMixedSegmentUncertaintySurvivesTheReadBack,
% which exercises the specific failure through the public API.
tests = functiontests({@testNoIntegerSentinelOnARealColumn});
end

function testNoIntegerSentinelOnARealColumn(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
% Add and restore the path here rather than relying on the caller's. Neighbouring
% suites remove src/ in their own teardown, so a test that assumes it is present
% passes alone and errors inside the full suite.
sourcePath = fullfile(repoRoot, "src");
needsPath = ~contains(path, sourcePath);
if needsPath
    addpath(sourcePath);
    cleanupPath = onCleanup(@() rmpath(sourcePath)); %#ok<NASGU>
end
declared = declaredColumnTypes(repoRoot);
offenders = scanForIntegerSentinels(fullfile(repoRoot, "src"), declared, repoRoot);

verifyEmpty(testCase, offenders, ...
    "An integer IFNULL sentinel on a REAL column silently truncates every " + ...
    "real value in that column. Use a real-valued sentinel (-1.0, not -1):" + ...
    newline + strjoin(offenders, newline));
end

% --- helpers --------------------------------------------------------------

function map = declaredColumnTypes(repoRoot)
% Declared types come from a live schema rather than from parsing schema.sql,
% so the check cannot drift from what the database actually creates.
file = string(tempname) + ".sqlite";
conn = sqlite(char(file), "create");
cleanup = onCleanup(@() closeAndDelete(conn, file));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

map = containers.Map("KeyType", "char", "ValueType", "any");
tables = fetch(conn, "SELECT name FROM sqlite_master WHERE type='table'");
for index = 1:height(tables)
    columns = fetch(conn, "SELECT name, type FROM pragma_table_info('" + ...
        string(tables.name(index)) + "')");
    for column = 1:height(columns)
        key = char(lower(string(columns.name(column))));
        declaredType = upper(string(columns.type(column)));
        if isKey(map, key)
            map(key) = unique([map(key), declaredType]);
        else
            map(key) = declaredType;
        end
    end
end
clear cleanup
end

function offenders = scanForIntegerSentinels(sourceRoot, declared, repoRoot)
% A column name shared by a REAL and a non-REAL column is treated as REAL. That
% is deliberate: the false positive costs one character, and the false negative
% is the bug this exists to prevent.
offenders = strings(0, 1);
files = dir(fullfile(sourceRoot, "**", "*.m"));
pattern = "IFNULL\(\s*(?:\w+\.)?(\w+)\s*,\s*(-?\d+)\s*\)";
for index = 1:numel(files)
    path = fullfile(files(index).folder, files(index).name);
    lines = splitlines(string(fileread(path)));
    for lineNumber = 1:numel(lines)
        matches = regexp(lines(lineNumber), pattern, 'tokens');
        for match = 1:numel(matches)
            name = char(lower(string(matches{match}{1})));
            if ~isKey(declared, name), continue, end
            if ~any(contains(declared(name), "REAL")), continue, end
            relative = extractAfter(string(path), strlength(string(repoRoot)) + 1);
            offenders(end+1, 1) = relative + ":" + lineNumber + ...
                " IFNULL(" + string(name) + ", " + string(matches{match}{2}) + ")"; %#ok<AGROW>
        end
    end
end
end

function closeAndDelete(conn, file)
close(conn);
if isfile(file), delete(file); end
end
