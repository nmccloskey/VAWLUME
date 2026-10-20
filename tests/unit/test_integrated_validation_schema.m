function tests = test_integrated_validation_schema
%TEST_INTEGRATED_VALIDATION_SCHEMA Constraints of the 0.14-draft Phase 7 change.
%
% The sibling of test_native_estimator_schema, for what the integrated
% validation contract (docs/design/07_integrated_validation_contract.md, D9 and
% D10) adds:
%
%   * invariant 24 for every writer: a native_estimate candidate carries no
%     probability (trigger pair on attribution_candidates);
%   * invariant 26 for every writer: a native pose_localization or
%     visual_identity evidence row cites a tracking identity association
%     (trigger pair on attribution_evidence);
%   * attribution_candidate_no_score_reasons, every reason a producer gave, only
%     for an unscored candidate.
%
% Refusals are asserted by the message fragment of the constraint that should
% fire. Each guard is also shown to be load-bearing: with its trigger dropped,
% the violating statement succeeds. A refusal test that would pass without the
% trigger proves nothing about the trigger.
%
% Run 1 is native_estimate, run 2 imported, run 3 backend; each has one target
% (1, 2, 3) on detection 1 and one candidate (1, 2, 3) for entity 1. Candidate 1
% is unscored; candidate 2 is scored.
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

% --- invariant 24: no probability on a native candidate --------------------

function testNativeCandidateWithScoreAndNoProbabilityIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, "UPDATE attribution_candidates SET score=-1.5, " + ...
    "score_semantics='dB consistency; not a probability' WHERE attribution_candidate_id=1");
verifyEqual(testCase, scalar(conn, "SELECT score FROM attribution_candidates " + ...
    "WHERE attribution_candidate_id=1"), -1.5);
end

function testHandWrittenProbabilityOnANativeCandidateIsRefused(testCase)
% The 6.13 probe: the canonical layer accepted this at 0.13-draft.
verifyRefused(testCase, candidateSql(11, 1, "0.7", "'hand-written'"), ...
    "native_estimate candidate carries no probability");
end

function testProbabilitySemanticsAloneOnANativeCandidateIsRefused(testCase)
% The CHECK allows semantics without a value; on a native run they would
% describe a probability no native producer makes.
verifyRefused(testCase, candidateSql(11, 1, "NULL", "'hand-written'"), ...
    "native_estimate candidate carries no probability");
end

function testSettingAProbabilityOnANativeCandidateLaterIsRefused(testCase)
verifyRefused(testCase, "UPDATE attribution_candidates SET probability=0.7, " + ...
    "probability_semantics='hand-written' WHERE attribution_candidate_id=1", ...
    "native_estimate candidate carries no probability");
end

function testImportedAndBackendProbabilitiesAreStillAccepted(testCase)
% The exporting system's claim is a probability because it said so; the guard
% is about native runs only.
conn = testCase.TestData.conn;
execute(conn, candidateSql(12, 2, "0.7", "'exporter posterior'"));
execute(conn, candidateSql(13, 3, "0.4", "'backend posterior'"));
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_candidates " + ...
    "WHERE probability IS NOT NULL"), 2);
end

function testTheProbabilityGuardIsLoadBearing(testCase)
conn = testCase.TestData.conn;
execute(conn, "DROP TRIGGER trg_attribution_candidate_native_no_probability");
execute(conn, candidateSql(11, 1, "0.7", "'hand-written'"));
execute(conn, "DROP TRIGGER trg_attribution_candidate_native_no_probability_update");
execute(conn, "UPDATE attribution_candidates SET probability=0.6, " + ...
    "probability_semantics='hand-written' WHERE attribution_candidate_id=1");
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_candidates " + ...
    "WHERE probability IS NOT NULL"), 2);
end

% --- invariant 26: a native track reaches an entity only through a citation --

function testNativePoseRowCitingAnAssociationIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1, 1, "pose_localization", "1"));
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_evidence"), 1);
end

function testLabelOnlyPoseRowOnANativeCandidateIsRefused(testCase)
% The 6.13 probe (row 26): a pose row naming only the tracker's label.
verifyRefused(testCase, evidenceSql(1, 1, "pose_localization", "NULL"), ...
    "must cite a tracking identity association");
end

function testNativeIdentityRowWithoutAnAssociationIsRefused(testCase)
verifyRefused(testCase, evidenceSql(1, 1, "visual_identity", "NULL"), ...
    "must cite a tracking identity association");
end

function testNativeAcousticRowNeedsNoAssociation(testCase)
% The rule is about identity reaching an entity; other dimensions are untouched.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind,value_real,value_units,value_semantics) VALUES(1,'acoustic'," + ...
    "'normalized_level_difference',2.0,'dB','synthetic level difference')");
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_evidence"), 1);
end

