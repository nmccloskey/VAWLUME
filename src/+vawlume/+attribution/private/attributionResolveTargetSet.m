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
    % Every declared method is checked, not merely the first. A group missing
    % one of them would otherwise produce a target with no interval to compare.
    for method = extentMethod'
        extentRows = fetch(conn, "SELECT agreement_group_id FROM " + ...
            "v_agreement_group_extent WHERE agreement_group_id IN (" + ...
            idList(ids) + ") AND extent_method=" + sqlText(method));
        if isempty(extentRows) || height(extentRows) ~= numel(ids)
            error("vawlume:attribution:TargetSpecInvalid", ...
                "Every agreement-group target must have the requested derived " + ...
                "extent '%s'.", method);
        end
    end
end

if kind == "agreement_groups"
    % One target per (group, extent basis). A group compared under two bases is
    % two targets, because the two have different intervals: a correspondence
    % against the union extent is not a correspondence against the intersection
    % extent, and storing them as one row would make the basis unrecoverable.
    [groupColumn, methodColumn] = crossProduct(ids, extentMethod);
    targets = emptyTargets(numel(groupColumn));
    targets.agreement_group_id = groupColumn;
    targets.agreement_extent_method = methodColumn;
else
    targets = emptyTargets(numel(ids));
    switch kind
        case "detections"
            targets.detection_id = ids;
        otherwise
            targets.consensus_event_id = ids;
    end
end
targets.target_ordinal = (1:height(targets))';
targets.action(:) = "create";

resolved = struct();
resolved.targets = targets;
resolved.event_set = struct(kind=kind, source_kind=sourceKind, ...
    source_id=sourceIds(1), target_ids=ids, ...
    agreement_extent_method=extentMethod);
end

function value = agreementExtentMethod(targetSpec)
%AGREEMENTEXTENTMETHOD The extent bases this target set is computed on.
%
% One method or several. An agreement group has no intrinsic interval -- five
% derivations are defensible and none is ground truth -- so which one a result
% rests on is an analytical choice, and comparing two of them should not require
% a second attribution run over a separately ingested copy of the same claims.
%
% Returned sorted and deduplicated so target identity is canonical: two specs
% naming the same bases in different orders describe the same target set, and
% resolveTargets must not report a conflict between them.
if ~isfield(targetSpec, "agreement_extent_method")
    error("vawlume:attribution:TargetSpecInvalid", ...
        "An agreement-group target set requires agreement_extent_method.");
end
value = textVector(targetSpec.agreement_extent_method, ...
    "targetSpec.agreement_extent_method");
allowed = ["union_boundary_of_members", ...
    "intersection_boundary_of_members", "mean_boundary_of_members", ...
    "longest_member_boundary", "shortest_member_boundary"];
offenders = value(~ismember(value, allowed));
if ~isempty(offenders)
    error("vawlume:attribution:TargetSpecInvalid", ...
        "agreement_extent_method names '%s', which is not one of the five " + ...
        "schema methods.", strjoin(unique(offenders, "stable"), "', '"));
end
% Refused rather than silently deduplicated: a caller who named a basis twice
% believed something about this run that is not true, and quietly collapsing it
% would hide the misunderstanding instead of correcting it.
if numel(unique(value)) ~= numel(value)
    error("vawlume:attribution:TargetSpecInvalid", ...
        "agreement_extent_method repeats a basis. Each (group, extent basis) " + ...
        "pair is one target, so a repeat would ask for the same target twice.");
end
value = sort(value);
end

function [groups, methods] = crossProduct(ids, extentMethods)
%CROSSPRODUCT Group-major, methods ascending, so the order is deterministic.
%
% Determinism matters beyond tidiness: attributionTargetsEqual compares stored
% and resolved targets elementwise, so a resolution order that varied with the
% caller's spelling would report a conflict between two identical target sets.
count = numel(ids) * numel(extentMethods);
groups = NaN(count, 1);
methods = strings(count, 1);
position = 0;
for groupIndex = 1:numel(ids)
    for methodIndex = 1:numel(extentMethods)
        position = position + 1;
        groups(position) = ids(groupIndex);
        methods(position) = extentMethods(methodIndex);
    end
end
end

function value = textVector(raw, label)
try
    value = strtrim(string(raw));
catch
    error("vawlume:attribution:TargetSpecInvalid", ...
        "%s must be text.", label);
end
value = value(:);
if isempty(value) || any(ismissing(value)) || any(strlength(value) == 0)
    error("vawlume:attribution:TargetSpecInvalid", ...
        "%s must be one or more nonempty strings.", label);
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
