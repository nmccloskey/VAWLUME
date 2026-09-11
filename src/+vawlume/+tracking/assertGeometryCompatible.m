function result = assertGeometryCompatible(conn, streamRef, recordingRef)
%ASSERTGEOMETRYCOMPATIBLE Require tracking and microphone geometry to share a frame.
%
%   result = VAWLUME.TRACKING.ASSERTGEOMETRYCOMPATIBLE(conn, streamRef, recordingRef)
%
% Confirms that a registered tracking stream and the channel placements of a
% recording cite **the same declared coordinate system**, and returns that frame
% when they do.
%
% Spatial compatibility is identity of the frame, never structural similarity.
% Two frames that both declare 2 dimensions and 'cm' may have different origins,
% different axis directions, or describe different arenas, so matching metadata
% is not licence to relate coordinates. The comparison is delegated to
% vawlume.geometry.assertCompatible so that rule keeps one implementation.
%
% **Nothing is transformed.** VAWLUME performs no rotation, translation,
% rescaling or projection between spatial frames, so an incompatible pair raises
% vawlume:geometry:CoordinateSystemMismatch rather than being reconciled. If two
% frames genuinely describe one space, the fix is upstream - produce the data in
% one frame.
%
% A recording with no placed channels raises: an empty set of frames is not
% compatibility, it is absence of evidence that any comparison is legal.
%
% This performs no distance computation and no spatial arithmetic of any kind.
% It answers only whether relating the two is declared legal.
%
% See also VAWLUME.GEOMETRY.ASSERTCOMPATIBLE, VAWLUME.TRACKING.READWINDOW

arguments
    conn
    streamRef (1,1) struct
    recordingRef (1,1) struct
end

stream = trackingResolveStream(conn, streamRef);
recording = trackingResolveRecording(conn, recordingRef);

placements = fetch(conn, "SELECT cp.coordinate_system_id, rc.channel_index " + ...
    "FROM channel_placements cp " + ...
    "JOIN recording_channels rc " + ...
    "ON rc.recording_channel_id=cp.recording_channel_id " + ...
    "WHERE rc.recording_id=" + string(recording.recording_id) + ...
    " ORDER BY rc.channel_index");

if isempty(placements) || height(placements) == 0
    error("vawlume:tracking:GeometryUnavailable", ...
        "Recording %d has no placed channels, so there is no microphone " + ...
        "geometry for tracking stream '%s' to be compatible with. Declare " + ...
        "placements before relating tracking to channels.", ...
        recording.recording_id, stream.stream_name);
end

placementSystems = double(placements.coordinate_system_id)';
system = vawlume.geometry.assertCompatible(conn, ...
    [stream.coordinate_system_id placementSystems], ...
    Context="tracking stream '" + stream.stream_name + "' versus recording " + ...
        string(recording.recording_id) + " channel geometry");

result = struct( ...
    compatible=true, ...
    coordinate_system=system, ...
    stream=struct(external_stream_id=stream.external_stream_id, ...
        stream_name=stream.stream_name), ...
    recording_id=recording.recording_id, ...
    placed_channel_indices=double(placements.channel_index)', ...
    transformed=false, ...
    note="Compatibility is frame identity. No coordinate transformation was " + ...
        "applied, and none exists in VAWLUME.");
end
