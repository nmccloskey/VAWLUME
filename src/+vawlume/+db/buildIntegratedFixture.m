function [fixture, cleanup] = buildIntegratedFixture(options)
%BUILDINTEGRATEDFIXTURE Build the shared Phase 7 integrated session through the public API.
%
% [FIXTURE, CLEANUP] = vawlume.db.buildIntegratedFixture() builds, in a fresh
% disposable directory, one synthetic dyadic session that carries everything a
% cross-path or cross-event-set comparison needs, and returns an open connection
% to its database together with a manifest of every identifier a consumer needs.
% Delete or clear CLEANUP (an onCleanup object) to close the connection and
% remove every file the build wrote.
%
% WHAT IT BUILDS, every row through a public function (no direct SQL write):
%
%   * project intake of two recordings of one dyad (two animals, A and B):
%     "session", a two-channel recording, and "secondmic", a one-channel file
%     standing for a real rig's separately started microphone;
%   * DeepSqueak, MUPET and USVSEG imports of the session, each carrying one
%     real-shape token: MUPET's terminal "_" interval, a USVSEG NaN feature, and
%     a DeepSqueak zero-height box; a USVSEG import of the second microphone;
%   * three pairwise matching analyses under the tracked specification, one
%     arbitrary-N agreement analysis, and the consensus events they derive, with
%     a one_to_many, a many_to_one and an extractor-specific miss;
%   * two alignment sets onto one neural reference clock: the audio clock
%     affine from three anchors with about 200 ppm drift, the tracking (video)
%     clock piecewise affine with a declared breakpoint and no anchor beyond its
%     fourth, so a call there reaches tracking only by extrapolation;
%   * a declared frame, two placed channels, tracking registered in the frame,
%     and time-valid identity associations including a swap;
%   * a noise reference family AND a tone reference family in the call band,
%     measured on both channels and aggregated into one response estimate run;
%   * per call, a call-window measurement and a band-matched normalization;
%   * native runs over DeepSqueak detections and over DeepSqueak-MUPET
%     consensus events, an imported run and a backend run over the same
%     detections, each decided under its policy.
%
% THE SCENES (audio-native seconds), one call each unless stated:
%
%   separable        30.0   A near microphone a, B on the bisector
%   unfittable       31.2   8 dB louder at b, which neither position predicts
%   model_mismatch   31.5   A's prediction minus 10 dB of unmodelled directivity
%   coverage_gap     60.0   identity clear, no tracking sample
%   symmetric        70.0   both animals on the bisector
%   identity_swap    110.0  the two tracks swap identities mid-call
%   out_of_bracket   160.0  tracking samples beyond the tracking clock's anchors
%   split            140.0  MUPET reports one DeepSqueak call as two
%   merge            145.0  DeepSqueak reports one USVSEG call as two
%   miss             150.0  MUPET reports nothing
%
% EVERYTHING IS SYNTHETIC AND CIRCULAR. The imported and backend inputs are
% claims this builder wrote; the separable and symmetric calls follow the native
% method's own spreading assumption. Agreement between paths here shows that the
% machinery joins correctly, never that any path is accurate. The manifest
% repeats this in manifest.boundary.
%
% Name-value options:
%   Root      directory to build in; must not exist yet or be empty. Default: a
%             new directory under tempdir
%   RepoRoot  repository root, inferred from this file by default
%
% FIXTURE fields: conn, database_path, root, repo_root, manifest.
%
% See also VAWLUME.DB.BUILDPHASE1FIXTURE, VAWLUME.ESTIMATOR.ATTRIBUTECALLERS,
% VAWLUME.ATTRIBUTION.REPORT

arguments
    options.Root (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
root = options.Root;
if strlength(root) == 0
    root = string(fullfile(tempdir, "vawlume_integrated_fixture_" + ...
        string(java.util.UUID.randomUUID)));
end
if isfolder(root) && numel(dir(root)) > 2
    error("vawlume:db:FixtureRootNotEmpty", ...
        "The fixture root must not exist yet or be empty: %s", root);
end
if ~isfolder(root), mkdir(root); end
databasePath = fullfile(root, "integrated_fixture.sqlite");
conn = sqlite(char(databasePath), "create");
cleanup = onCleanup(@() removeFixture(conn, root));

g = generator();
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);

session = establishSession(conn, root, repoRoot, g);
extractors = importExtractors(conn, root, repoRoot, session, g);
correspondence = relateExtractors(conn, repoRoot, session, extractors, g);
clocks = alignClocks(conn, root, repoRoot, session, g);
space = declareSpace(conn, root, repoRoot, session, clocks, g);
acoustic = measureAcoustics(conn, repoRoot, session, extractors, correspondence, g);
attribution = attributeAllPaths(conn, root, repoRoot, session, extractors, ...
    correspondence, clocks, space, acoustic, g);

manifest = struct( ...
    project_key=session.project_key, ...
    recording_id=session.recording_id, ...
    second_microphone_recording_id=session.second_recording_id, ...
    entities=session.entities, ...
    extraction_runs=extractors.runs, ...
    scenes=sceneManifest(g, extractors, correspondence, attribution), ...
    correspondence=correspondence.manifest, ...
    real_shape_tokens=extractors.tokens, ...
    alignment=clocks.manifest, ...
    tracking=space.manifest, ...
    acoustic=acoustic.manifest, ...
    runs=attribution.runs, ...
    profiles=attribution.profiles, ...
    artifacts=artifactManifest(root), ...
    csv_values=struct(project_description=session.description, ...
        note="The project description carries a non-ASCII character and an " + ...
            "embedded newline, for the CSV export audit."), ...
    boundary="Every value here is synthetic. The imported and backend claims " + ...
        "were written by this builder, and the separable and symmetric calls " + ...
        "follow the native method's own spreading assumption. Agreement " + ...
        "between paths on this fixture is circular: it shows that the machinery " + ...
        "joins correctly, never that any path is accurate.");

fixture = struct(conn=conn, database_path=string(databasePath), root=root, ...
    repo_root=repoRoot, manifest=manifest);
end

% ============================================================== generator ===

function g = generator()
%GENERATOR The synthetic truth every artifact is written from.
%
% Clocks are generated from the neural (reference) clock. These are the
% GENERATOR's own parameters, used only to write the synthetic anchor tables. No
% stored transform is read or applied here; once the anchors are registered,
% every placement goes through vawlume.alignment.
g = struct();
g.rate = 1000;
g.duration_s = 200;
g.band_hz = [200 300];
g.call_hz = 250;
g.gains = [1 0.5];
g.mics = [0 0; 100 0];

% Audio: reference = (1 + 200e-6) * audio + 3 s.
g.audio_drift = 1.0002;
g.audio_intercept = 3.0;
% Video: two regimes around a knot placed at the reference time of audio 70 s.
g.video_slopes = [0.9995; 1.0010];
g.video_intercept_first = 18.0;
g.sync_audio = [10; 50; 90; 130; 190];
g.audio_observed = logical([1 0 1 0 1]);
g.video_observed = logical([1 1 1 1 0]);

reference = g.audio_drift * g.sync_audio + g.audio_intercept;
knotReference = g.audio_drift * 70 + g.audio_intercept;
g.video_knot = (knotReference - g.video_intercept_first) / g.video_slopes(1);
intercepts = [g.video_intercept_first; ...
    knotReference - g.video_slopes(2) * g.video_knot];
video = zeros(size(reference));
for k = 1:numel(reference)
    regime = 1 + double(reference(k) >= knotReference);
    video(k) = (reference(k) - intercepts(regime)) / g.video_slopes(regime);
end
g.sync_reference = reference;
g.sync_video = video;

