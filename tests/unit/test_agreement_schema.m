function tests = test_agreement_schema
%TEST_AGREEMENT_SCHEMA Arbitrary-N extractor-agreement relational surfaces.
%
% The agreement layer is derived: it composes the exact candidate edges of two or
% more pairwise analyses into components over native detections. These tests hold
% that layer to the contract it was added under.
%
% Exact edges are the stored authority. Support counts, fractions, patterns such
% as "2 of 3", and agreement labels are views over those edges and are asserted
% here to be absent from the schema rather than merely unused.
%
% Membership is never gated on feature support. A group whose members share no
% comparable non-timing feature, or whose pairwise groups are only
% temporally_matched, is a real observation about the extractors; these tests
% insert exactly those cases and require them to be accepted.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------------ schema shape ---

function testSchemaVersionAndAgreementObjectsExist(testCase)
[fixture, cleanup] = setUpSchema(); %#ok<ASGLU>
conn = fixture.conn;

verifyEqual(testCase, textOf(conn, "SELECT schema_version FROM schema_info"), "0.7-draft");
verifyEqual(testCase, numberOf(conn, "PRAGMA user_version"), 7);

for name = ["analysis_run_sources", "agreement_groups", ...
        "agreement_group_members", "agreement_supporting_edges"]
    verifyTrue(testCase, objectExists(conn, "table", name), name);
end
verifyTrue(testCase, objectExists(conn, "view", "v_feature_relationship_endpoints"));
for name = ["trg_analysis_run_source_project_scope", ...
        "trg_agreement_group_run_scope", "trg_agreement_member_recording", ...
        "trg_agreement_member_analysis_partition", ...
        "trg_agreement_supporting_edge_scope"]
    verifyTrue(testCase, objectExists(conn, "trigger", name), name);
end
for name = ["idx_analysis_run_sources_source", "idx_agreement_groups_recording", ...
        "idx_agreement_members_detection", ...
        "idx_agreement_supporting_edges_candidate"]
    verifyTrue(testCase, objectExists(conn, "index", name), name);
end

% The stored agreement columns are identity and provenance only. Every summary
% quantity a reader might want is derivable from the members, the edges, the
% declared inputs, and feature_relationships, so none of them is a column.
verifyEqual(testCase, columnsOf(conn, "agreement_groups"), [ ...
    "agreement_group_id"; "analysis_run_id"; "recording_id"; "group_key"; ...
    "derivation_method"; "notes"]);
verifyEqual(testCase, columnsOf(conn, "agreement_group_members"), [ ...
    "agreement_group_id"; "detection_id"; "member_role"]);
verifyEqual(testCase, columnsOf(conn, "agreement_supporting_edges"), [ ...
    "agreement_supporting_edge_id"; "agreement_group_id"; ...
    "candidate_pair_id"; "notes"]);
verifyEqual(testCase, columnsOf(conn, "analysis_run_sources"), [ ...
    "analysis_run_id"; "source_analysis_run_id"; "dependency_role"; "notes"]);

% The pairwise primitives are untouched by this pass.
verifyEqual(testCase, columnsOf(conn, "candidate_pairs"), [ ...
    "candidate_pair_id"; "analysis_run_id"; "recording_id"; "detection_a_id"; ...
    "detection_b_id"; "temporal_overlap_s"; "temporal_iou"; ...
    "onset_difference_s"; "offset_difference_s"; "duration_difference_s"; ...
    "candidate_score"; "candidate_status"; "details_json"]);
verifyEqual(testCase, columnsOf(conn, "match_groups"), [ ...
    "match_group_id"; "analysis_run_id"; "recording_id"; "match_type"; ...
    "ambiguity_status"; "match_score"; "notes"]);

clear cleanup
end

function testNoIntrinsicFeatureSupportColumnWasAdded(testCase)
[fixture, cleanup] = setUpSchema(); %#ok<ASGLU>

