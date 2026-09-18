function fig = plotSupportFeatureDistributions(features, equivalenceClass, options)
%PLOTSUPPORTFEATUREDISTRIBUTIONS Five-number summaries by exact support pattern.

arguments
    features table
    equivalenceClass (1,1) string
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [12 8]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
    options.InterpretationNote string = string.empty
end

required = ["extractor_set_key", "extractor_set_label", ...
    "equivalence_class", "canonical_unit", "is_cross_pattern_comparable", ...
    "pattern_population", "contributing_detections", "coverage_fraction", ...
    "coverage_label", "statistics_status", "minimum", "q25", "median", ...
    "q75", "maximum"];
edaRequireTableColumns(features, required, "Support-feature table");
rows = features(features.equivalence_class == equivalenceClass, :);
if height(rows) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "Feature '%s' has no support-pattern row.", equivalenceClass);
end
if any(~rows.is_cross_pattern_comparable)
    error("vawlume:eda:FeatureNotCrossPatternComparable", ...
        "Feature '%s' is not registered as comparable across the entire " + ...
        "extractor set and cannot be placed on a cross-pattern axis.", ...
        equivalenceClass);
end
units = unique(rows.canonical_unit);
if numel(units) ~= 1
    error("vawlume:eda:PlotInputInvalid", ...
        "Feature '%s' does not have one canonical unit.", equivalenceClass);
end
rows = sortrows(rows, "extractor_set_key");
caution = edaCautionNote();
note = options.InterpretationNote;
if isempty(note)
    note = "Coverage labels and n/N are part of every summary. Differences " + ...
        "describe this dataset at the reference configuration; they do not " + ...
        "establish extractor specialization or support-class confidence.";
end
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, note);
hold(ax, "on");
for index = 1:height(rows)
    if rows.statistics_status(index) == "computed"
        line(ax, [index index], [rows.minimum(index) rows.maximum(index)], ...
            Color=[0.2 0.2 0.2], LineWidth=1.2, ...
            Tag="vawlume-feature-range");
        line(ax, [index index], [rows.q25(index) rows.q75(index)], ...
            Color=[0 0.447 0.698], LineWidth=7, ...
            Tag="vawlume-feature-interquartile-range");
        plot(ax, index, rows.median(index), "o", MarkerFaceColor="white", ...
            MarkerEdgeColor=[0 0 0], LineWidth=1.2, ...
            Tag="vawlume-feature-median");
    end
end
finiteValues = [rows.minimum; rows.maximum; rows.median];
finiteValues = finiteValues(isfinite(finiteValues));
if isempty(finiteValues)
    ylim(ax, [-1 1]);
else
    span = max(finiteValues) - min(finiteValues);
    if span == 0, span = max(abs(finiteValues(1)), 1); end
    ylim(ax, [min(finiteValues)-0.12*span, max(finiteValues)+0.28*span]);
end
limits = ylim(ax);
labelY = limits(2) - 0.05 * diff(limits);
for index = 1:height(rows)
    if rows.statistics_status(index) ~= "computed"
        plot(ax, index, limits(1) + 0.06 * diff(limits), "x", ...
            Color=[0.35 0.35 0.35], LineWidth=1.5, ...
            Tag="vawlume-feature-undefined", ...
            UserData=string(rows.statistics_status(index)));
    end
    label = "n=" + string(rows.contributing_detections(index)) + "/" + ...
        string(rows.pattern_population(index)) + " (" + ...
        rows.coverage_label(index) + ")";
    alignment = "center";
    if index == 1
        alignment = "left";
    elseif index == height(rows)
        alignment = "right";
    end
    text(ax, index, labelY, label, Rotation=0, ...
        HorizontalAlignment=alignment, Interpreter="none", FontSize=7, ...
        Tag="vawlume-coverage-annotation", ...
        UserData=struct(coverage_fraction=rows.coverage_fraction(index), ...
        statistics_status=rows.statistics_status(index)));
end
ax.XTick = 1:height(rows);
ax.XTickLabel = rows.extractor_set_label;
ax.XTickLabelRotation = 35;
xlabel(ax, "Exact extractor-set support pattern");
ylabel(ax, replace(equivalenceClass, "_", " ") + " (" + units(1) + ")");
title(ax, "Exploratory shared-feature distribution by exact support pattern", ...
    Interpreter="none");
grid(ax, "on");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
