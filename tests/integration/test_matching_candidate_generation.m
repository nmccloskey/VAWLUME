function tests = test_matching_candidate_generation
%TEST_MATCHING_CANDIDATE_GENERATION Phase 6 transparent temporal candidates.
tests = functiontests(localfunctions);
end

function testNominalPlanIsCompleteTransparentAndReadOnly(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = matchingCounts(fixture.conn);

result = planNominal(fixture, "matching-v1");

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyEqual(testCase, result.detection_counts, struct(run_a=3, run_b=4));
verifyEqual(testCase, result.candidate_count, 3);
verifyEqual(testCase, result.unmatched_counts, struct(run_a=1, run_b=1));
verifyEqual(testCase, result.unmatched_detection_ids.run_a_detection_ids, 2);
verifyEqual(testCase, result.unmatched_detection_ids.run_b_detection_ids, 5);
verifyEqual(testCase, result.group_count, 4);
verifyEqual(testCase, result.consensus_count, 2);
verifyEqual(testCase, string(result.groups.match_type), ...
    ["one_to_one"; "unmatched"; "one_to_many"; "unmatched"]);
verifyEqual(testCase, matchingCounts(fixture.conn), before);

rows = result.candidates;
verifyEqual(testCase, rows.run_a_detection_id, [1; 3; 3]);
verifyEqual(testCase, rows.run_b_detection_id, [4; 6; 7]);
verifyEqual(testCase, rows.temporal_overlap_s, [.046; .043; .046], AbsTol=1e-12);
verifyEqual(testCase, rows.temporal_iou, [.046/.052; .43; .46], AbsTol=1e-12);
verifyEqual(testCase, rows.onset_difference_s, [.004; .002; .052], AbsTol=1e-12);
verifyEqual(testCase, rows.offset_difference_s, [.002; -.055; -.002], AbsTol=1e-12);
verifyEqual(testCase, rows.duration_difference_s, [-.002; -.057; -.054], AbsTol=1e-12);
verifyEqual(testCase, rows.candidate_score, rows.temporal_iou, AbsTol=1e-15);
verifyEqual(testCase, unique(rows.candidate_status), "eligible");
verifyTrue(testCase, all(rows.detection_a_id < rows.detection_b_id));
detail = jsondecode(rows.details_json(1));
verifyEqual(testCase, string(detail.evidence_direction), "run_a_to_run_b");
verifyEqual(testCase, detail.run_a_detection_id, 1);
verifyEqual(testCase, detail.run_b_detection_id, 4);
verifyEqual(testCase, detail.min_temporal_iou, .10, AbsTol=1e-15);

clear cleanup
end

function testActualDualImporterOutputFeedsCandidateGeneration(testCase)
[fixture, cleanup] = setUpImportedFixture(); %#ok<ASGLU>
beforeDetections = countOf(fixture.conn, "detections");
beforeMeasurements = countOf(fixture.conn, "event_measurements");

result = vawlume.matching.compare(fixture.conn, ...
    struct(project_key="imported-project", ...
        source_relative_path="audio/REC_A.wav"), ...
    struct(run_a="ds-imported", run_b="mupet-imported"), ...
    struct(run_key="matching-imported"), RepoRoot=fixture.repo_root, Apply=true);

verifyEqual(testCase, result.status, "committed");
verifyEqual(testCase, result.candidate_count, 3);
verifyEqual(testCase, result.unmatched_counts, struct(run_a=1, run_b=1));
verifyEqual(testCase, countOf(fixture.conn, "detections"), beforeDetections);
verifyEqual(testCase, countOf(fixture.conn, "event_measurements"), beforeMeasurements);
verifyEqual(testCase, beforeDetections, 7);
verifyEqual(testCase, beforeMeasurements, 90);
verifyEqual(testCase, countOf(fixture.conn, "match_groups"), 4);
verifyEqual(testCase, countOf(fixture.conn, "consensus_events"), 2);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testIntervalSweepEqualsBruteForceReference(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planNominal(fixture, "sweep-reference-v1");
expected = bruteForceCandidates(fixture.conn, 1, 2, .10);
actual = result.candidates(:, ["run_a_detection_id", "run_b_detection_id", ...
    "temporal_overlap_s", "temporal_iou", "onset_difference_s", ...
    "offset_difference_s", "duration_difference_s"]);

verifyEqual(testCase, actual.run_a_detection_id, expected.run_a_detection_id);
verifyEqual(testCase, actual.run_b_detection_id, expected.run_b_detection_id);
for name = ["temporal_overlap_s", "temporal_iou", ...
        "onset_difference_s", "offset_difference_s", "duration_difference_s"]
    verifyEqual(testCase, actual.(name), expected.(name), AbsTol=1e-12);
end

clear cleanup
end

function testApplyPersistsProvenanceCandidatesGroupsAndConsensus(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = applyNominal(fixture, "matching-v1");

verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.applied_counts.config_profiles, 1);
verifyEqual(testCase, result.applied_counts.config_profile_versions, 1);
verifyEqual(testCase, result.applied_counts.analysis_runs, 1);
verifyEqual(testCase, result.applied_counts.analysis_run_extraction_inputs, 2);
verifyEqual(testCase, result.applied_counts.candidate_pairs, 3);
verifyEqual(testCase, result.applied_counts.match_groups, 4);
verifyEqual(testCase, result.applied_counts.match_group_members, 7);
verifyEqual(testCase, result.applied_counts.consensus_events, 2);
verifyEqual(testCase, result.applied_counts.consensus_event_members, 5);

analysis = fetch(fixture.conn, "SELECT run_type, run_key, status FROM analysis_runs");
verifyEqual(testCase, string(analysis.run_type), "cross_extractor_matching");
verifyEqual(testCase, string(analysis.run_key), "matching-v1");
verifyEqual(testCase, string(analysis.status), "completed");
inputs = fetch(fixture.conn, "SELECT er.run_key, arei.input_role " + ...
    "FROM analysis_run_extraction_inputs arei JOIN extraction_runs er " + ...
    "ON er.extraction_run_id=arei.extraction_run_id ORDER BY arei.input_role");
verifyEqual(testCase, string(inputs.run_key), ["ds-1"; "mupet-1"]);
verifyEqual(testCase, string(inputs.input_role), ["run_a"; "run_b"]);
profile = fetch(fixture.conn, "SELECT cp.profile_kind, cpv.content_uri, " + ...
    "cpv.checksum_sha256, arp.assignment_role FROM config_profiles cp " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_id=cp.profile_id " + ...
    "JOIN analysis_run_profiles arp ON arp.profile_version_id=cpv.profile_version_id");
verifyEqual(testCase, string(profile.profile_kind), "consilience_policy");
verifyEqual(testCase, string(profile.assignment_role), "matching_spec");
verifyEqual(testCase, string(profile.content_uri), ...
    "config/05_matching_profiles/prototype_matching_consilience_spec.json");
verifyEqual(testCase, strlength(string(profile.checksum_sha256)), 64);

expectedCounts = struct(match_groups=4, match_group_members=7, ...
    consensus_events=2, consensus_event_members=5, ...
    consilience_assessments=0, agreement_statistics=0);
for tableName = string(fieldnames(expectedCounts))'
    verifyEqual(testCase, countOf(fixture.conn, tableName), ...
        expectedCounts.(tableName), tableName);
end
verifyEqual(testCase, countOf(fixture.conn, "detections"), 7);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testCompatibleRerunReusesAndChangedSpecConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyNominal(fixture, "matching-v1");
before = matchingCounts(fixture.conn);

again = applyNominal(fixture, "matching-v1");
verifyEqual(testCase, again.status, "reused");
verifyTrue(testCase, again.committed);
verifyEqual(testCase, again.applied_counts.analysis_runs, 0);
verifyEqual(testCase, again.applied_counts.candidate_pairs, 0);
verifyEqual(testCase, again.applied_counts.reused_analysis_runs, 1);
verifyEqual(testCase, again.applied_counts.reused_match_groups, 4);
verifyEqual(testCase, again.applied_counts.reused_consensus_events, 2);
verifyEqual(testCase, matchingCounts(fixture.conn), before);

changedPath = writeSpecVariant(fixture, "changed_same_identity.json", ...
    {'"min_temporal_iou": 0.10'}, {'"min_temporal_iou": 0.25'});
conflict = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key="matching-v1", profile_path=changedPath), ...
    RepoRoot=fixture.repo_root, Apply=true);