% How much cross-extractor support a native feature has depends on which
% extractor versions are compared, so it cannot be a property of the feature.
% The relationship graph stays the only authority.
verifyEqual(testCase, columnsOf(fixture.conn, "extractor_features"), [ ...
    "extractor_feature_id"; "extractor_version_id"; "native_name"; ...
    "native_unit"; "value_type"; "native_definition"; "source_artifact_type"; ...
    "derivation_stage"; "measurement_method"; "operational_variant"; ...
    "equivalence_class"; "source_reference"; "notes"]);
verifyEqual(testCase, columnsOf(fixture.conn, "feature_relationships"), [ ...
    "feature_relationship_id"; "feature_a_id"; "feature_b_id"; ...
    "relationship_type"; "comparison_method"; "unit_normalization"; ...
    "consilience_eligible"; "default_role"; "justification"; "source_reference"]);

clear cleanup
end

% ---------------------------------------------------------------- lineage ---

function testMultiSourceLineageIsRepresentableAndConstrained(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% The claim parent_analysis_run_id cannot make: one derived analysis over three
% pairwise analyses, with no single parent among them.
sources = fetch(conn, "SELECT source_analysis_run_id, dependency_role " + ...
    "FROM analysis_run_sources WHERE analysis_run_id = " + string(fixture.agreement_run) + ...
    " ORDER BY source_analysis_run_id");
verifyEqual(testCase, height(sources), 3);
verifyEqual(testCase, double(sources.source_analysis_run_id), ...
    [fixture.pair_ds_mupet; fixture.pair_ds_usvseg; fixture.pair_mupet_usvseg]);
verifyEqual(testCase, unique(string(sources.dependency_role)), "pairwise_source");
verifyEqual(testCase, numberOf(conn, "SELECT IFNULL(parent_analysis_run_id, -1) AS n " + ...
    "FROM analysis_runs WHERE analysis_run_id = " + string(fixture.agreement_run)), -1);

verifySqlFails(testCase, conn, sourceInsert(fixture.agreement_run, fixture.agreement_run));
verifySqlFails(testCase, conn, sourceInsert(fixture.agreement_run, fixture.pair_ds_mupet));
verifySqlFails(testCase, conn, sourceInsert(fixture.other_project_run, fixture.pair_ds_mupet));

clear cleanup
end

% ------------------------------------------------------- groups and members ---

function testAgreementGroupRequiresItsOwnRunTypeAndProjectRecording(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

verifyEqual(testCase, textOf(conn, "SELECT run_type FROM analysis_runs " + ...
    "WHERE analysis_run_id = " + string(fixture.agreement_run)), ...
    "multi_extractor_agreement");

% An agreement group cannot be grafted onto a pairwise matching analysis, which
% would quietly turn a two-run partition into something else.
verifySqlFails(testCase, conn, groupInsert(fixture.pair_ds_mupet, fixture.recording, "grafted"));
verifySqlFails(testCase, conn, groupInsert(fixture.other_project_run, fixture.recording, "wrong_project"));
verifySqlFails(testCase, conn, groupInsert(fixture.agreement_run, fixture.recording, "convergent"));

clear cleanup
end

function testMembersReferenceNativeDetectionsUnderStrictScope(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

members = fetch(conn, "SELECT vc.extraction_run_key, vc.native_event_id " + ...
    "FROM agreement_group_members agm " + ...
    "JOIN v_detection_core vc ON vc.detection_id = agm.detection_id " + ...
    "WHERE agm.agreement_group_id = " + string(fixture.convergent_group) + ...
    " ORDER BY vc.extraction_run_key");
verifyEqual(testCase, string(members.extraction_run_key), ["ds1"; "mu1"; "uv1"]);
verifyEqual(testCase, string(members.native_event_id), ["d1"; "m1"; "u1"]);

second = insertGroup(conn, fixture.agreement_run, fixture.recording, "second");
% One detection, one group per agreement run.
verifySqlFails(testCase, conn, memberInsert(second, fixture.detections.ds_match));
% Only detections from runs this agreement analysis declared as inputs.
verifySqlFails(testCase, conn, memberInsert(second, fixture.detections.undeclared));
% One recording per group.
verifySqlFails(testCase, conn, memberInsert(second, fixture.detections.other_recording));

% The same detection may participate in a different agreement run. Two
% derivations over the same evidence are separate results, not a conflict.
otherRun = insertAgreementRun(conn, fixture.project, "agree_2");
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
    "extraction_run_id,input_role) VALUES(" + string(otherRun) + "," + ...
    string(fixture.runs.ds) + ",'agreement_input')");
otherGroup = insertGroup(conn, otherRun, fixture.recording, "convergent");
execute(conn, memberInsert(otherGroup, fixture.detections.ds_match));
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM agreement_group_members " + ...
    "WHERE detection_id = " + string(fixture.detections.ds_match)), 2);

