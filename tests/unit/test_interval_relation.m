function tests = test_interval_relation
%TEST_INTERVAL_RELATION Domain-neutral interval arithmetic contract.
tests = functiontests(localfunctions);
end

function testIdenticalIntervals(testCase)
actual = vawlume.interval.relation(1, 3, 1, 3);

verifyEqual(testCase, actual, expectedRelation(2, 2, 1, 0, 0, 0));
verifyEqual(testCase, string(fieldnames(actual)), [ ...
    "intersection_s"; "union_s"; "temporal_iou"; ...
    "onset_difference_s"; "offset_difference_s"; ...
    "duration_difference_s"]);
end

function testDisjointIntervals(testCase)
actual = vawlume.interval.relation(1, 2, 3, 4);

verifyEqual(testCase, actual, expectedRelation(0, 3, 0, 2, 2, 0));
end

function testIntervalsTouchingAtOneBoundary(testCase)
actual = vawlume.interval.relation(1, 2, 2, 4);

verifyEqual(testCase, actual, expectedRelation(0, 3, 0, 1, 2, 1));
end

function testOneIntervalContainsTheOther(testCase)
actual = vawlume.interval.relation(1, 5, 2, 4);

verifyEqual(testCase, actual, expectedRelation(2, 4, .5, 1, -1, -2));
end

function testCoincidentZeroLengthIntervalsHaveUndefinedIou(testCase)
actual = vawlume.interval.relation(2, 2, 2, 2);

verifyEqual(testCase, actual.intersection_s, 0);
verifyEqual(testCase, actual.union_s, 0);
verifyTrue(testCase, isnan(actual.temporal_iou));
verifyEqual(testCase, actual.onset_difference_s, 0);
verifyEqual(testCase, actual.offset_difference_s, 0);
verifyEqual(testCase, actual.duration_difference_s, 0);
end

function testZeroLengthAgainstPositiveIntervalHasZeroIou(testCase)
actual = vawlume.interval.relation(2, 2, 1, 3);

verifyEqual(testCase, actual, expectedRelation(0, 2, 0, -1, 1, 2));
end

function testReversingArgumentsNegatesOnlyDirectionalDifferences(testCase)
forward = vawlume.interval.relation(1, 5, 2, 4);
reverse = vawlume.interval.relation(2, 4, 1, 5);

verifyEqual(testCase, reverse.intersection_s, forward.intersection_s);
verifyEqual(testCase, reverse.union_s, forward.union_s);
verifyEqual(testCase, reverse.temporal_iou, forward.temporal_iou);
verifyEqual(testCase, reverse.onset_difference_s, ...
    -forward.onset_difference_s);
verifyEqual(testCase, reverse.offset_difference_s, ...
    -forward.offset_difference_s);
verifyEqual(testCase, reverse.duration_difference_s, ...
    -forward.duration_difference_s);
end

function testReversedIntervalsAreRefused(testCase)
verifyError(testCase, @() vawlume.interval.relation(2, 1, 3, 4), ...
    "vawlume:interval:ReversedInterval");
verifyError(testCase, @() vawlume.interval.relation(1, 2, 4, 3), ...
    "vawlume:interval:ReversedInterval");
end

function value = expectedRelation(intersectionS, unionS, temporalIou, ...
        onsetDifferenceS, offsetDifferenceS, durationDifferenceS)
value = struct( ...
    intersection_s=intersectionS, ...
    union_s=unionS, ...
    temporal_iou=temporalIou, ...
    onset_difference_s=onsetDifferenceS, ...
    offset_difference_s=offsetDifferenceS, ...
    duration_difference_s=durationDifferenceS);
end
