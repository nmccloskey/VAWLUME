function result = distance(positionsA, frameA, positionsB, frameB, options)
%DISTANCE Euclidean distance between positions that cite one declared frame.
%
%   result = VAWLUME.GEOMETRY.DISTANCE(positionsA, frameA, positionsB, frameB)
%   result = VAWLUME.GEOMETRY.DISTANCE(..., PlanarIn3D=true)
%
% POSITIONSA and POSITIONSB are N-by-2 or N-by-3 numeric arrays of x, y and
% optionally z. Either may have a single row, which is paired with every row of
% the other (one microphone against many tracked samples, say). FRAMEA and FRAMEB
% are frame descriptors: structs with coordinate_system_id, dimensionality and
% unit, as vawlume.geometry.readChannelPlacements and readCoordinateSystems
% return them.
%
% PURE. This reads no database, no file and no clock. It is one of the three
% places spatial arithmetic may occur in VAWLUME, all in +geometry/, and it is
% what the repository-wide arithmetic guard permits by package.
%
% THE FRAMES MUST BE ONE FRAME. The two descriptors' coordinate_system_id values
% go through the same identity rule vawlume.geometry.assertCompatible applies,
% so a mismatch raises vawlume:geometry:CoordinateSystemMismatch and nothing is
% transformed, rescaled or reinterpreted. Two descriptors naming one frame but
% disagreeing about its dimensionality or unit raise
% vawlume:geometry:FrameDescriptorConflict: one of them is wrong about the frame.
%
% DIMENSIONALITY:
%   2D frame   x and y. A third column is accepted only if it is entirely NaN,
%              which is how a 2D placement reads back; a real z under a 2D frame
%              is refused (vawlume:geometry:PositionDimensionalityInvalid).
%              basis "planar".
%   3D frame   x, y and z. A row missing z on either side is NOT computed, with
%              reason "z_missing". It is never computed in the plane with z
%              treated as 0, which would claim both points lie at the origin's
%              height. basis "spatial_3d".
%              PlanarIn3D=true opts in to a declared planar distance that ignores
%              z, labelled basis "planar_declared" so it can never pass for a 3D
%              one. It is never a silent fallback.
%
% UNIT IS CARRIED, NOT INTERPRETED. result.unit is the frame's unit string,
% verbatim. A 'px' frame's distance is in 'px'. Whether a consumer may treat a
% unit as physical, or as uniform in scale, is that consumer's declared decision
% (see docs/design/06_native_estimator_contract.md D17).
%
% ABSENCE IS ABSENCE. A row with a missing x or y on either side is not computed
% (reason "position_missing") and its distance is NaN, never 0.
%
% RESULT fields:
%   distance              N-by-1, NaN where not computed
%   status                N-by-1 string, "computed" or "not_computed"
%   reason                N-by-1 string, "" when computed
%   basis                 "planar", "spatial_3d" or "planar_declared"
%   unit                  the frame's unit, verbatim
%   coordinate_system_id  the shared frame
%   dimensionality        2 or 3
%
% See also VAWLUME.GEOMETRY.ASSERTCOMPATIBLE,
% VAWLUME.GEOMETRY.POSITIONATINSTANTS, VAWLUME.GEOMETRY.SUMMARIZEDISTANCES

arguments
    positionsA double
    frameA (1,1) struct
    positionsB double
    frameB (1,1) struct
    options.PlanarIn3D (1,1) logical = false
end

frame = sharedFrame(frameA, frameB);
[a, b] = pairRows(positionsA, positionsB);
a = conformToFrame(a, frame, "positionsA");
b = conformToFrame(b, frame, "positionsB");

count = size(a, 1);
value = NaN(count, 1);
status = repmat("not_computed", count, 1);
reason = strings(count, 1);

missingPlane = any(isnan(a(:, 1:2)), 2) | any(isnan(b(:, 1:2)), 2);
reason(missingPlane) = "position_missing";

