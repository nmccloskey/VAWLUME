function tests = test_native_run_creation
%TEST_NATIVE_RUN_CREATION Phase 6.8: createRun admits native_estimate; addEvidence cites a measurement.
%
% Contract 06 D15 and D16. A native run cites an attribution_estimator_settings
% profile and stores its four declared inputs from that profile in the same
% transaction. addEvidence accepts derived_measurement_id and refuses a citation
% of another recording, another event or another channel.
tests = functiontests(localfunctions);
end

function setup(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
file = string(tempname) + ".sqlite";
conn = sqlite(char(file), "create");
vawlume.db.applySchema(conn, fullfile(root, "schema", "schema.sql"));
seed(conn);
settings = vawlume.estimator.loadSettings(RepoRoot=root);
registered = vawlume.db.registerProfileVersion(conn, struct(project_id=1), struct( ...
    profile_key=settings.profile_key, profile_name=settings.profile_name, ...
    version_label=settings.version_label, content_path=settings.path, ...
    profile_kind=settings.profile_kind, ...
    profile_schema_version=settings.profile_schema_version), RepoRoot=root);
testCase.TestData = struct(root=root, conn=conn, file=file, settings=settings, ...
    estimator_version=registered.profile_version_id, measurements=measurementIds());
end

function teardown(testCase)
close(testCase.TestData.conn);
if isfile(testCase.TestData.file)
    delete(testCase.TestData.file);
end
rmpath(fullfile(testCase.TestData.root, "src"));
end

% ------------------------------------------------------------ createRun ---

function testANativeRunStoresAllFourDeclaredInputs(testCase)
t = testCase.TestData;
plan = createRun(t, nativeSpec(t));
verifyEqual(testCase, plan.status, "planned");
verifyEqual(testCase, plan.declared_inputs, t.settings.declared_inputs(sortOrder(t), :));
verifyEqual(testCase, countOf(t.conn, "attribution_runs"), 0, "Planning writes nothing.");

created = createRun(t, nativeSpec(t), true);
verifyEqual(testCase, created.status, "created");
verifyEqual(testCase, created.run.attribution_path, "native_estimate");
verifyEqual(testCase, created.applied_counts.attribution_run_declared_inputs, 4);
rows = fetch(t.conn, "SELECT input_dimension, declaration, declared_by_profile_version_id, " + ...
    "notes FROM attribution_run_declared_inputs WHERE attribution_run_id=" + ...
    string(created.run.attribution_run_id) + " ORDER BY input_dimension");
verifyEqual(testCase, string(rows.input_dimension), ...
    ["acoustic"; "pose_localization"; "temporal_alignment"; "visual_identity"], ...
    "No upstream dimension is undeclared.");
verifyEqual(testCase, string(rows.declaration), repmat("used", 4, 1));
verifyEqual(testCase, double(rows.declared_by_profile_version_id), ...
    repmat(t.estimator_version, 4, 1), "Declared by the profile version the run cites.");
verifyEqual(testCase, string(rows.notes), t.settings.declared_inputs.notes(sortOrder(t)));
run = fetch(t.conn, "SELECT settings_profile_version_id FROM attribution_runs");
verifyEqual(testCase, double(run.settings_profile_version_id), t.estimator_version);

reused = createRun(t, nativeSpec(t), true);
verifyEqual(testCase, reused.status, "reused");
verifyEqual(testCase, reused.applied_counts.reused_attribution_run_declared_inputs, 4);
changed = nativeSpec(t);
changed.declared_inputs.declaration(1) = "not_used";
verifyEqual(testCase, createRun(t, changed, true).status, "conflict");
verifyEqual(testCase, countOf(t.conn, "attribution_run_declared_inputs"), 4);
end

function testANativeRunWithoutItsProfileOrDeclarationsIsRefused(testCase)
t = testCase.TestData;
spec = nativeSpec(t);
verifyError(testCase, @() createRun(t, rmfield(spec, "declared_inputs"), true), ...
    "vawlume:attribution:DeclaredInputsRequired");
incomplete = spec;
incomplete.declared_inputs = incomplete.declared_inputs(1:3, :);
verifyError(testCase, @() createRun(t, incomplete, true), ...
    "vawlume:attribution:DeclaredInputsIncomplete");
duplicated = spec;
duplicated.declared_inputs.input_dimension(4) = duplicated.declared_inputs.input_dimension(1);
verifyError(testCase, @() createRun(t, duplicated, true), ...
    "vawlume:attribution:DeclaredInputsIncomplete");
wrong = spec;
wrong.declared_inputs.declaration(2) = "partly";
verifyError(testCase, @() createRun(t, wrong, true), ...
    "vawlume:attribution:DeclaredInputsInvalid");
withImportedProfile = spec;
withImportedProfile.settings_profile_version_id = 1;
verifyError(testCase, @() createRun(t, withImportedProfile, true), ...
    "vawlume:attribution:NativeRunProfileRequired");
verifyEqual(testCase, countOf(t.conn, "attribution_runs"), 0);
end

function testAnEstimatorProfileOnAnImportedOrBackendRunIsRefused(testCase)
t = testCase.TestData;
for path = ["imported", "backend"]
    spec = nativeSpec(t);
    spec = rmfield(spec, "declared_inputs");
    spec.attribution_path = path;
    spec.run_key = path + "-with-estimator";
    verifyError(testCase, @() createRun(t, spec, true), ...
        "vawlume:attribution:EstimatorProfileOnNonNativeRun");
    declaring = importedSpec(path);
    declaring.declared_inputs = t.settings.declared_inputs;
    verifyError(testCase, @() createRun(t, declaring, true), ...
        "vawlume:attribution:DeclaredInputsNotAccepted");
end
bogus = importedSpec("imported");
bogus.attribution_path = "native";
verifyError(testCase, @() createRun(t, bogus, true), "vawlume:attribution:RunSpecInvalid");
verifyEqual(testCase, createRun(t, importedSpec("imported"), true).status, "created", ...
    "An imported run is created as before, with no declared inputs.");
verifyEqual(testCase, countOf(t.conn, "attribution_run_declared_inputs"), 0);
end

% ---------------------------------------------- addEvidence: the citation ---

function testAnEvidenceRowCitesTheMeasurementItReports(testCase)
t = testCase.TestData;
target = nativeTarget(t);
result = vawlume.attribution.addEvidence(t.conn, target, ...
    acousticRow(t.measurements.d1_ch1, 1), Apply=true);
verifyEqual(testCase, result.evidence.derived_measurement_id, t.measurements.d1_ch1);
stored = fetch(t.conn, "SELECT derived_measurement_id, recording_channel_id, value_real " + ...
    "FROM attribution_evidence");
verifyEqual(testCase, double(stored.derived_measurement_id), t.measurements.d1_ch1);
verifyEqual(testCase, double(stored.recording_channel_id), 1);
verifyEqual(testCase, double(stored.value_real), 0.25, ...
    "The row keeps its own value; the citation is an identifier.");
% The citation alone is a source pointer.
row = acousticRow(t.measurements.d1_ch2, 2);
verifyEqual(testCase, vawlume.attribution.addEvidence(t.conn, target, row).evidence_count, 1);
end

function testACitationOfAnotherRecordingEventOrChannelIsRefused(testCase)
t = testCase.TestData;
target = nativeTarget(t);
m = t.measurements;
cases = {
    acousticRow(999, 1), "vawlume:attribution:EvidenceMeasurementNotFound"
    acousticRow(m.other_recording, NaN), "vawlume:attribution:EvidenceMeasurementScopeMismatch"
    acousticRow(m.d2_ch1, 1), "vawlume:attribution:EvidenceMeasurementTargetMismatch"
    acousticRow(m.d1_ch1, 2), "vawlume:attribution:EvidenceMeasurementChannelMismatch"
    acousticRow(m.d1_ch1, NaN), "vawlume:attribution:EvidenceMeasurementChannelMismatch"
    acousticRow(m.d1_nochannel, 1), "vawlume:attribution:EvidenceMeasurementChannelMismatch"
    };
for k = 1:size(cases, 1)
    verifyError(testCase, @() vawlume.attribution.addEvidence(t.conn, target, ...
        cases{k, 1}, Apply=true), cases{k, 2});
end
verifyEqual(testCase, countOf(t.conn, "attribution_evidence"), 0);
verifyEqual(testCase, vawlume.attribution.addEvidence(t.conn, target, ...
    acousticRow(m.d1_nochannel, NaN)).evidence_count, 1, ...
    "A channel-less measurement is cited by a channel-less row.");
end

% --------------------------------------------------------------- helpers ---

function result = createRun(t, spec, apply)
if nargin < 3
    apply = false;
end
result = vawlume.attribution.createRun(t.conn, struct(recording_id=1), spec, Apply=apply);
end

function spec = nativeSpec(t)
spec = struct(run_key="native-run", attribution_path="native_estimate", ...
    method="vawlume.estimator.level_difference_consistency 1.0.0", ...
    settings_profile_version_id=t.estimator_version, ...
    target_set=struct(detection_ids=1), participating_entity_ids=[1 2], ...
    sources=struct(source_file_ids=1), declared_inputs=t.settings.declared_inputs);
end

function spec = importedSpec(path)
spec = struct(run_key=path + "-run", attribution_path=path, method="External", ...
    settings_profile_version_id=1, target_set=struct(detection_ids=1), ...
    participating_entity_ids=[1 2], sources=struct(source_file_ids=2));
if path == "backend"
    spec.settings_profile_version_id = 2;
end
end

function order = sortOrder(t)
[~, order] = sort(t.settings.declared_inputs.input_dimension);
end

function ref = nativeTarget(t)
created = createRun(t, nativeSpec(t), true);
ref = struct(attribution_target_id=created.targets.attribution_target_id(1));
end

function row = acousticRow(measurementId, channelId)
row = struct(evidence_dimension="acoustic", evidence_kind="call_band_power_normalized", ...
    value_real=0.25, value_units="ratio_to_channel_response", ...
    value_semantics="synthetic normalized level; producer=test", ...
    recording_channel_id=channelId, derived_measurement_id=measurementId);
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function seed(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p1','P')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri,relative_path) VALUES" + ...
    "(1,1,'recording_audio','audio.wav','audio.wav'),(2,1,'attribution_output','c.csv','c.csv')," + ...
    "(3,1,'recording_audio','other.wav','other.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id,native_recording_id) " + ...
    "VALUES(1,1,1,'R1'),(2,1,3,'R2')");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id,channel_index) " + ...
    "VALUES(1,1,1),(2,1,2),(3,2,1)");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name,is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id,entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id,recording_id,entity_id,link_type) " + ...
    "VALUES(1,1,1,'participant'),(2,1,2,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name,profile_kind) VALUES" + ...
    "(1,1,'imp','Imp','attribution_input_mapping'),(2,1,'bk','Bk','attribution_backend_mapping')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id,version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1','json','a.json','" + string(repmat('a', 1, 64)) + "',1),(2,2,'1','json','b.json','" + string(repmat('b', 1, 64)) + "',1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) VALUES(1,'ds','DS')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id,extractor_version_id,run_key) VALUES(1,1,1,'det')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1),(1,2)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id,start_time_s,end_time_s) " + ...
    "VALUES(1,1,1,1.0,1.1),(2,1,1,2.0,2.1),(3,1,2,1.0,1.1)");
execute(conn, "INSERT INTO metric_definitions(metric_definition_id,metric_key,metric_name,definition) " + ...
    "VALUES(1,'call_band_power_normalized','Normalized band power','synthetic')");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key,status) " + ...
    "VALUES(50,1,'acoustic_call_level_normalization','norm','completed')");
execute(conn, "INSERT INTO derived_measurements(derived_measurement_id,analysis_run_id," + ...
    "metric_definition_id,detection_id,recording_channel_id,value_real) VALUES" + ...
    "(11,50,1,1,1,0.25),(12,50,1,1,2,0.5),(13,50,1,2,1,0.75),(14,50,1,1,NULL,1.0),(15,50,1,3,3,1.5)");
end

function value = measurementIds()
value = struct(d1_ch1=11, d1_ch2=12, d2_ch1=13, d1_nochannel=14, other_recording=15);
end
