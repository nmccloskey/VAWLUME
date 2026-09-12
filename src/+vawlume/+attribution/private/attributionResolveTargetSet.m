function resolved = attributionResolveTargetSet(conn, recording, targetSpec)
%ATTRIBUTIONRESOLVETARGETSET Resolve one explicit, single-kind event set.

fields = ["detection_ids", "consensus_event_ids", "agreement_group_ids"];
present = arrayfun(@(name) isfield(targetSpec, name), fields);
if sum(present) > 1
    error("vawlume:attribution:TargetSetMixed", ...
        "An attribution run targets exactly one event-set kind, not a mixture.");
end
if ~any(present)
    error("vawlume:attribution:TargetSetEmpty", ...
        "targetSpec must name one nonempty event set.");
end

selectedField = fields(present);
ids = identifierVector(targetSpec.(selectedField), "targetSpec." + selectedField);
if isempty(ids)
    error("vawlume:attribution:TargetSetEmpty", ...
        "The requested attribution target set is empty.");
end

switch selectedField
    case "detection_ids"
        kind = "detections";
        rows = fetch(conn, "SELECT d.detection_id AS event_id, " + ...
            "d.recording_id, er.project_id, d.extraction_run_id AS source_id " + ...
            "FROM detections d JOIN extraction_runs er " + ...
            "ON er.extraction_run_id=d.extraction_run_id " + ...
            "WHERE d.detection_id IN (" + idList(ids) + ") " + ...
            "ORDER BY d.detection_id");
        extentMethod = "";
        sourceKind = "extraction_run";
    case "consensus_event_ids"
        kind = "consensus_events";
        rows = fetch(conn, "SELECT ce.consensus_event_id AS event_id, " + ...
            "ce.recording_id, ar.project_id, ce.analysis_run_id AS source_id " + ...
            "FROM consensus_events ce JOIN analysis_runs ar " + ...
            "ON ar.analysis_run_id=ce.analysis_run_id " + ...
            "WHERE ce.consensus_event_id IN (" + idList(ids) + ") " + ...
            "ORDER BY ce.consensus_event_id");
        extentMethod = "";
        sourceKind = "analysis_run";
    otherwise
        kind = "agreement_groups";
        rows = fetch(conn, "SELECT ag.agreement_group_id AS event_id, " + ...
            "ag.recording_id, ar.project_id, ag.analysis_run_id AS source_id " + ...
            "FROM agreement_groups ag JOIN analysis_runs ar " + ...
            "ON ar.analysis_run_id=ag.analysis_run_id " + ...
            "WHERE ag.agreement_group_id IN (" + idList(ids) + ") " + ...
            "ORDER BY ag.agreement_group_id");
        extentMethod = agreementExtentMethod(targetSpec);
        sourceKind = "analysis_run";
end

if isempty(rows) || height(rows) ~= numel(ids)
    error("vawlume:attribution:TargetNotFound", ...
        "One or more requested %s do not exist.", kind);
end
if any(double(rows.recording_id) ~= recording.recording_id) || ...
        any(double(rows.project_id) ~= recording.project_id)
    error("vawlume:attribution:TargetSetCrossesRecording", ...
        "Every target must belong to recording %d and project '%s'.", ...
        recording.recording_id, recording.project_key);
end
sourceIds = unique(double(rows.source_id));
if numel(sourceIds) ~= 1
    error("vawlume:attribution:TargetSetMixed", ...
        "The selected %s come from more than one source event set.", kind);
end
if kind == "agreement_groups"
    extentRows = fetch(conn, "SELECT agreement_group_id FROM " + ...
        "v_agreement_group_extent WHERE agreement_group_id IN (" + ...
        idList(ids) + ") AND extent_method=" + sqlText(extentMethod));
    if isempty(extentRows) || height(extentRows) ~= numel(ids)
        error("vawlume:attribution:TargetSpecInvalid", ...
            "Every agreement-group target must have the requested derived extent.");
    end
end

targets = emptyTargets(numel(ids));
targets.target_ordinal = (1:numel(ids))';
targets.action(:) = "create";
switch kind
    case "detections"
        targets.detection_id = ids;
    case "consensus_events"
        targets.consensus_event_id = ids;
    otherwise
        targets.agreement_group_id = ids;
        targets.agreement_extent_method(:) = extentMethod;
end

resolved = struct();
resolved.targets = targets;
resolved.event_set = struct(kind=kind, source_kind=sourceKind, ...
    source_id=sourceIds(1), target_ids=ids, ...
    agreement_extent_method=extentMethod);
end

function value = agreementExtentMethod(targetSpec)
if ~isfield(targetSpec, "agreement_extent_method")
    error("vawlume:attribution:TargetSpecInvalid", ...
        "An agreement-group target set requires agreement_extent_method.");
end
value = scalarText(targetSpec.agreement_extent_method, ...
    "targetSpec.agreement_extent_method");
allowed = ["union_boundary_of_members", ...
    "intersection_boundary_of_members", "mean_boundary_of_members", ...
    "longest_member_boundary", "shortest_member_boundary"];
if ~ismember(value, allowed)
    error("vawlume:attribution:TargetSpecInvalid", ...
        "agreement_extent_method is not one of the five schema methods.");
end
end

function value = identifierVector(raw, label)
if isempty(raw)
    value = zeros(0, 1);
    return
end
if ~isnumeric(raw) || ~isvector(raw) || any(~isfinite(raw)) || ...
        any(raw < 1) || any(fix(raw) ~= raw)
    error("vawlume:attribution:TargetSpecInvalid", ...
        "%s must be a vector of positive integer identifiers.", label);
end
value = unique(double(raw(:)));
end

function value = scalarText(raw, label)
try
    value = strtrim(string(raw));
catch
    error("vawlume:attribution:TargetSpecInvalid", ...
        "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("vawlume:attribution:TargetSpecInvalid", ...
        "%s must be nonempty scalar text.", label);
end
end

function value = idList(ids)
value = strjoin(string(ids'), ",");
end

function value = sqlText(raw)
value = "'" + replace(string(raw), "'", "''") + "'";
end

function targets = emptyTargets(count)
targets = table(NaN(count, 1), NaN(count, 1), zeros(count, 1), ...
    NaN(count, 1), NaN(count, 1), NaN(count, 1), strings(count, 1), ...
    strings(count, 1), strings(count, 1), ...
    VariableNames=["attribution_target_id", "attribution_run_id", ...
    "target_ordinal", ...
    "detection_id", "consensus_event_id", "agreement_group_id", ...
    "agreement_extent_method", "notes", "action"]);
end