if frame.dimensionality == 2
    basis = "planar";
    usable = ~missingPlane;
    delta = a(usable, 1:2) - b(usable, 1:2);
elseif options.PlanarIn3D
    basis = "planar_declared";
    usable = ~missingPlane;
    delta = a(usable, 1:2) - b(usable, 1:2);
else
    basis = "spatial_3d";
    missingZ = ~missingPlane & (isnan(a(:, 3)) | isnan(b(:, 3)));
    reason(missingZ) = "z_missing";
    usable = ~missingPlane & ~missingZ;
    delta = a(usable, :) - b(usable, :);
end

value(usable) = sqrt(sum(delta .^ 2, 2));
status(usable) = "computed";

result = struct(distance=value, status=status, reason=reason, basis=basis, ...
    unit=frame.unit, coordinate_system_id=frame.coordinate_system_id, ...
    dimensionality=frame.dimensionality);
end

function frame = sharedFrame(frameA, frameB)
for candidate = {frameA, frameB}
    descriptor = candidate{1};
    for field = ["coordinate_system_id", "dimensionality", "unit"]
        if ~isfield(descriptor, field)
            error("vawlume:geometry:FrameDescriptorInvalid", ...
                "A frame descriptor requires coordinate_system_id, " + ...
                "dimensionality and unit; %s is missing.", field);
        end
    end
end
id = geometryAssertSameFrame([double(frameA.coordinate_system_id), ...
    double(frameB.coordinate_system_id)], "distance");
dimensionality = double(frameA.dimensionality);
if ~ismember(dimensionality, [2 3])
    error("vawlume:geometry:FrameDescriptorInvalid", ...
        "Frame %d declares dimensionality %g; a frame is 2- or 3-dimensional.", ...
        id, dimensionality);
end
if double(frameB.dimensionality) ~= dimensionality || ...
        string(frameA.unit) ~= string(frameB.unit)
    error("vawlume:geometry:FrameDescriptorConflict", ...
        "Two descriptors of frame %d disagree about its dimensionality or " + ...
        "unit (%g '%s' versus %g '%s'). One of them is wrong about the frame.", ...
        id, dimensionality, string(frameA.unit), double(frameB.dimensionality), ...
        string(frameB.unit));
end
frame = struct(coordinate_system_id=id, dimensionality=dimensionality, ...
    unit=string(frameA.unit));
end

function [a, b] = pairRows(a, b)
if ~ismatrix(a) || ~ismatrix(b) || ~ismember(size(a, 2), [2 3]) || ...
        ~ismember(size(b, 2), [2 3])
    error("vawlume:geometry:PositionDimensionalityInvalid", ...
        "Positions are N-by-2 or N-by-3 arrays of x, y and optionally z.");
end
if size(a, 1) == size(b, 1)
    return
elseif size(a, 1) == 1
    a = repmat(a, size(b, 1), 1);
elseif size(b, 1) == 1
    b = repmat(b, size(a, 1), 1);
else
    error("vawlume:geometry:PositionCountMismatch", ...
        "positionsA has %d rows and positionsB %d. They must match, or one " + ...
        "must be a single row.", size(a, 1), size(b, 1));
end
end

function positions = conformToFrame(positions, frame, name)
if frame.dimensionality == 2
    if size(positions, 2) == 3
        if any(~isnan(positions(:, 3)))
            error("vawlume:geometry:PositionDimensionalityInvalid", ...
                "%s carries a z value under 2-dimensional frame %d. A 2D frame " + ...
                "has no z; a value there is a measurement on a plane the frame " + ...
                "does not have.", name, frame.coordinate_system_id);
        end
        positions = positions(:, 1:2);
    end
elseif size(positions, 2) == 2
    % A 3D frame read with no z column: z is absent, not zero.
    positions = [positions, NaN(size(positions, 1), 1)];
end
end
