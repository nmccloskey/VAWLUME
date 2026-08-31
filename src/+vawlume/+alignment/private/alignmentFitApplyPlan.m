function [plan, counts] = alignmentFitApplyPlan(conn, plan)
%ALIGNMENTFITAPPLYPLAN Persist transforms and residual evidence atomically.
%
% Every segment, residual, run summary, and set status commits together or not at
% all. A partial write would leave a run claiming a fit while only some of its
% anchors could account for it.
%
% Status becomes 'estimated', never 'validated'. A fit that solves is a fit that
% solves; calling it validated would assert an accuracy claim no calibrated
% threshold exists to support.

if plan.has_conflicts
    error("vawlume:alignment:FitPlanConflict", ...
        "An alignment fit plan with conflicts cannot be applied.");
end
counts = emptyCounts();
if all([plan.runs.action] == "reuse")
    counts.reused_alignment_runs = numel(plan.runs);
    counts.reused_alignment_segments = numel(plan.runs);
    plan.status = "reused";
    return
end

oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:alignment:TransactionState", ...
        "Alignment fit apply requires a connection with AutoCommit enabled.");
end
conn.AutoCommit = "off";
try
    for index = 1:numel(plan.runs)
        run = plan.runs(index);
        if run.action == "reuse"
            counts.reused_alignment_runs = counts.reused_alignment_runs + 1;
            counts.reused_alignment_segments = counts.reused_alignment_segments + 1;
            continue
        end
        counts = applySegment(conn, run, counts);
        counts = applyResiduals(conn, run, counts);
        counts = applyRunSummary(conn, run, counts);
    end
    counts = applySetStatus(conn, plan, counts);
    commit(conn);
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
plan.status = "committed";
end

% --------------------------------------------------------------- segments ---

function counts = applySegment(conn, run, counts)
%APPLYSEGMENT One global segment. Its bounds stay NULL because the fit applies
% over the whole clock, not over an estimated interval.
alignmentInsertRow(conn, "alignment_segments", struct( ...
    alignment_run_id=run.alignment_run_id, ...
    segment_index=1, ...
    scale=run.scale, ...
    offset_s=run.offset_s, ...
    rmse_s=run.rmse_s), "alignment_segment_id");
counts.alignment_segments = counts.alignment_segments + 1;
end

function counts = applyResiduals(conn, run, counts)
for index = 1:height(run.anchors)
    row = run.anchors(index, :);
    values = struct( ...
        alignment_run_id=run.alignment_run_id, ...
        alignment_anchor_id=row.alignment_anchor_id, ...
        source_observation_id=row.source_observation_id, ...
        reference_observation_id=row.reference_observation_id, ...
        observed_source_time=row.observed_source_time, ...
        observed_reference_time=row.observed_reference_time, ...
        predicted_reference_time=row.predicted_reference_time, ...
        residual_s=row.residual_s, ...
        included_in_fit=row.included_in_fit);
    if row.included_in_fit == 0
        values.exclusion_reason = exclusionReason(row);
        values.notes = "Residual evaluated but withheld from the fit.";
    end
    alignmentInsertRow(conn, "alignment_anchor_residuals", values, ...
        "alignment_anchor_residual_id");
    counts.alignment_anchor_residuals = counts.alignment_anchor_residuals + 1;
end
end

function value = exclusionReason(row)
value = string(row.exclusion_reason);
if ismissing(value) || strlength(strtrim(value)) == 0
    value = "observation excluded from fit";
end
end

function counts = applyRunSummary(conn, run, counts)
execute(conn, "UPDATE time_alignment_runs SET " + ...
    "n_anchors_used=" + string(run.fit_anchor_count) + ", " + ...
    "fit_rmse_s=" + numberLiteral(run.rmse_s) + ", " + ...
    "max_error_s=" + numberLiteral(run.max_abs_residual_s) + ", " + ...
    "status='estimated' " + ...
    "WHERE alignment_run_id=" + string(run.alignment_run_id));
counts.alignment_runs_estimated = counts.alignment_runs_estimated + 1;
end

function counts = applySetStatus(conn, plan, counts)
%APPLYSETSTATUS The set is 'fitted' only when every one of its runs is.
%
% 'validated' is deliberately not reachable from here. It would need a calibrated
% acceptance rule, and none exists.
remaining = fetch(conn, "SELECT COUNT(*) AS n FROM time_alignment_runs " + ...
    "WHERE alignment_set_id=" + string(plan.set.alignment_set_id) + ...
    " AND status='registered'");
if double(remaining.n(1)) > 0
    return
end
execute(conn, "UPDATE alignment_sets SET status='fitted' " + ...
    "WHERE alignment_set_id=" + string(plan.set.alignment_set_id) + ...
    " AND status='draft'");
counts.alignment_sets_fitted = 1;
end

% ---------------------------------------------------------------- plumbing ---

function value = numberLiteral(value)
if isnan(value)
    value = "NULL";
    return
end
value = string(sprintf("%.17g", value));
end

function counts = emptyCounts()
counts = struct(alignment_segments=0, alignment_anchor_residuals=0, ...
    alignment_runs_estimated=0, alignment_sets_fitted=0, ...
    reused_alignment_runs=0, reused_alignment_segments=0);
end
