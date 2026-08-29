function tests = test_mupet_run_provenance
%TEST_MUPET_RUN_PROVENANCE Read-only MUPET provenance planning contracts.
tests = functiontests(localfunctions);
end

function testPlanIsReadOnlyAndExact(testCase)
[fixture, cleanup] = setUpFixture();
before = tableCounts(fixture.conn);
result = plan(fixture, defaultRunSpec(fixture));
verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyTrue(testCase, result.ready_for_event_apply);
verifyEqual(testCase, result.recording.recording_id, 1);
verifyEqual(testCase, result.extractor.extractor_name, "MUPET");
verifyEqual(testCase, result.output_profile.profile_key, "vawlume.mupet.output.v2_1");
verifyEqual(testCase, sort(string(result.artifacts.role)), ...
    sort(["event_measurement_export"; "extractor_settings"; "native_processed_recording"]));
verifyEqual(testCase, result.artifacts.artifact_type(result.artifacts.role == "event_measurement_export"), ...
    "extractor_event_export");
verifyFalse(testCase, result.artifacts.is_native(result.artifacts.role == "extractor_settings"));
verifyTrue(testCase, result.artifacts.is_native(result.artifacts.role == "native_processed_recording"));
verifyEqual(testCase, result.event_population.planned_detection_count, 0);
verifyEqual(testCase, result.event_population.source_row_count, 4);
verifyEqual(testCase, height(result.extractor_objects), 0);
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

function testSettingsCaptureLivesOnRawArtifactMetadata(testCase)
[fixture, cleanup] = setUpFixture();
result = plan(fixture, defaultRunSpec(fixture));
row = result.artifacts(result.artifacts.role == "extractor_settings",:);
metadata = jsondecode(char(row.metadata_json(1)));
verifyEqual(testCase, string(metadata.status), "captured");
verifyTrue(testCase, logical(metadata.complete));
verifyEqual(testCase, numel(metadata.entries), 11);
verifyEqual(testCase, string(metadata.source_checksum_sha256), row.checksum_sha256(1));
verifyEqual(testCase, strlength(string(metadata.structured_capture_checksum_sha256)), 64);
verifyEqual(testCase, result.plan.settings_profile.mode, "none");
verifyTrue(testCase, isnan(result.plan.settings_profile.profile_version_id));
clear cleanup
end

function testMissingSettingsCanPlanButCannotApply(testCase)
[fixture, cleanup] = setUpFixture();
spec = rmfield(defaultRunSpec(fixture), "settings");
before = tableCounts(fixture.conn);
result = plan(fixture, spec);
verifyEqual(testCase, result.settings.status, "not_supplied");
verifyFalse(testCase, result.ready_for_event_apply);
verifyTrue(testCase, any(contains(result.warnings, "MUPET_SETTINGS_REQUIRED_FOR_APPLY")));
verifyError(testCase, @() apply(fixture, spec), "vawlume:ingest:MupetSettingsRequired");
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

function testCompleteApplyIsDeferredWithoutEmptyRun(testCase)
[fixture, cleanup] = setUpFixture();
before = tableCounts(fixture.conn);
verifyError(testCase, @() apply(fixture, defaultRunSpec(fixture)), ...
    "vawlume:ingest:MupetApplyNotAvailable");
verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 0);
clear cleanup
end

function testVersionBoundaryIsProfileDriven(testCase)
[fixture, cleanup] = setUpFixture();
for accepted = ["2.1", "2.1.7", "2.1.z"]
    spec = defaultRunSpec(fixture);
    spec.extractor_version = accepted;
    result = plan(fixture, spec);
    verifyEqual(testCase, result.extractor.declared_version, accepted);
end
spec = rmfield(defaultRunSpec(fixture), "extractor_version");
verifyError(testCase, @() plan(fixture, spec), "vawlume:ingest:MupetVersionRequired");
for rejected = ["2", "2.0", "2.2", "3.0"]
    spec = defaultRunSpec(fixture);
    spec.extractor_version = rejected;
    verifyError(testCase, @() plan(fixture, spec), "vawlume:ingest:MupetVersionIncompatible");
