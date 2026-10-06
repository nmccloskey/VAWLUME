function tests = test_geometry_spatial_primitives
%TEST_GEOMETRY_SPATIAL_PRIMITIVES The pure spatial primitives of +geometry/.
%
% vawlume.geometry.distance, positionAtInstants and summarizeDistances are the
% first spatial arithmetic in VAWLUME (docs/design/06_native_estimator_contract.md
% D3, D4). Their value is in the POLICY: what they refuse, what they mark as not
% computed, and what basis every number carries. These tests are mostly about
% that, with known-input/known-output checks for the arithmetic itself.
%
% No database is opened here, which is part of the point: the primitives are
% pure, so their policy is testable without one.
tests = functiontests(localfunctions);
end

function setupOnce(~)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(repoRoot, "src"));
end

% --- distance: the arithmetic ---------------------------------------------

function testThreeFourFiveInATwoDimensionalFrame(testCase)
result = vawlume.geometry.distance([0 0], frame2d(), [3 4], frame2d());
verifyEqual(testCase, result.distance, 5, AbsTol=1e-12);
verifyEqual(testCase, result.status, "computed");
verifyEqual(testCase, result.basis, "planar");
verifyEqual(testCase, result.unit, "cm");
verifyEqual(testCase, result.coordinate_system_id, 1);
end

function testThreeDimensionalDistanceUsesZ(testCase)
result = vawlume.geometry.distance([0 0 0], frame3d(), [2 3 6], frame3d());
verifyEqual(testCase, result.distance, 7, AbsTol=1e-12);
verifyEqual(testCase, result.basis, "spatial_3d");
end

function testOneRowIsPairedWithEveryRowOfTheOther(testCase)
% One microphone against several tracked samples.
result = vawlume.geometry.distance([0 0], frame2d(), [3 4; 6 8; 0 1], frame2d());
verifyEqual(testCase, result.distance, [5; 10; 1], AbsTol=1e-12);
end

% --- distance: frames ------------------------------------------------------

function testDifferentFramesAreRefusedThroughTheIdentityRule(testCase)
% Same dimensionality, same unit, different frame: still refused, by the same
% rule and identifier vawlume.geometry.assertCompatible uses.
other = struct(coordinate_system_id=2, dimensionality=2, unit="cm");
verifyError(testCase, @() vawlume.geometry.distance([0 0], frame2d(), [3 4], other), ...
    "vawlume:geometry:CoordinateSystemMismatch");
end

function testDescriptorsDisagreeingAboutOneFrameAreRefused(testCase)
wrongUnit = struct(coordinate_system_id=1, dimensionality=2, unit="mm");
verifyError(testCase, @() vawlume.geometry.distance([0 0], frame2d(), [3 4], wrongUnit), ...
    "vawlume:geometry:FrameDescriptorConflict");
end

function testAnIncompleteDescriptorIsRefused(testCase)
verifyError(testCase, @() vawlume.geometry.distance([0 0], ...
    struct(coordinate_system_id=1, dimensionality=2), [3 4], frame2d()), ...
    "vawlume:geometry:FrameDescriptorInvalid");
end

function testTheUnitIsCarriedVerbatimAndNotInterpreted(testCase)
% A px frame's distance is in px. Whether px may be treated as uniform-scale is a
% consumer's declared decision, not this function's.
px = struct(coordinate_system_id=5, dimensionality=2, unit="px");
result = vawlume.geometry.distance([0 0], px, [30 40], px);
verifyEqual(testCase, result.distance, 50, AbsTol=1e-12);
verifyEqual(testCase, result.unit, "px");
end

% --- distance: dimensionality and absence ----------------------------------

function testMissingZInAThreeDimensionalFrameIsNotComputed(testCase)
% Never computed in the plane with z treated as 0.
result = vawlume.geometry.distance([0 0 NaN; 0 0 0], frame3d(), [3 4 0], frame3d());
verifyTrue(testCase, isnan(result.distance(1)));
verifyEqual(testCase, result.status(1), "not_computed");
verifyEqual(testCase, result.reason(1), "z_missing");
verifyEqual(testCase, result.distance(2), 5, AbsTol=1e-12);
end

function testATwoColumnPositionInAThreeDimensionalFrameHasNoZ(testCase)
result = vawlume.geometry.distance([0 0], frame3d(), [3 4 0], frame3d());
verifyEqual(testCase, result.reason, "z_missing");
end

