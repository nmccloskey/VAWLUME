function value = edaGateBoundNames()
%EDAGATEBOUNDNAMES The optional plausibility bounds a matching specification may declare.
%
% These are the magnitude bounds added to candidate_generation.plausibility_rule
% alongside min_temporal_iou. Each is optional, and absent means unconstrained,
% so a specification declaring none of them writes none of these keys into
% candidate_pairs.details_json and its stored rows stay byte-identical to those
% written before the dimensions existed. An absent bound reaches the surface as
% NaN, which is how a caller detects that the dimension was unconstrained.
value = ["max_abs_onset_difference_s", "max_abs_offset_difference_s", ...
    "max_abs_duration_difference_s"];
end
