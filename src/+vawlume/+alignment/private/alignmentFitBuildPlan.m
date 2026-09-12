function plan = alignmentFitBuildPlan(conn, alignmentRef, options)
%ALIGNMENTFITBUILDPLAN Resolve anchors and solve every fittable transform.
%
% Nothing here writes. Each pairwise run in the alignment set is resolved to its
% explicit logical anchors, solved if it is fit-ready, and classified create,
% reuse, or conflict against whatever is already stored.
%
% Anchor pairing is by **logical anchor identity only**. No nearest-time search,
% no pulse-order alignment, and no averaging of redundant observations happens
% anywhere in this file.

plan = struct();
plan.set = resolveAlignmentSet(conn, alignmentRef);
plan.options = options;
plan.runs = resolveRuns(conn, plan.set, options.SourceTimebase);
plan.anchors_without_transform = clocksWithAnchorsButNoTransform(conn, plan.set);
plan.conflicts = strings(0, 1);
plan.failures = strings(0, 1);

% A conflict is a disagreement with what is already stored, and blocks the
% whole apply because writing over it would rewrite history. A failure is one
% transform's own outcome: it is recorded on that transform and leaves the
% others alone, so one clock's missing evidence does not take a session down.
for index = 1:numel(plan.runs)
    plan.runs(index) = resolveRunFit(conn, plan.set, plan.runs(index), options);
    if strlength(plan.runs(index).conflict_message) > 0
        plan.conflicts(end + 1, 1) = plan.runs(index).conflict_message;
    end
    if strlength(plan.runs(index).failure_reason) > 0
        plan.failures(end + 1, 1) = plan.runs(index).failure_reason;
    end
end
plan.has_conflicts = ~isempty(plan.conflicts);
plan.has_failures = ~isempty(plan.failures);
end

% ------------------------------------------------------------------- scope ---

function value = resolveAlignmentSet(conn, alignmentRef)
hasId = isfield(alignmentRef, "alignment_set_id");
hasKey = isfield(alignmentRef, "run_key");
if hasId == hasKey
    error("vawlume:alignment:AlignmentRefInvalid", ...
        "alignmentRef must contain exactly one of alignment_set_id or run_key.");
end
if hasId
    predicate = "aset.alignment_set_id=" + string(scalarPositiveInteger( ...
        alignmentRef.alignment_set_id, "alignment_set_id"));
else
    predicate = "ar.run_key=" + sqlText(scalarText(alignmentRef.run_key, "run_key"));
    if isfield(alignmentRef, "project_key")
        predicate = predicate + " AND p.project_key=" + ...
            sqlText(scalarText(alignmentRef.project_key, "project_key"));
    end
end

rows = fetch(conn, "SELECT aset.alignment_set_id, aset.analysis_run_id, " + ...
    "aset.reference_timebase_id, aset.status, " + ...
    "IFNULL(aset.alignment_set_key,'') AS alignment_set_key, " + ...
    "ar.run_key, ar.project_id, ar.run_type, p.project_key, " + ...
    "tb.timebase_name AS reference_timebase_key " + ...
    "FROM alignment_sets aset " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=aset.analysis_run_id " + ...
    "JOIN projects p ON p.project_id=ar.project_id " + ...
    "JOIN timebases tb ON tb.timebase_id=aset.reference_timebase_id " + ...
    "WHERE " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:alignment:AlignmentSetNotFound", ...
        "No alignment set matches alignmentRef.");
end
if height(rows) ~= 1
    error("vawlume:alignment:AlignmentSetAmbiguous", ...
        "alignmentRef matched %d alignment sets; supply project_key or " + ...
        "alignment_set_id.", height(rows));
end
if presentText(rows.run_type(1)) ~= "temporal_alignment"
    error("vawlume:alignment:AlignmentRunTypeInvalid", ...
        "Fitting requires a temporal_alignment analysis run, not '%s'.", ...
        presentText(rows.run_type(1)));
end

