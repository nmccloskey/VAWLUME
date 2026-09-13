function tests = test_imported_attribution_intake
%TEST_IMPORTED_ATTRIBUTION_INTAKE Phase 4.8 generic imported attribution path.
%
% The claim this suite defends is that VAWLUME can hold somebody else's
% attribution result without changing it. The load-bearing tests are the
% bit-identity ones: a value that arrived as 0.9137 is stored as 0.9137 and not
% as anything tidier, because a re-normalized imported score is unauditable
% forever -- the original is gone.
%
% The second claim is a boundary: intake relates imported windows to no VAWLUME
% event. Everything needed to do so is deliberately absent.
tests = functiontests({ ...
    @testPlanningWritesNothingAndReportsWhatItCouldNotMap, ...
    @testImportLandsWindowsWithProvenance, ...
    @testWindowTimesAreBitIdenticalToTheSourceFile, ...
    @testClaimValuesAreBitIdenticalToTheSourceFile, ...
    @testALabelWithNoNumberStaysAbsentRatherThanBecomingOne, ...
    @testScoreAndProbabilityKeepSeparateSemantics, ...
    @testUndeclaredCallerLabelIsRefusedByName, ...
    @testLabelResolvingOutsideTheParticipantSetIsRefused, ...
    @testProbabilityOutsideUnitIntervalIsReportedNotClamped, ...
    @testReversedWindowIsReportedNotDropped, ...
    @testImportIsAtomic, ...
    @testASecondImportIsRefused, ...
    @testNonImportedRunIsRefused, ...
    @testIntakeRelatesWindowsToNoVawlumeEvent});
end

% --- planning and preview -------------------------------------------------

function testPlanningWritesNothingAndReportsWhatItCouldNotMap(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9137,0.8812"; ...
    "w2,22.5,23.1,A,0.7700,0.7000"; ...
    "w3,30.0,29.0,A,0.5000,0.5000"]);      % ends before it starts

plan = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source);

verifyEqual(testCase, plan.status, "planned");
verifyFalse(testCase, plan.committed);
verifyEqual(testCase, height(plan.windows), 2);
verifyEqual(testCase, height(plan.claims), 2);
verifyEqual(testCase, plan.unmapped_rows, 1);
% Reported, not dropped. A preview that hides what it could not read is worse
% than one that reads nothing.
verifyEqual(testCase, height(plan.issues), 1);
verifyTrue(testCase, contains(plan.issues.code(1), "WINDOW_REVERSED"));
verifyEqual(testCase, windowRowCount(fixture), 0);
clear cleanup
end

% --- what lands -----------------------------------------------------------

function testImportLandsWindowsWithProvenance(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9137,0.8812"; ...
    "w1,10.0,10.4,B,0.4210,0.1188"; ...
    "w2,22.5,23.1,A,0.7700,0.7000"]);

result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);
verifyEqual(testCase, result.status, "imported");
verifyEqual(testCase, result.applied_counts.imported_attribution_windows, 2);

stored = fetch(fixture.conn, "SELECT w.native_window_id AS id, " + ...
    "IFNULL(w.source_caller_label,'') AS labels, " + ...
    "IFNULL(f.checksum_sha256,'') AS file_checksum, " + ...
    "IFNULL(v.checksum_sha256,'') AS profile_checksum, " + ...
    "p.profile_kind AS profile_kind " + ...
    "FROM imported_attribution_windows w " + ...
    "JOIN source_files f ON f.source_file_id = w.source_file_id " + ...
    "JOIN config_profile_versions v ON v.profile_version_id = w.mapping_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id " + ...
    "ORDER BY w.imported_attribution_window_id");

verifyEqual(testCase, presentText(stored.id)', ["w1" "w2"]);
% Both labels claimed over w1 are recorded verbatim on the window.
verifyEqual(testCase, presentText(stored.labels(1)), "A|B");
% Origin is recoverable: which file, which bytes, which profile version.
verifyEqual(testCase, strlength(presentText(stored.file_checksum(1))), 64);
verifyEqual(testCase, strlength(presentText(stored.profile_checksum(1))), 64);
verifyEqual(testCase, presentText(stored.profile_kind(1)), "attribution_input_mapping");
clear cleanup
end

function testWindowTimesAreBitIdenticalToTheSourceFile(testCase)
% Exact comparison, not a tolerance. The claim is that nothing was transformed.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.123456789,10.987654321,A,0.5,0.5"; ...
    "w2,22.000000001,23.999999999,B,0.5,0.5"]);
vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

stored = fetch(fixture.conn, "SELECT start_time_native AS s, end_time_native AS e " + ...
    "FROM imported_attribution_windows ORDER BY imported_attribution_window_id");
