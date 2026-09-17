function coverage = edaCoverage(metrics, temporalNames, featureMetrics, featureStatus)
%EDACOVERAGE Count every metric's observations across the disjoint categories.
%
% Conceptual specification §4.2 requires a supported count and an
% unsupported count for every metric. This is not a footnote: it is the
% difference between "this metric is centred near zero" and "this metric has 14
% observations out of 9,000". The categories are kept apart rather than summed
% into one "missing" count because they imply different next steps, and because
% the dependency layer decides computability from them.
%
% A temporal metric is computed for every stored candidate row by construction,
% so it is only ever supported or non_finite. A feature discrepancy carries the
% status the feature layer assigned per row.
%
% non_finite covers NaN, Inf, and SQL NULL alike. A stored candidate row whose
% metric column is NULL reaches MATLAB as NaN through the read sentinel, and the
% honest report is that the row exists and the value does not.

rowCount = height(metrics);
coverage = emptyCoverage();

for index = 1:numel(temporalNames)
    name = temporalNames(index);
    values = metrics.(name);
    supported = nnz(isfinite(values));
    coverage(end + 1, :) = {name, "temporal", supported, 0, 0, 0, ...
        rowCount - supported, rowCount}; %#ok<AGROW>
end

for index = 1:height(featureMetrics)
    name = featureMetrics.metric_name(index);
    if isempty(featureStatus)
        states = strings(rowCount, 1);
    else
        states = featureStatus(:, index);
    end
    coverage(end + 1, :) = {name, "feature", ...
        nnz(states == "supported"), nnz(states == "not_eligible"), ...
        nnz(states == "not_measured"), ...
        nnz(states == "not_comparable_topology"), ...
        nnz(states == "non_finite"), rowCount}; %#ok<AGROW>
end

if height(coverage) == 0
    return
end
totals = coverage.supported + coverage.not_eligible + ...
    coverage.not_measured + coverage.not_comparable_topology + ...
    coverage.non_finite;
if any(totals ~= coverage.total)
    error("vawlume:eda:CoverageNotPartitioned", ...
        "Coverage categories must partition the row count exactly; a " + ...
        "metric whose categories do not sum to the total has lost an " + ...
        "observation somewhere.");
end
end

function value = emptyCoverage()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["metric_name", "metric_kind", "supported", ...
    "not_eligible", "not_measured", "not_comparable_topology", ...
    "non_finite", "total"]);
end
