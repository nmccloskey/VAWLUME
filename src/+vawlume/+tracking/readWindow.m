function result = readWindow(conn, streamRef, interval, options)
%READWINDOW Read a bounded window of tracking samples from the external artifact.
%
%   result = VAWLUME.TRACKING.READWINDOW(conn, streamRef, [startTime endTime])
%   result = VAWLUME.TRACKING.READWINDOW(..., Basis="frame")
%   result = VAWLUME.TRACKING.READWINDOW(..., ReferenceTimebaseKey="neural_native")
%
% Dense tracking samples live in the registered artifact, never in SQLite. This
% reads a bounded window of them into MATLAB memory and returns canonicalized
% samples, leaving the database untouched.
%
% STREAMREF selects a registered tracking stream with exactly one of:
%
%   struct(external_stream_id=4)
%   struct(project_key="p", stream_name="tracking_primary")
%
% INTERVAL is [start end] in the stream's own native units - seconds under a
% time basis, frame indices under Basis="frame".
%
% IDENTITY BOUNDARY. Samples carry `native_track_id`, the upstream trajectory
% label. That is **not** a canonical VAWLUME entity: a tracker may emit a
% stable-looking name like 'mouse_a' while still permitting identity swaps and
% ambiguous crossings, so the label names a trajectory and says nothing certain
% about which animal it follows. No entity column appears in the result, and
% nothing here resolves one. Track-to-entity association is time-varying
% evidence owned by a separate layer.
%
% POSE CONFIDENCE IS NOT IDENTITY CONFIDENCE. `pose_confidence` describes how
% well localized a keypoint is. It says nothing about which animal the
% trajectory belongs to. When the upstream tracker supplied none the column is
% all NaN and `has_pose_confidence` is false - absence is reported, never
% imputed as certainty.
%
% COVERAGE IS THREE-STATE. `result.coverage_status` is one of:
%
%   "covered"        the window lies inside declared coverage
%   "partial"        the window overlaps coverage; covered_interval names the part
%   "uncovered"      declared coverage establishes no observation here
%
% and `result.sample_status` separately distinguishes "populated" from "empty".
% A window that is covered but empty is a QC finding; a window that is uncovered
% carries no information at all. Zero rows never means "nothing happened".
%
% COMMON TIME IS OPTIONAL AND NEVER FAKED. With ReferenceTimebaseKey the reader
% asks the existing alignment layer for a stored transform and adds
% `time_reference_s`. If no usable transform exists it returns
% `reference_time_status` explaining why and leaves native times untouched; it
% never reimplements transform arithmetic or degrades to a simpler model.
% Transform fit diagnostics are returned under `transform`, separate from
% `pose_confidence`, because alignment uncertainty and localization uncertainty
% are different quantities.
%
% See also VAWLUME.TRACKING.REGISTER, VAWLUME.TRACKING.ASSERTGEOMETRYCOMPATIBLE

