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
    @testEachClaimIsItsOwnRowWithItsOwnLabelAndValue, ...
    @testStoredClaimValuesAreBitIdenticalAndCarryTheirSemantics, ...
    @testAStoredClaimWithNoNumberStaysNullRatherThanBecomingOne, ...
    @testWindowTimesAreBitIdenticalToTheSourceFile, ...
    @testClaimValuesAreBitIdenticalToTheSourceFile, ...
    @testALabelWithNoNumberStaysAbsentRatherThanBecomingOne, ...
    @testScoreAndProbabilityKeepSeparateSemantics, ...
    @testStoredSemanticsNamesTheExportingSystem, ...
    @testSemanticsNamesTheProducerEvenWhenTheProfileNeverMentionsIt, ...
    @testAnUnknownExporterVersionIsOmittedRatherThanRendered, ...
    @testRenderingTheSemanticsChangesNoStoredNumber, ...
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
verifyEqual(testCase, result.applied_counts.imported_attribution_claims, 3);

stored = fetch(fixture.conn, "SELECT w.native_window_id AS id, " + ...
    "IFNULL(f.checksum_sha256,'') AS file_checksum, " + ...
    "IFNULL(v.checksum_sha256,'') AS profile_checksum, " + ...
    "p.profile_kind AS profile_kind " + ...
    "FROM imported_attribution_windows w " + ...
    "JOIN source_files f ON f.source_file_id = w.source_file_id " + ...
    "JOIN config_profile_versions v ON v.profile_version_id = w.mapping_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id " + ...
    "ORDER BY w.imported_attribution_window_id");

verifyEqual(testCase, presentText(stored.id)', ["w1" "w2"]);
% Origin is recoverable: which file, which bytes, which profile version.
verifyEqual(testCase, strlength(presentText(stored.file_checksum(1))), 64);
verifyEqual(testCase, strlength(presentText(stored.profile_checksum(1))), 64);
verifyEqual(testCase, presentText(stored.profile_kind(1)), "attribution_input_mapping");
clear cleanup
end

function testEachClaimIsItsOwnRowWithItsOwnLabelAndValue(testCase)
% P4-5. Two callers claimed over one window are two rows, each carrying its own
% verbatim label and its own number. Before 0.10-draft the window held 'A|B' --
% a string no source file contained -- and the two scores were discarded, so a
% number could not be attributed to the caller it belonged to.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.0,10.4,A,0.9137,0.8812"; ...
    "w1,10.0,10.4,B,0.4210,0.1188"]);
vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

stored = fetch(fixture.conn, "SELECT c.claim_ordinal AS ordinal, " + ...
    "c.source_caller_label AS label, e.native_id AS entity, " + ...
    "c.score AS score, c.probability AS probability " + ...
    "FROM imported_attribution_claims c " + ...
    "JOIN experimental_entities e ON e.entity_id = c.entity_id " + ...
    "JOIN imported_attribution_windows w " + ...
    "  ON w.imported_attribution_window_id = c.imported_attribution_window_id " + ...
    "WHERE w.native_window_id='w1' ORDER BY c.claim_ordinal");

verifyEqual(testCase, height(stored), 2);
verifyEqual(testCase, presentText(stored.label)', ["A" "B"]);
% The label resolved to an entity, and each caller kept its own number.
verifyEqual(testCase, presentText(stored.entity)', ["A" "B"]);
verifyEqual(testCase, double(stored.score)', [0.9137 0.4210]);
verifyEqual(testCase, double(stored.probability)', [0.8812 0.1188]);
% No synthesized multi-value label survives anywhere.
verifyFalse(testCase, any(contains(presentText(stored.label), "|")));
clear cleanup
end

function testStoredClaimValuesAreBitIdenticalAndCarryTheirSemantics(testCase)
% The claim travels with the sentence that makes it interpretable. Exact
% comparison, not a tolerance: the claim is that nothing was transformed.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "w1,10.0,10.4,A,1234.56789,0.8812");
vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

stored = fetch(fixture.conn, "SELECT score, score_semantics AS ss, " + ...
    "probability, probability_semantics AS ps FROM imported_attribution_claims");
verifyEqual(testCase, double(stored.score(1)), 1234.56789);
verifyEqual(testCase, double(stored.probability(1)), 0.8812);
verifyTrue(testCase, contains(presentText(stored.ss(1)), "uncalibrated"));
verifyTrue(testCase, contains(presentText(stored.ss(1)), "not a probability"));
verifyTrue(testCase, contains(presentText(stored.ps(1)), "not validated by VAWLUME"));
clear cleanup
end

function testAStoredClaimWithNoNumberStaysNullRatherThanBecomingOne(testCase)
% The failure this refuses, now at the storage layer rather than only in the
% returned plan: a label with no number must not acquire certainty on its way in.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "w1,10.0,10.4,A,,");
vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

stored = fetch(fixture.conn, "SELECT " + ...
    "SUM(score IS NULL) AS null_scores, " + ...
    "SUM(probability IS NULL) AS null_probabilities, " + ...
    "SUM(score IS NOT NULL) AS present_scores, " + ...
    "COUNT(*) AS n FROM imported_attribution_claims");
verifyEqual(testCase, double(stored.n(1)), 1);
verifyEqual(testCase, double(stored.null_scores(1)), 1);
verifyEqual(testCase, double(stored.null_probabilities(1)), 1);
% Not zero, not one, not any other substitute.
verifyEqual(testCase, double(stored.present_scores(1)), 0);
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

% --- the stored semantics names its producer (F4-1) ------------------------

function testStoredSemanticsNamesTheExportingSystem(testCase)
% Before 4.12a the shipped profile said "producer declared in
% context.exporting_system" and that string was stored verbatim, so a reader
% holding only the database got a pointer into a file they might not have.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "w1,10.0,10.4,A,0.91,0.87");
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

producer = "Example Caller Attribution System";
verifyTrue(testCase, contains(presentText(result.claims.score_semantics(1)), ...
    "producer=" + producer));
verifyTrue(testCase, contains(presentText(result.claims.probability_semantics(1)), ...
    "producer=" + producer));
% And the pointer it replaced is gone from what was stored.
verifyFalse(testCase, contains(presentText(result.claims.score_semantics(1)), ...
    "declared in context"));
% Read back from the database rather than from the plan: this is what a later
% reader actually gets.
stored = fetch(fixture.conn, "SELECT score_semantics FROM " + ...
    "imported_attribution_claims ORDER BY imported_attribution_claim_id");
verifyTrue(testCase, contains(string(stored.score_semantics(1)), producer));
clear cleanup
end

function testSemanticsNamesTheProducerEvenWhenTheProfileNeverMentionsIt(testCase)
% The load-bearing half. The test above passes for a profile whose wording
% happens to be right; this one proves the guarantee holds for a profile VAWLUME
% did not ship, which is the case the invariant exists for.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = semanticsProfile(fixture, struct( ...
    score="A number. Nothing else is claimed about it.", ...
    probability="Another number."), "Somebody Else's Tool", "3.1");
source = writeSource(fixture, "w1,10.0,10.4,A,0.91,0.87");
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, ...
    ProfilePath=profile, Apply=true);

