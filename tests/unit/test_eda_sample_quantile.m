function tests = test_eda_sample_quantile
%TEST_EDA_SAMPLE_QUANTILE The base-MATLAB quantile helper, against hand references.
%
% The helper exists so the exploratory diagnostics run under base MATLAB alone.
% `quantile`, `prctile` and `iqr` moved into base MATLAB only in recent
% releases and were Statistics and Machine Learning Toolbox functions before
% that, so calling one would make the workflow unavailable on an older release.
%
% Every expected value below is computed by hand from the stated definition, not
% by calling MATLAB's own quantile. A test that used the very function the
% helper is meant to replace would not be evidence that the helper is correct on
% a machine where that function is absent.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
% Add src/ if it is absent, and remove it only if this file added it. Several
% neighbouring suites call rmpath in their own teardown, so a suite that relies
% on the caller having set the path works alone and fails in company.
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

function testFourPointSampleMatchesTheHandComputedDefinition(testCase)
% n = 4, so the order statistics 1 2 3 4 sit at p = 0.125 0.375 0.625 0.875.
% q(0.25)  lies 0.125/0.25 of the way from 1 to 2  -> 1.5
% q(0.50)  lies midway between 2 and 3             -> 2.5
% q(0.75)  lies 0.125/0.25 of the way from 3 to 4  -> 3.5
sample = [1 2 3 4];
verifyEqual(testCase, vawlume.eda.sampleQuantile(sample, [.25 .50 .75]), ...
    [1.5 2.5 3.5], AbsTol=1e-12);
end

function testProbabilitiesOutsideThePlateauClampToTheExtremes(testCase)
% With n = 4 the first plateau is p = 0.125 and the last is p = 0.875, so any
% probability below or above those clamps rather than extrapolating. Without the
% clamp, linear extrapolation would invent values beyond the observed range.
sample = [1 2 3 4];
verifyEqual(testCase, vawlume.eda.sampleQuantile(sample, [0 .05 .10 .125]), ...
    [1 1 1 1], AbsTol=1e-12);
verifyEqual(testCase, vawlume.eda.sampleQuantile(sample, [.875 .90 .95 1]), ...
    [4 4 4 4], AbsTol=1e-12);
end

function testFivePointSampleHitsOrderStatisticsExactly(testCase)
% n = 5 places the order statistics at 0.1 0.3 0.5 0.7 0.9, so those five
% probabilities must return the sample values themselves with no interpolation.
sample = [10 20 30 40 50];
verifyEqual(testCase, ...
    vawlume.eda.sampleQuantile(sample, [.1 .3 .5 .7 .9]), ...
    [10 20 30 40 50], AbsTol=1e-12);
% Halfway between two plateaus is halfway between their order statistics.
verifyEqual(testCase, vawlume.eda.sampleQuantile(sample, .2), 15, AbsTol=1e-12);
verifyEqual(testCase, vawlume.eda.sampleQuantile(sample, .4), 25, AbsTol=1e-12);
end

function testInterquartileRangeFollowsFromTheSameDefinition(testCase)
sample = [1 2 3 4];
q = vawlume.eda.sampleQuantile(sample, [.25 .75]);
verifyEqual(testCase, q(2) - q(1), 2, AbsTol=1e-12);
end

function testUnsortedInputAndRepeatedValuesAreHandled(testCase)
verifyEqual(testCase, vawlume.eda.sampleQuantile([4 1 3 2], [.25 .5 .75]), ...
    [1.5 2.5 3.5], AbsTol=1e-12);
verifyEqual(testCase, vawlume.eda.sampleQuantile([7 7 7 7], [0 .5 1]), ...
    [7 7 7], AbsTol=1e-12);
end

function testNaNEntriesAreIgnoredRatherThanPoisoningTheResult(testCase)
% NaN is dropped, as MATLAB's own quantile drops it, so the remaining four
% values give the same answer as the clean four-point sample.
verifyEqual(testCase, ...
    vawlume.eda.sampleQuantile([1 NaN 2 3 NaN 4], [.25 .5 .75]), ...
    [1.5 2.5 3.5], AbsTol=1e-12);
end

function testDegenerateSamplesReportRatherThanRaise(testCase)
% A metric with no supported observation is a fact to report, not an error.
verifyEqual(testCase, vawlume.eda.sampleQuantile([], [.25 .5]), [NaN NaN]);
verifyEqual(testCase, vawlume.eda.sampleQuantile([NaN NaN], .5), NaN);
verifyEqual(testCase, vawlume.eda.sampleQuantile(42, [0 .5 1]), [42 42 42]);
end

function testOutputShapeFollowsTheProbabilityShape(testCase)
verifyEqual(testCase, size(vawlume.eda.sampleQuantile(1:10, [.1; .9])), [2 1]);
verifyEqual(testCase, size(vawlume.eda.sampleQuantile(1:10, [.1 .9])), [1 2]);
end

function testProbabilitiesOutsideTheUnitIntervalAreRefused(testCase)
verifyError(testCase, @() vawlume.eda.sampleQuantile(1:10, -0.1), ...
    "vawlume:eda:ProbabilityOutOfRange");
verifyError(testCase, @() vawlume.eda.sampleQuantile(1:10, 1.5), ...
    "vawlume:eda:ProbabilityOutOfRange");
end

function testNoStatisticsToolboxFunctionIsCalledInThePackage(testCase)
% The diagnostics must remain available to a base-MATLAB user. corr and
% partialcorr are Statistics and Machine Learning Toolbox functions in every
% release; quantile, prctile and iqr were until recently, so the package avoids
% all five rather than depending on the reader's release.
root = testCase.TestData.repo_root;
files = dir(fullfile(root, "src", "+vawlume", "+eda", "**", "*.m"));
verifyGreaterThan(testCase, numel(files), 0);
forbidden = ["corr", "partialcorr", "quantile", "prctile", "iqr", ...
    "tiedrank", "zscore", "nanmean", "nanmedian"];
for index = 1:numel(files)
    text = string(fileread(fullfile(files(index).folder, files(index).name)));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for name = forbidden
        verifyFalse(testCase, ...
            ~isempty(regexp(body, "(?<![\w.])" + name + "\s*\(", "once")), ...
            files(index).name + " calls " + name);
    end
end
end
