function result = measureCallWindow(conn, eventRef, channelIndices, options)
%MEASURECALLWINDOW Measure one vocal event's window on each requested channel.
%
%   result = VAWLUME.ACOUSTIC.MEASURECALLWINDOW(conn, ...
%       struct(detection_id=ID), [1 2], SourceRoot=root, BandHz=[f1 f2])
%   result = VAWLUME.ACOUSTIC.MEASURECALLWINDOW(conn, ...
%       struct(consensus_event_id=ID), [1 2], ..., Apply=true, RunKey="key")
%
% The fixed method vawlume.acoustic.call_window_response version 1.0.0
% (contract 06 D6). The window is the event's own native interval on the
% recording-native audio clock: no padding and no clock transform, because the
% audio and the event share a timebase. RMS, peak absolute amplitude and band
% power come from the same core as measureReferenceResponse, under doc 27's
% conventions, and are stored under the call_* metric keys.
%
% The band is declared, never inferred. BandHz=[min max] is the only source of
% a band; the event's own frequency bounds are not used. With no BandHz there is
% no band power, and band_state says "not_declared".
%
% Each requested channel is measured independently. A channel that cannot be
% read (undeclared, absent from the file, or a failed sample read) is that
% channel's failure, reported with its error; the other channels are still
% measured. A broken recording link (missing or unsupported artifact, metadata
% mismatch, no SourceRoot for a relative path) fails every channel alike and is
% raised instead.
%
% Agreement-group targets are refused: derived_measurements has no
% agreement-group target column. This function normalizes nothing and compares
% no channels with each other.
%
% Apply=false (default) is read-only. Apply=true creates, or exactly reuses,
% one analysis run of type acoustic_call_window_response and one
% derived_measurements row per (event, channel, metric). A run key that already
% identifies different provenance, a different target, or different values
% raises vawlume:acoustic:MeasurementRunConflict.

arguments
    conn
    eventRef (1,1) struct
    channelIndices (1,:) double
    options.BandHz double = []
    options.SourceRoot (1,1) string = ""
    options.Apply (1,1) logical = false
    options.RunKey (1,1) string = ""
    options.RunLabel (1,1) string = ""
    options.VawlumeVersion (1,1) string = ""
    options.SourceCommit (1,1) string = ""
    options.Notes (1,1) string = ""
end

event = resolveEvent(conn, eventRef);
validateChannels(channelIndices);
band = declaredBand(options.BandHz);

channels = repmat(emptyChannel(), 1, 0);
for channelIndex = channelIndices
    channels(end + 1) = measureChannel(conn, event, channelIndex, band, ...
        channelIndices, options.SourceRoot); %#ok<AGROW>
end
status = runStatus(channels);

analysisRunId = NaN;
action = "planned";
if options.Apply
    if ismissing(options.RunKey) || strlength(options.RunKey) == 0
        error("vawlume:acoustic:RunKeyRequired", ...
            "RunKey is required when Apply=true.");
    end
    [analysisRunId, channels, action] = persistMeasurements(conn, event, ...
        channels, status, options);
end

result = struct( ...
    target_kind=event.target_kind, ...
    detection_id=event.detection_id, ...
    consensus_event_id=event.consensus_event_id, ...
    recording_id=event.recording_id, ...
    event_interval_s=[event.start_time_s event.end_time_s], ...
    band_hz=band, ...
    status=status, ...
    channels=channels, ...
    measurements=measurementTable(channels), ...
    method_key=methodKey(), ...
    method_version=methodVersion(), ...
    run_type=runType(), ...
    analysis_run_id=analysisRunId, ...
    action=action);
end

function value = methodKey()
value = "vawlume.acoustic.call_window_response";
end

function value = methodVersion()
value = "1.0.0";
end

function value = runType()
value = "acoustic_call_window_response";
end

% ------------------------------------------------------------ resolution ---

function event = resolveEvent(conn, ref)
names = string(fieldnames(ref));
if any(names == "agreement_group_id")
    error("vawlume:acoustic:AgreementGroupTargetUnsupported", ...
        "Agreement groups cannot be call-window measurement targets in v1: " + ...
        "derived_measurements has no agreement-group target. Measure a member " + ...
        "detection or a consensus event instead.");
end
if numel(names) ~= 1 || ~any(names == ["detection_id", "consensus_event_id"])
    error("vawlume:acoustic:EventRefInvalid", ...
        "eventRef must contain exactly one of detection_id or consensus_event_id.");
end
id = double(ref.(names));
if ~isscalar(id) || ~isfinite(id) || id < 1 || id ~= floor(id)
    error("vawlume:acoustic:EventRefInvalid", ...
        "eventRef.%s must be a positive integer.", names);
