function [aligned, transform] = applyTransform(conn, alignmentRunId, nativeTimes, options)
%APPLYTRANSFORM Express native source times on the reference clock.
%
% ALIGNED = vawlume.alignment.applyTransform(CONN, ALIGNMENTRUNID, NATIVETIMES)
% reads the stored segment coefficients for one pairwise transform, selects the
% segment covering each time, and returns
%
%   aligned = scale * nativeTimes + offset_s
%
% for that segment, preserving the shape of NATIVETIMES.
%
% [ALIGNED, TRANSFORM] = ... also returns the coefficients, clocks, method, fit
% summary, status, and per-element evidence actually used, so a caller can record
% what produced a number rather than carrying a bare vector around.
%
% [~, TRANSFORM] = vawlume.alignment.applyTransform(CONN, ALIGNMENTRUNID) called
% with no times returns the transform description with empty per-element arrays.
% Use this to inspect a transform rather than passing a dummy time, which asks
% where an arbitrary instant lands and gets an answer -- including, once
% extrapolation is flagged, a warning about an instant nobody was interested in.
%
% **It never refits.** The stored transform is the authority; recomputing here
% could silently disagree with the residuals persisted beside it. It also writes
% nothing: detections, external events, and anchor observations keep their native
% timestamps, and an aligned value is derived on demand.
%
% A run that has not been fitted, or whose fit was rejected or failed, raises
% rather than returning a plausible-looking number.
%
% **A segment covers [source_start, source_end).** A time exactly at a breakpoint
% belongs to the segment beginning there. Selection goes through
% vawlume.alignment.internal.evaluateSegments, the same implementation the fitter
% predicts anchors with, so the two cannot disagree about that boundary.
%
% **Extrapolation is flagged, not hidden.** A time outside the range the anchors
% covered is still transformed, using the terminal segment, and marked in
% TRANSFORM.extrapolated. Refusing would break the promise of a value per input;
% returning an unmarked number would be worse. Pass ErrorOnExtrapolation=true to
% escalate it, mirroring ErrorOnOutsideCoverage in VAWLUME.ALIGNMENT.COMMONTIME.
%
% Coverage and extrapolation are different statements and must not be conflated:
% coverage says the stream was observed, extrapolation says the transform was not
% anchored there.
%
% **Propagated uncertainty is uncalibrated.** TRANSFORM.uncertainty_s carries the
% segment's stored bound — the largest recorded anchor uncertainty among the
% anchors that determined it — with its semantics beside it. It is **not** a
% confidence interval, a standard error, or a probability. A segment whose
% anchors recorded no uncertainty yields NaN, never 0, because absence is not
% perfect knowledge. It is never combined with the fit residual: how well the
% model describes the anchors and how well each anchor was read are different
% quantities.
%
% Name-value arguments:
%   ErrorOnExtrapolation  raise instead of flagging (default false)
%
% TRANSFORM fields:
%
%   alignment_run_id, source_timebase_key, reference_timebase_key, method, status
%   scale, offset_s                     NaN when the transform has several segments
%   n_anchors_used, rmse_s, max_abs_residual_s
%   segments                            one row per stored segment
%   segment_index, extrapolated         per element of NATIVETIMES
%   uncertainty_s, uncertainty_semantics    per element
%   anchored_range_start, anchored_range_end, anchored_range_known
%   source
%
% See also VAWLUME.ALIGNMENT.APPLYTRANSFORMINTERVAL, VAWLUME.ALIGNMENT.FIT.

arguments
    conn
    alignmentRunId (1,1) double {mustBePositive, mustBeInteger}
    nativeTimes double = double.empty(0, 1)
    options.ErrorOnExtrapolation (1,1) logical = false
end

