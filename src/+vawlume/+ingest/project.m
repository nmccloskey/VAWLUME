function result = project(conn, ir, projectSpec, options)
%PROJECT Plan or atomically apply a provenance-bearing project intake.
%
% RESULT classifies the explicit project, inherited mapping-profile
% provenance, optional tracked device/setup linkage, portable sources,
% experimental graph, recordings, assignments, and audit rows as create,
% reuse, or conflict.

arguments
    conn
    ir (1,1) struct
    projectSpec (1,1) struct
    options.Apply (1,1) logical = false
    options.ProfileLinkagePath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

[ir, projectSpec] = validateProjectInputs(ir, projectSpec);
plan = buildProjectPlan(conn, ir, projectSpec, ...
    options.ProfileLinkagePath, options.RepoRoot);
if options.Apply && ~plan.has_conflicts
    [plan, appliedCounts] = applyEntityPlan(conn, plan);
    result = projectPlanResult(plan);
    result.status = plan.ingestion_run.status;
    result.committed = true;
    result.applied_counts = appliedCounts;
    return
end
result = projectPlanResult(plan);
end
