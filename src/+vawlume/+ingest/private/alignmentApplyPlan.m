function [plan, counts] = alignmentApplyPlan(conn, plan)
%ALIGNMENTAPPLYPLAN Atomically register one alignment session.
%
% Everything a manifest describes commits together or not at all. A failure part
% way through must not leave an analysis run claiming an alignment exists while
% only some of its streams, events, or anchors do, so the whole registration runs
% inside one transaction and any exception rolls it back before rethrowing.
%
% No transform is fitted here. Segments and residuals stay empty, and each
% pairwise run is written with status 'registered' so nothing claims a fit it
% does not have.

if plan.has_conflicts
    error("vawlume:ingest:AlignmentPlanConflict", ...
        "An alignment plan with identity conflicts cannot be applied.");
end
counts = emptyCounts();
if plan.analysis.action == "reuse"
    counts = reuseCounts(plan, counts);
    plan.status = "reused";
    return
end

oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:ingest:AlignmentTransactionState", ...
        "Alignment apply requires a connection with AutoCommit enabled.");
end
conn.AutoCommit = "off";
try
    [plan, counts] = applySources(conn, plan, counts);
    [plan, counts] = applyProfiles(conn, plan, counts);
    [plan, counts] = applyTimebases(conn, plan, counts);
    [plan, counts] = applyAnalysis(conn, plan, counts);
    [plan, counts] = applyStreams(conn, plan, counts);
    [plan, counts] = applyAnchors(conn, plan, counts);
    [plan, counts] = applyTransformRuns(conn, plan, counts);
    execute(conn, "UPDATE analysis_runs SET status='completed', " + ...
        "completed_at_utc=strftime('%Y-%m-%dT%H:%M:%fZ','now') " + ...
        "WHERE analysis_run_id=" + string(plan.analysis.analysis_run_id));
    commit(conn);
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
plan.status = "committed";
end

% ---------------------------------------------------------------- sources ---

function [plan, counts] = applySources(conn, plan, counts)
for index = 1:numel(plan.sources)
    row = plan.sources(index);
    if row.action == "reuse"
        counts.reused_source_files = counts.reused_source_files + 1;
        continue
    end
    values = struct(project_id=plan.project.project_id, ...
        file_role=row.file_role, path_or_uri=row.runtime_path, ...
        relative_path=row.relative_path, filename=row.filename, ...
        file_format=formatOf(row.filename), ...
        checksum_sha256=row.checksum_sha256);
    if ~isnan(row.size_bytes)
        values.size_bytes = row.size_bytes;
    end
    plan.sources(index).source_file_id = insertIntakeRow(conn, "source_files", ...
        values, "source_file_id");
    counts.source_files = counts.source_files + 1;
end
end

function [plan, counts] = applyProfiles(conn, plan, counts)
for index = 1:numel(plan.profiles)
    row = plan.profiles(index);
    if row.profile_action == "create"
        plan.profiles(index).profile_id = insertIntakeRow(conn, "config_profiles", ...
            struct(project_id=plan.project.project_id, profile_key=row.profile_key, ...
            profile_name=row.profile_name, profile_kind=row.profile_kind, ...
            is_builtin=0, ...
            description="Mapping profile registered by alignment intake."), ...
            "profile_id");
        counts.config_profiles = counts.config_profiles + 1;
    else
        counts.reused_config_profiles = counts.reused_config_profiles + 1;
    end
    if row.version_action == "create"
        plan.profiles(index).profile_version_id = insertIntakeRow(conn, ...
            "config_profile_versions", struct( ...
            profile_id=plan.profiles(index).profile_id, ...
            version_label=row.version_label, ...
            profile_schema_version=row.profile_schema_version, ...
            content_format="json", content_uri=row.content_uri, ...
            checksum_sha256=row.checksum_sha256, is_snapshot=1, ...
            notes="Exact mapping profile used by one alignment registration."), ...
            "profile_version_id");
        counts.config_profile_versions = counts.config_profile_versions + 1;
    else
        counts.reused_config_profile_versions = ...
            counts.reused_config_profile_versions + 1;
    end
end
end

