function tests = test_eda_metric_dependencies
%TEST_EDA_METRIC_DEPENDENCIES Pearson, Spearman and partial correlation diagnostics.
%
% Every function under test is pure, so every interesting case is constructible
% and unit coverage is both sufficient and demanding here.
%
% Two tests carry most of the weight. The conditional-structure test is what
% proves the partial correlation is actually partial rather than a marginal
% correlation wearing the wrong label - an easy defect to ship and a hard one to
% notice. The mid-rank tie test is where a hand-written Spearman goes wrong.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repoRoot, "src");
testCase.TestData.repo_root = repoRoot;
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

% ------------------------------------------------------------ mid-ranks ---

function testMidRankAssignsAverageRanksToTies(testCase)
% 10 20 20 30: the two 20s occupy ranks 2 and 3, so both take 2.5.
verifyEqual(testCase, vawlume.eda.midRank([10 20 20 30]), [1 2.5 2.5 4], ...
    AbsTol=1e-12);
% Every value tied: all take the mean of 1..3.
verifyEqual(testCase, vawlume.eda.midRank([5 5 5]), [2 2 2], AbsTol=1e-12);
% Unsorted input, with a three-way tie at ranks 2,3,4.
verifyEqual(testCase, vawlume.eda.midRank([9 1 4 4 4]), [5 1 3 3 3], ...
    AbsTol=1e-12);
verifyEqual(testCase, size(vawlume.eda.midRank([1; 2; 3])), [3 1]);
verifyEqual(testCase, size(vawlume.eda.midRank([1 2 3])), [1 3]);
end

function testMidRankRefusesNonFiniteValues(testCase)
% A rank is a statement about position in a particular sample. Dropping NaN
% would silently return a vector shorter than the caller passed.
verifyError(testCase, @() vawlume.eda.midRank([1 NaN 3]), ...
    "vawlume:eda:RankRequiresFiniteValues");
verifyError(testCase, @() vawlume.eda.midRank([1 Inf 3]), ...
    "vawlume:eda:RankRequiresFiniteValues");
end

% ------------------------------------------------- known toy correlations ---

function testPearsonAndSpearmanMatchHandComputedValues(testCase)
% x = 1 2 3 4, y = 1 3 2 4.
%   dx = -1.5 -0.5 0.5 1.5, dy = -1.5 0.5 -0.5 1.5
%   sum(dx.*dy) = 4, sum(dx^2) = sum(dy^2) = 5, so r = 4/5 = 0.8 exactly.
% Neither vector has ties, so the ranks equal the values and Spearman matches.
result = dependenciesOf(["x", "y"], [1 2 3 4]', [1 3 2 4]');
row = result.pairs;
verifyEqual(testCase, row.pearson, 0.8, AbsTol=1e-12);
verifyEqual(testCase, row.spearman, 0.8, AbsTol=1e-12);
verifyEqual(testCase, row.observations, 4);
verifyEqual(testCase, row.correlation_undefined_reason, "");
end

function testPerfectLinearRelationshipsAreExactlyPlusOrMinusOne(testCase)
x = (1:10)';
verifyEqual(testCase, dependenciesOf(["x", "y"], x, 2 * x + 1).pairs.pearson, ...
    1, AbsTol=1e-12);
verifyEqual(testCase, dependenciesOf(["x", "y"], x, -3 * x + 7).pairs.pearson, ...
    -1, AbsTol=1e-12);
end

function testSpearmanUsesMidRanksWhenTiesArePresent(testCase)
% x = 1 2 2 4 ranks as 1 2.5 2.5 4; y = 1 2 3 4 ranks as itself.
%   drx = -1.5 0 0 1.5, dry = -1.5 -0.5 0.5 1.5
%   sum(drx.*dry) = 4.5, sum(drx^2) = 4.5, sum(dry^2) = 5
%   rho = 4.5 / sqrt(4.5 * 5) = sqrt(0.9)
result = dependenciesOf(["x", "y"], [1 2 2 4]', [1 2 3 4]');
verifyEqual(testCase, result.pairs.spearman, sqrt(0.9), AbsTol=1e-12);
% Ordinal ranks would have given 1 exactly, so this value distinguishes the two.
verifyNotEqual(testCase, round(result.pairs.spearman, 6), 1);
end

