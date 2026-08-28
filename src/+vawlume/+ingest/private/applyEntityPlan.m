function [plan, counts] = applyEntityPlan(conn, plan)
%APPLYENTITYPLAN Atomically apply the project graph through recording context.

if plan.has_conflicts
    error("vawlume:ingest:PlanConflict", ...
        "An intake plan with conflicts cannot be applied.");
end
oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:ingest:TransactionState", ...
        "Project graph apply requires a connection with AutoCommit enabled.");
end

counts = emptyCounts();
if ~hasCreates(plan)
    [plan, counts] = applyProject(conn, plan, counts);
    [plan, counts] = applySources(conn, plan, counts);
    [plan, counts] = applyEntityTypes(conn, plan, counts);
    [plan, counts] = applyEntities(conn, plan, counts);
    [plan, counts] = applyRelationships(conn, plan, counts);
    [plan, counts] = applyRecordings(conn, plan, counts);
    [plan, counts] = applyRecordingLinks(conn, plan, counts);
    return
end

conn.AutoCommit = "off";
try
    [plan, counts] = applyProject(conn, plan, counts);
    [plan, counts] = applySources(conn, plan, counts);
    [plan, counts] = applyEntityTypes(conn, plan, counts);
    [plan, counts] = applyEntities(conn, plan, counts);
    [plan, counts] = applyRelationships(conn, plan, counts);
    [plan, counts] = applyRecordings(conn, plan, counts);
    [plan, counts] = applyRecordingLinks(conn, plan, counts);
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
    any(plan.sources.action == "create") || ...
    any(plan.entity_types.action == "create") || ...
    any(plan.entities.action == "create") || ...
    any(plan.relationships.action == "create") || ...
    any(plan.recordings.action == "create") || ...
    any(plan.recording_links.action == "create");
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
plan.recordings.project_id(:) = projectId;
plan.recording_links.project_id(:) = projectId;
end

function [plan, counts] = applySources(conn, plan, counts)
for index = 1:height(plan.sources)
    action = plan.sources.action(index);
    if action == "create"
        id = insertIntakeRow(conn, "source_files", struct( ...
            project_id=plan.project.existing_project_id, ...
            file_role=plan.sources.file_role(index), ...
            path_or_uri=plan.sources.path_or_uri(index), ...
            relative_path=plan.sources.relative_path(index), ...
            filename=plan.sources.filename(index), ...
            file_format=plan.sources.file_format(index), ...
            checksum_sha256=plan.sources.checksum_sha256(index)), ...
            "source_file_id");
        counts.source_files = counts.source_files + 1;
    elseif action == "reuse"
        id = plan.sources.existing_source_file_id(index);
        counts.reused_source_files = counts.reused_source_files + 1;
    else
        error("vawlume:ingest:PlanConflict", ...
            "Source action '%s' cannot be applied.", action);
    end
    plan.sources.existing_source_file_id(index) = id;
    recordingMatches = plan.recordings.source_key == ...
        plan.sources.source_key(index);
    plan.recordings.source_file_id(recordingMatches) = id;
    ingestionMatches = plan.ingestion_files.source_key == ...
        plan.sources.source_key(index);
    plan.ingestion_files.source_file_id(ingestionMatches) = id;
end
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
    linkMatches = plan.recording_links.entity_key == ...
        plan.entities.entity_key(index);
    plan.recording_links.entity_id(linkMatches) = id;
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

function [plan, counts] = applyRecordings(conn, plan, counts)
for index = 1:height(plan.recordings)
    action = plan.recordings.action(index);
    if action == "create"
        id = insertIntakeRow(conn, "recordings", struct( ...
            project_id=plan.project.existing_project_id, ...
            source_file_id=plan.recordings.source_file_id(index), ...
            native_recording_id=plan.recordings.native_recording_id(index), ...
            checksum_sha256=plan.recordings.checksum_sha256(index)), ...
            "recording_id");
        counts.recordings = counts.recordings + 1;
    elseif action == "reuse"
        id = plan.recordings.existing_recording_id(index);
        counts.reused_recordings = counts.reused_recordings + 1;
    else
        error("vawlume:ingest:PlanConflict", ...
            "Recording action '%s' cannot be applied.", action);
    end
    plan.recordings.existing_recording_id(index) = id;
    matches = plan.recording_links.recording_key == ...
        plan.recordings.record_key(index);
    plan.recording_links.recording_id(matches) = id;
end
end

function [plan, counts] = applyRecordingLinks(conn, plan, counts)
for index = 1:height(plan.recording_links)
    action = plan.recording_links.action(index);
    if action == "create"
        id = insertIntakeRow(conn, "recording_entity_links", struct( ...
            recording_id=plan.recording_links.recording_id(index), ...
            entity_id=plan.recording_links.entity_id(index), ...
            link_type=plan.recording_links.link_type(index), ...
            role_label=plan.recording_links.role_label(index)), ...
            "recording_entity_link_id");
        counts.recording_entity_links = counts.recording_entity_links + 1;
    elseif action == "reuse"
        id = plan.recording_links.existing_recording_entity_link_id(index);
        counts.reused_recording_entity_links = ...
            counts.reused_recording_entity_links + 1;
    else
        error("vawlume:ingest:PlanConflict", ...
            "Recording-link action '%s' cannot be applied.", action);
    end
    plan.recording_links.existing_recording_entity_link_id(index) = id;
end
end

function value = emptyCounts()
value = struct(projects=0, source_files=0, entity_types=0, entities=0, ...
    entity_relationships=0, recordings=0, recording_entity_links=0, ...
    reused_projects=0, reused_source_files=0, reused_entity_types=0, ...
    reused_entities=0, reused_entity_relationships=0, reused_recordings=0, ...
    reused_recording_entity_links=0);
end
