function rows = edaSelectResponseIdentity(table0, selector, context)
%EDASELECTRESPONSEIDENTITY Select one tidy response identity without collapsing.
required = ["response", "qualifier_kind", "qualifier", "secondary_kind", ...
    "secondary", "value_kind"];
edaRequireTableColumns(table0, required, context);
rows = table0(table0.response == selector.Response, :);
for pair = {"QualifierKind", "qualifier_kind"; "Qualifier", "qualifier"; ...
        "SecondaryKind", "secondary_kind"; "Secondary", "secondary"; ...
        "ValueKind", "value_kind"}'
    optionName = pair{1};
    columnName = pair{2};
    value = string(selector.(optionName));
    if strlength(value) > 0
        rows = rows(rows.(columnName) == value, :);
    end
end
if height(rows) == 0
    error("vawlume:eda:PlotSelectionEmpty", ...
        "%s has no row matching response '%s' and the supplied selectors.", ...
        context, selector.Response);
end
identity = unique(rows(:, required), "rows");
if height(identity) ~= 1
    error("vawlume:eda:PlotSelectionAmbiguous", ...
        "%s selectors leave %d response identities. Supply qualifier, " + ...
        "secondary and value-kind selectors until exactly one remains.", ...
        context, height(identity));
end
end
