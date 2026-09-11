function tests = test_acoustic_reference_measurement
tests = functiontests({ ...
    @testReadsBoundedRelativeArtifactWindowWithoutMutation, ...
    @testReaderReportsCoverageAndFailsClearly, ...
    @testMeasuresDeterministicResponseAndPersistsProvenance, ...
    @testMeasurementQcIsExplicit, ...
    @testSchemaEnforcesReferenceTargetAndChannelQualifier});
end

function testReadsBoundedRelativeArtifactWindowWithoutMutation(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = readBytes(fixture.audio_path);

window = vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 2, 0.25, 0.75, SourceRoot=fixture.source_root);

expected = audioread(char(fixture.audio_path), [3 6]);
verifyEqual(testCase, window.samples, expected(:, 2));
verifyEqual(testCase, window.status, "covered_populated");
verifyEqual(testCase, window.requested_interval_s, [0.25 0.75]);
verifyEqual(testCase, window.read_interval_s, [0.25 0.75]);
verifyEqual(testCase, window.first_sample, 3);
verifyEqual(testCase, window.last_sample, 6);
verifyEqual(testCase, window.sample_count, 4);
verifyEqual(testCase, window.sample_rate_hz, 8);
verifyEqual(testCase, window.total_channels, 2);
verifyEqual(testCase, window.channel_label, "right");
verifyEqual(testCase, window.source_file_id, 1);
verifyEqual(testCase, window.source_path_or_uri, "audio/tiny.wav");
verifyEqual(testCase, readBytes(fixture.audio_path), before);

clear cleanup
end

function testReaderReportsCoverageAndFailsClearly(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

verifyError(testCase, @() vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 1, 0, 1), ...
    "vawlume:acoustic:AudioSourceRootRequired");

partial = vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 1, 1.5, 2.5, SourceRoot=fixture.source_root);
verifyEqual(testCase, partial.status, "partial_populated");
verifyEqual(testCase, partial.covered_interval_s, [1.5 2]);
verifyTrue(testCase, any(partial.qc_flags == "incomplete_audio_coverage"));

outside = vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 1, 3, 4, SourceRoot=fixture.source_root);
verifyEqual(testCase, outside.status, "not_covered");
verifyEqual(testCase, outside.sample_count, 0);
verifyTrue(testCase, any(outside.qc_flags == "empty_window"));

