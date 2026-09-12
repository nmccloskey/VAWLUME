function tests = test_acoustic_channel_response_profiles
tests = functiontests({ ...
    @testConsistentTwoChannelProfilePersistsAndReadsExactLineage, ...
    @testReferenceTypeDivergenceRemainsSeparatedAndVisible, ...
    @testMissingRequiredReferenceFamilyIsExplicit, ...
    @testWarningSourcesAreExcludedOrRetainedByPolicy, ...
    @testUnpairedChannelReferencesAreNotComparable, ...
    @testSchemaProtectsSupportingEvidenceAndScope});
end

function testConsistentTwoChannelProfilePersistsAndReadsExactLineage(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
ids = [1; 2; 3; 4];

planned = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, ids, RequiredReferenceTypes="tone");
verifyEqual(testCase, planned.action, "planned");
verifyEqual(testCase, planned.status, "completed");
verifyEqual(testCase, height(planned.estimates), 2);
verifyEqual(testCase, planned.estimates.channel_index, [1; 2]);
verifyEqual(testCase, planned.estimates.value_real, [1; 0.5], AbsTol=1e-12);
verifyEqual(testCase, planned.estimates.qc_status, ["ok"; "ok"]);
verifyEqual(testCase, planned.estimates.n_references, [2; 2]);
verifyEqual(testCase, countRows(fixture.conn, "channel_response_estimates"), 0);
verifyError(testCase, @() vawlume.acoustic.estimateChannelResponse( ...
    fixture.conn, fixture.recording_ref, ids, RequiredReferenceTypes="tone", ...
    SettingsProfileVersionId=1), ...
    "vawlume:acoustic:ResponseSettingsProfileKindInvalid");

applied = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, ids, RequiredReferenceTypes="tone", ...
    SettingsProfileVersionId=20, Apply=true, RunKey="consistent-profile", ...
    RunLabel="consistent synthetic", VawlumeVersion="test", SourceCommit="abc");
verifyEqual(testCase, applied.action, "created");
verifyEqual(testCase, numel(applied.channel_response_estimate_ids), 2);

readBack = vawlume.acoustic.readChannelResponse(fixture.conn, ...
    struct(project_key="response-test", run_key="consistent-profile"));
verifyEqual(testCase, readBack.analysis.status, "completed");
verifyEqual(testCase, readBack.estimates.value_real, [1; 0.5], AbsTol=1e-12);
verifyEqual(testCase, sort(readBack.source_measurements.derived_measurement_id), ids);
verifyEqual(testCase, sort(readBack.source_analyses.source_analysis_run_id), ids);
verifyTrue(testCase, all(readBack.source_analyses.dependency_role == ...
    "reference_response_measurement"));
verifyEqual(testCase, unique(readBack.source_measurements.metric_key), ...
    "acoustic_rms_amplitude");
verifyEqual(testCase, readBack.settings_profiles.profile_version_id, 20);
verifyEqual(testCase, readBack.settings_profiles.assignment_role, ...
    "response_aggregation_policy");

reused = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, ids, RequiredReferenceTypes="tone", ...
    SettingsProfileVersionId=20, Apply=true, RunKey="consistent-profile", ...
    RunLabel="consistent synthetic", VawlumeVersion="test", SourceCommit="abc");
verifyEqual(testCase, reused.action, "reused");
verifyEqual(testCase, reused.analysis_run_id, applied.analysis_run_id);
verifyEqual(testCase, countRows(fixture.conn, "channel_response_estimates"), 2);

verifyError(testCase, @() vawlume.acoustic.estimateChannelResponse( ...
    fixture.conn, fixture.recording_ref, ids, RequiredReferenceTypes="tone", ...
    SettingsProfileVersionId=20, Apply=true, RunKey="consistent-profile", ...
    RunLabel="changed"), "vawlume:acoustic:ResponseProfileConflict");

clear cleanup
end

function testReferenceTypeDivergenceRemainsSeparatedAndVisible(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
ids = 1:8;

profile = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, ids, RequiredReferenceTypes=["tone", "noise"], ...
    DivergenceRelativeThreshold=0.25);

verifyEqual(testCase, height(profile.estimates), 4);
verifyEqual(testCase, profile.status, "completed_with_warnings");
verifyTrue(testCase, all(profile.estimates.qc_status == "divergent"));
verifyTrue(testCase, all(cellfun(@(flags) ...
    any(flags == "reference_type_divergence"), profile.estimates.qc_flags)));
