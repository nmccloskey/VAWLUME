function fig = plotMetricCorrelation(dependencies, kind, options)
%PLOTMETRICCORRELATION Heatmap of a precomputed dependency matrix.
%
% Undefined entries remain NaN and receive an explicit crossed cell labelled
% with their precomputed reason. They are never replaced by zero.

arguments
    dependencies (1,1) struct
    kind (1,1) string {mustBeMember(kind, ["pearson", "spearman", "partial"])}
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [11 8]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

required = ["metric_names", "correlation_observations", ...
    "correlation_undefined_reason", "partial", "pearson", "spearman"];
missingNames = required(~isfield(dependencies, required));
if ~isempty(missingNames)
    error("vawlume:eda:PlotInputInvalid", ...
        "Dependency result is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
names = string(dependencies.metric_names(:));
if numel(names) < 2
    error("vawlume:eda:PlotCorrelationDegenerate", ...
        "A correlation heatmap requires at least two metrics.");
end
if kind == "partial"
    matrix = double(dependencies.partial.matrix);
    reasons = string(dependencies.partial.undefined_reason);
else
    matrix = double(dependencies.(kind));
    reasons = string(dependencies.correlation_undefined_reason);
end
if ~isequal(size(matrix), [numel(names), numel(names)]) || ...
        ~isequal(size(reasons), size(matrix))
    error("vawlume:eda:PlotInputInvalid", ...
        "The %s matrix and its undefined-reason matrix do not match the " + ...
        "metric-name count.", kind);
end
caution = edaCautionNote();
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, "Undefined cells are NaN with the displayed reason; they are " + ...
    "not zero and do not indicate absence of association.");
imageHandle = imagesc(ax, matrix, [-1 1]);
imageHandle.AlphaData = isfinite(matrix);
imageHandle.Tag = "vawlume-correlation-matrix";
colormap(ax, parula(256));
colorbar(ax);
axis(ax, "equal", "tight");
ax.XTick = 1:numel(names);
ax.YTick = 1:numel(names);
ax.XTickLabel = replace(names, "_", " ");
ax.YTickLabel = replace(names, "_", " ");
ax.XTickLabelRotation = 35;
xlabel(ax, "Metric");
ylabel(ax, "Metric");
title(ax, "Exploratory " + kind + " correlation", Interpreter="none");
hold(ax, "on");
observations = double(dependencies.correlation_observations);
for row = 1:numel(names)
    for column = 1:numel(names)
        if isfinite(matrix(row, column))
            text(ax, column, row, compose("%.2f\nn=%d", ...
                matrix(row, column), observations(row, column)), ...
                HorizontalAlignment="center", FontSize=7, ...
                Tag="vawlume-correlation-value");
        else
            rectangle(ax, Position=[column-0.5 row-0.5 1 1], ...
                FaceColor=[0.93 0.93 0.93], EdgeColor=[0.35 0.35 0.35], ...
                Tag="vawlume-undefined-cell", ...
                UserData=struct(value=NaN, reason=reasons(row, column)));
            line(ax, [column-0.42 column+0.42], [row-0.42 row+0.42], ...
                Color=[0.35 0.35 0.35], HandleVisibility="off");
            line(ax, [column-0.42 column+0.42], [row+0.42 row-0.42], ...
                Color=[0.35 0.35 0.35], HandleVisibility="off");
            label = replace(reasons(row, column), "_", " ");
            if strlength(label) == 0, label = "undefined"; end
            text(ax, column, row, "undefined" + newline + label, ...
                HorizontalAlignment="center", FontSize=6, ...
                Interpreter="none", Tag="vawlume-undefined-reason");
        end
    end
end
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
