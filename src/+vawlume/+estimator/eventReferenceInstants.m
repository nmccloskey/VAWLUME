function result = eventReferenceInstants(conn, eventRef, clock)
%EVENTREFERENCEINSTANTS The instants of one vocal event, placed on a reference clock.
%
%   result = VAWLUME.ESTIMATOR.EVENTREFERENCEINSTANTS(conn, eventRef, clock)
%
% EVENTREF names one event, with exactly one of:
%
%   struct(detection_id=12)
%   struct(consensus_event_id=4)
%
% An agreement group is refused (vawlume:estimator:EventSetUnsupported): it has
% no intrinsic interval, and the native estimator's v1 targets the two event
% sets that do (docs/design/06_native_estimator_contract.md D6).
%
% CLOCK declares how the event's clock relates to the reference clock the
% tracking samples will be placed on, with clock_relation one of:
%
%   struct(clock_relation="alignment_run", reference_timebase_key="neural",
%          audio_alignment_run_id=7)
%       The event's recording-native timebase is placed on the reference through
%       stored alignment run 7, which must transform exactly that timebase to
%       exactly that reference. When the recording-native timebase IS the
%       reference, omit audio_alignment_run_id (or pass NaN): no transform
%       applies, and supplying one is refused as a contradiction.
%
%   struct(clock_relation="same_clock")
%       An explicit declaration that the audio clock and the tracking clock are
%       one clock. Nothing verifies it. The result says it was declared.
%
% Nothing is inferred: no alignment run is looked up, and no timebase is chosen
% by its name's spelling. Which clock is the recording's own is read from the
% stored timebases row marked is_recording_native.
%
% RESULT fields:
%   event_kind, event_id, recording_id
%   native_interval               [start end] on the recording-native clock
%   recording_timebase_key, reference_timebase_key, clock_relation
%   instants                      table: instant_basis ("onset", "midpoint",
%                                 "offset"), time_native_s, time_reference_s,
%                                 segment_index, extrapolated,
%                                 uncertainty_s, uncertainty_semantics
%   reference_interval            [onset offset] on the reference clock
%   alignment_run_id              NaN when no transform applied
%   duration_change_s             aligned minus native duration (NaN if none applied)
%   crosses_breakpoint            whether the interval spans a transform breakpoint
%   uncertainty_note              the alignment layer's statement of what the
%                                 bound is and is not
%
% The midpoint is the midpoint of the NATIVE interval, placed on the reference
% clock through the transform like the other two instants. It is not the average
% of the transformed endpoints, which under a piecewise transform is a different
% instant.
%
% Every time placed on the reference clock went through
% vawlume.alignment.applyTransform or applyTransformInterval. This function
% performs no transform arithmetic of its own.
%
% See also VAWLUME.TRACKING.POSITIONSATINSTANTS, VAWLUME.ALIGNMENT.APPLYTRANSFORM

arguments
    conn
    eventRef (1,1) struct
    clock (1,1) struct
end

event = resolveEvent(conn, eventRef);
recordingClock = recordingNativeTimebase(conn, event.recording_id);
relation = requiredText(clock, "clock_relation");

nativeTimes = [event.start_time_s; (event.start_time_s + event.end_time_s) / 2; ...
    event.end_time_s];
basisLabels = ["onset"; "midpoint"; "offset"];
result = struct(event_kind=event.kind, event_id=event.id, ...
    recording_id=event.recording_id, ...
    native_interval=[event.start_time_s event.end_time_s], ...
    recording_timebase_key=recordingClock.timebase_name, ...
    reference_timebase_key="", clock_relation=relation, instants=table(), ...
    reference_interval=[NaN NaN], alignment_run_id=NaN, ...
    duration_change_s=NaN, crosses_breakpoint=false, uncertainty_note="");