rows = fetch(conn, "SELECT r.alignment_run_id, r.method, r.status, " + ...
    "IFNULL(r.n_anchors_used,-1) AS n_anchors_used, " + ...
    "IFNULL(r.fit_rmse_s,-1) AS fit_rmse_s, " + ...
    "IFNULL(r.max_error_s,-1) AS max_error_s, " + ...
    "src.timebase_name AS source_timebase_key, " + ...
    "ref.timebase_name AS reference_timebase_key " + ...
    "FROM time_alignment_runs r " + ...
    "JOIN timebases src ON src.timebase_id=r.source_timebase_id " + ...
    "JOIN timebases ref ON ref.timebase_id=r.target_timebase_id " + ...
    "WHERE r.alignment_run_id=" + string(alignmentRunId));
if isempty(rows) || height(rows) == 0
    error("vawlume:alignment:TransformRunNotFound", ...
        "No pairwise transform run has id %d.", alignmentRunId);
end

status = presentText(rows.status(1));
if ismember(status, ["rejected", "failed"])
    error("vawlume:alignment:TransformNotUsable", ...
        ['Transform run %d has status ''%s''. A rejected or failed fit must not ' ...
        'be used to place events on another clock.'], alignmentRunId, status);
end
if status == "registered"
    error("vawlume:alignment:TransformNotFitted", ...
        ['Transform run %d is registered but not fitted. Fit it with ' ...
        'vawlume.alignment.fit before applying it.'], alignmentRunId);
end

segments = storedSegments(conn, alignmentRunId, status);
[aligned, segmentIndex] = vawlume.alignment.internal.evaluateSegments( ...
    segments, nativeTimes);

anchored = anchoredRange(conn, alignmentRunId);
extrapolated = extrapolationFlags(nativeTimes, anchored);
if options.ErrorOnExtrapolation && any(extrapolated(:))
    outside = nativeTimes(extrapolated);
    error("vawlume:alignment:ExtrapolatedTime", ...
        ['Source time %g lies outside the range the anchors covered, ' ...
        '[%g, %g]. The transform still evaluates there, but it was never ' ...
        'anchored there; pass ErrorOnExtrapolation=false to accept the ' ...
        'extrapolation and read the flag instead.'], ...
        outside(1), anchored.start, anchored.finish);
end

if height(segments) == 1
    scale = double(segments.scale(1));
    offset = double(segments.offset_s(1));
else
    % A segmented transform has no single slope, and reporting the first
    % segment's would be a plausible-looking number for the whole clock.
    scale = NaN;
    offset = NaN;
end

if isempty(segmentIndex)
    uncertainty = double.empty(size(segmentIndex));
    semantics = strings(size(segmentIndex));
else
    uncertainty = reshape(double(segments.uncertainty_s(segmentIndex(:))), ...
        size(segmentIndex));
    semantics = reshape(string(segments.uncertainty_semantics(segmentIndex(:))), ...
        size(segmentIndex));
end

transform = struct( ...
    alignment_run_id=double(rows.alignment_run_id(1)), ...
    source_timebase_key=presentText(rows.source_timebase_key(1)), ...
    reference_timebase_key=presentText(rows.reference_timebase_key(1)), ...
    method=presentText(rows.method(1)), ...
    scale=scale, ...
    offset_s=offset, ...
    n_anchors_used=optionalNumber(rows.n_anchors_used(1)), ...
    rmse_s=optionalNumber(rows.fit_rmse_s(1)), ...
    max_abs_residual_s=optionalNumber(rows.max_error_s(1)), ...
    status=status, ...
    segment_index=segmentIndex, ...
    extrapolated=extrapolated, ...
    uncertainty_s=uncertainty, ...
    uncertainty_semantics=semantics, ...
    anchored_range_start=anchored.start, ...
    anchored_range_end=anchored.finish, ...
    anchored_range_known=anchored.known, ...
    uncertainty_note=uncertaintyNote(), ...
    source="stored alignment_segments coefficients; not refitted");
transform.segments = segments;
end

% ----------------------------------------------------------------- reading ---

