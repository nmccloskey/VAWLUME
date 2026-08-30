function value = alignmentResolvePath(path, root)
%ALIGNMENTRESOLVEPATH Resolve a manifest-declared path against a root.
%
% A manifest names its inputs relatively so the same session description works on
% another machine. An absolute path is respected as given.

value = string(path);
if strlength(value) == 0
    return
end
if ~alignmentIsAbsolutePath(value) && strlength(string(root)) > 0
    value = fullfile(string(root), value);
end
value = alignmentCanonicalPath(value);
end
