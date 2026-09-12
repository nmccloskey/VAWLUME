function result = solveTransform(method, sourceTimes, referenceTimes, options)
%SOLVETRANSFORM Fit a transparent source-to-reference time transform.
%
% RESULT = vawlume.alignment.solveTransform(METHOD, SOURCETIMES, REFERENCETIMES)
% estimates the coefficients of
%
%   reference = scale * source + offset_s
%
% from explicitly paired anchor observations, and returns the coefficients with
% per-anchor predictions and residuals. It touches no database and holds no
% state, so the mathematics can be audited on its own.
%
% METHOD is one of:
%
%   "offset"           scale is fixed at 1 and only a shift is estimated. One
%                      anchor gives offset = reference - source; several give the
%                      ordinary least-squares solution, which is the mean of the
%                      pairwise differences.
%   "affine"           scale and offset are estimated together by ordinary least
%                      squares. At least two anchors with two distinct source
%                      times are required, because one point cannot determine a
%                      slope and identical source times leave the system rank
%                      deficient.
%   "piecewise_affine" one affine segment per declared interval, continuous at
%                      the breakpoints. Requires Breakpoints; see below.
%
% The solution is plain MATLAB least squares — `X \ y` — with no optimizer, no
% robust regression, no automatic outlier rejection, and no iterative refinement.
% Anchors are sorted by source time before solving so that the coefficients do
% not depend on the order rows happened to arrive in; RESULT.residual_s is
% returned in the caller's original order.
%
% Name-value arguments:
%
%   Breakpoints  source-clock times where a piecewise transform changes regime.
%                Required for "piecewise_affine" and refused for the other two.
%
% **Breakpoints are declared, never estimated.** VAWLUME does not search for
% them. A breakpoint is a claim that something happened to a clock — a restart, a
% dropped buffer, a drift regime change — and choosing one from the residuals
% would be model selection this prototype has no basis for performing. There is
% no option here that asks for one to be found.
%
% **Segments are continuous at their breakpoints.** A discontinuity would map one
% source instant to two reference times, leaving both application and interval
% transformation undefined at exactly the point of interest. A clock that
% genuinely jumps is a gap in coverage, or two alignment identities, not one
% transform with a step in it.
%
% Continuity costs nothing: with the knots declared, a continuous
% piecewise-linear fit is one ordinary least-squares problem in a hinge basis,
%
%   reference = a0 + a1 * source + SUM_k b_k * max(0, source - knot_k)
%
% so per-segment `scale` and `offset_s` follow by accumulation and the solve
% stays `X \ y`.
%
% **A segment covers [source_start, source_end).** An anchor exactly at a
% breakpoint belongs to the segment that begins there. The first segment is open
% below and the last open above, reported as NaN bounds, so every finite source
% time falls in exactly one segment.
%
% RESULT fields:
%
%   method, scale, offset_s, n_anchors_used
%   source_times, reference_times, predicted_reference_times, residual_s
%   rmse_s, max_abs_residual_s
%   breakpoints, segments, segment_index
%
% `segments` is a table of segment_index, source_start, source_end, scale,
% offset_s and anchor_count, and is present for every method: offset and affine
% return one open-ended segment, so a caller reads one shape regardless.
%
% For "piecewise_affine" the scalar `scale` and `offset_s` are **NaN**. A
% piecewise transform has no single slope, and returning the first segment's
% would be a plausible-looking number for a question that was not asked.
%
% Anchor uncertainty is deliberately not accepted here. This is an unweighted
% fit; weighting anchors by a recorded uncertainty would be a different estimator
% and this prototype has no basis for choosing one.
%
% Errors:
%   :MethodUnsupported            method outside the closed vocabulary
%   :AnchorPairMismatch           source and reference counts differ
%   :NoAnchors                    nothing to fit
%   :NonFiniteAnchor              a NaN or Inf timestamp
%   :InsufficientAnchors          fewer anchors than the model has parameters
%   :DegenerateAnchors            too few distinct source times; rank deficient
%   :BreakpointsRequired          piecewise requested with no breakpoints
%   :BreakpointsInvalid           breakpoints unsorted, repeated, non-finite,
%                                 outside the anchor span, or supplied for a
%                                 method that has no segments
%   :SegmentUnderdetermined       a segment holds no anchor
%   :NonPositiveTransformScale    a derived segment scale is at or below zero

