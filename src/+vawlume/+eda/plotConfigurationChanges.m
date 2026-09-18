function fig = plotConfigurationChanges(responses, options)
%PLOTCONFIGURATIONCHANGES Precomputed group-change classes by configuration.

arguments
    responses table
    options.Response (1,1) string = "group_change_from"
    options.ValueKind (1,1) string {mustBeMember(options.ValueKind, ...
        ["count", "fraction"])} = "count"
    options.Scope (1,1) string = "pooled"
    options.BaselineConfigurationId (1,1) string = ""
    options.Visible (1,1) logical = false
    options.FigureSizeInches (1,2) double {mustBePositive} = [11 7]
    options.ExportPath (1,1) string = ""
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
end

required = ["configuration_id", "scope", "response", "qualifier_kind", ...
    "qualifier", "secondary", "value", "denominator", "value_kind"];
edaRequireTableColumns(responses, required, "Screen-response table");
rows = responses(responses.scope == options.Scope & ...
    responses.response == options.Response & ...
    responses.qualifier_kind == "change_class" & ...
    responses.value_kind == options.ValueKind, :);
if strlength(options.BaselineConfigurationId) > 0
    rows = rows(rows.secondary == options.BaselineConfigurationId, :);
end
if height(rows) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "No configuration-change response matches the supplied selectors.");
end
configurations = sort(unique(rows.configuration_id));
if numel(configurations) < 2
    error("vawlume:eda:PlotConfigurationDegenerate", ...
        "A configuration comparison requires at least two configurations.");
end
classes = sort(unique(rows.qualifier));
values = nan(numel(configurations), numel(classes));
for configIndex = 1:numel(configurations)
    for classIndex = 1:numel(classes)
        match = rows.configuration_id == configurations(configIndex) & ...
            rows.qualifier == classes(classIndex);
        if nnz(match) ~= 1
            error("vawlume:eda:PlotInputInvalid", ...
                "Configuration '%s' and change class '%s' do not have " + ...
                "exactly one precomputed row.", configurations(configIndex), ...
                classes(classIndex));
        end
        values(configIndex, classIndex) = rows.value(match);
    end
end
caution = edaCautionNote();
[fig, ax] = edaPlotFigure(options.Visible, options.FigureSizeInches, ...
    caution, "Change classes are the supplied group-identity comparison. " + ...
    "The view selects no configuration and highlights no maximum.");
bars = bar(ax, values, "grouped", Tag="vawlume-configuration-changes");
palette = parula(max(numel(classes), 2));
for index = 1:numel(bars)
    bars(index).FaceColor = palette(index, :);
end
ax.XTickLabel = configurations;
ax.XTickLabelRotation = 30;
xlabel(ax, "Configuration identifier");
if options.ValueKind == "fraction"
    ylabel(ax, "Agreement groups (fraction of stated baseline denominator)");
else
    ylabel(ax, "Agreement groups (count by change class)");
end
title(ax, "Exploratory configuration-to-reference changes");
legend(ax, classes, Location="eastoutside", Interpreter="none");
grid(ax, "on");
edaMaybeExport(fig, options.ExportPath, options.ResolutionDpi, ...
    options.FigureSizeInches);
end
