function [plan, counts] = deepsqueakApplyPlan(conn, plan)
%DEEPSQUEAKAPPLYPLAN Atomically apply the DeepSqueak provenance graph.
%
% One function owns one transaction for the whole import. Later passes add the
% event population inside this same transaction body rather than opening a second
% one, so a failure while inserting detections can never leave an orphaned
% extraction run behind. Helpers called from here perform inserts only; none
% starts, commits, or rolls back a transaction of its own, and semantic seed
% registration is never invoked from inside it.
%
% Dependency order is fixed by the schema: extraction_run_inputs must exist
% before any detection, because trg_detection_requires_run_input rejects a
% detection whose recording is not a registered input to its run.

if plan.has_conflicts
    error("vawlume:ingest:DeepSqueakPlanConflict", ...
        "A DeepSqueak import plan with conflicts cannot be applied.");
end

oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:ingest:TransactionState", ...
        "DeepSqueak import requires a connection with AutoCommit enabled.");
end

counts = emptyCounts();
conn.AutoCommit = "off";
try
    [plan, counts] = applySettingsProfile(conn, plan, counts);
    [plan, counts] = applyExtractorVersion(conn, plan, counts);
    [plan, counts] = applyArtifacts(conn, plan, counts);
    [plan, counts] = applyExtractionRun(conn, plan, counts);
    [plan, counts] = applyRunInputs(conn, plan, counts);
    [plan, counts] = applyRunArtifacts(conn, plan, counts);
    [plan, counts] = applyClassificationRun(conn, plan, counts);
    [plan, counts] = applyEventPopulation(conn, plan, counts);
    if insertedRowCount(counts) > 0
        commit(conn);
    end
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end

function [plan, counts] = applySettingsProfile(conn, plan, counts)
settings = plan.settings_profile;
if settings.mode ~= "profile"
    return
end

if settings.profile_action == "create"
    settings.profile_id = insertIntakeRow(conn, "config_profiles", struct( ...
        project_id=plan.recording.project_id, ...
        profile_key=settings.profile_key, ...
        profile_name=settings.profile_name, ...
        profile_kind="extractor_settings", ...
        is_builtin=0, ...
        description=settingsDescription(settings)), "profile_id");
    counts.config_profiles = counts.config_profiles + 1;
elseif settings.profile_action == "reuse"
    counts.reused_config_profiles = counts.reused_config_profiles + 1;
end

if settings.version_action == "create"
    settings.profile_version_id = insertIntakeRow(conn, "config_profile_versions", struct( ...
        profile_id=settings.profile_id, ...
        version_label=settings.version_label, ...
        content_format=settings.content_format, ...
        content_uri=settings.content_uri, ...
        checksum_sha256=settings.checksum_sha256, ...
        is_snapshot=1, ...
        notes="Extractor settings profile supplied with a DeepSqueak import."), ...
        "profile_version_id");
    counts.config_profile_versions = counts.config_profile_versions + 1;
elseif settings.version_action == "reuse"
    counts.reused_config_profile_versions = counts.reused_config_profile_versions + 1;
end

plan.settings_profile = settings;
end

function description = settingsDescription(settings)
description = settings.description;
if strlength(description) == 0
    description = "DeepSqueak extractor settings profile.";
end
end

function [plan, counts] = applyExtractorVersion(conn, plan, counts)
if plan.extractor.version_action ~= "create"
    counts.reused_extractor_versions = counts.reused_extractor_versions + 1;
    return
end

plan.extractor.run_version_id = insertIntakeRow(conn, "extractor_versions", struct( ...
    extractor_id=plan.extractor.extractor_id, ...
    version_label=plan.extractor.run_version_label, ...
    implementation_language="MATLAB", ...
    notes="Exact extractor version declared for a DeepSqueak import."), ...
    "extractor_version_id");
counts.extractor_versions = counts.extractor_versions + 1;
end

