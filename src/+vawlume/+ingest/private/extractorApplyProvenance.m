function [plan, counts] = extractorApplyProvenance(conn, plan, counts, options)
%EXTRACTORAPPLYPROVENANCE Write the run and provenance rows of one import plan.
%
% Both importers write the same provenance graph in the same dependency order:
% settings profile, exact extractor version, artifacts, extraction run, its
% recording input, and its artifact role links. Only the descriptive text
% differs, so that arrives as data rather than as a second implementation.
%
% This helper only inserts. It never opens, commits, or rolls back a
% transaction: the caller owns the transaction so a later failure rolls back the
% whole scientific graph. Dependency order matters, because
% trg_detection_requires_run_input rejects a detection whose recording is not
% already a registered input to its run.
%
% Every count field this touches exists in both importers' counters, so the
% caller's counts struct passes through unchanged in shape.

arguments
    conn
    plan (1,1) struct
    counts (1,1) struct
    options.SettingsDescription (1,1) string = "Extractor settings profile."
    options.SettingsVersionNote (1,1) string = "Extractor settings profile supplied with an import."
    options.ExtractorVersionNote (1,1) string = "Exact extractor version declared for an import."
    options.RunNotes (1,1) string = ""
end

[plan, counts] = applySettingsProfile(conn, plan, counts, options);
[plan, counts] = applyExtractorVersion(conn, plan, counts, options);
[plan, counts] = applyArtifacts(conn, plan, counts);
[plan, counts] = applyExtractionRun(conn, plan, counts, options);
[plan, counts] = applyRunInputs(conn, plan, counts);
[plan, counts] = applyRunArtifacts(conn, plan, counts);
end

function [plan, counts] = applySettingsProfile(conn, plan, counts, options)
%APPLYSETTINGSPROFILE Register an explicit VAWLUME extractor-settings profile.
%
% Only the profile mode creates rows. An extractor whose settings evidence is a
% native artifact carries it as that artifact instead, because the schema has no
% truthful lineage edge from a source artifact to a synthesized profile version.
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
        description=settingsDescription(settings, options)), "profile_id");
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
        notes=options.SettingsVersionNote), "profile_version_id");
    counts.config_profile_versions = counts.config_profile_versions + 1;
elseif settings.version_action == "reuse"
    counts.reused_config_profile_versions = counts.reused_config_profile_versions + 1;
end

plan.settings_profile = settings;
end

function description = settingsDescription(settings, options)
description = settings.description;
if strlength(description) == 0
    description = options.SettingsDescription;
end
end

function [plan, counts] = applyExtractorVersion(conn, plan, counts, options)
if plan.extractor.version_action ~= "create"
    counts.reused_extractor_versions = counts.reused_extractor_versions + 1;
    return
end

plan.extractor.run_version_id = insertIntakeRow(conn, "extractor_versions", struct( ...
    extractor_id=plan.extractor.extractor_id, ...
    version_label=plan.extractor.run_version_label, ...
    implementation_language="MATLAB", ...
    notes=options.ExtractorVersionNote), "extractor_version_id");
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
%ARTIFACTMETADATA Role provenance merged with whatever the plan captured.
%
% The runtime path is diagnostic provenance for this execution, never durable
% identity, so it is recorded beside the portable path rather than as it. An
% artifact that carries its own planned capture - a native MUPET config.csv
% carries its structured 11-key settings capture, and any dataset or workspace
% provenance rides along - keeps it, because that is the only place those exact
% values survive. An artifact with no planned metadata simply gets the role
% block.
metadata = struct( ...
    role=string(plan.artifacts.role(index)), ...
    description=string(plan.artifacts.description(index)), ...
    runtime_path=string(plan.artifacts.runtime_path(index)), ...
    checksum_status=string(plan.artifacts.checksum_status(index)));

if ~ismember("metadata_json", string(plan.artifacts.Properties.VariableNames))
    metadata = string(jsonencode(metadata));
    return
end

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

function [plan, counts] = applyExtractionRun(conn, plan, counts, options)
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
    notes=options.RunNotes), "extraction_run_id");
counts.extraction_runs = counts.extraction_runs + 1;
end

function id = settingsVersionId(plan)
id = "";
if plan.settings_profile.mode == "profile" && ...
        ~isnan(plan.settings_profile.profile_version_id)
    id = plan.settings_profile.profile_version_id;
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
