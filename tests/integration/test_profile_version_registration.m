function tests = test_profile_version_registration
%TEST_PROFILE_VERSION_REGISTRATION Phase 4.12a: the settings-profile gap, closed.
%
% `createRun` has always required a checksum-bearing `config_profile_versions`
% row, and until this pass no public function created one. Every test seeded the
% two rows by SQL and usage guide §7.7 carried the same workaround, so a user
% could not create an attribution run from the documented example without
% hand-writing INSERTs.
%
% The load-bearing tests are not the ones that prove a row inserts. They are
% `testTheRegisteredVersionIsAcceptedByCreateRun`, which proves the row satisfies
% the path the workaround existed for, and the conflict tests, which prove
% re-registering cannot silently re-point evidence that already cites a version.
tests = functiontests(localfunctions);
end

% --- it creates what createRun needs --------------------------------------

function testRegisteringCreatesProfileAndVersion(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = register(fixture, struct());

verifyEqual(testCase, result.status, "created");
verifyGreaterThan(testCase, result.profile_version_id, 0);
verifyEqual(testCase, result.profile_kind, "analysis_settings");
verifyEqual(testCase, result.content_format, "json");
verifyEqual(testCase, strlength(result.checksum_sha256), 64);
% Both rows exist, scoped to the project that was named.
rows = fetch(fixture.conn, "SELECT p.project_id, p.profile_key, p.profile_kind, " + ...
    "v.version_label FROM config_profile_versions v " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id " + ...
    "WHERE v.profile_version_id=" + string(result.profile_version_id));
verifyEqual(testCase, double(rows.project_id(1)), 1);
verifyEqual(testCase, string(rows.profile_key(1)), "demo-settings");
verifyEqual(testCase, string(rows.profile_kind(1)), "analysis_settings");
verifyEqual(testCase, string(rows.version_label(1)), "1.0.0");
clear cleanup
end

function testTheRegisteredVersionIsAcceptedByCreateRun(testCase)
% The claim is not that a row inserts. It is that the row satisfies the path the
% workaround existed for.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = register(fixture, struct());

run = vawlume.attribution.createRun(fixture.conn, struct(recording_id=1), ...
    struct(run_key="from-registered-profile", attribution_path="imported", ...
        method="External Caller 2.0", ...
        settings_profile_version_id=result.profile_version_id, ...
        target_set=struct(detection_ids=1), ...
        participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1)), Apply=true);

verifyEqual(testCase, run.status, "created");
verifyEqual(testCase, double(run.run.settings_profile_version_id), ...
    result.profile_version_id);
clear cleanup
end

function testTheChecksumIsTheFilesOwnDigest(testCase)
% Not a placeholder and not the path's hash: the bytes' digest, so a later reader
% can confirm the file they hold is the one that was registered.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = register(fixture, struct());
writeText(fixture.settings_path, "{""threshold"": 0.9}" + newline);
second = register(fixture, struct(version_label="2.0.0"));

verifyNotEqual(testCase, first.checksum_sha256, second.checksum_sha256);
verifyEqual(testCase, strlength(second.checksum_sha256), 64);
clear cleanup
end

% --- paths ----------------------------------------------------------------

function testAFileUnderTheRepositoryIsStoredRelatively(testCase)
% A profile registered from config/ must cite a path that resolves on another
% machine, exactly as an imported profile does.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.db.registerProfileVersion(fixture.conn, ...
    struct(project_key="p1"), struct( ...
    profile_key="shipped-policy", profile_name="Shipped policy", ...
    version_label="0.1.0", profile_kind="attribution_policy", ...
    content_path=fullfile("config", "08_attribution_policies", ...
        "prototype_attribution_decision_policy.json")), ...
    RepoRoot=fixture.repo_root);

verifyEqual(testCase, result.content_uri, ...
    "config/08_attribution_policies/prototype_attribution_decision_policy.json");
