function [plan, counts] = attributionImportApplyPlan(conn, plan)
%ATTRIBUTIONIMPORTAPPLYPLAN Persist one imported attribution table atomically.
%
% Transaction shape, established empirically in Phase 3: sqlwrite OPENS a
% transaction when AutoCommit is off; execute and sqlupdate JOIN one already
% open; an explicit BEGIN is refused.

counts = struct(source_files=0, config_profiles=0, config_profile_versions=0, ...
    imported_attribution_windows=0);

previousAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
restore = onCleanup(@() restoreAutoCommit(conn, previousAutoCommit));

try
    [sourceFileId, counts] = registerSourceFile(conn, plan, counts);
    [profileVersionId, counts] = registerProfile(conn, plan, counts);
    plan.source_file_id = sourceFileId;
    plan.profile_version_id = profileVersionId;

    windowIds = containers.Map("KeyType", "char", "ValueType", "double");
    for index = 1:height(plan.windows)
        row = plan.windows(index, :);
        id = attributionImportInsertRow(conn, "imported_attribution_windows", struct( ...
            attribution_run_id=plan.run.attribution_run_id, ...
            recording_id=plan.run.recording_id, ...
            native_window_id=string(row.native_window_id), ...
            start_time_native=double(row.start_time_native), ...
            end_time_native=double(row.end_time_native), ...
            source_caller_label=callerLabelsFor(plan, string(row.window_key)), ...
            source_file_id=sourceFileId, ...
            mapping_profile_version_id=profileVersionId, ...
            source_locator=string(row.source_locator)), ...
            "imported_attribution_window_id");
        windowIds(char(string(row.window_key))) = id;
        counts.imported_attribution_windows = counts.imported_attribution_windows + 1;
    end
    plan.window_ids = windowIds;

    % NO CANDIDATE OR EVIDENCE ROW IS WRITTEN HERE, and that is the pass's main
    % finding rather than an omission.
    %
    % A candidate belongs to (target, entity). An imported claim belongs to
    % (window, entity). Mapping one onto the other requires knowing which window
    % refers to which event -- which is correspondence, and has not happened.
    % Writing a candidate on every target would assert that every window's claim
    % applies to every event, and would silently collapse two different scores
    % for one entity into whichever row was written first.
    %
    % The claims are returned in the plan with their values intact. They have
    % nowhere to be stored until correspondence exists: imported_attribution_windows
    % carries no score or probability column, and attribution_evidence requires a
    % target. Recorded as P4-5.

    commit(conn);
catch exception
    try
        rollback(conn);
    catch
    end
    rethrow(exception);
end
clear restore
end

% ---------------------------------------------------------------- helpers ---

function label = callerLabelsFor(plan, windowKey)
% The window records which labels were claimed over it, verbatim, so the imported
% representation is readable without joining to candidates.
matching = plan.claims(string(plan.claims.window_key) == windowKey, :);
label = strjoin(unique(string(matching.caller_label), "stable"), "|");
end

function [sourceFileId, counts] = registerSourceFile(conn, plan, counts)
existing = fetch(conn, "SELECT source_file_id FROM source_files " + ...
    "WHERE project_id=" + string(plan.run.project_id) + ...
    " AND path_or_uri=" + sqlText(plan.source.relative_path));
if ~isempty(existing) && height(existing) > 0
    sourceFileId = double(existing.source_file_id(1));
    return
end
sourceFileId = attributionImportInsertRow(conn, "source_files", struct( ...
    project_id=plan.run.project_id, ...
    file_role="attribution_output", ...
    path_or_uri=plan.source.relative_path, ...
    relative_path=plan.source.relative_path, ...
    filename=plan.source.filename, ...
    file_format="delimited_text", ...
    checksum_sha256=plan.source.checksum_sha256), "source_file_id");
counts.source_files = counts.source_files + 1;
end

function [versionId, counts] = registerProfile(conn, plan, counts)
existing = fetch(conn, "SELECT p.profile_id AS profile_id, " + ...
    "IFNULL(v.profile_version_id,-1) AS version_id, " + ...
    "IFNULL(v.checksum_sha256,'') AS checksum " + ...
    "FROM config_profiles p LEFT JOIN config_profile_versions v " + ...
    "  ON v.profile_id = p.profile_id AND v.version_label=" + ...
    sqlText(plan.profile.version_label) + ...
    " WHERE p.profile_key=" + sqlText(plan.profile.profile_key));
if ~isempty(existing) && height(existing) > 0
    profileId = double(existing.profile_id(1));
    versionId = double(existing.version_id(1));
    if versionId > 0
        stored = string(existing.checksum(1));
        if stored ~= "" && stored ~= plan.profile.checksum_sha256
            error("vawlume:attribution:ProfileVersionConflict", ...
                "Mapping profile %s version %s is registered with a different " + ...
                "checksum. Publish a new profile_version rather than editing one.", ...
                plan.profile.profile_key, plan.profile.version_label);
        end
        return
    end
else
    profileId = attributionImportInsertRow(conn, "config_profiles", struct( ...
        project_id=plan.run.project_id, ...
        profile_key=plan.profile.profile_key, ...
        profile_name=plan.profile.profile_name, ...
        profile_kind="attribution_input_mapping"), "profile_id");
    counts.config_profiles = counts.config_profiles + 1;
end
versionId = attributionImportInsertRow(conn, "config_profile_versions", struct( ...
    profile_id=profileId, ...
    version_label=plan.profile.version_label, ...
    profile_schema_version=plan.profile.profile_schema_version, ...
    content_format="json", ...
    content_uri=plan.profile.content_uri, ...
    checksum_sha256=plan.profile.checksum_sha256, ...
    is_snapshot=1), "profile_version_id");
counts.config_profile_versions = counts.config_profile_versions + 1;
end

function restoreAutoCommit(conn, previous)
try
    conn.AutoCommit = previous;
catch
end
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
