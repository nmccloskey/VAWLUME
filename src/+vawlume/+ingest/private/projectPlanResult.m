function result = projectPlanResult(plan)
%PROJECTPLANRESULT Build the stable developer-facing planning manifest.

result = struct();
if plan.has_conflicts
    result.status = "conflict";
else
    result.status = "planned";
end
result.committed = false;
result.project_id = resolvedId(plan.project.action, ...
    plan.project.existing_project_id);
result.ingestion_run_id = NaN;
result.mapping_profile_version_id = resolvedId( ...
    plan.mapping_profile.version_action, ...
    plan.mapping_profile.existing_profile_version_id);
result.source_ids = plan.sources(:, ...
    ["source_key", "existing_source_file_id", "action"]);
result.source_ids.Properties.VariableNames{2} = 'source_file_id';
result.entity_type_ids = plan.entity_types(:, ...
    ["entity_type_key", "existing_entity_type_id", "action"]);
result.entity_type_ids.Properties.VariableNames{2} = 'entity_type_id';
result.entity_ids = plan.entity_records(:, ...
    ["record_key", "existing_entity_id", "action"]);
result.entity_ids.Properties.VariableNames{2} = 'entity_id';
result.relationship_summary = struct( ...
    created=sum(plan.relationships.action == "create"), ...
    reused=sum(plan.relationships.action == "reuse"), ...
    conflicts=sum(plan.relationships.action == "conflict"), ...
    deferred=height(plan.deferred_relationships));
result.recording_ids = emptyIdMap("record_key", "recording_id");
result.profile_assignment_summary = struct(created=0, reused=0, conflicts=0);
result.created_counts = actionCounts(plan, "create");
result.reused_counts = actionCounts(plan, "reuse");
result.conflict_counts = actionCounts(plan, "conflict");
result.applied_counts = zeroAppliedCounts();
result.issues = plan.issues;
result.plan = plan;
end

function value = resolvedId(action, id)
if action == "reuse"
    value = id;
else
    value = NaN;
end
end

function value = actionCounts(plan, action)
value = struct( ...
    projects=double(plan.project.action == action), ...
    mapping_profiles=double(plan.mapping_profile.profile_action == action), ...
    mapping_profile_versions=double(plan.mapping_profile.version_action == action), ...
    source_files=sum(plan.sources.action == action), ...
    entity_types=sum(plan.entity_types.action == action), ...
    entities=sum(plan.entities.action == action), ...
    entity_relationships=sum(plan.relationships.action == action));
end

function value = emptyIdMap(keyName, idName)
value = table(strings(0, 1), NaN(0, 1), strings(0, 1), ...
    VariableNames=[keyName, idName, "action"]);
end

function value = zeroAppliedCounts()
value = struct(projects=0, entity_types=0, entities=0, ...
    entity_relationships=0, reused_projects=0, reused_entity_types=0, ...
    reused_entities=0, reused_entity_relationships=0);
end
