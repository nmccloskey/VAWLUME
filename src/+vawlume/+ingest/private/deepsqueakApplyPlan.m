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

function total = insertedRowCount(counts)
%INSERTEDROWCOUNT Number of rows this apply actually wrote.
%
% A fully compatible rerun reuses every row and therefore writes nothing, which
% leaves SQLite with no open transaction to commit. Unlike project intake, this
% importer records no per-attempt audit row, so the no-write case is normal
% rather than exceptional and must not be reported as a commit failure.
total = counts.config_profiles + counts.config_profile_versions + ...
    counts.extractor_versions + counts.artifacts + counts.extraction_runs + ...
    counts.extraction_run_inputs + counts.extraction_run_artifacts;
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
    reused_config_profiles=0, ...
    reused_config_profile_versions=0, ...
    reused_extractor_versions=0, ...
    reused_artifacts=0, ...
    reused_extraction_runs=0, ...
    reused_extraction_run_inputs=0, ...
    reused_extraction_run_artifacts=0);
end
