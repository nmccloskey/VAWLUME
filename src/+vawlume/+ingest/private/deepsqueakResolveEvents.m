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
    [detection, conflicts] = classifyDetection(conn, plan, row, existing, ...
        artifactId, events.classification);
    events.detections{index, 1} = detection;
    events.conflicts = [events.conflicts; conflicts];
end

events.counts = summarize(events);
end

function [detection, conflicts] = classifyDetection(conn, plan, row, existing, ...
        artifactId, classification)
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
[detection, conflicts] = classifyExistingChildren(conn, plan, detection, ...
    conflicts, classification);
end

function [detection, conflicts] = classifyExistingChildren(conn, plan, detection, ...
        conflicts, classification)
storedMeasurements = existingMeasurements(conn, detection.detection_id);
for index = 1:height(detection.measurements)
    featureId = detection.measurements.extractor_feature_id(index);
    match = storedMeasurements(storedMeasurements.extractor_feature_id == featureId, :);
    if isempty(match) || height(match) == 0
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = "Detection '" + detection.native_event_id + ...
            "' measurement '" + string(detection.measurements.native_name(index)) + ...
            "': the stored measurement is missing."; %#ok<AGROW>
        continue
    end
    if height(match) > 1
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = "Detection '" + detection.native_event_id + ...
            "' measurement '" + string(detection.measurements.native_name(index)) + ...
            "': more than one stored measurement uses this feature identity."; %#ok<AGROW>
        continue
    end
    [compatible, message] = measurementIsCompatible(match, ...
        detection.measurements(index, :), detection.source_artifact_id);
    if compatible
        detection.measurements.action(index) = "reuse";
    else
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = "Detection '" + detection.native_event_id + ...
            "' measurement '" + string(detection.measurements.native_name(index)) + ...
            "': " + message; %#ok<AGROW>
    end
end

if detection.curation.present
    [compatible, message] = curationIsCompatible(conn, detection);
    if compatible
        detection.curation.action = "reuse";
    else
        detection.curation.action = "conflict";
        conflicts(end + 1, 1) = "Detection '" + detection.native_event_id + ...
            "' curation evidence: " + message;
    end
end

if detection.classification.action == "create"
    [compatible, message] = assignmentIsCompatible(conn, detection, plan, classification);
    if compatible
        detection.classification.action = "reuse";
    else
        detection.classification.action = "conflict";
        conflicts(end + 1, 1) = "Detection '" + detection.native_event_id + ...
            "' classification evidence: " + message;
    end
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

function [compatible, message] = measurementIsCompatible(match, planned, sourceArtifactId)
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
        ~valuesAgree(nullableReal(match.native_value_integer(1)), planned.native_value_integer(1), tolerance) || ...
        ~valuesAgree(nullableReal(match.canonical_value_real(1)), planned.canonical_value_real(1), tolerance) || ...
        ~valuesAgree(nullableReal(match.canonical_value_integer(1)), planned.canonical_value_integer(1), tolerance) || ...
        presentText(match.native_value_text(1)) ~= presentText(planned.native_value_text(1)) || ...
        presentText(match.canonical_value_text(1)) ~= presentText(planned.canonical_value_text(1))
    compatible = false;
    message = "stored value differs from the imported value.";
    return
end

if double(match.source_artifact_id(1)) ~= sourceArtifactId || ...
        double(match.canonical_feature_id(1)) ~= double(planned.canonical_feature_id(1)) || ...
        presentText(match.native_unit(1)) ~= presentText(planned.native_unit(1)) || ...
        presentText(match.canonical_unit(1)) ~= presentText(planned.canonical_unit(1)) || ...
        presentText(match.transform_key(1)) ~= presentText(planned.transform_key(1)) || ...
        presentText(match.operational_variant(1)) ~= presentText(planned.operational_variant(1)) || ...
        presentText(match.source_locator(1)) ~= presentText(planned.source_locator(1))
    compatible = false;
    message = "stored feature or provenance fields differ from the imported evidence.";
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
    raw_token=row.review_raw_token, ...
    native_field=row.review_native_field);
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
    curation_create=0, curation_reuse=0, curation_conflict=0, ...
    classification_assignments_create=0, classification_assignments_reuse=0, ...
    classification_assignments_conflict=0);

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
    "SELECT extractor_feature_id, IFNULL(canonical_feature_id, -1) AS canonical_feature_id, " + ...
    "IFNULL(source_artifact_id, -1) AS source_artifact_id, native_value_type, " + ...
    "IFNULL(native_raw_token, '') AS native_raw_token, " + ...
    "IFNULL(native_value_real, 1e308) AS native_value_real, " + ...
    "IFNULL(native_value_integer, 1e308) AS native_value_integer, " + ...
    "IFNULL(native_value_text, '') AS native_value_text, " + ...
    "IFNULL(canonical_value_real, 1e308) AS canonical_value_real, " + ...
    "IFNULL(canonical_value_integer, 1e308) AS canonical_value_integer, " + ...
    "IFNULL(canonical_value_text, '') AS canonical_value_text, " + ...
    "IFNULL(native_unit, '') AS native_unit, " + ...
    "IFNULL(canonical_unit, '') AS canonical_unit, " + ...
    "IFNULL(transform_key, '') AS transform_key, " + ...
    "IFNULL(operational_variant, '') AS operational_variant, " + ...
    "IFNULL(source_locator, '') AS source_locator " + ...
    "FROM event_measurements WHERE detection_id = " + string(detectionId));
