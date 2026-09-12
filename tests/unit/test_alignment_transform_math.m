function tests = test_alignment_transform_math
%TEST_ALIGNMENT_TRANSFORM_MATH Transparent offset, affine, and piecewise fitting.
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
    @testPiecewiseRecoversATwoSegmentDriftChange, ...
    @testPiecewiseRecoversThreeSegmentsAndAttributesAnchors, ...
    @testBreakpointOnAnAnchorBelongsToTheLaterSegment, ...
    @testPiecewiseSegmentsAreContinuousAtTheirBreakpoints, ...
    @testPiecewiseOverAStraightLineAgreesWithAffine, ...
    @testPiecewiseRejectsUndeclaredAndImpossibleBreakpoints, ...
    @testPiecewiseRejectsAnchorSetsThatCannotDetermineIt, ...
    @testEverySolvedTransformReportsSegments, ...
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

% --------------------------------------------------------- piecewise affine ---

function testPiecewiseRecoversATwoSegmentDriftChange(testCase)
sourcePath = useSource(); %#ok<NASGU>
knot = 600;
[source, reference, scale, offset] = piecewiseFixture([1.0015; 0.9990], 117.25, knot);

result = vawlume.alignment.solveTransform("piecewise_affine", source, ...
    reference, Breakpoints=knot);

verifyEqual(testCase, result.method, "piecewise_affine");
verifyEqual(testCase, height(result.segments), 2);
verifyEqual(testCase, result.segments.scale, scale, RelTol=1e-9);
verifyEqual(testCase, result.segments.offset_s, offset, AbsTol=1e-9);
verifyLessThan(testCase, result.max_abs_residual_s, 1e-9);

% A piecewise transform has no single slope. Returning the first segment's would
% answer a question the caller did not ask.
verifyTrue(testCase, isnan(result.scale));
verifyTrue(testCase, isnan(result.offset_s));

% The first segment is open below and the last open above, so every finite
% source time falls in exactly one of them.
verifyTrue(testCase, isnan(result.segments.source_start(1)));
verifyEqual(testCase, result.segments.source_end(1), knot);
verifyEqual(testCase, result.segments.source_start(2), knot);
verifyTrue(testCase, isnan(result.segments.source_end(2)));

verifyEqual(testCase, result.breakpoints, knot);
end

function testPiecewiseRecoversThreeSegmentsAndAttributesAnchors(testCase)
sourcePath = useSource(); %#ok<NASGU>
knots = [400; 1000];
[source, reference, scale, offset] = piecewiseFixture( ...
    [1.0020; 0.9985; 1.0007], 50, knots);

result = vawlume.alignment.solveTransform("piecewise_affine", source, ...
    reference, Breakpoints=knots);

verifyEqual(testCase, height(result.segments), 3);
verifyEqual(testCase, result.segments.scale, scale, RelTol=1e-9);
verifyEqual(testCase, result.segments.offset_s, offset, AbsTol=1e-9);
verifyLessThan(testCase, result.max_abs_residual_s, 1e-9);

% Every anchor is attributed to exactly one segment, and the counts add up.
verifyEqual(testCase, sum(result.segments.anchor_count), numel(source));
expected = 1 + double(source >= knots(1)) + double(source >= knots(2));
verifyEqual(testCase, result.segment_index, expected);

% Coefficients are a property of the anchor set, not of row order.
permutation = [7; 3; 11; 1; 14; 5; 9; 2; 16; 6; 12; 4; 10; 8; 15; 13];
shuffled = vawlume.alignment.solveTransform("piecewise_affine", ...
    source(permutation), reference(permutation), Breakpoints=knots);
verifyEqual(testCase, shuffled.segments.scale, result.segments.scale);
verifyEqual(testCase, shuffled.segments.offset_s, result.segments.offset_s);

