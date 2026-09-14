function [plan, counts] = attributionImportApplyPlan(conn, plan)
%ATTRIBUTIONIMPORTAPPLYPLAN Persist one imported attribution table atomically.
%
% Transaction shape, established empirically in Phase 3: sqlwrite OPENS a
% transaction when AutoCommit is off; execute and sqlupdate JOIN one already
% open; an explicit BEGIN is refused.

counts = struct(source_files=0, config_profiles=0, config_profile_versions=0, ...
    imported_attribution_windows=0, imported_attribution_claims=0);

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
            source_file_id=sourceFileId, ...
            mapping_profile_version_id=profileVersionId, ...
            source_locator=string(row.source_locator)), ...
            "imported_attribution_window_id");
        windowIds(char(string(row.window_key))) = id;
        counts.imported_attribution_windows = counts.imported_attribution_windows + 1;
    end
    plan.window_ids = windowIds;

    % The claims, with the exporter's numbers and the semantics the profile
    % declared for them. P4-5 closed at 0.10-draft: before that table existed the
    % values were parsed here and discarded, because a window had no column for a
    % number and a candidate needs a target that correspondence has not yet found.
    %
    % NO CANDIDATE OR EVIDENCE ROW IS WRITTEN HERE, and that is still true.
    %
    % A candidate belongs to (target, entity). An imported claim belongs to
    % (window, entity). Mapping one onto the other requires knowing which window
    % refers to which event -- which is correspondence, and has not happened.
    % Writing a candidate on every target would assert that every window's claim
    % applies to every event, and would silently collapse two different scores
    % for one entity into whichever row was written first.
    %
    % Nor does a claim become a candidate once correspondence exists. Deciding
    % which correspondence is good enough to carry a claim onto a target is a
    % policy question, and answering it in storage would collapse the ambiguity
    % correspondence preserves. vawlume.attribution.addCandidates stays explicit.
    [plan, counts] = writeClaims(conn, plan, counts);

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

function [plan, counts] = writeClaims(conn, plan, counts)
% One row per claim, in source order, each carrying its own verbatim label.
%
% The window used to carry a '|'-joined synthesis of these labels. That string was
% in no source file, and it made a score unassignable to the caller it belonged
% to. The claims are the source's own shape: one row per (window, caller).
%
% Absent values are left absent. attributionImportInsertRow drops a NaN number and
% an empty string before writing, so an unscored claim stores SQL NULL rather than
% a substitute -- which is the whole point of the profile's
% require_one_of_score_or_probability=false.
claimIds = NaN(height(plan.claims), 1);
ordinals = containers.Map("KeyType", "char", "ValueType", "double");
for index = 1:height(plan.claims)
    claim = plan.claims(index, :);
    windowKey = char(string(claim.window_key));
    if isKey(ordinals, windowKey)
        ordinals(windowKey) = ordinals(windowKey) + 1;
    else
        ordinals(windowKey) = 1;
    end
    claimIds(index) = attributionImportInsertRow(conn, "imported_attribution_claims", struct( ...
        imported_attribution_window_id=plan.window_ids(windowKey), ...
        claim_ordinal=ordinals(windowKey), ...
        source_caller_label=string(claim.caller_label), ...
        entity_id=double(claim.entity_id), ...
        score=double(claim.score), ...
        score_semantics=string(claim.score_semantics), ...
        probability=double(claim.probability), ...
        probability_semantics=string(claim.probability_semantics), ...
        source_locator=string(claim.source_locator)), ...
        "imported_attribution_claim_id");
    counts.imported_attribution_claims = counts.imported_attribution_claims + 1;
end
plan.claim_ids = claimIds;
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
