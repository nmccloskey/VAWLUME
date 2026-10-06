function tests = test_identity_candidate_geometry
%TEST_IDENTITY_CANDIDATE_GEOMETRY Itinerary 6.5: track -> entity -> microphone.
%
% The session is 6.4's (test_event_window_tracking_retrieval): a piecewise audio
% clock, an affine video clock, a neural reference, and two native tracks whose
% snouts move linearly in video time. Added here: two placed microphones and an
% unplaced third channel, a second frame with a placement in it, three linked
% participants (A, B, C), and identity associations arranged per call so that
% every identity outcome is reachable:
%
%   detection 1 (~300.0 s)   track0 -> A, track1 -> B, both for the whole call
%   detection 6 (~300.6 s)   track1 also narrowly claimed A: A has two tracks
%   detection 7 (~300.95 s)  track0's A claim ends inside the call: partial
%   detection 2 (~900 s)     track1's two candidate claims tie: unresolved
%   detection 5 (~1100.1 s)  the tracks swap identities during the call
%   detection 3 (~600 s)     claims exist, coverage exists, but no samples
%   detection 4 (~2000 s)    claims exist, but no declared coverage
%
% Participant C never has a track. The fixture's own setup is a copy of 6.4's,
% kept local because this repository's tests carry their fixtures with them.
tests = functiontests(localfunctions);
end

% =================================================== identityOverWindow ===

