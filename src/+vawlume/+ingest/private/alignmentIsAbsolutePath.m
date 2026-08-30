function value = alignmentIsAbsolutePath(path)
%ALIGNMENTISABSOLUTEPATH True when the supplied path is already absolute.

try
    value = java.io.File(char(string(path))).isAbsolute();
catch
    value = false;
end
end
