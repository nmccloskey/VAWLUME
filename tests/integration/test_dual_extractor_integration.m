function tests = test_dual_extractor_integration
%TEST_DUAL_EXTRACTOR_INTEGRATION DeepSqueak and MUPET over one recording.
%
% Phase 4 proved VAWLUME can import DeepSqueak. This suite tests the stronger
% claim Phase 5 exists to establish: that two materially different extractor
% outputs reach one relational model through shared infrastructure without the
% system becoming a collection of special cases, and without either extractor's
% semantics being flattened into the other's.
%
% The event geometry deliberately overlaps. DeepSqueak call 1 and MUPET syllable
% 1 describe what a later phase may decide is the same vocalization; MUPET
% syllable 2 has no DeepSqueak counterpart; DeepSqueak call 3 spans two MUPET
% syllables. Those are fixture semantics for co-residence only. This pass
% creates no candidate pairs, no match groups, and no consensus events, and
% asserts that none appear.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------- shared recording ---

function testBothExtractorsImportOneRecordingAsSeparateRuns(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

deepSqueak = applyDeepSqueak(fixture, deepSqueakRunSpec());
mupet = applyMupet(fixture, mupetRunSpec(fixture));
verifyTrue(testCase, deepSqueak.committed);
verifyTrue(testCase, mupet.committed);

% One project, one recording, two runs.
verifyEqual(testCase, countOf(fixture.conn, "projects"), 1);
verifyEqual(testCase, countOf(fixture.conn, "recordings"), 1);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 2);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 7);
verifyEqual(testCase, countOf(fixture.conn, "event_measurements"), 90);

% Both runs analyse the same recording and keep separate extractor identity,
% version, output mapping profile, and artifacts.
runs = fetch(fixture.conn, ...
    "SELECT e.extractor_name, ev.version_label, er.run_key, cp.profile_key, " + ...
    "eri.recording_id, COUNT(DISTINCT d.detection_id) AS detections, " + ...
    "COUNT(DISTINCT era.artifact_id) AS artifacts " + ...
    "FROM extraction_runs er " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = er.output_mapping_profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "JOIN extraction_run_inputs eri ON eri.extraction_run_id = er.extraction_run_id " + ...
    "LEFT JOIN detections d ON d.extraction_run_id = er.extraction_run_id " + ...
    "LEFT JOIN extraction_run_artifacts era ON era.extraction_run_id = er.extraction_run_id " + ...
    "GROUP BY er.extraction_run_id ORDER BY e.extractor_name");
verifyEqual(testCase, height(runs), 2);
verifyEqual(testCase, string(runs.extractor_name), ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, string(runs.version_label), ["3.2.1"; "2.1"]);
verifyEqual(testCase, string(runs.profile_key), ...
    ["vawlume.deepsqueak.output.v3_2"; "vawlume.mupet.output.v2_1"]);
verifyEqual(testCase, double(runs.recording_id), [1; 1]);
verifyEqual(testCase, double(runs.detections), [3; 4]);
verifyEqual(testCase, double(runs.artifacts), [1; 2]);

% No artifact is shared between the two runs.
shared = fetch(fixture.conn, ...
    "SELECT artifact_id, COUNT(DISTINCT extraction_run_id) AS runs " + ...
    "FROM extraction_run_artifacts GROUP BY artifact_id HAVING runs > 1");
verifyEqual(testCase, height(shared), 0);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testNativeIdentifiersOverlapWithoutCollision(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

% DeepSqueak call 1 and MUPET syllable 1 both exist on this recording. Native
% event identity is scoped by extraction run, so there is nothing to collide.
overlapping = fetch(fixture.conn, ...
    "SELECT extractor_name, extraction_run_key, start_time_s, end_time_s " + ...
    "FROM v_detection_core WHERE native_event_id = '1' ORDER BY extractor_name");
verifyEqual(testCase, height(overlapping), 2);
verifyEqual(testCase, string(overlapping.extractor_name), ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, double(overlapping.start_time_s), [10.000; 10.004], AbsTol=1e-9);

% A second MUPET run over the same recording repeats the same ordinals legally.
second = mupetRunSpec(fixture);
second.run_key = "mupet-run-2";
result = applyMupet(fixture, second);
verifyTrue(testCase, result.committed);
repeated = fetch(fixture.conn, ...
    "SELECT extraction_run_key FROM v_detection_core " + ...
    "WHERE extractor_name = 'MUPET' AND native_event_id = '1' " + ...
    "ORDER BY extraction_run_key");
verifyEqual(testCase, string(repeated.extraction_run_key), ["mupet-run-1"; "mupet-run-2"]);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 11);

