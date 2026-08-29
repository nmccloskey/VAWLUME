function readResult = mupetReadExportTable(artifactPath, spec, profileDocument)
%MUPETREADEXPORTTABLE Read one MUPET CSV without losing lexical sentinels.
%
% Every profile mapping that declares missing_value_policy is imported as
% string with MATLAB missing-token conversion disabled. All remaining columns
% retain detectImportOptions' inferred types. No field semantics are restated.

arguments
    artifactPath (1,1) string
    spec (1,1) struct
    profileDocument (1,1) struct
end

if ~isfile(artifactPath)
    error("vawlume:ingest:MupetArtifactNotFound", ...
        "MUPET export file does not exist: %s", artifactPath);
end
[~, ~, extension] = fileparts(artifactPath);
if lower(erase(string(extension), ".")) ~= spec.file_format
    error("vawlume:ingest:MupetArtifactUnsupported", ...
        "MUPET artifact '%s' requires .%s, but received %s.", ...
        spec.artifact_key, spec.file_format, artifactPath);
end
fileInfo = dir(artifactPath);
if fileInfo.bytes == 0
    error("vawlume:ingest:MupetArtifactUnreadable", ...
        "MUPET CSV is empty: %s", artifactPath);
end

try
    options = detectImportOptions(artifactPath, FileType="text", ...
        Delimiter=char(spec.delimiter), VariableNamingRule="preserve");
    options.VariableNamesLine = spec.header_row;
    options.DataLines = [spec.header_row + 1, Inf];
    if numel(options.VariableNames) < 2
        error("vawlume:ingest:MupetArtifactUnsupported", ...
            ['MUPET CSV yielded fewer than two columns with profile delimiter ' ...
            '''%s''. Check the delimiter and header row: %s'], ...
            spec.delimiter, artifactPath);
    end

    lexicalColumns = declaredLexicalColumns(profileDocument, options.VariableNames);
    if ~isempty(lexicalColumns)
        options = setvartype(options, cellstr(lexicalColumns), "string");
        options = setvaropts(options, cellstr(lexicalColumns), ...
            TreatAsMissing={}, FillValue="");
    end
    tbl = readtable(artifactPath, options);
catch exception
    if startsWith(string(exception.identifier), "vawlume:")
        rethrow(exception);
    end
    error("vawlume:ingest:MupetArtifactUnreadable", ...
        "Could not read MUPET CSV %s: %s", artifactPath, exception.message);
end

if width(tbl) == 0
    error("vawlume:ingest:MupetArtifactUnreadable", ...
        "MUPET CSV yielded no columns at header row %d: %s", ...
        spec.header_row, artifactPath);
end

readResult = struct(table=tbl, delimiter=spec.delimiter, ...
    header_row=spec.header_row, row_count=height(tbl), column_count=width(tbl), ...
    source_columns=string(tbl.Properties.VariableNames)', ...
    lexical_columns=lexicalColumns(:));
end

function columns = declaredLexicalColumns(profileDocument, actualNames)
columns = strings(0, 1);
mappings = normalizeSequence(profileDocument.field_mappings);
actualNames = string(actualNames);
for index = 1:numel(mappings)
    mapping = mappings{index};
    if ~isfield(mapping, "missing_value_policy")
        continue
    end
    labels = string(mapping.source_field);
    if isfield(mapping, "aliases")
        labels = [labels; string(mapping.aliases(:))]; %#ok<AGROW>
    end
    match = actualNames(ismember(actualNames, labels));
    if isscalar(match)
        columns(end + 1, 1) = match; %#ok<AGROW>
    end
end
columns = unique(columns, "stable");
end

function items = normalizeSequence(raw)
if iscell(raw)
    items = raw(:);
elseif isstruct(raw)
    items = num2cell(raw(:));
else
    items = {};
end
end
