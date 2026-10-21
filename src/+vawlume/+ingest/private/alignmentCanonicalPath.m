function value = alignmentCanonicalPath(path)
%ALIGNMENTCANONICALPATH Canonical filesystem path, falling back to the input.

value = string(path);
try
    value = vawlume.internal.resolvePath(value);
catch
end
end
