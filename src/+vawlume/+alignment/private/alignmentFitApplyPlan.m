function [plan, counts] = alignmentFitApplyPlan(conn, plan)
%ALIGNMENTFITAPPLYPLAN Persist transforms and residual evidence.
%
% Inserted rows — segments, breakpoints and residuals — are written under one
% transaction and roll back together. A partial write would leave a run claiming
% a fit while only some of its anchors could account for it.
%
% **Status updates are not covered by that transaction.** Under the MATLAB
% sqlite interface an UPDATE issued through `execute` runs outside the
% AutoCommit transaction that `sqlwrite` opens: it takes effect immediately and
% a later rollback does not undo it. Every write here is therefore ordered so
% that the rows a status claims exist are inserted before the status is set,
% which makes the failure mode a run that is still `registered` beside rows that
% describe it, rather than a run claiming a fit that was rolled back.
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
    for index = 1:numel(plan.runs)
        counts.reused_alignment_segments = counts.reused_alignment_segments + ...
            height(plan.runs(index).segments);
    end
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
            counts.reused_alignment_segments = counts.reused_alignment_segments + ...
                height(run.segments);
            continue
        end
        if run.action == "not_fit_ready"
            counts = applyFailure(conn, run, counts);
            continue
        end
        counts = applyBreakpoints(conn, run, counts);
        counts = applySegments(conn, run, counts);
        counts = applyResiduals(conn, run, counts);
        counts = applyRunSummary(conn, run, counts);
    end
    counts = applySetStatus(conn, plan, counts);
    if insertedRows(counts) > 0
        commit(conn);
    end
catch exception
    try
        if insertedRows(counts) > 0
            rollback(conn);
        end
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
plan.status = "committed";
end

% --------------------------------------------------------------- segments ---

function counts = applyBreakpoints(conn, run, counts)
%APPLYBREAKPOINTS Persist the declared segmentation as part of the model.
%
% Without this the fit would not be reconstructable from the database: the same
% anchors under a different breakpoint set give a different answer, so the set
% is part of what produced the coefficients.
if isempty(run.breakpoints)
    return
end
for index = 1:numel(run.breakpoints)
    alignmentInsertRow(conn, "alignment_run_breakpoints", struct( ...
        alignment_run_id=run.alignment_run_id, ...
        breakpoint_index=index, ...
        source_time=run.breakpoints(index), ...
        declared_by="caller"), "alignment_run_breakpoint_id");
    counts.alignment_run_breakpoints = counts.alignment_run_breakpoints + 1;
end
end

function counts = applySegments(conn, run, counts)
%APPLYSEGMENTS One row per segment, refusing any set that does not tile.
%
% An offset or affine fit writes one segment open at both ends, because it
% applies over the whole clock rather than over an estimated interval.
vawlume.alignment.internal.assertSegmentsTile(run.segments, run.source_timebase_key);
for index = 1:height(run.segments)
    segment = run.segments(index, :);
    values = struct( ...
        alignment_run_id=run.alignment_run_id, ...
        segment_index=segment.segment_index, ...
        scale=segment.scale, ...
        offset_s=segment.offset_s, ...
        rmse_s=segment.rmse_s);
    if ~isnan(segment.source_start)
        values.source_start = segment.source_start;
    end
    if ~isnan(segment.source_end)
        values.source_end = segment.source_end;
    end
    if ~isnan(segment.uncertainty_s)
        values.uncertainty_s = segment.uncertainty_s;
        values.uncertainty_semantics = "max_contributing_anchor_uncertainty_s";
    end
    alignmentInsertRow(conn, "alignment_segments", values, "alignment_segment_id");
    counts.alignment_segments = counts.alignment_segments + 1;
end
end

function counts = applyFailure(conn, run, counts)
%APPLYFAILURE Record that this transform was attempted and could not be fitted.
%
% Without this a run that was tried and could not be honoured is
% indistinguishable from one nobody attempted: both would sit at 'registered'
% with no segments.
execute(conn, "UPDATE time_alignment_runs SET status='failed', " + ...
    "failure_code=" + sqlText(run.failure_code) + ", " + ...
    "failure_reason=" + sqlText(run.failure_reason) + " " + ...
    "WHERE alignment_run_id=" + string(run.alignment_run_id));
counts.alignment_runs_failed = counts.alignment_runs_failed + 1;
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
%
% A set holding a failed transform is not fitted either. Saying otherwise would
% let a partial outcome read as a complete one, which is the distinction the
% status vocabulary exists to keep.
remaining = fetch(conn, "SELECT COUNT(*) AS n FROM time_alignment_runs " + ...
    "WHERE alignment_set_id=" + string(plan.set.alignment_set_id) + ...
    " AND status<>'estimated' AND status<>'validated'");
if double(remaining.n(1)) > 0
    return
end
execute(conn, "UPDATE alignment_sets SET status='fitted' " + ...
    "WHERE alignment_set_id=" + string(plan.set.alignment_set_id) + ...
    " AND status='draft'");
counts.alignment_sets_fitted = 1;
end

% ---------------------------------------------------------------- plumbing ---

function value = insertedRows(counts)
%INSERTEDROWS How many rows were written through the transactional path.
%
% Only inserts open the driver's transaction. An apply that recorded nothing but
% failures issued no insert, so there is no transaction to commit and asking for
% one raises 'Attempted to commit transaction when none was in progress'.
value = counts.alignment_segments + counts.alignment_run_breakpoints + ...
    counts.alignment_anchor_residuals;
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end

function value = numberLiteral(value)
if isnan(value)
    value = "NULL";
    return
end
value = string(sprintf("%.17g", value));
end

function counts = emptyCounts()
counts = struct(alignment_segments=0, alignment_run_breakpoints=0, ...
    alignment_anchor_residuals=0, alignment_runs_estimated=0, ...
    alignment_runs_failed=0, alignment_sets_fitted=0, ...
    reused_alignment_runs=0, reused_alignment_segments=0);
end
