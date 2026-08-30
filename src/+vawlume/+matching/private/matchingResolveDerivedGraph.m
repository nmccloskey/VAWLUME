function plan = matchingResolveDerivedGraph(conn, plan)
%MATCHINGRESOLVEDERIVEDGRAPH Classify stored groups and consensus for reruns.

if plan.analysis.action == "create"
    plan.analysis.graph_action = "create";
    return
end
if plan.analysis.action == "conflict"
    plan.analysis.graph_action = "conflict";
    return
end

analysisId = plan.analysis.analysis_run_id;
storedGroups = fetch(conn, "SELECT match_group_id, match_type, " + ...
    "IFNULL(ambiguity_status,'') AS ambiguity_status, " + ...
    "IFNULL(match_score,1e308) AS match_score, IFNULL(notes,'') AS notes " + ...
    "FROM match_groups WHERE analysis_run_id=" + string(analysisId) + ...
    " ORDER BY match_group_id");
storedConsensus = fetch(conn, "SELECT ce.consensus_event_id, " + ...
    "IFNULL(ce.match_group_id,-1) AS match_group_id, " + ...
    "ce.start_time_s, ce.end_time_s, " + ...
    "ce.derivation_method, IFNULL(ce.consensus_status,'') AS consensus_status, " + ...
    "IFNULL(ce.confidence_score,1e308) AS confidence_score, " + ...
    "IFNULL(ce.notes,'') AS notes " + ...
    "FROM consensus_events ce WHERE ce.analysis_run_id=" + ...
    string(analysisId) + " ORDER BY ce.consensus_event_id");

if height(storedGroups) == 0 && height(storedConsensus) == 0
    if height(plan.groups) == 0
        plan.analysis.graph_action = "reuse";
    else
        plan.analysis.graph_action = "append";
    end
    return
end

[compatible, reason, plan] = graphCompatible( ...
    conn, plan, storedGroups, storedConsensus);
if compatible
    plan.analysis.graph_action = "reuse";
else
    plan.analysis.action = "conflict";
    plan.analysis.graph_action = "conflict";
    plan.analysis.conflict_message = "Analysis run_key '" + ...
        plan.analysis.run_key + "' has different persisted assignment or " + ...
        "consensus evidence: " + reason;
end
end

function [compatible, reason, plan] = graphCompatible( ...
        conn, plan, storedGroups, storedConsensus)
compatible = false;
reason = "group count differs";
if height(storedGroups) ~= height(plan.groups)
    return
end
if height(storedConsensus) ~= height(plan.consensus_events)
    reason = "consensus-event count differs";
    return
end

for index = 1:height(plan.groups)
    expected = plan.groups(index, :);
    selected = presentText(storedGroups.notes) == expected.notes;
    if sum(selected) ~= 1
        reason = "component identity or notes differ";
        return
    end
    stored = storedGroups(selected, :);
    if presentText(stored.match_type(1)) ~= expected.match_type || ...
            presentText(stored.ambiguity_status(1)) ~= ...
            expected.ambiguity_status || double(stored.match_score(1)) ~= 1e308
        reason = "group topology, ambiguity status, or score differs";
        return
    end
    groupId = double(stored.match_group_id(1));
    plan.groups.match_group_id(index) = groupId;
    plan.groups.action(index) = "reuse";
    memberRows = fetch(conn, "SELECT detection_id, IFNULL(member_role,'') " + ...
        "AS member_role FROM match_group_members WHERE match_group_id=" + ...
        string(groupId) + " ORDER BY member_role, detection_id");
    expectedMembers = plan.group_members( ...
        plan.group_members.component_ordinal == expected.component_ordinal, :);
    expectedMembers = sortrows(expectedMembers, ["member_role", "detection_id"]);
    if height(memberRows) ~= height(expectedMembers) || ...
            (height(memberRows) > 0 && (~all(double(memberRows.detection_id) == ...
            expectedMembers.detection_id) || ~all(presentText( ...
            memberRows.member_role) == expectedMembers.member_role)))
        reason = "group membership or member role differs";
        return
    end
    selectedMembers = plan.group_members.component_ordinal == ...
        expected.component_ordinal;
    plan.group_members.match_group_id(selectedMembers) = groupId;
    plan.group_members.action(selectedMembers) = "reuse";
end

for index = 1:height(plan.consensus_events)
    expected = plan.consensus_events(index, :);
    selected = presentText(storedConsensus.notes) == expected.notes;
    if sum(selected) ~= 1
        reason = "consensus identity or notes differ";
        return
    end
    stored = storedConsensus(selected, :);
    groupId = plan.groups.match_group_id( ...
        plan.groups.component_ordinal == expected.component_ordinal);
    numericOkay = abs(double(stored.start_time_s(1)) - ...
        expected.start_time_s) <= 1e-12 && ...
        abs(double(stored.end_time_s(1)) - expected.end_time_s) <= 1e-12;
    textOkay = presentText(stored.derivation_method(1)) == ...
        expected.derivation_method && presentText(stored.consensus_status(1)) == ...
        expected.consensus_status;
    if double(stored.match_group_id(1)) ~= groupId || ~numericOkay || ...
            ~textOkay || double(stored.confidence_score(1)) ~= 1e308
        reason = "consensus group, interval, method, status, or score differs";
        return
    end
    consensusId = double(stored.consensus_event_id(1));
    plan.consensus_events.consensus_event_id(index) = consensusId;
    plan.consensus_events.match_group_id(index) = groupId;
    plan.consensus_events.action(index) = "reuse";
    memberRows = fetch(conn, "SELECT detection_id, IFNULL(member_role,'') " + ...
        "AS member_role FROM consensus_event_members WHERE consensus_event_id=" + ...
        string(consensusId) + " ORDER BY member_role, detection_id");
    expectedMembers = plan.consensus_event_members( ...
        plan.consensus_event_members.consensus_ordinal == ...
        expected.consensus_ordinal, :);
    expectedMembers = sortrows(expectedMembers, ["member_role", "detection_id"]);
    if height(memberRows) ~= height(expectedMembers) || ...
            (height(memberRows) > 0 && (~all(double(memberRows.detection_id) == ...
            expectedMembers.detection_id) || ~all(presentText( ...
            memberRows.member_role) == expectedMembers.member_role)))
        reason = "consensus membership or member role differs";
        return
    end
    selectedMembers = plan.consensus_event_members.consensus_ordinal == ...
        expected.consensus_ordinal;
    plan.consensus_event_members.consensus_event_id(selectedMembers) = consensusId;
    plan.consensus_event_members.action(selectedMembers) = "reuse";
end

compatible = true;
reason = "";
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
