function [groups, members, supportEdges] = agreementBuildComponents(graph, specification)
%AGREEMENTBUILDCOMPONENTS Compose components, keeping every exact support edge.
%
% Membership comes from connectivity. Support comes from the exact edges. Those
% are different facts and this function keeps them apart: a component of three
% detections says they are connected, never that all three extractor pairs
% support each other, and no edge is added to make a component look complete.
%
% Each group reports several separate dimensions rather than one verdict:
% member and extractor counts, which unordered extractor pairs are supported,
% which are not, and which contributing pairwise topologies were ambiguous. A
% component can be complete at extractor-pair level and still ambiguous because
% one source pair resolved one-to-many; another can be partial yet unambiguous
% among the links it has. Collapsing those into a single score or flag would
% destroy the distinction, so none is computed and none is stored.
%
% Nothing here is persisted except identity, membership, and edges. The reported
% dimensions are query products, recomputed from the stored rows whenever they
% are wanted.

assignment = vawlume.agreement.internal.connectedComponents( ...
    graph.nodes.detection_id, edgeMatrix(graph.edges));

groups = emptyGroups();
members = emptyMembers();
supportEdges = emptySupportEdges();
if height(assignment) == 0
    return
end

ordinals = unique(assignment.component_ordinal);
for index = 1:numel(ordinals)
    ordinal = ordinals(index);
    nodeIds = assignment.node_id(assignment.component_ordinal == ordinal);
    selectedNodes = graph.nodes(ismember(graph.nodes.detection_id, nodeIds), :);
    selectedNodes = sortrows(selectedNodes, "detection_id");
    selectedEdges = graph.edges(ismember(graph.edges.node_a, nodeIds), :);

    groups(end + 1, :) = {ordinal, groupKey(selectedNodes), ...
        specification.component_rule, NaN, "create"}; %#ok<AGROW>
    for memberIndex = 1:height(selectedNodes)
        members(end + 1, :) = {ordinal, selectedNodes.detection_id(memberIndex), ...
            selectedNodes.selector(memberIndex), ...
            selectedNodes.extractor_name(memberIndex), "member", NaN, ...
            "create"}; %#ok<AGROW>
    end
    for edgeIndex = 1:height(selectedEdges)
        supportEdges(end + 1, :) = {ordinal, ...
            selectedEdges.candidate_pair_id(edgeIndex), ...
            selectedEdges.source_analysis_run_id(edgeIndex), ...
            selectedEdges.source_run_key(edgeIndex), ...
            selectedEdges.pair_label(edgeIndex), ...
            selectedEdges.node_a(edgeIndex), selectedEdges.node_b(edgeIndex), ...
            selectedEdges.pairwise_match_type(edgeIndex), NaN, "create"}; %#ok<AGROW>
    end
end
groups = attachReportedDimensions(groups, members, supportEdges);
end

function value = groupKey(selectedNodes)
%GROUPKEY Machine-derived component identity from run-scoped native selectors.
%
% Extraction-run key plus native event id is the stable selector established for
% this fixture family; detection ids are surrogates. Sorting makes the key
% independent of how the component was traversed, so a rerun that walks the same
% graph in another order resolves to the same stored group.
%
% It is an identity, not a summary. Nothing derivable about support belongs here,
% and free-form notes are never part of identity.
value = strjoin(sort(selectedNodes.selector)', "|");
end

function groups = attachReportedDimensions(groups, members, supportEdges)
groups.member_count = zeros(height(groups), 1);
groups.extractor_count = zeros(height(groups), 1);
groups.extractor_names = strings(height(groups), 1);
groups.support_edge_count = zeros(height(groups), 1);
groups.supported_pair_labels = strings(height(groups), 1);
groups.unsupported_pair_labels = strings(height(groups), 1);
groups.ambiguous_source_topologies = strings(height(groups), 1);
groups.is_singleton = false(height(groups), 1);
groups.pair_support_complete = false(height(groups), 1);

for index = 1:height(groups)
    ordinal = groups.component_ordinal(index);
    componentMembers = members(members.component_ordinal == ordinal, :);
    componentEdges = supportEdges(supportEdges.component_ordinal == ordinal, :);
    extractors = unique(componentMembers.extractor_name);

    groups.member_count(index) = height(componentMembers);
    groups.extractor_count(index) = numel(extractors);
    groups.extractor_names(index) = strjoin(sort(extractors)', ",");
    groups.support_edge_count(index) = height(componentEdges);
    groups.is_singleton(index) = height(componentMembers) == 1;

    % Coarse support is summarized at the extractor-pair level, never by raw
    % detection-edge count. A component holding two MUPET syllables against one
    % DeepSqueak call keeps all its edges, and still supports exactly one pair.
    supported = unique(componentEdges.pair_label);
    possible = unorderedPairLabels(extractors);
    groups.supported_pair_labels(index) = strjoin(sort(supported)', ";");
    groups.unsupported_pair_labels(index) = ...
        strjoin(sort(setdiff(possible, supported))', ";");
    groups.pair_support_complete(index) = ...
        numel(possible) > 0 && isempty(setdiff(possible, supported));

    ambiguous = unique(componentEdges.pairwise_match_type( ...
        ismember(componentEdges.pairwise_match_type, ...
        ["one_to_many", "many_to_one", "many_to_many"])));
    groups.ambiguous_source_topologies(index) = strjoin(sort(ambiguous)', ";");
end
end

function value = edgeMatrix(edges)
if height(edges) == 0
    value = zeros(0, 2);
    return
end
value = [edges.node_a, edges.node_b];
end

function labels = unorderedPairLabels(names)
labels = strings(0, 1);
sorted = sort(names);
for left = 1:numel(sorted) - 1
    for right = left + 1:numel(sorted)
        labels(end + 1, 1) = strjoin(sort([sorted(left), sorted(right)]), "|"); %#ok<AGROW>
    end
end
labels = unique(labels);
end

function value = emptyGroups()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), VariableNames=["component_ordinal", "group_key", ...
    "derivation_method", "agreement_group_id", "action"]);
end

function value = emptyMembers()
value = table(zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["component_ordinal", "detection_id", "selector", ...
    "extractor_name", "member_role", "agreement_group_id", "action"]);
end

function value = emptySupportEdges()
value = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), VariableNames=["component_ordinal", "candidate_pair_id", ...
    "source_analysis_run_id", "source_run_key", "pair_label", "node_a", ...
    "node_b", "pairwise_match_type", "agreement_group_id", "action"]);
end