% Attribution scenes: one call each, A and B stationary in arena centimetres.
g.scenes = table( ...
    ["separable"; "unfittable"; "model_mismatch"; "coverage_gap"; "symmetric"; ...
        "identity_swap"; "out_of_bracket"], ...
    [30.0; 31.2; 31.5; 60.0; 70.0; 110.0; 160.0], ...
    [30.1; 31.3; 31.6; 60.1; 70.1; 110.2; 160.1], ...
    ["separable"; "separable"; "separable"; "none"; "symmetric"; "swap"; ...
        "separable"], ...
    [0; 0; -10; 0; 0; 0; 0], ...
    ["generated from A's distances under spherical spreading"; ...
     "8 dB louder at microphone b, which neither position predicts"; ...
     "A's spherical prediction minus 10 dB of directivity the method does not " + ...
         "model; B, on the bisector, then fits within the selection threshold"; ...
     "identity is clear, but the tracker recorded no sample during the call"; ...
     "both animals on the perpendicular bisector; the call is equally loud at both"; ...
     "the two tracks swap identities during the call"; ...
     "the tracking samples lie beyond the tracking clock's last anchor"], ...
    VariableNames=["scene", "start_s", "end_s", "layout", "bias_db", "built_how"]);
% Tracking regions, audio seconds, and who stands where.
g.regions = table( ...
    ["separable"; "symmetric"; "swap"; "out_of_bracket"], ...
    [29.5; 69.5; 109.5; 159.5], [32.5; 70.6; 110.7; 160.6], ...
    VariableNames=["region", "start_s", "end_s"]);
g.positions = struct( ...
    separable=struct(track0=[10 20], track1=[50 20]), ...
    symmetric=struct(track1=[50 20], track2=[50 60]), ...
    swap=struct(track0=[10 20], track1=[50 20]), ...
    out_of_bracket=struct(track0=[10 20], track1=[50 20]));
g.swap_at_s = 110.1;

% Extractor-only correspondence scenes.
g.structure = table(["split"; "merge"; "miss"], [140.0; 145.0; 150.0], ...
    ["one_to_many"; "many_to_one"; "unmatched_left"], ...
    ["deepsqueak_mupet"; "deepsqueak_usvseg"; "deepsqueak_mupet"], ...
    ["MUPET reports one DeepSqueak call as two detections"; ...
     "DeepSqueak reports one USVSEG call as two detections"; ...
     "DeepSqueak and USVSEG report a call MUPET does not"], ...
    VariableNames=["scene", "start_s", "expected_unit", "pair", "built_how"]);

% Synthetic claims, by scene: [A score, B score] and probabilities.
g.imported_scores = [0.10 0.90; 0.40 0.35; 0.70 0.20; 0.80 0.10; 0.88 0.84; ...
    0.55 0.50; 0.75 0.20];
g.backend_scores = [0.92 0.15; 0.30 0.28; 0.65 0.25; 0.85 0.10; 0.60 0.58; ...
    0.50 0.45; 0.70 0.30];
end

% ================================================================ session ===

function session = establishSession(conn, root, repoRoot, g)
sourceRoot = fullfile(root, "project");
dyad = fullfile(sourceRoot, "cohort_01", "dyad_004");
mkdir(dyad);
sessionWav = fullfile(dyad, "D004_M012_F031_session.wav");
secondWav = fullfile(dyad, "D004_M012_F031_secondmic.wav");
writeSessionAudio(sessionWav, g);
writeSecondMicrophone(secondWav, g);

profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
ir = vawlume.source_mapping.parse(profilePath, sourceRoot, ...
    ProfileId="example.project.social_dyad.multi_subject", RepoRoot=repoRoot);
description = "Synthetic integrated session " + char(8212) + ...
    " the Phase 7 shared fixture." + newline + ...
    "Every value is generated; nothing here is a measurement.";
intake = vawlume.ingest.project(conn, ir, struct( ...
    project_key="phase7_integrated_session", ...
    project_name="Phase 7 integrated validation session", ...
    description=description), Apply=true, RepoRoot=repoRoot);
mustCommit(intake, "Project intake");

recordings = fetch(conn, "SELECT r.recording_id, sf.relative_path, " + ...
    "IFNULL(r.native_recording_id,'') AS native_recording_id " + ...
    "FROM recordings r JOIN source_files sf ON sf.source_file_id = r.source_file_id " + ...
    "ORDER BY r.recording_id");
paths = string(recordings.relative_path);
sessionRow = endsWith(paths, "_session.wav");
secondRow = endsWith(paths, "_secondmic.wav");
entities = fetch(conn, "SELECT e.entity_id, e.native_id FROM experimental_entities e " + ...
    "JOIN recording_entity_links rel ON rel.entity_id = e.entity_id " + ...
    "WHERE rel.recording_id = " + string(double(recordings.recording_id(sessionRow))) + ...
    " ORDER BY e.entity_id");
native = string(entities.native_id);
session = struct( ...
    project_key="phase7_integrated_session", ...
    description=description, ...
    source_root=string(sourceRoot), ...
    recording_id=double(recordings.recording_id(sessionRow)), ...
    second_recording_id=double(recordings.recording_id(secondRow)), ...
    relative_path=paths(sessionRow), ...
    native_recording_id=string(recordings.native_recording_id(sessionRow)), ...
    second_native_recording_id=string(recordings.native_recording_id(secondRow)), ...
    A=double(entities.entity_id(native == "M012")), ...
    B=double(entities.entity_id(native == "F031")), ...
    linked_entities=table(double(entities.entity_id), native, ...
        VariableNames=["entity_id", "native_id"]));
session.entities = struct(A=session.A, B=session.B, A_native_id="M012", ...
    B_native_id="F031", note="A is the male partner and B the female partner " + ...
    "by the project's own naming; the scenes use A and B only.");
end

% ============================================================= extractors ===

function value = importExtractors(conn, root, repoRoot, session, g)
recordingRef = struct(recording_id=session.recording_id);
calls = [g.scenes.start_s, g.scenes.end_s];

% DeepSqueak: every attribution call, the split call whole, the merge call as
% two, and the miss. The last file row, the miss call at 150 s, is a
% zero-height box.
ds = [calls; 140.0 140.2; 145.0 145.10; 145.15 145.25; 150.0 150.1];
dsRoot = fullfile(root, "deepsqueak");
dsPath = fullfile(dsRoot, "exports", "D004_session_Stats.xlsx");
writeDeepSqueak(dsPath, ds);
dsResult = vawlume.ingest.deepsqueak(conn, string(dsPath), recordingRef, ...
    struct(run_key="p7-ds", extractor_version="3.2.1"), ...
    RepoRoot=repoRoot, ArtifactRoot=string(dsRoot), Apply=true);
mustCommit(dsResult, "DeepSqueak import");

% MUPET: every attribution call (slightly late), the split call as two, the
% merge call whole, no miss call. The final row's interval is the terminal "_".
mu = [calls + 0.002; 140.0 140.09; 140.11 140.2; 145.0 145.25];
muRoot = fullfile(root, "mupet");
muPath = fullfile(muRoot, "CSV", "D004_session.csv");
configPath = fullfile(muRoot, "config.csv");
writeMupet(muPath, mu);
writeLinesTo(configPath, mupetConfig());
muResult = vawlume.ingest.mupet(conn, string(muPath), recordingRef, ...
    struct(run_key="p7-mupet", extractor_version="2.1", ...
    settings=struct(config_path=string(configPath))), ...
    RepoRoot=repoRoot, ArtifactRoot=string(muRoot), Apply=true);
mustCommit(muResult, "MUPET import");

