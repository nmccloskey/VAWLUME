function plan = alignmentBuildPlan(conn, bundle, runSpec)
%ALIGNMENTBUILDPLAN Classify every alignment registration row before writing any.
%
% Nothing here writes. Each resolvable identity is classified create, reuse, or
% conflict, so an apply either commits a coherent registration or refuses with a
% stated reason. Unknown timebase or stream keys fail during planning, which is
% what keeps a partial write from ever being attempted.

plan = struct();
plan.bundle = bundle;
plan.context = validateRunSpec(runSpec, bundle);
plan.conflicts = strings(0, 1);

plan.project = resolveProject(conn, bundle.manifest.project_key);
plan.recording = resolveRecording(conn, plan.project, bundle.manifest.recording);
plan.timebases = resolveTimebases(conn, plan, bundle.manifest);
plan.sources = resolveSources(conn, plan, bundle);
plan.profiles = resolveProfiles(conn, plan, bundle);
plan.streams = resolveStreams(conn, plan, bundle);
plan.anchors = resolveAnchors(plan, bundle);
plan.transform_runs = resolveTransformRuns(plan, bundle);
plan.analysis = resolveAnalysis(conn, plan, bundle);

plan = appendConflict(plan, plan.analysis.conflict_message);
plan.has_conflicts = ~isempty(plan.conflicts);
end

% ------------------------------------------------------------------ inputs ---

function context = validateRunSpec(runSpec, bundle)
context = struct( ...
    run_key=bundle.manifest.alignment_key, ...
    run_label=bundle.manifest.label, ...
    vawlume_version=optionalText(runSpec, "vawlume_version"), ...
    source_commit=optionalText(runSpec, "source_commit"), ...
    notes=bundle.manifest.notes);
if isfield(runSpec, "run_key")
    context.run_key = scalarText(runSpec.run_key, "runSpec.run_key");
end
if isfield(runSpec, "run_label")
    context.run_label = scalarText(runSpec.run_label, "runSpec.run_label");
end
if strlength(context.run_key) == 0
    error("vawlume:ingest:AlignmentRunKeyInvalid", ...
        "The alignment analysis run key must be nonempty.");
end
end

function project = resolveProject(conn, projectKey)
rows = fetch(conn, "SELECT project_id FROM projects WHERE project_key=" + ...
    sqlText(projectKey));
if isempty(rows) || height(rows) == 0
    error("vawlume:ingest:AlignmentProjectNotFound", ...
        "No established project matches project_key '%s'.", projectKey);
end
project = struct(project_id=double(rows.project_id(1)), project_key=projectKey);
end

function recording = resolveRecording(conn, project, selector)
if selector.mode == "native_recording_id"
    predicate = "r.native_recording_id=" + sqlText(selector.value);
else
    predicate = "sf.relative_path=" + sqlText(selector.value);
end
rows = fetch(conn, "SELECT r.recording_id, " + ...
    "IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
    "IFNULL(r.sample_rate_hz, -1) AS sample_rate_hz, " + ...
    "IFNULL(sf.relative_path,'') AS relative_path " + ...
    "FROM recordings r JOIN source_files sf ON sf.source_file_id=r.source_file_id " + ...
    "WHERE r.project_id=" + string(project.project_id) + " AND " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:ingest:AlignmentRecordingNotFound", ...
        "No recording in project '%s' matches %s '%s'.", ...
        project.project_key, selector.mode, selector.value);
end
if height(rows) ~= 1
    error("vawlume:ingest:AlignmentRecordingAmbiguous", ...
        "%s '%s' matched %d recordings; exactly one is required.", ...
        selector.mode, selector.value, height(rows));
end
sampleRate = double(rows.sample_rate_hz(1));
if sampleRate <= 0
    sampleRate = NaN;
