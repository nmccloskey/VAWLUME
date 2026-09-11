function selection = trackingSelectWindow(tbl, columns, stream, interval, basis, ...
    options)
%TRACKINGSELECTWINDOW Canonicalize and bound the artifact's rows to one window.
%
% COLUMNS is the resolved role-to-column contract from trackingColumnContract.
% This function returns only the rows inside the requested window. Correctness
% and bounded access first: the artifact is read once and filtered in memory
% rather than indexed. A general indexing engine needs evidence it is required,
% and none exists yet.

trackIds = trackingTextColumn(tbl, columns.track_label);
bodyparts = trackingTextColumn(tbl, columns.bodypart_label);
x = trackingNumericColumn(tbl, columns.position_x);
y = trackingNumericColumn(tbl, columns.position_y);
z = trackingNumericColumn(tbl, columns.position_z);
confidence = trackingNumericColumn(tbl, columns.confidence);

[timeNative, frameNative] = nativeTimes(tbl, columns, stream);
switch basis
    case "time"
        basisValues = timeNative;
    case "frame"
        basisValues = frameNative;
end

inWindow = basisValues >= interval(1) & basisValues <= interval(2);
inWindow(isnan(basisValues)) = false;

if ~isempty(options.NativeTrackIds)
    inWindow = inWindow & ismember(trackIds, options.NativeTrackIds);
end
if ~isempty(options.BodypartLabels)
    inWindow = inWindow & ismember(bodyparts, options.BodypartLabels);
end

rows = find(inWindow);

% A sample inside the window whose position is unusable is a QC finding about
% the artifact, not a reason to drop the row silently. It is returned with NaN
% coordinates and counted, so a caller can tell "no samples" from "samples that
% could not be used".
invalid = ~isfinite(x(rows)) | ~isfinite(y(rows));

selection = struct();
selection.invalid_count = nnz(invalid);
selection.rows = table( ...
    timeNative(rows), frameNative(rows), trackIds(rows), bodyparts(rows), ...
    x(rows), y(rows), z(rows), confidence(rows), ...
    NaN(numel(rows), 1), ...
    VariableNames=["time_native_s", "frame_native", "native_track_id", ...
    "native_bodypart_label", "position_x", "position_y", "position_z", ...
    "pose_confidence", "time_reference_s"]);
selection.rows = sortrows(selection.rows, ...
    ["time_native_s", "native_track_id", "native_bodypart_label"]);
end

function [timeNative, frameNative] = nativeTimes(tbl, columns, stream)
%NATIVETIMES Both native clocks, each present only when the artifact has it.
%
% A frame index is converted to seconds only when the stream registered a frame
% rate. Without one, no relationship between frames and seconds was ever
% declared, and inventing one here would fabricate a clock.
count = height(tbl);
timeNative = NaN(count, 1);
frameNative = NaN(count, 1);

if strlength(columns.native_time) > 0
    timeNative = trackingNumericColumn(tbl, columns.native_time);
end
if strlength(columns.native_frame) > 0
    frameNative = trackingNumericColumn(tbl, columns.native_frame);
end

if all(isnan(timeNative)) && ~all(isnan(frameNative)) && ...
        ~isnan(stream.nominal_frame_rate_hz)
    timeNative = frameNative / stream.nominal_frame_rate_hz;
end
end

function value = trackingTextColumn(tbl, columnName)
if strlength(columnName) == 0
    value = strings(height(tbl), 1);
    return
end
column = tbl.(char(columnName));
if iscell(column)
    value = strings(numel(column), 1);
    for index = 1:numel(column)
        value(index) = string(column{index});
    end
else
    if iscategorical(column)
        column = string(column);
    end
    value = string(column);
end
value = value(:);
value(ismissing(value)) = "";
end

function value = trackingNumericColumn(tbl, columnName)
if strlength(columnName) == 0
    value = NaN(height(tbl), 1);
    return
end
column = tbl.(char(columnName));
if iscell(column)
    value = NaN(numel(column), 1);
    for index = 1:numel(column)
        value(index) = str2double(string(column{index}));
    end
    return
end
if isnumeric(column) || islogical(column)
    value = double(column);
else
    value = str2double(string(column));
end
value = value(:);
end