clear cleanup
end

% ---------------------------------------------- co-residence of concepts ----

function testCanonicalConceptsAreJointlyQueryableWithoutErasingMethod(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

% Six broad concepts are reachable for both extractors by canonical name, in
% one query across both populations, through the shipped views.
concepts = ["call_start_time", "call_end_time", "call_duration", ...
    "frequency_min", "frequency_max", "frequency_bandwidth"];
rows = fetch(fixture.conn, ...
    "SELECT c.extractor_name, m.canonical_name, m.native_name, " + ...
    "m.native_unit, m.canonical_unit, m.transform_key " + ...
    "FROM v_event_measurements_long m " + ...
    "JOIN v_detection_core c ON c.detection_id = m.detection_id " + ...
    "WHERE m.canonical_name IN ('" + strjoin(concepts, "','") + "') " + ...
    "GROUP BY c.extractor_name, m.canonical_name " + ...
    "ORDER BY m.canonical_name, c.extractor_name");
verifyEqual(testCase, height(rows), 2 * numel(concepts));
for concept = concepts
    present = string(rows.extractor_name(string(rows.canonical_name) == concept));
    verifyEqual(testCase, sort(present), ["DeepSqueak"; "MUPET"], concept);
end

% Discoverability never costs method. Each row still names the extractor, its
% native field, its native unit, and the transform that produced the canonical
% value, and no two extractors contribute the same native field name.
verifyFalse(testCase, any(strlength(string(rows.native_name)) == 0));
verifyFalse(testCase, any(strlength(string(rows.transform_key)) == 0));
verifyEqual(testCase, numel(unique(string(rows.native_name))), height(rows));

% Canonical units agree even though native units do not, which is what makes
% the concepts comparable at all without making the measurements identical.
bandwidth = rows(string(rows.canonical_name) == "frequency_bandwidth", :);
verifyEqual(testCase, unique(string(bandwidth.canonical_unit)), "Hz");
verifyEqual(testCase, sort(string(bandwidth.native_name)), ...
    ["Delta Freq (kHz)"; "frequency bandwidth (kHz)"]);

% Central frequency is the deliberate exception, and it is the clearest
% illustration of the whole pass. DeepSqueak's contour median is NOT registered
% under the generic frequency_center canonical name, because calling it that
% would assert it is the same statistic as MUPET's filterbank mean. Only MUPET
% populates frequency_center by canonical name.
centreByName = fetch(fixture.conn, ...
    "SELECT DISTINCT c.extractor_name FROM v_event_measurements_long m " + ...
    "JOIN v_detection_core c ON c.detection_id = m.detection_id " + ...
    "WHERE m.canonical_name = 'frequency_center'");
verifyEqual(testCase, string(centreByName.extractor_name), "MUPET");

% The cross-extractor bridge for that concept is the shared equivalence class,
% which both native features carry, plus the seeded relationship between them.
% A matching phase must join there rather than on canonical name.
centreByClass = fetch(fixture.conn, ...
    "SELECT DISTINCT e.extractor_name, xf.native_name, " + ...
    "IFNULL(cf.canonical_name,'') AS canonical_name " + ...
    "FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "LEFT JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "LEFT JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE xf.equivalence_class = 'vocalization_frequency_center' " + ...
    "ORDER BY e.extractor_name");
verifyEqual(testCase, string(centreByClass.extractor_name), ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, string(centreByClass.canonical_name), ...
    ["contour_median_frequency"; "frequency_center"]);

% The profile's broader-concept declaration is not lost; it is preserved as
% registered feature provenance rather than as a joinable column.
broader = fetch(fixture.conn, ...
    "SELECT IFNULL(notes,'') AS notes FROM extractor_features " + ...
    "WHERE native_name = 'Principle Frequency (kHz)'");
verifyTrue(testCase, contains(string(broader.notes(1)), ...
    "broader_canonical_concept=frequency_center"));

clear cleanup
end

function testStructuralEquivalenceIsNotMetricIdentity(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

% Stress case 1 - duration. Both extractors address call_duration, but through
% different native features with different derivation stages, and MUPET keeps
% an operational variant DeepSqueak has no counterpart for.
duration = conceptRows(fixture.conn, "call_duration");
verifyEqual(testCase, height(duration), 2);
verifyEqual(testCase, sort(string(duration.native_name)), ...
    ["Call Length (s)"; "syllable duration (msec)"]);
verifyEqual(testCase, numel(unique(double(duration.extractor_feature_id))), 2);
verifyNotEqual(testCase, presentText(duration.derivation_stage(1)), ...
    presentText(duration.derivation_stage(2)));
mupetDuration = duration(string(duration.extractor_name) == "MUPET", :);
verifyEqual(testCase, presentText(mupetDuration.operational_variant(1)), ...
    "pre_noise_reduction");
deepSqueakDuration = duration(string(duration.extractor_name) == "DeepSqueak", :);
verifyEqual(testCase, presentText(deepSqueakDuration.operational_variant(1)), "");

% Stress case 2 - central frequency. Two methods for one broad idea, and the
% database refuses to pretend otherwise: they map to different canonical
% features, so no query can silently average a contour median with a
% filterbank mean. They meet only at the shared equivalence class.
centre = fetch(fixture.conn, ...
    "SELECT e.extractor_name, xf.native_name, xf.extractor_feature_id, " + ...
    "IFNULL(cf.canonical_name,'') AS canonical_name, " + ...
    "IFNULL(xf.native_definition,'') AS native_definition " + ...
    "FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "LEFT JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "LEFT JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE xf.equivalence_class = 'vocalization_frequency_center' " + ...
    "ORDER BY e.extractor_name");
verifyEqual(testCase, height(centre), 2);
verifyEqual(testCase, string(centre.canonical_name), ...
    ["contour_median_frequency"; "frequency_center"]);
verifyEqual(testCase, numel(unique(double(centre.extractor_feature_id))), 2);
verifyNotEqual(testCase, presentText(centre.native_definition(1)), ...
    presentText(centre.native_definition(2)));

% Stress case 3 - power, energy, and amplitude. Three distinct quantities that
% are never collapsed into one interchangeable canonical measure.
levels = fetch(fixture.conn, ...
    "SELECT DISTINCT cf.canonical_name, cf.feature_domain " + ...
    "FROM v_event_measurements_long m " + ...
    "JOIN canonical_features cf ON cf.canonical_name = m.canonical_name " + ...
    "WHERE m.canonical_name IN " + ...
    "('mean_power_spectral_density','total_energy','peak_amplitude') " + ...
    "ORDER BY cf.canonical_name");
verifyEqual(testCase, height(levels), 3);
verifyEqual(testCase, string(levels.feature_domain), ...
    ["power_energy"; "amplitude"; "power_energy"]);

% The seeded relationship between them stays 'related' and stays ineligible for
% consilience. Importing real rows from both extractors did not upgrade it, and
% no transform-equivalent assertion exists anywhere.
relationships = fetch(fixture.conn, ...
    "SELECT relationship_type, consilience_eligible FROM feature_relationships");
verifyTrue(testCase, any(string(relationships.relationship_type) == "related"));
verifyEqual(testCase, nnz(string(relationships.relationship_type) == "transform_equivalent"), 0);
related = relationships(string(relationships.relationship_type) == "related", :);
verifyEqual(testCase, unique(double(related.consilience_eligible)), 0);

clear cleanup
end

% ------------------------------------------------------------ asymmetries ---

function testCurationAndClassificationAsymmetriesAreVisible(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

% DeepSqueak exports a review state and an opaque label, so its detections
% carry extractor-authored curation and classification evidence. MUPET's
% per-syllable CSV exports neither, so its detections carry none. The relational
% model holds both populations without either capability being mandatory.
byExtractor = fetch(fixture.conn, ...
    "SELECT c.extractor_name, " + ...
    "COUNT(DISTINCT c.detection_id) AS detections, " + ...
    "COUNT(DISTINCT ce.curation_event_id) AS curation_rows, " + ...
    "COUNT(DISTINCT ca.classification_assignment_id) AS assignments " + ...
    "FROM v_detection_core c " + ...
    "LEFT JOIN curation_events ce ON ce.detection_id = c.detection_id " + ...
    "LEFT JOIN classification_assignments ca ON ca.detection_id = c.detection_id " + ...
    "GROUP BY c.extractor_name ORDER BY c.extractor_name");
verifyEqual(testCase, string(byExtractor.extractor_name), ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, double(byExtractor.detections), [3; 4]);
verifyEqual(testCase, double(byExtractor.curation_rows), [3; 0]);
verifyEqual(testCase, double(byExtractor.assignments), [3; 0]);

% DeepSqueak's review evidence remains extractor-authored and keeps its native
% token; no reviewer was invented for either extractor.
actors = fetch(fixture.conn, "SELECT DISTINCT actor_type FROM curation_events");
verifyEqual(testCase, string(actors.actor_type), "extractor");

% The rejected DeepSqueak call is still imported. A review state is evidence,
% not a filter.
rejected = fetch(fixture.conn, ...
    "SELECT c.native_event_id FROM v_detection_core c " + ...
    "JOIN curation_events ce ON ce.detection_id = c.detection_id " + ...
    "WHERE ce.status_after = 'rejected'");
verifyEqual(testCase, string(rejected.native_event_id), "3");

% DeepSqueak's labels are preserved without canonical biological meaning, and
% the classification run says its provenance is unspecified.
runs = fetch(fixture.conn, ...
    "SELECT method, number_of_classes FROM classification_runs");
verifyEqual(testCase, height(runs), 1);
verifyEqual(testCase, string(runs.method(1)), "native_label_unspecified_provenance");
canonical = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM classification_classes " + ...
    "WHERE canonical_class_label IS NOT NULL");
verifyEqual(testCase, double(canonical.n(1)), 0);

% Detector score is likewise a DeepSqueak capability, not a universal column.
scores = fetch(fixture.conn, ...
    "SELECT extractor_name, COUNT(detection_score) AS with_score " + ...
    "FROM v_detection_core GROUP BY extractor_name ORDER BY extractor_name");
verifyEqual(testCase, double(scores.with_score), [3; 0]);

clear cleanup
end

% ------------------------------------------------------------ no matching ---

function testNoMatchingOrConsensusRowsExist(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

% Two overlapping populations now sit on one recording. Phase 5 must not have
% drawn a single conclusion about how they correspond.
for tableName = ["candidate_pairs", "match_groups", "match_group_members", ...
        "consensus_events", "consensus_event_members", "consilience_assessments", ...
        "analysis_runs", "agreement_statistics", "derived_measurements"]
    verifyEqual(testCase, countOf(fixture.conn, tableName), 0, tableName);
end

clear cleanup
end

% -------------------------------------------------- rerun and relocation ----

function testRerunAndRelocationMatrixAcrossBothExtractors(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));
after = tableCounts(fixture.conn);

% Unchanged reruns of both extractors reuse every scientific row.
deepSqueakAgain = applyDeepSqueak(fixture, deepSqueakRunSpec());
verifyTrue(testCase, deepSqueakAgain.committed);
verifyEqual(testCase, deepSqueakAgain.applied_counts.detections, 0);
mupetAgain = applyMupet(fixture, mupetRunSpec(fixture));
verifyTrue(testCase, mupetAgain.committed);
verifyEqual(testCase, mupetAgain.applied_counts.detections, 0);
verifyEqual(testCase, tableCounts(fixture.conn), after);

% Relocating both artifact trees under new absolute roots changes nothing,
% because durable artifact identity is the portable path plus content.
relocated = relocateArtifacts(fixture);
deepSqueakMoved = vawlume.ingest.deepsqueak(fixture.conn, relocated.deepsqueak_export, ...
    portableRef(), deepSqueakRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=relocated.deepsqueak_root, Apply=true);
verifyTrue(testCase, deepSqueakMoved.committed);
verifyEqual(testCase, deepSqueakMoved.applied_counts.artifacts, 0);
mupetSpec = mupetRunSpec(fixture);
mupetSpec.settings = struct(config_path=relocated.mupet_config);
mupetMoved = vawlume.ingest.mupet(fixture.conn, relocated.mupet_export, ...
    portableRef(), mupetSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=relocated.mupet_root, Apply=true);
verifyTrue(testCase, mupetMoved.committed);
verifyEqual(testCase, mupetMoved.applied_counts.artifacts, 0);
verifyEqual(testCase, tableCounts(fixture.conn), after);

% Changed MUPET settings conflict the MUPET run and leave DeepSqueak alone.
writeText(fixture.mupet_config, strjoin([mupetConfigLines(); ...
    "extra-setting,1"], newline) + newline);
conflicted = planMupet(fixture, mupetRunSpec(fixture));
verifyTrue(testCase, conflicted.has_conflicts);
verifyEqual(testCase, applyDeepSqueak(fixture, deepSqueakRunSpec()).committed, true);
verifyEqual(testCase, tableCounts(fixture.conn), after);
writeText(fixture.mupet_config, strjoin(mupetConfigLines(), newline) + newline);

% A changed DeepSqueak export under one run key retains Phase 4 behaviour and
% does not disturb MUPET.
changedPath = fullfile(fixture.scratch, "ds_changed", "exports", "REC_A_Stats.xlsx");
writeExport(changedPath, changedDeepSqueakExport());
changed = vawlume.ingest.deepsqueak(fixture.conn, changedPath, portableRef(), ...
    deepSqueakRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fullfile(fixture.scratch, "ds_changed"), Apply=true);
verifyTrue(testCase, changed.has_conflicts);
verifyFalse(testCase, changed.committed);
verifyEqual(testCase, tableCounts(fixture.conn), after);

% Second legitimate runs of each extractor coexist without mutating the first.
secondDeepSqueak = deepSqueakRunSpec();
secondDeepSqueak.run_key = "ds-run-2";
verifyTrue(testCase, applyDeepSqueak(fixture, secondDeepSqueak).committed);
secondMupet = mupetRunSpec(fixture);
secondMupet.run_key = "mupet-run-2";
verifyTrue(testCase, applyMupet(fixture, secondMupet).committed);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 4);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 14);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), after.artifacts);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ------------------------------------------------- transaction isolation ----

