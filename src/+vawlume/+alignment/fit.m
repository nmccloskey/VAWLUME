function result = fit(conn, alignmentRef, options)
%FIT Estimate and persist source-to-reference transforms for one alignment set.
%
% RESULT = vawlume.alignment.fit(CONN, ALIGNMENTREF) resolves each registered
% pairwise transform in an alignment set, pairs its logical anchors, solves the
% declared offset or affine model, and returns the coefficients with per-anchor
% residuals. Planning is the default and writes nothing.
%
% RESULT = vawlume.alignment.fit(..., Apply=true) persists one segment per run,
% one residual row per evaluated anchor, and the run and set fit summaries in a
% single transaction.
%
% ALIGNMENTREF selects exactly one alignment set:
%
%   struct(alignment_set_id=3)
%   struct(run_key="synthetic_session_01_alignment")
%   struct(project_key="...", run_key="...")
%
% Anchors are paired by **logical anchor identity**. An anchor contributes to a
% fit only when exactly one observation on the source clock and exactly one on
% the reference clock are marked included. Redundant replicate observations are
% left where they are: nothing here averages them, picks one by row order, or
% searches for the nearest timestamp.
%
% An anchor that pairs unambiguously but is withheld from the fit still receives
% a residual, marked `included_in_fit = 0` with a reason, so a held-out anchor can
% be inspected without having influenced the coefficients.
%
% A successful fit sets the run's status to **estimated**, never to `validated`.
% Solving is not validating, and this prototype ships no calibrated acceptance
% threshold that could justify the stronger word. The alignment set becomes
% `fitted` once none of its runs is still `registered`.
%
% Anchor `uncertainty_s` is carried through to the result but is **not** used as a
% weight. The fit is unweighted ordinary least squares; introducing weights would
% be a different estimator, and this prototype has no basis for choosing one.
%
% A completed transform is never rewritten in place. Refitting identical inputs
% reuses the stored result; a different result is a conflict that needs a new
% alignment identity.
%
% Name-value options:
%   Apply           persist a conflict-free plan (default false)
%   SourceTimebase  restrict to one source clock by its timebase key
%   Breakpoints     declared source-clock times where a piecewise transform
%                   changes regime. SourceTimebase must name the transform they
%                   belong to, because a breakpoint is a claim about one clock.
%
% A piecewise_affine transform needs breakpoints and VAWLUME does not search for
% them. Apply persists the declared set, so a later fit reuses it without
% restatement and the coefficients stay reconstructable from the database alone.
% Declaring a different set against a fitted transform is a conflict, not a
% correction: the same anchors under a different segmentation are a different
% alignment.
%
% A transform that was attempted and could not be honoured is recorded as
% `failed` with a code and a reason, and does not block the others. That is
% distinct from a conflict, which disagrees with what is already stored and
% blocks the whole apply.

arguments
    conn
    alignmentRef (1,1) struct
    options.Apply (1,1) logical = false
    options.SourceTimebase (1,1) string = ""
    options.Breakpoints double = double.empty(0, 1)
end

plan = alignmentFitBuildPlan(conn, alignmentRef, options);

if options.Apply && ~plan.has_conflicts
    [plan, appliedCounts] = alignmentFitApplyPlan(conn, plan);
    result = alignmentFitResult(plan);
    result.status = plan.status;
    result.committed = true;
    result.applied_counts = appliedCounts;
    return
end

result = alignmentFitResult(plan);
end
