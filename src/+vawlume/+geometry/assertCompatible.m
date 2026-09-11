function system = assertCompatible(conn, coordinateSystemIds, options)
%ASSERTCOMPATIBLE Require spatial facts to share one declared frame.
%
%   system = VAWLUME.GEOMETRY.ASSERTCOMPATIBLE(conn, coordinateSystemIds)
%   system = VAWLUME.GEOMETRY.ASSERTCOMPATIBLE(..., Context="tracking join")
%
% Spatial compatibility in VAWLUME is IDENTITY of coordinate_system_id, never
% structural similarity. Two frames that both declare 2 dimensions and 'cm' are
% not interchangeable: they may have different origins, different axis
% directions, or describe different arenas. Treating matching metadata as licence
% to compare coordinates is how a confident, wrong distance gets computed, so
% this function compares identifiers and nothing else.
%
% COORDINATESYSTEMIDS is a vector of coordinate_system_id values that a caller is
% about to relate - for example a tracking stream's frame and the frame of the
% channel placements it would be measured against. When every value is the same
% declared frame, the frame's row is returned. Otherwise the call raises
% vawlume:geometry:CoordinateSystemMismatch and nothing is transformed,
% rescaled, or reinterpreted to make the comparison possible.
%
% CONTEXT is optional text naming the operation, used only to make the error
% message legible at the call site.
%
% This is the reusable primitive later spatial work composes: a caller resolves
% the frames of the things it wants to relate, then asks here whether relating
% them is declared legal. It performs no spatial arithmetic of its own.
%
% VAWLUME never transforms between spatial frames. If two frames genuinely
% describe one space, the correct fix is upstream - produce the data in one
% frame - not a transform inferred here.
%
% See also VAWLUME.GEOMETRY.READCOORDINATESYSTEMS,
% VAWLUME.GEOMETRY.READCHANNELPLACEMENTS

arguments
    conn
    coordinateSystemIds (1,:) double
    options.Context (1,1) string = ""
end

if isempty(coordinateSystemIds)
    error("vawlume:geometry:CoordinateSystemMismatch", ...
        "%sNo coordinate system was supplied, so compatibility cannot be " + ...
        "established. Absence of a declared frame is not compatibility.", ...
        contextPrefix(options.Context));
end
if any(~isfinite(coordinateSystemIds)) || ...
        any(coordinateSystemIds <= 0) || ...
        any(coordinateSystemIds ~= floor(coordinateSystemIds))
    error("vawlume:geometry:CoordinateSystemMismatch", ...
        "%sCoordinate system identifiers must be positive integers.", ...
        contextPrefix(options.Context));
end

distinct = unique(coordinateSystemIds);
if numel(distinct) ~= 1
    error("vawlume:geometry:CoordinateSystemMismatch", ...
        "%s%d different coordinate systems were supplied (%s). Spatial " + ...
        "compatibility is identity of the declared frame, and VAWLUME " + ...
        "performs no transformation between frames. Produce the data in one " + ...
        "frame rather than relating two.", contextPrefix(options.Context), ...
        numel(distinct), strjoin(string(distinct(:)'), ", "));
end

rows = fetch(conn, "SELECT coordinate_system_id, project_id, " + ...
    "coordinate_system_key, coordinate_system_name, dimensionality, unit " + ...
    "FROM coordinate_systems WHERE coordinate_system_id=" + string(distinct));
if isempty(rows) || height(rows) == 0
    error("vawlume:geometry:CoordinateSystemNotFound", ...
        "%sCoordinate system %d is not declared.", ...
        contextPrefix(options.Context), distinct);
end

system = struct( ...
    coordinate_system_id=double(rows.coordinate_system_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    coordinate_system_key=geometryPresentText(rows.coordinate_system_key(1)), ...
    coordinate_system_name=geometryPresentText(rows.coordinate_system_name(1)), ...
    dimensionality=double(rows.dimensionality(1)), ...
    unit=geometryPresentText(rows.unit(1)));
end

function value = contextPrefix(context)
value = "";
if strlength(context) > 0
    value = context + ": ";
end
end
