function [plan, counts] = attributionApplyDecisionPlan(conn, plan)
%ATTRIBUTIONAPPLYDECISIONPLAN Persist decisions and their selections atomically.
%
% Transaction shape follows the established alignment/attribution finding:
% sqlwrite OPENS a transaction when AutoCommit is off; execute and sqlupdate
% JOIN one already open; an explicit BEGIN is refused.

counts = struct(config_profiles=0, config_profile_versions=0, ...
    attribution_decisions=0, attribution_decision_candidates=0, ...
    run_completed=0);

previousAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
restore = onCleanup(@() restoreAutoCommit(conn, previousAutoCommit));

try
    [policyVersionId, counts] = registerPolicy(conn, plan.policy, counts);
    plan.policy_profile_version_id = policyVersionId;

    decisionIds = NaN(height(plan.decisions), 1);
    for index = 1:height(plan.decisions)
        row = plan.decisions(index, :);
        values = struct( ...
            attribution_target_id=double(row.attribution_target_id), ...
            decision_status=string(row.decision_status), ...
            policy_profile_version_id=policyVersionId);
        if ~isnan(row.applied_threshold)
            values.applied_threshold = double(row.applied_threshold);
            values.applied_threshold_semantics = string(row.applied_threshold_semantics);
        end
        if strlength(string(row.exclusion_reason)) > 0
            values.exclusion_reason = string(row.exclusion_reason);
        end
        decisionIds(index) = attributionInsertRow(conn, "attribution_decisions", ...
            values, "attribution_decision_id");
        counts.attribution_decisions = counts.attribution_decisions + 1;
    end
    plan.decisions.attribution_decision_id = decisionIds;

    for index = 1:height(plan.selections)
        row = plan.selections(index, :);
        decisionId = decisionIds(double(plan.decisions.attribution_target_id) == ...
            double(row.attribution_target_id));
        attributionInsertRow(conn, "attribution_decision_candidates", struct( ...
            attribution_decision_id=decisionId(1), ...
            attribution_candidate_id=double(row.attribution_candidate_id), ...
            selection_role=string(row.selection_role)), "");
        counts.attribution_decision_candidates = ...
            counts.attribution_decision_candidates + 1;
    end

    counts.run_completed = completeRunWhenFullyDecided(conn, plan);

    commit(conn);
catch exception
    % Roll back defensively. sqlwrite OPENS a transaction while execute and
    % sqlupdate only JOIN one already open, so a failure before this plan's
    % first sqlwrite leaves nothing to roll back -- and an unguarded rollback
    % would then replace the real cause with an interface error about a
    % transaction that never existed.
    try
        rollback(conn);
    catch
    end
    rethrow(exception);
end
clear restore
end

% ---------------------------------------------------------------- helpers ---

function [versionId, counts] = registerPolicy(conn, policy, counts)
%REGISTERPOLICY Reuse the checksum-bearing profile version, or create it.
%
% Reuse is by (profile_key, version_label). A same-labelled version whose
% content checksum differs is refused rather than silently accepted: two
% different policies sharing one version label would make every decision citing
% that label ambiguous.
% The LEFT JOIN returns a NULL version id when the profile exists but this
% version does not, and the Database Toolbox raises on any SQL NULL in a result
% set. An integer sentinel is correct here because the column is an integer key.
existing = fetch(conn, "SELECT p.profile_id AS profile_id, " + ...
    "IFNULL(v.profile_version_id,-1) AS version_id, " + ...
    "IFNULL(v.checksum_sha256,'') AS checksum " + ...
    "FROM config_profiles p LEFT JOIN config_profile_versions v " + ...
    "  ON v.profile_id = p.profile_id AND v.version_label=" + ...
    sqlText(policy.version_label) + ...
    " WHERE p.profile_key=" + sqlText(policy.profile_key));

if height(existing) > 0
    profileId = double(existing.profile_id(1));
    versionId = double(existing.version_id(1));
    if versionId > 0
        stored = string(existing.checksum(1));
        if stored ~= "" && stored ~= policy.checksum_sha256
            error("vawlume:attribution:PolicyVersionConflict", ...
                "Policy %s version %s is already registered with a different " + ...
                "checksum. Publish a new profile_version rather than editing one.", ...
                policy.profile_key, policy.version_label);
        end
        return
    end
else
    profileId = attributionInsertRow(conn, "config_profiles", struct( ...
        project_id=policy.project_id, ...
        profile_key=policy.profile_key, ...
        profile_name=policy.profile_name, ...
        profile_kind=policy.profile_kind, ...
        description=policy.calibration_meaning), "profile_id");
    counts.config_profiles = counts.config_profiles + 1;
end

versionId = attributionInsertRow(conn, "config_profile_versions", struct( ...
    profile_id=profileId, ...
    version_label=policy.version_label, ...
    profile_schema_version=policy.profile_schema_version, ...
    content_format="json", ...
    content_uri=policy.content_uri, ...
    checksum_sha256=policy.checksum_sha256, ...
    is_snapshot=1), "profile_version_id");
counts.config_profile_versions = counts.config_profile_versions + 1;
end

function completed = completeRunWhenFullyDecided(conn, plan)
%COMPLETERUNWHENFULLYDECIDED Finish the run once every target has a decision.
%
% Completion freezes the EVIDENCE, not the decision set: candidates and evidence
% rows are refused after completion, while a further policy may still be applied
% to the frozen candidates. Comparing policies over one body of evidence is the
% point of keeping the layers apart, so completion must not foreclose it.
completed = 0;
undecided = fetch(conn, "SELECT COUNT(*) AS n FROM attribution_targets t " + ...
    "WHERE t.attribution_run_id=" + string(plan.run.attribution_run_id) + ...
    " AND NOT EXISTS (SELECT 1 FROM attribution_decisions d " + ...
    "  WHERE d.attribution_target_id = t.attribution_target_id)");
if double(undecided.n(1)) > 0
    return
end
execute(conn, "UPDATE attribution_runs SET status='complete' " + ...
    "WHERE attribution_run_id=" + string(plan.run.attribution_run_id) + ...
    " AND status='planned'");
execute(conn, "UPDATE analysis_runs SET status='completed' " + ...
    "WHERE analysis_run_id=" + string(plan.run.analysis_run_id) + ...
    " AND status='started'");
completed = 1;
end

function restoreAutoCommit(conn, previous)
try
    conn.AutoCommit = previous;
catch
    % Nothing further can be done here; the caller's rethrow carries the cause.
end
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
