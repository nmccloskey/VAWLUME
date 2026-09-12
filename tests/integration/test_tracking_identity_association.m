function tests = test_tracking_identity_association
%TEST_TRACKING_IDENTITY_ASSOCIATION Visual identity association and uncertainty.
%
% The scenario throughout is a crossing: two tracks and two animals, cleanly
% associated before the crossing, ambiguous during it, and swapped after.
%
% The claims this suite holds:
%
%   identity is interval-scoped evidence, not a property of a trajectory;
%   several candidates may cover one interval, and that is the ambiguity model;
%   an unresolved statement is not the same as no evidence;
%   a missing numeric confidence stays missing and never becomes 1.0;
%   a number without stated semantics is refused;
%   pose confidence and identity evidence vary independently;
%   the query returns candidates and never forces one entity.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------------ the crossing ---

function testTimeVaryingIdentityAcrossACrossing(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

% Before the crossing each associated track is cleanly resolved. track2 is also
% listed, with resolution "none", because a track nobody examined is a finding
% the summary must not hide.
before = vawlume.tracking.identityCandidates(conn, streamRef(), [0 1.5]);
verifyEqual(testCase, sort(before.tracks.native_track_id)', ...
    ["track0", "track1", "track2"]);
crossed = before.tracks(ismember(before.tracks.native_track_id, ...
    ["track0", "track1"]), :);
verifyEqual(testCase, crossed.resolution', ["resolved", "resolved"]);
verifyEqual(testCase, crossed.candidate_count', [1 1]);
verifyEqual(testCase, ...
    sort(before.associations.entity_native_id)', ["mouse_a", "mouse_b"]);

% During the crossing track0 is compatible with either animal. Both candidates
% are returned; nothing picks one.
during = vawlume.tracking.identityCandidates(conn, streamRef(), [2.2 2.8]);
track0 = during.tracks(during.tracks.native_track_id == "track0", :);
verifyEqual(testCase, track0.resolution, "ambiguous");
verifyEqual(testCase, track0.candidate_count, 2);
candidates = during.associations( ...
    during.associations.native_track_id == "track0", :);
verifyEqual(testCase, sort(candidates.entity_native_id)', ["mouse_a", "mouse_b"]);
verifyEqual(testCase, unique(candidates.assignment_state), "ambiguous");

% After the crossing each track is cleanly associated again.
after = vawlume.tracking.identityCandidates(conn, streamRef(), [3.5 5]);
afterTracks = after.tracks(ismember(after.tracks.native_track_id, ...
    ["track0", "track1"]), :);
verifyEqual(testCase, afterTracks.resolution', ["resolved", "resolved"]);

clear cleanup
end

function testIdentityReversesAfterTheCrossing(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>

before = vawlume.tracking.identityCandidates(fixture.conn, streamRef(), [0 1.5]);
after = vawlume.tracking.identityCandidates(fixture.conn, streamRef(), [3.5 5]);

beforeTrack0 = before.associations( ...
    before.associations.native_track_id == "track0", :);
afterTrack0 = after.associations( ...
    after.associations.native_track_id == "track0", :);

% The same trajectory carries a different animal before and after. A
% session-global track-to-entity row could not express this at all.
verifyEqual(testCase, beforeTrack0.entity_native_id, "mouse_a");
verifyEqual(testCase, afterTrack0.entity_native_id, "mouse_b");
verifyEqual(testCase, afterTrack0.assignment_state, "assigned");

clear cleanup
end

% --------------------------------------------------- unresolved versus none ---

function testUnresolvedIsAStatementAndNoEvidenceIsNot(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

% track1 has an explicit unresolved statement over the crossing: somebody looked
% and could not tell.
during = vawlume.tracking.identityCandidates(conn, streamRef(), [2.2 2.8]);
track1 = during.tracks(during.tracks.native_track_id == "track1", :);
verifyEqual(testCase, track1.resolution, "unresolved");
verifyEqual(testCase, track1.candidate_count, 0);

unresolvedRow = during.associations( ...
    during.associations.native_track_id == "track1", :);
verifyTrue(testCase, isnan(unresolvedRow.entity_id));
verifyEqual(testCase, unresolvedRow.assignment_state, "unresolved");

% A third track exists in the stream with no identity evidence at all. That is
% a different finding - nobody looked - and it must not read as unresolved.
verifyTrue(testCase, ismember("track2", during.tracks.native_track_id));
track2 = during.tracks(during.tracks.native_track_id == "track2", :);
verifyEqual(testCase, track2.resolution, "none");
verifyEqual(testCase, track2.candidate_count, 0);

% The two are distinguishable in the summary even though both have zero
% candidates, which is the whole point.
verifyNotEqual(testCase, track1.resolution, track2.resolution);

clear cleanup
end

% ------------------------------------------------------------ score semantics ---

function testMissingNumericConfidenceStaysMissing(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>

result = vawlume.tracking.identityCandidates(fixture.conn, streamRef(), [0 1.5]);

% The pre-crossing associations are manual assertions with no numeric
% confidence. They must come back as missing, never as 1.0.
manual = result.associations(result.associations.evidence_kind == ...
    "manual_assertion", :);
verifyGreaterThan(testCase, height(manual), 0);
verifyTrue(testCase, all(isnan(manual.identity_value)));
verifyTrue(testCase, all(manual.identity_value_semantics == ""));

track0 = result.tracks(result.tracks.native_track_id == "track0", :);
verifyFalse(testCase, track0.has_numeric_evidence);

clear cleanup
end

function testNumericEvidenceCarriesItsSemantics(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

% An upstream re-identification score, recorded with what it means.
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), struct( ...
    native_track_id="track2", entity_native_id="mouse_a", ...
    start_time_native=0, end_time_native=5, ...
    assignment_state="candidate", evidence_kind="reidentification_score", ...
    identity_value=0.62, ...
    identity_value_semantics="cosine_similarity_of_appearance_embeddings", ...
    calibration_status="uncalibrated", method="upstream_reid_v2"));

result = vawlume.tracking.identityCandidates(conn, streamRef(), [0 5]);
scored = result.associations(result.associations.evidence_kind == ...
    "reidentification_score", :);
verifyEqual(testCase, scored.identity_value, 0.62, AbsTol=1e-12);
verifyEqual(testCase, scored.identity_value_semantics, ...
    "cosine_similarity_of_appearance_embeddings");
verifyEqual(testCase, scored.calibration_status, "uncalibrated");

% A number with no stated meaning is refused: it would invite comparison with
% quantities that mean something else entirely.
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), struct(native_track_id="track2", entity_native_id="mouse_b", ...
        start_time_native=0, end_time_native=5, assignment_state="candidate", ...
        evidence_kind="unknown_score", identity_value=0.9)), ...
    "vawlume:tracking:IdentityValueSemanticsRequired");

clear cleanup
end

% ---------------------------------------------------------------- invariants ---

function testUnresolvedAndCandidateAreMutuallyExclusive(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

% Naming an entity while claiming nothing is known is incoherent.
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), struct(native_track_id="track2", entity_native_id="mouse_a", ...
        start_time_native=0, end_time_native=1, ...
        assignment_state="unresolved", evidence_kind="manual_assertion")), ...
    "vawlume:tracking:IdentityStateInconsistent");

% So is claiming an assignment with nobody assigned.
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), struct(native_track_id="track2", ...
        start_time_native=0, end_time_native=1, ...
        assignment_state="assigned", evidence_kind="manual_assertion")), ...
    "vawlume:tracking:IdentityStateInconsistent");