clear cleanup
end

% ------------------------------------------------------- exact support edges ---

function testSupportingEdgesCiteExactCandidatePairs(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% The stored authority is the candidate_pair_id, and everything a summary would
% have flattened is still reachable from it.
edges = fetch(conn, "SELECT ar.run_key AS source_analysis, cp.temporal_iou, " + ...
    "a.extraction_run_key || '#' || a.native_event_id || '~' || " + ...
    "b.extraction_run_key || '#' || b.native_event_id AS edge " + ...
    "FROM agreement_supporting_edges ase " + ...
    "JOIN candidate_pairs cp ON cp.candidate_pair_id = ase.candidate_pair_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "JOIN v_detection_core a ON a.detection_id = cp.detection_a_id " + ...
    "JOIN v_detection_core b ON b.detection_id = cp.detection_b_id " + ...
    "WHERE ase.agreement_group_id = " + string(fixture.convergent_group) + ...
    " ORDER BY ar.run_key");
verifyEqual(testCase, height(edges), 3);
verifyEqual(testCase, string(edges.source_analysis), ...
    ["m_ds_mupet"; "m_ds_usvseg"; "m_mupet_usvseg"]);
verifyEqual(testCase, string(edges.edge), [ ...
    "ds1#d1~mu1#m1"; "ds1#d1~uv1#u1"; "mu1#m1~uv1#u1"]);
verifyEqual(testCase, double(edges.temporal_iou), [0.88; 0.94; 0.90], AbsTol=1e-12);

% One edge cited once per group.
verifySqlFails(testCase, conn, edgeInsert(fixture.convergent_group, fixture.candidates.ds_mupet));

% An edge from an analysis this derivation never declared as a source.
verifySqlFails(testCase, conn, edgeInsert(fixture.convergent_group, fixture.candidates.undeclared));

% An edge whose endpoints are not both members of the group it claims to support.
partial = insertGroup(conn, fixture.agreement_run, fixture.recording, "partial");
execute(conn, memberInsert(partial, fixture.detections.ds_only));
verifySqlFails(testCase, conn, edgeInsert(partial, fixture.candidates.ds_mupet));

clear cleanup
end

function testAgreementMembershipIsNotGatedOnFeatureSupport(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% The DeepSqueak/USVSEG and MUPET/USVSEG pairwise groups here are only
% temporally_matched, which is what the current categorical rule returns when
% too few eligible non-timing feature comparisons exist. The DeepSqueak/MUPET
% group carries no consilience assessment at all. All three edges already
% support the convergent group, so nothing in this layer consulted either.
statuses = fetch(conn, "SELECT ar.run_key, IFNULL(ca.status,'no_assessment') AS status " + ...
    "FROM agreement_supporting_edges ase " + ...
    "JOIN candidate_pairs cp ON cp.candidate_pair_id = ase.candidate_pair_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "LEFT JOIN (" + pairwiseGroupSubquery() + ") mg " + ...
    "ON mg.detection_id = cp.detection_a_id AND mg.analysis_run_id = cp.analysis_run_id " + ...
    "LEFT JOIN consilience_assessments ca ON ca.match_group_id = mg.match_group_id " + ...
    "WHERE ase.agreement_group_id = " + string(fixture.convergent_group) + ...
    " ORDER BY ar.run_key");
verifyEqual(testCase, height(statuses), 3);
verifyEqual(testCase, string(statuses.status), ...
    ["no_assessment"; "temporally_matched"; "temporally_matched"]);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM consilience_assessments " + ...
    "WHERE status = 'matched_feature_supported'"), 0);