% USVSEG: every attribution call (slightly early), the split call whole, the
% merge call whole, the miss. One row has maxfreq NaN.
us = [calls - 0.002; 140.0 140.2; 145.0 145.25; 150.0 150.1];
usRoot = fullfile(root, "usvseg");
usPath = fullfile(usRoot, "D004_session_dat.csv");
writeUsvseg(usPath, us, 5);
usResult = vawlume.ingest.usvseg(conn, string(usPath), recordingRef, ...
    struct(run_key="p7-usvseg", extractor_version="0.9r2"), ...
    RepoRoot=repoRoot, ArtifactRoot=string(usRoot), Apply=true);
mustCommit(usResult, "USVSEG import");

% The second microphone's own extractor output.
secondPath = fullfile(usRoot, "D004_secondmic_dat.csv");
writeUsvseg(secondPath, [30.0 30.1; 70.0 70.1], 0);
secondResult = vawlume.ingest.usvseg(conn, string(secondPath), ...
    struct(recording_id=session.second_recording_id), ...
    struct(run_key="p7-usvseg-secondmic", extractor_version="0.9r2"), ...
    RepoRoot=repoRoot, ArtifactRoot=string(usRoot), Apply=true);
mustCommit(secondResult, "USVSEG import of the second microphone");

value = struct();
value.runs = struct(deepsqueak="p7-ds", mupet="p7-mupet", usvseg="p7-usvseg", ...
    usvseg_second_microphone="p7-usvseg-secondmic");
value.ds = detectionsOf(conn, "p7-ds");
value.mupet = detectionsOf(conn, "p7-mupet");
value.usvseg = detectionsOf(conn, "p7-usvseg");
value.usvseg_second = detectionsOf(conn, "p7-usvseg-secondmic");
value.tokens = struct( ...
    mupet_terminal_interval=struct(run_key="p7-mupet", ...
        detection_id=value.mupet.detection_id(end), raw_token="_", ...
        field="inter-syllable interval (sec)"), ...
    usvseg_nan=struct(run_key="p7-usvseg", ...
        detection_id=value.usvseg.detection_id(5), raw_token="NaN", ...
        field="maxfreq"), ...
    deepsqueak_zero_height=struct(run_key="p7-ds", ...
        detection_id=idsNear(value.ds, 150.0), ...
        note="Low Freq equals High Freq and Delta Freq is 0, stored literally"));
end