verifyEqual(testCase, double(stored.s)', [10.123456789 22.000000001]);
verifyEqual(testCase, double(stored.e)', [10.987654321 23.999999999]);
clear cleanup
end

function testClaimValuesAreBitIdenticalToTheSourceFile(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,1234.56789,0.8812"; ...
    "w1,10.0,10.4,B,-0.0001,0.1188"]);
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

% A score is unconstrained: a value far outside [0,1] and a negative one both
% survive untouched, because they are the exporter's scale and not VAWLUME's.
verifyEqual(testCase, double(result.claims.score)', [1234.56789 -0.0001]);
verifyEqual(testCase, double(result.claims.probability)', [0.8812 0.1188]);
clear cleanup
end

function testALabelWithNoNumberStaysAbsentRatherThanBecomingOne(testCase)
% Converting a name into certainty is the specific failure this refuses.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "w1,10.0,10.4,A,,");
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

verifyEqual(testCase, height(result.claims), 1);
verifyTrue(testCase, isnan(double(result.claims.score(1))));
verifyTrue(testCase, isnan(double(result.claims.probability(1))));
verifyEqual(testCase, presentText(result.claims.score_semantics(1)), "");
clear cleanup
end

function testScoreAndProbabilityKeepSeparateSemantics(testCase)
% Different quantities on different scales. Nothing converts between them, and
% each carries its own statement of what it meant where it came from.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "w1,10.0,10.4,A,42.7,0.8812");
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

scoreSemantics = presentText(result.claims.score_semantics(1));
probabilitySemantics = presentText(result.claims.probability_semantics(1));
verifyNotEqual(testCase, scoreSemantics, probabilitySemantics);
verifyTrue(testCase, contains(scoreSemantics, "uncalibrated"));
verifyTrue(testCase, contains(scoreSemantics, "not a probability"));
verifyTrue(testCase, contains(probabilitySemantics, "not validated by VAWLUME"));
clear cleanup
end

% --- refusals -------------------------------------------------------------

function testUndeclaredCallerLabelIsRefusedByName(testCase)
% A label is a string in somebody else's file. Nothing infers which entity it
% denotes, and nothing creates an entity to accommodate it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9,0.9"; ...
    "w2,20.0,20.4,Z,0.9,0.9"]);
plan = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source);

% The undeclared label is reported by name rather than silently excluded.
verifyEqual(testCase, height(plan.claims), 1);
verifyTrue(testCase, any(contains(plan.issues.code, "CALLER_LABEL_UNDECLARED")));
verifyTrue(testCase, any(contains(plan.issues.message, "'Z'")));
clear cleanup
end

function testLabelResolvingOutsideTheParticipantSetIsRefused(testCase)
% Declared in the profile, but naming an animal that was never in the recording.
% A surfaced problem, not a new entity.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = variantProfile(fixture, struct(caller_label="A", entity_native_id="D"));
source = writeSource(fixture, "w1,10.0,10.4,A,0.9,0.9");
verifyRefused(testCase, ...
    @() vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, ...
        ProfilePath=profile), ...
    "vawlume:attribution:CallerLabelUnresolved");
clear cleanup
end

function testProbabilityOutsideUnitIntervalIsReportedNotClamped(testCase)
% Clamping would silently rewrite the exporter's claim into one it never made.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9,0.9"; ...
    "w2,20.0,20.4,B,0.9,1.7"]);
plan = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source);

verifyEqual(testCase, height(plan.claims), 1);
verifyTrue(testCase, any(contains(plan.issues.code, "PROBABILITY_OUT_OF_RANGE")));
verifyTrue(testCase, any(contains(plan.issues.message, "refused rather than clamped")));
clear cleanup
end

function testReversedWindowIsReportedNotDropped(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9,0.9"; ...
    "w2,30.0,29.0,B,0.9,0.9"]);
plan = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source);
verifyEqual(testCase, plan.unmapped_rows, 1);
verifyTrue(testCase, any(contains(plan.issues.code, "WINDOW_REVERSED")));
clear cleanup
end

function testNonImportedRunIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE attribution_runs SET attribution_path='backend' " + ...
    "WHERE attribution_run_id=" + string(fixture.attribution_run_id));
source = writeSource(fixture, "w1,10.0,10.4,A,0.9,0.9");
verifyRefused(testCase, ...
    @() vawlume.ingest.attribution(fixture.conn, runRef(fixture), source), ...
    "vawlume:attribution:RunPathMismatch");
clear cleanup
end

function testASecondImportIsRefused(testCase)
% Evidence is append-only, so a second apply would duplicate rather than
% reconcile. Refusing is honest; silently appending is not.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "w1,10.0,10.4,A,0.9,0.9");
vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);
verifyRefused(testCase, ...
    @() vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true), ...
    "vawlume:attribution:ImportAlreadyApplied");
