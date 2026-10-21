function value = attributionCompareTargets(left, right, leftTargetId, rightTargetId)
%ATTRIBUTIONCOMPARETARGETS One left target against one right target (contract 07 D4).
%
% LEFT and RIGHT are compare's side records: the run's report tables, the
% decisions and selections under the side's policy, and its rank basis. Returns
% the per-target values every comparison reports, whatever joined the two
% targets: top_entity_agreement, selected_set_relation and both decision
% statuses. Nothing here combines the two sides or chooses between them.
%
% This is the unit core. Same-event-set comparison calls it once per target;
% cross-event-set comparison (7.7) calls it per (left, right) pair inside a
% correspondence unit, and never promotes the result to the unit.
[leftState, leftTop] = topEntity(left, leftTargetId);
[rightState, rightTop] = topEntity(right, rightTargetId);
value = struct( ...
    top_entity_agreement=topAgreement(leftState, leftTop, rightState, rightTop), ...
    selected_set_relation=setRelation(selected(left, leftTargetId), ...
        selected(right, rightTargetId)), ...
    left_decision_status=status(left, leftTargetId), ...
    right_decision_status=status(right, rightTargetId));
end

function [state, top] = topEntity(side, targetId)
% state: "ranked", "tie", "unscored" or "orientation_unknown". The rank basis is
% the side's policy (its reads column, higher_is_stronger); without a policy,
% candidate_rank where every candidate of the target carries one.
top = zeros(0, 1);
rows = side.report.candidates(side.report.candidates.attribution_target_id == targetId, :);
if height(rows) == 0
    state = "unscored";
    return
end
if side.rank_basis == "score" || side.rank_basis == "probability"
    values = rows.(side.rank_basis);
    valid = ~isnan(values);
    if ~any(valid)
        state = "unscored";
        return
    end
    top = rows.entity_id(valid & values == max(values(valid)));
elseif any(isnan(rows.candidate_rank)) || all(isnan(rows.score))
    % candidate_rank is a presentation of score: a target whose candidates are
    % all unscored carries no rank, and an incomplete ranking has no orientation.
    if all(isnan(rows.score)) && all(isnan(rows.probability))
        state = "unscored";
    else
        state = "orientation_unknown";
    end
    return
else
    top = rows.entity_id(rows.candidate_rank == min(rows.candidate_rank));
end
top = sort(unique(top));
if numel(top) > 1
    state = "tie";
else
    state = "ranked";
end
end

function value = topAgreement(leftState, leftTop, rightState, rightTop)
% Precedence, documented in compare's help: orientation, then unscored, then
% ties, left before right.
if leftState == "orientation_unknown" || rightState == "orientation_unknown"
    value = "orientation_unknown";
elseif leftState == "unscored" && rightState == "unscored"
    value = "both_unscored";
elseif leftState == "unscored"
    value = "left_unscored";
elseif rightState == "unscored"
    value = "right_unscored";
elseif leftState == "tie"
    value = "tie_left";
elseif rightState == "tie"
    value = "tie_right";
elseif isequal(leftTop, rightTop)
    value = "same";
else
    value = "different";
end
end

function ids = selected(side, targetId)
decision = side.decisions(side.decisions.attribution_target_id == targetId, :);
ids = zeros(0, 1);
if height(decision) == 0
    return
end
rows = side.selections(ismember(side.selections.attribution_decision_id, ...
    decision.attribution_decision_id), :);
ids = sort(unique(rows.entity_id));
end

function value = setRelation(left, right)
if isempty(left) && isempty(right)
    value = "both_empty";
elseif isempty(left)
    value = "left_empty";
elseif isempty(right)
    value = "right_empty";
elseif isequal(left, right)
    value = "equal";
elseif isempty(intersect(left, right))
    value = "disjoint";
elseif all(ismember(left, right))
    value = "subset";
elseif all(ismember(right, left))
    value = "superset";
else
    value = "overlap";
end
end

function value = status(side, targetId)
decision = side.decisions(side.decisions.attribution_target_id == targetId, :);
if height(decision) == 0
    value = "no_decision";
else
    value = decision.decision_status(1);
end
end