% A group of two detections whose only pairwise evidence is discrepant is still
% a group. Feature outcome is a queryable dimension, not an admission rule.
discrepant = insertGroup(conn, fixture.agreement_run, fixture.recording, "discrepant");
execute(conn, memberInsert(discrepant, fixture.detections.ds_only));
execute(conn, memberInsert(discrepant, fixture.detections.mupet_only));
execute(conn, edgeInsert(discrepant, fixture.candidates.ds_mupet_weak));
execute(conn, "INSERT INTO consilience_assessments(analysis_run_id,match_group_id," + ...
    "status) VALUES(" + string(fixture.pair_ds_mupet) + "," + ...
    string(fixture.weak_match_group) + ",'matched_feature_discrepant')");
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM agreement_supporting_edges " + ...
    "WHERE agreement_group_id = " + string(discrepant)), 1);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testTopologyAndProvenanceAreDerivableFromTheEdge(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% No second FK to match_group_id is stored because the pairwise group is unique
% per edge: a pairwise analysis assigns a detection to at most one group, and a
% candidate edge's endpoints are joined into the same component. One row per
% edge, and both endpoints resolve to the same group.
derived = fetch(conn, "SELECT ase.agreement_supporting_edge_id, ar.run_key, " + ...
    "IFNULL(ga.match_type,'no_group_materialized') AS topology, " + ...
    "IFNULL(ga.match_group_id, -1) AS group_a, IFNULL(gb.match_group_id, -1) AS group_b " + ...
    "FROM agreement_supporting_edges ase " + ...
    "JOIN candidate_pairs cp ON cp.candidate_pair_id = ase.candidate_pair_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "LEFT JOIN (" + pairwiseGroupSubquery() + ") ga " + ...
    "ON ga.detection_id = cp.detection_a_id AND ga.analysis_run_id = cp.analysis_run_id " + ...
    "LEFT JOIN (" + pairwiseGroupSubquery() + ") gb " + ...
    "ON gb.detection_id = cp.detection_b_id AND gb.analysis_run_id = cp.analysis_run_id " + ...
    "WHERE ase.agreement_group_id = " + string(fixture.convergent_group) + ...
    " ORDER BY ar.run_key");
verifyEqual(testCase, height(derived), 3);
verifyEqual(testCase, double(derived.group_a), double(derived.group_b));
verifyEqual(testCase, string(derived.topology), ...
    ["one_to_one"; "one_to_one"; "one_to_one"]);

% A candidate-only source analysis has no group to report. That is absence, not
% ambiguity, and it does not disqualify the edge.
candidateOnly = insertMatchingRun(conn, fixture.project, "m_candidate_only");
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
    "extraction_run_id,input_role) VALUES(" + string(candidateOnly) + "," + ...
    string(fixture.runs.ds) + ",'run_a'),(" + string(candidateOnly) + "," + ...
    string(fixture.runs.usvseg) + ",'run_b')");
edgeId = insertCandidatePair(conn, candidateOnly, fixture.recording, ...
    fixture.detections.ds_match, fixture.detections.usvseg_match, 0.94);
execute(conn, sourceInsert(fixture.agreement_run, candidateOnly));
execute(conn, edgeInsert(fixture.convergent_group, edgeId));
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM match_groups " + ...
    "WHERE analysis_run_id = " + string(candidateOnly)), 0);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM agreement_supporting_edges " + ...
    "WHERE agreement_group_id = " + string(fixture.convergent_group)), 4);
queryEdge = fetch(conn, "SELECT pairwise_topology_label, " + ...
    "IFNULL(pairwise_match_group_id,-1) AS pairwise_match_group_id " + ...
    "FROM v_agreement_supporting_edges WHERE candidate_pair_id=" + ...
    string(edgeId));