function value = storedSegments(conn, alignmentRunId, status)
%STOREDSEGMENTS The transform of record, with its open bounds restored to NaN.
%
% Every nullable column is wrapped. The Database Toolbox raises 'Unexpected NULL'
% while building a result set containing SQL NULL, and an open segment bound is
% exactly that.
value = fetch(conn, "SELECT segment_index, " + ...
    "IFNULL(source_start, 1e308) AS source_start, " + ...
    "IFNULL(source_end, 1e308) AS source_end, scale, offset_s, " + ...
    "IFNULL(rmse_s,-1) AS rmse_s, " + ...
    "IFNULL(uncertainty_s,-1) AS uncertainty_s, " + ...
    "IFNULL(uncertainty_semantics,'') AS uncertainty_semantics " + ...
    "FROM alignment_segments WHERE alignment_run_id=" + ...
    string(alignmentRunId) + " ORDER BY segment_index");
if isempty(value) || height(value) == 0
    error("vawlume:alignment:TransformSegmentMissing", ...
        "Transform run %d has status '%s' but stores no segment coefficients.", ...
        alignmentRunId, status);
end
value.source_start = openToNaN(double(value.source_start));
value.source_end = openToNaN(double(value.source_end));
value.rmse_s = absentToNaN(double(value.rmse_s));
value.uncertainty_s = absentToNaN(double(value.uncertainty_s));
value.uncertainty_semantics = string(value.uncertainty_semantics);

% Checked on read as well as on write. The write guard is the contract, but a
% database edited by hand bypasses it, and this is the point where a segmentation
% that gaps or overlaps would start producing plausible-looking wrong numbers.
%
% Open outer bounds are not required here. A fit always produces them, but the
% schema permits a bounded transform and shipped fixtures store one; refusing
% those on read would reject data the schema allows. Contiguity is what the
% arithmetic depends on.
vawlume.alignment.internal.assertSegmentsTile(value, ...
    "alignment run " + string(alignmentRunId), RequireOpenEnds=false);
end

function value = anchoredRange(conn, alignmentRunId)
%ANCHOREDRANGE The span of source times the included anchors actually covered.
%
% Read from the residuals, which name the observation each was computed from. A
% transform with no stored residuals — a hand-built fixture, say — leaves the
% range unknown, and this says so rather than assuming the whole clock was
% anchored.
value = struct(start=NaN, finish=NaN, known=false);
% MIN and MAX over zero rows are SQL NULL, and the Database Toolbox raises
% rather than returning one, so both are wrapped. COUNT decides whether the
% wrapped values mean anything.
rows = fetch(conn, "SELECT IFNULL(MIN(observed_source_time), 0) AS low, " + ...
    "IFNULL(MAX(observed_source_time), 0) AS high, COUNT(*) AS n " + ...
    "FROM alignment_anchor_residuals WHERE alignment_run_id=" + ...
    string(alignmentRunId) + " AND included_in_fit=1");
if isempty(rows) || height(rows) == 0 || double(rows.n(1)) == 0
    return
end
value.start = double(rows.low(1));
value.finish = double(rows.high(1));
value.known = true;
end

function value = extrapolationFlags(nativeTimes, anchored)
value = false(size(nativeTimes));
if ~anchored.known || isempty(nativeTimes)
    return
end
value = nativeTimes < anchored.start | nativeTimes > anchored.finish;
end

% ----------------------------------------------------------------- helpers ---

function value = uncertaintyNote()
value = "uncertainty_s is the largest recorded anchor uncertainty among the " + ...
    "anchors that determined the segment used, on the reference clock. It is " + ...
    "uncalibrated: not a confidence interval, a standard error, or a " + ...
    "probability. NaN means no contributing anchor recorded one, which is an " + ...
    "absence rather than zero. It is never combined with rmse_s.";
end

function value = openToNaN(value)
value(value >= 1e307) = NaN;
end

function value = absentToNaN(value)
value(value < 0) = NaN;
end

function value = optionalNumber(raw)
value = double(raw);
if value < 0
    value = NaN;
end
end

function value = presentText(value)
value = string(value);
value(ismissing(value)) = "";
end
