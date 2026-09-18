function fig = renderMetricCoverageTable(distributions, options)
%RENDERMETRICCOVERAGETABLE Figure-table view of precomputed metric coverage.

arguments
    distributions table
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [12 7]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

columns = ["metric_name", "supported", "not_eligible", "not_measured", ...
    "not_comparable_topology", "non_finite", "total", "statistics_status"];
edaRequireTableColumns(distributions, columns, "Metric-distribution table");
if height(distributions) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "The metric-coverage table has no row to render.");
end
caution = edaCautionNote();
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, "Counts are mutually exclusive coverage categories; total is " + ...
    "the denominator for every metric row.");
delete(ax);
annotation(fig, "textbox", [0.04 0.91 0.92 0.055], ...
    String="Exploratory metric coverage (counts; denominator = total)", ...
    EdgeColor="none", HorizontalAlignment="center", FontWeight="bold", ...
    Tag="vawlume-coverage-title");
selected = distributions(:, columns);
uitable(fig, Data=selected, Units="normalized", ...
    Position=[0.04 0.34 0.92 0.55], Tag="vawlume-metric-coverage-table");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
