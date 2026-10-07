function demonstration = native_estimator_demo(options)
%NATIVE_ESTIMATOR_DEMO Demonstrate the integrated Phase 6 native caller estimator.
%
% DEMONSTRATION = NATIVE_ESTIMATOR_DEMO() creates a disposable synthetic session
% and carries it through VAWLUME's own caller-attribution path: a recording with
% two participating animals and two microphone channels of deliberately
% different gain, placed in the frame the tracking data uses; reference noise on
% both channels, measured and aggregated into response estimates; tracking on
% its own clock, related to the recording's through a piecewise audio transform,
% with a coverage gap; identity associations including a swap; call-window
% measurement and normalization, with raw and normalized level differences side
% by side; the estimator run, previewed before it is applied; the settings
% profile's five conditions, printed from the stored profile; every candidate's
% score or its reason for none; every evidence dimension with its citation; one
% score reconstructed from read-back rows; decisions under the native policy;
% and the full read-back through vawlume.attribution.report.
%
% Six targets, one per scene: separable, symmetric geometry, MODEL MISMATCH (a
% call with directivity the method does not model), an unfittable level
% difference, a tracking coverage gap, and an identity swap.
%
% The refusals are demonstrated beside the successes, in a harness that fails
% the example if a refusal stops refusing: a native run without an estimator
% settings profile, a settings profile missing one of its five conditions, a
% distance across two frames, a normalization against another recording's
% response estimate, and a second apply.
%
% Nothing here is calibrated and nothing is validated. Every number is
% synthetic. The separable and symmetric scenes are generated from the method's
% own spreading assumption, so they show SELF-CONSISTENCY, not accuracy. No
% score is a probability, and no decision is evidence that any animal called.
% All inputs are created under the system temporary directory and removed
% before return.
%
% Name-value options:
%   Print     print compact developer-facing read-backs (default true)
%   RepoRoot  repository root, inferred from this file by default
%
% See also BACKEND_LOCALIZATION_DEMO, CALLER_ATTRIBUTION_DEMO,
% MULTIMODAL_INTEGRATION_DEMO, VAWLUME.ESTIMATOR.ATTRIBUTECALLERS

arguments
    options.Print (1,1) logical = true
    options.RepoRoot (1,1) string = ""
end

repoRoot = normalizedRepoRoot(options.RepoRoot);
sourcePath = fullfile(repoRoot, "src");
removeSourcePath = ~pathContains(sourcePath);
if removeSourcePath, addpath(sourcePath); end
cleanupPath = onCleanup(@() restoreSourcePath(sourcePath, removeSourcePath));

workspace = string(fullfile(tempdir, "VAWLUME phase 6 native estimator demo " + ...
    string(java.util.UUID.randomUUID)));
mkdir(workspace);
mkdir(fullfile(workspace, "audio"));
cleanupWorkspace = onCleanup(@() removeTree(workspace));
databasePath = fullfile(workspace, "native_estimator_demo.sqlite");
conn = sqlite(char(databasePath), "create");
cleanupConnection = onCleanup(@() closeConnection(conn));

vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);

scenes = sceneTable();
session = seedSession(conn, workspace, repoRoot, scenes);
settings = vawlume.estimator.loadSettings(RepoRoot=repoRoot);
session.settings_version = vawlume.db.registerProfileVersion(conn, ...
    struct(project_id=1), struct(profile_key=settings.profile_key, ...
    profile_name=settings.profile_name, version_label=settings.version_label, ...
    content_path=settings.path, profile_kind=settings.profile_kind, ...
    profile_schema_version=settings.profile_schema_version), ...
    RepoRoot=repoRoot).profile_version_id;
generating = generatingDistances(conn, session, settings, scenes);
writeAudio(fullfile(workspace, "audio", "session.wav"), session, scenes, generating);
acoustic = acousticChain(conn, session, scenes, repoRoot);

% --- The estimator: dry run, then apply ----------------------------------------

spec = runSpec(session, "session01-native", scenes, acoustic);
before = attributionCounts(conn);
preview = vawlume.estimator.attributeCallers(conn, struct(recording_id=1), spec, ...
    RepoRoot=repoRoot);
previewWroteNothing = isequal(attributionCounts(conn), before);
applied = vawlume.estimator.attributeCallers(conn, struct(recording_id=1), spec, ...
    Apply=true, RepoRoot=repoRoot);
runRef = struct(attribution_run_id=applied.attribution_run_id);

refusals = emptyRefusals();
refusals = recordRefusal(refusals, "a second apply of the same native run key", ...
    @() vawlume.estimator.attributeCallers(conn, struct(recording_id=1), spec, ...
        Apply=true, RepoRoot=repoRoot));
refusals = demonstrateRefusals(conn, session, settings, acoustic, workspace, ...
    repoRoot, refusals);

% --- Decisions and read-back ---------------------------------------------------

decided = vawlume.attribution.decide(conn, runRef, string(fullfile(repoRoot, ...
    "config", "08_attribution_policies", "native_level_difference_decision_policy.json")), ...
    RepoRoot=repoRoot, Apply=true);
report = vawlume.attribution.report(conn, runRef);
stored = storedSettings(conn, report.settings_profile_version_id, repoRoot);