end
recording = struct( ...
    recording_id=double(rows.recording_id(1)), ...
    native_recording_id=presentText(rows.native_recording_id(1)), ...
    source_relative_path=presentText(rows.relative_path(1)), ...
    sample_rate_hz=sampleRate);
end

% -------------------------------------------------------------- timebases ---

function value = resolveTimebases(conn, plan, manifest)
%RESOLVETIMEBASES Register each declared clock once, and ensure the native one.
%
% A clock declared recording_native is scoped to the recording; every other clock
% is project-scoped, so two streams may share one neural_native clock while a
% second session's identically named clock stays distinct through its own project
% or recording scope.
%
% The recording's native audio timebase is ensured rather than assumed. Recordings
% created before Phase 7 have none, and requiring manual SQL to align them would
% make every fresh test database a special case.
value = repmat(emptyTimebase(), numel(manifest.timebases), 1);
for index = 1:numel(manifest.timebases)
    declaration = manifest.timebases(index);
    row = emptyTimebase();
    row.timebase_key = declaration.timebase_key;
    row.timebase_kind = declaration.timebase_kind;
    row.recording_native = declaration.recording_native;
    row.native_unit = declaration.native_unit;
    row.nominal_rate_hz = declaration.nominal_rate_hz;
    row.origin_description = declaration.origin_description;
    row.clock_identifier = declaration.clock_identifier;
    row.notes = declaration.notes;

    if declaration.recording_native
        row.recording_id = plan.recording.recording_id;
        if isnan(row.nominal_rate_hz)
            row.nominal_rate_hz = plan.recording.sample_rate_hz;
        end
        if strlength(row.origin_description) == 0
            row.origin_description = "Recording file time zero.";
        end
        if strlength(row.clock_identifier) == 0
            row.clock_identifier = plan.recording.native_recording_id;
        end
        existing = fetchTimebaseForRecording(conn, plan.recording.recording_id);
    else
        row.recording_id = NaN;
        existing = fetchProjectTimebase(conn, plan.project.project_id, ...
            declaration.timebase_key);
    end

    if isempty(existing)
        row.action = "create";
    else
        row.timebase_id = existing.timebase_id;
        row.action = "reuse";
        if declaration.recording_native && existing.timebase_name ~= row.timebase_key
            % The recording already resolves a native clock under another name.
            % Reuse it rather than creating a second one the schema would refuse.
            row.reused_name = existing.timebase_name;
        end
        if ~declaration.recording_native && existing.timebase_kind ~= row.timebase_kind
            error("vawlume:ingest:AlignmentTimebaseConflict", ...
                ['Timebase ''%s'' is already registered with kind ''%s'' but the ' ...
                'manifest declares ''%s''. A changed clock declaration must use a ' ...
                'new key rather than rewriting prior provenance.'], ...
                declaration.timebase_key, existing.timebase_kind, row.timebase_kind);
        end
    end
    value(index) = row;
end
end

function value = fetchTimebaseForRecording(conn, recordingId)
value = [];
rows = fetch(conn, "SELECT timebase_id, timebase_name, timebase_kind " + ...
    "FROM timebases WHERE recording_id=" + string(recordingId) + ...
    " AND is_recording_native=1");
if isempty(rows) || height(rows) == 0
    return
end
value = struct(timebase_id=double(rows.timebase_id(1)), ...
    timebase_name=presentText(rows.timebase_name(1)), ...
    timebase_kind=presentText(rows.timebase_kind(1)));
end

function value = fetchProjectTimebase(conn, projectId, timebaseKey)
value = [];
rows = fetch(conn, "SELECT timebase_id, timebase_name, timebase_kind " + ...
    "FROM timebases WHERE project_id=" + string(projectId) + ...
    " AND recording_id IS NULL AND timebase_name=" + sqlText(timebaseKey));
if isempty(rows) || height(rows) == 0
    return
end
value = struct(timebase_id=double(rows.timebase_id(1)), ...
    timebase_name=presentText(rows.timebase_name(1)), ...
    timebase_kind=presentText(rows.timebase_kind(1)));
