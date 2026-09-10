function tests = test_agreement_filter_demonstration
%TEST_AGREEMENT_FILTER_DEMONSTRATION Runnable synthetic Phase 1.10 example.
tests = functiontests(localfunctions);
end

function testDemoFiltersAndJoinsWithoutCollapsingNativeMembers(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
examplePath = fullfile(repoRoot, "examples");
addpath(examplePath);
cleanup = onCleanup(@() rmpath(examplePath));

value = agreement_filter_demo(Print=false, RepoRoot=repoRoot);
verifyTrue(testCase, value.temporary_artifacts_removed);
summary = value.population_summary;
verifyPopulation(testCase, summary, "all_groups", 5, 13);
verifyPopulation(testCase, summary, "at_least_two_pairs", 2, 8);
verifyPopulation(testCase, summary, "exact_all_three_pairs", 2, 8);
verifyPopulation(testCase, summary, ...
    "exact_ds_usvseg_and_mupet_usvseg", 1, 3);
verifyPopulation(testCase, summary, "clean_complete_triple", 1, 3);
verifyPopulation(testCase, summary, "complete_ambiguous", 1, 5);
verifyPopulation(testCase, summary, "extractor_unique", 1, 1);

partial = value.populations.exact_ds_usvseg_and_mupet_usvseg;
verifyEqual(testCase, unique(partial.groups.supported_extractor_pair_pattern), ...
    "deepsqueak--usvseg|mupet--usvseg");
verifyEqual(testCase, unique(partial.groups.supported_extractor_pair_count), 2);
verifyEqual(testCase, unique(partial.groups.possible_extractor_pair_count), 3);

members = value.member_context_measurements;
verifyEqual(testCase, height(members), 13);
verifyEqual(testCase, numel(unique(members.detection_id)), 13);
verifyEqual(testCase, numel(unique(members.agreement_group_id)), 5);
verifyTrue(testCase, all(members.duration_unit == "s"));
verifyFalse(testCase, any(isnan(members.call_duration_s)));

counts = sortrows(value.condition_counts, "condition_key");
verifyEqual(testCase, counts.condition_key, ["DEMO_EARLY"; "DEMO_LATE"]);
verifyEqual(testCase, counts.groupCount, [3; 2]);
verifyEqual(testCase, counts.memberCount, [7; 6]);
verifyEqual(testCase, sum(value.duration_summary.memberCount), 13);
verifyEqual(testCase, height(value.duration_summary), 6);
verifyEqual(testCase, height(value.foreign_key_check), 0);
verifyTrue(testCase, any(contains(value.does_not_prove, "calibration")));
verifyTrue(testCase, any(contains(value.does_not_prove, "inferential")));
clear cleanup
end

function verifyPopulation(testCase, summary, key, groups, members)
row = summary(summary.filter_key == key, :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.group_count, groups);
verifyEqual(testCase, row.member_count, members);
end
