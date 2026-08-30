function [groups, members, consensus, consensusMembers] = ...
        matchingBuildGroups(runA, runB, candidates)
%MATCHINGBUILDGROUPS Build a deterministic, ambiguity-preserving partition.

ids = [double(runA.detection_id); double(runB.detection_id)];
roles = [repmat("run_a", height(runA), 1); repmat("run_b", height(runB), 1)];
starts = [double(runA.start_time_s); double(runB.start_time_s)];
ends = [double(runA.end_time_s); double(runB.end_time_s)];
parent = (1:numel(ids))';

if ~isempty(candidates)
    edges = sortrows(candidates, ["run_a_detection_id", "run_b_detection_id"]);
    for index = 1:height(edges)
        left = find(ids == edges.run_a_detection_id(index), 1);
        right = find(ids == edges.run_b_detection_id(index), 1);
        parent = unite(parent, left, right);
    end
end
for index = 1:numel(parent)
    [parent, parent(index)] = rootOf(parent, index);
end

groups = emptyGroups();
members = emptyMembers();
consensus = emptyConsensus();
consensusMembers = emptyConsensusMembers();
if isempty(ids)
    return
end

roots = unique(parent);
minimumId = zeros(numel(roots), 1);
for index = 1:numel(roots)
    minimumId(index) = min(ids(parent == roots(index)));
end
[~, order] = sort(minimumId);
roots = roots(order);

for groupIndex = 1:numel(roots)
    selected = find(parent == roots(groupIndex));
    runAIds = sort(ids(selected(roles(selected) == "run_a")));
    runBIds = sort(ids(selected(roles(selected) == "run_b")));
    [matchType, ambiguityStatus] = topology(numel(runAIds), numel(runBIds));
    componentKey = "run_a:[" + strjoin(string(runAIds'), ",") + ...
        "]|run_b:[" + strjoin(string(runBIds'), ",") + "]";
    groupNotes = string(jsonencode(struct( ...
        component_key=componentKey, identity_model="ordered_member_ids", ...
        run_a_member_count=numel(runAIds), ...
        run_b_member_count=numel(runBIds))));
    groups(end + 1, :) = {groupIndex, componentKey, NaN, ...
        numel(runAIds), numel(runBIds), matchType, ambiguityStatus, ...
        NaN, groupNotes, "create"}; %#ok<AGROW>

    orderedIds = [runAIds; runBIds];
    orderedRoles = [repmat("run_a", numel(runAIds), 1); ...
        repmat("run_b", numel(runBIds), 1)];
    for memberIndex = 1:numel(orderedIds)
        members(end + 1, :) = {groupIndex, componentKey, NaN, ...
            orderedIds(memberIndex), orderedRoles(memberIndex), ...
            memberIndex, "create"}; %#ok<AGROW>
    end

    [emit, method, status] = consensusPolicy(matchType);
    if ~emit
        continue
    end
    selectedGeometry = ismember(ids, orderedIds);
    if method == "mean_boundary_of_members"
        startS = mean(starts(selectedGeometry));
        endS = mean(ends(selectedGeometry));
    else
        startS = min(starts(selectedGeometry));
        endS = max(ends(selectedGeometry));
    end
    consensusIndex = height(consensus) + 1;
    consensusNotes = string(jsonencode(struct( ...
        component_key=componentKey, topology=matchType, ...
        interval_semantics=method)));
    consensus(end + 1, :) = {consensusIndex, groupIndex, componentKey, ...
        NaN, NaN, startS, endS, method, status, NaN, ...
        consensusNotes, "create"}; %#ok<AGROW>
    for memberIndex = 1:numel(orderedIds)
        consensusMembers(end + 1, :) = {consensusIndex, ...
            componentKey, NaN, orderedIds(memberIndex), ...
            orderedRoles(memberIndex), memberIndex, "create"}; %#ok<AGROW>
    end
end
end

function parent = unite(parent, left, right)
[parent, leftRoot] = rootOf(parent, left);
[parent, rightRoot] = rootOf(parent, right);
if leftRoot ~= rightRoot
    if leftRoot < rightRoot
        parent(rightRoot) = leftRoot;
    else
        parent(leftRoot) = rightRoot;
    end
end
end

function [parent, root] = rootOf(parent, node)
root = node;
while parent(root) ~= root
    root = parent(root);
end
while parent(node) ~= node
    next = parent(node);
    parent(node) = root;
    node = next;
end
end

function [matchType, ambiguityStatus] = topology(runACount, runBCount)
if runACount == 0 || runBCount == 0
    matchType = "unmatched";
    ambiguityStatus = "unmatched";
elseif runACount == 1 && runBCount == 1
    matchType = "one_to_one";
    ambiguityStatus = "unambiguous";
elseif runACount == 1
    matchType = "one_to_many";
    ambiguityStatus = "ambiguous";
elseif runBCount == 1
    matchType = "many_to_one";
    ambiguityStatus = "ambiguous";
else
    matchType = "many_to_many";
    ambiguityStatus = "ambiguous";
end
end

function [emit, method, status] = consensusPolicy(matchType)
emit = true;
if matchType == "one_to_one"
    method = "mean_boundary_of_members";
    status = "derived_unambiguous";
elseif matchType == "one_to_many" || matchType == "many_to_one"
    method = "union_boundary_of_members";
    status = "derived_ambiguity_preserving";
else
    emit = false;
    method = "";
    status = "";
end
end

function value = emptyGroups()
value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["component_ordinal", "component_key", "match_group_id", ...
    "run_a_member_count", "run_b_member_count", "match_type", ...
    "ambiguity_status", "match_score", "notes", "action"]);
end

function value = emptyMembers()
value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["component_ordinal", "component_key", "match_group_id", ...
    "detection_id", "member_role", "member_ordinal", "action"]);
end

function value = emptyConsensus()
value = table(zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["consensus_ordinal", "component_ordinal", "component_key", ...
    "consensus_event_id", "match_group_id", "start_time_s", "end_time_s", ...
    "derivation_method", "consensus_status", "confidence_score", "notes", ...
    "action"]);
end

function value = emptyConsensusMembers()
value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["consensus_ordinal", "component_key", ...
    "consensus_event_id", "detection_id", "member_role", ...
    "member_ordinal", "action"]);
end