function rows = detectionsOf(conn, runKey)
rows = fetch(conn, "SELECT d.detection_id, d.start_time_s, d.end_time_s " + ...
    "FROM detections d JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "WHERE er.run_key = '" + runKey + "' ORDER BY d.start_time_s, d.detection_id");
rows.detection_id = double(rows.detection_id);
rows.start_time_s = double(rows.start_time_s);
rows.end_time_s = double(rows.end_time_s);
end

% ========================================================= correspondence ===

function value = relateExtractors(conn, repoRoot, session, extractors, g)
recordingRef = struct(recording_id=session.recording_id);
specPath = fullfile(repoRoot, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json");
pairs = ["p7-match-ds-mupet", "p7-ds", "p7-mupet"; ...
    "p7-match-ds-usvseg", "p7-ds", "p7-usvseg"; ...
    "p7-match-mupet-usvseg", "p7-mupet", "p7-usvseg"];
ids = zeros(3, 1);
for k = 1:3
    result = vawlume.matching.compare(conn, recordingRef, ...
        struct(run_a=pairs(k, 2), run_b=pairs(k, 3)), ...
        struct(run_key=pairs(k, 1), profile_path=string(specPath)), ...
        RepoRoot=repoRoot, Apply=true);
    mustCommit(result, "Matching " + pairs(k, 1));
    ids(k) = double(result.analysis.analysis_run_id);
end
composed = vawlume.agreement.compose(conn, recordingRef, pairs(:, 1), ...
    struct(run_key="p7-agreement", run_label="Three-extractor agreement"), ...
    RepoRoot=repoRoot, Apply=true);
if ~composed.committed
    error("vawlume:db:FixtureBuildFailed", "Agreement composition did not commit: %s", ...
        string(composed.status));
end

% Consensus events of the DeepSqueak-MUPET analysis that cover the calls.
consensus = fetch(conn, "SELECT ce.consensus_event_id, ce.start_time_s, ce.end_time_s " + ...
    "FROM consensus_events ce WHERE ce.analysis_run_id = " + string(ids(1)) + ...
    " ORDER BY ce.start_time_s");
consensus.consensus_event_id = double(consensus.consensus_event_id);
consensus.start_time_s = double(consensus.start_time_s);
consensus.end_time_s = double(consensus.end_time_s);
sceneConsensus = NaN(height(g.scenes), 1);
for k = 1:height(g.scenes)
    hit = consensus.start_time_s < g.scenes.end_s(k) & ...
        consensus.end_time_s > g.scenes.start_s(k);
    if nnz(hit) == 1
        sceneConsensus(k) = consensus.consensus_event_id(hit);
    end
end
if any(isnan(sceneConsensus))
    error("vawlume:db:FixtureBuildFailed", ...
        "Not every attribution call has exactly one DeepSqueak-MUPET consensus event.");
end

value = struct();
value.analysis_ids = struct(ds_mupet=ids(1), ds_usvseg=ids(2), mupet_usvseg=ids(3), ...
    agreement=double(composed.analysis.analysis_run_id));
value.scene_consensus_event_ids = sceneConsensus;
value.manifest = struct( ...
    matching_analyses=table(pairs(:, 1), pairs(:, 2), pairs(:, 3), ids, ...
        VariableNames=["run_key", "run_a", "run_b", "analysis_run_id"]), ...
    agreement=struct(run_key="p7-agreement", ...
        analysis_run_id=value.analysis_ids.agreement), ...
    consensus_source=struct(run_key="p7-match-ds-mupet", analysis_run_id=ids(1), ...
        note="Consensus targets of the native consensus run come from this analysis."), ...
    structure=structureManifest(g, extractors, value.analysis_ids));
end

function value = structureManifest(g, extractors, analysisIds)
dsIds = cell(height(g.structure), 1);
otherIds = cell(height(g.structure), 1);
analysis = zeros(height(g.structure), 1);
for k = 1:height(g.structure)
    t = g.structure.start_s(k);
    dsIds{k} = idsNear(extractors.ds, t);
    switch g.structure.pair(k)
        case "deepsqueak_mupet"
            otherIds{k} = idsNear(extractors.mupet, t);
            analysis(k) = analysisIds.ds_mupet;
        otherwise
            otherIds{k} = idsNear(extractors.usvseg, t);
            analysis(k) = analysisIds.ds_usvseg;
    end
end
value = table(g.structure.scene, g.structure.expected_unit, g.structure.pair, ...
    analysis, dsIds, otherIds, g.structure.built_how, VariableNames=["scene", ...
    "expected_unit", "pair", "analysis_run_id", "left_detection_ids", ...
    "right_detection_ids", "built_how"]);
value.note = repmat("left is DeepSqueak; units follow contract 07 D3", ...
    height(value), 1);
end

function ids = idsNear(rows, t)
ids = rows.detection_id(rows.start_time_s >= t - 0.01 & rows.start_time_s < t + 0.5)';
end

% ================================================================= clocks ===

function value = alignClocks(conn, root, repoRoot, session, g)
alignmentRoot = fullfile(root, "alignment");
mkdir(alignmentRoot);
% Set 1: the audio clock, affine, three anchors.
audioKey = "p7_audio_clock";
writeAnchorSet(alignmentRoot, "audio", g.sync_audio, g.sync_reference, ...
    g.audio_observed, "a_sync");
audioManifest = writeAlignmentManifest(alignmentRoot, repoRoot, session, audioKey, ...
    "affine", "audio", "audio_native", "audio_sample_clock", true);
vawlume.ingest.alignment(conn, audioManifest, RepoRoot=repoRoot, ...
    SourceRoot=string(alignmentRoot), Apply=true);
vawlume.alignment.fit(conn, struct(project_key=session.project_key, ...
    run_key=audioKey), SourceTimebase="audio_native", Apply=true);
% Set 2: the tracking (video) clock, piecewise, four anchors, none past the fourth.
videoKey = "p7_tracking_clock";
writeAnchorSet(alignmentRoot, "video", g.sync_video, g.sync_reference, ...
    g.video_observed, "v_sync");
videoManifest = writeAlignmentManifest(alignmentRoot, repoRoot, session, videoKey, ...
    "piecewise_affine", "video", "video_native", "video_frame_clock", false);
vawlume.ingest.alignment(conn, videoManifest, RepoRoot=repoRoot, ...
    SourceRoot=string(alignmentRoot), Apply=true);
vawlume.alignment.fit(conn, struct(project_key=session.project_key, ...
    run_key=videoKey), SourceTimebase="video_native", Breakpoints=g.video_knot, ...
    Apply=true);

value = struct();
value.audio_run = runIdFor(conn, session.project_key, audioKey, "audio_native");
value.video_run = runIdFor(conn, session.project_key, videoKey, "video_native");
value.manifest = struct( ...
    reference_timebase="neural_native", ...
    audio=struct(alignment_key=audioKey, alignment_run_id=value.audio_run, ...
        method="affine", anchors=nnz(g.audio_observed), drift_ppm=200, ...
        anchored_audio_s=[min(g.sync_audio(g.audio_observed)), ...
            max(g.sync_audio(g.audio_observed))]), ...
    tracking=struct(alignment_key=videoKey, alignment_run_id=value.video_run, ...
        method="piecewise_affine", anchors=nnz(g.video_observed), ...
        breakpoint_video_s=g.video_knot, ...
        anchored_through_audio_s=max(g.sync_audio(g.video_observed)), ...
        note="A call later than this audio time reaches tracking only by " + ...
            "extrapolation, so its bracket_extrapolated flag is true."));
end

function writeAnchorSet(folder, streamName, nativeTimes, referenceTimes, observed, prefix)
markers = strings(0, 1);
streams = strings(0, 1);
stamps = strings(0, 1);
for k = 1:numel(nativeTimes)
    if ~observed(k), continue, end
    key = prefix + compose("%02d", k);
    markers = [markers; key; key]; %#ok<AGROW>
    streams = [streams; streamName; "neural"]; %#ok<AGROW>
    stamps = [stamps; compose("%.9f", nativeTimes(k)); ...
        compose("%.9f", referenceTimes(k))]; %#ok<AGROW>
end
count = numel(markers);
writetable(table(markers, streams, stamps, repmat("primary", count, 1), ...
    repmat("true", count, 1), repmat("0.002", count, 1), ...
    repmat("device_level", count, 1), VariableNames=["marker", "stream", ...
    "timestamp_s", "role", "include", "uncertainty_s", "evidence_class"]), ...
    fullfile(folder, streamName + "_anchors.csv"), QuoteStrings="minimal");
end

function manifestPath = writeAlignmentManifest(folder, repoRoot, session, key, ...
        method, streamName, timebaseKey, timebaseKind, recordingNative)
profile = jsondecode(fileread(fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "alignment_anchors", "long_anchor_mapping_profile.json")));
profile.profile.id = "vawlume.alignment.anchor.long.phase7_" + streamName + ".v1";
profile.profile.name = "Phase 7 fixture " + streamName + " anchor profile";
profile.context.declared_timebases = {char(timebaseKey); 'neural_native'};
mapping = profile.context.stream_timebases(1);
mapping.native_value = streamName;
mapping.stream_key = streamName + "_sync";
mapping.timebase_key = timebaseKey;
neural = mapping;
neural.native_value = "neural";
neural.stream_key = "neural_sync";
neural.timebase_key = "neural_native";
profile.context.stream_timebases = [mapping; neural];
pair = profile.context.fit_pairs(1);
pair.source_timebase_key = timebaseKey;
pair.reference_timebase_key = "neural_native";
profile.context.fit_pairs = pair;
profilePath = fullfile(folder, streamName + "_anchor_profile.json");
writeTextTo(profilePath, string(jsonencode(profile, PrettyPrint=true)) + newline);

source = struct(timebase_key=timebaseKey, timebase_kind=timebaseKind, ...
    recording_native=recordingNative, native_unit="s", ...
    origin_description="Synthetic " + streamName + " clock start.");
if ~recordingNative
    source.nominal_rate_hz = 30;
end
document = struct();
document.manifest = struct(manifest_schema_version="0.1-draft", ...
    manifest_version="0.1.0", alignment_key=key, ...
    label="Phase 7 fixture " + streamName + " clock", ...
    notes="Synthetic. No clock here is a real device.");
document.session = struct(project_key=session.project_key, ...
    recording=struct(source_relative_path=session.relative_path));
document.reference_timebase = "neural_native";
document.method = method;
document.timebases = {source, struct(timebase_key="neural_native", ...
    timebase_kind="acquisition_clock", scope="project", recording_native=false, ...
    native_unit="s", nominal_rate_hz=30000, clock_identifier="ACQ_FIXTURE", ...
    origin_description="Synthetic acquisition clock start.")};
document.anchors = struct(source=streamName + "_anchors.csv", ...
    mapping_profile=char(profilePath), file_role="alignment_anchor_table");
manifestPath = string(fullfile(folder, streamName + "_alignment_manifest.json"));
writeTextTo(manifestPath, string(jsonencode(document, PrettyPrint=true)) + newline);
end

function id = runIdFor(conn, projectKey, alignmentKey, timebaseKey)
qc = vawlume.alignment.report(conn, struct(project_key=projectKey, run_key=alignmentKey));
transform = qc.transforms(qc.transforms.source_timebase_key == timebaseKey, :);
if height(transform) ~= 1 || string(transform.status(1)) ~= "estimated"
    error("vawlume:db:FixtureBuildFailed", ...
        "Alignment %s did not produce one estimated transform for %s.", ...
        alignmentKey, timebaseKey);
end
id = double(transform.alignment_run_id(1));
end

% ================================================================== space ===

function value = declareSpace(conn, root, repoRoot, session, clocks, g)
project = struct(project_key=session.project_key);
vawlume.geometry.registerCoordinateSystem(conn, project, struct( ...
    coordinate_system_key="arena_2d", coordinate_system_name="Arena floor plane", ...
    dimensionality=2, unit="cm"));
for channel = 1:2
    vawlume.geometry.registerRecordingChannel(conn, ...
        struct(recording_id=session.recording_id), ...
        struct(channel_index=channel, channel_label="mic_" + char('a' + channel - 1)));
    vawlume.geometry.registerChannelPlacement(conn, ...
        struct(recording_id=session.recording_id), struct(channel_index=channel, ...
        coordinate_system_key="arena_2d", position_x=g.mics(channel, 1), ...
        position_y=g.mics(channel, 2)));
end
vawlume.geometry.registerRecordingChannel(conn, ...
    struct(recording_id=session.second_recording_id), ...
    struct(channel_index=1, channel_label="mic_second"));

trackingRoot = fullfile(root, "tracking");
mkdir(trackingRoot);
writeTracking(conn, fullfile(trackingRoot, "arena_tracking.csv"), clocks, g);
profilePath = fullfile(trackingRoot, "tracking_profile.json");
copyfile(fullfile(repoRoot, "config", "01_mapping_profiles", "tracking", ...
    "generic_tracking_mapping_profile.json"), profilePath);
vawlume.tracking.register(conn, struct(recording_id=session.recording_id), struct( ...
    artifact_path="arena_tracking.csv", profile_path=string(profilePath), ...
    timebase_key="video_native", stream_name="arena_tracking"), ...
    Apply=true, RepoRoot=repoRoot, SourceRoot=string(trackingRoot));
stream = struct(project_key=session.project_key, stream_name="arena_tracking");
associations = registerIdentity(conn, stream, session, clocks, g);
value = struct(stream=stream, source_root=string(trackingRoot), ...
    associations=associations);
value.manifest = struct(stream_name="arena_tracking", frame="arena_2d (cm)", ...
    microphones_cm=g.mics, channel_gains=g.gains, associations=associations, ...
    regions=g.regions);
end

function writeTracking(conn, path, clocks, g)
lines = "time_s,subject,bodypart,x,y,likelihood";
for r = 1:height(g.regions)
    window = videoTimes(conn, clocks, [g.regions.start_s(r); g.regions.end_s(r)]);
    frames = (ceil(window(1) * 30):floor(window(2) * 30))' / 30;
    layout = g.positions.(g.regions.region(r));
    tracks = string(fieldnames(layout))';
    for t = frames'
        for track = tracks
            xy = layout.(track);
            for part = ["snout", "tail_base"]
                lines(end + 1, 1) = compose("%.9f", t) + "," + track + "," + part + ...
                    "," + compose("%.6f", xy(1)) + "," + compose("%.6f", xy(2)) + ...
                    ",0.95"; %#ok<AGROW>
            end
        end
    end
end
writelines(lines, path);
end

function value = videoTimes(conn, clocks, audioTimes)
% Audio -> reference -> tracking clock, through the stored transforms only.
reference = vawlume.alignment.applyTransform(conn, clocks.audio_run, audioTimes);
value = vawlume.alignment.applyInverseTransform(conn, clocks.video_run, reference);
end

function value = registerIdentity(conn, stream, session, clocks, g)
spans = [ ...
    "track0", "A", 29.0, 33.0;  "track1", "B", 29.0, 33.0; ...
    "track0", "A", 59.0, 61.0;  "track1", "B", 59.0, 61.0; ...
    "track1", "A", 69.0, 71.0;  "track2", "B", 69.0, 71.0; ...
    "track0", "A", 109.0, g.swap_at_s; "track0", "B", g.swap_at_s, 111.0; ...
    "track1", "B", 109.0, g.swap_at_s; "track1", "A", g.swap_at_s, 111.0; ...
    "track0", "A", 159.0, 161.0; "track1", "B", 159.0, 161.0];
ids = zeros(size(spans, 1), 1);
for k = 1:size(spans, 1)
    window = videoTimes(conn, clocks, [double(spans(k, 3)); double(spans(k, 4))]);
    entity = session.(spans(k, 2));
    result = vawlume.tracking.registerIdentityAssociation(conn, stream, struct( ...
        native_track_id=spans(k, 1), entity_id=entity, ...
        start_time_native=window(1), end_time_native=window(2), ...
        assignment_state="assigned", evidence_kind="manual_assertion"));
    ids(k) = double(result.tracking_identity_association_id);
end
value = table(spans(:, 1), spans(:, 2), double(spans(:, 3)), double(spans(:, 4)), ...
    ids, VariableNames=["native_track_id", "entity", "start_audio_s", ...
    "end_audio_s", "tracking_identity_association_id"]);
end

% =============================================================== acoustic ===

function value = measureAcoustics(conn, repoRoot, session, extractors, ...
        correspondence, g)
recordingRef = struct(recording_id=session.recording_id);
references = table(["noise-1"; "noise-2"; "tone-1"; "tone-2"], ...
    ["noise"; "noise"; "tone"; "tone"], [5.0; 5.4; 6.0; 6.4], [5.4; 5.8; 6.4; 6.8], ...
    VariableNames=["reference_key", "reference_type", "start_s", "end_s"]);
ids = zeros(0, 1);
for k = 1:height(references)
    ref = vawlume.acoustic.registerReference(conn, recordingRef, struct( ...
        reference_key=references.reference_key(k), ...
        reference_type=references.reference_type(k), ...
        start_time_s=references.start_s(k), end_time_s=references.end_s(k), ...
        frequency_min_hz=g.band_hz(1), frequency_max_hz=g.band_hz(2)));
    for channel = 1:2
        measured = vawlume.acoustic.measureReferenceResponse(conn, ...
            struct(acoustic_reference_id=ref.acoustic_reference_id), channel, ...
            SourceRoot=session.source_root, Apply=true, ...
            RunKey="p7-ref-" + references.reference_key(k) + "-ch" + channel);
        ids(end + 1, 1) = measured.derived_measurement_ids( ...
            measured.metrics.metric_key == "acoustic_band_power"); %#ok<AGROW>
    end
end
response = vawlume.acoustic.estimateChannelResponse(conn, recordingRef, ids, ...
    RequiredReferenceTypes=["noise", "tone"], MinReferences=2, Apply=true, ...
    RunKey="p7-response").analysis_run_id;

dsIds = sceneDetections(extractors.ds, g);
detectionRuns = normalizeEach(conn, repoRoot, session, response, ...
    "detection_id", dsIds, "d");
consensusRuns = normalizeEach(conn, repoRoot, session, response, ...
    "consensus_event_id", correspondence.scene_consensus_event_ids, "c");
value = struct(response_run=double(response), detection_runs=detectionRuns, ...
    consensus_runs=consensusRuns);
value.manifest = struct(response_run_id=double(response), references=references, ...
    band_hz=g.band_hz, normalization_policy="config/09_acoustic_normalization_" + ...
        "policies/band_matched_noise_reference_v1.json", ...
    detection_normalization_runs=detectionRuns, ...
    consensus_normalization_runs=consensusRuns, ...
    note="Both a noise family and a tone family are measured in the call band, " + ...
        "so a tone-family normalization variant (contract 07 D6) has estimates " + ...
        "to read. The shipped policy reads the noise family.");
end

function runs = normalizeEach(conn, repoRoot, session, responseRun, field, ids, tag)
callRuns = zeros(numel(ids), 1);
normRuns = zeros(numel(ids), 1);
for k = 1:numel(ids)
    target = struct();
    target.(field) = ids(k);
    call = vawlume.acoustic.measureCallWindow(conn, target, [1 2], ...
        BandHz=[200 300], SourceRoot=session.source_root, Apply=true, ...
        RunKey="p7-call-" + tag + ids(k));
    callRuns(k) = double(call.analysis_run_id);
    normalized = vawlume.acoustic.normalizeCallLevels(conn, ...
        struct(analysis_run_id=call.analysis_run_id), ...
        struct(analysis_run_id=responseRun), RepoRoot=repoRoot, Apply=true, ...
        RunKey="p7-norm-" + tag + ids(k));
    normRuns(k) = double(normalized.analysis_run_id);
end
runs = table(ids(:), callRuns, normRuns, VariableNames=[field, "call_run_id", ...
    "analysis_run_id"]);
end

function ids = sceneDetections(rows, g)
ids = zeros(height(g.scenes), 1);
for k = 1:height(g.scenes)
    ids(k) = rows.detection_id(abs(rows.start_time_s - g.scenes.start_s(k)) < 1e-6);
end
end

% ============================================================ attribution ===

function value = attributeAllPaths(conn, root, repoRoot, session, extractors, ...
        correspondence, clocks, space, acoustic, g)
recordingRef = struct(recording_id=session.recording_id);
dsIds = sceneDetections(extractors.ds, g);
participants = [session.A session.B];

settings = vawlume.estimator.loadSettings(RepoRoot=repoRoot);
settingsVersion = vawlume.db.registerProfileVersion(conn, ...
    struct(project_key=session.project_key), struct( ...
    profile_key=settings.profile_key, profile_name=settings.profile_name, ...
    version_label=settings.version_label, content_path=settings.path, ...
    profile_kind=settings.profile_kind, ...
    profile_schema_version=settings.profile_schema_version), ...
    RepoRoot=repoRoot).profile_version_id;
nativePolicy = string(fullfile(repoRoot, "config", "08_attribution_policies", ...
    "native_level_difference_decision_policy.json"));
clock = struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
    audio_alignment_run_id=clocks.audio_run);
