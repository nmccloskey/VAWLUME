function plan = buildProjectPlan(conn, ir, projectSpec)
%BUILDPROJECTPLAN Resolve project, profile, and source identities read-only.

project = resolveProject(conn, projectSpec);
mappingProfile = resolveMappingProfile(conn, ir.profile);
sources = resolveSources(conn, ir.sources, project);

plan = struct();
plan.plan_version = "0.1-draft";
plan.project = project;
plan.mapping_profile = mappingProfile;
plan.sources = sources;
plan.issues = collectIssues(project, mappingProfile, sources);
plan.has_conflicts = ~isempty(plan.issues);
end

function issues = collectIssues(project, mappingProfile, sources)
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
end

function issues = emptyIssues()
issues = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    VariableNames=["severity", "code", "category", "logical_key", "message"]);
end
