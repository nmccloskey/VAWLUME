function plan = buildProjectPlan( ...
        conn, ir, projectSpec, profileLinkagePath, repoRoot)
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
profileLinkage = resolveProfileLinkage( ...
    conn, ir.profile, profileLinkagePath, repoRoot);
[projectProfileAssignments, recordingProfileAssignments] = ...
    resolveProfileAssignments( ...
    conn, project, mappingProfile, profileLinkage, recordings);
ingestionRun = planIngestionRun(ir, project, mappingProfile);
ingestionFiles = planIngestionFiles(ir, sources);
issues = collectIssues( ...
    ir, project, mappingProfile, profileLinkage.profiles, ...
    projectProfileAssignments, recordingProfileAssignments, ...
    sources, entityTypes, entities, relationships, recordings, recordingLinks);
hasConflicts = any(issues.severity == "error");
if hasConflicts
    ingestionRun.action = "skip";
    ingestionFiles.action(:) = "skip";
end

plan = struct();
plan.plan_version = "0.2-draft";
plan.project = project;
plan.mapping_profile = mappingProfile;
plan.profile_linkage = profileLinkage;
plan.project_profile_assignments = projectProfileAssignments;
plan.recording_profile_assignments = recordingProfileAssignments;
plan.ingestion_run = ingestionRun;
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
plan.issues = issues;
plan.has_conflicts = hasConflicts;
end

function issues = collectIssues( ...
        ir, project, mappingProfile, linkedProfiles, projectAssignments, ...
        recordingAssignments, sources, entityTypes, entities, relationships, ...
        recordings, recordingLinks)
issues = irIssues(ir);
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
conflicts = linkedProfiles.profile_action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "LINKED_PROFILE_CONFLICT", ...
        "linked_profile", linkedProfiles.profile_key(index), ...
        linkedProfiles.profile_conflict_message(index)}; %#ok<AGROW>
end
conflicts = linkedProfiles.version_action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", "LINKED_PROFILE_VERSION_CONFLICT", ...
        "linked_profile_version", linkedProfiles.profile_key(index) + ...
        "@" + linkedProfiles.version_label(index), ...
        linkedProfiles.version_conflict_message(index)}; %#ok<AGROW>
end
conflicts = projectAssignments.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", ...
        "PROJECT_PROFILE_ASSIGNMENT_CONFLICT", ...
        "project_profile_assignment", ...
        projectAssignments.assignment_key(index), ...
        projectAssignments.conflict_message(index)}; %#ok<AGROW>
end
conflicts = recordingAssignments.action == "conflict";
for index = find(conflicts)'
    issues(end + 1, :) = {"error", ...
        "RECORDING_PROFILE_ASSIGNMENT_CONFLICT", ...
        "recording_profile_assignment", ...
        recordingAssignments.assignment_key(index), ...
        recordingAssignments.conflict_message(index)}; %#ok<AGROW>
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

function issues = irIssues(ir)
issues = emptyIssues();
if ~isfield(ir, "issues") || ~istable(ir.issues) || isempty(ir.issues)
    return
end
required = ["severity", "code", "message"];
if ~all(ismember(required, string(ir.issues.Properties.VariableNames)))
    return
end
for index = 1:height(ir.issues)
    severity = string(ir.issues.severity(index));
    if ~ismember(severity, ["warning", "error", "fatal"])
        continue
    end
    if severity == "fatal"
        severity = "error";
    end
    logicalKey = issueLogicalKey(ir.issues(index, :), index);
    issues(end + 1, :) = { ...
        severity, string(ir.issues.code(index)), "source_mapping", ...
        logicalKey, string(ir.issues.message(index))}; %#ok<AGROW>
end
end

function key = issueLogicalKey(issue, index)
key = "issue:" + string(index);
for field = ["issue_key", "record_key", "source_key", "location"]
    if ismember(field, string(issue.Properties.VariableNames))
        candidate = string(issue.(field)(1));
        if ~ismissing(candidate) && strlength(candidate) > 0
            key = candidate;
            return
        end
    end
end
end

function issues = emptyIssues()
issues = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    VariableNames=["severity", "code", "category", "logical_key", "message"]);
end
