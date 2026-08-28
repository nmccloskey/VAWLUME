function plan = buildProjectPlan(conn, ir, projectSpec)
%BUILDPROJECTPLAN Resolve project, profile, and source identities read-only.

project = resolveProject(conn, projectSpec);
mappingProfile = resolveMappingProfile(conn, ir.profile);
sources = resolveSources(conn, ir.sources, project);
entityTypes = resolveEntityTypes(conn, ir.records, project);
[entities, entityRecords] = resolveEntities( ...
    conn, ir.records, project, entityTypes);
[relationships, relationshipEvidence, deferredRelationships] = ...
    resolveEntityRelationships( ...
    conn, ir.relationships, project, entities, entityRecords);
recordings = resolveRecordings(conn, ir.records, project, sources);
[recordingLinks, recordingLinkEvidence] = resolveRecordingLinks( ...
    conn, ir.relationships, project, recordings, entities, entityRecords);
ingestionFiles = planIngestionFiles(ir, sources);

plan = struct();
plan.plan_version = "0.1-draft";
plan.project = project;
plan.mapping_profile = mappingProfile;
plan.sources = sources;
plan.entity_types = entityTypes;
plan.entities = entities;
plan.entity_records = entityRecords;
plan.relationships = relationships;
plan.relationship_evidence = relationshipEvidence;
plan.deferred_relationships = deferredRelationships;
plan.recordings = recordings;
plan.recording_links = recordingLinks;
plan.recording_link_evidence = recordingLinkEvidence;
plan.ingestion_files = ingestionFiles;
plan.issues = collectIssues( ...
    project, mappingProfile, sources, entityTypes, entities, relationships, ...
    recordings, recordingLinks);
plan.has_conflicts = ~isempty(plan.issues);
end

function issues = collectIssues( ...
        project, mappingProfile, sources, entityTypes, entities, relationships, ...
        recordings, recordingLinks)
issues = emptyIssues();
if project.action == "conflict"
    issues(end + 1, :) = {"error", "PROJECT_IDENTITY_CONFLICT", ...
        "project", project.project_key, project.conflict_message};
end
if mappingProfile.profile_action == "conflict"
    issues(end + 1, :) = {"error", "MAPPING_PROFILE_CONFLICT", ...
        "mapping_profile", mappingProfile.profile_key, ...
        mappingProfile.profile_conflict_message};
end
if mappingProfile.version_action == "conflict"
    issues(end + 1, :) = {"error", "MAPPING_PROFILE_VERSION_CONFLICT", ...
        "mapping_profile_version", ...
        mappingProfile.profile_key + "@" + mappingProfile.version_label, ...
        mappingProfile.version_conflict_message};
end
conflicts = sources.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "SOURCE_IDENTITY_CONFLICT", ...
        "source_file", sources.source_key(index), ...
        sources.conflict_message(index)}; %#ok<AGROW>
end
conflicts = entityTypes.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "ENTITY_TYPE_CONFLICT", ...
        "entity_type", entityTypes.entity_type_key(index), ...
        entityTypes.conflict_message(index)}; %#ok<AGROW>
end
conflicts = entities.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "ENTITY_CONFLICT", ...
        "entity", entities.entity_key(index), ...
        entities.conflict_message(index)}; %#ok<AGROW>
end
conflicts = relationships.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "ENTITY_RELATIONSHIP_CONFLICT", ...
        "entity_relationship", relationships.relationship_key(index), ...
        relationships.conflict_message(index)}; %#ok<AGROW>
end
conflicts = recordings.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "RECORDING_CONFLICT", ...
        "recording", recordings.record_key(index), ...
        recordings.conflict_message(index)}; %#ok<AGROW>
end
conflicts = recordingLinks.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "RECORDING_LINK_CONFLICT", ...
        "recording_link", recordingLinks.recording_link_key(index), ...
        recordingLinks.conflict_message(index)}; %#ok<AGROW>
end
if ~isempty(issues)
    issues = sortrows(issues, ["category", "logical_key", "code"]);
end
end

function issues = emptyIssues()
issues = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    VariableNames=["severity", "code", "category", "logical_key", "message"]);
end