end
clear cleanup
end

function testRecordingGrammarAndExtractorSpecificRejections(testCase)
[fixture, cleanup] = setUpFixture();
spec = defaultRunSpec(fixture);
byId = vawlume.ingest.mupet(fixture.conn, fixture.export_path, ...
    struct(recording_id=1), spec, RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root);
verifyEqual(testCase, byId.recording.resolution_mode, "recording_id");
verifyError(testCase, @() vawlume.ingest.mupet(fixture.conn, fixture.export_path, ...
    struct(recording_id=999), spec, RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root), ...
    "vawlume:ingest:MupetRecordingNotFound");
withModel = spec; withModel.model = struct(artifact_path=fixture.native_path);
verifyError(testCase, @() plan(fixture, withModel), "vawlume:ingest:MupetRunSpecInvalid");
withClassification = spec; withClassification.classification = struct(method="manual");
verifyError(testCase, @() plan(fixture, withClassification), "vawlume:ingest:MupetRunSpecInvalid");
matSettings = spec; matSettings.settings = struct(profile_path=fixture.native_path);
verifyError(testCase, @() plan(fixture, matSettings), "vawlume:ingest:MupetSettingsUnsupported");
clear cleanup
end

function testCompatibleExistingGraphReusesEverything(testCase)
[fixture, cleanup] = setUpFixture();
first = plan(fixture, defaultRunSpec(fixture));
seedPlannedGraph(fixture.conn, first.plan);
before = tableCounts(fixture.conn);
again = plan(fixture, defaultRunSpec(fixture));
verifyEqual(testCase, again.extraction_run.action, "reuse");
verifyTrue(testCase, all(again.artifacts.action == "reuse"));
verifyTrue(testCase, all(again.run_artifacts.action == "reuse"));
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

function testDifferentRunCanReuseArtifactsWithoutDuplicatingThem(testCase)
[fixture, cleanup] = setUpFixture();
first = plan(fixture, defaultRunSpec(fixture));
seedPlannedGraph(fixture.conn, first.plan);
spec = defaultRunSpec(fixture);
spec.run_key = "mupet-run-2";
second = plan(fixture, spec);
verifyEqual(testCase, second.extraction_run.action, "create");
verifyTrue(testCase, all(second.artifacts.action == "reuse"));
verifyTrue(testCase, all(second.run_artifacts.action == "create"));
clear cleanup
end

function testChangedIdentityBearingArtifactsConflict(testCase)
[fixture, cleanup] = setUpFixture();
initial = plan(fixture, defaultRunSpec(fixture));
seedPlannedGraph(fixture.conn, initial.plan);

writeCsv(fixture.export_path, nominalExport(13.5));
changedExport = plan(fixture, defaultRunSpec(fixture));
verifyTrue(testCase, changedExport.has_conflicts);
verifyEqual(testCase, changedExport.artifacts.action( ...
    changedExport.artifacts.role == "event_measurement_export"), "conflict");

writeCsv(fixture.export_path, nominalExport(12.5));
writeText(fixture.config_path, strjoin([nominalConfigLines(); "unknown-setting,9"], newline) + newline);
changedSettings = plan(fixture, defaultRunSpec(fixture));
verifyTrue(testCase, changedSettings.has_conflicts);
verifyEqual(testCase, changedSettings.artifacts.action( ...
    changedSettings.artifacts.role == "extractor_settings"), "conflict");

writeText(fixture.config_path, strjoin(nominalConfigLines(), newline) + newline);
spec = defaultRunSpec(fixture);
spec = rmfield(spec, "native_artifact");
missingNative = plan(fixture, spec);
verifyEqual(testCase, missingNative.extraction_run.action, "conflict");
clear cleanup
end

