function result = registerChannelPlacement(conn, recordingRef, placementSpec)
%REGISTERCHANNELPLACEMENT Locate one recording channel's microphone in a frame.
%
%   result = VAWLUME.GEOMETRY.REGISTERCHANNELPLACEMENT(conn, recordingRef, spec)
%
% Placement attaches to a recording channel because a microphone reaches VAWLUME
% as a recording channel. A channel belongs to exactly one recording, so a
% placement is session-specific by construction: it cannot claim a position that
% outlives the session it was measured in. A four-microphone interface produces
% four channels with four placements, which are four different microphones in
% four different places rather than duplication.
%
% RECORDINGREF selects the recording with exactly one of:
%
%   struct(recording_id=12)
%   struct(project_key="my_project", source_relative_path="audio/s01.wav")
%
% PLACEMENTSPEC requires:
%
%   channel_index           1-based index of an established recording channel
%   coordinate_system_key   a frame already declared for this project
%   position_x, position_y  coordinates in that frame's unit
%
% and optionally accepts position_z, placement_role, orientation_description,
% source_profile_version_id, and notes.
%
% POSITION_Z is permitted only when the cited frame declares dimensionality 3,
% and remains optional even then: an unknown height is missing data rather than
% a modelling error. The schema enforces this independently through
% trg_channel_placement_dimensionality; the check here exists to name the problem
% in VAWLUME's vocabulary rather than SQLite's.
%
% Reusable recording-device and experimental-setup profiles are placement
% PROVENANCE, not placement authority: their geometry blocks may be applied to
% many sessions, so neither can answer where a microphone was during one
% recording. Pass the originating config_profile_versions row as
% source_profile_version_id to record where the numbers came from.
%
% That citation is validated rather than merely stored. It must name an existing
% profile version of kind recording_device or experimental_setup - the two kinds
% that carry geometry - and that profile must belong to this recording's project
% or be a built-in whose project_id is NULL. A foreign key alone would prove only
% that some row exists, so a placement could cite an extractor's output profile
% from an unrelated experiment and read back as though it were auditable
% provenance.
%
% One placement per channel. A microphone moved mid-recording is not
% representable and needs an explicit time-bounded model rather than a second
% row. Re-registering a channel whose stored placement is identical reuses it;
% re-registering with different coordinates raises
% vawlume:geometry:PlacementConflict.
%
% Native recording observations are never modified.
%
% See also VAWLUME.GEOMETRY.REGISTERCOORDINATESYSTEM,
% VAWLUME.GEOMETRY.READCHANNELPLACEMENTS, VAWLUME.GEOMETRY.ASSERTCOMPATIBLE

arguments
    conn
    recordingRef (1,1) struct
    placementSpec (1,1) struct
end

recording = geometryResolveRecording(conn, recordingRef);
channel = geometryResolveChannel(conn, recording, placementSpec);
declared = normalizeSpec(placementSpec);
system = resolveCoordinateSystem(conn, recording, declared.coordinate_system_key);
assertDimensionality(system, declared);
assertSourceProfile(conn, recording, declared.source_profile_version_id);

existing = fetch(conn, "SELECT channel_placement_id, coordinate_system_id, " + ...
    "position_x, position_y, IFNULL(position_z, 1e308) AS position_z, " + ...
    "IFNULL(placement_role,'') AS placement_role, " + ...
    "IFNULL(orientation_description,'') AS orientation_description, " + ...
    "IFNULL(notes,'') AS notes FROM channel_placements " + ...
    "WHERE recording_channel_id=" + string(channel.recording_channel_id));

if ~isempty(existing) && height(existing) > 0
    assertMatchesStored(existing(1, :), declared, system, channel);
    result = placementResult(double(existing.channel_placement_id(1)), ...
        channel, system, "reused");
    return
end

values = struct( ...
    recording_channel_id=channel.recording_channel_id, ...
    coordinate_system_id=system.coordinate_system_id, ...
    position_x=declared.position_x, ...
    position_y=declared.position_y, ...
    placement_role=declared.placement_role, ...
    orientation_description=declared.orientation_description, ...
    notes=declared.notes);
