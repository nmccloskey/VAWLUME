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
%
% Read from edaFactorPolicy, the one declaration of factor and metric (EXP-042),
% so the metric a factor's probe values are anchored on and the metric its
% redundancy finding is about cannot diverge.
value = edaFactorPolicy().metric_name';
end
