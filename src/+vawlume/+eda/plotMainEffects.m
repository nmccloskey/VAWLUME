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

required = ["factor_name", "main_effect", "response_range", "category", ...
    "strictness_direction"];
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
directions = strictnessLabels(rows.strictness_direction, values);
factorIds = "F" + string((1:height(rows))');
ax.Position = [.08 .50 .60 .40];
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
finiteOrZero = values;
finiteOrZero(~isfinite(finiteOrZero)) = 0;
lower = min([finiteOrZero; 0]);
upper = max([finiteOrZero; 0]);
plotSpan = max(upper - lower, 1);
ylim(ax, [lower - 0.12 * plotSpan, upper + 0.12 * plotSpan]);
for index = 1:height(rows)
    y = values(index);
    prefix = strings(0, 1);
    if ~isfinite(y)
        y = 0;
        prefix = "undefined";
    end
    category = [prefix; split(rows.category(index), "_")];
    if y < 0
        labelY = y - 0.025 * plotSpan;
        verticalAlignment = "top";
    else
        labelY = y + 0.025 * plotSpan;
        verticalAlignment = "bottom";
    end
    text(ax, index, labelY, char(strjoin(category, newline)), ...
        HorizontalAlignment="center", VerticalAlignment=verticalAlignment, ...
        Interpreter="none", ...
        FontSize=7, Tag="vawlume-leverage-category", ...
        UserData=struct(category=rows.category(index), ...
        response_range=rows.response_range(index)));
end
ax.XTick = 1:height(rows);
ax.XTickLabel = factorIds;
ax.TickLabelInterpreter = "none";
xlabel(ax, "Screened factor (see factor key)");
factorKeyRows = factorIds + "  " + replace(rows.factor_name, "_", " ") + ...
    newline + "    " + directions;
factorKey = annotation(fig, "textbox", [.70 .50 .28 .40], ...
    String="Factor key" + newline + newline + strjoin(factorKeyRows, ...
    sprintf('\n\n')), Interpreter="none", FontSize=7.5, ...
    VerticalAlignment="top", EdgeColor=[0.82 0.82 0.82], ...
    BackgroundColor=[1 1 1], Tag="vawlume-main-effects-factor-key");
factorKey.UserData = struct(factor_id=factorIds, ...
    factor_name=string(rows.factor_name), strictness_label=directions);
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

function value = strictnessLabels(direction, mainEffect)
direction = string(direction(:));
value = strings(size(direction));
value(direction == "larger_is_stricter") = "larger = stricter";
value(direction == "smaller_is_stricter") = "smaller = stricter";
missing = strlength(direction) == 0;
if any(missing & isfinite(mainEffect))
    error("vawlume:eda:PlotInputInvalid", ...
        "A finite main effect lacks its strictness_direction.");
end
value(missing) = "strictness not supplied";
invalid = strlength(value) == 0;
if any(invalid)
    error("vawlume:eda:PlotInputInvalid", ...
        "Unknown strictness_direction value(s): %s.", ...
        strjoin(unique(direction(invalid)), ", "));
end
end
