function writePackageFiles(record, stagingRoot)
%WRITEPACKAGEFILES Render the README and meta/*.csv from the package record.
%
%   vawlume.export.internal.writePackageFiles(RECORD, STAGINGROOT)
%
%   Writes meta/tables.csv, meta/columns.csv, meta/relationships.csv, README.md,
%   and -- LAST -- meta/manifest.csv. The manifest is the completion marker
%   (contract §F.3), so a directory that has one holds a finished package.
%
%   The metadata files go through the same writer as the data files, so they
%   follow the same CSV rules: every value quoted, a blank field for an absent
%   value, UTF-8, CRLF. Nothing here reads the database or the semantic document;
%   everything comes from RECORD.

arguments
    record (1,1) struct
    stagingRoot (1,1) string
end

metaDir = fullfile(stagingRoot, "meta");
mkdir(metaDir);
writeTable(record.tables_csv, fullfile(metaDir, "tables.csv"));
writeTable(record.columns_csv, fullfile(metaDir, "columns.csv"));
writeTable(record.relationships_csv, fullfile(metaDir, "relationships.csv"));

readme = vawlume.export.internal.renderReadme(record);
fid = fopen(fullfile(stagingRoot, "README.md"), "w", "n", "UTF-8");
if fid < 0
    error("vawlume:export:WriteFailed", "Could not write README.md in %s.", stagingRoot);
end
closer = onCleanup(@() fclose(fid));
fwrite(fid, unicode2native(char(readme), "UTF-8"));
clear closer

writeTable(record.manifest_csv, fullfile(metaDir, "manifest.csv"));
end

function writeTable(data, path)
vawlume.export.internal.writeCsv(data, string(data.Properties.VariableNames), path);
end
