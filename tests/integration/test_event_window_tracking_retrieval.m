function tests = test_event_window_tracking_retrieval
%TEST_EVENT_WINDOW_TRACKING_RETRIEVAL Itinerary 6.4: event -> tracking positions.
%
% The session reuses the alignment suite's construction: an audio clock that
% changes drift regime at 900 s (piecewise, continuous), a video clock related
% by an affine map, and a neural clock that is the reference. A tracking stream
% on the video clock carries two native tracks whose snout moves LINEARLY in
% video time, so every interpolated position has an exact ground truth.
%
% Three things are under test:
%   * vawlume.alignment.applyInverseTransform - additive, round-trips at
%     interiors and exactly at the breakpoint, refuses what is not invertible,
%     flags extrapolation; the forward functions are untouched;
%   * vawlume.estimator.eventReferenceInstants - an event's instants placed on
%     the reference clock only through the alignment API, from an explicitly
%     declared clock relation;
%   * vawlume.tracking.positionsAtInstants - per-track positions with every
%     state kept distinct, and no entity anywhere in the result.
tests = functiontests(localfunctions);
end

% =========================================================== the inverse ===

function testInverseRoundTripsAtInteriorsAndAtTheBreakpoint(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
conn = fixture.conn;
native = [10; 400; 899.5; fixture.knot; 900.25; 1200; 1500];
reference = vawlume.alignment.applyTransform(conn, fixture.audio_run, native);
[back, transform] = vawlume.alignment.applyInverseTransform(conn, ...
    fixture.audio_run, reference);
verifyEqual(testCase, back, native, AbsTol=1e-9);
% The breakpoint belongs to the segment beginning there, on both sides.
[~, forward] = vawlume.alignment.applyTransform(conn, fixture.audio_run, native);
verifyEqual(testCase, transform.segment_index, forward.segment_index);
verifyEqual(testCase, transform.segment_index(4), 2);
verifyEqual(testCase, transform.direction, "reference_to_native");
% And reference -> native -> reference.
again = vawlume.alignment.applyTransform(conn, fixture.audio_run, back);
verifyEqual(testCase, again, reference, AbsTol=1e-9);
clear cleanup
end

function testInverseOfAnAffineRunMatchesItsGroundTruth(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
reference = [500; 1000];
native = vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.video_run, reference);
verifyEqual(testCase, native, (reference - fixture.video_offset) / fixture.video_scale, ...
    AbsTol=1e-6);
clear cleanup
end

function testInverseFlagsAndEscalatesExtrapolation(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
% Anchors covered audio 10..1500 s. A reference time mapping to audio 2000 s is
% still inverted and flagged; a supported one is not flagged.
reference = vawlume.alignment.applyTransform(fixture.conn, fixture.audio_run, ...
    [400; 2000]);
[~, transform] = vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.audio_run, reference);
verifyEqual(testCase, transform.extrapolated, [false; true]);
verifyError(testCase, @() vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.audio_run, reference, ErrorOnExtrapolation=true), ...
    "vawlume:alignment:ExtrapolatedTime");
clear cleanup
end

function testInverseCarriesTheStoredUncalibratedBound(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[reference, forward] = vawlume.alignment.applyTransform(fixture.conn, ...
    fixture.audio_run, [400; 1200]);
[~, inverse] = vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.audio_run, reference);
verifyEqual(testCase, inverse.uncertainty_s, forward.uncertainty_s);
verifyTrue(testCase, all(isfinite(inverse.uncertainty_s)));
verifyTrue(testCase, contains(inverse.uncertainty_note, "uncalibrated"));
verifyEqual(testCase, inverse.uncertainty_semantics, forward.uncertainty_semantics);
clear cleanup
end

function testANonPositiveScaleIsNotInverted(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE alignment_segments SET scale=-0.5 WHERE " + ...
    "alignment_run_id=" + fixture.video_run);
verifyError(testCase, @() vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.video_run, 100), "vawlume:alignment:TransformNotInvertible");
clear cleanup
end