value = struct( ...
    alignment_set_id=double(rows.alignment_set_id(1)), ...
    analysis_run_id=double(rows.analysis_run_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    project_key=presentText(rows.project_key(1)), ...
    run_key=presentText(rows.run_key(1)), ...
    alignment_set_key=presentText(rows.alignment_set_key(1)), ...
    reference_timebase_id=double(rows.reference_timebase_id(1)), ...
    reference_timebase_key=presentText(rows.reference_timebase_key(1)), ...
    status=presentText(rows.status(1)));
end

function value = resolveRuns(conn, set, sourceTimebase)
predicate = "";
if strlength(sourceTimebase) > 0
    predicate = " AND tb.timebase_name=" + sqlText(sourceTimebase);
end
rows = fetch(conn, "SELECT r.alignment_run_id, r.source_timebase_id, " + ...
    "r.target_timebase_id, r.method, r.status, tb.timebase_name AS source_timebase_key " + ...
    "FROM time_alignment_runs r " + ...
    "JOIN timebases tb ON tb.timebase_id=r.source_timebase_id " + ...
    "WHERE r.alignment_set_id=" + string(set.alignment_set_id) + predicate + ...
    " ORDER BY tb.timebase_name");
if isempty(rows) || height(rows) == 0
    if strlength(sourceTimebase) > 0
        error("vawlume:alignment:TransformRunNotFound", ...
            "Alignment set '%s' has no registered transform for source timebase '%s'.", ...
            set.run_key, sourceTimebase);
    end
    error("vawlume:alignment:NoTransformRuns", ...
        "Alignment set '%s' has no registered pairwise transform runs to fit.", ...
        set.run_key);
end

value = repmat(emptyRun(), height(rows), 1);
for index = 1:height(rows)
    run = emptyRun();
    run.alignment_run_id = double(rows.alignment_run_id(index));
    run.source_timebase_id = double(rows.source_timebase_id(index));
    run.source_timebase_key = presentText(rows.source_timebase_key(index));
    run.target_timebase_id = double(rows.target_timebase_id(index));
    run.reference_timebase_key = set.reference_timebase_key;
    run.method = presentText(rows.method(index));
    run.stored_status = presentText(rows.status(index));
    value(index) = run;
end
end

% ------------------------------------------------------------ anchor pairing ---

function run = resolveRunFit(conn, set, run, options)
%RESOLVERUNFIT Pair anchors by identity, solve, and classify against storage.
[run.anchors, run.unpaired_anchors] = resolveAnchorPairs(conn, set, run);
run.fit_anchor_count = nnz(run.anchors.included_in_fit == 1);
run.withheld_anchor_count = nnz(run.anchors.included_in_fit == 0);
run.stored_breakpoints = storedBreakpoints(conn, run);

if run.fit_anchor_count == 0
    run = markFailed(run, "InsufficientAnchors", ...
        "has no logical anchor with one included observation on both clocks");
    return
end

if run.method == "piecewise_affine"
    [run, ready] = resolveBreakpoints(run, options);
    if ~ready
        return
    end
end

included = run.anchors(run.anchors.included_in_fit == 1, :);
try
    if run.method == "piecewise_affine"
        run.fit = vawlume.alignment.solveTransform(run.method, ...
            included.observed_source_time, included.observed_reference_time, ...
            Breakpoints=run.breakpoints);
    else
        run.fit = vawlume.alignment.solveTransform(run.method, ...
            included.observed_source_time, included.observed_reference_time);
    end
catch exception
    run = markFailed(run, failureCodeOf(exception), ...
        "cannot be fitted: " + string(exception.message));
    return
end

run.segments = segmentEvidence(run.fit, included);
run.anchors = applyPredictions(run.anchors, run.segments);
run.scale = run.fit.scale;
run.offset_s = run.fit.offset_s;
run.rmse_s = run.fit.rmse_s;
run.max_abs_residual_s = run.fit.max_abs_residual_s;

% Diagnostics are computed from the fit that was already solved above. They
% describe it; they never feed back into it.
run.diagnostics = anchorDiagnostics(included);
influence = leaveOneOutInfluence(run.method, included.observed_source_time, ...
    included.observed_reference_time, run.fit, run.breakpoints);
includedRows = find(run.anchors.included_in_fit == 1);
run.anchors.loo_scale_delta(includedRows) = influence.scale_delta;
run.anchors.loo_offset_delta_s(includedRows) = influence.offset_delta_s;

run = classifyAgainstStorage(conn, run);
end

% ------------------------------------------------------------- breakpoints ---

function value = storedBreakpoints(conn, run)
%STOREDBREAKPOINTS The declared segmentation a transform already carries.
rows = fetch(conn, "SELECT source_time FROM alignment_run_breakpoints " + ...
    "WHERE alignment_run_id=" + string(run.alignment_run_id) + ...
    " ORDER BY breakpoint_index");
if isempty(rows) || height(rows) == 0
    value = double.empty(0, 1);
    return
end
value = double(rows.source_time);
value = value(:);
end

function [run, ready] = resolveBreakpoints(run, options)
%RESOLVEBREAKPOINTS Reconcile what is stored with what the caller declared.
%
% A declared breakpoint set is part of the model's identity, so a stored set and
% a different requested set are two alignments rather than one being corrected.
ready = false;
requested = options.Breakpoints(:);
restricted = strlength(options.SourceTimebase) > 0;

if ~isempty(requested) && ~restricted
    % Breakpoints are a claim about one clock. Applying one caller's set to
    % every piecewise transform in a set would attribute a drift regime to
    % clocks that never showed it.
    error("vawlume:alignment:BreakpointsInvalid", ...
        ['Breakpoints describe one source clock, so SourceTimebase must name ' ...
        'the transform they belong to.']);
end

if ~isempty(run.stored_breakpoints) && ~isempty(requested)
    if numel(requested) ~= numel(run.stored_breakpoints) || ...
            any(abs(sort(requested) - run.stored_breakpoints) > 0)
        run = markConflict(run, ...
            "already declares breakpoints [" + ...
            join(compose("%g", run.stored_breakpoints'), ", ") + ...
            "]. A different segmentation is a different alignment, not a " + ...
            "correction to this one");
        return
    end
end

if ~isempty(run.stored_breakpoints)
    run.breakpoints = run.stored_breakpoints;
elseif ~isempty(requested)
    run.breakpoints = sort(requested);
else
    run = markFailed(run, "BreakpointsRequired", ...
        ['declares method piecewise_affine but no breakpoints. VAWLUME does ' ...
        'not search for them: declare where the segments meet']);
    return
end
ready = true;
end

% -------------------------------------------------------- segment evidence ---

function value = segmentEvidence(fit, included)
%SEGMENTEVIDENCE Per-segment fit quality and the anchor-uncertainty bound.
%
% The bound is the largest recorded anchor uncertainty among the anchors that
% determined this segment, expressed on the reference clock. It is not a
% confidence interval, a standard error, or a probability, and the semantics
% string it is stored beside says so.
%
% Absence propagates as absence: a segment whose contributing anchors recorded no
% uncertainty carries NaN, never 0, which would claim perfect knowledge.
value = fit.segments;
count = height(value);
value.rmse_s = nan(count, 1);
value.uncertainty_s = nan(count, 1);

index = fit.segment_index(:);
sourceUncertainty = double(included.source_uncertainty_s);
referenceUncertainty = double(included.reference_uncertainty_s);
residual = fit.residual_s(:);

for segment = 1:count
    rows = index == segment;
    if ~any(rows)
        continue
    end
    value.rmse_s(segment) = sqrt(mean(residual(rows) .^ 2));
    % A source-clock uncertainty is a duration on the source clock; scale is
    % exactly the factor that expresses it on the reference clock.
    bounds = [value.scale(segment) * sourceUncertainty(rows); ...
        referenceUncertainty(rows)];
    bounds = bounds(~isnan(bounds));
    if ~isempty(bounds)
        value.uncertainty_s(segment) = max(bounds);
    end
end
end

% ----------------------------------------------------------------- outcome ---

function run = markFailed(run, code, detail)
%MARKFAILED A transform that was attempted and could not be honoured.
%
% Distinct from a conflict. A failure is this transform's own outcome and is
% recorded on it; a conflict is a disagreement with what is already stored and
% blocks the whole apply, because writing over it would rewrite history.
run.action = "not_fit_ready";
run.failure_code = code;
run.failure_reason = "Transform for source timebase '" + ...
    run.source_timebase_key + "' " + detail + ".";
end

function run = markConflict(run, detail)
run.action = "conflict";
run.conflict_message = "Transform for source timebase '" + ...
    run.source_timebase_key + "' " + detail + ".";
end

function value = failureCodeOf(exception)
value = string(exception.identifier);
if startsWith(value, "vawlume:alignment:")
    value = extractAfter(value, "vawlume:alignment:");
end
end

function [value, unpaired] = resolveAnchorPairs(conn, set, run)
%RESOLVEANCHORPAIRS One row per logical anchor that pairs unambiguously.
%
% An anchor contributes to the fit only when exactly one observation on each
% clock is marked included. The schema's partial unique index already forbids two
% included observations on one clock for one anchor, so ambiguity here can only
% mean too few, never too many.
%
% An anchor whose observations exist but are not included is still evaluated when
% the pairing is unambiguous — a held-out validation anchor should be able to
% show its residual without influencing the coefficients.
%
% An anchor that cannot be paired at all is returned separately rather than
% skipped in silence, so a reader can see which evidence the fit never saw.
value = emptyAnchorTable();
unpaired = emptyUnpairedTable();
anchors = fetch(conn, "SELECT alignment_anchor_id, anchor_key, " + ...
    "IFNULL(anchor_type,'') AS anchor_type " + ...
    "FROM alignment_anchors WHERE alignment_set_id=" + ...
    string(set.alignment_set_id) + " ORDER BY anchor_key");
for index = 1:height(anchors)
    anchorId = double(anchors.alignment_anchor_id(index));
    anchorKey = presentText(anchors.anchor_key(index));
    source = observationsOn(conn, anchorId, run.source_timebase_id);
    reference = observationsOn(conn, anchorId, run.target_timebase_id);

    [sourceRow, sourceReason] = selectObservation(source, "source");
    [referenceRow, referenceReason] = selectObservation(reference, "reference");
    if isempty(sourceRow) || isempty(referenceRow)
        reason = strtrim(sourceReason + " " + referenceReason);
        if strlength(reason) == 0
            reason = "anchor is not observed on both clocks";
        end
        unpaired(end + 1, :) = {anchorKey, anchorId, height(source), ...
            height(reference), reason}; %#ok<AGROW>
        continue
    end

    included = double(sourceRow.included_in_fit == 1 && referenceRow.included_in_fit == 1);
    reason = "";
    if included == 0
        reason = strtrim(sourceReason + " " + referenceReason);
        if strlength(reason) == 0
            reason = "observation excluded from fit";
        end
    end
    sourceSpread = dispersionOf(source, sourceRow.anchor_observation_id);
    referenceSpread = dispersionOf(reference, referenceRow.anchor_observation_id);
    value(end + 1, :) = {anchorKey, anchorId, ...
        sourceRow.anchor_observation_id, referenceRow.anchor_observation_id, ...
        sourceRow.observed_time_native, referenceRow.observed_time_native, ...
        NaN, NaN, included, sourceRow.observation_role, ...
        referenceRow.observation_role, reason, ...
        sourceRow.uncertainty_s, referenceRow.uncertainty_s, ...
        height(source), height(reference), ...
        sourceSpread.spread_s, referenceSpread.spread_s, ...
        sourceSpread.max_deviation_s, referenceSpread.max_deviation_s, ...
        NaN, NaN}; %#ok<AGROW>
end
end

function value = observationsOn(conn, anchorId, timebaseId)
value = fetch(conn, "SELECT anchor_observation_id, observed_time_native, " + ...
    "observation_role, included_in_fit, " + ...
    "IFNULL(uncertainty_s, -1) AS uncertainty_s " + ...
    "FROM alignment_anchor_observations WHERE alignment_anchor_id=" + ...
    string(anchorId) + " AND timebase_id=" + string(timebaseId) + ...
    " ORDER BY anchor_observation_id");
end

function [row, reason] = selectObservation(observations, side)
%SELECTOBSERVATION The one included reading, or the one reading, or nothing.
%
% Redundant replicates are preserved in the database and simply are not selected.
% Nothing here averages them or picks by row order.
row = [];
reason = "";
if height(observations) == 0
    return
end
included = observations(double(observations.included_in_fit) == 1, :);
if height(included) == 1
    row = observationStruct(included);
    return
end
if height(included) > 1
    % The schema's partial unique index should make this unreachable.
    error("vawlume:alignment:AnchorObservationAmbiguous", ...
        "An anchor carries %d included %s observations on one timebase.", ...
        height(included), side);
end
if height(observations) == 1
    row = observationStruct(observations);
    reason = side + " observation is excluded from the fit;";
    return
end
% Several observations, none included: which one is meant is genuinely unknown.
reason = side + " observation selection is unresolved;";
end

function value = observationStruct(rows)
uncertainty = double(rows.uncertainty_s(1));
if uncertainty < 0
    uncertainty = NaN;
end
value = struct( ...
    anchor_observation_id=double(rows.anchor_observation_id(1)), ...
    observed_time_native=double(rows.observed_time_native(1)), ...
    observation_role=presentText(rows.observation_role(1)), ...
    included_in_fit=double(rows.included_in_fit(1)), ...
    uncertainty_s=uncertainty);
end

function value = applyPredictions(value, segments)
%APPLYPREDICTIONS Evaluate the fitted segmentation at every paired anchor.
%
% Withheld anchors are predicted too, so a held-out reading still receives a
% residual against the transform it did not help produce. The shared segment
% evaluator is used rather than a local formula, so the fitter and the applier
% cannot disagree about which segment owns a boundary instant.
predicted = vawlume.alignment.internal.evaluateSegments(segments, value.observed_source_time);
value.predicted_reference_time = predicted;
value.residual_s = value.observed_reference_time - predicted;
end

% ------------------------------------------------------------- anchor QC ---

function value = dispersionOf(observations, selectedId)
%DISPERSIONOF Spread across redundant readings of one anchor on one clock.
%
% Derived, never stored. Spread is a pure function of
% alignment_anchor_observations, which is the authority for those rows;
% persisting it would create a second place to look for the same number and a
% second thing to keep current when an observation is added or re-included.
%
% An anchor read once has no dispersion. That is an absence, not a zero, so it
% is reported as NaN rather than as agreement between one reading and itself.
%
% None of this reaches the design matrix. A replicate is evidence about how
% consistently a marker was read, never an extra statistical anchor.
value = struct(spread_s=NaN, max_deviation_s=NaN);
if height(observations) < 2
    return
end
times = double(observations.observed_time_native);
value.spread_s = max(times) - min(times);
if isnan(selectedId)
    return
end
selected = times(double(observations.anchor_observation_id) == selectedId);
if isempty(selected)
    return
end
value.max_deviation_s = max(abs(times - selected(1)));
end

function value = leaveOneOutInfluence(method, sourceTimes, referenceTimes, fit, knots)
%LEAVEONEOUTINFLUENCE How far the coefficients move when one anchor is dropped.
%
% Reported, never acted on. This says how much a fit leans on one reading; it
% does not decide that an anchor is bad, and nothing here excludes anything.
% Exclusion stays a declared decision recorded on the observation.
%
% It mixes two things a reader must not conflate: how far a reading sits from
% the model, and how much leverage its position gives it. An anchor at the end
% of a session moves a slope more than one in the middle does, however well it
% was read. A large delta therefore means this reading matters to the answer,
% not that it is wrong.
%
% An anchor whose removal leaves too few readings to determine the model has no
% influence number, because the counterfactual fit does not exist.
count = numel(sourceTimes);
value = struct(scale_delta=nan(count, 1), offset_delta_s=nan(count, 1));
if count < 2
    return
end
for index = 1:count
    keep = true(count, 1);
    keep(index) = false;
    try
        if method == "piecewise_affine"
            reduced = vawlume.alignment.solveTransform(method, ...
                sourceTimes(keep), referenceTimes(keep), Breakpoints=knots);
        else
            reduced = vawlume.alignment.solveTransform(method, ...
                sourceTimes(keep), referenceTimes(keep));
        end
    catch
        continue
    end
    % A piecewise transform has no single slope, so influence is reported
    % against the segment the dropped anchor belonged to.
    segment = fit.segment_index(index);
    value.scale_delta(index) = reduced.segments.scale(segment) - ...
        fit.segments.scale(segment);
    value.offset_delta_s(index) = reduced.segments.offset_s(segment) - ...
        fit.segments.offset_s(segment);
end
end

function value = anchorDiagnostics(included)
%ANCHORDIAGNOSTICS Whether the anchors could support the model asked of them.
%
% Every number here is reported for a reader to judge. None is a threshold, a
% grade, or a verdict: this prototype ships no calibrated acceptance criterion,
% and residual size is reported, never judged.
%
% The distribution measures matter because anchors clustered at one end of a
% session support an offset far better than a slope, and a fit summary alone
% cannot show that.
value = emptyDiagnostics();
times = sort(double(included.observed_source_time));
value.included_anchor_count = numel(times);
if isempty(times)
    return
end
value.source_range_start = times(1);
value.source_range_end = times(end);
value.source_span_s = times(end) - times(1);
if numel(times) < 2 || value.source_span_s <= 0
    return
end
% Largest gap between consecutive anchors, as a fraction of the span. A value
% near 1 means the anchors sit in two clumps with nothing between them.
value.largest_gap_fraction = max(diff(times)) / value.source_span_s;
% Where the anchors sit within their own span: 0 is balanced, +/-0.5 means every
% anchor is bunched at one end.
midpoint = (times(1) + times(end)) / 2;
value.centroid_offset_fraction = (mean(times) - midpoint) / value.source_span_s;
end

function value = emptyDiagnostics()
value = struct(included_anchor_count=0, source_range_start=NaN, ...
    source_range_end=NaN, source_span_s=NaN, largest_gap_fraction=NaN, ...
    centroid_offset_fraction=NaN);
end

function value = emptyUnpairedTable()
%EMPTYUNPAIREDTABLE Anchors the fitter could not pair, and why.
%
% Previously these were skipped silently. An anchor read on only one clock, or
% read several times with none included, is a real gap in the evidence, and a
% reader who cannot see it happened cannot act on it.
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), ...
    VariableNames=["anchor_key", "alignment_anchor_id", ...
    "source_observation_count", "reference_observation_count", "reason"]);
end

function value = clocksWithAnchorsButNoTransform(conn, set)
%CLOCKSWITHANCHORSBUTNOTRANSFORM Observations nothing in this set can use.
%
% Reported rather than raised. It is legal for a set to carry readings on a
% clock it does not align - a clock may be registered before its transform is -
% but it is equally often a manifest that named a stream and forgot its
% transform, and the two look identical from the database.
%
% The set's reference clock is excluded: every anchor is read on it by
% definition, and it is the one clock that needs no transform of its own.
value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    VariableNames=["timebase_id", "timebase_key", "observation_count"]);
rows = fetch(conn, "SELECT o.timebase_id, tb.timebase_name AS timebase_key, " + ...
    "COUNT(*) AS observation_count " + ...
    "FROM alignment_anchor_observations o " + ...
    "JOIN alignment_anchors a ON a.alignment_anchor_id=o.alignment_anchor_id " + ...
    "JOIN timebases tb ON tb.timebase_id=o.timebase_id " + ...
    "WHERE a.alignment_set_id=" + string(set.alignment_set_id) + ...
    " AND o.timebase_id <> " + string(set.reference_timebase_id) + ...
    " AND o.timebase_id NOT IN (SELECT source_timebase_id FROM time_alignment_runs " + ...
    "WHERE alignment_set_id=" + string(set.alignment_set_id) + ") " + ...
    "GROUP BY o.timebase_id, tb.timebase_name ORDER BY tb.timebase_name");