arguments
    method (1,1) string
    sourceTimes double
    referenceTimes double
    options.Breakpoints double = double.empty(0, 1)
end

supported = ["offset", "affine", "piecewise_affine"];
if ~ismember(method, supported)
    error("vawlume:alignment:MethodUnsupported", ...
        "Transform method '%s' is not supported; expected %s.", method, ...
        strjoin(supported, ", "));
end

knots = options.Breakpoints(:);
if method ~= "piecewise_affine" && ~isempty(knots)
    error("vawlume:alignment:BreakpointsInvalid", ...
        ['Breakpoints were supplied for method ''%s'', which has one segment ' ...
        'by definition. Declaring where segments meet is only meaningful for ' ...
        'piecewise_affine.'], method);
end

source = sourceTimes(:);
reference = referenceTimes(:);
if numel(source) ~= numel(reference)
    error("vawlume:alignment:AnchorPairMismatch", ...
        "Received %d source times and %d reference times; anchors must be paired.", ...
        numel(source), numel(reference));
end
if isempty(source)
    error("vawlume:alignment:NoAnchors", ...
        "Fitting requires at least one paired anchor observation.");
end
if ~all(isfinite(source)) || ~all(isfinite(reference))
    error("vawlume:alignment:NonFiniteAnchor", ...
        ['Anchor observations must all be finite. A NaN or Inf timestamp is ' ...
        'missing or malformed evidence, not a value to fit through.']);
end

if method == "affine"
    if numel(source) < 2
        error("vawlume:alignment:InsufficientAnchors", ...
            ['An affine fit needs at least two anchors; %d was supplied. One ' ...
            'anchor cannot determine a scale, and assuming scale 1 would be an ' ...
            'offset fit reported under the wrong name.'], numel(source));
    end
    if numel(uniquetol(source, 1e-12, DataScale=1)) < 2
        error("vawlume:alignment:DegenerateAnchors", ...
            ['An affine fit needs at least two distinct source times. All %d ' ...
            'anchors share one source time, which leaves the scale undetermined.'], ...
            numel(source));
    end
end

% Solve on a stable ordering so coefficients are a property of the anchor set
% rather than of row order.
[~, order] = sortrows([source, reference]);
orderedSource = source(order);
orderedReference = reference(order);

if method == "piecewise_affine"
    [knots, segments] = solvePiecewise(orderedSource, orderedReference, knots);
    segmentIndex = segmentIndexFor(source, knots);
    predicted = segments.scale(segmentIndex) .* source + ...
        segments.offset_s(segmentIndex);
    scale = NaN;
    offset = NaN;
else
    if method == "offset"
        scale = 1;
        offset = mean(orderedReference - orderedSource);
    else
        design = [orderedSource, ones(numel(orderedSource), 1)];
        coefficients = design \ orderedReference;
        scale = coefficients(1);
        offset = coefficients(2);
    end
    predicted = scale * source + offset;
    segmentIndex = ones(numel(source), 1);
    segments = segmentTable(1, NaN, NaN, scale, offset, numel(source));
end

residual = reference - predicted;

result = struct( ...
    method=method, ...
    scale=scale, ...
    offset_s=offset, ...
    n_anchors_used=numel(source), ...
    source_times=reshape(source, size(sourceTimes)), ...
    reference_times=reshape(reference, size(sourceTimes)), ...
    predicted_reference_times=reshape(predicted, size(sourceTimes)), ...
    residual_s=reshape(residual, size(sourceTimes)), ...
    rmse_s=sqrt(mean(residual .^ 2)), ...
    max_abs_residual_s=max(abs(residual)), ...
    breakpoints=knots, ...
    segment_index=reshape(segmentIndex, size(sourceTimes)));
result.segments = segments;
end

% --------------------------------------------------------------- piecewise ---

function [knots, segments] = solvePiecewise(source, reference, knots)
%SOLVEPIECEWISE Continuous piecewise-linear least squares over declared knots.
if isempty(knots)
    error("vawlume:alignment:BreakpointsRequired", ...
        ['A piecewise_affine fit requires declared breakpoints. VAWLUME does ' ...
        'not search for them: a breakpoint is a claim that something happened ' ...
        'to a clock, and choosing one from the residuals would be model ' ...
        'selection with no basis behind it.']);
