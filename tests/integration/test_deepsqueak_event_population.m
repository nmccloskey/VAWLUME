function tests = test_deepsqueak_event_population
tests = functiontests({ ...
    @testNominalPopulationIsCompleteAndProvenanceBearing, ...
    @testMeasurementsPreserveNativeAndCanonicalEvidence, ...
    @testMissingMeasurementKeepsExplicitMissingness, ...
    @testAcceptedBecomesCurationEvidenceNotTruth, ...
    @testScoreIsStoredUnderItsDeclaredSemantics, ...
    @testLabelIsPreservedWithoutBiologicalInterpretation, ...
    @testDetectionIdentityIgnoresRowOrder, ...
    @testTwoRunsOverOneRecordingReuseNativeCallIds, ...
    @testDuplicateCallIdWithinOneRunIsRefused, ...
    @testTimingViolationsFollowProfileSeverity, ...
    @testCompatibleRerunDoesNotDuplicateScientificRows, ...
    @testChangedEvidenceIsConflictNotSilentUpdate, ...
    @testLateFailureRollsBackTheWholeEventPopulation, ...
    @testEventReadBacksAnswerTheRequiredQuestions});
end

function testNominalPopulationIsCompleteAndProvenanceBearing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

planned = plan(fixture, defaultRunSpec());
% The caller can inspect the whole population before commit.
verifyEqual(testCase, planned.status, "planned");
verifyEqual(testCase, height(planned.events), 3);
verifyEqual(testCase, planned.detections.detections_create, 3);
verifyEqual(testCase, planned.detections.measurements_create, 42);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 0);

% Measurement count is 14 registered features per call, not the 18 mapped IR
% values: identity, review, label, and artifact-locator evidence are not
% measurements.
verifyEqual(testCase, unique(planned.events.measurement_count), 14);

result = apply(fixture, defaultRunSpec());
verifyEqual(testCase, result.status, "committed");
verifyEqual(testCase, result.applied_counts.detections, 3);
verifyEqual(testCase, result.applied_counts.event_measurements, 42);
verifyEqual(testCase, result.applied_counts.curation_events, 3);

stored = fetch(fixture.conn, ...
    "SELECT native_event_id, start_time_s, end_time_s, timing_basis, " + ...
    "extraction_run_id, recording_id, source_artifact_id, IFNULL(notes,'') AS notes " + ...
    "FROM detections ORDER BY CAST(native_event_id AS INTEGER)");
verifyEqual(testCase, height(stored), 3);
verifyEqual(testCase, string(stored.native_event_id), ["1"; "2"; "3"]);
verifyEqual(testCase, stored.start_time_s, [10.0; 20.0; 40.0]);
verifyEqual(testCase, stored.end_time_s, [10.05; 20.04; 40.1]);
verifyEqual(testCase, unique(string(stored.timing_basis)), "profile_selected_event_geometry");

% Every detection is bound to the established recording, the extraction run, and
% the imported export artifact.
verifyEqual(testCase, unique(double(stored.recording_id)), fixture.recording_a);
verifyEqual(testCase, unique(double(stored.extraction_run_id)), ...
    result.extraction_run.extraction_run_id);
verifyEqual(testCase, numel(unique(double(stored.source_artifact_id))), 1);
verifyFalse(testCase, any(isnan(double(stored.source_artifact_id))));

% The workbook row survives as provenance without being event identity.
verifyEqual(testCase, string(stored.notes), ...
    ["source_row=1"; "source_row=2"; "source_row=3"]);

% No cross-extractor or consensus rows are invented.
for name = ["candidate_pairs", "match_groups", "consensus_events", ...
        "extractor_objects", "unmapped_source_values"]
    verifyEqual(testCase, countOf(fixture.conn, name), 0);
end
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testMeasurementsPreserveNativeAndCanonicalEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());

rows = fetch(fixture.conn, ...
    "SELECT xf.native_name, em.native_value_type, " + ...
    "IFNULL(em.native_raw_token,'') AS native_raw_token, em.native_value_real, " + ...
    "IFNULL(em.native_unit,'') AS native_unit, em.canonical_value_real, " + ...
    "IFNULL(em.canonical_unit,'') AS canonical_unit, " + ...
    "IFNULL(em.transform_key,'') AS transform_key, " + ...
    "IFNULL(cf.canonical_name,'') AS canonical_name, " + ...
    "IFNULL(em.source_locator,'') AS source_locator " + ...
    "FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "LEFT JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "WHERE d.native_event_id = '1' ORDER BY xf.native_name");
