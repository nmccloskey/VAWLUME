function tests = test_deepsqueak_import_demonstration
tests = functiontests({ ...
    @testDemonstrationCompletesTheWholeDeepSqueakPath, ...
    @testDemonstrationReadBacksAreCorrect, ...
    @testDemonstrationRerunAndRelocationAreStable, ...
    @testDemonstrationCreatesNoCrossExtractorRowsAndCleansUp});
end

function testDemonstrationCompletesTheWholeDeepSqueakPath(testCase)
demonstration = runDemonstration();

% Project intake through the real public path, then a valid IR, a conflict-free
% plan, and a committed apply.
verifyEqual(testCase, demonstration.project_intake.status, "completed");
verifyTrue(testCase, demonstration.project_intake.committed);
verifyEqual(testCase, demonstration.project_intake.preview_verdict, "READY FOR INGEST");
verifyGreaterThan(testCase, demonstration.project_intake.recording_id, 0);

verifyTrue(testCase, demonstration.import_summary.ir_valid);
verifyEqual(testCase, demonstration.import_summary.ir_source_rows, 5);
verifyEqual(testCase, demonstration.import_summary.plan_status, "planned");
verifyEqual(testCase, demonstration.import_summary.plan_conflicts, 0);
verifyEqual(testCase, demonstration.import_summary.planned_detections, 5);
verifyEqual(testCase, demonstration.import_summary.planned_measurements, 70);
verifyEqual(testCase, demonstration.import_summary.apply_status, "committed");
verifyTrue(testCase, demonstration.import_summary.committed);

% Exactly one extraction run for the initial import, and the expected call
% population beneath it.
verifyEqual(testCase, demonstration.database_inventory.extraction_runs, 1);
verifyEqual(testCase, demonstration.database_inventory.detections, 5);
verifyEqual(testCase, demonstration.database_inventory.event_measurements, 70);
verifyEqual(testCase, demonstration.database_inventory.curation_events, 5);
verifyEqual(testCase, demonstration.database_inventory.classification_assignments, 5);

% Settings provenance was genuinely available and is captured. No detector model
% was known, and that absence is stated rather than filled in.
verifyEqual(testCase, demonstration.import_summary.settings_status, "captured_profile");
verifyEqual(testCase, demonstration.import_summary.model_status, "not_recoverable");
verifyFalse(testCase, any(demonstration.artifact_provenance.artifact_role == "detector_network"));

verifyEqual(testCase, height(demonstration.foreign_key_violations), 0);
end

function testDemonstrationReadBacksAreCorrect(testCase)
demonstration = runDemonstration();

% The run resolves to the intended recording, the exact extractor version, and
% the exact tracked output mapping profile with its checksum.
runRow = demonstration.extraction_run_provenance;
verifyEqual(testCase, height(runRow), 1);
verifyEqual(testCase, string(runRow.run_key(1)), "demo_deepsqueak_run_1");
verifyEqual(testCase, string(runRow.recording_source(1)), "001_baseline_1.wav");
verifyEqual(testCase, string(runRow.extractor_name(1)), "DeepSqueak");
verifyEqual(testCase, string(runRow.extractor_version(1)), "3.2.1");
verifyEqual(testCase, string(runRow.output_mapping_profile(1)), ...
    "vawlume.deepsqueak.output.v3_2");
verifyEqual(testCase, string(runRow.profile_version(1)), "0.1.0");
verifyMatches(testCase, string(runRow.profile_checksum(1)), "^[0-9a-f]{12}$");
verifyEqual(testCase, string(runRow.settings_profile(1)), "demo.deepsqueak.settings.v1");

% The imported workbook is registered as a portable artifact with a checksum.
artifacts = demonstration.artifact_provenance;
verifyEqual(testCase, string(artifacts.artifact_role), "event_measurement_export");
verifyEqual(testCase, string(artifacts.path_or_uri(1)), ...
    "exports/MOUSE001_BASELINE_Stats.xlsx");
verifyEqual(testCase, string(artifacts.file_format(1)), "xlsx");
verifyMatches(testCase, string(artifacts.checksum(1)), "^[0-9a-f]{12}$");

% Detections keep their DeepSqueak native identifiers, timing, and score.
detections = demonstration.detections;
verifyEqual(testCase, height(detections), 5);
verifyEqual(testCase, string(detections.native_event_id), ["1"; "2"; "3"; "4"; "5"]);
verifyEqual(testCase, detections.start_time_s, ...
    [10.0; 20.0; 31.25; 40.0; 52.5], AbsTol=1e-9);
verifyEqual(testCase, detections.duration_s, ...
    [0.05; 0.044; 0.112; 0.1; 0.03], AbsTol=1e-9);
verifyEqual(testCase, detections.detection_score, ...
    [0.9134; 0.8021; 0.6440; 0.2107; 0.1802], AbsTol=1e-9);

% Accepted state is preserved as extractor review evidence under the frozen
% vocabulary, including for the calls DeepSqueak rejected.
verifyEqual(testCase, string(detections.review_state), ...
    ["accepted"; "accepted"; "accepted"; "rejected"; "rejected"]);
verifyEqual(testCase, string(detections.native_label), ...
    ["class_a"; "class_a"; "class_b"; "class_b"; "class_c"]);