demonstration = struct( ...
    calibration_boundary="Every position, level, score and threshold here is " + ...
        "synthetic. The native score is VAWLUME's own uncalibrated dB consistency " + ...
        "score, comparable within this recording only. It is not a probability, " + ...
        "and no decision below means an animal called.", ...
    geometry=struct(microphones_cm=session.mics, channel_gains=session.gains, ...
        frame="arena_2d (cm)", audio_clock="piecewise affine, knot at 900 s", ...
        tracking_clock="affine, video_native"), ...
    response_estimates=acoustic.response_estimates, ...
    scenes=sceneSummary(conn, scenes, applied, decided, acoustic), ...
    preview=struct(status=preview.status, wrote_nothing=previewWroteNothing, ...
        planned_counts=preview.planned_counts), ...
    applied=struct(status=applied.status, attribution_run_id=applied.attribution_run_id, ...
        planned_counts=applied.planned_counts), ...
    five_conditions=fiveConditions(stored), ...
    candidates=report.candidates(:, ["attribution_target_id", "entity_native_id", ...
        "score", "notes"]), ...
    score_semantics=unique(report.candidates.score_semantics( ...
        strlength(report.candidates.score_semantics) > 0)), ...
    evidence=evidenceDisplay(report, applied, scenes), ...
    reconstruction=reconstruct(conn, report, stored, scenes, applied), ...
    mismatch=mismatchFinding(scenes, applied, decided, session), ...
    decisions=decisionDisplay(decided, applied, scenes), ...
    policy=decided.policy, ...
    report=compactReport(report), ...
    refusals=refusals, ...
    database_inventory=databaseInventory(conn), ...
    foreign_key_check=fetch(conn, "PRAGMA foreign_key_check"), ...
    proves=["VAWLUME scores caller candidates from its own audio, tracking, " + ...
        "identity and alignment evidence through one public call, which previews " + ...
        "before it writes and writes one atomic run through the canonical API"; ...
        "a channel gain difference is removed by a versioned, band-matched " + ...
        "normalization before any comparison"; ...
        "a track reaches an animal only through a stored, time-valid identity " + ...
        "association; a swap or a tracking gap gives no score, and says why"; ...
        "the method's licence, its five conditions, is stored with the run and " + ...
        "read back from the version the run cites"; ...
        "every input is its own cited evidence row, and a stored score is " + ...
        "recomputed from those rows alone"; ...
        "the native policy calls geometry it cannot separate ambiguous, never " + ...
        "simultaneous, and excludes a target it cannot score"; ...
        "the path refuses, by name, where guessing would look like success"], ...
    does_not_prove=["that any animal called, or that an assigned animal did"; ...
        "that the method is accurate: the separable and symmetric scenes are " + ...
        "generated from the method's own spreading assumption"; ...
        "that a real call's level difference follows spherical spreading: the " + ...
        "model-mismatch scene shows the method assigning the wrong animal when it does not"; ...
        "that any score or threshold is calibrated, or comparable across recordings"; ...
        "that a real session's tracking, identity or response estimates behave " + ...
        "like these synthetic ones"; ...
        "anything about more than two animals or two microphones"], ...
    temporary_artifacts_removed=false);

close(conn);
clear cleanupConnection
removeTree(workspace);
clear cleanupWorkspace
demonstration.temporary_artifacts_removed = ...
    ~isfolder(workspace) && ~isfile(databasePath);

if options.Print, printDemonstration(demonstration); end
clear cleanupPath
end

% ================================================================= scenes ===

function value = sceneTable()
% One target per scene, in recording-native audio seconds. bias_db is
% directivity added at microphone a that the method does not model.
value = table( ...
    ["separable"; "symmetric"; "model_mismatch"; "unfittable"; "coverage_gap"; ...
        "identity_swap"], ...
    [1; 7; 11; 10; 3; 5], ...
    [300.0; 700.0; 301.5; 301.2; 600.0; 1100.0], ...
    [300.1; 700.1; 301.6; 301.3; 600.1; 1100.2], ...
    [0; 0; -9; 0; 0; 0], ...
    ["A is near microphone a and B is far. The call is generated from A's own " + ...
        "distances under spherical spreading: self-consistency, not accuracy"; ...
    "both animals stand on the perpendicular bisector of the microphones, so " + ...
        "each predicts 0 dB; the call is equally loud at both"; ...
    "A calls facing away from microphone a: the observation is A's spherical " + ...
        "prediction minus 9 dB of directivity the method does not model"; ...
    "the call is 8 dB louder at microphone b, which neither position predicts"; ...
    "identity is clear, but the tracker recorded no sample during the call"; ...
    "the two tracks swap identities during the call"], ...
    VariableNames=["scene", "detection_id", "start_s", "end_s", "bias_db", "built_how"]);
end

% ================================================================ session ===

function session = seedSession(conn, workspace, repoRoot, scenes)
%SEEDSESSION The session recipe of the Phase 6 integration tests.
execute(conn, "INSERT INTO projects(project_key, project_name) VALUES " + ...
    "('synthetic_alignment_session', 'Synthetic alignment session')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, " + ...
    "relative_path) VALUES (1, 'recording_audio', 'audio/session.wav', " + ...
    "'audio/session.wav'),(1, 'recording_audio', 'audio/other.wav', 'audio/other.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, native_recording_id, " + ...
    "sample_rate_hz, channel_count) VALUES (1, 1, 'REC_SESSION_01', 1000, 2)," + ...
    "(1, 2, 'REC_OTHER', 1000, 2)");

session = struct(workspace=workspace, knot=900, video_scale=0.9992, ...
    video_offset=53.40, mics=[0 0; 100 0], gains=[1 0.5]);
session.scale = [1.0015; 0.9990];
session.offset = [117.25; (1.0015 - 0.9990) * session.knot + 117.25];
audioTimes = [10; 400; 900; 1200; 1500];
segment = 1 + double(audioTimes >= session.knot);
neuralTimes = session.scale(segment) .* audioTimes + session.offset(segment);
videoTimes = (neuralTimes - session.video_offset) / session.video_scale;
writetable(behaviorTable(), fullfile(workspace, "video_events.csv"));
writetable(neuralTable(neuralTimes), fullfile(workspace, "neural_events.csv"));
writetable(anchorTable(audioTimes, videoTimes, neuralTimes), ...
    fullfile(workspace, "sync_anchors.csv"));