function testPlanarDistanceInThreeDimensionsIsOptInAndLabelled(testCase)
result = vawlume.geometry.distance([0 0 NaN], frame3d(), [3 4 10], frame3d(), ...
    PlanarIn3D=true);
verifyEqual(testCase, result.distance, 5, AbsTol=1e-12);
verifyEqual(testCase, result.basis, "planar_declared");
end

function testATwoDimensionalPlacementReadBackWithNaNZIsAccepted(testCase)
% readChannelPlacements returns position_z = NaN for a 2D frame.
result = vawlume.geometry.distance([0 0 NaN], frame2d(), [3 4], frame2d());
verifyEqual(testCase, result.distance, 5, AbsTol=1e-12);
end

function testARealZUnderATwoDimensionalFrameIsRefused(testCase)
verifyError(testCase, @() vawlume.geometry.distance([0 0 1], frame2d(), [3 4], frame2d()), ...
    "vawlume:geometry:PositionDimensionalityInvalid");
end

function testAMissingCoordinateIsAbsenceNotZero(testCase)
result = vawlume.geometry.distance([NaN 0; 0 0], frame2d(), [3 4], frame2d());
verifyTrue(testCase, isnan(result.distance(1)));
verifyEqual(testCase, result.reason(1), "position_missing");
verifyEqual(testCase, result.status, ["not_computed"; "computed"]);
end

function testMismatchedRowCountsAreRefused(testCase)
verifyError(testCase, @() vawlume.geometry.distance([0 0; 1 1], frame2d(), ...
    [3 4; 1 1; 2 2], frame2d()), "vawlume:geometry:PositionCountMismatch");
end

% --- positionAtInstants ----------------------------------------------------

function testAnExactSampleHitIsObservedNotInterpolated(testCase)
r = vawlume.geometry.positionAtInstants([0; 1; 2], [0 0; 10 0; 20 0], 1, MaxGapS=1);
verifyEqual(testCase, [r.x r.y], [10 0]);
verifyEqual(testCase, r.basis, "observed");
verifyEqual(testCase, r.gap_s, 0);
end

function testBetweenSamplesIsLinearlyInterpolated(testCase)
r = vawlume.geometry.positionAtInstants([0; 1], [0 0; 10 20], 0.25, MaxGapS=1);
verifyEqual(testCase, [r.x r.y], [2.5 5], AbsTol=1e-12);
verifyEqual(testCase, r.basis, "interpolated");
verifyEqual(testCase, [r.bracket_before_time r.bracket_after_time], [0 1]);
end

function testAGapAtTheMaximumIsInterpolatedAndAboveItIsNot(testCase)
% The threshold is inclusive. A hair above it is not an estimate.
atMax = vawlume.geometry.positionAtInstants([0; 0.5], [0 0; 10 0], 0.25, MaxGapS=0.5);
verifyEqual(testCase, atMax.basis, "interpolated");
above = vawlume.geometry.positionAtInstants([0; 0.5], [0 0; 10 0], 0.25, ...
    MaxGapS=0.5 - 1e-9);
verifyEqual(testCase, above.basis, "not_covered");
verifyEqual(testCase, above.reason, "gap_exceeds_max");
verifyTrue(testCase, isnan(above.x));
verifyEqual(testCase, above.gap_s, 0.5, AbsTol=1e-12);
end

function testThereIsNoExtrapolation(testCase)
r = vawlume.geometry.positionAtInstants([1; 2], [0 0; 10 0], [0.9; 2.1], MaxGapS=10);
verifyEqual(testCase, r.basis, ["not_covered"; "not_covered"]);
verifyEqual(testCase, r.reason, ["before_first_sample"; "after_last_sample"]);
verifyTrue(testCase, all(isnan(r.x)));
end

function testASingleSampleTraceCoversOnlyItsOwnInstant(testCase)
r = vawlume.geometry.positionAtInstants(1, [5 5], [1; 1.01], MaxGapS=10);
verifyEqual(testCase, r.basis, ["observed"; "not_covered"]);
verifyEqual(testCase, r.reason(2), "after_last_sample");
end

function testAnEmptyTraceHasNoSamples(testCase)
r = vawlume.geometry.positionAtInstants(zeros(0, 1), zeros(0, 2), 1, MaxGapS=1);
verifyEqual(testCase, r.reason, "no_samples");
end

function testUnsortedTimesAreRefusedNotSorted(testCase)
verifyError(testCase, @() vawlume.geometry.positionAtInstants([1; 0], ...
    [0 0; 1 1], 0.5, MaxGapS=1), "vawlume:geometry:SampleTimesInvalid");
