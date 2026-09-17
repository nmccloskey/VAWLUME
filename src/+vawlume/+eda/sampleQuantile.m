function values = sampleQuantile(sample, probabilities)
%SAMPLEQUANTILE Sample quantiles by linear interpolation of order statistics.
%
% VALUES = vawlume.eda.SAMPLEQUANTILE(SAMPLE, PROBABILITIES) returns the
% quantiles of SAMPLE at each probability in PROBABILITIES, under one stated
% definition:
%
%   sort the sample, place the i-th of n order statistics at cumulative
%   probability (i - 0.5)/n, interpolate linearly between neighbouring order
%   statistics, and clamp any probability outside [(0.5)/n, (n-0.5)/n] to the
%   nearest extreme order statistic.
%
% That is MATLAB's own default quantile definition, chosen deliberately. This
% function exists so the exploratory diagnostics run under base MATLAB alone:
% `quantile`, `prctile` and `iqr` moved into base MATLAB only in recent
% releases and were Statistics and Machine Learning Toolbox functions before
% that, so calling one would silently make the whole workflow unavailable to a
% user on an older release. Matching the definition means a user who does hold
% the toolbox gets identical numbers, and it makes the implementation testable
% against a hand-computed reference.
%
% NaN entries are ignored, as MATLAB's `quantile` ignores them. Inf entries are
% NOT ignored and participate in the ordering, again matching `quantile`. The
% diagnostic layer filters to finite values before calling, so an infinity
% reaches this function only when a caller asks it to.
%
% An empty sample, or one containing no non-NaN value, returns NaN for every
% requested probability rather than raising: a metric with no supported
% observation is a fact to report, not an error.
%
% This function computes one definition of one statistic. It does not decide
% which metrics are worth summarizing, does not filter a sample, and does not
% interpret the result.

arguments
    sample {mustBeNumeric}
    probabilities {mustBeNumeric, mustBeReal}
end

if any(probabilities(:) < 0 | probabilities(:) > 1)
    error("vawlume:eda:ProbabilityOutOfRange", ...
        "Every requested probability must lie in [0, 1].");
end

values = NaN(size(probabilities));
ordered = sort(double(sample(~isnan(sample(:)))));
n = numel(ordered);
if n == 0
    return
end
if n == 1
    values(:) = ordered(1);
    return
end

positions = ((1:n)' - 0.5) / n;
requested = double(probabilities(:));
interpolated = interp1(positions, ordered, requested, "linear");
interpolated(requested <= positions(1)) = ordered(1);
interpolated(requested >= positions(end)) = ordered(end);
values = reshape(interpolated, size(probabilities));
end
