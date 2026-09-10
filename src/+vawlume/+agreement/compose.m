function result = compose(conn, recordingRef, sources, agreementSpec, options)
%COMPOSE Plan or atomically persist one arbitrary-N extractor-agreement run.
%
% RESULT = vawlume.agreement.compose(CONN, RECORDINGREF, SOURCES, AGREEMENTSPEC)
% validates a set of completed pairwise matching analyses, resolves the derived
% agreement run's identity and provenance, and returns the plan. Planning is the
% default and writes nothing.
%
% SOURCES is the set of source pairwise analyses, not a run signature. The
% arbitrary-N layer composes analyses, so it takes analyses:
%
%   [7 8 9]
%   ["m_ds_mupet", "m_ds_usvseg", "m_mupet_usvseg"]
%   struct(run_key="m_ds_mupet")
%
% Each entry is an analysis_run_id, an analysis run_key, or a scalar struct
% holding exactly one of those. Order carries no meaning: the plan normalizes
% sources into a canonical order for identity and reporting.
%
% RECORDINGREF selects the one recording every source analysis describes, using
% the same selectors as vawlume.matching.compare:
%
%   struct(recording_id=1)
%   struct(project_key="project-a", source_relative_path="audio/rec1.wav")
%
% It is a caller assertion that is validated against every stored candidate row
% and match group of every source analysis, and against each participating
% extraction run's declared inputs. Deriving it instead would be impossible for
% a source analysis that legitimately holds no rows.
%
% AGREEMENTSPEC supplies the immutable analysis identity and the policy source:
%
%   struct(run_key="agree-v1", ...
%          profile_path="config/07_agreement_profiles/...json")
%
% profile_path may be omitted to use the tracked prototype policy under
% RepoRoot. Optional fields are run_label, vawlume_version, source_commit, and
% notes.
%
% This pass requires a complete unordered pairwise set: for N participating
% extraction runs, all N*(N-1)/2 extractor pairs must be present exactly once,
% every source must be a completed cross_extractor_matching analysis on the same
% project and recording, every run must be a distinct extractor, and every
% source must cite the same versioned matching specification. The requirement
% exists so that a missing supporting edge cannot be confused with a pair that
% was never assessed.
%
% RESULT = vawlume.agreement.compose(..., Apply=true) creates or reuses the
% policy profile version, the derived analysis run, its participating extraction
% inputs, its many-parent lineage rows, and its policy linkage, in one
% transaction. It composes no agreement groups: the derived run is left with
% status 'started' because its composition has not been performed.
%
% The agreement policy declares no temporal, feature, or agreement threshold.
% Thresholds stay in the pairwise matching specification the source analyses
% already recorded, and a policy file that tries to introduce one is refused.

arguments
    conn
    recordingRef (1,1) struct
    sources
    agreementSpec (1,1) struct
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
end

plan = agreementBuildPlan(conn, recordingRef, sources, agreementSpec, ...
    options.RepoRoot);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = agreementApplyPlan(conn, plan);
    result = agreementPlanResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    if plan.analysis.action == "reuse"
        result.status = "reused";
    else
        result.status = "committed";
    end
    return
end

result = agreementPlanResult(plan);
end
