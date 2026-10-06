function tests = test_backend_localization_demonstration
%TEST_BACKEND_LOCALIZATION_DEMONSTRATION Integrated synthetic Phase 5 example.
%
% Runs backend_localization_demo once; each test then holds one printed claim
% against its returned evidence. The load-bearing tests assert what must NOT
% appear: a combined value, a candidate promoted by intake, a distance, a
% refusal that stopped refusing.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testCase.TestData.example_path = fullfile(repoRoot, "examples");
addpath(testCase.TestData.example_path);
testCase.TestData.value = backend_localization_demo(Print=false, RepoRoot=repoRoot);
end

function teardownOnce(testCase)
rmpath(testCase.TestData.example_path);
end

function testWorkflowCompletesAndCleansEveryArtifact(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyEqual(testCase, height(value.foreign_key_check), 0);
verifyEqual(testCase, value.tracking.dense_samples_stored, 0);
end

function testTheDryRunWritesNothingAndNamesWhatItCouldNotMap(testCase)
preview = testCase.TestData.value.import_preview;
verifyEqual(testCase, preview.status, "planned");
verifyTrue(testCase, preview.wrote_nothing);
verifyEqual(testCase, preview.window_count, 5);
verifyEqual(testCase, preview.estimate_count, 5);
verifyEqual(testCase, preview.unmapped_rows, 1);
verifyEqual(testCase, preview.issues.code, "ATTRIBUTION_WINDOW_REVERSED");
verifyEqual(testCase, preview.resolutions.frames.coordinate_system_key, "arena_2d");
end

function testIntakeWritesNoCandidateEvidenceOrCorrespondence(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, value.import.not_written, ["attribution_candidates"; ...
    "attribution_evidence"; "attribution_window_correspondences"]);
verifyEqual(testCase, value.import.applied_counts.attribution_localization_estimates, 5);
end

function testEstimatesCarryTheirFrameUnitsAndConfidenceSemantics(testCase)
value = testCase.TestData.value;
estimates = value.main_report.localization_estimates;
verifyEqual(testCase, unique(estimates.coordinate_system_key), "arena_2d");
verifyEqual(testCase, unique(estimates.coordinate_system_unit), "cm");
% A 2D backend's height is absent, never zero; a missing confidence is absent too.
verifyTrue(testCase, all(isnan(estimates.position_z)));
verifyEqual(testCase, nnz(isnan(estimates.confidence)), 1);
verifyTrue(testCase, contains(value.evidence.confidence_semantics, "not a caller probability"));
verifyTrue(testCase, contains(value.evidence.confidence_semantics, "Synthetic Localization Backend"));
end

function testTheSecondBackendShowsAHeightUnderAThreeDimensionalFrame(testCase)
value = testCase.TestData.value;
estimates = value.array_report.localization_estimates;
verifyEqual(testCase, unique(estimates.coordinate_system_key), "arena_3d");
verifyEqual(testCase, estimates.position_z', [15 12]);
verifyEqual(testCase, estimates.estimate_ordinal', [1 2]);
verifyTrue(testCase, all(isnan(estimates.confidence)));
verifyTrue(testCase, value.same_read_surface);
end

function testCorrespondenceCrossesTheBackendClockThroughTheSharedTransform(testCase)
value = testCase.TestData.value;
rows = value.correspondence.rows;
verifyTrue(testCase, all(rows.iou_basis == "aligned"));
verifyEqual(testCase, value.correspondence.alignment_run_id, value.backend_clock.alignment_run_id);
verifyEqual(testCase, value.backend_clock.status, "estimated");
verifyEqual(testCase, height(rows), 5);
verifyGreaterThan(testCase, min(rows.temporal_iou), 0.9);
end

function testSeveralCandidatesPerTargetAndOneTargetWithNone(testCase)
value = testCase.TestData.value;
perTarget = value.candidates.per_target;
verifyEqual(testCase, perTarget.candidate_count', [2 2 2 2 1 0]);
verifyEqual(testCase, height(value.main_report.qc.targets_without_candidate), 1);
end

function testFiveDimensionsSitSideBySideAndNothingCombinesThem(testCase)
value = testCase.TestData.value;
display = value.evidence.display;
verifyEqual(testCase, sort(display.evidence_dimension)', sort(["temporal_alignment" ...
    "pose_localization" "visual_identity" "acoustic" "source_localization"]));
verifyFalse(testCase, value.evidence.combined_value_present);
verifyFalse(testCase, value.separation.combined_value_computed);
verifyFalse(testCase, value.separation.distance_computed);
% The source-localization row carries no value of its own; its position and
% frame are the estimate's.
localization = display(display.evidence_dimension == "source_localization", :);
verifyTrue(testCase, isnan(localization.value_real));
verifyEqual(testCase, localization.frame, "arena_2d");
% The acoustic row names its channel relationally.
acoustic = display(display.evidence_dimension == "acoustic", :);
verifyEqual(testCase, acoustic.channel, "mic_left");
% No displayed column name joins two dimension names.
names = string(display.Properties.VariableNames);
verifyFalse(testCase, any(contains(names, "combined") | contains(names, "overall")));
end

function testEveryDecisionStatusIsDemonstrated(testCase)
rows = testCase.TestData.value.decisions.rows;
verifyEqual(testCase, rows.decision_status', ...
    ["assigned" "simultaneous" "ambiguous" "unassigned" "excluded"]);
verifyEqual(testCase, rows.selected_count', [1 2 0 0 0]);
end

function testNativeFieldsArePreservedApartFromCanonicalColumns(testCase)
native = testCase.TestData.value.main_report.native_attributes;
verifyEqual(testCase, sort(unique(native.attribute_namespace))', ...
    ["channel" "producer_native" "track_reference"]);
verifyEqual(testCase, sort(unique(native.owner_kind))', ["claim" "estimate" "window"]);
% An absent producer field is recorded as missing, not as zero.
majorAxis = native(native.attribute_name == "localization_error_major_axis", :);
verifyEqual(testCase, nnz(majorAxis.value_type == "real"), 1);
verifyEqual(testCase, nnz(majorAxis.value_type == "missing"), 4);
end

function testDeclaredInputsKeepUndeclaredAsUnknown(testCase)
declared = testCase.TestData.value.main_report.declared_inputs;
verifyEqual(testCase, sort(declared.input_dimension)', ...
    ["acoustic" "pose_localization" "visual_identity"]);
verifyFalse(testCase, any(declared.input_dimension == "temporal_alignment"));
end

function testTheGrainOfEveryReturnedTableIsStatedBesideItsCount(testCase)
grain = testCase.TestData.value.main_report.grain;
verifyTrue(testCase, all(strlength(grain.one_row_per) > 0));
verifyTrue(testCase, any(grain.table_name == "localization_estimates"));
verifyTrue(testCase, any(grain.table_name == "native_attributes"));
verifyTrue(testCase, any(grain.table_name == "declared_inputs"));
end

function testLocalizationQcIsPerFrameAndNeverPooled(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, height(value.main_report.qc.localization_by_coordinate_system), 1);
verifyEqual(testCase, height(value.array_report.qc.localization_by_coordinate_system), 1);
verifyNotEqual(testCase, ...
    value.main_report.qc.localization_by_coordinate_system.coordinate_system_key, ...
    value.array_report.qc.localization_by_coordinate_system.coordinate_system_key);
end

function testTheRefusalsActuallyRefused(testCase)
% A path that shows only what works teaches a reader that everything works.
refusals = testCase.TestData.value.refusals;
verifyEqual(testCase, sort(refusals.identifier)', sort([ ...
    "vawlume:attribution:LocalizationFrameScopeMismatch", ...
    "vawlume:attribution:CallerLabelUnresolved", ...
    "vawlume:attribution:ImportAlreadyApplied", ...
    "vawlume:attribution:ClockRelationUndeclared", ...
    "vawlume:attribution:LocalizationFrameRequired"]));
verifyTrue(testCase, all(strlength(refusals.message) > 0));
end

function testTheBoundariesAreStatedAsClaims(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, any(contains(value.does_not_prove, "real backend")));
verifyTrue(testCase, any(contains(value.does_not_prove, "estimates none")));
verifyFalse(testCase, value.separation.caller_estimated);
end
