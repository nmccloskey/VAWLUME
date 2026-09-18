function fig = plotMetricDistribution(metrics, metricName, options)
%PLOTMETRICDISTRIBUTION Histogram of one precomputed candidate-metric column.

arguments
    metrics table
    metricName (1,1) string
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [10 7]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

edaRequireTableColumns(metrics, metricName, "Candidate-metric table");
if ~isnumeric(metrics.(metricName))
    error("vawlume:eda:PlotInputInvalid", ...
        "Metric '%s' is not numeric.", metricName);
end
values = double(metrics.(metricName));
finite = values(isfinite(values));
if numel(finite) < 2
    error("vawlume:eda:PlotDistributionDegenerate", ...
        "Metric '%s' has %d finite observation(s); at least two are " + ...
        "required for a distribution plot.", metricName, numel(finite));
end
caution = edaCautionNote();
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, "Histogram bins are a visual summary of the finite values in " + ...
    "the supplied table; no observation is imputed or regularized.");
h = histogram(ax, finite, DisplayStyle="stairs", EdgeColor=[0 0.447 0.698], ...
    LineWidth=2, Tag="vawlume-metric-histogram");
h.UserData = struct(metric_name=metricName, finite_observations=numel(finite), ...
    total_rows=numel(values));
xlabel(ax, replace(metricName, "_", " "), Interpreter="none");
ylabel(ax, "Candidate pairs (count per bin; finite n=" + ...
    string(numel(finite)) + " of total " + string(numel(values)) + ")");
title(ax, "Exploratory metric distribution", Interpreter="none");
grid(ax, "on");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
