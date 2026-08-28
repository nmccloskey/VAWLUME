function result = project(conn, ir, projectSpec, options)
%PROJECT Plan project intake and optionally apply through recording context.
%
% RESULT classifies the explicit project, inherited mapping-profile
% provenance, portable sources, entity types, entities, and relationships as
% create, reuse, or conflict. Apply=true transactionally creates the project,
% portable sources, experimental graph, recordings, and recording links.
% Profile registration and ingestion-run provenance remain deferred.

arguments
    conn
    ir (1,1) struct
    projectSpec (1,1) struct
    options.Apply (1,1) logical = false
end

[ir, projectSpec] = validateProjectInputs(ir, projectSpec);
plan = buildProjectPlan(conn, ir, projectSpec);
if options.Apply && ~plan.has_conflicts
    [plan, appliedCounts] = applyEntityPlan(conn, plan);
    result = projectPlanResult(plan);
    result.status = "recording_graph_committed";
    result.committed = true;
    result.applied_counts = appliedCounts;
    return
end
result = projectPlanResult(plan);
end