verifyEqual(testCase, conflict.status, "conflict");
verifyTrue(testCase, conflict.has_conflicts);
verifyFalse(testCase, conflict.committed);
verifyEqual(testCase, matchingCounts(fixture.conn), before);

clear cleanup
end

function testReversedOrderFlipsSignedEvidenceButNotSchemaOrdering(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a="mupet-1", run_b="ds-1"), struct(run_key="reverse-v1"), ...
    RepoRoot=fixture.repo_root);

verifyEqual(testCase, result.candidate_count, 3);
row = result.candidates(result.candidates.run_a_detection_id == 4 & ...
    result.candidates.run_b_detection_id == 1, :);
verifyEqual(testCase, row.onset_difference_s, -.004, AbsTol=1e-12);
verifyEqual(testCase, row.offset_difference_s, -.002, AbsTol=1e-12);
verifyEqual(testCase, row.duration_difference_s, .002, AbsTol=1e-12);
verifyEqual(testCase, row.detection_a_id, 1);
verifyEqual(testCase, row.detection_b_id, 4);
detail = jsondecode(row.details_json);
verifyEqual(testCase, detail.run_a_extraction_run_id, 2);
verifyEqual(testCase, detail.run_b_extraction_run_id, 1);

clear cleanup
end

function testRunPairLegalityIsEnforcedBeforeGeneration(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
spec = struct(run_key="invalid-v1");

verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
    recordingRef(), struct(run_a="ds-1", run_b="ds-1"), spec, ...
    RepoRoot=fixture.repo_root), "vawlume:matching:SameExtractionRun");
verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
    recordingRef(), struct(run_a="ds-1", run_b="ds-2"), spec, ...
    RepoRoot=fixture.repo_root), "vawlume:matching:SameExtractor");
verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
    recordingRef(), struct(run_a="ds-1", run_b="mupet-rec2"), spec, ...
    RepoRoot=fixture.repo_root), "vawlume:matching:RunRecordingMismatch");

clear cleanup
end

