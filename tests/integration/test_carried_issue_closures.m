function tests = test_carried_issue_closures
%TEST_CARRIED_ISSUE_CLOSURES P2-15, A-1 and P2-13, carried since Phase 2 close.
%
% Each was deferred repeatedly and correctly: a storage layer inventing identity
% precedence would have hidden evidence, and a channel API written before
% anything consumed channels would have guessed. Phase 4 is the first consumer
% that needs all three, so this suite is the evidence that closes them.
%
% The load-bearing assertions are the ones that prove a closure did not cost
% something else: that a registered channel is accepted by the paths that
% require one rather than merely inserting, and that `identityCandidates` still
% returns every claim after a precedence rule exists elsewhere.
tests = functiontests({ ...
    @testRegisteredChannelIsAcceptedByPlacement, ...
    @testRegisteredChannelIsAcceptedByResponseMeasurement, ...
    @testReregisteringAnIdenticalChannelReusesIt, ...
    @testReregisteringWithDifferentContentIsRefused, ...
    @testChannelBeyondDeclaredCountIsRefused, ...
    @testRecordingWithNoDeclaredCountIsNotSecondGuessed, ...
    @testVisualIdentityEvidenceMustSayWhatItRestsOn, ...
    @testDeclaredLinkAndIdentityAssociationAreDistinguishable, ...
    @testAssignedOutranksCandidate, ...
    @testNarrowestIntervalWinsAmongEqualStates, ...
    @testRejectedClaimsAreNeverChosen, ...
    @testAnUnbreakableTieIsReportedNotBroken, ...
    @testResolutionReportsWhatItSetAsideAndWhy, ...
    @testIdentityCandidatesStillReturnsEveryClaim});
end

% --- P2-15: a public function creates recording_channels -----------------

function testRegisteredChannelIsAcceptedByPlacement(testCase)
% The claim is not that a row inserts. It is that the row satisfies the paths
% that required one, which is what the workaround existed for.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
channel = vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), struct(channel_index=1, channel_label="left"));
verifyEqual(testCase, channel.action, "created");

vawlume.geometry.registerCoordinateSystem(fixture.conn, ...
    struct(project_key="p1"), struct(coordinate_system_key="arena", ...
        coordinate_system_name="Arena frame", dimensionality=2, unit="m"));
placement = vawlume.geometry.registerChannelPlacement(fixture.conn, ...
    struct(recording_id=1), struct(channel_index=1, ...
        coordinate_system_key="arena", position_x=0.1, position_y=0.2));
verifyEqual(testCase, placement.recording_channel_id, channel.recording_channel_id);
clear cleanup
end

function testRegisteredChannelIsAcceptedByResponseMeasurement(testCase)
% The acoustic layer resolves a channel by index. A channel created here must be
% the one it finds.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), struct(channel_index=1, channel_label="left"));
vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), struct(channel_index=2, channel_label="right"));

stored = fetch(fixture.conn, "SELECT recording_channel_id AS id, " + ...
    "channel_index AS idx, IFNULL(channel_label,'') AS label " + ...
    "FROM recording_channels WHERE recording_id=1 ORDER BY channel_index");
verifyEqual(testCase, double(stored.idx)', [1 2]);
verifyEqual(testCase, presentText(stored.label)', ["left" "right"]);

reference = vawlume.acoustic.registerReference(fixture.conn, ...
    struct(recording_id=1), struct(reference_key="tone-1", reference_type="synthetic_tone", ...
        start_time_s=1.0, end_time_s=2.0, channel_index=1, ...
        native_label="1 kHz tone"));
verifyEqual(testCase, double(reference.recording_channel_id), double(stored.id(1)));
verifyEqual(testCase, double(reference.channel_index), 1);
clear cleanup
end

function testReregisteringAnIdenticalChannelReusesIt(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
spec = struct(channel_index=1, channel_label="left", channel_role="signal");
first = vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), spec);
second = vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), spec);
verifyEqual(testCase, first.action, "created");
verifyEqual(testCase, second.action, "reused");
verifyEqual(testCase, second.recording_channel_id, first.recording_channel_id);
verifyEqual(testCase, channelRowCount(fixture), 1);
clear cleanup
end

function testReregisteringWithDifferentContentIsRefused(testCase)
% Placements and measurements already address the channel by ID. Rewriting what
% it denotes would silently re-point evidence that cites it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), struct(channel_index=1, channel_label="left"));
verifyRefused(testCase, ...
    @() vawlume.geometry.registerRecordingChannel(fixture.conn, ...
        struct(recording_id=1), struct(channel_index=1, channel_label="right")), ...
    "vawlume:geometry:ChannelConflict");