if ~isnan(declared.position_z)
    values.position_z = declared.position_z;
end
if ~isnan(declared.source_profile_version_id)
    values.source_profile_version_id = declared.source_profile_version_id;
end

id = geometryInsertRow(conn, "channel_placements", values, "channel_placement_id");
result = placementResult(id, channel, system, "created");
end

function declared = normalizeSpec(placementSpec)
declared = struct();
declared.coordinate_system_key = geometryRequiredText(placementSpec, ...
    "coordinate_system_key");
declared.position_x = requiredFiniteReal(placementSpec, "position_x");
declared.position_y = requiredFiniteReal(placementSpec, "position_y");
declared.position_z = optionalFiniteReal(placementSpec, "position_z");
declared.placement_role = geometryOptionalText(placementSpec, "placement_role");
declared.orientation_description = geometryOptionalText(placementSpec, ...
    "orientation_description");
declared.notes = geometryOptionalText(placementSpec, "notes");
declared.source_profile_version_id = optionalPositiveInteger(placementSpec, ...
    "source_profile_version_id");
end

function system = resolveCoordinateSystem(conn, recording, key)
rows = fetch(conn, "SELECT coordinate_system_id, coordinate_system_name, " + ...
    "dimensionality, unit FROM coordinate_systems " + ...
    "WHERE project_id=" + string(recording.project_id) + ...
    " AND coordinate_system_key=" + geometrySqlText(key));
if isempty(rows) || height(rows) == 0
    error("vawlume:geometry:CoordinateSystemNotFound", ...
        "No coordinate system '%s' is declared for project '%s'. A placement " + ...
        "must cite a frame that already exists; VAWLUME never creates one " + ...
        "implicitly.", key, recording.project_key);
end
system = struct( ...
    coordinate_system_id=double(rows.coordinate_system_id(1)), ...
    coordinate_system_key=key, ...
    coordinate_system_name=string(rows.coordinate_system_name(1)), ...
    dimensionality=double(rows.dimensionality(1)), ...
    unit=string(rows.unit(1)));
end

function assertDimensionality(system, declared)
if ~isnan(declared.position_z) && system.dimensionality ~= 3
    error("vawlume:geometry:DimensionalityMismatch", ...
        "Coordinate system '%s' declares %d dimensions, so a placement in it " + ...
        "carries no z coordinate. Declare a 3-dimensional frame, or omit " + ...
        "position_z.", system.coordinate_system_key, system.dimensionality);
end
end

function assertSourceProfile(conn, recording, profileVersionId)
%ASSERTSOURCEPROFILE A placement's provenance citation must be citable.
%
% Geometry reaches a placement from a recording-device or experimental-setup
% profile; those are the two kinds that carry a geometry block. Any other kind
% cited here would be provenance that does not describe geometry at all.
%
% A built-in profile carries project_id NULL and is legitimately citable from any
% project, which is the same allowance vawlume.acoustic.registerReference makes.
if isnan(profileVersionId)
    return
end
rows = fetch(conn, "SELECT cp.profile_kind, IFNULL(cp.project_id,-1) AS project_id " + ...
    "FROM config_profile_versions cpv JOIN config_profiles cp " + ...
    "ON cp.profile_id=cpv.profile_id WHERE cpv.profile_version_id=" + ...
    string(profileVersionId));
if isempty(rows) || height(rows) == 0
    error("vawlume:geometry:PlacementProfileNotFound", ...
        "No config profile version %d exists, so a placement cannot cite it " + ...
        "as the source of its coordinates.", profileVersionId);
end
kind = geometryPresentText(rows.profile_kind(1));
allowed = ["recording_device", "experimental_setup"];
if ~ismember(kind, allowed)
    error("vawlume:geometry:PlacementProfileKindInvalid", ...
        "Placement provenance cites profile version %d of kind '%s'. " + ...
        "Geometry comes from a recording_device or experimental_setup profile; " + ...
        "citing another kind would record provenance that describes no " + ...
        "geometry.", profileVersionId, kind);
