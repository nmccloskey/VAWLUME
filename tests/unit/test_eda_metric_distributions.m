function tests = test_eda_metric_distributions
%TEST_EDA_METRIC_DISTRIBUTIONS Distribution, coverage and constancy reporting.
%
% The distribution layer is pure: it takes an assembled surface and returns a
% table. These tests build minimal surfaces by hand so each behaviour is
% exercised on a sample whose statistics can be computed on paper.
%
% Two properties matter more than the arithmetic. A metric with too few
% supported observations must keep its row, because an omitted row looks like a
% metric nobody asked for. And a constant or near-constant metric must be
% flagged and kept, because the conceptual specification forbids deleting a
% scientifically requested dimension on the strength of a statistic.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repoRoot, "src");
testCase.TestData.source_path = sourcePath;
testCase.TestData.added_path = ~contains(path, sourcePath);
if testCase.TestData.added_path
    addpath(sourcePath);
end
end

function teardownOnce(testCase)
if testCase.TestData.added_path && contains(path, testCase.TestData.source_path)
    rmpath(testCase.TestData.source_path);
end
end

function testStatisticsMatchTheHandComputedDefinition(testCase)
% Sample 1 2 3 4: q(0.25)=1.5, q(0.5)=2.5, q(0.75)=3.5, so IQR is exactly 2.
surface = surfaceWith("metric_one", [1 2 3 4]);
result = vawlume.eda.metricDistributions(surface);
row = rowFor(result, "metric_one");

verifyEqual(testCase, row.statistics_status, "computed");
verifyEqual(testCase, row.supported, 4);
verifyEqual(testCase, row.minimum, 1, AbsTol=1e-12);
verifyEqual(testCase, row.maximum, 4, AbsTol=1e-12);
verifyEqual(testCase, row.median, 2.5, AbsTol=1e-12);
verifyEqual(testCase, row.interquartile_range, 2, AbsTol=1e-12);
verifyEqual(testCase, row.q0_250, 1.5, AbsTol=1e-12);
verifyEqual(testCase, row.q0_500, 2.5, AbsTol=1e-12);
verifyEqual(testCase, row.q0_750, 3.5, AbsTol=1e-12);
verifyEqual(testCase, row.q0_050, 1, AbsTol=1e-12);
verifyEqual(testCase, row.q0_950, 4, AbsTol=1e-12);
verifyEqual(testCase, row.distinct_values, 4);

verifyEqual(testCase, result.quantile_probabilities, ...
    [0.05 0.10 0.25 0.50 0.75 0.90 0.95], AbsTol=1e-12);
verifyTrue(testCase, contains(result.quantile_definition, "(i-0.5)/n"));
verifyTrue(testCase, contains(result.statistics_implementation, "base MATLAB"));
end

function testNonFiniteValuesAreExcludedFromTheStatisticsButCounted(testCase)
surface = surfaceWith("metric_one", [1 2 3 4 NaN Inf]);
result = vawlume.eda.metricDistributions(surface);
row = rowFor(result, "metric_one");

verifyEqual(testCase, row.supported, 4);
verifyEqual(testCase, row.non_finite, 2);
verifyEqual(testCase, row.total, 6);
verifyEqual(testCase, row.median, 2.5, AbsTol=1e-12);
verifyEqual(testCase, row.maximum, 4, AbsTol=1e-12);
end

function testAThinMetricKeepsItsRowWithUndefinedStatistics(testCase)
surface = surfaceWith("metric_one", [7 NaN NaN NaN]);
result = vawlume.eda.metricDistributions(surface);
row = rowFor(result, "metric_one");

verifyEqual(testCase, height(result.distributions), 1);
verifyEqual(testCase, row.statistics_status, "insufficient_observations");
verifyEqual(testCase, row.supported, 1);
verifyEqual(testCase, row.non_finite, 3);
verifyEqual(testCase, row.total, 4);
verifyTrue(testCase, isnan(row.median));
verifyTrue(testCase, isnan(row.interquartile_range));
verifyTrue(testCase, isnan(row.q0_500));
end