function [plan, counts] = applyTimebases(conn, plan, counts)
for index = 1:numel(plan.timebases)
    row = plan.timebases(index);
    if row.action == "reuse"
        counts.reused_timebases = counts.reused_timebases + 1;
        continue
    end
    values = struct(project_id=plan.project.project_id, ...
        timebase_name=row.timebase_key, timebase_kind=row.timebase_kind, ...
        is_recording_native=double(row.recording_native), ...
        native_unit=row.native_unit, origin_description=row.origin_description, ...
        clock_identifier=row.clock_identifier, notes=row.notes);
    if ~isnan(row.recording_id)
        values.recording_id = row.recording_id;
    end
    if ~isnan(row.nominal_rate_hz)
        values.nominal_rate_hz = row.nominal_rate_hz;
    end
    plan.timebases(index).timebase_id = insertIntakeRow(conn, "timebases", ...
        values, "timebase_id");
    counts.timebases = counts.timebases + 1;
end
end

% --------------------------------------------------------------- analysis ---

function [plan, counts] = applyAnalysis(conn, plan, counts)
plan.analysis.analysis_run_id = insertIntakeRow(conn, "analysis_runs", struct( ...
    project_id=plan.project.project_id, run_type=plan.analysis.run_type, ...
    run_key=plan.context.run_key, run_label=plan.context.run_label, ...
    vawlume_version=plan.context.vawlume_version, ...
    source_commit=plan.context.source_commit, status="started", ...
    notes=analysisNotes(plan)), "analysis_run_id");
counts.analysis_runs = 1;

for index = 1:numel(plan.profiles)
    insertIntakeRow(conn, "analysis_run_profiles", struct( ...
        analysis_run_id=plan.analysis.analysis_run_id, ...
        profile_version_id=plan.profiles(index).profile_version_id, ...
        assignment_role=assignmentRole(plan.profiles(index))));
    counts.analysis_run_profiles = counts.analysis_run_profiles + 1;
end

manifestIndex = find([plan.sources.role] == "manifest", 1);
referenceIndex = find([plan.timebases.timebase_key] == ...
    plan.bundle.manifest.reference_timebase_key, 1);
plan.analysis.alignment_set_id = insertIntakeRow(conn, "alignment_sets", struct( ...
    analysis_run_id=plan.analysis.analysis_run_id, ...
    recording_id=plan.recording.recording_id, ...
    reference_timebase_id=plan.timebases(referenceIndex).timebase_id, ...
    manifest_source_file_id=plan.sources(manifestIndex).source_file_id, ...
    alignment_set_key=plan.context.run_key, ...
    status="draft", ...
    notes="Registered from a session alignment manifest; no transform fitted."), ...
    "alignment_set_id");
counts.alignment_sets = 1;
end

function value = profileIndexFor(plan, streamKey)
%PROFILEINDEXFOR The mapping profile registered for one stream's source.
value = find([plan.profiles.role] == "external_stream_mapping:" + streamKey, 1);
end

function value = assignmentRole(profile)
if profile.profile_kind == "alignment_anchor_mapping"
    value = "alignment_anchor_mapping";
    return
end
value = "external_stream_mapping";
end

function value = analysisNotes(plan)
value = string(jsonencode(struct( ...
    manifest_schema_version=plan.bundle.manifest.manifest_schema_version, ...
    manifest_version=plan.bundle.manifest.manifest_version, ...
    manifest_checksum_sha256=plan.bundle.manifest.checksum_sha256, ...
    manifest_content_uri=plan.bundle.manifest.content_uri, ...
    reference_timebase=plan.bundle.manifest.reference_timebase_key, ...
    declared_method=plan.bundle.manifest.method, ...
    transforms_fitted=false, ...
    stage="registration_only")));
end

% ----------------------------------------------------- streams and events ---

function [plan, counts] = applyStreams(conn, plan, counts)
for index = 1:numel(plan.streams)
    row = plan.streams(index);
    timebase = plan.timebases(row.timebase_index);
    if row.action == "reuse"
        % A logical stream belongs to its recording, not to one alignment set.
        % It and its events were materialized by an earlier registration, so a
        % second alignment over the same session references them rather than
        % inserting a duplicate population.
        counts.reused_external_streams = counts.reused_external_streams + 1;
        plan.streams(index).event_ids = existingEventIds(conn, ...
            row.external_stream_id);
        continue
    end

    plan.streams(index).external_stream_id = insertIntakeRow(conn, ...
        "external_streams", struct(project_id=plan.project.project_id, ...
        recording_id=plan.recording.recording_id, ...
        timebase_id=timebase.timebase_id, stream_name=row.stream_key, ...
        stream_kind=row.stream_kind, modality=row.modality, ...
        units=row.units, ...
        notes="Registered by alignment intake from a validated mapping IR."), ...
        "external_stream_id");
    counts.external_streams = counts.external_streams + 1;
    streamId = plan.streams(index).external_stream_id;

    sourceIndex = find([plan.sources.role] == "stream:" + row.stream_key, 1);
    if ~isempty(sourceIndex)
        profileIndex = profileIndexFor(plan, row.stream_key);
        values = struct(external_stream_id=streamId, ...
            source_file_id=plan.sources(sourceIndex).source_file_id, ...
            source_role=row.source_role, ...
            source_locator=plan.sources(sourceIndex).relative_path);
        if ~isempty(profileIndex)
            values.mapping_profile_version_id = ...
                plan.profiles(profileIndex).profile_version_id;
        end
        insertIntakeRow(conn, "external_stream_sources", values, ...
            "external_stream_source_id");
        counts.external_stream_sources = counts.external_stream_sources + 1;
    end

    counts = applyCoverage(conn, streamId, row.ir, counts);
    [eventIds, counts] = applyEvents(conn, plan, streamId, row.ir, counts);
    counts = applyEventAttributes(conn, row.ir, eventIds, counts);
    plan.streams(index).event_ids = eventIds;