function [plan, counts] = applyArtifacts(conn, plan, counts)
for index = 1:height(plan.artifacts)
    action = string(plan.artifacts.action(index));
    if action == "reuse"
        counts.reused_artifacts = counts.reused_artifacts + 1;
        continue
    end

    artifactId = insertIntakeRow(conn, "artifacts", struct( ...
        project_id=plan.recording.project_id, ...
        artifact_type=string(plan.artifacts.artifact_type(index)), ...
        native_artifact_type=string(plan.artifacts.native_artifact_type(index)), ...
        path_or_uri=string(plan.artifacts.path_or_uri(index)), ...
        file_format=string(plan.artifacts.file_format(index)), ...
        checksum_sha256=string(plan.artifacts.checksum_sha256(index)), ...
        is_native=double(plan.artifacts.is_native(index)), ...
        metadata_json=artifactMetadata(plan, index)), "artifact_id");
    plan.artifacts.existing_artifact_id(index) = artifactId;
    counts.artifacts = counts.artifacts + 1;
end
end

function metadata = artifactMetadata(plan, index)
% The runtime path is diagnostic provenance for this execution, never durable
% identity, so it is recorded beside the portable path rather than as it.
metadata = jsonencode(struct( ...
    role=string(plan.artifacts.role(index)), ...
    description=string(plan.artifacts.description(index)), ...
    runtime_path=string(plan.artifacts.runtime_path(index)), ...
    checksum_status=string(plan.artifacts.checksum_status(index))));
end

function [plan, counts] = applyExtractionRun(conn, plan, counts)
if plan.run.action == "reuse"
    counts.reused_extraction_runs = counts.reused_extraction_runs + 1;
    return
end

plan.run.existing_extraction_run_id = insertIntakeRow(conn, "extraction_runs", struct( ...
    project_id=plan.recording.project_id, ...
    extractor_version_id=plan.extractor.run_version_id, ...
    run_key=plan.run.run_key, ...
    run_label=plan.run.run_label, ...
    output_mapping_profile_version_id=plan.output_profile.profile_version_id, ...
    settings_profile_version_id=settingsVersionId(plan), ...
    started_at_utc=plan.run.started_at_utc, ...
    completed_at_utc=plan.run.completed_at_utc, ...
    status=plan.run.status, ...
    notes=runNotes(plan)), "extraction_run_id");
counts.extraction_runs = counts.extraction_runs + 1;
end

function id = settingsVersionId(plan)
id = "";
if plan.settings_profile.mode == "profile" && ...
        ~isnan(plan.settings_profile.profile_version_id)
    id = plan.settings_profile.profile_version_id;
end
end

function notes = runNotes(plan)
% Absent settings and model rows are indistinguishable from "never asked" unless
% the run says so, so the run records what was and was not recoverable.
statements = "settings=" + plan.settings_status + "; model=" + plan.model_status;
if strlength(plan.run.notes) > 0
    notes = plan.run.notes + " [" + statements + "]";
else
    notes = statements;
end
end

function [plan, counts] = applyRunInputs(conn, plan, counts)
if plan.run.input_action == "reuse"
    counts.reused_extraction_run_inputs = counts.reused_extraction_run_inputs + 1;
    return
end

insertIntakeRow(conn, "extraction_run_inputs", struct( ...
    extraction_run_id=plan.run.existing_extraction_run_id, ...
    recording_id=plan.recording.recording_id, ...
    input_role="source_audio"));
counts.extraction_run_inputs = counts.extraction_run_inputs + 1;
end

function [plan, counts] = applyRunArtifacts(conn, plan, counts)
for index = 1:height(plan.run_artifacts)
    if string(plan.run_artifacts.action(index)) == "reuse"
        counts.reused_extraction_run_artifacts = ...
            counts.reused_extraction_run_artifacts + 1;
        continue
    end
    role = string(plan.run_artifacts.artifact_role(index));
    artifactRow = plan.artifacts(plan.artifacts.role == role, :);
    insertIntakeRow(conn, "extraction_run_artifacts", struct( ...
        extraction_run_id=plan.run.existing_extraction_run_id, ...
        artifact_id=artifactRow.existing_artifact_id(1), ...
        artifact_role=role));
    counts.extraction_run_artifacts = counts.extraction_run_artifacts + 1;
end
end

