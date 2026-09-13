function result = decide(conn, runRef, policyRef, options)
%DECIDE Plan or atomically apply a declared policy over stored candidates.
%
% RESULT = VAWLUME.ATTRIBUTION.DECIDE(CONN, RUNREF, POLICYREF) previews one
% decision per target without writing. Apply=true persists the decisions, their
% selected candidates, and the policy's registered profile version in one
% transaction.
%
% RUNREF contains attribution_run_id, or project_key and run_key.
%
% POLICYREF is a path to a versioned attribution policy, or a struct with
% profile_path. Omit it to use the shipped illustrative policy under
% config/08_attribution_policies/. The policy is an input, never a constant:
% its key, version, checksum and the threshold that actually bound each
% decision are all recoverable from the stored rows.
%
% A decision is DERIVED and re-derivable. Nothing it records is unrecoverable
% from the candidate rows plus the policy, and applying a different policy to
% the same candidates produces a different decision while changing no candidate.
% This function writes no candidate, score, probability, or evidence row.
%
% Statuses, and what each claims:
%
%   assigned      one candidate is supported and no other is close to it
%   simultaneous  several contenders are EACH independently strong -- a claim
%                 about the world, that more than one animal called
%   ambiguous     several contenders are close and none is independently
%                 strong -- a claim about the evidence, not about the world
%   unassigned    the policy ran and no candidate was supportable
%   excluded      the policy could not be applied, or a caller declared a QC
%                 exclusion with a reason
%
% No status means validated. No threshold that ships is calibrated.
%
% Name-value arguments:
%   Apply       persist the batch (default false)
%   Targets     decide only these attribution_target_ids (default: all)
%   Exclusions  struct array of attribution_target_id and reason
%   RepoRoot    repository root, inferred from this file by default
%
% A second decision for one target under the same policy version is refused
% rather than rewritten. A different policy version is a different decision and
% both remain readable, which is what lets a later phase compare policies over
% one body of evidence.
%
% See also VAWLUME.ATTRIBUTION.ADDCANDIDATES, VAWLUME.ATTRIBUTION.ADDEVIDENCE

arguments
    conn
    runRef (1,1) struct
    policyRef = struct()
    options.Apply (1,1) logical = false
    options.Targets double = []
    options.Exclusions = []
    options.RepoRoot (1,1) string = ""
end

plan = attributionBuildDecisionPlan(conn, runRef, policyRef, options);
result = decisionResult(plan);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = attributionApplyDecisionPlan(conn, plan);
    result = decisionResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    result.status = "decided";
    result.policy_profile_version_id = plan.policy_profile_version_id;
    result.run_completed = counts.run_completed == 1;
end
end

function result = decisionResult(plan)
if plan.has_conflicts
    status = "conflict";
else
    status = "planned";
end
result = struct( ...
    status=status, ...
    committed=false, ...
    attribution_run_id=plan.run.attribution_run_id, ...
    run_key=plan.run.run_key, ...
    policy=policySummary(plan.policy), ...
    decisions=plan.decisions, ...
    selections=plan.selections, ...
    has_conflicts=plan.has_conflicts, ...
    run_completed=false, ...
    proves="a declared policy was applied to stored candidates", ...
    does_not_prove=["that any selected entity called"; ...
        "that any threshold here is calibrated"; ...
        "that the candidate set was complete"]);
end

function summary = policySummary(policy)
% Everything a reader needs to interpret the decision without this code.
summary = struct( ...
    profile_key=policy.profile_key, ...
    version_label=policy.version_label, ...
    checksum_sha256=policy.checksum_sha256, ...
    content_uri=policy.content_uri, ...
    rule_key=policy.rule_key, ...
    reads=policy.reads, ...
    selection_threshold=policy.selection_threshold, ...
    separation_margin=policy.separation_margin, ...
    co_occurrence_threshold=policy.co_occurrence_threshold, ...
    calibration_state=policy.calibration_state, ...
    calibration_meaning=policy.calibration_meaning);
end
