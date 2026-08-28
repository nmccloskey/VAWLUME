function project = resolveProject(conn, projectSpec)
%RESOLVEPROJECT Classify explicit project identity against current rows.

project = struct( ...
    action="create", ...
    existing_project_id=NaN, ...
    project_key=projectSpec.project_key, ...
    project_name=projectSpec.project_name, ...
    description=projectSpec.description, ...
    conflict_message="");

rows = fetch(conn, ...
    "SELECT project_id, project_key, project_name, " + ...
    "IFNULL(description, '') AS description FROM projects");
if isempty(rows)
    return
end
match = rows(string(rows.project_key) == projectSpec.project_key, :);
if isempty(match)
    return
end

project.existing_project_id = double(match.project_id(1));
storedName = string(match.project_name(1));
storedDescription = string(match.description(1));
descriptionCompatible = strlength(projectSpec.description) == 0 || ...
    strlength(storedDescription) == 0 || storedDescription == projectSpec.description;
if storedName == projectSpec.project_name && descriptionCompatible
    project.action = "reuse";
else
    project.action = "conflict";
    project.conflict_message = ...
        "Existing project_key has incompatible project_name or description.";
end
end