function testDatasetRemainsProvenanceNotExperimentalHierarchy(testCase)
[fixture, cleanup] = setUpFixture();
spec = defaultRunSpec(fixture);
spec.dataset = struct(workspace_name="ws-a", dataset_name="dataset-a", ...
    native_dataset_path="audio/dataset-a");
before = tableCounts(fixture.conn);
result = plan(fixture, spec);
verifyEqual(testCase, result.dataset.status, "captured_provenance_only");
verifyEqual(testCase, result.dataset.dataset_name, "dataset-a");
verifyEqual(testCase, height(result.extractor_objects), 0);
verifyEqual(testCase, countOf(fixture.conn, "extractor_objects"), 0);
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

function testSettingsJsonIsPortableIdentityBearingEvidence(testCase)
[fixture, cleanup] = setUpFixture();
jsonPath = fullfile(fixture.artifact_root, "mupet", "settings.json");
writeText(jsonPath, jsonencode(struct(profile=struct(id="lab.mupet.settings", ...
    kind="extractor_settings", profile_version="1.0.0"), ...
    minimum_syllable_duration_ms=8)));
spec = defaultRunSpec(fixture);
spec.settings = struct(json_path=jsonPath);
before = tableCounts(fixture.conn);
result = plan(fixture, spec);
verifyEqual(testCase, result.settings.mode, "profile");
verifyEqual(testCase, result.settings.status, "captured");
verifyEqual(testCase, result.settings.profile_key, "lab.mupet.settings");
verifyEqual(testCase, result.settings.version_label, "1.0.0");
verifyEqual(testCase, result.settings.profile_action, "create");
verifyEqual(testCase, result.settings.version_action, "create");
verifyFalse(testCase, any(result.artifacts.role == "extractor_settings"));
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

function testRelationalReadbacksCoverRequiredProvenanceQuestions(testCase)
[fixture, cleanup] = setUpFixture();
planned = plan(fixture, defaultRunSpec(fixture));
seedPlannedGraph(fixture.conn, planned.plan);
seedDeepSqueakRun(fixture.conn);

recording = fetch(fixture.conn, "SELECT r.recording_id FROM extraction_runs er " + ...
    "JOIN extraction_run_inputs eri ON eri.extraction_run_id=er.extraction_run_id " + ...
    "JOIN recordings r ON r.recording_id=eri.recording_id WHERE er.run_key='mupet-run-1'");
verifyEqual(testCase, double(recording.recording_id), 1);