function [plan, counts] = applyClassificationRun(conn, plan, counts)
%APPLYCLASSIFICATIONRUN Create the run-scoped label context before assignments.
%
% classification_* is the only schema surface that can preserve an extractor's
% label evidence, so the run is recorded, but its method states that the label's
% provenance is unspecified unless the caller supplied a real one. No class is
% given a canonical biological meaning and no model is claimed.
classification = plan.events.classification;
if ~classification.present
    return
end

existing = fetch(conn, ...
    "SELECT classification_run_id FROM classification_runs " + ...
    "WHERE parent_extraction_run_id = " + string(plan.run.existing_extraction_run_id) + ...
    " AND method = '" + replace(classification.method, "'", "''") + "'");
if ~isempty(existing) && height(existing) > 0
    classification.classification_run_id = double(existing.classification_run_id(1));
    classification.action = "reuse";
    counts.reused_classification_runs = counts.reused_classification_runs + 1;
else
    classification.classification_run_id = insertIntakeRow(conn, "classification_runs", struct( ...
        project_id=plan.recording.project_id, ...
        parent_extraction_run_id=plan.run.existing_extraction_run_id, ...
        method=classification.method, ...
        run_label=classification.run_label, ...
        number_of_classes=numel(classification.classes), ...
        notes="Extractor-native labels imported from a DeepSqueak call-statistics export."), ...
        "classification_run_id");
    classification.action = "create";
    counts.classification_runs = counts.classification_runs + 1;
end

for index = 1:numel(classification.classes)
    nativeLabel = classification.classes(index);
    stored = fetch(conn, ...
        "SELECT classification_class_id FROM classification_classes " + ...
        "WHERE classification_run_id = " + string(classification.classification_run_id) + ...
        " AND native_class_id = '" + replace(nativeLabel, "'", "''") + "'");
    if ~isempty(stored) && height(stored) > 0
        classification.class_ids(index) = double(stored.classification_class_id(1));
        classification.class_actions(index) = "reuse";
        counts.reused_classification_classes = counts.reused_classification_classes + 1;
        continue
    end
    classification.class_ids(index) = insertIntakeRow(conn, "classification_classes", struct( ...
        classification_run_id=classification.classification_run_id, ...
        native_class_id=nativeLabel, ...
        native_class_label=nativeLabel, ...
        description="Extractor-native label preserved without canonical interpretation."), ...
        "classification_class_id");
    classification.class_actions(index) = "create";
    counts.classification_classes = counts.classification_classes + 1;
end

plan.events.classification = classification;
end

function [plan, counts] = applyEventPopulation(conn, plan, counts)
% The export artifact's row id is read again here rather than taken from the
% plan. When the artifact is created by this same apply, the plan recorded it as
% unresolved, and writing that into detections would leave source_artifact_id
% NULL. Detection identity is UNIQUE(run, recording, source_artifact_id,
% native_event_id), and SQLite treats NULLs as distinct, so a NULL there would
% silently let every rerun insert a second copy of the whole population.
artifactId = appliedExportArtifactId(plan);

for index = 1:numel(plan.events.detections)
    detection = plan.events.detections{index};
    detection.source_artifact_id = artifactId;
    if detection.action == "create"
        detection.detection_id = insertIntakeRow(conn, "detections", struct( ...
            extraction_run_id=plan.run.existing_extraction_run_id, ...
            recording_id=plan.recording.recording_id, ...
            source_artifact_id=detection.source_artifact_id, ...
            native_event_id=detection.native_event_id, ...
            event_subtype="vocalization_detection", ...
            start_time_s=detection.start_time_s, ...
            end_time_s=detection.end_time_s, ...
            timing_basis="profile_selected_event_geometry", ...
            detection_score=optionalReal(detection.detection_score), ...
            notes="source_row=" + string(detection.source_row)), "detection_id");
        counts.detections = counts.detections + 1;
    else
        counts.reused_detections = counts.reused_detections + 1;
    end

    counts = applyMeasurements(conn, detection, counts);
    counts = applyCuration(conn, detection, counts);
    counts = applyAssignment(conn, plan, detection, counts);
    plan.events.detections{index} = detection;
end
end

