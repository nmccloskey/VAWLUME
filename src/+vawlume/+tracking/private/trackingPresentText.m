function value = trackingPresentText(raw)
%TRACKINGPRESENTTEXT Normalize fetched text, mapping missing to "".
%
% Reads in this package wrap nullable columns in IFNULL, so this normalizes type
% rather than recovering from NULL. It still maps missing defensively: the
% Database Toolbox can return an empty text column as <missing> even through
% IFNULL, and a missing element propagates silently through concatenation.
value = string(raw);
value(ismissing(value)) = "";
end
