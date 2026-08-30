function [actualField, resolution, issue] = resolveMappedColumn(tbl, rule, defaults, location, required, missingCode)
%RESOLVEMAPPEDCOLUMN Resolve one declared table column without fuzzy guessing.

actualField = "";
resolution = "";
issue = [];
variableNames = string(tbl.Properties.VariableNames);

sourceField = optionalRuleText(rule, "source_field");
if strlength(sourceField) > 0 && any(variableNames == sourceField)
    actualField = sourceField;
    resolution = "exact";
    return
end

aliases = ruleTextSequence(rule, "aliases");
aliasMatches = variableNames(ismember(variableNames, aliases));
if isscalar(aliasMatches)
    actualField = aliasMatches;
    resolution = "alias";
    return
elseif numel(aliasMatches) > 1
    issue = makeIssue("error", "COLUMN_AMBIGUOUS", location, ...
        "Several declared aliases are present: " + strjoin(aliasMatches, ", ") + ".");
    return
end

declaredDefaults = ruleTextSequence(rule, "default_source_fields");
candidateDefaults = unique([declaredDefaults(:); string(defaults(:))], "stable");
defaultMatches = variableNames(ismember(variableNames, candidateDefaults));
if isscalar(defaultMatches)
    actualField = defaultMatches;
    resolution = "default";
    return
elseif numel(defaultMatches) > 1
    issue = makeIssue("error", "COLUMN_AMBIGUOUS", location, ...
        "Several deterministic default columns are present: " + ...
        strjoin(defaultMatches, ", ") + ". Declare source_field explicitly.");
    return
end

if required
    label = sourceField;
    if strlength(label) == 0
        label = strjoin(candidateDefaults, " or ");
    end
    issue = makeIssue("error", missingCode, location, ...
        "Required mapped source column is absent: " + label + ".");
end
end

function value = optionalRuleText(rule, field)
value = "";
if ~isstruct(rule) || ~isfield(rule, char(field)) || isempty(rule.(char(field)))
    return
end
try
    candidate = string(rule.(char(field)));
    if isscalar(candidate) && ~ismissing(candidate)
        value = candidate;
    end
catch
end
end

function values = ruleTextSequence(rule, field)
values = strings(0, 1);
if ~isstruct(rule) || ~isfield(rule, char(field)) || isempty(rule.(char(field)))
    return
end
raw = rule.(char(field));
if iscell(raw)
    values = strings(numel(raw), 1);
    for index = 1:numel(raw)
        values(index) = string(raw{index});
    end
else
    try
        values = string(raw(:));
    catch
        values = strings(0, 1);
    end
end
values = values(~ismissing(values) & strlength(values) > 0);
end