tone = profile.estimates(profile.estimates.reference_type == "tone", :);
noise = profile.estimates(profile.estimates.reference_type == "noise", :);
verifyEqual(testCase, tone.value_real, [1; 0.5], AbsTol=1e-12);
verifyEqual(testCase, noise.value_real, [2; 1], AbsTol=1e-12);
verifyFalse(testCase, any(profile.estimates.value_real == 1.5));

clear cleanup
end

function testMissingRequiredReferenceFamilyIsExplicit(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

profile = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, [1; 2; 3; 4], ...
    RequiredReferenceTypes=["tone", "missing-family"]);
missing = profile.estimates(profile.estimates.reference_type == "missing-family", :);

verifyEqual(testCase, height(missing), 2);
verifyTrue(testCase, all(isnan(missing.value_real)));
verifyTrue(testCase, all(missing.qc_status == "insufficient_evidence"));
verifyTrue(testCase, all(cellfun(@(flags) ...
    any(flags == "missing_reference_family"), missing.qc_flags)));
verifyEqual(testCase, profile.status, "completed_with_warnings");

clear cleanup
end

function testWarningSourcesAreExcludedOrRetainedByPolicy(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
ids = [9; 10];

excluded = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, ids, RequiredReferenceTypes="tone", MinReferences=1);
verifyEqual(testCase, excluded.status, "completed_with_warnings");
verifyTrue(testCase, all(excluded.estimates.qc_status == "insufficient_evidence"));
verifyTrue(testCase, all(isnan(excluded.estimates.value_real)));
verifyEqual(testCase, sort(excluded.excluded_measurements.derived_measurement_id), ids);

retained = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, ids, RequiredReferenceTypes="tone", MinReferences=1, ...
    IncludeWarningSources=true);
verifyTrue(testCase, all(retained.estimates.qc_status == "source_qc_warning"));
verifyEqual(testCase, retained.estimates.value_real, [1; 0.5], AbsTol=1e-12);
verifyEqual(testCase, height(retained.excluded_measurements), 0);

failedExcluded = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, 11, RequiredReferenceTypes="tone", MinReferences=1);
verifyTrue(testCase, isnan(failedExcluded.estimates.value_real));
failedRetained = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, 11, RequiredReferenceTypes="tone", MinReferences=1, ...
    IncludeFailedSources=true);
verifyEqual(testCase, failedRetained.estimates.value_real, 0.8, AbsTol=1e-12);
verifyEqual(testCase, failedRetained.estimates.qc_status, "source_qc_warning");
verifyTrue(testCase, any(failedRetained.estimates.qc_flags{1} == ...
    "included_failed_source"));

clear cleanup
end

function testUnpairedChannelReferencesAreNotComparable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

profile = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, [1; 4], RequiredReferenceTypes="tone", MinReferences=1);
verifyEqual(testCase, profile.status, "failed");
verifyTrue(testCase, all(profile.estimates.qc_status == "not_comparable"));
verifyTrue(testCase, all(cellfun(@(flags) ...
    any(flags == "unpaired_channel_references"), profile.estimates.qc_flags)));

clear cleanup
end

