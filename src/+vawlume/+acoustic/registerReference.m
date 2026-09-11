function result = registerReference(conn, recordingRef, referenceSpec)
%REGISTERREFERENCE Declare an acoustic-reference point or interval.
%
%   result = VAWLUME.ACOUSTIC.REGISTERREFERENCE(conn, recordingRef, spec)
%
% A reference says where a known or useful signal is claimed to occur in a
% recording's native audio clock. It stores no amplitude, power, correction, or
% measured response.
%
% RECORDINGREF selects the recording with exactly one of:
%
%   struct(recording_id=12)
%   struct(project_key="my_project", source_relative_path="audio/s01.wav")
%
% REFERENCESPEC requires reference_key, reference_type, start_time_s, and
% end_time_s. Equal start/end values represent a point-like reference.
%
% Optional fields are channel_index (omission means all recording channels),
% native_label, frequency_min_hz, frequency_max_hz, external_event_id,
% source_file_id, source_locator, mapping_profile_version_id, and notes.
%
% reference_type is free text. Tone, noise, persistent background, and
% user-defined labels are equally valid. Frequency bounds are optional and may
% be supplied independently; no band is inferred when neither exists.
%
% external_event_id is provenance only. It may cite an event imported through
% the existing external_stream_mapping path, but registration never creates or
% infers an alignment anchor. The linked event must belong to this recording.
%
% Registration is idempotent by (recording, reference_key). Repeating identical
% content reuses the row; changing content raises
% vawlume:acoustic:ReferenceConflict rather than rewriting evidence.
%
% See also VAWLUME.ACOUSTIC.READREFERENCES

arguments
    conn
    recordingRef (1,1) struct
    referenceSpec (1,1) struct
end

recording = acousticResolveRecording(conn, recordingRef);
declared = normalizeSpec(referenceSpec);
channel = resolveChannel(conn, recording, declared.channel_index);
assertExternalEventScope(conn, recording, declared.external_event_id);
assertSourceFileScope(conn, recording, declared.source_file_id);
assertMappingProfile(conn, recording, declared.mapping_profile_version_id);

existing = fetch(conn, "SELECT acoustic_reference_id, " + ...
    "IFNULL(recording_channel_id,-1) AS recording_channel_id, " + ...
    "IFNULL(external_event_id,-1) AS external_event_id, reference_type, " + ...
    "IFNULL(native_label,'') AS native_label, start_time_s, end_time_s, " + ...
    "IFNULL(frequency_min_hz,-1) AS frequency_min_hz, " + ...
    "IFNULL(frequency_max_hz,-1) AS frequency_max_hz, " + ...
    "IFNULL(source_file_id,-1) AS source_file_id, " + ...
    "IFNULL(source_locator,'') AS source_locator, " + ...
    "IFNULL(mapping_profile_version_id,-1) AS mapping_profile_version_id, " + ...
    "IFNULL(notes,'') AS notes FROM acoustic_references " + ...
    "WHERE recording_id=" + string(recording.recording_id) + ...
    " AND reference_key=" + acousticSqlText(declared.reference_key));

if ~isempty(existing) && height(existing) > 0
    assertMatchesStored(existing(1, :), declared, channel);
    result = referenceResult(double(existing.acoustic_reference_id(1)), ...
        recording, declared, channel, "reused");
    return
end

values = struct( ...
    recording_id=recording.recording_id, ...
    reference_key=declared.reference_key, ...
    reference_type=declared.reference_type, ...
    native_label=declared.native_label, ...
    start_time_s=declared.start_time_s, ...
    end_time_s=declared.end_time_s, ...
    source_locator=declared.source_locator, ...
    notes=declared.notes);
if ~isnan(channel.recording_channel_id)
    values.recording_channel_id = channel.recording_channel_id;
end
for field = ["external_event_id", "source_file_id", ...
        "mapping_profile_version_id", "frequency_min_hz", "frequency_max_hz"]
    if ~isnan(declared.(field))
        values.(field) = declared.(field);
    end
end

id = acousticInsertRow(conn, "acoustic_references", values, ...
    "acoustic_reference_id");
result = referenceResult(id, recording, declared, channel, "created");
end