function testMonotoneNonlinearIsWhereTheTwoMeasuresDisagree(testCase)
% The case that justifies reporting both: a strictly increasing but sharply
% curved relationship has Spearman exactly 1 while Pearson is clearly lower.
x = linspace(0.01, 1, 100)';
result = dependenciesOf(["x", "y"], x, x .^ 6);
verifyEqual(testCase, result.pairs.spearman, 1, AbsTol=1e-12);
verifyLessThan(testCase, result.pairs.pearson, 0.85);
verifyGreaterThan(testCase, result.pairs.pearson, 0.5);
end

function testEveryCellCarriesItsOwnObservationCount(testCase)
% A correlation computed on 11 pairs and one computed on 11,000 are
% indistinguishable as numbers, so the count is not optional.
rng(3);
x = randn(40, 1);
y = randn(40, 1);
z = randn(40, 1);
z(1:12) = NaN;
result = dependenciesOf(["x", "y", "z"], x, y, z);
verifyEqual(testCase, result.observation_policy.mode, "listwise");
verifyEqual(testCase, result.observation_policy.complete_case_n, 28);
verifyEqual(testCase, unique(result.pairs.observations), 28);
verifyEqual(testCase, size(result.correlation_observations), [3 3]);
end

% ------------------------------------------------- conditional structure ---

function testPartialCorrelationIsActuallyPartial(testCase)
% X and Y are correlated ONLY through Z. Their marginal correlation is strong;
% their partial correlation, controlling for Z, must collapse toward zero.
%
% This is the test that catches an implementation returning marginal
% correlations mislabelled as partial.
rng(11);
n = 400;
z = randn(n, 1);
x = z + 0.3 * randn(n, 1);
y = z + 0.3 * randn(n, 1);
result = dependenciesOf(["x", "y", "z"], x, y, z);

xy = pairOf(result, "x", "y");
verifyGreaterThan(testCase, xy.pearson, 0.85, ...
    "The marginal association must be strong for this test to mean anything.");
verifyLessThan(testCase, abs(xy.partial), 0.10);
verifyEqual(testCase, xy.partial_undefined_reason, "");

% The genuinely direct relationships survive conditioning.
xz = pairOf(result, "x", "z");
verifyGreaterThan(testCase, abs(xz.partial), 0.5);

verifyEqual(testCase, result.partial.status, "computed");
verifyEqual(testCase, result.partial.source, "pearson");
verifyEqual(testCase, result.partial.regularization, "none");
verifyEqual(testCase, diag(result.partial.matrix), ones(3, 1), AbsTol=1e-12);
end

% ----------------------------------------------------- degeneracy cases ---

function testConstantColumnIsExcludedByNameAndNeverReturnedAsZero(testCase)
rng(5);
result = dependenciesOf(["a", "b", "c"], randn(40, 1), randn(40, 1), ...
    7 * ones(40, 1));

verifyEqual(testCase, height(result.excluded_metrics), 1);
verifyEqual(testCase, result.excluded_metrics.metric_name, "c");
verifyEqual(testCase, result.excluded_metrics.reason, "constant_column");

ac = pairOf(result, "a", "c");
verifyTrue(testCase, isnan(ac.pearson));
verifyTrue(testCase, isnan(ac.spearman));
verifyTrue(testCase, isnan(ac.partial));
verifyEqual(testCase, ac.correlation_undefined_reason, "constant_column");
verifyEqual(testCase, ac.partial_undefined_reason, "constant_column");

% The surviving pair is still computed: one degenerate column does not sink
% the whole diagnostic.
verifyEqual(testCase, pairOf(result, "a", "b").correlation_undefined_reason, "");
verifyEqual(testCase, result.partial.status, "computed");
verifyEqual(testCase, sort(result.partial.retained_metric_names), ["a", "b"]);
end

function testNearConstantColumnGetsItsOwnReason(testCase)
rng(7);
base = randn(40, 1);
nearly = 1 + 1e-12 * (1:40)';
result = dependenciesOf(["a", "b", "n"], base, randn(40, 1), nearly);

