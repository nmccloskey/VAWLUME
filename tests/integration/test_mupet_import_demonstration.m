function tests = test_mupet_import_demonstration
tests = functiontests({ ...
    @testDemonstrationCompletesTheWholeMupetPath, ...
    @testSettingsProvenanceIsCapturedNotAssumed, ...
    @testMeasurementsKeepNativeEvidenceBesideCanonicalForm, ...
    @testTerminalIntervalStaysExplicitlyMissing, ...
    @testCurationAndClassificationAbsenceIsContract, ...
    @testRerunAndRelocationAreStable, ...
    @testCoResidenceShowsTwoExtractorsAndNoMatching, ...
    @testDemonstrationCleansUpEveryTemporaryArtifact});
end

function testDemonstrationCompletesTheWholeMupetPath(testCase)
demonstration = runDemonstration();

% Project intake through the real public path.
verifyEqual(testCase, demonstration.project_intake.status, "completed");
verifyTrue(testCase, demonstration.project_intake.committed);
verifyEqual(testCase, demonstration.project_intake.preview_verdict, "READY FOR INGEST");
verifyGreaterThan(testCase, demonstration.project_intake.recording_id, 0);

% The adapter reads the CSV without database access, keeps the interval column
% lexical so its NA survives, and accepts the declared v2.1 version.
adapter = demonstration.adapter_summary;
verifyEqual(testCase, adapter.row_count, 4);
verifyEqual(testCase, adapter.column_count, 13);
verifyEqual(testCase, adapter.lexical_columns, "inter-syllable interval (sec)");
verifyEqual(testCase, adapter.extractor_version_status, "preferred");
verifyEqual(testCase, adapter.adapter_errors, 0);
verifyTrue(testCase, adapter.valid_for_ingest);

% The dry run is IR-only and reports the normalized missing token before any
% database write happens.
verifyEqual(testCase, demonstration.preview_summary.verdict, "READY FOR INGEST");
verifyEqual(testCase, demonstration.preview_summary.ir_record_count, 4);
verifyEqual(testCase, demonstration.preview_summary.ir_issue_codes, ...
    "MISSING_TOKEN_NORMALIZED");

% A conflict-free plan, then a committed apply of exactly four syllables.
summary = demonstration.import_summary;
verifyTrue(testCase, summary.ir_valid);
verifyEqual(testCase, summary.ir_source_rows, 4);
verifyEqual(testCase, summary.plan_status, "planned");
verifyEqual(testCase, summary.plan_conflicts, 0);
verifyEqual(testCase, summary.planned_detections, 4);
verifyEqual(testCase, summary.planned_measurements, 48);
verifyEqual(testCase, summary.apply_status, "committed");
verifyTrue(testCase, summary.committed);
verifyTrue(testCase, summary.provenance_complete);

% The exported duration is pre-noise-reduction, so it may legitimately disagree
% with the boundary span. That is a declared warning-severity check, and both
% values are stored exactly as exported rather than one repairing the other.
verifyTrue(testCase, summary.validation_valid);
verifyEqual(testCase, summary.validation_warnings, 1);
verifyTrue(testCase, contains(demonstration.validation.warnings(1), ...
    "duration_consistency"));

detections = demonstration.detections;
verifyEqual(testCase, height(detections), 4);
verifyEqual(testCase, string(detections.native_event_id), ["1"; "2"; "3"; "4"]);
verifyEqual(testCase, detections.start_time_s, ...
    [10.000; 10.200; 10.500; 10.800], AbsTol=1e-9);
verifyEqual(testCase, detections.end_time_s, ...
    [10.050; 10.240; 10.560; 10.835], AbsTol=1e-9);
verifyEqual(testCase, detections.exported_duration_s, ...
    [0.050; 0.038; 0.060; 0.035], AbsTol=1e-9);
verifyEqual(testCase, unique(string(detections.duration_variant)), ...
    "pre_noise_reduction");

% Syllable 2 is the one case where the exported duration and the boundary span
% differ. Neither was recomputed from the other.
verifyEqual(testCase, detections.boundary_span_s(2), 0.040, AbsTol=1e-9);
verifyEqual(testCase, detections.exported_duration_s(2), 0.038, AbsTol=1e-9);

verifyEqual(testCase, height(demonstration.foreign_key_violations), 0);
end

