function result = writeExampleIndex(index, path, options)
%WRITEEXAMPLEINDEX Write and verify the fixed UTF-8 CSV example index.

arguments
    index table
    path (1,1) string
    options.Overwrite (1,1) logical = false
end

expected = edaExampleIndexColumns();
actual = string(index.Properties.VariableNames);
if ~isequal(actual, expected)
    error("vawlume:eda:ExampleIndexColumnsInvalid", ...
        "The example index must contain exactly the 22 contract columns in " + ...
        "their fixed order. Expected: %s.", strjoin(expected, ", "));
end
if isfile(path) && ~options.Overwrite
    error("vawlume:eda:ExampleIndexExists", ...
        "The example index '%s' already exists. Pass Overwrite=true to " + ...
        "replace it explicitly.", path);
end
parent = string(fileparts(path));
if strlength(parent) > 0 && ~isfolder(parent)
    mkdir(parent);
end

writetable(index, path, Delimiter=",", QuoteStrings="all", ...
    Encoding="UTF-8");
roundTrip = readTyped(path, height(index));
if ~tablesEqual(index, roundTrip)
    error("vawlume:eda:ExampleIndexRoundTripFailed", ...
        "The CSV example index did not survive a typed write/read round trip.");
end

result = struct(status="written", path=path, row_count=height(index), ...
    columns=expected, delimiter=",", encoding="UTF-8", ...
    quote_policy="all string fields quoted by writetable", ...
    round_trip_verified=true);
end

function value = readTyped(path, rowCount)
names = edaExampleIndexColumns();
types = repmat("string", 1, numel(names));
numericNames = ["recording_id", "group_start_time_s", "group_end_time_s", ...
    "snippet_window_start_s", "snippet_window_end_s", ...
    "snippet_channel_index"];
types(ismember(names, numericNames)) = "double";
opts = delimitedTextImportOptions(NumVariables=numel(names), ...
    VariableNames=cellstr(names), VariableTypes=cellstr(types), ...
    DataLines=[2, max(rowCount + 1, 2)], Delimiter=",");
opts.VariableNamingRule = "preserve";
value = readtable(path, opts);
end

function tf = tablesEqual(left, right)
if ~isequal(string(left.Properties.VariableNames), ...
        string(right.Properties.VariableNames)) || height(left) ~= height(right)
    tf = false;
    return
end
tf = true;
for name = string(left.Properties.VariableNames)
    a = left.(name);
    b = right.(name);
    if isstring(a)
        a(ismissing(a)) = "";
        b = string(b);
        b(ismissing(b)) = "";
    end
    if ~isequaln(a, b)
        tf = false;
        return
    end
end
end
