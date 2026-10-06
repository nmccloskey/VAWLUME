function tests = test_backend_localization_schema
%TEST_BACKEND_LOCALIZATION_SCHEMA Constraints of the 0.12-draft backend/localization slice.
%
% The sibling of test_caller_attribution_schema, for the tables and columns the
% backend/localization contract (docs/design/05_backend_localization_contract.md)
% adds: attribution_localization_estimates, attribution_native_attributes,
% attribution_run_declared_inputs, and attribution_evidence's
% source_localization dimension, estimate citation and channel citation.
%
% These tests assert REFUSALS, each by the message fragment of the constraint
% that should fire. A refusal alone proves little: a BEFORE trigger fires ahead
% of a row's CHECK constraints in SQLite, so the wrong guard can refuse a row for
% the wrong reason and a bare "it was refused" test would still pass.
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

% --- a localization estimate declares its frame ---------------------------

function testEstimateWithoutACoordinateSystemIsRefused(testCase)
% A pair of numbers with no declared frame is not a weak coordinate; it is not
% a coordinate.
verifyRefused(testCase, ...
    "INSERT INTO attribution_localization_estimates(imported_attribution_window_id," + ...
    "estimate_ordinal,position_x,position_y,position_semantics) VALUES(1,1,10,20,'s')", ...
    "attribution_localization_estimates.coordinate_system_id");
end

function testEstimateFrameFromAnotherProjectIsRefused(testCase)
% Frame 3 is declared for project 2. Identity comparison alone would call it a
% valid frame, which is exactly why the project guard exists.
verifyRefused(testCase, estimateSql(1, 1, 3, "10,20,NULL"), ...
    "different project than its window's recording");
end

function testEstimateWithoutPositionSemanticsIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_localization_estimates(imported_attribution_window_id," + ...
    "estimate_ordinal,coordinate_system_id,position_x,position_y) VALUES(1,1,1,10,20)", ...
    "attribution_localization_estimates.position_semantics");
end

function testEstimateWithoutAPositionIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_localization_estimates(imported_attribution_window_id," + ...
    "estimate_ordinal,coordinate_system_id,position_y,position_semantics) VALUES(1,1,1,20,'s')", ...
    "attribution_localization_estimates.position_x");
end

% --- confidence is separate and declares its semantics --------------------

function testConfidenceWithoutSemanticsIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_localization_estimates(imported_attribution_window_id," + ...
    "estimate_ordinal,coordinate_system_id,position_x,position_y,position_semantics," + ...
    "confidence) VALUES(1,1,1,10,20,'s',0.9)", "confidence_semantics");
end

function testConfidenceIsTheProducersUnboundedScale(testCase)
% Localization confidence is not a probability, and VAWLUME does not know the
% producer's range, so it is stored exactly as given.
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_localization_estimates(" + ...
    "imported_attribution_window_id,estimate_ordinal,coordinate_system_id," + ...
    "position_x,position_y,position_semantics,confidence,confidence_semantics) " + ...
    "VALUES(1,1,1,10,20,'s',37.5,'producer localization margin; uncalibrated')");
stored = fetch(conn, "SELECT confidence FROM attribution_localization_estimates");
verifyEqual(testCase, double(stored.confidence(1)), 37.5, AbsTol=1e-12);
end

% --- z: optional, and absence is absence ----------------------------------

function testAbsentZStaysNullNotZero(testCase)
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
stored = fetch(conn, "SELECT typeof(position_z) AS t FROM attribution_localization_estimates");
verifyEqual(testCase, string(stored.t(1)), "null");
end

function testZUnderATwoDimensionalFrameIsRefused(testCase)
verifyRefused(testCase, estimateSql(1, 1, 1, "10,20,5"), "not 3-dimensional");
end

function testGivingAnEstimateAZUnderATwoDimensionalFrameIsRefused(testCase)
% The update twin. Without it a row inserted legally could acquire a z later.
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
verifyRefused(testCase, ...
    "UPDATE attribution_localization_estimates SET position_z=5", "not 3-dimensional");
end

function testZUnderAThreeDimensionalFrameIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 2, "10,20,5"));
stored = fetch(conn, "SELECT position_z FROM attribution_localization_estimates");
verifyEqual(testCase, double(stored.position_z(1)), 5);
end

% --- several estimates per window; claims stay with their window ----------

function testSeveralEstimatesForOneWindowCoexist(testCase)
% A producer may report several plausible sources. Nothing here ranks them.
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
execute(conn, estimateSql(1, 2, 1, "40,25,NULL"));
stored = fetch(conn, "SELECT estimate_ordinal AS o FROM attribution_localization_estimates " + ...
    "ORDER BY estimate_ordinal");
