function value = edaFactorPolicy()
%EDAFACTORPOLICY The contract's screened factors and their probe-value anchors.
%
% The factor set comes from the governing contract, not from the data: a factor
% participates because the matching specification supports it and the user has
% not disabled it. Four factors is the position the design contract assumes, a
% 2^(4-1) resolution-IV screen in eight runs.
%
% Low and high are anchored on quantiles of an OBSERVED metric rather than fixed
% constants. A hard-coded 0.1/0.5 IoU pair can sit entirely outside a dataset's
% observed range, producing a screen in which one level changes nothing and the
% factor reports zero leverage for a reason that has nothing to do with the
% science. Quantile anchoring guarantees both levels fall where data exist.
%
% STRICTNESS RUNS IN OPPOSITE DIRECTIONS across these factors and the table says
% so per factor. A larger min_temporal_iou is stricter; a larger max_abs_* bound
% is looser. "Low" and "high" name the parameter value, never the strictness.
% Without this recorded, the sign of a screening main effect is uninterpretable
% and an axis label is actively misleading.
factorName = ["min_temporal_iou"; "max_abs_onset_difference_s"; ...
    "max_abs_offset_difference_s"; "max_abs_duration_difference_s"];
metricName = ["temporal_iou"; "abs_onset_difference_s"; ...
    "abs_offset_difference_s"; "abs_duration_difference_s"];
lowQuantile = [0.10; 0.50; 0.50; 0.50];
highQuantile = [0.50; 0.95; 0.95; 0.95];
strictness = ["larger_is_stricter"; "smaller_is_stricter"; ...
    "smaller_is_stricter"; "smaller_is_stricter"];
unit = ["ratio"; "seconds"; "seconds"; "seconds"];
minimumValue = [0; 0; 0; 0];
maximumValue = [1; Inf; Inf; Inf];
value = table(factorName, metricName, lowQuantile, highQuantile, strictness, ...
    unit, minimumValue, maximumValue, ...
    VariableNames=["factor_name", "metric_name", "low_quantile", ...
    "high_quantile", "strictness_direction", "unit", "minimum_value", ...
    "maximum_value"]);
end
