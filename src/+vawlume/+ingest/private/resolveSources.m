function sources = resolveSources(conn, irSources, project)
%RESOLVESOURCES Resolve portable source identity without runtime-root identity.

count = height(irSources);
sources = table( ...
    string(irSources.source_key), repmat("create", count, 1), NaN(count, 1), ...
    repmat(project.existing_project_id, count, 1), ...
    sourceRoles(irSources), string(irSources.relative_path), ...
    string(irSources.relative_path), string(irSources.runtime_path), ...
    string(irSources.filename), strings(count, 1), ...
    string(irSources.checksum_sha256), string(irSources.status), ...
    strings(count, 1), ...
    VariableNames=["source_key", "action", "existing_source_file_id", ...
    "project_id", "file_role", "path_or_uri", "relative_path", ...
    "runtime_path", "filename", "file_format", "checksum_sha256", ...
    "source_status", "conflict_message"]);
sources = sortrows(sources, "source_key");

if project.action ~= "reuse"
    if project.action == "conflict"
        sources.action(:) = "skip";
    end
    return
end

rows = fetch(conn, "SELECT source_file_id, project_id, file_role, path_or_uri, " + ...
    "IFNULL(relative_path, '') AS relative_path, IFNULL(filename, '') AS filename, " + ...
    "IFNULL(file_format, '') AS file_format, " + ...
    "IFNULL(checksum_sha256, '') AS checksum_sha256 FROM source_files");
if isempty(rows)
    return
end
rows = rows(double(rows.project_id) == project.existing_project_id, :);
for index = 1:height(sources)
    match = rows(string(rows.path_or_uri) == sources.path_or_uri(index), :);
    if isempty(match)
        continue
    end
    sources.existing_source_file_id(index) = double(match.source_file_id(1));
    compatible = string(match.file_role(1)) == sources.file_role(index) && ...
        string(match.relative_path(1)) == sources.relative_path(index) && ...
        compatibleOptional(string(match.filename(1)), sources.filename(index)) && ...
        compatibleOptional(string(match.checksum_sha256(1)), ...
        sources.checksum_sha256(index));
    if compatible
        sources.action(index) = "reuse";
        sources.file_format(index) = string(match.file_format(1));
    else
        sources.action(index) = "conflict";
        sources.conflict_message(index) = ...
            "Existing project-relative source has incompatible role or provenance.";
    end
end
end

function roles = sourceRoles(irSources)
roles = string(irSources.artifact_type);
missing = strlength(roles) == 0;
roles(missing) = string(irSources.source_type(missing));
end

function value = compatibleOptional(stored, proposed)
value = strlength(stored) == 0 || strlength(proposed) == 0 || stored == proposed;
end
