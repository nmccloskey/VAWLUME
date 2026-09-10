function tests = test_usvseg_import_demonstration
%TEST_USVSEG_IMPORT_DEMONSTRATION Runnable synthetic USVSEG import example.
tests = functiontests(localfunctions);
end

function testDemoImportsUsvsegAndStatesAbsentEvidencePositively(testCase)
value = runDemo();

verifyEqual(testCase, value.project.intake_status, "completed");
verifyEqual(testCase, value.inspection.preview_verdict, "READY FOR INGEST");
verifyTrue(testCase, value.inspection.valid_for_ingest);
verifyTrue(testCase, value.inspection.identifier_column_preserved);
verifyEqual(testCase, value.inspection.source_row_count, 5);
verifyEqual(testCase, value.inspection.declared_version, "preferred");

verifyEqual(testCase, value.primary_run.plan_status, "planned");
verifyTrue(testCase, value.primary_run.plan_wrote_nothing);
verifyEqual(testCase, value.primary_run.import_status, "committed");
verifyEqual(testCase, value.primary_run.detection_count, 5);
verifyEqual(testCase, value.primary_run.event_measurement_count, 35);

% Seven measurements per detection: every mapped source column is retained.
verifyEqual(testCase, height(value.measurements), 35);
verifyEqual(testCase, height(value.detections), 5);
verifyTrue(testCase, all(value.detections.timing_basis == ...
    "profile_selected_event_geometry"));
verifyTrue(testCase, all(logical(value.detections.detection_score_absent)));

% Native tokens survive beside canonicalized values in canonical units.
duration = measurementRow(value.measurements, "1", "duration");
verifyEqual(testCase, duration.native_raw_token, "47.0");
verifyEqual(testCase, double(duration.native_value_real), 47, AbsTol=1e-12);
verifyEqual(testCase, double(duration.canonical_value_real), 0.047, AbsTol=1e-12);
verifyEqual(testCase, duration.native_unit, "ms");
verifyEqual(testCase, duration.canonical_unit, "s");
peak = measurementRow(value.measurements, "1", "maxfreq");
verifyEqual(testCase, double(peak.native_value_real), 72.5, AbsTol=1e-12);
verifyEqual(testCase, double(peak.canonical_value_real), 72500, AbsTol=1e-9);
verifyEqual(testCase, peak.canonical_unit, "Hz");

% USVSEG exports none of these, so none may be synthesized.
verifyEqual(testCase, value.absent_evidence.curation_rows, 0);
verifyEqual(testCase, value.absent_evidence.classification_rows, 0);
verifyEqual(testCase, value.absent_evidence.detection_score_rows, 0);
verifyEqual(testCase, value.absent_evidence.frequency_bound_measurements, 0);
end

function testDemoSettingsRerunUnmappedColumnAndZeroDetectionRun(testCase)
value = runDemo();

% Settings evidence is optional, and its absence is explicit rather than
% silently defaulted from published USVSEG defaults.
verifyEqual(testCase, value.primary_run.settings_status, "unavailable");
verifyFalse(testCase, value.primary_run.settings_verified_run_configuration);
verifyTrue(testCase, value.primary_run.settings_absence_is_explicit);

% usvseg_prm.mat is application-scoped, so it never becomes the run's
% settings profile version.
weak = value.weak_settings_evidence;
verifyEqual(testCase, weak.status, "committed");
verifyEqual(testCase, weak.settings_status, "captured_weak");
verifyEqual(testCase, weak.settings_evidence_strength, "weak_not_run_scoped");
verifyFalse(testCase, weak.verified_run_configuration);
verifyEqual(testCase, weak.run_settings_profile_version_id, -1);
verifyTrue(testCase, contains(weak.settings_evidence_scope, "not_verified"));

% A source column the profile does not claim is preserved, not discarded.
verifyEqual(testCase, weak.unmapped_source_value_count, 5);
verifyEqual(testCase, unique(string(weak.unmapped_source_values.native_field_name)), ...
    "snr_db");
verifyEqual(testCase, string(weak.unmapped_source_values.raw_value_text), ...
    ["11.20"; "9.80"; "12.45"; "10.05"; "8.60"]);

% An unchanged rerun reuses every identity and adds no scientific row.
verifyEqual(testCase, value.rerun.status, "committed");
verifyTrue(testCase, value.rerun.extraction_run_id_stable);
verifyEqual(testCase, value.rerun.new_detections, 0);
verifyEqual(testCase, value.rerun.reused_detections, 5);
verifyTrue(testCase, value.rerun.rows_unchanged);

% A header-only export is a valid zero-detection segmentation pass.
zeroRun = value.zero_detection_run;
verifyEqual(testCase, zeroRun.status, "committed");
verifyTrue(testCase, zeroRun.committed);
verifyEqual(testCase, zeroRun.source_row_count, 0);
verifyEqual(testCase, zeroRun.detection_count, 0);
verifyTrue(testCase, zeroRun.extraction_run_registered);
verifyEqual(testCase, zeroRun.artifact_count, 1);

verifyEqual(testCase, height(value.foreign_key_check), 0);
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyTrue(testCase, any(contains(value.does_not_prove, "calibration")));
end

function value = runDemo()
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
examplePath = fullfile(repoRoot, "examples");
addpath(examplePath);
cleanup = onCleanup(@() rmpath(examplePath));
value = usvseg_import_demo(Print=false, RepoRoot=repoRoot);
clear cleanup
end

function row = measurementRow(measurements, nativeEventId, nativeName)
selected = string(measurements.native_event_id) == nativeEventId & ...
    string(measurements.native_name) == nativeName;
assert(nnz(selected) == 1, ...
    "Expected one '%s' measurement for event %s.", nativeName, nativeEventId);
row = measurements(selected, :);
row.native_raw_token = string(row.native_raw_token);
row.native_unit = string(row.native_unit);
row.canonical_unit = string(row.canonical_unit);
end