function testAMetricWithNoSupportedObservationKeepsItsRowToo(testCase)
surface = surfaceWith("metric_one", [NaN NaN]);
result = vawlume.eda.metricDistributions(surface);
row = rowFor(result, "metric_one");

verifyEqual(testCase, row.statistics_status, "no_supported_observations");
verifyEqual(testCase, row.supported, 0);
verifyTrue(testCase, isnan(row.minimum));
verifyTrue(testCase, isnan(row.maximum));
end

function testTheObservationFloorIsConfigurableAndRecorded(testCase)
surface = surfaceWith("metric_one", [1 2 3]);
strict = vawlume.eda.metricDistributions(surface, ...
    MinimumSupportedObservations=4);
relaxed = vawlume.eda.metricDistributions(surface, ...
    MinimumSupportedObservations=3);

verifyEqual(testCase, rowFor(strict, "metric_one").statistics_status, ...
    "insufficient_observations");
verifyEqual(testCase, rowFor(relaxed, "metric_one").statistics_status, ...
    "computed");
verifyEqual(testCase, strict.minimum_supported_observations, 4);
end

function testConstantMetricIsFlaggedAndKept(testCase)
surface = surfaceWith("metric_one", [5 5 5 5]);
result = vawlume.eda.metricDistributions(surface);
row = rowFor(result, "metric_one");

verifyTrue(testCase, row.is_constant);
verifyFalse(testCase, row.is_near_constant);
verifyEqual(testCase, row.constancy_note, "constant");
verifyEqual(testCase, row.interquartile_range, 0, AbsTol=1e-12);
verifyEqual(testCase, height(result.distributions), 1, ...
    "A flagged metric is annotated, never removed.");
end

function testNearConstantFiresBelowItsThresholdAndNotAboveIt(testCase)
% The rule is max-min <= tolerance * max(1, abs(median)). With a median near 1
% the threshold is the tolerance itself, so a span just inside it fires and a
% span just outside it does not. Testing only the firing side would leave the
% threshold itself unverified.
tolerance = 1e-6;
below = surfaceWith("metric_one", [1, 1 + 0.5e-6]);
above = surfaceWith("metric_one", [1, 1 + 2e-6]);

fired = rowFor(vawlume.eda.metricDistributions(below, ...
    NearConstantTolerance=tolerance), "metric_one");
notFired = rowFor(vawlume.eda.metricDistributions(above, ...
    NearConstantTolerance=tolerance), "metric_one");

verifyTrue(testCase, fired.is_near_constant);
verifyFalse(testCase, fired.is_constant);
verifyEqual(testCase, fired.constancy_note, "near_constant");
verifyFalse(testCase, notFired.is_near_constant);
verifyEqual(testCase, notFired.constancy_note, "none");
end

function testZeroInterquartileRangeIsReportedSeparatelyFromConstancy(testCase)
% Eleven values, nine of them identical: the middle half is flat while the
% metric is neither constant nor near-constant. Reporting that as constancy
% would be wrong, and not reporting it at all would hide a degenerate column
% from the dependency layer.
surface = surfaceWith("metric_one", [0 5 5 5 5 5 5 5 5 5 10]);
row = rowFor(vawlume.eda.metricDistributions(surface), "metric_one");

verifyFalse(testCase, row.is_constant);
verifyFalse(testCase, row.is_near_constant);
verifyTrue(testCase, row.is_zero_interquartile_range);
verifyEqual(testCase, row.constancy_note, "zero_interquartile_range");
verifyEqual(testCase, row.interquartile_range, 0, AbsTol=1e-12);
verifyEqual(testCase, row.distinct_values, 3);
end

