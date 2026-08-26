function tests = test_phase1_fixture
tests = functiontests({ ...
    @testCreatePhase1FixtureDatabasePopulatesRequiredShape, ...
    @testPhase1FixtureRebuildsStably, ...
    @testPhase1FixtureRejectsProtectedIntegrityViolations});
end

function testCreatePhase1FixtureDatabasePopulatesRequiredShape(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile, summary] = createFixtureDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

verifyEqual(testCase, summary.project_key, "phase1_synthetic_fixture");
verifyEqual(testCase, summary.foreign_key_violation_count, 0);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);
verifyCoreCounts(testCase, summary.counts);
verifyExperimentalShape(testCase, conn);
verifyProfilesAndRuns(testCase, conn);
verifyDetectionsAndMeasurements(testCase, conn);
verifyReviewAndMatching(testCase, conn);
verifyExternalAlignment(testCase, conn);

clear cleanupPath cleanupDb summary
end

function testPhase1FixtureRebuildsStably(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[connA, dbFileA, summaryA] = createFixtureDatabase(repoRoot);
cleanupDbA = onCleanup(@() cleanupDatabase(connA, dbFileA));

[connB, dbFileB, summaryB] = createFixtureDatabase(repoRoot);
cleanupDbB = onCleanup(@() cleanupDatabase(connB, dbFileB));

verifyEqual(testCase, summaryA.counts, summaryB.counts);
verifyEqual(testCase, summaryA.stability_signature, summaryB.stability_signature);

clear cleanupPath cleanupDbA cleanupDbB summaryA summaryB
end

function testPhase1FixtureRejectsProtectedIntegrityViolations(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createFixtureDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ids = fixtureIds(conn);
countsBefore = protectedCounts(conn);

verifySqlFails(testCase, conn, ...
    "INSERT INTO detections(extraction_run_id, recording_id, native_event_id, start_time_s, end_time_s) " + ...
    "VALUES (" + string(ids.dsSocialRun) + ", " + string(ids.socialRecording) + ", 'BAD_TIME', 1.000, 0.500)");

verifySqlFails(testCase, conn, ...
    "INSERT INTO detections(extraction_run_id, recording_id, native_event_id, start_time_s, end_time_s) " + ...
    "VALUES (" + string(ids.dsSocialRun) + ", " + string(ids.baselineRecording) + ", 'BAD_RUN_INPUT', 1.000, 1.100)");

[sameRunA, sameRunB] = orderedPair(ids.dsSocial1, ids.dsSocial2);
verifySqlFails(testCase, conn, candidateInsertSql(ids.matchingAnalysis, ids.socialRecording, sameRunA, sameRunB, "same_run"));

[crossRecordingA, crossRecordingB] = orderedPair(ids.dsSocial1, ids.dsBaseline1);
verifySqlFails(testCase, conn, candidateInsertSql(ids.matchingAnalysis, ids.socialRecording, crossRecordingA, crossRecordingB, "cross_recording"));

verifySqlFails(testCase, conn, ...
    "INSERT INTO feature_relationships(feature_a_id, feature_b_id, relationship_type) " + ...
    "VALUES (" + string(ids.maxFeature) + ", " + string(ids.minFeature) + ", 'comparable')");

existingRelationship = fetch(conn, ...
    "SELECT feature_a_id, feature_b_id FROM feature_relationships ORDER BY feature_relationship_id LIMIT 1");
verifySqlFails(testCase, conn, ...
    "INSERT INTO feature_relationships(feature_a_id, feature_b_id, relationship_type) " + ...
    "VALUES (" + string(existingRelationship.feature_a_id(1)) + ", " + ...
    string(existingRelationship.feature_b_id(1)) + ", 'comparable')");

verifyEqual(testCase, protectedCounts(conn), countsBefore);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupPath cleanupDb
end

function verifyCoreCounts(testCase, counts)
verifyEqual(testCase, counts.projects, 1);
verifyEqual(testCase, counts.example_profile_versions, 2);
verifyEqual(testCase, counts.source_files, 3);
verifyEqual(testCase, counts.entity_types, 5);
verifyEqual(testCase, counts.experimental_entities, 8);
verifyEqual(testCase, counts.entity_relationships, 9);
verifyEqual(testCase, counts.recordings, 2);
verifyEqual(testCase, counts.recording_channels, 2);
verifyEqual(testCase, counts.recording_entity_links, 6);
verifyEqual(testCase, counts.recording_profile_assignments, 4);
verifyEqual(testCase, counts.recording_epochs, 2);
verifyEqual(testCase, counts.artifacts, 5);
verifyEqual(testCase, counts.extraction_runs, 3);
verifyEqual(testCase, counts.extraction_run_inputs, 3);
verifyEqual(testCase, counts.extraction_run_profiles, 6);
verifyEqual(testCase, counts.extraction_run_artifacts, 5);
verifyEqual(testCase, counts.extractor_objects, 7);
verifyEqual(testCase, counts.extractor_object_recordings, 7);
verifyEqual(testCase, counts.detections, 8);
verifyEqual(testCase, counts.event_measurements, 80);
verifyEqual(testCase, counts.curation_events, 4);
verifyEqual(testCase, counts.analysis_runs, 2);
verifyEqual(testCase, counts.candidate_pairs, 3);
verifyEqual(testCase, counts.match_groups, 4);
verifyEqual(testCase, counts.match_group_members, 7);
verifyEqual(testCase, counts.consensus_events, 2);
verifyEqual(testCase, counts.consensus_event_members, 5);
verifyEqual(testCase, counts.manual_reviews, 3);
verifyEqual(testCase, counts.consilience_assessments, 3);
verifyEqual(testCase, counts.timebases, 2);
verifyEqual(testCase, counts.external_streams, 1);
verifyEqual(testCase, counts.external_events, 2);
verifyEqual(testCase, counts.time_alignment_runs, 1);
verifyEqual(testCase, counts.alignment_anchors, 2);
verifyEqual(testCase, counts.alignment_segments, 1);
verifyEqual(testCase, counts.aligned_external_events, 2);
end

function verifyExperimentalShape(testCase, conn)
project = sqlText("phase1_synthetic_fixture");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM experimental_entities ee " + ...
    "JOIN entity_types et ON et.entity_type_id = ee.entity_type_id " + ...
    "JOIN projects p ON p.project_id = ee.project_id " + ...
    "WHERE p.project_key = " + project + " AND et.native_name = 'subject'"), 3);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(DISTINCT er.role_label) AS n FROM entity_relationships er " + ...
    "JOIN experimental_entities parent ON parent.entity_id = er.parent_entity_id " + ...
    "WHERE parent.native_id = 'DYAD_01' AND er.relationship_type = 'member' " + ...
    "AND er.role_label IN ('male', 'female')"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_recording_entity_context " + ...
    "WHERE project_key = " + project + " AND native_recording_id = 'REC_SOCIAL_DYAD_01' " + ...
    "AND entity_type = 'subject' AND role_label IN ('male', 'female')"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_recording_entity_context " + ...
    "WHERE project_key = " + project + " AND native_recording_id = 'REC_BASELINE_M01' " + ...
    "AND entity_type = 'subject'"), 1);
