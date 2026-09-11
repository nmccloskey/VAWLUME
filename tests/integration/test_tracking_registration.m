function tests = test_tracking_registration
%TEST_TRACKING_REGISTRATION Registering tracking as logical external data.
%
% The workflow: a synthetic long-form tracking export, a declared 2D frame, a
% declared video clock, and one registration that stores the stream, its traces,
% its coverage and its provenance.
%
% The claims this suite holds:
%
%   no tracking sample is ever written to SQLite;
%   a tracking stream reuses the external-stream ontology rather than a parallel one;
%   the frame and the clock must already exist - registration invents neither;
%   dry run shows the real plan without writing;
%   re-registering identical content reuses, and changed content conflicts.
tests = functiontests(localfunctions);
end

% ----------------------------------------------------------------- dry run ---

function testDryRunPlansWithoutWriting(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
before = trackingCounts(fixture.conn);

result = register(fixture, false);

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyTrue(testCase, result.valid_for_ingest);
verifyEqual(testCase, trackingCounts(fixture.conn), before);

% The plan reports what it would register, resolved against the real database.
verifyEqual(testCase, result.stream.action, "create");
verifyEqual(testCase, result.stream.native_time_basis, "time");
verifyEqual(testCase, result.stream.declared_sample_count, 24);
verifyTrue(testCase, result.stream.has_confidence);
verifyEqual(testCase, result.coordinate_system.coordinate_system_key, "arena_2d");
verifyEqual(testCase, result.timebase.timebase_name, "video_native");
verifyEqual(testCase, height(result.series), 4);
verifyEqual(testCase, strlength(result.artifact.checksum_sha256), 64);

% And it states its own policy where a caller will see it.
verifyEqual(testCase, result.dense_samples_stored, 0);

clear cleanup
end

% ---------------------------------------------------------------- the apply ---

function testApplyRegistersStreamTracesAndCoverageButNoSamples(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

result = register(fixture, true);
verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);

% The logical stream is an ordinary external stream carrying stream_kind
% 'tracking', not a parallel ontology.
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM external_streams " + ...
    "WHERE stream_kind='tracking'"), 1);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM tracking_streams"), 1);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM tracking_series"), 4);
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM external_stream_coverage"), 1);
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM external_stream_sources"), 1);

% Artifact and profile provenance both reached the database.
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM source_files " + ...
    "WHERE file_role='tracking_export'"), 1);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n FROM config_profiles " + ...
    "WHERE profile_kind='tracking_input_mapping'"), 1);
verifyEqual(testCase, numberOf(conn, "SELECT COUNT(*) AS n " + ...
    "FROM external_stream_sources WHERE mapping_profile_version_id IS NOT NULL"), 1);

% The subtype carries the tracking-specific facts, and the frame it cites.
stored = fetch(conn, "SELECT ts.native_time_basis, ts.has_confidence, " + ...
    "ts.declared_sample_count, cs.coordinate_system_key " + ...
    "FROM tracking_streams ts " + ...
    "JOIN coordinate_systems cs ON cs.coordinate_system_id=ts.coordinate_system_id");
verifyEqual(testCase, string(stored.native_time_basis(1)), "time");
verifyEqual(testCase, double(stored.has_confidence(1)), 1);
verifyEqual(testCase, double(stored.declared_sample_count(1)), 24);
verifyEqual(testCase, string(stored.coordinate_system_key(1)), "arena_2d");

% Native labels are preserved and the canonical role stayed additive.
series = fetch(conn, "SELECT native_entity_label, native_bodypart_label, " + ...
    "IFNULL(canonical_bodypart_role,'') AS canonical_bodypart_role, " + ...
    "IFNULL(entity_id,-1) AS entity_id FROM tracking_series " + ...
    "ORDER BY native_entity_label, native_bodypart_label");
verifyEqual(testCase, string(series.native_bodypart_label)', ...
    ["snout", "tail_base", "snout", "tail_base"]);
% presentText, not string(): the Database Toolbox returns an empty text column
% as <missing> even through IFNULL. 2.4 must normalize this column the same way
% when it reads series identity.
verifyEqual(testCase, presentText(series.canonical_bodypart_role)', ...
    ["snout", "", "snout", ""]);

% mouse_a is an established entity and links; mouse_b is not and stays unlinked
% rather than being invented.
linked = double(series.entity_id);
verifyEqual(testCase, nnz(linked > 0), 2);
verifyEqual(testCase, nnz(linked < 0), 2);

% THE claim of this itinerary: no table holds a tracking sample.
verifyEqual(testCase, height(fetch(conn, "SELECT name FROM sqlite_master " + ...
    "WHERE type='table' AND name LIKE '%tracking_sample%'")), 0);