verifyEqual(testCase, result.excluded_metrics.metric_name, "n");
verifyEqual(testCase, result.excluded_metrics.reason, "near_constant_column");
verifyEqual(testCase, pairOf(result, "a", "n").correlation_undefined_reason, ...
    "near_constant_column");
end

function testTooFewObservationsInACellGetsItsOwnReason(testCase)
% Two jointly finite observations is below the floor: a Pearson correlation on
% two points is always exactly +/-1 and carries no information.
a = [1; 2; NaN; NaN; NaN; NaN];
b = [2; 5; NaN; NaN; NaN; NaN];
result = dependenciesOf(["a", "b"], a, b);
verifyEqual(testCase, result.observation_policy.mode, "pairwise");
verifyEqual(testCase, result.pairs.correlation_undefined_reason, ...
    "insufficient_observations");
verifyEqual(testCase, result.pairs.observations, 2);
verifyTrue(testCase, isnan(result.pairs.pearson));
end

function testNoOverlappingObservationsGetsItsOwnReason(testCase)
a = [1; 2; NaN; NaN];
b = [NaN; NaN; 3; 4];
result = dependenciesOf(["a", "b"], a, b);
verifyEqual(testCase, result.pairs.correlation_undefined_reason, ...
    "no_overlapping_observations");
verifyEqual(testCase, result.pairs.observations, 0);
end

function testNearSingularStructureIsCaughtBeforeInversion(testCase)
% An exact duplicate column makes the correlation matrix singular. The guard
% must fire on the reciprocal condition number rather than relying on `inv`
% raising, because `inv` does not raise here - it returns numerical noise.
rng(13);
a = randn(50, 1);
result = dependenciesOf(["a", "b", "d"], a, randn(50, 1), a);

verifyEqual(testCase, result.partial.status, "undefined");
verifyEqual(testCase, result.partial.reason, "ill_conditioned");
verifyLessThan(testCase, result.partial.reciprocal_condition_number, 1e-10);
verifyTrue(testCase, all(isnan(result.partial.matrix(:))));
verifyTrue(testCase, all(result.pairs.partial_undefined_reason == ...
    "ill_conditioned"));

% The marginal correlations remain defined: only the inversion failed.
verifyEqual(testCase, pairOf(result, "a", "d").pearson, 1, AbsTol=1e-12);
verifyEqual(testCase, pairOf(result, "a", "d").correlation_undefined_reason, "");
end

function testEveryReasonUsedComesFromTheFixedVocabulary(testCase)
rng(17);
result = dependenciesOf(["a", "b", "c"], randn(40, 1), randn(40, 1), ...
    3 * ones(40, 1));
vocabulary = [""; edaVocabulary()];
verifyTrue(testCase, all(ismember( ...
    result.correlation_undefined_reason(:), vocabulary)));
verifyTrue(testCase, all(ismember( ...
    result.partial.undefined_reason(:), vocabulary)));
verifyEqual(testCase, sort(result.undefined_reason_vocabulary(:)), ...
    sort(edaVocabulary()));
end

% ------------------------------------------------- missing-value policy ---

function testListwiseIsThePrimaryPathAndIsRecorded(testCase)
rng(19);
x = randn(50, 1);
y = randn(50, 1);
y(1:5) = NaN;
result = dependenciesOf(["x", "y"], x, y);
verifyEqual(testCase, result.observation_policy.mode, "listwise");
verifyEqual(testCase, result.observation_policy.complete_case_n, 45);
verifyEqual(testCase, result.observation_policy.required_minimum, 12);
verifyEqual(testCase, result.pairs.observations, 45);
verifyTrue(testCase, contains(result.observation_policy.description, ...
    "Listwise"));
end

function testSparseColumnTriggersThePairwiseFallback(testCase)
% The fallback is expected rather than hypothetical: a feature-discrepancy
% column is sparse wherever an extractor registers few comparable features, so
% listwise deletion across every metric can retain almost nothing.
rng(23);
a = randn(60, 1);
b = randn(60, 1);
sparseColumn = NaN(60, 1);
sparseColumn(1:3) = randn(3, 1);
result = dependenciesOf(["a", "b", "sparse"], a, b, sparseColumn);

