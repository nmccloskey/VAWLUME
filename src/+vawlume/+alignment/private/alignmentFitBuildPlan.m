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
plan.conflicts = strings(0, 1);

for index = 1:numel(plan.runs)
    plan.runs(index) = resolveRunFit(conn, plan.set, plan.runs(index));
    if strlength(plan.runs(index).conflict_message) > 0
        plan.conflicts(end + 1, 1) = plan.runs(index).conflict_message;
    end
end
plan.has_conflicts = ~isempty(plan.conflicts);
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

function run = resolveRunFit(conn, set, run)
%RESOLVERUNFIT Pair anchors by identity, solve, and classify against storage.
run.anchors = resolveAnchorPairs(conn, set, run);
run.fit_anchor_count = nnz(run.anchors.included_in_fit == 1);

if run.method == "piecewise_affine"
    run.action = "unsupported";
    run.conflict_message = "Transform for source timebase '" + ...
        run.source_timebase_key + "' declares method 'piecewise_affine', " + ...
        "which this prototype does not fit.";
    return
end

if run.fit_anchor_count == 0
    run.action = "not_fit_ready";
    run.conflict_message = "Transform for source timebase '" + ...
        run.source_timebase_key + "' has no logical anchor with one included " + ...
        "observation on both clocks.";
    return
end

included = run.anchors(run.anchors.included_in_fit == 1, :);
try
    run.fit = vawlume.alignment.solveTransform(run.method, ...
        included.observed_source_time, included.observed_reference_time);
catch exception
    run.action = "not_fit_ready";
    run.conflict_message = "Transform for source timebase '" + ...
        run.source_timebase_key + "' cannot be fitted: " + string(exception.message);
    return
end

run.anchors = applyPredictions(run.anchors, run.fit);
run.scale = run.fit.scale;
run.offset_s = run.fit.offset_s;
run.rmse_s = run.fit.rmse_s;
run.max_abs_residual_s = run.fit.max_abs_residual_s;
run = classifyAgainstStorage(conn, run);
end

function value = resolveAnchorPairs(conn, set, run)
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
value = emptyAnchorTable();
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
    value(end + 1, :) = {anchorKey, anchorId, ...
        sourceRow.anchor_observation_id, referenceRow.anchor_observation_id, ...
        sourceRow.observed_time_native, referenceRow.observed_time_native, ...
        NaN, NaN, included, sourceRow.observation_role, ...
        referenceRow.observation_role, reason, ...
        sourceRow.uncertainty_s, referenceRow.uncertainty_s, ...
        height(source), height(reference)}; %#ok<AGROW>
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

function value = applyPredictions(value, fit)
predicted = fit.scale * value.observed_source_time + fit.offset_s;
value.predicted_reference_time = predicted;
value.residual_s = value.observed_reference_time - predicted;
end

% ------------------------------------------------------- storage comparison ---

function run = classifyAgainstStorage(conn, run)
%CLASSIFYAGAINSTSTORAGE A completed fit is never rewritten in place.
segments = fetch(conn, "SELECT segment_index, scale, offset_s, " + ...
    "IFNULL(rmse_s,-1) AS rmse_s FROM alignment_segments " + ...
    "WHERE alignment_run_id=" + string(run.alignment_run_id) + ...
    " ORDER BY segment_index");
if height(segments) == 0
    if run.stored_status == "registered"
        run.action = "create";
    else
        run.action = "conflict";
        run.conflict_message = "Transform for source timebase '" + ...
            run.source_timebase_key + "' has status '" + run.stored_status + ...
            "' but stores no segment; refitting would invent a history.";
    end
    return
end
if height(segments) > 1
    run.action = "conflict";
    run.conflict_message = "Transform for source timebase '" + ...
        run.source_timebase_key + "' stores " + string(height(segments)) + ...
        " segments; piecewise transforms are not fitted or refitted here.";
    return
end

storedScale = double(segments.scale(1));
storedOffset = double(segments.offset_s(1));
if agrees(storedScale, run.scale) && agrees(storedOffset, run.offset_s)
    run.action = "reuse";
    return
end
run.action = "conflict";
run.conflict_message = "Transform for source timebase '" + ...
    run.source_timebase_key + "' is already fitted with scale " + ...
    string(storedScale) + " and offset " + string(storedOffset) + ...
    " s. A different result means different inputs or a different method, " + ...
    "which needs a new alignment identity rather than an overwrite.";
end

function value = agrees(stored, computed)
value = abs(stored - computed) <= 1e-12 * max(1, abs(computed));
end

% ---------------------------------------------------------------- plumbing ---

function value = emptyRun()
value = struct(alignment_run_id=NaN, source_timebase_id=NaN, ...
    source_timebase_key="", target_timebase_id=NaN, reference_timebase_key="", ...
    method="", stored_status="", anchors=emptyAnchorTable(), ...
    fit=struct(), fit_anchor_count=0, scale=NaN, offset_s=NaN, rmse_s=NaN, ...
    max_abs_residual_s=NaN, action="create", conflict_message="");
end

function value = emptyAnchorTable()
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), ...
    VariableNames=["anchor_key", "alignment_anchor_id", ...
    "source_observation_id", "reference_observation_id", ...
    "observed_source_time", "observed_reference_time", ...
    "predicted_reference_time", "residual_s", "included_in_fit", ...
    "source_role", "reference_role", "exclusion_reason", ...
    "source_uncertainty_s", "reference_uncertainty_s", ...
    "source_observation_count", "reference_observation_count"]);
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
