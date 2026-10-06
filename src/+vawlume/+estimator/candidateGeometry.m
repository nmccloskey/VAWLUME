function result = candidateGeometry(conn, eventRef, clock, tracking, participants, channelIndices)
%CANDIDATEGEOMETRY Each participant's distance to each microphone, through identity.
%
%   result = VAWLUME.ESTIMATOR.CANDIDATEGEOMETRY(conn, eventRef, clock, tracking, ...
%       participants, channelIndices)
%
% For one vocal event, answers per participating entity: which native track
% represents it over the call, by which stored association, chosen by which rule
% step; where that track's bodypoint was at each declared instant; and how far
% that was from each requested microphone. Development plan section 11.1 step 7:
% candidate-entity-to-microphone geometry THROUGH the visual identity layer,
% never by assuming a track label is a subject.
%
% READ-ONLY. It writes nothing; the native estimator's run (itinerary 6.9) writes
% what this returns as evidence.
%
% INPUTS
%   eventRef        struct(detection_id=N) or struct(consensus_event_id=N)
%   clock           the event-clock declaration of
%                   vawlume.estimator.eventReferenceInstants
%   tracking        struct with stream (a streamRef), bodypart, max_gap_s, and
%                   exactly one of alignment_run_id or same_clock=true (or
%                   neither when the stream's clock is the reference); optional
%                   source_root, repo_root, planar_in_3d
%   participants    entity_id values: the run's participant snapshot. Never
%                   track labels
%   channelIndices  the recording channels to measure distance to
%
% ENUMERATE, NEVER MARGINALIZE (contract D9). A participant gets distances only
% when exactly one native track resolves to it with time_validity
% "whole_window", through vawlume.tracking.identityOverWindow. Otherwise it gets
% none, and one reason from the native estimator's closed set:
%
%   identity_changes_within_window  the entity is chosen by, or contradicts, a
%                                   track whose identity changes during the call
%   identity_multiple_tracks        two or more tracks resolve to this entity
%   identity_partial_window         its one track's claim covers part of the call
%   identity_unresolved             no track resolves to it, and some track's
%                                   identity is unresolved, tied or all-rejected:
%                                   it could be this entity
%   identity_no_track               no track resolves to it, and no unresolved
%                                   track could be it
%
% No identity_value is read as a weight, and nothing averages over tracks.
%
% Once a track is established, each (channel, instant) row carries its own
% state, with reason:
%   bodypart_missing     no track in the stream carries the bodypart
%   track_not_covered    the instant has no position: outside declared coverage,
%                        beyond the samples, or across a gap above max_gap_s
%                        (detail in position_reason)
%   track_covered_empty  coverage is declared but the window holds no sample
%   channel_unplaced     the channel has no declared placement
%
% FRAMES MUST BE ONE FRAME. The tracking stream's frame and every placement's
% frame go through vawlume.geometry.distance's identity rule; a mismatch raises
% vawlume:geometry:CoordinateSystemMismatch and nothing is transformed. A 'px'
% distance is returned in 'px': whether the estimator may use a unit is its
% profile's declared decision (contract D17), not this function's.
%
% Instant bases: onset, midpoint, offset (positions at those instants, observed
% or interpolated), and window_median, window_min (over observed samples inside
% the call window only).
%
% RESULT fields:
%   event                the eventReferenceInstants result (event clock evidence)
%   tracking_clock       the tracking clock declaration and read span
%   coordinate_system    the tracking frame descriptor
%   tracking_status, coverage_status, sample_status, has_pose_confidence
%   identity             the identityOverWindow result (tracks, contradictions,
%                        set_aside, rule) over the call's tracking-native window
%   tracking_window_native  that window
%   entities             one row per participant: entity_id, has_geometry,
%                        reason, native_track_id, tracking_identity_association_id,
%                        decided_by_step, time_validity
%   tracks               the reverse view, one row per track: its identity and
%                        whether its entity is a participant (a track associated
%                        with no participant is QC information)
%   geometry             one row per (participant with geometry, channel,
%                        instant basis): see GEOMETRYVARIABLENAMES below
%   placements           the recording's channel placements consulted
%
% See also VAWLUME.ESTIMATOR.EVENTREFERENCEINSTANTS,
% VAWLUME.TRACKING.POSITIONSATINSTANTS, VAWLUME.TRACKING.IDENTITYOVERWINDOW,
% VAWLUME.GEOMETRY.DISTANCE

arguments
    conn
    eventRef (1,1) struct
    clock (1,1) struct
    tracking (1,1) struct
    participants (1,:) double
    channelIndices (1,:) double
end

tracking = normalizeTracking(tracking);
if isempty(participants) || numel(unique(participants)) ~= numel(participants)
    error("vawlume:estimator:ParticipantsInvalid", ...
        "participants must be a nonempty list of distinct entity_id values.");
end
if isempty(channelIndices) || numel(unique(channelIndices)) ~= numel(channelIndices)
    error("vawlume:estimator:ChannelsInvalid", ...
        "channelIndices must be a nonempty list of distinct channel indices.");
end

instants = vawlume.estimator.eventReferenceInstants(conn, eventRef, clock);
assertParticipantsLinked(conn, instants.recording_id, participants);

positions = vawlume.tracking.positionsAtInstants(conn, tracking.stream, ...
    instants.instants.time_reference_s, ...
    ReferenceTimebaseKey=instants.reference_timebase_key, ...
    AlignmentRunId=tracking.alignment_run_id, SameClock=tracking.same_clock, ...
    Bodypart=tracking.bodypart, MaxGapS=tracking.max_gap_s, ...
    InstantLabels=instants.instants.instant_basis, ...
    CallWindow=instants.reference_interval, ...
    SourceRoot=tracking.source_root, RepoRoot=tracking.repo_root);

% Identity claims are stated on the tracking stream's own clock, so the call's
% window is expressed there through the alignment layer, never estimated.
nativeWindow = trackingNativeWindow(conn, positions.clock, instants.reference_interval);
identity = vawlume.tracking.identityOverWindow(conn, tracking.stream, nativeWindow);

placements = vawlume.geometry.readChannelPlacements(conn, ...
    struct(recording_id=instants.recording_id));

entities = participantOutcomes(identity, participants);
geometry = emptyGeometry();
for k = find(entities.has_geometry)'
    geometry = [geometry; entityGeometry(entities(k, :), positions, placements, ...
        channelIndices, instants, tracking)]; %#ok<AGROW>
end

result = struct(event=instants, tracking_clock=positions.clock, ...
    coordinate_system=positions.coordinate_system, ...
    tracking_status=positions.status, coverage_status=positions.coverage_status, ...
    sample_status=positions.sample_status, ...
    has_pose_confidence=positions.has_pose_confidence, identity=identity, ...
    tracking_window_native=nativeWindow, entities=entities, ...
    tracks=reverseView(identity, participants), geometry=geometry, ...
    placements=placements);
end

% ------------------------------------------------------------- identity ---

function entities = participantOutcomes(identity, participants)
tracks = identity.tracks;
resolved = tracks(tracks.identity_status == "resolved", :);
changing = tracks(tracks.time_validity == "changes_within_window", :);
changingEntities = [changing.entity_id; ...
    identity.contradictions.entity_id(~isnan(identity.contradictions.entity_id))];
anyUnresolved = any(ismember(tracks.identity_status, ["unresolved", "tied", "all_rejected"]));

entities = emptyEntities();
for entityId = participants
    mine = resolved(resolved.entity_id == entityId, :);
    row = struct(entity_id=entityId, has_geometry=false, reason="", ...
        native_track_id="", tracking_identity_association_id=NaN, ...
        decided_by_step="", time_validity="");
    if any(changingEntities == entityId)
        row.reason = "identity_changes_within_window";
    elseif height(mine) > 1
        row.reason = "identity_multiple_tracks";
    elseif height(mine) == 1 && mine.time_validity(1) == "partial"
        row.reason = "identity_partial_window";
    elseif height(mine) == 0 && anyUnresolved
        row.reason = "identity_unresolved";
    elseif height(mine) == 0
        row.reason = "identity_no_track";
    else
        row.has_geometry = true;
    end
    if height(mine) == 1
        row.native_track_id = mine.native_track_id(1);
        row.tracking_identity_association_id = mine.tracking_identity_association_id(1);
        row.decided_by_step = mine.decided_by_step(1);
        row.time_validity = mine.time_validity(1);
    end
    entities = [entities; struct2table(row)]; %#ok<AGROW>
end
end

function view = reverseView(identity, participants)
view = identity.tracks(:, ["native_track_id", "identity_status", "entity_id", ...
    "tracking_identity_association_id", "time_validity", "contradiction_count"]);
view.entity_is_participant = ismember(view.entity_id, participants);
end

% ------------------------------------------------------------- geometry ---

function rows = entityGeometry(entity, positions, placements, channelIndices, instants, tracking)
rows = emptyGeometry();
track = entity.native_track_id;
frame = positions.coordinate_system;
mine = positions.positions(positions.positions.native_track_id == track, :);
window = positions.window_samples(positions.window_samples.native_track_id == track, :);
eventExtrapolated = instants.instants.extrapolated;

for channel = channelIndices
    placement = placements(placements.channel_index == channel, :);
    base = struct(entity_id=entity.entity_id, native_track_id=track, ...
        tracking_identity_association_id=entity.tracking_identity_association_id, ...
        decided_by_step=entity.decided_by_step, time_validity=entity.time_validity, ...
        channel_index=channel, recording_channel_id=NaN, instant_basis="", ...
        distance=NaN, unit=string(frame.unit), distance_basis="", ...
        status="not_computed", reason="", position_basis="", position_reason="", ...
        coverage_state="", n_samples=NaN, pose_confidence_before=NaN, ...
        pose_confidence_after=NaN, pose_confidence_min_bracket=NaN, ...
        event_extrapolated=false, bracket_extrapolated=false, ...
        clock_uncertainty_s=NaN, clock_uncertainty_semantics="");
    if height(placement) == 1
        base.recording_channel_id = placement.recording_channel_id(1);
        micFrame = struct(coordinate_system_id=placement.coordinate_system_id(1), ...
            dimensionality=placement.dimensionality(1), unit=placement.unit(1));
        mic = [placement.position_x(1), placement.position_y(1), placement.position_z(1)];
    end

    for k = 1:height(instants.instants)
        row = base;
        row.instant_basis = instants.instants.instant_basis(k);
        row.event_extrapolated = eventExtrapolated(k);
        position = mine(mine.instant_label == row.instant_basis, :);
        if positions.status == "bodypart_missing"
            row.reason = "bodypart_missing";
        elseif height(placement) == 0
            row.reason = "channel_unplaced";
        elseif height(position) == 1
            row.position_basis = position.basis(1);
            row.position_reason = position.reason(1);
            row.coverage_state = position.coverage_state(1);
            row.pose_confidence_before = position.pose_confidence_before(1);
            row.pose_confidence_after = position.pose_confidence_after(1);
            row.pose_confidence_min_bracket = position.pose_confidence_min_bracket(1);
            row.bracket_extrapolated = position.bracket_extrapolated(1);
            row.clock_uncertainty_s = position.clock_uncertainty_s(1);
            row.clock_uncertainty_semantics = position.clock_uncertainty_semantics(1);
            if position.basis(1) == "not_covered"
                row.reason = notCoveredReason(positions, position);
            else
                d = vawlume.geometry.distance([position.x(1) position.y(1) position.z(1)], ...
                    frame, mic, micFrame, PlanarIn3D=tracking.planar_in_3d);
                row.distance = d.distance;
                row.distance_basis = d.basis;
                row.status = d.status;
                row.reason = d.reason;
            end
        else
            row.reason = notCoveredReason(positions, []);
        end
        rows = [rows; struct2table(row)]; %#ok<AGROW>
    end

    for summaryBasis = ["window_median", "window_min"]
        row = base;
        row.instant_basis = summaryBasis;
        row.position_basis = "observed_samples";
        row.event_extrapolated = any(eventExtrapolated);
        if positions.status == "bodypart_missing"
            row.reason = "bodypart_missing";
        elseif height(placement) == 0
            row.reason = "channel_unplaced";
        else
            perSample = vawlume.geometry.distance([window.x window.y window.z], ...
                frame, mic, micFrame, PlanarIn3D=tracking.planar_in_3d);
            if height(window) == 0
                perSample.distance = zeros(0, 1);
            end
            summary = vawlume.geometry.summarizeDistances(perSample.distance, ...
                repmat("observed", height(window), 1));
            row.n_samples = summary.n_computed;
            row.bracket_extrapolated = any(window.extrapolated);
            if summary.status == "computed"
                row.distance = summary.(summaryBasis);
                row.distance_basis = perSample.basis;
                row.status = "computed";
            else
                row.reason = notCoveredReason(positions, []);
                row.position_reason = summary.reason;
            end
        end
        rows = [rows; struct2table(row)]; %#ok<AGROW>
    end
end
end

function reason = notCoveredReason(positions, position)
if positions.sample_status == "empty" && ...
        (isempty(position) || position.coverage_state(1) == "covered")
    reason = "track_covered_empty";
else
    reason = "track_not_covered";
end
end

% --------------------------------------------------------------- helpers ---

function window = trackingNativeWindow(conn, trackingClock, referenceInterval)
if trackingClock.relation == "alignment_run"
    window = vawlume.alignment.applyInverseTransform(conn, ...
        trackingClock.alignment_run_id, referenceInterval(:))';
else
    window = referenceInterval;
end
end

function tracking = normalizeTracking(tracking)
for name = ["stream", "bodypart", "max_gap_s"]
    if ~isfield(tracking, name)
        error("vawlume:estimator:TrackingSpecInvalid", "tracking.%s is required.", name);
    end
end
defaults = struct(alignment_run_id=NaN, same_clock=false, source_root="", ...
    repo_root="", planar_in_3d=false);
for name = string(fieldnames(defaults))'
    if ~isfield(tracking, name)
        tracking.(name) = defaults.(name);
    end
end
tracking.bodypart = string(tracking.bodypart);
tracking.source_root = string(tracking.source_root);
tracking.repo_root = string(tracking.repo_root);
end

function assertParticipantsLinked(conn, recordingId, participants)
% A participant is an entity linked to the recording, as attribution's
% participant snapshot requires. Nothing here creates or infers one.
rows = fetch(conn, "SELECT entity_id FROM recording_entity_links WHERE " + ...
    "recording_id=" + string(recordingId));
linked = [];
if ~isempty(rows) && height(rows) > 0
    linked = double(rows.entity_id);
end
missing = participants(~ismember(participants, linked));
if ~isempty(missing)
    error("vawlume:estimator:ParticipantNotLinked", ...
        "Entity %d is not linked to recording %d, so it is not a participant.", ...
        missing(1), recordingId);
end
end

function value = emptyEntities()
value = table(Size=[0 7], VariableTypes=["double", "logical", "string", "string", ...
    "double", "string", "string"], VariableNames=["entity_id", "has_geometry", ...
    "reason", "native_track_id", "tracking_identity_association_id", ...
    "decided_by_step", "time_validity"]);
end

function value = emptyGeometry()
names = ["entity_id", "native_track_id", "tracking_identity_association_id", ...
    "decided_by_step", "time_validity", "channel_index", "recording_channel_id", ...
    "instant_basis", "distance", "unit", "distance_basis", "status", "reason", ...
    "position_basis", "position_reason", "coverage_state", "n_samples", ...
    "pose_confidence_before", "pose_confidence_after", ...
    "pose_confidence_min_bracket", "event_extrapolated", "bracket_extrapolated", ...
    "clock_uncertainty_s", "clock_uncertainty_semantics"];
types = ["double", "string", "double", "string", "string", "double", "double", ...
    "string", "double", "string", "string", "string", "string", "string", ...
    "string", "string", "double", "double", "double", "double", "logical", ...
    "logical", "double", "string"];
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end
