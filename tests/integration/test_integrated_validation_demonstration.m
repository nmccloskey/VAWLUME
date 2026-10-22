function tests = test_integrated_validation_demonstration
%TEST_INTEGRATED_VALIDATION_DEMONSTRATION Integrated synthetic Phase 7 example.
%
% Runs integrated_validation_demo once; each test then holds one printed claim
% against its returned evidence. The load-bearing tests assert what must NOT
% happen: a structural empty counted as disagreement, an undeclared input read
% as "not used", a split forced to one-to-one, a variant ranked, a native row
% overwritten, a refusal that stopped refusing or changed its identifier.
% Agreement here is circular; nothing asserts that any path is right.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testCase.TestData.example_path = fullfile(repoRoot, "examples");
addpath(testCase.TestData.example_path);
testCase.TestData.value = integrated_validation_demo(Print=false, RepoRoot=repoRoot);
end

function teardownOnce(testCase)
rmpath(testCase.TestData.example_path);
end

function testWorkflowCompletesAndCleansEveryArtifact(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyEqual(testCase, height(value.foreign_key_check), 0);
verifyTrue(testCase, value.native_rows_unchanged);
end

function testTheSceneHasThreePathsOverOneEventSet(testCase)
runs = testCase.TestData.value.scene.runs;
verifyEqual(testCase, sort(unique(runs.attribution_path))', ...
    ["backend", "imported", "native_estimate"]);
verifyTrue(testCase, all(runs.targets == runs.targets(1)));
verifyEqual(testCase, runs.windows(runs.attribution_path == "native_estimate"), [0; 0], ...
    "A native run has no windows: an empty table, not an absent one.");
end

function testADisagreementIsReportedAndNotCollapsed(testCase)
p = testCase.TestData.value.cross_path;
row = p.separable(p.separable.pair == "imported vs native_detections", :);
verifyEqual(testCase, [row.top_entity_agreement, row.selected_set_relation], ...
    ["different", "disjoint"]);
verifyEqual(testCase, [row.left_status, row.right_status], ["assigned", "assigned"], ...
    "The status cross-tab compares statuses, not callers.");
counts = p.counts(p.counts.pair == "imported vs backend", :);
verifyGreaterThan(testCase, counts.disagree, 0);
end

function testAStructuralEmptyIsNotADisagreement(testCase)
p = testCase.TestData.value.cross_path;
verifyEqual(testCase, p.symmetric_imported_vs_native.cell_kind, "structural_empty");
verifyEqual(testCase, p.symmetric_imported_vs_backend.cell_kind, "disagree", ...
    "Against a rule that CAN say simultaneous, the same pair is a disagreement.");
row = p.counts(p.counts.pair == "imported vs native_detections", :);
verifyEqual(testCase, row.disagree, 0);
verifyEqual(testCase, row.structural_empty, 1);
verifyFalse(testCase, contains(p.native_producible_statuses, "simultaneous"));
end

function testImportedDeclaredInputsAreUnknownNotUnused(testCase)
d = testCase.TestData.value.cross_path.declared_inputs;
verifyTrue(testCase, all(d.imported == "unknown"));
verifyFalse(testCase, any(d.imported == "not_used"));
end

function testValuesAreNeverComparedAcrossPaths(testCase)
counts = testCase.TestData.value.cross_path.counts;
verifyTrue(testCase, all(counts.score_comparability == "not_comparable:producer_scale"));
end

function testSplitMergeAndUnmatchedKeepTheirCategoriesThroughNamedAnalyses(testCase)
s = testCase.TestData.value.cross_event_set.scenes;
verifyEqual(testCase, s.unit(s.scene == "split"), "one_to_many");
verifyEqual(testCase, s.unit(s.scene == "merge"), "many_to_one");
verifyEqual(testCase, s.unit(s.scene == "miss"), "unmatched_left");
verifyTrue(testCase, all(strlength(s.named_analysis) > 0), "Every join names its analysis.");
verifyEqual(testCase, s.right_status(s.scene == "split"), "not_applicable_unit", ...
    "A unit with several targets on a side picks none of them.");
verifyEqual(testCase, s.right_status(s.scene == "miss"), "no_counterpart");
end

function testAttributionSensitivityVariesEachHandleAndRanksNothing(testCase)
a = testCase.TestData.value.attribution_sensitivity;
verifyTrue(testCase, a.plan_wrote_nothing);
verifyEqual(testCase, sort(a.variants.handle)', ["alignment_run", "decision_policy", ...
    "estimator_settings", "normalization_policy"]);
