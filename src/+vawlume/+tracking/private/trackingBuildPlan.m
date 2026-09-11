function plan = trackingBuildPlan(conn, recordingRef, trackingSpec, options)
%TRACKINGBUILDPLAN Resolve one tracking registration and classify every row.
%
% Nothing is written. Each row is classified create, reuse, or conflict against
% what is already stored, so a rerun over the same artifact resolves to the same
% stream rather than adding a second copy.

repoRoot = trackingRepoRoot(options.RepoRoot);
sourceRoot = options.SourceRoot;
if strlength(sourceRoot) == 0
    sourceRoot = repoRoot;
end

plan = struct();
plan.recording = trackingResolveRecording(conn, recordingRef);
plan.spec = normalizeSpec(trackingSpec);

% The artifact is read here, in full, into MATLAB memory. That is what the
% mapper needs to derive the trace inventory and the observed span, and it is
% not what the dense-data policy forbids - the policy is about SQLite.
[tbl, artifactPath] = trackingReadArtifact(plan.spec.artifact_path, sourceRoot, ...
    options.Table);
plan.artifact = trackingArtifactFacts(artifactPath, sourceRoot);

loaded = vawlume.source_mapping.loadProfile(plan.spec.profile_path, ...
    RepoRoot=repoRoot);
plan.ir = vawlume.source_mapping.mapTableToIR(tbl, loaded, ...
    ProfileId=plan.spec.profile_id, SourceKey="source:tracking_table", ...
    RuntimePath=artifactPath, RelativePath=plan.artifact.relative_path, ...
    Filename=plan.artifact.filename, RepoRoot=repoRoot);

if height(plan.ir.tracking_streams) ~= 1
    error("vawlume:tracking:ProfileUnsupported", ...
        "A tracking registration requires exactly one mapped tracking stream; " + ...
        "the profile produced %d.", height(plan.ir.tracking_streams));
end
stream = table2struct(plan.ir.tracking_streams(1, :));
plan.stream_facts = stream;
plan.profile = trackingProfileFacts(plan.ir.profile, plan.spec, repoRoot);

plan.coordinate_system = resolveCoordinateSystem(conn, plan.recording, ...
    stream.coordinate_system_key);
plan.timebase = resolveTimebase(conn, plan.recording, plan.spec.timebase_key);

streamName = plan.spec.stream_name;
if strlength(streamName) == 0
    streamName = stream.stream_key;
end
plan.stream = resolveStream(conn, plan, streamName);
plan.series = resolveSeries(plan);
plan.coverage = plan.ir.coverage;

plan.conflicts = strings(0, 1);
plan = appendConflict(plan, plan.stream.conflict_message);
plan.has_conflicts = ~isempty(plan.conflicts);
plan.status = "planned";
if plan.has_conflicts
    plan.status = "conflict";
end
end

function spec = normalizeSpec(trackingSpec)
spec = struct();
spec.artifact_path = trackingRequiredText(trackingSpec, "artifact_path");
spec.profile_path = trackingRequiredText(trackingSpec, "profile_path");
spec.timebase_key = trackingRequiredText(trackingSpec, "timebase_key");
spec.profile_id = trackingOptionalText(trackingSpec, "profile_id");
spec.stream_name = trackingOptionalText(trackingSpec, "stream_name");
spec.notes = trackingOptionalText(trackingSpec, "notes");
end

function system = resolveCoordinateSystem(conn, recording, key)
%RESOLVECOORDINATESYSTEM The frame must already be declared for this project.
if strlength(key) == 0
    error("vawlume:tracking:CoordinateSystemUndeclared", ...
        "The tracking profile declares no coordinate_system_key.");
end
rows = fetch(conn, "SELECT coordinate_system_id, coordinate_system_key, " + ...
    "dimensionality, unit FROM coordinate_systems " + ...
    "WHERE project_id=" + string(recording.project_id) + ...
    " AND coordinate_system_key=" + trackingSqlText(key));
if isempty(rows) || height(rows) == 0
    error("vawlume:tracking:CoordinateSystemNotFound", ...
        "No coordinate system '%s' is declared for project '%s'. Declare the " + ...
        "frame before registering tracking in it; VAWLUME never creates one " + ...
        "implicitly, because that would let an import choose its own units " + ...
        "and dimensionality.", key, recording.project_key);