for index = 1:height(rows)
    value(end + 1, :) = {double(rows.timebase_id(index)), ...
        presentText(rows.timebase_key(index)), ...
        double(rows.observation_count(index))}; %#ok<AGROW>
end
end

% ------------------------------------------------------- storage comparison ---

function run = classifyAgainstStorage(conn, run)
%CLASSIFYAGAINSTSTORAGE A completed fit is never rewritten in place.
stored = fetch(conn, "SELECT segment_index, " + ...
    "IFNULL(source_start, 1e308) AS source_start, " + ...
    "IFNULL(source_end, 1e308) AS source_end, scale, offset_s " + ...
    "FROM alignment_segments WHERE alignment_run_id=" + ...
    string(run.alignment_run_id) + " ORDER BY segment_index");
if height(stored) == 0
    if run.stored_status == "registered"
        run.action = "create";
    else
        run = markConflict(run, "has status '" + run.stored_status + ...
            "' but stores no segment; refitting would invent a history");
    end
    return
end

if height(stored) ~= height(run.segments)
    run = markConflict(run, "stores " + string(height(stored)) + ...
        " segments and this fit produces " + string(height(run.segments)) + ...
        ". A different segmentation is a different alignment identity");
    return
end

for index = 1:height(stored)
    if ~agrees(double(stored.scale(index)), run.segments.scale(index)) || ...
            ~agrees(double(stored.offset_s(index)), run.segments.offset_s(index)) || ...
            ~boundAgrees(double(stored.source_start(index)), run.segments.source_start(index)) || ...
            ~boundAgrees(double(stored.source_end(index)), run.segments.source_end(index))
        run = markConflict(run, "is already fitted with segment " + ...
            string(index) + " at scale " + string(double(stored.scale(index))) + ...
            " and offset " + string(double(stored.offset_s(index))) + ...
            " s. A different result means different inputs or a different " + ...
            "method, which needs a new alignment identity rather than an overwrite");
        return
    end