manifestPath = fullfile(workspace, "alignment_manifest.json");
copyfile(fullfile(repoRoot, "config", "06_alignment_manifests", ...
    "synthetic_session_alignment_manifest.json"), manifestPath);
vawlume.ingest.alignment(conn, string(manifestPath), RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);
% The audio clock is piecewise around a knot at 900 s; the video clock is affine.
execute(conn, "UPDATE time_alignment_runs SET method='piecewise_affine' " + ...
    "WHERE source_timebase_id = (SELECT timebase_id FROM timebases " + ...
    "WHERE timebase_name='audio_native')");
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="audio_native", Breakpoints=session.knot, Apply=true);
vawlume.alignment.fit(conn, struct(run_key="synthetic_session_01_alignment"), ...
    SourceTimebase="video_native", Apply=true);
session.audio_run = runIdFor(conn, "audio_native");
session.video_run = runIdFor(conn, "video_native");

execute(conn, "INSERT INTO extractors(extractor_id, extractor_key, extractor_name) " + ...
    "VALUES (90,'synthetic','Synthetic')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id, extractor_id, " + ...
    "version_label) VALUES (90,90,'v')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id, project_id, " + ...
    "extractor_version_id, run_key) VALUES (1, 1, 90, 'calls')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id, recording_id) " + ...
    "VALUES (1, 1)");
values = strjoin(compose("(%d,1,1,%.1f,%.1f)", scenes.detection_id, scenes.start_s, ...
    scenes.end_s), ",");
execute(conn, "INSERT INTO detections(detection_id, extraction_run_id, recording_id, " + ...
    "start_time_s, end_time_s) VALUES " + values);

execute(conn, "INSERT INTO entity_types(project_id, native_name) VALUES (1, 'subject')");
execute(conn, "INSERT INTO experimental_entities(entity_id, project_id, entity_type_id, " + ...
    "native_id) VALUES (1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_id, entity_id) VALUES (1,1),(1,2)");
session.A = 1;
session.B = 2;

% Two frames: the arena, which microphones and tracking share, and a camera
% image frame used only to show that VAWLUME will not measure across frames.
vawlume.geometry.registerCoordinateSystem(conn, struct(project_id=1), struct( ...
    coordinate_system_key="arena_2d", coordinate_system_name="Arena floor plane", ...
    dimensionality=2, unit="cm"));
vawlume.geometry.registerCoordinateSystem(conn, struct(project_id=1), struct( ...
    coordinate_system_key="camera_2d", coordinate_system_name="Overhead camera image", ...
    dimensionality=2, unit="cm"));
for recording = 1:2
    for channel = 1:2
        vawlume.geometry.registerRecordingChannel(conn, struct(recording_id=recording), ...
            struct(channel_index=channel, channel_label="mic_" + char('a' + channel - 1)));
    end
end
for channel = 1:2
    vawlume.geometry.registerChannelPlacement(conn, struct(recording_id=1), struct( ...
        channel_index=channel, coordinate_system_key="arena_2d", ...
        position_x=session.mics(channel, 1), position_y=session.mics(channel, 2)));
end

% Tracking: three regions with samples. Between them the tracker recorded
% nothing, which is the gap the coverage-gap scene falls in.
regions = [videoAround(conn, session, 300.5, 1.5); ...
    videoAround(conn, session, 700.05, 1); videoAround(conn, session, 1100.1, 1)];
writeTrackingCsv(fullfile(workspace, "arena_tracking.csv"), regions);
profilePath = fullfile(workspace, "tracking_profile.json");
writelines(string(fileread(fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "tracking", "generic_tracking_mapping_profile.json"))), profilePath);
vawlume.tracking.register(conn, struct(recording_id=1), struct( ...
    artifact_path="arena_tracking.csv", profile_path=profilePath, ...
    timebase_key="video_native", stream_name="arena_tracking"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=workspace);
registerIdentity(conn, session);
end

function registerIdentity(conn, session)
v = @(audioTime) videoTimeOf(conn, session, audioTime);
claim = @(track, entity, startAudio, endAudio) ...
    vawlume.tracking.registerIdentityAssociation(conn, streamRef(), struct( ...
    native_track_id=track, entity_id=entity, start_time_native=v(startAudio), ...
    end_time_native=v(endAudio), assignment_state="assigned", ...
    evidence_kind="manual_assertion"));
claim("track0", session.A, 299.0, 302.0);   % separable, mismatch, unfittable
claim("track1", session.B, 299.0, 302.0);
claim("track0", session.A, 590, 610);       % coverage gap: identity is clear
claim("track1", session.B, 590, 610);
claim("track1", session.A, 698, 702);       % symmetric: both on the bisector
claim("track2", session.B, 698, 702);
claim("track0", session.A, 1099, 1100.15);  % identity swap, mid-call
claim("track0", session.B, 1100.15, 1101.2);
claim("track1", session.B, 1099, 1100.15);
claim("track1", session.A, 1100.15, 1101.2);
end

function distances = generatingDistances(conn, session, settings, scenes)
% A's own midpoint distances, read through the same geometry the estimator uses,
% for the scenes whose call is generated from A's position.
distances = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["detection_id", "distance_a", "distance_b"]);
generated = scenes.detection_id(ismember(scenes.scene, ["separable", "model_mismatch"]));
for detection = generated'
    geometry = vawlume.estimator.candidateGeometry(conn, struct(detection_id=detection), ...
        audioClock(session), struct(stream=streamRef(), ...
        bodypart=settings.parameters.bodypart, ...
        max_gap_s=settings.parameters.max_interpolation_gap_s, ...
        alignment_run_id=session.video_run, source_root=session.workspace), ...
        [session.A session.B], settings.parameters.channel_pair);
    g = geometry.geometry;
    at = g(g.entity_id == session.A & g.instant_basis == "midpoint", :);
    distances(end + 1, :) = {detection, at.distance(at.channel_index == 1), ...
        at.distance(at.channel_index == 2)}; %#ok<AGROW>
