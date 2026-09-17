function result = metricDistributions(surface, options)
%METRICDISTRIBUTIONS Shape and coverage of every candidate metric in a surface.
%
% RESULT = vawlume.eda.METRICDISTRIBUTIONS(SURFACE) summarizes each metric of a
% vawlume.eda.candidateMetrics surface with its coverage counts, extremes,
% median, interquartile range, and the robust quantiles the governing contract
% fixes.
%
% Name-value options:
%   Probabilities                 quantile probabilities, default
%                                 [0.05 0.10 0.25 0.50 0.75 0.90 0.95]
%   MinimumSupportedObservations  below this many supported observations the
%                                 statistics are reported as undefined rather
%                                 than computed, default 2
%   NearConstantTolerance         relative tolerance of the near-constant rule,
%                                 default 1e-9
%
% RESULT.distributions has one row per metric. A metric with too few supported
% observations KEEPS ITS ROW, carrying its counts and NaN statistics under a
% named status. An omitted row looks like a metric nobody asked for, which is a
% different and misleading thing.
%
% Quantiles use vawlume.eda.sampleQuantile, whose definition is recorded in
% RESULT.quantile_definition and which is implemented in base MATLAB so the
% diagnostics do not depend on a toolbox.
%
% Constant and near-constant metrics are FLAGGED, never removed. The conceptual
% specification is explicit that the MVP must not automatically delete a
% scientifically requested dimension on the strength of a statistic; the finding
% travels with the metric so a later leverage report can be read in its light,
% and the dimension is screened anyway.
%
% This function is pure. It takes no connection, reads no database, and draws
% nothing: the distribution figures are built from this table elsewhere.

arguments
    surface (1,1) struct
    options.Probabilities (1,:) double = [0.05 0.10 0.25 0.50 0.75 0.90 0.95]
    options.MinimumSupportedObservations (1,1) double {mustBeNonnegative} = 2
    options.NearConstantTolerance (1,1) double {mustBeNonnegative} = 1e-9
end

requireFields(surface, ["metrics", "metric_names", "coverage"]);
probabilities = sort(options.Probabilities);
if any(probabilities < 0 | probabilities > 1)
    error("vawlume:eda:ProbabilityOutOfRange", ...
        "Every requested probability must lie in [0, 1].");
end

names = string(surface.metric_names(:))';
quantileNames = "q" + replace(string(compose("%05.3f", probabilities)), ".", "_");
if numel(unique(quantileNames)) ~= numel(quantileNames)
    error("vawlume:eda:ProbabilityNotDistinct", ...
        "Requested quantile probabilities must be distinct to three decimals.");
end

distributions = emptyDistributions(quantileNames);
for index = 1:numel(names)
    distributions(end + 1, :) = summarizeMetric(surface, names(index), ...
        probabilities, options); %#ok<AGROW>
end

result = struct( ...
    status="summarized", ...
    metric_count=numel(names), ...
    candidate_count=height(surface.metrics), ...
    distributions=distributions, ...
    quantile_probabilities=probabilities, ...
    quantile_names=quantileNames, ...
    quantile_definition=quantileDefinition(), ...
    iqr_definition="q(0.75) - q(0.25) under the recorded quantile definition", ...
    near_constant_rule=nearConstantRule(options.NearConstantTolerance), ...
    minimum_supported_observations=options.MinimumSupportedObservations, ...
    coverage_categories=edaCoverageCategories()', ...
    statistics_implementation= ...
        "base MATLAB; no Statistics and Machine Learning Toolbox call", ...
    caution=edaCautionNote());
end

function row = summarizeMetric(surface, name, probabilities, options)
if ~ismember(name, string(surface.metrics.Properties.VariableNames))
    error("vawlume:eda:MetricNotPresent", ...
        "Metric '%s' is named by the surface but absent from its table.", name);
end
values = double(surface.metrics.(name));
finiteValues = values(isfinite(values));
supported = numel(finiteValues);
counts = coverageFor(surface, name, numel(values), supported);

quantiles = NaN(1, numel(probabilities));
minimum = NaN;
maximum = NaN;
medianValue = NaN;
iqrValue = NaN;
isConstant = false;
isNearConstant = false;
isIqrDegenerate = false;
distinctCount = 0;

if supported == 0
    status = "no_supported_observations";
elseif supported < options.MinimumSupportedObservations
    status = "insufficient_observations";
    distinctCount = numel(unique(finiteValues));
