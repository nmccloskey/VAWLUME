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
    "IFNULL(r.sample_rate_hz,-1.0) AS sample_rate_hz, " + ...
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
% Every clock defaults to recording scope. Project scope is an explicit manifest
% declaration for a physical clock intentionally shared across recordings.
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
    row.scope = declaration.scope;
    row.recording_native = declaration.recording_native;
    row.native_unit = declaration.native_unit;
    row.nominal_rate_hz = declaration.nominal_rate_hz;
    row.origin_description = declaration.origin_description;
    row.clock_identifier = declaration.clock_identifier;
    row.notes = declaration.notes;

    if declaration.scope == "recording"
        row.recording_id = plan.recording.recording_id;
    end
    if declaration.recording_native
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
    elseif declaration.scope == "recording"
        existing = fetchNamedTimebase(conn, plan.project.project_id, ...
            plan.recording.recording_id, declaration.timebase_key);
    else
        existing = fetchNamedTimebase(conn, plan.project.project_id, NaN, ...
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
        if ~timebaseDeclarationMatches(existing, row)
            error("vawlume:ingest:AlignmentTimebaseConflict", ...
                ['Timebase ''%s'' already exists in %s scope with materially ' ...
                'different clock metadata. A changed clock declaration must use ' ...
                'a new key rather than rewriting prior provenance.'], ...
                declaration.timebase_key, declaration.scope);
        end
    end
    value(index) = row;
end
end

function value = fetchTimebaseForRecording(conn, recordingId)
rows = fetchTimebaseRows(conn, "recording_id=" + string(recordingId) + ...
    " AND is_recording_native=1");
value = timebaseStruct(rows);
end

function value = fetchNamedTimebase(conn, projectId, recordingId, timebaseKey)
scopePredicate = "recording_id IS NULL";
if ~isnan(recordingId)
    scopePredicate = "recording_id=" + string(recordingId);
end
rows = fetchTimebaseRows(conn, "project_id=" + string(projectId) + ...
    " AND " + scopePredicate + " AND timebase_name=" + sqlText(timebaseKey));
value = timebaseStruct(rows);
end

function rows = fetchTimebaseRows(conn, predicate)
rows = fetch(conn, "SELECT timebase_id, timebase_name, timebase_kind, " + ...
    "is_recording_native, native_unit, " + ...
    "IFNULL(nominal_rate_hz,-1.0) AS nominal_rate_hz, " + ...
    "IFNULL(origin_description,'') AS origin_description, " + ...
    "IFNULL(clock_identifier,'') AS clock_identifier, " + ...
    "IFNULL(notes,'') AS notes FROM timebases WHERE " + predicate);
end

function value = timebaseStruct(rows)
value = [];
if isempty(rows) || height(rows) == 0
    return
end
rate = double(rows.nominal_rate_hz(1));
if rate < 0, rate = NaN; end
value = struct(timebase_id=double(rows.timebase_id(1)), ...
    timebase_name=presentText(rows.timebase_name(1)), ...
    timebase_kind=presentText(rows.timebase_kind(1)), ...
    recording_native=logical(rows.is_recording_native(1)), ...
    native_unit=presentText(rows.native_unit(1)), nominal_rate_hz=rate, ...
    origin_description=presentText(rows.origin_description(1)), ...
    clock_identifier=presentText(rows.clock_identifier(1)), ...
    notes=presentText(rows.notes(1)));
end

function value = timebaseDeclarationMatches(existing, planned)
value = existing.timebase_kind == planned.timebase_kind && ...
    existing.recording_native == planned.recording_native && ...
    existing.native_unit == planned.native_unit && ...
    isequaln(existing.nominal_rate_hz, planned.nominal_rate_hz) && ...
    existing.origin_description == planned.origin_description && ...
    existing.clock_identifier == planned.clock_identifier && ...
    existing.notes == planned.notes;
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

    existing = fetch(conn, "SELECT external_stream_id, timebase_id, stream_kind, " + ...
        "IFNULL(modality,'') AS modality, IFNULL(units,'') AS units " + ...
        "FROM external_streams " + ...
        "WHERE recording_id=" + string(plan.recording.recording_id) + ...
        " AND stream_name=" + sqlText(row.stream_key));
    if isempty(existing) || height(existing) == 0
        row.action = "create";
    else
        row.external_stream_id = double(existing.external_stream_id(1));
        assertStreamReuseMatches(conn, plan, row, existing(1, :));
        row.action = "reuse";
    end
    value(index) = row;
end
end

function assertStreamReuseMatches(conn, plan, row, existing)
timebase = plan.timebases(row.timebase_index);
if isnan(timebase.timebase_id) || double(existing.timebase_id(1)) ~= timebase.timebase_id
    streamEvidenceConflict(row.stream_key, "resolved timebase identity differs");
end
if presentText(existing.stream_kind(1)) ~= row.stream_kind || ...
        presentText(existing.modality(1)) ~= row.modality || ...
        presentText(existing.units(1)) ~= row.units
    streamEvidenceConflict(row.stream_key, "stream kind, modality, or units differ");
end

links = fetch(conn, "SELECT ess.source_file_id, ess.source_role, " + ...
    "IFNULL(sf.checksum_sha256,'') AS source_checksum, " + ...
    "IFNULL(cpv.version_label,'') AS profile_version, " + ...
    "IFNULL(cpv.checksum_sha256,'') AS profile_checksum " + ...
    "FROM external_stream_sources ess " + ...
    "LEFT JOIN source_files sf ON sf.source_file_id=ess.source_file_id " + ...
    "LEFT JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=ess.mapping_profile_version_id " + ...
    "WHERE ess.external_stream_id=" + string(row.external_stream_id));
sourceIndex = find([plan.sources.role] == "stream:" + row.stream_key, 1);
if isempty(sourceIndex)
    if ~isempty(links) && height(links) > 0
        streamEvidenceConflict(row.stream_key, ...
            "stored source evidence exists but the new input is an in-memory table");
    end
elseif isempty(links) || height(links) ~= 1
    streamEvidenceConflict(row.stream_key, ...
        "the stored source-link population is not exactly the declared source");
else
    profileIndex = find([plan.profiles.role] == ...
        "external_stream_mapping:" + row.stream_key, 1);
    sourceMatches = presentText(links.source_checksum(1)) == ...
        plan.sources(sourceIndex).checksum_sha256 && ...
        ~isnan(plan.sources(sourceIndex).source_file_id) && ...
        double(links.source_file_id(1)) == plan.sources(sourceIndex).source_file_id;
    roleMatches = presentText(links.source_role(1)) == row.source_role;
    profileMatches = ~isempty(profileIndex) && ...
        presentText(links.profile_version(1)) == ...
            plan.profiles(profileIndex).version_label && ...
        presentText(links.profile_checksum(1)) == ...
            plan.profiles(profileIndex).checksum_sha256;
    if ~sourceMatches || ~roleMatches || ~profileMatches
        streamEvidenceConflict(row.stream_key, ...
            "source identity/checksum, source role, or mapping-profile evidence differs");
    end
end
if ~streamPopulationMatches(conn, row.external_stream_id, row.ir)
    streamEvidenceConflict(row.stream_key, ...
        "stored coverage, events, or attributes differ from the mapped population");
end
end

function streamEvidenceConflict(streamKey, detail)
error("vawlume:ingest:AlignmentStreamEvidenceConflict", ...
    ['Logical stream ''%s'' already exists with different immutable evidence: ' ...
    '%s. Register corrected or revised evidence under a new stream_key; ' ...
    'existing stream evidence is never replaced in place.'], streamKey, detail);
end

function value = streamPopulationMatches(conn, streamId, ir)
value = coveragePopulationMatches(conn, streamId, ir.coverage) && ...
    eventPopulationMatches(conn, streamId, ir.events) && ...
    attributePopulationMatches(conn, streamId, ir);
end

function value = coveragePopulationMatches(conn, streamId, expected)
actual = fetch(conn, "SELECT segment_index, start_time_native, end_time_native, " + ...
    "observation_status, IFNULL(source_locator,'') AS source_locator, " + ...
    "IFNULL(notes,'') AS notes FROM external_stream_coverage " + ...
    "WHERE external_stream_id=" + string(streamId) + " ORDER BY segment_index");
if height(actual) ~= height(expected)
    value = false;
    return
end
value = true;
for index = 1:height(expected)
    value = value && double(actual.segment_index(index)) == ...
        double(expected.segment_index(index)) && ...
        double(actual.start_time_native(index)) == ...
            double(expected.start_time_native(index)) && ...
        double(actual.end_time_native(index)) == ...
            double(expected.end_time_native(index)) && ...
        presentText(actual.observation_status(index)) == ...
            presentText(expected.observation_status(index)) && ...
        presentText(actual.source_locator(index)) == ...
            presentText(expected.source_locator(index)) && ...
        presentText(actual.notes(index)) == presentText(expected.mapping_rule(index));
end
end

function value = eventPopulationMatches(conn, streamId, expected)
actual = fetch(conn, "SELECT external_event_id, " + ...
    "IFNULL(native_event_id,'') AS native_event_id, " + ...
    "IFNULL(native_event_label,'') AS native_event_label, event_type, " + ...
    "start_time_native, end_time_native IS NULL AS end_missing, " + ...
    "IFNULL(end_time_native,0.0) AS end_time_native, " + ...
    "IFNULL(value_text,'') AS value_text, value_real IS NULL AS real_missing, " + ...
    "IFNULL(value_real,0.0) AS value_real, IFNULL(unit,'') AS unit, " + ...
    "IFNULL(mapping_rule_key,'') AS mapping_rule_key, " + ...
    "IFNULL(source_locator,'') AS source_locator FROM external_events " + ...
    "WHERE external_stream_id=" + string(streamId) + " ORDER BY external_event_id");
if height(actual) ~= height(expected)
    value = false;
    return
end
value = true;
for index = 1:height(expected)
    eventType = presentText(expected.normalized_event_key(index));
    if strlength(eventType) == 0
        eventType = presentText(expected.native_event_label(index));
    end
    unit = presentText(expected.scalar_unit(index));
    if strlength(unit) == 0
        unit = presentText(expected.native_time_unit(index));
    end
    expectedEnd = double(expected.end_time_s(index));
    expectedReal = double(expected.scalar_value_real(index));
    value = value && ...
        presentText(actual.native_event_id(index)) == ...
            presentText(expected.native_event_id(index)) && ...
        presentText(actual.native_event_label(index)) == ...
            presentText(expected.native_event_label(index)) && ...
        presentText(actual.event_type(index)) == eventType && ...
        double(actual.start_time_native(index)) == double(expected.start_time_s(index)) && ...
        logical(actual.end_missing(index)) == isnan(expectedEnd) && ...
        (isnan(expectedEnd) || double(actual.end_time_native(index)) == expectedEnd) && ...
        presentText(actual.value_text(index)) == ...
            presentText(expected.scalar_value_text(index)) && ...
        logical(actual.real_missing(index)) == isnan(expectedReal) && ...
        (isnan(expectedReal) || double(actual.value_real(index)) == expectedReal) && ...
        presentText(actual.unit(index)) == unit && ...
        presentText(actual.mapping_rule_key(index)) == ...
            presentText(expected.mapping_rule(index)) && ...
        presentText(actual.source_locator(index)) == ...
            presentText(expected.source_locator(index));
end
end

function value = attributePopulationMatches(conn, streamId, ir)
eventIds = fetch(conn, "SELECT external_event_id FROM external_events " + ...
    "WHERE external_stream_id=" + string(streamId) + " ORDER BY external_event_id");
actual = fetch(conn, "SELECT a.external_event_id, a.attribute_name, " + ...
    "IFNULL(a.native_field_name,'') AS native_field_name, a.value_type, " + ...
    "IFNULL(a.value_text,'') AS value_text, IFNULL(a.value_real,0.0) AS value_real, " + ...
    "IFNULL(a.value_integer,0) AS value_integer, " + ...
    "IFNULL(a.value_boolean,0) AS value_boolean, " + ...
    "IFNULL(a.native_raw_token,'') AS native_raw_token, " + ...
    "IFNULL(a.unit,'') AS unit, IFNULL(a.source_locator,'') AS source_locator, " + ...
    "IFNULL(a.mapping_rule_key,'') AS mapping_rule_key " + ...
    "FROM external_event_attributes a JOIN external_events e " + ...
    "ON e.external_event_id=a.external_event_id " + ...
    "WHERE e.external_stream_id=" + string(streamId) + ...
    " ORDER BY a.external_event_attribute_id");
expected = ir.event_attributes;
if height(actual) ~= height(expected)
    value = false;
    return
end
value = true;
for index = 1:height(expected)
    expectedEventIndex = find(ir.events.event_key == expected.event_key(index), 1);
    actualEventIndex = find(double(eventIds.external_event_id) == ...
        double(actual.external_event_id(index)), 1);
    valueType = plannedAttributeValueType(expected(index, :));
    value = value && ~isempty(expectedEventIndex) && ...
        isequal(actualEventIndex, expectedEventIndex) && ...
        presentText(actual.attribute_name(index)) == ...
            presentText(expected.attribute_name(index)) && ...
        presentText(actual.native_field_name(index)) == ...
            presentText(expected.native_field(index)) && ...
        presentText(actual.value_type(index)) == valueType && ...
        presentText(actual.native_raw_token(index)) == ...
            presentText(expected.raw_value(index)) && ...
        presentText(actual.unit(index)) == presentText(expected.normalized_unit(index)) && ...
        presentText(actual.source_locator(index)) == ...
            presentText(expected.source_locator(index)) && ...
        presentText(actual.mapping_rule_key(index)) == ...
            presentText(expected.mapping_rule(index));
    switch valueType
        case "text"
            value = value && presentText(actual.value_text(index)) == ...
                presentText(expected.value_text(index));
        case "real"
            value = value && double(actual.value_real(index)) == ...
                double(expected.value_real(index));
        case "integer"
            value = value && double(actual.value_integer(index)) == ...
                double(expected.value_integer(index));
        case "boolean"
            value = value && double(actual.value_boolean(index)) == ...
                double(expected.value_boolean(index));
    end
end
end

function value = plannedAttributeValueType(row)
value = presentText(row.value_type(1));
switch value
    case "real"
        if isnan(double(row.value_real(1))), value = "missing"; end
    case "integer"
        if isnan(double(row.value_integer(1))), value = "missing"; end
    case "boolean"
        if isnan(double(row.value_boolean(1))), value = "missing"; end
    case "text"
        if strlength(presentText(row.value_text(1))) == 0, value = "missing"; end
    otherwise
        value = "missing";
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
validateResolvedEventReferences(plan, ir);
value.observations_by_timebase = observationCounts(ir);
value.fit_pairs = fitPairs(plan, ir);
end

function validateResolvedEventReferences(plan, ir)
observations = ir.anchor_observations;
rows = find(strlength(observations.event_native_event_id) > 0 & ...
    strlength(observations.event_stream_key) > 0 & observations.status ~= "invalid");
for rowIndex = rows'
    streamKey = string(observations.event_stream_key(rowIndex));
    nativeId = string(observations.event_native_event_id(rowIndex));
    streamIndex = find([plan.streams.stream_key] == streamKey);
    if numel(streamIndex) ~= 1
        error("vawlume:ingest:AlignmentEventReferenceUnresolved", ...
            "Resolved event stream '%s' is not unique in the alignment plan.", streamKey);
    end
    events = plan.streams(streamIndex).ir.events;
    if nnz(events.native_event_id == nativeId) ~= 1
        error("vawlume:ingest:AlignmentEventReferenceUnresolved", ...
            ['Native event ID ''%s'' is not unique in resolved event stream ''%s''. ' ...
            'No database writes were attempted.'], nativeId, streamKey);
    end
end
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
value = struct(timebase_key="", timebase_kind="", scope="recording", ...
    recording_native=false, ...
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