verifyEqual(testCase, a.variants.handle, sort(a.variants.handle), ...
    "Rows are ordered by handle, never by outcome.");
verifyTrue(testCase, a.tone_family_generated);
verifyTrue(testCase, a.alignment_variant_cites_offset_fit);
verifyTrue(testCase, a.out_of_bracket_extrapolated);
verifyEqual(testCase, sort(a.reported_not_varied.status)', ["not_exercised", ...
    "not_measurable", "not_variable", "not_variable", "not_variable", "reported_elsewhere"]);
words = lower(strjoin([string(a.variants.Properties.VariableNames), ...
    a.reported_not_varied.reason'], " "));
verifyFalse(testCase, contains(words, ["best", "optimal", "recommended", "validated", "calibrated"]));
end

function testASpectralMatchingVariantMovesNoEventSet(testCase)
m = testCase.TestData.value.matching_sensitivity;
verifyTrue(testCase, m.plan_wrote_nothing);
spectral = m.moved(m.moved.handle == "matching_spectral", :);
verifyEqual(testCase, [spectral.targets_lost, spectral.targets_gained, ...
    spectral.units_unmatched_left, spectral.units_unmatched_right], [0 0 0 0]);
temporal = m.moved(m.moved.handle == "matching_temporal", :);
verifyGreaterThan(testCase, temporal.targets_lost, 0, "The temporal variant moves the event set.");
verifyEqual(testCase, m.reported_not_varied.handle, "matching_duration");
end

function testQcFactsStateTheMarginAndTheUndetectableClass(testCase)
q = testCase.TestData.value.qc_facts;
row = @(name) q.scenes(q.scenes.scene == name, :);
verifyTrue(testCase, row("symmetric").predictions_coincide);
verifyTrue(testCase, row("unfittable").outside_predictions);
mismatch = row("model_mismatch");
verifyFalse(testCase, mismatch.outside_predictions, ...
    "The model-mismatch call looks ordinary: that is the point.");
verifyFalse(testCase, mismatch.no_candidate_within_tolerance);
verifyTrue(testCase, q.every_target_carries_it);
verifyTrue(testCase, contains(q.undetectable_failure_class, "not detectable"));
end

function testEveryRefusalRefusedWithItsIdentifier(testCase)
r = testCase.TestData.value.refusals;
verifyEqual(testCase, height(r), 5);
verifyEqual(testCase, r.identifier, r.expected_identifier);
verifyEqual(testCase, sort(unique(r.identifier))', ...
    ["vawlume:attribution:CorrespondenceAnalysisRequired", ...
    "vawlume:attribution:NativeIdentityCitationRequired", ...
    "vawlume:attribution:NativeProbabilityRefused", ...
    "vawlume:attribution:ScoreNotComparable"]);
end

function testTheExportIsFaithful(testCase)
e = testCase.TestData.value.export;
verifyEqual(testCase, e.warnings, 0);
verifyEqual(testCase, e.strict_read.csv_rows, e.strict_read.sqlite_rows);
verifyTrue(testCase, all(e.strict_read.header_matches));
verifyTrue(testCase, e.non_ascii_and_newline_survive);
end

function testTheBoundaryIsStated(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, contains(value.calibration_boundary, "circular"));
verifyTrue(testCase, any(contains(value.does_not_prove, "circular")));
verifyTrue(testCase, any(contains(value.does_not_prove, "real data")));
verifyTrue(testCase, any(contains(value.does_not_prove, "sensitivity selects")));
end