verifyEqual(testCase, result.observation_policy.mode, "pairwise");
verifyEqual(testCase, result.observation_policy.complete_case_n, 3);
verifyEqual(testCase, result.observation_policy.required_minimum, 13);

% Marginals are computed pairwise and labelled as such, each on its own sample.
verifyEqual(testCase, pairOf(result, "a", "b").observations, 60);
verifyEqual(testCase, pairOf(result, "a", "sparse").observations, 3);
verifyEqual(testCase, pairOf(result, "a", "b").correlation_undefined_reason, "");

% The partial matrix is entirely undefined with the fixed reason.
verifyEqual(testCase, result.partial.status, "undefined");
verifyEqual(testCase, result.partial.reason, "insufficient_observations");
verifyTrue(testCase, all(isnan(result.partial.matrix(:))));

% The culprit is named, so a caller can restrict Metrics and recover a usable
% partial correlation rather than only learning that it failed.
limiting = result.observation_policy.limiting_metrics;
verifyEqual(testCase, limiting.metric_name(1), "sparse");
verifyEqual(testCase, limiting.non_finite_rows(1), 57);
verifyEqual(testCase, limiting.complete_cases_lost_alone(1), 57);
verifyEqual(testCase, limiting.complete_cases_without_it(1), 60);
verifyEqual(testCase, limiting.non_finite_rows(2:3), [0; 0]);

% Restricting to the well-covered metrics does recover it.
recovered = vawlume.eda.metricDependencies( ...
    surfaceOf(["a", "b", "sparse"], a, b, sparseColumn), Metrics=["a", "b"]);
verifyEqual(testCase, recovered.observation_policy.mode, "listwise");
verifyEqual(testCase, recovered.partial.status, "computed");
end

function testPairwiseDeletionMayYieldANonPsdMatrixAndItIsNotPatched(testCase)
% Pairwise cells rest on different samples, so the assembled matrix need not be
% positive semi-definite. The honest response is to report the deletion mode and
% return the matrix as computed, not to project it onto the nearest valid one.
a = [1; 2; 3; 4; 5; 6; NaN; NaN; NaN];
b = [1; 2; 3; NaN; NaN; NaN; 1; 2; 3];
c = [NaN; NaN; NaN; 1; 2; 3; 3; 2; 1];
result = dependenciesOf(["a", "b", "c"], a, b, c);

verifyEqual(testCase, result.observation_policy.mode, "pairwise");
verifyTrue(testCase, contains(result.observation_policy.description, ...
    "positive semi-definite"));

matrix = result.pearson;
verifyTrue(testCase, all(isfinite(matrix(:))), ...
    "This fixture is built so every pairwise cell is computable.");
verifyLessThan(testCase, min(eig(matrix)), -1e-9, ...
    "The fixture is chosen so the pairwise matrix is genuinely non-PSD.");
verifyEqual(testCase, diag(matrix), ones(3, 1), AbsTol=1e-12);
verifyEqual(testCase, result.partial.status, "undefined");
end

% ------------------------------------------------------------ redundancy ---

function testRedundancyIsReportedWithItsConsequenceAndNothingIsPruned(testCase)
rng(29);
base = randn(80, 1);
nearCopy = base + 0.02 * randn(80, 1);
independent = randn(80, 1);
result = vawlume.eda.metricDependencies( ...
    surfaceOf(["temporal_iou", "abs_onset_difference_s", "other"], ...
    base, nearCopy, independent));

verifyEqual(testCase, height(result.redundancy), 1);
row = result.redundancy;
verifyEqual(testCase, sort([row.metric_a, row.metric_b]), ...
    ["abs_onset_difference_s", "temporal_iou"]);
verifyGreaterThan(testCase, row.strongest_magnitude, 0.90);
verifyEqual(testCase, row.screening_relevance, "both_screened_factors");
verifyTrue(testCase, contains(row.consequence, "cannot be attributed"));

% Nothing was removed: every requested metric is still in the output.
verifyEqual(testCase, result.metric_names, ...
    ["temporal_iou", "abs_onset_difference_s", "other"]);
verifyEqual(testCase, height(result.pairs), 3);
verifyTrue(testCase, any(contains(result.interpretation, "Nothing was pruned")));
verifyTrue(testCase, any(contains(result.interpretation, "SCREENED FACTORS")));
end