end
end

function value = existingEventIds(conn, streamId)
%EXISTINGEVENTIDS Native event ID to surrogate ID for an already-registered stream.
%
% Anchor observations in a later alignment still need to resolve their event
% references, and those events already exist.
value = dictionary(string.empty, double.empty);
rows = fetch(conn, "SELECT external_event_id, " + ...
    "IFNULL(native_event_id,'') AS native_event_id FROM external_events " + ...
    "WHERE external_stream_id=" + string(streamId));
for index = 1:height(rows)
    nativeId = presentText(rows.native_event_id(index));
    if strlength(nativeId) == 0
        continue
    end
    value("native:" + nativeId) = double(rows.external_event_id(index));
end
end

function counts = applyCoverage(conn, streamId, ir, counts)
for index = 1:height(ir.coverage)
    row = ir.coverage(index, :);
    insertIntakeRow(conn, "external_stream_coverage", struct( ...
        external_stream_id=streamId, ...
        segment_index=double(row.segment_index(1)), ...
        start_time_native=double(row.start_time_native(1)), ...
        end_time_native=double(row.end_time_native(1)), ...
        observation_status=presentText(row.observation_status(1)), ...
        source_locator=presentText(row.source_locator(1)), ...
        notes=presentText(row.mapping_rule(1))), "external_stream_coverage_id");
    counts.external_stream_coverage = counts.external_stream_coverage + 1;
end
end

function [eventIds, counts] = applyEvents(conn, plan, streamId, ir, counts)
%APPLYEVENTS Insert one row per mapped event, keyed by its IR event key.
%
% Native IDs are preserved when the source supplied them and left NULL when it
% did not. No surrogate native ID is invented, because a fabricated identifier
% would later be indistinguishable from one the source actually provided.
eventIds = dictionary(string.empty, double.empty);
entityCache = dictionary(string.empty, double.empty);
for index = 1:height(ir.events)
    row = ir.events(index, :);
    values = struct(external_stream_id=streamId, ...
        event_type=presentText(row.normalized_event_key(1)), ...
        start_time_native=double(row.start_time_s(1)), ...
        native_event_id=presentText(row.native_event_id(1)), ...
        native_event_label=presentText(row.native_event_label(1)), ...
        mapping_rule_key=presentText(row.mapping_rule(1)), ...
        source_locator=presentText(row.source_locator(1)));
    if strlength(values.event_type) == 0
        values.event_type = presentText(row.native_event_label(1));
    end
    endTime = double(row.end_time_s(1));
    if ~isnan(endTime)
        values.end_time_native = endTime;
    end
    scalarText = presentText(row.scalar_value_text(1));
    if strlength(scalarText) > 0
        values.value_text = scalarText;
    end
    scalarReal = double(row.scalar_value_real(1));
    if ~isnan(scalarReal)
        values.value_real = scalarReal;
    end
    unit = presentText(row.scalar_unit(1));
    if strlength(unit) == 0
        unit = presentText(row.native_time_unit(1));
    end
    values.unit = unit;
    [entityId, entityCache] = resolveEntity(conn, plan, entityCache, ...
        presentText(row.entity_key(1)));
    if ~isnan(entityId)
        values.entity_id = entityId;
    end
    eventIds(string(row.event_key(1))) = insertIntakeRow(conn, "external_events", ...
        values, "external_event_id");
    counts.external_events = counts.external_events + 1;
end
end

