function result = relation(startA, endA, startB, endB)
%RELATION Compute domain-neutral temporal relations between two intervals.
%
%   result = VAWLUME.INTERVAL.RELATION(startA, endA, startB, endB)
%
% Compares the finite scalar intervals [startA, endA] and [startB, endB].
% Bounds and returned distances are in seconds. Equal bounds are permitted,
% so a zero-duration interval is representable. An end before its start is
% refused.
%
% RESULT is a scalar struct with exactly these arithmetic fields:
%
%   intersection_s       max(0, min(endA,endB) - max(startA,startB))
%   union_s              max(endA,endB) - min(startA,startB)
%   temporal_iou         intersection_s / union_s when union_s > 0
%   onset_difference_s   startB - startA
%   offset_difference_s  endB - endA
%   duration_difference_s
%                        (endB-startB) - (endA-startA)
%
% Signed differences are always interval B minus interval A. The function
% has no domain meaning for A or B beyond argument order.
%
% Exact boundary contact has zero intersection and temporal_iou 0. Two
% zero-duration intervals at the same instant have both zero intersection
% and zero union; temporal_iou is explicitly NaN because 0/0 has no overlap
% fraction. A zero-duration interval compared with a distinct or positive-
% duration interval has temporal_iou 0 because its union is positive.
%
% This primitive computes arithmetic only. It does not decide eligibility,
% apply a threshold, generate candidates, attach identifiers, or interpret
% either interval as a detection or caller estimate.

arguments
    startA (1,1) double {mustBeReal, mustBeFinite}
    endA (1,1) double {mustBeReal, mustBeFinite}
    startB (1,1) double {mustBeReal, mustBeFinite}
    endB (1,1) double {mustBeReal, mustBeFinite}
end

if endA < startA
    error("vawlume:interval:ReversedInterval", ...
        "Interval A ends before it starts: [%g %g].", startA, endA);
end
if endB < startB
    error("vawlume:interval:ReversedInterval", ...
        "Interval B ends before it starts: [%g %g].", startB, endB);
end

intersectionS = max(0, min(endA, endB) - max(startA, startB));
unionS = max(endA, endB) - min(startA, startB);
if unionS == 0
    temporalIou = NaN;
else
    temporalIou = intersectionS / unionS;
end

result = struct( ...
    intersection_s=intersectionS, ...
    union_s=unionS, ...
    temporal_iou=temporalIou, ...
    onset_difference_s=startB - startA, ...
    offset_difference_s=endB - endA, ...
    duration_difference_s=(endB - startB) - (endA - startA));
end
