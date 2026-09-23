function tests = test_caller_attribution_schema
%TEST_CALLER_ATTRIBUTION_SCHEMA Constraints of the Phase 4 attribution slice.
%
% Every negative case here asserts a REFUSAL, and each was verified to fire for
% its own reason rather than by tripping an unrelated constraint first. Three of
% them originally did not: a BEFORE trigger fires ahead of a row's CHECK
% constraints in SQLite, so a scope guard masked the constraint that actually
% described the problem. The guard was narrowed; these tests are what would catch
% that happening again.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repoRoot = repoRoot;
end

function setup(testCase)
file = string(tempname) + ".sqlite";
conn = sqlite(char(file), "create");
vawlume.db.applySchema(conn, fullfile(testCase.TestData.repoRoot, "schema", "schema.sql"));
seedFixture(conn);
testCase.TestData.conn = conn;
testCase.TestData.file = file;
end

function teardown(testCase)
close(testCase.TestData.conn);
if isfile(testCase.TestData.file), delete(testCase.TestData.file); end
end

% --- version -------------------------------------------------------------

function testSchemaVersionIsCurrent(testCase)
conn = testCase.TestData.conn;
version = fetch(conn, "SELECT schema_version FROM schema_info");
verifyEqual(testCase, string(version{1,1}), "0.11-draft");
userVersion = fetch(conn, "PRAGMA user_version");
verifyEqual(testCase, double(userVersion{1,1}), 11);
end

% --- targets name exactly one event set ----------------------------------

function testTargetNamingTwoEventSetsIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_targets(attribution_run_id,detection_id,consensus_event_id) " + ...
    "VALUES(1,1,1)", "detection_id IS NOT NULL");
end

function testTargetNamingNoEventSetIsRefused(testCase)
% Must be refused by the exclusive CHECK, not by a scope trigger. The message
% is asserted because a row naming no event has no recording to mismatch, and a
% recording-mismatch error here would be actively misleading.
verifyRefused(testCase, ...
    "INSERT INTO attribution_targets(attribution_run_id) VALUES(1)", ...
    "detection_id IS NOT NULL");
end

function testAgreementGroupTargetMustDeclareItsExtent(testCase)
% An agreement group has no intrinsic interval, so targeting one without saying
% which extent is meant leaves the target's own timespan undefined.
verifyRefused(testCase, ...
    "INSERT INTO attribution_targets(attribution_run_id,agreement_group_id) VALUES(1,1)", ...
    "agreement_extent_method");
end

function testNonGroupTargetMayNotDeclareAnExtent(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_targets(attribution_run_id,detection_id,agreement_extent_method) " + ...
    "VALUES(1,1,'union_boundary_of_members')", "agreement_extent_method");
end

function testAgreementGroupTargetWithAnExtentIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_targets(attribution_run_id,agreement_group_id," + ...
    "agreement_extent_method) VALUES(1,1,'intersection_boundary_of_members')");
stored = fetch(conn, "SELECT agreement_extent_method AS m FROM attribution_targets " + ...
    "WHERE agreement_group_id IS NOT NULL");
verifyEqual(testCase, string(stored.m(1)), "intersection_boundary_of_members");
end

% --- a stored number declares its semantics ------------------------------

function testScoreWithoutSemanticsIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_candidates(attribution_target_id,entity_id,score) VALUES(1,1,0.8)", ...
    "score_semantics");
end

function testProbabilityWithoutSemanticsIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_candidates(attribution_target_id,entity_id,probability) VALUES(1,1,0.8)", ...
    "probability_semantics");
end

function testProbabilityOutsideUnitIntervalIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_candidates(attribution_target_id,entity_id,probability," + ...
    "probability_semantics) VALUES(1,1,1.4,'s')", "probability >= 0");
end

function testScoreIsNotBoundedTheWayProbabilityIs(testCase)
% A score is somebody else's scale and VAWLUME does not know its range.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_candidates(attribution_target_id,entity_id,score," + ...
    "score_semantics) VALUES(1,1,42.7,'external system raw margin, uncalibrated')");
stored = fetch(conn, "SELECT score FROM attribution_candidates WHERE entity_id=1");
verifyEqual(testCase, double(stored.score(1)), 42.7, AbsTol=1e-12);
end