function testEmptyRunsAreLegalAndInvalidGeometryIsAPreflightDefect(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
empty = vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a="ds-2", run_b="other-1"), struct(run_key="empty-v1"), ...
    RepoRoot=fixture.repo_root);
verifyEqual(testCase, empty.detection_counts, struct(run_a=0, run_b=0));
verifyEqual(testCase, empty.candidate_count, 0);
verifyEqual(testCase, empty.unmatched_counts, struct(run_a=0, run_b=0));

insertDetection(fixture.conn, 5, 1, "zero", 8, 8);
verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
    recordingRef(), struct(run_a="ds-2", run_b="other-1"), ...
    struct(run_key="invalid-geometry-v1"), RepoRoot=fixture.repo_root), ...
    "vawlume:matching:InvalidGeometry");

clear cleanup
end

function testTouchingContainedAndPartialIntervalsUseFrozenFormulas(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
insertDetection(fixture.conn, 3, 1, "a-contained", 1, 2);
insertDetection(fixture.conn, 3, 1, "a-partial", 4, 6);
insertDetection(fixture.conn, 5, 1, "b-touching", 2, 3);
insertDetection(fixture.conn, 5, 1, "b-contained", 1.25, 1.75);
insertDetection(fixture.conn, 5, 1, "b-partial", 5, 7);

result = vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a="ds-2", run_b="other-1"), struct(run_key="geometry-v1"), ...
    RepoRoot=fixture.repo_root);
verifyEqual(testCase, result.candidate_count, 2);
verifyEqual(testCase, result.unmatched_counts, struct(run_a=0, run_b=1));

contained = result.candidates(1, :);
verifyEqual(testCase, contained.temporal_overlap_s, .5, AbsTol=1e-12);
verifyEqual(testCase, contained.temporal_iou, .5, AbsTol=1e-12);
verifyEqual(testCase, contained.onset_difference_s, .25, AbsTol=1e-12);
verifyEqual(testCase, contained.offset_difference_s, -.25, AbsTol=1e-12);
verifyEqual(testCase, contained.duration_difference_s, -.5, AbsTol=1e-12);
partial = result.candidates(2, :);
verifyEqual(testCase, partial.temporal_overlap_s, 1, AbsTol=1e-12);
verifyEqual(testCase, partial.temporal_iou, 1/3, AbsTol=1e-12);
verifyEqual(testCase, partial.onset_difference_s, 1, AbsTol=1e-12);
verifyEqual(testCase, partial.offset_difference_s, 1, AbsTol=1e-12);
verifyEqual(testCase, partial.duration_difference_s, 0, AbsTol=1e-12);

clear cleanup
end

function testAnalysesCoexistAndThresholdComesOnlyFromVersionedSpec(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyNominal(fixture, "matching-v1");

strictPath = writeSpecVariant(fixture, "strict.json", ...
    {'vawlume.matching.prototype.v1', '"profile_version": "0.1.0"', ...
    '"min_temporal_iou": 0.10'}, ...
    {'vawlume.matching.prototype.strict', '"profile_version": "0.2.0"', ...
    '"min_temporal_iou": 0.50'});
strict = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key="matching-strict", profile_path=strictPath), ...
    RepoRoot=fixture.repo_root, Apply=true);
verifyEqual(testCase, strict.candidate_count, 1);
verifyEqual(testCase, countOf(fixture.conn, "analysis_runs"), 2);
verifyEqual(testCase, countOf(fixture.conn, "candidate_pairs"), 4);
verifyEqual(testCase, countOf(fixture.conn, "config_profile_versions"), 2);

clear cleanup
end

function testAssignmentAndConsensusPolicyMustMatchVersionedContract(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
optimizerPath = writeSpecVariant(fixture, "optimizer.json", ...
    {'"model": "connected_components_over_candidate_edges"'}, ...
    {'"model": "score_winner"'});
verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
    recordingRef(), nominalPair(), struct(run_key="invalid-assignment", ...
    profile_path=optimizerPath), RepoRoot=fixture.repo_root), ...
    "vawlume:matching:SpecificationInvalid");
consensusPath = writeSpecVariant(fixture, "bad-consensus.json", ...
    {'"derivation_method": "mean_boundary_of_members"'}, ...
    {'"derivation_method": "union_boundary_of_members"'});
verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
    recordingRef(), nominalPair(), struct(run_key="invalid-consensus", ...
    profile_path=consensusPath), RepoRoot=fixture.repo_root), ...
    "vawlume:matching:SpecificationInvalid");
clear cleanup
end

function testGeneratedCandidatesStayInsideDeclaredInputsAndTriggerStillGuards(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = applyNominal(fixture, "matching-v1");
outside = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN detections a ON a.detection_id=cp.detection_a_id " + ...
    "JOIN detections b ON b.detection_id=cp.detection_b_id " + ...
    "WHERE a.extraction_run_id NOT IN (1,2) OR b.extraction_run_id NOT IN (1,2)");
verifyEqual(testCase, double(outside.n), 0);

verifySqlFails(testCase, fixture.conn, ...
    "INSERT INTO candidate_pairs(analysis_run_id,recording_id," + ...
    "detection_a_id,detection_b_id,candidate_status) VALUES(" + ...
    string(result.analysis.analysis_run_id) + ",1,1,2,'illegal_same_run')");
