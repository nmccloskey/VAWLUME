function [analysis, units] = attributionCorrespondenceUnits(conn, leftReport, rightReport, ref)
%ATTRIBUTIONCORRESPONDENCEUNITS Units of two event sets, from one named analysis's stored rows.
%
% Contract 07 D3. Targets in different event sets correspond only through the
% stored membership rows of the analysis REF names (analysis_run_id, or run_key
% in the runs' project):
%
%   detections against detections    match_group_members of a cross_extractor_matching
%                                    analysis, or agreement_group_members of a
%                                    multi_extractor_agreement analysis
%   detections against consensus     consensus_event_members of the matching
%     events                         analysis that produced those consensus events
%   detections against agreement     agreement_group_members of that agreement
%     groups                         analysis
%   consensus events of two          their SHARED MEMBER DETECTIONS, through both
%     analyses (configurations P, Q)  analyses' consensus_event_members (itinerary
%                                    7.9). REF is struct(shared_member_detections=true):
%                                    the two analyses are the runs' own target
%                                    sources, so no third analysis is named. Both
%                                    must be complete cross_extractor_matching
%                                    analyses over the same extraction runs
%
% A UNIT is one connected component of that membership graph restricted to the
% two runs' targets. Nothing is matched here: no interval, overlap or score is
% read, and no matching or agreement function is called. A target in no stored
% group is a unit of its own (unmatched).
%
% Refused (vawlume:attribution:CorrespondenceAnalysisInvalid) when the analysis
% does not exist, is of another project, is not complete, is of another kind,
% does not take both runs' event sets as its inputs or outputs, or stores no
% row on the runs' recording. Never "the latest analysis".
left = sideEvents(leftReport);
right = sideEvents(rightReport);
if isstruct(ref) && isscalar(ref) && isfield(ref, "shared_member_detections")
    [analysis, edges] = sharedMembers(conn, left, right, leftReport.recording_id);
    units = components(edges, left, right);
    return
end
analysis = resolveAnalysis(conn, leftReport, ref);
if left.set == right.set
    invalid("Runs %d and %d target one event set; compare them without Correspondence.", ...
        leftReport.attribution_run_id, rightReport.attribution_run_id);
end
[analysis.kind, edges] = membership(conn, analysis, left, right, leftReport.recording_id);
units = components(edges, left, right);
end

function analysis = resolveAnalysis(conn, r, ref)
if ~isstruct(ref) || ~isscalar(ref) || ...
        ~(isfield(ref, "analysis_run_id") || isfield(ref, "run_key"))
    invalid("Correspondence must be a struct naming analysis_run_id or run_key.");
end
if isfield(ref, "analysis_run_id")
    predicate = "analysis_run_id=" + string(double(ref.analysis_run_id));
else
    predicate = "run_key='" + replace(string(ref.run_key), "'", "''") + "'";
end
rows = fetch(conn, "SELECT analysis_run_id, project_id, run_type, run_key, status " + ...
    "FROM analysis_runs WHERE " + predicate + " AND project_id=" + ...
    "(SELECT project_id FROM projects WHERE project_key='" + ...
    replace(string(r.project_key), "'", "''") + "')");
if isempty(rows) || height(rows) == 0
    invalid("No analysis run of project %s matches the Correspondence reference.", r.project_key);
end
analysis = struct(analysis_run_id=double(rows.analysis_run_id(1)), ...
    run_key=string(rows.run_key(1)), run_type=string(rows.run_type(1)), kind="");
if ~ismember(string(rows.status(1)), ["completed", "completed_with_warnings"])
    invalid("Analysis %s is %s, not complete.", analysis.run_key, string(rows.status(1)));
end
if ~ismember(analysis.run_type, ["cross_extractor_matching", "multi_extractor_agreement"])
    invalid("Analysis %s is a %s run; correspondence comes from a " + ...
        "cross_extractor_matching or multi_extractor_agreement analysis.", ...
        analysis.run_key, analysis.run_type);
end
inputs = fetch(conn, "SELECT extraction_run_id FROM analysis_run_extraction_inputs " + ...
    "WHERE analysis_run_id=" + string(analysis.analysis_run_id));
analysis.extraction_inputs = double(inputs.extraction_run_id);
end

function side = sideEvents(r)
p = r.provenance;
% Provenance names the set in the plural (detections, consensus_events,
% agreement_groups); targets use the singular kind.
singular = replace(string(p.target_kind), ["detections", "consensus_events", ...
    "agreement_groups"], ["detection", "consensus_event", "agreement_group"]);
side = struct(kind=singular, source_kind=string(p.target_source_kind), ...
    source_id=double(p.target_source_id));
side.set = string(p.target_kind) + " of " + side.source_kind + " " + string(side.source_id);
t = r.targets;
switch side.kind
    case "detection"
        side.events = t.detection_id;
    case "consensus_event"
        side.events = t.consensus_event_id;
    otherwise
        side.events = t.agreement_group_id;