end

% Routed through the geometry primitive rather than compared here, so the
% identity-not-similarity rule has exactly one implementation.
system = vawlume.geometry.assertCompatible(conn, ...
    double(rows.coordinate_system_id(1)), Context="tracking stream registration");
end

function timebase = resolveTimebase(conn, recording, key)
%RESOLVETIMEBASE An established clock of this recording, or of its project.
rows = fetch(conn, "SELECT timebase_id, timebase_name, timebase_kind, " + ...
    "IFNULL(recording_id, -1) AS recording_id FROM timebases " + ...
    "WHERE project_id=" + string(recording.project_id) + ...
    " AND timebase_name=" + trackingSqlText(key) + ...
    " AND (recording_id IS NULL OR recording_id=" + ...
    string(recording.recording_id) + ") ORDER BY recording_id DESC");
if isempty(rows) || height(rows) == 0
    error("vawlume:tracking:TimebaseNotFound", ...
        "No timebase '%s' is established for recording %d or its project. " + ...
        "Tracking states its samples on a declared clock; it does not invent " + ...
        "one.", key, recording.recording_id);
end
timebase = struct( ...
    timebase_id=double(rows.timebase_id(1)), ...
    timebase_name=trackingPresentText(rows.timebase_name(1)), ...
    timebase_kind=trackingPresentText(rows.timebase_kind(1)));
end

function stream = resolveStream(conn, plan, streamName)
%RESOLVESTREAM Classify the logical stream as create, reuse, or conflict.
facts = plan.stream_facts;
rows = fetch(conn, "SELECT es.external_stream_id, es.stream_kind, " + ...
    "es.timebase_id, IFNULL(ts.coordinate_system_id, -1) AS coordinate_system_id, " + ...
    "IFNULL(ts.native_time_basis,'') AS native_time_basis, " + ...
    "IFNULL(ts.nominal_frame_rate_hz, -1) AS nominal_frame_rate_hz, " + ...
    "IFNULL(ts.has_confidence, -1) AS has_confidence, " + ...
    "IFNULL(ts.declared_sample_count, -1) AS declared_sample_count " + ...
    "FROM external_streams es " + ...
    "LEFT JOIN tracking_streams ts ON ts.external_stream_id=es.external_stream_id " + ...
    "WHERE es.project_id=" + string(plan.recording.project_id) + ...
    " AND es.stream_name=" + trackingSqlText(streamName));

stream = struct( ...
    stream_name=streamName, ...
    external_stream_id=NaN, ...
    action="create", ...
    conflict_message="");

if isempty(rows) || height(rows) == 0
    return
end

stored = rows(1, :);
differing = strings(0, 1);
if trackingPresentText(stored.stream_kind) ~= "tracking"
    differing(end + 1, 1) = "stream_kind";
end
if double(stored.coordinate_system_id) ~= plan.coordinate_system.coordinate_system_id
    differing(end + 1, 1) = "coordinate_system";
end
if double(stored.timebase_id) ~= plan.timebase.timebase_id
    differing(end + 1, 1) = "timebase";
end
if trackingPresentText(stored.native_time_basis) ~= string(facts.native_time_basis)
    differing(end + 1, 1) = "native_time_basis";
end
if double(stored.declared_sample_count) ~= facts.declared_sample_count
    differing(end + 1, 1) = "declared_sample_count";
end
storedConfidence = double(stored.has_confidence);
if storedConfidence ~= double(facts.has_confidence)
    differing(end + 1, 1) = "has_confidence";
end

if isempty(differing)
    stream.external_stream_id = double(stored.external_stream_id);
    stream.action = "reuse";
    return
end

stream.external_stream_id = double(stored.external_stream_id);
stream.action = "conflict";
stream.conflict_message = "Tracking stream '" + streamName + ...
    "' already exists with different content: " + ...
    strjoin(differing(:)', ", ") + ". Registering over it would silently " + ...
    "redefine a stream that coverage and later window reads already cite.";
end

function series = resolveSeries(plan)
%RESOLVESERIES The trace inventory the mapper derived, as plan rows.
series = plan.ir.tracking_series;
end

function plan = appendConflict(plan, message)
if strlength(message) > 0
    plan.conflicts(end + 1, 1) = message;
end
end