% Shape is preserved, so a caller keeps its own anchor association.
row = vawlume.alignment.solveTransform("piecewise_affine", source', ...
    reference', Breakpoints=knots);
verifyEqual(testCase, size(row.residual_s), size(source'));
verifyEqual(testCase, size(row.segment_index), size(source'));
end

function testBreakpointOnAnAnchorBelongsToTheLaterSegment(testCase)
sourcePath = useSource(); %#ok<NASGU>
knot = 600;
[source, reference] = piecewiseFixture([1.0015; 0.9990], 117.25, knot);

% The fixture places an anchor exactly on the breakpoint. A segment covers
% [source_start, source_end), so that anchor belongs to the segment beginning
% there — the rule the applier must agree with, and the off-by-one most likely
% to survive review.
verifyEqual(testCase, nnz(source == knot), 1);
result = vawlume.alignment.solveTransform("piecewise_affine", source, ...
    reference, Breakpoints=knot);
verifyEqual(testCase, result.segment_index(source == knot), 2);
verifyEqual(testCase, result.segments.anchor_count(1), nnz(source < knot));
verifyEqual(testCase, result.segments.anchor_count(2), nnz(source >= knot));
end

function testPiecewiseSegmentsAreContinuousAtTheirBreakpoints(testCase)
sourcePath = useSource(); %#ok<NASGU>
knots = [400; 1000];
[source, reference] = piecewiseFixture([1.0020; 0.9985; 1.0007], 50, knots);

result = vawlume.alignment.solveTransform("piecewise_affine", source, ...
    reference, Breakpoints=knots);

% Both segments meeting at a breakpoint must give the same reference time there.
% A discontinuity would map one source instant to two reference times.
for index = 1:numel(knots)
    left = result.segments.scale(index) * knots(index) + ...
        result.segments.offset_s(index);
    right = result.segments.scale(index + 1) * knots(index) + ...
        result.segments.offset_s(index + 1);
    verifyEqual(testCase, left, right, AbsTol=1e-9);
end
end

function testPiecewiseOverAStraightLineAgreesWithAffine(testCase)
sourcePath = useSource(); %#ok<NASGU>
source = [10; 400; 900; 1500];
reference = 1.0015 * source + 117.25;

% Anchors that really do lie on one line: every segment should recover that one
% line. This is the cheapest available check that the hinge-basis path did not
% quietly change the arithmetic the affine path already had.
affine = vawlume.alignment.solveTransform("affine", source, reference);
piecewise = vawlume.alignment.solveTransform("piecewise_affine", source, ...
    reference, Breakpoints=700);

verifyEqual(testCase, piecewise.segments.scale, ...
    repmat(affine.scale, 2, 1), AbsTol=1e-12);
verifyEqual(testCase, piecewise.segments.offset_s, ...
    repmat(affine.offset_s, 2, 1), AbsTol=1e-9);
verifyEqual(testCase, piecewise.predicted_reference_times, ...
    affine.predicted_reference_times, AbsTol=1e-9);
end

function testPiecewiseRejectsUndeclaredAndImpossibleBreakpoints(testCase)
sourcePath = useSource(); %#ok<NASGU>
[source, reference] = piecewiseFixture([1.0015; 0.9990], 117.25, 600);
solve = @(knots) vawlume.alignment.solveTransform("piecewise_affine", ...
    source, reference, Breakpoints=knots);

% VAWLUME does not search for a breakpoint, so a piecewise request without one
% has nothing to fit. It says so rather than falling back to affine.
verifyError(testCase, @() vawlume.alignment.solveTransform( ...
    "piecewise_affine", source, reference), ...
    "vawlume:alignment:BreakpointsRequired");

verifyError(testCase, @() solve([700; 300]), "vawlume:alignment:BreakpointsInvalid");
verifyError(testCase, @() solve([300; 300]), "vawlume:alignment:BreakpointsInvalid");
verifyError(testCase, @() solve(NaN), "vawlume:alignment:BreakpointsInvalid");
verifyError(testCase, @() solve(Inf), "vawlume:alignment:BreakpointsInvalid");

% At or beyond an end of the anchored span leaves a segment nothing to determine
% it with.
verifyError(testCase, @() solve(min(source)), "vawlume:alignment:BreakpointsInvalid");
verifyError(testCase, @() solve(max(source)), "vawlume:alignment:BreakpointsInvalid");
verifyError(testCase, @() solve(max(source) + 1), "vawlume:alignment:BreakpointsInvalid");

% Declaring where segments meet is meaningless for a method that has one.
verifyError(testCase, @() vawlume.alignment.solveTransform("affine", ...
    source, reference, Breakpoints=600), "vawlume:alignment:BreakpointsInvalid");
verifyError(testCase, @() vawlume.alignment.solveTransform("offset", ...
    source, reference, Breakpoints=600), "vawlume:alignment:BreakpointsInvalid");
end

function testPiecewiseRejectsAnchorSetsThatCannotDetermineIt(testCase)
sourcePath = useSource(); %#ok<NASGU>

% A segment holding no anchor has a slope no observation determines.
verifyError(testCase, @() vawlume.alignment.solveTransform("piecewise_affine", ...
    [0; 1; 2; 40], [0; 1; 2; 40], Breakpoints=[5; 35]), ...
    "vawlume:alignment:SegmentUnderdetermined");

% Two segments carry three parameters, so three anchors are the minimum.
verifyError(testCase, @() vawlume.alignment.solveTransform("piecewise_affine", ...
    [0; 10; 20], [0; 10; 20], Breakpoints=[5; 15]), ...
    "vawlume:alignment:InsufficientAnchors");

% Anchors that repeat two source times cannot determine two slopes.
verifyError(testCase, @() vawlume.alignment.solveTransform("piecewise_affine", ...
    [0; 0; 20; 20], [1; 1; 21; 21], Breakpoints=10), ...
    "vawlume:alignment:DegenerateAnchors");

% A clock does not run backwards, so a segmentation that implies it is refused
% rather than persisted as a transform nothing could apply meaningfully.
verifyError(testCase, @() vawlume.alignment.solveTransform("piecewise_affine", ...
    [0; 10; 20; 30], [0; 10; 5; 0], Breakpoints=15), ...
    "vawlume:alignment:NonPositiveTransformScale");

% And the existing guards still apply to the new method.
verifyError(testCase, @() vawlume.alignment.solveTransform("piecewise_affine", ...
    [5; 5; 5; 5], [1; 2; 3; 4], Breakpoints=5), ...
    "vawlume:alignment:DegenerateAnchors");
end

function testEverySolvedTransformReportsSegments(testCase)
sourcePath = useSource(); %#ok<NASGU>
source = [10; 400; 900; 1500];
reference = 1.0015 * source + 117.25;

% Offset and affine return one open-ended segment, so a caller reads one shape
% regardless of method and the database sees one row per segment either way.
for method = ["offset", "affine"]
    result = vawlume.alignment.solveTransform(method, source, reference);
    verifyEqual(testCase, height(result.segments), 1);
    verifyEqual(testCase, result.segments.segment_index, 1);
    verifyTrue(testCase, isnan(result.segments.source_start));
    verifyTrue(testCase, isnan(result.segments.source_end));
    verifyEqual(testCase, result.segments.scale, result.scale);
    verifyEqual(testCase, result.segments.offset_s, result.offset_s);
    verifyEqual(testCase, result.segments.anchor_count, numel(source));
    verifyEqual(testCase, result.segment_index, ones(size(source)));
    verifyEmpty(testCase, result.breakpoints);
end
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

function [source, reference, scale, offset] = piecewiseFixture(scale, firstOffset, knots)
%PIECEWISEFIXTURE Anchors generated from a known continuous piecewise transform.
%
% The segment offsets are derived from continuity rather than chosen, so the
% fixture cannot accidentally describe a transform with a step in it. These are
% test ground truth; they are not a claim that real device clocks drift this way.
scale = scale(:);
knots = knots(:);
offset = zeros(numel(scale), 1);
offset(1) = firstOffset;
for index = 2:numel(scale)
    offset(index) = (scale(index - 1) - scale(index)) * knots(index - 1) + ...
        offset(index - 1);
end

% Anchors every 100 s, which places one exactly on each breakpoint used here.
source = (0:100:1500)';
segment = ones(numel(source), 1);
for index = 1:numel(knots)
    segment = segment + double(source >= knots(index));
end
reference = scale(segment) .* source + offset(segment);
end

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