end
if ~all(isfinite(knots))
    error("vawlume:alignment:BreakpointsInvalid", ...
        "Breakpoints must all be finite.");
end
if any(diff(knots) <= 0)
    error("vawlume:alignment:BreakpointsInvalid", ...
        ['Breakpoints must be strictly increasing. Repeated or unsorted ' ...
        'breakpoints do not describe a segmentation.']);
end
if numel(uniquetol(source, 1e-12, DataScale=1)) < 2
    error("vawlume:alignment:DegenerateAnchors", ...
        ['A piecewise_affine fit needs at least two distinct source times. ' ...
        'All %d anchors share one source time.'], numel(source));
end

% Strictly inside, so no segment is empty by construction and no segment's slope
% rests on the single anchor sitting on its own boundary, where both segments
% already agree.
lower = min(source);
upper = max(source);
outside = knots <= lower | knots >= upper;
if any(outside)
    error("vawlume:alignment:BreakpointsInvalid", ...
        ['Breakpoint %g lies outside the anchored source span [%g, %g]. A ' ...
        'breakpoint at or beyond an end leaves a segment with no anchor to ' ...
        'determine it.'], knots(find(outside, 1)), lower, upper);
end

segmentCount = numel(knots) + 1;
parameterCount = segmentCount + 1;
if numel(source) < parameterCount
    error("vawlume:alignment:InsufficientAnchors", ...
        ['A piecewise_affine fit over %d segments has %d parameters and needs ' ...
        'at least that many anchors; %d were supplied.'], ...
        segmentCount, parameterCount, numel(source));
end

index = segmentIndexFor(source, knots);
counts = accumarray(index, 1, [segmentCount, 1]);
empty = find(counts == 0, 1);
if ~isempty(empty)
    error("vawlume:alignment:SegmentUnderdetermined", ...
        ['Segment %d holds no anchor, so its slope is not determined by any ' ...
        'observation. Declare a breakpoint set the anchors actually support.'], ...
        empty);
end

% reference = a0 + a1 * source + SUM_k b_k * max(0, source - knot_k)
design = [ones(numel(source), 1), source, max(0, source - knots')];
if rank(design) < parameterCount
    error("vawlume:alignment:DegenerateAnchors", ...
        ['The anchors do not determine a %d-segment piecewise fit: the design ' ...
        'is rank deficient. This normally means a segment''s anchors share one ' ...
        'source time.'], segmentCount);
end

coefficients = design \ reference;
scale = zeros(segmentCount, 1);
offset = zeros(segmentCount, 1);
scale(1) = coefficients(2);
offset(1) = coefficients(1);
for segment = 2:segmentCount
    hinge = coefficients(segment + 1);
    scale(segment) = scale(segment - 1) + hinge;
    offset(segment) = offset(segment - 1) - hinge * knots(segment - 1);
end

if any(scale <= 0)
    error("vawlume:alignment:NonPositiveTransformScale", ...
        ['Segment %d resolves to scale %g. A clock does not run backwards or ' ...
        'stand still, so this anchor set does not support the declared ' ...
        'segmentation.'], find(scale <= 0, 1), scale(find(scale <= 0, 1)));
end

starts = [NaN; knots];
ends = [knots; NaN];
segments = segmentTable((1:segmentCount)', starts, ends, scale, offset, counts);
end

function value = segmentIndexFor(source, knots)
%SEGMENTINDEXFOR A segment covers [source_start, source_end).
%
% An anchor exactly at a breakpoint belongs to the segment that begins there.
% Stated once, here, because the fitter and the applier must not disagree about
% it and an off-by-one at a breakpoint survives review.
value = ones(numel(source), 1);
for k = 1:numel(knots)
    value = value + double(source(:) >= knots(k));
end
end

function value = segmentTable(index, starts, ends, scale, offset, counts)
value = table(index(:), starts(:), ends(:), scale(:), offset(:), counts(:), ...
    VariableNames=["segment_index", "source_start", "source_end", "scale", ...
    "offset_s", "anchor_count"]);
end