end

% ---------------------------------------------------- sources and profiles ---

function value = resolveSources(conn, plan, bundle)
value = repmat(emptySource(), 0, 1);
value = appendSource(value, conn, plan, bundle.manifest.source_path, ...
    bundle.manifest.content_uri, bundle.manifest.filename, ...
    "alignment_manifest", bundle.manifest.checksum_sha256, NaN, "manifest");
for index = 1:numel(bundle.streams)
    stream = bundle.streams(index);
    if stream.source.mode ~= "file"
        continue
    end
    value = appendSource(value, conn, plan, stream.source.runtime_path, ...
        stream.source.relative_path, stream.source.filename, ...
        stream.source.file_role, stream.source.checksum_sha256, ...
        stream.source.size_bytes, "stream:" + stream.stream_key);
end
if bundle.anchors.declared && bundle.anchors.source.mode == "file"
    value = appendSource(value, conn, plan, bundle.anchors.source.runtime_path, ...
        bundle.anchors.source.relative_path, bundle.anchors.source.filename, ...
        bundle.anchors.source.file_role, bundle.anchors.source.checksum_sha256, ...
        bundle.anchors.source.size_bytes, "anchors");
end
end

function value = appendSource(value, conn, plan, runtimePath, relativePath, ...
        filename, fileRole, checksum, sizeBytes, role)
row = emptySource();
row.role = role;
row.runtime_path = runtimePath;
row.relative_path = relativePath;
row.filename = filename;
row.file_role = fileRole;
row.checksum_sha256 = checksum;
row.size_bytes = sizeBytes;

rows = fetch(conn, "SELECT source_file_id, IFNULL(checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM source_files WHERE project_id=" + string(plan.project.project_id) + ...
    " AND path_or_uri=" + sqlText(runtimePath));
if isempty(rows) || height(rows) == 0
    row.action = "create";
else
    row.source_file_id = double(rows.source_file_id(1));
    row.action = "reuse";
    stored = presentText(rows.checksum_sha256(1));
    if strlength(stored) > 0 && strlength(checksum) > 0 && stored ~= checksum
        error("vawlume:ingest:AlignmentSourceChanged", ...
            ['Source file %s is registered with checksum %s but now hashes to ' ...
            '%s. A changed input is a new alignment, not a correction to an ' ...
            'existing one.'], relativePath, extractBefore(stored, 13), ...
            extractBefore(checksum, 13));
    end
end
value(end + 1, 1) = row;
end

function value = resolveProfiles(conn, plan, bundle)
value = repmat(emptyProfile(), 0, 1);
for index = 1:numel(bundle.streams)
    value = appendProfile(value, conn, plan, bundle.streams(index).profile, ...
        "external_stream_mapping:" + bundle.streams(index).stream_key);
end
if bundle.anchors.declared
    value = appendProfile(value, conn, plan, bundle.anchors.profile, ...
        "alignment_anchor_mapping");
end
end

function value = appendProfile(value, conn, plan, profile, role)
for index = 1:numel(value)
    if value(index).profile_key == profile.profile_key && ...
            value(index).version_label == profile.version_label
        return
    end
end
row = emptyProfile();
row.role = role;
row.profile_key = profile.profile_key;
row.profile_name = profile.profile_name;
row.profile_kind = profile.profile_kind;
row.version_label = profile.version_label;
row.profile_schema_version = profile.profile_schema_version;
row.content_uri = profile.content_uri;
row.checksum_sha256 = profile.checksum_sha256;

rows = fetch(conn, "SELECT profile_id, profile_kind FROM config_profiles " + ...
    "WHERE project_id=" + string(plan.project.project_id) + ...
    " AND profile_key=" + sqlText(row.profile_key));