function declared = normalizeSpec(spec)
declared = struct();
declared.reference_key = requiredText(spec, "reference_key");
declared.reference_type = requiredText(spec, "reference_type");
declared.native_label = optionalText(spec, "native_label");
declared.start_time_s = requiredNonnegativeReal(spec, "start_time_s");
declared.end_time_s = requiredNonnegativeReal(spec, "end_time_s");
if declared.end_time_s < declared.start_time_s
    error("vawlume:acoustic:ReferenceIntervalInvalid", ...
        "referenceSpec.end_time_s must be greater than or equal to start_time_s.");
end

declared.frequency_min_hz = optionalNonnegativeReal(spec, "frequency_min_hz");
declared.frequency_max_hz = optionalNonnegativeReal(spec, "frequency_max_hz");
if ~isnan(declared.frequency_min_hz) && ~isnan(declared.frequency_max_hz) && ...
        declared.frequency_max_hz < declared.frequency_min_hz
    error("vawlume:acoustic:FrequencyBandInvalid", ...
        "frequency_max_hz must be greater than or equal to frequency_min_hz.");
end

declared.channel_index = optionalPositiveInteger(spec, "channel_index");
declared.external_event_id = optionalPositiveInteger(spec, "external_event_id");
declared.source_file_id = optionalPositiveInteger(spec, "source_file_id");
declared.mapping_profile_version_id = optionalPositiveInteger(spec, ...
    "mapping_profile_version_id");
declared.source_locator = optionalText(spec, "source_locator");
declared.notes = optionalText(spec, "notes");
end

function channel = resolveChannel(conn, recording, channelIndex)
channel = struct(recording_channel_id=NaN, channel_index=NaN, channel_label="");
if isnan(channelIndex)
    return
end
rows = fetch(conn, "SELECT recording_channel_id, channel_index, " + ...
    "IFNULL(channel_label,'') AS channel_label FROM recording_channels " + ...
    "WHERE recording_id=" + string(recording.recording_id) + ...
    " AND channel_index=" + string(channelIndex));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:ChannelNotFound", ...
        "Recording %d has no channel_index %d.", ...
        recording.recording_id, channelIndex);
end
channel = struct( ...
    recording_channel_id=double(rows.recording_channel_id(1)), ...
    channel_index=double(rows.channel_index(1)), ...
    channel_label=acousticPresentText(rows.channel_label(1)));
end

function assertExternalEventScope(conn, recording, externalEventId)
if isnan(externalEventId)
    return
end
rows = fetch(conn, "SELECT IFNULL(es.recording_id,-1) AS recording_id " + ...
    "FROM external_events ee " + ...
    "JOIN external_streams es ON es.external_stream_id=ee.external_stream_id " + ...
    "WHERE ee.external_event_id=" + string(externalEventId));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:ExternalEventNotFound", ...
        "No external event %d exists.", externalEventId);
end
if double(rows.recording_id(1)) ~= recording.recording_id
    error("vawlume:acoustic:ExternalEventScopeMismatch", ...
        "External event %d does not belong to recording %d.", ...
        externalEventId, recording.recording_id);
end
end

function assertSourceFileScope(conn, recording, sourceFileId)
if isnan(sourceFileId)
    return
end
rows = fetch(conn, "SELECT project_id FROM source_files WHERE source_file_id=" + ...
    string(sourceFileId));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:SourceFileNotFound", ...
        "No source file %d exists.", sourceFileId);
end
if double(rows.project_id(1)) ~= recording.project_id
    error("vawlume:acoustic:SourceFileScopeMismatch", ...
        "Source file %d belongs to a different project than recording %d.", ...
        sourceFileId, recording.recording_id);
end
end

function assertMappingProfile(conn, recording, profileVersionId)
if isnan(profileVersionId)
    return
end
rows = fetch(conn, "SELECT cp.profile_kind, IFNULL(cp.project_id,-1) AS project_id " + ...
    "FROM config_profile_versions cpv JOIN config_profiles cp " + ...
    "ON cp.profile_id=cpv.profile_id WHERE cpv.profile_version_id=" + ...
    string(profileVersionId));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:MappingProfileNotFound", ...
        "No mapping profile version %d exists.", profileVersionId);
end
if acousticPresentText(rows.profile_kind(1)) ~= "external_stream_mapping"
    error("vawlume:acoustic:MappingProfileKindInvalid", ...
        "Acoustic-reference table mapping reuses profile kind " + ...
        "external_stream_mapping; profile version %d has kind '%s'.", ...
        profileVersionId, acousticPresentText(rows.profile_kind(1)));
