function figureHandle = exportFigure(figureHandle, path, options)
%EXPORTFIGURE Export an EDA figure at explicit size and poster-ready resolution.

arguments
    figureHandle (1,1) matlab.ui.Figure
    path (1,1) string
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
    options.SizeInches (1,2) double {mustBePositive} = [10 7]
    options.Overwrite (1,1) logical = false
end

if isfile(path) && ~options.Overwrite
    error("vawlume:eda:FigureExportExists", ...
        "Figure export '%s' exists. Pass Overwrite=true to replace it.", path);
end
parent = string(fileparts(path));
if strlength(parent) > 0 && ~isfolder(parent)
    mkdir(parent);
end
figureHandle.Units = "inches";
position = figureHandle.Position;
figureHandle.Position = [position(1:2), options.SizeInches];

[~, ~, extension] = fileparts(path);
extension = lower(string(extension));
if ismember(extension, [".pdf", ".svg", ".eps"])
    exportgraphics(figureHandle, path, ContentType="vector");
elseif extension == ".png"
    % PRINT respects the requested physical figure dimensions. In contrast,
    % EXPORTGRAPHICS tightly crops figure content, so its raster dimensions
    % need not equal SizeInches * ResolutionDpi.
    figureHandle.PaperUnits = "inches";
    figureHandle.PaperPosition = [0 0 options.SizeInches];
    figureHandle.PaperSize = options.SizeInches;
    print(figureHandle, path, "-dpng", "-r" + string(options.ResolutionDpi));
else
    exportgraphics(figureHandle, path, Resolution=options.ResolutionDpi);
end
end
