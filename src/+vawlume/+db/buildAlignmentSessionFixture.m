function [fixture, cleanup] = buildAlignmentSessionFixture(options)
%BUILDALIGNMENTSESSIONFIXTURE Build the Phase 6 alignment-session core for module tests.
%
% [FIXTURE, CLEANUP] = vawlume.db.buildAlignmentSessionFixture(...) builds, in a
% fresh disposable directory, the session several Phase 6 integration tests
% share: one project, its recordings, three clocks and a tracking stream whose
% tracks move LINEARLY in video time, so every interpolated position has an exact
% ground truth. The caller adds its own scene on top: detections, entities,
% channels, identity claims, audio. Delete or clear CLEANUP to close the
% connection and remove the directory.
%
% THE CLOCKS (the generator's, written into synthetic anchor tables):
%
%   audio_native   piecewise affine onto the reference, regime change at 900 s
%   video_native   affine onto the reference
%   neural_native  the reference
%
% with five anchors at audio 10, 400, 900, 1200 and 1500 s, registered through the
% shipped synthetic session manifest and fitted through vawlume.alignment.fit.
%
% ONE DOCUMENTED WORKAROUND. A manifest's method applies to its whole alignment
% set, and this session needs an affine video transform beside a piecewise audio
% one in ONE set, which the tests that use it read as one set. The audio run is
% therefore switched to piecewise_affine by a direct UPDATE before it is fitted,
% as the Phase 6 tests did. vawlume.db.buildIntegratedFixture shows the public
% alternative (one set per method).
%
% WHO SHOULD USE WHICH BUILDER. A test that needs moving trajectories or the
% piecewise audio clock uses this one. Cross-module and cross-path work uses
% vawlume.db.buildIntegratedFixture, the Phase 7 integrated scene.
%
% Name-value options:
%   Recordings         struct array of path_or_uri, relative_path,
%                      native_recording_id, sample_rate_hz and channel_count
%                      (NaN when not declared). Default: one recording,
%                      REC_SESSION_01 at 250 kHz, channel count undeclared
%   RegisterSemantics  run vawlume.db.registerBuiltinSemantics (default false)
%   Regions            N-by-2 [audio centre, half width] of tracked regions, in
%                      audio seconds. Default [300.05 1; 900.0 1; 1100.1 1]
%   Tracks             native track labels written (default ["track0","track1"])
%   WithConfidence     write a likelihood column and map it (default true)
%   TrackStop          struct(track=..., region=..., after_audio_s=...): that
%                      track has no sample after that time in that region
%   WorkspacePrefix    directory-name prefix under tempdir
%   RepoRoot           repository root, inferred from this file by default
%
% FIXTURE fields: conn, workspace, repo_root, knot, scale, offset, video_scale,
% video_offset, audio_run, video_run.
%
% Every value is synthetic. Nothing here is calibrated or validated.
%
% See also VAWLUME.DB.BUILDINTEGRATEDFIXTURE, VAWLUME.DB.BUILDPHASE1FIXTURE

arguments
    options.Recordings struct = struct(path_or_uri="synthetic/session01.wav", ...
        relative_path="session01.wav", native_recording_id="REC_SESSION_01", ...
        sample_rate_hz=250000, channel_count=NaN)
    options.RegisterSemantics (1,1) logical = false
    options.Regions (:,2) double = [300.05 1; 900.0 1; 1100.1 1]
    options.Tracks (1,:) string = ["track0", "track1"]
    options.WithConfidence (1,1) logical = true
    options.TrackStop struct = struct([])
    options.WorkspacePrefix (1,1) string = "vawlume_alignment_session_"
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
workspace = string(fullfile(tempdir, options.WorkspacePrefix + ...
    string(java.util.UUID.randomUUID)));
mkdir(workspace);
conn = sqlite(char(fullfile(workspace, "session.sqlite")), "create");
cleanup = onCleanup(@() removeSession(conn, workspace));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
if options.RegisterSemantics
    vawlume.db.registerBuiltinSemantics(conn, repoRoot);
end

execute(conn, "INSERT INTO projects(project_key, project_name) VALUES " + ...
    "('synthetic_alignment_session', 'Synthetic alignment session')");
seedRecordings(conn, options.Recordings);

fixture = generator();
fixture.conn = conn;
fixture.workspace = workspace;
fixture.repo_root = repoRoot;
fixture = orderFields(fixture);
registerClocks(conn, fixture, workspace, repoRoot);
fixture.audio_run = runIdFor(conn, "audio_native");
fixture.video_run = runIdFor(conn, "video_native");

vawlume.geometry.registerCoordinateSystem(conn, struct(project_id=1), struct( ...
    coordinate_system_key="arena_2d", coordinate_system_name="Arena floor plane", ...
    dimensionality=2, unit="cm"));
registerTracking(conn, fixture, options, workspace, repoRoot);
end

% ============================================================== generator ===

function g = generator()
%GENERATOR The synthetic clocks the anchor tables are written from.
%
% These are the generator's own parameters, as the Phase 6 tests declared them.
% Once the anchors are registered, every stored transform is fitted and applied
% by vawlume.alignment; the video map below only places synthetic samples.
g = struct(knot=900, video_scale=0.9992, video_offset=53.40);
g.scale = [1.0015; 0.9990];
g.offset = [117.25; (1.0015 - 0.9990) * g.knot + 117.25];
end

function fixture = orderFields(fixture)
fixture = orderfields(fixture, ["conn", "workspace", "repo_root", "knot", ...
    "video_scale", "video_offset", "scale", "offset"]);
end

function value = generatedVideoTime(fixture, referenceTime)
value = (referenceTime - fixture.video_offset) / fixture.video_scale;
end

% ================================================================= clocks ===

function registerClocks(conn, fixture, workspace, repoRoot)
audioTimes = [10; 400; 900; 1200; 1500];
segment = 1 + double(audioTimes >= fixture.knot);
neuralTimes = fixture.scale(segment) .* audioTimes + fixture.offset(segment);
videoTimes = generatedVideoTime(fixture, neuralTimes);
writetable(behaviorTable(), fullfile(workspace, "video_events.csv"));
writetable(neuralTable(neuralTimes), fullfile(workspace, "neural_events.csv"));
writetable(anchorTable(audioTimes, videoTimes, neuralTimes), ...
    fullfile(workspace, "sync_anchors.csv"));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
vawlume.ingest.alignment(conn, string(manifestPath), RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);
% The documented workaround: piecewise audio beside affine video in one set.
execute(conn, "UPDATE time_alignment_runs SET method='piecewise_affine' " + ...
    "WHERE source_timebase_id = (SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='audio_native')");
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="audio_native", Breakpoints=fixture.knot, Apply=true);
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="video_native", Apply=true);
end

