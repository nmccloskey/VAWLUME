function tests = test_mupet_event_population
%TEST_MUPET_EVENT_POPULATION MUPET syllable detections and event measurements.
%
% The contract under test is that a MUPET per-syllable CSV becomes a complete,
% provenance-bearing detection population with its own native semantics intact -
% and that it does not acquire DeepSqueak's semantics on the way in. The two
% deliberate absences, curation and classification evidence, are asserted as
% explicitly as the values that are present.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------------- population ---

function testNominalPopulationIsCompleteAndProvenanceBearing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = apply(fixture, defaultRunSpec(fixture));

verifyEqual(testCase, result.status, "committed");
verifyEqual(testCase, result.applied_counts.detections, 4);
verifyEqual(testCase, result.applied_counts.event_measurements, 48);
verifyEqual(testCase, result.detections.detections_create, 4);
verifyEqual(testCase, result.detections.measurements_create, 48);

stored = fetch(fixture.conn, ...
    "SELECT native_event_id, start_time_s, end_time_s, timing_basis, " + ...
    "event_subtype, IFNULL(notes,'') AS notes " + ...
    "FROM detections ORDER BY CAST(native_event_id AS INTEGER)");
verifyEqual(testCase, height(stored), 4);
verifyEqual(testCase, string(stored.native_event_id), ["1"; "2"; "3"; "4"]);
verifyEqual(testCase, double(stored.start_time_s), [.100; .200; .300; .400], AbsTol=1e-12);
verifyEqual(testCase, double(stored.end_time_s), [.148; .235; .351; .445], AbsTol=1e-12);
verifyEqual(testCase, unique(string(stored.timing_basis)), "profile_selected_event_geometry");
verifyEqual(testCase, unique(string(stored.event_subtype)), "vocalization_detection");

% The CSV row survives as provenance and is never the event's identity.
verifyEqual(testCase, string(stored.notes), ...
    ["source_row=1"; "source_row=2"; "source_row=3"; "source_row=4"]);

% Every syllable is anchored to the run and to the recording project intake
% established, and the graph is referentially sound.
anchored = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "JOIN recordings r ON r.recording_id = d.recording_id " + ...
    "JOIN artifacts a ON a.artifact_id = d.source_artifact_id " + ...
    "WHERE er.run_key = 'mupet-run-1' AND r.recording_id = 1 " + ...
    "AND a.artifact_type = 'extractor_event_export'");
verifyEqual(testCase, double(anchored.n(1)), 4);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testExportedDurationKeepsItsOperationalVariant(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));

% MUPET exports a pre-noise-reduction onset/offset duration, which is a
% different quantity from the post-noise-reduction duration it filters on and
% from the boundaries it also exports. Native milliseconds, canonical seconds,
% the transform, and the operational variant must all survive together.
row = measurementFor(fixture.conn, "1", "syllable duration (msec)");
verifyEqual(testCase, string(row.native_value_type(1)), "real");
verifyEqual(testCase, double(row.native_value_real(1)), 48, AbsTol=1e-12);
verifyEqual(testCase, string(row.native_unit(1)), "ms");
verifyEqual(testCase, double(row.canonical_value_real(1)), 0.048, AbsTol=1e-12);
verifyEqual(testCase, string(row.canonical_unit(1)), "s");
verifyEqual(testCase, string(row.transform_key(1)), "ms_to_s");
verifyEqual(testCase, string(row.operational_variant(1)), "pre_noise_reduction");
verifyEqual(testCase, string(row.canonical_name(1)), "call_duration");
verifyEqual(testCase, string(row.derivation_stage(1)), "pre_noise_reduction_onset_offset");

% The boundaries are the extractor's own, never recomputed from the duration,
% and the duration is never recomputed from the boundaries.
detection = fetch(fixture.conn, ...
    "SELECT start_time_s, end_time_s FROM detections WHERE native_event_id = '2'");
verifyEqual(testCase, double(detection.start_time_s(1)), .200, AbsTol=1e-12);
verifyEqual(testCase, double(detection.end_time_s(1)), .235, AbsTol=1e-12);
exported = measurementFor(fixture.conn, "2", "syllable duration (msec)");
verifyEqual(testCase, double(exported.native_value_real(1)), 34.7, AbsTol=1e-12);
verifyEqual(testCase, double(exported.canonical_value_real(1)), 0.0347, AbsTol=1e-12);