verifyFalse(testCase, contains(result.content_uri, fixture.repo_root));
clear cleanup
end

function testAFileOutsideTheRepositoryKeepsItsAbsolutePath(testCase)
% Honest rather than portable. Pretending a machine-local path is relative would
% produce a citation that silently resolves to the wrong file elsewhere.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = register(fixture, struct());

verifyTrue(testCase, contains(result.content_uri, "/"));
verifyTrue(testCase, endsWith(result.content_uri, "demo_settings.json"));
verifyFalse(testCase, startsWith(result.content_uri, "config/"));
clear cleanup
end

function testAMissingFileIsRefusedByName(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() register(fixture, ...
    struct(content_path=fullfile(fixture.workspace, "absent.json"))), ...
    "vawlume:db:ProfileContentNotFound");
clear cleanup
end

% --- reuse and refusal ----------------------------------------------------

function testReregisteringAnIdenticalVersionReusesIt(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = register(fixture, struct());
second = register(fixture, struct());

verifyEqual(testCase, second.status, "reused");
verifyEqual(testCase, second.profile_version_id, first.profile_version_id);
verifyEqual(testCase, rowCount(fixture, "config_profile_versions"), 1);
verifyEqual(testCase, rowCount(fixture, "config_profiles"), 1);
clear cleanup
end

function testReregisteringTheSameLabelOverDifferentBytesIsRefused(testCase)
% The load-bearing refusal. Decisions and imported windows cite a version by ID;
% rewriting what that version denotes would silently re-point stored evidence.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
register(fixture, struct());
writeText(fixture.settings_path, "{""threshold"": 0.9}" + newline);

verifyError(testCase, @() register(fixture, struct()), ...
    "vawlume:db:ProfileVersionConflict");
% And nothing was written by the attempt.
verifyEqual(testCase, rowCount(fixture, "config_profile_versions"), 1);
clear cleanup
end

function testASecondVersionOfTheSameProfileIsCreatedNotRefused(testCase)
% Publishing a new version_label is the supported way to change content, so it
% must not be blocked by the rule that protects the old one.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = register(fixture, struct());
writeText(fixture.settings_path, "{""threshold"": 0.9}" + newline);
second = register(fixture, struct(version_label="2.0.0"));

verifyEqual(testCase, second.status, "created");
verifyEqual(testCase, second.profile_id, first.profile_id);
verifyNotEqual(testCase, second.profile_version_id, first.profile_version_id);
verifyEqual(testCase, rowCount(fixture, "config_profiles"), 1);
verifyEqual(testCase, rowCount(fixture, "config_profile_versions"), 2);
clear cleanup
end

function testChangingAProfilesKindIsRefused(testCase)
% The kind belongs to the profile, not to a version. A profile that meant two
% things would make every row citing it ambiguous.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
register(fixture, struct());
verifyError(testCase, @() register(fixture, ...
    struct(version_label="2.0.0", profile_kind="attribution_policy")), ...
    "vawlume:db:ProfileKindConflict");
clear cleanup
end

% --- validation -----------------------------------------------------------

function testAnUndeclaredProfileKindIsRefusedAgainstTheSchema(testCase)
% The vocabulary is read from the live config_profiles definition rather than
% from a list copied into MATLAB, so this fails for the schema's reason.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() register(fixture, ...
    struct(profile_kind="caller_vibes")), "vawlume:db:ProfileKindInvalid");
clear cleanup
end

function testEveryDeclaredKindIsAccepted(testCase)
% The complement of the test above, and the one that would catch a vocabulary
% parser that rejected everything. Each kind in the schema's own CHECK must pass.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
declared = ["project_input", "extractor_output", "extractor_settings", ...
    "recording_device", "experimental_setup", "external_stream_mapping", ...
    "alignment_anchor_mapping", "tracking_input_mapping", "analysis_settings", ...
    "consilience_policy", "attribution_input_mapping", "attribution_policy", ...
    "other"];
