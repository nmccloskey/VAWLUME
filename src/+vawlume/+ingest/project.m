function result = project(conn, ir, projectSpec, options)
%PROJECT Plan project intake and optionally apply its experimental entity graph.
%
% RESULT classifies the explicit project, inherited mapping-profile
% provenance, portable sources, entity types, entities, and relationships as
% create, reuse, or conflict. Apply=true transactionally creates only the
% project and experimental entity graph; recordings remain deferred.

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
    result.status = "entity_graph_committed";
    result.committed = true;
    result.applied_counts = appliedCounts;
    return
end
result = projectPlanResult(plan);
end
