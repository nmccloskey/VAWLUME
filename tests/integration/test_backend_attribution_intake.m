function tests = test_backend_attribution_intake
%TEST_BACKEND_ATTRIBUTION_INTAKE Plan and apply a localization-backend export.
%
% The persistence half of the backend adapter, through the public
% vawlume.ingest.backendAttribution. Every refusal is asserted by identifier.
% Every number is compared exactly -- as a bit pattern -- against the double its
% source text denotes, never within a tolerance.
tests = functiontests(localfunctions);
end

% --- plan, then apply ------------------------------------------------------

function testPlanningWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, standardRows());
before = tableCounts(fixture);
plan = vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source);
verifyEqual(testCase, plan.status, "planned");
verifyFalse(testCase, plan.committed);
verifyEqual(testCase, height(plan.windows), 2);
verifyEqual(testCase, height(plan.estimates), 2);
verifyEqual(testCase, tableCounts(fixture), before, "Planning must write nothing.");
clear cleanup
end

function testApplyLandsTheExportWithItsProvenance(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, standardRows());
result = vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source, Apply=true);
verifyEqual(testCase, result.status, "imported");
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.applied_counts.imported_attribution_windows, 2);
verifyEqual(testCase, result.applied_counts.imported_attribution_claims, 2);
verifyEqual(testCase, result.applied_counts.attribution_localization_estimates, 2);

windows = fetch(fixture.conn, "SELECT w.native_window_id AS id, sf.file_role AS role, " + ...
    "sf.checksum_sha256 AS checksum, p.profile_kind AS kind " + ...
    "FROM imported_attribution_windows w " + ...
    "JOIN source_files sf ON sf.source_file_id = w.source_file_id " + ...
    "JOIN config_profile_versions v ON v.profile_version_id = w.mapping_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id ORDER BY w.native_window_id");
verifyEqual(testCase, string(windows.id)', ["s1" "s2"]);
verifyEqual(testCase, unique(string(windows.role)), "backend_attribution_output");
verifyEqual(testCase, unique(string(windows.kind)), "attribution_backend_mapping");
verifyEqual(testCase, strlength(string(windows.checksum(1))), 64);

estimates = fetch(fixture.conn, "SELECT e.coordinate_system_id AS frame, " + ...
    "e.source_file_id AS source, e.mapping_profile_version_id AS profile " + ...
    "FROM attribution_localization_estimates e");
verifyEqual(testCase, unique(double(estimates.frame)), 1);
verifyEqual(testCase, numel(unique(double(estimates.source))), 1);
clear cleanup
end

% --- exactness -------------------------------------------------------------

function testCoordinatesConfidencesAndScoresAreBitIdenticalToTheSource(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
xText = "10.123456789012345678";
yText = "-0.30000000000000004";
confidenceText = "7.250000000000001e-3";
scoreText = "0.1000000000000000055511151231257827";
source = writeSource(fixture, "s1,1.0,1.4,A," + scoreText + ",," + xText + "," + ...
    yText + "," + confidenceText + ",,,");
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source, Apply=true);
stored = fetch(fixture.conn, "SELECT position_x, position_y, confidence " + ...
    "FROM attribution_localization_estimates");
verifyBitIdentical(testCase, stored.position_x, xText);
verifyBitIdentical(testCase, stored.position_y, yText);
verifyBitIdentical(testCase, stored.confidence, confidenceText);
claim = fetch(fixture.conn, "SELECT score FROM imported_attribution_claims");
verifyBitIdentical(testCase, claim.score, scoreText);
clear cleanup
end

function testAbsentHeightAndConfidenceAreStoredAsNull(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "s1,1.0,1.4,A,,,10,20,,,,");
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source, Apply=true);
stored = fetch(fixture.conn, "SELECT typeof(position_z) AS z, typeof(confidence) AS c, " + ...
    "typeof(confidence_semantics) AS cs FROM attribution_localization_estimates");
verifyEqual(testCase, string(stored.z), "null");
verifyEqual(testCase, string(stored.c), "null");
verifyEqual(testCase, string(stored.cs), "null");
score = fetch(fixture.conn, "SELECT typeof(score) AS s FROM imported_attribution_claims");
verifyEqual(testCase, string(score.s), "null", "A label with no number stays NULL, never 1.0.");
clear cleanup
end

function testAHeightUnderAThreeDimensionalFrameIsStored(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @(entry) withHeightIn(entry, "arena_volume"));
source = writeSource(fixture, "s1,1.0,1.4,A,,,10,20,,,,", "z", "2.5");
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source, ...
    Apply=true, ProfilePath=profile);