verifyError(testCase, @() vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 9, 0, 1, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:ChannelNotFound");
execute(fixture.conn, "INSERT INTO recording_channels(recording_id, channel_index) VALUES (1,3)");
execute(fixture.conn, "UPDATE recordings SET channel_count=3 WHERE recording_id=1");
verifyError(testCase, @() vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 3, 0, 1, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:UnsupportedChannelLayout");
execute(fixture.conn, "UPDATE recordings SET channel_count=2 WHERE recording_id=1");
execute(fixture.conn, "UPDATE source_files SET path_or_uri='audio/missing.wav', " + ...
    "relative_path='audio/missing.wav' WHERE source_file_id=1");
verifyError(testCase, @() vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 1, 0, 1, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:AudioArtifactMissing");
execute(fixture.conn, "UPDATE source_files SET path_or_uri='https://example.invalid/tiny.wav' " + ...
    "WHERE source_file_id=1");
verifyError(testCase, @() vawlume.acoustic.readAudioWindow(fixture.conn, ...
    fixture.recording_ref, 1, 0, 1, SourceRoot=fixture.source_root), ...
    "vawlume:acoustic:AudioArtifactUnsupported");

clear cleanup
end

function testMeasuresDeterministicResponseAndPersistsProvenance(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
reference = registerReference(fixture, "pure-tone", 0, 1, 2, 0.5, 1.5);

planned = vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
    struct(acoustic_reference_id=reference.acoustic_reference_id), 2, ...
    SourceRoot=fixture.source_root);
verifyEqual(testCase, planned.action, "planned");
verifyEqual(testCase, planned.status, "completed");
verifyEqual(testCase, planned.metrics.metric_key, ...
    ["acoustic_rms_amplitude"; "acoustic_peak_abs_amplitude"; "acoustic_band_power"]);
verifyEqual(testCase, planned.metrics.value(1), sqrt(0.125), AbsTol=2e-5);
verifyEqual(testCase, planned.metrics.value(2), 0.5, AbsTol=2e-5);
verifyEqual(testCase, planned.metrics.value(3), 0.125, AbsTol=2e-5);
verifyEqual(testCase, scalar(fixture.conn, "SELECT COUNT(*) AS n FROM analysis_runs"), 0);

applied = vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
    struct(acoustic_reference_id=reference.acoustic_reference_id), 2, ...
    SourceRoot=fixture.source_root, Apply=true, RunKey="response-pure-tone", ...
    RunLabel="synthetic response", VawlumeVersion="test", SourceCommit="abc123");
verifyEqual(testCase, applied.action, "created");
verifyEqual(testCase, numel(applied.derived_measurement_ids), 3);
rows = fetch(fixture.conn, "SELECT dm.acoustic_reference_id, dm.recording_channel_id, " + ...
    "md.metric_key, dm.unit, dm.derivation_details_json, ar.run_type, ar.status, " + ...
    "ar.vawlume_version, ar.source_commit FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=dm.analysis_run_id " + ...
    "ORDER BY md.metric_key");
verifyEqual(testCase, height(rows), 3);
verifyEqual(testCase, unique(double(rows.acoustic_reference_id)), ...
    reference.acoustic_reference_id);
verifyEqual(testCase, unique(double(rows.recording_channel_id)), 2);
verifyTrue(testCase, all(string(rows.run_type) == "acoustic_reference_response"));
verifyTrue(testCase, all(string(rows.status) == "completed"));
verifyTrue(testCase, all(contains(string(rows.derivation_details_json), ...
    '"source_file_id":1')));
verifyTrue(testCase, all(contains(string(rows.derivation_details_json), ...
    '"method_version":"1.0.0"')));

reused = vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
    struct(acoustic_reference_id=reference.acoustic_reference_id), 2, ...
    SourceRoot=fixture.source_root, Apply=true, RunKey="response-pure-tone", ...
    RunLabel="synthetic response", VawlumeVersion="test", SourceCommit="abc123");
verifyEqual(testCase, reused.action, "reused");
verifyEqual(testCase, reused.analysis_run_id, applied.analysis_run_id);
verifyEqual(testCase, scalar(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM derived_measurements"), 3);
verifyError(testCase, @() vawlume.acoustic.measureReferenceResponse( ...
    fixture.conn, struct(acoustic_reference_id=reference.acoustic_reference_id), 2, ...
    SourceRoot=fixture.source_root, Apply=true, RunKey="response-pure-tone", ...
    RunLabel="changed"), "vawlume:acoustic:MeasurementRunConflict");

clear cleanup
end

function testMeasurementQcIsExplicit(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
partialRef = registerReference(fixture, "partial-clipped", 1, 3, 1, 1, 5);
measured = vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
    struct(acoustic_reference_id=partialRef.acoustic_reference_id), 1, ...
    SourceRoot=fixture.source_root);
verifyEqual(testCase, measured.status, "completed_with_warnings");
verifyEqual(testCase, height(measured.metrics), 2);
verifyFalse(testCase, any(measured.metrics.metric_key == "acoustic_band_power"));
verifyTrue(testCase, any(measured.qc_flags == "incomplete_audio_coverage"));
verifyTrue(testCase, any(measured.qc_flags == "reference_band_above_nyquist"));
verifyTrue(testCase, any(measured.qc_flags == "clipped_samples"));

zeroRef = registerReference(fixture, "zero", 1, 1, 1, NaN, NaN);
zero = vawlume.acoustic.measureReferenceResponse(fixture.conn, ...
    struct(acoustic_reference_id=zeroRef.acoustic_reference_id), 1, ...
    SourceRoot=fixture.source_root);
verifyEqual(testCase, zero.status, "failed");
verifyEqual(testCase, height(zero.metrics), 0);
verifyTrue(testCase, any(zero.qc_flags == "zero_length_window"));
verifyTrue(testCase, any(zero.qc_flags == "empty_window"));

clear cleanup
end

function testSchemaEnforcesReferenceTargetAndChannelQualifier(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
reference = registerReference(fixture, "schema-ref", 0, 1, 1, NaN, NaN);
execute(fixture.conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri) " + ...
    "VALUES (2,1,'recording_audio','other.wav')");
execute(fixture.conn, "INSERT INTO recordings(recording_id,project_id,source_file_id) VALUES (2,1,2)");
execute(fixture.conn, "INSERT INTO recording_channels(recording_channel_id,recording_id,channel_index) " + ...
    "VALUES (3,2,1)");
execute(fixture.conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES (1,1,'test','schema-derived')");
metricId = scalar(fixture.conn, "SELECT metric_definition_id AS n FROM metric_definitions " + ...
    "WHERE metric_key='acoustic_rms_amplitude'");

verifySqlFails(testCase, fixture.conn, "INSERT INTO derived_measurements(" + ...
    "analysis_run_id,metric_definition_id,acoustic_reference_id,recording_id," + ...
    "recording_channel_id,value_real) VALUES (1," + string(metricId) + "," + ...
    string(reference.acoustic_reference_id) + ",1,1,0.1)");
verifySqlFails(testCase, fixture.conn, "INSERT INTO derived_measurements(" + ...
    "analysis_run_id,metric_definition_id,acoustic_reference_id," + ...
    "recording_channel_id,value_real) VALUES (1," + string(metricId) + "," + ...
    string(reference.acoustic_reference_id) + ",3,0.1)");
execute(fixture.conn, "INSERT INTO derived_measurements(" + ...
    "analysis_run_id,metric_definition_id,acoustic_reference_id," + ...
    "recording_channel_id,value_real) VALUES (1," + string(metricId) + "," + ...
    string(reference.acoustic_reference_id) + ",1,0.1)");
verifySqlFails(testCase, fixture.conn, "INSERT INTO derived_measurements(" + ...
    "analysis_run_id,metric_definition_id,acoustic_reference_id," + ...
    "recording_channel_id,value_real) VALUES (1," + string(metricId) + "," + ...
    string(reference.acoustic_reference_id) + ",1,0.1)");
verifySqlFails(testCase, fixture.conn, "UPDATE derived_measurements " + ...
    "SET recording_channel_id=3 WHERE derived_measurement_id=1");
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function reference = registerReference(fixture, key, startS, endS, channel, bandMin, bandMax)
spec = struct(reference_key=key, reference_type="synthetic", ...
    start_time_s=startS, end_time_s=endS, channel_index=channel);
if ~isnan(bandMin)
    spec.frequency_min_hz = bandMin;
end
if ~isnan(bandMax)
    spec.frequency_max_hz = bandMax;
end
reference = vawlume.acoustic.registerReference(fixture.conn, ...
    fixture.recording_ref, spec);
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
sourceRoot = string(tempname);
mkdir(sourceRoot);
mkdir(fullfile(sourceRoot, "audio"));
audioPath = fullfile(sourceRoot, "audio", "tiny.wav");
sampleRate = 8;
t = (0:15)' / sampleRate;
left = zeros(16, 1);
left(9) = -1;
right = 0.5 * sin(2 * pi * t);
audiowrite(char(audioPath), [left right], sampleRate, BitsPerSample=16);
fileInfo = dir(audioPath);

dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() cleanUpFixture(conn, dbFile, sourceRoot, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES (1,'audio-test','Audio test')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path,filename,file_format,size_bytes,checksum_sha256) " + ...
    "VALUES (1,1,'recording_audio','audio/tiny.wav','audio/tiny.wav'," + ...
    "'tiny.wav','wav'," + string(fileInfo.bytes) + ",'synthetic-sha256')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id,sample_rate_hz,channel_count,duration_s) " + ...
    "VALUES (1,1,1,'tiny',8,2,2)");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index,channel_label) VALUES (1,1,1,'left'),(2,1,2,'right')");
fixture = struct(conn=conn, db_file=dbFile, repo_root=repoRoot, ...
    source_root=sourceRoot, audio_path=string(audioPath), ...
    recording_ref=struct(recording_id=1));
end

function bytes = readBytes(path)
fileId = fopen(path, "r");
cleaner = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8");
clear cleaner
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.n(1));
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

function cleanUpFixture(conn, dbFile, sourceRoot, repoRoot)
if isopen(conn)
    close(conn);
end
for suffix = ["", "-journal", "-wal", "-shm"]
    path = dbFile + suffix;
    if isfile(path)
        delete(path);
    end
end
if isfolder(sourceRoot)
    rmdir(sourceRoot, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
