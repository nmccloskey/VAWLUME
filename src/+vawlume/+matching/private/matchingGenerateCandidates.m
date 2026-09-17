function [candidates, unmatched] = matchingGenerateCandidates(runA, runB, pair, rule)
%MATCHINGGENERATECANDIDATES Compute exhaustive transparent temporal evidence.
%
% Duration is the boundary-derived v_detection_core.duration_s surface. A
% start-ordered interval sweep compares only pairs with positive temporal
% overlap. Every qualifying edge survives; no best-candidate reduction occurs.
%
% RULE is the validated plausibility rule from matchingLoadSpec. Beyond positive
% overlap and min_temporal_iou it may declare magnitude bounds on the signed
% onset, offset, and duration differences. Each declared bound only removes
% candidates the earlier rule admits, so the sweep's end_time_s > next_start
% pruning remains correctness-preserving: a pair the sweep never examines has no
% positive overlap and was never admissible under any of these dimensions.

gates = plausibilityGates(rule);
runA = sortrows(runA, ["start_time_s", "detection_id"]);
runB = sortrows(runB, ["start_time_s", "detection_id"]);
records = emptyRecords();
activeA = zeros(0, 1);
activeB = zeros(0, 1);
aIndex = 1;
bIndex = 1;

while aIndex <= height(runA) || bIndex <= height(runB)
    nextA = Inf;
    nextB = Inf;
    if aIndex <= height(runA), nextA = runA.start_time_s(aIndex); end
    if bIndex <= height(runB), nextB = runB.start_time_s(bIndex); end

    if nextA <= nextB
        activeB = activeB(runB.end_time_s(activeB) > nextA);
        for activeIndex = activeB'
            record = candidateRecord(runA(aIndex, :), runB(activeIndex, :), ...
                pair, gates);
            if ~isempty(record)
                records(end + 1, 1) = record; %#ok<AGROW>
            end
        end
        activeA(end + 1, 1) = aIndex; %#ok<AGROW>
        aIndex = aIndex + 1;
    else
        activeA = activeA(runA.end_time_s(activeA) > nextB);
        for activeIndex = activeA'
            record = candidateRecord(runA(activeIndex, :), runB(bIndex, :), ...
                pair, gates);
            if ~isempty(record)
                records(end + 1, 1) = record; %#ok<AGROW>
            end
        end
        activeB(end + 1, 1) = bIndex; %#ok<AGROW>
        bIndex = bIndex + 1;
    end
end

if isempty(records)
    candidates = emptyCandidateTable();
else
    candidates = struct2table(records, "AsArray", true);
    candidates.candidate_status = string(candidates.candidate_status);
    candidates.details_json = string(candidates.details_json);
    candidates = sortrows(candidates, ["run_a_detection_id", ...
        "run_b_detection_id"]);
end

matchedA = unique(candidates.run_a_detection_id);
matchedB = unique(candidates.run_b_detection_id);
unmatched = struct( ...
    run_a_detection_ids=runA.detection_id(~ismember(runA.detection_id, matchedA)), ...
    run_b_detection_ids=runB.detection_id(~ismember(runB.detection_id, matchedB)));
end

function gates = plausibilityGates(rule)
%PLAUSIBILITYGATES Reduce the validated rule to the bounds actually declared.
%
% An undeclared bound is NaN and leaves its dimension unconstrained, so it
% contributes neither a gate nor a details_json key. A specification declaring
% only min_temporal_iou therefore produces exactly the eligibility rule and
% exactly the stored evidence the prior contract produced.
names = ["max_abs_onset_difference_s"; "max_abs_offset_difference_s"; ...
    "max_abs_duration_difference_s"];
evidence = ["onset_difference_s"; "offset_difference_s"; ...
    "duration_difference_s"];
values = [rule.max_abs_onset_difference_s; rule.max_abs_offset_difference_s; ...
    rule.max_abs_duration_difference_s];
declared = ~isnan(values);
gates = struct();
gates.min_temporal_iou = rule.min_temporal_iou;
gates.bound_names = names(declared);
gates.evidence_names = evidence(declared);
gates.bound_values = values(declared);
gates.eligibility_rule = strjoin(["positive_overlap"; "min_temporal_iou"; ...
    names(declared)], "_and_");
end

function record = candidateRecord(runA, runB, pair, gates)
relation = vawlume.interval.relation(runA.start_time_s, runA.end_time_s, ...
    runB.start_time_s, runB.end_time_s);
if relation.intersection_s <= 0 || relation.temporal_iou < gates.min_temporal_iou
    record = [];
    return
end
for index = 1:numel(gates.bound_values)
    % Magnitude semantics: relation's differences are signed and directional
    % (B minus A), so the bound is applied to abs() and excludes -0.05 s
    % exactly as it excludes +0.05 s.
    if abs(relation.(gates.evidence_names(index))) > gates.bound_values(index)
        record = [];
        return
    end
end
runAId = runA.detection_id;
runBId = runB.detection_id;
details = struct( ...
    evidence_direction="run_a_to_run_b", ...
    run_a_extraction_run_id=pair.run_a.extraction_run_id, ...
    run_b_extraction_run_id=pair.run_b.extraction_run_id, ...
    run_a_detection_id=runAId, ...
    run_b_detection_id=runBId, ...
    schema_detection_order="ascending_detection_id", ...
    eligibility_rule=gates.eligibility_rule, ...
    min_temporal_iou=gates.min_temporal_iou);
for index = 1:numel(gates.bound_names)
    details.(gates.bound_names(index)) = gates.bound_values(index);
end
record = struct( ...
    run_a_detection_id=runAId, ...
    run_b_detection_id=runBId, ...
    detection_a_id=min(runAId, runBId), ...
    detection_b_id=max(runAId, runBId), ...
    temporal_overlap_s=relation.intersection_s, ...
    temporal_iou=relation.temporal_iou, ...
    onset_difference_s=relation.onset_difference_s, ...
    offset_difference_s=relation.offset_difference_s, ...
    duration_difference_s=relation.duration_difference_s, ...
    candidate_score=relation.temporal_iou, ...
    candidate_status="eligible", ...
    details_json=jsonencode(details));
end

function records = emptyRecords()
records = struct( ...
    run_a_detection_id={}, run_b_detection_id={}, ...
    detection_a_id={}, detection_b_id={}, temporal_overlap_s={}, ...
    temporal_iou={}, onset_difference_s={}, offset_difference_s={}, ...
    duration_difference_s={}, candidate_score={}, candidate_status={}, ...
    details_json={});
end

function candidates = emptyCandidateTable()
candidates = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["run_a_detection_id", "run_b_detection_id", ...
    "detection_a_id", "detection_b_id", "temporal_overlap_s", ...
    "temporal_iou", "onset_difference_s", "offset_difference_s", ...
    "duration_difference_s", "candidate_score", "candidate_status", ...
    "details_json"]);
end
