function value = alignmentFilenameOf(path)
%ALIGNMENTFILENAMEOF Filename with extension for a supplied path.

[~, name, extension] = fileparts(string(path));
value = name + extension;
end