stored = fetch(fixture.conn, "SELECT position_z, coordinate_system_id AS frame " + ...
    "FROM attribution_localization_estimates");
verifyEqual(testCase, double(stored.position_z), 2.5);
verifyEqual(testCase, double(stored.frame), 2);
clear cleanup
end

% --- section B resolutions, each refused by identifier ---------------------

function testAnUnknownFrameIsRefusedByName(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @(entry) withFrameKey(entry, "no_such_frame"));
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, standardRows()), ...
    ProfilePath=profile, Apply=true), "vawlume:attribution:LocalizationFrameUnknown");
clear cleanup
end

function testAnotherProjectsFrameIsADifferentRefusal(testCase)
% other_arena exists, but only in project 2. The key resolves -- to the wrong
% experiment -- which is a different problem from a missing declaration.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @(entry) withFrameKey(entry, "other_arena"));
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, standardRows()), ...
    ProfilePath=profile, Apply=true), "vawlume:attribution:LocalizationFrameScopeMismatch");
clear cleanup
end

function testAHeightUnderATwoDimensionalFrameIsRefusedBeforeAnyWrite(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @(entry) withHeightIn(entry, "arena_floor"));
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, "s1,1.0,1.4,A,,,10,20,,,,", "z", "2.5"), ...
    ProfilePath=profile, Apply=true), "vawlume:attribution:LocalizationDimensionMismatch");
clear cleanup
end

function testALabelResolvingOutsideTheParticipantSnapshotIsRefused(testCase)
% D is linked to the recording AFTER the run was created. The run's own
% snapshot is the participant set, so D is still not a participant.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "INSERT INTO recording_entity_links(recording_id,entity_id," + ...
    "link_type) VALUES(1,3,'participant')");
profile = variantProfile(fixture, @(entry) withLabelMap(entry, "D", "D"));
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, "s1,1.0,1.4,D,0.5,,10,20,,,,"), ...
    ProfilePath=profile, Apply=true), "vawlume:attribution:CallerLabelUnresolved");
clear cleanup
end

function testAChannelTheRecordingDoesNotDeclareIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @withThirdChannel);
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, "s1,1.0,1.4,A,,,10,20,,,-41,", "mic3", "-40"), ...
    ProfilePath=profile, Apply=true), "vawlume:attribution:ChannelIndexUndeclared");
clear cleanup
end

function testAnUnknownTrackingStreamIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @(entry) withTrackingStream(entry, "side_camera"));
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, standardRows()), ...
    ProfilePath=profile, Apply=true), "vawlume:attribution:TrackingStreamUnknown");
clear cleanup
end

function testATrackWithNoRecordedAssociationIsRefused(testCase)
% A video-derived association is evidence somebody recorded, not something an
% importer may assert.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, "s1,1.0,1.4,A,0.7,t9,10,20,,,,"), ...
    Apply=true), "vawlume:attribution:IdentityAssociationNotFound");
verifyEqual(testCase, countOf(fixture, "tracking_identity_associations"), 1);
clear cleanup
end

function testANonBackendRunIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
imported = vawlume.attribution.createRun(fixture.conn, struct(recording_id=1), ...
    struct(run_key="imported-run", attribution_path="imported", ...
        method="External Caller 2.0", settings_profile_version_id=fixture.settings_version_id, ...
        target_set=struct(detection_ids=[1 2]), participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1)), Apply=true);
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, struct(attribution_run_id=imported.run.attribution_run_id), ...
    writeSource(fixture, standardRows()), Apply=true), "vawlume:attribution:RunPathMismatch");
clear cleanup
end

function testAnImportedProfileIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importedProfile = fullfile(fixture.repo_root, "config", "01_mapping_profiles", ...
    "attribution", "generic_imported_attribution_profile.json");
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), writeSource(fixture, standardRows()), ...
    ProfilePath=importedProfile, Apply=true), "vawlume:attribution:ProfileKindInvalid");
clear cleanup
end

% --- section D: one apply, atomically --------------------------------------

function testASecondApplyIsRefusedByName(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, standardRows());
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source, Apply=true);
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.ingest.backendAttribution( ...
    fixture.conn, runRef(fixture), source, Apply=true), ...
    "vawlume:attribution:ImportAlreadyApplied");
clear cleanup
end

