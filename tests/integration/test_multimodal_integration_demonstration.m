function tests = test_multimodal_integration_demonstration
%TEST_MULTIMODAL_INTEGRATION_DEMONSTRATION The runnable Phase 2 example.
%
% The demonstration is expensive enough to run once and assert against many
% times, so the shared setup runs it and every test reads the same result.
%
% The claims this suite holds are the ones the example exists to make:
%
%   every Phase 2 capability is exercised through the public API in one workflow;
%   native trajectories, canonical entities, pose confidence, identity evidence
%     and clock QC stay separately queryable;
%   the ambiguous crossing is representable without forcing identity certainty;
%   reference families are estimated separately and never blended;
%   no caller is assigned and no combined confidence is produced;
%   the run leaves no artifact and no foreign-key violation behind.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testCase.TestData.repo_root = repoRoot;
testCase.TestData.example_path = fullfile(repoRoot, "examples");
addpath(testCase.TestData.example_path);
testCase.TestData.value = multimodal_integration_demo(Print=false, ...
    RepoRoot=repoRoot);
end

function teardownOnce(testCase)
rmpath(testCase.TestData.example_path);
end

% --------------------------------------------------- the workflow completes ---

function testWorkflowRunsCleanlyAndLeavesNothingBehind(testCase)
value = testCase.TestData.value;

verifyTrue(testCase, value.temporary_artifacts_removed);
verifyEqual(testCase, height(value.foreign_key_check), 0);

% A dry run really is a dry run, on both of the layers that offer one.
verifyTrue(testCase, value.tracking.dry_run_wrote_nothing);
verifyTrue(testCase, value.acoustic.planned_profile_wrote_nothing);

inventory = value.database_inventory;
verifyEqual(testCase, inventory.tracking_series, 6);
verifyEqual(testCase, inventory.identity_associations, 7);
verifyEqual(testCase, inventory.acoustic_references, 4);
verifyEqual(testCase, inventory.channel_response_estimates, 4);
end

% ------------------------------------------------------- geometry and frames ---

function testTwoMicrophonesAndTheTrackerShareOneDeclaredFrame(testCase)
value = testCase.TestData.value;

