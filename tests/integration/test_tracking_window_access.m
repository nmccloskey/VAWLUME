function tests = test_tracking_window_access
%TEST_TRACKING_WINDOW_ACCESS Bounded, coverage-aware reads of external tracking.
%
% The claims this suite holds:
%
%   dense samples are read from the artifact, never from SQLite;
%   coverage has three states and absence never means "nothing happened";
%   native_track_id is a trajectory label and never becomes an animal identity;
%   pose confidence is localization quality, separate from everything else;
%   coordinate mismatch is explicit and nothing is transformed;
%   alignment uncertainty stays separate from pose confidence.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------------ the happy path ---

function testCompleteWindowReturnsCanonicalizedSamples(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>

result = vawlume.tracking.readWindow(fixture.conn, streamRef(), [1 3], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);

verifyEqual(testCase, result.coverage_status, "covered");
verifyEqual(testCase, result.sample_status, "populated");

% Four traces over three timestamps.
verifyEqual(testCase, height(result.samples), 12);
verifyEqual(testCase, unique(result.samples.time_native_s)', [1 2 3]);
verifyEqual(testCase, sort(unique(result.samples.native_track_id))', ...
    ["mouse_a", "mouse_b"]);
verifyEqual(testCase, sort(unique(result.samples.native_bodypart_label))', ...
    ["snout", "tail_base"]);

% The frame the coordinates are stated in is explicit, not assumed.
verifyEqual(testCase, result.coordinate_system.coordinate_system_key, "arena_2d");
verifyEqual(testCase, result.coordinate_system.unit, "cm");
verifyEqual(testCase, result.timebase.timebase_name, "video_native");

% Pose confidence is present and is its own quantity.
verifyTrue(testCase, result.has_pose_confidence);
verifyTrue(testCase, all(isfinite(result.samples.pose_confidence)));

% The artifact was verified against the checksum registration recorded.
verifyEqual(testCase, result.artifact.checksum_status, "verified");

% And nothing was written.
verifyEqual(testCase, result.dense_samples_stored, 0);
verifyEqual(testCase, numberOf(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM tracking_series"), 4);

clear cleanup
end

function testWindowIsBoundedAndFilterable(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>

narrow = vawlume.tracking.readWindow(fixture.conn, streamRef(), [2 2], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
verifyEqual(testCase, height(narrow.samples), 4);

oneTrack = vawlume.tracking.readWindow(fixture.conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root, ...
    NativeTrackIds="mouse_b");
verifyEqual(testCase, unique(oneTrack.samples.native_track_id), "mouse_b");
verifyEqual(testCase, height(oneTrack.samples), 12);

onePart = vawlume.tracking.readWindow(fixture.conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root, ...
    BodypartLabels="snout");
verifyEqual(testCase, unique(onePart.samples.native_bodypart_label), "snout");

clear cleanup
end

% --------------------------------------------------------- coverage semantics ---

function testCoverageHasThreeStatesAndAbsenceIsNotEmptiness(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>
conn = fixture.conn;

% The fixture's artifact spans 0-5 s, so declared coverage does too.
covered = vawlume.tracking.readWindow(conn, streamRef(), [1 4], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
verifyEqual(testCase, covered.coverage_status, "covered");

% A window running past the end of coverage is partial, and says which part was
% actually observed rather than silently returning only what it found.
partial = vawlume.tracking.readWindow(conn, streamRef(), [4 9], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
verifyEqual(testCase, partial.coverage_status, "partial");
verifyEqual(testCase, partial.covered_interval, [4 5]);
verifyEqual(testCase, partial.sample_status, "populated");

% A window entirely outside coverage is uncovered. Zero samples here means
% nothing established that anyone was observing - NOT that the tracker saw
% nothing - and the reader does not even open the artifact.
uncovered = vawlume.tracking.readWindow(conn, streamRef(), [20 30], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
verifyEqual(testCase, uncovered.coverage_status, "uncovered");
verifyEqual(testCase, uncovered.sample_status, "uncovered");
verifyEqual(testCase, height(uncovered.samples), 0);

% Covered but empty is the third state and is a QC finding, not an absence of
% observation. Widening declared coverage past the artifact's samples produces
% it without touching the artifact.
execute(conn, "UPDATE external_stream_coverage SET end_time_native = 40");
emptyWindow = vawlume.tracking.readWindow(conn, streamRef(), [20 30], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);
verifyEqual(testCase, emptyWindow.coverage_status, "covered");
verifyEqual(testCase, emptyWindow.sample_status, "empty");
verifyEqual(testCase, height(emptyWindow.samples), 0);

clear cleanup
end

% ---------------------------------------------------------- identity boundary ---

function testAnimalLikeTrackLabelsNeverBecomeEntityIdentity(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>

% The fixture deliberately uses animal-like track labels, and 'mouse_a' is also
% an established experimental entity in this project. A tracker naming a
% trajectory after an animal is still only naming a trajectory.
verifyEqual(testCase, numberOf(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM experimental_entities WHERE native_id='mouse_a'"), 1);

result = vawlume.tracking.readWindow(fixture.conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);

% The samples carry the trajectory label...
verifyTrue(testCase, ismember("native_track_id", ...
    string(result.samples.Properties.VariableNames)));

% ...and no canonical entity of any spelling.
names = lower(string(result.samples.Properties.VariableNames));
verifyFalse(testCase, any(contains(names, "entity")));
verifyFalse(testCase, any(contains(names, "subject")));
verifyFalse(testCase, any(contains(names, "animal")));

% The result says so in as many words, so a caller reading it cannot mistake
% the label for an identity.
verifyTrue(testCase, contains(result.identity_boundary, "not a canonical"));

clear cleanup
end

function testPoseConfidenceAbsenceIsReportedNotImputed(testCase)
[fixture, cleanup] = setUpRegistered(WithConfidence=false); %#ok<ASGLU>

result = vawlume.tracking.readWindow(fixture.conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root);

% A tracker that emits no confidence produces missing confidence, never 1.0.
verifyFalse(testCase, result.has_pose_confidence);
verifyTrue(testCase, all(isnan(result.samples.pose_confidence)));
verifyGreaterThan(testCase, height(result.samples), 0);

clear cleanup
end

% ------------------------------------------------------ coordinate compatibility ---

function testGeometryCompatibilityIsCheckedAndNeverRepaired(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>
conn = fixture.conn;

execute(conn, "INSERT INTO recording_channels(recording_id,channel_index," + ...
    "channel_label) VALUES(1,1,'left'),(1,2,'right')");
execute(conn, "INSERT INTO channel_placements(recording_channel_id," + ...
    "coordinate_system_id,position_x,position_y) VALUES(1,1,0,18.5),(2,1,37,18.5)");

ok = vawlume.tracking.assertGeometryCompatible(conn, streamRef(), ...
    struct(recording_id=1));
verifyTrue(testCase, ok.compatible);
verifyFalse(testCase, ok.transformed);
verifyEqual(testCase, ok.coordinate_system.coordinate_system_key, "arena_2d");
verifyEqual(testCase, ok.placed_channel_indices, [1 2]);

% A second frame with identical unit and dimensionality is still a different
% frame: it may have a different origin or describe a different arena.
execute(conn, "INSERT INTO coordinate_systems(project_id,coordinate_system_key," + ...
    "coordinate_system_name,dimensionality,unit) " + ...
    "VALUES(1,'other_2d','Other arena',2,'cm')");
execute(conn, "UPDATE channel_placements SET coordinate_system_id = " + ...
    "(SELECT coordinate_system_id FROM coordinate_systems " + ...
    "WHERE coordinate_system_key='other_2d') WHERE recording_channel_id=2");

verifyError(testCase, @() vawlume.tracking.assertGeometryCompatible(conn, ...
    streamRef(), struct(recording_id=1)), ...
    "vawlume:geometry:CoordinateSystemMismatch");

clear cleanup
end

function testGeometryWithNoPlacedChannelsIsNotCompatibility(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>

% An empty set of frames is absence of evidence that any comparison is legal,
% not a compatible one.
verifyError(testCase, @() vawlume.tracking.assertGeometryCompatible( ...
    fixture.conn, streamRef(), struct(recording_id=1)), ...
    "vawlume:tracking:GeometryUnavailable");

clear cleanup
end

% ----------------------------------------------------------- timebase boundary ---

function testCommonTimeIsAppliedOnlyFromAStoredTransform(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>
conn = fixture.conn;

% No transform exists yet, so the reader says so and leaves native times alone
% rather than estimating one.
missing = vawlume.tracking.readWindow(conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root, ...
    ReferenceTimebaseKey="neural_native");
verifyEqual(testCase, missing.reference_time_status, "no_transform");
verifyTrue(testCase, all(isnan(missing.samples.time_reference_s)));
verifyTrue(testCase, all(isfinite(missing.samples.time_native_s)));

% With a solved transform stored by the alignment layer, the reader applies it.
writeSolvedTransform(conn);
applied = vawlume.tracking.readWindow(conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root, ...
    ReferenceTimebaseKey="neural_native");
verifyEqual(testCase, applied.reference_time_status, "applied");
verifyEqual(testCase, applied.samples.time_reference_s, ...
    applied.samples.time_native_s + 10, AbsTol=1e-12);

% Fit diagnostics come back beside the samples, NOT folded into pose
% confidence: how well two clocks agree and how well a keypoint was localized
% are different quantities.
verifyEqual(testCase, applied.transform.method, "offset");
verifyEqual(testCase, applied.transform.rmse_s, 0.001, AbsTol=1e-12);
verifyEqual(testCase, applied.transform.max_abs_residual_s, 0.002, AbsTol=1e-12);
verifyEqual(testCase, applied.transform.status, "estimated");
verifyTrue(testCase, applied.has_pose_confidence);
verifyTrue(testCase, all(isfinite(applied.samples.pose_confidence)));

% The two uncertainties are numerically independent here: the fit's RMSE is
% 0.001 s and every pose confidence is 0.97. Neither influences the other, and
% no combined "tracking confidence" is produced anywhere in the result.
verifyEqual(testCase, unique(applied.samples.pose_confidence), 0.97);
verifyFalse(testCase, any(contains(lower(string(fieldnames(applied))), ...
    "combined_confidence")));

clear cleanup
end

function testUnusableTransformIsReportedNotSilentlyDegraded(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>
conn = fixture.conn;

writeSolvedTransform(conn);
execute(conn, "UPDATE time_alignment_runs SET method='piecewise_affine'");
execute(conn, "DELETE FROM alignment_segments");

degraded = vawlume.tracking.readWindow(conn, streamRef(), [0 5], ...
    SourceRoot=fixture.scratch, RepoRoot=fixture.repo_root, ...
    ReferenceTimebaseKey="neural_native");
verifyEqual(testCase, degraded.reference_time_status, "unusable_transform");
verifyGreaterThan(testCase, strlength(degraded.reference_time_message), 0);
verifyTrue(testCase, all(isnan(degraded.samples.time_reference_s)));

clear cleanup
end

% ------------------------------------------------------------------ refusals ---

function testUnregisteredStreamAndBadWindowAreRefused(testCase)
[fixture, cleanup] = setUpRegistered(); %#ok<ASGLU>

verifyError(testCase, @() vawlume.tracking.readWindow(fixture.conn, ...
    struct(external_stream_id=999), [0 1]), "vawlume:tracking:StreamNotFound");
verifyError(testCase, @() vawlume.tracking.readWindow(fixture.conn, ...
    streamRef(), [5 1]), "vawlume:tracking:WindowInvalid");
verifyError(testCase, @() vawlume.tracking.readWindow(fixture.conn, ...
    streamRef(), [0 1], Basis="frame"), "vawlume:tracking:BasisUnsupported");

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function ref = streamRef()
ref = struct(project_key="tracking_project", stream_name="tracking_primary");
end

function writeSolvedTransform(conn)
%WRITESOLVEDTRANSFORM One stored offset transform, video_native -> neural_native.
%
% Written directly rather than fitted, because this suite is about the tracking
% reader's use of a stored transform, not about fitting. Status 'estimated' is
% the alignment layer's vocabulary for a solved but uncalibrated fit.
execute(conn, "INSERT INTO timebases(project_id,recording_id,timebase_name," + ...
    "timebase_kind) VALUES(1,1,'neural_native','neural_acquisition_clock')");
execute(conn, "INSERT INTO analysis_runs(project_id,run_type,run_key,status) " + ...
    "VALUES(1,'temporal_alignment','align-1','completed')");
execute(conn, "INSERT INTO alignment_sets(analysis_run_id," + ...
    "recording_id,reference_timebase_id,alignment_set_key,status) " + ...
    "VALUES(1,1,(SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='neural_native'),'set-1','fitted')");
execute(conn, "INSERT INTO time_alignment_runs(alignment_set_id," + ...
    "source_timebase_id,target_timebase_id,method,status,n_anchors_used," + ...
    "fit_rmse_s,max_error_s) VALUES(1," + ...
    "(SELECT timebase_id FROM timebases WHERE timebase_name='video_native')," + ...
    "(SELECT timebase_id FROM timebases WHERE timebase_name='neural_native')," + ...
    "'offset','estimated',2,0.001,0.002)");
execute(conn, "INSERT INTO alignment_segments(alignment_run_id,segment_index," + ...
    "source_start,source_end,scale,offset_s) VALUES(1,1,0,100,1.0,10.0)");
end

function writeTrackingCsv(path, options)
arguments
    path (1,1) string
    options.WithConfidence (1,1) logical = true
end
header = "time_s,subject,bodypart,x,y";
if options.WithConfidence
    header = header + ",likelihood";
end
lines = header;
row = 0;
for subject = ["mouse_a", "mouse_b"]
    for part = ["snout", "tail_base"]
        for t = 0:5
            row = row + 1;
            line = string(t) + "," + subject + "," + part + "," + ...
                string(row * 0.5) + "," + string(row * 0.25);
            if options.WithConfidence
                line = line + ",0.97";
            end
            lines(end + 1, 1) = line; %#ok<AGROW>
        end
    end
end
writelines(lines, path);
end

function writeProfile(path, withConfidence)
%WRITEPROFILE The shipped generic profile, optionally without a confidence role.
repoRoot = repoRootPath();
source = fullfile(repoRoot, "config", "01_mapping_profiles", "tracking", ...
    "generic_tracking_mapping_profile.json");
document = jsondecode(fileread(source));
if ~withConfidence
    document.profiles.columns = rmfield(document.profiles.columns, "confidence");
end
writelines(string(jsonencode(document, PrettyPrint=true)), path);
end

function [fixture, cleanup] = setUpRegistered(options)
arguments
    options.WithConfidence (1,1) logical = true
end
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbFile = fullfile(scratch, "tracking_window.sqlite");
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
    "native_id) VALUES(1,1,'mouse_a')");

artifactPath = fullfile(scratch, "session_01_tracking.csv");
writeTrackingCsv(artifactPath, WithConfidence=options.WithConfidence);
profilePath = fullfile(scratch, "tracking_profile.json");
writeProfile(profilePath, options.WithConfidence);

vawlume.tracking.register(conn, struct(recording_id=1), struct( ...
    artifact_path="session_01_tracking.csv", ...
    profile_path=profilePath, timebase_key="video_native"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=scratch);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    artifact_path=artifactPath);
end

function value = numberOf(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
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
