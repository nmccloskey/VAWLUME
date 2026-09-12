function [target, run] = attributionResolveTarget(conn, targetRef)
%ATTRIBUTIONRESOLVETARGET Resolve one stored target and its attribution run.

if ~isstruct(targetRef) || ~isscalar(targetRef)
    error("vawlume:attribution:TargetRefInvalid", ...
        "targetRef must be a scalar struct.");
end
hasId = isfield(targetRef, "attribution_target_id");
hasPortable = isfield(targetRef, "project_key") || ...
    isfield(targetRef, "run_key");
if hasId == hasPortable
    error("vawlume:attribution:TargetRefInvalid", ...
        "targetRef must contain attribution_target_id, or project_key, run_key, and one event ID.");
end

if hasId
    targetId = positiveInteger(targetRef.attribution_target_id, ...
        "targetRef.attribution_target_id");
    row = fetch(conn, "SELECT attribution_run_id FROM attribution_targets " + ...
        "WHERE attribution_target_id=" + string(targetId));
    if isempty(row) || height(row) == 0
        error("vawlume:attribution:TargetNotFound", ...
            "Attribution target %d does not exist.", targetId);
    end
    run = attributionResolveRun(conn, struct( ...
        attribution_run_id=double(row.attribution_run_id(1))));
    targets = attributionReadTargets(conn, run.attribution_run_id);
    match = targets.attribution_target_id == targetId;
else
    if ~isfield(targetRef, "project_key") || ~isfield(targetRef, "run_key")
        error("vawlume:attribution:TargetRefInvalid", ...
            "A portable targetRef requires project_key and run_key.");
    end
    run = attributionResolveRun(conn, struct( ...
        project_key=targetRef.project_key, run_key=targetRef.run_key));
    targets = attributionReadTargets(conn, run.attribution_run_id);
    selectors = ["detection_id", "consensus_event_id", "agreement_group_id"];
    present = false(size(selectors));
    for index = 1:numel(selectors)
        present(index) = isfield(targetRef, selectors(index));
    end
    if sum(present) ~= 1
        error("vawlume:attribution:TargetRefInvalid", ...
            "A portable targetRef must name exactly one detection_id, consensus_event_id, or agreement_group_id.");
    end
    selector = selectors(present);
    eventId = positiveInteger(targetRef.(selector), "targetRef." + selector);
    match = targets.(selector) == eventId;
    if selector == "agreement_group_id" && ...
            isfield(targetRef, "agreement_extent_method")
        extent = scalarText(targetRef.agreement_extent_method, ...
            "targetRef.agreement_extent_method");
        match = match & targets.agreement_extent_method == extent;
    elseif selector ~= "agreement_group_id" && ...
            isfield(targetRef, "agreement_extent_method")
        error("vawlume:attribution:TargetRefInvalid", ...
            "agreement_extent_method only disambiguates an agreement-group target.");
    end
end

indices = find(match);
if isempty(indices)
    error("vawlume:attribution:TargetNotFound", ...
        "No stored target matches targetRef.");
end
if numel(indices) ~= 1
    error("vawlume:attribution:TargetAmbiguous", ...
        "targetRef matched %d stored targets.", numel(indices));
end
row = targets(indices, :);
target = struct( ...
    attribution_target_id=double(row.attribution_target_id), ...
    attribution_run_id=double(row.attribution_run_id), ...
    target_ordinal=double(row.target_ordinal), ...
    detection_id=double(row.detection_id), ...
    consensus_event_id=double(row.consensus_event_id), ...
    agreement_group_id=double(row.agreement_group_id), ...
    agreement_extent_method=string(row.agreement_extent_method), ...
    notes=string(row.notes));
end

function value = positiveInteger(raw, label)
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || ...
        raw < 1 || fix(raw) ~= raw
    error("vawlume:attribution:TargetRefInvalid", ...
        "%s must be a positive integer.", label);
end
value = double(raw);
end

function value = scalarText(raw, label)
try
    value = strtrim(string(raw));
catch
    error("vawlume:attribution:TargetRefInvalid", ...
        "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("vawlume:attribution:TargetRefInvalid", ...
        "%s must be nonempty scalar text.", label);
end
end