end
end

function writeAudio(path, session, scenes, generating)
% 1000 Hz, 24-bit, two channels. Channel k hears every source at gain(k). Calls
% are 250 Hz; the reference family is four tones in the declared band.
rate = 1000;
total = 1102 * rate;
time = (0:total - 1)' / rate;
signal = zeros(total, 2);
noise = zeros(total, 1);
for frequency = [220 240 260 280]
    noise = noise + 0.05 * sin(2 * pi * frequency * time);
end
tone = sin(2 * pi * 250 * time);
for channel = 1:2
    g = session.gains(channel);
    signal = place(signal, channel, g * noise, [50.0 50.4], rate);
    signal = place(signal, channel, g * noise, [50.4 50.8], rate);
    for k = 1:height(scenes)
        switch scenes.scene(k)
            case {"separable", "model_mismatch"}
                % Spherical spreading from A: amplitude ~ 1/d, power ~ 1/d^2.
                d = generating(generating.detection_id == scenes.detection_id(k), :);
                distance = [d.distance_a, d.distance_b];
                level = 10 / distance(channel);
                if channel == 1
                    level = level * 10^(scenes.bias_db(k) / 20);
                end
            case "unfittable"
                towardB = [10^(-8 / 20), 1];
                level = 0.3 * towardB(channel);
            case "identity_swap"
                level = 0.3;
            otherwise
                level = 0.2;
        end
        signal = place(signal, channel, g * level * tone, ...
            [scenes.start_s(k) scenes.end_s(k)], rate);
    end
end
audiowrite(char(path), signal, rate, BitsPerSample=24);
% The other recording is a copy, for the cross-recording refusal only.
copyfile(path, fullfile(fileparts(path), "other.wav"));
end

function signal = place(signal, channel, values, interval, rate)
selected = (round(interval(1) * rate) + 1:round(interval(2) * rate))';
signal(selected, channel) = values(selected);
end

function acoustic = acousticChain(conn, session, scenes, repoRoot)
% Reference responses, then per call a measurement and a normalization.
response = responseEstimate(conn, session, 1, "");
count = height(scenes);
callRuns = zeros(count, 1);
normalizationRuns = zeros(count, 1);
rawDb = NaN(count, 1);
for k = 1:count
    detection = scenes.detection_id(k);
    call = vawlume.acoustic.measureCallWindow(conn, struct(detection_id=detection), ...
        [1 2], BandHz=[200 300], SourceRoot=session.workspace, Apply=true, ...
        RunKey="call-d" + detection);
    callRuns(k) = call.analysis_run_id;
    normalized = vawlume.acoustic.normalizeCallLevels(conn, ...
        struct(analysis_run_id=call.analysis_run_id), struct(analysis_run_id=response), ...
        RepoRoot=repoRoot, Apply=true, RunKey="norm-d" + detection);
    normalizationRuns(k) = normalized.analysis_run_id;
    % For display only: the raw band-power ratio still carries the channels'
    % gain difference, which is what normalization removes.
    rawDb(k) = rawRatioDb(conn, call.analysis_run_id);
end
estimates = vawlume.acoustic.readChannelResponse(conn, ...
    struct(analysis_run_id=response)).estimates;
estimates = estimates(estimates.metric_key == "acoustic_band_power", ...
    ["channel_index", "channel_label", "metric_key", "reference_type", ...
    "frequency_min_hz", "frequency_max_hz", "value_real", "qc_status"]);
acoustic = struct(response_run=response, response_estimates=estimates, ...
    runs=table(scenes.detection_id, callRuns, normalizationRuns, rawDb, ...
        VariableNames=["detection_id", "call_run_id", "analysis_run_id", ...
        "raw_difference_db"]));
end

function value = rawRatioDb(conn, runId)
rows = fetch(conn, "SELECT rc.channel_index, dm.value_real FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "JOIN recording_channels rc ON rc.recording_channel_id=dm.recording_channel_id " + ...
    "WHERE dm.analysis_run_id=" + string(runId) + " AND md.metric_key='call_band_power'");
index = double(rows.channel_index);
power = double(rows.value_real);
value = 10 * log10(power(index == 1) / power(index == 2));
end

function runId = responseEstimate(conn, session, recordingId, prefix)
ids = zeros(0, 1);
for k = 1:2
    interval = [50.0 50.4] + 0.4 * (k - 1);
    ref = vawlume.acoustic.registerReference(conn, struct(recording_id=recordingId), ...
        struct(reference_key=prefix + "noise-" + k, reference_type="noise", ...
        start_time_s=interval(1), end_time_s=interval(2), frequency_min_hz=200, ...
        frequency_max_hz=300));
    for channel = 1:2
        measured = vawlume.acoustic.measureReferenceResponse(conn, ...
            struct(acoustic_reference_id=ref.acoustic_reference_id), channel, ...
            SourceRoot=session.workspace, Apply=true, ...
            RunKey=prefix + "ref-" + k + "-ch" + channel);
        ids(end + 1, 1) = measured.derived_measurement_ids( ...
            measured.metrics.metric_key == "acoustic_band_power"); %#ok<AGROW>
    end
end
runId = vawlume.acoustic.estimateChannelResponse(conn, ...
    struct(recording_id=recordingId), ids, RequiredReferenceTypes="noise", ...
    MinReferences=2, Apply=true, RunKey=prefix + "response").analysis_run_id;
end

