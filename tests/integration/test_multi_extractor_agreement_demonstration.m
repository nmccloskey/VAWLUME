function tests = test_multi_extractor_agreement_demonstration
%TEST_MULTI_EXTRACTOR_AGREEMENT_DEMONSTRATION Runnable three-extractor example.
tests = functiontests(localfunctions);
end

function testDemoImportsThreeExtractorsAndComposesAgreement(testCase)
value = runDemo();

verifyEqual(testCase, value.project.intake_status, "completed");
verifyEqual(testCase, value.project.preview_verdict, "READY FOR INGEST");

% Three extractors, three separate extraction runs on one recording.
runs = value.imports.runs;
verifyEqual(testCase, string(runs.extractor), ...
    ["DeepSqueak"; "MUPET"; "USVSEG"]);
verifyEqual(testCase, runs.detection_count, [5; 6; 5]);
verifyEqual(testCase, value.imports.total_detection_count, 16);

% All three pairwise comparisons ran; matching is the primitive.
pairwise = value.pairwise;
verifyEqual(testCase, height(pairwise), 3);
verifyEqual(testCase, string(pairwise.run_key), ...
    ["demo-match-ds-mupet"; "demo-match-ds-usvseg"; "demo-match-mupet-usvseg"]);
verifyEqual(testCase, pairwise.candidate_pair_count, [5; 3; 5]);

% Agreement is derived over those analyses, and it partitions the native
% detections without collapsing or duplicating any of them.
verifyEqual(testCase, value.agreement.status, "committed");
verifyEqual(testCase, value.agreement.source_analysis_count, 3);
verifyEqual(testCase, value.agreement.group_count, 6);
verifyEqual(testCase, value.agreement.native_member_count, 16);
verifyTrue(testCase, value.identity.detections_partitioned);
verifyTrue(testCase, value.identity.member_detections_unique);
verifyTrue(testCase, value.identity.native_detections_unchanged);
verifyEqual(testCase, height(value.foreign_key_check), 0);
verifyTrue(testCase, value.temporary_artifacts_removed);
end

function testExactEdgePatternsDoNotMergeAtTheSameCoarseCount(testCase)
value = runDemo();
summary = value.population_summary;

% The coarse query merges both open chains; the exact queries keep them apart.
verifyPopulation(testCase, summary, "coarse_exactly_two_pairs", 2, 6);
verifyPopulation(testCase, summary, "exact_chain_through_mupet", 1, 3);
verifyPopulation(testCase, summary, "exact_chain_through_usvseg", 1, 3);

comparison = value.exact_versus_coarse;
verifyEqual(testCase, comparison.coarse_group_count, 2);
verifyEqual(testCase, comparison.exact_pattern_group_counts, [1; 1]);
verifyEqual(testCase, comparison.exact_patterns, ...
    ["deepsqueak--mupet|mupet--usvseg"; "deepsqueak--usvseg|mupet--usvseg"]);
verifyTrue(testCase, comparison.exact_patterns_are_disjoint);
verifyTrue(testCase, comparison.exact_partition_recovers_coarse);

% Both chains are 2 of 3 and each names its own missing pair.
chainA = value.populations.exact_chain_through_mupet.groups;
chainB = value.populations.exact_chain_through_usvseg.groups;
verifyEqual(testCase, chainA.supported_extractor_pair_count, 2);
verifyEqual(testCase, chainB.supported_extractor_pair_count, 2);
verifyEqual(testCase, chainA.possible_extractor_pair_count, 3);
verifyEqual(testCase, chainB.possible_extractor_pair_count, 3);
verifyEqual(testCase, chainA.unsupported_extractor_pair_pattern, ...
    "deepsqueak--usvseg");
verifyEqual(testCase, chainB.unsupported_extractor_pair_pattern, ...
    "deepsqueak--mupet");

% Coarse K is a genuine superset relation, not a synonym for the exact shape.
verifyPopulation(testCase, summary, "coarse_at_least_two_pairs", 4, 13);
verifyPopulation(testCase, summary, "all_groups", 6, 16);
end

function testIndependentShapeDimensionsRemainDistinct(testCase)
value = runDemo();
summary = value.population_summary;

verifyPopulation(testCase, summary, "exact_all_three_pairs", 2, 7);
verifyPopulation(testCase, summary, "clean_complete_triple", 1, 3);
verifyPopulation(testCase, summary, "complete_ambiguous", 1, 4);
verifyPopulation(testCase, summary, "two_extractor_pair_only", 1, 2);
verifyPopulation(testCase, summary, "extractor_unique", 1, 1);

shapes = value.group_shapes;
verifyEqual(testCase, height(shapes), 6);

% The split/merge component is one group with four native observations, and
% complete pair support does not make it clean.
ambiguous = value.populations.complete_ambiguous;
verifyEqual(testCase, ambiguous.selected_group_count, 1);
verifyEqual(testCase, ambiguous.selected_member_count, 4);
verifyTrue(testCase, ambiguous.groups.is_extractor_pair_support_complete);
verifyFalse(testCase, ambiguous.groups.is_unambiguous_one_to_one);
verifyFalse(testCase, ambiguous.groups.is_one_detection_per_extractor);
verifyEqual(testCase, ambiguous.groups.extractor_count, 3);

% The clean triple is complete on every dimension at once.
clean = value.populations.clean_complete_triple.groups;
verifyTrue(testCase, clean.is_extractor_pair_support_complete);
verifyTrue(testCase, clean.is_unambiguous_one_to_one);
verifyTrue(testCase, clean.is_one_detection_per_extractor);

% A two-extractor component has a component-local C(2,2)=1 denominator; a
% singleton has none at all and its support fraction is NaN, not zero.
pairOnly = value.populations.two_extractor_pair_only.groups;
verifyEqual(testCase, pairOnly.possible_extractor_pair_count, 1);
verifyEqual(testCase, pairOnly.supported_extractor_pair_count, 1);
verifyEqual(testCase, pairOnly.extractor_set_key, "deepsqueak|mupet");

unique = value.populations.extractor_unique.groups;
verifyTrue(testCase, unique.is_singleton);
verifyTrue(testCase, unique.is_extractor_unique);
verifyEqual(testCase, unique.possible_extractor_pair_count, 0);
verifyTrue(testCase, isnan(unique.support_fraction));

verifyTrue(testCase, any(contains(value.does_not_prove, "biological truth")));
verifyTrue(testCase, any(contains(value.does_not_prove, "calibration")));
end

function value = runDemo()
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
examplePath = fullfile(repoRoot, "examples");
addpath(examplePath);
cleanup = onCleanup(@() rmpath(examplePath));
value = multi_extractor_agreement_demo(Print=false, RepoRoot=repoRoot);
clear cleanup
end

function verifyPopulation(testCase, summary, key, groups, members)
row = summary(summary.filter_key == key, :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.group_count, groups);
verifyEqual(testCase, row.native_member_count, members);
end