function testSchemaProtectsSupportingEvidenceAndScope(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applied = vawlume.acoustic.estimateChannelResponse(fixture.conn, ...
    fixture.recording_ref, [1; 2; 3; 4], RequiredReferenceTypes="tone", ...
    Apply=true, RunKey="lineage-profile");

verifySqlFails(testCase, fixture.conn, ...
    "DELETE FROM derived_measurements WHERE derived_measurement_id=1");
verifySqlFails(testCase, fixture.conn, ...
    "DELETE FROM analysis_runs WHERE analysis_run_id=1");

execute(fixture.conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES (2,1,'recording_audio','other.wav')");
execute(fixture.conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) VALUES (2,1,2)");
execute(fixture.conn, "INSERT INTO recording_channels(recording_channel_id,recording_id,channel_index) " + ...
    "VALUES (3,2,1)");
verifySqlFails(testCase, fixture.conn, "UPDATE channel_response_estimates " + ...
    "SET recording_channel_id=3 WHERE channel_response_estimate_id=" + ...
    string(applied.channel_response_estimate_ids(1)));
verifySqlFails(testCase, fixture.conn, "UPDATE channel_response_estimates " + ...
    "SET reference_type='noise' WHERE channel_response_estimate_id=" + ...
    string(applied.channel_response_estimate_ids(1)));
verifySqlFails(testCase, fixture.conn, "INSERT INTO channel_response_estimate_sources(" + ...
    "channel_response_estimate_id,derived_measurement_id) VALUES (" + ...
    string(applied.channel_response_estimate_ids(1)) + ",2)");

execute(fixture.conn, "DELETE FROM analysis_runs WHERE analysis_run_id=" + ...
    string(applied.analysis_run_id));
execute(fixture.conn, "DELETE FROM analysis_runs WHERE analysis_run_id=1");
verifyEqual(testCase, countRows(fixture.conn, "channel_response_estimates"), 0);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() cleanUpFixture(conn, dbFile, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);

execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES (1,'response-test','Response test')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES (1,1,'recording_audio','response.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "sample_rate_hz,channel_count,duration_s) VALUES (1,1,1,8,2,20)");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index,channel_label) VALUES (1,1,1,'left'),(2,1,2,'right')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key," + ...
    "profile_name,profile_kind) VALUES (20,1,'response-policy-v1'," + ...
    "'Response policy','analysis_settings')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id," + ...
    "version_label,profile_schema_version,content_format,content_uri,checksum_sha256) " + ...
    "VALUES (20,20,'1.0.0','0.1-draft','json','response-policy.json','policy-sha')");

execute(conn, "INSERT INTO acoustic_references(acoustic_reference_id,recording_id," + ...
    "reference_key,reference_type,start_time_s,end_time_s,frequency_min_hz,frequency_max_hz) " + ...
    "VALUES (1,1,'tone-1','tone',0,1,1,2),(2,1,'tone-2','tone',2,3,1,2)," + ...
    "(3,1,'noise-1','noise',4,5,1,2),(4,1,'noise-2','noise',6,7,1,2)," + ...
    "(5,1,'tone-warning','tone',8,9,1,2)");

metricId = scalar(conn, "SELECT metric_definition_id AS n FROM metric_definitions " + ...
    "WHERE metric_key='acoustic_rms_amplitude'");
details = jsonencode(struct(method_key="vawlume.acoustic.reference_response", ...
    method_version="1.0.0", ...
    sample_semantics="MATLAB audioread normalized full-scale ratio", ...
    interval_semantics="half-open [start,end) in native audio seconds"));
definitions = [ ...
    1 1 1 1.0 0
    2 1 2 0.5 0
    3 2 1 1.0 0
    4 2 2 0.5 0
    5 3 1 2.0 0
    6 3 2 1.0 0
    7 4 1 2.0 0
    8 4 2 1.0 0
    9 5 1 1.0 1
    10 5 2 0.5 1
    11 5 1 0.8 2
];
for index = 1:size(definitions, 1)
    id = definitions(index, 1);
    referenceId = definitions(index, 2);
    channelId = definitions(index, 3);
    value = definitions(index, 4);
    sourceState = definitions(index, 5);
    status = "completed";
    if sourceState == 1
        status = "completed_with_warnings";
    elseif sourceState == 2
        status = "failed";
    end
    execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type," + ...
        "run_key,status) VALUES (" + string(id) + ",1,'acoustic_reference_response'," + ...
        sqlText("measurement-" + string(id)) + "," + sqlText(status) + ")");
    execute(conn, "INSERT INTO derived_measurements(derived_measurement_id," + ...
        "analysis_run_id,metric_definition_id,acoustic_reference_id," + ...
        "recording_channel_id,value_real,unit,derivation_details_json) VALUES (" + ...
        string(id) + "," + string(id) + "," + string(metricId) + "," + ...
        string(referenceId) + "," + string(channelId) + "," + ...
        compose("%.17g", value) + ",'full_scale_ratio'," + sqlText(details) + ")");
end
fixture = struct(conn=conn, db_file=dbFile, repo_root=repoRoot, ...
    recording_ref=struct(recording_id=1));
end

function value = countRows(conn, tableName)
value = scalar(conn, "SELECT COUNT(*) AS n FROM " + tableName);
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.n(1));
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
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

function cleanUpFixture(conn, dbFile, repoRoot)
if isopen(conn)
    close(conn);
end
for suffix = ["", "-journal", "-wal", "-shm"]
    path = dbFile + suffix;
    if isfile(path)
        delete(path);
    end
end
rmpath(fullfile(repoRoot, "src"));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