end
side.target_ids = t.attribution_target_id;
end

function [kind, edges] = membership(conn, analysis, left, right, recordingId)
% EDGES: one row per (container, event, side). A container is a stored group or
% consensus event; an event is a target's event on that side.
a = string(analysis.analysis_run_id);
r = string(recordingId);
kinds = [left.kind, right.kind];
if all(kinds == "detection")
    requireInput(analysis, left);
    requireInput(analysis, right);
    if analysis.run_type == "cross_extractor_matching"
        kind = "matching_membership";
        rows = fetch(conn, "SELECT g.match_group_id AS container, m.detection_id AS event " + ...
            "FROM match_groups g JOIN match_group_members m ON m.match_group_id=g.match_group_id " + ...
            "WHERE g.analysis_run_id=" + a + " AND g.recording_id=" + r);
    else
        kind = "agreement_membership";
        rows = fetch(conn, "SELECT g.agreement_group_id AS container, m.detection_id AS event " + ...
            "FROM agreement_groups g JOIN agreement_group_members m ON " + ...
            "m.agreement_group_id=g.agreement_group_id " + ...
            "WHERE g.analysis_run_id=" + a + " AND g.recording_id=" + r);
    end
    requireRows(rows, analysis, recordingId);
    edges = [edgesOf(rows, left, "left"); edgesOf(rows, right, "right")];
elseif any(kinds == "detection") && any(kinds ~= "detection")
    [detectionSide, containerSide, detectionLabel, containerLabel] = orient(left, right);
    requireInput(analysis, detectionSide);
    if containerSide.source_kind ~= "analysis_run" || ...
            containerSide.source_id ~= analysis.analysis_run_id
        invalid("The %s side's targets come from %s, not from analysis %s.", ...
            containerLabel, containerSide.set, analysis.run_key);
    end
    if containerSide.kind == "consensus_event" && ...
            analysis.run_type == "cross_extractor_matching"
        kind = "consensus_membership";
        rows = fetch(conn, "SELECT c.consensus_event_id AS container, m.detection_id AS event " + ...
            "FROM consensus_events c JOIN consensus_event_members m ON " + ...
            "m.consensus_event_id=c.consensus_event_id " + ...
            "WHERE c.analysis_run_id=" + a + " AND c.recording_id=" + r);
    elseif containerSide.kind == "agreement_group" && ...
            analysis.run_type == "multi_extractor_agreement"
        kind = "agreement_membership";
        rows = fetch(conn, "SELECT g.agreement_group_id AS container, m.detection_id AS event " + ...
            "FROM agreement_groups g JOIN agreement_group_members m ON " + ...
            "m.agreement_group_id=g.agreement_group_id " + ...
            "WHERE g.analysis_run_id=" + a + " AND g.recording_id=" + r);
    else
        invalid("Analysis %s (%s) does not store %s membership.", analysis.run_key, ...
            analysis.run_type, containerSide.kind);
    end
    requireRows(rows, analysis, recordingId);
    % The container IS the other side's event: each stored member row is one
    % edge between a detection target and a container target.
    detectionEdges = edgesOf(rows, detectionSide, detectionLabel);
    containerRows = table(double(rows.container), double(rows.container), ...
        VariableNames=["container", "event"]);
    containerEdges = edgesOf(containerRows, containerSide, containerLabel);
    edges = [detectionEdges; unique(containerEdges, "rows")];
else
    invalid("Both runs target %s and %s: two derived event sets join through " + ...
        "their shared member detections (itinerary 7.9), not through a named analysis here.", ...
        left.set, right.set);
end
end

function requireRows(rows, analysis, recordingId)
if isempty(rows) || height(rows) == 0
    invalid("Analysis %s stores no membership row on recording %d.", analysis.run_key, recordingId);
end
end

function [analysis, edges] = sharedMembers(conn, left, right, recordingId)
% Consensus events of two matching analyses join where they share a member
% detection (contract 07 D3, third join). Each stored member row is one edge
% between a consensus-event target and a detection node.
if left.kind ~= "consensus_event" || right.kind ~= "consensus_event" || ...
        left.source_kind ~= "analysis_run" || right.source_kind ~= "analysis_run"
    invalid("shared_member_detections joins consensus events of two matching " + ...
        "analyses; the runs target %s and %s.", left.set, right.set);
end
if left.source_id == right.source_id
    invalid("Both runs target consensus events of analysis %d: one event set; " + ...
        "compare them without Correspondence.", left.source_id);
end
ids = [left.source_id, right.source_id];
rows = fetch(conn, "SELECT analysis_run_id, run_key, run_type, status FROM analysis_runs " + ...
    "WHERE analysis_run_id IN (" + strjoin(string(ids), ",") + ")");
