function graph = agreementResolveGraph(conn, recording, sources, extractorRuns)
%AGREEMENTRESOLVEGRAPH Collect the detection nodes and exact support edges.
%
% Nodes are every native detection of the participating extraction runs on this
% recording, including detections with no support edge at all. An
% extractor-unique event has to reach composition to survive it as a singleton.
%
% Support edges are the stored candidate_pairs rows of the declared source
% analyses, each retaining its exact candidate_pair_id. That is the whole edge
% universe, and it is the frozen eligibility rule:
%
%   Every stored candidate row of a source analysis is a support edge.
%
% This is a statement about the current matcher, not an assumption. Candidate
% generation keeps every pair that satisfies the specification's plausibility
% rule and performs no best-candidate reduction, assignment consumes all of them
% as graph edges, and each row is written with candidate_status 'eligible'. So
% the stored candidate set and the set of edges that actually participate in the
% pairwise partition are the same set.
%
% Because that identity is load-bearing here, it is verified rather than
% trusted. Where a source analysis materialized its match groups, every edge is
% required to join two detections of one group; an edge that does not is refused
% rather than composed, which is what a future rejected-candidate state or a
% hand-authored analysis would trip. Where a source analysis materialized no
% groups its candidate rows remain the assessed edge set, and their pairwise
% topology is reported as absent rather than guessed.

nodes = resolveNodes(conn, recording, extractorRuns);
edges = resolveEdges(conn, recording, sources, nodes);
graph = struct(nodes=nodes, edges=edges, eligibility=eligibilityRule());
end

function rule = eligibilityRule()
rule = struct( ...
    edge_universe="stored_candidate_pairs_of_declared_source_analyses", ...
    status_filter="none_applied", ...
    status_reason="Candidate generation writes one status, 'eligible', and " + ...
        "performs no best-candidate reduction, so no accepted/rejected " + ...
        "distinction exists to filter on.", ...
    coherence_check="every_edge_joins_one_pairwise_match_group_where_groups_exist", ...
    transitive_edges="never_synthesized");
end