end

function verifyProfilesAndRuns(testCase, conn)
project = sqlText("phase1_synthetic_fixture");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM config_profile_versions cpv " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE cp.profile_key IN ('example.device.ultrasonic_usb_primary', 'example.setup.mouse_courtship_chamber') " + ...
    "AND LENGTH(IFNULL(cpv.checksum_sha256, '')) = 64"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(DISTINCT extractor_name) AS n FROM v_detection_core " + ...
    "WHERE project_key = " + project + " AND native_recording_id = 'REC_SOCIAL_DYAD_01'"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(DISTINCT extraction_run_key) AS n FROM v_detection_core " + ...
    "WHERE project_key = " + project + " AND native_recording_id = 'REC_BASELINE_M01'"), 1);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extraction_run_profiles erp " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = erp.extraction_run_id " + ...
    "JOIN projects p ON p.project_id = er.project_id " + ...
    "WHERE p.project_key = " + project), 6);
end

function verifyDetectionsAndMeasurements(testCase, conn)
project = sqlText("phase1_synthetic_fixture");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_detection_core WHERE project_key = " + project + ...
    " AND native_recording_id = 'REC_SOCIAL_DYAD_01'"), 7);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_detection_core WHERE project_key = " + project + ...
    " AND native_event_id = '1'"), 3);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_event_measurements_long vml " + ...
    "JOIN v_detection_core vc ON vc.detection_id = vml.detection_id " + ...
    "WHERE vc.project_key = " + project + " AND vml.transform_key = 'kHz_to_Hz' " + ...
    "AND vml.native_unit = 'kHz' AND vml.canonical_unit = 'Hz' " + ...
    "AND ABS(vml.canonical_value_real - (vml.native_value_real * 1000)) < 1e-9"), 32);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_event_measurements_long vml " + ...
    "JOIN v_detection_core vc ON vc.detection_id = vml.detection_id " + ...
    "WHERE vc.project_key = " + project + " AND vml.transform_key = 'ms_to_s' " + ...
    "AND vml.native_unit = 'ms' AND vml.canonical_unit = 's' " + ...
    "AND ABS(vml.canonical_value_real - (vml.native_value_real / 1000)) < 1e-9"), 4);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM event_measurements em " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "WHERE cf.canonical_name = 'inter_call_interval' AND em.native_value_type = 'missing' " + ...
    "AND em.native_raw_token = 'NA' AND em.canonical_value_real IS NULL"), 1);
verifyGreaterThanOrEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_event_measurements_long vml " + ...
    "JOIN v_detection_core vc ON vc.detection_id = vml.detection_id " + ...
    "WHERE vc.project_key = " + project + ...
    " AND vml.canonical_name IN ('native_detection_score', 'contour_sinuosity', 'tonality')"), 4);
end

function verifyReviewAndMatching(testCase, conn)
project = sqlText("phase1_synthetic_fixture");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM curation_events ce " + ...
    "JOIN manual_reviews mr ON mr.detection_id = ce.detection_id " + ...
    "JOIN detections d ON d.detection_id = ce.detection_id " + ...
    "JOIN recordings r ON r.recording_id = d.recording_id " + ...
    "JOIN projects p ON p.project_id = r.project_id " + ...
    "WHERE p.project_key = " + project + " AND ce.status_after = 'Accepted' " + ...
    "AND ce.actor_type = 'extractor' AND mr.review_status = 'adjudicated_false_positive'"), 1);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "JOIN projects p ON p.project_id = ar.project_id WHERE p.project_key = " + project), 3);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM match_groups mg " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "JOIN projects p ON p.project_id = ar.project_id WHERE p.project_key = " + project + ...
    " AND mg.match_type = 'unmatched'"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM match_groups mg " + ...
    "JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "JOIN projects p ON p.project_id = ar.project_id WHERE p.project_key = " + project + ...
    " AND mg.match_type = 'one_to_many'"), 3);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM consensus_events ce " + ...
    "JOIN consensus_event_members cem ON cem.consensus_event_id = ce.consensus_event_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = ce.analysis_run_id " + ...
    "JOIN projects p ON p.project_id = ar.project_id WHERE p.project_key = " + project + ...
    " AND ce.derivation_method = 'union_boundary_split_merge'"), 3);
end

function verifyExternalAlignment(testCase, conn)
project = sqlText("phase1_synthetic_fixture");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_external_events_aligned vea " + ...
    "JOIN recordings r ON r.recording_id = vea.recording_id " + ...
    "JOIN projects p ON p.project_id = r.project_id WHERE p.project_key = " + project + ...
    " AND vea.start_time_aligned_s IS NOT NULL"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM v_external_events_aligned vea " + ...
    "JOIN recordings r ON r.recording_id = vea.recording_id " + ...
    "JOIN projects p ON p.project_id = r.project_id WHERE p.project_key = " + project + ...
    " AND ABS((vea.start_time_aligned_s - vea.start_time_native) - 0.55) < 1e-9"), 2);
