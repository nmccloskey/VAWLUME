function value = alignmentCanonicalPath(path)
%ALIGNMENTCANONICALPATH Canonical filesystem path, falling back to the input.

value = string(path);
try
    value = string(java.io.File(char(value)).getCanonicalPath());
catch
end
end
