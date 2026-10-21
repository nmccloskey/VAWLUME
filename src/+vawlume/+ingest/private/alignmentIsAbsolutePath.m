function value = alignmentIsAbsolutePath(path)
%ALIGNMENTISABSOLUTEPATH True when the supplied path is already absolute.

try
    value = vawlume.internal.resolvePath(path, Mode="isAbsolute");
catch
    value = false;
end
end