verifyEqual(testCase, string(queryEdge.pairwise_topology_label), ...
    "no_group_materialized");
verifyEqual(testCase, double(queryEdge.pairwise_match_group_id), -1);

clear cleanup
end

% -------------------------------------------------------- deletion behaviour ---

function testSourceEvidenceDeletionIsRestrictedAndDerivedDeletionCascades(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;
before = counts(conn);

% A derived agreement result must not silently outlive the pairwise evidence it
% was composed from, so the deletion is refused rather than cascading.
verifySqlFails(testCase, conn, "DELETE FROM candidate_pairs WHERE candidate_pair_id = " + ...
    string(fixture.candidates.ds_mupet));
verifySqlFails(testCase, conn, "DELETE FROM analysis_runs WHERE analysis_run_id = " + ...
    string(fixture.pair_ds_mupet));
verifySqlFails(testCase, conn, "DELETE FROM detections WHERE detection_id = " + ...
    string(fixture.detections.ds_match));
verifyEqual(testCase, counts(conn), before);

% Deleting the derivation removes the derived layer and nothing else.
execute(conn, "DELETE FROM analysis_runs WHERE analysis_run_id = " + ...
    string(fixture.agreement_run));
after = counts(conn);
verifyEqual(testCase, after.analysis_run_sources, 0);
verifyEqual(testCase, after.agreement_groups, 0);
verifyEqual(testCase, after.agreement_group_members, 0);
verifyEqual(testCase, after.agreement_supporting_edges, 0);
verifyEqual(testCase, after.candidate_pairs, before.candidate_pairs);
verifyEqual(testCase, after.detections, before.detections);
verifyEqual(testCase, after.match_groups, before.match_groups);

% With the derived result gone, the source evidence is deletable again.
execute(conn, "DELETE FROM analysis_runs WHERE analysis_run_id = " + ...
    string(fixture.pair_ds_mupet));
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM candidate_pairs"), ...
    before.candidate_pairs - 2);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testSingletonMemberDeletionIsRestrictedToo(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% A matched member is protected indirectly: the candidate pair joining it to its
% group restricts, so deleting the detection is refused by that edge. A
% singleton or extractor-unique member participates in no candidate pair and has
% no such indirect protection - and it is exactly the member the composition
% policy deliberately keeps. Without its own RESTRICT it would cascade away,
% leaving a group whose stored group_key still named it.
% A detection no other extractor corroborated, in a declared participating run.
% The fixture's ds_only and mupet_only overlap each other and so do carry a
% candidate pair; this one deliberately overlaps nothing.
unpaired = insertDetection(conn, 1, 1, "d_unpaired", 40.000, 40.040);
singleton = insertGroup(conn, fixture.agreement_run, 1, "extractor_unique");
execute(conn, memberInsert(singleton, unpaired));

% The premise this test depends on: nothing else protects this detection.
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM candidate_pairs " + ...
    "WHERE detection_a_id = " + string(unpaired) + ...
    " OR detection_b_id = " + string(unpaired)), 0);

before = counts(conn);
verifySqlFails(testCase, conn, "DELETE FROM detections WHERE detection_id = " + ...
    string(unpaired));
verifyEqual(testCase, counts(conn), before);

% Deleting the derivation still removes the derived layer and frees the
% detection, so the restriction protects a live result rather than pinning the
% row permanently.
execute(conn, "DELETE FROM analysis_runs WHERE analysis_run_id = " + ...
    string(fixture.agreement_run));
execute(conn, "DELETE FROM detections WHERE detection_id = " + string(unpaired));
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM agreement_groups"), 0);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function value = pairwiseGroupSubquery()
value = "SELECT mgm.detection_id, mg.analysis_run_id, mg.match_group_id, " + ...
    "mg.match_type FROM match_group_members mgm " + ...
    "JOIN match_groups mg ON mg.match_group_id = mgm.match_group_id";
end