end
if names == "detection_id"
    rows = fetch(conn, "SELECT d.recording_id, r.project_id, d.start_time_s, " + ...
        "d.end_time_s FROM detections d JOIN recordings r " + ...
        "ON r.recording_id=d.recording_id WHERE d.detection_id=" + string(id));
    kind = "detection";
else
    rows = fetch(conn, "SELECT ce.recording_id, r.project_id, ce.start_time_s, " + ...
        "ce.end_time_s FROM consensus_events ce JOIN recordings r " + ...
        "ON r.recording_id=ce.recording_id WHERE ce.consensus_event_id=" + string(id));
    kind = "consensus_event";
end
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:EventNotFound", "No %s %d exists.", ...
        replace(kind, "_", " "), id);
end
event = struct(target_kind=kind, target_column=names, target_id=id, ...
    detection_id=NaN, consensus_event_id=NaN, ...
    recording_id=double(rows.recording_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    start_time_s=double(rows.start_time_s(1)), ...
    end_time_s=double(rows.end_time_s(1)));
event.(names) = id;
end

function validateChannels(channelIndices)
if isempty(channelIndices) || any(~isfinite(channelIndices)) || ...
        any(channelIndices < 1) || any(channelIndices ~= floor(channelIndices))
    error("vawlume:acoustic:ChannelSetInvalid", ...
        "channelIndices must be a nonempty list of positive integers.");
end
if numel(unique(channelIndices)) ~= numel(channelIndices)
    error("vawlume:acoustic:ChannelSetInvalid", ...
        "channelIndices must not repeat a channel.");
end
end

function band = declaredBand(raw)
% A declaration is [min max]. A NaN bound is carried to the core, which reports
% it as an incomplete band, exactly as an incomplete reference band is reported.
if isempty(raw)
    band = zeros(1, 0);
    return
end
if ~isnumeric(raw) || numel(raw) ~= 2 || any(isinf(raw))
    error("vawlume:acoustic:CallBandInvalid", ...
        "BandHz must be empty or a two-element [min max] declaration in Hz.");
end
band = double(raw(:)');
end

% ----------------------------------------------------------- measurement ---

function channel = measureChannel(conn, event, channelIndex, band, requested, sourceRoot)
channel = emptyChannel();
channel.channel_index = channelIndex;
try
    window = vawlume.acoustic.readAudioWindow(conn, ...
        struct(recording_id=event.recording_id), channelIndex, ...
        event.start_time_s, event.end_time_s, SourceRoot=sourceRoot);
catch exception
    if ~any(exception.identifier == channelScopedErrors())
        rethrow(exception);
    end
    channel.recording_channel_id = declaredChannelId(conn, event.recording_id, channelIndex);
    channel.status = "failed";
    channel.coverage_status = "unreadable";
    channel.band_state = "not_examined";
    channel.qc_flags = "channel_unreadable";
    channel.error_identifier = string(exception.identifier);
    channel.error_message = string(exception.message);
    return
end

if isempty(band)
    [bandMin, bandMax] = deal(NaN);
else
    [bandMin, bandMax] = deal(band(1), band(2));
end
[metrics, bandState] = acousticWindowMetrics(window.samples, ...
    window.sample_rate_hz, bandMin, bandMax);
metrics.metric_key = "call_" + metrics.metric_key;
qcFlags = unique([window.qc_flags; bandFlags(bandState)], "stable");

if window.sample_count == 0
    status = "failed";
elseif isempty(qcFlags)
    status = "completed";
else
    status = "completed_with_warnings";
end

channel.recording_channel_id = window.recording_channel_id;
channel.status = status;
channel.coverage_status = window.status;
channel.band_state = bandState;
channel.qc_flags = qcFlags;
channel.clipped_sample_count = window.clipped_sample_count;
channel.metrics = metrics;
channel.audio_window = window;
channel.derivation_details = derivationDetails(event, window, band, ...
    bandState, qcFlags, requested);
end

function ids = channelScopedErrors()
% Errors about one channel. Every other reader error concerns the recording's
% audio link as a whole and is raised to the caller.
ids = ["vawlume:acoustic:ChannelNotFound", ...
    "vawlume:acoustic:UnsupportedChannelLayout", ...
    "vawlume:acoustic:AudioWindowReadFailed"];
end

function id = declaredChannelId(conn, recordingId, channelIndex)
rows = fetch(conn, "SELECT recording_channel_id FROM recording_channels " + ...
    "WHERE recording_id=" + string(recordingId) + ...
    " AND channel_index=" + string(channelIndex));
if isempty(rows) || height(rows) == 0
    id = NaN;
else
    id = double(rows.recording_channel_id(1));
end
end

function flags = bandFlags(bandState)
switch bandState
    case "incomplete"
        flags = "incomplete_call_band";
    case "invalid"
        flags = "invalid_call_band";
    case "above_nyquist"
        flags = "call_band_above_nyquist";
    otherwise
        flags = strings(0, 1);
end
end

function status = runStatus(channels)
statuses = [channels.status];
if all(statuses == "failed")
    status = "failed";
elseif all(statuses == "completed")
    status = "completed";
else
    status = "completed_with_warnings";
end
end

function channel = emptyChannel()
channel = struct( ...
    channel_index=NaN, ...
    recording_channel_id=NaN, ...
    status="", ...
    coverage_status="", ...
    band_state="", ...
    qc_flags=strings(0, 1), ...
    clipped_sample_count=0, ...
    metrics=table(Size=[0 3], VariableTypes=["string", "double", "string"], ...
        VariableNames=["metric_key", "value", "unit"]), ...
    audio_window=[], ...
    derivation_details=[], ...
    error_identifier="", ...
    error_message="", ...
    derived_measurement_ids=zeros(0, 1));
end

function details = derivationDetails(event, window, band, bandState, qcFlags, requested)
if isempty(band)
    bandSource = "none";
else
    bandSource = "explicit";
end
details = struct( ...
    method_key=methodKey(), ...
    method_version=methodVersion(), ...
    sample_semantics="MATLAB audioread normalized full-scale ratio", ...
    interval_semantics="half-open [start,end) in native audio seconds", ...
    window_semantics="the event's own native interval on the recording-native audio clock; no padding; no clock transform", ...
    band_power_method="two-sided rectangular-bin DFT power folded by absolute frequency; no detrending or window", ...
    target_kind=event.target_kind, ...
    detection_id=event.detection_id, ...
    consensus_event_id=event.consensus_event_id, ...
    event_interval_s=[event.start_time_s event.end_time_s], ...
    recording_id=window.recording_id, ...
    recording_channel_id=window.recording_channel_id, ...
    channel_index=window.channel_index, ...
    requested_channel_indices=requested, ...
    source_file_id=window.source_file_id, ...
    source_path_or_uri=window.source_path_or_uri, ...
    source_relative_path=window.source_relative_path, ...
    resolved_source_path=window.resolved_source_path, ...
    source_checksum_sha256=window.source_checksum_sha256, ...
    requested_interval_s=window.requested_interval_s, ...
    covered_interval_s=window.covered_interval_s, ...
    read_interval_s=window.read_interval_s, ...
    coverage_status=window.status, ...
    first_sample=window.first_sample, ...
    last_sample=window.last_sample, ...
    sample_count=window.sample_count, ...
    sample_rate_hz=window.sample_rate_hz, ...
    band_source=bandSource, ...
    frequency_band_hz=band, ...
    band_state=bandState, ...
    clipped_sample_count=window.clipped_sample_count, ...
    qc_flags=qcFlags(:)');
end

function measurements = measurementTable(channels)
measurements = table(Size=[0 6], ...
    VariableTypes=["double", "double", "string", "double", "string", "double"], ...
    VariableNames=["channel_index", "recording_channel_id", "metric_key", ...
    "value", "unit", "derived_measurement_id"]);
for channel = channels
    count = height(channel.metrics);
    if count == 0
        continue
    end
    ids = channel.derived_measurement_ids;
    if isempty(ids)
        ids = NaN(count, 1);
    end
    measurements = [measurements; table(repmat(channel.channel_index, count, 1), ...
        repmat(channel.recording_channel_id, count, 1), channel.metrics.metric_key, ...
        channel.metrics.value, channel.metrics.unit, ids, ...
        VariableNames=measurements.Properties.VariableNames)]; %#ok<AGROW>
end
end

% ----------------------------------------------------------- persistence ---

function [runId, channels, action] = persistMeasurements(conn, event, channels, status, options)
metricRows = resolveMetricDefinitions(conn, ...
    ["call_rms_amplitude"; "call_peak_abs_amplitude"; "call_band_power"]);
oldAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
try
    existing = fetch(conn, "SELECT analysis_run_id, run_type, status, " + ...
        "IFNULL(run_label,'') AS run_label, IFNULL(vawlume_version,'') AS vawlume_version, " + ...
        "IFNULL(source_commit,'') AS source_commit, IFNULL(notes,'') AS notes " + ...
        "FROM analysis_runs WHERE project_id=" + string(event.project_id) + ...
        " AND run_key=" + acousticSqlText(options.RunKey));
    if isempty(existing) || height(existing) == 0
        values = struct(project_id=event.project_id, ...
            run_type=runType(), run_key=options.RunKey, ...
            run_label=options.RunLabel, vawlume_version=options.VawlumeVersion, ...
            source_commit=options.SourceCommit, status=status, ...
            completed_at_utc=currentTimestamp(), notes=options.Notes);
        runId = acousticInsertRow(conn, "analysis_runs", values, "analysis_run_id");
        for index = 1:numel(channels)
            channels(index).derived_measurement_ids = insertMeasurements(conn, ...
                runId, event, channels(index), metricRows);
        end
        action = "created";
        commit(conn);
    else
        runId = double(existing.analysis_run_id(1));
        assertRunCompatible(existing(1, :), status, options);
        channels = assertMeasurementsCompatible(conn, runId, event, channels);
        action = "reused";
    end
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end

function rows = resolveMetricDefinitions(conn, keys)
quoted = arrayfun(@acousticSqlText, keys);
rows = fetch(conn, "SELECT metric_definition_id, metric_key FROM metric_definitions " + ...
    "WHERE metric_key IN (" + strjoin(quoted, ",") + ")");
if height(rows) ~= numel(keys)
    error("vawlume:acoustic:MetricDefinitionsMissing", ...
        "Built-in call-window metric definitions are missing; run vawlume.db.registerBuiltinSemantics first.");
end
rows.metric_definition_id = double(rows.metric_definition_id);
rows.metric_key = string(rows.metric_key);
end

function ids = insertMeasurements(conn, runId, event, channel, definitions)
ids = zeros(height(channel.metrics), 1);
detailsJson = string(jsonencode(channel.derivation_details));
for index = 1:height(channel.metrics)
    definitionId = definitions.metric_definition_id( ...
        definitions.metric_key == channel.metrics.metric_key(index));
    values = struct(analysis_run_id=runId, metric_definition_id=definitionId);
    values.(event.target_column) = event.target_id;
    values.recording_channel_id = channel.recording_channel_id;
    values.value_real = channel.metrics.value(index);
    values.unit = channel.metrics.unit(index);
    values.derivation_details_json = detailsJson;
    ids(index) = acousticInsertRow(conn, "derived_measurements", values, ...
        "derived_measurement_id");
end
end

function assertRunCompatible(row, status, options)
actual = [acousticPresentText(row.run_type(1)), acousticPresentText(row.status(1)), ...
    acousticPresentText(row.run_label(1)), acousticPresentText(row.vawlume_version(1)), ...
    acousticPresentText(row.source_commit(1)), acousticPresentText(row.notes(1))];
expected = [runType(), status, options.RunLabel, ...
    options.VawlumeVersion, options.SourceCommit, options.Notes];
if ~isequal(actual, expected)
    error("vawlume:acoustic:MeasurementRunConflict", ...
        "RunKey '%s' already identifies an analysis run with different provenance or status.", ...
        options.RunKey);
end
end

function channels = assertMeasurementsCompatible(conn, runId, event, channels)
% The run must hold exactly this event's rows for exactly these channels:
% nothing missing, nothing extra, no other target, and identical values and
% method evidence.
total = fetch(conn, "SELECT COUNT(*) AS n FROM derived_measurements " + ...
    "WHERE analysis_run_id=" + string(runId));
expectedTotal = sum(arrayfun(@(c) height(c.metrics), channels));
if double(total.n(1)) ~= expectedTotal
    conflict();
end
for index = 1:numel(channels)
    channel = channels(index);
    if height(channel.metrics) == 0
        continue
    end
    rows = fetch(conn, "SELECT dm.derived_measurement_id, md.metric_key, dm.value_real, " + ...
        "IFNULL(dm.unit,'') AS unit, IFNULL(dm.derivation_details_json,'') AS details " + ...
        "FROM derived_measurements dm JOIN metric_definitions md " + ...
        "ON md.metric_definition_id=dm.metric_definition_id " + ...
        "WHERE dm.analysis_run_id=" + string(runId) + ...
        " AND dm." + event.target_column + "=" + string(event.target_id) + ...
        " AND dm.recording_channel_id=" + string(channel.recording_channel_id) + ...
        " ORDER BY md.metric_key");
    if isempty(rows) || height(rows) ~= height(channel.metrics)
        conflict();
    end
    rows.metric_key = string(rows.metric_key);
    rows.unit = string(rows.unit);
    rows.details = string(rows.details);
    [expectedKeys, order] = sort(channel.metrics.metric_key);
    detailsJson = string(jsonencode(channel.derivation_details));
    if ~isequal(rows.metric_key, expectedKeys) || ...
            ~isequal(double(rows.value_real), channel.metrics.value(order)) || ...
            ~isequal(rows.unit, channel.metrics.unit(order)) || ...
            any(rows.details ~= detailsJson)
        conflict();
    end
    ids = zeros(height(rows), 1);
    ids(order) = double(rows.derived_measurement_id);
    channels(index).derived_measurement_ids = ids;
end
end

function conflict()
error("vawlume:acoustic:MeasurementRunConflict", ...
    "The existing analysis run does not contain exactly the requested deterministic measurements.");
end

function value = currentTimestamp()
value = string(char(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")));
end
