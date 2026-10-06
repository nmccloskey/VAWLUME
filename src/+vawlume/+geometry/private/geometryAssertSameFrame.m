function coordinateSystemId = geometryAssertSameFrame(coordinateSystemIds, context)
%GEOMETRYASSERTSAMEFRAME The identity rule for spatial frames, and its only implementation.
%
% Two spatial facts may be related if and only if they cite the same
% coordinate_system_id. Structural similarity never suffices: two 2D 'cm' frames
% may have different origins or describe different arenas.
%
% This is the comparison VAWLUME.GEOMETRY.ASSERTCOMPATIBLE makes before it looks
% the frame up, extracted so that the pure spatial primitives (distance,
% positionAtInstants) apply exactly the same rule without a database connection.
% One rule, one implementation: a second local id comparison would be a second
% copy of the decision that compatibility is identity, and copies drift.
%
% Returns the single shared identifier, or raises
% vawlume:geometry:CoordinateSystemMismatch with the messages assertCompatible
% has always raised.

arguments
    coordinateSystemIds (1,:) double
    context (1,1) string = ""
end

if isempty(coordinateSystemIds)
    error("vawlume:geometry:CoordinateSystemMismatch", ...
        "%sNo coordinate system was supplied, so compatibility cannot be " + ...
        "established. Absence of a declared frame is not compatibility.", ...
        geometryContextPrefix(context));
end
if any(~isfinite(coordinateSystemIds)) || ...
        any(coordinateSystemIds <= 0) || ...
        any(coordinateSystemIds ~= floor(coordinateSystemIds))
    error("vawlume:geometry:CoordinateSystemMismatch", ...
        "%sCoordinate system identifiers must be positive integers.", ...
        geometryContextPrefix(context));
end

distinct = unique(coordinateSystemIds);
if numel(distinct) ~= 1
    error("vawlume:geometry:CoordinateSystemMismatch", ...
        "%s%d different coordinate systems were supplied (%s). Spatial " + ...
        "compatibility is identity of the declared frame, and VAWLUME " + ...
        "performs no transformation between frames. Produce the data in one " + ...
        "frame rather than relating two.", geometryContextPrefix(context), ...
        numel(distinct), strjoin(string(distinct(:)'), ", "));
end
coordinateSystemId = distinct;
end