function sql = sourceInsert(analysisRunId, sourceRunId)
sql = "INSERT INTO analysis_run_sources(analysis_run_id," + ...
    "source_analysis_run_id,dependency_role) VALUES(" + ...
    string(analysisRunId) + "," + string(sourceRunId) + ",'pairwise_source')";
end

function sql = groupInsert(analysisRunId, recordingId, groupKey)
sql = "INSERT INTO agreement_groups(analysis_run_id,recording_id,group_key," + ...
    "derivation_method) VALUES(" + string(analysisRunId) + "," + ...
    string(recordingId) + "," + sqlText(groupKey) + ",'connected_supporting_edges')";
end

function sql = memberInsert(groupId, detectionId)
sql = "INSERT INTO agreement_group_members(agreement_group_id,detection_id," + ...
    "member_role) VALUES(" + string(groupId) + "," + string(detectionId) + ",'member')";
end

function sql = edgeInsert(groupId, candidatePairId)
sql = "INSERT INTO agreement_supporting_edges(agreement_group_id," + ...
    "candidate_pair_id) VALUES(" + string(groupId) + "," + ...
    string(candidatePairId) + ")";
end

function id = insertGroup(conn, analysisRunId, recordingId, groupKey)
execute(conn, groupInsert(analysisRunId, recordingId, groupKey));
id = lastId(conn);
end

function id = insertAgreementRun(conn, projectId, runKey)
id = insertAnalysisRun(conn, projectId, "multi_extractor_agreement", runKey);
end

function id = insertMatchingRun(conn, projectId, runKey)
id = insertAnalysisRun(conn, projectId, "cross_extractor_matching", runKey);
end

function id = insertAnalysisRun(conn, projectId, runType, runKey)
execute(conn, "INSERT INTO analysis_runs(project_id,run_type,run_key,status) " + ...
    "VALUES(" + string(projectId) + "," + sqlText(runType) + "," + ...
    sqlText(runKey) + ",'completed')");
id = lastId(conn);
end

function id = insertCandidatePair(conn, analysisRunId, recordingId, first, second, iou)
execute(conn, "INSERT INTO candidate_pairs(analysis_run_id,recording_id," + ...
    "detection_a_id,detection_b_id,temporal_iou,candidate_score," + ...
    "candidate_status) VALUES(" + string(analysisRunId) + "," + ...
    string(recordingId) + "," + string(min(first, second)) + "," + ...
    string(max(first, second)) + "," + string(iou) + "," + string(iou) + ...
    ",'eligible')");
id = lastId(conn);
end

function id = insertDetection(conn, runId, recordingId, nativeEventId, startS, endS)
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES(" + ...
    string(runId) + "," + string(recordingId) + "," + sqlText(nativeEventId) + ...
    "," + string(startS) + "," + string(endS) + ...
    ",'profile_selected_event_geometry')");
id = lastId(conn);
end

function value = counts(conn)
names = ["analysis_run_sources", "agreement_groups", "agreement_group_members", ...
    "agreement_supporting_edges", "candidate_pairs", "match_groups", "detections"];
value = struct();
for name = names
    value.(name) = numberOf(conn, "SELECT COUNT(*) AS n FROM " + name);
end
end

function [fixture, cleanup] = setUpSchema()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, dbFile, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
fixture = struct(conn=conn, repo_root=repoRoot, db_file=dbFile);
end

function [fixture, cleanup] = setUpWorld()
%SETUPWORLD One recording, three extractors, three pairwise analyses, and one
% arbitrary-N agreement derivation composed from all three.
[fixture, cleanup] = setUpSchema();
conn = fixture.conn;

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('agreement_project','Agreement project'),('other_project','Other project')");
fixture.project = 1;
fixture.other_project = 2;
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri," + ...
    "relative_path,filename) VALUES(1,'recording_audio','a.wav','a.wav','a.wav')," + ...
    "(1,'recording_audio','b.wav','b.wav','b.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,'REC_A'),(1,2,'REC_B')");
fixture.recording = 1;
fixture.other_recording = 2;
execute(conn, "INSERT INTO extractors(extractor_key,extractor_name) " + ...
    "VALUES('deepsqueak','DeepSqueak'),('mupet','MUPET'),('usvseg','USVSEG')");