function testAWholeWindowClaimIsValidForTheWholeWindow(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
identity = identityFor(fixture, 1);
verifyEqual(testCase, identity.tracks.time_validity, ["whole_window"; "whole_window"]);
verifyEqual(testCase, identity.tracks.entity_id, [fixture.A; fixture.B]);
verifyEqual(testCase, identity.tracks.identity_status, ["resolved"; "resolved"]);
verifyEqual(testCase, height(identity.contradictions), 0);
clear cleanup
end

function testASwapDuringTheCallIsAChangeNotAMidpointAnswer(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
identity = identityFor(fixture, 5);
verifyEqual(testCase, identity.tracks.time_validity, ...
    ["changes_within_window"; "changes_within_window"]);
verifyEqual(testCase, identity.tracks.contradiction_count, [1; 1]);
verifyEqual(testCase, sort(identity.contradictions.entity_id), sort([fixture.A; fixture.B]));
clear cleanup
end

function testASwapExactlyAtTheMidpointIsStillAChange(testCase)
% The swap instant equals the call's midpoint on the tracking clock. Answering
% with "whichever claim covers the midpoint" would pick one silently.
[fixture, cleanup] = setUpSession(SwapAtMidpoint=true); %#ok<ASGLU>
identity = identityFor(fixture, 5);
verifyEqual(testCase, unique(identity.tracks.time_validity), "changes_within_window");
clear cleanup
end

function testAChosenClaimCoveringPartOfTheCallIsPartial(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
identity = identityFor(fixture, 7);
row = identity.tracks(identity.tracks.native_track_id == "track0", :);
verifyEqual(testCase, row.time_validity, "partial");
verifyEqual(testCase, row.entity_id, fixture.A);
clear cleanup
end

function testATieIsReportedAndNotBroken(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
identity = identityFor(fixture, 2);
row = identity.tracks(identity.tracks.native_track_id == "track1", :);
verifyEqual(testCase, row.identity_status, "tied");
verifyEqual(testCase, row.time_validity, "none");
verifyTrue(testCase, isnan(row.entity_id));
clear cleanup
end

function testTheHelperChoosesWhatResolveIdentityChooses(testCase)
% It adds time validity and no precedence rule: whenever the window is valid,
% the chosen association is resolveIdentity's own.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
for detection = [1 6 7 2 5]
    window = nativeWindowFor(fixture, detection);
    identity = vawlume.tracking.identityOverWindow(fixture.conn, streamRef(), window);
    resolved = vawlume.tracking.resolveIdentity(fixture.conn, streamRef(), window);
    verifyEqual(testCase, identity.tracks.tracking_identity_association_id, ...
        resolved.resolutions.tracking_identity_association_id);
    verifyEqual(testCase, identity.tracks.decided_by_step, ...
        string(resolved.resolutions.decided_by_step));
end
clear cleanup
end

function testNoEvidenceIsNoneNotUnresolved(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
identity = vawlume.tracking.identityOverWindow(fixture.conn, streamRef(), [100 101]);
verifyEqual(testCase, unique(identity.tracks.identity_status), "none");
verifyEqual(testCase, unique(identity.tracks.time_validity), "none");
clear cleanup
end

% ==================================================== candidateGeometry ===

function testDistancesMatchGroundTruthThroughIdentity(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 1);
verifyEqual(testCase, result.entities.has_geometry, [true; true; false]);
verifyEqual(testCase, result.entities.native_track_id(1:2), ["track0"; "track1"]);
for entity = [fixture.A fixture.B]
    track = "track0";
    if entity == fixture.B
        track = "track1";
    end
    for basis = ["onset", "midpoint", "offset"]
        instant = result.event.instants(result.event.instants.instant_basis == basis, :);
        video = (instant.time_reference_s - fixture.video_offset) / fixture.video_scale;
        [x, y] = truePosition(track, video);
        for channel = [1 2]
            row = result.geometry(result.geometry.entity_id == entity & ...
                result.geometry.channel_index == channel & ...
                result.geometry.instant_basis == basis, :);
            mic = fixture.mics(channel, :);
            verifyEqual(testCase, row.distance, sqrt((x - mic(1))^2 + (y - mic(2))^2), ...
                AbsTol=1e-6);
            verifyEqual(testCase, row.status, "computed");
            verifyEqual(testCase, row.unit, "cm");
            verifyEqual(testCase, row.distance_basis, "planar");
            verifyEqual(testCase, row.native_track_id, track);
            verifyGreaterThan(testCase, row.tracking_identity_association_id, 0);
        end
    end
end
clear cleanup
end

function testWindowSummariesUseObservedSamples(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 1);
rows = result.geometry(result.geometry.entity_id == fixture.A & ...
    result.geometry.channel_index == 1 & ...
    ismember(result.geometry.instant_basis, ["window_median", "window_min"]), :);
verifyEqual(testCase, rows.status, ["computed"; "computed"]);
verifyGreaterThan(testCase, rows.n_samples(1), 0);
verifyLessThanOrEqual(testCase, rows.distance(2), rows.distance(1));
verifyEqual(testCase, rows.position_basis, ["observed_samples"; "observed_samples"]);
clear cleanup
end

function testAnEntityWithNoTrackHasNoGeometryAndSaysWhy(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 1);
c = result.entities(result.entities.entity_id == fixture.C, :);
verifyFalse(testCase, c.has_geometry);
verifyEqual(testCase, c.reason, "identity_no_track");
verifyEqual(testCase, sum(result.geometry.entity_id == fixture.C), 0);
clear cleanup
end

function testTwoTracksClaimingOneEntityGiveNoDistance(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 6);
a = result.entities(result.entities.entity_id == fixture.A, :);
verifyEqual(testCase, a.reason, "identity_multiple_tracks");
verifyEqual(testCase, sum(result.geometry.entity_id == fixture.A), 0);
% The reverse view shows it: two tracks, both on a participant.
verifyEqual(testCase, sum(result.tracks.entity_id == fixture.A), 2);
clear cleanup
end

function testASwapGivesNoDistanceForEitherEntity(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 5);
verifyEqual(testCase, result.entities.reason(1:2), ...
    ["identity_changes_within_window"; "identity_changes_within_window"]);
verifyEqual(testCase, height(result.geometry), 0);
clear cleanup
end

function testAPartialClaimGivesNoDistance(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 7);
a = result.entities(result.entities.entity_id == fixture.A, :);
verifyEqual(testCase, a.reason, "identity_partial_window");
verifyEqual(testCase, a.time_validity, "partial");
b = result.entities(result.entities.entity_id == fixture.B, :);
verifyTrue(testCase, b.has_geometry);
clear cleanup
end

function testATiedTrackMakesUnmatchedEntitiesUnresolved(testCase)
% At detection 2, track0 is A for the whole call and track1's claims tie
% between B and C. B and C could be track1, so neither is "no track".
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 2);
verifyTrue(testCase, result.entities.has_geometry(result.entities.entity_id == fixture.A));
verifyEqual(testCase, result.entities.reason(result.entities.entity_id ~= fixture.A), ...
    ["identity_unresolved"; "identity_unresolved"]);
clear cleanup
end

function testCoveredButEmptyAndUncoveredAreDistinct(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
empty = geometryFor(fixture, 3);
verifyEqual(testCase, empty.sample_status, "empty");
emptyRows = empty.geometry(empty.geometry.entity_id == fixture.A, :);
verifyEqual(testCase, unique(emptyRows.reason), "track_covered_empty");
verifyTrue(testCase, all(isnan(emptyRows.distance)));

uncovered = geometryFor(fixture, 4);
verifyEqual(testCase, uncovered.coverage_status, "uncovered");
uncoveredRows = uncovered.geometry(uncovered.geometry.entity_id == fixture.A, :);
verifyEqual(testCase, unique(uncoveredRows.reason), "track_not_covered");
verifyTrue(testCase, all(uncoveredRows.event_extrapolated(1:3)));
clear cleanup
end

function testAnUnplacedChannelIsItsOwnState(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 1, Channels=[1 3]);
rows = result.geometry(result.geometry.channel_index == 3, :);
verifyEqual(testCase, unique(rows.reason), "channel_unplaced");
verifyTrue(testCase, all(isnan(rows.distance)));
verifyTrue(testCase, all(isnan(rows.recording_channel_id)));
clear cleanup
end

function testAPlacementInAnotherFrameIsRefused(testCase)
% Channel 4 is placed in a second 2D 'cm' frame. Same dimensionality, same unit,
% different frame: refused, and nothing is transformed.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
verifyError(testCase, @() geometryFor(fixture, 1, Channels=[1 4]), ...
    "vawlume:geometry:CoordinateSystemMismatch");
clear cleanup
end

function testAMissingBodypartIsNotSubstituted(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 1, Bodypart="left_ear");
verifyEqual(testCase, result.tracking_status, "bodypart_missing");
verifyEqual(testCase, unique(result.geometry.reason), "bodypart_missing");
clear cleanup
end

function testParticipantsAreLinkedEntitiesNeverTrackLabels(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
verifyError(testCase, @() vawlume.estimator.candidateGeometry(fixture.conn, ...
    struct(detection_id=1), audioClock(fixture), trackingSpec(fixture, "snout"), ...
    [fixture.A fixture.unlinked], [1 2]), "vawlume:estimator:ParticipantNotLinked");
clear cleanup
end

function testATrackNamedLikeAnEntityDoesNotLinkToIt(testCase)
% The entity "track0" exists, is linked to the recording, and is a participant.
% No association names it, so it has no track, even though a native track
% carries exactly its native_id as a label.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = vawlume.estimator.candidateGeometry(fixture.conn, struct(detection_id=1), ...
    audioClock(fixture), trackingSpec(fixture, "snout"), ...
    [fixture.A fixture.B fixture.lookalike], [1 2]);
row = result.entities(result.entities.entity_id == fixture.lookalike, :);
verifyFalse(testCase, row.has_geometry);
verifyEqual(testCase, row.reason, "identity_no_track");
verifyEqual(testCase, sum(result.geometry.entity_id == fixture.lookalike), 0);
clear cleanup
end

function testPoseConfidenceAndClockEvidenceTravelSeparately(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
result = geometryFor(fixture, 1);
rows = result.geometry(ismember(result.geometry.instant_basis, ...
    ["onset", "midpoint", "offset"]), :);
verifyEqual(testCase, unique(rows.pose_confidence_min_bracket), 0.95);
verifyTrue(testCase, all(isfinite(rows.clock_uncertainty_s)));
verifyFalse(testCase, any(rows.event_extrapolated | rows.bracket_extrapolated));
verifyEqual(testCase, result.event.alignment_run_id, fixture.audio_run);
verifyEqual(testCase, result.tracking_clock.alignment_run_id, fixture.video_run);
clear cleanup
end

function testNothingIsWritten(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
before = tableCounts(fixture.conn);
geometryFor(fixture, 1);
geometryFor(fixture, 5);
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

% ===================================================== the static guard ===

function testNoCodeComparesATrackLabelWithAnEntityIdentifier(testCase)
% Invariant 26 (contract D12): a track reaches an entity only through a cited
% tracking_identity_associations row. The failure this guards against is the one
% doc 24 records an early draft making: matching experimental_entities.native_id
% against a track label. Searched in +estimator/ and +tracking/, string literals
% KEPT so SQL joins are seen, comments removed.
root = repoRootPath();
hits = labelEntityComparisons(root);
verifyEmpty(testCase, hits, "A track label compared with an entity identifier:" + ...
    newline + strjoin(hits, newline));
% The probe can fire.
verifyNotEmpty(testCase, lineComparesLabelWithEntity( ...
    "match = entities.native_id == samples.native_track_id;"));
verifyNotEmpty(testCase, lineComparesLabelWithEntity( ...
    """JOIN experimental_entities e ON e.native_id = ts.native_track_id"""));
verifyNotEmpty(testCase, lineComparesLabelWithEntity( ...
    "hit = strcmp(trackId, row.entity_native_id);"));
verifyEmpty(testCase, lineComparesLabelWithEntity( ...
    "rows = table(trackId, string(resolution.entity_native_id));"));
verifyEmpty(testCase, lineComparesLabelWithEntity( ...
    "names = [""native_track_id"", ""entity_id"", ""entity_native_id""];"));
end

% ================================================================ helpers ===

function hits = labelEntityComparisons(root)
hits = strings(0, 1);
for folder = ["+estimator", "+tracking"]
    files = dir(fullfile(root, "src", "+vawlume", folder, "**", "*.m"));
    for index = 1:numel(files)
        path = fullfile(files(index).folder, files(index).name);
        lines = splitlines(string(fileread(path)));
        for lineNumber = 1:numel(lines)
            code = regexprep(lines(lineNumber), "^\s*%.*$", "");
            if ~isempty(lineComparesLabelWithEntity(code))
                hits(end + 1, 1) = files(index).name + ":" + lineNumber + ": " + ...
                    strtrim(code); %#ok<AGROW>
            end
        end
    end
end
end

function hit = lineComparesLabelWithEntity(code)
% Two genuine shapes, and only those:
%   (a) in CODE, outside string literals: a track-label token, an entity
%       native-identifier token and a comparison on one line;
%   (b) in ONE string literal (a SQL fragment): both tokens and an '='.
% A list of column names - ["native_track_id", "entity_native_id", ...] - puts
% each token in its own literal and compares nothing. The first version of this
% probe matched raw lines and reported three such lists as violations.
literals = regexp(code, """[^""]*""|'[^']*'", "match");
outside = regexprep(code, """[^""]*""|'[^']*'", "");
labelPattern = "native_track_id|track_label|\<trackIds?\>";
entityPattern = "\<native_id\>|entity_native_id|entity_key";
% In code, assignment is not comparison: only == and ~= and the comparing
% functions count. A bare = counts only inside a SQL literal, above.
comparePattern = "==|~=|\<strcmpi?\>|\<ismember\>|\<matches\>|" + ...
    "\<contains\>|\<isequal\>|\<intersect\>|\<startsWith\>";
inCode = ~isempty(regexp(outside, labelPattern, "once")) && ...
    ~isempty(regexp(outside, entityPattern, "once")) && ...
    ~isempty(regexp(outside, comparePattern, "once"));
inSql = false;
for literal = string(literals)
    if ~isempty(regexp(literal, labelPattern, "once")) && ...
            ~isempty(regexp(literal, entityPattern, "once")) && contains(literal, "=")
        inSql = true;
    end
end
hit = [];
if inCode || inSql
    hit = code;
end
end
function identity = identityFor(fixture, detectionId)
identity = vawlume.tracking.identityOverWindow(fixture.conn, streamRef(), ...
    nativeWindowFor(fixture, detectionId));
end

function window = nativeWindowFor(fixture, detectionId)
instants = vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=detectionId), audioClock(fixture));
window = vawlume.alignment.applyInverseTransform(fixture.conn, fixture.video_run, ...
    instants.reference_interval(:))';
end

function result = geometryFor(fixture, detectionId, options)
arguments
    fixture
    detectionId
    options.Channels = [1 2]
    options.Bodypart = "snout"
end
result = vawlume.estimator.candidateGeometry(fixture.conn, ...
    struct(detection_id=detectionId), audioClock(fixture), ...
    trackingSpec(fixture, options.Bodypart), [fixture.A fixture.B fixture.C], ...
    options.Channels);
end

function value = trackingSpec(fixture, bodypart)
value = struct(stream=streamRef(), bodypart=bodypart, max_gap_s=0.05, ...
    alignment_run_id=fixture.video_run, source_root=fixture.workspace, ...
    repo_root=fixture.repo_root);
end

function value = audioClock(fixture)
value = struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
    audio_alignment_run_id=fixture.audio_run);
end

function value = streamRef()
value = struct(project_key="synthetic_alignment_session", stream_name="arena_tracking");
end

function [x, y] = truePosition(track, videoTime)
if track == "track0"
    x = 10 + 0.01 * videoTime;
    y = 20 + 0 * videoTime;
else
    x = 50 + 0 * videoTime;
    y = 20 + 0.005 * videoTime;
end
end

function counts = tableCounts(conn)
names = ["tracking_identity_associations", "attribution_evidence", ...
    "attribution_candidates", "derived_measurements", "channel_placements"];
counts = zeros(1, numel(names));
for k = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(k));
    counts(k) = double(rows.n(1));
end
end

function [fixture, cleanup] = setUpSession(options)
arguments
    options.SwapAtMidpoint (1,1) logical = false
end
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
workspace = string(fullfile(tempdir, "vawlume_identity_geometry_" + ...
    string(java.util.UUID.randomUUID)));
mkdir(workspace);
conn = sqlite(char(fullfile(workspace, "session.sqlite")), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, fullfile(repoRoot, "src")));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

execute(conn, "INSERT INTO projects(project_key, project_name) VALUES " + ...
    "('synthetic_alignment_session', 'Synthetic alignment session')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, " + ...
    "relative_path) VALUES (1, 'recording_audio', 'synthetic/session01.wav', " + ...
    "'session01.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, " + ...
    "native_recording_id, sample_rate_hz) VALUES (1, 1, 'REC_SESSION_01', 250000)");

fixture = struct(conn=conn, workspace=workspace, repo_root=repoRoot, knot=900, ...
    video_scale=0.9992, video_offset=53.40, mics=[0 0; 100 0]);
fixture.scale = [1.0015; 0.9990];
fixture.offset = [117.25; (1.0015 - 0.9990) * fixture.knot + 117.25];
audioTimes = [10; 400; 900; 1200; 1500];
segment = 1 + double(audioTimes >= fixture.knot);
neuralTimes = fixture.scale(segment) .* audioTimes + fixture.offset(segment);
videoTimes = (neuralTimes - fixture.video_offset) / fixture.video_scale;
writetable(behaviorTable(), fullfile(workspace, "video_events.csv"));
writetable(neuralTable(neuralTimes), fullfile(workspace, "neural_events.csv"));
writetable(anchorTable(audioTimes, videoTimes, neuralTimes), ...
    fullfile(workspace, "sync_anchors.csv"));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
vawlume.ingest.alignment(conn, string(manifestPath), RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);
execute(conn, "UPDATE time_alignment_runs SET method='piecewise_affine' " + ...
    "WHERE source_timebase_id = (SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='audio_native')");
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="video_native", Apply=true);
fixture.audio_run = runIdFor(conn, "audio_native");
fixture.video_run = runIdFor(conn, "video_native");

execute(conn, "INSERT INTO extractors(extractor_key, extractor_name) VALUES ('ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_id, version_label) VALUES (1,'v')");
execute(conn, "INSERT INTO extraction_runs(project_id, extractor_version_id, run_key) " + ...
    "VALUES (1, 1, 'calls')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id, recording_id) VALUES (1, 1)");
execute(conn, "INSERT INTO detections(detection_id, extraction_run_id, recording_id, " + ...
    "start_time_s, end_time_s) VALUES (1,1,1,300.0,300.1),(2,1,1,899.9,900.1)," + ...
    "(3,1,1,600.0,600.1),(4,1,1,2000.0,2000.1),(5,1,1,1100.0,1100.2)," + ...
    "(6,1,1,300.6,300.7),(7,1,1,300.9,301.0)");

% Participants A, B, C, a lookalike entity whose native_id equals a track label,
% and one entity not linked to the recording.
execute(conn, "INSERT INTO entity_types(project_id, native_name) VALUES (1, 'subject')");
execute(conn, "INSERT INTO experimental_entities(entity_id, project_id, entity_type_id, " + ...
    "native_id) VALUES (1,1,1,'A'),(2,1,1,'B'),(3,1,1,'C'),(4,1,1,'track0'),(5,1,1,'X')");
execute(conn, "INSERT INTO recording_entity_links(recording_id, entity_id) " + ...
    "VALUES (1,1),(1,2),(1,3),(1,4)");
fixture.A = 1; fixture.B = 2; fixture.C = 3; fixture.lookalike = 4; fixture.unlinked = 5;

vawlume.geometry.registerCoordinateSystem(conn, struct(project_id=1), struct( ...
    coordinate_system_key="arena_2d", coordinate_system_name="Arena floor plane", ...
    dimensionality=2, unit="cm"));
vawlume.geometry.registerCoordinateSystem(conn, struct(project_id=1), struct( ...
    coordinate_system_key="other_2d", coordinate_system_name="Another arena", ...
    dimensionality=2, unit="cm"));
for channel = 1:4
    vawlume.geometry.registerRecordingChannel(conn, struct(recording_id=1), ...
        struct(channel_index=channel));
end
for channel = 1:2
    vawlume.geometry.registerChannelPlacement(conn, struct(recording_id=1), struct( ...
        channel_index=channel, coordinate_system_key="arena_2d", ...
        position_x=fixture.mics(channel, 1), position_y=fixture.mics(channel, 2)));
end
vawlume.geometry.registerChannelPlacement(conn, struct(recording_id=1), struct( ...
    channel_index=4, coordinate_system_key="other_2d", position_x=0, position_y=0));

regions = [videoAround(fixture, 300.5, 1.5); videoAround(fixture, 900.0, 1); ...
    videoAround(fixture, 1100.1, 1)];
writeTrackingCsv(fullfile(workspace, "arena_tracking.csv"), regions);
profilePath = fullfile(workspace, "tracking_profile.json");
writelines(string(fileread(fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "tracking", "generic_tracking_mapping_profile.json"))), profilePath);
vawlume.tracking.register(conn, struct(recording_id=1), struct( ...
    artifact_path="arena_tracking.csv", profile_path=profilePath, ...
    timebase_key="video_native", stream_name="arena_tracking"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=workspace);

registerIdentity(fixture, options.SwapAtMidpoint);
end

function registerIdentity(fixture, swapAtMidpoint)
v = @(audioTime) videoTimeOf(fixture, audioTime);
claim = @(track, entity, startAudio, endAudio, state) ...
    vawlume.tracking.registerIdentityAssociation(fixture.conn, streamRef(), struct( ...
    native_track_id=track, entity_id=entity, start_time_native=v(startAudio), ...
    end_time_native=v(endAudio), assignment_state=state, ...
    evidence_kind="manual_assertion"));
% Region 1 (around 300 s): track0 is A until 300.95 s; track1 is B throughout,
% and also narrowly A around detection 6.
claim("track0", fixture.A, 299.0, 300.95, "assigned");
claim("track1", fixture.B, 299.0, 302.0, "assigned");
claim("track1", fixture.A, 300.55, 300.75, "assigned");
% Detections 3 and 4: identity is clear; tracking is what is missing.
claim("track0", fixture.A, 590, 610, "assigned");
claim("track1", fixture.B, 590, 610, "assigned");
claim("track0", fixture.A, 1990, 2010, "assigned");
claim("track1", fixture.B, 1990, 2010, "assigned");
% Region 2 (around 900 s): track0 is A; track1 ties between B and C.
claim("track0", fixture.A, 898, 902, "assigned");
claim("track1", fixture.B, 898, 902, "candidate");
claim("track1", fixture.C, 898, 902, "candidate");
% Region 3 (around 1100 s): the tracks swap during detection 5.
swap = 1100.15;
if swapAtMidpoint
    swap = 1100.1;
end
claim("track0", fixture.A, 1099, swap, "assigned");
claim("track0", fixture.B, swap, 1101.2, "assigned");
claim("track1", fixture.B, 1099, swap, "assigned");
claim("track1", fixture.A, swap, 1101.2, "assigned");
end

function value = videoTimeOf(fixture, audioTime)
reference = vawlume.alignment.applyTransform(fixture.conn, fixture.audio_run, audioTime);
value = (reference - fixture.video_offset) / fixture.video_scale;
end

function region = videoAround(fixture, audioTime, halfWidth)
center = videoTimeOf(fixture, audioTime);
region = [center - halfWidth, center + halfWidth];
end

function writeTrackingCsv(path, regions)
lines = "time_s,subject,bodypart,x,y,likelihood";
for r = 1:height(regions)
    times = (ceil(regions(r, 1) * 30):floor(regions(r, 2) * 30))' / 30;
    for t = times'
        for track = ["track0", "track1"]
            [x, y] = truePosition(track, t);
            for part = ["snout", "tail_base"]
                lines(end + 1, 1) = compose("%.9f", t) + "," + track + "," + part + ...
                    "," + compose("%.9f", x) + "," + compose("%.9f", y) + ",0.95"; %#ok<AGROW>
            end
        end
    end
end
writelines(lines, path);
end

function tbl = behaviorTable()
tbl = table(["b1"; "b2"; "b3"], ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    ["10"; "20"; "30"], ["12"; missing; "30"], ["F01"; "M01"; ""], ...
    ["door"; "center"; "sync"], VariableNames=["event_id", "event", ...
    "start_time_s", "end_time_s", "subject", "zone"]);
end

function tbl = neuralTable(neuralTimes)
ids = "n" + string(1:numel(neuralTimes))';
tbl = table(ids, repmat("TTL1_HIGH", numel(ids), 1), ...
    compose("%.9f", neuralTimes * 1000), repmat("5", numel(ids), 1), ...
    repmat("1", numel(ids), 1), ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
end

function tbl = anchorTable(audioTimes, videoTimes, neuralTimes)
keys = "sync0" + string(1:numel(audioTimes))';
markers = repelem(keys, 3);
streams = repmat(["audio"; "video"; "neural"], numel(keys), 1);
timestamps = strings(3 * numel(keys), 1);
eventIds = strings(3 * numel(keys), 1);
for index = 1:numel(keys)
    base = (index - 1) * 3;
    timestamps(base + 1) = compose("%.9f", audioTimes(index));
    timestamps(base + 2) = compose("%.9f", videoTimes(index));
    timestamps(base + 3) = compose("%.9f", neuralTimes(index));
    eventIds(base + 3) = "n" + string(index);
end
tbl = table(markers, streams, timestamps, repmat("primary", 3 * numel(keys), 1), ...
    repmat("true", 3 * numel(keys), 1), repmat("0.002", 3 * numel(keys), 1), eventIds, ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
end

function value = runIdFor(conn, timebaseKey)
rows = fetch(conn, "SELECT t.alignment_run_id FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = double(rows.alignment_run_id(1));
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

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