function spec = runSpec(session, runKey, scenes, acoustic)
spec = struct(run_key=runKey, settings_profile_version_id=session.settings_version, ...
    target_set=struct(detection_ids=scenes.detection_id'), ...
    participating_entity_ids=[session.A session.B], clock=audioClock(session), ...
    tracking=struct(stream=streamRef(), alignment_run_id=session.video_run, ...
        source_root=session.workspace), ...
    normalization_runs=acoustic.runs(:, ["detection_id", "analysis_run_id"]));
end

% ================================================================ refusals ===

function refusals = demonstrateRefusals(conn, session, settings, acoustic, ...
        workspace, repoRoot, refusals)
% A native run whose settings profile is an imported mapping, not an estimator
% settings profile: a native score with no licence.
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name," + ...
    "profile_kind) VALUES (801,1,'imported-map','Imported mapping','attribution_input_mapping')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id,version_label," + ...
    "content_format,content_uri,checksum_sha256,is_snapshot) VALUES " + ...
    "(801,801,'1','json','imported.json','" + string(repmat('a', 1, 64)) + "',1)");
refusals = recordRefusal(refusals, ...
    "a native run whose settings profile is not an estimator settings profile", ...
    @() vawlume.attribution.createRun(conn, struct(recording_id=1), struct( ...
        run_key="native-without-licence", attribution_path="native_estimate", ...
        method="vawlume.estimator.level_difference_consistency 1.0.0", ...
        settings_profile_version_id=801, target_set=struct(detection_ids=1), ...
        participating_entity_ids=[session.A session.B], ...
        sources=struct(source_file_ids=1), declared_inputs=settings.declared_inputs), ...
        Apply=true));

% An estimator settings profile that omits one of its five conditions.
document = jsondecode(fileread(settings.path));
document = rmfield(document, "calibration_status");
partialPath = fullfile(workspace, "profile_without_calibration_status.json");
writeText(partialPath, jsonencode(document, PrettyPrint=true));
refusals = recordRefusal(refusals, ...
    "an estimator settings profile without its calibration_status condition", ...
    @() vawlume.estimator.loadSettings(string(partialPath), RepoRoot=repoRoot));

% A distance between a microphone in the arena frame and a point in the camera
% frame: two declared frames, and VAWLUME transforms between none.
frames = vawlume.geometry.readCoordinateSystems(conn, struct(project_id=1));
arena = table2struct(frames(frames.coordinate_system_key == "arena_2d", ...
    ["coordinate_system_id", "dimensionality", "unit"]));
camera = table2struct(frames(frames.coordinate_system_key == "camera_2d", ...
    ["coordinate_system_id", "dimensionality", "unit"]));
refusals = recordRefusal(refusals, ...
    "a distance between a microphone in the arena frame and a point in the camera frame", ...
    @() vawlume.geometry.distance(session.mics(1, :), arena, [10 20], camera));

% A call normalized against another recording's channel-response estimate.
otherResponse = responseEstimate(conn, session, 2, "other-");
refusals = recordRefusal(refusals, ...
    "a call normalized against another recording's channel-response estimate", ...
    @() vawlume.acoustic.normalizeCallLevels(conn, ...
        struct(analysis_run_id=acoustic.runs.call_run_id(1)), ...
        struct(analysis_run_id=otherResponse), RepoRoot=repoRoot));
end

function value = emptyRefusals()
value = table('Size', [0 3], 'VariableTypes', ["string", "string", "string"], ...
    'VariableNames', ["what_was_attempted", "identifier", "message"]);
end

function refusals = recordRefusal(refusals, description, action)
%RECORDREFUSAL Exercise a path that must refuse, and keep what it said.
%
% If the action succeeds the example fails: a refusal that stopped refusing is a
% regression, and showing it as a success would teach the opposite lesson.
try
    action();
    error("vawlume:examples:RefusalNotRaised", "Expected a refusal for: %s", description);
catch exception
    if exception.identifier == "vawlume:examples:RefusalNotRaised"
        rethrow(exception);
    end
    captured = exception;
end
refusals = [refusals; table(string(description), string(captured.identifier), ...
    firstSentence(captured.message), VariableNames=["what_was_attempted", ...
    "identifier", "message"])];
end

function value = firstSentence(message)
value = string(message);
stop = strfind(value, ". ");
if ~isempty(stop)
    value = extractBefore(value, stop(1) + 1);
end
end

% ============================================================== read-backs ===

function settings = storedSettings(conn, profileVersionId, repoRoot)
% The run's licence, read back from the profile version it cites.
rows = fetch(conn, "SELECT content_uri, checksum_sha256 FROM config_profile_versions " + ...
    "WHERE profile_version_id=" + string(profileVersionId));
settings = vawlume.estimator.loadSettings(string(rows.content_uri(1)), RepoRoot=repoRoot);
settings.checksum_matches_registration = ...
    settings.checksum_sha256 == string(rows.checksum_sha256(1));
end

function value = fiveConditions(settings)
dims = settings.dimensions;
names = ["temporal_alignment"; "pose_localization"; "visual_identity"; "acoustic"];
declarations = strings(4, 1);
roles = strings(4, 1);
for k = 1:4
    declarations(k) = dims.(names(k)).declaration;
    roles(k) = dims.(names(k)).role;
end
value = struct( ...
    profile=settings.profile_key + "@" + settings.version_label, ...
    content_uri=settings.content_uri, ...
    checksum_matches_registration=settings.checksum_matches_registration, ...
    dimensions=table([names; "source_localization"], ...
        [declarations; dims.source_localization.declaration], ...
        [roles; dims.source_localization.reason], ...
        VariableNames=["dimension", "declaration", "role_or_reason"]), ...
    score=settings.score, ...
    scaling=settings.scaling, ...
    readability=settings.readability, ...
    calibration_status=settings.calibration_status);
end

function value = sceneSummary(conn, scenes, applied, decided, acoustic)
count = height(scenes);
first = strings(count, 1);
second = strings(count, 1);
status = strings(count, 1);
normalizedDb = NaN(count, 1);
for k = 1:count
    target = targetOf(applied, scenes.detection_id(k));
    c = target.method.candidates;
    names = entityNames(conn, c.entity_id);
    first(k) = names(1) + ": " + scoreText(c.score(1), c.no_score_reason(1));
    second(k) = names(2) + ": " + scoreText(c.score(2), c.no_score_reason(2));
    status(k) = decided.decisions.decision_status( ...
        decided.decisions.attribution_target_id == target.attribution_target_id);
    normalizedDb(k) = target.difference.value;
