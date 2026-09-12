function tests = test_alignment_identity_anchors
%TEST_ALIGNMENT_IDENTITY_ANCHORS Phase 3 identity-dependent anchor evidence.
%
% Device-level alignment is identity-independent, and this file exists to hold
% that boundary rather than to describe it. The load-bearing test is
% testFittedCoefficientsAreInvariantToIdentityEvidence: SQLite cannot forbid a
% join, so the only thing separating visual-identity uncertainty from a clock
% transform is that the fitter does not read it, and the only way to know that
% stays true is to vary the evidence and watch the coefficients not move.
%
% The fixture's identity claims are synthetic. They are test ground truth, not a
% claim about how any real re-identification behaves.
tests = functiontests({ ...
    @testEvidenceClassIsRegisteredThroughTheNormalIntakePath, ...
    @testUnrecognizedEvidenceClassIsRefusedNotCoerced, ...
    @testIdentityEvidenceLinksRealAmbiguousAndUnresolvedClaims, ...
    @testLinkingRefusesDeviceLevelUndeclaredAndDuplicates, ...
    @testFittedCoefficientsAreInvariantToIdentityEvidence, ...
    @testReportSurfacesEvidenceClassAndIdentityBesideResiduals, ...
    @testPhase2IdentityModelIsUnchanged});
end

% ------------------------------------------------------------ evidence class ---

