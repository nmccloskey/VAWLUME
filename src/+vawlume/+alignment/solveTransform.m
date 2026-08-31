function result = solveTransform(method, sourceTimes, referenceTimes)
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
%   "piecewise_affine" raises. The schema can represent piecewise segments but no
%                      segment-selection or breakpoint estimation is implemented,
%                      and silently returning a single affine fit would answer a
%                      different question than the caller asked.
%
% The solution is plain MATLAB least squares — `X \ y` — with no optimizer, no
% robust regression, no automatic outlier rejection, and no iterative refinement.
% Anchors are sorted by source time before solving so that the coefficients do
% not depend on the order rows happened to arrive in; RESULT.residual_s is
% returned in the caller's original order.
%
% RESULT fields:
%
%   method, scale, offset_s, n_anchors_used
%   source_times, reference_times, predicted_reference_times, residual_s
%   rmse_s, max_abs_residual_s
%
% Anchor uncertainty is deliberately not accepted here. This is an unweighted
% fit; weighting anchors by a recorded uncertainty would be a different estimator
% and this prototype has no basis for choosing one.

arguments
    method (1,1) string
    sourceTimes double
    referenceTimes double
end

if method == "piecewise_affine"
    error("vawlume:alignment:MethodNotImplemented", ...
        ['Piecewise-affine fitting is not implemented. The schema can represent ' ...
        'piecewise segments, but no breakpoint estimation or segment selection ' ...
        'exists, and returning a single affine fit instead would silently answer ' ...
        'a different question.']);
end
if ~ismember(method, ["offset", "affine"])
    error("vawlume:alignment:MethodUnsupported", ...
        "Transform method '%s' is not supported; expected offset or affine.", method);
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
    max_abs_residual_s=max(abs(residual)));
end
