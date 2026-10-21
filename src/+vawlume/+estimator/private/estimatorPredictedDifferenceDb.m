function value = estimatorPredictedDifferenceDb(distanceA, distanceB)
%ESTIMATORPREDICTEDDIFFERENCEDB The method's prediction: 20*log10(d_b/d_a), in dB.
%
% Method vawlume.estimator.level_difference_consistency 1.0.0, spherical
% spreading (contract 06 D7): power falls as 1/d^2, so the level difference
% between channel a and channel b predicted for a source at distances d_a and
% d_b is 20*log10(d_b/d_a). The ONE home of this arithmetic:
% levelDifferenceConsistency scores with it and qcFacts reports with it, so the
% two cannot drift apart. Factored out at itinerary 7.10 with identical
% floating-point operations; stored scores are unchanged.
value = 20 * log10(distanceB ./ distanceA);
end