function testSettingsProvenanceIsCapturedNotAssumed(testCase)
demonstration = runDemonstration();

% Every declared native key is captured from the generated config.csv, none is
% missing, and nothing is unrecognized or substituted.
settings = demonstration.settings_summary;
verifyEqual(testCase, settings.mode, "config_csv");
verifyEqual(testCase, settings.status, "captured");
verifyEqual(testCase, settings.capture_status, "captured");
verifyTrue(testCase, settings.capture_complete);
verifyEqual(testCase, settings.declared_keys_captured, 11);
verifyEqual(testCase, settings.missing_required_keys, 0);
verifyEqual(testCase, settings.unrecognized_keys, 0);

% Both the source checksum and the structured-capture checksum are reported, and
% the capture declares itself a faithful reading of the source rather than a
% derived reinterpretation of it.
verifyMatches(testCase, settings.source_checksum, "^[0-9a-f]{12}$");
verifyMatches(testCase, settings.structured_capture_checksum, "^[0-9a-f]{12}$");
verifyEqual(testCase, settings.lineage_derivation, "faithful_config_csv_capture");
verifyEqual(testCase, settings.source_artifact, "config.csv");

capture = demonstration.settings_capture;
verifyEqual(testCase, height(capture), 11);
verifyEqual(testCase, unique(string(capture.status)), "captured");
verifyTrue(testCase, ismember("sample-frequency", string(capture.native_name)));
verifyFalse(testCase, any(strlength(string(capture.canonical_setting)) == 0));

% The run resolves the exact recording, extractor version, and tracked output
% mapping profile version with its checksum.
runs = demonstration.extraction_run_provenance;
mupetRun = runs(string(runs.extractor_name) == "MUPET", :);
verifyEqual(testCase, height(mupetRun), 1);
verifyEqual(testCase, string(mupetRun.run_key(1)), "demo_mupet_run_1");
verifyEqual(testCase, string(mupetRun.recording_source(1)), "001_baseline_1.wav");
verifyEqual(testCase, string(mupetRun.extractor_version(1)), "2.1");
verifyEqual(testCase, string(mupetRun.output_mapping_profile(1)), ...
    "vawlume.mupet.output.v2_1");
verifyEqual(testCase, string(mupetRun.profile_version(1)), "0.1.0");
verifyMatches(testCase, string(mupetRun.profile_checksum(1)), "^[0-9a-f]{12}$");

% MUPET's settings live as the registered native artifact rather than a
% synthesized profile version. The demonstration says which of those two it is,
% instead of reporting the settings as unrecoverable.
verifyEqual(testCase, string(mupetRun.settings_provenance(1)), ...
    "<native settings artifact>");

% All three MUPET artifact roles are registered with portable paths and
% checksums, and only the processed .mat is marked native.
artifacts = demonstration.artifact_provenance;
mupetArtifacts = artifacts(string(artifacts.extractor_name) == "MUPET", :);
verifyEqual(testCase, sort(string(mupetArtifacts.artifact_role)), ...
    ["event_measurement_export"; "extractor_settings"; "native_processed_recording"]);
verifyTrue(testCase, ismember("CSV/MOUSE001_BASELINE.csv", ...
    string(mupetArtifacts.path_or_uri)));
verifyFalse(testCase, any(strlength(string(mupetArtifacts.checksum)) == 0));
native = mupetArtifacts(string(mupetArtifacts.artifact_role) == ...
    "native_processed_recording", :);
verifyEqual(testCase, double(native.is_native(1)), 1);
end

function testMeasurementsKeepNativeEvidenceBesideCanonicalForm(testCase)
demonstration = runDemonstration();
measurements = demonstration.measurements;

% Normalization is additive. The millisecond duration keeps its native value and
% unit beside the canonical seconds, names the transform, and carries the
% operational variant that says which duration this actually is.
duration = measurementFor(measurements, "syllable duration (msec)");
verifyEqual(testCase, string(duration.native_value), "50.0");
verifyEqual(testCase, string(duration.native_unit), "ms");
verifyEqual(testCase, string(duration.canonical_feature), "call_duration");
verifyEqual(testCase, string(duration.canonical_value), "0.05");
verifyEqual(testCase, string(duration.canonical_unit), "s");
verifyEqual(testCase, string(duration.transform_key), "ms_to_s");
verifyEqual(testCase, string(duration.operational_variant), "pre_noise_reduction");
verifyEqual(testCase, string(duration.derivation_stage), ...
    "pre_noise_reduction_onset_offset");