end
value = table(scenes.scene, scenes.detection_id, acoustic.runs.raw_difference_db, ...
    normalizedDb, first, second, status, scenes.built_how, VariableNames=["scene", ...
    "detection_id", "raw_difference_db", "normalized_difference_db", "candidate_1", ...
    "candidate_2", "decision", "built_how"]);
end

function text = scoreText(score, reason)
if isnan(score)
    text = "no score (" + reason + ")";
else
    text = string(sprintf("%.3f dB", score));
end
end

function names = entityNames(conn, ids)
names = strings(numel(ids), 1);
for k = 1:numel(ids)
    rows = fetch(conn, "SELECT native_id FROM experimental_entities WHERE entity_id=" + ...
        string(ids(k)));
    names(k) = string(rows.native_id(1));
end
end

function target = targetOf(applied, detection)
target = applied.targets([applied.targets.event_id] == detection);
end

function value = evidenceDisplay(report, applied, scenes)
% Every row of the separable target, one dimension each, with its citation.
targetId = targetOf(applied, ...
    scenes.detection_id(scenes.scene == "separable")).attribution_target_id;
e = report.evidence(report.evidence.attribution_target_id == targetId, :);
producer = extractBetween(e.value_semantics, "producer=", ";");
% Distances and pose confidence are stored for every instant basis; the score
% reads the primary one (midpoint) only.
basis = arrayfun(@(s) semanticsField(s, "instant_basis"), e.value_semantics);
value = struct(by_dimension=report.qc.evidence_by_dimension, ...
    separable_target=[e(:, ["attribution_candidate_id", "evidence_dimension", ...
        "evidence_kind", "value_real", "value_units", ...
        "tracking_identity_association_id", "alignment_run_id", ...
        "recording_channel_index", "derived_measurement_id"]), ...
        table(basis, producer, VariableNames=["instant_basis", "producer"])]);
end

function value = reconstruct(conn, report, settings, scenes, applied)
%RECONSTRUCT One stored score, recomputed from read-back rows in front of the reader.
detection = scenes.detection_id(scenes.scene == "separable");
targetId = targetOf(applied, detection).attribution_target_id;
p = settings.parameters;
e = report.evidence(report.evidence.attribution_target_id == targetId, :);

% The observed level difference, from the two stored per-channel rows and the
% measurements they cite.
perChannel = e(e.evidence_kind == "call_band_power_normalized", :);
sides = repmat(struct(target_kind="detection", target_id=detection, channel_index=NaN, ...
    normalized_metric="call_band_power_normalized", unit="", status="normalized", ...
    reason="", value=NaN, qc_flags=strings(0, 1), derived_measurement_id=NaN), 1, 2);
for k = 1:2
    row = perChannel(perChannel.recording_channel_index == p.channel_pair(k), :);
    cited = fetch(conn, "SELECT derivation_details_json FROM derived_measurements " + ...
        "WHERE derived_measurement_id=" + string(row.derived_measurement_id));
    details = jsondecode(char(cited.derivation_details_json(1)));
    sides(k).channel_index = p.channel_pair(k);
    sides(k).value = row.value_real;
    sides(k).unit = row.value_units;
    sides(k).derived_measurement_id = row.derived_measurement_id;
    sides(k).qc_flags = string(details.qc_flags(:));
end
difference = vawlume.acoustic.levelDifference(sides(1), sides(2), p.refuse_clipped_channels);

% Each candidate's two stored distances on the primary instant basis.
candidates = report.candidates(report.candidates.attribution_target_id == targetId, :);
entities = table(candidates.entity_id, true(height(candidates), 1), ...
    strings(height(candidates), 1), VariableNames=["entity_id", "has_geometry", "reason"]);
geometry = table();
for k = 1:height(candidates)
    rows = e(e.attribution_candidate_id == candidates.attribution_candidate_id(k) & ...
        e.evidence_kind == "bodypoint_microphone_distance" & ...
        contains(e.value_semantics, "instant_basis=" + p.primary_instant_basis + ";"), :);
    for r = 1:height(rows)
        geometry = [geometry; table(candidates.entity_id(k), ...
            rows.recording_channel_index(r), p.primary_instant_basis, rows.value_real(r), ...
            rows.value_units(r), "computed", "", ...
            semanticsField(rows.value_semantics(r), "event_extrapolated") == "true", ...
            semanticsField(rows.value_semantics(r), "bracket_extrapolated") == "true", ...
            VariableNames=["entity_id", "channel_index", "instant_basis", "distance", ...
            "unit", "status", "reason", "event_extrapolated", ...
            "bracket_extrapolated"])]; %#ok<AGROW>
    end
end
recomputed = vawlume.estimator.levelDifferenceConsistency(entities, geometry, ...
    difference, settings).candidates;
value = table(candidates.entity_native_id, recomputed.distance_a, ...
    recomputed.distance_b, recomputed.predicted_difference_db, ...
    recomputed.observed_difference_db, recomputed.score, candidates.score, ...
    abs(recomputed.score - candidates.score), VariableNames=["entity", ...
    "distance_a_cm", "distance_b_cm", "predicted_db", "observed_db", ...
    "recomputed_score", "stored_score", "absolute_difference"]);
end

function value = semanticsField(semantics, key)
token = regexp(semantics, "(^|; )" + key + "=([^;]*)", "tokens", "once");
if isempty(token)
    value = "";
else
    value = string(token{2});
end
end

