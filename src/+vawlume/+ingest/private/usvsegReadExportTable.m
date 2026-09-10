function readResult = usvsegReadExportTable(artifactPath, spec)
%USVSEGREADEXPORTTABLE Read one USVSEG event CSV without losing source tokens.
%
% USVSEG's eight columns are numeric, but reading them as strings is
% intentional: it preserves the exact printed evidence (including any
% non-finite or unexpected token) until the profile-driven mapper interprets
% each value. The reader performs file mechanics only.

arguments
    artifactPath (1,1) string
    spec (1,1) struct
end

if ~isfile(artifactPath)
    error("vawlume:ingest:UsvsegArtifactNotFound", ...
        "USVSEG export file does not exist: %s", artifactPath);
end
[~, ~, extension] = fileparts(artifactPath);
if lower(erase(string(extension), ".")) ~= spec.file_format
    error("vawlume:ingest:UsvsegArtifactUnsupported", ...
        "USVSEG artifact '%s' requires .%s, but received %s.", ...
        spec.artifact_key, spec.file_format, artifactPath);
end
fileInfo = dir(artifactPath);
if fileInfo.bytes == 0
    error("vawlume:ingest:UsvsegArtifactUnreadable", ...
        "USVSEG CSV is empty: %s", artifactPath);
end

try
    options = detectImportOptions(artifactPath, FileType="text", ...
        Delimiter=char(spec.delimiter), VariableNamingRule="preserve");
    options.VariableNamesLine = spec.header_row;
    options.DataLines = [spec.header_row + 1, Inf];
    if numel(options.VariableNames) < 2
        error("vawlume:ingest:UsvsegArtifactUnsupported", ...
            ['USVSEG CSV yielded fewer than two columns with profile delimiter ' ...
            '''%s''. Check the delimiter and header row: %s'], ...
            spec.delimiter, artifactPath);
    end

    assertDistinctHeaderLabels(options.VariableNames, artifactPath);
    options = setvartype(options, options.VariableNames, "string");
    options = setvaropts(options, options.VariableNames, ...
        TreatAsMissing={}, FillValue="");
    tbl = readtable(artifactPath, options);
catch exception
    if startsWith(string(exception.identifier), "vawlume:")
        rethrow(exception);
    end
    error("vawlume:ingest:UsvsegArtifactUnreadable", ...
        "Could not read USVSEG CSV %s: %s", artifactPath, exception.message);
end

if width(tbl) == 0
    error("vawlume:ingest:UsvsegArtifactUnreadable", ...
        "USVSEG CSV yielded no columns at header row %d: %s", ...
        spec.header_row, artifactPath);
end

sourceColumns = string(tbl.Properties.VariableNames)';
readResult = struct(table=tbl, delimiter=spec.delimiter, ...
    header_row=spec.header_row, row_count=height(tbl), column_count=width(tbl), ...
    source_columns=sourceColumns, lexical_columns=sourceColumns);
end

function assertDistinctHeaderLabels(labels, path)
labels = string(labels(:));
repeated = unique(labels(sum(labels == labels', 2) > 1));
if ~isempty(repeated)
    error("vawlume:ingest:UsvsegArtifactUnsupported", ...
        "USVSEG CSV repeats source column label(s) in %s: %s.", ...
        path, strjoin(repeated, ", "));
end
end