switch relation
    case "same_clock"
        result.reference_timebase_key = recordingClock.timebase_name;
        result.instants = instantTable(basisLabels, nativeTimes, nativeTimes, ...
            NaN(3, 1), false(3, 1), NaN(3, 1), repmat("", 3, 1));
        result.reference_interval = result.native_interval;
        result.uncertainty_note = "same_clock was declared by the caller; no " + ...
            "transform applied and nothing verified that the clocks agree.";
    case "alignment_run"
        referenceKey = requiredText(clock, "reference_timebase_key");
        result.reference_timebase_key = referenceKey;
        runId = NaN;
        if isfield(clock, "audio_alignment_run_id")
            runId = double(clock.audio_alignment_run_id);
        end
        if referenceKey == recordingClock.timebase_name
            if ~isnan(runId)
                error("vawlume:estimator:ClockDeclarationInvalid", ...
                    "The reference timebase '%s' is this recording's own clock, " + ...
                    "so no transform applies; alignment run %d was supplied " + ...
                    "anyway. Omit it.", referenceKey, runId);
            end
            result.instants = instantTable(basisLabels, nativeTimes, nativeTimes, ...
                NaN(3, 1), false(3, 1), NaN(3, 1), repmat("", 3, 1));
            result.reference_interval = result.native_interval;
            result.uncertainty_note = "The reference clock is the recording's " + ...
                "own clock; no transform applied.";
        else
            if isnan(runId)
                error("vawlume:estimator:ClockDeclarationInvalid", ...
                    "The recording's clock '%s' is not the reference '%s', so " + ...
                    "audio_alignment_run_id is required. It is never looked up.", ...
                    recordingClock.timebase_name, referenceKey);
            end
            assertRunRelates(conn, runId, recordingClock.timebase_id, referenceKey);
            [aligned, transform] = vawlume.alignment.applyTransform(conn, runId, ...
                nativeTimes);
            intervals = vawlume.alignment.applyTransformInterval(conn, runId, ...
                event.start_time_s, event.end_time_s);
            result.instants = instantTable(basisLabels, nativeTimes, aligned(:), ...
                double(transform.segment_index(:)), logical(transform.extrapolated(:)), ...
                double(transform.uncertainty_s(:)), string(transform.uncertainty_semantics(:)));
            result.reference_interval = [intervals.start_aligned intervals.end_aligned];
            result.alignment_run_id = runId;
            result.duration_change_s = intervals.duration_change_s;
            result.crosses_breakpoint = intervals.crosses_breakpoint;
            result.uncertainty_note = transform.uncertainty_note;
        end
    otherwise
        error("vawlume:estimator:ClockDeclarationInvalid", ...
            "clock_relation must be ""alignment_run"" or ""same_clock"", not ""%s"".", ...
            relation);
end
end

function event = resolveEvent(conn, eventRef)
names = string(fieldnames(eventRef));
if any(names == "agreement_group_id")
    error("vawlume:estimator:EventSetUnsupported", ...
        "Agreement-group targets are not supported by the native estimator v1: " + ...
        "a group has no intrinsic interval, and derived measurements cannot " + ...
        "target one (native estimator contract D6).");
end
known = intersect(names, ["detection_id", "consensus_event_id"]);
if numel(known) ~= 1 || numel(names) ~= 1
    error("vawlume:estimator:EventRefInvalid", ...
        "eventRef must contain exactly one of detection_id or consensus_event_id.");
end
kind = known(1);
id = double(eventRef.(kind));
tableName = "detections";
if kind == "consensus_event_id"
    tableName = "consensus_events";
end
rows = fetch(conn, "SELECT recording_id, start_time_s, end_time_s FROM " + ...
    tableName + " WHERE " + kind + "=" + string(id));
if isempty(rows) || height(rows) == 0
    error("vawlume:estimator:EventNotFound", "No %s has %s %d.", ...
        tableName, kind, id);
end
event = struct(kind=kind, id=id, recording_id=double(rows.recording_id(1)), ...
    start_time_s=double(rows.start_time_s(1)), end_time_s=double(rows.end_time_s(1)));
end

function value = recordingNativeTimebase(conn, recordingId)
rows = fetch(conn, "SELECT timebase_id, timebase_name FROM timebases WHERE " + ...
    "recording_id=" + string(recordingId) + " AND is_recording_native=1");
if isempty(rows) || height(rows) == 0
    error("vawlume:estimator:RecordingClockUndeclared", ...
        "Recording %d has no timebase marked is_recording_native, so its " + ...
        "events have no declared clock to place on a reference.", recordingId);
end
if height(rows) > 1
    error("vawlume:estimator:RecordingClockAmbiguous", ...
        "Recording %d has %d timebases marked is_recording_native.", ...
        recordingId, height(rows));
end
value = struct(timebase_id=double(rows.timebase_id(1)), ...
    timebase_name=presentText(rows.timebase_name(1)));
end

function assertRunRelates(conn, runId, sourceTimebaseId, referenceKey)
rows = fetch(conn, "SELECT r.source_timebase_id, ref.timebase_name AS reference_key " + ...
    "FROM time_alignment_runs r JOIN timebases ref ON " + ...
    "ref.timebase_id=r.target_timebase_id WHERE r.alignment_run_id=" + string(runId));
if isempty(rows) || height(rows) == 0
    error("vawlume:estimator:ClockDeclarationInvalid", ...
        "Alignment run %d does not exist.", runId);
end
if double(rows.source_timebase_id(1)) ~= sourceTimebaseId || ...
        presentText(rows.reference_key(1)) ~= referenceKey
    error("vawlume:estimator:ClockDeclarationInvalid", ...
        "Alignment run %d does not transform this recording's clock to '%s'.", ...
        runId, referenceKey);
end
end

function value = instantTable(labels, nativeTimes, referenceTimes, segmentIndex, ...
        extrapolated, uncertainty, semantics)
value = table(labels, nativeTimes, referenceTimes, segmentIndex, extrapolated, ...
    uncertainty, semantics, VariableNames=["instant_basis", "time_native_s", ...
    "time_reference_s", "segment_index", "extrapolated", "uncertainty_s", ...
    "uncertainty_semantics"]);
end

function value = requiredText(source, name)
if ~isfield(source, name) || strlength(string(source.(name))) == 0
    error("vawlume:estimator:ClockDeclarationInvalid", "clock.%s is required.", name);
end
value = string(source.(name));
end

function value = presentText(value)
value = string(value);
value(ismissing(value)) = "";
end