verifyEqual(testCase, countOf(fixture.conn, "candidate_pairs"), 3);

clear cleanup
end

function testApplyFailureRollsBackWholeCandidateGraphAndRestoresConnection(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "CREATE TRIGGER trg_matching_failure " + ...
    "BEFORE INSERT ON candidate_pairs FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT,'induced matching failure'); END");
dropper = onCleanup(@() dropTrigger(fixture.conn));

verifyError(testCase, @() applyWithInducedFailure(fixture), ...
    "vawlume:matching:InducedApplyFailure");
verifyEqual(testCase, countOf(fixture.conn, "config_profiles"), 0);
verifyEqual(testCase, countOf(fixture.conn, "config_profile_versions"), 0);
verifyEqual(testCase, countOf(fixture.conn, "analysis_runs"), 0);
verifyEqual(testCase, countOf(fixture.conn, "analysis_run_extraction_inputs"), 0);
verifyEqual(testCase, countOf(fixture.conn, "candidate_pairs"), 0);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");
clear dropper

recovered = applyNominal(fixture, "matching-v1");
verifyEqual(testCase, recovered.status, "committed");

clear cleanup
end

function testApplyRequiresTransactionOwnershipAndStaticBoundariesHold(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
fixture.conn.AutoCommit = "off";
restore = onCleanup(@() setAutoCommit(fixture.conn, "on"));
verifyError(testCase, @() applyNominal(fixture, "matching-v1"), ...
    "vawlume:matching:TransactionState");
clear restore

matchingRoot = fullfile(fixture.repo_root, "src", "+vawlume", "+matching");
files = dir(fullfile(matchingRoot, "**", "*.m"));
owners = strings(0, 1);
source = "";
for index = 1:numel(files)
    text = string(fileread(fullfile(files(index).folder, files(index).name)));
    source = source + newline + text;
    if contains(text, "conn.AutoCommit = ""off""")
        owners(end + 1, 1) = string(files(index).name); %#ok<AGROW>
    end
end
verifyEqual(testCase, owners, "matchingApplyPlan.m");
verifyFalse(testCase, contains(source, "vawlume.ingest."));
verifyFalse(testCase, contains(source, [".xlsx", ".csv", ...
    "Begin Time (s)", "Syllable start time (sec)"]));
verifyFalse(testCase, contains(source, "hungarian", IgnoreCase=true));
verifyFalse(testCase, contains(source, "matchpairs(", IgnoreCase=true));
verifyFalse(testCase, contains(source, "max(candidate_score", IgnoreCase=true));
verifyFalse(testCase, contains(source, "DELETE FROM candidate_pairs", ...
    IgnoreCase=true));
verifyFalse(testCase, contains(source, "UPDATE detections", IgnoreCase=true));
verifyFalse(testCase, contains(source, "consilience_assessments"));
verifyFalse(testCase, contains(source, "agreement_statistics"));

clear cleanup
end

function testConnectedComponentsPreserveEveryTopologyAndExactConsensus(testCase)
[fixture, cleanup] = setUpTopologyFixture(); %#ok<ASGLU>
beforeDetections = fetch(fixture.conn, "SELECT detection_id,start_time_s,end_time_s " + ...
    "FROM detections ORDER BY detection_id");
result = applyTopology(fixture, "topology-v1", false);

verifyEqual(testCase, result.candidate_count, 9);
verifyEqual(testCase, result.group_count, 6);
verifyEqual(testCase, result.consensus_count, 3);
verifyEqual(testCase, string(result.groups.match_type), ["one_to_one"; ...
    "one_to_many"; "many_to_one"; "many_to_many"; "unmatched"; "unmatched"]);
verifyEqual(testCase, result.groups.run_a_member_count, [1; 1; 2; 2; 1; 0]);
verifyEqual(testCase, result.groups.run_b_member_count, [1; 2; 1; 2; 0; 1]);
verifyEqual(testCase, string(result.groups.ambiguity_status), ["unambiguous"; ...
    "ambiguous"; "ambiguous"; "ambiguous"; "unmatched"; "unmatched"]);
verifyTrue(testCase, all(isnan(result.groups.match_score)));

partition = fetch(fixture.conn, "SELECT d.detection_id, COUNT(mgm.match_group_id) AS n " + ...
    "FROM detections d JOIN match_group_members mgm ON mgm.detection_id=d.detection_id " + ...
    "JOIN match_groups mg ON mg.match_group_id=mgm.match_group_id " + ...
    "WHERE mg.analysis_run_id=" + string(result.analysis.analysis_run_id) + ...
    " AND d.extraction_run_id IN (3,5) GROUP BY d.detection_id ORDER BY d.detection_id");
verifyEqual(testCase, height(partition), 14);
verifyEqual(testCase, double(partition.n), ones(14, 1));
edgeLineage = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN match_group_members left_member ON left_member.detection_id=cp.detection_a_id " + ...
    "JOIN match_group_members right_member ON right_member.detection_id=cp.detection_b_id " + ...
    "JOIN match_groups mg ON mg.match_group_id=left_member.match_group_id " + ...
    "WHERE cp.analysis_run_id=" + string(result.analysis.analysis_run_id) + ...
    " AND right_member.match_group_id=left_member.match_group_id " + ...
    "AND mg.analysis_run_id=cp.analysis_run_id");