function testEvidenceClassIsRegisteredThroughTheNormalIntakePath(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The class arrives through the shipped anchor mapping profile and the ordinary
% intake path, not through a second registration route.
classes = fetch(fixture.conn, "SELECT a.anchor_key, " + ...
    "IFNULL(o.evidence_class,'') AS evidence_class " + ...
    "FROM alignment_anchor_observations o " + ...
    "JOIN alignment_anchors a ON a.alignment_anchor_id=o.alignment_anchor_id " + ...
    "JOIN timebases tb ON tb.timebase_id=o.timebase_id " + ...
    "WHERE tb.timebase_name='audio_native' ORDER BY a.anchor_key");
declared = string(classes.evidence_class);
declared(ismissing(declared)) = "";

% sync01..sync03 are TTL edges; sync04 is the scored female entry; sync05's
% column is blank because nobody examined it.
verifyEqual(testCase, declared(1:3), repmat("device_level", 3, 1));
verifyEqual(testCase, declared(4), "identity_dependent");
verifyEqual(testCase, declared(5), "");

% Undeclared is not device_level. A default would have converted an unexamined
% case into a confident one.
verifyEqual(testCase, nnz(declared == "device_level"), 3);
verifyEqual(testCase, nnz(declared == ""), 1);

clear cleanup
end

function testUnrecognizedEvidenceClassIsRefusedNotCoerced(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% A class outside the closed vocabulary is an error at mapping time, not a value
% quietly rounded to the nearest one the schema happens to accept.
workspace = fullfile(tempdir, "vawlume_identity_bad_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
restore = onCleanup(@() rmdir(workspace, "s"));

copyfile(fullfile(fixture.workspace, "video_events.csv"), workspace);
copyfile(fullfile(fixture.workspace, "neural_events.csv"), workspace);
copyfile(fixture.manifest_path, fullfile(workspace, "alignment_manifest.json"));

tbl = anchorTable(fixture);
tbl.evidence_class(1) = "probably_a_ttl";
writetable(tbl, fullfile(workspace, "sync_anchors.csv"));

% Read through the ordinary manifest path, which maps every declared table.
bundle = vawlume.ingest.alignmentManifest( ...
    string(fullfile(workspace, "alignment_manifest.json")), ...
    RepoRoot=fixture.repo_root, SourceRoot=string(workspace));

codes = strings(0, 1);
severities = strings(0, 1);
for index = 1:numel(bundle.anchors)
    issues = bundle.anchors(index).ir.issues;
    codes = [codes; string(issues.code)]; %#ok<AGROW>
    severities = [severities; string(issues.severity)]; %#ok<AGROW>
end
verifyTrue(testCase, any(codes == "ANCHOR_EVIDENCE_CLASS_INVALID"));
verifyTrue(testCase, any(severities == "error"));

clear cleanup
end

% --------------------------------------------------------------- the links ---

function testIdentityEvidenceLinksRealAmbiguousAndUnresolvedClaims(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
observationId = audioObservationId(fixture, "sync04");

% Two candidate entities over the crossing: this is what ambiguous identity
% looks like, and refusing it would push the ambiguity out of the record.
first = vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, ...
    observationId, fixture.ambiguous_ids(1));
verifyEqual(testCase, first.assignment_state, "ambiguous");
verifyEqual(testCase, first.link_count, 1);

second = vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, ...
    observationId, fixture.ambiguous_ids(2));
verifyEqual(testCase, second.link_count, 2);

% The Phase 2 semantics arrive intact: a number is meaningless without them.
verifyEqual(testCase, first.evidence_kind, "appearance_embedding");
verifyEqual(testCase, first.identity_value_semantics, ...
    "cosine_similarity_of_appearance_embeddings");
verifyEqual(testCase, first.calibration_status, "uncalibrated");

% An unresolved claim is a statement, and is equally linkable: the anchor was
% examined and no entity could be named.
third = vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, ...
    observationId, fixture.unresolved_id);
verifyEqual(testCase, third.assignment_state, "unresolved");
verifyTrue(testCase, isnan(third.identity_value));
verifyEqual(testCase, third.link_count, 3);

verifyTrue(testCase, contains(third.separation_note, "never an input"));

clear cleanup
end

function testLinkingRefusesDeviceLevelUndeclaredAndDuplicates(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% A TTL edge does not depend on which animal was present, so identity evidence
% has nothing to qualify there and nothing would ever weigh it.
verifyError(testCase, @() vawlume.alignment.linkAnchorIdentityEvidence( ...
    fixture.conn, audioObservationId(fixture, "sync01"), ...
    fixture.ambiguous_ids(1)), "vawlume:alignment:EvidenceClassRequired");

% Nor may an observation nobody classified: attaching evidence to an unexamined
% reading would assert a classification the record does not contain.
verifyError(testCase, @() vawlume.alignment.linkAnchorIdentityEvidence( ...
    fixture.conn, audioObservationId(fixture, "sync05"), ...
    fixture.ambiguous_ids(1)), "vawlume:alignment:EvidenceClassRequired");

observationId = audioObservationId(fixture, "sync04");
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.ambiguous_ids(1));

% The same association twice says nothing new.
verifyError(testCase, @() vawlume.alignment.linkAnchorIdentityEvidence( ...
    fixture.conn, observationId, fixture.ambiguous_ids(1)), ...
    "vawlume:alignment:IdentityEvidenceAlreadyLinked");

% This function links evidence that exists; it creates none.
verifyError(testCase, @() vawlume.alignment.linkAnchorIdentityEvidence( ...
    fixture.conn, observationId, 99999), ...
    "vawlume:alignment:IdentityAssociationNotFound");
verifyError(testCase, @() vawlume.alignment.linkAnchorIdentityEvidence( ...
    fixture.conn, 99999, fixture.ambiguous_ids(1)), ...
    "vawlume:alignment:AnchorObservationNotFound");

clear cleanup
end

% ------------------------------------------------------------- the boundary ---

function testFittedCoefficientsAreInvariantToIdentityEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
observationId = audioObservationId(fixture, "sync04");

% Planning recomputes coefficients from the anchors and writes nothing, so each
% call below is a fresh solve over the same evidence the fitter is allowed to
% see, plus whatever identity evidence has been attached since.
baseline = coefficients(fixture);

% Confident identity evidence.
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.confident_id);
verifyEqual(testCase, coefficients(fixture), baseline);

% Weak identity evidence.
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.weak_id);
verifyEqual(testCase, coefficients(fixture), baseline);

