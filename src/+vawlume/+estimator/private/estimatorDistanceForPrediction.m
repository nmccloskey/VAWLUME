function value = estimatorDistanceForPrediction(otherDistance, predictedDb, side)
%ESTIMATORDISTANCEFORPREDICTION Invert the method's prediction for one distance.
%
% The distance to channel SIDE ("a" or "b") that, holding the other channel's
% distance OTHERDISTANCE, makes estimatorPredictedDifferenceDb equal PREDICTEDDB:
%
%   side a:  20*log10(d_b/d_a) = p  =>  d_a = d_b * 10^(-p/20)
%   side b:  20*log10(d_b/d_a) = p  =>  d_b = d_a * 10^( p/20)
%
% Method arithmetic on two stored distances: it reads no coordinate and computes
% no position (contract 07 D8), so it is not spatial arithmetic.
switch side
    case "a"
        value = otherDistance .* 10 .^ (-predictedDb ./ 20);
    case "b"
        value = otherDistance .* 10 .^ (predictedDb ./ 20);
    otherwise
        error("vawlume:estimator:InputInvalid", "side must be a or b.");
end
end
