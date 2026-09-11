function project = geometryResolveProject(conn, projectRef)
%GEOMETRYRESOLVEPROJECT Resolve exactly one project from a selector struct.
%
% Follows the recordingRef convention used by the matching and agreement layers:
% exactly one selector, never a silent preference between two.

hasId = isfield(projectRef, "project_id");
hasKey = isfield(projectRef, "project_key");
if hasId == hasKey
    error("vawlume:geometry:ProjectRefInvalid", ...
        "projectRef must contain exactly one selector: project_id or project_key.");
end

columns = "SELECT project_id, project_key FROM projects WHERE ";
if hasId
    id = geometryPositiveInteger(projectRef.project_id, "project_id");
    rows = fetch(conn, columns + "project_id=" + string(id));
else
    key = geometryScalarText(projectRef.project_key, "project_key");
    rows = fetch(conn, columns + "project_key=" + geometrySqlText(key));
end

if isempty(rows) || height(rows) == 0
    error("vawlume:geometry:ProjectNotFound", ...
        "No project matches projectRef.");
end
if height(rows) ~= 1
    error("vawlume:geometry:ProjectAmbiguous", ...
        "projectRef matched %d projects; exactly one is required.", height(rows));
end

project = struct( ...
    project_id=double(rows.project_id(1)), ...
    project_key=geometryPresentText(rows.project_key(1)));
end