end
projectId = double(rows.project_id(1));
if projectId >= 0 && projectId ~= recording.project_id
    error("vawlume:geometry:PlacementProfileScopeMismatch", ...
        "Profile version %d belongs to a different project than recording " + ...
        "%d. A placement's provenance must come from this project or from a " + ...
        "built-in profile.", profileVersionId, recording.recording_id);
end
end

function assertMatchesStored(stored, declared, system, channel)
differing = strings(0, 1);
if double(stored.coordinate_system_id) ~= system.coordinate_system_id
    differing(end + 1, 1) = "coordinate_system";
end
storedZ = double(stored.position_z);
if storedZ == 1e308
    storedZ = NaN;
end
numeric = { ...
    "position_x", double(stored.position_x), declared.position_x; ...
    "position_y", double(stored.position_y), declared.position_y; ...
    "position_z", storedZ, declared.position_z};
for index = 1:size(numeric, 1)
    if ~isequaln(numeric{index, 2}, numeric{index, 3})
        differing(end + 1, 1) = numeric{index, 1} + " (stored " + ...
            string(numeric{index, 2}) + ", supplied " + ...
            string(numeric{index, 3}) + ")"; %#ok<AGROW>
    end
end
% geometryPresentText rather than string(): the Database Toolbox can return an
% empty text column as <missing>, which would propagate silently through the
% concatenation building the diagnostic below.
text = { ...
    "placement_role", geometryPresentText(stored.placement_role), declared.placement_role; ...
    "orientation_description", geometryPresentText(stored.orientation_description), ...
        declared.orientation_description; ...
    "notes", geometryPresentText(stored.notes), declared.notes};
for index = 1:size(text, 1)
    if text{index, 2} ~= text{index, 3}
        differing(end + 1, 1) = text{index, 1}; %#ok<AGROW>
    end
end

if ~isempty(differing)
    error("vawlume:geometry:PlacementConflict", ...
        "Channel %d of this recording already has a placement with different " + ...
        "content: %s. One placement per channel is deliberate - a microphone " + ...
        "moved mid-recording needs an explicit time-bounded model, not a " + ...
        "second row.", channel.channel_index, strjoin(differing(:)', "; "));
end
end

function result = placementResult(id, channel, system, action)
result = struct( ...
    channel_placement_id=id, ...
    recording_channel_id=channel.recording_channel_id, ...
    channel_index=channel.channel_index, ...
    coordinate_system_id=system.coordinate_system_id, ...
    coordinate_system_key=system.coordinate_system_key, ...
    unit=system.unit, ...
    dimensionality=system.dimensionality, ...
    action=action);
end

function value = requiredFiniteReal(spec, name)
if ~isfield(spec, name)
    error("vawlume:geometry:PlacementInvalid", ...
        "placementSpec.%s is required.", name);
end
value = spec.(name);
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    error("vawlume:geometry:PlacementInvalid", ...
        "placementSpec.%s must be a finite scalar number.", name);
end
value = double(value);
end

function value = optionalFiniteReal(spec, name)
value = NaN;
if ~isfield(spec, name)
    return
end
candidate = spec.(name);
if isnumeric(candidate) && isscalar(candidate) && isnan(candidate)
    return
end
value = requiredFiniteReal(spec, name);
end

function value = optionalPositiveInteger(spec, name)
value = NaN;
if ~isfield(spec, name)
    return
end
candidate = spec.(name);
if isnumeric(candidate) && isscalar(candidate) && isnan(candidate)
    return
end
if ~isnumeric(candidate) || ~isscalar(candidate) || ~isfinite(candidate) || ...
        candidate <= 0 || candidate ~= floor(candidate)
    error("vawlume:geometry:PlacementInvalid", ...
        "placementSpec.%s must be a positive integer when supplied.", name);
end
value = double(candidate);
end