verifyEqual(testCase, double(edgeLineage.n), 9);
verifyEqual(testCase, countWhere(fixture.conn, "match_groups", ...
    "analysis_run_id=" + string(result.analysis.analysis_run_id) + ...
    " AND match_type='unmatched'"), 2);

events = fetch(fixture.conn, "SELECT mg.match_type,ce.start_time_s,ce.end_time_s," + ...
    "ce.derivation_method,ce.consensus_status FROM consensus_events ce " + ...
    "JOIN match_groups mg ON mg.match_group_id=ce.match_group_id " + ...
    "WHERE ce.analysis_run_id=" + string(result.analysis.analysis_run_id) + ...
    " ORDER BY ce.start_time_s");
verifyEqual(testCase, string(events.match_type), ...
    ["one_to_one"; "one_to_many"; "many_to_one"]);
verifyEqual(testCase, double(events.start_time_s), [100.1; 200; 300], AbsTol=1e-12);
verifyEqual(testCase, double(events.end_time_s), [101.9; 204; 304], AbsTol=1e-12);
verifyEqual(testCase, string(events.derivation_method), ...
    ["mean_boundary_of_members"; "union_boundary_of_members"; ...
    "union_boundary_of_members"]);
verifyEqual(testCase, countWhere(fixture.conn, "match_groups", ...
    "match_score IS NOT NULL"), 0);
verifyEqual(testCase, countWhere(fixture.conn, "consensus_events", ...
    "confidence_score IS NOT NULL"), 0);
verifyEqual(testCase, fetch(fixture.conn, "SELECT detection_id,start_time_s,end_time_s " + ...
    "FROM detections ORDER BY detection_id"), beforeDetections);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testRunOrderReversalChangesRelativeTopologyOnly(testCase)
[fixture, cleanup] = setUpTopologyFixture(); %#ok<ASGLU>
forward = applyTopology(fixture, "topology-forward", false);
reverse = applyTopology(fixture, "topology-reverse", true);

verifyEqual(testCase, forward.candidate_count, reverse.candidate_count);
verifyEqual(testCase, string(reverse.groups.match_type), ["one_to_one"; ...
    "many_to_one"; "one_to_many"; "many_to_many"; "unmatched"; "unmatched"]);
forwardSets = componentMemberSets(forward);
reverseSets = componentMemberSets(reverse);
verifyEqual(testCase, forwardSets, reverseSets);
verifyEqual(testCase, sortrows([forward.consensus_events.start_time_s, ...
    forward.consensus_events.end_time_s]), sortrows([reverse.consensus_events.start_time_s, ...
    reverse.consensus_events.end_time_s]), AbsTol=1e-12);

clear cleanup
end

function testCandidateOnlyAnalysisIsCompletedWithoutRewritingEdges(testCase)
[fixture, cleanup] = setUpTopologyFixture(); %#ok<ASGLU>
first = applyTopology(fixture, "legacy-pass2", false);
analysisId = first.analysis.analysis_run_id;
stored = fetch(fixture.conn, "SELECT * FROM candidate_pairs WHERE analysis_run_id=" + ...
    string(analysisId) + " ORDER BY candidate_pair_id DESC");
execute(fixture.conn, "DELETE FROM consensus_events WHERE analysis_run_id=" + ...
    string(analysisId));
execute(fixture.conn, "DELETE FROM match_groups WHERE analysis_run_id=" + string(analysisId));
execute(fixture.conn, "DELETE FROM candidate_pairs WHERE analysis_run_id=" + string(analysisId));
for index = 1:height(stored)
    sqlwrite(fixture.conn, "candidate_pairs", stored(index, setdiff( ...
        string(stored.Properties.VariableNames), "candidate_pair_id", "stable")));
end
before = fetch(fixture.conn, "SELECT detection_a_id,detection_b_id,details_json " + ...
    "FROM candidate_pairs WHERE analysis_run_id=" + string(analysisId) + ...
    " ORDER BY detection_a_id,detection_b_id");

completed = applyTopology(fixture, "legacy-pass2", false);
verifyEqual(testCase, completed.status, "committed");
verifyEqual(testCase, completed.applied_counts.candidate_pairs, 0);
verifyEqual(testCase, completed.applied_counts.reused_candidate_pairs, 9);
verifyEqual(testCase, completed.applied_counts.match_groups, 6);
verifyEqual(testCase, completed.applied_counts.consensus_events, 3);
after = fetch(fixture.conn, "SELECT detection_a_id,detection_b_id,details_json " + ...
    "FROM candidate_pairs WHERE analysis_run_id=" + string(analysisId) + ...
    " ORDER BY detection_a_id,detection_b_id");
verifyEqual(testCase, after, before);
verifyEqual(testCase, string(fetch(fixture.conn, "SELECT status FROM analysis_runs " + ...
    "WHERE analysis_run_id=" + string(analysisId)).status), "completed");

again = applyTopology(fixture, "legacy-pass2", false);
verifyEqual(testCase, again.status, "reused");
verifyEqual(testCase, again.applied_counts.reused_match_groups, 6);
clear cleanup
end