% The schema enforces the same pairing independently of the API.
verifySqlFails(testCase, conn, "INSERT INTO tracking_identity_associations(" + ...
    "external_stream_id,native_track_id,entity_id,start_time_native," + ...
    "end_time_native,assignment_state,evidence_kind) " + ...
    "VALUES(1,'track2',1,0,1,'unresolved','manual_assertion')");
verifySqlFails(testCase, conn, "INSERT INTO tracking_identity_associations(" + ...
    "external_stream_id,native_track_id,start_time_native," + ...
    "end_time_native,assignment_state,evidence_kind) " + ...
    "VALUES(1,'track2',0,1,'assigned','manual_assertion')");

clear cleanup
end

function testEvidenceIsOnlyRecordedAboutRealTracksAndEntities(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

% A trajectory the stream never produced would be evidence about nothing.
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), struct(native_track_id="track9", entity_native_id="mouse_a", ...
        start_time_native=0, end_time_native=1, ...
        assignment_state="candidate", evidence_kind="manual_assertion")), ...
    "vawlume:tracking:NativeTrackNotFound");

% Identity evidence cites established entities; it never creates them.
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), struct(native_track_id="track2", entity_native_id="mouse_z", ...
        start_time_native=0, end_time_native=1, ...
        assignment_state="candidate", evidence_kind="manual_assertion")), ...
    "vawlume:tracking:EntityNotFound");

