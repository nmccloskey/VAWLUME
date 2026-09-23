function destination = checkDestination(output, overwrite, sourcePath)
%CHECKDESTINATION Decide whether a package may be published at OUTPUT, and how.
%
%   DESTINATION = vawlume.export.internal.checkDestination(OUTPUT, OVERWRITE, SOURCEPATH)
%
%   Returns a struct with `path` (the absolute, canonical destination; a
%   relative OUTPUT or SOURCEPATH is resolved against the current folder) and
%   `state`, which is one of:
%
%     "absent"   nothing is there; publication is a rename onto it
%     "empty"    an empty directory; accepted with or without OVERWRITE
%     "package"  a previous VAWLUME export package, and OVERWRITE is true
%
%   Everything else is refused before anything is written (contract §§F.1-F.2):
%
%     vawlume:export:OutputRequired             OUTPUT is empty or missing
%     vawlume:export:AmbiguousPath              OUTPUT is drive-relative ("C:x")
%                                               or rooted without a drive ("\x")
%     vawlume:export:DestinationUnsafe          a filesystem or drive root; the
%         home directory; a repository root; an ancestor of any of these; the
%         directory holding the source database, or any directory containing it;
%         an existing file rather than a directory; or a non-empty directory
%         that is not a recognizable VAWLUME package, even with OVERWRITE
%     vawlume:export:DestinationExists          a non-empty directory, without
%                                               OVERWRITE
%     vawlume:export:DestinationParentMissing   the parent directory does not
%                                               exist; nothing is created above
%                                               the destination
%
%   OVERWRITE is never a licence to delete an arbitrary directory. A destination
%   is replaced only when the tool recognizes it as its own output: README.md
%   and meta/manifest.csv both present, and the manifest's package_format row
%   reading vawlume_csv_export.
%
%   A repository root is recognized by a .git entry, which covers VAWLUME,
%   VAWLUME_dev, and any other working tree, without calling git. A tracked
%   directory inside a repository is non-empty and not a package, so it is
%   refused by the rule above. This function inspects the filesystem and
%   changes nothing.

arguments
    output
    overwrite (1,1) logical
    sourcePath (1,1) string = ""
end

if isempty(output) || ~(isstring(output) || ischar(output)) || ...
        any(ismissing(string(output))) || strlength(strtrim(string(output))) == 0
    error("vawlume:export:OutputRequired", ...
        "Output is required: name the directory the package should be published to. " + ...
        "There is no default destination.");
end

% A relative Output is resolved against the current folder (exportResolvePath).
path = exportResolvePath(string(output), "Output");
destination = struct(path=path, state="");

if isRoot(path)
    unsafe(path, "it is a filesystem or drive root");
end
home = homeDirectory();
if home ~= "" && isSameOrAncestor(path, home)
    unsafe(path, "it is your home directory or contains it");
end
if isfolder(fullfile(path, ".git")) || isfile(fullfile(path, ".git"))
    unsafe(path, "it is the root of a repository");
end
repository = canonical(string(fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath"))))))));
if isSameOrAncestor(path, repository)
    unsafe(path, "it contains the VAWLUME repository");
end
if sourcePath ~= ""
    source = exportResolvePath(sourcePath, "The database path");
    % The source lies inside its own directory, so this also refuses that
    % directory itself.
    if isSameOrAncestor(path, source)
        unsafe(path, "it is, or contains, the directory holding the source database");
    end
end

parent = string(fileparts(path));
if ~isfolder(parent)
    error("vawlume:export:DestinationParentMissing", ...
        "The parent of Output, ""%s"", does not exist. Create it first; the exporter " + ...
        "creates only the package directory itself.", parent);
end

if isfile(path)
    unsafe(path, "it is an existing file, not a directory");
end
if ~isfolder(path)
    destination.state = "absent";
    return
end

entries = dir(path);
entries = entries(~ismember({entries.name}, {'.', '..'}));
if isempty(entries)
    destination.state = "empty";
    return
end
if ~overwrite
    error("vawlume:export:DestinationExists", ...
        "Output ""%s"" already exists and is not empty. Choose a new directory, or " + ...
        "pass Overwrite=true to replace a previous VAWLUME export package there.", path);
end
if ~isVawlumePackage(path)
    unsafe(path, "it is not empty and is not a VAWLUME export package, so Overwrite " + ...
        "will not replace it");
end
destination.state = "package";
end

% ---------------------------------------------------------------------------

function unsafe(path, reason)
error("vawlume:export:DestinationUnsafe", ...
    "Refusing Output ""%s"": %s.", path, reason);
end

function yes = isVawlumePackage(path)
yes = false;
manifestPath = fullfile(path, "meta", "manifest.csv");
if ~isfile(fullfile(path, "README.md")) || ~isfile(manifestPath)
    return
end
try
    manifest = exportReadCsv(manifestPath);
    yes = all(ismember(["key", "value"], string(manifest.Properties.VariableNames))) && ...
        any(manifest.key == "package_format" & manifest.value == "vawlume_csv_export");
catch
    yes = false;
end
end

function path = canonical(path)
% Only for paths already known to be absolute (home, this repository). A
% caller-supplied path goes through exportResolvePath instead.
path = string(java.io.File(char(path)).getCanonicalPath());
end

function yes = isRoot(path)
yes = string(fileparts(path)) == path || ...
    ~isempty(regexp(path, "^[A-Za-z]:\\?$", "once")) || path == "/";
end

function home = homeDirectory()
home = string(getenv("USERPROFILE"));
if home == ""
    home = string(getenv("HOME"));
end
if home ~= ""
    home = canonical(home);
end
end

function yes = isSameOrAncestor(candidate, path)
% True when PATH is CANDIDATE or lies inside it. Compared case-insensitively on
% Windows, where the filesystem is.
if ispc
    candidate = lower(candidate);
    path = lower(path);
end
separator = string(filesep);
yes = path == candidate || startsWith(path, strip(candidate, "right", filesep) + separator);
end
