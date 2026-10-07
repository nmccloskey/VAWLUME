function [metrics, bandState] = acousticWindowMetrics(samples, sampleRate, bandMin, bandMax)
%ACOUSTICWINDOWMETRICS The one computational core for bounded-window levels.
%
% Shared by measureReferenceResponse and measureCallWindow, so the two methods
% cannot drift apart: one copy of the convention, not two kept in agreement.
% Metric names are neutral ("rms_amplitude", "peak_abs_amplitude",
% "band_power"); each caller prefixes its own metric keys, because a call's RMS
% and a reference's RMS are different measurements with the same arithmetic.
%
% Conventions (doc 27): samples are AUDIOREAD full-scale ratios; RMS is the
% square root of the mean square; band power is two-sided rectangular-bin DFT
% power selected by folded absolute frequency, normalized by N^2 so a full band
% obeys Parseval. No detrending, window function, calibration or gain.
%
% bandState is one of:
%   "no_samples"     empty window; no metrics at all, band not examined
%   "not_declared"   neither bound given; no band power, and none inferred
%   "incomplete"     exactly one bound given
%   "invalid"        max <= min
%   "above_nyquist"  max exceeds sampleRate / 2
%   "computed"       band power is in the table

metrics = table(Size=[0 3], VariableTypes=["string", "double", "string"], ...
    VariableNames=["metric_key", "value", "unit"]);
if isempty(samples)
    bandState = "no_samples";
    return
end
metrics = [metrics; {"rms_amplitude", ...
    sqrt(mean(samples .^ 2)), "full_scale_ratio"}];
metrics = [metrics; {"peak_abs_amplitude", ...
    max(abs(samples)), "full_scale_ratio"}];

hasMin = ~isnan(bandMin);
hasMax = ~isnan(bandMax);
if ~hasMin && ~hasMax
    bandState = "not_declared";
    return
end
if hasMin ~= hasMax
    bandState = "incomplete";
    return
end
if bandMax <= bandMin
    bandState = "invalid";
    return
end
if bandMax > sampleRate / 2
    bandState = "above_nyquist";
    return
end

n = numel(samples);
spectrum = fft(samples);
frequency = (0:n-1)' * (sampleRate / n);
foldedFrequency = min(frequency, sampleRate - frequency);
selected = foldedFrequency >= bandMin & foldedFrequency <= bandMax;
bandPower = sum(abs(spectrum(selected)) .^ 2) / (n ^ 2);
metrics = [metrics; {"band_power", bandPower, ...
    "full_scale_ratio_squared"}];
bandState = "computed";
end
