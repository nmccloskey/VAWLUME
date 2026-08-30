function [plan, counts] = mupetApplyPlan(conn, plan)
%MUPETAPPLYPLAN Atomically apply the whole MUPET scientific graph.
%
% One function owns one transaction for the whole import: the settings profile,
% the exact extractor version, every artifact, the extraction run and its
% recording input, the run-artifact role links, and the complete syllable
% population with its measurements. A failure at any point rolls all of it back,
% so the invariant holds:
%
%   an extraction run exists  <=>  its intended syllables were imported
%
% Helpers called from here insert only; none starts, commits, or rolls back a
% transaction of its own.
%
% Dependency order is fixed by the schema: extraction_run_inputs must exist
% before any detection, because trg_detection_requires_run_input rejects a
% detection whose recording is not a registered input to its run.
%
% No curation_events, classification_runs, classification_classes, or
% classification_assignments rows are written, because the MUPET per-syllable CSV
% exports no review state and no class label. That is a capability difference,
% not an omission.

arguments
    conn
    plan (1,1) struct
end

if plan.has_conflicts
    error("vawlume:ingest:MupetPlanConflict", ...
        "A MUPET import plan with conflicts cannot be applied.");
end

oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:ingest:TransactionState", ...
        "MUPET import requires a connection with AutoCommit enabled.");
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
%APPLYSETTINGSPROFILE Register a caller-supplied VAWLUME settings JSON.
%
% Only the JSON mode creates a config_profiles row. Native config.csv evidence is
% carried by its own artifact and that artifact's structured capture, because the
% schema has no truthful lineage edge from a source artifact to a synthesized
% profile version. Fabricating one would assert a derivation the database cannot
% describe.
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
        notes="Extractor settings profile supplied with a MUPET import."), ...
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
    description = "MUPET extractor settings profile.";
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
    notes="Exact extractor version declared for a MUPET import."), ...
    "extractor_version_id");
counts.extractor_versions = counts.extractor_versions + 1;
end

function [plan, counts] = applyArtifacts(conn, plan, counts)
for index = 1:height(plan.artifacts)
    if string(plan.artifacts.action(index)) == "reuse"
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
%ARTIFACTMETADATA Role provenance merged with the artifact's own capture.
%
% The runtime path is diagnostic provenance for this execution, never durable
% identity, so it is recorded beside the portable path rather than as it. The
% planned metadata - the native config.csv structured capture, and any
% dataset/workspace provenance - is preserved alongside rather than replaced,
% because it is the only place the exact 11 captured settings survive.
metadata = struct( ...
    role=string(plan.artifacts.role(index)), ...
    description=string(plan.artifacts.description(index)), ...
    runtime_path=string(plan.artifacts.runtime_path(index)), ...
    checksum_status=string(plan.artifacts.checksum_status(index)));

planned = string(plan.artifacts.metadata_json(index));
if strlength(planned) > 0
    try
        decoded = jsondecode(char(planned));
    catch
        decoded = [];
    end
    if isstruct(decoded) && isscalar(decoded)
        for name = string(fieldnames(decoded))'
            metadata.(char(name)) = decoded.(char(name));
        end
    end
end
metadata = string(jsonencode(metadata));
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
% MUPET's segmentation and filtering behaviour is settings-dependent, so the run
% states which settings source produced it and whether native processed evidence
% and extractor-native grouping were supplied at all.
statements = "settings=" + plan.settings_status + ...
    "; settings_source=" + plan.context.settings.mode + ...
    "; native_processed=" + plan.context.native_artifact.mode + ...
    "; dataset=" + plan.context.dataset.status;
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

function [plan, counts] = applyEventPopulation(conn, plan, counts)
% The export artifact's row id is read again here rather than taken from the
% plan. When the artifact is created by this same apply, the plan recorded it as
% unresolved, and writing that into detections would leave source_artifact_id
% NULL. Detection identity is UNIQUE(run, recording, source_artifact_id,
% native_event_id), and SQLite treats NULLs as distinct, so a NULL there would
% silently let every rerun insert a second copy of the whole population.
scope = struct( ...
    extraction_run_id=plan.run.existing_extraction_run_id, ...
    recording_id=plan.recording.recording_id, ...
    source_artifact_id=appliedExportArtifactId(plan), ...
    event_subtype="vocalization_detection", ...
    timing_basis="profile_selected_event_geometry");
[plan.events.detections, counts] = extractorApplyEvents(conn, scope, ...
    plan.events.detections, counts);
end

function id = appliedExportArtifactId(plan)
rows = plan.artifacts(plan.artifacts.role == "event_measurement_export", :);
id = double(rows.existing_artifact_id(1));
if isnan(id)
    error("vawlume:ingest:MupetArtifactUnresolved", ...
        "The event CSV artifact was not resolved before the syllable population.");
end
end

function total = insertedRowCount(counts)
%INSERTEDROWCOUNT Number of rows this apply actually wrote.
%
% A fully compatible rerun reuses every row and therefore writes nothing, which
% leaves SQLite with no open transaction to commit. This importer records no
% per-attempt audit row, so the no-write case is normal rather than exceptional
% and must not be reported as a commit failure.
total = counts.config_profiles + counts.config_profile_versions + ...
    counts.extractor_versions + counts.artifacts + counts.extraction_runs + ...
    counts.extraction_run_inputs + counts.extraction_run_artifacts + ...
    counts.detections + counts.event_measurements;
end

function counts = emptyCounts()
% curation_events and classification rows have no counter because this importer
% never writes one. A zero counter would suggest the rows were considered and
% found empty; their absence from the contract is the accurate statement.
counts = struct( ...
    config_profiles=0, ...
    config_profile_versions=0, ...
    extractor_versions=0, ...
    artifacts=0, ...
    extraction_runs=0, ...
    extraction_run_inputs=0, ...
    extraction_run_artifacts=0, ...
    detections=0, ...
    event_measurements=0, ...
    reused_config_profiles=0, ...
    reused_config_profile_versions=0, ...
    reused_extractor_versions=0, ...
    reused_artifacts=0, ...
    reused_extraction_runs=0, ...
    reused_extraction_run_inputs=0, ...
    reused_extraction_run_artifacts=0, ...
    reused_detections=0, ...
    reused_event_measurements=0);
end