function testImportIsAtomic(testCase)
% The induced failure is keyed on a count certain to be reached -- the SECOND
% estimate of an export that always has two -- after the windows, claims and
% first estimate are written, and the test asserts that it propagated. A test
% that only checked "nothing was written" would pass vacuously if the trigger
% never fired. testTheInducedFailurePointIsReachable is its control.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, standardRows());
before = tableCounts(fixture);
execute(fixture.conn, "CREATE TRIGGER trg_induced_backend_failure " + ...
    "BEFORE INSERT ON attribution_localization_estimates FOR EACH ROW " + ...
    "WHEN (SELECT COUNT(*) FROM attribution_localization_estimates) >= 1 " + ...
    "BEGIN SELECT RAISE(ABORT,'induced late backend failure'); END");
threw = false;
message = "";
try
    vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), source, Apply=true);
catch err
    threw = true;
    message = string(err.message);
end
execute(fixture.conn, "DROP TRIGGER trg_induced_backend_failure");
verifyTrue(testCase, threw, "The induced failure must propagate.");
verifyTrue(testCase, contains(message, "induced late backend failure"), ...
    "The apply failed, but not at the induced point: " + message);
verifyEqual(testCase, tableCounts(fixture), before, ...
    "A failed apply must leave no window, claim, estimate, attribute or provenance row.");
clear cleanup
end

function testTheInducedFailurePointIsReachable(testCase)
% Control for the atomicity test: the same export does reach a second estimate,
% after the windows and claims, so the induced trigger's condition is reached.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, standardRows()), Apply=true);
verifyEqual(testCase, result.applied_counts.attribution_localization_estimates, 2);
verifyGreaterThan(testCase, result.applied_counts.imported_attribution_windows, 0);
clear cleanup
end

% --- native fields: preserved, never canonical -----------------------------

function testNativeFieldsArePreservedApartFromCanonicalColumns(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, "s1,1.0,1.4,A,0.7,,10,20,0.9,,,3.50"), Apply=true);
attribute = fetch(fixture.conn, "SELECT attribute_name AS name, value_type AS type, " + ...
    "value_real AS value, native_raw_token AS token, unit, " + ...
    "IFNULL(attribution_localization_estimate_id,-1) AS estimate " + ...
    "FROM attribution_native_attributes WHERE attribute_name='localization_error_major_axis'");
verifyEqual(testCase, string(attribute.type), "real");
verifyEqual(testCase, double(attribute.value), 3.5);
verifyEqual(testCase, string(attribute.token), "3.50");
verifyEqual(testCase, string(attribute.unit), "cm");
verifyGreaterThan(testCase, double(attribute.estimate), 0);
% The canonical confidence is the declared confidence column, untouched by the
% native field beside it.
estimate = fetch(fixture.conn, "SELECT confidence FROM attribution_localization_estimates");
verifyEqual(testCase, double(estimate.confidence), 0.9);
clear cleanup
end

function testChannelEvidenceIsPreservedOnItsWindowWithItsSemantics(testCase)
% F5.3-1 option (a): per-channel evidence has no window-grain relational home,
% so it is preserved as window-owned native attributes, after the channel was
% checked to exist on the recording.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, "s1,1.0,1.4,A,,,10,20,,-41.25,-45,"), Apply=true);
rows = fetch(fixture.conn, "SELECT attribute_name AS name, value_type AS type, " + ...
    "IFNULL(value_real,-999.0) AS value, IFNULL(value_text,'') AS text, " + ...
    "IFNULL(unit,'') AS unit FROM attribution_native_attributes " + ...
    "WHERE attribute_name LIKE 'channel:%' ORDER BY attribute_name");
names = string(rows.name)';
verifyEqual(testCase, names, ["channel:1:backend_channel_power", ...
    "channel:1:backend_channel_power:semantics", "channel:2:backend_channel_power", ...
    "channel:2:backend_channel_power:semantics"]);
verifyEqual(testCase, double(rows.value(1)), -41.25);
verifyEqual(testCase, string(rows.unit(1)), "dB");
verifyTrue(testCase, contains(string(rows.text(2)), "Example Localization Backend"));
verifyEqual(testCase, countOf(fixture, "attribution_evidence"), 0);
clear cleanup
end

function testATrackReferenceIsPreservedOnItsClaim(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, "s1,1.0,1.4,A,0.7,t1,10,20,,,,"), Apply=true);
row = fetch(fixture.conn, "SELECT a.value_text AS track, c.source_caller_label AS label " + ...
    "FROM attribution_native_attributes a JOIN imported_attribution_claims c " + ...
    "ON c.imported_attribution_claim_id = a.imported_attribution_claim_id " + ...
    "WHERE a.attribute_name='track_reference:overhead_pose'");
