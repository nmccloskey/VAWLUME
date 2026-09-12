function [plan, count] = attributionApplyCandidatePlan(conn, plan)
%ATTRIBUTIONAPPLYCANDIDATEPLAN Atomically append every planned candidate.

if plan.has_conflicts
    error("vawlume:attribution:PlanConflict", ...
        "A candidate plan with conflicts cannot be applied.");
end
create = plan.candidates.action == "create";
count = sum(create);
if count == 0
    return
end
oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:attribution:TransactionState", ...
        "Candidate apply requires a connection with AutoCommit enabled.");
end
conn.AutoCommit = "off";
try
    for index = find(create)'
        row = plan.candidates(index, :);
        candidateId = attributionInsertRow(conn, "attribution_candidates", ...
            struct(attribution_target_id=row.attribution_target_id, ...
            entity_id=row.entity_id, candidate_status=row.candidate_status, ...
            candidate_rank=row.candidate_rank, score=row.score, ...
            score_semantics=row.score_semantics, ...
            probability=row.probability, ...
            probability_semantics=row.probability_semantics, ...
            source_label=row.source_label, notes=row.notes), ...
            "attribution_candidate_id");
        plan.candidates.attribution_candidate_id(index) = candidateId;
    end
    commit(conn);
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end