function id = appliedExportArtifactId(plan)
rows = plan.artifacts(plan.artifacts.role == "event_measurement_export", :);
id = double(rows.existing_artifact_id(1));
if isnan(id)
    error("vawlume:ingest:DeepSqueakArtifactUnresolved", ...
        "The export artifact was not resolved before the event population.");
end
end

function counts = applyMeasurements(conn, detection, counts)
for index = 1:height(detection.measurements)
    action = string(detection.measurements.action(index));
    if action ~= "create"
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
% value is explicitly missing. A missing measurement keeps its raw token and
% never becomes a fabricated zero.
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

function counts = applyCuration(conn, detection, counts)
if detection.curation.action == "skip"
    return
end
if detection.curation.action == "reuse"
    counts.reused_curation_events = counts.reused_curation_events + 1;
    return
end

insertIntakeRow(conn, "curation_events", struct( ...
    detection_id=detection.detection_id, ...
    source_artifact_id=detection.source_artifact_id, ...
    action_type=detection.curation.action_type, ...
    status_after=detection.curation.status_after, ...
    actor_type="extractor", ...
    actor_label="DeepSqueak " + detection.curation.native_field + " column", ...
    details_json=jsonencode(struct( ...
        native_field=detection.curation.native_field, ...
        native_raw_token=detection.curation.raw_token, ...
        canonical_status=detection.curation.status_after)), ...
    notes="Extractor review state, not a biological ground-truth claim."));
counts.curation_events = counts.curation_events + 1;
end

function counts = applyAssignment(conn, plan, detection, counts)
if detection.classification.action == "skip"
    return
end
if detection.classification.action == "reuse"
    counts.reused_classification_assignments = ...
        counts.reused_classification_assignments + 1;
    return
end

classification = plan.events.classification;
classIndex = find(classification.classes == detection.classification.native_label, 1);
if isempty(classIndex)
    return
end

insertIntakeRow(conn, "classification_assignments", struct( ...
    detection_id=detection.detection_id, ...
    classification_run_id=classification.classification_run_id, ...
    classification_class_id=classification.class_ids(classIndex), ...
    assignment_source="extractor", ...
    notes="Extractor-native label; provenance of the labelling method is not stated by the export."));
counts.classification_assignments = counts.classification_assignments + 1;
end

function value = optionalReal(candidate)
value = "";
if ~isnan(candidate)
    value = candidate;
end
end

function total = insertedRowCount(counts)
%INSERTEDROWCOUNT Number of rows this apply actually wrote.
%
% A fully compatible rerun reuses every row and therefore writes nothing, which
% leaves SQLite with no open transaction to commit. Unlike project intake, this
% importer records no per-attempt audit row, so the no-write case is normal
% rather than exceptional and must not be reported as a commit failure.
total = counts.config_profiles + counts.config_profile_versions + ...
    counts.extractor_versions + counts.artifacts + counts.extraction_runs + ...
    counts.extraction_run_inputs + counts.extraction_run_artifacts + ...
    counts.classification_runs + counts.classification_classes + ...
    counts.detections + counts.event_measurements + counts.curation_events + ...
    counts.classification_assignments;
end

function counts = emptyCounts()
counts = struct( ...
    config_profiles=0, ...
    config_profile_versions=0, ...
    extractor_versions=0, ...
    artifacts=0, ...
    extraction_runs=0, ...
    extraction_run_inputs=0, ...
    extraction_run_artifacts=0, ...
    classification_runs=0, ...
    classification_classes=0, ...
    detections=0, ...
    event_measurements=0, ...
    curation_events=0, ...
    classification_assignments=0, ...
    reused_config_profiles=0, ...
    reused_config_profile_versions=0, ...
    reused_extractor_versions=0, ...
    reused_artifacts=0, ...
    reused_extraction_runs=0, ...
    reused_extraction_run_inputs=0, ...
    reused_extraction_run_artifacts=0, ...
    reused_classification_runs=0, ...
    reused_classification_classes=0, ...
    reused_detections=0, ...
    reused_event_measurements=0, ...
    reused_curation_events=0, ...
    reused_classification_assignments=0);
end
