function [names, isAbsolute] = edaTemporalMetricNames()
%EDATEMPORALMETRICNAMES The numeric temporal metrics the diagnostics summarize.
%
% Signed and absolute variants are both carried. The conceptual specification
% asks for absolute onset, offset and duration differences; the stored columns
% are signed. Carrying both, under names that cannot be confused, lets the
% distribution layer report either without a second definition of the quantity
% existing anywhere.
names = ["temporal_iou", "temporal_overlap_s", "candidate_score", ...
    "onset_difference_s", "offset_difference_s", "duration_difference_s", ...
    "abs_onset_difference_s", "abs_offset_difference_s", ...
    "abs_duration_difference_s"];
isAbsolute = startsWith(names, "abs_");
end
