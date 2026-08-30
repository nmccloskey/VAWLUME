function tests = test_matching_consensus_demonstration
%TEST_MATCHING_CONSENSUS_DEMONSTRATION Phase 6 public end-to-end proof.
tests = functiontests(localfunctions);
end

function testPublicDemonstrationMakesTheCompleteGoalThreeLegible(testCase)
repoRoot = repoRootPath();
examplesPath = fullfile(repoRoot, "examples");
addpath(examplesPath);
cleanupPath = onCleanup(@() rmpath(examplesPath));

printed = evalc("result = matching_consensus_demo(Print=false, RepoRoot=repoRoot);");
verifyEqual(testCase, strtrim(string(printed)), "");

% Project intake and both public importers ran before matching.
verifyTrue(testCase, result.project.committed);
verifyEqual(testCase, result.project.preview_verdict, "READY FOR INGEST");
verifyTrue(testCase, result.deep_squeak.committed);
verifyTrue(testCase, result.mupet.committed);
verifyEqual(testCase, result.deep_squeak.detection_count, 4);
verifyEqual(testCase, result.mupet.detection_count, 6);
verifyEqual(testCase, result.mupet.curation_rows_expected, 0);
verifyEqual(testCase, result.mupet.classification_rows_expected, 0);
verifyEqual(testCase, result.pre_matching_inventory.row_count, ...
    zeros(height(result.pre_matching_inventory), 1));

% Four transparent candidates become two 1:1 groups, one 1:2 group, and
% three explicit unmatched groups. Every edge and native population survives.
verifyEqual(testCase, height(result.candidate_evidence), 4);
verifyTrue(testCase, all(result.candidate_evidence.eligible));
verifyEqual(testCase, height(result.match_groups), 6);
verifyEqual(testCase, topologyCount(result.match_groups, "one_to_one"), 2);
verifyEqual(testCase, topologyCount(result.match_groups, "one_to_many"), 1);
verifyEqual(testCase, topologyCount(result.match_groups, "unmatched"), 3);
split = result.match_groups(result.match_groups.topology == "one_to_many", :);
verifyEqual(testCase, split.deep_squeak_native_ids, "4");
verifyEqual(testCase, split.mupet_native_ids, "4, 5");
verifyEqual(testCase, split.consensus_start_s, 40, AbsTol=1e-12);
verifyEqual(testCase, split.consensus_end_s, 40.1, AbsTol=1e-12);
verifyEqual(testCase, split.consensus_method, "union_boundary_of_members");
verifyEqual(testCase, height(result.consensus_events), 3);
verifyTrue(testCase, result.native_detections_unchanged);

% Detection agreement publishes each extractor's own denominator.
agreement = result.detection_agreement;
verifyEqual(testCase, string(agreement.run_role), ["run_a"; "run_b"]);
verifyEqual(testCase, agreement.total_detections, [4; 6]);
verifyEqual(testCase, agreement.in_one_to_one_groups, [2; 2]);
verifyEqual(testCase, agreement.in_ambiguous_groups, [1; 2]);
verifyEqual(testCase, agreement.unmatched_detections, [1; 2]);

% Central frequency is found through registry semantics while its methods stay
% distinct. Power/energy/amplitude relationships are visible but never scored.
centre = result.central_frequency;
verifyEqual(testCase, centre.deep_squeak_canonical_name, ...
    "contour_median_frequency");
verifyEqual(testCase, centre.mupet_canonical_name, "frequency_center");
verifyEqual(testCase, centre.shared_equivalence_class, ...
    "vocalization_frequency_center");
verifyEqual(testCase, centre.relationship_type, "comparable");
verifyNotEqual(testCase, centre.deep_squeak_method, centre.mupet_method);
verifyTrue(testCase, centre.consilience_eligible);
verifyEqual(testCase, height(centre.comparison), 2);
verifyEqual(testCase, height(result.ineligible_features), 2);
verifyFalse(testCase, any(result.ineligible_features.consilience_eligible));
verifyTrue(testCase, all(result.ineligible_features.not_scored));

% Automated statuses stay separate from independent manual adjudication.
counts = result.consilience.status_counts;
verifyEqual(testCase, statusCount(counts, "matched_feature_supported"), 1);
verifyEqual(testCase, statusCount(counts, "matched_feature_discrepant"), 1);
verifyEqual(testCase, statusCount(counts, "ambiguous_split_merge"), 1);
verifyEqual(testCase, statusCount(counts, "single_extractor"), 3);
manual = result.manual_qc.per_run;
verifyEqual(testCase, manual.detection_count, [4; 6]);
verifyEqual(testCase, manual.true_positives, [3; 3]);
verifyEqual(testCase, manual.precision, [.75; .5], AbsTol=1e-12);
verifyEqual(testCase, manual.recall, [.75; .75], AbsTol=1e-12);
curation = result.manual_qc.curation_cross_reference;
accepted = curation(curation.curation_status == "accepted", :);
rejected = curation(curation.curation_status == "rejected", :);
verifyEqual(testCase, accepted.reference_supported, 2);
verifyEqual(testCase, accepted.reference_absent, 1);
verifyEqual(testCase, rejected.reference_supported, 1);
verifyEqual(testCase, rejected.reference_absent, 0);