function testADiscontinuousStoredTransformIsNotInverted(testCase)
% A fitted transform is continuous by construction. A hand-edited one that jumps
% at its breakpoint maps some reference times to two native times or none.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE alignment_segments SET offset_s=offset_s+0.01 " + ...
    "WHERE alignment_run_id=" + fixture.audio_run + " AND segment_index=2");
verifyError(testCase, @() vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.audio_run, 1000), "vawlume:alignment:TransformNotInvertible");
clear cleanup
end

function testAReferenceTimeBelowABoundedImageIsRefused(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
execute(fixture.conn, "UPDATE alignment_segments SET source_start=0 WHERE " + ...
    "alignment_run_id=" + fixture.video_run);
verifyError(testCase, @() vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.video_run, -1000), "vawlume:alignment:ReferenceTimeOutsideTransform");
clear cleanup
end

% ============================================= event -> reference instants ===

function testEventInstantsArePlacedThroughTheAlignmentLayer(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
instants = vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=1), audioClock(fixture));
verifyEqual(testCase, instants.instants.instant_basis, ["onset"; "midpoint"; "offset"]);
native = [300.0; 300.05; 300.1];
verifyEqual(testCase, instants.instants.time_native_s, native, AbsTol=1e-12);
expected = vawlume.alignment.applyTransform(fixture.conn, fixture.audio_run, native);
verifyEqual(testCase, instants.instants.time_reference_s, expected, AbsTol=1e-12);
verifyEqual(testCase, instants.alignment_run_id, fixture.audio_run);
verifyEqual(testCase, instants.recording_timebase_key, "audio_native");
verifyEqual(testCase, instants.reference_timebase_key, "neural_native");
clear cleanup
end

function testAnEventAcrossTheBreakpointReportsItsDurationChange(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
instants = vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=2), audioClock(fixture));
verifyTrue(testCase, instants.crosses_breakpoint);
verifyNotEqual(testCase, instants.duration_change_s, 0);
% The midpoint is the native midpoint placed on the reference clock, not the
% average of the transformed endpoints.
verifyEqual(testCase, instants.instants.time_native_s(2), 900.0, AbsTol=1e-12);
verifyEqual(testCase, instants.instants.segment_index, [1; 2; 2]);
clear cleanup
end

function testAnExtrapolatedEventIsFlagged(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
instants = vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=4), audioClock(fixture));
verifyTrue(testCase, all(instants.instants.extrapolated));
clear cleanup
end

function testTheClockIsDeclaredNotDiscovered(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
conn = fixture.conn;
noRun = struct(clock_relation="alignment_run", reference_timebase_key="neural_native");
verifyError(testCase, @() vawlume.estimator.eventReferenceInstants(conn, ...
    struct(detection_id=1), noRun), "vawlume:estimator:ClockDeclarationInvalid");
wrongRun = audioClock(fixture);
wrongRun.audio_alignment_run_id = fixture.video_run;
verifyError(testCase, @() vawlume.estimator.eventReferenceInstants(conn, ...
    struct(detection_id=1), wrongRun), "vawlume:estimator:ClockDeclarationInvalid");
ownClockWithRun = struct(clock_relation="alignment_run", ...
    reference_timebase_key="audio_native", audio_alignment_run_id=fixture.audio_run);
verifyError(testCase, @() vawlume.estimator.eventReferenceInstants(conn, ...
    struct(detection_id=1), ownClockWithRun), "vawlume:estimator:ClockDeclarationInvalid");
% Same clock is a declaration, and it says so.
same = vawlume.estimator.eventReferenceInstants(conn, struct(detection_id=1), ...
    struct(clock_relation="same_clock"));
verifyEqual(testCase, same.instants.time_reference_s, same.instants.time_native_s);
verifyTrue(testCase, contains(same.uncertainty_note, "declared"));
clear cleanup
end

function testAgreementGroupsAndUnknownEventsAreRefused(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
verifyError(testCase, @() vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(agreement_group_id=1), audioClock(fixture)), ...
    "vawlume:estimator:EventSetUnsupported");
verifyError(testCase, @() vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=999), audioClock(fixture)), "vawlume:estimator:EventNotFound");
clear cleanup
end

