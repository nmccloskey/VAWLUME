function result = positionsAtInstants(conn, streamRef, referenceTimes, options)
%POSITIONSATINSTANTS Where each native track's bodypoint was at reference-clock instants.
%
%   result = VAWLUME.TRACKING.POSITIONSATINSTANTS(conn, streamRef, referenceTimes, ...
%       ReferenceTimebaseKey="neural", AlignmentRunId=9, Bodypart="snout", ...
%       MaxGapS=0.1)
%
% For every native track that carries BODYPART, returns its position at each of
% REFERENCETIMES (seconds on the reference clock), with the basis and coverage
% that say how much each position can be trusted, and optionally the samples it
% actually observed inside a CallWindow.
%
% READ-ONLY. Dense samples are read window-wise from the registered artifact
% through vawlume.tracking.readWindow and never written anywhere.
%
% THE CLOCK IS DECLARED, NEVER DISCOVERED. Exactly one of:
%
%   AlignmentRunId=N   stored run N must transform this stream's timebase to
%                      ReferenceTimebaseKey. It is validated, not looked up.
%   SameClock=true     an explicit declaration that the stream's clock is the
%                      reference clock. Nothing verifies it.
%   neither            allowed only when the stream's own timebase IS
%                      ReferenceTimebaseKey.
%
% readWindow's own ReferenceTimebaseKey option is deliberately not used: it
% selects the newest qualifying run itself, a query whose answer can change when
% a run is added. A caller that must cite the transform it used names it.
%
% Every clock conversion goes through the alignment layer: the reference read
% span is mapped to the stream's native clock by
% vawlume.alignment.applyInverseTransform, and samples are mapped to the
% reference clock by vawlume.alignment.applyTransform. This function does no
% transform arithmetic.
%
% POSITIONS come from vawlume.geometry.positionAtInstants, under its policy:
% observed, interpolated within MaxGapS, or not_covered with a reason, never
% extrapolated. MaxGapS has no default. Samples are read over the instants' span
% padded by MaxGapS on each side, so the samples that bracket the first and last
% instants are seen.
%
% STATES THAT STAY DISTINCT:
%   result.status            "read", or "bodypart_missing" when no track in the
%                            stream carries BODYPART (no other bodypart is
%                            substituted), or "uncovered" when declared coverage
%                            establishes no observation over the read span
%   result.coverage_status   readWindow's covered / partial / uncovered
%   result.sample_status     readWindow's populated / empty / uncovered.
%                            "empty" under coverage is a QC finding, not absence
%   positions.coverage_state per instant: whether the instant's native time lies
%                            inside declared coverage
%   positions.basis/reason   per instant, from positionAtInstants
%   has_pose_confidence      false when the tracker supplied none; values NaN
%
% IDENTITY BOUNDARY. Rows carry native_track_id, an upstream trajectory label.
% There is no entity column, and nothing here resolves one. Which entity a track
% represents is time-varying evidence owned by
% vawlume.tracking.identityCandidates and resolveIdentity.
%
% UNCERTAINTIES STAY SEPARATE. pose_confidence (where a keypoint was) and the
% clock bound clock_uncertainty_s (how well two clocks agree) are separate
% columns and are never combined.
%
% Name-value arguments:
%   ReferenceTimebaseKey  required
%   Bodypart              required, the native bodypart label
%   MaxGapS               required, reference-clock seconds
%   AlignmentRunId        see above (default NaN)
%   SameClock             see above (default false)
%   InstantLabels         one label per instant, e.g. "onset" (default "")
%   CallWindow            [start end) on the reference clock; returns the samples
%                         observed inside it as result.window_samples
%   SourceRoot, RepoRoot  passed to readWindow
%
% RESULT fields:
%   status, stream, coordinate_system (a frame descriptor), bodypart,
%   tracks, clock, coverage_status, covered_interval, sample_status,
%   has_pose_confidence, artifact, positions, window_samples, identity_boundary
%
% See also VAWLUME.TRACKING.READWINDOW, VAWLUME.GEOMETRY.POSITIONATINSTANTS,
% VAWLUME.ALIGNMENT.APPLYINVERSETRANSFORM