end
run.action = "reuse";
end

function value = agrees(stored, computed)
value = abs(stored - computed) <= 1e-12 * max(1, abs(computed));
end

function value = boundAgrees(stored, computed)
%BOUNDAGREES An open bound reads back as the sentinel this query substitutes.
%
% SQL NULL cannot be fetched into a double column through the Database Toolbox
% without the IFNULL above, so an open bound arrives as 1e308. Comparing that to
% NaN directly would report disagreement on every well-formed open segment.
storedOpen = stored >= 1e307;
computedOpen = isnan(computed);
if storedOpen || computedOpen
    value = storedOpen && computedOpen;
    return
end
value = agrees(stored, computed);
end

% ---------------------------------------------------------------- plumbing ---

function value = emptyRun()
value = struct(alignment_run_id=NaN, source_timebase_id=NaN, ...
    source_timebase_key="", target_timebase_id=NaN, reference_timebase_key="", ...
    method="", stored_status="", anchors=emptyAnchorTable(), ...
    unpaired_anchors=emptyUnpairedTable(), diagnostics=emptyDiagnostics(), ...
    fit=struct(), fit_anchor_count=0, withheld_anchor_count=0, scale=NaN, ...
    offset_s=NaN, rmse_s=NaN, max_abs_residual_s=NaN, action="create", ...
    breakpoints=double.empty(0, 1), stored_breakpoints=double.empty(0, 1), ...
    segments=emptySegmentTable(), ...
    failure_code="", failure_reason="", conflict_message="");