verifyEqual(testCase, string(row.track), "t1");
verifyEqual(testCase, string(row.label), "A");
clear cleanup
end

% --- declared inputs --------------------------------------------------------

function testDeclaredInputsAreStoredWithTheProfileThatDeclaredThem(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, @withDeclarations);
vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, standardRows()), ProfilePath=profile, Apply=true);
rows = fetch(fixture.conn, "SELECT d.input_dimension AS dimension, d.declaration, " + ...
    "p.profile_kind AS kind FROM attribution_run_declared_inputs d " + ...
    "JOIN config_profile_versions v ON v.profile_version_id = d.declared_by_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id ORDER BY d.input_dimension");
verifyEqual(testCase, string(rows.dimension)', ["acoustic" "visual_identity"]);
verifyEqual(testCase, string(rows.declaration)', ["used" "not_used"]);
verifyEqual(testCase, unique(string(rows.kind)), "attribution_backend_mapping");
clear cleanup
end

% --- unmappable rows, and the boundary --------------------------------------

function testUnmappableRowsAreReportedAndTheRestApplied(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, ["s1,1.0,1.4,A,0.7,,10,20,,,,"; "s2,3.0,2.0,B,0.4,,11,21,,,,"]), ...
    Apply=true);
verifyEqual(testCase, result.unmapped_rows, 1);
verifyEqual(testCase, result.issues.code, "ATTRIBUTION_WINDOW_REVERSED");
verifyEqual(testCase, countOf(fixture, "imported_attribution_windows"), 1);
clear cleanup
end

function testIntakeWritesNoCandidateEvidenceOrCorrespondence(testCase)
% Tripwire 2. A backend's claim and estimate are not VAWLUME's attribution
% result; promoting either onto a target is explicit and later.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.ingest.backendAttribution(fixture.conn, runRef(fixture), ...
    writeSource(fixture, standardRows()), Apply=true);
verifyEqual(testCase, countOf(fixture, "attribution_candidates"), 0);
verifyEqual(testCase, countOf(fixture, "attribution_evidence"), 0);
verifyEqual(testCase, countOf(fixture, "attribution_window_correspondences"), 0);
verifyEqual(testCase, result.not_written, ["attribution_candidates"; ...
    "attribution_evidence"; "attribution_window_correspondences"]);
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function rows = standardRows()
% Two windows; s1 carries two caller rows sharing one estimate, a track and
% channel evidence; s2 carries a localization only.
rows = [
    "s1,1.0,1.4,A,0.7,t1,10,20,0.9,-41,-45,3.5"
    "s1,1.0,1.4,B,0.2,,10,20,0.9,-41,-45,3.5"
    "s2,2.0,2.3,,,,30,5,,,,"];
end

function verifyBitIdentical(testCase, stored, text)
verifyTrue(testCase, isequal(typecast(double(stored), "uint64"), ...
    typecast(str2double(text), "uint64")), ...
    "Stored " + sprintf("%.17g", double(stored)) + " is not the double denoted by " + text);
end

function verifyRefusedWritingNothing(testCase, fixture, action, identifier)
before = tableCounts(fixture);
refused = false;
observed = "";
try
    action();
catch err
    refused = true;
    observed = string(err.identifier);
end
verifyTrue(testCase, refused, "Expected a refusal identified as " + identifier);
verifyEqual(testCase, observed, string(identifier));
verifyEqual(testCase, tableCounts(fixture), before, "A refusal must write nothing.");
end

function counts = tableCounts(fixture)
names = ["source_files", "config_profile_versions", "imported_attribution_windows", ...
    "imported_attribution_claims", "attribution_localization_estimates", ...
    "attribution_native_attributes", "attribution_run_declared_inputs"];
counts = zeros(1, numel(names));
for index = 1:numel(names)
    counts(index) = countOf(fixture, names(index));
end
end

function value = countOf(fixture, tableName)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function value = runRef(fixture)
value = struct(attribution_run_id=fixture.attribution_run_id);
end

function path = writeSource(fixture, rows, extraColumn, extraValue)
header = "segment_id,start_s,end_s,candidate,assignment_score,track,source_x," + ...
    "source_y,localization_confidence,mic1_power,mic2_power,err_major";
if nargin > 2
    header = header + "," + extraColumn;
    rows = rows + "," + extraValue;
end
path = fullfile(fixture.workspace, "backend_export_" + ...
    string(java.util.UUID.randomUUID) + ".csv");
fileId = fopen(path, "w");
fprintf(fileId, "%s\n", header);
for index = 1:numel(rows)
    fprintf(fileId, "%s\n", rows(index));
end
fclose(fileId);
end

function path = variantProfile(fixture, mutate)
% A modified copy of the shipped template, with its own profile version so it
% never collides with the shipped one in config_profile_versions.
document = jsondecode(fileread(fullfile(fixture.repo_root, "config", ...
    "01_mapping_profiles", "attribution", "generic_backend_attribution_profile.json")));
entry = mutate(document.profiles);
entry.profile.id = "test.backend.variant." + strrep(string(java.util.UUID.randomUUID), "-", "");
document.profiles = entry;
path = fullfile(fixture.workspace, "variant_" + string(java.util.UUID.randomUUID) + ".json");
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document, PrettyPrint=true));
fclose(fileId);
end

