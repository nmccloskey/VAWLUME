function location = mupetPortableLocation(path, declaredRelativePath, roots)
%MUPETPORTABLELOCATION Derive a durable root-independent artifact location.

arguments
    path (1,1) string
    declaredRelativePath (1,1) string
    roots (1,:) string
end

runtimePath = string(java.io.File(char(path)).getAbsolutePath());
[~, stem, extension] = fileparts(runtimePath);
location = struct(runtime_path=runtimePath, ...
    filename=string(stem) + string(extension), ...
    extension=lower(erase(string(extension), ".")), ...
    relative_path="", relative_path_source="unavailable");

if strlength(declaredRelativePath) > 0
    location.relative_path = normalizeDeclaredPath(declaredRelativePath);
    location.relative_path_source = "declared";
    return
end

labels = ["artifact_root", "repo_root", "additional_root"];
for index = 1:numel(roots)
    if strlength(roots(index)) == 0
        continue
    end
    info = vawlume.source_mapping.normalizeRelativePath(runtimePath, roots(index), ...
        MustBeInsideRoot=false);
    if info.is_inside_root
        location.relative_path = info.relative_path;
        location.relative_path_source = labels(min(index, numel(labels)));
        return
    end
end
end

function path = normalizeDeclaredPath(path)
path = strtrim(replace(string(path), "\", "/"));
path = regexprep(path, "/+", "/");
characters = char(path);
isDrive = numel(characters) >= 2 && isletter(characters(1)) && characters(2) == ':';
parts = split(path, "/");
if strlength(path) == 0 || isDrive || startsWith(path, "/") || any(parts == "..")
    error("vawlume:ingest:MupetArtifactNotPortable", ...
        "Declared artifact identity '%s' is not a portable relative path.", path);
end
parts(parts == "." | strlength(parts) == 0) = [];
if isempty(parts)
    error("vawlume:ingest:MupetArtifactNotPortable", ...
        "Declared artifact identity must name a portable relative path.");
end
path = strjoin(parts, "/");
end