placements = value.geometry.placements;
verifyEqual(testCase, height(placements), 2);
verifyEqual(testCase, placements.position_x', [0 37]);
verifyEqual(testCase, unique(string(placements.coordinate_system_key)), "arena_2d");

% A 2D frame yields no height at all, rather than a zero that reads like one.
verifyTrue(testCase, all(isnan(placements.position_z)));

% Compatibility is a declaration check. Nothing was rescaled or reprojected to
% make the tracker and the microphones comparable.
verifyTrue(testCase, value.geometry_compatibility.compatible);
verifyFalse(testCase, value.geometry_compatibility.transformed);
verifyEqual(testCase, ...
    value.geometry_compatibility.coordinate_system.coordinate_system_key, ...
    "arena_2d");
verifyEqual(testCase, value.geometry_compatibility.placed_channel_indices, [1 2]);

% Sharing a frame licenses comparison; the example draws no distance from it.
verifyFalse(testCase, value.geometry.distance_computed);
end

% -------------------------------------------------------- tracking boundary ---

function testDenseSamplesStayExternalAndCoverageHasThreeStates(testCase)
value = testCase.TestData.value;

verifyEqual(testCase, value.tracking.dense_samples_stored, 0);
verifyEqual(testCase, value.database_inventory.tracking_samples_in_sqlite, 0);
verifyFalse(testCase, value.tracking.raw_video_processed);
verifyFalse(testCase, value.tracking.reidentification_performed);

states = value.tracking_windows.coverage_states;
verifyEqual(testCase, states.coverage_status', ...
    ["covered", "covered", "partial", "uncovered"]);
verifyEqual(testCase, states.sample_status', ...
    ["populated", "populated", "populated", "uncovered"]);

% An uncovered window returns no rows, and that zero is not an observation of
% nothing happening.
verifyEqual(testCase, states.sample_rows(end), 0);
verifyGreaterThan(testCase, states.sample_rows(1), 0);

% The result says in as many words that a track label is not an identity.
verifyTrue(testCase, contains(value.tracking_windows.identity_boundary, ...
    "not a canonical"));
end

% -------------------------------------------------------- visual identity ---

function testTheCrossingIsRepresentableWithoutForcingCertainty(testCase)
value = testCase.TestData.value;
summary = value.identity.resolution_by_window;

verifyResolution(testCase, summary, "before", "mouse_a", "resolved", 1);
verifyResolution(testCase, summary, "before", "mouse_b", "resolved", 1);

% During the crossing one trajectory is compatible with either animal and both
% candidates survive; the other trajectory's identity is explicitly unknown.
verifyResolution(testCase, summary, "during", "mouse_a", "ambiguous", 2);
verifyResolution(testCase, summary, "during", "mouse_b", "unresolved", 0);

% A track nobody examined is a third, distinct finding. Both it and the
% unresolved statement have zero candidates, and they must not read alike.
verifyResolution(testCase, summary, "during", "mouse_c", "none", 0);
verifyNotEqual(testCase, ...
    resolutionOf(summary, "during", "mouse_b"), ...
    resolutionOf(summary, "during", "mouse_c"));

verifyResolution(testCase, summary, "after", "mouse_a", "resolved", 1);
verifyResolution(testCase, summary, "after", "mouse_b", "resolved", 1);
end

function testAnAnimalLikeTrackLabelIsNeverCanonicalIdentity(testCase)
value = testCase.TestData.value;
labels = value.identity.label_versus_identity;

% Two track labels are spelled exactly like canonical entities, and before the
% crossing the evidence happens to agree with the spelling.
verifyEqual(testCase, labels.label_matches_evidence_before', ...
    [true true false]);

% After the crossing the evidence names the other animal while the labels stay
% exactly where they were. A session-global track-to-entity column could not
% express this, and a label taken as identity would now be wrong.
verifyEqual(testCase, labels.label_matches_evidence_after', ...
    [false false false]);
verifyEqual(testCase, labels.entity_before_crossing', ...
    ["mouse_a", "mouse_b", "<no evidence>"]);
verifyEqual(testCase, labels.entity_after_crossing', ...
    ["mouse_b", "mouse_a", "<no evidence>"]);

% The third label names a plausible animal and created nothing.
verifyEqual(testCase, value.identity.unexamined_track, "mouse_c");
verifyFalse(testCase, value.identity.image_reidentification_performed);
end

function testIdentityNumbersAreMissingOrCarryTheirSemantics(testCase)
value = testCase.TestData.value;

% The manual assertions before the crossing record no number at all. A reviewer
% who is certain has still not measured anything, so nothing becomes 1.0.
verifyTrue(testCase, value.identity.missing_values_remain_missing);

scored = value.identity.numeric_evidence;
verifyEqual(testCase, height(scored), 2);
verifyEqual(testCase, scored.identity_value', [0.55 0.52], AbsTol=1e-12);
verifyEqual(testCase, unique(scored.identity_value_semantics), ...
    "cosine_similarity_of_appearance_embeddings");
verifyEqual(testCase, unique(scored.calibration_status), "uncalibrated");
verifyEqual(testCase, unique(scored.assignment_state), "ambiguous");
end

% ------------------------------------------- the four uncertainty components ---

function testPoseIdentityClockAndAcousticEvidenceStaySeparate(testCase)
value = testCase.TestData.value;

% Without a stored transform the reader says so and invents nothing, leaving
% pose confidence exactly where it was.
without = value.clock_separation.without_transform;
verifyEqual(testCase, without.reference_time_status, "no_transform");
verifyTrue(testCase, without.reference_times_all_missing);
verifyTrue(testCase, without.native_times_untouched);
verifyTrue(testCase, without.pose_confidence_unchanged);

% With one stored, its residual evidence arrives beside the samples rather than
% folded into their confidence.
with = value.clock_separation.with_transform;
verifyEqual(testCase, with.reference_time_status, "applied");
verifyEqual(testCase, with.offset_recovered_s, 10, AbsTol=1e-9);
verifyEqual(testCase, with.rmse_s, 0.001, AbsTol=1e-12);
verifyTrue(testCase, value.clock_separation.fit_is_estimated_not_validated);

% Four components, four different numbers, none derived from another and none
% combined. Pose confidence during the crossing is 0.34 while the identity
% evidence is 0.55/0.52 and the clock residual is 0.001 s.
verifyEqual(testCase, value.tracking_windows.pose_confidence_nominal, 0.98);
verifyEqual(testCase, value.tracking_windows.pose_confidence_crossing, 0.34);
verifyEqual(testCase, height(value.uncertainty), 4);
verifyEqual(testCase, value.uncertainty.dimension', ...
    ["pose_localization", "visual_identity", "temporal_alignment", ...
    "acoustic_channel_response"]);
verifyNotEqual(testCase, value.uncertainty.value(1), value.uncertainty.value(2));
verifyNotEqual(testCase, value.uncertainty.value(2), value.uncertainty.value(3));
end

% ------------------------------------------------------- acoustic evidence ---

function testBoundedAudioReadsReportCoverageRatherThanTrimSilently(testCase)
value = testCase.TestData.value;
summary = value.acoustic.windows.summary;

verifyEqual(testCase, summary.status', ["covered_populated", ...
    "covered_populated", "partial_populated", "not_covered"]);

% A declared reference interval reads back at exactly the level written into it,
% and a silent stretch reads as silence rather than as missing data.
verifyEqual(testCase, summary.rms(1), 0.4, AbsTol=1e-5);
verifyEqual(testCase, summary.rms(2), 0, AbsTol=1e-9);
verifyEqual(testCase, summary.sample_count(end), 0);
verifyTrue(testCase, isnan(summary.rms(end)));
end

function testReferenceFamiliesAreEstimatedSeparatelyAndNeverBlended(testCase)
value = testCase.TestData.value;
estimates = value.acoustic.estimates;

verifyEqual(testCase, value.acoustic.profile.status, "completed");
verifyEqual(testCase, height(estimates), 4);
verifyEqual(testCase, sort(unique(estimates.reference_type))', ["noise", "tone"]);
verifyTrue(testCase, value.acoustic.families_kept_separate);

% Channel 2 was written at exactly half of channel 1 in both families, and each
% family's two repeats agree exactly, so the medians are reproducible.
verifyEqual(testCase, familyValue(estimates, "tone", 1), 0.4, AbsTol=1e-5);
verifyEqual(testCase, familyValue(estimates, "noise", 1), 0.36, AbsTol=1e-5);
verifyEqual(testCase, familyValue(estimates, "tone", 2), 0.2, AbsTol=1e-5);
verifyEqual(testCase, familyValue(estimates, "noise", 2), 0.18, AbsTol=1e-5);
verifyTrue(testCase, all(estimates.qc_status == "ok"));
verifyTrue(testCase, all(estimates.n_references == 2));

% Averaging the two families would give 0.38 on channel 1 - a plausible number
% describing neither family. It appears nowhere.
verifyTrue(testCase, value.acoustic.blended_family_value_absent);

% And the estimate is response/QC evidence, not a correction or a probability.
verifyFalse(testCase, value.acoustic.is_caller_probability);
verifyFalse(testCase, value.acoustic.is_gain_correction);
end

function testTheProfileCitesEveryMeasurementAndSourceRun(testCase)
value = testCase.TestData.value;

% Four references on two channels, aggregated from the RMS rows selected by
% exact identifier: eight measurements, eight source runs, all cited.
verifyEqual(testCase, value.acoustic.lineage.source_measurements, 8);
verifyEqual(testCase, value.acoustic.lineage.source_analyses, 8);
verifyEqual(testCase, value.acoustic.lineage.dependency_roles, ...
    "reference_response_measurement");
verifyEqual(testCase, value.database_inventory.channel_response_estimate_sources, 8);

audit = value.acoustic.audit;
verifyEqual(testCase, audit.analysis.status, "completed");
verifyEqual(testCase, unique(audit.source_measurements.metric_key), ...
    "acoustic_rms_amplitude");

% Only the RMS rows were aggregated, but the measurement evidence retained is
% wider than the population that was aggregated.
verifyEqual(testCase, value.database_inventory.derived_measurements, 24);
end

function testARequiredFamilyWithNoEvidenceStaysVisible(testCase)
value = testCase.TestData.value;
missing = value.acoustic.missing_family;

% Two channels, two explicit rows. A required family that simply vanished from
% the result would leave a caller unable to tell it was ever expected.
verifyEqual(testCase, height(missing), 2);
verifyTrue(testCase, all(isnan(missing.value_real)));
verifyEqual(testCase, missing.n_references', [0 0]);
verifyTrue(testCase, all(missing.qc_status == "insufficient_evidence"));
end

% --------------------------------------------------- the attribution boundary ---

function testNoCallerIsAssignedAnywhere(testCase)
value = testCase.TestData.value;

verifyFalse(testCase, value.caller_attribution.performed);
verifyFalse(testCase, value.caller_attribution.combined_confidence_computed);
verifyEqual(testCase, value.database_inventory.caller_attribution_rows, 0);

% The example states its own limits, and the ones that matter are named.
verifyTrue(testCase, any(contains(value.does_not_prove, ...
    "which animal produced any detected vocalization")));
verifyTrue(testCase, any(contains(value.does_not_prove, "calibrated")));
verifyTrue(testCase, any(contains(value.does_not_prove, "distance")));
end

% ------------------------------------------------------------------ helpers ---

function verifyResolution(testCase, summary, window, track, resolution, candidates)
row = summary(summary.window == window & ...
    summary.native_track_id == track, :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.resolution, resolution);
verifyEqual(testCase, row.candidate_count, candidates);
end

function value = resolutionOf(summary, window, track)
row = summary(summary.window == window & summary.native_track_id == track, :);
value = row.resolution;
end

function value = familyValue(estimates, referenceType, channelIndex)
row = estimates(estimates.reference_type == referenceType & ...
    estimates.channel_index == channelIndex, :);
value = row.value_real;
end
