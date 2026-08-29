function readResult = deepsqueakReadExportTable(artifactPath, spec, sheetOverride)
%DEEPSQUEAKREADEXPORTTABLE Read one DeepSqueak call-statistics workbook.
%
% This is the only function in the DeepSqueak import path that touches the
% workbook. It performs file mechanics only: accessibility, deterministic sheet
% selection, and a name-preserving table read. It does not rename columns,
% convert units, apply transforms, or interpret any field semantically.

arguments
    artifactPath (1,1) string
    spec (1,1) struct
    sheetOverride (1,1) string = ""
end

if ~isfile(artifactPath)
    error("vawlume:ingest:DeepSqueakArtifactNotFound", ...
        "DeepSqueak export file does not exist: %s", artifactPath);
end

assertSupportedFormat(artifactPath, spec);

sheets = workbookSheetNames(artifactPath);
[sheetName, sheetIndex] = selectSheet(sheets, spec, sheetOverride, artifactPath);
tbl = readSheet(artifactPath, sheetName, spec);

readResult = struct();
readResult.table = tbl;
readResult.sheet_name = sheetName;
readResult.sheet_index = sheetIndex;
readResult.sheet_names = sheets;
readResult.sheet_selection_rule = sheetSelectionRule(spec, sheetOverride);
readResult.header_row = spec.header_row;
readResult.row_count = height(tbl);
readResult.column_count = width(tbl);
readResult.source_columns = string(tbl.Properties.VariableNames)';
end

function assertSupportedFormat(artifactPath, spec)
[~, ~, extension] = fileparts(artifactPath);
extension = lower(erase(string(extension), "."));
expected = lower(string(spec.file_format));
if strlength(expected) == 0
    return
end
if extension ~= expected
    error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
        ['DeepSqueak artifact ''%s'' is declared as format ''%s'' but the ' ...
        'supplied file has extension ''%s'': %s'], ...
        spec.artifact_key, expected, extension, artifactPath);
end
end

function sheets = workbookSheetNames(artifactPath)
try
    sheets = string(sheetnames(artifactPath));
catch exception
    error("vawlume:ingest:DeepSqueakArtifactUnreadable", ...
        "Could not read workbook structure from %s: %s", ...
        artifactPath, exception.message);
end
sheets = sheets(:);
if isempty(sheets)
    error("vawlume:ingest:DeepSqueakArtifactUnreadable", ...
        "Workbook contains no readable sheet: %s", artifactPath);
end
end

function [sheetName, sheetIndex] = selectSheet(sheets, spec, sheetOverride, artifactPath)
if strlength(sheetOverride) > 0
    matches = find(sheets == sheetOverride, 1);
    if isempty(matches)
        error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
            "Requested sheet '%s' is not present in %s. Available sheets: %s.", ...
            sheetOverride, artifactPath, strjoin(sheets, ", "));
    end
    sheetIndex = matches;
    sheetName = sheets(sheetIndex);
    return
end

switch lower(string(spec.sheet_selector))
    case "first_sheet"
        sheetIndex = 1;
        sheetName = sheets(1);
    otherwise
        error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
            ['Profile declares sheet_selector ''%s'' for artifact ''%s'', which ' ...
            'this adapter does not implement. Supply an explicit Sheet instead.'], ...
            spec.sheet_selector, spec.artifact_key);
end
end

function rule = sheetSelectionRule(spec, sheetOverride)
if strlength(sheetOverride) > 0
    rule = "caller_supplied_sheet";
else
    rule = "profile_" + lower(string(spec.sheet_selector));
end
end

function tbl = readSheet(artifactPath, sheetName, spec)
try
    options = detectImportOptions(artifactPath, Sheet=char(sheetName), ...
        VariableNamingRule="preserve");
    options.VariableNamesRange = "A" + string(spec.header_row);
    options.DataRange = "A" + string(spec.header_row + 1);
    assertDistinctHeaderLabels(artifactPath, sheetName, spec, ...
        numel(options.VariableNames));
    tbl = readtable(artifactPath, options);
catch exception
    if startsWith(string(exception.identifier), "vawlume:")
        rethrow(exception);
    end
    error("vawlume:ingest:DeepSqueakArtifactUnreadable", ...
        "Could not read sheet '%s' of %s: %s", ...
        sheetName, artifactPath, exception.message);
end

if width(tbl) == 0
    error("vawlume:ingest:DeepSqueakArtifactUnreadable", ...
        ['Sheet ''%s'' of %s yielded no columns at header row %d. Check the ' ...
        'sheet selection and header row for this export.'], ...
        sheetName, artifactPath, spec.header_row);
end
end

function assertDistinctHeaderLabels(artifactPath, sheetName, spec, columnCount)
%ASSERTDISTINCTHEADERLABELS Reject repeated header labels at the source.
%
% MATLAB silently uniquifies repeated table variable names, so a genuinely
% ambiguous export would otherwise be hidden behind a fabricated label such as
% "Tonality_1". The header row is therefore inspected as written.
%
% The range is bounded by the detected column count. Reading an open-ended row
% costs an order of magnitude more time, and a full-width range costs two, so
% the bound is load-bearing rather than cosmetic.

if columnCount < 2
    return
end

headerRange = "A" + string(spec.header_row) + ":" + ...
    columnLetters(columnCount) + string(spec.header_row);
try
    headerCells = readcell(artifactPath, Sheet=char(sheetName), Range=char(headerRange));
catch
    return
end

labels = strings(0, 1);
for index = 1:numel(headerCells)
    cellValue = headerCells{index};
    if ismissing(cellValue)
        continue
    end
    try
        labels(end + 1, 1) = strtrim(string(cellValue)); %#ok<AGROW>
    catch
        continue
    end
end
labels = labels(strlength(labels) > 0);
if numel(labels) < 2
    return
end

sorted = sort(labels);
repeated = unique(sorted(sorted(1:end - 1) == sorted(2:end)));
if isempty(repeated)
    return
end
error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
    "Sheet '%s' of %s repeats source column label(s): %s.", ...
    sheetName, artifactPath, strjoin(repeated, ", "));
end

function letters = columnLetters(columnIndex)
letters = "";
while columnIndex > 0
    remainder = mod(columnIndex - 1, 26);
    letters = string(char('A' + remainder)) + letters;
    columnIndex = floor((columnIndex - remainder - 1) / 26);
end
end