function testImportedAndBackendLabelOnlyPoseRowsAreStillAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(2, 2, "pose_localization", "NULL"));
execute(conn, evidenceSql(3, 3, "pose_localization", "NULL"));
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_evidence"), 2);
end

function testRemovingTheCitationFromANativeRowIsRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1, 1, "pose_localization", "1"));
verifyRefused(testCase, "UPDATE attribution_evidence " + ...
    "SET tracking_identity_association_id=NULL", ...
    "must cite a tracking identity association");
end

function testDeletingAnAssociationANativeRowCitesIsRefused(testCase)
% ON DELETE SET NULL is an update of the citing row, so the update twin refuses
% it: a score computed from the association could no longer be reconstructed.
% Asserted under both recursive_triggers settings, because the property must not
% depend on how a caller configured its connection.
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1, 1, "pose_localization", "1"));
for setting = ["OFF", "ON"]
    execute(conn, "PRAGMA recursive_triggers = " + setting);
    verifyRefused(testCase, "DELETE FROM tracking_identity_associations " + ...
        "WHERE tracking_identity_association_id=1", ...
        "must cite a tracking identity association");
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM " + ...
        "tracking_identity_associations"), 1, "recursive_triggers=" + setting);
end
end

function testDeletingAnAssociationOnlyAnImportedRowCitesProceeds(testCase)
% The SET NULL action is unaffected outside native runs.
conn = testCase.TestData.conn;
execute(conn, evidenceSql(2, 2, "pose_localization", "1"));
execute(conn, "DELETE FROM tracking_identity_associations WHERE tracking_identity_association_id=1");
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_evidence " + ...
    "WHERE tracking_identity_association_id IS NULL"), 1);
end

function testTheIdentityCitationGuardIsLoadBearing(testCase)
conn = testCase.TestData.conn;
execute(conn, "DROP TRIGGER trg_attribution_evidence_native_identity_cited");
execute(conn, evidenceSql(1, 1, "pose_localization", "NULL"));
execute(conn, evidenceSql(1, 1, "pose_localization", "1"));
execute(conn, "DROP TRIGGER trg_attribution_evidence_native_identity_cited_update");
execute(conn, "DELETE FROM tracking_identity_associations WHERE tracking_identity_association_id=1");
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM attribution_evidence " + ...
    "WHERE tracking_identity_association_id IS NULL"), 2);
end

% --- every no-score reason ---------------------------------------------------

function testEveryReasonOfAnUnscoredCandidateIsStoredInOrder(testCase)
conn = testCase.TestData.conn;
execute(conn, reasonSql(1, 1, "identity_changes_within_window"));
execute(conn, reasonSql(1, 2, "alignment_extrapolated"));
rows = fetch(conn, "SELECT reason_ordinal, reason_code FROM " + ...
    "attribution_candidate_no_score_reasons ORDER BY reason_ordinal");
verifyEqual(testCase, double(rows.reason_ordinal), [1; 2]);
verifyEqual(testCase, string(rows.reason_code), ...
    ["identity_changes_within_window"; "alignment_extrapolated"]);
end

function testAReasonForAScoredCandidateIsRefused(testCase)
verifyRefused(testCase, reasonSql(2, 1, "acoustic_clipped"), ...
    "only for a candidate that has no score");
end

function testARepeatedReasonIsRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, reasonSql(1, 1, "track_not_covered"));
verifyRefused(testCase, reasonSql(1, 2, "track_not_covered"), "UNIQUE constraint failed");
end

function testTwoReasonsAtOneOrdinalAreRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, reasonSql(1, 1, "track_not_covered"));
verifyRefused(testCase, reasonSql(1, 1, "bodypart_missing"), "UNIQUE constraint failed");
end

function testOrdinalsStartAtOneAndCodesAreNotBlank(testCase)
verifyRefused(testCase, reasonSql(1, 0, "track_not_covered"), "CHECK constraint failed");
verifyRefused(testCase, reasonSql(1, 1, "  "), "CHECK constraint failed");
end

function testAReasonForAMissingCandidateReachesTheForeignKeyError(testCase)
verifyRefused(testCase, reasonSql(999, 1, "track_not_covered"), ...
    "FOREIGN KEY constraint failed");
end

function testDeletingTheCandidateDeletesItsReasons(testCase)
conn = testCase.TestData.conn;
execute(conn, reasonSql(1, 1, "track_not_covered"));
execute(conn, "DELETE FROM attribution_candidates WHERE attribution_candidate_id=1");
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM " + ...
    "attribution_candidate_no_score_reasons"), 0);
end

function testTheUnscoredGuardIsLoadBearing(testCase)
conn = testCase.TestData.conn;
execute(conn, "DROP TRIGGER trg_no_score_reason_requires_unscored_candidate");
execute(conn, reasonSql(2, 1, "acoustic_clipped"));
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) FROM " + ...
    "attribution_candidate_no_score_reasons"), 1);
