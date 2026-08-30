function result = compare(conn, recordingRef, runPair, matchSpec, options)
%COMPARE Plan or atomically persist cross-extractor temporal candidates.
%
% RESULT = vawlume.matching.compare(CONN, RECORDINGREF, RUNPAIR, MATCHSPEC)
% resolves two explicitly selected extraction runs on one established recording,
% reads their canonical event geometry from v_detection_core, and returns every
% pair satisfying the matching specification's temporal plausibility rule.
% Planning is the default and does not write to the database.
%
% RUNPAIR preserves caller direction:
%
%   struct(run_a="deepsqueak-run", run_b="mupet-run")
%
% Each run reference may be a project-scoped run_key, a numeric
% extraction_run_id, or a struct containing exactly one of run_key and
% extraction_run_id. Signed differences are always run B minus run A. The
% candidate_pairs detection columns are independently sorted by detection ID to
% satisfy the schema and carry no directional meaning.
%
% MATCHSPEC supplies the immutable analysis identity and profile source:
%
%   struct(run_key="matching-v1", ...
%          profile_path="config/.../matching_spec.json")
%
% profile_path may be omitted to use the tracked prototype specification under
% RepoRoot. Optional fields are run_label, vawlume_version, source_commit, and
% notes. RESULT = vawlume.matching.compare(..., Apply=true) creates or reuses
% the checksum-bearing specification, analysis parent, ordered input links, and
% candidate rows in one transaction. It never creates match groups, consensus
% events, consilience assessments, or agreement statistics.

arguments
    conn
    recordingRef (1,1) struct
    runPair (1,1) struct
    matchSpec (1,1) struct
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
end

plan = matchingBuildPlan(conn, recordingRef, runPair, matchSpec, options.RepoRoot);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = matchingApplyPlan(conn, plan);
    result = matchingPlanResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    if plan.analysis.action == "reuse"
        result.status = "reused";
    else
        result.status = "committed";
    end
    return
end

result = matchingPlanResult(plan);
end