scoreSemantics = presentText(result.claims.score_semantics(1));
verifyTrue(testCase, startsWith(scoreSemantics, "A number."));
verifyTrue(testCase, endsWith(scoreSemantics, "; producer=Somebody Else's Tool 3.1"));
verifyTrue(testCase, contains(presentText(result.claims.probability_semantics(1)), ...
    "producer=Somebody Else's Tool 3.1"));
clear cleanup
end

function testAnUnknownExporterVersionIsOmittedRatherThanRendered(testCase)
% The shipped template's default version is the literal "unknown". Rendering
% "Example System unknown" would put a disclaimer where a reader expects a
% version, which reads like a version somebody chose.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
profile = semanticsProfile(fixture, struct(score="Score from {producer}.", ...
    probability="Probability from {producer}."), "Nameless Tool", "unknown");
source = writeSource(fixture, "w1,10.0,10.4,A,0.91,0.87");
result = vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, ...
    ProfilePath=profile, Apply=true);

verifyEqual(testCase, presentText(result.claims.score_semantics(1)), ...
    "Score from Nameless Tool.");
verifyFalse(testCase, contains(presentText(result.claims.score_semantics(1)), ...
    "unknown"));
clear cleanup
end

function testRenderingTheSemanticsChangesNoStoredNumber(testCase)
% 4.12a's tripwire. This pass edits prose; if an imported number moved, something
% recomputed it. Awkward values chosen so a rescale could not hide.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, [ ...
    "w1,10.123456789,10.987654321,A,1234.56789,0.8812"; ...
    "w1,10.123456789,10.987654321,B,-0.0001,0.1188"]);
vawlume.ingest.attribution(fixture.conn, runRef(fixture), source, Apply=true);

% Read from the database, not the plan: a rescale between plan and write would
% be invisible to a check that only inspected the returned struct.
stored = fetch(fixture.conn, "SELECT score, probability FROM " + ...
    "imported_attribution_claims ORDER BY imported_attribution_claim_id");
verifyEqual(testCase, double(stored.score)', [1234.56789 -0.0001]);
verifyEqual(testCase, double(stored.probability)', [0.8812 0.1188]);
times = fetch(fixture.conn, "SELECT start_time_native AS s, end_time_native AS e " + ...
    "FROM imported_attribution_windows");
verifyEqual(testCase, double(times.s(1)), 10.123456789);
verifyEqual(testCase, double(times.e(1)), 10.987654321);
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
% And no orphan claim: claims are written in the same transaction as the windows
% they belong to.
claims = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM imported_attribution_claims");
verifyEqual(testCase, double(claims.n(1)), 0, ...
    "A failed import must leave no claim either.");
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
% exist. The claims now have their own home, which is not a candidate and never
% becomes one implicitly.
candidates = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_candidates");
evidence = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_evidence");
verifyEqual(testCase, double(candidates.n(1)), 0);
verifyEqual(testCase, double(evidence.n(1)), 0);
% The claims landed as claims, and are still returned intact.
claims = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM imported_attribution_claims");
verifyEqual(testCase, double(claims.n(1)), 2);
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

function path = semanticsProfile(fixture, semantics, exportingSystem, version)
%SEMANTICSPROFILE A profile whose declared semantics say whatever a test needs.
%
% Written so the producer guarantee can be tested against wording VAWLUME did
% not choose. A guarantee only ever tested against the shipped profile is a
% guarantee about that profile, not about the rule.
document = jsondecode(fileread(fullfile(fixture.repo_root, "config", ...
    "01_mapping_profiles", "attribution", ...
    "generic_imported_attribution_profile.json")));
document.profiles.value_semantics.score = semantics.score;
document.profiles.value_semantics.probability = semantics.probability;
document.profiles.context.exporting_system = exportingSystem;
document.profiles.context.exporting_system_version = version;
path = fullfile(fixture.workspace, "semantics_profile_" + ...
    string(java.util.UUID.randomUUID) + ".json");
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document, PrettyPrint=true));
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
