function events = deepsqueakResolveEvents(conn, plan, routed)
%DEEPSQUEAKRESOLVEEVENTS Classify the event population against existing rows.
%
% Detection identity is the schema's UNIQUE(extraction_run_id, recording_id,
% source_artifact_id, native_event_id). Row order is never identity: the same
% export reordered produces the same population, and the workbook row survives
% only as provenance in the detection's notes and in each measurement's
% source_locator.
%
% Existing scientific rows are never updated in place. Identical evidence is
% reused; changed evidence under one run identity is an explicit conflict that a
% future migration workflow must resolve deliberately.

arguments
    conn
    plan (1,1) struct
    routed (1,1) struct
end

events = struct();
events.detections = {};
events.conflicts = strings(0, 1);
events.classification = classificationPlan(plan, routed);

runId = plan.run.existing_extraction_run_id;
artifactId = exportArtifactId(plan);
existing = existingDetections(conn, runId, plan.recording.recording_id, artifactId);

for index = 1:numel(routed.rows)
    row = routed.rows{index};
    [detection, conflicts] = classifyDetection(conn, plan, row, existing, artifactId);
    events.detections{index, 1} = detection;
    events.conflicts = [events.conflicts; conflicts];
end

events.counts = summarize(events);
end

function [detection, conflicts] = classifyDetection(conn, plan, row, existing, artifactId)
conflicts = strings(0, 1);
detection = struct();
detection.source_row = row.source_row;
detection.native_event_id = row.native_event_id;
detection.start_time_s = row.start_time_s;
detection.end_time_s = row.end_time_s;
detection.detection_score = row.detection_score;
detection.source_artifact_id = artifactId;
detection.action = "create";
detection.detection_id = NaN;
detection.measurements = measurementDispositions(row.measurements);
detection.curation = curationDisposition(row);
detection.classification = struct( ...
    present=row.label_present, native_label=row.label_raw_token, action="skip");

if row.label_present
    detection.classification.action = "create";
end

match = matchExisting(existing, row.native_event_id);
if isempty(match)
    return
end

detection.detection_id = double(match.detection_id(1));
[compatible, message] = detectionIsCompatible(match, row);
if ~compatible
    detection.action = "conflict";
    conflicts(end + 1, 1) = "Detection '" + row.native_event_id + "': " + message;
    return
end

detection.action = "reuse";
[detection, conflicts] = classifyExistingChildren(conn, plan, detection, conflicts);
end

function [detection, conflicts] = classifyExistingChildren(conn, plan, detection, conflicts)
storedMeasurements = existingMeasurements(conn, detection.detection_id);
for index = 1:height(detection.measurements)
    featureId = detection.measurements.extractor_feature_id(index);
    match = storedMeasurements(storedMeasurements.extractor_feature_id == featureId, :);
    if isempty(match) || height(match) == 0
        continue
    end
    [compatible, message] = measurementIsCompatible(match, detection.measurements(index, :));
    if compatible
        detection.measurements.action(index) = "reuse";
    else
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = "Detection '" + detection.native_event_id + ...
            "' measurement '" + string(detection.measurements.native_name(index)) + ...
            "': " + message; %#ok<AGROW>
    end
end

if detection.curation.present && ...
        curationExists(conn, detection.detection_id, detection.curation.action_type)
    detection.curation.action = "reuse";
end

if detection.classification.action == "create" && ...
        assignmentExists(conn, detection.detection_id, plan)
    detection.classification.action = "reuse";
end
end

function [compatible, message] = detectionIsCompatible(match, row)
compatible = true;
message = "";
tolerance = 1e-9;

if ~valuesAgree(double(match.start_time_s(1)), row.start_time_s, tolerance) || ...
        ~valuesAgree(double(match.end_time_s(1)), row.end_time_s, tolerance)
    compatible = false;
    message = "existing timing differs from the imported evidence.";
    return
end
if ~valuesAgree(nullableReal(match.detection_score(1)), row.detection_score, tolerance)
    compatible = false;
    message = "existing detection score differs from the imported evidence.";
end
end

function value = nullableReal(stored)
%NULLABLEREAL Map the SQL NULL sentinel back to NaN.
%
% MATLAB's SQLite fetch errors on NULL columns, so nullable reals are selected
% through IFNULL with an out-of-range sentinel. Converting it back here keeps
% "absent" distinct from any real measured value.
value = double(stored);
if value >= 1e307
    value = NaN;
end
end

function [compatible, message] = measurementIsCompatible(match, planned)
compatible = true;
message = "";
tolerance = 1e-9;

storedType = presentText(match.native_value_type(1));
if storedType ~= presentText(planned.native_value_type(1))
    compatible = false;
    message = "native value type changed from '" + storedType + "' to '" + ...
        presentText(planned.native_value_type(1)) + "'.";
    return
end
if presentText(match.native_raw_token(1)) ~= presentText(planned.native_raw_token(1))
    compatible = false;
    message = "native raw token changed.";
    return
end
if ~valuesAgree(nullableReal(match.native_value_real(1)), planned.native_value_real(1), tolerance) || ...
        ~valuesAgree(nullableReal(match.canonical_value_real(1)), planned.canonical_value_real(1), tolerance)
    compatible = false;
    message = "stored value differs from the imported value.";
end
end

function tf = valuesAgree(stored, planned, tolerance)
if isnan(stored) && isnan(planned)
    tf = true;
    return
end
if isnan(stored) || isnan(planned)
    tf = false;
    return
end
tf = abs(stored - planned) <= tolerance;
end

function dispositions = measurementDispositions(measurements)
dispositions = measurements;
dispositions.action = repmat("create", height(measurements), 1);
end