execute(conn, "INSERT INTO extractor_versions(extractor_id,version_label) " + ...
    "VALUES(1,'3.2.x'),(2,'2.1'),(3,'0.9r2')");
execute(conn, "INSERT INTO extraction_runs(project_id,extractor_version_id," + ...
    "run_key,status) VALUES(1,1,'ds1','imported'),(1,2,'mu1','imported')," + ...
    "(1,3,'uv1','imported'),(1,1,'ds_other_recording','imported')," + ...
    "(1,2,'mu_undeclared','imported')");
fixture.runs = struct(ds=1, mupet=2, usvseg=3, other_recording=4, undeclared=5);
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id," + ...
    "input_role) VALUES(1,1,'source_audio'),(2,1,'source_audio')," + ...
    "(3,1,'source_audio'),(4,2,'source_audio'),(5,1,'source_audio')");

detections = struct();
detections.ds_match = insertDetection(conn, 1, 1, "d1", 10.000, 10.050);
detections.ds_only = insertDetection(conn, 1, 1, "d2", 20.000, 20.040);
detections.mupet_match = insertDetection(conn, 2, 1, "m1", 10.004, 10.052);
detections.mupet_only = insertDetection(conn, 2, 1, "m2", 20.001, 20.041);
detections.usvseg_match = insertDetection(conn, 3, 1, "u1", 10.002, 10.049);
detections.other_recording = insertDetection(conn, 4, 2, "d1", 10.000, 10.050);
detections.undeclared = insertDetection(conn, 5, 1, "x1", 30.000, 30.040);
fixture.detections = detections;

fixture.pair_ds_mupet = insertMatchingRun(conn, 1, "m_ds_mupet");
fixture.pair_ds_usvseg = insertMatchingRun(conn, 1, "m_ds_usvseg");
fixture.pair_mupet_usvseg = insertMatchingRun(conn, 1, "m_mupet_usvseg");
fixture.undeclared_pair = insertMatchingRun(conn, 1, "m_undeclared");
fixture.agreement_run = insertAgreementRun(conn, 1, "agree_1");
fixture.other_project_run = insertAgreementRun(conn, 2, "agree_other_project");

declareInputs(conn, fixture.pair_ds_mupet, [1 2], ["run_a", "run_b"]);
declareInputs(conn, fixture.pair_ds_usvseg, [1 3], ["run_a", "run_b"]);
declareInputs(conn, fixture.pair_mupet_usvseg, [2 3], ["run_a", "run_b"]);
declareInputs(conn, fixture.undeclared_pair, [1 5], ["run_a", "run_b"]);
declareInputs(conn, fixture.agreement_run, [1 2 3], ...
    repmat("agreement_input", 1, 3));

candidates = struct();
candidates.ds_mupet = insertCandidatePair(conn, fixture.pair_ds_mupet, 1, ...
    detections.ds_match, detections.mupet_match, 0.88);
candidates.ds_mupet_weak = insertCandidatePair(conn, fixture.pair_ds_mupet, 1, ...
    detections.ds_only, detections.mupet_only, 0.95);
candidates.ds_usvseg = insertCandidatePair(conn, fixture.pair_ds_usvseg, 1, ...
    detections.ds_match, detections.usvseg_match, 0.94);
candidates.mupet_usvseg = insertCandidatePair(conn, fixture.pair_mupet_usvseg, 1, ...
    detections.mupet_match, detections.usvseg_match, 0.90);
candidates.undeclared = insertCandidatePair(conn, fixture.undeclared_pair, 1, ...
    detections.ds_match, detections.undeclared, 0.50);
fixture.candidates = candidates;

% Pairwise groups for two of the three pairs, plus the weak DeepSqueak/MUPET
% component. The DeepSqueak/MUPET convergent component is deliberately left
% without a consilience assessment.
fixture.weak_match_group = insertMatchGroup(conn, fixture.pair_ds_mupet, 1, ...
    [detections.ds_only, detections.mupet_only], ["run_a", "run_b"]);