% 11 rows: the stream, its subtype, four traces, one coverage segment, one
% stream source, the artifact's source_file, and the profile plus its version.
verifyEqual(testCase, totalRowCount(conn), fixture.baseline_rows + 11);

verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testRerunReusesAndChangedContentConflicts(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

register(fixture, true);
after = trackingCounts(conn);

repeated = register(fixture, true);
verifyEqual(testCase, repeated.status, "reused");
verifyEqual(testCase, trackingCounts(conn), after);

% A different artifact under the same stream name is a conflict, not an
% overwrite: coverage and later window reads already cite the stored stream.
writeTrackingCsv(fixture.artifact_path, 4);
changed = register(fixture, true);
verifyEqual(testCase, changed.status, "conflict");
verifyTrue(testCase, changed.has_conflicts);
verifyTrue(testCase, any(contains(changed.conflicts, "declared_sample_count")));
verifyEqual(testCase, trackingCounts(conn), after);

clear cleanup
end

% ---------------------------------------------------------------- refusals ---

function testRegistrationInventsNeitherFrameNorClock(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

execute(conn, "DELETE FROM coordinate_systems WHERE coordinate_system_key='arena_2d'");
verifyError(testCase, @() register(fixture, false), ...
    "vawlume:tracking:CoordinateSystemNotFound");

clear cleanup
end

function testUnknownTimebaseIsRefused(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
spec = fixture.spec;
spec.timebase_key = "no_such_clock";
verifyError(testCase, @() vawlume.tracking.register(fixture.conn, ...
    struct(recording_id=1), spec, RepoRoot=fixture.repo_root, ...
    SourceRoot=fixture.scratch), "vawlume:tracking:TimebaseNotFound");

clear cleanup
end

function testInvalidMappingIsNotRegistered(testCase)
[fixture, cleanup] = setUpWorld(); %#ok<ASGLU>
conn = fixture.conn;

% Blank identity in the artifact: the mapping is invalid, so Apply refuses
% rather than registering a stream whose traces are wrong.
writeTrackingCsv(fixture.artifact_path, 6, BlankIdentityRow=3);
verifyError(testCase, @() register(fixture, true), "vawlume:tracking:NotReady");
verifyEqual(testCase, numberOf(conn, ...
    "SELECT COUNT(*) AS n FROM tracking_streams"), 0);

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function result = register(fixture, apply)
result = vawlume.tracking.register(fixture.conn, struct(recording_id=1), ...
    fixture.spec, Apply=apply, RepoRoot=fixture.repo_root, ...
    SourceRoot=fixture.scratch);
end

function counts = trackingCounts(conn)
names = ["external_streams", "tracking_streams", "tracking_series", ...
    "external_stream_coverage", "external_stream_sources", "source_files", ...
    "config_profiles", "config_profile_versions"];
counts = struct();
for name = names
    counts.(name) = numberOf(conn, "SELECT COUNT(*) AS n FROM " + name);
end
end

function total = totalRowCount(conn)
rows = fetch(conn, "SELECT name FROM sqlite_master WHERE type='table' " + ...
    "AND name NOT LIKE 'sqlite_%'");
total = 0;
names = string(rows.name);
for index = 1:numel(names)
    total = total + numberOf(conn, "SELECT COUNT(*) AS n FROM " + names(index));
end
end

function writeTrackingCsv(path, sampleTimes, options)
arguments
    path (1,1) string
    sampleTimes (1,1) double
    options.BlankIdentityRow (1,1) double = NaN
end
lines = "time_s,subject,bodypart,x,y,likelihood";
row = 0;
for subject = ["mouse_a", "mouse_b"]
    for part = ["snout", "tail_base"]
        for t = 0:(sampleTimes - 1)
            row = row + 1;
            partLabel = part;
            if ~isnan(options.BlankIdentityRow) && row == options.BlankIdentityRow
                partLabel = "";
            end
            lines(end + 1, 1) = string(t) + "," + subject + "," + partLabel + ...
                "," + string(row * 0.5) + "," + string(row * 0.25) + ",0.97"; %#ok<AGROW>
        end
    end
end
writelines(lines, path);
end

function [fixture, cleanup] = setUpWorld()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbFile = fullfile(scratch, "tracking.sqlite");
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
writeTrackingCsv(artifactPath, 6);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    artifact_path=artifactPath);
fixture.spec = struct( ...
    artifact_path="session_01_tracking.csv", ...
    profile_path=fullfile(repoRoot, "config", "01_mapping_profiles", "tracking", ...
        "generic_tracking_mapping_profile.json"), ...
    timebase_key="video_native");
fixture.baseline_rows = totalRowCount(conn);
end

function value = numberOf(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
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
