function edaMaybeExport(fig, path, resolutionDpi, sizeInches)
%EDAMAYBEEXPORT One-call convenience shared by every Part 14 plot.
if strlength(path) == 0
    return
end
vawlume.eda.exportFigure(fig, path, ResolutionDpi=resolutionDpi, ...
    SizeInches=sizeInches);
end
