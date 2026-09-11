function result = mapTrackingTableToIR(tbl, result, entry, profileLocation, options)
%MAPTRACKINGTABLETOIR Summarize a canonicalized tracking table into the unified IR.
%
% This mapper is deliberately unlike its event and anchor siblings. They emit one
% IR row per source row, because an external event *is* the record. A tracking
% artifact's records are samples, and samples never enter the IR: the IR carries
% what is needed to register the logical stream and resolve the artifact later,
% not the artifact's contents.
%
% What it emits, for a table of any height:
%
%   one sources row
%   one tracking_streams row      the stream, its clock, its frame, its basis
%   one tracking_series row       per distinct (native track, bodypart) trace
%   one tracking_columns row      per mapped role
%   coverage rows                 derived from the native time span, or declared
%
% The table is scanned to derive the trace inventory and the time span, which are
% summaries of size O(series) and O(1). Nothing of size O(samples) is produced.
%
% Reading the artifact into MATLAB memory is expected and is not what the
% dense-data policy forbids; the policy is about SQLite. Bounded window access at
% query time is a separate concern and belongs to the tracking reader.

sourceKey = options.SourceKey;
if strlength(sourceKey) == 0 || sourceKey == "source:in_memory_table"
    sourceKey = optionalText(entry.source, "source_key_default");
end
if strlength(sourceKey) == 0
    sourceKey = "source:tracking_table";
end

context = entry.context;
streamKey = string(context.stream_key);
timebaseKey = string(context.timebase_key);
coordinateSystemKey = string(context.coordinate_system_key);
basis = string(context.native_time_basis);
nativeUnit = optionalText(context, "native_time_unit");
if strlength(nativeUnit) == 0
    nativeUnit = "s";
end
timeTransform = trackingTimeTransform(nativeUnit);
frameRate = optionalNumber(context, "nominal_frame_rate_hz");