function curation = curationDisposition(row)
% DeepSqueak's accept flag is recorded as extractor curation evidence with its
% native token retained. No human reviewer is invented, because the export
% states only a state.
curation = struct( ...
    present=row.review_present, ...
    action="skip", ...
    action_type="native_review_status_import", ...
    status_after=row.review_status, ...
    raw_token=row.review_raw_token);
if row.review_present
    curation.action = "create";
end
end

function classification = classificationPlan(plan, routed)
%CLASSIFICATIONPLAN Decide the run-scoped label context, if any labels exist.
%
% A DeepSqueak label may be manual, supervised, or clustering-derived, and the
% export does not say which. The profile therefore forbids inferring a
% classification method from a label alone. The run is still recorded, because
% classification_* is the only surface that can preserve label evidence, but its
% method states that the provenance is unspecified and no class is given a
% canonical biological meaning.
classification = struct( ...
    present=false, ...
    method="native_label_unspecified_provenance", ...
    run_label="DeepSqueak native call labels of unrecorded provenance", ...
    action="skip", ...
    classification_run_id=NaN, ...
    classes=strings(0, 1), ...
    class_actions=strings(0, 1), ...
    class_ids=NaN(0, 1));

declared = plan.context.classification;
if declared.mode == "declared"
    classification.method = declared.method;
    if strlength(declared.run_label) > 0
        classification.run_label = declared.run_label;
    end
end

labels = strings(0, 1);
for index = 1:numel(routed.rows)
    row = routed.rows{index};
    if row.label_present && strlength(row.label_raw_token) > 0
        labels(end + 1, 1) = row.label_raw_token; %#ok<AGROW>
    end
end
if isempty(labels)
    return
end

classification.present = true;
classification.action = "create";
classification.classes = unique(labels);
classification.class_actions = repmat("create", numel(classification.classes), 1);
classification.class_ids = NaN(numel(classification.classes), 1);
end

function counts = summarize(events)
counts = struct( ...
    detections_create=0, detections_reuse=0, detections_conflict=0, ...
    measurements_create=0, measurements_reuse=0, measurements_conflict=0, ...
    curation_create=0, curation_reuse=0, ...
    classification_assignments_create=0, classification_assignments_reuse=0);

for index = 1:numel(events.detections)
    detection = events.detections{index};
    counts = bump(counts, "detections_" + detection.action);
    for m = 1:height(detection.measurements)
        counts = bump(counts, "measurements_" + string(detection.measurements.action(m)));
    end
    if detection.curation.action ~= "skip"
        counts = bump(counts, "curation_" + detection.curation.action);
    end
    if detection.classification.action ~= "skip"
        counts = bump(counts, "classification_assignments_" + detection.classification.action);
    end
end
end

function counts = bump(counts, name)
name = char(name);
if isfield(counts, name)
    counts.(name) = counts.(name) + 1;
end
end

function id = exportArtifactId(plan)
rows = plan.artifacts(plan.artifacts.role == "event_measurement_export", :);
id = double(rows.existing_artifact_id(1));
end

function rows = existingDetections(conn, runId, recordingId, artifactId)
% A run that does not exist yet can have no detections, so the lookup is skipped
% rather than issued against an unresolved identifier.
if isnan(runId)
    rows = table();
    return
end
rows = fetch(conn, ...
    "SELECT detection_id, IFNULL(native_event_id, '') AS native_event_id, " + ...
    "start_time_s, end_time_s, IFNULL(detection_score, 1e308) AS detection_score " + ...
    "FROM detections WHERE extraction_run_id = " + string(runId) + ...
    " AND recording_id = " + string(recordingId) + ...
    " AND IFNULL(source_artifact_id, -1) = " + string(artifactIdOrMissing(artifactId)));
end

function value = artifactIdOrMissing(artifactId)
if isnan(artifactId)
    value = -1;
else
    value = artifactId;
end
end

function text = presentText(value)
%PRESENTTEXT Normalize a fetched text value to a comparable string.
%
% MATLAB's SQLite fetch returns <missing> rather than "" for an empty text
% value, even one produced by IFNULL, and every comparison against a missing
% string is false. Normalizing keeps "absent" and "empty" comparable.
text = string(value);
text(ismissing(text)) = "";
end

function match = matchExisting(existing, nativeEventId)
match = [];
if isempty(existing) || height(existing) == 0 || strlength(nativeEventId) == 0
    return
end
matches = presentText(existing.native_event_id) == nativeEventId;
if any(matches)
    match = existing(find(matches, 1), :);
end
end

function rows = existingMeasurements(conn, detectionId)
rows = fetch(conn, ...
    "SELECT extractor_feature_id, native_value_type, " + ...
    "IFNULL(native_raw_token, '') AS native_raw_token, " + ...
    "IFNULL(native_value_real, 1e308) AS native_value_real, " + ...
    "IFNULL(canonical_value_real, 1e308) AS canonical_value_real " + ...
    "FROM event_measurements WHERE detection_id = " + string(detectionId));
end

function tf = curationExists(conn, detectionId, actionType)
rows = fetch(conn, ...
    "SELECT COUNT(*) AS n FROM curation_events WHERE detection_id = " + ...
    string(detectionId) + " AND action_type = '" + actionType + "'");
tf = double(rows.n(1)) > 0;
end

function tf = assignmentExists(conn, detectionId, plan)
rows = fetch(conn, ...
    "SELECT COUNT(*) AS n FROM classification_assignments ca " + ...
    "JOIN classification_runs cr ON cr.classification_run_id = ca.classification_run_id " + ...
    "WHERE ca.detection_id = " + string(detectionId) + ...
    " AND cr.parent_extraction_run_id = " + string(plan.run.existing_extraction_run_id));
tf = double(rows.n(1)) > 0;
end
