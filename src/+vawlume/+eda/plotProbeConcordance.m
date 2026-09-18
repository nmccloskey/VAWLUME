function fig = plotProbeConcordance(concordance, options)
%PLOTPROBECONCORDANCE Precomputed category-contingency view of two probes.

arguments
    concordance (1,1) struct
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [10 8]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

required = ["category_contingency", "category_vocabulary"];
missingNames = required(~isfield(concordance, required));
if ~isempty(missingNames)
    error("vawlume:eda:PlotInputInvalid", ...
        "Concordance result is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
table0 = concordance.category_contingency;
edaRequireTableColumns(table0, ...
    ["screen_category", "subset_category", "factor_response_pairs"], ...
    "Probe category-contingency table");
if height(table0) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "The probe category-contingency table is empty.");
end
categories = [string(concordance.category_vocabulary(:)); "not_observed"];
matrix = zeros(numel(categories), numel(categories));
for index = 1:height(table0)
    row = find(categories == table0.screen_category(index), 1);
    column = find(categories == table0.subset_category(index), 1);
    if isempty(row) || isempty(column)
        error("vawlume:eda:PlotInputInvalid", ...
            "The contingency row names an unknown leverage category.");
    end
    matrix(row, column) = table0.factor_response_pairs(index);
end
caution = edaCautionNote();
note = "Counts are factor-response pairs in the supplied contingency table. " + ...
    "No agreement fraction, score, ranking or selected configuration is shown.";
if isfield(concordance, "calibration_note")
    note = note + " " + string(concordance.calibration_note);
end
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, note);
imageHandle = imagesc(ax, matrix);
imageHandle.Tag = "vawlume-probe-contingency";
colormap(ax, parula(256));
colorbar(ax);
axis(ax, "equal", "tight");
ax.XTick = 1:numel(categories);
ax.YTick = 1:numel(categories);
ax.XTickLabel = replace(categories, "_", " ");
ax.YTickLabel = replace(categories, "_", " ");
ax.XTickLabelRotation = 35;
xlabel(ax, "Subset-probe leverage category");
ylabel(ax, "Whole-dataset leverage category");
title(ax, "Exploratory probe convergence (factor-response pair counts)");
for row = 1:numel(categories)
    for column = 1:numel(categories)
        text(ax, column, row, string(matrix(row, column)), ...
            HorizontalAlignment="center", Tag="vawlume-contingency-count");
    end
end
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
