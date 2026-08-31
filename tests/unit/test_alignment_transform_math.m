function tests = test_alignment_transform_math
%TEST_ALIGNMENT_TRANSFORM_MATH Transparent offset and affine fitting.
%
% Pure mathematics, no database. Every expectation is a deterministic transform
% the test itself constructs, so a recovered coefficient is checked against known
% truth rather than against whatever the implementation happens to produce.
tests = functiontests({ ...
    @testOffsetFromOneAnchorIsExact, ...
    @testOffsetFromSeveralAnchorsIsTheLeastSquaresMean, ...
    @testAffineFromTwoAnchorsIsExact, ...
    @testAffineFromManyAnchorsAbsorbsASmallPerturbation, ...
    @testRealisticClockDriftIsRecovered, ...
    @testCoefficientsDoNotDependOnAnchorOrder, ...
    @testAffineRejectsInsufficientOrDegenerateAnchors, ...
    @testNonFiniteAndMismatchedAnchorsAreRejected, ...
    @testPiecewiseAffineFailsClearly, ...
    @testResidualSummariesMatchTheirDefinitions});
end

% ------------------------------------------------------------------ offset ---

function testOffsetFromOneAnchorIsExact(testCase)
sourcePath = useSource(); %#ok<NASGU>
result = vawlume.alignment.solveTransform("offset", 4.216, 121.482);

verifyEqual(testCase, result.scale, 1);
verifyEqual(testCase, result.offset_s, 121.482 - 4.216, AbsTol=1e-12);
verifyEqual(testCase, result.n_anchors_used, 1);
verifyEqual(testCase, result.residual_s, 0, AbsTol=1e-12);
verifyEqual(testCase, result.rmse_s, 0, AbsTol=1e-12);
end

function testOffsetFromSeveralAnchorsIsTheLeastSquaresMean(testCase)
sourcePath = useSource(); %#ok<NASGU>
source = [10; 400; 900; 1500];
offset = 117.25;
% Three anchors sit exactly on the transform; one is deliberately 0.03 s late.
reference = source + offset;
reference(3) = reference(3) + 0.03;

result = vawlume.alignment.solveTransform("offset", source, reference);

% Under a fixed scale the least-squares offset is the mean difference.
verifyEqual(testCase, result.scale, 1);
verifyEqual(testCase, result.offset_s, mean(reference - source), AbsTol=1e-12);
verifyEqual(testCase, result.offset_s, offset + 0.03 / 4, AbsTol=1e-12);

% Residuals sum to zero for an OLS intercept, and the late anchor carries most.
verifyEqual(testCase, sum(result.residual_s), 0, AbsTol=1e-12);
verifyEqual(testCase, result.residual_s(3), 0.03 - 0.03 / 4, AbsTol=1e-12);
verifyEqual(testCase, result.max_abs_residual_s, 0.03 - 0.03 / 4, AbsTol=1e-12);
end

% ------------------------------------------------------------------ affine ---

function testAffineFromTwoAnchorsIsExact(testCase)
sourcePath = useSource(); %#ok<NASGU>
scale = 1.0015;
offset = 117.25;
source = [10; 1500];
reference = scale * source + offset;

result = vawlume.alignment.solveTransform("affine", source, reference);

verifyEqual(testCase, result.scale, scale, RelTol=1e-12);
verifyEqual(testCase, result.offset_s, offset, AbsTol=1e-9);
verifyEqual(testCase, result.residual_s, [0; 0], AbsTol=1e-9);
verifyEqual(testCase, result.rmse_s, 0, AbsTol=1e-9);
end

function testAffineFromManyAnchorsAbsorbsASmallPerturbation(testCase)
sourcePath = useSource(); %#ok<NASGU>
scale = 1.0015;
offset = 117.25;
source = [10; 400; 900; 1500];
reference = scale * source + offset;
reference(2) = reference(2) + 0.004;

result = vawlume.alignment.solveTransform("affine", source, reference);

% A 4 ms perturbation on one of four anchors must not move the coefficients far,
% and must leave a residual large enough to see.
verifyEqual(testCase, result.scale, scale, AbsTol=1e-5);
verifyEqual(testCase, result.offset_s, offset, AbsTol=5e-3);
verifyGreaterThan(testCase, result.max_abs_residual_s, 1e-3);
verifyLessThan(testCase, result.rmse_s, 4e-3);
verifyEqual(testCase, sum(result.residual_s), 0, AbsTol=1e-9);
end

function testRealisticClockDriftIsRecovered(testCase)
sourcePath = useSource(); %#ok<NASGU>
% A scale near 1 is the case that matters: two devices nominally agreeing but
% drifting by a few parts in ten thousand over a session.
scale = 0.9992;
offset = 53.40;
source = (0:150:1500)';
reference = scale * source + offset;

result = vawlume.alignment.solveTransform("affine", source, reference);