function value = runIdFor(conn, timebaseKey)
rows = fetch(conn, "SELECT t.alignment_run_id FROM time_alignment_runs t " + ...
    "JOIN timebases tb ON tb.timebase_id = t.source_timebase_id " + ...
    "WHERE tb.timebase_name = '" + timebaseKey + "'");
value = double(rows.alignment_run_id(1));
end

% ============================================================== recordings ===

function seedRecordings(conn, recordings)
paths = strings(0, 1);
for k = 1:numel(recordings)
    r = recordings(k);
    paths(end + 1, 1) = "(1, 'recording_audio', '" + r.path_or_uri + "', '" + ...
        r.relative_path + "')"; %#ok<AGROW>
end
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, " + ...
    "relative_path) VALUES " + strjoin(paths, ","));
declaresCount = any(arrayfun(@(r) ~isnan(r.channel_count), recordings));
rows = strings(0, 1);
for k = 1:numel(recordings)
    r = recordings(k);
    row = "(1, " + k + ", '" + r.native_recording_id + "', " + ...
        string(r.sample_rate_hz);
    if declaresCount
        row = row + ", " + string(r.channel_count);
    end
    rows(end + 1, 1) = row + ")"; %#ok<AGROW>
end
columns = "project_id, source_file_id, native_recording_id, sample_rate_hz";
if declaresCount
    columns = columns + ", channel_count";