% ================================================= positions at instants ===

function testPositionsMatchGroundTruthOnTheReferenceClock(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[instants, result] = positionsForDetection(fixture, 1);
verifyEqual(testCase, result.status, "read");
verifyEqual(testCase, result.coverage_status, "covered");
verifyEqual(testCase, result.sample_status, "populated");
verifyEqual(testCase, sort(result.tracks), ["track0"; "track1"]);
verifyEqual(testCase, result.coordinate_system.unit, "cm");
verifyEqual(testCase, result.clock.relation, "alignment_run");
for track = ["track0", "track1"]
    rows = result.positions(result.positions.native_track_id == track, :);
    verifyEqual(testCase, rows.instant_label, ["onset"; "midpoint"; "offset"]);
    verifyTrue(testCase, all(ismember(rows.basis, ["observed", "interpolated"])));
    videoTime = (instants.instants.time_reference_s - fixture.video_offset) / ...
        fixture.video_scale;
    [x, y] = truePosition(track, videoTime);
    verifyEqual(testCase, rows.x, x, AbsTol=1e-6);
    verifyEqual(testCase, rows.y, y, AbsTol=1e-6);
    verifyEqual(testCase, rows.coverage_state, repmat("covered", 3, 1));
end
% Observed samples inside the call window come back for window summaries.
verifyGreaterThan(testCase, height(result.window_samples), 0);
inside = result.window_samples.time_reference_s;
verifyTrue(testCase, all(inside >= instants.reference_interval(1) & ...
    inside < instants.reference_interval(2)));
clear cleanup
end

function testPoseConfidenceAndClockUncertaintyStaySeparate(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 1);
verifyTrue(testCase, result.has_pose_confidence);
verifyEqual(testCase, unique(result.positions.pose_confidence_min_bracket), 0.95);
% The clock bound is the alignment layer's own value for the tracking clock at
% each instant, carried verbatim with its semantics, beside pose confidence.
track0 = result.positions(result.positions.native_track_id == "track0", :);
[~, inverse] = vawlume.alignment.applyInverseTransform(fixture.conn, ...
    fixture.video_run, track0.query_time);
verifyEqual(testCase, track0.clock_uncertainty_s, inverse.uncertainty_s(:));
verifyEqual(testCase, track0.clock_uncertainty_semantics, inverse.uncertainty_semantics(:));
verifyTrue(testCase, all(isfinite(track0.clock_uncertainty_s)));
names = string(result.positions.Properties.VariableNames);
verifyFalse(testCase, any(contains(names, "combined") | contains(names, "entity")));
clear cleanup
end

function testAbsentPoseConfidenceIsReportedNotImputed(testCase)
[fixture, cleanup] = setUpSession(WithConfidence=false); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 1);
verifyFalse(testCase, result.has_pose_confidence);
verifyTrue(testCase, all(isnan(result.positions.pose_confidence_min_bracket)));
verifyTrue(testCase, all(isfinite(result.positions.x)));
clear cleanup
end

function testCoveredButEmptyIsNotAbsenceOfAnimals(testCase)
% Detection 3 falls between the two tracked regions: declared coverage spans
% them, but no sample was recorded there. That is a QC finding, distinct from
% "uncovered", and no position is invented.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 3);
verifyEqual(testCase, result.coverage_status, "covered");
verifyEqual(testCase, result.sample_status, "empty");
verifyEqual(testCase, unique(result.positions.basis), "not_covered");
verifyEqual(testCase, unique(result.positions.reason), "no_samples");
verifyEqual(testCase, unique(result.positions.coverage_state), "covered");
clear cleanup
end

function testUncoveredIsItsOwnState(testCase)
% Detection 4 maps beyond the tracking artifact's declared coverage.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 4);
verifyEqual(testCase, result.status, "uncovered");
verifyEqual(testCase, result.coverage_status, "uncovered");
verifyEqual(testCase, unique(result.positions.coverage_state), "uncovered");
verifyTrue(testCase, all(isnan(result.positions.x)));
clear cleanup
end

