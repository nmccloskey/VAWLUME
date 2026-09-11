function tests = test_geometry_registration
%TEST_GEOMETRY_REGISTRATION The public coordinate-system and placement API.
%
% The workflow this suite exercises is the one Phase 2 actually needs: declare a
% 2D arena frame, locate two microphones in it, and read them back with their
% unit and dimensionality attached.
%
% It also holds the refusals, because the value of this layer is mostly in what
% it declines to do:
%
%   a placement never invents a coordinate system or a recording channel;
%   a frame is never silently redefined once placements cite it;
%   z is refused under a 2D frame with a VAWLUME diagnostic, not a SQLite one;
%   two different frames are never treated as compatible, whatever their unit
%   and dimensionality say.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------ the ordinary workflow ---

function testTwoMicrophonesAreLocatedInOneDeclaredFrame(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

system = vawlume.geometry.registerCoordinateSystem(conn, projectRef(), ...
    struct(coordinate_system_key="arena_2d", ...
        coordinate_system_name="Courtship arena floor plane", ...
        dimensionality=2, unit="cm", ...
        origin_description="front-left inner corner of the arena floor", ...
        orientation_description="x rightward, y away from the operator"));
verifyEqual(testCase, system.action, "created");

left = vawlume.geometry.registerChannelPlacement(conn, recordingRef(), ...
    struct(channel_index=1, coordinate_system_key="arena_2d", ...
        position_x=0, position_y=18.5, placement_role="microphone"));
right = vawlume.geometry.registerChannelPlacement(conn, recordingRef(), ...
    struct(channel_index=2, coordinate_system_key="arena_2d", ...
        position_x=37, position_y=18.5, placement_role="microphone"));

verifyEqual(testCase, left.action, "created");
verifyEqual(testCase, right.action, "created");
verifyEqual(testCase, left.unit, "cm");
verifyEqual(testCase, left.dimensionality, 2);

placements = vawlume.geometry.readChannelPlacements(conn, recordingRef());
verifyEqual(testCase, height(placements), 2);
verifyEqual(testCase, placements.channel_index', [1 2]);
verifyEqual(testCase, placements.position_x', [0 37]);
verifyEqual(testCase, placements.position_y', [18.5 18.5]);
verifyTrue(testCase, all(ismissing(string(placements.coordinate_system_key)) == false));
verifyEqual(testCase, unique(string(placements.coordinate_system_key)), "arena_2d");

% A 2D frame yields no height at all, rather than a zero that reads like one.
verifyTrue(testCase, all(isnan(placements.position_z)));

systems = vawlume.geometry.readCoordinateSystems(conn, projectRef());
verifyEqual(testCase, height(systems), 1);
verifyEqual(testCase, systems.unit, "cm");
verifyEqual(testCase, systems.dimensionality, 2);
verifyEqual(testCase, systems.origin_description, ...
    "front-left inner corner of the arena floor");

verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testRegistrationIsIdempotentAndNeverRewrites(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;
declareArena(conn);

repeated = vawlume.geometry.registerCoordinateSystem(conn, projectRef(), ...
    arenaSpec());
verifyEqual(testCase, repeated.action, "reused");

placed = vawlume.geometry.registerChannelPlacement(conn, recordingRef(), ...
    leftSpec());
verifyEqual(testCase, placed.action, "created");
again = vawlume.geometry.registerChannelPlacement(conn, recordingRef(), ...
    leftSpec());
verifyEqual(testCase, again.action, "reused");
verifyEqual(testCase, again.channel_placement_id, placed.channel_placement_id);

% A frame is never redefined in place: placements already cite it and were
% validated against its stored dimensionality.
changed = arenaSpec();
changed.unit = "mm";
verifyError(testCase, ...
    @() vawlume.geometry.registerCoordinateSystem(conn, projectRef(), changed), ...
    "vawlume:geometry:CoordinateSystemConflict");

moved = leftSpec();
moved.position_x = 4;
verifyError(testCase, ...
    @() vawlume.geometry.registerChannelPlacement(conn, recordingRef(), moved), ...
    "vawlume:geometry:PlacementConflict");

verifyEqual(testCase, height(vawlume.geometry.readChannelPlacements( ...
    conn, recordingRef())), 1);

clear cleanup
end

% ----------------------------------------------------------------- refusals ---

function testPlacementNeverInventsItsReferences(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% No frame declared yet. Creating one implicitly would mean a placement chose
% its own units and dimensionality.
verifyError(testCase, ...
    @() vawlume.geometry.registerChannelPlacement(conn, recordingRef(), leftSpec()), ...
    "vawlume:geometry:CoordinateSystemNotFound");

declareArena(conn);

% Channel 3 does not exist. Placement locates an established channel; a channel
% invented here would assert geometry for audio that was never recorded.
absent = leftSpec();
absent.channel_index = 3;
verifyError(testCase, ...
    @() vawlume.geometry.registerChannelPlacement(conn, recordingRef(), absent), ...
    "vawlume:geometry:RecordingChannelNotFound");

clear cleanup
end

function testHeightIsRefusedUnderATwoDimensionalFrame(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;
declareArena(conn);

withHeight = leftSpec();
withHeight.position_z = 12;

% The API names the problem in VAWLUME's vocabulary. The schema trigger enforces
% the same rule independently, so a caller bypassing this function still cannot
% reach the state.
verifyError(testCase, ...
    @() vawlume.geometry.registerChannelPlacement(conn, recordingRef(), withHeight), ...
    "vawlume:geometry:DimensionalityMismatch");

% Under a 3D frame the same height is accepted, and stays optional.
vawlume.geometry.registerCoordinateSystem(conn, projectRef(), ...
    struct(coordinate_system_key="arena_3d", ...
        coordinate_system_name="Courtship arena volume", ...
        dimensionality=3, unit="cm"));
raised = withHeight;
raised.coordinate_system_key = "arena_3d";
result = vawlume.geometry.registerChannelPlacement(conn, recordingRef(), raised);
verifyEqual(testCase, result.dimensionality, 3);

flat = leftSpec();
flat.channel_index = 2;
flat.coordinate_system_key = "arena_3d";
vawlume.geometry.registerChannelPlacement(conn, recordingRef(), flat);

placements = vawlume.geometry.readChannelPlacements(conn, recordingRef());
verifyEqual(testCase, placements.position_z', [12 NaN]);

clear cleanup
end

function testSelectorsRequireExactlyOneAddressingMode(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

verifyError(testCase, @() vawlume.geometry.readCoordinateSystems(conn, ...
    struct(project_id=1, project_key="geometry_project")), ...
    "vawlume:geometry:ProjectRefInvalid");
verifyError(testCase, @() vawlume.geometry.readCoordinateSystems(conn, ...
    struct(notes="neither")), "vawlume:geometry:ProjectRefInvalid");
verifyError(testCase, @() vawlume.geometry.readChannelPlacements(conn, ...
    struct(recording_id=1, project_key="geometry_project", ...
        source_relative_path="a.wav")), ...
    "vawlume:geometry:RecordingRefInvalid");

% The portable selector resolves to the same recording as the id selector.
declareArena(conn);
vawlume.geometry.registerChannelPlacement(conn, ...
    struct(project_key="geometry_project", source_relative_path="a.wav"), ...
    leftSpec());
verifyEqual(testCase, height(vawlume.geometry.readChannelPlacements( ...
    conn, struct(recording_id=1))), 1);

clear cleanup
end

% ------------------------------------------------------------ compatibility ---

function testCompatibilityIsFrameIdentityNotStructuralSimilarity(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

first = vawlume.geometry.registerCoordinateSystem(conn, projectRef(), arenaSpec());

% A second frame with the SAME dimensionality and unit. It may have a different
% origin, different axis directions, or describe a different arena entirely, so
% it is not interchangeable with the first however similar its metadata looks.
twin = arenaSpec();
twin.coordinate_system_key = "arena_2d_rig_b";
twin.coordinate_system_name = "Second rig arena floor plane";
second = vawlume.geometry.registerCoordinateSystem(conn, projectRef(), twin);

resolved = vawlume.geometry.assertCompatible(conn, ...
    [first.coordinate_system_id first.coordinate_system_id]);
verifyEqual(testCase, resolved.coordinate_system_key, "arena_2d");
verifyEqual(testCase, resolved.unit, "cm");

verifyError(testCase, @() vawlume.geometry.assertCompatible(conn, ...
    [first.coordinate_system_id second.coordinate_system_id]), ...
    "vawlume:geometry:CoordinateSystemMismatch");

% Absence of a declared frame is not compatibility.
verifyError(testCase, @() vawlume.geometry.assertCompatible(conn, []), ...
    "vawlume:geometry:CoordinateSystemMismatch");
verifyError(testCase, @() vawlume.geometry.assertCompatible(conn, 9999), ...
    "vawlume:geometry:CoordinateSystemNotFound");

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function ref = projectRef()
ref = struct(project_key="geometry_project");
end

function ref = recordingRef()
ref = struct(recording_id=1);
end

function spec = arenaSpec()
spec = struct(coordinate_system_key="arena_2d", ...
    coordinate_system_name="Courtship arena floor plane", ...
    dimensionality=2, unit="cm");
end

function spec = leftSpec()
spec = struct(channel_index=1, coordinate_system_key="arena_2d", ...
    position_x=0, position_y=18.5, placement_role="microphone");
end

function declareArena(conn)
vawlume.geometry.registerCoordinateSystem(conn, projectRef(), arenaSpec());
end

function [fixture, cleanup] = setUpWorld()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, dbFile, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('geometry_project','Geometry project')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri," + ...
    "relative_path,filename) VALUES(1,'recording_audio','a.wav','a.wav','a.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id,channel_count) " + ...
    "VALUES(1,1,2)");
execute(conn, "INSERT INTO recording_channels(recording_id,channel_index," + ...
    "channel_label) VALUES(1,1,'left'),(1,2,'right')");

fixture = struct(conn=conn, repo_root=repoRoot, db_file=dbFile);
end

function tearDown(conn, dbFile, repoRoot)
try
    close(conn);
catch
end
for suffix = ["", "-journal", "-wal", "-shm"]
    path = dbFile + suffix;
    if isfile(path)
        delete(path);
    end
end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
