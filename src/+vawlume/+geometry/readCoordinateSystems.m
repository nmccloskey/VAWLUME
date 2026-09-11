function systems = readCoordinateSystems(conn, projectRef)
%READCOORDINATESYSTEMS Declared spatial frames of one project.
%
%   systems = VAWLUME.GEOMETRY.READCOORDINATESYSTEMS(conn, projectRef)
%
% Returns one row per declared frame, ordered by key, with identity, name,
% dimensionality, unit, and the free-text origin and orientation descriptions.
%
% Read-only. Origin and orientation are human-readable provenance and are never
% machine-applied: VAWLUME performs no transformation between spatial frames.
%
% See also VAWLUME.GEOMETRY.REGISTERCOORDINATESYSTEM,
% VAWLUME.GEOMETRY.READCHANNELPLACEMENTS

arguments
    conn
    projectRef (1,1) struct
end

project = geometryResolveProject(conn, projectRef);
rows = fetch(conn, "SELECT coordinate_system_id, coordinate_system_key, " + ...
    "coordinate_system_name, dimensionality, unit, " + ...
    "IFNULL(origin_description,'') AS origin_description, " + ...
    "IFNULL(orientation_description,'') AS orientation_description, " + ...
    "IFNULL(notes,'') AS notes FROM coordinate_systems " + ...
    "WHERE project_id=" + string(project.project_id) + ...
    " ORDER BY coordinate_system_key");

if isempty(rows) || height(rows) == 0
    systems = emptySystems();
    return
end

systems = table(double(rows.coordinate_system_id), ...
    geometryPresentText(rows.coordinate_system_key), ...
    geometryPresentText(rows.coordinate_system_name), ...
    double(rows.dimensionality), geometryPresentText(rows.unit), ...
    geometryPresentText(rows.origin_description), ...
    geometryPresentText(rows.orientation_description), ...
    geometryPresentText(rows.notes), ...
    VariableNames=systemVariableNames());
end

function value = emptySystems()
names = systemVariableNames();
types = repmat("string", 1, numel(names));
types(ismember(names, ["coordinate_system_id", "dimensionality"])) = "double";
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end

function names = systemVariableNames()
names = ["coordinate_system_id", "coordinate_system_key", ...
    "coordinate_system_name", "dimensionality", "unit", ...
    "origin_description", "orientation_description", "notes"];
end
