function value = alignmentPortableUri(path, root)
%ALIGNMENTPORTABLEURI Repository-relative slash path when the file sits inside root.
%
% Provenance should survive being read on another machine, so a tracked input is
% recorded relative to the repository rather than by its local absolute path.

value = replace(alignmentCanonicalPath(path), "\", "/");
if strlength(string(root)) == 0
    return
end
prefix = strip(replace(alignmentCanonicalPath(root), "\", "/"), "right", "/") + "/";
if startsWith(lower(value), lower(prefix))
    value = extractAfter(value, strlength(prefix));
end
end