filename = trackingFilename(options.Filename, options.RelativePath, options.RuntimePath);
artifactType = optionalText(entry.source, "table_role");
result.sources(end + 1, :) = {sourceKey, options.RuntimePath, ...
    replace(options.RelativePath, "\", "/"), filename, "tracking_table", ...
    "supplied_table", artifactType, "mapped", height(tbl), ""};

[resolved, result] = resolveTrackingColumns(tbl, entry, basis, profileLocation, ...
    result, sourceKey, streamKey);

hasConfidence = strlength(resolved.confidence.actual) > 0;
result = resolveSeries(tbl, resolved, entry, result, sourceKey, streamKey);
[coverage, result] = resolveSpan(tbl, resolved, nativeUnit, frameRate, ...
    result, sourceKey);

status = "mapped";
if any(result.tracking_columns.status == "invalid") || ...
        any(result.tracking_series.status == "invalid") || coverage.status == "invalid"
    status = "invalid";
end

result.tracking_streams(end + 1, :) = {streamKey, sourceKey, timebaseKey, ...
    coordinateSystemKey, basis, frameRate, double(hasConfidence), ...
    height(tbl), nativeUnit, timeTransform, status};

if coverage.status ~= "invalid"
    result.coverage(end + 1, :) = {sourceKey + "|coverage:1", sourceKey, ...
        streamKey, timebaseKey, 1, coverage.start_native, coverage.end_native, ...
        coverage.start_seconds, coverage.end_seconds, nativeUnit, timeTransform, ...
        "derived:native_time_span", "tracking_span", "observed", "mapped"};
end

result = updateTrackingSourceStatus(result, sourceKey, status);
result = finalizeIntermediateRepresentation(result);
end

% -------------------------------------------------------------- the columns ---

function [resolved, result] = resolveTrackingColumns(tbl, entry, basis, location, ...
    result, sourceKey, streamKey)
%RESOLVETRACKINGCOLUMNS Resolve every declared role against the actual table.
%
% Roles, not vendor column names. A profile says "position_x lives in the column
% called snout_x"; nothing here knows what DeepLabCut or SLEAP call anything.
columns = entry.columns;
specs = { ...
    "position_x", ["x", "position_x"], true; ...
    "position_y", ["y", "position_y"], true; ...
    "track_label", ["entity", "subject", "individual"], true; ...
    "bodypart_label", ["bodypart", "node", "landmark"], true; ...
    "native_time", ["time", "timestamp_s", "time_s"], ismember(basis, ["time", "both"]); ...
    "native_frame", ["frame", "frame_index"], ismember(basis, ["frame", "both"]); ...
    "position_z", ["z", "position_z"], false; ...
    "confidence", ["confidence", "likelihood", "score"], false};

resolved = struct();
for index = 1:size(specs, 1)
    role = specs{index, 1};
    defaults = specs{index, 2};
    required = specs{index, 3};

    entryRule = struct();
    declared = hasProfileField(columns, role);
    if declared
        entryRule = columns.(char(role));
    end

    actual = "";
    resolution = "";
    if declared
        [actual, resolution, issue] = resolveMappedColumn(tbl, entryRule, defaults, ...
            location + ".columns." + role, required, "TRACKING_COLUMN_MISSING");
        result = appendIssues(result, issue, sourceKey);
    elseif required
        result = appendIssues(result, makeIssue("error", "TRACKING_COLUMN_MISSING", ...
            location + ".columns." + role, ...
            "Tracking profiles must declare the " + role + " column."), sourceKey);
    end

    columnStatus = "mapped";
    if required && strlength(actual) == 0
        columnStatus = "invalid";
    elseif ~declared
        columnStatus = "absent";
    end

    resolved.(char(role)) = struct(actual=actual, resolution=resolution, ...
        declared=declared);

    result.tracking_columns(end + 1, :) = { ...
        sourceKey + "|column:" + role, streamKey, sourceKey, role, ...
        declaredSourceField(entryRule, declared), actual, resolution, ...
        declaredUnit(entryRule, declared), double(required), columnStatus};
end
end

% --------------------------------------------------------------- the series ---

function result = resolveSeries(tbl, resolved, entry, result, sourceKey, streamKey)
%RESOLVESERIES Derive the distinct (native track, bodypart) traces in the table.
%
% This is the one place the table's contents are inspected, and it produces one
% row per trace rather than per sample. Track labels are taken verbatim: two
% labels that differ by whitespace are two trajectories, because silently
% merging them would merge two traces.
%
% A track label is the tracker's trajectory name. It says nothing about which
% animal the trajectory follows, and nothing here treats it as though it did.
if strlength(resolved.track_label.actual) == 0 || ...
        strlength(resolved.bodypart_label.actual) == 0
    return
end

trackLabels = trackingColumnText(tbl, resolved.track_label.actual);
bodyparts = trackingColumnText(tbl, resolved.bodypart_label.actual);
roles = bodypartRoleMap(entry);

blank = strlength(strtrim(trackLabels)) == 0 | strlength(strtrim(bodyparts)) == 0;
if any(blank)
    % An unlabelled sample cannot be attributed to a trace. Assigning it to a
    % default series would invent a trajectory the source did not supply.
    result = appendIssues(result, makeIssue("error", "TRACKING_IDENTITY_MISSING", ...
        "columns.track_label/bodypart_label", ...
        string(nnz(blank)) + " tracking row(s) carry no track or bodypart " + ...
        "label, so their samples cannot be attributed to a trace."), sourceKey);
end

pairs = trackLabels + newline + bodyparts;
[distinct, firstIndex] = unique(pairs, "stable");
counts = zeros(numel(distinct), 1);
for index = 1:numel(distinct)
    counts(index) = nnz(pairs == distinct(index));
end
[~, order] = sort(trackLabels(firstIndex) + newline + bodyparts(firstIndex));

for position = 1:numel(order)
    index = order(position);
    trackLabel = trackLabels(firstIndex(index));
    bodypartLabel = bodyparts(firstIndex(index));
    seriesStatus = "mapped";
    if strlength(strtrim(trackLabel)) == 0 || strlength(strtrim(bodypartLabel)) == 0
        seriesStatus = "invalid";
    end
    canonicalRole = "";
    if roles.isKey(bodypartLabel)
        canonicalRole = roles(bodypartLabel);
    end
    seriesKey = sourceKey + "|series:" + trackLabel + "/" + bodypartLabel;
    result.tracking_series(end + 1, :) = {seriesKey, streamKey, sourceKey, ...
        trackLabel, bodypartLabel, canonicalRole, counts(index), seriesStatus};
end
end

function roles = bodypartRoleMap(entry)
%BODYPARTROLEMAP Optional native-label to canonical-role declarations.
roles = dictionary(string.empty, string.empty);
if ~hasProfileField(entry, "bodypart_roles")
    return
end
items = normalizeMappingSequence(entry.bodypart_roles);
for index = 1:numel(items)
    item = items{index};
    if ~isstruct(item) || ~hasProfileField(item, "native_bodypart_label") || ...
            ~hasProfileField(item, "canonical_bodypart_role")
        continue
    end
    roles(string(item.native_bodypart_label)) = string(item.canonical_bodypart_role);
end
end

% ----------------------------------------------------------------- the span ---

function [coverage, result] = resolveSpan(tbl, resolved, nativeUnit, frameRate, ...
    result, sourceKey)
%RESOLVESPAN Derive one observed coverage segment from the artifact's own span.
%
% The basis is not consulted directly: which column resolved is the authority,
% because a profile declaring 'both' may still have only one column present in
% the artifact it was pointed at.
%
% One segment, because a canonicalized tracking export is a contiguous record of
% what the tracker produced. Gaps inside it are missing samples, which the reader
% reports per window, not a second coverage segment - inferring dropout segments
% from sample spacing would be a guess about the upstream tool's behaviour.
coverage = struct(start_native=NaN, end_native=NaN, start_seconds=NaN, ...
    end_seconds=NaN, status="absent");

if strlength(resolved.native_time.actual) > 0
    values = trackingColumnNumeric(tbl, resolved.native_time.actual);
    label = "native_time";
elseif strlength(resolved.native_frame.actual) > 0 && ~isnan(frameRate)
    values = trackingColumnNumeric(tbl, resolved.native_frame.actual) / frameRate;
    nativeUnit = "s";
    label = "native_frame";
else
    return
end

finite = values(isfinite(values));
if isempty(finite)
    result = appendIssues(result, makeIssue("error", "TRACKING_SPAN_UNRESOLVED", ...
        "columns." + label, ...
        "No finite " + label + " value was found, so the stream's observed " + ...
        "span cannot be derived."), sourceKey);
    coverage.status = "invalid";
    return
end

coverage.start_native = min(finite);
coverage.end_native = max(finite);
[~, startSeconds] = normalizeTimeValue(coverage.start_native, nativeUnit, ...
    "coverage.start");
[~, endSeconds] = normalizeTimeValue(coverage.end_native, nativeUnit, "coverage.end");
coverage.start_seconds = startSeconds;
coverage.end_seconds = endSeconds;
coverage.status = "mapped";
end

% ---------------------------------------------------------------- utilities ---

function value = declaredSourceField(rule, declared)
value = "";
if declared && isstruct(rule) && hasProfileField(rule, "source_field")
    value = string(rule.source_field);
end
end

function value = declaredUnit(rule, declared)
value = "";
if declared && isstruct(rule) && hasProfileField(rule, "native_unit")
    value = string(rule.native_unit);
end
end

function value = optionalNumber(container, field)
value = NaN;
if ~hasProfileField(container, field)
    return
end
candidate = container.(char(field));
if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
    value = double(candidate);
end
end

function values = trackingColumnText(tbl, columnName)
column = tbl.(char(columnName));
if iscell(column)
    values = strings(numel(column), 1);
    for index = 1:numel(column)
        values(index) = sourceRawToken(column{index});
    end
    return
end
if iscategorical(column)
    column = string(column);
end
values = string(column);
values = values(:);
values(ismissing(values)) = "";
end

function values = trackingColumnNumeric(tbl, columnName)
column = tbl.(char(columnName));
if iscell(column)
    values = NaN(numel(column), 1);
    for index = 1:numel(column)
        values(index) = str2double(sourceRawToken(column{index}));
    end
    return
end
if isnumeric(column) || islogical(column)
    values = double(column);
    values = values(:);
    return
end
values = str2double(string(column));
values = values(:);
end

function value = trackingTimeTransform(nativeUnit)
switch string(nativeUnit)
    case "s"
        value = "identity";
    case "ms"
        value = "milliseconds_to_seconds";
    case "us"
        value = "microseconds_to_seconds";
    otherwise
        value = "identity";
end
end

function value = trackingFilename(filename, relativePath, runtimePath)
value = string(filename);
if strlength(value) > 0
    return
end
candidate = string(relativePath);
if strlength(candidate) == 0
    candidate = string(runtimePath);
end
if strlength(candidate) == 0
    value = "";
    return
end
[~, stem, extension] = fileparts(candidate);
value = string(stem) + string(extension);
end

function result = appendIssues(result, issues, sourceKey)
if isempty(issues)
    return
end
result.issues = [result.issues; normalizeIssuesForIR(issues, SourceKey=sourceKey)];
end

function result = updateTrackingSourceStatus(result, sourceKey, status)
rows = result.sources.source_key == sourceKey;
if ~any(rows)
    return
end
if status == "invalid"
    result.sources.status(rows) = "invalid";
elseif any(result.issues.severity == "warning")
    result.sources.status(rows) = "mapped_with_warnings";
end
end