function [value, cache] = resolveEntity(conn, plan, cache, entityKey)
%RESOLVEENTITY Link an event to an existing subject when the source names one.
%
% An unmatched key is left unlinked rather than creating an entity. Experimental
% hierarchy belongs to project intake; inventing a subject from a behaviour table
% would fabricate the very metadata VAWLUME exists to keep honest.
value = NaN;
if strlength(entityKey) == 0
    return
end
if isKey(cache, entityKey)
    value = cache(entityKey);
    return
end
rows = fetch(conn, "SELECT entity_id FROM experimental_entities " + ...
    "WHERE project_id=" + string(plan.project.project_id) + ...
    " AND native_id='" + replace(entityKey, "'", "''") + "'");
if ~isempty(rows) && height(rows) > 0
    value = double(rows.entity_id(1));
end
cache(entityKey) = value;
end

function counts = applyEventAttributes(conn, ir, eventIds, counts)
for index = 1:height(ir.event_attributes)
    row = ir.event_attributes(index, :);
    eventKey = string(row.event_key(1));
    if ~isKey(eventIds, eventKey)
        continue
    end
    values = struct(external_event_id=eventIds(eventKey), ...
        attribute_name=presentText(row.attribute_name(1)), ...
        native_field_name=presentText(row.native_field(1)), ...
        value_type=attributeValueType(row), ...
        native_raw_token=presentText(row.raw_value(1)), ...
        unit=presentText(row.normalized_unit(1)), ...
        source_locator=presentText(row.source_locator(1)), ...
        mapping_rule_key=presentText(row.mapping_rule(1)));
    switch values.value_type
        case "real"
            values.value_real = double(row.value_real(1));
        case "integer"
            values.value_integer = double(row.value_integer(1));
        case "boolean"
            values.value_boolean = double(row.value_boolean(1));
        case "text"
            values.value_text = presentText(row.value_text(1));
    end
    insertIntakeRow(conn, "external_event_attributes", values, ...
        "external_event_attribute_id");
    counts.external_event_attributes = counts.external_event_attributes + 1;
end
end

function value = attributeValueType(row)
%ATTRIBUTEVALUETYPE Keep an unmapped attribute explicitly missing.
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

% ---------------------------------------------------- anchors and runs ---

function [plan, counts] = applyAnchors(conn, plan, counts)
if ~plan.anchors.declared
    return
end
ir = plan.anchors.ir;
eventLookup = eventIdLookup(plan);
anchorIds = dictionary(string.empty, double.empty);
for index = 1:height(ir.anchors)
    row = ir.anchors(index, :);
    values = struct(alignment_set_id=plan.analysis.alignment_set_id, ...
        anchor_key=presentText(row.anchor_key(1)), ...
        anchor_type=presentText(row.anchor_type(1)), ...
        notes=presentText(row.mapping_rule(1)));
    if strlength(values.anchor_type) == 0
        values.anchor_type = "sync_marker";
    end
    expectedOrder = double(row.expected_order(1));
    if ~isnan(expectedOrder) && expectedOrder >= 1
        values.expected_order = expectedOrder;
    end
    anchorIds(values.anchor_key) = insertIntakeRow(conn, "alignment_anchors", ...
        values, "alignment_anchor_id");
    counts.alignment_anchors = counts.alignment_anchors + 1;
end

for index = 1:height(ir.anchor_observations)
    row = ir.anchor_observations(index, :);
    anchorKey = presentText(row.anchor_key(1));
    if ~isKey(anchorIds, anchorKey)
        error("vawlume:ingest:AlignmentAnchorMissing", ...
            "Anchor observation references unknown anchor key '%s'.", anchorKey);
    end
    timebaseIndex = find([plan.timebases.timebase_key] == ...
        presentText(row.timebase_key(1)), 1);
    values = struct(alignment_anchor_id=anchorIds(anchorKey), ...
        timebase_id=plan.timebases(timebaseIndex).timebase_id, ...
        observed_time_native=double(row.observed_time_s(1)), ...
        observation_role=observationRole(row), ...
        included_in_fit=inclusionOf(row), ...
        source_locator=presentText(row.source_locator(1)), ...
        notes=presentText(row.mapping_rule(1)));
    uncertainty = double(row.uncertainty_s(1));
    if ~isnan(uncertainty)
        values.uncertainty_s = uncertainty;
    end
    profileIndex = find([plan.profiles.profile_kind] == "alignment_anchor_mapping", 1);
    if ~isempty(profileIndex)
        values.mapping_profile_version_id = ...
            plan.profiles(profileIndex).profile_version_id;
    end
    eventId = resolveObservationEvent(eventLookup, row);
    if ~isnan(eventId)
        values.external_event_id = eventId;
    end
    insertIntakeRow(conn, "alignment_anchor_observations", values, ...
        "anchor_observation_id");
    counts.alignment_anchor_observations = counts.alignment_anchor_observations + 1;
