function result = registerCoordinateSystem(conn, projectRef, systemSpec)
%REGISTERCOORDINATESYSTEM Declare a spatial frame for one project.
%
%   result = VAWLUME.GEOMETRY.REGISTERCOORDINATESYSTEM(conn, projectRef, spec)
%
% A coordinate system is a declared spatial frame: a key, a name, a
% dimensionality, a unit, and optional human-readable origin and orientation
% descriptions. Microphone placement cites it, and canonicalized tracking
% streams will cite the same table, so both sides of a spatial comparison name
% one frame.
%
% PROJECTREF selects the owning project with exactly one of:
%
%   struct(project_id=7)
%   struct(project_key="my_project")
%
% SYSTEMSPEC requires:
%
%   coordinate_system_key   stable identifier, unique within the project
%   coordinate_system_name  human-readable name
%   dimensionality          2 or 3
%   unit                    'cm', 'mm', 'm', 'px', ...
%
% and optionally accepts origin_description, orientation_description, and notes.
%
% Registration is idempotent. Re-registering a key whose stored declaration is
% identical reuses it; re-registering a key with a different dimensionality,
% unit, name, or description raises vawlume:geometry:CoordinateSystemConflict
% rather than rewriting it, because rows already citing the frame were validated
% against the stored declaration.
%
% Compatibility between two spatial facts is IDENTITY of coordinate_system_id,
% never structural similarity. Two systems that both declare 2 dimensions and
% 'cm' are not interchangeable, and this function never merges them.
%
% A unit is free text and is not interpreted. A 'px' frame supports no
% real-distance computation; nothing here converts units, and no transformation
% between frames exists anywhere in VAWLUME.
%
% See also VAWLUME.GEOMETRY.REGISTERCHANNELPLACEMENT,
% VAWLUME.GEOMETRY.READCOORDINATESYSTEMS, VAWLUME.GEOMETRY.ASSERTCOMPATIBLE

arguments
    conn
    projectRef (1,1) struct
    systemSpec (1,1) struct
end

project = geometryResolveProject(conn, projectRef);
declared = normalizeSpec(systemSpec);

existing = fetch(conn, "SELECT coordinate_system_id, coordinate_system_name, " + ...
    "dimensionality, unit, IFNULL(origin_description,'') AS origin_description, " + ...
    "IFNULL(orientation_description,'') AS orientation_description, " + ...
    "IFNULL(notes,'') AS notes FROM coordinate_systems " + ...
    "WHERE project_id=" + string(project.project_id) + ...
    " AND coordinate_system_key=" + geometrySqlText(declared.coordinate_system_key));

if ~isempty(existing) && height(existing) > 0
    assertMatchesStored(existing(1, :), declared);
    result = struct( ...
        coordinate_system_id=double(existing.coordinate_system_id(1)), ...
        coordinate_system_key=declared.coordinate_system_key, ...
        project_id=project.project_id, ...
        action="reused");
    return
end

values = struct( ...
    project_id=project.project_id, ...
    coordinate_system_key=declared.coordinate_system_key, ...
    coordinate_system_name=declared.coordinate_system_name, ...
    dimensionality=declared.dimensionality, ...
    unit=declared.unit, ...
    origin_description=declared.origin_description, ...
    orientation_description=declared.orientation_description, ...
    notes=declared.notes);
id = geometryInsertRow(conn, "coordinate_systems", values, "coordinate_system_id");

result = struct( ...
    coordinate_system_id=id, ...
    coordinate_system_key=declared.coordinate_system_key, ...
    project_id=project.project_id, ...
    action="created");
end

function declared = normalizeSpec(systemSpec)
declared = struct();
declared.coordinate_system_key = geometryRequiredText(systemSpec, ...
    "coordinate_system_key");
declared.coordinate_system_name = geometryRequiredText(systemSpec, ...
    "coordinate_system_name");
declared.unit = geometryRequiredText(systemSpec, "unit");
declared.dimensionality = dimensionalityOf(systemSpec);
declared.origin_description = geometryOptionalText(systemSpec, "origin_description");
declared.orientation_description = geometryOptionalText(systemSpec, ...
    "orientation_description");
declared.notes = geometryOptionalText(systemSpec, "notes");
end

function value = dimensionalityOf(systemSpec)
if ~isfield(systemSpec, "dimensionality")
    error("vawlume:geometry:CoordinateSystemInvalid", ...
        "systemSpec.dimensionality is required and must be 2 or 3.");
end
value = systemSpec.dimensionality;
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        ~ismember(double(value), [2 3])
    error("vawlume:geometry:CoordinateSystemInvalid", ...
        "systemSpec.dimensionality must be 2 or 3. 2D is the working case " + ...
        "and 3D is representable but never required.");
end
value = double(value);
end

function assertMatchesStored(stored, declared)
%ASSERTMATCHESSTORED A stored frame is never rewritten in place.
%
% Placements already cite this frame and were validated against its stored
% dimensionality. Silently redefining it would invalidate those rows without
% touching them.
% Fetched text goes through geometryPresentText rather than string(): the
% Database Toolbox can return an empty text column as <missing>, and a missing
% element propagates silently through concatenation into the diagnostic below.
comparisons = { ...
    "coordinate_system_name", geometryPresentText(stored.coordinate_system_name), declared.coordinate_system_name; ...
    "unit", geometryPresentText(stored.unit), declared.unit; ...
    "origin_description", geometryPresentText(stored.origin_description), declared.origin_description; ...
    "orientation_description", geometryPresentText(stored.orientation_description), declared.orientation_description; ...
    "notes", geometryPresentText(stored.notes), declared.notes};

differing = strings(0, 1);
if double(stored.dimensionality) ~= declared.dimensionality
    differing(end + 1, 1) = "dimensionality (stored " + ...
        string(double(stored.dimensionality)) + ", supplied " + ...
        string(declared.dimensionality) + ")";
end
for index = 1:size(comparisons, 1)
    if comparisons{index, 2} ~= comparisons{index, 3}
        differing(end + 1, 1) = comparisons{index, 1} + " (stored '" + ...
            comparisons{index, 2} + "', supplied '" + ...
            comparisons{index, 3} + "')"; %#ok<AGROW>
    end
end

if ~isempty(differing)
    error("vawlume:geometry:CoordinateSystemConflict", ...
        "Coordinate system '%s' is already declared with different content: " + ...
        "%s. Register a new key rather than redefining a frame that existing " + ...
        "placements were validated against.", declared.coordinate_system_key, ...
        strjoin(differing(:)', "; "));
end
end