% Three immutable analyses coexist and show threshold dependence without a
% recommended/optimal winner. Manual metrics stay independent of that threshold.
sensitivity = result.sensitivity.comparison;
verifyEqual(testCase, sensitivity.min_temporal_iou, [.05; .10; .50], ...
    AbsTol=1e-12);
verifyEqual(testCase, sensitivity.candidate_count, [5; 4; 2]);
verifyEqual(testCase, sensitivity.one_to_one_groups, [3; 2; 2]);
verifyEqual(testCase, sensitivity.one_to_many_groups, [1; 1; 0]);
verifyEqual(testCase, sensitivity.unmatched_groups, [1; 3; 6]);
verifyEqual(testCase, unique(sensitivity.run_a_precision), .75, AbsTol=1e-12);
verifyTrue(testCase, result.coexisting_matching_analyses.distinct_analysis_ids);
verifyFalse(testCase, any(contains(lower(string( ...
    sensitivity.Properties.VariableNames)), "optimal")));

% Rerun, provenance, relational integrity, and cleanup close the demonstration.
verifyEqual(testCase, result.rerun.status, "reused");
verifyTrue(testCase, result.rerun.analysis_id_stable);
verifyTrue(testCase, result.rerun.group_ids_stable);
verifyTrue(testCase, result.rerun.scientific_rows_unchanged);
verifyEqual(testCase, result.rerun.applied_counts.candidate_pairs, 0);
verifyEqual(testCase, result.rerun.applied_counts.reused_candidate_pairs, 4);
verifyEqual(testCase, result.rerun.applied_counts.reused_match_groups, 6);
verifyEqual(testCase, height(result.provenance.assessment_members), 2);
verifyEqual(testCase, height(result.provenance.candidate_evidence), 1);
verifyGreaterThan(testCase, height(result.provenance.run_artifacts), 0);
verifyGreaterThan(testCase, height(result.provenance.project_context), 0);
verifyEqual(testCase, height(result.foreign_key_check), 0);
verifyTrue(testCase, result.temporary_artifacts_removed);
end

function testPhaseSixStaticBoundariesRemainVisible(testCase)
repoRoot = repoRootPath();
matching = sourceUnder(fullfile(repoRoot, "src", "+vawlume", "+matching"));
consilience = sourceUnder(fullfile(repoRoot, "src", "+vawlume", "+consilience"));
example = string(fileread(fullfile(repoRoot, "examples", ...
    "matching_consensus_demo.m")));

verifyFalse(testCase, contains(matching, [".xlsx", ".csv", ...
    "readtable(", "vawlume.ingest."]));
verifyFalse(testCase, contains(lower(matching + consilience), ...
    ["hungarian", "matchpairs("]));
verifyFalse(testCase, contains(lower(matching), ...
    ["delete from candidate_pairs", "update detections"]));
verifyFalse(testCase, contains(lower(consilience), ...
    ["update detections", "update event_measurements", ...
    "delete from detections", "delete from event_measurements"]));
verifyFalse(testCase, contains(example, "recommended_configuration"));
verifyTrue(testCase, contains(example, "Illustrative synthetic prototype"));

% Direct SQL in the demonstration only authors the two reviewer-input layers;
% project, extractor, matching, agreement, and consilience rows use public APIs.
insertTargets = regexp(example, 'INSERT INTO\s+([a-z_]+)', 'tokens');
targets = strings(numel(insertTargets), 1);
for index = 1:numel(insertTargets)
    targets(index) = string(insertTargets{index}{1});
end
verifyEqual(testCase, sort(unique(targets)), ...
    ["manual_reference_events"; "manual_reviews"]);
end

function value = topologyCount(groups, topology)
value = nnz(groups.topology == topology);
end

function value = statusCount(counts, status)
selected = counts.status == status;
assert(nnz(selected) == 1);
value = counts.group_count(selected);
end

function value = sourceUnder(root)
files = dir(fullfile(root, "**", "*.m"));
value = "";
for index = 1:numel(files)
    value = value + newline + string(fileread( ...
        fullfile(files(index).folder, files(index).name)));
end
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