verifyEqual(testCase, channelRowCount(fixture), 1);
clear cleanup
end

function testChannelBeyondDeclaredCountIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE recordings SET channel_count=2 WHERE recording_id=1");
verifyRefused(testCase, ...
    @() vawlume.geometry.registerRecordingChannel(fixture.conn, ...
        struct(recording_id=1), struct(channel_index=3)), ...
    "vawlume:geometry:ChannelIndexOutOfRange");
clear cleanup
end

function testRecordingWithNoDeclaredCountIsNotSecondGuessed(testCase)
% An absent channel_count is missing metadata, not an assertion that the file
% has no channels.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE recordings SET channel_count=NULL WHERE recording_id=1");
channel = vawlume.geometry.registerRecordingChannel(fixture.conn, ...
    struct(recording_id=1), struct(channel_index=7));
verifyEqual(testCase, channel.action, "created");
verifyEqual(testCase, channel.channel_index, 7);
verifyTrue(testCase, channel.channel_count_is_caller_asserted);
clear cleanup
end

% --- A-1: which identity statement does this evidence rest on? -----------

function testVisualIdentityEvidenceMustSayWhatItRestsOn(testCase)
% A-1's remaining hole before this pass: visual-identity evidence could be
% written with only a source locator, leaving a weak declared entity link and a
% real identity association indistinguishable at the point attribution reads
% them. That is exactly the confusion A-1 was raised about.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = seedAttributionCandidate(fixture);
verifyRefused(testCase, ...
    @() vawlume.attribution.addEvidence(fixture.conn, ...
        struct(attribution_candidate_id=candidateId), ...
        struct(evidence_dimension="visual_identity", ...
            evidence_kind="reidentification_score", value_real=0.55, ...
            value_units="similarity", ...
            value_semantics="cosine similarity of appearance embeddings", ...
            source_locator="upstream.csv:row7"), Apply=true), ...
    "vawlume:attribution:EvidenceIdentityRequired");
clear cleanup
end

function testDeclaredLinkAndIdentityAssociationAreDistinguishable(testCase)
% Both may legitimately support a claim. The rule is not "prefer the stronger
% one"; it is never use either silently.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = seedAttributionCandidate(fixture);
seedTrackingStream(fixture);
associationId = seedAssociation(fixture, "track0", 1, 0, 10, "assigned");
execute(fixture.conn, "INSERT INTO external_events(external_event_id," + ...
    "external_stream_id,event_type,start_time_native,entity_id) " + ...
    "VALUES(1,1,'behavior_score',1.0,1)");

vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_candidate_id=candidateId), ...
    struct(evidence_dimension="visual_identity", ...
        evidence_kind="reidentification_score", value_real=0.55, ...
        value_units="similarity", value_semantics="cosine similarity", ...
        identity_statement_kind="identity_association", ...
        tracking_identity_association_id=associationId), Apply=true);
vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_candidate_id=candidateId), ...
    struct(evidence_dimension="visual_identity", ...
        evidence_kind="scored_behaviour_subject_column", value_text="A", ...
        value_units="entity native_id", ...
        value_semantics="whoever scored the behaviour said this event was about A", ...
        identity_statement_kind="declared_entity_link", external_event_id=1), ...
    Apply=true);

stored = fetch(fixture.conn, "SELECT identity_statement_kind AS kind, " + ...
    "IFNULL(tracking_identity_association_id,-1) AS assoc, " + ...
    "IFNULL(external_event_id,-1) AS event " + ...
    "FROM attribution_evidence ORDER BY attribution_evidence_id");
verifyEqual(testCase, presentText(stored.kind)', ...
    ["identity_association" "declared_entity_link"]);
% Each names the row it rests on, so the weaker claim cannot read as the
% stronger one.
verifyEqual(testCase, double(stored.assoc)', [associationId -1]);
verifyEqual(testCase, double(stored.event)', [-1 1]);
clear cleanup
end

% --- P2-13: precedence among overlapping identity claims -----------------

function testAssignedOutranksCandidate(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
seedTrackingStream(fixture);
seedAssociation(fixture, "track0", 1, 0, 100, "candidate");
strong = seedAssociation(fixture, "track0", 2, 0, 100, "assigned");

result = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), [10 20]);
verifyEqual(testCase, height(result.resolutions), 1);
verifyEqual(testCase, result.resolutions.entity_id(1), 2);
verifyEqual(testCase, result.resolutions.tracking_identity_association_id(1), strong);
verifyEqual(testCase, result.resolutions.decided_by_step(1), "state_precedence");
clear cleanup
end

function testNarrowestIntervalWinsAmongEqualStates(testCase)
% P2-13's motivating case, stated in the 2.4a handoff: a session-long weak claim
% beside a precise manual correction over a crossing. A narrower interval is the
% structural signal that somebody looked harder at that moment.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
seedTrackingStream(fixture);
seedAssociation(fixture, "track0", 1, 0, 600, "assigned");
precise = seedAssociation(fixture, "track0", 2, 14, 16, "assigned");

result = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), [14.5 15.5]);
verifyEqual(testCase, result.resolutions.entity_id(1), 2);
verifyEqual(testCase, result.resolutions.tracking_identity_association_id(1), precise);
verifyEqual(testCase, result.resolutions.decided_by_step(1), "interval_specificity");
verifyTrue(testCase, contains(result.resolutions.reason(1), "narrowest"));
clear cleanup
end