verifyEqual(testCase, height(rows), 14);

% A declared transform is preserved with both operand forms and both units, so
% normalization is additive rather than destructive.
frequency = rowFor(rows, "Principle Frequency (kHz)");
verifyEqual(testCase, frequency.native_value_real, 62.4);
verifyEqual(testCase, string(frequency.native_unit), "kHz");
verifyEqual(testCase, frequency.canonical_value_real, 62400);
verifyEqual(testCase, string(frequency.canonical_unit), "Hz");
verifyEqual(testCase, string(frequency.transform_key), "kHz_to_Hz");
verifyEqual(testCase, string(frequency.canonical_name), "contour_median_frequency");
verifyEqual(testCase, string(frequency.native_raw_token), "62.4");
verifyEqual(testCase, string(frequency.source_locator), ...
    "row=1; column=Principle Frequency (kHz)");

% DeepSqueak's own spelling is retained in the native dictionary even though the
% canonical name is standardized.
verifyTrue(testCase, ismember("Principle Frequency (kHz)", string(rows.native_name)));
verifyFalse(testCase, ismember("Principal Frequency (kHz)", string(rows.native_name)));

% Operational distinctness survives: two frequency measures sharing a broad
% concept keep separate canonical features and separate comparability metadata.
peak = rowFor(rows, "Peak Freq (kHz)");
verifyEqual(testCase, string(peak.canonical_name), "peak_frequency");
verifyNotEqual(testCase, string(peak.canonical_name), string(frequency.canonical_name));

comparability = fetch(fixture.conn, ...
    "SELECT fm.mapping_type FROM event_measurements em " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "WHERE d.native_event_id = '1' AND xf.native_name = 'Principle Frequency (kHz)'");
verifyEqual(testCase, string(comparability.mapping_type(1)), "comparable");

clear cleanup
end

function testMissingMeasurementKeepsExplicitMissingness(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());

% Call 2 has a blank Tonality cell. The detection must survive, and the missing
% measurement must be recorded as explicitly missing rather than as a fabricated
% zero or a silently absent row.
rows = fetch(fixture.conn, ...
    "SELECT em.native_value_type, " + ...
    "IFNULL(em.native_raw_token,'<null>') AS native_raw_token, " + ...
    "IFNULL(em.native_value_real, 1e308) AS native_value_real, " + ...
    "IFNULL(em.canonical_value_real, 1e308) AS canonical_value_real, " + ...
    "IFNULL(em.native_unit,'') AS native_unit " + ...
    "FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "WHERE d.native_event_id = '2' AND xf.native_name = 'Tonality'");
verifyEqual(testCase, height(rows), 1);
verifyEqual(testCase, string(rows.native_value_type(1)), "missing");
verifyEqual(testCase, double(rows.native_value_real(1)), 1e308);
verifyEqual(testCase, double(rows.canonical_value_real(1)), 1e308);

% The feature's unit is still known even though the value is not.
verifyEqual(testCase, string(rows.native_unit(1)), "ratio");

% The call itself is complete: 14 measurements, one of them missing.
counts = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "WHERE d.native_event_id = '2'");
verifyEqual(testCase, double(counts.n(1)), 14);

clear cleanup
end

function testAcceptedBecomesCurationEvidenceNotTruth(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());

rows = fetch(fixture.conn, ...
    "SELECT d.native_event_id, ce.action_type, ce.status_after, ce.actor_type, " + ...
    "IFNULL(ce.actor_label,'') AS actor_label, IFNULL(ce.details_json,'') AS details_json " + ...
    "FROM curation_events ce " + ...
    "JOIN detections d ON d.detection_id = ce.detection_id " + ...
    "ORDER BY CAST(d.native_event_id AS INTEGER)");
verifyEqual(testCase, height(rows), 3);

% The profile's declared value map supplies the canonical vocabulary; the raw
% native token is retained beside it.
verifyEqual(testCase, string(rows.status_after), ["accepted"; "accepted"; "rejected"]);
verifyEqual(testCase, unique(string(rows.actor_type)), "extractor");
verifyEqual(testCase, unique(string(rows.actor_label)), "DeepSqueak Accepted column");
verifyTrue(testCase, contains(string(rows.details_json(1)), "native_raw_token"));

