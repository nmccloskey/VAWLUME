function tests = test_geometry_schema
%TEST_GEOMETRY_SCHEMA Spatial coordinate systems and channel placement DDL.
%
% The claims this suite holds, all at the SQL level so they survive any change
% to the MATLAB API above them:
%
%   a coordinate system declares a dimensionality of exactly 2 or 3;
%   a placement locates one recording channel and only one;
%   a z coordinate is rejected under a 2-dimensional frame, on insert and update;
%   a placement cannot cite a frame declared for another project;
%   a frame cannot be deleted while a placement still cites it.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------------ schema shape ---

function testSchemaVersionAndSpatialObjectsExist(testCase)
[fixture, cleanup] = setUpSchema(); %#ok<ASGLU>
conn = fixture.conn;

verifyEqual(testCase, textOf(conn, "SELECT schema_version FROM schema_info"), ...
    "0.7-draft");
verifyEqual(testCase, numberOf(conn, "PRAGMA user_version"), 7);
verifyEqual(testCase, numberOf(conn, "PRAGMA foreign_keys"), 1);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

verifyTrue(testCase, objectExists(conn, "table", "coordinate_systems"));
verifyTrue(testCase, objectExists(conn, "table", "channel_placements"));
for name = ["trg_channel_placement_dimensionality", ...
        "trg_channel_placement_dimensionality_update", ...
        "trg_channel_placement_project_scope"]
    verifyTrue(testCase, objectExists(conn, "trigger", name), name);
end
verifyTrue(testCase, objectExists(conn, "index", "idx_channel_placements_system"));

verifyEqual(testCase, columnsOf(conn, "coordinate_systems"), [ ...
    "coordinate_system_id"; "project_id"; "coordinate_system_key"; ...
    "coordinate_system_name"; "dimensionality"; "unit"; "origin_description"; ...
    "orientation_description"; "notes"]);
verifyEqual(testCase, columnsOf(conn, "channel_placements"), [ ...
    "channel_placement_id"; "recording_channel_id"; "coordinate_system_id"; ...
    "position_x"; "position_y"; "position_z"; "placement_role"; ...
    "orientation_description"; "source_profile_version_id"; "notes"]);

clear cleanup
end

