function validatePackage(root, record)
%VALIDATEPACKAGE Check a staged package against its record before publication.
%
%   vawlume.export.internal.validatePackage(ROOT, RECORD)
%
%   Reads the staged files back and checks their shape against the record:
%
%     - every file the record lists exists, and nothing else is in csv/;
%     - schema-only packages have no csv/ directory at all, not even an empty one;
%     - meta/tables.csv has one row per supported object, and its exported rows
%       match the exported count and name files that exist;
%     - meta/columns.csv and meta/relationships.csv have their full row counts;
%     - meta/manifest.csv has as many rows as the record's manifest and
%       identifies the package format.
%
%   It does NOT compare fact values: not the manifest's counts, source, or
%   versions, and not README.md, which is only checked to exist. Those cannot
%   disagree with the record unless a renderer is changed, because every file
%   is rendered from the one record (contract §G.1); test_export_package and
%   test_csv_export_demo catch such a change.
%
%   Raises vawlume:export:PackageInvalid naming every failed check. This is the
%   last gate before a staged package is renamed onto the destination.

arguments
    root (1,1) string
    record (1,1) struct
end

problems = strings(0, 1);

for file = record.files(:)'
    if ~isfile(fullfile(root, file))
        problems(end + 1) = "missing " + file; %#ok<AGROW>
    end
end
if ~isempty(problems)
    % Nothing further can be read reliably from a package with files missing.
    raise(problems);
end

csvDir = fullfile(root, "csv");
if record.mode == "schema_only"
    if isfolder(csvDir)
        problems(end + 1) = "a schema-only package has a csv/ directory";
    end
else
    listing = dir(fullfile(csvDir, "*"));
    listing = listing(~[listing.isdir]);
    present = sort("csv/" + string({listing.name}'));
    if ~isequal(present, sort(record.data_files(:)))
        problems(end + 1) = "csv/ does not hold exactly the exported objects' files";
    end
end

tables = readStrings(fullfile(root, "meta", "tables.csv"));
if height(tables) ~= record.supported_object_count
    problems(end + 1) = sprintf("tables.csv has %d rows, not %d", ...
        height(tables), record.supported_object_count);
elseif sum(tables.exported == "true") ~= record.exported_object_count
    problems(end + 1) = "tables.csv's exported rows do not match the exported count";
else
    exportedFiles = tables.filename(tables.exported == "true");
    if any(ismissing(exportedFiles)) || ~all(ismember(exportedFiles, record.data_files))
        problems(end + 1) = "tables.csv names a data file the package does not hold";
    end
    if any(~ismissing(tables.filename(tables.exported == "false")))
        problems(end + 1) = "tables.csv gives a filename to an object that was not exported";
    end
end

for name = ["columns", "relationships"]
    expected = height(record.(name + "_csv"));
    actual = height(readStrings(fullfile(root, "meta", name + ".csv")));
    if actual ~= expected
        problems(end + 1) = sprintf("%s.csv has %d rows, not %d", name, actual, expected); %#ok<AGROW>
    end
end

manifest = readStrings(fullfile(root, "meta", "manifest.csv"));
if height(manifest) ~= height(record.manifest_csv) || ...
        ~any(manifest.key == "package_format" & manifest.value == record.package_format)
    problems(end + 1) = "manifest.csv does not match the package record";
end

if ~isempty(problems)
    raise(problems);
end
end

function raise(problems)
error("vawlume:export:PackageInvalid", ...
    "The staged package failed validation and was not published:\n  %s", ...
    strjoin(problems, newline + "  "));
end

function data = readStrings(path)
% Exact read-back: a blank (NULL) field is <missing>, a quoted one is text, and
% nothing is re-typed.
data = exportReadCsv(path);
end