end
projectId = double(rows.project_id(1));
if projectId >= 0 && projectId ~= recording.project_id
    error("vawlume:acoustic:MappingProfileScopeMismatch", ...
        "Mapping profile version %d belongs to a different project than recording %d.", ...
        profileVersionId, recording.recording_id);
end
end

function assertMatchesStored(stored, declared, channel)
storedValues = struct( ...
    recording_channel_id=nullableNumber(stored.recording_channel_id), ...
    external_event_id=nullableNumber(stored.external_event_id), ...
    reference_type=acousticPresentText(stored.reference_type), ...
    native_label=acousticPresentText(stored.native_label), ...
    start_time_s=double(stored.start_time_s), ...
    end_time_s=double(stored.end_time_s), ...
    frequency_min_hz=nullableNumber(stored.frequency_min_hz), ...
    frequency_max_hz=nullableNumber(stored.frequency_max_hz), ...
    source_file_id=nullableNumber(stored.source_file_id), ...
    source_locator=acousticPresentText(stored.source_locator), ...
    mapping_profile_version_id=nullableNumber(stored.mapping_profile_version_id), ...
    notes=acousticPresentText(stored.notes));
supplied = declared;
supplied.recording_channel_id = channel.recording_channel_id;

names = ["recording_channel_id", "external_event_id", "reference_type", ...
    "native_label", "start_time_s", "end_time_s", "frequency_min_hz", ...
    "frequency_max_hz", "source_file_id", "source_locator", ...
    "mapping_profile_version_id", "notes"];
differing = strings(0, 1);
for name = names
    if ~isequaln(storedValues.(name), supplied.(name))
        differing(end + 1, 1) = name; %#ok<AGROW>
    end
end
if ~isempty(differing)
    error("vawlume:acoustic:ReferenceConflict", ...
        "This recording already has reference_key '%s' with different content: %s.", ...
        declared.reference_key, strjoin(differing(:)', ", "));
end
end

function result = referenceResult(id, recording, declared, channel, action)
result = struct( ...
    acoustic_reference_id=id, ...
    recording_id=recording.recording_id, ...
    recording_channel_id=channel.recording_channel_id, ...
    channel_index=channel.channel_index, ...
    reference_key=declared.reference_key, ...
    reference_type=declared.reference_type, ...
    interval_s=[declared.start_time_s declared.end_time_s], ...
    frequency_band_hz=[declared.frequency_min_hz declared.frequency_max_hz], ...
    external_event_id=declared.external_event_id, ...
    action=action);
end

function value = requiredText(spec, name)
if ~isfield(spec, name)
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s is required.", name);
end
value = string(spec.(name));
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s must be nonempty scalar text.", name);
end
end

function value = optionalText(spec, name)
value = "";
if ~isfield(spec, name) || isempty(spec.(name))
    return
end
candidate = string(spec.(name));
if ~isscalar(candidate) || ismissing(candidate)
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s must be scalar text when supplied.", name);
end
value = candidate;
end

function value = requiredNonnegativeReal(spec, name)
if ~isfield(spec, name)
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s is required.", name);
end
value = spec.(name);
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value < 0
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s must be a finite nonnegative scalar number.", name);
end
value = double(value);
end

function value = optionalNonnegativeReal(spec, name)
value = NaN;
if ~isfield(spec, name) || isempty(spec.(name))
    return
end
candidate = spec.(name);
if isnumeric(candidate) && isscalar(candidate) && isnan(candidate)
    return
end
if ~isnumeric(candidate) || ~isscalar(candidate) || ~isfinite(candidate) || ...
        candidate < 0
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s must be a finite nonnegative scalar number when supplied.", ...
        name);
end
value = double(candidate);
end

function value = optionalPositiveInteger(spec, name)
value = NaN;
if ~isfield(spec, name) || isempty(spec.(name))
    return
end
candidate = spec.(name);
if isnumeric(candidate) && isscalar(candidate) && isnan(candidate)
    return
end
if ~isnumeric(candidate) || ~isscalar(candidate) || ~isfinite(candidate) || ...
        candidate <= 0 || candidate ~= floor(candidate)
    error("vawlume:acoustic:ReferenceInvalid", ...
        "referenceSpec.%s must be a positive integer when supplied.", name);
end
value = double(candidate);
end

function value = nullableNumber(raw)
value = double(raw);
if value < 0
    value = NaN;
end
end