% Ambiguous: two candidate entities at once.
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.ambiguous_ids(1));
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.ambiguous_ids(2));
verifyEqual(testCase, coefficients(fixture), baseline);

% Unresolved: examined, and no entity could be named.
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.unresolved_id);
verifyEqual(testCase, coefficients(fixture), baseline);

% Moving the underlying identity claims does not move the clock either. If the
% solver read any of this, changing a score would change a coefficient.
% Only where semantics already exist: Phase 2 refuses a number without them,
% and this test has no business weakening that rule to make its point.
execute(fixture.conn, "UPDATE tracking_identity_associations " + ...
    "SET identity_value = 0.01 " + ...
    "WHERE identity_value_semantics IS NOT NULL");
verifyEqual(testCase, coefficients(fixture), baseline);

execute(fixture.conn, "UPDATE tracking_identity_associations " + ...
    "SET assignment_state = 'rejected' WHERE assignment_state = 'ambiguous'");
verifyEqual(testCase, coefficients(fixture), baseline);

% Reclassifying every anchor as identity-dependent does not move it either: the
% class describes the evidence, and the fitter reads neither the class nor what
% it points at.
execute(fixture.conn, "UPDATE alignment_anchor_observations " + ...
    "SET evidence_class = 'identity_dependent'");
verifyEqual(testCase, coefficients(fixture), baseline);

% And the boundary is structural, not incidental: the fitter's queries read nine
% tables and none of them carries identity.
verifyEqual(testCase, nnz(fitterTables() == "alignment_anchor_identity_evidence"), 0);
verifyEqual(testCase, nnz(fitterTables() == "tracking_identity_associations"), 0);

clear cleanup
end

% ------------------------------------------------------------------- the QC ---

function testReportSurfacesEvidenceClassAndIdentityBesideResiduals(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
observationId = audioObservationId(fixture, "sync04");
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.ambiguous_ids(1));
vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, observationId, ...
    fixture.ambiguous_ids(2));
vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);

qc = vawlume.alignment.report(fixture.conn, alignmentRef());

% Every reading's class is readable, and undeclared is its own value rather than
% being folded into device_level.
audioClasses = qc.anchor_evidence_classes( ...
    qc.anchor_evidence_classes.timebase_key == "audio_native", :);
verifyEqual(testCase, nnz(audioClasses.evidence_class == "device_level"), 3);
verifyEqual(testCase, nnz(audioClasses.evidence_class == "identity_dependent"), 1);
verifyEqual(testCase, nnz(audioClasses.evidence_class == "undeclared"), 1);

% The identity evidence is readable with its own semantics, and ambiguity shows
% as two rows rather than as one resolved answer.
evidence = qc.anchor_identity_evidence;
verifyEqual(testCase, height(evidence), 2);
verifyTrue(testCase, all(evidence.anchor_key == "sync04"));
verifyTrue(testCase, all(evidence.assignment_state == "ambiguous"));
verifyTrue(testCase, all(evidence.identity_value_semantics == ...
    "cosine_similarity_of_appearance_embeddings"));
verifyTrue(testCase, all(evidence.calibration_status == "uncalibrated"));
verifyEqual(testCase, numel(unique(evidence.entity_id)), 2);

% Beside the residual, never combined with it. The anchor has both an alignment
% residual and identity evidence, and no field anywhere mixes them.
residual = qc.residuals(qc.residuals.anchor_key == "sync04" & ...
    qc.residuals.source_timebase_key == "audio_native", :);
verifyEqual(testCase, height(residual), 1);
verifyFalse(testCase, isnan(residual.residual_s(1)));
verifyEqual(testCase, nnz(contains(string(evidence.Properties.VariableNames), ...
    "residual")), 0);
verifyEqual(testCase, nnz(contains(string(qc.residuals.Properties.VariableNames), ...
    "identity")), 0);
verifyTrue(testCase, contains(qc.identity_separation_note, "never combined"));
verifyTrue(testCase, contains(qc.identity_separation_note, "does not down-weight"));

clear cleanup
end