arguments
    conn
    streamRef (1,1) struct
    referenceTimes double
    options.ReferenceTimebaseKey (1,1) string = ""
    options.Bodypart (1,1) string = ""
    options.MaxGapS (1,1) double = NaN
    options.AlignmentRunId (1,1) double = NaN
    options.SameClock (1,1) logical = false
    options.InstantLabels string = strings(0, 1)
    options.CallWindow (1,2) double = [NaN NaN]
    options.SourceRoot (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

referenceTimes = referenceTimes(:);
validateOptions(referenceTimes, options);
labels = options.InstantLabels(:);
if isempty(labels)
    labels = repmat("", numel(referenceTimes), 1);
end

stream = trackingResolveStream(conn, streamRef);
clock = resolveClock(conn, stream, options);
frame = struct(coordinate_system_id=stream.coordinate_system_id, ...
    coordinate_system_key=stream.coordinate_system_key, ...
    dimensionality=stream.dimensionality, unit=stream.unit);

result = struct(status="read", ...
    stream=struct(external_stream_id=stream.external_stream_id, ...
        stream_name=stream.stream_name, timebase_name=stream.timebase_name), ...
    coordinate_system=frame, bodypart=options.Bodypart, tracks=strings(0, 1), ...
    clock=clock, coverage_status="", covered_interval=[NaN NaN], ...
    sample_status="", has_pose_confidence=false, artifact=struct(), ...
    positions=emptyPositions(), window_samples=emptyWindowSamples(), ...
    identity_boundary="native_track_id is an upstream trajectory label, not a " + ...
    "canonical VAWLUME entity. No entity is resolved here.");

tracks = tracksWithBodypart(conn, stream.external_stream_id, options.Bodypart);
result.tracks = tracks;
if isempty(tracks)
    result.status = "bodypart_missing";
    return
end

% The reference span to read, padded so the samples bracketing the outer
% instants are included, then expressed on the stream's own clock.
span = [referenceTimes; options.CallWindow(~isnan(options.CallWindow))'];
referenceSpan = [min(span) - options.MaxGapS; max(span) + options.MaxGapS];
[nativeSpan, ~] = toNative(conn, clock, referenceSpan);
[instantNative, instantTransform] = toNative(conn, clock, referenceTimes);
result.clock.native_read_interval = nativeSpan(:)';

window = vawlume.tracking.readWindow(conn, streamRef, nativeSpan(:)', ...
    Basis="time", BodypartLabels=options.Bodypart, ...
    NativeTrackIds=tracks', SourceRoot=options.SourceRoot, RepoRoot=options.RepoRoot);
result.coverage_status = window.coverage_status;
result.covered_interval = window.covered_interval;
result.sample_status = window.sample_status;
result.has_pose_confidence = window.has_pose_confidence;
result.artifact = window.artifact;
if window.coverage_status == "uncovered"
    result.status = "uncovered";
end

samples = window.samples;
[samples.time_reference_s, sampleExtrapolated] = toReference(conn, clock, ...
    samples.time_native_s);
instantCovered = insideCoverage(instantNative, window.declared_coverage);

positions = emptyPositions();
for track = tracks'
    rows = samples(samples.native_track_id == track, :);
    rowsExtrapolated = sampleExtrapolated(samples.native_track_id == track);
    xyz = [rows.position_x, rows.position_y, rows.position_z];
    confidence = NaN(height(rows), 1);
    if window.has_pose_confidence
        confidence = rows.pose_confidence;
    end
    at = vawlume.geometry.positionAtInstants(rows.time_reference_s, xyz, ...
        referenceTimes, MaxGapS=options.MaxGapS, PoseConfidence=confidence);
    bracketExtrapolated = false(height(at), 1);
    for k = 1:height(at)
        used = rows.time_reference_s == at.bracket_before_time(k) | ...
            rows.time_reference_s == at.bracket_after_time(k);
        bracketExtrapolated(k) = any(rowsExtrapolated(used));
    end
    coverageState = repmat("uncovered", height(at), 1);
    coverageState(instantCovered) = "covered";
    block = [table(repmat(track, height(at), 1), labels, ...
        VariableNames=["native_track_id", "instant_label"]), at, ...
        table(coverageState, instantNative(:), bracketExtrapolated, ...
        instantTransform.uncertainty_s(:), instantTransform.uncertainty_semantics(:), ...
        VariableNames=["coverage_state", "query_time_native_s", ...
        "bracket_extrapolated", "clock_uncertainty_s", ...
        "clock_uncertainty_semantics"])];
    positions = [positions; block]; %#ok<AGROW>

    if all(~isnan(options.CallWindow))
        inside = rows.time_reference_s >= options.CallWindow(1) & ...
            rows.time_reference_s < options.CallWindow(2) & ...
            ~isnan(rows.position_x) & ~isnan(rows.position_y);
        result.window_samples = [result.window_samples; table( ...
            rows.native_track_id(inside), rows.time_reference_s(inside), ...
            rows.position_x(inside), rows.position_y(inside), rows.position_z(inside), ...
            confidence(inside), rowsExtrapolated(inside), ...
            VariableNames=emptyWindowSamples().Properties.VariableNames)];
    end
end
result.positions = positions;
end

% ---------------------------------------------------------------- clock ---

function clock = resolveClock(conn, stream, options)
clock = struct(relation="", alignment_run_id=NaN, ...
    reference_timebase_key=options.ReferenceTimebaseKey, ...
    stream_timebase_key=stream.timebase_name, native_read_interval=[NaN NaN]);
hasRun = ~isnan(options.AlignmentRunId);
if options.SameClock && hasRun
    error("vawlume:tracking:ClockDeclarationInvalid", ...
        "Declare SameClock or AlignmentRunId, not both.");
end
if options.SameClock
    clock.relation = "same_clock";
    return
end
if stream.timebase_name == options.ReferenceTimebaseKey
    if hasRun
        error("vawlume:tracking:ClockDeclarationInvalid", ...
            "The stream's own clock '%s' is the reference, so no transform " + ...
            "applies; alignment run %d was supplied anyway.", ...
            stream.timebase_name, options.AlignmentRunId);
    end
    clock.relation = "stream_is_reference";
    return
end
if ~hasRun
    error("vawlume:tracking:ClockDeclarationInvalid", ...
        "Stream clock '%s' is not the reference '%s'. Name the stored " + ...
        "alignment run that relates them (AlignmentRunId), or declare " + ...
        "SameClock=true. No run is looked up.", stream.timebase_name, ...
        options.ReferenceTimebaseKey);
end
rows = fetch(conn, "SELECT r.source_timebase_id, ref.timebase_name AS reference_key " + ...
    "FROM time_alignment_runs r JOIN timebases ref ON " + ...
    "ref.timebase_id=r.target_timebase_id WHERE r.alignment_run_id=" + ...
    string(options.AlignmentRunId));
if isempty(rows) || height(rows) == 0 || ...
        double(rows.source_timebase_id(1)) ~= stream.timebase_id || ...
        trackingPresentText(rows.reference_key(1)) ~= options.ReferenceTimebaseKey
    error("vawlume:tracking:ClockDeclarationInvalid", ...
        "Alignment run %d does not transform stream clock '%s' to '%s'.", ...
        options.AlignmentRunId, stream.timebase_name, options.ReferenceTimebaseKey);
end
clock.relation = "alignment_run";
clock.alignment_run_id = options.AlignmentRunId;
end

function [native, transform] = toNative(conn, clock, referenceTimes)
if clock.relation == "alignment_run"
    [native, transform] = vawlume.alignment.applyInverseTransform(conn, ...
        clock.alignment_run_id, referenceTimes);
else
    native = referenceTimes;
    transform = struct(uncertainty_s=NaN(size(referenceTimes)), ...
        uncertainty_semantics=repmat("", size(referenceTimes)));
end
end

function [reference, extrapolated] = toReference(conn, clock, nativeTimes)
extrapolated = false(size(nativeTimes));
if clock.relation == "alignment_run" && ~isempty(nativeTimes)
    [reference, transform] = vawlume.alignment.applyTransform(conn, ...
        clock.alignment_run_id, nativeTimes);
    extrapolated = logical(transform.extrapolated);
else
    reference = nativeTimes;
end
end

% -------------------------------------------------------------- helpers ---

function validateOptions(referenceTimes, options)
if strlength(options.ReferenceTimebaseKey) == 0
    error("vawlume:tracking:ClockDeclarationInvalid", ...
        "ReferenceTimebaseKey is required: the clock the instants are on.");
end
if strlength(options.Bodypart) == 0
    error("vawlume:tracking:BodypartRequired", ...
        "Bodypart is required. No bodypart is chosen by default.");
end
if ~isfinite(options.MaxGapS) || options.MaxGapS < 0
    error("vawlume:geometry:MaxGapRequired", ...
        "MaxGapS is required, finite and nonnegative.");
end
if isempty(referenceTimes) || any(~isfinite(referenceTimes))
    error("vawlume:tracking:InstantsInvalid", ...
        "At least one finite reference-clock instant is required.");
end
if ~isempty(options.InstantLabels) && numel(options.InstantLabels) ~= numel(referenceTimes)
    error("vawlume:tracking:InstantsInvalid", ...
        "InstantLabels needs one label per instant.");
end
window = options.CallWindow;
if xor(isnan(window(1)), isnan(window(2))) || (all(~isnan(window)) && window(2) < window(1))
    error("vawlume:tracking:WindowInvalid", ...
        "CallWindow is [start end] on the reference clock, both or neither.");
end
end

function tracks = tracksWithBodypart(conn, streamId, bodypart)
rows = fetch(conn, "SELECT DISTINCT native_track_id FROM tracking_series " + ...
    "WHERE external_stream_id=" + string(streamId) + ...
    " AND native_bodypart_label=" + trackingSqlText(bodypart) + ...
    " ORDER BY native_track_id");
tracks = strings(0, 1);
if ~isempty(rows) && height(rows) > 0
    tracks = trackingPresentText(rows.native_track_id(:));
end
end

function covered = insideCoverage(nativeTimes, segments)
covered = false(numel(nativeTimes), 1);
for k = 1:height(segments)
    covered = covered | (nativeTimes(:) >= segments.start_time_native(k) & ...
        nativeTimes(:) <= segments.end_time_native(k));
end
end

function value = emptyPositions()
names = ["native_track_id", "instant_label", "query_time", "x", "y", "z", ...
    "basis", "reason", "bracket_before_time", "bracket_after_time", "gap_s", ...
    "pose_confidence_before", "pose_confidence_after", ...
    "pose_confidence_min_bracket", "coverage_state", "query_time_native_s", ...
    "bracket_extrapolated", "clock_uncertainty_s", "clock_uncertainty_semantics"];
types = ["string", "string", repmat("double", 1, 4), "string", "string", ...
    repmat("double", 1, 6), "string", "double", "logical", "double", "string"];
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end

function value = emptyWindowSamples()
names = ["native_track_id", "time_reference_s", "x", "y", "z", ...
    "pose_confidence", "extrapolated"];
types = ["string", repmat("double", 1, 5), "logical"];
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end
