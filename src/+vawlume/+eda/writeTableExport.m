function result = writeTableExport(table0, path, options)
%WRITETABLEEXPORT Write a machine-readable CSV with provenance/caution header.
%
% The first line is JSON prefixed by `# vawlume_table_export=`. CSV readers may
% skip it as a comment/header line; a provenance-aware reader can decode the
% exact run identity and canonical caution before reading the table header.

arguments
    table0 table
    path (1,1) string
    options.Provenance (1,1) struct
    options.Overwrite (1,1) logical = false
end

if isempty(fieldnames(options.Provenance))
    error("vawlume:eda:TableExportProvenanceRequired", ...
        "Table export provenance must contain at least one named field.");
end
if isfile(path) && ~options.Overwrite
    error("vawlume:eda:TableExportExists", ...
        "Table export '%s' exists. Pass Overwrite=true to replace it.", path);
end
parent = string(fileparts(path));
if strlength(parent) > 0 && ~isfolder(parent)
    mkdir(parent);
end
caution = edaCautionNote();
header = struct(export_version="1.0", ...
    generated_by="vawlume.eda.writeTableExport", ...
    provenance=options.Provenance, caution=string(caution(:))');
headerText = "# vawlume_table_export=" + string(jsonencode(header));
temporaryPath = string(tempname(parentOrCurrent(parent))) + ".csv";
temporaryCleanup = onCleanup(@() deleteIfPresent(temporaryPath));
writetable(table0, temporaryPath, Delimiter=",", QuoteStrings="all", ...
    Encoding="UTF-8");
tableText = fileread(temporaryPath);

fileId = fopen(path, "w", "n", "UTF-8");
if fileId < 0
    error("vawlume:eda:TableExportOpenFailed", ...
        "Could not open table export '%s' for writing.", path);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", headerText);
fprintf(fileId, "%s", tableText);
clear cleanup
clear temporaryCleanup
result = struct(status="written", path=path, row_count=height(table0), ...
    columns=string(table0.Properties.VariableNames), header=header, ...
    header_prefix="# vawlume_table_export=", delimiter=",", ...
    encoding="UTF-8");
end

function folder = parentOrCurrent(parent)
folder = parent;
if strlength(folder) == 0
    folder = string(pwd);
end
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end