verifyEqual(testCase, result.scale, scale, RelTol=1e-12);
verifyEqual(testCase, result.offset_s, offset, AbsTol=1e-9);
verifyLessThan(testCase, result.max_abs_residual_s, 1e-9);

% Over 1500 s that drift is more than a second, so an offset-only fit of the
% same anchors is visibly worse. This is why the method is a declared choice.
offsetOnly = vawlume.alignment.solveTransform("offset", source, reference);
verifyGreaterThan(testCase, offsetOnly.max_abs_residual_s, 0.5);
end

% ------------------------------------------------------------ determinism ---

function testCoefficientsDoNotDependOnAnchorOrder(testCase)
sourcePath = useSource(); %#ok<NASGU>
scale = 1.0015;
offset = 117.25;
source = [10; 400; 900; 1500];
reference = scale * source + offset;
reference(3) = reference(3) - 0.002;

forward = vawlume.alignment.solveTransform("affine", source, reference);
shuffled = [3; 1; 4; 2];
reversed = vawlume.alignment.solveTransform("affine", ...
    source(shuffled), reference(shuffled));

verifyEqual(testCase, reversed.scale, forward.scale);
verifyEqual(testCase, reversed.offset_s, forward.offset_s);

% Residuals follow their own anchor rather than a row position.
verifyEqual(testCase, reversed.residual_s, forward.residual_s(shuffled), ...
    AbsTol=1e-12);
end

% ------------------------------------------------------------- rejections ---

function testAffineRejectsInsufficientOrDegenerateAnchors(testCase)
sourcePath = useSource(); %#ok<NASGU>
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("affine", 10, 127.265), ...
    "vawlume:alignment:InsufficientAnchors");

% Identical source times leave the scale undetermined; the fit must refuse
% rather than return whatever the pseudo-inverse produces.
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("affine", [10; 10; 10], [1; 2; 3]), ...
    "vawlume:alignment:DegenerateAnchors");

% One anchor is still a legal offset fit.
single = vawlume.alignment.solveTransform("offset", 10, 127.25);
verifyEqual(testCase, single.offset_s, 117.25, AbsTol=1e-12);
end

function testNonFiniteAndMismatchedAnchorsAreRejected(testCase)
sourcePath = useSource(); %#ok<NASGU>
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("affine", [10; NaN], [1; 2]), ...
    "vawlume:alignment:NonFiniteAnchor");
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("offset", [10; Inf], [1; 2]), ...
    "vawlume:alignment:NonFiniteAnchor");
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("offset", [10; 20], 1), ...
    "vawlume:alignment:AnchorPairMismatch");
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("offset", [], []), ...
    "vawlume:alignment:NoAnchors");
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("nearest_pulse", [1; 2], [3; 4]), ...
    "vawlume:alignment:MethodUnsupported");
end

function testPiecewiseAffineFailsClearly(testCase)
sourcePath = useSource(); %#ok<NASGU>
% The schema can represent piecewise segments. Fitting them is not implemented,
% and quietly returning one affine fit would answer a different question.
verifyError(testCase, ...
    @() vawlume.alignment.solveTransform("piecewise_affine", ...
    [10; 400; 900], [127; 518; 1019]), ...
    "vawlume:alignment:MethodNotImplemented");
end

% --------------------------------------------------------------- summaries ---

function testResidualSummariesMatchTheirDefinitions(testCase)
sourcePath = useSource(); %#ok<NASGU>
source = [10; 400; 900; 1500];
reference = 1.0015 * source + 117.25;
reference(1) = reference(1) + 0.01;
reference(4) = reference(4) - 0.006;

result = vawlume.alignment.solveTransform("affine", source, reference);

verifyEqual(testCase, result.predicted_reference_times, ...
    result.scale * source + result.offset_s, AbsTol=1e-12);
verifyEqual(testCase, result.residual_s, ...
    reference - result.predicted_reference_times, AbsTol=1e-12);
verifyEqual(testCase, result.rmse_s, ...
    sqrt(mean(result.residual_s .^ 2)), AbsTol=1e-12);
verifyEqual(testCase, result.max_abs_residual_s, ...
    max(abs(result.residual_s)), AbsTol=1e-12);

% Shape is preserved, so a caller keeps its own anchor association.
row = vawlume.alignment.solveTransform("affine", source', reference');
verifyEqual(testCase, size(row.residual_s), size(source'));
end

% ----------------------------------------------------------------- helpers ---

function cleanup = useSource()
%USESOURCE Put src on the path for the duration of one test.
%
% Other test files remove src in their teardown, so relying on an ambient path
% makes these tests pass alone and fail inside the suite. Each test adds it for
% itself, as every other test file in the repository does.
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repoRoot, "src");
addpath(sourcePath);
cleanup = onCleanup(@() rmpath(sourcePath));
end