function value = mismatchFinding(scenes, applied, decided, session)
k = find(scenes.scene == "model_mismatch");
target = targetOf(applied, scenes.detection_id(k));
c = target.method.candidates;
a = c.entity_id == session.A;
status = decided.decisions.decision_status( ...
    decided.decisions.attribution_target_id == target.attribution_target_id);
selected = decided.selections.attribution_candidate_id( ...
    decided.selections.attribution_target_id == target.attribution_target_id);
selectedEntity = target.candidate_ids.entity_id( ...
    ismember(target.candidate_ids.attribution_candidate_id, selected));
gap = abs(c.predicted_difference_db(a) - c.predicted_difference_db(~a));
value = struct( ...
    generating_entity="A", ...
    predicted_a_db=c.predicted_difference_db(a), ...
    predicted_b_db=c.predicted_difference_db(~a), ...
    unmodelled_bias_db=scenes.bias_db(k), ...
    observed_db=c.observed_difference_db(1), ...
    score_a=c.score(a), score_b=c.score(~a), ...
    generating_entity_ranked_first=c.score(a) > c.score(~a), ...
    decision=status, ...
    selected_generating_entity=isequal(selectedEntity, session.A), ...
    tolerance_db=gap / 2, ...
    meaning="The protection against unmodelled directivity is half the gap " + ...
        "between the two candidates' predictions. A bias larger than that moves " + ...
        "the observation nearer the other animal's prediction, and the other " + ...
        "animal then fits WELL: its score looks like any good fit, and nothing " + ...
        "in the run says it is wrong. This is printed and explained, not " + ...
        "asserted correct: it is what the method does when its assumption fails.");
end

function value = decisionDisplay(decided, applied, scenes)
rows = table();
for k = 1:height(scenes)
    target = targetOf(applied, scenes.detection_id(k));
    rows = [rows; decided.decisions(decided.decisions.attribution_target_id == ...
        target.attribution_target_id, ["decision_status", "applied_threshold", ...
        "selected_count", "exclusion_reason"])]; %#ok<AGROW>
end
value = [table(scenes.scene, VariableNames="scene"), rows];
end

function value = compactReport(report)
value = struct(run_key=report.run_key, attribution_path=report.attribution_path, ...
    grain=grainTable(report), ...
    declared_inputs=report.declared_inputs(:, ["input_dimension", "declaration", ...
        "profile_key"]), ...
    qc=report.qc, qc_note=report.qc_note, ...
    dimension_separation_note=report.dimension_separation_note);
end

function value = grainTable(report)
%GRAINTABLE What each returned table counts, beside how many rows it has.
names = ["targets"; "candidates"; "evidence"; "imported_claims"; ...
    "localization_estimates"; "native_attributes"; "declared_inputs"; ...
    "correspondences"; "claim_correspondences"; "decisions"; "decision_selections"];
grains = ["attribution target"; "(target, candidate entity)"; ...
    "stored evidence record"; "(imported window, claimed caller)"; ...
    "localization estimate"; "(owner, native attribute name)"; ...
    "(run, declared upstream input)"; "stored correspondence"; ...
    "(claim, correspondence)"; "(target, policy version)"; ...
    "candidate a decision selected"];
counts = zeros(numel(names), 1);
for index = 1:numel(names)
    counts(index) = height(report.(names(index)));
end
value = table(names, grains, counts, ...
    VariableNames=["table_name", "one_row_per", "row_count"]);
end

function value = attributionCounts(conn)
names = ["attribution_runs", "attribution_targets", "attribution_candidates", ...
    "attribution_evidence", "attribution_run_declared_inputs"];
value = zeros(1, numel(names));
for k = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(k));
    value(k) = double(rows.n(1));
end
end

function value = databaseInventory(conn)
names = ["attribution_runs"; "attribution_targets"; "attribution_candidates"; ...
    "attribution_evidence"; "attribution_run_declared_inputs"; ...
    "attribution_decisions"; "attribution_decision_candidates"; ...
    "derived_measurements"; "channel_response_estimates"; ...
    "tracking_identity_associations"; "alignment_segments"; "analysis_runs"];
counts = zeros(numel(names), 1);
for index = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(index));
    counts(index) = double(rows.n(1));
end
value = table(names, counts, VariableNames=["table_name", "row_count"]);
end

% =================================================================== print ===

function printDemonstration(value)
fprintf('\nVAWLUME synthetic Phase 6 native caller-estimator demonstration\n');
fprintf('%s\n', value.calibration_boundary);
fprintf('\nMicrophones (%s): a at (%g, %g), b at (%g, %g); channel gains %g and %g\n', ...
    value.geometry.frame, value.geometry.microphones_cm(1, :), ...
    value.geometry.microphones_cm(2, :), value.geometry.channel_gains);
fprintf('Audio clock: %s. Tracking clock: %s.\n', value.geometry.audio_clock, ...
    value.geometry.tracking_clock);
fprintf('Channel-response estimates from the reference noise (band power):\n');
disp(value.response_estimates);

fprintf('Estimator dry run: %s; wrote nothing: %d; would write %d targets, %d candidates, %d evidence rows\n', ...
    value.preview.status, value.preview.wrote_nothing, ...
    value.preview.planned_counts.attribution_targets, ...
    value.preview.planned_counts.attribution_candidates, ...
    value.preview.planned_counts.attribution_evidence);
fprintf('Applied: %s, attribution run %d, in one transaction\n', value.applied.status, ...
    value.applied.attribution_run_id);

c = value.five_conditions;
fprintf('\nThe five conditions, read from the stored profile %s (%s; checksum matches registration: %d):\n', ...
    c.profile, c.content_uri, c.checksum_matches_registration);
fprintf(' 1. Dimensions used and their roles:\n');
disp(c.dimensions);
fprintf(' 2. Score: %s, %s. %s\n    It is: %s\n', c.score.unit, c.score.orientation, ...
    c.score.meaning, strjoin(c.score.what_this_is_not, '; '));
