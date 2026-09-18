function fig = plotSupportPatternResponses(responses, options)
%PLOTSUPPORTPATTERNRESPONSES Exact pair-support patterns across configurations.

arguments
    responses table
    options.Response (1,1) string = "support_pattern_groups"
    options.ValueKind (1,1) string {mustBeMember(options.ValueKind, ...
        ["count", "fraction"])} = "count"
    options.Scope (1,1) string = "pooled"
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [12 7]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

required = ["configuration_id", "scope", "response", "qualifier_kind", ...
    "qualifier", "value", "denominator", "value_kind"];
edaRequireTableColumns(responses, required, "Screen-response table");
rows = responses(responses.scope == options.Scope & ...
    responses.response == options.Response & ...
    responses.qualifier_kind == "support_pattern" & ...
    responses.value_kind == options.ValueKind, :);
if height(rows) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "No exact support-pattern response matches the supplied selectors.");
end
configurations = sort(unique(rows.configuration_id));
if numel(configurations) < 2
    error("vawlume:eda:PlotConfigurationDegenerate", ...
        "A support-pattern response across configurations requires at least " + ...
        "two configurations; %d was supplied.", numel(configurations));
end
patterns = sort(unique(rows.qualifier));
caution = edaCautionNote();
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, "Every legend entry is an exact supported-pair pattern from the " + ...
    "table. Patterns are never collapsed to a coarse K-of-N category.");
hold(ax, "on");
palette = parula(max(numel(patterns), 2));
lineStyles = ["-", "--", ":", "-."];
handles = gobjects(numel(patterns), 1);
for patternIndex = 1:numel(patterns)
    selected = rows(rows.qualifier == patterns(patternIndex), :);
    values = nan(numel(configurations), 1);
    for configIndex = 1:numel(configurations)
        match = selected.configuration_id == configurations(configIndex);
        if nnz(match) ~= 1
            error("vawlume:eda:PlotInputInvalid", ...
                "Pattern '%s' has %d rows for configuration '%s'; expected " + ...
                "one zero-filled response row.", patterns(patternIndex), ...
                nnz(match), configurations(configIndex));
        end
        values(configIndex) = selected.value(match);
    end
    handles(patternIndex) = plot(ax, 1:numel(configurations), values, ...
        Color=palette(patternIndex, :), ...
        LineStyle=lineStyles(mod(patternIndex-1, 4)+1), Marker="o", ...
        LineWidth=1.8, DisplayName=patterns(patternIndex), ...
        Tag="vawlume-support-pattern-response");
end
ax.XTick = 1:numel(configurations);
ax.XTickLabel = configurations;
ax.XTickLabelRotation = 30;
xlabel(ax, "Configuration identifier");
if options.ValueKind == "fraction"
    ylabel(ax, "Exact support-pattern groups (fraction of stated denominator)");
else
    ylabel(ax, "Exact support-pattern groups (count)");
end
title(ax, "Exploratory exact support-pattern response", Interpreter="none");
legend(ax, handles, patterns, Location="eastoutside", Interpreter="none");
grid(ax, "on");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