function testDimensionalityVocabularyIsTwoOrThree(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% 2D is the working case and 3D is representable. Anything else is a typo or a
% concept this layer does not have, and either way it is refused rather than
% stored.
for bad = [0 1 4 -2]
    verifySqlFails(testCase, conn, systemInsert(1, "bad_" + string(bad), bad, "cm"));
end
execute(conn, systemInsert(1, "flat", 2, "cm"));
execute(conn, systemInsert(1, "volume", 3, "cm"));
% Two more beside the arena_2d and arena_3d frames setUpWorld declares.
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM coordinate_systems WHERE project_id=1"), 4);

% Keys are unique within a project and free across projects.
verifySqlFails(testCase, conn, systemInsert(1, "flat", 2, "cm"));
execute(conn, systemInsert(2, "flat", 2, "cm"));

clear cleanup
end

% -------------------------------------------------------- placement scoping ---

function testPlacementLocatesExactlyOneChannel(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

execute(conn, placementInsert(fixture.channel_a, fixture.system_2d, 10, 20));
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM channel_placements"), 1);

% One placement per channel. A microphone moved mid-recording is deliberately
% unrepresentable: it needs an explicit time-bounded model, not a second row.
verifySqlFails(testCase, conn, ...
    placementInsert(fixture.channel_a, fixture.system_2d, 11, 21));

% A second channel of the same recording is a different microphone.
execute(conn, placementInsert(fixture.channel_b, fixture.system_2d, 30, 20));
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM channel_placements"), 2);

clear cleanup
end

function testZCoordinateRequiresAThreeDimensionalFrame(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% The frame decides whether height is a meaningful quantity here.
verifySqlFails(testCase, conn, ...
    placementInsert(fixture.channel_a, fixture.system_2d, 10, 20, 5));

% Under a 3D frame it is accepted, and remains optional: an unknown height is
% missing data, not a modelling error.
execute(conn, placementInsert(fixture.channel_a, fixture.system_3d, 10, 20, 5));
execute(conn, placementInsert(fixture.channel_b, fixture.system_3d, 30, 20));
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n " + ...
    "FROM channel_placements WHERE position_z IS NULL"), 1);

clear cleanup
end

function testUpdateCannotReachTheStateInsertRefuses(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% Without an update guard, a row could be inserted legally and then given a z,
% or have its frame repointed at a 2D system, arriving at exactly the state the
% insert guard exists to prevent.
execute(conn, placementInsert(fixture.channel_a, fixture.system_2d, 10, 20));
verifySqlFails(testCase, conn, "UPDATE channel_placements SET position_z = 5 " + ...
    "WHERE recording_channel_id = " + string(fixture.channel_a));

execute(conn, placementInsert(fixture.channel_b, fixture.system_3d, 30, 20, 5));
verifySqlFails(testCase, conn, "UPDATE channel_placements SET coordinate_system_id = " + ...
    string(fixture.system_2d) + " WHERE recording_channel_id = " + ...
    string(fixture.channel_b));

clear cleanup
end

function testPlacementCannotCiteAnotherProjectsFrame(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% The channel reaches its project through its recording. Without this guard a
% placement could cite a frame declared for an unrelated project, and the two
% would look compatible to any query that only compares identifiers.
verifySqlFails(testCase, conn, ...
    placementInsert(fixture.channel_a, fixture.other_project_system, 10, 20));

clear cleanup
end

function testFrameCannotBeDeletedWhileAPlacementCitesIt(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

execute(conn, placementInsert(fixture.channel_a, fixture.system_2d, 10, 20));

% RESTRICT, not CASCADE: a placement whose frame vanished would carry
% coordinates in no declared space, which is worse than refusing the delete.
verifySqlFails(testCase, conn, "DELETE FROM coordinate_systems " + ...
    "WHERE coordinate_system_id = " + string(fixture.system_2d));

% Deleting the recording removes its channels and their placements, and frees
% the frame again.
execute(conn, "DELETE FROM recordings WHERE recording_id = 1");
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM channel_placements"), 0);
execute(conn, "DELETE FROM coordinate_systems WHERE coordinate_system_id = " + ...
    string(fixture.system_2d));
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function sql = systemInsert(projectId, key, dimensionality, unit)
sql = "INSERT INTO coordinate_systems(project_id,coordinate_system_key," + ...
    "coordinate_system_name,dimensionality,unit) VALUES(" + ...
    string(projectId) + "," + sqlText(key) + "," + sqlText(key) + "," + ...
    string(dimensionality) + "," + sqlText(unit) + ")";
end

function sql = placementInsert(channelId, systemId, x, y, z)
columns = "recording_channel_id,coordinate_system_id,position_x,position_y";
values = string(channelId) + "," + string(systemId) + "," + string(x) + "," + ...
    string(y);
if nargin >= 5
    columns = columns + ",position_z";
    values = values + "," + string(z);
end
sql = "INSERT INTO channel_placements(" + columns + ") VALUES(" + values + ")";
end

function [fixture, cleanup] = setUpWorld()
%SETUPWORLD Two projects, one two-channel recording, three declared frames.
[fixture, cleanup] = setUpSchema();
conn = fixture.conn;

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('geometry_project','Geometry project'),('other_project','Other')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri," + ...
    "relative_path,filename) VALUES(1,'recording_audio','a.wav','a.wav','a.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id,channel_count) " + ...
    "VALUES(1,1,2)");
execute(conn, "INSERT INTO recording_channels(recording_id,channel_index," + ...
    "channel_label) VALUES(1,1,'left'),(1,2,'right')");
fixture.channel_a = 1;
fixture.channel_b = 2;

execute(conn, systemInsert(1, "arena_2d", 2, "cm"));
fixture.system_2d = lastId(conn);
execute(conn, systemInsert(1, "arena_3d", 3, "cm"));
fixture.system_3d = lastId(conn);
execute(conn, systemInsert(2, "arena_2d", 2, "cm"));
fixture.other_project_system = lastId(conn);
end

function [fixture, cleanup] = setUpSchema()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, dbFile, repoRoot));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
fixture = struct(conn=conn, repo_root=repoRoot, db_file=dbFile);
end

function id = lastId(conn)
id = numberOf(conn, "SELECT last_insert_rowid() AS n");
end

function value = numberOf(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function value = textOf(conn, sql)
rows = fetch(conn, sql);
column = rows.(rows.Properties.VariableNames{1});
if iscell(column)
    value = string(column{1});
else
    value = string(column(1));
end
end

function value = objectExists(conn, objectType, name)
value = numberOf(conn, "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = " + ...
    sqlText(objectType) + " AND name = " + sqlText(name)) == 1;
end

function value = columnsOf(conn, tableName)
rows = fetch(conn, "SELECT name FROM pragma_table_info(" + sqlText(tableName) + ")");
value = string(rows.name);
value = value(:);
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

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
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