% Frequencies convert kHz to Hz and keep their filterbank derivation stage.
for pair = ["minimum frequency (kHz)", "frequency_min"; ...
        "maximum frequency (kHz)", "frequency_max"; ...
        "mean frequency (kHz)", "frequency_center"]'
    row = measurementFor(measurements, pair(1));
    verifyEqual(testCase, string(row.canonical_feature), pair(2));
    verifyEqual(testCase, string(row.native_unit), "kHz");
    verifyEqual(testCase, string(row.canonical_unit), "Hz");
    verifyEqual(testCase, string(row.transform_key), "kHz_to_Hz");
    verifyEqual(testCase, string(row.derivation_stage), "spectral_filterbank");
end
verifyEqual(testCase, ...
    string(measurementFor(measurements, "minimum frequency (kHz)").canonical_value), ...
    "50000.0");

% Energy and amplitude stay two separate quantities under identity transforms.
energy = measurementFor(measurements, "total syllable energy (dB)");
amplitude = measurementFor(measurements, "peak syllable amplitude (dB)");
verifyEqual(testCase, string(energy.canonical_feature), "total_energy");
verifyEqual(testCase, string(amplitude.canonical_feature), "peak_amplitude");
verifyEqual(testCase, string(energy.transform_key), "identity");
verifyEqual(testCase, string(amplitude.transform_key), "identity");
end

function testTerminalIntervalStaysExplicitlyMissing(testCase)
demonstration = runDemonstration();
intervals = demonstration.interval_evidence;

verifyEqual(testCase, height(intervals), 4);
verifyEqual(testCase, unique(string(intervals.derivation_stage)), ...
    "native_sequence_derived");

% The three intervals MUPET actually exported are stored as real values.
verifyEqual(testCase, string(intervals.native_value_type(1:3)), ...
    ["real"; "real"; "real"]);
verifyEqual(testCase, string(intervals.canonical_value(1:3)), ...
    ["0.15"; "0.26"; "0.24"]);

% The terminal syllable has no following syllable. Its NA is kept as the raw
% token with no typed value, and never becomes a zero interval.
terminal = intervals(4, :);
verifyEqual(testCase, string(terminal.native_event_id), "4");
verifyEqual(testCase, string(terminal.native_value_type), "missing");
verifyEqual(testCase, string(terminal.native_raw_token), "NA");
verifyEqual(testCase, string(terminal.native_value), "<missing>");
verifyEqual(testCase, string(terminal.canonical_value), "<missing>");
end

function testCurationAndClassificationAbsenceIsContract(testCase)
demonstration = runDemonstration();
absence = demonstration.capability_absence;

% The per-syllable CSV exports no review state, no class label, and no detector
% score, so a MUPET import creates none of the three. This is the contract, and
% the manifest states the zeros positively rather than leaving them inferred.
verifyEqual(testCase, absence.mupet_curation_rows, 0);
verifyEqual(testCase, absence.mupet_classification_assignments, 0);
verifyEqual(testCase, absence.mupet_detections_with_score, 0);
verifyEqual(testCase, absence.curation_rows_expected, 0);
verifyEqual(testCase, absence.classification_rows_expected, 0);
verifyTrue(testCase, any(contains(absence.reason, "not a reviewed state")));

verifyEqual(testCase, unique(string(demonstration.detections.detection_score)), ...
    "<none exported>");
verifyTrue(testCase, any(contains(demonstration.boundaries, ...
    "Contract, not omission: settings provenance is required to apply.")));
end

function testRerunAndRelocationAreStable(testCase)
demonstration = runDemonstration();

% An unchanged rerun reuses every scientific row and writes nothing.
rerun = demonstration.rerun;
verifyTrue(testCase, rerun.committed);
verifyEqual(testCase, rerun.extraction_run_action, "reuse");
verifyTrue(testCase, rerun.extraction_run_id_stable);
verifyEqual(testCase, rerun.detections_created, 0);
verifyEqual(testCase, rerun.measurements_created, 0);
verifyEqual(testCase, rerun.detections_reused, 4);
verifyEqual(testCase, rerun.measurements_reused, 48);
verifyTrue(testCase, rerun.scientific_rows_unchanged);

