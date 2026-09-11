function window = readAudioWindow(conn, recordingRef, channelIndex, startTimeS, endTimeS, options)
%READAUDIOWINDOW Read one bounded channel window through recording provenance.
%
%   window = VAWLUME.ACOUSTIC.READAUDIOWINDOW(conn, recordingRef, ...
%       channelIndex, startTimeS, endTimeS, SourceRoot=sourceRoot)
%
% The requested interval is half-open [startTimeS,endTimeS), in the native
% audio clock. Only the intersecting sample range is passed to AUDIOREAD.
% Samples are returned exactly as AUDIOREAD-normalized full-scale ratios; this
% function never rewrites audio and performs no calibration or normalization.
%
% Relative source_files paths are resolved against SourceRoot. Absolute local
% paths need no SourceRoot. URI sources, missing files, inconsistent database
% metadata, and invalid channel layouts fail with acoustic-specific errors.

arguments
    conn
    recordingRef (1,1) struct
    channelIndex (1,1) double
    startTimeS (1,1) double
    endTimeS (1,1) double
    options.SourceRoot (1,1) string = ""
end

validateRequest(channelIndex, startTimeS, endTimeS);
recording = acousticResolveRecording(conn, recordingRef);
channel = resolveChannel(conn, recording.recording_id, channelIndex);
source = resolveSource(conn, recording, options.SourceRoot);

try
    info = audioinfo(char(source.resolved_path));
catch exception
    error("vawlume:acoustic:AudioArtifactUnsupported", ...
        "Cannot inspect linked audio artifact '%s': %s", ...
        source.resolved_path, exception.message);
end
assertMetadata(recording, info, channelIndex, source.resolved_path);

sampleRate = double(info.SampleRate);
totalSamples = double(info.TotalSamples);
durationS = totalSamples / sampleRate;
requested = [startTimeS endTimeS];
covered = [min(max(startTimeS, 0), durationS), ...
    min(max(endTimeS, 0), durationS)];
firstSample = boundarySample(covered(1), sampleRate) + 1;
lastSample = boundarySample(covered(2), sampleRate);
firstSample = min(max(firstSample, 1), totalSamples + 1);
lastSample = min(max(lastSample, 0), totalSamples);

samples = zeros(0, 1);
readBounds = [covered(1) covered(1)];
if lastSample >= firstSample
    try
        allChannels = audioread(char(source.resolved_path), [firstSample lastSample]);
    catch exception
        error("vawlume:acoustic:AudioWindowReadFailed", ...
            "Cannot read samples %d:%d from linked audio artifact '%s': %s", ...
            firstSample, lastSample, source.resolved_path, exception.message);
    end
    if size(allChannels, 2) < channelIndex
        error("vawlume:acoustic:UnsupportedChannelLayout", ...
            "Audio artifact '%s' returned %d channels while channel %d was requested.", ...
            source.resolved_path, size(allChannels, 2), channelIndex);
    end
    samples = double(allChannels(:, channelIndex));
    readBounds = [(firstSample - 1) / sampleRate, lastSample / sampleRate];
end

qcFlags = strings(0, 1);
if startTimeS == endTimeS
    qcFlags(end + 1, 1) = "zero_length_window";
end
if endTimeS > durationS
    qcFlags(end + 1, 1) = "incomplete_audio_coverage";
end
if isempty(samples)
    qcFlags(end + 1, 1) = "empty_window";
end
clippedCount = sum(abs(samples) >= 1 - 1e-12);
if clippedCount > 0
    qcFlags(end + 1, 1) = "clipped_samples";
end

if isempty(samples)
    if startTimeS >= durationS && endTimeS > startTimeS
        status = "not_covered";
    else
        status = "covered_empty";
    end
elseif endTimeS > durationS
    status = "partial_populated";
else
    status = "covered_populated";
end

window = struct( ...
    status=status, ...
    qc_flags=qcFlags, ...
    samples=samples, ...
    requested_interval_s=requested, ...
    covered_interval_s=covered, ...
    read_interval_s=readBounds, ...
    first_sample=firstSample, ...
    last_sample=lastSample, ...
    sample_count=numel(samples), ...
    sample_rate_hz=sampleRate, ...
    recording_id=recording.recording_id, ...
    recording_channel_id=channel.recording_channel_id, ...
    channel_index=channel.channel_index, ...
    channel_label=channel.channel_label, ...
    source_file_id=source.source_file_id, ...
    source_path_or_uri=source.path_or_uri, ...
    source_relative_path=source.relative_path, ...
    resolved_source_path=source.resolved_path, ...
    source_checksum_sha256=source.checksum_sha256, ...
    source_size_bytes=source.size_bytes, ...
    total_samples=totalSamples, ...
    total_channels=double(info.NumChannels), ...
    duration_s=durationS, ...
    clipped_sample_count=clippedCount);
end

