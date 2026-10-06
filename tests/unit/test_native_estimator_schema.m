function tests = test_native_estimator_schema
%TEST_NATIVE_ESTIMATOR_SCHEMA Constraints of the 0.13-draft native-estimator change.
%
% The sibling of test_backend_localization_schema, for what the native estimator
% contract (docs/design/06_native_estimator_contract.md, D2 and D13) adds:
% attribution_evidence.derived_measurement_id with its scope trigger pair and
% RESTRICT delete behaviour, and the attribution_estimator_settings profile kind.
%
% These tests assert REFUSALS, each by the message fragment of the constraint
% that should fire. A BEFORE trigger fires ahead of the constraint that may
% actually describe a problem, so a bare "it was refused" proves little.
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

% --- the citation is scoped to the run's recording ------------------------

function testMeasurementOfTheRunsRecordingIsCitable(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1));
stored = fetch(conn, "SELECT derived_measurement_id FROM attribution_evidence");
verifyEqual(testCase, double(stored.derived_measurement_id(1)), 1);
end

function testMeasurementOfAnotherRecordingIsRefused(testCase)
% Measurement 2 is a call-window level on recording 2; the run is about
% recording 1. Citing it would attach another session's sound to this target.
verifyRefused(testCase, evidenceSql(2), ...
    "derived measurement whose recording is not its run's recording");
end

function testMeasurementWhoseRecordingCannotBeEstablishedIsRefused(testCase)
% Measurement 3 targets an entity, so it has no recording. A <> comparison would
% let it through on a NULL; the trigger compares with IS NOT so it does not.
verifyRefused(testCase, evidenceSql(3), ...
    "derived measurement whose recording is not its run's recording");
end

function testRepointingACitationToAnotherRecordingIsRefused(testCase)
% The update twin. Without it a legally inserted row could later be made to
% report a different session's measurement.
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1));
verifyRefused(testCase, ...
    "UPDATE attribution_evidence SET derived_measurement_id=2", ...
    "derived measurement whose recording is not its run's recording");
end

function testADanglingMeasurementReachesTheForeignKeyError(testCase)
% The scope trigger tests scope only once the measurement exists, so a missing
% identifier is reported as what it is rather than as a recording mismatch.
verifyRefused(testCase, evidenceSql(999), "FOREIGN KEY constraint failed");
end

% --- RESTRICT: a computed score cannot outlive its inputs -----------------

function testDeletingACitedMeasurementIsRefused(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1));
verifyRefused(testCase, ...
    "DELETE FROM derived_measurements WHERE derived_measurement_id=1", ...
    "FOREIGN KEY constraint failed");
end

function testDeletingTheMeasurementRunIsRefusedWhileCited(testCase)
% The realistic case: measurements cascade from their analysis run, and the
% RESTRICT stops the cascade rather than silently removing the evidence.
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1));
verifyRefused(testCase, "DELETE FROM analysis_runs WHERE analysis_run_id=2", ...
    "FOREIGN KEY constraint failed");
verifyEqual(testCase, countOf(conn, "derived_measurements"), 3);
end

function testDeletingTheAttributionRunFirstReleasesTheMeasurement(testCase)
conn = testCase.TestData.conn;
execute(conn, evidenceSql(1));
execute(conn, "DELETE FROM attribution_runs WHERE attribution_run_id=1");
verifyEqual(testCase, countOf(conn, "attribution_evidence"), 0);
execute(conn, "DELETE FROM derived_measurements WHERE derived_measurement_id=1");
verifyEqual(testCase, countOf(conn, "derived_measurements"), 2);
end

function testAnUncitedMeasurementDeletesFreely(testCase)
% RESTRICT applies only while a citation exists.
conn = testCase.TestData.conn;
execute(conn, "DELETE FROM derived_measurements WHERE derived_measurement_id=2");
verifyEqual(testCase, countOf(conn, "derived_measurements"), 2);
end

% --- profile kind -----------------------------------------------------------

function testEstimatorSettingsIsADeclaredProfileKind(testCase)
conn = testCase.TestData.conn;
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name," + ...
    "profile_kind) VALUES(9,1,'est','Native estimator settings','attribution_estimator_settings')");
verifyEqual(testCase, countOf(conn, "config_profiles"), 2);
end

function testAnUndeclaredProfileKindIsStillRefused(testCase)
% The vocabulary widened by one member; it did not open.
verifyRefused(testCase, ...
    "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name," + ...
    "profile_kind) VALUES(9,1,'est','x','attribution_estimator')", ...
    "CHECK constraint failed");
end

% --- the version moved once ---------------------------------------------------

function testSchemaIsThirteenDraft(testCase)
conn = testCase.TestData.conn;
info = fetch(conn, "SELECT schema_version FROM schema_info");
pragma = fetch(conn, "PRAGMA user_version");
verifyEqual(testCase, string(info.schema_version), "0.13-draft");
verifyEqual(testCase, double(pragma{1, 1}), 13);
end

% --- helpers --------------------------------------------------------------

function sql = evidenceSql(measurementId)
sql = "INSERT INTO attribution_evidence(attribution_target_id,evidence_dimension," + ...
    "evidence_kind,value_real,value_units,value_semantics,recording_channel_id," + ...
    "derived_measurement_id) VALUES(1,'acoustic','call_band_power_normalized',0.8," + ...
    "'ratio_to_channel_response','synthetic normalized level',1," + measurementId + ")";
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
% Two recordings so a measurement can belong to the wrong one. Measurement 1 is
% a level of detection 1 (recording 1), measurement 2 of detection 2 (recording
% 2), and measurement 3 targets an entity and so has no recording at all. All
% three come from measurement analysis run 2; attribution run 1 targets
% detection 1 on recording 1.
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p','P')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES(1,1,'recording_audio','r1.wav'),(2,1,'recording_audio','r2.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) " + ...
    "VALUES(1,1,1),(2,1,2)");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index) VALUES(1,1,1),(2,2,1)");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name,is_subject_like) " + ...
    "VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id,entity_type_id,native_id) " + ...
    "VALUES(1,1,1,'A')");
execute(conn, "INSERT INTO recording_entity_links(recording_id,entity_id) VALUES(1,1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) VALUES(1,1,'v')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id,extractor_version_id,run_key) " + ...
    "VALUES(1,1,1,'a')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1),(1,2)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5),(2,1,2,3.0,3.4)");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES(1,1,'caller_attribution','att1'),(2,1,'acoustic_call_window_response','m1')");
execute(conn, "INSERT INTO metric_definitions(metric_definition_id,metric_key,metric_name," + ...
    "definition) VALUES(1,'call_band_power','Call band power','synthetic test metric')");
execute(conn, "INSERT INTO derived_measurements(derived_measurement_id,analysis_run_id," + ...
    "metric_definition_id,detection_id,entity_id,recording_channel_id,value_real) VALUES" + ...
    "(1,2,1,1,NULL,1,0.25),(2,2,1,2,NULL,2,0.5),(3,2,1,NULL,1,NULL,0.75)");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name,profile_kind) " + ...
    "VALUES(1,1,'pol','Illustrative attribution policy','attribution_policy')");
execute(conn, "INSERT INTO attribution_runs(attribution_run_id,analysis_run_id,recording_id," + ...
    "run_key,attribution_path,method) VALUES(1,1,1,'run1','native_estimate','synthetic')");
execute(conn, "INSERT INTO attribution_targets(attribution_target_id,attribution_run_id,detection_id) " + ...
    "VALUES(1,1,1)");
end