% Relocating the CSV, the config, and the native .mat under a second absolute
% root creates no new run and no new artifact. The stored portable identity is
% not rewritten merely because the runtime path changed.
relocation = demonstration.relocation;
verifyTrue(testCase, relocation.committed);
verifyEqual(testCase, relocation.extraction_run_action, "reuse");
verifyEqual(testCase, relocation.artifact_actions, "reuse, reuse, reuse");
verifyTrue(testCase, relocation.runtime_path_changed);
verifyEqual(testCase, relocation.stored_portable_path, "CSV/MOUSE001_BASELINE.csv");
verifyTrue(testCase, relocation.scientific_rows_unchanged);
end

function testCoResidenceShowsTwoExtractorsAndNoMatching(testCase)
demonstration = runDemonstration();

verifyTrue(testCase, demonstration.deepsqueak_appendix.committed);

% Two runs, one recording, and each extractor's capabilities intact. MUPET
% carries no curation, no class assignment, and no score; DeepSqueak carries all
% three. Neither is required by the relational model.
rows = demonstration.co_residence;
verifyEqual(testCase, height(rows), 2);
mupet = rows(string(rows.extractor_name) == "MUPET", :);
deepsqueak = rows(string(rows.extractor_name) == "DeepSqueak", :);
verifyEqual(testCase, double(mupet.detections(1)), 4);
verifyEqual(testCase, double(mupet.scored(1)), 0);
verifyEqual(testCase, double(mupet.curation_rows(1)), 0);
verifyEqual(testCase, double(mupet.class_assignments(1)), 0);
verifyEqual(testCase, double(deepsqueak.detections(1)), 2);
verifyEqual(testCase, double(deepsqueak.scored(1)), 2);
verifyEqual(testCase, double(deepsqueak.curation_rows(1)), 2);
verifyEqual(testCase, double(deepsqueak.class_assignments(1)), 2);

% Six broad concepts are available for both extractors by canonical name, in
% comparable canonical units, without either extractor's native field or
% transform being erased.
concepts = demonstration.cross_extractor_concepts;
shared = ["call_start_time", "call_end_time", "call_duration", ...
    "frequency_min", "frequency_max", "frequency_bandwidth"];
for concept = shared
    present = string(concepts.extractor_name(string(concepts.canonical_name) == concept));
    verifyEqual(testCase, sort(present), ["DeepSqueak"; "MUPET"], concept);
end
verifyFalse(testCase, any(strlength(string(concepts.native_name)) == 0));
verifyFalse(testCase, any(strlength(string(concepts.transform_key)) == 0));

% Central frequency is the deliberate exception. DeepSqueak's contour median is
% not registered under the generic canonical name MUPET's filterbank mean uses,
% so only MUPET appears here. Cross-extractor comparison of that concept must go
% through the shared equivalence class, which is matching work and not import's.
centre = string(concepts.extractor_name( ...
    string(concepts.canonical_name) == "frequency_center"));
verifyEqual(testCase, centre, "MUPET");

% Import creates no correspondence between the two populations, because none is
% implemented.
inventory = demonstration.database_inventory;
verifyEqual(testCase, inventory.extraction_runs, 2);
verifyEqual(testCase, inventory.detections, 6);
verifyEqual(testCase, inventory.event_measurements, 76);
verifyEqual(testCase, inventory.candidate_pairs, 0);
verifyEqual(testCase, inventory.match_groups, 0);
verifyEqual(testCase, inventory.consensus_events, 0);
verifyEqual(testCase, inventory.consilience_assessments, 0);
end

function testDemonstrationCleansUpEveryTemporaryArtifact(testCase)
demonstration = runDemonstration();

verifyTrue(testCase, any(contains(demonstration.boundaries, ...
    "Not supported: cross-extractor matching")));
verifyTrue(testCase, any(contains(demonstration.boundaries, ...
    "Not supported: native .mat parsing")));

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
cached = mupet_import_demo(Print=false, RepoRoot=repoRoot);
demonstration = cached;
clear cleanupPath
end

function row = measurementFor(measurements, nativeName)
matches = string(measurements.native_name) == nativeName;
assert(nnz(matches) == 1, "Expected one measurement for %s, found %d.", ...
    nativeName, nnz(matches));
row = table2struct(measurements(matches, :));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
