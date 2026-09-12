function result = addCandidates(conn, targetRef, candidates, options)
%ADDCANDIDATES Plan or atomically append several candidate callers.
%
% RESULT = VAWLUME.ATTRIBUTION.ADDCANDIDATES(CONN, TARGETREF, CANDIDATES)
% validates and previews a candidate batch without writing. Apply=true appends
% the complete batch atomically.
%
% TARGETREF contains attribution_target_id, or project_key and run_key plus
% exactly one of detection_id, consensus_event_id, or agreement_group_id.
%
% CANDIDATES is a table or struct array with one row per entity. entity_id is
% required. Optional fields are candidate_rank, score, score_semantics,
% probability, probability_semantics, source_label, and notes. A stored score
% or probability requires its own nonempty semantics. Probability is bounded
% to [0,1]; score is not. Nothing converts between them.
%
% candidate_rank is supplied by the caller, never computed here. When present
% it must agree with a higher-score-is-stronger scale: equal scores have equal
% ranks, and a higher score has a lower rank. Omit rank for scales with other
% ordering semantics. All rows remain candidates; Phase 4.6 owns selection.
%
% Existing identical target/entity rows are reused. Different content for the
% same pair is a conflict and is never rewritten.
%
% See also VAWLUME.ATTRIBUTION.ADDEVIDENCE,
% VAWLUME.ATTRIBUTION.CREATERUN

arguments
    conn
    targetRef (1,1) struct
    candidates
    options.Apply (1,1) logical = false
end

plan = attributionBuildCandidatePlan(conn, targetRef, candidates);
result = candidateResult(plan);
if options.Apply && ~plan.has_conflicts
    [plan, inserted] = attributionApplyCandidatePlan(conn, plan);
    result = candidateResult(plan);
    result.committed = true;
    result.applied_count = inserted;
    if inserted == 0
        result.status = "reused";
    else
        result.status = "created";
    end
end
end

function result = candidateResult(plan)
if plan.has_conflicts
    status = "conflict";
else
    status = "planned";
end
result = struct(status=status, committed=false, ...
    has_conflicts=plan.has_conflicts, conflicts=plan.conflicts, ...
    run=plan.run, target=plan.target, ...
    candidate_count=height(plan.candidates), candidates=plan.candidates, ...
    applied_count=0);
end