function validateRequest(channelIndex, startTimeS, endTimeS)
if ~isfinite(channelIndex) || channelIndex < 1 || channelIndex ~= floor(channelIndex)
    error("vawlume:acoustic:AudioWindowInvalid", ...
        "channelIndex must be a positive integer.");
end
if ~isfinite(startTimeS) || ~isfinite(endTimeS) || startTimeS < 0 || endTimeS < startTimeS
    error("vawlume:acoustic:AudioWindowInvalid", ...
        "The requested interval must contain finite nonnegative bounds with endTimeS >= startTimeS.");
end
end

function channel = resolveChannel(conn, recordingId, channelIndex)
rows = fetch(conn, "SELECT recording_channel_id, channel_index, " + ...
    "IFNULL(channel_label,'') AS channel_label FROM recording_channels " + ...
    "WHERE recording_id=" + string(recordingId) + ...
    " AND channel_index=" + string(channelIndex));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:ChannelNotFound", ...
        "Recording %d has no declared channel_index %d.", recordingId, channelIndex);
end
channel = struct(recording_channel_id=double(rows.recording_channel_id(1)), ...
    channel_index=double(rows.channel_index(1)), ...
    channel_label=acousticPresentText(rows.channel_label(1)));
end

function source = resolveSource(conn, recording, sourceRoot)
rows = fetch(conn, "SELECT sf.source_file_id, sf.path_or_uri, " + ...
    "IFNULL(sf.relative_path,'') AS relative_path, " + ...
    "IFNULL(sf.checksum_sha256,'') AS checksum_sha256, " + ...
    "IFNULL(sf.size_bytes,-1) AS size_bytes FROM source_files sf " + ...
    "WHERE sf.source_file_id=" + string(recording.source_file_id));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:AudioArtifactMissing", ...
        "Recording %d has no resolvable linked source file.", recording.recording_id);
end
pathOrUri = acousticPresentText(rows.path_or_uri(1));
relativePath = acousticPresentText(rows.relative_path(1));
if isNonFileUri(pathOrUri)
    error("vawlume:acoustic:AudioArtifactUnsupported", ...
        "Linked audio source '%s' is a URI; readAudioWindow supports local files only.", pathOrUri);
end
if isAbsolutePath(pathOrUri)
    resolved = pathOrUri;
elseif strlength(sourceRoot) > 0
    candidate = relativePath;
    if strlength(candidate) == 0
        candidate = pathOrUri;
    end
    resolved = string(fullfile(sourceRoot, candidate));
else
    error("vawlume:acoustic:AudioSourceRootRequired", ...
        "Linked audio path '%s' is relative; SourceRoot is required.", pathOrUri);
end
resolved = canonicalPath(resolved);
if ~isfile(resolved)
    error("vawlume:acoustic:AudioArtifactMissing", ...
        "Linked audio artifact does not exist at '%s'.", resolved);
end
source = struct(source_file_id=double(rows.source_file_id(1)), ...
    path_or_uri=pathOrUri, relative_path=relativePath, ...
    resolved_path=resolved, ...
    checksum_sha256=acousticPresentText(rows.checksum_sha256(1)), ...
    size_bytes=double(rows.size_bytes(1)));
if source.size_bytes < 0
    source.size_bytes = NaN;
end
end

function assertMetadata(recording, info, channelIndex, path)
if channelIndex > double(info.NumChannels)
    error("vawlume:acoustic:UnsupportedChannelLayout", ...
        "Audio artifact '%s' has %d channels; channel %d was requested.", ...
        path, info.NumChannels, channelIndex);
end
if ~isnan(recording.channel_count) && recording.channel_count ~= double(info.NumChannels)
    error("vawlume:acoustic:AudioMetadataMismatch", ...
        "Recording metadata declares %d channels but '%s' contains %d.", ...
        recording.channel_count, path, info.NumChannels);
end
if ~isnan(recording.sample_rate_hz) && recording.sample_rate_hz ~= double(info.SampleRate)
    error("vawlume:acoustic:AudioMetadataMismatch", ...
        "Recording metadata declares sample rate %.17g Hz but '%s' contains %.17g Hz.", ...
        recording.sample_rate_hz, path, info.SampleRate);
end
end

function value = boundarySample(timeS, sampleRate)
raw = timeS * sampleRate;
value = ceil(raw - 16 * eps(max(1, abs(raw))));
end

function tf = isAbsolutePath(path)
text = char(path);
tf = startsWith(path, "/") || startsWith(path, "\\") || ...
    (~isempty(regexp(text, '^[A-Za-z]:[\\/]', 'once')));
end

function tf = isNonFileUri(path)
text = char(path);
tf = ~isempty(regexp(text, '^[A-Za-z][A-Za-z0-9+.-]*://', 'once'));
end

function path = canonicalPath(path)
try
    path = string(java.io.File(char(path)).getCanonicalPath());
catch
    path = string(path);
end
end