function testATrackPresentForPartOfTheWindowIsPerInstant(testCase)
% track1's samples stop part-way through detection 5; its later instants are
% not covered while track0's are interpolated as usual.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 5);
track0 = result.positions(result.positions.native_track_id == "track0", :);
track1 = result.positions(result.positions.native_track_id == "track1", :);
verifyTrue(testCase, all(ismember(track0.basis, ["observed", "interpolated"])));
verifyEqual(testCase, track1.basis(end), "not_covered");
verifyEqual(testCase, track1.reason(end), "after_last_sample");
clear cleanup
end

function testExtrapolatedSamplesAreFlaggedOnTheirBrackets(testCase)
% The video anchors cover a finite range; detection 1's samples lie inside it,
% so no bracket is flagged. The flag column exists and is honest either way.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 1);
verifyFalse(testCase, any(result.positions.bracket_extrapolated));
clear cleanup
end

function testAMissingBodypartIsNotSubstituted(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
instants = vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=1), audioClock(fixture));
result = vawlume.tracking.positionsAtInstants(fixture.conn, streamRef(), ...
    instants.instants.time_reference_s, ReferenceTimebaseKey="neural_native", ...
    AlignmentRunId=fixture.video_run, Bodypart="left_ear", MaxGapS=0.05, ...
    SourceRoot=fixture.workspace, RepoRoot=fixture.repo_root);
verifyEqual(testCase, result.status, "bodypart_missing");
verifyEqual(testCase, height(result.positions), 0);
clear cleanup
end

function testTheTrackingClockIsDeclaredNotDiscovered(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
call = @(varargin) vawlume.tracking.positionsAtInstants(fixture.conn, streamRef(), ...
    1000, "ReferenceTimebaseKey", "neural_native", "Bodypart", "snout", ...
    "MaxGapS", 0.05, "SourceRoot", fixture.workspace, "RepoRoot", ...
    fixture.repo_root, varargin{:});
verifyError(testCase, @() call(), "vawlume:tracking:ClockDeclarationInvalid");
verifyError(testCase, @() call(AlignmentRunId=fixture.audio_run), ...
    "vawlume:tracking:ClockDeclarationInvalid");
verifyError(testCase, @() call(AlignmentRunId=fixture.video_run, SameClock=true), ...
    "vawlume:tracking:ClockDeclarationInvalid");
verifyError(testCase, @() vawlume.tracking.positionsAtInstants(fixture.conn, ...
    streamRef(), 1000, ReferenceTimebaseKey="neural_native", Bodypart="snout", ...
    AlignmentRunId=fixture.video_run), "vawlume:geometry:MaxGapRequired");
verifyError(testCase, @() vawlume.tracking.positionsAtInstants(fixture.conn, ...
    streamRef(), 1000, ReferenceTimebaseKey="neural_native", MaxGapS=0.05, ...
    AlignmentRunId=fixture.video_run), "vawlume:tracking:BodypartRequired");
clear cleanup
end

function testNoEntityAppearsAnywhereInTheResult(testCase)
% A track is named exactly like an entity's native id ("track0" is also an
% experimental entity here). Nothing resolves it.
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
[~, result] = positionsForDetection(fixture, 1);
% Matched as a whole underscore-delimited word: "identity" contains the letters
% "entity", and result.identity_boundary is the field that states this boundary.
% (The first version of this probe used contains() and failed on exactly that.)
isEntityName = @(names) ~cellfun(@isempty, regexp(lower(cellstr(names)), ...
    "(^|_)entit(y|ies)(_|$)", "once"));
fields = string(fieldnames(result));
verifyFalse(testCase, any(isEntityName(fields)));
verifyTrue(testCase, any(fields == "identity_boundary"));
names = [string(result.positions.Properties.VariableNames), ...
    string(result.window_samples.Properties.VariableNames)];
verifyFalse(testCase, any(isEntityName(names)));
% The probe itself can fire.
verifyTrue(testCase, all(isEntityName(["entity_id", "candidate_entity", "entities"])));
clear cleanup
end

