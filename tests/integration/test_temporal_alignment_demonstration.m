function tests = test_temporal_alignment_demonstration
%TEST_TEMPORAL_ALIGNMENT_DEMONSTRATION Integrated synthetic Phase 3 example.
%
% Run the demonstration once: the individual tests then hold each printed claim
% against its returned evidence rather than relying on visual inspection.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testCase.TestData.repo_root = repoRoot;
testCase.TestData.example_path = fullfile(repoRoot, "examples");
addpath(testCase.TestData.example_path);
testCase.TestData.value = temporal_alignment_demo(Print=false, RepoRoot=repoRoot);
end

function teardownOnce(testCase)
rmpath(testCase.TestData.example_path);
end

function testWorkflowCompletesAndCleansEveryArtifact(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyEqual(testCase, height(value.foreign_key_check), 0);
verifyEqual(testCase, value.database_inventory.aligned_external_events, 0);
verifyEqual(testCase, value.database_inventory.sequences, 0);
verifyEqual(testCase, value.database_inventory.sequence_members, 0);
verifyEqual(testCase, value.tracking.dense_samples_stored, 0);
end

function testKnownPiecewiseTransformsAreRecovered(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, height(value.recovered_parameters), 4);
verifyLessThan(testCase, max(value.recovered_parameters.scale_absolute_error), 1e-9);
verifyLessThan(testCase, ...
    max(value.recovered_parameters.offset_absolute_error_s), 1e-6);

audio = value.qc.transforms(value.qc.transforms.source_timebase_key == ...
    "audio_native", :);
video = value.qc.transforms(value.qc.transforms.source_timebase_key == ...
    "video_native", :);
verifyEqual(testCase, audio.method, "piecewise_affine");
verifyEqual(testCase, video.method, "piecewise_affine");
verifyEqual(testCase, audio.segment_count, 2);
verifyEqual(testCase, video.segment_count, 2);
verifyTrue(testCase, all(value.qc.reference_timebase.timebase_key == ...
    "neural_native"));
end

function testOneSourceFailsNamefullyWithoutErasingSuccessfulClocks(testCase)
value = testCase.TestData.value;
transforms = value.qc.transforms;
verifyEqual(testCase, sort(transforms.source_timebase_key), ...
    ["audio_native"; "controller_native"; "video_native"]);
verifyEqual(testCase, nnz(transforms.status == "estimated"), 2);
verifyEqual(testCase, nnz(transforms.status == "failed"), 1);

failure = value.qc.failures;
verifyEqual(testCase, height(failure), 1);
verifyEqual(testCase, failure.source_timebase_key, "controller_native");
verifyEqual(testCase, failure.failure_code, "BreakpointsRequired");
verifyGreaterThan(testCase, strlength(failure.failure_reason), 0);
verifyEqual(testCase, value.qc.set_status, "draft");
end

function testReplicateWithheldAndClusteredAnchorsRemainDistinctEvidence(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, value.intake.anchor_summary.anchor_count, 6);
verifyEqual(testCase, value.replicate_dispersion.observation_count, 2);
verifyEqual(testCase, value.replicate_dispersion.spread_s, 0.006, AbsTol=1e-9);

withheld = value.withheld_residual;
verifyEqual(testCase, height(withheld), 1);
verifyEqual(testCase, withheld.included_in_fit, 0);
verifyEqual(testCase, withheld.residual_s, 0.015, AbsTol=1e-8);
verifyGreaterThan(testCase, strlength(withheld.exclusion_reason), 0);

diagnostics = value.anchor_configuration;
verifyEqual(testCase, diagnostics.paired_anchor_count, 6);
verifyEqual(testCase, diagnostics.included_anchor_count, 5);
verifyEqual(testCase, diagnostics.withheld_anchor_count, 1);
verifyEqual(testCase, diagnostics.source_span_s, 1490, AbsTol=1e-12);
verifyEqual(testCase, diagnostics.largest_gap_fraction, 1170 / 1490, ...
    AbsTol=1e-12);
end

function testIntervalAndPointSupportAreExplicit(testCase)
value = testCase.TestData.value;
crossing = value.interval_crossing;
verifyTrue(testCase, crossing.crosses_breakpoint);
verifyEqual(testCase, crossing.segments_crossed, 2);
verifyEqual(testCase, crossing.native_duration_s, 200);
verifyEqual(testCase, crossing.aligned_duration_s, 200.05, AbsTol=1e-9);
verifyEqual(testCase, crossing.duration_change_s, 0.05, AbsTol=1e-9);

points = value.point_support;
verifyEqual(testCase, points.extrapolated, [false; true]);
verifyEqual(testCase, points.segment_index, [2; 2]);
end

function testUncertaintyPropagationStatesValueSemanticsAndAbsence(testCase)
value = testCase.TestData.value;
rows = value.uncertainty_propagation;
audio = rows(rows.source_timebase == "audio_native", :);
video = rows(rows.source_timebase == "video_native", :);
verifyGreaterThan(testCase, audio.uncertainty_s, 0);
verifyEqual(testCase, audio.semantics, ...
    "max_contributing_anchor_uncertainty_s");
verifyTrue(testCase, isnan(video.uncertainty_s));
verifyTrue(testCase, ismissing(video.semantics) | strlength(video.semantics) == 0);
verifyTrue(testCase, contains(value.qc.uncertainty_note, "uncalibrated"));
end

function testCoverageDistinguishesAbsenceUnavailabilityAndExtrapolation(testCase)
value = testCase.TestData.value;
coverage = value.coverage_demonstration;
verifyTrue(testCase, coverage.first_bin_covered_empty);
verifyTrue(testCase, coverage.first_bin_extrapolated);
verifyTrue(testCase, coverage.unavailable_bin_present);
verifyTrue(testCase, any(coverage.timeline.behavior_event_count == 0));
verifyTrue(testCase, any(isnan(coverage.timeline.behavior_event_count)));
verifyTrue(testCase, any(coverage.projected_coverage.projection_status == ...
    "extrapolated"));
verifyTrue(testCase, all(coverage.projected_coverage.observation_status == ...
    "observed"));
end

function testIdentityEvidenceIsVisibleAndCannotChangeCoefficients(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, value.identity.coefficients_identical);
verifyEqual(testCase, value.identity.coefficients_before, ...
    value.identity.coefficients_after);
verifyEqual(testCase, height(value.qc.anchor_identity_evidence), 1);
verifyEqual(testCase, value.qc.anchor_identity_evidence.evidence_class, ...
    "identity_dependent");
verifyEqual(testCase, value.qc.anchor_identity_evidence.identity_value, ...
    0.55, AbsTol=1e-12);
verifyTrue(testCase, contains(value.qc.identity_separation_note, ...
    "never combined"));
end

function testTrackingConsumesTheStoredPiecewiseTransform(testCase)
value = testCase.TestData.value;
window = value.tracking_window;
verifyEqual(testCase, window.reference_time_status, "applied");
verifyEqual(testCase, window.transform.method, "piecewise_affine");
verifyTrue(testCase, ismember("time_reference_s", ...
    window.samples.Properties.VariableNames));
verifyTrue(testCase, all(isfinite(window.samples.time_reference_s)));
verifyEqual(testCase, unique(window.samples.pose_confidence), 0.73, ...
    AbsTol=1e-12);
verifyTrue(testCase, contains(window.identity_boundary, "not a canonical"));
end

function testFourEvidenceDimensionsStaySeparateAndNoCallerIsNamed(testCase)
value = testCase.TestData.value;
evidence = value.separate_evidence;
verifyEqual(testCase, evidence.dimension, ...
    ["temporal_alignment"; "pose_localization"; "visual_identity"; ...
        "acoustic_channel_response"]);
verifyEqual(testCase, evidence.value, [0.015; 0.73; 0.55; 0.42], ...
    AbsTol=1e-8);
verifyEqual(testCase, numel(unique(evidence.queried_from)), 4);
verifyEqual(testCase, numel(unique(evidence.semantics)), 4);
verifyEqual(testCase, numel(unique(evidence.unit)), 4);
verifyFalse(testCase, value.separation.combined_value_computed);
verifyFalse(testCase, value.separation.caller_named);
verifyEqual(testCase, value.database_inventory.caller_attribution_rows, 0);
end