function testStoredDerivedMismatchConflictsBeforeAnyWrite(testCase)
[fixture, cleanup] = setUpTopologyFixture(); %#ok<ASGLU>
result = applyTopology(fixture, "conflicting-graph", false);
execute(fixture.conn, "UPDATE match_groups SET ambiguity_status='changed' " + ...
    "WHERE analysis_run_id=" + string(result.analysis.analysis_run_id) + ...
    " AND match_type='one_to_one'");
before = matchingCounts(fixture.conn);
conflict = applyTopology(fixture, "conflicting-graph", false);
verifyEqual(testCase, conflict.status, "conflict");
verifyTrue(testCase, conflict.has_conflicts);
verifyFalse(testCase, conflict.committed);
verifyEqual(testCase, matchingCounts(fixture.conn), before);
clear cleanup
end

function testCandidateOnlyCompletionFailureRollsBackToCompletedCandidateState(testCase)
[fixture, cleanup] = setUpTopologyFixture(); %#ok<ASGLU>
first = applyTopology(fixture, "legacy-failure", false);
analysisId = first.analysis.analysis_run_id;
execute(fixture.conn, "DELETE FROM consensus_events WHERE analysis_run_id=" + ...
    string(analysisId));
execute(fixture.conn, "DELETE FROM match_groups WHERE analysis_run_id=" + ...
    string(analysisId));
execute(fixture.conn, "CREATE TRIGGER trg_matching_consensus_failure " + ...
    "BEFORE INSERT ON consensus_events FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT,'induced consensus failure'); END");
dropper = onCleanup(@() dropNamedTrigger(fixture.conn, ...
    "trg_matching_consensus_failure"));

verifyError(testCase, @() applyTopologyWithInducedFailure(fixture), ...
    "vawlume:matching:InducedDerivedFailure");
verifyEqual(testCase, countWhere(fixture.conn, "candidate_pairs", ...
    "analysis_run_id=" + string(analysisId)), 9);
verifyEqual(testCase, countWhere(fixture.conn, "match_groups", ...
    "analysis_run_id=" + string(analysisId)), 0);
verifyEqual(testCase, countWhere(fixture.conn, "consensus_events", ...
    "analysis_run_id=" + string(analysisId)), 0);
status = fetch(fixture.conn, "SELECT status FROM analysis_runs WHERE analysis_run_id=" + ...
    string(analysisId));
verifyEqual(testCase, string(status.status), "completed");
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");
clear dropper

recovered = applyTopology(fixture, "legacy-failure", false);
verifyEqual(testCase, recovered.status, "committed");
clear cleanup
end

function testAssignmentAndConsensusIntegrityTriggersRejectCrossScopeRows(testCase)
[fixture, cleanup] = setUpTopologyFixture(); %#ok<ASGLU>
result = applyTopology(fixture, "integrity-v1", false);
analysisId = result.analysis.analysis_run_id;
firstGroup = result.groups.match_group_id(1);
secondGroup = result.groups.match_group_id(2);
memberId = result.group_members.detection_id(1);
verifySqlFails(testCase, fixture.conn, "INSERT INTO match_group_members(" + ...
    "match_group_id,detection_id,member_role) VALUES(" + string(secondGroup) + ...
    "," + string(memberId) + ",'run_a')");
verifySqlFails(testCase, fixture.conn, "INSERT INTO match_group_members(" + ...
    "match_group_id,detection_id,member_role) VALUES(" + string(firstGroup) + ...
    ",1,'run_a')");
verifySqlFails(testCase, fixture.conn, "INSERT INTO consensus_events(" + ...
    "analysis_run_id,match_group_id,recording_id,start_time_s,end_time_s," + ...
    "derivation_method) VALUES(" + string(analysisId) + "," + ...
    string(firstGroup) + ",2,1,2,'illegal')");
consensusId = result.consensus_events.consensus_event_id(1);
nonmember = result.group_members.detection_id( ...
    result.group_members.component_ordinal == 2);
verifySqlFails(testCase, fixture.conn, "INSERT INTO consensus_event_members(" + ...
    "consensus_event_id,detection_id,member_role) VALUES(" + ...
    string(consensusId) + "," + string(nonmember(1)) + ",'run_a')");
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpTopologyFixture()
[fixture, cleanup] = setUpFixture();
intervalsA = [100 102; 200 204; 300 302; 302.01 304; ...
    400 403; 402 405; 500 501];
intervalsB = [100.2 101.8; 200 202; 202.01 204; 300 304; ...
    400 404; 401 405; 600 601];
for index = 1:height(intervalsA)
    insertDetection(fixture.conn, 3, 1, "topology-a-" + index, ...
        intervalsA(index, 1), intervalsA(index, 2));
end
for index = 1:height(intervalsB)
    insertDetection(fixture.conn, 5, 1, "topology-b-" + index, ...
        intervalsB(index, 1), intervalsB(index, 2));
end
end

function result = applyTopology(fixture, runKey, reverse)
if reverse
    pair = struct(run_a="other-1", run_b="ds-2");
else
    pair = struct(run_a="ds-2", run_b="other-1");
end
result = vawlume.matching.compare(fixture.conn, recordingRef(), pair, ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root, Apply=true);
end

function applyTopologyWithInducedFailure(fixture)
try
    applyTopology(fixture, "legacy-failure", false);
