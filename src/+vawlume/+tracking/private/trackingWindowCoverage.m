function coverage = trackingWindowCoverage(conn, stream, interval, basis)
%TRACKINGWINDOWCOVERAGE Classify a requested window against declared coverage.
%
% Three states, never two. The distinction this function exists to protect:
%
%   covered     observation is established across the whole window
%   partial     observation is established across part of it
%   uncovered   nothing establishes that anyone was observing here
%
% Without it, "no rows came back" would mean both "the tracker saw nothing" and
% "nobody was looking", which are not the same finding and must not collapse.
%
% Coverage is stored in the stream's own native time units. A frame-basis request
% is converted to native time through the declared frame rate before comparison,
% because coverage is a property of the clock rather than of a request's units.

segments = fetch(conn, "SELECT segment_index, start_time_native, " + ...
    "end_time_native, observation_status FROM external_stream_coverage " + ...
    "WHERE external_stream_id=" + string(stream.external_stream_id) + ...
    " ORDER BY segment_index");

coverage = struct( ...
    status="uncovered", ...
    covered_interval=[NaN NaN], ...
    segments=trackingEmptyCoverage(), ...
    requested_native=[NaN NaN]);

requested = nativeInterval(stream, interval, basis);
coverage.requested_native = requested;

if isempty(segments) || height(segments) == 0
    % No declared coverage at all. Treating that as "covered" would convert an
    % unregistered span into an assertion that someone was watching.
    return
end

starts = double(segments.start_time_native);
ends = double(segments.end_time_native);
coverage.segments = table(double(segments.segment_index), starts, ends, ...
    trackingPresentText(segments.observation_status), ...
    VariableNames=["segment_index", "start_time_native", "end_time_native", ...
    "observation_status"]);

overlapStart = max(starts, requested(1));
overlapEnd = min(ends, requested(2));
overlapping = overlapEnd >= overlapStart;
if ~any(overlapping)
    return
end

coveredStart = min(overlapStart(overlapping));
coveredEnd = max(overlapEnd(overlapping));
coverage.covered_interval = [coveredStart coveredEnd];

% Whole-window coverage requires one segment to contain it. Stitching adjacent
% segments would assume the gap between them was observed, which is the guess
% this three-state model exists to refuse.
contained = starts <= requested(1) & ends >= requested(2);
if any(contained)
    coverage.status = "covered";
else
    coverage.status = "partial";
end
end

function value = nativeInterval(stream, interval, basis)
value = double(interval);
if basis ~= "frame"
    return
end
if isnan(stream.nominal_frame_rate_hz)
    % A frame-basis stream without a rate cannot be compared against coverage
    % stated in time. Registration requires the rate for a frame-only basis, so
    % reaching here means coverage is in frames already.
    return
end
value = value / stream.nominal_frame_rate_hz;
end