end

function ids = fixtureIds(conn)
ids = struct();
ids.socialRecording = lookupId(conn, "SELECT recording_id AS id FROM recordings WHERE native_recording_id = 'REC_SOCIAL_DYAD_01'");
ids.baselineRecording = lookupId(conn, "SELECT recording_id AS id FROM recordings WHERE native_recording_id = 'REC_BASELINE_M01'");
ids.dsSocialRun = lookupId(conn, "SELECT extraction_run_id AS id FROM extraction_runs WHERE run_key = 'fixture_deepsqueak_social_v1'");
ids.matchingAnalysis = lookupId(conn, "SELECT analysis_run_id AS id FROM analysis_runs WHERE run_key = 'fixture_cross_extractor_matching_v1'");
ids.dsSocial1 = detectionId(conn, "fixture_deepsqueak_social_v1", "REC_SOCIAL_DYAD_01", "1");
ids.dsSocial2 = detectionId(conn, "fixture_deepsqueak_social_v1", "REC_SOCIAL_DYAD_01", "2");
ids.dsBaseline1 = detectionId(conn, "fixture_deepsqueak_baseline_v1", "REC_BASELINE_M01", "1");
ids.minFeature = lookupId(conn, "SELECT MIN(extractor_feature_id) AS id FROM extractor_features");
ids.maxFeature = lookupId(conn, "SELECT MAX(extractor_feature_id) AS id FROM extractor_features");
end

function id = detectionId(conn, runKey, recordingNativeId, nativeEventId)
id = lookupId(conn, ...
    "SELECT d.detection_id AS id FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "JOIN recordings r ON r.recording_id = d.recording_id " + ...
    "WHERE er.run_key = " + sqlText(runKey) + ...
    " AND r.native_recording_id = " + sqlText(recordingNativeId) + ...
    " AND d.native_event_id = " + sqlText(nativeEventId));
end

function sql = candidateInsertSql(analysisRunId, recordingId, detectionAId, detectionBId, status)
sql = ...
    "INSERT INTO candidate_pairs(analysis_run_id, recording_id, detection_a_id, detection_b_id, candidate_status) " + ...
    "VALUES (" + string(analysisRunId) + ", " + string(recordingId) + ", " + ...
    string(detectionAId) + ", " + string(detectionBId) + ", " + sqlText(status) + ")";
end

function counts = protectedCounts(conn)
counts = struct();
counts.detections = scalar(conn, "SELECT COUNT(*) AS n FROM detections");
counts.candidate_pairs = scalar(conn, "SELECT COUNT(*) AS n FROM candidate_pairs");
counts.feature_relationships = scalar(conn, "SELECT COUNT(*) AS n FROM feature_relationships");
end

function [left, right] = orderedPair(a, b)
left = min(a, b);
right = max(a, b);
end

function [conn, dbFile, summary] = createFixtureDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
[conn, databaseSummary] = vawlume.db.createPhase1FixtureDatabase(dbFile, repoRoot);
summary = databaseSummary.fixture;
end

function id = lookupId(conn, sql)
rows = fetch(conn, sql);
if height(rows) ~= 1
    error("vawlume:test:LookupFailed", "Expected one row for lookup, found %d. SQL: %s", height(rows), sql);
end
id = double(rows.id(1));
end

function value = scalar(conn, sql)
result = fetch(conn, sql);
value = double(result.n(1));
end

function verifySqlFails(testCase, conn, sql)
didFail = false;
try
    execute(conn, sql);
catch
    didFail = true;
end
verifyTrue(testCase, didFail, "Expected SQL statement to fail: " + sql);
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end

function cleanupDatabase(conn, dbFile)
if isopen(conn)
    close(conn);
end
deleteIfExists(dbFile);
deleteIfExists(dbFile + "-journal");
deleteIfExists(dbFile + "-wal");
deleteIfExists(dbFile + "-shm");
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
