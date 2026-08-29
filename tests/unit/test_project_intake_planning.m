function tests = test_project_intake_planning
tests = functiontests({ ...
    @testInvalidIRRejectedWithoutMutation, ...
    @testNonProjectProfileRejected, ...
    @testMissingProjectKeyRejected, ...
    @testNewProjectIsPlannedAsCreate, ...
    @testCompatibleProjectIsPlannedAsReuse, ...
    @testIncompatibleProjectIdentityIsConflict, ...
    @testMappingProfileVersionIsPlannedAsReuse, ...
    @testMappingProfileChecksumConflictIsReported, ...
    @testRepeatedPlanningIsDeterministic, ...
    @testRelocatedRuntimeRootReusesPortableSource, ...
    @testIngestNamespaceDoesNotDuplicateSourceParsing});
end

function testInvalidIRRejectedWithoutMutation(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = validProjectIR();
ir.valid_for_ingest = false;
before = intakeCounts(conn);

verifyError(testCase, @() vawlume.ingest.project(conn, ir, projectSpec()), ...
    "vawlume:ingest:IntakeNotReady");
verifyEqual(testCase, intakeCounts(conn), before);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testNonProjectProfileRejected(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = validProjectIR();
ir.profile.profile_kind = "extractor_output";

verifyError(testCase, @() vawlume.ingest.project(conn, ir, projectSpec()), ...
    "vawlume:ingest:InvalidIR");

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testMissingProjectKeyRejected(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
spec = rmfield(projectSpec(), "project_key");

verifyError(testCase, @() vawlume.ingest.project(conn, validProjectIR(), spec), ...
    "vawlume:ingest:InvalidProjectSpec");

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testNewProjectIsPlannedAsCreate(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

result = vawlume.ingest.project(conn, validProjectIR(), projectSpec());

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyEqual(testCase, result.plan.project.action, "create");
verifyEqual(testCase, result.plan.mapping_profile.profile_action, "create");
verifyEqual(testCase, result.plan.mapping_profile.version_action, "create");
verifyEqual(testCase, result.plan.sources.action, "create");
verifyEqual(testCase, result.plan.sources.path_or_uri, "audio/session_01/call.wav");
verifyEqual(testCase, result.created_counts.projects, 1);
verifyTrue(testCase, isnan(result.ingestion_run_id));
verifyEqual(testCase, intakeCounts(conn), zeroIntakeCounts());

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testCompatibleProjectIsPlannedAsReuse(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
projectId = insertProject(conn, projectSpec());

result = vawlume.ingest.project(conn, validProjectIR(), projectSpec());

verifyEqual(testCase, result.plan.project.action, "reuse");
verifyEqual(testCase, result.project_id, projectId);
verifyEqual(testCase, result.reused_counts.projects, 1);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testIncompatibleProjectIdentityIsConflict(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
stored = projectSpec();
stored.project_name = "Stored project name";
insertProject(conn, stored);

result = vawlume.ingest.project(conn, validProjectIR(), projectSpec());

verifyEqual(testCase, result.status, "conflict");
verifyEqual(testCase, result.plan.project.action, "conflict");
verifyEqual(testCase, result.conflict_counts.projects, 1);
verifyTrue(testCase, any(result.issues.code == "PROJECT_IDENTITY_CONFLICT"));
verifyEqual(testCase, result.plan.sources.action, "skip");

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testMappingProfileVersionIsPlannedAsReuse(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = validProjectIR();
[profileId, versionId] = insertMappingProfile(conn, ir.profile, ir.profile.profile_checksum);

result = vawlume.ingest.project(conn, ir, projectSpec());

verifyEqual(testCase, result.plan.mapping_profile.profile_action, "reuse");
verifyEqual(testCase, result.plan.mapping_profile.version_action, "reuse");
verifyEqual(testCase, result.plan.mapping_profile.existing_profile_id, profileId);
verifyEqual(testCase, result.mapping_profile_version_id, versionId);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testMappingProfileChecksumConflictIsReported(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = validProjectIR();
insertMappingProfile(conn, ir.profile, string(repmat('b', 1, 64)));

result = vawlume.ingest.project(conn, ir, projectSpec());

verifyEqual(testCase, result.status, "conflict");
verifyEqual(testCase, result.plan.mapping_profile.profile_action, "reuse");
verifyEqual(testCase, result.plan.mapping_profile.version_action, "conflict");
verifyTrue(testCase, any(result.issues.code == ...
    "MAPPING_PROFILE_VERSION_CONFLICT"));

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testRepeatedPlanningIsDeterministic(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = validProjectIR();

first = vawlume.ingest.project(conn, ir, projectSpec());
second = vawlume.ingest.project(conn, ir, projectSpec());

verifyEqual(testCase, second, first);
verifyEqual(testCase, intakeCounts(conn), zeroIntakeCounts());

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testRelocatedRuntimeRootReusesPortableSource(testCase)
[conn, dbFile, repoRoot] = createDisposableDatabase();
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
spec = projectSpec();
projectId = insertProject(conn, spec);
execute(conn, "INSERT INTO source_files(" + ...
    "project_id, file_role, path_or_uri, relative_path, filename) VALUES (" + ...
    string(projectId) + ", 'recording_audio', 'audio/session_01/call.wav', " + ...
    "'audio/session_01/call.wav', 'call.wav')");
sourceId = scalar(conn, "SELECT source_file_id AS n FROM source_files");

homeIR = validProjectIR();
homeIR.sources.runtime_path = "C:/home/project/audio/session_01/call.wav";
workIR = homeIR;
workIR.sources.runtime_path = "D:/work/project/audio/session_01/call.wav";
homePlan = vawlume.ingest.project(conn, homeIR, spec);
workPlan = vawlume.ingest.project(conn, workIR, spec);

verifyEqual(testCase, homePlan.plan.sources.action, "reuse");
verifyEqual(testCase, workPlan.plan.sources.action, "reuse");
verifyEqual(testCase, homePlan.source_ids.source_file_id, sourceId);
verifyEqual(testCase, workPlan.source_ids.source_file_id, sourceId);
verifyNotEqual(testCase, homePlan.plan.sources.runtime_path, ...
    workPlan.plan.sources.runtime_path);
verifyEqual(testCase, homePlan.plan.sources.path_or_uri, ...
    workPlan.plan.sources.path_or_uri);

clear cleanupDb
rmpath(fullfile(repoRoot, "src"));
end

function testIngestNamespaceDoesNotDuplicateSourceParsing(testCase)
repoRoot = repoRootForTest();
files = dir(fullfile(repoRoot, "src", "+vawlume", "+ingest", "**", "*.m"));

namespaceText = "";
intakeText = "";
for index = 1:numel(files)
    contents = newline + string(fileread(fullfile(files(index).folder, files(index).name)));
    namespaceText = namespaceText + contents;
    if isProjectIntakeFile(files(index).name)
        intakeText = intakeText + contents;
    end
end

% Source discovery and path-rule parsing belong to +source_mapping. No file in
% the ingest namespace, project intake or extractor adapter, may reimplement
% them.
for forbidden = ["regexp(", "discoverSources", "parsePath", "source_mapping.parse"]
    verifyFalse(testCase, contains(namespaceText, forbidden), ...
        "The ingest namespace must consume interpreted IR without source parsing.");
end

% Project intake additionally consumes only already-interpreted IR, so it must
% never relativize a path itself. An extractor adapter reads an artifact that
% never passed through source discovery and must derive that artifact's portable
% path, but it does so by delegating to the shared source_mapping helper rather
% than duplicating the logic, which is what this guard protects.
verifyFalse(testCase, contains(intakeText, "normalizeRelativePath"), ...
    "Project intake must take portable source paths from the IR, not recompute them.");
end

function tf = isProjectIntakeFile(name)
name = string(name);
tf = ~startsWith(name, "deepsqueak") && name ~= "sha256OfFile.m";
end

function ir = validProjectIR()
checksum = string(repmat('a', 1, 64));
ir = struct();
ir.profile = struct( ...
    profile_key="example.project.intake.test", ...
    profile_name="Project intake test profile", ...
    profile_kind="project_input", ...
    profile_version="0.1.0", ...
    profile_schema_version="0.2-draft", ...
    profile_content_format="json", ...
    profile_path="config/project_input_test.json", ...
    profile_runtime_path="C:/repo/config/project_input_test.json", ...
    profile_checksum=checksum);
ir.sources = table( ...
    "source:audio/session_01/call.wav", ...
    "C:/runtime/project/audio/session_01/call.wav", ...
    "audio/session_01/call.wav", "call.wav", "project_file", ...
    "rule.audio", "recording_audio", "mapped", "", ...
    VariableNames=["source_key", "runtime_path", "relative_path", ...
    "filename", "source_type", "discovery_rule", "artifact_type", ...
    "status", "checksum_sha256"]);
ir.records = table( ...
    "record:recording:call", "source:audio/session_01/call.wav", ...
    "recording", "recording", "audio/session_01/call.wav", ...
    "source_recording", "", "rule.recording", "mapped", ...
    VariableNames=["record_key", "source_key", "native_level", ...
    "canonical_level", "native_identifier", "record_scope", "role_label", ...
    "mapping_rule", "status"]);
ir.relationships = table( ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), ...
    VariableNames=["relationship_key", "source_key", "from_record_key", ...
    "to_record_key", "native_relationship", "canonical_relationship", ...
    "role_label", "mapping_rule", "status"]);
ir.valid_for_ingest = true;
end

function value = projectSpec()
value = struct( ...
    project_key="intake_test_project", ...
    project_name="Intake test project", ...
    description="Focused Phase 3 planning test.");
end

function [conn, dbFile, repoRoot] = createDisposableDatabase()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
end

function id = insertProject(conn, spec)
execute(conn, "INSERT INTO projects(project_key, project_name, description) VALUES (" + ...
    sqlText(spec.project_key) + ", " + sqlText(spec.project_name) + ", " + ...
    sqlText(spec.description) + ")");
id = scalar(conn, "SELECT last_insert_rowid() AS n");
end

function [profileId, versionId] = insertMappingProfile(conn, profile, checksum)
execute(conn, "INSERT INTO config_profiles(" + ...
    "profile_key, profile_name, profile_kind, is_builtin) VALUES (" + ...
    sqlText(profile.profile_key) + ", " + sqlText(profile.profile_name) + ...
    ", 'project_input', 1)");
profileId = scalar(conn, "SELECT last_insert_rowid() AS n");
execute(conn, "INSERT INTO config_profile_versions(" + ...
    "profile_id, version_label, profile_schema_version, content_format, " + ...
    "content_uri, checksum_sha256, is_snapshot) VALUES (" + ...
    string(profileId) + ", " + sqlText(profile.profile_version) + ", " + ...
    sqlText(profile.profile_schema_version) + ", " + ...
    sqlText(profile.profile_content_format) + ", " + ...
    sqlText(profile.profile_path) + ", " + sqlText(checksum) + ", 1)");
versionId = scalar(conn, "SELECT last_insert_rowid() AS n");
end

function counts = intakeCounts(conn)
counts = struct( ...
    projects=scalar(conn, "SELECT COUNT(*) AS n FROM projects"), ...
    profiles=scalar(conn, "SELECT COUNT(*) AS n FROM config_profiles"), ...
    profile_versions=scalar(conn, ...
    "SELECT COUNT(*) AS n FROM config_profile_versions"), ...
    sources=scalar(conn, "SELECT COUNT(*) AS n FROM source_files"), ...
    ingestion_runs=scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_runs"));
end

function counts = zeroIntakeCounts()
counts = struct(projects=0, profiles=0, profile_versions=0, ...
    sources=0, ingestion_runs=0);
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.n(1));
end

function value = sqlText(value)
value = "'" + replace(string(value), "'", "''") + "'";
end

function cleanupDatabase(conn, dbFile)
if isopen(conn)
    close(conn);
end
deleteIfExists(dbFile);
deleteIfExists(dbFile + "-journal");
deleteIfExists(dbFile + "-wal");
deleteIfExists(dbFile + "-shm");
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