clear cleanup
end

function testTerminalIntervalKeepsRawTokenAndExplicitMissingness(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));

% The final syllable has no following syllable, so MUPET exports its sentinel.
% The lexical token must survive as evidence while the value becomes explicitly
% missing. A zero here would be a fabricated measurement.
final = measurementFor(fixture.conn, "4", "inter-syllable interval (sec)");
verifyEqual(testCase, height(final), 1);
verifyEqual(testCase, string(final.native_value_type(1)), "missing");
verifyEqual(testCase, string(final.native_raw_token(1)), "NA");
verifyEqual(testCase, double(final.native_value_real(1)), 1e308);
verifyEqual(testCase, double(final.canonical_value_real(1)), 1e308);

% The feature's unit and its native-sequence derivation are still known even
% though the value is not.
verifyEqual(testCase, string(final.native_unit(1)), "s");
verifyEqual(testCase, string(final.derivation_stage(1)), "native_sequence_derived");

% The syllable itself still imports completely.
verifyEqual(testCase, measurementCountFor(fixture.conn, "4"), 12);

% Earlier syllables carry real intervals, so missingness is specific rather
% than a whole-column failure, and no VAWLUME-derived interval is substituted.
present = measurementFor(fixture.conn, "1", "inter-syllable interval (sec)");
verifyEqual(testCase, string(present.native_value_type(1)), "real");
verifyEqual(testCase, double(present.native_value_real(1)), 0.052, AbsTol=1e-12);
verifyEqual(testCase, double(present.canonical_value_real(1)), 0.052, AbsTol=1e-12);

clear cleanup
end

function testFrequencyEnergyAndAmplitudeKeepMethodSpecificIdentity(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));

expected = { ...
    "starting frequency (kHz)", 45, 45000, "kHz", "Hz", "kHz_to_Hz", "frequency_start"; ...
    "final frequency (kHz)", 60, 60000, "kHz", "Hz", "kHz_to_Hz", "frequency_end"; ...
    "minimum frequency (kHz)", 40, 40000, "kHz", "Hz", "kHz_to_Hz", "frequency_min"; ...
    "maximum frequency (kHz)", 75, 75000, "kHz", "Hz", "kHz_to_Hz", "frequency_max"; ...
    "mean frequency (kHz)", 55, 55000, "kHz", "Hz", "kHz_to_Hz", "frequency_center"; ...
    "frequency bandwidth (kHz)", 35, 35000, "kHz", "Hz", "kHz_to_Hz", "frequency_bandwidth"; ...
    "total syllable energy (dB)", 12.5, 12.5, "dB", "dB", "identity", "total_energy"; ...
    "peak syllable amplitude (dB)", -18, -18, "dB", "dB", "identity", "peak_amplitude"};

for index = 1:size(expected, 1)
    row = measurementFor(fixture.conn, "1", expected{index, 1});
    verifyEqual(testCase, height(row), 1, expected{index, 1});
    verifyEqual(testCase, double(row.native_value_real(1)), expected{index, 2}, AbsTol=1e-9);
    verifyEqual(testCase, double(row.canonical_value_real(1)), expected{index, 3}, AbsTol=1e-9);
    verifyEqual(testCase, string(row.native_unit(1)), expected{index, 4});
    verifyEqual(testCase, string(row.canonical_unit(1)), expected{index, 5});
    verifyEqual(testCase, string(row.transform_key(1)), expected{index, 6});
    verifyEqual(testCase, string(row.canonical_name(1)), expected{index, 7});
end

