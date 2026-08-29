function location = deepsqueakPortableLocation(path, declaredRelativePath, roots)
%DEEPSQUEAKPORTABLELOCATION Derive an artifact's portable identity.
%
% Durable artifact identity is a portable path, never an absolute runtime root,
% so the same content under a different checkout resolves to the same row rather
% than duplicating. The runtime path is kept alongside for diagnostics only.
%
% ROOTS is a string array of candidate roots in precedence order. Path
% containment is delegated to the shared source-mapping helper rather than
% reimplemented here.

arguments
    path (1,1) string
    declaredRelativePath (1,1) string
    roots (1,:) string
end

runtimePath = string(java.io.File(char(path)).getAbsolutePath());
[~, stem, extension] = fileparts(runtimePath);

location = struct();
location.runtime_path = runtimePath;
location.filename = string(stem) + string(extension);
location.extension = lower(erase(string(extension), "."));
location.relative_path = "";
location.relative_path_source = "unavailable";

if strlength(declaredRelativePath) > 0
    location.relative_path = normalizeDeclaredPortablePath(declaredRelativePath);
    location.relative_path_source = "declared";
    return
end

labels = ["artifact_root", "repo_root", "additional_root"];
for index = 1:numel(roots)
    root = roots(index);
    if strlength(root) == 0
        continue
    end
    info = vawlume.source_mapping.normalizeRelativePath(runtimePath, root, ...
        MustBeInsideRoot=false);
    if info.is_inside_root
        location.relative_path = info.relative_path;
        location.relative_path_source = labels(min(index, numel(labels)));
        return
    end
end
end

function path = normalizeDeclaredPortablePath(path)
%NORMALIZEDECLAREDPORTABLEPATH Validate caller-declared durable identity.
%
% A RelativePath value bypasses root-based containment, so it must prove its
% own portability. Accepting a drive-qualified, rooted, or parent-traversing
% value here would persist a machine location while labelling it portable.

path = strtrim(replace(string(path), "\", "/"));
path = regexprep(path, "/+", "/");

isDriveQualified = false;
pathCharacters = char(path);
if numel(pathCharacters) >= 2
    isDriveQualified = isletter(pathCharacters(1)) && pathCharacters(2) == ':';
end
isRooted = startsWith(path, "/");
parts = split(path, "/");
hasParentTraversal = any(parts == "..");

if strlength(path) == 0 || isDriveQualified || isRooted || hasParentTraversal
    error("vawlume:ingest:DeepSqueakArtifactNotPortable", ...
        ['Declared artifact identity ''%s'' is not a portable relative path. ' ...
        'Use a root-independent path with no drive, leading separator, or ''..'' segment.'], ...
        path);
end

parts(parts == "." | strlength(parts) == 0) = [];
if isempty(parts)
    error("vawlume:ingest:DeepSqueakArtifactNotPortable", ...
        "Declared artifact identity must name a portable relative path.");
end
path = strjoin(parts, "/");
end
