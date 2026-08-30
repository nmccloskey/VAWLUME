function [detections, counts] = extractorApplyEvents(conn, scope, detections, counts)
%EXTRACTORAPPLYEVENTS Insert the detection and measurement rows of one plan.
%
% This helper only inserts. It never opens, commits, or rolls back a
% transaction: the caller owns the transaction so that a later failure rolls back
% the whole scientific graph rather than leaving a partial event population.
%
% SCOPE.source_artifact_id must already be resolved. Detection identity is
% UNIQUE(extraction_run_id, recording_id, source_artifact_id, native_event_id),
% and SQLite treats NULLs as distinct, so a NULL artifact id there would silently
% let every rerun insert a second copy of the whole population.
%
% Every extractor populates detections and measurements the same way, which is
% why this is shared. Evidence only some extractors produce - review state, class
% assignments - is written by the extractor-specific apply after this returns.

arguments
    conn
    scope (1,1) struct
    detections (:, 1) cell
    counts (1,1) struct
end

if isnan(scope.source_artifact_id)
    error("vawlume:ingest:ExtractorArtifactUnresolved", ...
        "The event export artifact was not resolved before the event population.");
end

for index = 1:numel(detections)
    detection = detections{index};
    detection.source_artifact_id = scope.source_artifact_id;
    if detection.action == "create"
        detection.detection_id = insertIntakeRow(conn, "detections", struct( ...
            extraction_run_id=scope.extraction_run_id, ...
            recording_id=scope.recording_id, ...
            source_artifact_id=detection.source_artifact_id, ...
            native_event_id=detection.native_event_id, ...
            event_subtype=scope.event_subtype, ...
            start_time_s=detection.start_time_s, ...
            end_time_s=detection.end_time_s, ...
            timing_basis=scope.timing_basis, ...
            detection_score=optionalReal(detection.detection_score), ...
            notes="source_row=" + string(detection.source_row)), "detection_id");
        counts.detections = counts.detections + 1;
    else
        counts.reused_detections = counts.reused_detections + 1;
    end

    counts = applyMeasurements(conn, detection, counts);
    detections{index} = detection;
end
end

function counts = applyMeasurements(conn, detection, counts)
for index = 1:height(detection.measurements)
    if string(detection.measurements.action(index)) ~= "create"
        counts.reused_event_measurements = counts.reused_event_measurements + 1;
        continue
    end
    measurement = table2struct(detection.measurements(index, :));
    insertIntakeRow(conn, "event_measurements", measurementValues(detection, measurement));
    counts.event_measurements = counts.event_measurements + 1;
end
end

function values = measurementValues(detection, measurement)
values = struct( ...
    detection_id=detection.detection_id, ...
    extractor_feature_id=measurement.extractor_feature_id, ...
    source_artifact_id=detection.source_artifact_id, ...
    native_value_type=measurement.native_value_type, ...
    native_raw_token=measurement.native_raw_token, ...
    native_unit=measurement.native_unit, ...
    canonical_unit=measurement.canonical_unit, ...
    transform_key=measurement.transform_key, ...
    operational_variant=measurement.operational_variant, ...
    source_locator=measurement.source_locator);

if measurement.canonical_feature_id >= 0
    values.canonical_feature_id = measurement.canonical_feature_id;
end

% The schema requires exactly one typed native payload, or none at all when the
% value is explicitly missing. A missing measurement keeps its raw token - a
% MUPET terminal inter-syllable interval keeps its exported "NA" - and never
% becomes a fabricated zero.
switch string(measurement.native_value_type)
    case "real"
        values.native_value_real = measurement.native_value_real;
    case "integer"
        values.native_value_integer = measurement.native_value_integer;
    case "text"
        values.native_value_text = measurement.native_value_text;
end

if ~isnan(measurement.canonical_value_real)
    values.canonical_value_real = measurement.canonical_value_real;
elseif ~isnan(measurement.canonical_value_integer)
    values.canonical_value_integer = measurement.canonical_value_integer;
elseif strlength(string(measurement.canonical_value_text)) > 0
    values.canonical_value_text = measurement.canonical_value_text;
end
end

function value = optionalReal(candidate)
value = "";
if ~isnan(candidate)
    value = candidate;
end
end