function testRejectedClaimsAreNeverChosen(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
seedTrackingStream(fixture);
seedAssociation(fixture, "track0", 1, 0, 100, "rejected");
seedAssociation(fixture, "track0", NaN, 0, 100, "unresolved");

result = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), [10 20], ...
    NativeTrackIds="track0");

% A rejected claim is out at every step, so the surviving statement is the
% unresolved one -- which names no entity. That is the honest answer here:
% somebody looked and could not tell, and the resolver reports that rather than
% falling back to the rejected claim because it happens to name somebody.
verifyTrue(testCase, isnan(result.resolutions.entity_id(1)));
verifyEqual(testCase, result.resolutions.decided_by_step(1), "state_precedence");
verifyTrue(testCase, any(contains(result.set_aside.why_not, "rejected")));
verifyFalse(testCase, any(result.set_aside.entity_id == 1 & ...
    contains(result.set_aside.why_not, "stronger")));
clear cleanup
end

function testAnUnbreakableTieIsReportedNotBroken(testCase)
% Two claims, same state, same interval width. An arbitrary tiebreak here would
% be a silent rule, so the tie is reported and the caller decides.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
seedTrackingStream(fixture);
seedAssociation(fixture, "track0", 1, 0, 100, "assigned");
seedAssociation(fixture, "track0", 2, 0, 100, "assigned");

result = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), [10 20]);
verifyTrue(testCase, isnan(result.resolutions.entity_id(1)));
verifyEqual(testCase, result.resolutions.decided_by_step(1), "tied");
verifyTrue(testCase, contains(result.resolutions.reason(1), "tie"));
verifyEqual(testCase, result.resolutions.set_aside_count(1), 2);
clear cleanup
end

function testResolutionReportsWhatItSetAsideAndWhy(testCase)
% A precedence rule whose reasoning is not returned is a silent rule with extra
% steps.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
seedTrackingStream(fixture);
seedAssociation(fixture, "track0", 1, 0, 600, "candidate");
seedAssociation(fixture, "track0", 2, 14, 16, "assigned");

result = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), [14.5 15.5]);
verifyEqual(testCase, result.resolutions.entity_id(1), 2);
verifyEqual(testCase, height(result.set_aside), 1);
verifyEqual(testCase, result.set_aside.entity_id(1), 1);
verifyTrue(testCase, contains(result.set_aside.why_not(1), "stronger assignment_state"));

% The rule states what it did not use, so a reader cannot assume it weighed a
% similarity score or a review state.
verifyTrue(testCase, ismember("identity_value", result.rule.does_not_use));
verifyTrue(testCase, ismember("review_state", result.rule.does_not_use));
verifyTrue(testCase, ismember("assignment_state", result.rule.uses));
clear cleanup
end

function testIdentityCandidatesStillReturnsEveryClaim(testCase)
% The tripwire. If a precedence rule existing elsewhere made the query layer
% return fewer rows, P2-13 was implemented in the wrong place.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
seedTrackingStream(fixture);
seedAssociation(fixture, "track0", 1, 0, 600, "candidate");
seedAssociation(fixture, "track0", 2, 14, 16, "assigned");

candidates = vawlume.tracking.identityCandidates(fixture.conn, streamRef(), ...
    [14.5 15.5]);
verifyEqual(testCase, height(candidates.associations), 2);
verifyEqual(testCase, sort(double(candidates.associations.entity_id))', [1 2]);

% And the resolver, over the same data, chose one without changing the query.
resolved = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), [14.5 15.5]);
verifyEqual(testCase, height(resolved.candidates.associations), 2);
verifyEqual(testCase, resolved.resolutions.entity_id(1), 2);
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

function value = streamRef()
value = struct(project_key="p1", stream_name="video-track");
end

function value = channelRowCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM recording_channels");
value = double(rows.n(1));
end

