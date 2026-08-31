function value = regularizeTimeline(commonTimeView, channels, options)
%REGULARIZETIMELINE Bin common-time events without persisting dense rows.
%
% VALUE = vawlume.sequence.regularizeTimeline(VIEW, CHANNELS, ...) accepts the
% derived output of vawlume.alignment.commonTime and returns a MATLAB table.
% It performs no database writes and does not create sequences.
%
% CHANNELS is a struct array with scalar fields:
%   name, event_source_kind, normalized_event_key, coverage_key, aggregation
%
% Supported aggregations are onset_count, presence, and any_overlap. Bins are
% half-open [start,end), including the last bin: an onset exactly at WindowEnd
% is outside the requested window. A bin is covered only when one declared
% observed interval covers the complete bin. Numeric channel values use NaN
% when unavailable and 0 when covered but empty; each channel also receives an
% explicit <name>_covered logical column.

arguments
    commonTimeView (1,1) struct
    channels (1,:) struct
    options.WindowStart (1,1) double {mustBeFinite}
    options.WindowEnd (1,1) double {mustBeFinite}
    options.BinWidth (1,1) double {mustBeFinite, mustBePositive}
    options.BinOrigin (1,1) double = NaN
end

validateView(commonTimeView);
validateWindow(options);
channels = validateChannels(channels);

origin = options.BinOrigin;
if isnan(origin), origin = options.WindowStart; end
offsetBins = (options.WindowStart - origin) / options.BinWidth;
if abs(offsetBins - round(offsetBins)) > 1e-9
    error("vawlume:sequence:BinOriginMisaligned", ...
        "WindowStart must lie on the BinOrigin + k*BinWidth grid.");
end
binCountRaw = (options.WindowEnd - options.WindowStart) / options.BinWidth;
if abs(binCountRaw - round(binCountRaw)) > 1e-9
    error("vawlume:sequence:WindowNotDivisible", ...
        "The requested window must contain a whole number of bins.");
end
binCount = round(binCountRaw);
starts = options.WindowStart + (0:binCount-1)' * options.BinWidth;
ends = starts + options.BinWidth;
timeline = table(starts, ends, VariableNames=["bin_start", "bin_end"]);

events = commonTimeView.events;
coverage = commonTimeView.coverage;
for channelIndex = 1:numel(channels)
    channel = channels(channelIndex);
    selectedCoverage = coverage.coverage_key == channel.coverage_key & ...
        coverage.observation_status == "observed";
    covered = false(binCount, 1);
    for binIndex = 1:binCount
        covered(binIndex) = any( ...
            coverage.aligned_start(selectedCoverage) <= starts(binIndex) & ...
            coverage.aligned_end(selectedCoverage) >= ends(binIndex));
    end

    selectedEvents = events.event_source_kind == channel.event_source_kind & ...
        events.normalized_event_key == channel.normalized_event_key & ...
        events.coverage_key == channel.coverage_key;
    chosen = events(selectedEvents, :);
    data = NaN(binCount, 1);
    data(covered) = 0;
    for binIndex = find(covered)'
        if channel.aggregation == "any_overlap"
            eventEnds = chosen.aligned_end;
            pointRows = ~isfinite(eventEnds);
            eventEnds(pointRows) = chosen.aligned_start(pointRows);
            overlaps = (chosen.aligned_start < ends(binIndex) & ...
                eventEnds > starts(binIndex)) | ...
                (pointRows & chosen.aligned_start >= starts(binIndex) & ...
                chosen.aligned_start < ends(binIndex));
            data(binIndex) = double(any(overlaps));
        else
            onsets = chosen.aligned_start >= starts(binIndex) & ...
                chosen.aligned_start < ends(binIndex);
            count = nnz(onsets);
            if channel.aggregation == "presence"
                data(binIndex) = double(count > 0);
            else
                data(binIndex) = count;
            end
        end
    end
    timeline.(channel.name + "_covered") = covered;
    timeline.(channel.name) = data;
end

referenceKey = "";
referenceId = NaN;
if isfield(commonTimeView, "specification")
    spec = commonTimeView.specification;
    if isfield(spec, "reference_timebase_key")
        referenceKey = string(spec.reference_timebase_key);
    end
    if isfield(spec, "reference_timebase_id")
        referenceId = double(spec.reference_timebase_id);
    end
end
value = struct(timeline=timeline, specification=struct( ...
    reference_timebase_id=referenceId, ...
    reference_timebase_key=referenceKey, ...
    window_start=options.WindowStart, window_end=options.WindowEnd, ...
    bin_width=options.BinWidth, bin_origin=origin, ...
    edge_convention="half-open [start,end); WindowEnd excluded", ...
    coverage_rule="full bin must lie within one observed interval", ...
    unavailable_representation="NaN plus explicit <channel>_covered=false", ...
    channels=channels, persistence="derived MATLAB table; no SQLite rows"));
end

function validateView(value)
if ~isfield(value, "events") || ~istable(value.events) || ...
        ~isfield(value, "coverage") || ~istable(value.coverage)
    error("vawlume:sequence:CommonTimeViewInvalid", ...
        "VIEW must contain common-time events and coverage tables.");
end
requiredEvents = ["event_source_kind", "normalized_event_key", ...
    "coverage_key", "aligned_start", "aligned_end"];
requiredCoverage = ["coverage_key", "observation_status", ...
    "aligned_start", "aligned_end"];
if ~all(ismember(requiredEvents, string(value.events.Properties.VariableNames))) || ...
        ~all(ismember(requiredCoverage, string(value.coverage.Properties.VariableNames)))
    error("vawlume:sequence:CommonTimeViewInvalid", ...
        "VIEW does not implement the common-time table contract.");
end
end

function validateWindow(options)
if options.WindowEnd <= options.WindowStart
    error("vawlume:sequence:WindowInvalid", ...
        "WindowEnd must be greater than WindowStart.");
end
end

function value = validateChannels(value)
required = ["name", "event_source_kind", "normalized_event_key", ...
    "coverage_key", "aggregation"];
if isempty(value)
    error("vawlume:sequence:ChannelsRequired", ...
        "At least one channel specification is required.");
end
if ~all(isfield(value, required))
    error("vawlume:sequence:ChannelInvalid", ...
        "Every channel needs name, event source, event key, coverage key, and aggregation.");
end
names = strings(numel(value), 1);
for index = 1:numel(value)
    fields = required;
    for fieldIndex = 1:numel(fields)
        field = fields(fieldIndex);
        text = string(value(index).(field));
        if ~isscalar(text) || ismissing(text) || strlength(text) == 0
            error("vawlume:sequence:ChannelInvalid", ...
                "Channel %d field %s must be nonempty scalar text.", index, field);
        end
        value(index).(field) = text;
    end
    if ~ismember(value(index).aggregation, ...
            ["onset_count", "presence", "any_overlap"])
        error("vawlume:sequence:AggregationUnsupported", ...
            "Channel '%s' requests unsupported aggregation '%s'.", ...
            value(index).name, value(index).aggregation);
    end
    if ~isvarname(value(index).name)
        error("vawlume:sequence:ChannelNameInvalid", ...
            "Channel name '%s' is not a valid MATLAB variable name.", ...
            value(index).name);
    end
    names(index) = value(index).name;
end
if numel(unique(names)) ~= numel(names)
    error("vawlume:sequence:ChannelNameDuplicate", ...
        "Channel names must be unique.");
end
end