end
end

function value = observationRole(row)
value = presentText(row.observation_role(1));
if strlength(value) == 0
    value = "primary";
end
if ~ismember(value, ["primary", "replicate", "excluded"])
    value = "replicate";
end
if value ~= "excluded" && inclusionOf(row) == 0 && value == "primary"
    % A row that is not in the fit cannot also be the primary reading.
    value = "replicate";
end
end

function value = inclusionOf(row)
%INCLUSIONOF Unresolved inclusion is registered as excluded, never guessed.
%
% The IR leaves inclusion NaN when a duplicate group has no explicit resolution.
% Such evidence is still worth keeping, so it is stored with included_in_fit = 0
% rather than discarded or silently promoted to the fit.
value = double(row.included_in_fit(1));
if isnan(value) || value ~= 1
    value = 0;
end
end

function value = eventIdLookup(plan)
%EVENTIDLOOKUP Stream-scoped native event ID to surrogate ID.
%
% Scoped by stream because native IDs are only unique within their own source; two
% streams may legitimately both number their rows from 1.
value = dictionary(string.empty, double.empty);
for index = 1:numel(plan.streams)
    stream = plan.streams(index);
    if ~isfield(stream, "event_ids") || isempty(stream.event_ids)
        continue
    end
    entries = stream.event_ids;
    entryKeys = keys(entries);
    for position = 1:numel(entryKeys)
        entryKey = entryKeys(position);
        if startsWith(entryKey, "native:")
            nativeId = extractAfter(entryKey, "native:");
        else
            nativeId = nativeIdForEventKey(stream.ir, entryKey);
        end
        if strlength(nativeId) == 0
            continue
        end
        value(stream.stream_key + "|" + nativeId) = entries(entryKey);
    end
end
end

function value = nativeIdForEventKey(ir, eventKey)
value = "";
selected = ir.events.event_key == eventKey;
if any(selected)
    value = presentText(ir.events.native_event_id(find(selected, 1)));
end
end

function value = resolveObservationEvent(lookup, row)
value = NaN;
nativeId = presentText(row.event_native_event_id(1));
if strlength(nativeId) == 0
    return
end
streamKey = presentText(row.stream_key(1));
candidate = streamKey + "|" + nativeId;
if isKey(lookup, candidate)
    value = lookup(candidate);
end
end

function [plan, counts] = applyTransformRuns(conn, plan, counts)
for index = 1:numel(plan.transform_runs)
    row = plan.transform_runs(index);
    plan.transform_runs(index).alignment_run_id = insertIntakeRow(conn, ...
        "time_alignment_runs", struct( ...
        alignment_set_id=plan.analysis.alignment_set_id, ...
        source_timebase_id=plan.timebases(row.source_timebase_index).timebase_id, ...
        target_timebase_id=plan.timebases(row.reference_timebase_index).timebase_id, ...
        method=row.method, ...
        n_anchors_used=row.fit_eligible_anchor_count, ...
        status="registered", ...
        notes="Registered by alignment intake. No transform fitted."), ...
        "alignment_run_id");
    counts.time_alignment_runs = counts.time_alignment_runs + 1;
end
end

% ---------------------------------------------------------------- shaping ---

function counts = reuseCounts(plan, counts)
counts.reused_analysis_runs = 1;
counts.reused_alignment_sets = 1;
counts.reused_external_streams = numel(plan.streams);
counts.reused_timebases = numel(plan.timebases);
end

function counts = emptyCounts()
counts = struct(source_files=0, config_profiles=0, config_profile_versions=0, ...
    timebases=0, analysis_runs=0, analysis_run_profiles=0, alignment_sets=0, ...
    external_streams=0, external_stream_sources=0, external_stream_coverage=0, ...
    external_events=0, external_event_attributes=0, alignment_anchors=0, ...
    alignment_anchor_observations=0, time_alignment_runs=0, ...
    reused_source_files=0, reused_config_profiles=0, ...
    reused_config_profile_versions=0, reused_timebases=0, ...
    reused_analysis_runs=0, reused_alignment_sets=0, reused_external_streams=0);
end

function value = formatOf(filename)
[~, ~, extension] = fileparts(string(filename));
value = lower(erase(extension, "."));
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
