function value = edaExplorationStages(request, name)
%EDAEXPLORATIONSTAGES The exploration workflow's stages and their dependencies.
%
% EDAEXPLORATIONSTAGES("all") returns every stage in execution order.
%
% EDAEXPLORATIONSTAGES("prerequisites", NAME) returns the stages NAME reads
% from directly.
%
% EDAEXPLORATIONSTAGES(REQUESTED) returns the requested stages plus everything
% they depend on, in execution order. A user asking for the diagnostics gets the
% dataset and the reference run too, because the diagnostics read what the
% reference run stored - and refusing instead would make "run only the
% diagnostics" a thing nobody can do.
%
% The order is the dependency order and the dependencies are declared here once,
% so a stage cannot quietly acquire an input that nothing sequenced.

arguments
    request (1,:) string
    name (1,1) string = ""
end

graph = dependencyGraph();
order = string(fieldnames(graph))';

if isscalar(request) && request == "prerequisites"
    if ~isfield(graph, name)
        error("vawlume:eda:ExplorationStageUnknown", ...
            "'%s' is not an exploration stage. The stages are: %s.", ...
            name, strjoin(order, ", "));
    end
    value = graph.(name);
    return
end

if isscalar(request) && request == "all"
    value = order;
    return
end

requested = unique(strtrim(request));
unknown = requested(~ismember(requested, order));
if ~isempty(unknown)
    error("vawlume:eda:ExplorationStageUnknown", ...
        "Unknown exploration stage(s): %s. The stages are: %s.", ...
        strjoin(unknown, ", "), strjoin(order, ", "));
end

included = requested;
changed = true;
while changed
    changed = false;
    for stage = included
        needed = graph.(stage);
        missing = needed(~ismember(needed, included));
        if ~isempty(missing)
            included = [included, missing]; %#ok<AGROW>
            changed = true;
        end
    end
end

value = order(ismember(order, included));
end

function value = dependencyGraph()
%DEPENDENCYGRAPH Declared in execution order; the field order IS the run order.
value = struct();
value.dataset = strings(1, 0);
value.reference = "dataset";
value.diagnostics = "reference";
value.probe = "diagnostics";
value.screen = "probe";
value.subset = "screen";
value.concordance = ["screen", "subset"];
value.support_patterns = "reference";
value.examples = ["reference", "probe"];
value.exports = "dataset";
end
