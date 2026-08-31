function demonstration = temporal_alignment_demo(options)
%TEMPORAL_ALIGNMENT_DEMO Demonstrate synthetic common-time event binning.
%
% DEMONSTRATION = TEMPORAL_ALIGNMENT_DEMO() creates a disposable audio/video/
% neural session, registers a manifest and reusable mapping profiles, fits known
% affine transforms from four logical anchors, reads calls and external events on
% the neural reference clock, and builds a small regularized timeline.
%
% All inputs are synthetic and all files are removed before return. The example
% demonstrates provenance, explicit clock transforms, residual read-back, and
% absent-versus-unavailable bins. It does not validate real synchronization,
% ingest continuous neural samples, or perform sequence/motif analysis.
%
% Name-value options:
%   Print     print compact developer-facing read-backs (default true)
%   RepoRoot  repository root, inferred from this file by default

arguments
    options.Print (1,1) logical = true
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
end
sourcePath = fullfile(repoRoot, "src");
removePath = ~contains(path, sourcePath);
if removePath, addpath(sourcePath); end
cleanupPath = onCleanup(@() restorePath(sourcePath, removePath));

workspace = fullfile(tempdir, "VAWLUME temporal alignment demo " + ...
    string(java.util.UUID.randomUUID));
mkdir(workspace);
cleanupWorkspace = onCleanup(@() removeTree(workspace));
databasePath = fullfile(workspace, "temporal_alignment_demo.sqlite");
conn = sqlite(char(databasePath), "create");
cleanupConnection = onCleanup(@() closeConnection(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

seedRecordingAndCalls(conn);
[truth, manifestPath] = writeAlignmentInputs(workspace, repoRoot);
intake = vawlume.ingest.alignment(conn, manifestPath, RepoRoot=repoRoot, ...
    SourceRoot=workspace, Apply=true);
fit = vawlume.alignment.fit(conn, struct(run_key="demo_alignment"), Apply=true);
qc = vawlume.alignment.report(conn, struct(run_key="demo_alignment"));
view = vawlume.alignment.commonTime(conn, struct(run_key="demo_alignment"), ...
    VocalizationSource="detections", VocalizationRunId=1);

videoKey = unique(view.events.coverage_key( ...
    view.events.source_timebase_key == "video_native"));
neuralKey = unique(view.events.coverage_key( ...
    view.events.source_timebase_key == "neural_native"));
assert(isscalar(videoKey) && isscalar(neuralKey), ...
    "Expected one video stream and one neural stream.");
channels = [struct(name="call_count", event_source_kind="detection", ...
    normalized_event_key="vocalization", coverage_key="recording:1", ...
    aggregation="onset_count"), ...
    struct(name="female_entry_present", event_source_kind="external_event", ...
    normalized_event_key="female_entry", coverage_key=videoKey, ...
    aggregation="any_overlap"), ...
    struct(name="neural_event_count", event_source_kind="external_event", ...
    normalized_event_key="sync_marker", coverage_key=neuralKey, ...
    aggregation="onset_count")];
regularized = vawlume.sequence.regularizeTimeline(view, channels, ...
    WindowStart=120, WindowEnd=180, BinWidth=5, BinOrigin=120);

recovered = recoveredParameters(qc, truth);
inventory = struct(aligned_external_events=rowCount(conn, ...
    "aligned_external_events"), sequences=rowCount(conn, "sequences"), ...
    sequence_members=rowCount(conn, "sequence_members"));
foreignKeyCheck = fetch(conn, "PRAGMA foreign_key_check");
demonstration = struct( ...
    synthetic_truth=truth, intake=intake, fit=fit, qc=qc, ...
    recovered_parameters=recovered, common_time_events=view.events, ...
    projected_coverage=view.coverage, ...
    regularization_specification=regularized.specification, ...
    timeline=regularized.timeline, database_inventory=inventory, ...
    foreign_key_check=foreignKeyCheck, ...
    proves=["explicit audio/video transforms recover known parameters"; ...
        "native and aligned timestamps coexist in a derived union"; ...
        "reference-clock events use identity semantics"; ...
        "coverage distinguishes covered-empty zero from unavailable NaN"], ...
    does_not_prove=["real-device synchronization accuracy"; ...
        "calibrated residual acceptance thresholds"; ...
        "continuous neural ingestion or sequence analytics"], ...
    temporary_artifacts_removed=false);

if options.Print, printDemo(demonstration); end
close(conn);
clear cleanupConnection
removeTree(workspace);
clear cleanupWorkspace
demonstration.temporary_artifacts_removed = ...
    ~isfolder(workspace) && ~isfile(databasePath);
clear cleanupPath
end

function seedRecordingAndCalls(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES (1,'synthetic_alignment_session','Synthetic alignment demo')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES " + ...
    "(1,1,'recording_audio','synthetic/session01.wav','session01.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id,sample_rate_hz,duration_s) " + ...
    "VALUES (1,1,1,'REC_SESSION_01',250000,60)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES (1,'synthetic_calls','Synthetic call fixture')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES (1,1,'0.1-demo')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES (1,1,1,'demo_calls')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES (1,1)");
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES " + ...
    "(1,1,'call01',10,10.08,'synthetic fixture')," + ...
    "(1,1,'call02',20,20.06,'synthetic fixture')");
end

function [truth, manifestPath] = writeAlignmentInputs(workspace, repoRoot)
truth = struct(audio_scale=1.0015, audio_offset_s=117.25, ...
    video_scale=0.9992, video_offset_s=53.40);
audio = [10; 20; 40; 55];
neural = truth.audio_scale * audio + truth.audio_offset_s;
video = (neural - truth.video_offset_s) / truth.video_scale;

behavior = table(["b1"; "b2"; "b3"], ...
    ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    ["70"; "75"; "80"], ["72"; missing; "80"], ...
    ["F01"; "M01"; ""], ["door"; "center"; "sync"], ...
    VariableNames=["event_id", "event", "start_time_s", "end_time_s", ...
    "subject", "zone"]);
writeTable(fullfile(workspace, "video_events.csv"), behavior);

neuralEvents = table("n" + string(1:4)', repmat("TTL1_HIGH", 4, 1), ...
    compose("%.9f", neural * 1000), repmat("5", 4, 1), repmat("1", 4, 1), ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
writeTable(fullfile(workspace, "neural_events.csv"), neuralEvents);

keys = repelem(["sync01"; "sync02"; "sync03"; "sync04"], 3);
streams = repmat(["audio"; "video"; "neural"], 4, 1);
times = strings(12, 1);
eventIds = strings(12, 1);
for index = 1:4
    base = (index - 1) * 3;
    times(base + 1) = compose("%.9f", audio(index));
    times(base + 2) = compose("%.9f", video(index));
    times(base + 3) = compose("%.9f", neural(index));
    eventIds(base + 3) = "n" + string(index);
end
anchors = table(keys, streams, times, repmat("primary", 12, 1), ...
    repmat("true", 12, 1), repmat("0.002", 12, 1), eventIds, ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
writeTable(fullfile(workspace, "sync_anchors.csv"), anchors);

manifestPath = fullfile(workspace, "alignment_manifest.json");
document = jsondecode(fileread(fullfile(repoRoot, "config", ...
    "06_alignment_manifests", "synthetic_session_alignment_manifest.json")));
document.manifest.alignment_key = "demo_alignment";
writeText(manifestPath, string(jsonencode(document, PrettyPrint=true)) + newline);
end

function value = recoveredParameters(qc, truth)
audio = qc.transforms(qc.transforms.source_timebase_key == "audio_native", :);
video = qc.transforms(qc.transforms.source_timebase_key == "video_native", :);
value = table(["audio_native"; "video_native"], [audio.scale; video.scale], ...
    [audio.offset_s; video.offset_s], ...
    [abs(audio.scale-truth.audio_scale); abs(video.scale-truth.video_scale)], ...
    [abs(audio.offset_s-truth.audio_offset_s); ...
    abs(video.offset_s-truth.video_offset_s)], ...
    VariableNames=["source_timebase", "scale", "offset_s", ...
    "scale_absolute_error", "offset_absolute_error_s"]);
end

function printDemo(value)
fprintf('\nVAWLUME synthetic temporal-alignment demonstration\n');
fprintf('Recovered transform parameters:\n');
disp(value.recovered_parameters);
fprintf('Per-anchor residual evidence:\n');
disp(value.qc.residuals);
fprintf('Native and aligned events:\n');
disp(value.common_time_events(:, ["event_source_kind", "normalized_event_key", ...
    "native_start", "aligned_start", "alignment_kind"]));
fprintf('Regularized timeline (0 = covered-empty, NaN = unavailable):\n');
disp(value.timeline);
fprintf('Proves:\n  %s\n', strjoin(value.proves, '\n  '));
fprintf('Does not prove:\n  %s\n', strjoin(value.does_not_prove, '\n  '));
end

function writeTable(pathValue, value)
writetable(value, pathValue, QuoteStrings="minimal");
end

function writeText(pathValue, value)
fid = fopen(pathValue, "w");
assert(fid >= 0, "Could not create synthetic demonstration input.");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", value);
clear cleanup
end

function value = rowCount(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function restorePath(sourcePath, removePath)
if removePath && contains(path, sourcePath), rmpath(sourcePath); end
end

function closeConnection(conn)
if isopen(conn), close(conn); end
end

function removeTree(workspace)
if isfolder(workspace), rmdir(workspace, "s"); end
end