function testPhase2IdentityModelIsUnchanged(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = associationFingerprint(fixture.conn);

vawlume.alignment.linkAnchorIdentityEvidence(fixture.conn, ...
    audioObservationId(fixture, "sync04"), fixture.ambiguous_ids(1));
vawlume.alignment.fit(fixture.conn, alignmentRef(), Apply=true);
vawlume.alignment.report(fixture.conn, alignmentRef());

% This phase reads Phase 2's identity evidence and creates none of it. Nothing
% in the alignment layer writes, reweights, or reinterprets an association.
verifyEqual(testCase, associationFingerprint(fixture.conn), before);

% And the evidence an anchor was admitted on cannot be deleted out from under
% it, so the anchor cannot be silently un-qualified. The refusal comes from the
% schema's ON DELETE RESTRICT, whose error identifier is the driver's rather
% than VAWLUME's, so the assertion is on the refusal rather than on its name.
refused = false;
try
    execute(fixture.conn, "DELETE FROM tracking_identity_associations " + ...
        "WHERE tracking_identity_association_id = " + ...
        string(fixture.ambiguous_ids(1)));
catch
    refused = true;
end
verifyTrue(testCase, refused);
verifyEqual(testCase, associationFingerprint(fixture.conn), before);

clear cleanup
end

% ------------------------------------------------------------------ setup ---

function value = coefficients(fixture)
%COEFFICIENTS A fresh solve over the anchors, at full precision.
plan = vawlume.alignment.fit(fixture.conn, alignmentRef(), ...
    SourceTimebase="audio_native");
row = plan.transforms(plan.transforms.source_timebase_key == "audio_native", :);
value = sprintf("%.17g|%.17g|%.17g|%.17g", row.scale, row.offset_s, ...
    row.rmse_s, row.max_abs_residual_s);
end

function value = fitterTables()
%FITTERTABLES Every table the fit planner's queries name.
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
text = string(fileread(fullfile(repoRoot, "src", "+vawlume", "+alignment", ...
    "private", "alignmentFitBuildPlan.m")));
matches = regexp(text, "(?:FROM|JOIN)\s+([a-z_]+)", "tokens");
value = strings(numel(matches), 1);
for index = 1:numel(matches)
    value(index) = string(matches{index}{1});
end
value = unique(value);
end

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE Anchors of both evidence classes, over real Phase 2 identity claims.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
workspace = fullfile(tempdir, "vawlume_identity_anchor_" + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "identity.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedRecording(conn);

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
    audio_scale=1.0015, audio_offset=117.25, ...
    video_scale=0.9992, video_offset=53.40);

fixture.audio_times = [10; 400; 900; 1200; 1500];
fixture.anchor_keys = ["sync01"; "sync02"; "sync03"; "sync04"; "sync05"];
% sync04 is the scored female entry: an identity-dependent marker. sync05's
% class is left blank, which is the state of every anchor nobody examined.
fixture.evidence_classes = ["device_level"; "device_level"; "device_level"; ...
    "identity_dependent"; ""];
fixture.neural_times = fixture.audio_scale * fixture.audio_times + ...
    fixture.audio_offset;
fixture.video_times = (fixture.neural_times - fixture.video_offset) / ...
    fixture.video_scale;

writeTableFile(workspace, "video_events.csv", behaviorTable());
writeTableFile(workspace, "neural_events.csv", neuralTable(fixture));
writeTableFile(workspace, "sync_anchors.csv", anchorTable(fixture));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
fixture.manifest_path = string(manifestPath);
fixture.anchor_profile_path = fullfile(repoRoot, "config", ...
    "01_mapping_profiles", "alignment_anchors", "long_anchor_mapping_profile.json");

vawlume.ingest.alignment(conn, fixture.manifest_path, RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);

fixture.audio_timebase_id = timebaseId(conn, "audio_native");
fixture = seedIdentityClaims(fixture);
end

function fixture = seedIdentityClaims(fixture)
%SEEDIDENTITYCLAIMS Phase 2 associations of four strengths over one crossing.
conn = fixture.conn;
execute(conn, "INSERT INTO coordinate_systems(project_id, " + ...
    "coordinate_system_key, coordinate_system_name, dimensionality, unit) " + ...
    "VALUES (1, 'arena_2d', 'Arena floor', 2, 'cm')");
execute(conn, "INSERT INTO timebases(project_id, timebase_name, timebase_kind) " + ...
    "VALUES (1, 'pose_clock', 'acquisition_clock')");
execute(conn, "INSERT INTO external_streams(project_id, recording_id, " + ...
    "timebase_id, stream_name, stream_kind) VALUES (1, 1, " + ...
    string(timebaseId(conn, "pose_clock")) + ", 'pose', 'tracking')");
poseStream = double(fetchScalar(conn, "SELECT MAX(external_stream_id) AS n " + ...
    "FROM external_streams"));
execute(conn, "INSERT INTO tracking_streams(external_stream_id, " + ...
    "coordinate_system_id, native_time_basis) VALUES (" + ...
    string(poseStream) + ", 1, 'time')");
execute(conn, "INSERT INTO entity_types(project_id, native_name, " + ...
    "is_subject_like) VALUES (1, 'mouse', 1)");
for index = 1:2
    execute(conn, "INSERT INTO experimental_entities(project_id, " + ...
        "entity_type_id, native_id) VALUES (1, 1, 'M" + string(index) + "')");
end

% Each claim gets its own interval. The schema keeps one association per
% (stream, track, interval, entity), which is the rule that stops two
% contradictory claims about the same moment from coexisting silently; the
% ambiguous pair is the deliberate exception, two entities over one interval.
semantics = "cosine_similarity_of_appearance_embeddings";
fixture.confident_id = insertAssociation(conn, poseStream, 1, "assigned", ...
    0.97, semantics, [1100, 1110]);
fixture.weak_id = insertAssociation(conn, poseStream, 1, "candidate", ...
    0.31, semantics, [1120, 1130]);
fixture.ambiguous_ids = [ ...
    insertAssociation(conn, poseStream, 1, "ambiguous", 0.55, ...
        semantics, [1195, 1205]); ...
    insertAssociation(conn, poseStream, 2, "ambiguous", 0.52, ...
        semantics, [1195, 1205])];
fixture.unresolved_id = insertAssociation(conn, poseStream, NaN, "unresolved", ...
    NaN, "", [1210, 1220]);
end

function value = insertAssociation(conn, streamId, entityIndex, state, ...
        score, semantics, interval)
%INSERTASSOCIATION One Phase 2 claim. A missing score records no number at all.
columns = "external_stream_id, native_track_id, start_time_native, " + ...
    "end_time_native, assignment_state, evidence_kind, calibration_status, " + ...
    "review_state";
values = string(streamId) + ", 'mouse_a', " + compose("%.9f", interval(1)) + ...
    ", " + compose("%.9f", interval(2)) + ", '" + state + ...
    "', 'appearance_embedding', 'uncalibrated', 'unreviewed'";
if ~isnan(entityIndex)
    columns = columns + ", entity_id";
    values = values + ", " + string(entityIndex);
end
if ~isnan(score)
    columns = columns + ", identity_value, identity_value_semantics";
    values = values + ", " + compose("%.9f", score) + ", '" + semantics + "'";
end
execute(conn, "INSERT INTO tracking_identity_associations(" + columns + ...
    ") VALUES (" + values + ")");
value = double(fetchScalar(conn, "SELECT MAX(tracking_identity_association_id) " + ...
    "AS n FROM tracking_identity_associations"));
end

function tearDown(conn, workspace, sourcePath)
if isopen(conn)
    close(conn);
end
if isfolder(workspace)
    rmdir(workspace, "s");
end
rmpath(sourcePath);
end

function seedRecording(conn)
execute(conn, "INSERT INTO projects(project_key, project_name) " + ...
    "VALUES ('synthetic_alignment_session', 'Synthetic alignment session')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, " + ...
    "relative_path) VALUES (1, 'recording_audio', " + ...
    "'synthetic/session01.wav', 'session01.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, " + ...
    "native_recording_id, sample_rate_hz) " + ...
    "VALUES (1, 1, 'REC_SESSION_01', 250000)");
end

function tbl = behaviorTable()
tbl = table(["b1"; "b2"; "b3"], ...
    ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    ["10"; "20"; "30"], ["12"; missing; "30"], ["F01"; "M01"; ""], ...
    ["door"; "center"; "sync"], ...
    VariableNames=["event_id", "event", "start_time_s", "end_time_s", ...
    "subject", "zone"]);
end

function tbl = neuralTable(fixture)
ids = "n" + string(1:numel(fixture.neural_times))';
tbl = table(ids, repmat("TTL1_HIGH", numel(ids), 1), ...
    compose("%.9f", fixture.neural_times * 1000), ...
    repmat("5", numel(ids), 1), repmat("1", numel(ids), 1), ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
end

function tbl = anchorTable(fixture)
count = numel(fixture.anchor_keys);
markers = repelem(fixture.anchor_keys, 3);
streams = repmat(["audio"; "video"; "neural"], count, 1);
timestamps = strings(3 * count, 1);
eventIds = strings(3 * count, 1);
classes = strings(3 * count, 1);
for index = 1:count
    base = (index - 1) * 3;
    timestamps(base + 1) = compose("%.9f", fixture.audio_times(index));
    timestamps(base + 2) = compose("%.9f", fixture.video_times(index));
    timestamps(base + 3) = compose("%.9f", fixture.neural_times(index));
    eventIds(base + 3) = "n" + string(index);
    classes(base + (1:3)) = fixture.evidence_classes(index);
end
tbl = table(markers, streams, timestamps, repmat("primary", 3 * count, 1), ...
    repmat("true", 3 * count, 1), repmat("0.002", 3 * count, 1), classes, ...
    eventIds, ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "evidence_class", "event_id"]);
end

% ---------------------------------------------------------------- helpers ---

function value = alignmentRef()
value = struct(run_key="synthetic_session_01_alignment");
end

function value = timebaseId(conn, timebaseKey)
value = double(fetchScalar(conn, "SELECT timebase_id AS n FROM timebases " + ...
    "WHERE timebase_name = '" + timebaseKey + "'"));
end

function value = anchorId(fixture, anchorKey)
value = double(fetchScalar(fixture.conn, "SELECT alignment_anchor_id AS n " + ...
    "FROM alignment_anchors WHERE anchor_key = '" + anchorKey + "'"));
end

function value = audioObservationId(fixture, anchorKey)
value = double(fetchScalar(fixture.conn, "SELECT anchor_observation_id AS n " + ...
    "FROM alignment_anchor_observations WHERE alignment_anchor_id = " + ...
    string(anchorId(fixture, anchorKey)) + " AND timebase_id = " + ...
    string(fixture.audio_timebase_id)));
end

function value = associationFingerprint(conn)
%ASSOCIATIONFINGERPRINT Everything Phase 2's identity model holds.
rows = fetch(conn, "SELECT COUNT(*) AS n, " + ...
    "IFNULL(SUM(identity_value),0) AS score_sum, " + ...
    "IFNULL(SUM(entity_id),0) AS entity_sum, " + ...
    "COUNT(DISTINCT assignment_state) AS states " + ...
    "FROM tracking_identity_associations");
value = sprintf("%d|%.17g|%.17g|%d", double(rows.n(1)), ...
    double(rows.score_sum(1)), double(rows.entity_sum(1)), double(rows.states(1)));
end

function value = fetchScalar(conn, sql)
rows = fetch(conn, sql);
value = rows.(rows.Properties.VariableNames{1})(1);
end

function writeTableFile(workspace, name, tbl)
writetable(tbl, fullfile(workspace, name));
end

function root = repoRootForTest()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