catch exception
    error("vawlume:matching:InducedDerivedFailure", ...
        "Induced derived-graph failure surfaced as: %s", exception.message);
end
error("vawlume:matching:InducedDerivedFailure", ...
    "The induced derived-graph failure did not abort.");
end

function values = componentMemberSets(result)
values = strings(height(result.groups), 1);
for index = 1:height(result.groups)
    ids = sort(result.group_members.detection_id( ...
        result.group_members.component_ordinal == ...
        result.groups.component_ordinal(index)));
    values(index) = strjoin(string(ids'), ",");
end
values = sort(values);
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "matching.sqlite");
conn = sqlite(char(dbPath), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'project-a','Project A')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path,filename) VALUES" + ...
    "(1,1,'recording_audio','audio/rec1.wav','audio/rec1.wav','rec1.wav')," + ...
    "(2,1,'recording_audio','audio/rec2.wav','audio/rec2.wav','rec2.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'REC1'),(2,1,2,'REC2')");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'deepsqueak','DeepSqueak'),(2,'mupet','MUPET')," + ...
    "(3,'other','Other Extractor')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'3.2.1'),(2,2,'2.1'),(3,3,'1.0')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key,status) VALUES" + ...
    "(1,1,1,'ds-1','imported'),(2,1,2,'mupet-1','imported')," + ...
    "(3,1,1,'ds-2','imported'),(4,1,2,'mupet-rec2','imported')," + ...
    "(5,1,3,'other-1','imported')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id," + ...
    "input_role) VALUES(1,1,'source_audio'),(2,1,'source_audio')," + ...
    "(3,1,'source_audio'),(4,2,'source_audio'),(5,1,'source_audio')");

insertDetection(conn, 1, 1, "ds-1", 10.000, 10.050);
insertDetection(conn, 1, 1, "ds-2", 20.000, 20.040);
insertDetection(conn, 1, 1, "ds-3", 40.000, 40.100);
insertDetection(conn, 2, 1, "mupet-1", 10.004, 10.052);
insertDetection(conn, 2, 1, "mupet-2", 30.000, 30.035);
insertDetection(conn, 2, 1, "mupet-3", 40.002, 40.045);
insertDetection(conn, 2, 1, "mupet-4", 40.052, 40.098);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);
end

function [fixture, cleanup] = setUpImportedFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "imported-matching.sqlite");
conn = sqlite(char(dbPath), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('imported-project','Imported Project')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri," + ...
    "relative_path,filename) VALUES(1,'recording_audio','audio/REC_A.wav'," + ...
    "'audio/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,'REC_A')");

dsRoot = fullfile(scratch, "deepsqueak");
mupetRoot = fullfile(scratch, "mupet");
dsPath = fullfile(dsRoot, "exports", "REC_A_Stats.xlsx");
mupetPath = fullfile(mupetRoot, "audio", "set", "CSV", "REC_A.csv");
configPath = fullfile(mupetRoot, "config.csv");
writeCells(dsPath, importedDeepSqueakCells());
writeCells(mupetPath, importedMupetCells());
writeText(configPath, strjoin(importedMupetConfigLines(), newline) + newline);
ref = struct(project_key="imported-project", ...
    source_relative_path="audio/REC_A.wav");
vawlume.ingest.deepsqueak(conn, dsPath, ref, ...
    struct(run_key="ds-imported", extractor_version="3.2.1"), ...
    RepoRoot=repoRoot, ArtifactRoot=dsRoot, Apply=true);
vawlume.ingest.mupet(conn, mupetPath, ref, ...
    struct(run_key="mupet-imported", extractor_version="2.1", ...
        settings=struct(config_path=configPath)), ...
    RepoRoot=repoRoot, ArtifactRoot=mupetRoot, Apply=true);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);
end

function insertDetection(conn, runId, recordingId, nativeId, startS, endS)
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES(" + ...
    string(runId) + "," + string(recordingId) + "," + sqlText(nativeId) + ...
    "," + string(startS) + "," + string(endS) + ...
    ",'profile_selected_event_geometry')");
end

function result = planNominal(fixture, runKey)
result = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root);
end

function result = applyNominal(fixture, runKey)
result = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root, Apply=true);
end

function ref = recordingRef()
ref = struct(recording_id=1);
end

function pair = nominalPair()
pair = struct(run_a="ds-1", run_b="mupet-1");
end

