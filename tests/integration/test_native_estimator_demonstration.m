function tests = test_native_estimator_demonstration
%TEST_NATIVE_ESTIMATOR_DEMONSTRATION Integrated synthetic Phase 6 example.
%
% Runs native_estimator_demo once; each test then holds one printed claim
% against its returned evidence. The load-bearing tests assert what must NOT
% appear: a probability, a simultaneous decision, a score for a target the
% method cannot score, a refusal that stopped refusing. The model-mismatch scene
% is asserted only as the demonstration describes it (the wrong animal fits),
% never as a correct result.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testCase.TestData.example_path = fullfile(repoRoot, "examples");
addpath(testCase.TestData.example_path);
testCase.TestData.value = native_estimator_demo(Print=false, RepoRoot=repoRoot);
end

function teardownOnce(testCase)
rmpath(testCase.TestData.example_path);
end

function testWorkflowCompletesAndCleansEveryArtifact(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyEqual(testCase, height(value.foreign_key_check), 0);
end

function testTheDryRunWritesNothingAndApplyWritesThePlan(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, value.preview.status, "planned");
verifyTrue(testCase, value.preview.wrote_nothing);
verifyEqual(testCase, value.applied.status, "applied");
verifyEqual(testCase, value.applied.planned_counts, value.preview.planned_counts);
grain = value.report.grain;
verifyEqual(testCase, grain.row_count(grain.table_name == "evidence"), ...
    value.preview.planned_counts.attribution_evidence);
end

function testNormalizationRemovesTheChannelGainDifference(testCase)
% Channel b's gain is half channel a's: 6.02 dB in power. The symmetric call
% is equally loud at both microphones, so its raw difference is the gain alone.
scenes = testCase.TestData.value.scenes;
symmetric = scenes(scenes.scene == "symmetric", :);
verifyEqual(testCase, symmetric.raw_difference_db, 20 * log10(2), AbsTol=1e-3);
verifyEqual(testCase, symmetric.normalized_difference_db, 0, AbsTol=1e-3);
verifyEqual(testCase, scenes.raw_difference_db - scenes.normalized_difference_db, ...
    repmat(20 * log10(2), height(scenes), 1), AbsTol=1e-3);
end

function testTheFiveConditionsAreReadFromTheStoredProfile(testCase)
c = testCase.TestData.value.five_conditions;
verifyTrue(testCase, c.checksum_matches_registration);
verifyEqual(testCase, c.profile, "vawlume.estimator.native_level_difference@1.0.0");
verifyEqual(testCase, c.dimensions.declaration', ...
    ["used" "used" "used" "used" "not_used"]);
verifyEqual(testCase, c.score.what_this_is_not(1), "not a probability");
verifyEqual(testCase, c.scaling.comparability_scope, "within_recording");
verifyNotEmpty(testCase, c.readability.reconstruction);
verifyEqual(testCase, c.calibration_status.state, "uncalibrated");
end

function testEveryCandidateHasAScoreOrItsReasonAndNoProbability(testCase)
value = testCase.TestData.value;
candidates = value.candidates;
verifyEqual(testCase, height(candidates), 12);
unscored = isnan(candidates.score);
verifyTrue(testCase, all(startsWith(candidates.notes(unscored), "no_score_reason=")));
verifyTrue(testCase, all(candidates.notes(~unscored) == ""));
verifyTrue(testCase, all(candidates.score(~unscored) <= 0), "The score is -|discrepancy|.");
verifyEqual(testCase, numel(value.score_semantics), 1);
verifySubstring(testCase, value.score_semantics, "not a probability");
end

function testEveryEvidenceRowIsOneDimensionWithItsCitation(testCase)
e = testCase.TestData.value.evidence.separable_target;
verifyEqual(testCase, sort(unique(e.evidence_dimension))', ...
    ["acoustic" "pose_localization" "temporal_alignment" "visual_identity"]);
verifyTrue(testCase, all(strlength(e.producer) > 0));
perChannel = e(e.evidence_kind == "call_band_power_normalized", :);
verifyTrue(testCase, all(~isnan(perChannel.derived_measurement_id)));
clock = e(e.evidence_kind == "call_clock_placement", :);
verifyTrue(testCase, all(~isnan(clock.alignment_run_id)));
pose = e(e.evidence_dimension == "pose_localization" | ...
    e.evidence_dimension == "visual_identity", :);
verifyTrue(testCase, all(~isnan(pose.tracking_identity_association_id)));
verifyFalse(testCase, any(e.evidence_dimension == "source_localization"));
end

function testTheSeparableScoreIsReconstructedFromReadBackRows(testCase)
r = testCase.TestData.value.reconstruction;
verifyEqual(testCase, r.entity', ["A" "B"]);
verifyEqual(testCase, r.recomputed_score, r.stored_score, AbsTol=1e-12);
verifyGreaterThan(testCase, r.stored_score(1), r.stored_score(2));
end

function testEveryDecisionStatusTheNativePolicyCanReachAppears(testCase)
rows = testCase.TestData.value.decisions;
verifyEqual(testCase, rows.scene', ["separable" "symmetric" "model_mismatch" ...
    "unfittable" "coverage_gap" "identity_swap"]);
verifyEqual(testCase, rows.decision_status', ["assigned" "ambiguous" "assigned" ...
    "unassigned" "excluded" "excluded"]);