% Labels carry no canonical biological interpretation, and the classification
% run states that the labelling method is unrecorded.
review = demonstration.review_and_labels;
verifyEqual(testCase, unique(string(review.action_type)), "native_review_status_import");
verifyEqual(testCase, unique(string(review.actor_type)), "extractor");
verifyEqual(testCase, unique(string(review.classification_method)), ...
    "native_label_unspecified_provenance");
verifyEqual(testCase, unique(string(review.canonical_class)), ...
    "<no canonical interpretation>");

% Normalization is additive: the native value and unit sit beside the canonical
% value and unit, with the declared transform recorded.
measurements = demonstration.measurements;
frequency = measurementFor(measurements, "1", "Principle Frequency (kHz)");
verifyEqual(testCase, string(frequency.native_value), "62.4");
verifyEqual(testCase, string(frequency.native_unit), "kHz");
verifyEqual(testCase, string(frequency.canonical_feature), "contour_median_frequency");
verifyEqual(testCase, string(frequency.canonical_value), "62400.0");
verifyEqual(testCase, string(frequency.canonical_unit), "Hz");
verifyEqual(testCase, string(frequency.transform_key), "kHz_to_Hz");
verifyEqual(testCase, string(frequency.derivation_stage), "contour_derived");

identity = measurementFor(measurements, "1", "Begin Time (s)");
verifyEqual(testCase, string(identity.transform_key), "identity");
verifyEqual(testCase, string(identity.native_unit), string(identity.canonical_unit));

% The optional missing measurement is shown as missing, never as a zero.
missing = measurementFor(measurements, "2", "Tonality");
verifyEqual(testCase, string(missing.native_value_type), "missing");
verifyEqual(testCase, string(missing.native_value), "<missing>");
verifyEqual(testCase, string(missing.canonical_value), "<missing>");
verifyEqual(testCase, string(missing.native_unit), "ratio");

% Experimental context from project intake is reachable from the recording.
verifyGreaterThan(testCase, height(demonstration.recording_context), 0);
verifyTrue(testCase, ismember("subject", string(demonstration.recording_context.canonical_role)));
end

function testDemonstrationRerunAndRelocationAreStable(testCase)
demonstration = runDemonstration();

% An unchanged rerun reuses every scientific row and writes nothing. The run
% identifier is stable, as the identity contract promises.
rerun = demonstration.rerun;
verifyTrue(testCase, rerun.committed);
verifyEqual(testCase, rerun.extraction_run_action, "reuse");
verifyTrue(testCase, rerun.extraction_run_id_stable);
verifyEqual(testCase, rerun.detections_created, 0);
verifyEqual(testCase, rerun.measurements_created, 0);
verifyEqual(testCase, rerun.detections_reused, 5);
verifyEqual(testCase, rerun.measurements_reused, 70);
verifyTrue(testCase, rerun.scientific_rows_unchanged);

% Relocating the same content under a second absolute root creates no new run,
% artifact, or detections. The stored portable path is not rewritten, while the
% runtime location legitimately differs.
relocation = demonstration.relocation;
verifyTrue(testCase, relocation.committed);
verifyEqual(testCase, relocation.extraction_run_action, "reuse");
verifyEqual(testCase, relocation.artifact_action, "reuse");
verifyTrue(testCase, relocation.runtime_path_changed);
verifyEqual(testCase, relocation.stored_portable_path, ...
    "exports/MOUSE001_BASELINE_Stats.xlsx");
verifyTrue(testCase, relocation.scientific_rows_unchanged);

% After both, the population is exactly the original one.
verifyEqual(testCase, demonstration.database_inventory.extraction_runs, 1);
verifyEqual(testCase, demonstration.database_inventory.detections, 5);
verifyEqual(testCase, demonstration.database_inventory.artifacts, 1);
end

function testDemonstrationCreatesNoCrossExtractorRowsAndCleansUp(testCase)
demonstration = runDemonstration();

% The demonstration must not imply capability VAWLUME does not have yet.
inventory = demonstration.database_inventory;
verifyEqual(testCase, inventory.extraction_runs, 1);
verifyFalse(testCase, isfield(inventory, "match_groups"));

verifyTrue(testCase, any(contains(demonstration.boundaries, "Not supported: MUPET")));
verifyTrue(testCase, any(contains(demonstration.boundaries, ...
    "extractor evidence, not biological truth")));

% Every temporary input and the disposable database are removed before the
% function returns.
verifyTrue(testCase, demonstration.temporary_artifacts_removed);
verifyFalse(testCase, isfolder(demonstration.workspace_root));
verifyFalse(testCase, isfile(demonstration.database_path));
end

% ---------------------------------------------------------------- helpers ---

function demonstration = runDemonstration()
%RUNDEMONSTRATION Call the example itself rather than restating its orchestration.
persistent cached
if ~isempty(cached)
    demonstration = cached;
    return
end

repoRoot = repoRootForTest();
examplesPath = fullfile(repoRoot, "examples");
addpath(examplesPath);
cleanupPath = onCleanup(@() rmpath(examplesPath));
cached = deepsqueak_import_demo(Print=false, RepoRoot=repoRoot);
demonstration = cached;
clear cleanupPath
end

function row = measurementFor(measurements, nativeEventId, nativeName)
matches = string(measurements.native_event_id) == nativeEventId & ...
    string(measurements.native_name) == nativeName;
assert(nnz(matches) == 1, "Expected one measurement for call %s field %s, found %d.", ...
    nativeEventId, nativeName, nnz(matches));
row = table2struct(measurements(matches, :));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
