function value = attributionIntakePortableUri(path, repoRoot)
%ATTRIBUTIONINTAKEPORTABLEURI Repository-relative URI when under the root, else the path.
path = replace(string(path), "\", "/");
root = strip(replace(string(repoRoot), "\", "/"), "right", "/");
prefix = root + "/";
if startsWith(lower(path), lower(prefix))
    value = extractAfter(path, strlength(prefix));
else
    value = path;
end
end