function path = writeSpecVariant(fixture, name, oldValues, newValues)
text = string(fileread(fullfile(fixture.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json")));
for index = 1:numel(oldValues)
    text = replace(text, string(oldValues{index}), string(newValues{index}));
end
path = fullfile(fixture.scratch, name);
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function cells = importedDeepSqueakCells()
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
source = 'C:\deepsqueak\detections\REC_A_deepsqueak.mat';
cells = [
    headers
    {source, 1, '22kHz-Call', 1, .9134, 10, 10.05, .05, ...
        62.4, 45.1, 80.2, 35.1, 3.2, -120.5, 1.12, -71.4, .78, 63}
    {source, 2, 'USV', 1, .8021, 20, 20.04, .04, ...
        61, 50, 72, 22, 2.1, 15, 1.05, -70.1, .81, 61.5}
    {source, 3, 'Noise', 0, .2107, 40, 40.1, .1, ...
        63.5, 42, 84, 42, 4.4, -8.25, 1.4, -69.3, .69, 64.2}
    ];
end

function cells = importedMupetCells()
headers = {'Syllable number', 'Syllable start time (sec)', ...
    'Syllable end time (sec)', 'inter-syllable interval (sec)', ...
    'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', ...
    'maximum frequency (kHz)', 'mean frequency (kHz)', ...
    'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
cells = [
    headers
    {1, 10.004, 10.052, 19.948, 48, 45, 62, 44.5, 80, 62, 35.5, 12.5, -18}
    {2, 30, 30.035, 10.002, 34.7, 46, 59, 50.5, 72.5, 61, 22, 11.5, -19}
    {3, 40.002, 40.045, .007, 42.6, 47, 61, 42.5, 84.5, 63, 42, 10.5, -20}
    {4, 40.052, 40.098, 'NA', 45.8, 48, 62, 43, 83, 62.5, 40, 9.5, -21}
    ];
end

function lines = importedMupetConfigLines()
lines = ["noise-reduction,5"; "minimum-syllable-duration,008"; ...
    "maximum-syllable-duration,200"; "minimum-syllable-total-energy,-15"; ...
    "minimum-syllable-peak-amplitude,-25"; "minimum-syllable-distance,5"; ...
    "sample-frequency,250000"; "minimum-usv-frequency,30000"; ...
    "maximum-usv-frequency,120000"; "number-filterbank-filters,64"; ...
    "filterbank-type,1"];
end

function writeCells(path, cells)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
writecell(cells, path);
end

function writeText(path, value)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", value);
delete(cleaner);
end

function applyWithInducedFailure(fixture)
try
    applyNominal(fixture, "matching-v1");
catch exception
    error("vawlume:matching:InducedApplyFailure", ...
        "Induced matching failure surfaced as: %s", exception.message);
end
error("vawlume:matching:InducedApplyFailure", ...
    "The induced matching failure did not abort.");
end

function dropTrigger(conn)
try
    execute(conn, "DROP TRIGGER IF EXISTS trg_matching_failure");
catch
end
end

function dropNamedTrigger(conn, name)
try
    execute(conn, "DROP TRIGGER IF EXISTS " + name);
catch
end
end

function verifySqlFails(testCase, conn, sql)
failed = false;
try
    execute(conn, sql);
catch
    failed = true;
end
verifyTrue(testCase, failed, "Expected SQL statement to fail: " + sql);
end

function counts = matchingCounts(conn)
names = ["config_profiles", "config_profile_versions", "analysis_runs", ...
    "analysis_run_profiles", "analysis_run_extraction_inputs", "candidate_pairs", ...
    "match_groups", "match_group_members", "consensus_events", ...
    "consensus_event_members"];
counts = struct();
for name = names
    counts.(name) = countOf(conn, name);
end
end

function candidates = bruteForceCandidates(conn, runAId, runBId, minIou)
runA = fetch(conn, "SELECT detection_id,start_time_s,end_time_s," + ...
    "end_time_s-start_time_s AS duration_s FROM detections " + ...
    "WHERE extraction_run_id=" + string(runAId) + " ORDER BY detection_id");
runB = fetch(conn, "SELECT detection_id,start_time_s,end_time_s," + ...
    "end_time_s-start_time_s AS duration_s FROM detections " + ...
    "WHERE extraction_run_id=" + string(runBId) + " ORDER BY detection_id");
records = struct(run_a_detection_id={}, run_b_detection_id={}, ...
    temporal_overlap_s={}, temporal_iou={}, onset_difference_s={}, ...
    offset_difference_s={}, duration_difference_s={});
for aIndex = 1:height(runA)
    for bIndex = 1:height(runB)
        overlap = max(0, min(runA.end_time_s(aIndex), runB.end_time_s(bIndex)) - ...
            max(runA.start_time_s(aIndex), runB.start_time_s(bIndex)));
        union = max(runA.end_time_s(aIndex), runB.end_time_s(bIndex)) - ...
            min(runA.start_time_s(aIndex), runB.start_time_s(bIndex));
        iou = overlap / union;
        if overlap <= 0 || iou < minIou, continue, end
        record = struct( ...
            run_a_detection_id=double(runA.detection_id(aIndex)), ...
            run_b_detection_id=double(runB.detection_id(bIndex)), ...
            temporal_overlap_s=overlap, temporal_iou=iou, ...
            onset_difference_s=runB.start_time_s(bIndex) - runA.start_time_s(aIndex), ...
            offset_difference_s=runB.end_time_s(bIndex) - runA.end_time_s(aIndex), ...
            duration_difference_s=runB.duration_s(bIndex) - runA.duration_s(aIndex));
        records(end + 1, 1) = record; %#ok<AGROW>
    end
end
candidates = sortrows(struct2table(records, "AsArray", true), ...
    ["run_a_detection_id", "run_b_detection_id"]);
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function value = countWhere(conn, tableName, predicate)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName + ...
    " WHERE " + predicate);
value = double(rows.n(1));
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end

function setAutoCommit(conn, value)
try
    conn.AutoCommit = value;
catch
end
end

function tearDown(conn, scratch, repoRoot)
try close(conn); catch; end
if isfolder(scratch), rmdir(scratch, "s"); end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
