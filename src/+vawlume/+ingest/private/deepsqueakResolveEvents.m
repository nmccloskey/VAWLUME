function events = deepsqueakResolveEvents(conn, plan, routed)
%DEEPSQUEAKRESOLVEEVENTS Classify the event population against existing rows.
%
% Detections and their measurements are classified by the shared extractor core,
% because every extractor populates them identically. This function adds only the
% evidence DeepSqueak actually exports and MUPET does not: the accept flag that
% becomes curation evidence, and the opaque call label that becomes a
% classification assignment. Those layers exist here rather than in the shared
% core so that an extractor without them produces no such rows at all, instead of
% producing empty or fabricated ones.

arguments
    conn
    plan (1,1) struct
    routed (1,1) struct
end

events = struct();
events.classification = classificationPlan(plan, routed);

scope = struct( ...
    extraction_run_id=plan.run.existing_extraction_run_id, ...
    recording_id=plan.recording.recording_id, ...
    source_artifact_id=exportArtifactId(plan));
[detections, conflicts] = extractorClassifyDetections(conn, scope, routed, "call");

for index = 1:numel(detections)
    detection = detections{index};
    row = routed.rows{index};
    detection.curation = curationDisposition(row);
    detection.classification = struct( ...
        present=row.label_present, native_label=row.label_raw_token, action="skip");
    if row.label_present
        detection.classification.action = "create";
    end

    if detection.action == "reuse"
        [detection, conflicts] = classifyExistingAnnotations(conn, plan, detection, ...
            conflicts, events.classification);
    end
    detections{index} = detection;
end

events.detections = detections;
events.conflicts = conflicts;
events.counts = summarize(events);
end

function [detection, conflicts] = classifyExistingAnnotations(conn, plan, detection, ...
        conflicts, classification)
%CLASSIFYEXISTINGANNOTATIONS Compare stored review and label evidence.
%
% Only reached for a detection the shared core already found compatible, so a
% disagreement here is specifically about annotation evidence rather than about
% the event itself.
if detection.curation.present
    [compatible, message] = curationIsCompatible(conn, detection);
    if compatible
        detection.curation.action = "reuse";
    else
        detection.curation.action = "conflict";
        conflicts(end + 1, 1) = "Call '" + detection.native_event_id + ...
            "' curation evidence: " + message;
    end
end

if detection.classification.action == "create"
    [compatible, message] = assignmentIsCompatible(conn, detection, plan, classification);
    if compatible
        detection.classification.action = "reuse";
    else
        detection.classification.action = "conflict";
        conflicts(end + 1, 1) = "Call '" + detection.native_event_id + ...
            "' classification evidence: " + message;
    end
end
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

function text = presentText(value)
%PRESENTTEXT Normalize a fetched text value to a comparable string.
%
% MATLAB's SQLite fetch returns <missing> rather than "" for an empty text
% value, even one produced by IFNULL, and every comparison against a missing
% string is false. Normalizing keeps "absent" and "empty" comparable.
text = string(value);
text(ismissing(text)) = "";
end

function value = nullableReal(stored)
%NULLABLEREAL Map the SQL NULL sentinel back to NaN.
value = double(stored);
if value >= 1e307
    value = NaN;
end
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
