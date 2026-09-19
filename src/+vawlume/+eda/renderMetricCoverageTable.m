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
annotation(fig, "textbox", [0.04 0.91 0.92 0.055], ...
    String="Exploratory metric coverage (counts; denominator = total)", ...
    EdgeColor="none", HorizontalAlignment="center", FontWeight="bold", ...
    Tag="vawlume-coverage-title");
selected = distributions(:, columns);
renderCoverageTable(ax, selected, columns);
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end

function renderCoverageTable(ax, selected, columns)
%RENDERCOVERAGETABLE A printable table made only from ordinary axes graphics.
ax.Position = [0.04 0.50 0.92 0.39];
ax.Tag = "vawlume-metric-coverage-table";
ax.UserData = selected;
rowCount = height(selected);
widths = [3.4 1.2 1.5 1.5 2.3 1.3 1.0 2.0];
xEdges = [0 cumsum(widths)];
xCenters = (xEdges(1:end-1) + xEdges(2:end)) / 2;
xlim(ax, [xEdges(1) xEdges(end)]);
ylim(ax, [0 rowCount + 1]);
axis(ax, "off");

for x = xEdges
    line(ax, [x x], [0 rowCount + 1], Color=[0.75 0.75 0.75], ...
        HandleVisibility="off");
end
for y = 0:(rowCount + 1)
    line(ax, [xEdges(1) xEdges(end)], [y y], ...
        Color=[0.75 0.75 0.75], HandleVisibility="off");
end

headerY = rowCount + 0.5;
for column = 1:numel(columns)
    header = replace(columns(column), "_", " ");
    text(ax, xCenters(column), headerY, header, ...
        HorizontalAlignment="center", VerticalAlignment="middle", ...
        Interpreter="none", FontSize=6.5, FontWeight="bold", ...
        Tag="vawlume-coverage-header");
end
fontSize = max(5.5, min(7.5, 46 / (rowCount + 1)));
for row = 1:rowCount
    y = rowCount - row + 0.5;
    for column = 1:numel(columns)
        value = string(selected.(columns(column))(row));
        alignment = "center";
        x = xCenters(column);
        if column == 1 || column == numel(columns)
            alignment = "left";
            x = xEdges(column) + 0.08;
        end
        text(ax, x, y, value, HorizontalAlignment=alignment, ...
            VerticalAlignment="middle", Interpreter="none", ...
            FontSize=fontSize, Tag="vawlume-coverage-cell");
    end
end
end