extractor = fetch(fixture.conn, "SELECT e.extractor_name, ev.version_label FROM extraction_runs er " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id WHERE er.run_key='mupet-run-1'");
verifyEqual(testCase, string(extractor.extractor_name), "MUPET");
verifyEqual(testCase, string(extractor.version_label), "2.1");

profile = fetch(fixture.conn, "SELECT cp.profile_key, cpv.version_label FROM extraction_runs er " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id=er.output_mapping_profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id WHERE er.run_key='mupet-run-1'");
verifyEqual(testCase, string(profile.profile_key), "vawlume.mupet.output.v2_1");

artifacts = fetch(fixture.conn, "SELECT era.artifact_role, a.artifact_type, a.is_native " + ...
    "FROM extraction_runs er JOIN extraction_run_artifacts era ON era.extraction_run_id=er.extraction_run_id " + ...
    "JOIN artifacts a ON a.artifact_id=era.artifact_id WHERE er.run_key='mupet-run-1' ORDER BY era.artifact_role");
verifyEqual(testCase, string(artifacts.artifact_role), ...
    ["event_measurement_export"; "extractor_settings"; "native_processed_recording"]);
verifyEqual(testCase, string(artifacts.artifact_type), ...
    ["extractor_event_export"; "extractor_settings"; "native_processed_recording"]);
verifyEqual(testCase, double(artifacts.is_native), [0;0;1]);

runs = fetch(fixture.conn, "SELECT er.run_key, e.extractor_name FROM recordings r " + ...
    "JOIN extraction_run_inputs eri ON eri.recording_id=r.recording_id " + ...
    "JOIN extraction_runs er ON er.extraction_run_id=eri.extraction_run_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id WHERE r.recording_id=1 ORDER BY er.run_key");
verifyEqual(testCase, string(runs.run_key), ["ds-existing"; "mupet-run-1"]);
verifyEqual(testCase, string(runs.extractor_name), ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 0);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname); mkdir(scratch);
dbPath = fullfile(scratch, "mupet.sqlite");
copyfile(seededTemplateDatabase(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
execute(conn, "INSERT INTO projects(project_key, project_name) VALUES('proj-a','Project A')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri,relative_path,filename) " + ...
    "VALUES(1,'recording_audio','audio/set/REC_A.wav','audio/set/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id,native_recording_id) VALUES(1,1,'REC_A')");
artifactRoot = scratch;
exportPath = fullfile(scratch, "mupet", "audio", "set", "CSV", "REC_A.csv");
configPath = fullfile(scratch, "mupet", "config.csv");
nativePath = fullfile(scratch, "mupet", "audio", "set", "REC_A.mat");
makeParent(exportPath); writeCsv(exportPath, nominalExport(12.5));
writeText(configPath, strjoin(nominalConfigLines(), newline) + newline);
writeText(nativePath, "synthetic MUPET native state stand-in");
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    artifact_root=artifactRoot, export_path=exportPath, config_path=configPath, ...
    native_path=nativePath);
end

function path = seededTemplateDatabase(repoRoot)
persistent templatePath
if ~isempty(templatePath) && isfile(templatePath), path = templatePath; return, end
templatePath = string(tempname) + ".sqlite";
conn = sqlite(char(templatePath), "create"); cleaner = onCleanup(@() close(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
delete(cleaner); path = templatePath;
end

function result = plan(fixture, spec)
result = vawlume.ingest.mupet(fixture.conn, fixture.export_path, ...
    struct(project_key="proj-a", source_relative_path="audio/set/REC_A.wav"), spec, ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root);
end
function result = apply(fixture, spec)
result = vawlume.ingest.mupet(fixture.conn, fixture.export_path, ...
    struct(project_key="proj-a", source_relative_path="audio/set/REC_A.wav"), spec, ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
end
function spec = defaultRunSpec(fixture)
spec = struct(run_key="mupet-run-1", extractor_version="2.1", ...
    run_label="MUPET run 1", settings=struct(config_path=fixture.config_path), ...
    native_artifact=struct(artifact_path=fixture.native_path));
end

function seedPlannedGraph(conn, plan)
assert(~isnan(plan.extractor.run_version_id));
execute(conn, "INSERT INTO extraction_runs(project_id,extractor_version_id,run_key,run_label," + ...
    "output_mapping_profile_version_id,status) VALUES(" + string(plan.recording.project_id) + "," + ...
    string(plan.extractor.run_version_id) + "," + sqlText(plan.run.run_key) + "," + ...
    sqlText(plan.run.run_label) + "," + string(plan.output_profile.profile_version_id) + "," + ...
    sqlText(plan.run.status) + ")");
runId = scalarFetch(conn, "SELECT last_insert_rowid() AS id", "id");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id,input_role) VALUES(" + ...
    string(runId) + "," + string(plan.recording.recording_id) + ",'source_audio')");
for index = 1:height(plan.artifacts)
    row = plan.artifacts(index,:);
    execute(conn, "INSERT INTO artifacts(project_id,artifact_type,native_artifact_type,path_or_uri," + ...
        "file_format,checksum_sha256,is_native,metadata_json) VALUES(" + ...
        string(plan.recording.project_id) + "," + sqlText(row.artifact_type) + "," + ...
        sqlText(row.native_artifact_type) + "," + sqlText(row.path_or_uri) + "," + ...
        sqlText(row.file_format) + "," + sqlText(row.checksum_sha256) + "," + ...
        string(double(row.is_native)) + "," + sqlText(row.metadata_json) + ")");
    artifactId = scalarFetch(conn, "SELECT last_insert_rowid() AS id", "id");
    execute(conn, "INSERT INTO extraction_run_artifacts(extraction_run_id,artifact_id,artifact_role) VALUES(" + ...
        string(runId) + "," + string(artifactId) + "," + sqlText(row.role) + ")");
end
end

function seedDeepSqueakRun(conn)
version = fetch(conn, "SELECT ev.extractor_version_id FROM extractor_versions ev " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE e.extractor_name='DeepSqueak' AND ev.version_label='3.2.x'");
profile = fetch(conn, "SELECT cpv.profile_version_id FROM config_profile_versions cpv " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE cp.profile_key='vawlume.deepsqueak.output.v3_2'");
execute(conn, "INSERT INTO extraction_runs(project_id,extractor_version_id,run_key," + ...
    "output_mapping_profile_version_id,status) VALUES(1," + ...
    string(double(version.extractor_version_id(1))) + ",'ds-existing'," + ...
    string(double(profile.profile_version_id(1))) + ",'imported')");
runId = scalarFetch(conn, "SELECT last_insert_rowid() AS id", "id");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id,input_role) VALUES(" + ...
    string(runId) + ",1,'source_audio')");
end

function cells = nominalExport(energy)
headers = {'Syllable number','Syllable start time (sec)','Syllable end time (sec)', ...
    'inter-syllable interval (sec)','syllable duration (msec)','starting frequency (kHz)', ...
    'final frequency (kHz)','minimum frequency (kHz)','maximum frequency (kHz)', ...
    'mean frequency (kHz)','frequency bandwidth (kHz)','total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
cells = [headers; {1,.100,.148,.052,48,45,60,40,75,55,35,energy,-18}; ...
    {2,.200,.235,.065,34.7,46,59,41,74,54,33,11.5,-19}; ...
    {3,.300,.351,.049,50.2,47,61,42,76,56,34,10.5,-20}; ...
    {4,.400,.445,'NA',44.9,48,62,43,77,57,34,9.5,-21}];
end
function lines = nominalConfigLines()
lines = ["noise-reduction,5"; "minimum-syllable-duration,008"; ...
    "maximum-syllable-duration,200"; "minimum-syllable-total-energy,-15"; ...
    "minimum-syllable-peak-amplitude,-25"; "minimum-syllable-distance,5"; ...
    "sample-frequency,250000"; "minimum-usv-frequency,30000"; ...
    "maximum-usv-frequency,120000"; "number-filterbank-filters,64"; "filterbank-type,1"];
end

function counts = tableCounts(conn)
names = ["projects","source_files","recordings","config_profiles", ...
    "config_profile_versions","extractors","extractor_versions","artifacts", ...
    "extraction_runs","extraction_run_inputs","extraction_run_artifacts", ...
    "extractor_objects","detections","event_measurements"];
counts = struct(); for name = names, counts.(name) = countOf(conn,name); end
end
function value = countOf(conn, name)
value = scalarFetch(conn, "SELECT COUNT(*) AS n FROM " + name, "n");
end
function value = scalarFetch(conn, query, field)
rows = fetch(conn, query); value = double(rows.(char(field))(1));
end
function text = sqlText(value), text = "'" + replace(string(value), "'", "''") + "'"; end
function writeCsv(path, cells), makeParent(path); if isfile(path), delete(path); end; writecell(cells,path); end
function writeText(path, value)
makeParent(path); id = fopen(path,"w"); assert(id>=0); cleaner=onCleanup(@() fclose(id));
fprintf(id,"%s",value); delete(cleaner);
end
function makeParent(path), parent=fileparts(path); if ~isfolder(parent), mkdir(parent); end; end
function tearDown(conn, scratch, repoRoot)
try, close(conn); catch, end
if isfolder(scratch), rmdir(scratch,"s"); end
rmpath(fullfile(repoRoot,"src"));
end
function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
