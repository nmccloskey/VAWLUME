function plan = agreementResolveDerivedGraph(conn, plan)
%AGREEMENTRESOLVEDERIVEDGRAPH Classify stored components for reruns.
%
% Derived identity is the stored group_key column, not a note. The pairwise
% layer matches its components by a key embedded in free-form notes; that works
% but makes an audit comment part of identity. The agreement schema gave
% group_key its own column and UNIQUE(analysis_run_id, group_key) precisely so
% identity is a declared constraint, and this function uses it.
%
% Three outcomes:
%   create   nothing derived is stored yet, including the ordinary case of a
%            provenance skeleton applied earlier with composition pending
%   reuse    every planned group, member set, and supporting edge set is already
%            stored exactly
%   conflict something derived is stored and differs

if plan.analysis.action == "create"
    plan.analysis.graph_action = "create";
    return
end
if plan.analysis.action == "conflict"
    plan.analysis.graph_action = "conflict";
    return
end

analysisId = plan.analysis.analysis_run_id;
stored = fetch(conn, "SELECT agreement_group_id, group_key, " + ...
    "derivation_method FROM agreement_groups WHERE analysis_run_id=" + ...
    string(analysisId) + " ORDER BY group_key");
if height(stored) == 0
    plan.analysis.graph_action = "create";
    return
end

[compatible, reason, plan] = graphCompatible(conn, plan, stored);
if compatible
    plan.analysis.graph_action = "reuse";
else
    plan.analysis.action = "conflict";
    plan.analysis.graph_action = "conflict";
    plan.analysis.conflict_message = "Analysis run_key '" + ...
        plan.analysis.run_key + "' has different persisted agreement " + ...
        "components: " + reason;
end
end

function [compatible, reason, plan] = graphCompatible(conn, plan, stored)
compatible = false;
storedKeys = presentText(stored.group_key);
if height(stored) ~= height(plan.groups)
    reason = "component count differs (" + string(height(stored)) + ...
        " stored, " + string(height(plan.groups)) + " planned)";
    return
end
missing = setdiff(plan.groups.group_key, storedKeys);
if ~isempty(missing)
    reason = "component identity differs; planned component(s) " + ...
        strjoin("'" + missing(:)' + "'", ", ") + " are not stored";
    return
end

for index = 1:height(plan.groups)
    expected = plan.groups(index, :);
    selected = storedKeys == expected.group_key;
    row = stored(selected, :);
    if presentText(row.derivation_method(1)) ~= expected.derivation_method
        reason = "derivation method differs for component '" + ...
            expected.group_key + "'";
        return
    end
    groupId = double(row.agreement_group_id(1));
    plan.groups.agreement_group_id(index) = groupId;
    plan.groups.action(index) = "reuse";

    [membersOkay, memberReason] = membersCompatible(conn, plan, expected, groupId);
    if ~membersOkay
        reason = memberReason;
        return
    end
    [edgesOkay, edgeReason] = edgesCompatible(conn, plan, expected, groupId);
    if ~edgesOkay
        reason = edgeReason;
        return
    end
    selectedMembers = plan.members.component_ordinal == expected.component_ordinal;
    plan.members.agreement_group_id(selectedMembers) = groupId;
    plan.members.action(selectedMembers) = "reuse";
    selectedEdges = plan.support_edges.component_ordinal == expected.component_ordinal;
    plan.support_edges.agreement_group_id(selectedEdges) = groupId;
    plan.support_edges.action(selectedEdges) = "reuse";
end

compatible = true;
reason = "";
end

function [okay, reason] = membersCompatible(conn, plan, expected, groupId)
okay = false;
rows = fetch(conn, "SELECT detection_id FROM agreement_group_members " + ...
    "WHERE agreement_group_id=" + string(groupId) + " ORDER BY detection_id");
expectedMembers = sort(plan.members.detection_id( ...
    plan.members.component_ordinal == expected.component_ordinal));
if height(rows) ~= numel(expectedMembers)
    reason = "membership count differs for component '" + expected.group_key + "'";
    return
end
if ~isempty(expectedMembers) && ~isequal(double(rows.detection_id), expectedMembers)
    reason = "membership differs for component '" + expected.group_key + "'";
    return
end
okay = true;
reason = "";
end

function [okay, reason] = edgesCompatible(conn, plan, expected, groupId)
okay = false;
rows = fetch(conn, "SELECT candidate_pair_id FROM agreement_supporting_edges " + ...
    "WHERE agreement_group_id=" + string(groupId) + " ORDER BY candidate_pair_id");
expectedEdges = sort(plan.support_edges.candidate_pair_id( ...
    plan.support_edges.component_ordinal == expected.component_ordinal));
if height(rows) ~= numel(expectedEdges)
    reason = "supporting-edge count differs for component '" + ...
        expected.group_key + "' (" + string(height(rows)) + " stored, " + ...
        string(numel(expectedEdges)) + " planned)";
    return
end
if ~isempty(expectedEdges) && ~isequal(double(rows.candidate_pair_id), expectedEdges)
    reason = "supporting edges cite different candidate pairs for component '" + ...
        expected.group_key + "'";
    return
end
okay = true;
reason = "";
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
