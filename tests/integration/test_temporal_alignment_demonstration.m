function tests = test_temporal_alignment_demonstration
%TEST_TEMPORAL_ALIGNMENT_DEMONSTRATION Runnable synthetic Pass 7 example.
tests = functiontests(localfunctions);
end

function testDemoRecoversTransformsAndLeavesNoCanonicalDenseRows(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
examplePath = fullfile(repoRoot, "examples");
addpath(examplePath);
cleanup = onCleanup(@() rmpath(examplePath));

value = temporal_alignment_demo(Print=false, RepoRoot=repoRoot);
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyLessThan(testCase, max(value.recovered_parameters.scale_absolute_error), 1e-9);
verifyLessThan(testCase, max(value.recovered_parameters.offset_absolute_error_s), 1e-6);
verifyGreaterThanOrEqual(testCase, height(value.qc.residuals), 6);
verifyTrue(testCase, any(value.common_time_events.alignment_kind == "identity"));
verifyTrue(testCase, any(value.common_time_events.alignment_kind == ...
    "stored_transform"));
verifyTrue(testCase, any(value.timeline.call_count == 0));
verifyTrue(testCase, any(isnan(value.timeline.call_count)));
verifyEqual(testCase, value.database_inventory.aligned_external_events, 0);
verifyEqual(testCase, value.database_inventory.sequences, 0);
verifyEqual(testCase, value.database_inventory.sequence_members, 0);
verifyEqual(testCase, height(value.foreign_key_check), 0);
clear cleanup
end
