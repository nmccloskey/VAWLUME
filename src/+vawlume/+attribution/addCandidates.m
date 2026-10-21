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
% probability, probability_semantics, source_label, notes, and
% no_score_reasons. A stored score or probability requires its own nonempty
% semantics. Probability is bounded to [0,1]; score is not. Nothing converts
% between them.
%
% A candidate on a native_estimate run carries no probability and no
% probability_semantics: its score is not one (invariant 24, contract 07 D9).
% Either is refused before any write with
% vawlume:attribution:NativeProbabilityRefused. Imported and backend runs are
% unaffected.
%
% no_score_reasons lists, per candidate, every reason its producer gives for
% not scoring it, in the producer's order (a string array or cellstr; empty
% means none stated). Each is stored as its own row of
% attribution_candidate_no_score_reasons, ordinal 1 first, in the same
% transaction as the candidate. Reasons are refused on a scored candidate and
% when a code repeats (vawlume:attribution:CandidateSpecInvalid). Codes are the
% producer's vocabulary and are stored verbatim.
%
% candidate_rank is supplied by the caller, never computed here. When present
% it must agree with a higher-score-is-stronger scale: equal scores have equal
% ranks, and a higher score has a lower rank. Omit rank for scales with other
% ordering semantics. All rows remain candidates; Phase 4.6 owns selection.
%
% Existing identical target/entity rows, reasons included, are reused.
% Different content for the same pair is a conflict and is never rewritten.
%
% Transaction="own" (default) commits here. Transaction="caller" joins the
% caller's open transaction (AutoCommit off, set by the caller) and leaves
% commit and rollback to it; with AutoCommit on it is refused
% (vawlume:attribution:TransactionState). See VAWLUME.ATTRIBUTION.CREATERUN.
%
% See also VAWLUME.ATTRIBUTION.ADDEVIDENCE,
% VAWLUME.ATTRIBUTION.CREATERUN

arguments
    conn
    targetRef (1,1) struct
    candidates
    options.Apply (1,1) logical = false
    options.Transaction (1,1) string {mustBeMember(options.Transaction, ...
        ["own", "caller"])} = "own"
end

plan = attributionBuildCandidatePlan(conn, targetRef, candidates);
result = candidateResult(plan);
if options.Apply && ~plan.has_conflicts
    [plan, inserted] = attributionApplyCandidatePlan(conn, plan, options.Transaction);
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