function entry = withFrameKey(entry, key)
entry.context.coordinate_system_key = key;
end

function entry = withHeightIn(entry, key)
entry.context.coordinate_system_key = key;
entry.localization.position_z = struct(source_field="z");
end

function entry = withLabelMap(entry, label, entityNativeId)
entry.caller_label_resolution.map(end+1) = struct(caller_label=label, ...
    entity_native_id=entityNativeId);
end

function entry = withThirdChannel(entry)
entry.channel_evidence.declared_channel_indices = [1; 2; 3];
third = entry.channel_evidence.entries(1);
third.channel_index = 3;
third.value_field = "mic3";
entry.channel_evidence.entries(end+1) = third;
end

function entry = withTrackingStream(entry, key)
entry.context.tracking_stream_key = key;
end

function entry = withDeclarations(entry)
entry.declared_inputs.declarations = struct(acoustic="used", visual_identity="not_used");
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repositoryRoot();
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_backend_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "backend.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedFixture(conn);

% The run's settings profile is registered through the public path, not by SQL.
settingsPath = fullfile(workspace, "backend_settings.json");
fileId = fopen(settingsPath, "w");
fprintf(fileId, "{""note"": ""synthetic backend run settings""}");
fclose(fileId);
settings = vawlume.db.registerProfileVersion(conn, struct(project_id=1), struct( ...
    profile_key="backend-settings", profile_name="Backend run settings", ...
    version_label="1.0.0", content_path=settingsPath));
settingsVersionId = settings.profile_version_id;

run = vawlume.attribution.createRun(conn, struct(recording_id=1), ...
    struct(run_key="phase54-backend", attribution_path="backend", ...
        method="Example Localization Backend", ...
        settings_profile_version_id=settingsVersionId, ...
        target_set=struct(detection_ids=[1 2]), ...
        participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1), ...
        notes="Synthetic Phase 5.4 fixture."), Apply=true);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), settings_version_id=settingsVersionId, ...
    attribution_run_id=run.run.attribution_run_id);
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
    "VALUES(1,'p1','Project 1'),(2,'p2','Project 2')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','audio.wav','audio.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index) VALUES(1,1,1),(2,1,2)");
% arena_floor (2D) and arena_volume (3D) belong to project 1; other_arena exists
% only in project 2.
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) VALUES" + ...
    "(1,1,'arena_floor','Arena floor',2,'cm'),(2,1,'arena_volume','Arena volume',3,'cm')," + ...
    "(3,2,'other_arena','Another experiment',2,'cm')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
% Entity D exists but is deliberately not a participant of the run.
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'D')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES" + ...
    "(1,1,1,'participant'),(2,1,2,'participant')");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5),(2,1,1,2.0,2.4)");
% One tracking stream, overhead_pose, with one recorded association for track t1.
execute(conn, "INSERT INTO timebases(timebase_id,project_id,recording_id,timebase_name," + ...
    "timebase_kind,native_unit) VALUES(1,1,1,'video_clock','video_frames','s')");
execute(conn, "INSERT INTO external_streams(external_stream_id,project_id,recording_id," + ...
    "timebase_id,stream_name,stream_kind) VALUES(1,1,1,1,'overhead_pose','tracking')");
execute(conn, "INSERT INTO tracking_streams(external_stream_id,coordinate_system_id," + ...
    "native_time_basis) VALUES(1,1,'time')");
execute(conn, "INSERT INTO tracking_identity_associations(external_stream_id," + ...
    "native_track_id,entity_id,start_time_native,end_time_native,assignment_state," + ...
    "evidence_kind) VALUES(1,'t1',1,0,100,'assigned','manual_review')");
end

function root = repositoryRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