for index = 1:numel(declared)
    result = register(fixture, struct(profile_key="k" + string(index), ...
        profile_kind=declared(index)));
    verifyEqual(testCase, result.profile_kind, declared(index));
end
verifyEqual(testCase, rowCount(fixture, "config_profiles"), numel(declared));
clear cleanup
end

function testAMissingRequiredFieldIsRefusedByName(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() vawlume.db.registerProfileVersion(fixture.conn, ...
    struct(project_key="p1"), struct(profile_key="k", profile_name="n", ...
        version_label="1.0.0"), RepoRoot=fixture.repo_root), ...
    "vawlume:db:ProfileSpecInvalid");
clear cleanup
end

function testAnUnknownSpecFieldIsRefused(testCase)
% A misspelled option that was silently ignored would register a profile the
% caller did not describe.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() register(fixture, struct(profile_knid="oops")), ...
    "vawlume:db:ProfileSpecInvalid");
clear cleanup
end

function testAnAmbiguousProjectSelectorIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() vawlume.db.registerProfileVersion(fixture.conn, ...
    struct(project_id=1, project_key="p1"), settingsSpec(fixture, struct()), ...
    RepoRoot=fixture.repo_root), "vawlume:db:ProjectSelectorInvalid");
verifyError(testCase, @() vawlume.db.registerProfileVersion(fixture.conn, ...
    struct(project_key="absent"), settingsSpec(fixture, struct()), ...
    RepoRoot=fixture.repo_root), "vawlume:db:ProjectNotFound");
clear cleanup
end

function testTheFormatIsInferredFromTheExtension(testCase)
% A caller registering a .toml and getting 'json' recorded would have a row that
% misdescribes its own file.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
tomlPath = fullfile(fixture.workspace, "settings.toml");
writeText(tomlPath, "threshold = 0.5" + newline);
result = register(fixture, struct(content_path=tomlPath));
verifyEqual(testCase, result.content_format, "toml");

oddPath = fullfile(fixture.workspace, "settings.cfg");
writeText(oddPath, "threshold=0.5" + newline);
odd = register(fixture, struct(profile_key="odd", content_path=oddPath));
verifyEqual(testCase, odd.content_format, "other");
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function result = register(fixture, overrides)
result = vawlume.db.registerProfileVersion(fixture.conn, ...
    struct(project_key="p1"), settingsSpec(fixture, overrides), ...
    RepoRoot=fixture.repo_root);
end

function spec = settingsSpec(fixture, overrides)
spec = struct(profile_key="demo-settings", ...
    profile_name="Imported attribution run settings", ...
    version_label="1.0.0", content_path=fixture.settings_path);
names = string(fieldnames(overrides));
for name = names'
    spec.(name) = overrides.(name);
end
end

function value = rowCount(fixture, tableName)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function [fixture, cleanup] = setUpFixture()
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_profile_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
conn = sqlite(char(fullfile(workspace, "profile.sqlite")), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedFixture(conn);

settingsPath = fullfile(workspace, "demo_settings.json");
writeText(settingsPath, "{""threshold"": 0.5}" + newline);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=repoRoot, settings_path=string(settingsPath));
end

function tearDown(conn, workspace, sourcePath, addedPath)
try, close(conn); catch, end %#ok<NOCOM>
if isfolder(workspace), rmdir(workspace, "s"); end
if addedPath && contains(path, sourcePath)
    rmpath(sourcePath);
end
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'p1','Project 1')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','a.wav','a.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'mouse',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES(1,1,1,'participant'),(2,1,2,'participant')");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id," + ...
    "recording_id,start_time_s,end_time_s) VALUES(1,1,1,10.0,10.5)");
end

function writeText(pathValue, value)
fileId = fopen(pathValue, "w");
cleanupFile = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", value);
clear cleanupFile
end