function testNearConstantRuleAndCoverageVocabularyAreRecorded(testCase)
result = vawlume.eda.metricDistributions(surfaceWith("metric_one", [1 2 3 4]));
verifyTrue(testCase, contains(result.near_constant_rule, "max-min == 0"));
verifyTrue(testCase, contains(result.near_constant_rule, "never remove"));
verifyEqual(testCase, sort(result.coverage_categories), ...
    sort(["supported", "not_eligible", "not_measured", ...
    "not_comparable_topology", "non_finite"]));
verifyEqual(testCase, numel(result.caution), 4);
end

function testCoverageRowsAreCarriedThroughFromTheSurface(testCase)
surface = surfaceWith("metric_one", [1 2 NaN NaN]);
surface.coverage = table("metric_one", "feature", 2, 1, 1, 0, 0, 4, ...
    VariableNames=["metric_name", "metric_kind", "supported", ...
    "not_eligible", "not_measured", "not_comparable_topology", ...
    "non_finite", "total"]);
surface.feature_metric_names = "metric_one";
row = rowFor(vawlume.eda.metricDistributions(surface), "metric_one");

verifyEqual(testCase, row.metric_kind, "feature");
verifyEqual(testCase, row.not_eligible, 1);
verifyEqual(testCase, row.not_measured, 1);
verifyEqual(testCase, row.non_finite, 0);
end

function testCoverageDisagreeingWithTheDataIsRefused(testCase)
% A coverage row that does not match the values it describes means the surface
% and its accounting have diverged, which would misreport how much of the
% dataset a statistic rests on.
surface = surfaceWith("metric_one", [1 2 NaN NaN]);
surface.coverage = table("metric_one", "temporal", 4, 0, 0, 0, 0, 4, ...
    VariableNames=["metric_name", "metric_kind", "supported", ...
    "not_eligible", "not_measured", "not_comparable_topology", ...
    "non_finite", "total"]);
verifyError(testCase, @() vawlume.eda.metricDistributions(surface), ...
    "vawlume:eda:CoverageDisagrees");
end

function testMalformedRequestsAreRefused(testCase)
surface = surfaceWith("metric_one", [1 2 3 4]);
verifyError(testCase, @() vawlume.eda.metricDistributions( ...
    rmfield(surface, "metrics")), "vawlume:eda:SurfaceInvalid");
verifyError(testCase, @() vawlume.eda.metricDistributions(surface, ...
    Probabilities=[0.5 1.5]), "vawlume:eda:ProbabilityOutOfRange");

absent = surface;
absent.metric_names = "not_a_column";
verifyError(testCase, @() vawlume.eda.metricDistributions(absent), ...
    "vawlume:eda:MetricNotPresent");
end

function testEveryNamedMetricProducesExactlyOneRow(testCase)
surface = surfaceWith("metric_one", [1 2 3 4]);
surface.metrics.metric_two = [10; 20; 30; 40];
surface.metric_names = ["metric_one", "metric_two"];
result = vawlume.eda.metricDistributions(surface);

verifyEqual(testCase, height(result.distributions), 2);
verifyEqual(testCase, result.metric_count, 2);
verifyEqual(testCase, sort(result.distributions.metric_name), ...
    ["metric_one"; "metric_two"]);
end

% ---------------------------------------------------------------- helpers ---

function surface = surfaceWith(name, values)
%SURFACEWITH A minimal hand-built surface carrying one metric column.
%
% The distribution layer takes no connection and reads no database, so a plain
% struct is a complete input. That is the point of separating calculation from
% assembly.
metrics = table(values(:), VariableNames=name);
surface = struct( ...
    metrics=metrics, ...
    metric_names=string(name), ...
    coverage=table.empty(0, 0), ...
    absolute_metric_names=strings(1, 0), ...
    feature_metric_names=strings(1, 0));
end

function row = rowFor(result, name)
row = result.distributions(result.distributions.metric_name == name, :);
end