if ~isempty(rows) && height(rows) > 0
    row.profile_id = double(rows.profile_id(1));
    row.profile_action = "reuse";
    if presentText(rows.profile_kind(1)) ~= row.profile_kind
        error("vawlume:ingest:AlignmentProfileKindConflict", ...
            "Profile '%s' is registered with kind '%s', not '%s'.", ...
            row.profile_key, presentText(rows.profile_kind(1)), row.profile_kind);
    end
    versions = fetch(conn, "SELECT profile_version_id, " + ...
        "IFNULL(checksum_sha256,'') AS checksum_sha256 FROM config_profile_versions " + ...
        "WHERE profile_id=" + string(row.profile_id) + ...
        " AND version_label=" + sqlText(row.version_label));
    if ~isempty(versions) && height(versions) > 0
        row.profile_version_id = double(versions.profile_version_id(1));
        row.version_action = "reuse";
        stored = presentText(versions.checksum_sha256(1));
        if stored ~= row.checksum_sha256
            error("vawlume:ingest:AlignmentProfileChanged", ...
                ['Mapping profile ''%s'' version ''%s'' is registered with ' ...
                'checksum %s but the supplied file hashes to %s.'], ...
                row.profile_key, row.version_label, extractBefore(stored, 13), ...
                extractBefore(row.checksum_sha256, 13));
        end
    end
end
value(end + 1, 1) = row;
end

% --------------------------------------------------- streams and materials ---

function value = resolveStreams(conn, plan, bundle)
value = repmat(emptyStream(), numel(bundle.streams), 1);
for index = 1:numel(bundle.streams)
    stream = bundle.streams(index);
    row = emptyStream();
    row.stream_key = stream.stream_key;
    row.timebase_key = stream.timebase_key;
    row.timebase_index = timebaseIndexOf(plan, stream.timebase_key, ...
        "stream '" + stream.stream_key + "'");
    row.source_role = stream.declaration.source_role;
    row.ir = stream.ir;
    row.event_count = height(stream.ir.events);
    row.attribute_count = height(stream.ir.event_attributes);
    row.coverage_count = height(stream.ir.coverage);
    if height(stream.ir.streams) == 1
        row.stream_kind = presentText(stream.ir.streams.stream_kind(1));
        row.modality = presentText(stream.ir.streams.modality(1));
        row.units = presentText(stream.ir.streams.normalized_time_unit(1));
    end
    if strlength(row.stream_kind) == 0
        row.stream_kind = "event";
    end

    existing = fetch(conn, "SELECT external_stream_id FROM external_streams " + ...
        "WHERE recording_id=" + string(plan.recording.recording_id) + ...
        " AND stream_name=" + sqlText(row.stream_key));
    if isempty(existing) || height(existing) == 0
        row.action = "create";
    else
        row.external_stream_id = double(existing.external_stream_id(1));
        row.action = "reuse";
    end
    value(index) = row;
end
end

function value = resolveAnchors(plan, bundle)
value = struct(declared=false, ir=[], anchor_count=0, observation_count=0, ...
    observations_by_timebase=emptyObservationCounts(), ...
    fit_pairs=emptyFitPairs());
if ~bundle.anchors.declared
    return
end
ir = bundle.anchors.ir;
value.declared = true;
value.ir = ir;
value.anchor_count = height(ir.anchors);
value.observation_count = height(ir.anchor_observations);

% Every clock an observation claims must be a clock the manifest declared. This
% is checked while planning so an unknown key can never reach a partial write.
observedKeys = unique(string(ir.anchor_observations.timebase_key));
for index = 1:numel(observedKeys)
    timebaseIndexOf(plan, observedKeys(index), ...
        "anchor observation timebase '" + observedKeys(index) + "'");
end
value.observations_by_timebase = observationCounts(ir);
value.fit_pairs = fitPairs(plan, ir);
end