arguments
    conn
    streamRef (1,1) struct
    interval (1,2) double {mustBeFinite}
    options.Basis (1,1) string {mustBeMember(options.Basis, ["time", "frame"])} = "time"
    options.SourceRoot (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.ReferenceTimebaseKey (1,1) string = ""
    options.NativeTrackIds (1,:) string = string.empty
    options.BodypartLabels (1,:) string = string.empty
end

if interval(2) < interval(1)
    error("vawlume:tracking:WindowInvalid", ...
        "The requested window ends before it starts: [%g %g].", ...
        interval(1), interval(2));
end

stream = trackingResolveStream(conn, streamRef);
assertBasisSupported(stream, options.Basis);

coverage = trackingWindowCoverage(conn, stream, interval, options.Basis);
result = emptyResult(stream, interval, options.Basis, coverage);

if coverage.status == "uncovered"
    % Declared coverage establishes no observation here, so there is nothing to
    % read and nothing an absent row could mean.
    result.sample_status = "uncovered";
    return
end

[tbl, artifact] = trackingOpenArtifact(conn, stream, options.SourceRoot);
result.artifact = artifact;

columns = trackingColumnContract(conn, stream, tbl, ...
    trackingRepoRoot(options.RepoRoot));
result.column_contract = columns;

samples = trackingSelectWindow(tbl, columns, stream, interval, options.Basis, ...
    options);
result.samples = samples.rows;
result.requested_sample_count = height(samples.rows);
result.invalid_sample_count = samples.invalid_count;
result.has_pose_confidence = stream.has_confidence;

if height(samples.rows) == 0
    % Covered but empty is a QC finding, not an absence of events: something was
    % observing and produced no usable sample here.
    result.sample_status = "empty";
else
    result.sample_status = "populated";
end

if strlength(options.ReferenceTimebaseKey) > 0
    result = attachReferenceTime(conn, stream, result, options.ReferenceTimebaseKey);
end
end

function assertBasisSupported(stream, basis)
%ASSERTBASISSUPPORTED A window can only be requested on a basis the stream has.
switch basis
    case "time"
        supported = ismember(stream.native_time_basis, ["time", "both"]);
    case "frame"
        supported = ismember(stream.native_time_basis, ["frame", "both"]);
end
if ~supported
    error("vawlume:tracking:BasisUnsupported", ...
        "Stream '%s' declares native_time_basis '%s', so a '%s' window cannot " + ...
        "be requested. Converting between them here would invent a mapping the " + ...
        "registration did not record.", stream.stream_name, ...
        stream.native_time_basis, basis);
end
end

function result = attachReferenceTime(conn, stream, result, referenceKey)
%ATTACHREFERENCETIME Project native times through a STORED alignment transform.
%
% The alignment layer owns transforms. This asks it for one and reports clearly
% when none is usable, rather than reimplementing the arithmetic or silently
% degrading to a simpler model. Phase 3 robustification is not anticipated here.
result.reference_timebase_key = referenceKey;

if result.basis ~= "time"
    result.reference_time_status = "unsupported_basis";
    result.reference_time_message = "A frame-basis window has no native " + ...
        "seconds to transform. Request a time-basis window, or align the " + ...
        "frame clock explicitly.";
    return
end

runId = trackingResolveAlignmentRun(conn, stream, referenceKey);
if isnan(runId)
    result.reference_time_status = "no_transform";
    result.reference_time_message = "No fitted transform relates timebase '" + ...
        stream.timebase_name + "' to '" + referenceKey + "'. Fit one through " + ...
        "the alignment layer; this reader never estimates a transform.";
    return
end

try
    if height(result.samples) == 0
        [~, transform] = vawlume.alignment.applyTransform(conn, runId, 0);
    else
        [aligned, transform] = vawlume.alignment.applyTransform(conn, runId, ...
            result.samples.time_native_s);
        result.samples.time_reference_s = aligned(:);
    end
catch exception
    % A rejected, failed, or unfitted run raises rather than returning a
    % plausible number. That refusal is reported, not swallowed.
    result.reference_time_status = "unusable_transform";
    result.reference_time_message = string(exception.message);
    return
end

result.reference_time_status = "applied";
% Fit diagnostics are kept here, apart from pose_confidence: how well the clocks
% agree and how well a keypoint was localized are different quantities, and
% collapsing them into one confidence would destroy both.
result.transform = transform;
end

function result = emptyResult(stream, interval, basis, coverage)
result = struct();
result.stream = struct( ...
    external_stream_id=stream.external_stream_id, ...
    stream_name=stream.stream_name, ...
    recording_id=stream.recording_id, ...
    native_time_basis=stream.native_time_basis, ...
    nominal_frame_rate_hz=stream.nominal_frame_rate_hz, ...
    declared_sample_count=stream.declared_sample_count);
result.timebase = struct( ...
    timebase_id=stream.timebase_id, ...
    timebase_name=stream.timebase_name);
result.coordinate_system = struct( ...
    coordinate_system_id=stream.coordinate_system_id, ...
    coordinate_system_key=stream.coordinate_system_key, ...
    dimensionality=stream.dimensionality, ...
    unit=stream.unit);

result.basis = basis;
result.requested_interval = interval;
result.coverage_status = coverage.status;
result.covered_interval = coverage.covered_interval;
result.declared_coverage = coverage.segments;

result.samples = trackingEmptySamples();
result.sample_status = "uncovered";
result.requested_sample_count = 0;
result.invalid_sample_count = 0;
result.has_pose_confidence = false;

result.artifact = struct();
result.column_contract = struct();
result.reference_timebase_key = "";
result.reference_time_status = "not_requested";
result.reference_time_message = "";
result.transform = struct();

result.identity_boundary = "native_track_id is an upstream trajectory label, " + ...
    "not a canonical VAWLUME entity. This reader resolves no entity and " + ...
    "asserts no animal identity.";
result.dense_samples_stored = 0;
end