function testNothingIsWrittenToTheDatabase(testCase)
[fixture, cleanup] = setUpSession(); %#ok<ASGLU>
before = tableCounts(fixture.conn);
positionsForDetection(fixture, 1);
verifyEqual(testCase, tableCounts(fixture.conn), before);
clear cleanup
end

% ================================================================ helpers ===

function [instants, result] = positionsForDetection(fixture, detectionId)
instants = vawlume.estimator.eventReferenceInstants(fixture.conn, ...
    struct(detection_id=detectionId), audioClock(fixture));
result = vawlume.tracking.positionsAtInstants(fixture.conn, streamRef(), ...
    instants.instants.time_reference_s, ReferenceTimebaseKey="neural_native", ...
    AlignmentRunId=fixture.video_run, Bodypart="snout", MaxGapS=0.05, ...
    InstantLabels=instants.instants.instant_basis, ...
    CallWindow=instants.reference_interval, ...
    SourceRoot=fixture.workspace, RepoRoot=fixture.repo_root);
end

function value = audioClock(fixture)
value = struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
    audio_alignment_run_id=fixture.audio_run);
end

function value = streamRef()
value = struct(project_key="synthetic_alignment_session", stream_name="arena_tracking");
end

function [x, y] = truePosition(track, videoTime)
% Snout trajectories, linear in video time, so linear interpolation is exact.
if track == "track0"
    x = 10 + 0.01 * videoTime;
    y = 20 + 0 * videoTime;
else
    x = 50 + 0 * videoTime;
    y = 20 + 0.005 * videoTime;
end
end

function counts = tableCounts(conn)
names = ["detections", "derived_measurements", "attribution_evidence", ...
    "tracking_series", "external_stream_coverage", "alignment_segments", ...
    "tracking_identity_associations"];
counts = zeros(1, numel(names));
for k = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(k));
    counts(k) = double(rows.n(1));
end
end

function [fixture, cleanup] = setUpSession(options)
%SETUPSESSION The shared alignment session, plus this suite's detections.
%
% The clocks, the tracking stream and its linear trajectories come from
% vawlume.db.buildAlignmentSessionFixture (itinerary 7.3a); what is added here is
% this suite's own scene.
arguments
    options.WithConfidence (1,1) logical = true
end
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
[fixture, session] = vawlume.db.buildAlignmentSessionFixture(RepoRoot=repoRoot, ...
    WorkspacePrefix="vawlume_event_window_", WithConfidence=options.WithConfidence, ...
    TrackStop=struct(track="track1", region=3, after_audio_s=1100.12));
cleanup = onCleanup(@() tearDown(session, fullfile(repoRoot, "src")));
conn = fixture.conn;

% Detections on the audio clock. 1: ordinary; 2: straddles the 900 s breakpoint;
% 3: between the two tracked regions (covered but empty); 4: beyond the anchors
% and the tracking artifact (extrapolated, uncovered); 5: where track1 stops.
execute(conn, "INSERT INTO extractors(extractor_key, extractor_name) VALUES ('ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_id, version_label) VALUES (1,'v')");
execute(conn, "INSERT INTO extraction_runs(project_id, extractor_version_id, run_key) " + ...
    "VALUES (1, 1, 'calls')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id, recording_id) VALUES (1, 1)");
execute(conn, "INSERT INTO detections(detection_id, extraction_run_id, recording_id, " + ...
    "start_time_s, end_time_s) VALUES (1,1,1,300.0,300.1),(2,1,1,899.9,900.1)," + ...
    "(3,1,1,600.0,600.1),(4,1,1,2000.0,2000.1),(5,1,1,1100.0,1100.2)");

% An entity whose native id equals a track label, to prove nothing resolves it.
execute(conn, "INSERT INTO entity_types(project_id, native_name) VALUES (1, 'subject')");
execute(conn, "INSERT INTO experimental_entities(project_id, entity_type_id, native_id) " + ...
    "VALUES (1, 1, 'track0')");
end

function tearDown(session, sourcePath)
delete(session);   % closes the connection and removes the workspace
rmpath(sourcePath);
end