tracking = struct(stream=space.stream, alignment_run_id=clocks.video_run, ...
    source_root=space.source_root);

nativeDs = vawlume.estimator.attributeCallers(conn, recordingRef, struct( ...
    run_key="p7-native-ds", settings_profile_version_id=settingsVersion, ...
    target_set=struct(detection_ids=dsIds'), participating_entity_ids=participants, ...
    clock=clock, tracking=tracking, ...
    normalization_runs=acoustic.detection_runs(:, ["detection_id", "analysis_run_id"])), ...
    Apply=true, RepoRoot=repoRoot);
vawlume.attribution.decide(conn, struct(attribution_run_id=nativeDs.attribution_run_id), ...
    nativePolicy, RepoRoot=repoRoot, Apply=true);

consensusIds = correspondence.scene_consensus_event_ids;
nativeConsensus = vawlume.estimator.attributeCallers(conn, recordingRef, struct( ...
    run_key="p7-native-consensus", settings_profile_version_id=settingsVersion, ...
    target_set=struct(consensus_event_ids=consensusIds'), ...
    participating_entity_ids=participants, clock=clock, tracking=tracking, ...
    normalization_runs=acoustic.consensus_runs(:, ["consensus_event_id", ...
        "analysis_run_id"])), Apply=true, RepoRoot=repoRoot);
vawlume.attribution.decide(conn, ...
    struct(attribution_run_id=nativeConsensus.attribution_run_id), nativePolicy, ...
    RepoRoot=repoRoot, Apply=true);

attributionRoot = fullfile(root, "attribution");
mkdir(attributionRoot);
runSettingsPath = fullfile(attributionRoot, "external_run_settings.json");
writeTextTo(runSettingsPath, "{""note"": ""Synthetic settings of the Phase 7 " + ...
    "fixture's imported and backend runs.""}" + newline);
externalSettings = vawlume.db.registerProfileVersion(conn, ...
    struct(project_key=session.project_key), struct( ...
    profile_key="p7-external-run-settings", ...
    profile_name="Phase 7 fixture external run settings", version_label="1.0.0", ...
    content_path=string(runSettingsPath)), RepoRoot=repoRoot).profile_version_id;

imported = importedRun(conn, attributionRoot, repoRoot, session, dsIds, ...
    externalSettings, g);
backend = backendRun(conn, attributionRoot, repoRoot, session, dsIds, ...
    externalSettings, g);

value = struct();
value.native_ds = nativeDs;
value.native_consensus = nativeConsensus;
value.imported_target_ids = imported.target_ids;
value.backend_target_ids = backend.target_ids;
value.runs = struct( ...
    native_detections=runEntry(conn, "p7-native-ds"), ...
    native_consensus=runEntry(conn, "p7-native-consensus"), ...
    imported=runEntry(conn, "p7-imported"), ...
    backend=runEntry(conn, "p7-backend"));
value.profiles = struct( ...
    estimator_settings_version_id=double(settingsVersion), ...
    external_run_settings_version_id=double(externalSettings), ...
    native_decision_policy=nativePolicy, ...
    imported_decision_policy="config/08_attribution_policies/" + ...
        "prototype_attribution_decision_policy.json (the shipped default)", ...
    normalization_policy=acoustic.manifest.normalization_policy);
end

function value = importedRun(conn, folder, repoRoot, session, dsIds, settingsVersion, g)
template = jsondecode(fileread(fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "attribution", "generic_imported_attribution_profile.json")));
entry = template.profiles(1);
entry.profile.id = "vawlume.attribution.phase7_fixture_imported.v0_1";
entry.profile.name = "Phase 7 fixture synthetic caller export";
entry.profile.profile_version = "0.1.0-fixture";
entry.context.exporting_system = "Synthetic Caller Attribution System";
entry.context.exporting_system_version = "7.0.0";
entry.context.window_timebase_key = "audio_native";
entry.caller_label_resolution.map = [ ...
    struct(caller_label="A", entity_native_id=session.entities.A_native_id); ...
    struct(caller_label="B", entity_native_id=session.entities.B_native_id)];
template.profiles = entry;
profilePath = fullfile(folder, "imported_profile.json");
writeTextTo(profilePath, string(jsonencode(template, PrettyPrint=true)) + newline);

lines = "window_id,start_s,end_s,caller,score,probability";
for k = 1:height(g.scenes)
    for which = 1:2
        score = g.imported_scores(k, which);
        lines(end + 1, 1) = compose("w%02d,%.3f,%.3f,%s,%.2f,%.2f", k, ...
            g.scenes.start_s(k) - 0.005, g.scenes.end_s(k) + 0.005, ...
            char('A' + which - 1), score, score); %#ok<AGROW>
    end
end
exportPath = fullfile(folder, "imported_export.csv");
writeLinesTo(exportPath, lines);

created = vawlume.attribution.createRun(conn, struct(recording_id=session.recording_id), ...
    struct(run_key="p7-imported", attribution_path="imported", ...
    method="Synthetic Caller Attribution System 7.0.0", ...
    settings_profile_version_id=settingsVersion, ...
    target_set=struct(detection_ids=dsIds'), ...
    participating_entity_ids=[session.A session.B], ...
    sources=struct(source_file_ids=sourceFileOf(conn, session))), Apply=true);
runRef = struct(attribution_run_id=double(created.run.attribution_run_id));
vawlume.ingest.attribution(conn, runRef, string(exportPath), ...
    ProfilePath=string(profilePath), RepoRoot=repoRoot, Apply=true);
vawlume.attribution.correspondWindows(conn, runRef, SameClock=true, ...
    RepoRoot=repoRoot, Apply=true);
promoteClaims(conn, double(created.targets.attribution_target_id)', true);
vawlume.attribution.decide(conn, runRef, struct(), RepoRoot=repoRoot, Apply=true);
value = struct(target_ids=double(created.targets.attribution_target_id));
end

function value = backendRun(conn, folder, repoRoot, session, dsIds, settingsVersion, g)
template = jsondecode(fileread(fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "attribution", "generic_backend_attribution_profile.json")));
entry = template.profiles(1);
entry.profile.id = "vawlume.attribution.phase7_fixture_backend.v0_1";
entry.profile.name = "Phase 7 fixture synthetic localization backend";
entry.profile.profile_version = "0.1.0-fixture";
entry.context.exporting_system = "Synthetic Localization Backend";
entry.context.exporting_system_version = "7.0.0";
entry.context.coordinate_system_key = "arena_2d";
entry.context.tracking_stream_key = "arena_tracking";
entry.context.window_timebase_key = "audio_native";
entry.caller_label_resolution.map = [ ...
    struct(caller_label="A", entity_native_id=session.entities.A_native_id); ...
    struct(caller_label="B", entity_native_id=session.entities.B_native_id)];
entry.declared_inputs.declarations = struct(acoustic="used", ...
    pose_localization="used", visual_identity="not_used");
template.profiles = entry;
profilePath = fullfile(folder, "backend_profile.json");
writeTextTo(profilePath, string(jsonencode(template, PrettyPrint=true)) + newline);

lines = "segment_id,start_s,end_s,candidate,assignment_score,track,source_x," + ...
    "source_y,localization_confidence,mic1_power,mic2_power,err_major";
for k = 1:height(g.scenes)
    for which = 1:2
        lines(end + 1, 1) = compose("b%02d,%.3f,%.3f,%s,%.2f,,%.1f,%.1f,0.80,-41.0,-44.5,3.0", ...
            k, g.scenes.start_s(k) - 0.004, g.scenes.end_s(k) + 0.004, ...
            char('A' + which - 1), g.backend_scores(k, which), ...
            12.0 + k, 21.0); %#ok<AGROW>
    end
end
exportPath = fullfile(folder, "backend_export.csv");
writeLinesTo(exportPath, lines);

created = vawlume.attribution.createRun(conn, struct(recording_id=session.recording_id), ...
    struct(run_key="p7-backend", attribution_path="backend", ...
    method="Synthetic Localization Backend 7.0.0", ...
    settings_profile_version_id=settingsVersion, ...
    target_set=struct(detection_ids=dsIds'), ...
    participating_entity_ids=[session.A session.B], ...
    sources=struct(source_file_ids=sourceFileOf(conn, session))), Apply=true);
runRef = struct(attribution_run_id=double(created.run.attribution_run_id));
vawlume.ingest.backendAttribution(conn, runRef, string(exportPath), ...
    ProfilePath=string(profilePath), RepoRoot=repoRoot, Apply=true);
vawlume.attribution.correspondWindows(conn, runRef, SameClock=true, ...
    RepoRoot=repoRoot, Apply=true);
promoteClaims(conn, double(created.targets.attribution_target_id)', false);
vawlume.attribution.decide(conn, runRef, struct(), RepoRoot=repoRoot, Apply=true);
value = struct(target_ids=double(created.targets.attribution_target_id));
end

function promoteClaims(conn, targetIds, withProbability)
%PROMOTECLAIMS This fixture's explicit promotion rule.
%
% Every claim over a window that corresponds to a target becomes a candidate of
% that target, its number and semantics copied unchanged. That is the FIXTURE's
% declared rule, as the backend demonstration's is; VAWLUME never promotes a
% claim implicitly. Reads use the documented sentinel for a NULL number.
for target = targetIds
    claims = fetch(conn, "SELECT cl.entity_id AS entity_id, " + ...
        "IFNULL(cl.score,-999.0) AS score, IFNULL(cl.score_semantics,'') AS score_semantics, " + ...
        "IFNULL(cl.probability,-999.0) AS probability, " + ...
        "IFNULL(cl.probability_semantics,'') AS probability_semantics, " + ...
        "cl.source_caller_label AS label FROM imported_attribution_claims cl " + ...
        "JOIN attribution_window_correspondences wc " + ...
        "ON wc.imported_attribution_window_id = cl.imported_attribution_window_id " + ...
        "WHERE wc.attribution_target_id=" + string(target) + " ORDER BY cl.entity_id");
    if height(claims) == 0, continue, end
    batch = table(double(claims.entity_id), double(claims.score), ...
        string(claims.score_semantics), string(claims.label), ...
        VariableNames=["entity_id", "score", "score_semantics", "source_label"]);
    if withProbability
        batch.probability = double(claims.probability);
        batch.probability_semantics = string(claims.probability_semantics);
    end
    vawlume.attribution.addCandidates(conn, struct(attribution_target_id=target), ...
        batch, Apply=true);
end
end

function id = sourceFileOf(conn, session)
rows = fetch(conn, "SELECT source_file_id FROM recordings WHERE recording_id=" + ...
    string(session.recording_id));
id = double(rows.source_file_id(1));
end

function value = runEntry(conn, runKey)
rows = fetch(conn, "SELECT attribution_run_id, attribution_path, method " + ...
    "FROM attribution_runs WHERE run_key='" + runKey + "'");
targets = fetch(conn, "SELECT attribution_target_id, " + ...
    "IFNULL(detection_id,-1) AS detection_id, " + ...
    "IFNULL(consensus_event_id,-1) AS consensus_event_id FROM attribution_targets " + ...
    "WHERE attribution_run_id=" + string(double(rows.attribution_run_id(1))) + ...
    " ORDER BY attribution_target_id");
value = struct(run_key=runKey, attribution_run_id=double(rows.attribution_run_id(1)), ...
    attribution_path=string(rows.attribution_path(1)), method=string(rows.method(1)), ...
    target_ids=double(targets.attribution_target_id), ...
    detection_ids=double(targets.detection_id), ...
    consensus_event_ids=double(targets.consensus_event_id), ...
    synthetic_claims=string(rows.attribution_path(1)) ~= "native_estimate");
end

% ============================================================== manifests ===

function value = sceneManifest(g, extractors, correspondence, attribution)
count = height(g.scenes);
ds = sceneDetections(extractors.ds, g);
mu = sceneDetections(shifted(extractors.mupet, 0.002), g);
us = sceneDetections(shifted(extractors.usvseg, -0.002), g);
targetOf = @(run, events, ids) arrayfun(@(id) run.target_ids(events == id), ids);
runs = attribution.runs;
value = table(g.scenes.scene, g.scenes.start_s, g.scenes.end_s, ds, mu, us, ...
    correspondence.scene_consensus_event_ids, ...
    targetOf(runs.native_detections, runs.native_detections.detection_ids, ds), ...
    targetOf(runs.native_consensus, runs.native_consensus.consensus_event_ids, ...
        correspondence.scene_consensus_event_ids), ...
    targetOf(runs.imported, runs.imported.detection_ids, ds), ...
    targetOf(runs.backend, runs.backend.detection_ids, ds), ...
    g.scenes.built_how, ...
    VariableNames=["scene", "start_s", "end_s", "deepsqueak_detection_id", ...
    "mupet_detection_id", "usvseg_detection_id", "consensus_event_id", ...
    "native_detection_target_id", "native_consensus_target_id", ...
    "imported_target_id", "backend_target_id", "built_how"]);
value.imported_scores = g.imported_scores;
value.backend_scores = g.backend_scores;
if count ~= height(value)
    error("vawlume:db:FixtureBuildFailed", "Scene manifest is incomplete.");
end
end

function rows = shifted(rows, delta)
rows.start_time_s = round((rows.start_time_s - delta) * 1e6) / 1e6;
end

function value = artifactManifest(root)
listing = dir(fullfile(root, "**", "*"));
listing = listing(~[listing.isdir]);
paths = strings(numel(listing), 1);
bytes = zeros(numel(listing), 1);
for k = 1:numel(listing)
    full = string(fullfile(listing(k).folder, listing(k).name));
    paths(k) = extractAfter(replace(full, "\", "/"), strlength(replace(root, "\", "/")) + 1);
    bytes(k) = listing(k).bytes;
end
value = sortrows(table(paths, bytes, VariableNames=["relative_path", "bytes"]), ...
    "relative_path");
end

% ============================================================ audio files ===

function writeSessionAudio(path, g)
% 1000 Hz, 24-bit, two channels. Channel k hears every source at gain(k).
rate = g.rate;
total = g.duration_s * rate;
time = (0:total - 1)' / rate;
signal = zeros(total, 2);
noise = zeros(total, 1);
for frequency = [220 240 260 280]
    noise = noise + 0.05 * sin(2 * pi * frequency * time);
end
tone = sin(2 * pi * g.call_hz * time);
% The audio is written before intake, because intake checksums it. The arena
% frame is not registered yet, so the pure distance primitive gets a descriptor
% naming the one generator frame on both sides; it reads no database, and the
% identity rule it applies holds because both sides are that same frame.
frame = struct(coordinate_system_id=1, dimensionality=2, unit="cm");
for channel = 1:2
    gain = g.gains(channel);
    signal = place(signal, channel, gain * noise, [5.0 5.8], rate);
    signal = place(signal, channel, gain * 0.2 * tone, [6.0 6.8], rate);
    for k = 1:height(g.scenes)
        switch g.scenes.layout(k)
            case "separable"
                % A's own distances, through the geometry primitive.
                d = vawlume.geometry.distance(g.mics, frame, ...
                    g.positions.separable.track0, frame).distance;
                level = 10 / d(channel);
                if channel == 1
                    level = level * 10^(g.scenes.bias_db(k) / 20);
                end
                if g.scenes.scene(k) == "unfittable"
                    towardB = [10^(-8 / 20), 1];
                    level = 0.3 * towardB(channel);
                end
            case "swap"
                level = 0.3;
            otherwise
                level = 0.2;
        end
        signal = place(signal, channel, gain * level * tone, ...
            [g.scenes.start_s(k) g.scenes.end_s(k)], rate);
    end
end
audiowrite(char(path), signal, rate, BitsPerSample=24);
end

function writeSecondMicrophone(path, g)
rate = g.rate;
total = g.duration_s * rate;
time = (0:total - 1)' / rate;
signal = zeros(total, 1);
tone = sin(2 * pi * g.call_hz * time);
signal = place(signal, 1, 0.1 * tone, [30.0 30.1], rate);
signal = place(signal, 1, 0.1 * tone, [70.0 70.1], rate);
audiowrite(char(path), signal, rate, BitsPerSample=24);
end

function signal = place(signal, channel, values, interval, rate)
selected = (round(interval(1) * rate) + 1:round(interval(2) * rate))';
signal(selected, channel) = values(selected);
end

% ======================================================== extractor files ===

function writeDeepSqueak(path, times)
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
file = 'synthetic/deepsqueak/D004_session_detections.mat';
cells = headers;
for k = 1:size(times, 1)
    low = 45 + mod(k, 5);
    high = 75 + mod(k, 7);
    if k == size(times, 1)
        high = low;   % the zero-height box a real Stats export can carry
    end
    cells(end + 1, :) = {file, k, 'class_a', 1, 0.80, times(k, 1), times(k, 2), ...
        times(k, 2) - times(k, 1), 60.0, low, high, high - low, 2.5, 4.0, 1.1, ...
        -70.0, 0.75, 61.0}; %#ok<AGROW>
end
makeParent(path);
writecell(cells, path);
normalizeWorkbook(path);
end

function writeMupet(path, times)
headers = {'Syllable number', 'Syllable start time (sec)', ...
    'Syllable end time (sec)', 'inter-syllable interval (sec)', ...
    'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', ...
    'maximum frequency (kHz)', 'mean frequency (kHz)', ...
    'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
[~, order] = sort(times(:, 1));
times = times(order, :);
cells = headers;
for k = 1:size(times, 1)
    if k < size(times, 1)
        interval = times(k + 1, 1) - times(k, 2);
        intervalCell = {round(interval, 6)};
    else
        intervalCell = {'_'};   % MUPET's terminal sentinel
    end
    duration = round((times(k, 2) - times(k, 1)) * 1000, 3);
    cells(end + 1, :) = [{k, times(k, 1), times(k, 2)}, intervalCell, ...
        {duration, 47, 61, 45.0, 78.0, 62.0, 33, 11.0, -19}]; %#ok<AGROW>
end
makeParent(path);
writecell(cells, path);
end

function lines = mupetConfig()
lines = ["noise-reduction,5"; "minimum-syllable-duration,008"; ...
    "maximum-syllable-duration,200"; "minimum-syllable-total-energy,-15"; ...
    "minimum-syllable-peak-amplitude,-25"; "minimum-syllable-distance,5"; ...
    "sample-frequency,250000"; "minimum-usv-frequency,30000"; ...
    "maximum-usv-frequency,120000"; "number-filterbank-filters,64"; ...
    "filterbank-type,1"];
end

function writeUsvseg(path, times, nanRow)
[~, order] = sort(times(:, 1));
times = times(order, :);
lines = "#,start,end,duration,maxfreq,maxamp,meanfreq,cvfreq";
for k = 1:size(times, 1)
    maxfreq = "72.500";
    if k == nanRow
        maxfreq = "NaN";   % USVSEG's missing acoustic feature
    end
    lines(end + 1, 1) = compose("%d,%.4f,%.4f,%.1f,%s,-18.5,61.250,0.1200", k, ...
        times(k, 1), times(k, 2), (times(k, 2) - times(k, 1)) * 1000, maxfreq); %#ok<AGROW>
end
writeLinesTo(path, lines);
end

function normalizeWorkbook(path)
%NORMALIZEWORKBOOK Make a written .xlsx byte-reproducible.
%
% MATLAB's writer stamps the package's entries and docProps/core.xml with the
% current time, so two identical workbooks hash differently. The fixture's
% artifact checksums must reproduce, so the package is rewritten with a fixed
% entry time and fixed document dates. Cell content is untouched.
staging = string(tempname);
extracted = string(unzip(char(path), char(staging)));
names = cell(1, numel(extracted));
contents = cell(1, numel(extracted));
for k = 1:numel(extracted)
    name = char(replace(extractAfter(extracted(k), strlength(staging) + 1), "\", "/"));
    fileId = fopen(extracted(k), "r");
    bytes = fread(fileId, Inf, "*uint8");
    fclose(fileId);
    if strcmp(name, "docProps/core.xml")
        text = native2unicode(bytes(:)', "UTF-8");
        text = regexprep(text, "(<dcterms:created[^>]*>)[^<]*", "$12000-01-01T00:00:00Z");
        text = regexprep(text, "(<dcterms:modified[^>]*>)[^<]*", "$12000-01-01T00:00:00Z");
        bytes = unicode2native(text, "UTF-8");
    end
    names{k} = name;
    contents{k} = bytes(:);
end
rmdir(staging, "s");
[~, order] = sort(names);
% Java would read a relative path against user.dir; MATLAB wrote it against pwd.
fileOut = java.io.FileOutputStream(char(vawlume.internal.resolvePath(path, Mode="absolute")));
zipOut = java.util.zip.ZipOutputStream(fileOut);
fixedTime = java.util.GregorianCalendar(2000, 0, 1, 0, 0, 0).getTimeInMillis();
for k = order
    entry = java.util.zip.ZipEntry(names{k});
    entry.setTime(fixedTime);
    zipOut.putNextEntry(entry);
    zipOut.write(typecast(contents{k}, "int8"));
    zipOut.closeEntry();
end
zipOut.close();
fileOut.close();
end

% ================================================================ helpers ===

function mustCommit(result, what)
committed = false;
if isfield(result, "committed")
    committed = logical(result.committed);
end
if ~committed
    status = "";
    if isfield(result, "status"), status = string(result.status); end
    error("vawlume:db:FixtureBuildFailed", "%s did not commit: %s", what, status);
end
end

function writeLinesTo(path, lines)
makeParent(path);
fileId = fopen(path, "w");
if fileId < 0
    error("vawlume:db:FixtureBuildFailed", "Could not write %s", path);
end
closer = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", lines);
end

function writeTextTo(path, text)
makeParent(path);
fileId = fopen(path, "w");
if fileId < 0
    error("vawlume:db:FixtureBuildFailed", "Could not write %s", path);
end
closer = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
end

function makeParent(path)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
end

function removeFixture(conn, root)
try
    if isopen(conn), close(conn); end
catch
end
try
    if isfolder(root), rmdir(root, "s"); end
catch
end
end