function testAnUnrelatedMetricSetReportsNoRedundancy(testCase)
rng(31);
result = dependenciesOf(["a", "b", "c"], randn(100, 1), randn(100, 1), ...
    randn(100, 1));
verifyEqual(testCase, height(result.redundancy), 0);
verifyTrue(testCase, any(contains(result.interpretation, ...
    "No metric pair reached the redundancy threshold")));
end

% ------------------------------------------------------------- contract ---

function testNoInferentialMachineryAppearsAnywhere(testCase)
% These are dependency measures over a convenience sample of candidate pairs.
% Attaching a p-value would imply a sampling model this MVP does not have.
rng(37);
result = dependenciesOf(["a", "b"], randn(30, 1), randn(30, 1));
verifyFalse(testCase, any(contains(string(fieldnames(result)), ...
    ["p_value", "pvalue", "confidence", "significance"], IgnoreCase=true)));
verifyFalse(testCase, any(contains(result.pairs.Properties.VariableNames, ...
    ["p_value", "confidence"], IgnoreCase=true)));
verifyTrue(testCase, contains(result.inference_note, "No p-value"));

root = testCase.TestData.repo_root;
files = dir(fullfile(root, "src", "+vawlume", "+eda", "**", "*.m"));
for index = 1:numel(files)
    text = string(fileread(fullfile(files(index).folder, files(index).name)));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for forbidden = ["ttest", "normcdf", "tcdf", "anova", "ridge", "lasso"]
        verifyFalse(testCase, ...
            ~isempty(regexp(body, "(?<![\w.])" + forbidden + "\s*\(", "once")), ...
            files(index).name + " calls " + forbidden);
    end
end
end

function testMalformedRequestsAreRefused(testCase)
rng(41);
surface = surfaceOf(["a", "b"], randn(20, 1), randn(20, 1));
verifyError(testCase, @() vawlume.eda.metricDependencies( ...
    rmfield(surface, "metrics")), "vawlume:eda:SurfaceInvalid");
verifyError(testCase, @() vawlume.eda.metricDependencies(surface, ...
    Metrics="nope"), "vawlume:eda:MetricNotPresent");
verifyError(testCase, @() vawlume.eda.metricDependencies(surface, ...
    Metrics="a"), "vawlume:eda:TooFewMetrics");
verifyError(testCase, @() vawlume.eda.metricDependencies(surface, ...
    Metrics=["a", "a"]), "vawlume:eda:MetricNotDistinct");
verifyError(testCase, @() vawlume.eda.metricDependencies(surface, ...
    RedundancyThreshold=1.5), "vawlume:eda:RedundancyThresholdInvalid");
end

function testMatricesAreSymmetricAndShareOneShapeAndOrdering(testCase)
rng(43);
result = dependenciesOf(["a", "b", "c"], randn(50, 1), randn(50, 1), ...
    randn(50, 1));
for matrix = {result.pearson, result.spearman, result.partial.matrix, ...
        result.correlation_observations}
    value = matrix{1};
    verifyEqual(testCase, size(value), [3 3]);
    verifyEqual(testCase, value, value', AbsTol=1e-12);
end
verifyEqual(testCase, diag(result.pearson), ones(3, 1), AbsTol=1e-12);
verifyEqual(testCase, height(result.pairs), 3);
verifyEqual(testCase, numel(result.caution), 4);
end

% ---------------------------------------------------------------- helpers ---

function result = dependenciesOf(names, varargin)
result = vawlume.eda.metricDependencies(surfaceOf(names, varargin{:}));
end

function surface = surfaceOf(names, varargin)
metrics = table();
for index = 1:numel(names)
    metrics.(names(index)) = varargin{index}(:);
end
surface = struct(metrics=metrics, metric_names=string(names));
end

function row = pairOf(result, a, b)
selected = (result.pairs.metric_a == a & result.pairs.metric_b == b) | ...
    (result.pairs.metric_a == b & result.pairs.metric_b == a);
row = result.pairs(selected, :);
end

function value = edaVocabulary()
value = ["constant_column"; "near_constant_column"; ...
    "insufficient_observations"; "ill_conditioned"; ...
    "no_overlapping_observations"];
end