verifyEqual(testCase, double(stored.o)', [1 2]);
end

function testRepeatingAnOrdinalWithinAWindowIsRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
verifyRefused(testCase, estimateSql(1, 1, 1, "40,25,NULL"), "UNIQUE");
end

function testEstimateTiedToAClaimOverAnotherWindowIsRefused(testCase)
% Claim 2 was made over window 2; this estimate is over window 1.
verifyRefused(testCase, ...
    "INSERT INTO attribution_localization_estimates(imported_attribution_window_id," + ...
    "imported_attribution_claim_id,estimate_ordinal,coordinate_system_id,position_x," + ...
    "position_y,position_semantics) VALUES(1,2,1,1,10,20,'s')", ...
    "claim belongs to a different window");
end

function testEstimateTiedToAClaimOverItsOwnWindowIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_localization_estimates(" + ...
    "imported_attribution_window_id,imported_attribution_claim_id,estimate_ordinal," + ...
    "coordinate_system_id,position_x,position_y,position_semantics) " + ...
    "VALUES(1,1,1,1,10,20,'s')");
verifyEqual(testCase, countOf(conn, "attribution_localization_estimates"), 1);
end

% --- evidence: the fifth dimension cites its estimate ---------------------

function testSourceLocalizationEvidenceCitingItsEstimateIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
execute(conn, evidenceSql(1, "'source_localization'", "1", "NULL"));
stored = fetch(conn, "SELECT evidence_dimension AS d, typeof(value_real) AS t " + ...
    "FROM attribution_evidence");
verifyEqual(testCase, string(stored.d(1)), "source_localization");
% The row copies nothing: the estimate is the authority.
verifyEqual(testCase, string(stored.t(1)), "null");
end

function testSourceLocalizationWithoutAnEstimateIsRefused(testCase)
verifyRefused(testCase, evidenceSql(1, "'source_localization'", "NULL", "NULL"), ...
    "attribution_localization_estimate_id IS NOT NULL");
end

function testAnotherDimensionCitingAnEstimateIsRefused(testCase)
% A pose row citing a sound-source estimate would make the hypothesis being
% tested look like its own evidence.
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
verifyRefused(testCase, evidenceSql(1, "'pose_localization'", "1", "NULL"), ...
    "attribution_localization_estimate_id IS NOT NULL");
end

function testAnInventedDimensionIsStillRefused(testCase)
% Widening the vocabulary by one deliberate member did not open it.
verifyRefused(testCase, evidenceSql(1, "'sound_source'", "NULL", "NULL"), ...
    "evidence_dimension IN");
end

function testEvidenceCitingAnEstimateFromAnotherRunIsRefused(testCase)
% Window 3 belongs to run 2; target 1 belongs to run 1.
conn = testCase.TestData.conn;
execute(conn, estimateSql(3, 1, 1, "10,20,NULL"));
verifyRefused(testCase, evidenceSql(1, "'source_localization'", "1", "NULL"), ...
    "localization estimate from a different attribution run");
end

function testRepointingEvidenceAtAnotherRunsEstimateIsRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
execute(conn, estimateSql(3, 1, 1, "10,20,NULL"));
execute(conn, evidenceSql(1, "'source_localization'", "1", "NULL"));
verifyRefused(testCase, ...
    "UPDATE attribution_evidence SET attribution_localization_estimate_id=2", ...
    "localization estimate from a different attribution run");
end

function testDeletingAnEstimateRemovesTheEvidenceCitingIt(testCase)
% An orphaned source_localization row is illegal by CHECK, so the citation
% cascades rather than going NULL.
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
execute(conn, evidenceSql(1, "'source_localization'", "1", "NULL"));
execute(conn, "DELETE FROM attribution_localization_estimates");
verifyEqual(testCase, countOf(conn, "attribution_evidence"), 0);
end

% --- evidence: channel citation -------------------------------------------

function testEvidenceNamingItsOwnRecordingsChannelIsAccepted(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1, "'acoustic'", "NULL", "1"));
stored = fetch(conn, "SELECT recording_channel_id AS c FROM attribution_evidence");
verifyEqual(testCase, double(stored.c(1)), 1);
end

function testEvidenceNamingAnotherRecordingsChannelIsRefused(testCase)
% Channel 2 belongs to recording 2; target 1's run is about recording 1.
verifyRefused(testCase, evidenceSql(1, "'acoustic'", "NULL", "2"), ...
    "channel belongs to a different recording than its run");
