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
result.entity_type_ids = emptyIdMap("entity_type_key", "entity_type_id");
result.entity_ids = emptyIdMap("record_key", "entity_id");
result.relationship_summary = struct(created=0, reused=0, conflicts=0);
result.recording_ids = emptyIdMap("record_key", "recording_id");
result.profile_assignment_summary = struct(created=0, reused=0, conflicts=0);
result.created_counts = actionCounts(plan, "create");
result.reused_counts = actionCounts(plan, "reuse");
result.conflict_counts = actionCounts(plan, "conflict");
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
    source_files=sum(plan.sources.action == action));
end

function value = emptyIdMap(keyName, idName)
value = table(strings(0, 1), NaN(0, 1), strings(0, 1), ...
    VariableNames=[keyName, idName, "action"]);
end