convergentDsMupet = insertMatchGroup(conn, fixture.pair_ds_mupet, 1, ...
    [detections.ds_match, detections.mupet_match], ["run_a", "run_b"]);
dsUsvsegGroup = insertMatchGroup(conn, fixture.pair_ds_usvseg, 1, ...
    [detections.ds_match, detections.usvseg_match], ["run_a", "run_b"]);
mupetUsvsegGroup = insertMatchGroup(conn, fixture.pair_mupet_usvseg, 1, ...
    [detections.mupet_match, detections.usvseg_match], ["run_a", "run_b"]);
fixture.groups = struct(ds_mupet=convergentDsMupet, ...
    ds_usvseg=dsUsvsegGroup, mupet_usvseg=mupetUsvsegGroup);
for groupId = [dsUsvsegGroup, mupetUsvsegGroup]
    analysisRunId = numberOf(conn, "SELECT analysis_run_id AS n FROM match_groups " + ...
        "WHERE match_group_id = " + string(groupId));
    execute(conn, "INSERT INTO consilience_assessments(analysis_run_id," + ...
        "match_group_id,status) VALUES(" + string(analysisRunId) + "," + ...
        string(groupId) + ",'temporally_matched')");
end

execute(conn, sourceInsert(fixture.agreement_run, fixture.pair_ds_mupet));
execute(conn, sourceInsert(fixture.agreement_run, fixture.pair_ds_usvseg));
execute(conn, sourceInsert(fixture.agreement_run, fixture.pair_mupet_usvseg));

fixture.convergent_group = insertGroup(conn, fixture.agreement_run, 1, "convergent");
for detectionId = [detections.ds_match, detections.mupet_match, detections.usvseg_match]
    execute(conn, memberInsert(fixture.convergent_group, detectionId));
end
for candidateId = [candidates.ds_mupet, candidates.ds_usvseg, candidates.mupet_usvseg]
    execute(conn, edgeInsert(fixture.convergent_group, candidateId));
end
end

function declareInputs(conn, analysisRunId, extractionRunIds, roles)
for index = 1:numel(extractionRunIds)
    execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
        "extraction_run_id,input_role) VALUES(" + string(analysisRunId) + "," + ...
        string(extractionRunIds(index)) + "," + sqlText(roles(index)) + ")");
end
end

function id = insertMatchGroup(conn, analysisRunId, recordingId, detectionIds, roles)
execute(conn, "INSERT INTO match_groups(analysis_run_id,recording_id," + ...
    "match_type,ambiguity_status) VALUES(" + string(analysisRunId) + "," + ...
    string(recordingId) + ",'one_to_one','unambiguous')");
id = lastId(conn);
for index = 1:numel(detectionIds)
    execute(conn, "INSERT INTO match_group_members(match_group_id,detection_id," + ...
        "member_role) VALUES(" + string(id) + "," + string(detectionIds(index)) + ...
        "," + sqlText(roles(index)) + ")");
end
end

function value = lastId(conn)
rows = fetch(conn, "SELECT last_insert_rowid() AS n");
value = double(rows.n(1));
end

function value = numberOf(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function value = textOf(conn, sql)
rows = fetch(conn, sql);
column = rows.(rows.Properties.VariableNames{1});
if iscell(column)
    value = string(column{1});
else
    value = string(column(1));
end
end

function value = objectExists(conn, objectType, name)
value = numberOf(conn, "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = " + ...
    sqlText(objectType) + " AND name = " + sqlText(name)) == 1;
end

function value = columnsOf(conn, tableName)
rows = fetch(conn, "SELECT name FROM pragma_table_info(" + sqlText(tableName) + ")");
value = string(rows.name);
value = value(:);
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

function tearDown(conn, dbFile, repoRoot)
try
    close(conn);
catch
end
for suffix = ["", "-journal", "-wal", "-shm"]
    path = dbFile + suffix;
    if isfile(path)
        delete(path);
    end
end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