function value = observationCounts(ir)
value = emptyObservationCounts();
keys = unique(string(ir.anchor_observations.timebase_key));
for index = 1:numel(keys)
    selected = string(ir.anchor_observations.timebase_key) == keys(index);
    included = ir.anchor_observations.included_in_fit(selected);
    value(end + 1, :) = {keys(index), nnz(selected), ...
        nnz(included == 1), nnz(isnan(included))}; %#ok<AGROW>
end
end

function value = fitPairs(plan, ir)
value = emptyFitPairs();
for index = 1:height(ir.anchor_fit_pairs)
    row = ir.anchor_fit_pairs(index, :);
    sourceKey = string(row.source_timebase_key(1));
    referenceKey = string(row.reference_timebase_key(1));
    if ~isKnownTimebase(plan, sourceKey) || ~isKnownTimebase(plan, referenceKey)
        continue
    end
    value(end + 1, :) = {sourceKey, referenceKey, ...
        double(row.fit_eligible_anchor_count(1))}; %#ok<AGROW>
end
end

function value = resolveTransformRuns(plan, bundle)
%RESOLVETRANSFORMRUNS One registered, unfitted transform per participating clock.
%
% A run is created only for a non-reference clock that anchors actually observe.
% Registering a transform for a clock with no anchor evidence would assert an
% intention the session cannot support.
value = repmat(emptyTransformRun(), 0, 1);
referenceKey = bundle.manifest.reference_timebase_key;
if ~plan.anchors.declared
    return
end
observed = unique(string(plan.anchors.ir.anchor_observations.timebase_key));
for index = 1:numel(observed)
    sourceKey = observed(index);
    if sourceKey == referenceKey
        continue
    end
    row = emptyTransformRun();
    row.source_timebase_key = sourceKey;
    row.reference_timebase_key = referenceKey;
    row.source_timebase_index = timebaseIndexOf(plan, sourceKey, "transform source");
    row.reference_timebase_index = timebaseIndexOf(plan, referenceKey, ...
        "transform reference");
    row.method = bundle.manifest.method;
    row.fit_eligible_anchor_count = eligibleCount(plan.anchors.fit_pairs, ...
        sourceKey, referenceKey);
    value(end + 1, 1) = row; %#ok<AGROW>
end
end

function value = eligibleCount(pairs, sourceKey, referenceKey)
value = 0;
if height(pairs) == 0
    return
end
selected = pairs.source_timebase_key == sourceKey & ...
    pairs.reference_timebase_key == referenceKey;
if any(selected)
    value = pairs.fit_eligible_anchor_count(find(selected, 1));
end
end

% ---------------------------------------------------------------- analysis ---

function analysis = resolveAnalysis(conn, plan, bundle)
analysis = struct(action="create", analysis_run_id=NaN, alignment_set_id=NaN, ...
    run_type="temporal_alignment", run_key=plan.context.run_key, ...
    conflict_message="");
rows = fetch(conn, "SELECT analysis_run_id, run_type, status FROM analysis_runs " + ...
    "WHERE project_id=" + string(plan.project.project_id) + ...
    " AND run_key=" + sqlText(plan.context.run_key));
if isempty(rows) || height(rows) == 0
    return
end
analysis.analysis_run_id = double(rows.analysis_run_id(1));
analysis.action = "reuse";
if presentText(rows.run_type(1)) ~= analysis.run_type
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' exists with run_type '" + presentText(rows.run_type(1)) + ...
        "', not '" + analysis.run_type + "'.";
    return
end

sets = fetch(conn, "SELECT alignment_set_id, reference_timebase_id, " + ...
    "IFNULL(manifest_source_file_id,-1) AS manifest_source_file_id, status " + ...
    "FROM alignment_sets WHERE analysis_run_id=" + string(analysis.analysis_run_id));
if isempty(sets) || height(sets) == 0
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' exists without an alignment set.";
    return
end
analysis.alignment_set_id = double(sets.alignment_set_id(1));