function nodes = resolveNodes(conn, recording, extractorRuns)
runList = strjoin(string(extractorRuns.extraction_run_id'), ",");
rows = fetch(conn, "SELECT vc.detection_id, vc.extraction_run_id, " + ...
    "vc.extraction_run_key, vc.extractor_name, vc.native_event_id, " + ...
    "vc.start_time_s, vc.end_time_s FROM v_detection_core vc " + ...
    "WHERE vc.recording_id=" + string(recording.recording_id) + ...
    " AND vc.extraction_run_id IN (" + runList + ") ORDER BY vc.detection_id");
if isempty(rows) || height(rows) == 0
    nodes = emptyNodes();
    return
end
nodes = table(double(rows.detection_id), double(rows.extraction_run_id), ...
    presentText(rows.extraction_run_key), presentText(rows.extractor_name), ...
    presentText(rows.native_event_id), double(rows.start_time_s), ...
    double(rows.end_time_s), VariableNames=["detection_id", ...
    "extraction_run_id", "extraction_run_key", "extractor_name", ...
    "native_event_id", "start_time_s", "end_time_s"]);
nodes.selector = nodes.extraction_run_key + "#" + nodes.native_event_id;
if numel(unique(nodes.detection_id)) ~= height(nodes)
    error("vawlume:agreement:NodeSetInvalid", ...
        "One detection resolved more than once into the node set.");
end
end

function edges = resolveEdges(conn, recording, sources, nodes)
edges = emptyEdges();
for index = 1:height(sources)
    edges = [edges; sourceEdges(conn, recording, sources(index, :), nodes)]; %#ok<AGROW>
end
if height(edges) == 0
    return
end
edges = sortrows(edges, ["node_a", "node_b"]);
pairKeys = string(edges.node_a) + ":" + string(edges.node_b);
[distinct, ~, grouping] = unique(pairKeys);
repeated = distinct(accumarray(grouping, 1) > 1);
if ~isempty(repeated)
    error("vawlume:agreement:DuplicateSupportEdge", ...
        "Detection pair %s is supported by more than one source analysis. " + ...
        "One unordered extractor pair is covered by exactly one analysis, so " + ...
        "this indicates incompatible source evidence.", ...
        strjoin("'" + repeated(:)' + "'", ", "));
end
end

function rows = sourceEdges(conn, recording, source, nodes)
analysisId = source.analysis_run_id;
stored = fetch(conn, "SELECT candidate_pair_id, detection_a_id, " + ...
    "detection_b_id, IFNULL(temporal_iou,1e308) AS temporal_iou, " + ...
    "IFNULL(candidate_status,'') AS candidate_status FROM candidate_pairs " + ...
    "WHERE analysis_run_id=" + string(analysisId) + ...
    " AND recording_id=" + string(recording.recording_id) + ...
    " ORDER BY candidate_pair_id");
rows = emptyEdges();
if isempty(stored) || height(stored) == 0
    return
end
partition = pairwisePartition(conn, analysisId);
for index = 1:height(stored)
    nodeA = double(stored.detection_a_id(index));
    nodeB = double(stored.detection_b_id(index));
    if ~ismember(nodeA, nodes.detection_id) || ~ismember(nodeB, nodes.detection_id)
        error("vawlume:agreement:EdgeOutsideNodeSet", ...
            "Source analysis '%s' has candidate pair %d whose detections are " + ...
            "not both in the participating node set.", source.run_key, ...
            double(stored.candidate_pair_id(index)));
    end
    [groupId, matchType] = partitionOf(partition, nodeA, nodeB, ...
        source.run_key, double(stored.candidate_pair_id(index)));
    rows(end + 1, :) = {double(stored.candidate_pair_id(index)), ...
        analysisId, source.run_key, source.pair_label, nodeA, nodeB, ...
        double(stored.temporal_iou(index)), ...
        presentText(stored.candidate_status(index)), groupId, matchType}; %#ok<AGROW>
end
end

function partition = pairwisePartition(conn, analysisId)
%PAIRWISEPARTITION Detection to pairwise group and topology, for one analysis.
rows = fetch(conn, "SELECT mgm.detection_id, mg.match_group_id, mg.match_type " + ...
    "FROM match_group_members mgm " + ...
    "JOIN match_groups mg ON mg.match_group_id=mgm.match_group_id " + ...
    "WHERE mg.analysis_run_id=" + string(analysisId));
if isempty(rows) || height(rows) == 0
    partition = struct(materialized=false, detection_id=zeros(0, 1), ...
        match_group_id=zeros(0, 1), match_type=strings(0, 1));
    return
end
partition = struct(materialized=true, ...
    detection_id=double(rows.detection_id), ...
    match_group_id=double(rows.match_group_id), ...
    match_type=presentText(rows.match_type));
end

function [groupId, matchType] = partitionOf(partition, nodeA, nodeB, runKey, candidateId)
% A pairwise analysis with no groups reports absence, not ambiguity: the pair
% was assessed and its edges stand, but no topology was derived from them.
if ~partition.materialized
    groupId = NaN;
    matchType = "no_group_materialized";
    return
end
left = partition.match_group_id(partition.detection_id == nodeA);
right = partition.match_group_id(partition.detection_id == nodeB);
if numel(left) ~= 1 || numel(right) ~= 1 || left(1) ~= right(1)
    error("vawlume:agreement:EdgeOutsidePairwisePartition", ...
        "Source analysis '%s' stores candidate pair %d whose detections do " + ...
        "not share one match group. The composition rule assumes every " + ...
        "stored candidate edge participates in its own analysis's partition, " + ...
        "so this evidence is refused rather than composed.", runKey, candidateId);
end
groupId = left(1);
matchType = partition.match_type(partition.detection_id == nodeA);
matchType = matchType(1);
end

function value = emptyNodes()
value = table(zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["detection_id", "extraction_run_id", "extraction_run_key", ...
    "extractor_name", "native_event_id", "start_time_s", "end_time_s", ...
    "selector"]);
end

function value = emptyEdges()
value = table(zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), VariableNames=["candidate_pair_id", ...
    "source_analysis_run_id", "source_run_key", "pair_label", "node_a", ...
    "node_b", "temporal_iou", "candidate_status", "pairwise_match_group_id", ...
    "pairwise_match_type"]);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
