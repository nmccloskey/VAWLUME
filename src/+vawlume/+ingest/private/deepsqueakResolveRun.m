function run = deepsqueakResolveRun(conn, plan)
%DEEPSQUEAKRESOLVERUN Classify the extraction run against its declared identity.
%
% A scientific extraction run is one specific DeepSqueak execution against an
% established recording. It is not the project ingestion run, not the recording,
% not the workbook, not the output mapping profile, and not the DeepSqueak
% version alone. Its identity is the caller's explicit run_key scoped to the
% project, matching the schema's UNIQUE(project_id, run_key).
%
% Reuse requires every identity-defining element to agree: recording input,
% extractor version, output mapping profile version, settings provenance, and
% the imported export artifact's content. Any disagreement is an explicit
% conflict, never a silent update. Spreadsheet row content alone never decides
% whether two runs are the same execution.

arguments
    conn
    plan (1,1) struct
end

run = struct( ...
    run_key=plan.context.run.run_key, ...
    run_label=plan.context.run.run_label, ...
    notes=plan.context.run.notes, ...
    status=plan.context.run.status, ...
    started_at_utc=plan.context.run.started_at_utc, ...
    completed_at_utc=plan.context.run.completed_at_utc, ...
    action="create", ...
    existing_extraction_run_id=NaN, ...
    input_action="create", ...
    conflict_message="");

rows = fetch(conn, ...
    "SELECT extraction_run_id, extractor_version_id, " + ...
    "IFNULL(output_mapping_profile_version_id, -1) AS output_mapping_profile_version_id, " + ...
    "IFNULL(settings_profile_version_id, -1) AS settings_profile_version_id " + ...
    "FROM extraction_runs WHERE project_id = " + string(plan.recording.project_id) + ...
    " AND run_key = " + sqlText(run.run_key));
if isempty(rows) || height(rows) == 0
    return
end

run.existing_extraction_run_id = double(rows.extraction_run_id(1));
run.action = "reuse";

differences = strings(0, 1);
differences = appendDifference(differences, ...
    extractorVersionDifference(rows, plan));
differences = appendDifference(differences, ...
    profileVersionDifference(rows, plan));
differences = appendDifference(differences, ...
    settingsDifference(rows, plan));
differences = appendDifference(differences, ...
    recordingDifference(conn, run.existing_extraction_run_id, plan));
differences = appendDifference(differences, ...
    exportArtifactDifference(conn, run.existing_extraction_run_id, plan));

if ~isempty(differences)
    run.action = "conflict";
    run.conflict_message = "Extraction run '" + run.run_key + ...
        "' already exists with different provenance: " + ...
        strjoin(differences, " ");
    return
end

run.input_action = recordingInputAction(conn, run.existing_extraction_run_id, plan);
end

function message = extractorVersionDifference(rows, plan)
message = "";
storedId = double(rows.extractor_version_id(1));
plannedId = plan.extractor.run_version_id;
if isnan(plannedId)
    % The declared version has no registered row yet, so it cannot match the
    % version an existing run already recorded.
    message = "declared extractor version '" + ...
        plan.extractor.run_version_label + "' is not the registered version of the existing run.";
    return
end
if storedId ~= plannedId
    message = "extractor version differs from the existing run.";
end
end

function message = profileVersionDifference(rows, plan)
message = "";
storedId = double(rows.output_mapping_profile_version_id(1));
if storedId ~= plan.output_profile.profile_version_id
    message = "output mapping profile version differs from the existing run.";
end
end

function message = settingsDifference(rows, plan)
message = "";
storedId = double(rows.settings_profile_version_id(1));
plannedId = -1;
if plan.settings_profile.mode == "profile"
    if isnan(plan.settings_profile.profile_version_id)
        % A settings profile that must still be created cannot match a run that
        % already recorded one.
        if storedId ~= -1
            message = "settings profile provenance differs from the existing run.";
        else
            message = "the existing run records no settings profile, but this import supplies one.";
        end
        return
    end
    plannedId = plan.settings_profile.profile_version_id;
end
if storedId ~= plannedId
    message = "settings profile provenance differs from the existing run.";
end
end

function message = recordingDifference(conn, extractionRunId, plan)
message = "";
rows = fetch(conn, ...
    "SELECT recording_id FROM extraction_run_inputs " + ...
    "WHERE extraction_run_id = " + string(extractionRunId));
if isempty(rows) || height(rows) == 0
    return
end
if ~any(double(rows.recording_id) == plan.recording.recording_id)
    message = "the existing run analysed a different recording.";
end
end

function message = exportArtifactDifference(conn, extractionRunId, plan)
message = "";
planned = plan.artifacts(plan.artifacts.role == "event_measurement_export", :);
if isempty(planned) || height(planned) == 0
    return
end

rows = fetch(conn, ...
    "SELECT a.path_or_uri, IFNULL(a.checksum_sha256, '') AS checksum_sha256 " + ...
    "FROM extraction_run_artifacts ra " + ...
    "JOIN artifacts a ON a.artifact_id = ra.artifact_id " + ...
    "WHERE ra.extraction_run_id = " + string(extractionRunId) + ...
    " AND ra.artifact_role = 'event_measurement_export'");
if isempty(rows) || height(rows) == 0
    return
end

plannedChecksum = string(planned.checksum_sha256(1));
storedChecksums = string(rows.checksum_sha256);
if strlength(plannedChecksum) == 0 || all(strlength(storedChecksums) == 0)
    return
end
if ~any(storedChecksums == plannedChecksum)
    % Content, not location, decides. A relocated copy of the same export keeps
    % its checksum and so remains the same run input.
    message = "the existing run imported an export with a different checksum.";
end
end

function action = recordingInputAction(conn, extractionRunId, plan)
rows = fetch(conn, ...
    "SELECT recording_id, input_role FROM extraction_run_inputs " + ...
    "WHERE extraction_run_id = " + string(extractionRunId) + ...
    " AND recording_id = " + string(plan.recording.recording_id) + ...
    " AND input_role = 'source_audio'");
if isempty(rows) || height(rows) == 0
    action = "create";
else
    action = "reuse";
end
end

function differences = appendDifference(differences, message)
if strlength(message) > 0
    differences(end + 1, 1) = message;
end
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end