% --- several candidates per target is structural -------------------------

function testSeveralCandidatesCoexistForOneTarget(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_candidates(attribution_target_id,entity_id,score," + ...
    "score_semantics,candidate_rank) VALUES" + ...
    "(1,1,0.8,'external posterior-like score, uncalibrated',1)," + ...
    "(1,2,0.6,'external posterior-like score, uncalibrated',2)," + ...
    "(1,3,0.1,'external posterior-like score, uncalibrated',3)");
rows = fetch(conn, "SELECT entity_id, score FROM attribution_candidates " + ...
    "WHERE attribution_target_id=1 ORDER BY entity_id");
% Read all three back rather than asserting a count: the claim is that none is
% privileged, and a count would pass even if two were unreachable.
verifyEqual(testCase, double(rows.entity_id)', [1 2 3]);
verifyEqual(testCase, double(rows.score)', [0.8 0.6 0.1], AbsTol=1e-12);
end

function testCandidateEntityMustBeLinkedToTheRecording(testCase)
% An imported label naming an animal that was never in the recording is a data
% problem the import path must surface, not a row to create quietly.
verifyRefused(testCase, ...
    "INSERT INTO attribution_candidates(attribution_target_id,entity_id) VALUES(1,4)", ...
    "not an entity linked to this recording");
end

% --- decisions ------------------------------------------------------------

function testDecisionRequiresItsPolicy(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_decisions(attribution_target_id,decision_status) " + ...
    "VALUES(1,'unassigned')", "policy_profile_version_id");
end

function testAppliedThresholdRequiresItsSemantics(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_decisions(attribution_target_id,decision_status," + ...
    "policy_profile_version_id,applied_threshold) VALUES(1,'unassigned',1,0.5)", ...
    "applied_threshold_semantics");
end

function testExcludedDecisionRequiresAReason(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_decisions(attribution_target_id,decision_status," + ...
    "policy_profile_version_id) VALUES(1,'excluded',1)", "exclusion_reason");
end

function testNoStatusMeansValidated(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_decisions(attribution_target_id,decision_status," + ...
    "policy_profile_version_id) VALUES(1,'validated',1)", "decision_status IN");
end

function testASecondDecisionUnderTheSamePolicyIsRefused(testCase)
% A completed decision is never rewritten in place. A different policy is a
% different row, and both stay readable.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_decisions(attribution_target_id,decision_status," + ...
    "policy_profile_version_id) VALUES(1,'unassigned',1)");
verifyRefused(testCase, ...
    "INSERT INTO attribution_decisions(attribution_target_id,decision_status," + ...
    "policy_profile_version_id) VALUES(1,'ambiguous',1)", "UNIQUE");
end

function testSimultaneousSelectsSeveralCandidatesAndAssignedCannot(testCase)
% This is the structural difference between "two animals called" and "we cannot
% tell which one did": how many candidates the decision selects.
conn = testCase.TestData.conn;
addThreeCandidates(conn);
execute(conn, "INSERT INTO attribution_decisions(attribution_decision_id," + ...
    "attribution_target_id,decision_status,policy_profile_version_id) " + ...
    "VALUES(1,1,'simultaneous',1)");
execute(conn, "INSERT INTO attribution_decision_candidates(attribution_decision_id," + ...
    "attribution_candidate_id) VALUES(1,1),(1,2)");
selected = fetch(conn, "SELECT COUNT(*) AS n FROM attribution_decision_candidates " + ...
    "WHERE attribution_decision_id=1");
verifyEqual(testCase, double(selected.n(1)), 2);
verifyRefused(testCase, ...
    "UPDATE attribution_decisions SET decision_status='assigned' " + ...
    "WHERE attribution_decision_id=1", "contradicts the candidates");
end

function testDecisionCannotSelectAnotherTargetsCandidate(testCase)
conn = testCase.TestData.conn;
addThreeCandidates(conn);
execute(conn, "INSERT INTO attribution_decisions(attribution_decision_id," + ...
    "attribution_target_id,decision_status,policy_profile_version_id) " + ...
    "VALUES(1,1,'unassigned',1)");
verifyRefused(testCase, ...
    "INSERT INTO attribution_decision_candidates(attribution_decision_id," + ...
    "attribution_candidate_id) VALUES(1,999)", "different attribution target");
end

% --- decision cardinality survives deletion ---------------------------------

function testDeletingTheOnlySelectionOfAnAssignedDecisionIsRefused(testCase)
% The status-to-cardinality rule was checked when a selection was added and when
% the status changed, but not when a selection was removed, so an 'assigned'
% decision could be left selecting nobody.
conn = testCase.TestData.conn;
addThreeCandidates(conn);
addDecision(conn, "assigned", 1);
verifyRefused(testCase, "DELETE FROM attribution_decision_candidates " + ...
    "WHERE attribution_decision_id=1", "Removing this selection");
end

function testDeletingASelectionBelowTwoForSimultaneousIsRefused(testCase)
conn = testCase.TestData.conn;
addThreeCandidates(conn);
addDecision(conn, "simultaneous", [1 2 3]);
% Three down to two still satisfies 'simultaneous'.
execute(conn, "DELETE FROM attribution_decision_candidates " + ...
    "WHERE attribution_decision_id=1 AND attribution_candidate_id=3");
verifyRefused(testCase, "DELETE FROM attribution_decision_candidates " + ...
    "WHERE attribution_decision_id=1 AND attribution_candidate_id=2", ...
    "Removing this selection");
end

function testDeletingASelectedCandidateIsRefused(testCase)
% Deleting the candidate removes the selection by cascade, which is the same
% violation reached one step further away.
conn = testCase.TestData.conn;
addThreeCandidates(conn);
addDecision(conn, "assigned", 1);
verifyRefused(testCase, "DELETE FROM attribution_candidates " + ...
    "WHERE attribution_candidate_id=1", "Removing this selection");
% A candidate the decision did not select is unaffected.
execute(conn, "DELETE FROM attribution_candidates WHERE attribution_candidate_id=3");
end

function testDeletingTheDecisionTargetOrRunStillCascades(testCase)
% The guard must not refuse the cascades that remove the decision itself. Cascade
% order between sibling tables is an SQLite implementation detail, so the guard
% keys on whether the decision's target still exists rather than on that order.
conn = testCase.TestData.conn;
addThreeCandidates(conn);

addDecision(conn, "assigned", 1);
execute(conn, "DELETE FROM attribution_decisions WHERE attribution_decision_id=1");
verifyEqual(testCase, countOf(conn, "attribution_decision_candidates"), 0);

addDecision(conn, "simultaneous", [1 2]);
execute(conn, "DELETE FROM attribution_targets WHERE attribution_target_id=1");
verifyEqual(testCase, countOf(conn, "attribution_decisions"), 0);
verifyEqual(testCase, countOf(conn, "attribution_candidates"), 0);

execute(conn, "INSERT INTO attribution_targets(attribution_target_id," + ...
    "attribution_run_id,detection_id) VALUES(1,1,1)");
addThreeCandidates(conn);
addDecision(conn, "assigned", 2);
execute(conn, "DELETE FROM attribution_runs WHERE attribution_run_id=1");
verifyEqual(testCase, countOf(conn, "attribution_targets"), 0);
verifyEqual(testCase, countOf(conn, "attribution_decision_candidates"), 0);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);
end

% --- evidence -------------------------------------------------------------

function testEvidenceDimensionVocabularyIsClosed(testCase)
% Closed on purpose: the phase's separation claim is only checkable if the
% dimensions are enumerable.
verifyRefused(testCase, ...
    "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind) VALUES(1,'combined_confidence','x')", "evidence_dimension IN");
end

function testEvidenceValueRequiresSemantics(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind,value_real) VALUES(1,'acoustic','k',0.5)", "value_semantics");
end

function testIdentityStatementKindRequiresTheRowItRestsOn(testCase)
% A-1: a weak declared link used knowingly is honest evidence; a weak link
% presented as identity evidence is not. Either way it names which it is.
verifyRefused(testCase, ...
    "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind,identity_statement_kind) VALUES(1,'visual_identity','k','identity_association')", ...
    "identity_statement_kind");
end

function testAllFourDimensionsCoexistOnOneTarget(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind,value_real,value_units,value_semantics) VALUES" + ...
    "(1,'temporal_alignment','propagated_bound',0.002,'s','largest contributing anchor uncertainty; uncalibrated')," + ...
    "(1,'pose_localization','keypoint_confidence',0.73,'upstream score','upstream keypoint localization confidence')," + ...
    "(1,'visual_identity','reidentification_score',0.55,'similarity','cosine similarity of appearance embeddings')," + ...
    "(1,'acoustic','channel_rms_ratio',0.42,'ratio','channel 1 to 2 rms ratio')");
rows = fetch(conn, "SELECT evidence_dimension AS d FROM attribution_evidence " + ...
    "WHERE attribution_target_id=1 ORDER BY evidence_dimension");
verifyEqual(testCase, sort(string(rows.d))', ...
    sort(["temporal_alignment" "pose_localization" "visual_identity" "acoustic"]));
end

% --- imported windows and correspondence ---------------------------------

function testAlignedCorrespondenceMustNameItsTransform(testCase)
% An aligned basis means a transform was applied, so the row says which one.
verifyRefused(testCase, ...
    "INSERT INTO attribution_window_correspondences(imported_attribution_window_id," + ...
    "attribution_target_id,iou_basis,eligibility_rule) VALUES(1,1,'aligned','r')", ...
    "alignment_run_id IS NOT NULL");
end

function testOneWindowMayCorrespondToSeveralTargets(testCase)
% Ambiguity is preserved. Nothing here chooses.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(2,1,1,1.1,1.6)");
execute(conn, "INSERT INTO attribution_targets(attribution_target_id,attribution_run_id," + ...
    "detection_id) VALUES(2,1,2)");
execute(conn, "INSERT INTO attribution_window_correspondences(" + ...
    "imported_attribution_window_id,attribution_target_id,iou_basis,eligibility_rule," + ...
    "temporal_iou) VALUES(1,1,'native','positive_overlap',0.8),(1,2,'native','positive_overlap',0.6)");
rows = fetch(conn, "SELECT attribution_target_id AS t FROM attribution_window_correspondences " + ...
    "WHERE imported_attribution_window_id=1 ORDER BY attribution_target_id");
verifyEqual(testCase, double(rows.t)', [1 2]);
end

% --- the agreement-group extent view -------------------------------------

function testEveryExtentMethodIsComputed(testCase)
conn = testCase.TestData.conn;
rows = fetch(conn, "SELECT extent_method AS m FROM v_agreement_group_extent " + ...
    "WHERE agreement_group_id=1 ORDER BY extent_method");
verifyEqual(testCase, sort(string(rows.m))', sort([ ...
    "union_boundary_of_members" "intersection_boundary_of_members" ...
    "mean_boundary_of_members" "longest_member_boundary" ...
    "shortest_member_boundary"]));
end

function testExtentMethodsDifferWhenMembersDisagree(testCase)
% Three members with different boundaries: union is widest, intersection
% narrowest, mean between them. If these ever collapse to one value the view has
% stopped offering a choice.
conn = testCase.TestData.conn;
addDisagreeingGroup(conn);
rows = fetch(conn, "SELECT extent_method AS m, start_time_s AS s, end_time_s AS e " + ...
    "FROM v_agreement_group_extent WHERE agreement_group_id=2 ORDER BY extent_method");
method = string(rows.m);
unionRow = double(rows.s(method == "union_boundary_of_members"));
interRow = double(rows.s(method == "intersection_boundary_of_members"));
meanRow = double(rows.s(method == "mean_boundary_of_members"));
verifyEqual(testCase, unionRow, 10.0, AbsTol=1e-12);
verifyEqual(testCase, interRow, 10.4, AbsTol=1e-12);
verifyTrue(testCase, meanRow > unionRow && meanRow < interRow);
end

function testEmptyIntersectionIsFlaggedRatherThanReversed(testCase)
% Members that do not all overlap have no common interval. The row says so and
% reports the gap, instead of storing an interval whose end precedes its start.
conn = testCase.TestData.conn;
addNonOverlappingGroup(conn);
row = fetch(conn, "SELECT extent_is_empty AS ie, IFNULL(gap_s,-999.0) AS gap, " + ...
    "IFNULL(start_time_s,-999.0) AS s FROM v_agreement_group_extent " + ...
    "WHERE agreement_group_id=3 AND extent_method='intersection_boundary_of_members'");
verifyEqual(testCase, double(row.ie(1)), 1);
verifyEqual(testCase, double(row.gap(1)), 0.4, AbsTol=1e-9);
verifyEqual(testCase, double(row.s(1)), -999, AbsTol=1e-12);
end

function testNoNonEmptyExtentEverReverses(testCase)
conn = testCase.TestData.conn;
addDisagreeingGroup(conn);
addNonOverlappingGroup(conn);
bad = fetch(conn, "SELECT COUNT(*) AS n FROM v_agreement_group_extent " + ...
    "WHERE extent_is_empty=0 AND end_time_s < start_time_s");
verifyEqual(testCase, double(bad.n(1)), 0);
end

function testSingletonGroupGivesOneAnswerUnderEveryMethod(testCase)
% With one member there is nothing to disagree about, so every method must
% collapse to that member's own interval.
conn = testCase.TestData.conn;
counts = fetch(conn, "SELECT COUNT(DISTINCT start_time_s) AS ds, " + ...
    "COUNT(DISTINCT end_time_s) AS de FROM v_agreement_group_extent " + ...
    "WHERE agreement_group_id=1");
verifyEqual(testCase, double(counts.ds(1)), 1);
verifyEqual(testCase, double(counts.de(1)), 1);
end

function testExtractorCountSupportsConsilienceCriterionFiltering(testCase)
% "Groups where all three extractors agree" must be answerable from the view.
conn = testCase.TestData.conn;
addDisagreeingGroup(conn);
rows = fetch(conn, "SELECT agreement_group_id AS g FROM v_agreement_group_extent " + ...
    "WHERE extent_method='union_boundary_of_members' AND extractor_count=3");
verifyEqual(testCase, double(rows.g)', 2);
end

% --- Phase 3 debts closed by this bump -----------------------------------

function testAnchorObservationEventTimebaseIsGuardedOnUpdate(testCase)
% E-1. Repointing external_event_id changes which event the reading claims to be
% of, not merely where the row is filed.
conn = testCase.TestData.conn;
present = fetch(conn, "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='trigger' " + ...
    "AND name='trg_anchor_observation_event_timebase_update'");
verifyEqual(testCase, double(present.n(1)), 1);
end

function testAlignmentUncertaintyColumnsNowDeclareSemantics(testCase)
% P3-1. Both columns stored a number whose meaning lived only in prose.
conn = testCase.TestData.conn;
for table = ["alignment_anchor_observations", "aligned_external_events"]
    columns = fetch(conn, "SELECT name FROM pragma_table_info('" + table + "')");
    verifyTrue(testCase, any(string(columns.name) == "uncertainty_semantics"), ...
        table + " should declare its uncertainty semantics");
end
verifyRefused(testCase, ...
    "INSERT INTO alignment_anchor_observations(alignment_anchor_id,timebase_id," + ...
    "observed_time_native,uncertainty_s) VALUES(1,1,0.5,0.01)", "uncertainty_semantics");
end

% --- imported claims (P4-5) ----------------------------------------------

function testClaimScoreWithoutSemanticsIsRefused(testCase)
% The same rule attribution_candidates applies, applied here for the same
% reason: a number without stated semantics is not interpretable evidence.
verifyRefused(testCase, ...
    "INSERT INTO imported_attribution_claims(imported_attribution_window_id," + ...
    "claim_ordinal,source_caller_label,score) VALUES(1,1,'A',0.91)", ...
    "score_semantics");
end

function testClaimProbabilityWithoutSemanticsIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO imported_attribution_claims(imported_attribution_window_id," + ...
    "claim_ordinal,source_caller_label,probability) VALUES(1,1,'A',0.5)", ...
    "probability_semantics");
end

function testClaimProbabilityOutsideUnitIntervalIsRefused(testCase)
% probability is bounded because the word means something.
verifyRefused(testCase, ...
    "INSERT INTO imported_attribution_claims(imported_attribution_window_id," + ...
    "claim_ordinal,source_caller_label,probability,probability_semantics) " + ...
    "VALUES(1,1,'A',1.7,'exporter probability')", "probability >= 0");
end

function testClaimScoreIsNotBoundedToAnyRange(testCase)
% score is somebody else's scale and VAWLUME does not know its range. A value
% far outside [0,1] and a negative one are both legitimate.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO imported_attribution_claims(" + ...
    "imported_attribution_window_id,claim_ordinal,source_caller_label," + ...
    "score,score_semantics) VALUES(1,1,'A',1234.56789,'exporter score')," + ...
    "(1,2,'B',-0.0001,'exporter score')");
stored = fetch(conn, "SELECT score FROM imported_attribution_claims " + ...
    "ORDER BY claim_ordinal");
verifyEqual(testCase, double(stored.score)', [1234.56789 -0.0001]);
end

function testAClaimWithNoNumberIsAccepted(testCase)
% A label with no number is a legitimate import. Nothing here requires a value,
% because a NOT NULL would force the importer to invent one.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO imported_attribution_claims(" + ...
    "imported_attribution_window_id,claim_ordinal,source_caller_label,entity_id) " + ...
    "VALUES(1,1,'A',1)");
stored = fetch(conn, "SELECT COUNT(*) AS n FROM imported_attribution_claims " + ...
    "WHERE score IS NULL AND probability IS NULL");
verifyEqual(testCase, double(stored.n(1)), 1);
end

function testOneWindowMayCarrySeveralClaims(testCase)
% The source shape is one row per (window, caller). Several callers claimed over
% one window is the ordinary case, not an error.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO imported_attribution_claims(" + ...
    "imported_attribution_window_id,claim_ordinal,source_caller_label,entity_id," + ...
    "score,score_semantics) VALUES(1,1,'A',1,0.9,'s'),(1,2,'B',2,0.4,'s')");
stored = fetch(conn, "SELECT COUNT(*) AS n FROM imported_attribution_claims " + ...
    "WHERE imported_attribution_window_id=1");
verifyEqual(testCase, double(stored.n(1)), 2);
end

function testRepeatingOneLabelOverOneWindowIsRefused(testCase)
% Two rows for one caller over one window assert the same thing twice, possibly
% with two different numbers. Keeping whichever was written first is how a score
% goes missing without a symptom.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO imported_attribution_claims(" + ...
    "imported_attribution_window_id,claim_ordinal,source_caller_label) VALUES(1,1,'A')");
verifyRefused(testCase, ...
    "INSERT INTO imported_attribution_claims(imported_attribution_window_id," + ...
    "claim_ordinal,source_caller_label) VALUES(1,2,'A')", "UNIQUE");
end

function testClaimedCallerOutsideTheRecordingIsRefused(testCase)
% Entity 4 exists but is not linked to the recording. An imported label
% resolving to an animal that was never there is a surfaced problem, not a new
% participant -- the rule candidates already follow.
verifyRefused(testCase, ...
    "INSERT INTO imported_attribution_claims(imported_attribution_window_id," + ...
    "claim_ordinal,source_caller_label,entity_id) VALUES(1,1,'Z',4)", ...
    "not an entity linked to this recording");
end

% --- helpers --------------------------------------------------------------

function verifyRefused(testCase, statement, expectedFragment)
conn = testCase.TestData.conn;
refused = false;
message = "";
try
    execute(conn, statement);
catch err
    refused = true;
    message = string(err.message);
end
verifyTrue(testCase, refused, "Statement should have been refused: " + statement);
% The fragment matters as much as the refusal. A BEFORE trigger fires ahead of a
% row's CHECK constraints, so a refusal alone does not prove the intended
% constraint is the one that fired.
verifyTrue(testCase, contains(message, expectedFragment), ...
    "Refused, but not for its own reason. Expected """ + expectedFragment + ...
    """ in: " + message);
end

function addThreeCandidates(conn)
execute(conn, "INSERT INTO attribution_candidates(attribution_candidate_id," + ...
    "attribution_target_id,entity_id,score,score_semantics) VALUES" + ...
    "(1,1,1,0.8,'external posterior-like score, uncalibrated')," + ...
    "(2,1,2,0.6,'external posterior-like score, uncalibrated')," + ...
    "(3,1,3,0.1,'external posterior-like score, uncalibrated')");
end

function addDecision(conn, status, candidateIds)
execute(conn, "INSERT INTO attribution_decisions(attribution_decision_id," + ...
    "attribution_target_id,decision_status,policy_profile_version_id) " + ...
    "VALUES(1,1," + "'" + status + "',1)");
for candidateId = candidateIds
    execute(conn, "INSERT INTO attribution_decision_candidates(" + ...
        "attribution_decision_id,attribution_candidate_id) VALUES(1," + ...
        string(candidateId) + ")");
end
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function addDisagreeingGroup(conn)
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(2,'mu','MUPET'),(3,'us','USVSEG')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) " + ...
    "VALUES(2,2,'v'),(3,3,'v')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(2,1,2,'b'),(3,1,3,'c')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(2,1),(3,1)");
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id,extraction_run_id) " + ...
    "VALUES(2,2),(2,3)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(11,1,1,10.0,10.9),(12,2,1,10.2,10.5),(13,3,1,10.4,11.2)");
execute(conn, "INSERT INTO agreement_groups(agreement_group_id,analysis_run_id," + ...
    "recording_id,group_key,derivation_method) VALUES(2,2,1,'g2','connected_component')");
execute(conn, "INSERT INTO agreement_group_members(agreement_group_id,detection_id) " + ...
    "VALUES(2,11),(2,12),(2,13)");
end

function addNonOverlappingGroup(conn)
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(21,1,1,20.0,20.4),(22,1,1,20.3,20.9),(23,1,1,20.8,21.5)");
execute(conn, "INSERT INTO agreement_groups(agreement_group_id,analysis_run_id," + ...
    "recording_id,group_key,derivation_method) VALUES(3,2,1,'g3','connected_component')");
execute(conn, "INSERT INTO agreement_group_members(agreement_group_id,detection_id) " + ...
    "VALUES(3,21),(3,22),(3,23)");
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p','P')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES(1,1,'recording_audio','r.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) VALUES(1,1,1)");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name,is_subject_like) " + ...
    "VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id,entity_type_id,native_id) " + ...
    "VALUES(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'C'),(4,1,1,'Z')");
% Entity 4 is deliberately NOT linked to the recording.
execute(conn, "INSERT INTO recording_entity_links(recording_id,entity_id) VALUES(1,1),(1,2),(1,3)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) VALUES(1,1,'v')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id,extractor_version_id,run_key) " + ...
    "VALUES(1,1,1,'a')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5)");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES(1,1,'caller_attribution','att'),(2,1,'multi_extractor_agreement','ag')");
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id,extraction_run_id) " + ...
    "VALUES(1,1),(2,1)");
execute(conn, "INSERT INTO agreement_groups(agreement_group_id,analysis_run_id,recording_id," + ...
    "group_key,derivation_method) VALUES(1,2,1,'g1','connected_component')");
execute(conn, "INSERT INTO agreement_group_members(agreement_group_id,detection_id) VALUES(1,1)");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name,profile_kind) " + ...
    "VALUES(1,1,'pol','Illustrative attribution policy','attribution_policy')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id,version_label," + ...
    "content_format,content_uri,checksum_sha256) VALUES(1,1,'v1','json','config/policy.json','abc')");
execute(conn, "INSERT INTO attribution_runs(attribution_run_id,analysis_run_id,recording_id," + ...
    "run_key,attribution_path,method,status) VALUES(1,1,1,'run1','imported','ExternalSystem v2','complete')");
execute(conn, "INSERT INTO attribution_targets(attribution_target_id,attribution_run_id,detection_id) " + ...
    "VALUES(1,1,1)");
execute(conn, "INSERT INTO imported_attribution_windows(imported_attribution_window_id," + ...
    "attribution_run_id,recording_id,native_window_id,start_time_native,end_time_native) " + ...
    "VALUES(1,1,1,'w1',1.0,1.5)");
% One anchor and timebase, so the P3-1 refusal has a valid row to attach to.
execute(conn, "INSERT INTO timebases(timebase_id,project_id,timebase_name,timebase_kind,native_unit) " + ...
    "VALUES(1,1,'audio_native','recording_clock','s')");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES(3,1,'temporal_alignment','align')");
execute(conn, "INSERT INTO alignment_sets(alignment_set_id,analysis_run_id,recording_id," + ...
    "alignment_set_key,reference_timebase_id) VALUES(1,3,1,'set1',1)");
execute(conn, "INSERT INTO alignment_anchors(alignment_anchor_id,alignment_set_id,anchor_key,anchor_type) " + ...
    "VALUES(1,1,'sync01','ttl_edge')");
end