clear cleanup
end

function testTheSameCandidateCannotBeAssertedTwice(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

spec = struct(native_track_id="track2", entity_native_id="mouse_a", ...
    start_time_native=0, end_time_native=1, ...
    assignment_state="candidate", evidence_kind="manual_assertion");
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), spec);

% The identical candidate over the identical interval is a duplicate.
verifyError(testCase, ...
    @() vawlume.tracking.registerIdentityAssociation(conn, streamRef(), spec), ...
    "vawlume:tracking:IdentityAssociationDuplicate");

% A DIFFERENT candidate over the same interval is the ambiguity model and is
% allowed.
other = spec;
other.entity_native_id = "mouse_b";
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), other);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n " + ...
    "FROM tracking_identity_associations WHERE native_track_id='track2'"), 2);

% But the unresolved statement can only be made once per interval, because
% SQLite would otherwise treat two NULL entities as distinct rows.
unresolved = struct(native_track_id="track2", start_time_native=3, ...
    end_time_native=4, assignment_state="unresolved", ...
    evidence_kind="manual_review");
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), unresolved);
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), unresolved), "vawlume:tracking:IdentityAssociationDuplicate");

clear cleanup
end

% -------------------------------------------------------------- provenance ---

function testProvenanceIsRecordedAndReadBack(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;
declareProvenanceRows(conn);

% A claim that names where it came from: the reviewed artifact, the analysis run
% that produced the review, the profile that interpreted the table, and the row
% within it.
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), struct( ...
    native_track_id="track2", entity_native_id="mouse_a", ...
    start_time_native=0, end_time_native=5, ...
    assignment_state="candidate", evidence_kind="reidentification_score", ...
    identity_value=0.71, ...
    identity_value_semantics="cosine_similarity_of_appearance_embeddings", ...
    calibration_status="uncalibrated", review_state="reviewed", ...
    method="upstream_reid_v2", analysis_run_id=20, source_file_id=20, ...
    mapping_profile_version_id=20, source_locator="identity.csv:row:7"));

result = vawlume.tracking.identityCandidates(conn, streamRef(), [0 5]);
claim = result.associations(result.associations.native_track_id == "track2", :);
verifyEqual(testCase, height(claim), 1);
verifyEqual(testCase, claim.source_file_id, 20);
verifyEqual(testCase, claim.analysis_run_id, 20);
verifyEqual(testCase, claim.method, "upstream_reid_v2");
verifyEqual(testCase, claim.review_state, "reviewed");

% The mapping profile and locator are not in the query result, so read them from
% the row: they are provenance a later audit needs, not query output.
stored = fetch(conn, "SELECT mapping_profile_version_id, source_locator " + ...
    "FROM tracking_identity_associations WHERE native_track_id='track2'");
