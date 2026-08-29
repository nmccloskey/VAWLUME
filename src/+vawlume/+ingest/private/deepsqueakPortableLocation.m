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
    location.relative_path = replace(declaredRelativePath, "\", "/");
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
