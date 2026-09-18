function edaRequireTableColumns(value, names, context)
%EDAREQUIRETABLECOLUMNS Uniform, specific input errors for plot consumers.
if ~istable(value)
    error("vawlume:eda:PlotInputInvalid", ...
        "%s must be a precomputed table.", context);
end
missingNames = names(~ismember(names, string(value.Properties.VariableNames)));
if ~isempty(missingNames)
    error("vawlume:eda:PlotInputInvalid", ...
        "%s is missing column(s): %s.", context, strjoin(missingNames, ", "));
end
end