verifyEqual(testCase, windowRowCount(fixture), 1);
clear cleanup
end

% --- atomicity and boundary ----------------------------------------------

function testImportIsAtomic(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9,0.9"; ...
    "w2,20.0,20.4,B,0.8,0.8"; ...
    "w3,30.0,30.4,A,0.7,0.7"]);
before = windowRowCount(fixture);
sourceFilesBefore = sourceFileCount(fixture);

% Keyed on a count certain to be reached, not on an ordering assumption.
execute(fixture.conn, "CREATE TRIGGER trg_induced_import_failure " + ...
    "BEFORE INSERT ON imported_attribution_windows FOR EACH ROW " + ...
    "WHEN (SELECT COUNT(*) FROM imported_attribution_windows) >= 2 " + ...
    "BEGIN SELECT RAISE(ABORT,'induced late import failure'); END");
threw = false;
try
    vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);
catch
    threw = true;
end
execute(fixture.conn, "DROP TRIGGER trg_induced_import_failure");

verifyTrue(testCase, threw, "The induced failure must propagate.");
verifyEqual(testCase, windowRowCount(fixture), before, ...
    "A failed import must leave no partial window.");
% The provenance rows written before the failure roll back with it.
verifyEqual(testCase, sourceFileCount(fixture), sourceFilesBefore);
clear cleanup
end

function testIntakeRelatesWindowsToNoVawlumeEvent(testCase)
% The tripwire. Intake lands imported windows; associating them with a detection
% or consensus event is correspondence work with its own eligibility rule.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9,0.9"; ...
    "w2,20.0,20.4,B,0.8,0.8"]);
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

correspondences = fetch(fixture.conn, "SELECT COUNT(*) AS n " + ...
    "FROM attribution_window_correspondences");
verifyEqual(testCase, double(correspondences.n(1)), 0);
% And no candidate or evidence row either: a candidate belongs to
% (target, entity) and an imported claim to (window, entity), so mapping one
% onto the other without correspondence would assert a match that does not
% exist. See P4-5.
candidates = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_candidates");
evidence = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_evidence");
verifyEqual(testCase, double(candidates.n(1)), 0);
verifyEqual(testCase, double(evidence.n(1)), 0);
% The claims are still returned intact, so nothing was lost.
verifyEqual(testCase, height(result.claims), 2);
verifyEqual(testCase, result.correspondence, ...
    "none; 4.9 relates these windows to VAWLUME events");
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function verifyRefused(testCase, action, identifier)
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
end

function value = runRef(fixture)
value = struct(attribution_run_id=fixture.attribution_run_id);
end

function path = writeSource(fixture, rows)
path = fullfile(fixture.workspace, "caller_export_" + ...
    string(java.util.UUID.randomUUID) + ".csv");
fileId = fopen(path, "w");
fprintf(fileId, "window_id,start_s,end_s,caller,score,probability\n");
for index = 1:numel(rows)
    fprintf(fileId, "%s\n", rows(index));
end
fclose(fileId);
end

function path = variantProfile(fixture, mapping)
document = jsondecode(fileread(fullfile(fixture.repo_root, "config", ...
    "01_mapping_profiles", "attribution", ...
    "generic_imported_attribution_profile.json")));
document.profiles.caller_label_resolution.map = mapping;
path = fullfile(fixture.workspace, "variant_profile.json");
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document, PrettyPrint=true));
fclose(fileId);
end

function value = windowRowCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM imported_attribution_windows");
value = double(rows.n(1));
end

function value = sourceFileCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM source_files");
value = double(rows.n(1));
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_import_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "import.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedFixture(conn);

run = vawlume.attribution.createRun(conn, struct(recording_id=1), ...
    struct(run_key="phase48-import", attribution_path="imported", ...
        method="External Caller 2.0", settings_profile_version_id=1, ...
        target_set=struct(detection_ids=[1 2]), ...
        participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1), ...
        notes="Synthetic Phase 4.8 fixture."), Apply=true);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
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
    "VALUES(1,'p1','Project 1')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','audio.wav','audio.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
% Entity D exists but is deliberately not a participant of the run.
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'D')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES" + ...
    "(1,1,1,'participant'),(2,1,2,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key," + ...
    "profile_name,profile_kind) VALUES" + ...
    "(1,1,'import-settings','Import settings','analysis_settings')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id," + ...
    "version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1.0.0','json','config/settings.json'," + ...
    "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(1,1,1,10.0,10.5),(2,1,1,22.0,23.0)");
end

function root = repoRootForTest()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