end

function testDuplicateTimesAreRefused(testCase)
verifyError(testCase, @() vawlume.geometry.positionAtInstants([0; 0], ...
    [0 0; 1 1], 0, MaxGapS=1), "vawlume:geometry:SampleTimesInvalid");
end

function testMaxGapHasNoDefault(testCase)
verifyError(testCase, @() vawlume.geometry.positionAtInstants([0; 1], ...
    [0 0; 1 1], 0.5), "vawlume:geometry:MaxGapRequired");
end

function testADroppedSampleBecomesAGapRatherThanABracket(testCase)
% The middle sample has no position. Bracketing across it would interpolate
% over 2 s with MaxGapS = 1.5; dropping it lets the gap rule judge honestly.
r = vawlume.geometry.positionAtInstants([0; 1; 2], [0 0; NaN NaN; 20 0], 0.5, ...
    MaxGapS=1.5);
verifyEqual(testCase, r.reason, "gap_exceeds_max");
verifyEqual(testCase, r.gap_s, 2, AbsTol=1e-12);
end

function testPoseConfidenceTravelsBesideThePosition(testCase)
r = vawlume.geometry.positionAtInstants([0; 1], [0 0; 10 0], 0.5, MaxGapS=1, ...
    PoseConfidence=[0.9; 0.6]);
verifyEqual(testCase, [r.pose_confidence_before r.pose_confidence_after], [0.9 0.6]);
verifyEqual(testCase, r.pose_confidence_min_bracket, 0.6);
verifyEqual(testCase, [r.x r.y], [5 0], AbsTol=1e-12);
end

function testAMissingBracketConfidenceIsNotImputed(testCase)
% min(0.9, missing) would be 0.9 under omitnan, which invents a value for the
% bracket that had none.
r = vawlume.geometry.positionAtInstants([0; 1], [0 0; 10 0], 0.5, MaxGapS=1, ...
    PoseConfidence=[0.9; NaN]);
verifyTrue(testCase, isnan(r.pose_confidence_min_bracket));
end

function testZIsInterpolatedOnlyWhenBothBracketsHaveIt(testCase)
r = vawlume.geometry.positionAtInstants([0; 1; 2], [0 0 0; 10 0 10; 20 0 NaN], ...
    [0.5; 1.5], MaxGapS=1);
verifyEqual(testCase, r.z(1), 5, AbsTol=1e-12);
verifyTrue(testCase, isnan(r.z(2)));
verifyEqual(testCase, r.basis, ["interpolated"; "interpolated"]);
end

% --- summarizeDistances ------------------------------------------------------

function testSummariesOverAPopulatedWindow(testCase)
s = vawlume.geometry.summarizeDistances([4; 2; 9], repmat("observed", 3, 1));
verifyEqual(testCase, [s.window_median s.window_min], [4 2]);
verifyEqual(testCase, [s.n_samples s.n_computed], [3 3]);
verifyEqual(testCase, s.status, "computed");
end

function testUncomputedDistancesAreExcludedAndCounted(testCase)
s = vawlume.geometry.summarizeDistances([4; NaN; 8], repmat("observed", 3, 1));
verifyEqual(testCase, s.window_median, 6);
verifyEqual(testCase, [s.n_samples s.n_computed], [3 2]);
end

function testAnEmptyWindowIsNotAZero(testCase)
s = vawlume.geometry.summarizeDistances(zeros(0, 1), strings(0, 1));
verifyEqual(testCase, s.status, "not_covered");
verifyEqual(testCase, s.reason, "no_samples");
verifyTrue(testCase, isnan(s.window_median) && isnan(s.window_min));
end

function testAWindowWithNoComputedDistanceSaysSo(testCase)
s = vawlume.geometry.summarizeDistances([NaN; NaN], ["observed"; "observed"]);
verifyEqual(testCase, s.reason, "no_computed_distance");
verifyEqual(testCase, s.n_samples, 2);
end

function testInterpolatedPositionsCannotBeSummarized(testCase)
verifyError(testCase, @() vawlume.geometry.summarizeDistances([1; 2], ...
    ["observed"; "interpolated"]), "vawlume:geometry:SummaryBasisInvalid");
end

% --- helpers --------------------------------------------------------------

function value = frame2d()
value = struct(coordinate_system_id=1, dimensionality=2, unit="cm");
end

function value = frame3d()
value = struct(coordinate_system_id=3, dimensionality=3, unit="mm");
end