end

% --- the version moved once ---------------------------------------------------

function testSchemaIsFourteenDraft(testCase)
conn = testCase.TestData.conn;
verifyEqual(testCase, string(scalarText(conn, "SELECT schema_version FROM schema_info")), ...
    "0.14-draft");
verifyEqual(testCase, scalar(conn, "PRAGMA user_version"), 14);
end

% --- helpers --------------------------------------------------------------

function sql = candidateSql(candidateId, targetId, probability, semantics)
% A second candidate needs a second entity on the recording: (target, entity)
% is unique.
sql = "INSERT INTO attribution_candidates(attribution_candidate_id," + ...
    "attribution_target_id,entity_id,probability,probability_semantics) VALUES(" + ...
    candidateId + "," + targetId + ",2," + probability + "," + semantics + ")";
end

function sql = evidenceSql(targetId, candidateId, dimension, associationId)
% As the native estimator writes them (contract 06 D10): an identity row names
% its statement kind, a pose row cites the association without one. That
% matters for deletion. The A-1 CHECK already makes an association undeletable
% while a row STATES identity_association (its SET NULL would break the CHECK),
% so only the pose row exercises the update twin's own protection.
statement = "NULL";
if associationId ~= "NULL" && dimension == "visual_identity"
    statement = "'identity_association'";
end
sql = "INSERT INTO attribution_evidence(attribution_target_id," + ...
    "attribution_candidate_id,evidence_dimension,evidence_kind,value_real," + ...
    "value_text,value_units,value_semantics,identity_statement_kind," + ...
    "tracking_identity_association_id) VALUES(" + targetId + "," + candidateId + ...
    ",'" + dimension + "','synthetic_" + dimension + "',12.5,'mouse_a','cm'," + ...
    "'synthetic distance',"  + statement + "," + associationId + ")";
end

function sql = reasonSql(candidateId, ordinal, code)
sql = "INSERT INTO attribution_candidate_no_score_reasons(attribution_candidate_id," + ...
    "reason_ordinal,reason_code) VALUES(" + candidateId + "," + ordinal + ",'" + code + "')";
end

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
verifyTrue(testCase, contains(message, expectedFragment), ...
    "Refused, but not for its own reason. Expected """ + expectedFragment + ...
    """ in: " + message);
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows{1, 1});
end

function value = scalarText(conn, sql)
rows = fetch(conn, sql);
value = rows{1, 1};
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p','P')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES(1,1,'recording_audio','r1.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) VALUES(1,1,1)");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name,is_subject_like) " + ...
    "VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id,entity_type_id,native_id) " + ...
    "VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_id,entity_id) VALUES(1,1),(1,2)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) VALUES(1,1,'v')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id,extractor_version_id,run_key) " + ...
    "VALUES(1,1,1,'a')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5)");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES(1,1,'caller_attribution','native'),(2,1,'caller_attribution','imported')," + ...
    "(3,1,'caller_attribution','backend')");
execute(conn, "INSERT INTO attribution_runs(attribution_run_id,analysis_run_id,recording_id," + ...
    "run_key,attribution_path,method) VALUES(1,1,1,'native','native_estimate','synthetic')," + ...
    "(2,2,1,'imported','imported','synthetic exporter'),(3,3,1,'backend','backend','synthetic backend')");
execute(conn, "INSERT INTO attribution_targets(attribution_target_id,attribution_run_id,detection_id) " + ...
    "VALUES(1,1,1),(2,2,1),(3,3,1)");
execute(conn, "INSERT INTO attribution_candidates(attribution_candidate_id,attribution_target_id," + ...
    "entity_id,score,score_semantics) VALUES(1,1,1,NULL,NULL)," + ...
    "(2,2,1,0.9,'exporter score'),(3,3,1,NULL,NULL)");
% One tracking stream with one association for entity A.
execute(conn, "INSERT INTO timebases(timebase_id,project_id,timebase_name,timebase_kind) " + ...
    "VALUES(1,1,'tracking_clock','acquisition_clock')");
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) " + ...
    "VALUES(1,1,'arena_2d','Arena floor',2,'cm')");
execute(conn, "INSERT INTO external_streams(external_stream_id,project_id,recording_id," + ...
    "timebase_id,stream_name,stream_kind) VALUES(1,1,1,1,'pose','tracking')");
execute(conn, "INSERT INTO tracking_streams(external_stream_id,coordinate_system_id," + ...
    "native_time_basis) VALUES(1,1,'time')");
execute(conn, "INSERT INTO tracking_identity_associations(tracking_identity_association_id," + ...
    "external_stream_id,native_track_id,entity_id,start_time_native,end_time_native," + ...
    "assignment_state,evidence_kind) VALUES(1,1,'mouse_a',1,0.0,100.0,'assigned','manual')");
end