% A rejected call is still imported as a detection: review state is evidence
% about the extractor, not a filter on what exists.
rejected = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM detections WHERE native_event_id = '3'");
verifyEqual(testCase, double(rejected.n(1)), 1);

% Accept state never reaches consensus, match, or manual-review tables.
for name = ["consensus_events", "manual_reviews", "agreement_statistics"]
    verifyEqual(testCase, countOf(fixture.conn, name), 0);
end

clear cleanup
end

function testScoreIsStoredUnderItsDeclaredSemantics(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());

% The profile declares Score at event_measurement level with semantic role
% detector_model_score, so it is both an indexed detection column and a
% first-class measurement carrying its own dictionary entry.
detection = fetch(fixture.conn, ...
    "SELECT detection_score FROM detections WHERE native_event_id = '1'");
verifyEqual(testCase, double(detection.detection_score(1)), 0.9134, AbsTol=1e-9);

measurement = fetch(fixture.conn, ...
    "SELECT em.native_value_real, IFNULL(em.native_unit,'<null>') AS native_unit, " + ...
    "IFNULL(cf.canonical_name,'') AS canonical_name, " + ...
    "IFNULL(xf.equivalence_class,'') AS equivalence_class, fm.mapping_type " + ...
    "FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "LEFT JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = em.extractor_feature_id " + ...
    "WHERE d.native_event_id = '1' AND xf.native_name = 'Score'");
verifyEqual(testCase, height(measurement), 1);
verifyEqual(testCase, double(measurement.native_value_real(1)), 0.9134, AbsTol=1e-9);
verifyEqual(testCase, string(measurement.canonical_name(1)), "native_detection_score");
verifyEqual(testCase, string(measurement.equivalence_class(1)), ...
    "detector_confidence_like_quantity");

% A model score is not cross-extractor comparable by default, and the seeded
% dictionary says so rather than the importer assuming it.
verifyEqual(testCase, string(measurement.mapping_type(1)), "noncomparable");
verifyEqual(testCase, string(measurement.native_unit(1)), "<null>");

% The score is not mistaken for a classification score.
assignments = fetch(fixture.conn, ...
    "SELECT IFNULL(score_or_distance, 1e308) AS score FROM classification_assignments");
verifyTrue(testCase, all(double(assignments.score) == 1e308));

clear cleanup
end