verifyEqual(testCase, double(stored.mapping_profile_version_id(1)), 20);
verifyEqual(testCase, string(stored.source_locator(1)), "identity.csv:row:7");

% Provenance is per claim, not per stream: the crossing's manual rows carry none
% while this upstream row carries all of it.
manual = result.associations(result.associations.evidence_kind == ...
    "manual_assertion", :);
verifyTrue(testCase, all(isnan(manual.source_file_id)));

clear cleanup
end

function testProvenanceFromAnotherExperimentIsRefused(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;
declareProvenanceRows(conn);

base = struct(native_track_id="track2", entity_native_id="mouse_a", ...
    start_time_native=0, end_time_native=5, ...
    assignment_state="candidate", evidence_kind="manual_review");

% Every one of these rows exists, so a foreign key would accept all of them.
% They are simply not provenance for this stream's project, and a stated basis
% pointing at another experiment is worse than no stated basis at all.
verifyRefused(testCase, conn, base, "source_file_id", 21, ...
    "vawlume:tracking:SourceFileScopeMismatch");
verifyRefused(testCase, conn, base, "analysis_run_id", 21, ...
    "vawlume:tracking:AnalysisRunScopeMismatch");
verifyRefused(testCase, conn, base, "mapping_profile_version_id", 21, ...
    "vawlume:tracking:MappingProfileScopeMismatch");

% An extractor's output profile describes a different contract entirely.
verifyRefused(testCase, conn, base, "mapping_profile_version_id", 22, ...
    "vawlume:tracking:MappingProfileKindInvalid");

% And a reference to nothing at all.
verifyRefused(testCase, conn, base, "source_file_id", 999, ...
    "vawlume:tracking:SourceFileNotFound");
verifyRefused(testCase, conn, base, "analysis_run_id", 999, ...
    "vawlume:tracking:AnalysisRunNotFound");
verifyRefused(testCase, conn, base, "mapping_profile_version_id", 999, ...
    "vawlume:tracking:MappingProfileNotFound");

% A built-in profile has project_id NULL and remains citable.
accepted = base;
accepted.mapping_profile_version_id = 23;
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), accepted);

verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM " + ...
    "tracking_identity_associations WHERE native_track_id='track2'"), 1);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testAnEntityFromAnotherProjectIsNamedNotLeakedAsAConstraintError(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;
declareProvenanceRows(conn);

% The schema trigger refuses this too, but a raw constraint error would name
% neither project nor why a track cannot be evidence about another experiment's
% animal.
verifyError(testCase, @() vawlume.tracking.registerIdentityAssociation(conn, ...
    streamRef(), struct(native_track_id="track2", entity_id=99, ...
        start_time_native=0, end_time_native=1, ...
        assignment_state="candidate", evidence_kind="manual_assertion")), ...
    "vawlume:tracking:EntityScopeMismatch");

clear cleanup
end

% ------------------------------------------------- independence of dimensions ---

function testPoseConfidenceAndIdentityVaryIndependently(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>
conn = fixture.conn;

samples = vawlume.tracking.readWindow(conn, streamRef(), [0 1.5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
identity = vawlume.tracking.identityCandidates(conn, streamRef(), [0 1.5]);

% High pose confidence with certain identity, and the two are separate fields
% in separate results.
verifyTrue(testCase, samples.has_pose_confidence);
verifyTrue(testCase, all(samples.samples.pose_confidence > 0.9));
associated = identity.tracks(ismember(identity.tracks.native_track_id, ...
    ["track0", "track1"]), :);
verifyEqual(testCase, unique(associated.resolution), "resolved");

% Low pose confidence during the crossing, where identity is ALSO uncertain -
% but neither was derived from the other, and the identity rows carry no pose
% value at all.
crossing = vawlume.tracking.readWindow(conn, streamRef(), [2.2 2.8], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
verifyTrue(testCase, all(crossing.samples.pose_confidence < 0.5));

crossingIdentity = vawlume.tracking.identityCandidates(conn, streamRef(), [2.2 2.8]);
names = string(crossingIdentity.associations.Properties.VariableNames);
verifyFalse(testCase, any(contains(lower(names), "pose")));

% And the identity result says so where a caller will read it.
verifyTrue(testCase, contains(crossingIdentity.pose_confidence_note, ...
    "never derived from it"));

clear cleanup
end

function testIdentityQueryConsultsNoClockTransform(testCase)
[fixture, cleanup] = setUpCrossing(); %#ok<ASGLU>

% Identity evidence is stated in the stream's own native units. The result
% reports which clock that is and performs no transform, so alignment
% uncertainty and identity uncertainty stay separable downstream.
result = vawlume.tracking.identityCandidates(fixture.conn, streamRef(), [0 5]);
verifyEqual(testCase, result.timebase.timebase_name, "video_native");

names = string(fieldnames(result));
verifyFalse(testCase, any(contains(lower(names), "reference_time")));
verifyFalse(testCase, any(contains(lower(names), "transform")));

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function ref = streamRef()
ref = struct(project_key="tracking_project", stream_name="tracking_primary");
end

function writeTrackingCsv(path)
%WRITETRACKINGCSV Three tracks; pose confidence dips during the crossing.
%
% Track labels are 'track0'/'track1'/'track2' rather than animal names, which is
% how a tracker that makes no identity claim actually labels its output.
lines = "time_s,track,bodypart,x,y,likelihood";
for track = ["track0", "track1", "track2"]
    for part = ["snout", "tail_base"]
        for t = 0:0.5:5
            likelihood = 0.97;
            if t >= 2 && t <= 3
                likelihood = 0.31;
            end
            lines(end + 1, 1) = string(t) + "," + track + "," + part + "," + ...
                string(10 + t) + "," + string(20 - t) + "," + ...
                string(likelihood); %#ok<AGROW>
        end
    end
end
writelines(lines, path);
end

function writeProfile(path)
repoRoot = repoRootPath();
source = fullfile(repoRoot, "config", "01_mapping_profiles", "tracking", ...
    "generic_tracking_mapping_profile.json");
document = jsondecode(fileread(source));
document.profiles.columns.track_label.source_field = "track";
writelines(string(jsonencode(document, PrettyPrint=true)), path);
end

function [fixture, cleanup] = setUpCrossing()
%SETUPCROSSING Two animals, three tracks, and a crossing at t = 2-3 s.
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbFile = fullfile(scratch, "identity.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('tracking_project','Tracking project')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri," + ...
    "relative_path,filename) VALUES(1,'recording_audio','a.wav','a.wav','a.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id) VALUES(1,1)");
execute(conn, "INSERT INTO timebases(project_id,recording_id,timebase_name," + ...
    "timebase_kind) VALUES(1,1,'video_native','video_frame_clock')");
execute(conn, "INSERT INTO coordinate_systems(project_id,coordinate_system_key," + ...
    "coordinate_system_name,dimensionality,unit) " + ...
    "VALUES(1,'arena_2d','Arena floor plane',2,'cm')");
execute(conn, "INSERT INTO entity_types(project_id,native_name) VALUES(1,'subject')");
execute(conn, "INSERT INTO experimental_entities(project_id,entity_type_id," + ...
    "native_id) VALUES(1,1,'mouse_a'),(1,1,'mouse_b')");

artifactPath = fullfile(scratch, "session_01_tracking.csv");
writeTrackingCsv(artifactPath);
profilePath = fullfile(scratch, "tracking_profile.json");
writeProfile(profilePath);

vawlume.tracking.register(conn, struct(recording_id=1), struct( ...
    artifact_path="session_01_tracking.csv", ...
    profile_path=profilePath, timebase_key="video_native"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=scratch);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);

% Before the crossing: manual assertions, no numeric confidence.
registerAssociation(conn, "track0", "mouse_a", 0, 2, "assigned", ...
    "manual_assertion", "manual_review_by_scorer");
registerAssociation(conn, "track1", "mouse_b", 0, 2, "assigned", ...
    "manual_assertion", "manual_review_by_scorer");

% During the crossing: track0 is compatible with either animal; track1's
% identity is explicitly unresolved.
registerAssociation(conn, "track0", "mouse_a", 2, 3, "ambiguous", ...
    "manual_review", "manual_review_by_scorer");
registerAssociation(conn, "track0", "mouse_b", 2, 3, "ambiguous", ...
    "manual_review", "manual_review_by_scorer");
registerAssociation(conn, "track1", "", 2, 3, "unresolved", ...
    "manual_review", "manual_review_by_scorer");

% After the crossing the association has reversed.
registerAssociation(conn, "track0", "mouse_b", 3, 5, "assigned", ...
    "manual_assertion", "manual_review_by_scorer");
registerAssociation(conn, "track1", "mouse_a", 3, 5, "assigned", ...
    "manual_assertion", "manual_review_by_scorer");
end

function registerAssociation(conn, trackId, entityNativeId, startTime, endTime, ...
    state, evidenceKind, method)
spec = struct(native_track_id=trackId, start_time_native=startTime, ...
    end_time_native=endTime, assignment_state=state, ...
    evidence_kind=evidenceKind, method=method);
if strlength(entityNativeId) > 0
    spec.entity_native_id = entityNativeId;
end
vawlume.tracking.registerIdentityAssociation(conn, streamRef(), spec);
end

function value = numberOf(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function declareProvenanceRows(conn)
%DECLAREPROVENANCEROWS Citable provenance, and provenance that must be refused.
%
% The 20-series belongs to this project and is legitimate. The 21-series belongs
% to a second project, 22 is this project's extractor-output profile, 23 is a
% built-in with project_id NULL, and entity 99 is the other project's animal.
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(2,'other_project','Other project')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path,filename) VALUES" + ...
    "(20,1,'tracking_export','identity.csv','identity.csv','identity.csv')," + ...
    "(21,2,'tracking_export','foreign.csv','foreign.csv','foreign.csv')");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type," + ...
    "run_key,status) VALUES" + ...
    "(20,1,'visual_identity_review','identity-review','completed')," + ...
    "(21,2,'visual_identity_review','foreign-review','completed')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key," + ...
    "profile_name,profile_kind) VALUES" + ...
    "(20,1,'identity-map','Identity table','external_stream_mapping')," + ...
    "(21,2,'foreign-map','Foreign identity table','external_stream_mapping')," + ...
    "(22,1,'ds-out','DeepSqueak output','extractor_output')");
execute(conn, "INSERT INTO config_profiles(profile_id,profile_key,profile_name," + ...
    "profile_kind,is_builtin) VALUES" + ...
    "(23,'builtin-track','Built-in tracking map','tracking_input_mapping',1)");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id," + ...
    "version_label,content_format,content_uri) VALUES" + ...
    "(20,20,'1.0.0','json','identity-map.json')," + ...
    "(21,21,'1.0.0','json','foreign-map.json')," + ...
    "(22,22,'1.0.0','json','ds-out.json')," + ...
    "(23,23,'1.0.0','json','builtin-track.json')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name) " + ...
    "VALUES(99,2,'subject')");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(99,2,99,'mouse_other')");
end

function verifyRefused(testCase, conn, base, field, value, identifier)
spec = base;
spec.(field) = value;
verifyError(testCase, ...
    @() vawlume.tracking.registerIdentityAssociation(conn, streamRef(), spec), ...
    identifier);
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

function tearDown(conn, scratch, repoRoot)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