function testTransactionIsolationBetweenExtractors(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
deepSqueakOnly = tableCounts(fixture.conn);

% A MUPET import that fails part way must leave the existing DeepSqueak
% population exactly as it was.
verifyError(testCase, @() failingMupetImport(fixture), ...
    "vawlume:ingest:InducedApplyFailure");
verifyEqual(testCase, tableCounts(fixture.conn), deepSqueakOnly);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

% MUPET then imports cleanly on top of the untouched DeepSqueak population.
applyMupet(fixture, mupetRunSpec(fixture));
both = tableCounts(fixture.conn);
verifyEqual(testCase, both.detections, 7);

% A DeepSqueak run that fails part way must leave the MUPET population intact.
newRun = deepSqueakRunSpec();
newRun.run_key = "ds-run-2";
verifyError(testCase, @() failingDeepSqueakImport(fixture, newRun), ...
    "vawlume:ingest:InducedApplyFailure");
verifyEqual(testCase, tableCounts(fixture.conn), both);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

% Both connections and both importers remain usable afterwards.
verifyTrue(testCase, applyDeepSqueak(fixture, newRun).committed);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 10);

clear cleanup
end

% ----------------------------------------------------- relational integrity --

function testForeignKeyAndSemanticIntegrityHold(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

% Every detection belongs to exactly one extraction run, and every run input
% resolves to the intended recording.
orphans = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM detections d " + ...
    "LEFT JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "WHERE er.extraction_run_id IS NULL OR d.extraction_run_id IS NULL");
verifyEqual(testCase, double(orphans.n(1)), 0);
inputs = fetch(fixture.conn, ...
    "SELECT DISTINCT recording_id FROM extraction_run_inputs");
verifyEqual(testCase, double(inputs.recording_id), 1);

% Every measurement's feature belongs to the same extractor as the run that
% produced its detection. A MUPET measurement can never point at DeepSqueak
% native feature identity, or the reverse.
crossed = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM event_measurements em " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "JOIN extractor_versions runVersion " + ...
    "ON runVersion.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN extractor_versions featureVersion " + ...
    "ON featureVersion.extractor_version_id = xf.extractor_version_id " + ...
    "WHERE runVersion.extractor_id <> featureVersion.extractor_id");
