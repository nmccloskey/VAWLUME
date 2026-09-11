function value = geometryPresentText(raw)
%GEOMETRYPRESENTTEXT Normalize fetched text, mapping missing to "".
%
% Reads in this package wrap nullable columns in IFNULL, so this normalizes
% type rather than recovering from NULL. It still maps missing defensively: a
% column added later without its IFNULL guard should produce "" here rather
% than a <missing> that propagates into a comparison.
value = string(raw);
value(ismissing(value)) = "";
end