end

function value = emptySegmentTable()
value = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["segment_index", "source_start", "source_end", "scale", ...
    "offset_s", "anchor_count", "rmse_s", "uncertainty_s"]);
end

function value = emptyAnchorTable()
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["anchor_key", "alignment_anchor_id", ...
    "source_observation_id", "reference_observation_id", ...
    "observed_source_time", "observed_reference_time", ...
    "predicted_reference_time", "residual_s", "included_in_fit", ...
    "source_role", "reference_role", "exclusion_reason", ...
    "source_uncertainty_s", "reference_uncertainty_s", ...
    "source_observation_count", "reference_observation_count", ...
    "source_spread_s", "reference_spread_s", ...
    "source_max_deviation_s", "reference_max_deviation_s", ...
    "loo_scale_delta", "loo_offset_delta_s"]);
end

function value = scalarPositiveInteger(value, name)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        fix(value) ~= value || value <= 0
    error("vawlume:alignment:AlignmentRefInvalid", ...
        "%s must be a positive scalar integer.", name);
end
value = double(value);
end

function value = scalarText(value, name)
try
    value = string(value);
catch
    value = strings(0, 1);
end
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:alignment:AlignmentRefInvalid", ...
        "%s must be a nonempty scalar text value.", name);
end
value = strtrim(value);
end

function value = presentText(value)
value = string(value);
value(ismissing(value)) = "";
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