end

function [compatible, message] = curationIsCompatible(conn, detection)
rows = fetch(conn, ...
    "SELECT IFNULL(status_after, '') AS status_after, actor_type, " + ...
    "IFNULL(source_artifact_id, -1) AS source_artifact_id, " + ...
    "IFNULL(actor_label, '') AS actor_label, " + ...
    "IFNULL(details_json, '') AS details_json " + ...
    "FROM curation_events WHERE detection_id = " + string(detection.detection_id) + ...
    " AND action_type = " + sqlText(detection.curation.action_type));

compatible = false;
if isempty(rows) || height(rows) == 0
    message = "the stored curation row is missing.";
    return
end
if height(rows) > 1
    message = "more than one stored curation row has this action type.";
    return
end
if presentText(rows.status_after(1)) ~= detection.curation.status_after
    message = "stored review status differs from the imported evidence.";
    return
end
if presentText(rows.actor_type(1)) ~= "extractor" || ...
        double(rows.source_artifact_id(1)) ~= detection.source_artifact_id
    message = "stored curation provenance differs from the imported evidence.";
    return
end
expectedActorLabel = "DeepSqueak " + detection.curation.native_field + " column";
expectedDetails = jsonencode(struct( ...
    native_field=detection.curation.native_field, ...
    native_raw_token=detection.curation.raw_token, ...
    canonical_status=detection.curation.status_after));
if presentText(rows.actor_label(1)) ~= expectedActorLabel || ...
        presentText(rows.details_json(1)) ~= expectedDetails
    message = "stored native review token or field provenance differs from the imported evidence.";
    return
end
compatible = true;
message = "";
end

function [compatible, message] = assignmentIsCompatible(conn, detection, plan, classification)
rows = fetch(conn, ...
    "SELECT cc.native_class_id, cc.native_class_label, " + ...
    "IFNULL(cc.canonical_class_label, '') AS canonical_class_label, " + ...
    "ca.assignment_source, IFNULL(ca.score_or_distance, 1e308) AS score_or_distance " + ...
    "FROM classification_assignments ca " + ...
    "JOIN classification_runs cr ON cr.classification_run_id = ca.classification_run_id " + ...
    "JOIN classification_classes cc ON cc.classification_class_id = ca.classification_class_id " + ...
    "WHERE ca.detection_id = " + string(detection.detection_id) + ...
    " AND cr.parent_extraction_run_id = " + string(plan.run.existing_extraction_run_id) + ...
    " AND cr.method = " + sqlText(classification.method));

compatible = false;
if isempty(rows) || height(rows) == 0
    message = "the stored classification assignment is missing.";
    return
end
if height(rows) > 1
    message = "more than one stored assignment represents this imported label.";
    return
end
if presentText(rows.native_class_id(1)) ~= detection.classification.native_label || ...
        presentText(rows.native_class_label(1)) ~= detection.classification.native_label
    message = "stored native label differs from the imported evidence.";
    return
end
if strlength(presentText(rows.canonical_class_label(1))) > 0
    message = "stored assignment adds a canonical class interpretation not present in the export.";
    return
end
if presentText(rows.assignment_source(1)) ~= "extractor" || ...
        ~isnan(nullableReal(rows.score_or_distance(1)))
    message = "stored assignment source or score differs from the imported evidence.";
    return
end
compatible = true;
message = "";
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end
