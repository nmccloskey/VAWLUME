function result = project(conn, ir, projectSpec)
%PROJECT Build a read-only relational resolution plan for project intake.
%
% RESULT classifies the explicit project, inherited mapping-profile
% provenance, and portable source identities as create, reuse, or conflict.
% This Phase 3 planning boundary performs no relational mutation.

arguments
    conn
    ir (1,1) struct
    projectSpec (1,1) struct
end

[ir, projectSpec] = validateProjectInputs(ir, projectSpec);
plan = buildProjectPlan(conn, ir, projectSpec);
result = projectPlanResult(plan);
end