function id = seedAssociation(fixture, trackId, entityId, startTime, endTime, state)
% An unresolved claim names no entity: "somebody looked and could not tell" and
% "this is entity 2" are different statements, and a Phase 2 trigger keeps them
% apart. The fixture honours that rather than working around it.
if isnan(entityId)
    entityText = "NULL";
else
    entityText = string(entityId);
end
execute(fixture.conn, "INSERT INTO tracking_identity_associations(" + ...
    "external_stream_id,native_track_id,entity_id,start_time_native," + ...
    "end_time_native,assignment_state,evidence_kind) VALUES(1,'" + ...
    trackId + "'," + entityText + "," + string(startTime) + "," + ...
    string(endTime) + ",'" + state + "','manual_assertion')");
rows = fetch(fixture.conn, "SELECT last_insert_rowid() AS id");
id = double(rows.id(1));
end

function seedTrackingStream(fixture)
execute(fixture.conn, "INSERT INTO timebases(timebase_id,project_id," + ...
    "recording_id,timebase_name,timebase_kind,native_unit) " + ...
    "VALUES(1,1,1,'video_native','video_clock','s')");
execute(fixture.conn, "INSERT INTO external_streams(external_stream_id," + ...
    "project_id,recording_id,timebase_id,stream_name,stream_kind) " + ...
    "VALUES(1,1,1,1,'video-track','tracking')");
vawlume.geometry.registerCoordinateSystem(fixture.conn, ...
    struct(project_key="p1"), struct(coordinate_system_key="arena", ...
        coordinate_system_name="Arena frame", dimensionality=2, unit="m"));
execute(fixture.conn, "INSERT INTO tracking_streams(external_stream_id," + ...
    "coordinate_system_id,native_time_basis) VALUES(1,1,'time')");
% identityCandidates lists every track the stream contains, so a track needs a
% series row to be visible at all -- evidence alone does not conjure a track.
execute(fixture.conn, "INSERT INTO tracking_series(external_stream_id," + ...
    "native_track_id,native_bodypart_label) VALUES(1,'track0','snout')");
end

function candidateId = seedAttributionCandidate(fixture)
execute(fixture.conn, "INSERT INTO config_profiles(profile_id,project_id," + ...
    "profile_key,profile_name,profile_kind) VALUES" + ...
    "(1,1,'ci','Caller input','attribution_input_mapping')");
execute(fixture.conn, "INSERT INTO config_profile_versions(profile_version_id," + ...
    "profile_id,version_label,content_format,content_uri,checksum_sha256," + ...
    "is_snapshot) VALUES(1,1,'1.0.0','json','config/c.json','" + ...
    repmat('a', 1, 64) + "',1)");
execute(fixture.conn, "INSERT INTO extractors(extractor_id,extractor_key," + ...
    "extractor_name) VALUES(1,'ds','DeepSqueak')");
execute(fixture.conn, "INSERT INTO extractor_versions(extractor_version_id," + ...
    "extractor_id,version_label) VALUES(1,1,'v1')");
execute(fixture.conn, "INSERT INTO extraction_runs(extraction_run_id," + ...
    "project_id,extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(fixture.conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id) VALUES(1,1)");
execute(fixture.conn, "INSERT INTO detections(detection_id,extraction_run_id," + ...
    "recording_id,start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5)");
run = vawlume.attribution.createRun(fixture.conn, struct(recording_id=1), ...
    struct(run_key="p47", attribution_path="imported", method="X", ...
        settings_profile_version_id=1, target_set=struct(detection_ids=1), ...
        participating_entity_ids=[1 2], sources=struct(source_file_ids=2)), ...
    Apply=true);
targets = fetch(fixture.conn, "SELECT attribution_target_id AS id " + ...
    "FROM attribution_targets WHERE attribution_run_id=" + ...
    string(run.run.attribution_run_id));
vawlume.attribution.addCandidates(fixture.conn, ...
    struct(attribution_target_id=double(targets.id(1))), ...
    struct(entity_id=1, score=0.9, score_semantics="upstream score, uncalibrated"), ...
    Apply=true);
rows = fetch(fixture.conn, "SELECT attribution_candidate_id AS id " + ...
    "FROM attribution_candidates");
candidateId = double(rows.id(1));
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_closures_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "closures.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedFixture(conn);
fixture = struct(conn=conn, workspace=string(workspace), repo_root=string(repoRoot));
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
    "path_or_uri,relative_path) VALUES" + ...
    "(1,1,'recording_audio','audio.wav','audio.wav')," + ...
    "(2,1,'attribution_output','caller.csv','caller.csv')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id,channel_count,sample_rate_hz) VALUES(1,1,1,'R1',2,250000)");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES" + ...
    "(1,1,1,'participant'),(2,1,2,'participant')");
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function root = repoRootForTest()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