referenceIndex = timebaseIndexOf(plan, bundle.manifest.reference_timebase_key, ...
    "reference timebase");
storedReference = double(sets.reference_timebase_id(1));
plannedReference = plan.timebases(referenceIndex).timebase_id;
if isnan(plannedReference) || storedReference ~= plannedReference
    analysis.action = "conflict";
    analysis.conflict_message = "Alignment '" + analysis.run_key + ...
        "' is registered against a different reference timebase than the " + ...
        "manifest declares.";
    return
end

manifestIndex = find([plan.sources.role] == "manifest", 1);
storedManifest = double(sets.manifest_source_file_id(1));
plannedManifest = plan.sources(manifestIndex).source_file_id;
if isnan(plannedManifest) || storedManifest ~= plannedManifest
    analysis.action = "conflict";
    analysis.conflict_message = "Alignment '" + analysis.run_key + ...
        "' is registered against a different manifest than the one supplied.";
end
end

% ---------------------------------------------------------------- plumbing ---

function value = timebaseIndexOf(plan, timebaseKey, label)
value = find([plan.timebases.timebase_key] == timebaseKey, 1);
if isempty(value)
    error("vawlume:ingest:AlignmentTimebaseUndeclared", ...
        ['%s names timebase ''%s'', which the manifest does not declare. ' ...
        'Declare it in manifest.timebases rather than letting registration ' ...
        'invent a clock.'], label, timebaseKey);
end
end

function value = isKnownTimebase(plan, timebaseKey)
value = ~isempty(find([plan.timebases.timebase_key] == timebaseKey, 1));
end

function plan = appendConflict(plan, message)
if strlength(message) > 0
    plan.conflicts(end + 1, 1) = message;
end
end

function value = emptyTimebase()
value = struct(timebase_key="", timebase_kind="", recording_native=false, ...
    recording_id=NaN, native_unit="s", nominal_rate_hz=NaN, ...
    origin_description="", clock_identifier="", notes="", ...
    timebase_id=NaN, action="create", reused_name="");
end

function value = emptySource()
value = struct(role="", runtime_path="", relative_path="", filename="", ...
    file_role="", checksum_sha256="", size_bytes=NaN, ...
    source_file_id=NaN, action="create");
end

function value = emptyProfile()
value = struct(role="", profile_key="", profile_name="", profile_kind="", ...
    version_label="", profile_schema_version="", content_uri="", ...
    checksum_sha256="", profile_id=NaN, profile_version_id=NaN, ...
    profile_action="create", version_action="create");
end

function value = emptyStream()
value = struct(stream_key="", timebase_key="", timebase_index=NaN, ...
    stream_kind="", modality="", units="", source_role="events", ...
    ir=[], event_count=0, attribute_count=0, coverage_count=0, ...
    external_stream_id=NaN, action="create");
end

function value = emptyTransformRun()
value = struct(source_timebase_key="", reference_timebase_key="", ...
    source_timebase_index=NaN, reference_timebase_index=NaN, method="offset", ...
    fit_eligible_anchor_count=0, alignment_run_id=NaN, action="create");
end

function value = emptyObservationCounts()
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["timebase_key", "observation_count", "included_count", ...
    "unresolved_count"]);
end

function value = emptyFitPairs()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), ...
    VariableNames=["source_timebase_key", "reference_timebase_key", ...
    "fit_eligible_anchor_count"]);
end

function value = optionalText(container, field)
value = "";
if isfield(container, field)
    value = scalarText(container.(field), field);
end
end

function value = scalarText(raw, label)
try
    value = string(raw);
catch
    error("vawlume:ingest:AlignmentInvalidText", "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value)
    error("vawlume:ingest:AlignmentInvalidText", "%s must be scalar text.", label);
end
value = strtrim(value);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function value = sqlText(raw)
value = "'" + replace(string(raw), "'", "''") + "'";
end
