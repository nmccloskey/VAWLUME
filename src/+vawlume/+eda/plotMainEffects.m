function fig = plotMainEffects(categories, options)
%PLOTMAINEFFECTS Transparent main-effect view for one response identity.

arguments
    categories table
    options.Response (1,1) string
    options.QualifierKind (1,1) string = ""
    options.Qualifier (1,1) string = ""
    options.SecondaryKind (1,1) string = ""
    options.Secondary (1,1) string = ""
    options.ValueKind (1,1) string = ""
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [11 7]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

required = ["factor_name", "main_effect", "response_range", "category"];
edaRequireTableColumns(categories, required, "Leverage-category table");
rows = edaSelectResponseIdentity(categories, options, ...
    "Leverage-category table");
rows = sortrows(rows, "factor_name");
if height(rows) == 0
    error("vawlume:eda:PlotSelectionEmpty", "No main effect remains to plot.");
end
caution = edaCautionNote();
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, "Categories are reporting labels from the supplied table. " + ...
    "They are shown for every factor, including interaction_suspected and " + ...
    "insufficient_information; no factor is ranked.");

values = double(rows.main_effect);
bars = bar(ax, 1:height(rows), values, 0.65, ...
    FaceColor=[0.45 0.55 0.65], EdgeColor=[0.1 0.1 0.1], ...
    Tag="vawlume-main-effects");
if all(rows.qualifier_kind == "extractor_key") && ...
        isscalar(unique(rows.qualifier))
    style = vawlume.eda.exampleStyles(rows.qualifier(1));
    bars.FaceColor = [style.color_r style.color_g style.color_b];
    bars.LineStyle = style.line_style;
end
hold(ax, "on");
finiteValues = values(isfinite(values));
span = 1;
if ~isempty(finiteValues)
    span = max(max(finiteValues) - min(finiteValues), max(abs(finiteValues)));
    if span == 0, span = 1; end
end
for index = 1:height(rows)
    y = values(index);
    prefix = "";
    if ~isfinite(y)
        y = 0;
        prefix = "undefined; ";
    end
    text(ax, index, y + 0.04 * span, prefix + rows.category(index), ...
        Rotation=55, HorizontalAlignment="left", Interpreter="none", ...
        FontSize=7, Tag="vawlume-leverage-category", ...
        UserData=struct(category=rows.category(index), ...
        response_range=rows.response_range(index)));
end
ax.XTick = 1:height(rows);
ax.XTickLabel = replace(rows.factor_name, "_", " ");
ax.XTickLabelRotation = 30;
xlabel(ax, "Screened factor");
kind = string(rows.value_kind(1));
if kind == "fraction"
    ylabel(ax, "Main effect (fraction of the response's stated denominator)");
else
    ylabel(ax, "Main effect (count difference between factor levels)");
end
title(ax, "Exploratory sensitivity main effects: " + ...
    replace(options.Response, "_", " "), Interpreter="none");
yline(ax, 0, Color=[0.35 0.35 0.35], LineStyle=":", ...
    HandleVisibility="off");
grid(ax, "on");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