end
execute(conn, "INSERT INTO recordings(" + columns + ") VALUES " + strjoin(rows, ","));
end

% =============================================================== tracking ===

function registerTracking(conn, fixture, options, workspace, repoRoot)
regions = zeros(size(options.Regions));
for r = 1:size(options.Regions, 1)
    reference = vawlume.alignment.applyTransform(conn, fixture.audio_run, ...
        options.Regions(r, 1));
    center = generatedVideoTime(fixture, reference);
    regions(r, :) = [center - options.Regions(r, 2), center + options.Regions(r, 2)];
end
stop = struct(track="", region=0, video_time=Inf);
if ~isempty(options.TrackStop)
    reference = vawlume.alignment.applyTransform(conn, fixture.audio_run, ...
        options.TrackStop.after_audio_s);
    stop = struct(track=string(options.TrackStop.track), ...
        region=options.TrackStop.region, ...
        video_time=generatedVideoTime(fixture, reference));
end
writeTrackingCsv(fullfile(workspace, "arena_tracking.csv"), regions, ...
    options.Tracks, stop, options.WithConfidence);
profilePath = fullfile(workspace, "tracking_profile.json");
writeProfile(profilePath, repoRoot, options.WithConfidence);
vawlume.tracking.register(conn, struct(recording_id=1), struct( ...
    artifact_path="arena_tracking.csv", profile_path=profilePath, ...
    timebase_key="video_native", stream_name="arena_tracking"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=workspace);
end

function writeTrackingCsv(path, regions, tracks, stop, withConfidence)
% 30 Hz samples inside each region only, so the stretches between regions are
% covered (registration covers the artifact's whole span) but empty.
header = "time_s,subject,bodypart,x,y";
if withConfidence
    header = header + ",likelihood";
end
lines = header;
for r = 1:size(regions, 1)
    times = (ceil(regions(r, 1) * 30):floor(regions(r, 2) * 30))' / 30;
    for t = times'
        for track = tracks
            if track == stop.track && r == stop.region && t > stop.video_time
                continue
            end
            [x, y] = truePosition(track, t);
            for part = ["snout", "tail_base"]
                line = compose("%.9f", t) + "," + track + "," + part + "," + ...
                    compose("%.9f", x) + "," + compose("%.9f", y);
                if withConfidence
                    line = line + ",0.95";
                end
                lines(end + 1, 1) = line; %#ok<AGROW>
            end
        end
    end
end
writelines(lines, path);
end

function [x, y] = truePosition(track, videoTime)
% Snout trajectories, linear in video time, so linear interpolation is exact.
% track1 and track2 run along x = 50, the perpendicular bisector of microphones
% placed at (0,0) and (100,0), so each is equidistant from both.
switch track
    case "track0"
        x = 10 + 0.01 * videoTime;
        y = 20 + 0 * videoTime;
    case "track1"
        x = 50 + 0 * videoTime;
        y = 20 + 0.005 * videoTime;
    otherwise
        x = 50 + 0 * videoTime;
        y = 60 + 0.005 * videoTime;
end
end

function writeProfile(path, repoRoot, withConfidence)
source = fullfile(repoRoot, "config", "01_mapping_profiles", "tracking", ...
    "generic_tracking_mapping_profile.json");
if withConfidence
    writelines(string(fileread(source)), path);
    return
end
document = jsondecode(fileread(source));
document.profiles.columns = rmfield(document.profiles.columns, "confidence");
writelines(string(jsonencode(document, PrettyPrint=true)), path);
end

% ================================================================= tables ===

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

% ================================================================ cleanup ===

function removeSession(conn, workspace)
try
    if isopen(conn), close(conn); end
catch
end
try
    if isfolder(workspace), rmdir(workspace, "s"); end
catch
end
end
