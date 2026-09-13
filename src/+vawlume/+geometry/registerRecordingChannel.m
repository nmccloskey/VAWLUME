function result = registerRecordingChannel(conn, recordingRef, channelSpec)
%REGISTERRECORDINGCHANNEL Establish one channel of an established recording.
%
%   result = VAWLUME.GEOMETRY.REGISTERRECORDINGCHANNEL(conn, recordingRef, spec)
%
% A recording channel is the form a microphone takes inside VAWLUME. Placement,
% bounded audio reads and channel-response measurement all address an established
% channel row, and project intake creates none: intake reads what a source table
% declares, and how many channels a file carries is a property of the acquisition
% rather than of the mapping. This function is where that gap is closed.
%
% RECORDINGREF selects the recording with exactly one of:
%
%   struct(recording_id=12)
%   struct(project_key="my_project", source_relative_path="audio/s01.wav")
%
% CHANNELSPEC requires:
%
%   channel_index   1-based index of the channel within the recording
%
% and optionally accepts channel_label and channel_role.
%
% CHANNEL_INDEX IS THE ACQUISITION'S OWN NUMBERING, not a VAWLUME ordinal. It is
% how a caller says "the second channel of this file", so it must match what the
% recording actually contains; nothing here can verify that against the audio,
% which is why the count is a caller assertion and is documented as one.
%
% Re-registering a channel whose stored label and role are identical reuses it.
% Re-registering the same index with a different label or role raises
% vawlume:geometry:ChannelConflict rather than rewriting: downstream placements,
% measurements and response estimates already address that channel by ID, and
% changing what it denotes underneath them would silently re-point evidence.
%
% A channel index above the recording's declared channel_count is refused
% (vawlume:geometry:ChannelIndexOutOfRange) when the recording declares one. A
% recording that declares no channel count is not second-guessed.
%
% This function creates a channel and nothing else. It declares no placement,
% reads no audio, and measures no response.
%
% See also VAWLUME.GEOMETRY.REGISTERCHANNELPLACEMENT,
% VAWLUME.ACOUSTIC.READAUDIOWINDOW, VAWLUME.ACOUSTIC.MEASUREREFERENCERESPONSE

arguments
    conn
    recordingRef (1,1) struct
    channelSpec (1,1) struct
end

recording = geometryResolveRecording(conn, recordingRef);
declared = normalizeSpec(channelSpec);
assertWithinDeclaredCount(conn, recording, declared.channel_index);

existing = fetch(conn, "SELECT recording_channel_id, " + ...
    "IFNULL(channel_label,'') AS channel_label, " + ...
    "IFNULL(channel_role,'') AS channel_role " + ...
    "FROM recording_channels WHERE recording_id=" + ...
    string(recording.recording_id) + " AND channel_index=" + ...
    string(declared.channel_index));

if ~isempty(existing) && height(existing) > 0
    assertMatchesStored(existing(1, :), declared, recording);
    result = channelResult(double(existing.recording_channel_id(1)), ...
        recording, declared, "reused");
    return
end

id = geometryInsertRow(conn, "recording_channels", struct( ...
    recording_id=recording.recording_id, ...
    channel_index=declared.channel_index, ...
    channel_label=declared.channel_label, ...
    channel_role=declared.channel_role), "recording_channel_id");
result = channelResult(id, recording, declared, "created");
end

% ---------------------------------------------------------------- helpers ---

function declared = normalizeSpec(spec)
if ~isfield(spec, "channel_index")
    error("vawlume:geometry:ChannelSpecInvalid", ...
        "channelSpec requires channel_index.");
end
allowed = ["channel_index", "channel_label", "channel_role"];
unknown = setdiff(string(fieldnames(spec))', allowed);
if ~isempty(unknown)
    error("vawlume:geometry:ChannelSpecInvalid", ...
        "Unknown channelSpec fields: %s.", strjoin(unknown, ", "));
end

index = spec.channel_index;
if ~isnumeric(index) || ~isscalar(index) || ~isfinite(index) || ...
        fix(index) ~= index || index < 1
    error("vawlume:geometry:ChannelIndexInvalid", ...
        "channel_index must be a positive whole number.");
end
declared = struct( ...
    channel_index=double(index), ...
    channel_label=optionalText(spec, "channel_label"), ...
    channel_role=optionalText(spec, "channel_role"));
end

function assertWithinDeclaredCount(conn, recording, channelIndex)
% A recording that declares how many channels it has is taken at its word. One
% that declares none is not second-guessed: an absent count is missing metadata,
% not an assertion that the file is empty.
row = fetch(conn, "SELECT IFNULL(channel_count,-1) AS channel_count " + ...
    "FROM recordings WHERE recording_id=" + string(recording.recording_id));
declaredCount = double(row.channel_count(1));
if declaredCount >= 1 && channelIndex > declaredCount
    error("vawlume:geometry:ChannelIndexOutOfRange", ...
        "Channel index %d exceeds the %d channels this recording declares.", ...
        channelIndex, declaredCount);
end
end

function assertMatchesStored(stored, declared, recording)
storedLabel = presentText(stored.channel_label(1));
storedRole = presentText(stored.channel_role(1));
if storedLabel == declared.channel_label && storedRole == declared.channel_role
    return
end
error("vawlume:geometry:ChannelConflict", ...
    "Channel %d of recording %d is already established as label '%s' role '%s'. " + ...
    "Placements and measurements already address it by ID; register a different " + ...
    "index rather than redefining this one.", ...
    declared.channel_index, recording.recording_id, storedLabel, storedRole);
end

function result = channelResult(channelId, recording, declared, action)
result = struct( ...
    action=string(action), ...
    recording_channel_id=channelId, ...
    recording_id=recording.recording_id, ...
    project_key=recording.project_key, ...
    channel_index=declared.channel_index, ...
    channel_label=declared.channel_label, ...
    channel_role=declared.channel_role, ...
    channel_count_is_caller_asserted=true, ...
    note="A channel row records that this recording has this channel. " + ...
        "Nothing here inspects the audio to confirm it.");
end

function value = optionalText(spec, field)
value = "";
if isfield(spec, field) && ~isempty(spec.(field))
    value = strtrim(string(spec.(field)));
end
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
