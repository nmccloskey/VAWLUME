function result = mapExternalStreamTableToIR(tbl, result, entry, profileLocation, options)
%MAPEXTERNALSTREAMTABLETOIR Normalize an external event table into the unified IR.

sourceKey = options.SourceKey;
if strlength(sourceKey) == 0 || sourceKey == "source:in_memory_table"
    sourceKey = optionalText(entry.source, "source_key_default");
end
if strlength(sourceKey) == 0
    sourceKey = "source:external_event_table";
end
streamKey = string(entry.context.stream_key);
timebaseKey = string(entry.context.timebase_key);
nativeUnit = string(entry.context.native_time_unit);
timeTransform = timeTransformKey(nativeUnit);

filename = resolvedFilename(options.Filename, options.RelativePath, options.RuntimePath);
artifactType = optionalText(entry.source, "table_role");
result.sources(end + 1, :) = {sourceKey, options.RuntimePath, ...
    replace(options.RelativePath, "\", "/"), filename, "external_event_table", ...
    "supplied_table", artifactType, "mapped", height(tbl), ""};
result.streams(end + 1, :) = {streamKey, sourceKey, timebaseKey, ...
    string(entry.context.stream_kind), optionalText(entry.context, "modality"), ...
    nativeUnit, "s", "mapped"};

columns = entry.columns;
[resolved, result] = resolveCoreColumns(tbl, columns, profileLocation, result, sourceKey);
attributes = mappingSequence(entry, "attributes");
[attributeFields, result] = resolveAttributeColumns(tbl, attributes, profileLocation, ...
    result, sourceKey);
result = reportUnmappedColumns(tbl, columns, attributes, resolved, attributeFields, ...
    entry, profileLocation, result, sourceKey);

for rowIndex = 1:height(tbl)
    eventKey = sourceKey + "|event:row:" + compose("%08d", rowIndex);
    recordKey = eventKey;
    locator = "row:" + rowIndex;
    status = "mapped";

    nativeId = sourceToken(tbl, resolved.native_event_id, rowIndex);
    nativeLabel = sourceToken(tbl, resolved.native_event_label, rowIndex);
    normalizedLabel = normalizedEventLabel(nativeLabel, entry);
    entityKey = sourceToken(tbl, resolved.entity_key, rowIndex);

    startNative = NaN;
    startSeconds = NaN;
    if strlength(resolved.start_time) > 0
        [startNative, startSeconds, issue] = normalizeTimeValue( ...
            sourceTableValue(tbl, resolved.start_time, rowIndex), nativeUnit, ...
            locator + ":" + resolved.start_time);
        if ~isempty(issue)
            result = addIssues(result, issue, sourceKey, recordKey);
            status = "invalid";
        end
    else
        status = "invalid";
    end

    endNative = startNative;
    endSeconds = startSeconds;
    if strlength(resolved.end_time) > 0
        endValue = sourceTableValue(tbl, resolved.end_time, rowIndex);
        if ~isMissing(endValue)
            [endNative, endSeconds, issue] = normalizeTimeValue(endValue, nativeUnit, ...
                locator + ":" + resolved.end_time);
            if ~isempty(issue)
                result = addIssues(result, issue, sourceKey, recordKey);
                status = "invalid";
            end
        end
    end
    if isfinite(startNative) && isfinite(endNative) && endNative < startNative
        issue = makeIssue("error", "EVENT_INTERVAL_INVALID", locator, ...
            "Event end time precedes its start time.");
        result = addIssues(result, issue, sourceKey, recordKey);
        status = "invalid";
    end

    scalar = emptyTypedValue();
    if strlength(resolved.scalar_value) > 0
        rule = columns.scalar_value;
        [scalar, scalarIssues] = mapTypedSourceValue( ...
            sourceTableValue(tbl, resolved.scalar_value, rowIndex), rule, ...
            profileLocation + ".columns.scalar_value");
        result = addIssues(result, scalarIssues, sourceKey, recordKey);
        if scalar.status == "invalid"
            status = "invalid";
        end
    end

    result.events(end + 1, :) = {eventKey, sourceKey, streamKey, timebaseKey, ...
        rowIndex, locator, nativeId, nativeLabel, normalizedLabel, startNative, ...
        endNative, startSeconds, endSeconds, nativeUnit, timeTransform, ...
        resolved.start_time, resolved.end_time, resolved.start_time_resolution, ...
        resolved.end_time_resolution, entityKey, scalar.raw_value, scalar.value_real, ...
        scalar.value_integer, scalar.value_text, scalar.value_boolean, ...
        scalar.value_type, scalar.native_unit, scalar.normalized_unit, ...
        "external_event_mapping", status};

    for attributeIndex = 1:numel(attributes)
        actualField = attributeFields(attributeIndex);
        if strlength(actualField) == 0
            continue
        end
        rule = attributes{attributeIndex};
        [mapped, mappedIssues] = mapTypedSourceValue( ...
            sourceTableValue(tbl, actualField, rowIndex), rule, ...
            profileLocation + ".attributes(" + attributeIndex + ")");
        result = addIssues(result, mappedIssues, sourceKey, recordKey);
        attributeKey = eventKey + "|attribute:" + string(rule.attribute_name);
        result.event_attributes(end + 1, :) = {attributeKey, eventKey, sourceKey, ...
            rowIndex, locator, string(rule.source_field), actualField, ...
            string(rule.attribute_name), mapped.raw_value, mapped.value_type, ...
            mapped.value_real, mapped.value_integer, mapped.value_text, ...
            mapped.value_boolean, mapped.native_unit, mapped.normalized_unit, ...
            mapped.transform_key, "attributes(" + attributeIndex + ")", mapped.status};
    end
end

result = validateNativeEventIds(result, entry, sourceKey);
result = mapCoverage(result, entry, sourceKey, streamKey, timebaseKey, nativeUnit, ...
    timeTransform);
result = updateSourceStatus(result, sourceKey, streamKey);
result = finalizeIntermediateRepresentation(result);
end

function [resolved, result] = resolveCoreColumns(tbl, columns, location, result, sourceKey)
resolved = struct();
[resolved.start_time, resolved.start_time_resolution, issue] = resolveMappedColumn(tbl, columns.start_time, ...
    ["timestamp_s", "start_time_s"], location + ".columns.start_time", true, ...
    "TIMESTAMP_COLUMN_MISSING");
result = addIssues(result, issue, sourceKey, "");

optionalNames = ["end_time", "native_event_id", "native_event_label", ...
    "entity_key", "scalar_value"];
defaults = {"end_time_s", "event_id", ["event", "marker"], "", ""};
for index = 1:numel(optionalNames)
    name = optionalNames(index);
    rule = profileRule(columns, name);
    [resolved.(name), resolution, issue] = resolveMappedColumn(tbl, rule, defaults{index}, ...
        location + ".columns." + name, false, "COLUMN_MISSING");
    resolved.(name + "_resolution") = resolution;
    result = addIssues(result, issue, sourceKey, "");
end
end

function [fields, result] = resolveAttributeColumns(tbl, attributes, location, result, sourceKey)
fields = strings(numel(attributes), 1);
for index = 1:numel(attributes)
    rule = attributes{index};
    required = true;
    if isfield(rule, "required")
        required = logical(rule.required);
    end
    [fields(index), ~, issue] = resolveMappedColumn(tbl, rule, strings(0, 1), ...
        location + ".attributes(" + index + ")", required, "COLUMN_MISSING");
    result = addIssues(result, issue, sourceKey, "");
end
end

function result = reportUnmappedColumns(tbl, columns, attributes, resolved, attributeFields, ...
        entry, location, result, sourceKey)
claimed = strings(0, 1);
coreNames = string(fieldnames(resolved));
for index = 1:numel(coreNames)
    rule = profileRule(columns, coreNames(index));
    claimed = [claimed; ruleLabels(rule)]; %#ok<AGROW>
    try
        actual = string(resolved.(char(coreNames(index))));
        if isscalar(actual) && any(string(tbl.Properties.VariableNames) == actual)
            claimed(end + 1, 1) = actual; %#ok<AGROW>
        end
    catch
    end
end
for index = 1:numel(attributes)
    claimed = [claimed; ruleLabels(attributes{index})]; %#ok<AGROW>
end
claimed = unique([claimed; attributeFields]);
unmapped = string(tbl.Properties.VariableNames);
unmapped = unmapped(~ismember(unmapped, claimed));
severity = "info";
if isfield(entry, "mapping_policy")
    policy = lower(optionalText(entry.mapping_policy, "unknown_fields"));
    if ismember(policy, ["warn", "preserve_and_warn", "warn_and_preserve"])
        severity = "warning";
    elseif ismember(policy, ["error", "fail", "reject"])
        severity = "error";
    end
end
for index = 1:numel(unmapped)
    issue = makeIssue(severity, "SOURCE_COLUMN_UNMAPPED", ...
        location + ".mapping_policy.unknown_fields", ...
        "Supplied source column is not claimed by the profile: " + unmapped(index) + ".");
    result = addIssues(result, issue, sourceKey, "");
end
end

function result = validateNativeEventIds(result, entry, sourceKey)
if ~isfield(entry, "validation") || ~isfield(entry.validation, "native_event_id_unique") || ...
        ~logical(entry.validation.native_event_id_unique)
    return
end
rows = find(result.events.source_key == sourceKey & ...
    strlength(result.events.native_event_id) > 0);
ids = result.events.native_event_id(rows);
[groups, ~, groupIndex] = unique(ids);
counts = accumarray(groupIndex, 1);
duplicates = groups(counts > 1);
for index = 1:numel(duplicates)
    issue = makeIssue("error", "NATIVE_EVENT_ID_DUPLICATE", "events.native_event_id", ...
        "Profile promises unique native event IDs, but this value is repeated: " + ...
        duplicates(index) + ".");
    result = addIssues(result, issue, sourceKey, "");
    matches = rows(ids == duplicates(index));
    result.events.status(matches) = "invalid";
end
end

function result = mapCoverage(result, entry, sourceKey, streamKey, timebaseKey, ...
        nativeUnit, timeTransform)
if ~isfield(entry, "coverage") || ~isstruct(entry.coverage) || ...
        ~isfield(entry.coverage, "segments")
    return
end
segments = mappingSequence(entry.coverage, "segments");
for index = 1:numel(segments)
    segment = segments{index};
    locator = "profile:coverage.segments(" + index + ")";
    [startNative, startSeconds, startIssue] = normalizeTimeValue( ...
        segment.start_time_native, nativeUnit, locator + ".start_time_native");
    [endNative, endSeconds, endIssue] = normalizeTimeValue( ...
        segment.end_time_native, nativeUnit, locator + ".end_time_native");
    result = addIssues(result, startIssue, sourceKey, "");
    result = addIssues(result, endIssue, sourceKey, "");
    status = "mapped";
    if ~isempty(startIssue) || ~isempty(endIssue) || ...
            (isfinite(startNative) && isfinite(endNative) && endNative < startNative)
        status = "invalid";
        if isempty(startIssue) && isempty(endIssue) && endNative < startNative
            issue = makeIssue("error", "COVERAGE_INTERVAL_INVALID", locator, ...
                "Coverage end time precedes its start time.");
            result = addIssues(result, issue, sourceKey, "");
        end
    end
    key = sourceKey + "|coverage:" + compose("%04d", index);
    result.coverage(end + 1, :) = {key, sourceKey, streamKey, timebaseKey, ...
        index, startNative, endNative, startSeconds, endSeconds, nativeUnit, ...
        timeTransform, locator, "coverage.constant_segments", "observed", status};
end
end

function result = updateSourceStatus(result, sourceKey, streamKey)
issues = result.issues(result.issues.source_key == sourceKey, :);
status = "mapped";
if any(ismember(issues.severity, ["error", "fatal"]))
    status = "invalid";
elseif any(issues.severity == "warning")
    status = "mapped_with_warnings";
end
result.sources.status(result.sources.source_key == sourceKey) = status;
result.streams.status(result.streams.stream_key == streamKey) = status;
end

function label = normalizedEventLabel(nativeLabel, entry)
label = nativeLabel;
if strlength(nativeLabel) == 0 || ~isfield(entry, "normalized_event_mapping")
    return
end
mapping = entry.normalized_event_mapping;
if ~isfield(mapping, "mappings")
    return
end
items = mappingSequence(mapping, "mappings");
for index = 1:numel(items)
    item = items{index};
    if sourceRawToken(item.native_value) == nativeLabel
        label = string(item.normalized_value);
        return
    end
end
end

function value = sourceToken(tbl, field, rowIndex)
value = "";
if strlength(field) > 0
    value = sourceRawToken(sourceTableValue(tbl, field, rowIndex));
end
end

function typed = emptyTypedValue()
typed = struct(raw_value="", value_type="", value_real=NaN, ...
    value_integer=NaN, value_text="", value_boolean=NaN, native_unit="", ...
    normalized_unit="", transform_key="", status="mapped");
end

function result = addIssues(result, rawIssues, sourceKey, recordKey)
if isempty(rawIssues)
    return
end
result.issues = [result.issues; normalizeIssuesForIR(rawIssues, ...
    SourceKey=sourceKey, RecordKey=recordKey)];
end

function rule = profileRule(columns, name)
rule = struct();
if isstruct(columns) && isfield(columns, char(name)) && ...
        isstruct(columns.(char(name)))
    rule = columns.(char(name));
end
end

function labels = ruleLabels(rule)
labels = strings(0, 1);
for field = ["source_field", "aliases", "default_source_fields"]
    if isstruct(rule) && isfield(rule, char(field))
        raw = rule.(char(field));
        if iscell(raw)
            for index = 1:numel(raw)
                labels(end + 1, 1) = string(raw{index}); %#ok<AGROW>
            end
        else
            labels = [labels; string(raw(:))]; %#ok<AGROW>
        end
    end
end
labels = labels(strlength(labels) > 0);
end

function items = mappingSequence(container, field)
items = {};
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
raw = container.(char(field));
if iscell(raw)
    items = raw(:);
elseif isstruct(raw)
    items = num2cell(raw(:));
end
end

function value = optionalText(container, field)
value = "";
if isstruct(container) && isfield(container, char(field)) && ...
        ~isempty(container.(char(field)))
    try
        candidate = string(container.(char(field)));
        if isscalar(candidate) && ~ismissing(candidate)
            value = candidate;
        end
    catch
    end
end
end

function key = timeTransformKey(unit)
if ismember(lower(string(unit)), ["ms", "millisecond", "milliseconds"])
    key = "ms_to_s";
else
    key = "identity";
end
end

function tf = isMissing(value)
tf = isempty(value);
if ~tf
    try
        mask = ismissing(value);
        tf = isscalar(mask) && mask;
    catch
    end
end
if ~tf && isnumeric(value) && isscalar(value)
    tf = isnan(value);
end
end

function name = resolvedFilename(name, relativePath, runtimePath)
if strlength(name) > 0
    return
end
candidate = relativePath;
if strlength(candidate) == 0
    candidate = runtimePath;
end
if strlength(candidate) > 0
    [~, stem, extension] = fileparts(candidate);
    name = string(stem) + string(extension);
end
end
