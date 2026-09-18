function fig = plotSupportPatternSummary(patterns, options)
%PLOTSUPPORTPATTERNSUMMARY Counts or proportions by exact extractor-set pattern.

arguments
    patterns table
    options.Measure (1,1) string {mustBeMember(options.Measure, ...
        ["group_count", "group_proportion", "detection_count", ...
        "detection_proportion"])} = "group_count"
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [12 7]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
    options.InterpretationNote string = string.empty
end

required = ["extractor_set_key", "extractor_set_label", "extractor_count", ...
    options.Measure, ...
    "group_denominator", "detection_denominator"];
edaRequireTableColumns(patterns, required, "Support-pattern table");
if height(patterns) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "The support-pattern table is empty.");
end
rows = sortrows(patterns, ["extractor_count", "extractor_set_key"]);
caution = edaCautionNote();
note = options.InterpretationNote;
if isempty(note)
    note = "Exact support patterns are descriptive categories within this " + ...
        "dataset. A larger count is not a confidence ranking, and an " + ...
        "extractor-unique pattern is not an error category.";
end
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, note);
values = double(rows.(options.Measure));
bar(ax, 1:height(rows), values, 0.7, FaceColor=[0.30 0.55 0.70], ...
    EdgeColor=[0.1 0.1 0.1], Tag="vawlume-support-pattern-summary");
ax.XTick = 1:height(rows);
ax.XTickLabel = rows.extractor_set_label;
ax.XTickLabelRotation = 35;
xlabel(ax, "Exact extractor-set support pattern");
switch options.Measure
    case "group_count"
        ylabel(ax, "Agreement groups (count; denominator=" + ...
            string(uniqueDenominator(rows.group_denominator)) + ")");
    case "group_proportion"
        ylabel(ax, "Agreement groups (fraction of all groups; denominator=" + ...
            string(uniqueDenominator(rows.group_denominator)) + ")");
    case "detection_count"
        ylabel(ax, "Member detections (count; denominator=" + ...
            string(uniqueDenominator(rows.detection_denominator)) + ")");
    case "detection_proportion"
        ylabel(ax, "Member detections (fraction of all member detections; " + ...
            "denominator=" + ...
            string(uniqueDenominator(rows.detection_denominator)) + ")");
end
title(ax, "Exploratory exact support-pattern characterization");
grid(ax, "on");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end

function value = uniqueDenominator(values)
distinct = unique(double(values));
if numel(distinct) ~= 1
    error("vawlume:eda:PlotInputInvalid", ...
        "Support-pattern rows do not share one denominator.");
end
value = distinct;
end