function testLabelIsPreservedWithoutBiologicalInterpretation(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = apply(fixture, defaultRunSpec());

verifyTrue(testCase, result.classification.present);
verifyEqual(testCase, result.classification.canonical_interpretation, "none");

% A DeepSqueak label may be manual, supervised, or clustering-derived and the
% export does not say which, so the run records that its provenance is
% unspecified rather than claiming a method.
runs = fetch(fixture.conn, ...
    "SELECT method, IFNULL(model_artifact_id,-1) AS model_artifact_id, " + ...
    "IFNULL(settings_profile_version_id,-1) AS settings_id, number_of_classes " + ...
    "FROM classification_runs");
verifyEqual(testCase, height(runs), 1);
verifyEqual(testCase, string(runs.method(1)), "native_label_unspecified_provenance");
verifyEqual(testCase, double(runs.model_artifact_id(1)), -1);
verifyEqual(testCase, double(runs.settings_id(1)), -1);
verifyEqual(testCase, double(runs.number_of_classes(1)), 3);

% Native class identity is preserved exactly; no canonical biological label is
% assigned to it.
classes = fetch(fixture.conn, ...
    "SELECT native_class_id, native_class_label, " + ...
    "IFNULL(canonical_class_label,'<none>') AS canonical_class_label " + ...
    "FROM classification_classes ORDER BY native_class_id");
verifyEqual(testCase, string(classes.native_class_label), ["22kHz-Call"; "Noise"; "USV"]);
verifyEqual(testCase, unique(string(classes.canonical_class_label)), "<none>");

assignments = fetch(fixture.conn, ...
    "SELECT d.native_event_id, cc.native_class_label, ca.assignment_source " + ...
    "FROM classification_assignments ca " + ...
    "JOIN detections d ON d.detection_id = ca.detection_id " + ...
    "JOIN classification_classes cc ON cc.classification_class_id = ca.classification_class_id " + ...
    "ORDER BY CAST(d.native_event_id AS INTEGER)");
verifyEqual(testCase, string(assignments.native_class_label), ...
    ["22kHz-Call"; "USV"; "Noise"]);
verifyEqual(testCase, unique(string(assignments.assignment_source)), "extractor");

% A caller who does know the labelling method can say so instead.
declared = defaultRunSpec();
declared.run_key = "ds-run-supervised";
declared.classification = struct(method="supervised_classifier", ...
    run_label="Lab supervised classifier v3");
declaredResult = apply(fixture, declared);
verifyEqual(testCase, declaredResult.classification.method, "supervised_classifier");

clear cleanup
end

function testDetectionIdentityIgnoresRowOrder(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());

% The same calls exported in a different row order are the same population.
% Row position is provenance, never biological identity.
reorderedRoot = fullfile(fixture.scratch, "reordered");
reorderedPath = fullfile(reorderedRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(reorderedPath);
cells = nominalExport();
writeExport(reorderedPath, [cells(1, :); cells([4, 2, 3], :)]);

reordered = vawlume.ingest.deepsqueak(fixture.conn, reorderedPath, ...
    portableRef(), defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=reorderedRoot);

% Reordering changes the workbook bytes, so the artifact and run identity guard
% reports the content change. What matters here is that no detection is
% duplicated and the detection plan still recognises all three calls.
verifyEqual(testCase, height(reordered.events), 3);
verifyEqual(testCase, sort(string(reordered.events.native_event_id)), ["1"; "2"; "3"]);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 3);

clear cleanup
end

function testTwoRunsOverOneRecordingReuseNativeCallIds(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

first = apply(fixture, defaultRunSpec());
second = defaultRunSpec();
second.run_key = "ds-run-2";
secondResult = apply(fixture, second);

verifyNotEqual(testCase, secondResult.extraction_run.extraction_run_id, ...
    first.extraction_run.extraction_run_id);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 6);
verifyEqual(testCase, countOf(fixture.conn, "event_measurements"), 84);

% The same native call identifiers coexist because detections are scoped to
% their extraction run.
rows = fetch(fixture.conn, ...
    "SELECT extraction_run_key, native_event_id FROM v_detection_core " + ...
    "ORDER BY extraction_run_key, CAST(native_event_id AS INTEGER)");
verifyEqual(testCase, string(rows.native_event_id), ...
    ["1"; "2"; "3"; "1"; "2"; "3"]);
verifyEqual(testCase, unique(string(rows.extraction_run_key)), ...
    ["ds-run-1"; "ds-run-2"]);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testDuplicateCallIdWithinOneRunIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% The profile declares native_event_id_uniqueness at error severity, so a
% repeated identifier inside one artifact is refused before anything is written.
duplicatePath = writeVariant(fixture, "duplicate", duplicateIdExport());
verifyError(testCase, ...
    @() applyPath(fixture, duplicatePath, "duplicate", defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

% A call with no identifier at all is refused for the same reason: an
% identifier is never fabricated from row order.
missingPath = writeVariant(fixture, "missingid", missingIdExport());
verifyError(testCase, ...
    @() applyPath(fixture, missingPath, "missingid", defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

clear cleanup
end

function testTimingViolationsFollowProfileSeverity(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% event_time_order is declared at error severity, so an end before its start
% blocks the import entirely rather than aborting on a schema CHECK mid-write.
reversedPath = writeVariant(fixture, "reversed", reversedTimeExport());
verifyError(testCase, ...
    @() applyPath(fixture, reversedPath, "reversed", defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakEventValidationFailed");
verifyEqual(testCase, tableCounts(fixture.conn), before);

% duration_consistency is declared at warning severity, so a disagreeing
% duration is reported and imported. Neither timing field is repaired from the
% other: the extractor's own measurements are preserved as exported.
inconsistentPath = writeVariant(fixture, "duration", inconsistentDurationExport());
result = applyPath(fixture, inconsistentPath, "duration", defaultRunSpec());
verifyTrue(testCase, result.committed);
verifyTrue(testCase, any(contains(result.validation.warnings, "duration_consistency")));

stored = fetch(fixture.conn, ...
    "SELECT d.start_time_s, d.end_time_s, em.native_value_real AS duration " + ...
    "FROM detections d " + ...
    "JOIN event_measurements em ON em.detection_id = d.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "WHERE d.native_event_id = '1' AND xf.native_name = 'Call Length (s)'");
verifyEqual(testCase, double(stored.start_time_s(1)), 10.0);
verifyEqual(testCase, double(stored.end_time_s(1)), 10.05);
verifyEqual(testCase, double(stored.duration(1)), 0.09);

clear cleanup
end

function testCompatibleRerunDoesNotDuplicateScientificRows(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

apply(fixture, defaultRunSpec());
after = tableCounts(fixture.conn);
second = apply(fixture, defaultRunSpec());

verifyTrue(testCase, second.committed);
verifyEqual(testCase, tableCounts(fixture.conn), after);
verifyEqual(testCase, second.applied_counts.detections, 0);
verifyEqual(testCase, second.applied_counts.event_measurements, 0);
verifyEqual(testCase, second.applied_counts.curation_events, 0);
verifyEqual(testCase, second.applied_counts.classification_assignments, 0);
verifyEqual(testCase, second.detections.detections_reuse, 3);
verifyEqual(testCase, second.detections.measurements_reuse, 42);
verifyEqual(testCase, second.detections.curation_reuse, 3);
verifyEqual(testCase, second.detections.classification_assignments_reuse, 3);

clear cleanup
end

function testChangedEvidenceIsConflictNotSilentUpdate(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());

% Simulate a stored scientific row that no longer agrees with the artifact it
% came from. Re-importing the same run must surface that as a conflict rather
% than quietly rewriting the stored measurement.
execute(fixture.conn, ...
    "UPDATE detections SET start_time_s = 10.02 WHERE native_event_id = '1'");
execute(fixture.conn, ...
    "UPDATE event_measurements SET native_value_real = 99.9 " + ...
    "WHERE extractor_feature_id = (SELECT extractor_feature_id FROM extractor_features " + ...
    "WHERE native_name = 'Tonality') AND detection_id = " + ...
    "(SELECT detection_id FROM detections WHERE native_event_id = '3')");

conflicted = plan(fixture, defaultRunSpec());
verifyEqual(testCase, conflicted.status, "conflict");
verifyTrue(testCase, any(contains(conflicted.conflicts, "existing timing differs")));
verifyTrue(testCase, any(contains(conflicted.conflicts, "stored value differs")));
verifyEqual(testCase, conflicted.detections.detections_conflict, 1);
verifyEqual(testCase, conflicted.detections.measurements_conflict, 1);

% Requesting apply returns the conflict and changes nothing.
attempted = apply(fixture, defaultRunSpec());
verifyEqual(testCase, attempted.status, "conflict");
verifyFalse(testCase, attempted.committed);
stored = fetch(fixture.conn, ...
    "SELECT start_time_s FROM detections WHERE native_event_id = '1'");
verifyEqual(testCase, double(stored.start_time_s(1)), 10.02);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 3);

clear cleanup
end

function testLateFailureRollsBackTheWholeEventPopulation(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% Fail on the last table the importer writes, after the run, its artifacts, the
% detections, and their measurements have all been inserted in this transaction.
% Nothing may survive, so no extraction run is left without its calls.
verifyError(testCase, @() applyWithInducedFailure(fixture), ...
    "vawlume:ingest:InducedApplyFailure");

verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 0);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 0);
verifyEqual(testCase, countOf(fixture.conn, "event_measurements"), 0);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

% The connection remains usable and a later import succeeds completely.
recovered = apply(fixture, defaultRunSpec());
verifyTrue(testCase, recovered.committed);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 3);

clear cleanup
end

function testEventReadBacksAnswerTheRequiredQuestions(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
apply(fixture, defaultRunSpec());
second = defaultRunSpec();
second.run_key = "ds-run-2";
apply(fixture, second);

% Q1-Q5: detection to run and recording, native call id, source artifact,
% timing, and canonical geometry, all from the shipped view.
core = fetch(fixture.conn, ...
    "SELECT project_key, native_recording_id, extractor_name, extraction_run_key, " + ...
    "native_event_id, start_time_s, end_time_s, duration_s, detection_score " + ...
    "FROM v_detection_core WHERE extraction_run_key = 'ds-run-1' " + ...
    "ORDER BY CAST(native_event_id AS INTEGER)");
verifyEqual(testCase, height(core), 3);
verifyEqual(testCase, unique(string(core.native_recording_id)), "REC_A");
verifyEqual(testCase, unique(string(core.extractor_name)), "DeepSqueak");
verifyEqual(testCase, core.duration_s, [0.05; 0.04; 0.1], AbsTol=1e-9);

artifacts = fetch(fixture.conn, ...
    "SELECT a.path_or_uri, a.artifact_type FROM detections d " + ...
    "JOIN artifacts a ON a.artifact_id = d.source_artifact_id " + ...
    "WHERE d.native_event_id = '1' AND d.extraction_run_id = " + ...
    "(SELECT extraction_run_id FROM extraction_runs WHERE run_key = 'ds-run-1')");
verifyEqual(testCase, string(artifacts.path_or_uri(1)), "exports/REC_A_Stats.xlsx");
verifyEqual(testCase, string(artifacts.artifact_type(1)), "extractor_event_export");

% Q6-Q7: measurement to native field, unit, raw value, transform, and
% operational definition, through the shipped long view.
long = fetch(fixture.conn, ...
    "SELECT native_name, IFNULL(canonical_name,'') AS canonical_name, " + ...
    "IFNULL(native_unit,'') AS native_unit, IFNULL(canonical_unit,'') AS canonical_unit " + ...
    "FROM v_event_measurements_long WHERE native_name = 'Low Freq (kHz)' LIMIT 1");
verifyEqual(testCase, string(long.canonical_name(1)), "frequency_min");
verifyEqual(testCase, string(long.native_unit(1)), "kHz");
verifyEqual(testCase, string(long.canonical_unit(1)), "Hz");

definition = fetch(fixture.conn, ...
    "SELECT IFNULL(xf.native_definition,'') AS native_definition, " + ...
    "IFNULL(fm.transform_key,'') AS transform_key " + ...
    "FROM extractor_features xf " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "WHERE xf.native_name = 'Low Freq (kHz)'");
verifyEqual(testCase, string(definition.native_definition(1)), "lowest contour frequency");
verifyEqual(testCase, string(definition.transform_key(1)), "kHz_to_Hz");

% Q8-Q10: review state, score semantics, and label assignment.
review = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM curation_events ce " + ...
    "JOIN detections d ON d.detection_id = ce.detection_id " + ...
    "WHERE ce.status_after = 'rejected'");
verifyEqual(testCase, double(review.n(1)), 2);

labels = fetch(fixture.conn, ...
    "SELECT COUNT(DISTINCT cc.native_class_label) AS n FROM classification_assignments ca " + ...
    "JOIN classification_classes cc ON cc.classification_class_id = ca.classification_class_id");
verifyEqual(testCase, double(labels.n(1)), 3);

% Q11: one recording, several independent DeepSqueak runs, each with its own
% call population.
perRun = fetch(fixture.conn, ...
    "SELECT er.run_key, COUNT(d.detection_id) AS detection_count " + ...
    "FROM extraction_runs er " + ...
    "JOIN detections d ON d.extraction_run_id = er.extraction_run_id " + ...
    "JOIN extraction_run_inputs eri ON eri.extraction_run_id = er.extraction_run_id " + ...
    "WHERE eri.recording_id = " + string(fixture.recording_a) + ...
    " GROUP BY er.run_key ORDER BY er.run_key");
verifyEqual(testCase, string(perRun.run_key), ["ds-run-1"; "ds-run-2"]);
verifyEqual(testCase, double(perRun.detection_count), [3; 3]);

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));

scratch = string(tempname);
mkdir(scratch);
dbFile = fullfile(scratch, "deepsqueak_events.sqlite");
copyfile(seededTemplateDatabase(repoRoot), dbFile);
conn = sqlite(char(dbFile));

cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
seedProjectGraph(conn);

artifactRoot = fullfile(scratch, "deepsqueak");
exportPath = fullfile(artifactRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(exportPath);
writeExport(exportPath, nominalExport());

fixture = struct();
fixture.conn = conn;
fixture.repo_root = repoRoot;
fixture.scratch = scratch;
fixture.artifact_root = artifactRoot;
fixture.export_a = exportPath;
fixture.recording_a = 1;
end

function path = seededTemplateDatabase(repoRoot)
persistent templatePath
if ~isempty(templatePath) && isfile(templatePath)
    path = templatePath;
    return
end
templatePath = string(tempname) + ".sqlite";
conn = sqlite(char(templatePath), "create");
cleaner = onCleanup(@() close(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
delete(cleaner);
path = templatePath;
end

function tearDown(conn, scratch, repoRoot)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function seedProjectGraph(conn)
execute(conn, "INSERT INTO projects(project_key, project_name) VALUES('proj-a','Project A')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, relative_path, filename) " + ...
    "VALUES(1,'recording_audio','audio/day1/REC_A.wav','audio/day1/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, native_recording_id) VALUES(1,1,'REC_A')");
end

function spec = defaultRunSpec()
spec = struct(run_key="ds-run-1", extractor_version="3.2.1", ...
    run_label="DeepSqueak detection run 1");
end

function ref = portableRef()
ref = struct(project_key="proj-a", source_relative_path="audio/day1/REC_A.wav");
end

function result = plan(fixture, runSpec)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_a, ...
    portableRef(), runSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root);
end

function result = apply(fixture, runSpec)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_a, ...
    portableRef(), runSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root, Apply=true);
end

function result = applyPath(fixture, exportPath, variant, runSpec)
result = vawlume.ingest.deepsqueak(fixture.conn, exportPath, portableRef(), ...
    runSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fullfile(fixture.scratch, variant), Apply=true);
end

function path = writeVariant(fixture, variant, cells)
path = fullfile(fixture.scratch, variant, "exports", "REC_A_Stats.xlsx");
makeParentFolder(path);
writeExport(path, cells);
end

function applyWithInducedFailure(fixture)
% classification_assignments is the last table the importer writes, so aborting
% there proves the whole Phase 4 scientific graph rolls back together.
execute(fixture.conn, ...
    "CREATE TRIGGER trg_induced_event_failure " + ...
    "BEFORE INSERT ON classification_assignments FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced event failure'); END");
restore = onCleanup(@() dropTrigger(fixture.conn));
try
    apply(fixture, defaultRunSpec());
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
    execute(conn, "DROP TRIGGER IF EXISTS trg_induced_event_failure");
catch
end
end

function headers = nominalHeaders()
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
end

function cells = nominalExport()
% Three synthetic calls: two accepted and one rejected, three distinct labels,
% distinct native identifiers, and one blank optional measurement.
detectionFile = 'C:\deepsqueak\detections\REC_A_deepsqueak.mat';
cells = [
    nominalHeaders()
    {detectionFile, 1, '22kHz-Call', 1, 0.9134, 10.000, 10.050, 0.050, ...
        62.4, 45.1, 80.2, 35.1, 3.2, -120.5, 1.12, -71.4, 0.78, 63.0}
    {detectionFile, 2, 'USV', 1, 0.8021, 20.000, 20.040, 0.040, ...
        61.0, 50.0, 72.0, 22.0, 2.1, 15.0, 1.05, -70.1, [], 61.5}
    {detectionFile, 3, 'Noise', 0, 0.2107, 40.000, 40.100, 0.100, ...
        63.5, 42.0, 84.0, 42.0, 4.4, -8.25, 1.40, -69.3, 0.69, 64.2}
];
end

function cells = duplicateIdExport()
cells = nominalExport();
cells{3, 2} = 1;
end

function cells = missingIdExport()
cells = nominalExport();
cells{2, 2} = [];
end

function cells = reversedTimeExport()
cells = nominalExport();
cells{2, 7} = 9.5;
end

function cells = inconsistentDurationExport()
% Call Length disagrees with End Time minus Begin Time by 0.04 s.
cells = nominalExport();
cells{2, 8} = 0.09;
end

function writeExport(path, cells)
if isfile(path)
    delete(path);
end
writecell(cells, path);
end

function row = rowFor(rows, nativeName)
matches = string(rows.native_name) == nativeName;
assert(nnz(matches) == 1, "Expected one row for %s, found %d.", ...
    nativeName, nnz(matches));
row = table2struct(rows(matches, :));
end

function counts = tableCounts(conn)
tables = ["projects", "source_files", "recordings", "artifacts", ...
    "extraction_runs", "extraction_run_inputs", "extraction_run_artifacts", ...
    "detections", "event_measurements", "curation_events", ...
    "classification_runs", "classification_classes", "classification_assignments"];
counts = struct();
for name = tables
    counts.(name) = countOf(conn, name);
end
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function makeParentFolder(path)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
