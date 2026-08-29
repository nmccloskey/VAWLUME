function run = extractorResolveRun(conn, plan, identityRoles)
%EXTRACTORRESOLVERUN Classify a run against schema and provenance identity.

arguments
    conn
    plan (1,1) struct
    identityRoles (1,:) string
end

run = struct(run_key=plan.context.run.run_key, run_label=plan.context.run.run_label, ...
    notes=plan.context.run.notes, status=plan.context.run.status, ...
    started_at_utc=plan.context.run.started_at_utc, ...
    completed_at_utc=plan.context.run.completed_at_utc, action="create", ...
    existing_extraction_run_id=NaN, input_action="create", conflict_message="");
rows = fetch(conn, "SELECT extraction_run_id, extractor_version_id, " + ...
    "IFNULL(output_mapping_profile_version_id, -1) AS output_mapping_profile_version_id, " + ...
    "IFNULL(settings_profile_version_id, -1) AS settings_profile_version_id " + ...
    "FROM extraction_runs WHERE project_id = " + string(plan.recording.project_id) + ...
    " AND run_key = " + sqlText(run.run_key));
if isempty(rows) || height(rows) == 0, return, end

run.existing_extraction_run_id = double(rows.extraction_run_id(1));
run.action = "reuse";
differences = strings(0,1);
differences = appendDifference(differences, extractorVersionDifference(rows, plan));
differences = appendDifference(differences, profileVersionDifference(rows, plan));
differences = appendDifference(differences, settingsDifference(rows, plan));
differences = appendDifference(differences, recordingDifference(conn, run.existing_extraction_run_id, plan));
differences = [differences; artifactDifferences(conn, run.existing_extraction_run_id, plan, identityRoles)];
if ~isempty(differences)
    run.action = "conflict";
    run.conflict_message = "Extraction run '" + run.run_key + ...
        "' already exists with different provenance: " + strjoin(differences, " ");
    return
end
run.input_action = recordingInputAction(conn, run.existing_extraction_run_id, plan);
end

function message = extractorVersionDifference(rows, plan)
message = "";
plannedId = plan.extractor.run_version_id;
if isnan(plannedId)
    message = "declared extractor version '" + plan.extractor.run_version_label + ...
        "' is not the registered version of the existing run.";
elseif double(rows.extractor_version_id(1)) ~= plannedId
    message = "extractor version differs from the existing run.";
end
end

function message = profileVersionDifference(rows, plan)
message = "";
if double(rows.output_mapping_profile_version_id(1)) ~= plan.output_profile.profile_version_id
    message = "output mapping profile version differs from the existing run.";
end
end

function message = settingsDifference(rows, plan)
message = "";
storedId = double(rows.settings_profile_version_id(1));
plannedId = -1;
if isfield(plan, "settings_profile") && plan.settings_profile.mode == "profile"
    if isnan(plan.settings_profile.profile_version_id)
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

function message = recordingDifference(conn, runId, plan)
message = "";
rows = fetch(conn, "SELECT recording_id FROM extraction_run_inputs WHERE extraction_run_id = " + string(runId));
if ~isempty(rows) && height(rows) > 0 && ...
        ~any(double(rows.recording_id) == plan.recording.recording_id)
    message = "the existing run analysed a different recording.";
end
end

function differences = artifactDifferences(conn, runId, plan, roles)
differences = strings(0,1);
stored = fetch(conn, "SELECT ra.artifact_role, a.artifact_id, a.path_or_uri, " + ...
    "a.artifact_type, IFNULL(a.checksum_sha256, '') AS checksum_sha256 " + ...
    "FROM extraction_run_artifacts ra JOIN artifacts a ON a.artifact_id = ra.artifact_id " + ...
    "WHERE ra.extraction_run_id = " + string(runId));
for role = roles
    planned = plan.artifacts(plan.artifacts.role == role,:);
    if isempty(stored) || height(stored) == 0
        storedForRole = table();
    else
        storedForRole = stored(presentText(stored.artifact_role) == role,:);
    end
    if height(planned) ~= 1 || height(storedForRole) ~= 1
        if height(planned) ~= height(storedForRole)
            differences(end+1,1) = role + " artifact provenance is present on only one version of the run."; %#ok<AGROW>
        elseif height(planned) > 1
            differences(end+1,1) = role + " artifact provenance is ambiguous because more than one artifact has that role."; %#ok<AGROW>
        end
        continue
    end
    if string(planned.path_or_uri(1)) ~= presentText(storedForRole.path_or_uri(1))
        differences(end+1,1) = role + " artifact identity differs (stored '" + ...
            presentText(storedForRole.path_or_uri(1)) + "', supplied '" + ...
            string(planned.path_or_uri(1)) + "')."; %#ok<AGROW>
    elseif string(planned.artifact_type(1)) ~= presentText(storedForRole.artifact_type(1))
        differences(end+1,1) = role + " artifact type differs."; %#ok<AGROW>
    elseif strlength(string(planned.checksum_sha256(1))) > 0 && ...
            strlength(presentText(storedForRole.checksum_sha256(1))) > 0 && ...
            string(planned.checksum_sha256(1)) ~= presentText(storedForRole.checksum_sha256(1))
        differences(end+1,1) = role + " artifact has a different checksum."; %#ok<AGROW>
    end
end
end

function action = recordingInputAction(conn, runId, plan)
rows = fetch(conn, "SELECT recording_id FROM extraction_run_inputs WHERE extraction_run_id = " + ...
    string(runId) + " AND recording_id = " + string(plan.recording.recording_id) + ...
    " AND input_role = 'source_audio'");
if isempty(rows) || height(rows) == 0, action = "create"; else, action = "reuse"; end
end

function values = appendDifference(values, message)
if strlength(message) > 0, values(end+1,1) = message; end
end
function value = sqlText(text), value = "'" + replace(string(text), "'", "''") + "'"; end
function text = presentText(value), text = string(value); text(ismissing(text)) = ""; end