end

function testRepointingEvidenceAtAnotherRecordingsChannelIsRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1, "'acoustic'", "NULL", "1"));
verifyRefused(testCase, "UPDATE attribution_evidence SET recording_channel_id=2", ...
    "channel belongs to a different recording than its run");
end

% --- native attributes: one owner, typed, no JSON -------------------------

function testNativeAttributeWithNoOwnerIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_native_attributes(attribute_name,value_type,value_real) " + ...
    "VALUES('conf_v2','real',0.4)", "imported_attribution_claim_id IS NOT NULL");
end

function testNativeAttributeWithTwoOwnersIsRefused(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "imported_attribution_claim_id,attribute_name,value_type,value_real) " + ...
    "VALUES(1,1,'conf_v2','real',0.4)", "imported_attribution_claim_id IS NOT NULL");
end

function testNativeAttributeHasNoJsonValueType(testCase)
% P4-2 is the ledger item created by choosing JSON once.
verifyRefused(testCase, ...
    "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,value_type,value_text) VALUES(1,'cov','json','[1,0,0,1]')", ...
    "value_type IN");
end

function testMissingNativeAttributeMayNotCarryAValue(testCase)
verifyRefused(testCase, ...
    "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,value_type,value_real) VALUES(1,'conf_v2','missing',0.4)", ...
    "value_type = 'missing'");
end

function testMissingNativeAttributeIsDistinguishableFromAbsent(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,native_field_name,value_type) VALUES(1,'conf_v2','ConfV2','missing')");
stored = fetch(conn, "SELECT value_type AS t FROM attribution_native_attributes");
verifyEqual(testCase, string(stored.t(1)), "missing");
end

function testOneOwnerCannotRepeatAnAttributeName(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,value_type,value_real) VALUES(1,'conf_v2','real',0.4)");
verifyRefused(testCase, ...
    "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,value_type,value_real) VALUES(1,'conf_v2','real',0.7)", "UNIQUE");
end

function testTwoOwnersMayShareAnAttributeName(testCase)
% The uniqueness is per owner. The partial indexes must not collapse into one.
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
execute(conn, "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,value_type,value_real) VALUES(1,'conf_v2','real',0.4)");
execute(conn, "INSERT INTO attribution_native_attributes(imported_attribution_window_id," + ...
    "attribute_name,value_type,value_real) VALUES(2,'conf_v2','real',0.5)");
execute(conn, "INSERT INTO attribution_native_attributes(imported_attribution_claim_id," + ...
    "attribute_name,value_type,value_real) VALUES(1,'conf_v2','real',0.6)");
execute(conn, "INSERT INTO attribution_native_attributes(attribution_localization_estimate_id," + ...
    "attribute_name,value_type,value_real) VALUES(1,'conf_v2','real',0.7)");
verifyEqual(testCase, countOf(conn, "attribution_native_attributes"), 4);
end

% --- declared inputs: three states, four sources --------------------------

function testDeclaredInputOutsideTheFourSourcesIsRefused(testCase)
% A producer's output is not one of its inputs.
verifyRefused(testCase, declaredSql("'source_localization'", "'used'", "1"), ...
    "input_dimension IN");
end

function testDeclarationIsUsedOrNotUsedOnly(testCase)
% Undeclared is the absence of a row, never a stored 'unknown'.
verifyRefused(testCase, declaredSql("'acoustic'", "'unknown'", "1"), "declaration IN");
end

function testDeclarationRequiresTheProfileThatMadeIt(testCase)
verifyRefused(testCase, declaredSql("'acoustic'", "'used'", "NULL"), ...
    "attribution_run_declared_inputs.declared_by_profile_version_id");
end

function testOneDeclarationPerSourcePerRun(testCase)
conn = testCase.TestData.conn;
execute(conn, declaredSql("'acoustic'", "'used'", "1"));
verifyRefused(testCase, declaredSql("'acoustic'", "'not_used'", "1"), "UNIQUE");
end

function testDeclarationsCoexistAcrossSources(testCase)
conn = testCase.TestData.conn;
execute(conn, declaredSql("'acoustic'", "'used'", "1"));
execute(conn, declaredSql("'visual_identity'", "'not_used'", "1"));
verifyEqual(testCase, countOf(conn, "attribution_run_declared_inputs"), 2);
end

% --- profile kind ----------------------------------------------------------

function testBackendMappingIsADeclaredProfileKind(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name," + ...
    "profile_kind) VALUES(9,1,'bk','Backend mapping','attribution_backend_mapping')");
