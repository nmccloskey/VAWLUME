function value = edaEmptyFeatureCoverage()
%EDAEMPTYFEATURECOVERAGE An empty coverage table in Part 3's own column order.
%
% The same five disjoint categories edaCoverageCategories fixes, so a
% characterization surface can be handed to vawlume.eda.metricDistributions
% unchanged rather than forcing a second distribution implementation.
%
% `not_comparable_topology` is always zero here and the column is kept anyway.
% It means "the match group was a split, merge or unmatched group", which is a
% fact about a candidate PAIR; this layer counts detections, where the case
% cannot arise. Dropping the column would make the two surfaces structurally
% different for a reason that is about the question rather than about the data,
% and the shared shape is what lets one summarizer serve both.
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["metric_name", "metric_kind", "supported", ...
    "not_eligible", "not_measured", "not_comparable_topology", ...
    "non_finite", "total"]);
end