verifyEqual(testCase, double(crossed.n(1)), 0);

% Canonical concepts are shared only through feature_mappings. No canonical
% feature is reached by two extractors owning one native feature row.
nativeCollision = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM (" + ...
    "SELECT xf.extractor_feature_id FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "GROUP BY xf.extractor_feature_id HAVING COUNT(DISTINCT ev.extractor_id) > 1)");
verifyEqual(testCase, double(nativeCollision.n(1)), 0);

sharedCanonical = fetch(fixture.conn, ...
    "SELECT cf.canonical_name, COUNT(DISTINCT ev.extractor_id) AS extractors, " + ...
    "COUNT(DISTINCT xf.extractor_feature_id) AS native_features " + ...
    "FROM canonical_features cf " + ...
    "JOIN feature_mappings fm ON fm.canonical_feature_id = cf.canonical_feature_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = fm.extractor_feature_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "WHERE cf.canonical_name = 'frequency_min' GROUP BY cf.canonical_name");
verifyEqual(testCase, double(sharedCanonical.extractors(1)), 2);
verifyEqual(testCase, double(sharedCanonical.native_features(1)), 2);

clear cleanup
end

% ---------------------------------------------------- query readiness -------

function testQueryReadinessForMatchingWithoutCreatingMatches(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyDeepSqueak(fixture, deepSqueakRunSpec());
applyMupet(fixture, mupetRunSpec(fixture));

% Everything a matching phase needs is obtainable now, without any new view and
% without any match row being written.
population = fetch(fixture.conn, ...
    "SELECT extractor_name, native_event_id, start_time_s, end_time_s, duration_s " + ...
    "FROM v_detection_core WHERE recording_id = 1 " + ...
    "ORDER BY start_time_s, extractor_name");
verifyEqual(testCase, height(population), 7);
verifyEqual(testCase, double(population.start_time_s(1)), 10.000, AbsTol=1e-9);
verifyEqual(testCase, string(population.extractor_name(1)), "DeepSqueak");
verifyEqual(testCase, string(population.extractor_name(2)), "MUPET");

% The deliberately awkward fixture cases are all present and distinguishable:
% one overlapping pair, one MUPET-only event, and one DeepSqueak call spanning
% two MUPET syllables. Phase 6 gets to decide what any of that means.
mupetOnly = population(string(population.extractor_name) == "MUPET" & ...
    double(population.start_time_s) > 29 & double(population.start_time_s) < 31, :);
verifyEqual(testCase, height(mupetOnly), 1);
spanning = population(double(population.start_time_s) >= 40, :);
verifyEqual(testCase, height(spanning), 3);
verifyEqual(testCase, sort(string(spanning.extractor_name)), ...
    ["DeepSqueak"; "MUPET"; "MUPET"]);

% Comparable features arrive in canonical units with their native definitions
% and relationship metadata attached.
comparable = fetch(fixture.conn, ...
    "SELECT c.extractor_name, m.canonical_name, m.canonical_value_real, " + ...
    "m.canonical_unit, IFNULL(xf.native_definition,'') AS native_definition, " + ...
    "IFNULL(xf.equivalence_class,'') AS equivalence_class " + ...
    "FROM v_event_measurements_long m " + ...
    "JOIN v_detection_core c ON c.detection_id = m.detection_id " + ...
    "JOIN extractor_features xf ON xf.native_name = m.native_name " + ...
    "WHERE m.canonical_name = 'frequency_max' AND c.native_event_id = '1' " + ...
    "ORDER BY c.extractor_name");
verifyEqual(testCase, height(comparable), 2);
verifyEqual(testCase, unique(string(comparable.canonical_unit)), "Hz");
verifyEqual(testCase, unique(presentText(comparable.equivalence_class)), ...
    "vocalization_frequency_max");

relationships = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM feature_relationships WHERE consilience_eligible = 1");
verifyGreaterThan(testCase, double(relationships.n(1)), 0);

% Settings and profile provenance for both runs is reachable in one query.
provenance = fetch(fixture.conn, ...
    "SELECT e.extractor_name, cp.profile_key, cpv.checksum_sha256, " + ...
    "IFNULL(er.notes,'') AS notes FROM extraction_runs er " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = er.output_mapping_profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id ORDER BY e.extractor_name");
verifyEqual(testCase, height(provenance), 2);
verifyFalse(testCase, any(strlength(string(provenance.checksum_sha256)) == 0));
verifyTrue(testCase, contains(string(provenance.notes(2)), "settings=captured"));

% Still no matching rows after all of that.
verifyEqual(testCase, countOf(fixture.conn, "candidate_pairs"), 0);
verifyEqual(testCase, countOf(fixture.conn, "consensus_events"), 0);

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "dual_extractor.sqlite");
copyfile(seededTemplateDatabase(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

execute(conn, "INSERT INTO projects(project_key, project_name) VALUES('proj-a','Project A')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri,relative_path,filename) " + ...
    "VALUES(1,'recording_audio','audio/day1/REC_A.wav','audio/day1/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id,native_recording_id) VALUES(1,1,'REC_A')");

deepSqueakRoot = fullfile(scratch, "deepsqueak");
mupetRoot = fullfile(scratch, "mupet");
deepSqueakExport = fullfile(deepSqueakRoot, "exports", "REC_A_Stats.xlsx");
mupetExport = fullfile(mupetRoot, "audio", "set", "CSV", "REC_A.csv");
mupetConfig = fullfile(mupetRoot, "config.csv");
writeExport(deepSqueakExport, deepSqueakNominalExport());
writeCsv(mupetExport, mupetNominalExport());
writeText(mupetConfig, strjoin(mupetConfigLines(), newline) + newline);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    deepsqueak_root=deepSqueakRoot, mupet_root=mupetRoot, ...
    deepsqueak_export=deepSqueakExport, mupet_export=mupetExport, ...
    mupet_config=mupetConfig);
end

function path = seededTemplateDatabase(repoRoot)
persistent templatePath
if ~isempty(templatePath) && isfile(templatePath), path = templatePath; return, end
templatePath = string(tempname) + ".sqlite";
conn = sqlite(char(templatePath), "create");
cleaner = onCleanup(@() close(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
delete(cleaner);
path = templatePath;
end

function tearDown(conn, scratch, repoRoot)
try close(conn); catch; end
if isfolder(scratch), rmdir(scratch, "s"); end
rmpath(fullfile(repoRoot, "src"));
end

function ref = portableRef()
ref = struct(project_key="proj-a", source_relative_path="audio/day1/REC_A.wav");
end

function spec = deepSqueakRunSpec()
spec = struct(run_key="ds-run-1", extractor_version="3.2.1", ...
    run_label="DeepSqueak detection run 1");
end

function spec = mupetRunSpec(fixture)
spec = struct(run_key="mupet-run-1", extractor_version="2.1", ...
    run_label="MUPET syllable run 1", ...
    settings=struct(config_path=fixture.mupet_config));
end

function result = applyDeepSqueak(fixture, spec)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.deepsqueak_export, ...
    portableRef(), spec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.deepsqueak_root, Apply=true);
end

function result = applyMupet(fixture, spec)
result = vawlume.ingest.mupet(fixture.conn, fixture.mupet_export, ...
    portableRef(), spec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.mupet_root, Apply=true);
end

function result = planMupet(fixture, spec)
result = vawlume.ingest.mupet(fixture.conn, fixture.mupet_export, ...
    portableRef(), spec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.mupet_root);
end

function relocated = relocateArtifacts(fixture)
%RELOCATEARTIFACTS Copy both artifact trees under new absolute roots.
%
% The portable paths beneath each root are unchanged, so durable identity is
% unchanged and both importers must reuse their existing artifact rows.
target = fullfile(fixture.scratch, "relocated");
deepSqueakRoot = fullfile(target, "deepsqueak");
mupetRoot = fullfile(target, "mupet");
copyfile(fixture.deepsqueak_root, deepSqueakRoot);
copyfile(fixture.mupet_root, mupetRoot);
relocated = struct( ...
    deepsqueak_root=deepSqueakRoot, ...
    mupet_root=mupetRoot, ...
    deepsqueak_export=fullfile(deepSqueakRoot, "exports", "REC_A_Stats.xlsx"), ...
    mupet_export=fullfile(mupetRoot, "audio", "set", "CSV", "REC_A.csv"), ...
    mupet_config=fullfile(mupetRoot, "config.csv"));
end

function failingMupetImport(fixture)
% event_measurements is the last table the MUPET importer writes, so aborting
% there proves its whole transaction rolls back without touching DeepSqueak.
execute(fixture.conn, "CREATE TRIGGER trg_dual_mupet_failure " + ...
    "BEFORE INSERT ON event_measurements FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced MUPET failure'); END");
restore = onCleanup(@() dropTrigger(fixture.conn, "trg_dual_mupet_failure"));
try
    applyMupet(fixture, mupetRunSpec(fixture));
catch exception
    clear restore
    error("vawlume:ingest:InducedApplyFailure", ...
        "Induced MUPET failure surfaced as: %s", exception.message);
end
clear restore
error("vawlume:ingest:InducedApplyFailure", "The induced MUPET failure did not abort.");
end

function failingDeepSqueakImport(fixture, spec)
% classification_assignments is the last table the DeepSqueak importer writes,
% and MUPET never writes it, so aborting there is a DeepSqueak-only failure.
execute(fixture.conn, "CREATE TRIGGER trg_dual_deepsqueak_failure " + ...
    "BEFORE INSERT ON classification_assignments FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced DeepSqueak failure'); END");
restore = onCleanup(@() dropTrigger(fixture.conn, "trg_dual_deepsqueak_failure"));
try
    applyDeepSqueak(fixture, spec);
catch exception
    clear restore
    error("vawlume:ingest:InducedApplyFailure", ...
        "Induced DeepSqueak failure surfaced as: %s", exception.message);
end
clear restore
error("vawlume:ingest:InducedApplyFailure", "The induced DeepSqueak failure did not abort.");
end

function dropTrigger(conn, name)
try
    execute(conn, "DROP TRIGGER IF EXISTS " + name);
catch
end
end

function rows = conceptRows(conn, canonicalName)
rows = fetch(conn, ...
    "SELECT DISTINCT c.extractor_name, m.native_name, em.extractor_feature_id, " + ...
    "IFNULL(m.derivation_stage,'') AS derivation_stage, " + ...
    "IFNULL(m.operational_variant,'') AS operational_variant " + ...
    "FROM v_event_measurements_long m " + ...
    "JOIN v_detection_core c ON c.detection_id = m.detection_id " + ...
    "JOIN event_measurements em ON em.event_measurement_id = m.event_measurement_id " + ...
    "WHERE m.canonical_name = '" + canonicalName + "' ORDER BY c.extractor_name");
end

function headers = deepSqueakHeaders()
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
end

function cells = deepSqueakNominalExport()
% Three calls: one that overlaps a MUPET syllable, one with no MUPET
% counterpart nearby, and one long call spanning two MUPET syllables.
detectionFile = 'C:\deepsqueak\detections\REC_A_deepsqueak.mat';
cells = [
    deepSqueakHeaders()
    {detectionFile, 1, '22kHz-Call', 1, 0.9134, 10.000, 10.050, 0.050, ...
        62.4, 45.1, 80.2, 35.1, 3.2, -120.5, 1.12, -71.4, 0.78, 63.0}
    {detectionFile, 2, 'USV', 1, 0.8021, 20.000, 20.040, 0.040, ...
        61.0, 50.0, 72.0, 22.0, 2.1, 15.0, 1.05, -70.1, 0.81, 61.5}
    {detectionFile, 3, 'Noise', 0, 0.2107, 40.000, 40.100, 0.100, ...
        63.5, 42.0, 84.0, 42.0, 4.4, -8.25, 1.40, -69.3, 0.69, 64.2}
];
end

function cells = changedDeepSqueakExport()
cells = deepSqueakNominalExport();
cells{2, 7} = 10.060;
cells{2, 8} = 0.060;
end

function headers = mupetHeaders()
headers = {'Syllable number', 'Syllable start time (sec)', 'Syllable end time (sec)', ...
    'inter-syllable interval (sec)', 'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', 'maximum frequency (kHz)', ...
    'mean frequency (kHz)', 'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
end

function cells = mupetNominalExport()
% Syllable 1 overlaps DeepSqueak call 1 and deliberately reuses native id 1.
% Syllable 2 has no DeepSqueak counterpart. Syllables 3 and 4 both fall inside
% DeepSqueak call 3. The terminal interval carries MUPET's sentinel.
cells = [
    mupetHeaders()
    {1, 10.004, 10.052, 19.948, 48.0, 45.0, 62.0, 44.5, 80.0, 62.0, 35.5, 12.5, -18}
    {2, 30.000, 30.035, 10.002, 34.7, 46.0, 59.0, 50.5, 72.5, 61.0, 22.0, 11.5, -19}
    {3, 40.002, 40.045, 0.007, 42.6, 47.0, 61.0, 42.5, 84.5, 63.0, 42.0, 10.5, -20}
    {4, 40.052, 40.098, 'NA', 45.8, 48.0, 62.0, 43.0, 83.0, 62.5, 40.0, 9.5, -21}
];
end

function lines = mupetConfigLines()
lines = ["noise-reduction,5"; "minimum-syllable-duration,008"; ...
    "maximum-syllable-duration,200"; "minimum-syllable-total-energy,-15"; ...
    "minimum-syllable-peak-amplitude,-25"; "minimum-syllable-distance,5"; ...
    "sample-frequency,250000"; "minimum-usv-frequency,30000"; ...
    "maximum-usv-frequency,120000"; "number-filterbank-filters,64"; "filterbank-type,1"];
end

function counts = tableCounts(conn)
names = ["projects", "source_files", "recordings", "config_profiles", ...
    "config_profile_versions", "extractors", "extractor_versions", "artifacts", ...
    "extraction_runs", "extraction_run_inputs", "extraction_run_artifacts", ...
    "extractor_objects", "detections", "event_measurements", "curation_events", ...
    "classification_runs", "classification_classes", "classification_assignments", ...
    "candidate_pairs", "match_groups", "consensus_events"];
counts = struct();
for name = names
    counts.(name) = countOf(conn, name);
end
end

function value = countOf(conn, name)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + name);
value = double(rows.n(1));
end

function writeExport(path, cells)
makeParent(path);
if isfile(path), delete(path); end
writecell(cells, path);
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

function text = presentText(value)
%PRESENTTEXT Normalize a fetched text value to a comparable string.
%
% MATLAB's SQLite fetch returns <missing> rather than "" for an empty text
% value, even one produced by IFNULL, and every comparison against a missing
% string is false.
text = string(value);
text(ismissing(text)) = "";
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