verifyFalse(testCase, any(rows.decision_status == "simultaneous"), ...
    "Equal scores are never read as two callers.");
verifyEqual(testCase, rows.selected_count', [1 0 1 0 0 0]);
end

function testUnscorableTargetsSayWhy(testCase)
scenes = testCase.TestData.value.scenes;
verifySubstring(testCase, scenes.candidate_1(scenes.scene == "coverage_gap"), ...
    "track_covered_empty");
verifySubstring(testCase, scenes.candidate_1(scenes.scene == "identity_swap"), ...
    "identity_changes_within_window");
qc = testCase.TestData.value.report.qc;
verifyEqual(testCase, height(qc.targets_without_scored_candidate), 2);
end

function testTheModelMismatchIsShownAsTheMethodFailing(testCase)
% Described, not endorsed: under -9 dB of unmodelled directivity, more than half
% the gap between the two predictions, the animal that did not generate the call
% ranks first and is assigned. The test pins that the demonstration SAYS so.
m = testCase.TestData.value.mismatch;
verifyGreaterThan(testCase, abs(m.unmodelled_bias_db), m.tolerance_db);
verifyFalse(testCase, m.generating_entity_ranked_first);
verifyFalse(testCase, m.selected_generating_entity);
verifySubstring(testCase, m.meaning, "not asserted correct");
verifyTrue(testCase, any(contains(testCase.TestData.value.does_not_prove, ...
    "assigning the wrong animal")));
end

function testTheReportReadsBackAsANativeRun(testCase)
report = testCase.TestData.value.report;
verifyEqual(testCase, report.attribution_path, "native_estimate");
verifyEqual(testCase, sort(report.declared_inputs.input_dimension)', ...
    ["acoustic" "pose_localization" "temporal_alignment" "visual_identity"]);
verifyEqual(testCase, report.qc.settings_profile_statements.calibration_status, "uncalibrated");
verifySubstring(testCase, report.qc_note, "not a probability");
verifyTrue(testCase, all(strlength(report.grain.one_row_per) > 0));
end

function testTheRefusalsActuallyRefused(testCase)
% A path that shows only what works teaches a reader that everything works.
refusals = testCase.TestData.value.refusals;
verifyEqual(testCase, sort(refusals.identifier)', sort([ ...
    "vawlume:estimator:RunAlreadyApplied", ...
    "vawlume:attribution:NativeRunProfileRequired", ...
    "vawlume:estimator:SettingsBlockMissing", ...
    "vawlume:geometry:CoordinateSystemMismatch", ...
    "vawlume:acoustic:NormalizationRecordingMismatch"]));
verifyTrue(testCase, all(strlength(refusals.message) > 0));
end

function testTheBoundariesAreStatedAsClaims(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, any(contains(value.does_not_prove, "self") | ...
    contains(value.does_not_prove, "own spreading assumption")));
verifyTrue(testCase, any(contains(value.does_not_prove, "calibrated")));
verifySubstring(testCase, value.calibration_boundary, "not a probability");
end