fprintf(' 3. Scaling. Acoustic: %s\n    Pose: %s\n    Comparable %s: %s\n', ...
    c.scaling.acoustic, c.scaling.pose_localization, c.scaling.comparability_scope, ...
    c.scaling.comparability_justification);
fprintf(' 4. Readability: %s\n', c.readability.reconstruction);
fprintf(' 5. Calibration: %s. Evidence basis: %s\n    Calibration requires: %s\n', ...
    c.calibration_status.state, c.calibration_status.evidence_basis, ...
    c.calibration_status.calibration_requires);

fprintf('\nThe six scenes: raw and normalized level differences (a over b, dB), scores, decisions:\n');
disp(value.scenes(:, ["scene", "detection_id", "raw_difference_db", ...
    "normalized_difference_db", "candidate_1", "candidate_2", "decision"]));
for k = 1:height(value.scenes)
    fprintf('  %-15s %s\n', value.scenes.scene(k), value.scenes.built_how(k));
end
fprintf('  The raw differences carry channel b''s 6 dB lower gain; the normalized ones do not.\n');
fprintf('Score semantics: %s\n', strjoin(value.score_semantics, ' | '));

fprintf('\nCandidates as stored (an unscored candidate states its reason):\n');
disp(value.candidates);

fprintf('Evidence of the separable target, one dimension per row, each with its citation:\n');
disp(value.evidence.separable_target);
fprintf('Evidence by dimension (no total, no combined value):\n');
disp(value.evidence.by_dimension);

fprintf('Reconstruction: the separable target''s scores recomputed from read-back rows only:\n');
disp(value.reconstruction);

m = value.mismatch;
fprintf('\nMODEL MISMATCH. A generated this call. Predictions: A %.2f dB, B %.2f dB.\n', ...
    m.predicted_a_db, m.predicted_b_db);
fprintf('  Unmodelled directivity of %+.0f dB at microphone a gives an observation of %.2f dB.\n', ...
    m.unmodelled_bias_db, m.observed_db);
fprintf('  Scores: A %.2f dB, B %.2f dB. The generating animal ranks first: %d.\n', ...
    m.score_a, m.score_b, m.generating_entity_ranked_first);
fprintf('  Decision: %s; it selected the generating animal: %d. Tolerance here: %.2f dB.\n', ...
    m.decision, m.selected_generating_entity, m.tolerance_db);
fprintf('  %s\n', m.meaning);

fprintf('\nDecisions under the native policy (%s %s, rule %s; selection %g dB, separation %g dB):\n', ...
    value.policy.profile_key, value.policy.version_label, value.policy.rule_key, ...
    value.policy.selection_threshold, value.policy.separation_margin);
disp(value.decisions);

fprintf('Read-back grain, so nothing is counted from the wrong table:\n');
disp(value.report.grain);
fprintf('Declared inputs of the native run:\n');
disp(value.report.declared_inputs);
fprintf('Unscored candidates by reason:\n');
disp(value.report.qc.unscored_candidates_by_reason);
fprintf('Settings profile statements: %s, %s\n', ...
    value.report.qc.settings_profile_statements.calibration_status, ...
    value.report.qc.settings_profile_statements.comparability_scope);
fprintf('QC note: %s\n', value.report.qc_note);

fprintf('\nRefusals demonstrated beside the successes:\n');
disp(value.refusals);

fprintf('Database inventory:\n');
disp(value.database_inventory);
fprintf('Foreign-key violations: %d; temporary artifacts removed: %d\n', ...
    height(value.foreign_key_check), value.temporary_artifacts_removed);
fprintf('Proves:\n  %s\n', strjoin(value.proves, '\n  '));
fprintf('Does not prove:\n  %s\n', strjoin(value.does_not_prove, '\n  '));
end

% ========================================================= session helpers ===

function value = audioClock(session)
value = struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
    audio_alignment_run_id=session.audio_run);
end

function value = streamRef()
value = struct(project_key="synthetic_alignment_session", stream_name="arena_tracking");
end

function value = videoTimeOf(conn, session, audioTime)
reference = vawlume.alignment.applyTransform(conn, session.audio_run, audioTime);
value = (reference - session.video_offset) / session.video_scale;
end

function region = videoAround(conn, session, audioTime, halfWidth)
center = videoTimeOf(conn, session, audioTime);
region = [center - halfWidth, center + halfWidth];
end

function [x, y] = truePosition(track, videoTime)
% track0 moves slowly near microphone a. track1 and track2 run along x = 50, the
% perpendicular bisector of the microphones, so each is equidistant from both.
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

function writeTrackingCsv(path, regions)
lines = "time_s,subject,bodypart,x,y,likelihood";
for r = 1:height(regions)
    times = (ceil(regions(r, 1) * 30):floor(regions(r, 2) * 30))' / 30;
    for t = times'
        for track = ["track0", "track1", "track2"]
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

% ================================================================= helpers ===

function writeText(pathValue, value)
fileId = fopen(pathValue, "w");
if fileId < 0
    error("vawlume:examples:FixtureCreationFailed", ...
        "Could not create demonstration input: %s", pathValue);
end
cleanupFile = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", value);
clear cleanupFile
end

function root = normalizedRepoRoot(root)
if strlength(root) == 0
    root = fileparts(fileparts(mfilename("fullpath")));
end
try
    root = string(java.io.File(char(root)).getCanonicalPath());
catch
    root = string(root);
end
end

function value = pathContains(target)
value = any(split(string(path), pathsep) == string(target));
end

function restoreSourcePath(sourcePath, shouldRemove)
if shouldRemove && pathContains(sourcePath), rmpath(sourcePath); end
end

function closeConnection(conn)
try
    if isopen(conn), close(conn); end
catch
end
end

function removeTree(root)
try
    if isfolder(root), rmdir(root, "s"); end
catch
end
end