verifyEqual(testCase, countOf(conn, "config_profiles"), 2);
end

% --- the whole slice goes with its run ------------------------------------

function testDeletingTheRunRemovesTheSlice(testCase)
conn = testCase.TestData.conn;
execute(conn, estimateSql(1, 1, 1, "10,20,NULL"));
execute(conn, evidenceSql(1, "'source_localization'", "1", "1"));
execute(conn, "INSERT INTO attribution_native_attributes(" + ...
    "attribution_localization_estimate_id,attribute_name,value_type,value_real) " + ...
    "VALUES(1,'cov_xx','real',2.5)");
execute(conn, declaredSql("'acoustic'", "'used'", "1"));
execute(conn, "DELETE FROM attribution_runs WHERE attribution_run_id=1");
verifyEqual(testCase, countOf(conn, "attribution_localization_estimates"), 0);
verifyEqual(testCase, countOf(conn, "attribution_evidence"), 0);
verifyEqual(testCase, countOf(conn, "attribution_native_attributes"), 0);
verifyEqual(testCase, countOf(conn, "attribution_run_declared_inputs"), 0);
end

% --- helpers --------------------------------------------------------------

function sql = estimateSql(windowId, ordinal, systemId, xyz)
sql = "INSERT INTO attribution_localization_estimates(imported_attribution_window_id," + ...
    "estimate_ordinal,coordinate_system_id,position_x,position_y,position_z," + ...
    "position_semantics) VALUES(" + windowId + "," + ordinal + "," + systemId + "," + ...
    xyz + ",'estimated sound-source location; producer=SyntheticBackend; " + ...
    "not a bodypart position')";
end

function sql = evidenceSql(targetId, dimension, estimateId, channelId)
sql = "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind,attribution_localization_estimate_id,recording_channel_id," + ...
    "source_locator) VALUES(" + targetId + "," + dimension + ",'k'," + estimateId + "," + ...
    channelId + ",'row 1')";
end

function sql = declaredSql(dimension, declaration, profileVersionId)
sql = "INSERT INTO attribution_run_declared_inputs(attribution_run_id,input_dimension," + ...
    "declaration,declared_by_profile_version_id) VALUES(1," + dimension + "," + ...
    declaration + "," + profileVersionId + ")";
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

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function seedFixture(conn)
% Two projects so a frame can belong to the wrong one; two recordings so a
% channel can; two runs over recording 1 so an estimate can belong to the wrong
% run. Frame 1 is 2D and frame 2 is 3D in project 1; frame 3 is project 2's.
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'p','P'),(2,'q','Q')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES(1,1,'recording_audio','r1.wav'),(2,1,'recording_audio','r2.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) " + ...
    "VALUES(1,1,1),(2,1,2)");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index) VALUES(1,1,1),(2,2,1)");
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) VALUES" + ...
    "(1,1,'arena','Arena floor',2,'cm'),(2,1,'arena3d','Arena volume',3,'cm')," + ...
    "(3,2,'arena','Other project arena',2,'cm')");
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
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5),(2,1,1,3.0,3.4)");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES(1,1,'caller_attribution','att1'),(2,1,'caller_attribution','att2')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name,profile_kind) " + ...
    "VALUES(1,1,'pol','Illustrative attribution policy','attribution_policy')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id,version_label," + ...
    "content_format,content_uri,checksum_sha256) VALUES(1,1,'v1','json','config/policy.json','abc')");
execute(conn, "INSERT INTO attribution_runs(attribution_run_id,analysis_run_id,recording_id," + ...
    "run_key,attribution_path,method) VALUES" + ...
    "(1,1,1,'run1','backend','SyntheticBackend v1')," + ...
    "(2,2,1,'run2','backend','SyntheticBackend v1')");
execute(conn, "INSERT INTO attribution_targets(attribution_target_id,attribution_run_id,detection_id) " + ...
    "VALUES(1,1,1),(2,2,1)");
execute(conn, "INSERT INTO imported_attribution_windows(imported_attribution_window_id," + ...
    "attribution_run_id,recording_id,native_window_id,start_time_native,end_time_native) " + ...
    "VALUES(1,1,1,'w1',1.0,1.5),(2,1,1,'w2',3.0,3.4),(3,2,1,'w1',1.0,1.5)");
execute(conn, "INSERT INTO imported_attribution_claims(imported_attribution_claim_id," + ...
    "imported_attribution_window_id,claim_ordinal,source_caller_label,entity_id) " + ...
    "VALUES(1,1,1,'A',1),(2,2,1,'B',2)");
end
