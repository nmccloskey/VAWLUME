function [plan, counts] = applyEntityPlan(conn, plan)
%APPLYENTITYPLAN Atomically create the project and planned experimental graph.

if plan.has_conflicts
    error("vawlume:ingest:PlanConflict", ...
        "An intake plan with conflicts cannot be applied.");
end
oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:ingest:TransactionState", ...
        "Entity graph apply requires a connection with AutoCommit enabled.");
end

counts = emptyCounts();
if ~hasCreates(plan)
    [plan, counts] = applyProject(conn, plan, counts);
    [plan, counts] = applyEntityTypes(conn, plan, counts);
    [plan, counts] = applyEntities(conn, plan, counts);
    [plan, counts] = applyRelationships(conn, plan, counts);
    return
end

conn.AutoCommit = "off";
try
    [plan, counts] = applyProject(conn, plan, counts);
    [plan, counts] = applyEntityTypes(conn, plan, counts);
    [plan, counts] = applyEntities(conn, plan, counts);
    [plan, counts] = applyRelationships(conn, plan, counts);
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

function value = hasCreates(plan)
value = plan.project.action == "create" || ...
    any(plan.entity_types.action == "create") || ...
    any(plan.entities.action == "create") || ...
    any(plan.relationships.action == "create");
end

function [plan, counts] = applyProject(conn, plan, counts)
if plan.project.action == "create"
    projectId = insertIntakeRow(conn, "projects", struct( ...
        project_key=plan.project.project_key, ...
        project_name=plan.project.project_name, ...
        description=plan.project.description), "project_id");
    counts.projects = 1;
elseif plan.project.action == "reuse"
    projectId = plan.project.existing_project_id;
    counts.reused_projects = 1;
else
    error("vawlume:ingest:PlanConflict", ...
        "Project action '%s' cannot be applied.", plan.project.action);
end
plan.project.existing_project_id = projectId;
plan.sources.project_id(:) = projectId;
plan.entity_types.project_id(:) = projectId;
plan.entities.project_id(:) = projectId;
plan.relationships.project_id(:) = projectId;
end

function [plan, counts] = applyEntityTypes(conn, plan, counts)
for index = 1:height(plan.entity_types)
    action = plan.entity_types.action(index);
    if action == "create"
        id = insertIntakeRow(conn, "entity_types", struct( ...
            project_id=plan.project.existing_project_id, ...
            native_name=plan.entity_types.native_name(index), ...
            canonical_role=plan.entity_types.canonical_role(index), ...
            is_biological_unit=false, ...
            is_subject_like=false), "entity_type_id");
        counts.entity_types = counts.entity_types + 1;
    elseif action == "reuse"
        id = plan.entity_types.existing_entity_type_id(index);
        counts.reused_entity_types = counts.reused_entity_types + 1;
    else
        error("vawlume:ingest:PlanConflict", ...
            "Entity-type action '%s' cannot be applied.", action);
    end
    plan.entity_types.existing_entity_type_id(index) = id;
    matches = plan.entities.entity_type_key == ...
        plan.entity_types.entity_type_key(index);
    plan.entities.entity_type_id(matches) = id;
end
end

function [plan, counts] = applyEntities(conn, plan, counts)
for index = 1:height(plan.entities)
    action = plan.entities.action(index);
    if action == "create"
        id = insertIntakeRow(conn, "experimental_entities", struct( ...
            project_id=plan.project.existing_project_id, ...
            entity_type_id=plan.entities.entity_type_id(index), ...
            native_id=plan.entities.native_id(index)), "entity_id");
        counts.entities = counts.entities + 1;
    elseif action == "reuse"
        id = plan.entities.existing_entity_id(index);
        counts.reused_entities = counts.reused_entities + 1;
    else
        error("vawlume:ingest:PlanConflict", ...
            "Entity action '%s' cannot be applied.", action);
    end
    plan.entities.existing_entity_id(index) = id;
    matches = plan.entity_records.entity_key == plan.entities.entity_key(index);
    plan.entity_records.existing_entity_id(matches) = id;
    parentMatches = plan.relationships.parent_entity_key == ...
        plan.entities.entity_key(index);
    childMatches = plan.relationships.child_entity_key == ...
        plan.entities.entity_key(index);
    plan.relationships.parent_entity_id(parentMatches) = id;
    plan.relationships.child_entity_id(childMatches) = id;
end
end

function [plan, counts] = applyRelationships(conn, plan, counts)
for index = 1:height(plan.relationships)
    action = plan.relationships.action(index);
    if action == "create"
        id = insertIntakeRow(conn, "entity_relationships", struct( ...
            project_id=plan.project.existing_project_id, ...
            parent_entity_id=plan.relationships.parent_entity_id(index), ...
            child_entity_id=plan.relationships.child_entity_id(index), ...
            relationship_type=plan.relationships.relationship_type(index), ...
            role_label=plan.relationships.role_label(index), ...
            source_locator=plan.relationships.source_locator(index), ...
            mapping_rule_key=plan.relationships.mapping_rule_key(index)), ...
            "entity_relationship_id");
        counts.entity_relationships = counts.entity_relationships + 1;
    elseif action == "reuse"
        id = plan.relationships.existing_entity_relationship_id(index);
        counts.reused_entity_relationships = ...
            counts.reused_entity_relationships + 1;
    else
        error("vawlume:ingest:PlanConflict", ...
            "Entity-relationship action '%s' cannot be applied.", action);
    end
    plan.relationships.existing_entity_relationship_id(index) = id;
end
end

function value = emptyCounts()
value = struct(projects=0, entity_types=0, entities=0, ...
    entity_relationships=0, reused_projects=0, reused_entity_types=0, ...
    reused_entities=0, reused_entity_relationships=0);
end
