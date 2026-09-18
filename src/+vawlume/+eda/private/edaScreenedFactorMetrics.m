function value = edaScreenedFactorMetrics()
%EDASCREENEDFACTORMETRICS Surface columns corresponding to the screened factors.
%
% The governing contract screens four matching dimensions: min_temporal_iou and
% three max_abs_*_difference_s bounds. Those are parameters, not observations;
% the observed metric each one gates is the column named here.
%
% Redundancy between two of these is the finding that matters most, because two
% strongly collinear factors in a screening design produce main effects that
% cannot be attributed separately. The dependency report marks such a pair so the
% finding reaches the leverage report rather than staying in a heatmap.
value = ["temporal_iou", "abs_onset_difference_s", ...
    "abs_offset_difference_s", "abs_duration_difference_s"];
end