else
    status = "computed";
    quantiles = vawlume.eda.sampleQuantile(finiteValues, probabilities);
    minimum = min(finiteValues);
    maximum = max(finiteValues);
    medianValue = vawlume.eda.sampleQuantile(finiteValues, 0.5);
    iqrValue = vawlume.eda.sampleQuantile(finiteValues, 0.75) - ...
        vawlume.eda.sampleQuantile(finiteValues, 0.25);
    distinctCount = numel(unique(finiteValues));
    span = maximum - minimum;
    isConstant = span == 0;
    isNearConstant = ~isConstant && span <= ...
        options.NearConstantTolerance * max(1, abs(medianValue));
    isIqrDegenerate = iqrValue == 0 && distinctCount > 2;
end

row = [{name, metricKind(surface, name), ismember(name, ...
    string(surface.absolute_metric_names)), counts.supported, ...
    counts.not_eligible, counts.not_measured, ...
    counts.not_comparable_topology, counts.non_finite, counts.total, ...
    distinctCount, status, minimum, maximum, medianValue, iqrValue}, ...
    num2cell(quantiles), ...
    {isConstant, isNearConstant, isIqrDegenerate, ...
    constancyNote(isConstant, isNearConstant, isIqrDegenerate)}];
end

function counts = coverageFor(surface, name, total, supported)
%COVERAGEFOR Take the surface's coverage row, or derive a temporal-only one.
%
% A hand-built surface used in a unit test may carry no row for a metric. The
% derived fallback is correct for a metric computed on every row, which is what
% every temporal metric is; it never invents a feature category.
counts = struct(supported=supported, not_eligible=0, not_measured=0, ...
    not_comparable_topology=0, non_finite=total - supported, total=total);
if ~istable(surface.coverage) || height(surface.coverage) == 0
    return
end
selected = find(string(surface.coverage.metric_name) == name, 1);
if isempty(selected)
    return
end
for field = ["supported", "not_eligible", "not_measured", ...
        "not_comparable_topology", "non_finite", "total"]
    counts.(field) = double(surface.coverage.(field)(selected));
end
if counts.supported ~= supported
    error("vawlume:eda:CoverageDisagrees", ...
        "Metric '%s' has %d finite values but its coverage row reports %d " + ...
        "supported.", name, supported, counts.supported);
end
end

function value = metricKind(surface, name)
value = "temporal";
if isfield(surface, "feature_metric_names") && ...
        ismember(name, string(surface.feature_metric_names))
    value = "feature";
end
end

function value = constancyNote(isConstant, isNearConstant, isIqrDegenerate)
notes = strings(0, 1);
if isConstant
    notes(end + 1) = "constant";
end
if isNearConstant
    notes(end + 1) = "near_constant";
end
if isIqrDegenerate
    notes(end + 1) = "zero_interquartile_range";
end
if isempty(notes)
    value = "none";
    return
end
value = strjoin(notes, "|");
end

function value = quantileDefinition()
value = "linear interpolation between order statistics, with the i-th of n " + ...
    "placed at cumulative probability (i-0.5)/n and probabilities outside " + ...
    "that range clamped to the extreme order statistics";
end

function value = nearConstantRule(tolerance)
value = "constant when max-min == 0; near-constant when max-min <= " + ...
    string(tolerance) + " * max(1, abs(median)); " + ...
    "zero_interquartile_range reported separately when the interquartile " + ...
    "range is 0 while more than two distinct values are present. " + ...
    "Flags annotate the metric and never remove it.";
end

function requireFields(surface, names)
missingNames = names(~isfield(surface, names));
if ~isempty(missingNames)
    error("vawlume:eda:SurfaceInvalid", ...
        "The supplied surface is missing required field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end

function value = emptyDistributions(quantileNames)
head = table(strings(0, 1), strings(0, 1), false(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), ...
    VariableNames=["metric_name", "metric_kind", "is_absolute", ...
    "supported", "not_eligible", "not_measured", ...
    "not_comparable_topology", "non_finite", "total", "distinct_values", ...
    "statistics_status", "minimum", "maximum", "median", ...
    "interquartile_range"]);
middle = array2table(zeros(0, numel(quantileNames)), ...
    VariableNames=quantileNames);
tail = table(false(0, 1), false(0, 1), false(0, 1), strings(0, 1), ...
    VariableNames=["is_constant", "is_near_constant", ...
    "is_zero_interquartile_range", "constancy_note"]);
value = [head, middle, tail];
end
