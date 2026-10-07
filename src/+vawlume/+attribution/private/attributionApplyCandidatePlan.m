function [plan, count] = attributionApplyCandidatePlan(conn, plan, transaction)
%ATTRIBUTIONAPPLYCANDIDATEPLAN Atomically append every planned candidate.
%
% TRANSACTION "own" (default) commits here; "caller" joins the caller's open
% transaction and leaves commit and rollback to the caller.

if nargin < 3
    transaction = "own";
end
if plan.has_conflicts
    error("vawlume:attribution:PlanConflict", ...
        "A candidate plan with conflicts cannot be applied.");
end
create = plan.candidates.action == "create";
count = sum(create);
if transaction == "caller"
    attributionRequireCallerTransaction(conn, "Candidate apply");
    plan = writeCandidates(conn, plan, create);
    return
end
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
    plan = writeCandidates(conn, plan, create);
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

function plan = writeCandidates(conn, plan, create)
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
end