inputs = cell(1, 2);
keys = strings(1, 2);
for k = 1:2
    row = rows(double(rows.analysis_run_id) == ids(k), :);
    if height(row) == 0 || string(row.run_type(1)) ~= "cross_extractor_matching" || ...
            ~ismember(string(row.status(1)), ["completed", "completed_with_warnings"])
        invalid("Consensus source %d is not a complete cross_extractor_matching analysis.", ids(k));
    end
    keys(k) = string(row.run_key(1));
    found = fetch(conn, "SELECT extraction_run_id FROM analysis_run_extraction_inputs " + ...
        "WHERE analysis_run_id=" + string(ids(k)) + " ORDER BY extraction_run_id");
    inputs{k} = double(found.extraction_run_id);
end
if ~isequal(inputs{1}, inputs{2})
    invalid("Analyses %s and %s are over different extraction runs; their consensus " + ...
        "events share no stored member detection to join on.", keys(1), keys(2));
end
edges = table(zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["container", "event", "side"]);
sides = {left, right};
labels = ["left", "right"];
for k = 1:2
    members = fetch(conn, "SELECT m.consensus_event_id AS event, m.detection_id AS container " + ...
        "FROM consensus_event_members m JOIN consensus_events c " + ...
        "ON c.consensus_event_id=m.consensus_event_id WHERE c.analysis_run_id=" + ...
        string(ids(k)) + " AND c.recording_id=" + string(recordingId));
    requireRows(members, struct(run_key=keys(k)), recordingId);
    event = double(members.event);
    keep = ismember(event, sides{k}.events);
    edges = [edges; table(double(members.container(keep)), event(keep), ...
        repmat(labels(k), nnz(keep), 1), VariableNames=["container", "event", "side"])]; %#ok<AGROW>
end
analysis = struct(analysis_run_id=NaN, run_key=keys(1) + " | " + keys(2), ...
    run_type="cross_extractor_matching", kind="shared_member_detections", ...
    extraction_inputs=inputs{1});
end

function requireInput(analysis, side)
if side.source_kind ~= "extraction_run" || ~ismember(side.source_id, analysis.extraction_inputs)
    invalid("Analysis %s does not take %s as an input.", analysis.run_key, side.set);
end
end

function [d, c, dl, cl] = orient(left, right)
if left.kind == "detection"
    d = left; c = right; dl = "left"; cl = "right";
else
    d = right; c = left; dl = "right"; cl = "left";
end
end

function edges = edgesOf(rows, side, label)
% Only members that are this side's targets' events become edges.
edges = table(zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["container", "event", "side"]);
if isempty(rows) || height(rows) == 0
    return
end
container = double(rows.container);
event = double(rows.event);
keep = ismember(event, side.events);
edges = table(container(keep), event(keep), repmat(string(label), nnz(keep), 1), ...
    VariableNames=["container", "event", "side"]);
end

function units = components(edges, left, right)
% Connected components over nodes "c<container>", "l<event>", "r<event>". Every
% target is a node, so a target in no stored group is its own component.
leftNodes = "l" + string(left.events);
rightNodes = "r" + string(right.events);
containerNodes = "c" + string(unique(edges.container));
nodes = unique([leftNodes; rightNodes; containerNodes(:)], "stable");
g = graph();
g = addnode(g, cellstr(nodes));
if height(edges) > 0
    member = edges.side;
    endNodes = strings(height(edges), 1);
    endNodes(member == "left") = "l" + string(edges.event(member == "left"));
    endNodes(member == "right") = "r" + string(edges.event(member == "right"));
    g = addedge(g, cellstr("c" + string(edges.container)), cellstr(endNodes));
end
bins = conncomp(g);
names = string(g.Nodes.Name);
units = struct(left_target_ids={}, right_target_ids={});
for bin = unique(bins)
    inBin = names(bins == bin);
    leftIds = sort(left.target_ids(ismember(leftNodes, inBin)));
    rightIds = sort(right.target_ids(ismember(rightNodes, inBin)));
    if isempty(leftIds) && isempty(rightIds)
        continue
    end
    units(end + 1) = struct(left_target_ids=leftIds(:)', right_target_ids=rightIds(:)'); %#ok<AGROW>
end
% Deterministic order: by smallest left target, then smallest right target.
if isempty(units)
    return
end
keys = zeros(numel(units), 2);
for k = 1:numel(units)
    keys(k, :) = [firstOr(units(k).left_target_ids), firstOr(units(k).right_target_ids)];
end
[~, order] = sortrows(keys);
units = units(order);
end

function value = firstOr(ids)
if isempty(ids)
    value = Inf;
else
    value = ids(1);
end
end

function invalid(varargin)
error("vawlume:attribution:CorrespondenceAnalysisInvalid", varargin{:});
end