% MUPET's mean frequency and DeepSqueak's contour median share a broad
% central-frequency concept but are distinct registered features with distinct
% operational definitions. Importing MUPET must not collapse them.
mupetCentre = measurementFor(fixture.conn, "1", "mean frequency (kHz)");
deepSqueakCentre = fetch(fixture.conn, ...
    "SELECT xf.extractor_feature_id, IFNULL(cf.canonical_name,'') AS canonical_name " + ...
    "FROM extractor_features xf " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE xf.native_name = 'Principle Frequency (kHz)'");
verifyEqual(testCase, height(deepSqueakCentre), 1);
verifyNotEqual(testCase, double(mupetCentre.extractor_feature_id(1)), ...
    double(deepSqueakCentre.extractor_feature_id(1)));
verifyEqual(testCase, string(deepSqueakCentre.canonical_name(1)), "contour_median_frequency");

% Energy and amplitude relate to DeepSqueak power without becoming equivalent
% to it, and importing real rows must not upgrade that seeded relationship.
related = fetch(fixture.conn, ...
    "SELECT fr.relationship_type, fr.consilience_eligible " + ...
    "FROM feature_relationships fr " + ...
    "JOIN extractor_features xf " + ...
    "ON xf.extractor_feature_id IN (fr.feature_a_id, fr.feature_b_id) " + ...
    "WHERE xf.native_name IN ('total syllable energy (dB)','peak syllable amplitude (dB)')");
verifyEqual(testCase, height(related), 2);
verifyEqual(testCase, unique(string(related.relationship_type)), "related");
verifyEqual(testCase, unique(double(related.consilience_eligible)), 0);

clear cleanup
end

% ---------------------------------------------------------- the two zeros ---

function testNoCurationOrClassificationEvidenceIsFabricated(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = apply(fixture, defaultRunSpec(fixture));

% Surviving MUPET's programmatic duration/energy/amplitude filtering is not a
% reviewed state, and the per-syllable CSV carries no label. Neither surface may
% be populated to make MUPET resemble DeepSqueak.
verifyEqual(testCase, countOf(fixture.conn, "curation_events"), 0);
verifyEqual(testCase, countOf(fixture.conn, "classification_runs"), 0);
verifyEqual(testCase, countOf(fixture.conn, "classification_classes"), 0);
verifyEqual(testCase, countOf(fixture.conn, "classification_assignments"), 0);

% No detector score is invented either: MUPET declares no detector-score role.
scores = fetch(fixture.conn, "SELECT IFNULL(detection_score, 1e308) AS score FROM detections");
verifyTrue(testCase, all(double(scores.score) >= 1e307));

% The absence is stated in the manifest rather than left to be inferred.
verifyFalse(testCase, result.curation.present);
verifyEqual(testCase, result.curation.planned_rows, 0);
verifyTrue(testCase, contains(result.curation.reason, "curation_state"));
verifyFalse(testCase, result.classification.present);
verifyEqual(testCase, result.detections.curation_rows_expected, 0);
verifyEqual(testCase, result.detections.classification_rows_expected, 0);

% The run still explains why those syllables exist: the filter thresholds are
% recorded once as settings provenance rather than restated per syllable.
settings = fetch(fixture.conn, ...
    "SELECT IFNULL(a.metadata_json,'') AS metadata_json FROM extraction_runs er " + ...
    "JOIN extraction_run_artifacts era ON era.extraction_run_id = er.extraction_run_id " + ...
    "JOIN artifacts a ON a.artifact_id = era.artifact_id " + ...
    "WHERE er.run_key = 'mupet-run-1' AND era.artifact_role = 'extractor_settings'");
capture = jsondecode(char(string(settings.metadata_json(1))));
verifyEqual(testCase, numel(capture.entries), 11);
verifyEqual(testCase, string(capture.status), "captured");
verifyEqual(testCase, string(capture.role), "extractor_settings");

clear cleanup
end

% -------------------------------------------------------------- validation ---

function testDurationConsistencyWarnsAndNeverRepairs(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = apply(fixture, defaultRunSpec(fixture));

% Three of the four fixture syllables have an exported duration that disagrees
% with end minus start, which is expected for a pre-noise-reduction duration.
% The profile declares the check at warning severity, so the import proceeds and
% reports rather than silently altering one value to match the other.
verifyTrue(testCase, result.committed);
warnings = result.validation.warnings;
verifyEqual(testCase, nnz(contains(warnings, "duration_consistency")), 3);
verifyTrue(testCase, any(contains(warnings, "syllable 2")));

% Both source values remain exactly as exported.
detection = fetch(fixture.conn, ...
    "SELECT start_time_s, end_time_s FROM detections WHERE native_event_id = '3'");
verifyEqual(testCase, double(detection.end_time_s(1)) - double(detection.start_time_s(1)), ...
    0.051, AbsTol=1e-12);
exported = measurementFor(fixture.conn, "3", "syllable duration (msec)");
verifyEqual(testCase, double(exported.native_value_real(1)), 50.2, AbsTol=1e-12);

% The profile names a tolerance source but declares no numeric value, so the
% three checks it cannot evaluate are reported rather than treated as passing.
verifyEqual(testCase, sort(result.validation.unevaluated_checks), sort([ ...
    "final_inter_syllable_interval_missingness"
    "settings_consistency"
    "source_recording_linkage"]));

clear cleanup
end

function testSyllableIdentityFaultsAreRefusedBeforeAnyWrite(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% native_event_id_uniqueness is declared at error severity, so a repeated
% syllable number inside one export is refused before anything is written.
duplicatePath = writeVariant(fixture, "duplicate", duplicateNumberExport());
verifyError(testCase, @() applyPath(fixture, duplicatePath, defaultRunSpec(fixture)), ...
    "vawlume:ingest:MupetEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

% A syllable with no number at all is refused for the same reason: an ordinal is
% never fabricated from row position.
missingPath = writeVariant(fixture, "missingnumber", missingNumberExport());
verifyError(testCase, @() applyPath(fixture, missingPath, defaultRunSpec(fixture)), ...
    "vawlume:ingest:MupetEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

clear cleanup
end

function testGeometryViolationsFollowProfileSeverity(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% event_time_order and frequency_order are declared at error severity.
reversedPath = writeVariant(fixture, "reversed", reversedTimeExport());
verifyError(testCase, @() applyPath(fixture, reversedPath, defaultRunSpec(fixture)), ...
    "vawlume:ingest:MupetEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

invertedPath = writeVariant(fixture, "inverted", invertedFrequencyExport());
verifyError(testCase, @() applyPath(fixture, invertedPath, defaultRunSpec(fixture)), ...
    "vawlume:ingest:MupetEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

% bandwidth_consistency is declared at warning severity, so a disagreeing
% bandwidth is reported and imported. It is never recomputed from min and max.
bandwidthPath = writeVariant(fixture, "bandwidth", inconsistentBandwidthExport());
result = applyPath(fixture, bandwidthPath, defaultRunSpec(fixture));
verifyTrue(testCase, result.committed);
verifyTrue(testCase, any(contains(result.validation.warnings, "bandwidth_consistency")));
stored = measurementFor(fixture.conn, "1", "frequency bandwidth (kHz)");
verifyEqual(testCase, double(stored.native_value_real(1)), 30, AbsTol=1e-12);

clear cleanup
end

function testMissingMappedColumnBlocksTheImport(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% A required mapped column that the CSV does not supply is a source-mapping
% error, so no partial syllable population is written and the adapter does not
% invent the column.
incompletePath = writeVariant(fixture, "nodur", missingDurationColumnExport());
verifyError(testCase, @() applyPath(fixture, incompletePath, defaultRunSpec(fixture)), ...
    "vawlume:ingest:MupetIRNotValid");
verifyEqual(testCase, tableCounts(fixture.conn), before);

clear cleanup
end

% -------------------------------------------------------------- identity ----

function testRowOrderDoesNotChangeEventIdentity(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));
after = tableCounts(fixture.conn);

% The same syllables exported in a different row order are the same population.
% Only the recorded source row differs, because it is provenance rather than
% identity.
reorderedPath = writeVariant(fixture, "reordered", reorderedExport());
result = applyPath(fixture, reorderedPath, reorderedRunSpec(fixture));
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.applied_counts.detections, 4);

first = fetch(fixture.conn, ...
    "SELECT native_event_id, start_time_s FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "WHERE er.run_key = 'mupet-run-1' ORDER BY CAST(native_event_id AS INTEGER)");
second = fetch(fixture.conn, ...
    "SELECT native_event_id, start_time_s FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "WHERE er.run_key = 'mupet-run-reordered' ORDER BY CAST(native_event_id AS INTEGER)");
verifyEqual(testCase, string(first.native_event_id), string(second.native_event_id));
verifyEqual(testCase, double(first.start_time_s), double(second.start_time_s), AbsTol=1e-12);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 8);
verifyGreaterThan(testCase, countOf(fixture.conn, "detections"), after.detections);

clear cleanup
end

function testSyllableNumbersCollideAcrossNeitherRunsNorExtractors(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));

% A second legitimate MUPET run over the same recording reuses the same ordinals
% without collision, because a syllable number is scoped to its run and export.
second = defaultRunSpec(fixture);
second.run_key = "mupet-run-2";
result = apply(fixture, second);
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.applied_counts.detections, 4);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 8);

runs = fetch(fixture.conn, ...
    "SELECT er.run_key, COUNT(*) AS n FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "WHERE d.native_event_id = '1' GROUP BY er.run_key ORDER BY er.run_key");
verifyEqual(testCase, string(runs.run_key), ["mupet-run-1"; "mupet-run-2"]);
verifyEqual(testCase, double(runs.n), [1; 1]);

% A DeepSqueak call carrying the same native id on the same recording is equally
% legal. The DeepSqueak rows are seeded directly here because Pass 4 owns the
% MUPET population only; the full dual-extractor import proof belongs to Pass 5.
seedDeepSqueakDetections(fixture.conn);
shared = fetch(fixture.conn, ...
    "SELECT e.extractor_name FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE d.native_event_id = '1' ORDER BY e.extractor_name, er.extraction_run_id");
verifyEqual(testCase, sort(unique(string(shared.extractor_name))), ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ------------------------------------------------------ reuse and rollback ---

function testCompatibleRerunDoesNotDuplicateScientificRows(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));
after = tableCounts(fixture.conn);

second = apply(fixture, defaultRunSpec(fixture));
verifyEqual(testCase, second.status, "committed");
verifyEqual(testCase, second.applied_counts.detections, 0);
verifyEqual(testCase, second.applied_counts.event_measurements, 0);
verifyEqual(testCase, second.applied_counts.reused_detections, 4);
verifyEqual(testCase, second.applied_counts.reused_event_measurements, 48);
verifyEqual(testCase, tableCounts(fixture.conn), after);

clear cleanup
end

function testChangedStoredEvidenceIsConflictNotSilentUpdate(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));

% A stored measurement is altered behind the importer's back. A rerun must
% detect it by full evidence comparison rather than accept the row because a
% measurement with that feature identity happens to exist.
execute(fixture.conn, ...
    "UPDATE event_measurements SET canonical_value_real = 0.999 " + ...
    "WHERE event_measurement_id = (SELECT em.event_measurement_id " + ...
    "FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "WHERE d.native_event_id = '1' AND xf.native_name = 'syllable duration (msec)')");
after = tableCounts(fixture.conn);

conflicted = plan(fixture, defaultRunSpec(fixture));
verifyTrue(testCase, conflicted.has_conflicts);
verifyEqual(testCase, conflicted.status, "conflict");
verifyTrue(testCase, any(contains(conflicted.conflicts, "stored value differs")));
verifyTrue(testCase, any(contains(conflicted.conflicts, "Syllable '1'")));

% Requesting apply on a conflicting plan returns the conflict for inspection
% rather than raising, and writes nothing. Nothing is repaired.
attempted = apply(fixture, defaultRunSpec(fixture));
verifyEqual(testCase, attempted.status, "conflict");
verifyFalse(testCase, attempted.committed);
verifyEqual(testCase, tableCounts(fixture.conn), after);
altered = measurementFor(fixture.conn, "1", "syllable duration (msec)");
verifyEqual(testCase, double(altered.canonical_value_real(1)), 0.999, AbsTol=1e-12);

% A deleted child is a conflict too, not an invitation to re-insert it.
execute(fixture.conn, ...
    "DELETE FROM event_measurements WHERE event_measurement_id = " + ...
    "(SELECT MIN(event_measurement_id) FROM event_measurements)");
missing = plan(fixture, defaultRunSpec(fixture));
verifyTrue(testCase, any(contains(missing.conflicts, "stored measurement is missing")));

clear cleanup
end

function testLateFailureRollsBackTheWholeScientificGraph(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% event_measurements is the last table the MUPET importer writes. Aborting there
% happens after the settings artifact, the extractor version, the artifacts, the
% run, its recording input, its artifact links, and a detection have all been
% inserted in this transaction. Nothing may survive.
verifyError(testCase, @() applyWithInducedFailure(fixture), ...
    "vawlume:ingest:InducedApplyFailure");

verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 0);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 0);
verifyEqual(testCase, countOf(fixture.conn, "event_measurements"), 0);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

% The connection remains usable and a later import succeeds completely.
recovered = apply(fixture, defaultRunSpec(fixture));
verifyTrue(testCase, recovered.committed);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 4);

clear cleanup
end

% ------------------------------------------------------------- read-backs ---

function testEventReadBacksAnswerTheRequiredQuestions(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec(fixture));

% 1. Syllable -> run -> recording.
anchor = fetch(fixture.conn, ...
    "SELECT er.run_key, r.recording_id, sf.relative_path FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "JOIN recordings r ON r.recording_id = d.recording_id " + ...
    "JOIN source_files sf ON sf.source_file_id = r.source_file_id " + ...
    "WHERE d.native_event_id = '2'");
verifyEqual(testCase, string(anchor.run_key(1)), "mupet-run-1");
verifyEqual(testCase, string(anchor.relative_path(1)), "audio/set/REC_A.wav");

% 2 and 3. Native syllable number and exported boundaries.
core = fetch(fixture.conn, ...
    "SELECT native_event_id, start_time_s, end_time_s FROM detections " + ...
    "WHERE native_event_id = '2'");
verifyEqual(testCase, string(core.native_event_id(1)), "2");
verifyEqual(testCase, double(core.start_time_s(1)), .200, AbsTol=1e-12);

% 4. Exported duration with its operational variant.
duration = measurementFor(fixture.conn, "2", "syllable duration (msec)");
verifyEqual(testCase, string(duration.operational_variant(1)), "pre_noise_reduction");

% 5. Native inter-syllable interval, including the missing final token.
intervals = fetch(fixture.conn, ...
    "SELECT d.native_event_id, em.native_value_type, " + ...
    "IFNULL(em.native_raw_token,'') AS native_raw_token " + ...
    "FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "WHERE xf.native_name = 'inter-syllable interval (sec)' " + ...
    "ORDER BY CAST(d.native_event_id AS INTEGER)");
verifyEqual(testCase, height(intervals), 4);
verifyEqual(testCase, string(intervals.native_value_type), ...
    ["real"; "real"; "real"; "missing"]);
verifyEqual(testCase, string(intervals.native_raw_token(4)), "NA");

% 6. Native and canonical frequency features together.
frequencies = fetch(fixture.conn, ...
    "SELECT xf.native_name, cf.canonical_name, em.native_value_real, " + ...
    "em.canonical_value_real FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "WHERE d.native_event_id = '1' AND cf.feature_domain = 'frequency' " + ...
    "ORDER BY cf.canonical_name");
verifyEqual(testCase, height(frequencies), 6);
verifyEqual(testCase, sort(string(frequencies.canonical_name)), sort([ ...
    "frequency_bandwidth"; "frequency_center"; "frequency_end"; ...
    "frequency_max"; "frequency_min"; "frequency_start"]));

% 7. Total energy and peak amplitude under their own canonical concepts.
levels = fetch(fixture.conn, ...
    "SELECT cf.canonical_name, cf.feature_domain FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "WHERE d.native_event_id = '1' AND cf.canonical_name IN ('total_energy','peak_amplitude') " + ...
    "ORDER BY cf.canonical_name");
verifyEqual(testCase, string(levels.canonical_name), ["peak_amplitude"; "total_energy"]);
verifyEqual(testCase, string(levels.feature_domain), ["amplitude"; "power_energy"]);

% 8 and 9. No fabricated curation row and no fabricated class assignment.
fabricated = fetch(fixture.conn, ...
    "SELECT (SELECT COUNT(*) FROM curation_events ce JOIN detections d " + ...
    "ON d.detection_id = ce.detection_id) AS curation, " + ...
    "(SELECT COUNT(*) FROM classification_assignments ca JOIN detections d " + ...
    "ON d.detection_id = ca.detection_id) AS assignments");
verifyEqual(testCase, double(fabricated.curation(1)), 0);
verifyEqual(testCase, double(fabricated.assignments(1)), 0);

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname); mkdir(scratch);
dbPath = fullfile(scratch, "mupet_events.sqlite");
copyfile(seededTemplateDatabase(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
execute(conn, "INSERT INTO projects(project_key, project_name) VALUES('proj-a','Project A')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri,relative_path,filename) " + ...
    "VALUES(1,'recording_audio','audio/set/REC_A.wav','audio/set/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id,native_recording_id) VALUES(1,1,'REC_A')");

exportPath = fullfile(scratch, "mupet", "audio", "set", "CSV", "REC_A.csv");
configPath = fullfile(scratch, "mupet", "config.csv");
writeCsv(exportPath, nominalExport());
writeText(configPath, strjoin(nominalConfigLines(), newline) + newline);
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    artifact_root=scratch, export_path=exportPath, config_path=configPath);
end

function path = seededTemplateDatabase(repoRoot)
persistent templatePath
if ~isempty(templatePath) && isfile(templatePath), path = templatePath; return, end
templatePath = string(tempname) + ".sqlite";
conn = sqlite(char(templatePath), "create"); cleaner = onCleanup(@() close(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
delete(cleaner); path = templatePath;
end

function tearDown(conn, scratch, repoRoot)
try close(conn); catch; end
if isfolder(scratch), rmdir(scratch, "s"); end
rmpath(fullfile(repoRoot, "src"));
end

function spec = defaultRunSpec(fixture)
spec = struct(run_key="mupet-run-1", extractor_version="2.1", ...
    run_label="MUPET run 1", settings=struct(config_path=fixture.config_path));
end

function spec = reorderedRunSpec(fixture)
spec = defaultRunSpec(fixture);
spec.run_key = "mupet-run-reordered";
end

function ref = portableRef()
ref = struct(project_key="proj-a", source_relative_path="audio/set/REC_A.wav");
end

function result = plan(fixture, spec)
result = vawlume.ingest.mupet(fixture.conn, fixture.export_path, portableRef(), spec, ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root);
end

function result = apply(fixture, spec)
result = vawlume.ingest.mupet(fixture.conn, fixture.export_path, portableRef(), spec, ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
end

function result = applyPath(fixture, exportPath, spec)
result = vawlume.ingest.mupet(fixture.conn, exportPath, portableRef(), spec, ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
end

function path = writeVariant(fixture, variant, cells)
path = fullfile(fixture.scratch, "mupet", variant, "CSV", "REC_A.csv");
writeCsv(path, cells);
end

function applyWithInducedFailure(fixture)
execute(fixture.conn, ...
    "CREATE TRIGGER trg_induced_mupet_failure " + ...
    "BEFORE INSERT ON event_measurements FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced measurement failure'); END");
restore = onCleanup(@() dropTrigger(fixture.conn));
try
    apply(fixture, defaultRunSpec(fixture));
catch exception
    clear restore
    error("vawlume:ingest:InducedApplyFailure", ...
        "Induced apply failure surfaced as: %s", exception.message);
end
clear restore
error("vawlume:ingest:InducedApplyFailure", "The induced failure did not abort the apply.");
end

function dropTrigger(conn)
try
    execute(conn, "DROP TRIGGER IF EXISTS trg_induced_mupet_failure");
catch
end
end

function seedDeepSqueakDetections(conn)
%SEEDDEEPSQUEAKDETECTIONS A DeepSqueak run on the same recording, inserted directly.
%
% Pass 4 owns the MUPET population. These rows exist only to prove that native
% ids do not collide across extractors; importing a real DeepSqueak export
% alongside a real MUPET one is the Pass 5 independence proof.
version = fetch(conn, "SELECT ev.extractor_version_id FROM extractor_versions ev " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE e.extractor_name = 'DeepSqueak' AND ev.version_label = '3.2.x'");
profile = fetch(conn, "SELECT cpv.profile_version_id FROM config_profile_versions cpv " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE cp.profile_key = 'vawlume.deepsqueak.output.v3_2'");
execute(conn, "INSERT INTO extraction_runs(project_id,extractor_version_id,run_key," + ...
    "output_mapping_profile_version_id,status) VALUES(1," + ...
    string(double(version.extractor_version_id(1))) + ",'ds-existing'," + ...
    string(double(profile.profile_version_id(1))) + ",'imported')");
runId = scalarFetch(conn, "SELECT last_insert_rowid() AS id", "id");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id,input_role) " + ...
    "VALUES(" + string(runId) + ",1,'source_audio')");
for nativeId = ["1", "2"]
    execute(conn, "INSERT INTO detections(extraction_run_id,recording_id,native_event_id," + ...
        "start_time_s,end_time_s) VALUES(" + string(runId) + ",1,'" + nativeId + "',9.0,9.1)");
end
end

function headers = nominalHeaders()
headers = {'Syllable number', 'Syllable start time (sec)', 'Syllable end time (sec)', ...
    'inter-syllable interval (sec)', 'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', 'maximum frequency (kHz)', ...
    'mean frequency (kHz)', 'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
end

function cells = nominalExport()
% Four synthetic syllables. Syllable 1's exported duration agrees with its
% boundaries; syllables 2 to 4 disagree by more than representation noise, which
% is what a pre-noise-reduction duration legitimately does. Syllable 4 carries
% the terminal inter-syllable sentinel.
cells = [nominalHeaders(); ...
    {1, .100, .148, .052, 48, 45, 60, 40, 75, 55, 35, 12.5, -18}; ...
    {2, .200, .235, .065, 34.7, 46, 59, 41, 74, 54, 33, 11.5, -19}; ...
    {3, .300, .351, .049, 50.2, 47, 61, 42, 76, 56, 34, 10.5, -20}; ...
    {4, .400, .445, 'NA', 44.9, 48, 62, 43, 77, 57, 34, 9.5, -21}];
end

function cells = reorderedExport()
cells = nominalExport();
cells = [cells(1, :); cells([5 3 2 4], :)];
end

function cells = duplicateNumberExport()
cells = nominalExport();
cells{3, 1} = 1;
end

function cells = missingNumberExport()
cells = nominalExport();
cells{3, 1} = [];
end

function cells = reversedTimeExport()
cells = nominalExport();
cells{2, 3} = 0.050;
end

function cells = invertedFrequencyExport()
cells = nominalExport();
cells{2, 8} = 80;
end

function cells = inconsistentBandwidthExport()
cells = nominalExport();
cells{2, 11} = 30;
end

function cells = missingDurationColumnExport()
cells = nominalExport();
cells(:, 5) = [];
end

function lines = nominalConfigLines()
lines = ["noise-reduction,5"; "minimum-syllable-duration,008"; ...
    "maximum-syllable-duration,200"; "minimum-syllable-total-energy,-15"; ...
    "minimum-syllable-peak-amplitude,-25"; "minimum-syllable-distance,5"; ...
    "sample-frequency,250000"; "minimum-usv-frequency,30000"; ...
    "maximum-usv-frequency,120000"; "number-filterbank-filters,64"; "filterbank-type,1"];
end

function rows = measurementFor(conn, nativeEventId, nativeName)
rows = fetch(conn, ...
    "SELECT em.extractor_feature_id, em.native_value_type, " + ...
    "IFNULL(em.native_raw_token,'') AS native_raw_token, " + ...
    "IFNULL(em.native_value_real, 1e308) AS native_value_real, " + ...
    "IFNULL(em.canonical_value_real, 1e308) AS canonical_value_real, " + ...
    "IFNULL(em.native_unit,'') AS native_unit, " + ...
    "IFNULL(em.canonical_unit,'') AS canonical_unit, " + ...
    "IFNULL(em.transform_key,'') AS transform_key, " + ...
    "IFNULL(em.operational_variant,'') AS operational_variant, " + ...
    "IFNULL(em.source_locator,'') AS source_locator, " + ...
    "IFNULL(xf.derivation_stage,'') AS derivation_stage, " + ...
    "IFNULL(cf.canonical_name,'') AS canonical_name " + ...
    "FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "LEFT JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "WHERE d.native_event_id = '" + nativeEventId + "' " + ...
    "AND xf.native_name = '" + nativeName + "'");
end

function value = measurementCountFor(conn, nativeEventId)
value = scalarFetch(conn, ...
    "SELECT COUNT(*) AS n FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "WHERE d.native_event_id = '" + nativeEventId + "'", "n");
end

function counts = tableCounts(conn)
names = ["projects", "source_files", "recordings", "config_profiles", ...
    "config_profile_versions", "extractors", "extractor_versions", "artifacts", ...
    "extraction_runs", "extraction_run_inputs", "extraction_run_artifacts", ...
    "extractor_objects", "detections", "event_measurements", "curation_events", ...
    "classification_runs", "classification_classes", "classification_assignments"];
counts = struct();
for name = names
    counts.(name) = countOf(conn, name);
end
end

function value = countOf(conn, name)
value = scalarFetch(conn, "SELECT COUNT(*) AS n FROM " + name, "n");
end

function value = scalarFetch(conn, query, field)
rows = fetch(conn, query);
value = double(rows.(char(field))(1));
end

function writeCsv(path, cells)
makeParent(path);
if isfile(path), delete(path); end
writecell(cells, path);
end

function writeText(path, value)
makeParent(path);
id = fopen(path, "w");
assert(id >= 0);
cleaner = onCleanup(@() fclose(id));
fprintf(id, "%s", value);
delete(cleaner);
end

function makeParent(path)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
