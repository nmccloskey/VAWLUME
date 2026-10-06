function summary = summarizeDistances(distances, bases)
%SUMMARIZEDISTANCES Window summaries over the distances of observed samples.
%
%   summary = VAWLUME.GEOMETRY.SUMMARIZEDISTANCES(distances, bases)
%
% DISTANCES is a vector of per-sample distances over one window, NaN where a
% distance could not be computed. BASES gives each one's basis. Every basis
% must be "observed": window summaries are taken over what the tracker actually
% saw inside the window, never over interpolated positions, which would let the
% interpolation policy leak into a quantity that claims to describe the samples
% (vawlume:geometry:SummaryBasisInvalid).
%
% PURE, and one of the three places spatial arithmetic may occur, all in
% +geometry/.
%
% Several summaries are defensible, so both are returned and labelled, and the
% consumer records which it used (development plan section 4.7):
%
%   window_median   median distance over computed samples
%   window_min      minimum distance over computed samples
%
% AN EMPTY WINDOW IS NOT A ZERO. With no computed distance the status is
% "not_covered", both summaries are NaN, and the reason says whether the window
% held no sample at all ("no_samples") or only samples whose distance could not
% be computed ("no_computed_distance").
%
% SUMMARY fields:
%   window_median, window_min, n_samples, n_computed, status, reason, basis
%
% See also VAWLUME.GEOMETRY.DISTANCE, VAWLUME.GEOMETRY.POSITIONATINSTANTS

arguments
    distances double
    bases string
end

distances = distances(:);
bases = bases(:);
if numel(bases) ~= numel(distances)
    error("vawlume:geometry:SummaryBasisInvalid", ...
        "Supply one basis per distance (%d distances, %d bases).", ...
        numel(distances), numel(bases));
end
if any(bases ~= "observed")
    error("vawlume:geometry:SummaryBasisInvalid", ...
        "Window summaries are taken over observed samples only; %d input(s) " + ...
        "have another basis.", nnz(bases ~= "observed"));
end
if any(distances < 0)
    error("vawlume:geometry:SummaryDistanceInvalid", ...
        "A distance cannot be negative.");
end

computed = distances(~isnan(distances));
summary = struct(window_median=NaN, window_min=NaN, ...
    n_samples=numel(distances), n_computed=numel(computed), ...
    status="not_covered", reason="", basis="observed_samples_in_window");
if isempty(distances)
    summary.reason = "no_samples";
elseif isempty(computed)
    summary.reason = "no_computed_distance";
else
    summary.window_median = median(computed);
    summary.window_min = min(computed);
    summary.status = "computed";
end
end
