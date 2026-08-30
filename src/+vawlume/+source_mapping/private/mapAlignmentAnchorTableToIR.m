function result = mapAlignmentAnchorTableToIR(tbl, result, entry, profileLocation, options)
%MAPALIGNMENTANCHORTABLETOIR Normalize long or wide anchor tables into one IR.

sourceKey = options.SourceKey;
if strlength(sourceKey) == 0 || sourceKey == "source:in_memory_table"
    sourceKey = optionalText(entry.source, "source_key_default");
end
if strlength(sourceKey) == 0
    sourceKey = "source:alignment_anchor_table";
end
nativeUnit = string(entry.context.native_time_unit);
timeTransform = timeTransformKey(nativeUnit);
filename = resolvedFilename(options.Filename, options.RelativePath, options.RuntimePath);
result.sources(end + 1, :) = {sourceKey, options.RuntimePath, ...
    replace(options.RelativePath, "\", "/"), filename, "alignment_anchor_table", ...
    "supplied_table", optionalText(entry.source, "table_role"), ...
    "mapped", height(tbl), ""};

layoutKind = lower(string(entry.layout.kind));
switch layoutKind
    case "long"
        result = mapLong(tbl, result, entry, profileLocation, sourceKey, nativeUnit, ...
            timeTransform, options.EventContext);
    case "wide"
        result = mapWide(tbl, result, entry, profileLocation, sourceKey, nativeUnit, ...
            timeTransform);
    otherwise
        issue = makeIssue("error", "ANCHOR_LAYOUT_UNSUPPORTED", ...
            profileLocation + ".layout.kind", "Unsupported anchor layout: " + layoutKind + ".");
        result = addIssues(result, issue, sourceKey, "");
end

result = resolveDuplicateInclusion(result, sourceKey);
result = populateFitPairs(result, entry, sourceKey);
result = updateSourceStatus(result, sourceKey);
result = finalizeIntermediateRepresentation(result);
end

function result = mapLong(tbl, result, entry, location, sourceKey, nativeUnit, ...
        timeTransform, eventContext)
columns = entry.columns;
[anchorField, ~, issue] = resolveMappedColumn(tbl, columns.anchor_key, ...
    "marker", location + ".columns.anchor_key", true, "COLUMN_MISSING");
result = addIssues(result, issue, sourceKey, "");
[identityField, ~, issue] = resolveMappedColumn(tbl, columns.observation_identity, ...
    ["stream", "timebase"], location + ".columns.observation_identity", true, ...
    "COLUMN_MISSING");
result = addIssues(result, issue, sourceKey, "");
[timestampField, timestampResolution, issue] = resolveMappedColumn(tbl, columns.timestamp, ...
    ["timestamp_s", "timestamp_ms"], location + ".columns.timestamp", true, ...
    "TIMESTAMP_COLUMN_MISSING");
result = addIssues(result, issue, sourceKey, "");

optionalNames = ["observation_role", "included_in_fit", "uncertainty", ...
    "event_reference", "event_source_key", "anchor_type", "expected_order"];
defaults = {"role", "", "", "", "", "", ""};
resolved = struct(anchor_key=anchorField, observation_identity=identityField, ...
    timestamp=timestampField);
for index = 1:numel(optionalNames)
    name = optionalNames(index);
    [resolved.(name), ~, issue] = resolveMappedColumn(tbl, profileRule(columns, name), ...
        defaults{index}, location + ".columns." + name, false, "COLUMN_MISSING");
    result = addIssues(result, issue, sourceKey, "");
end
result = reportUnmapped(tbl, columns, resolved, entry, location, result, sourceKey);

for rowIndex = 1:height(tbl)
    locator = "row:" + rowIndex;
    rawAnchorKey = sourceToken(tbl, anchorField, rowIndex);
    recordKey = sourceKey + "|anchor-row:" + compose("%08d", rowIndex);
    anchorStatus = "mapped";
    if strlength(rawAnchorKey) == 0
        issue = makeIssue("error", "ANCHOR_KEY_MISSING", locator, ...
            "Anchor observation has no logical anchor key.");
        result = addIssues(result, issue, sourceKey, recordKey);
        rawAnchorKey = "<missing-row-" + rowIndex + ">";
        anchorStatus = "invalid";
    end

    anchorType = sourceToken(tbl, resolved.anchor_type, rowIndex);
    if strlength(anchorType) == 0
        anchorType = optionalText(entry.context, "default_anchor_type");
    end
    expectedOrder = numericOptional(tbl, resolved.expected_order, rowIndex);
    result = addOrValidateAnchor(result, rawAnchorKey, sourceKey, rowIndex, locator, ...
        anchorType, expectedOrder, anchorStatus);

    identity = sourceToken(tbl, identityField, rowIndex);
    [streamKey, timebaseKey, identityOk] = resolveIdentity(identity, entry.context);
    observationStatus = anchorStatus;
    if strlength(identity) == 0
        issue = makeIssue("error", "ANCHOR_OBSERVATION_IDENTITY_MISSING", locator, ...
            "Anchor observation has no stream/timebase logical key.");
        result = addIssues(result, issue, sourceKey, recordKey);
        observationStatus = "invalid";
    elseif ~identityOk
        issue = makeIssue("error", "ANCHOR_IDENTITY_UNDECLARED", locator, ...
            "Anchor stream/timebase is not declared in mapping context: " + identity + ".");
        result = addIssues(result, issue, sourceKey, recordKey);
        observationStatus = "invalid";
    end

    observedNative = NaN;
    observedSeconds = NaN;
    if strlength(timestampField) > 0
        [observedNative, observedSeconds, issue] = normalizeTimeValue( ...
            sourceTableValue(tbl, timestampField, rowIndex), nativeUnit, ...
            locator + ":" + timestampField);
        result = addIssues(result, issue, sourceKey, recordKey);
        if ~isempty(issue)
            observationStatus = "invalid";
        end
    else
        observationStatus = "invalid";
    end

    role = lower(sourceToken(tbl, resolved.observation_role, rowIndex));
    if strlength(role) > 0 && ~ismember(role, ["primary", "replicate", "excluded"])
        issue = makeIssue("error", "ANCHOR_ROLE_INVALID", locator, ...
            "Observation role must be primary, replicate, or excluded.");
        result = addIssues(result, issue, sourceKey, recordKey);
        observationStatus = "invalid";
    end
    [included, inclusionOk] = includedValue(tbl, resolved.included_in_fit, rowIndex);
    if ~inclusionOk
        issue = makeIssue("error", "ANCHOR_INCLUDED_INVALID", locator, ...
            "included_in_fit must be true/false, yes/no, or 1/0.");
        result = addIssues(result, issue, sourceKey, recordKey);
        observationStatus = "invalid";
    elseif isnan(included)
        if role == "primary"
            included = 1;
        elseif ismember(role, ["replicate", "excluded"])
            included = 0;
        end
    end
    if role == "excluded" && included == 1
        issue = makeIssue("error", "ANCHOR_INCLUDED_INVALID", locator, ...
            "An excluded observation cannot be included in fit.");
        result = addIssues(result, issue, sourceKey, recordKey);
        observationStatus = "invalid";
    end

    uncertaintySeconds = NaN;
    if strlength(resolved.uncertainty) > 0
        uncertaintyValue = sourceTableValue(tbl, resolved.uncertainty, rowIndex);
        if ~isMissing(uncertaintyValue)
            [~, uncertaintySeconds, issue] = normalizeTimeValue(uncertaintyValue, ...
                nativeUnit, locator + ":" + resolved.uncertainty);
            if isempty(issue) && uncertaintySeconds < 0
                issue = makeIssue("error", "ANCHOR_UNCERTAINTY_INVALID", locator, ...
                    "Observation uncertainty cannot be negative.");
            end
            result = addIssues(result, issue, sourceKey, recordKey);
            if ~isempty(issue)
                observationStatus = "invalid";
            end
        end
    end

    eventReference = sourceToken(tbl, resolved.event_reference, rowIndex);
    eventSource = sourceToken(tbl, resolved.event_source_key, rowIndex);
    if strlength(eventSource) == 0
        eventSource = optionalText(entry.context, "event_source_key_default");
    end
    if strlength(eventReference) > 0 && ...
            ~eventReferenceExists(eventContext, eventSource, eventReference)
        issue = makeIssue("error", "EVENT_REFERENCE_UNRESOLVED", locator, ...
            "Event reference cannot be resolved in the supplied mapped event context: " + ...
            eventReference + ".");
        result = addIssues(result, issue, sourceKey, recordKey);
        observationStatus = "invalid";
    end

    observationKey = sourceKey + "|observation:row:" + compose("%08d", rowIndex);
    result.anchor_observations(end + 1, :) = {observationKey, rawAnchorKey, ...
        sourceKey, rowIndex, locator, streamKey, timebaseKey, observedNative, ...
        observedSeconds, nativeUnit, timeTransform, timestampField, timestampResolution, ...
        role, included, ...
        uncertaintySeconds, eventSource, eventReference, "layout.long", observationStatus};
end
end

function result = mapWide(tbl, result, entry, location, sourceKey, nativeUnit, timeTransform)
columns = entry.columns;
[anchorField, ~, issue] = resolveMappedColumn(tbl, columns.anchor_key, ...
    "marker", location + ".columns.anchor_key", true, "COLUMN_MISSING");
result = addIssues(result, issue, sourceKey, "");
optionalNames = ["anchor_type", "expected_order"];
resolved = struct(anchor_key=anchorField);
for index = 1:numel(optionalNames)
    name = optionalNames(index);
    [resolved.(name), ~, issue] = resolveMappedColumn(tbl, profileRule(columns, name), ...
        "", location + ".columns." + name, false, "COLUMN_MISSING");
    result = addIssues(result, issue, sourceKey, "");
end

streamColumns = mappingSequence(entry.layout, "stream_columns");
actualFields = strings(numel(streamColumns), 1);
actualResolutions = strings(numel(streamColumns), 1);
for index = 1:numel(streamColumns)
    rule = streamColumns{index};
    [actualFields(index), actualResolutions(index), issue] = resolveMappedColumn(tbl, rule, strings(0, 1), ...
        location + ".layout.stream_columns(" + index + ")", true, ...
        "WIDE_STREAM_COLUMN_MISSING");
    result = addIssues(result, issue, sourceKey, "");
end
result = reportUnmappedWide(tbl, columns, resolved, streamColumns, actualFields, ...
    entry, location, result, sourceKey);

for rowIndex = 1:height(tbl)
    locator = "row:" + rowIndex;
    rawAnchorKey = sourceToken(tbl, anchorField, rowIndex);
    recordKey = sourceKey + "|anchor-row:" + compose("%08d", rowIndex);
    anchorStatus = "mapped";
    if strlength(rawAnchorKey) == 0
        issue = makeIssue("error", "ANCHOR_KEY_MISSING", locator, ...
            "Wide anchor row has no logical anchor key.");
        result = addIssues(result, issue, sourceKey, recordKey);
        rawAnchorKey = "<missing-row-" + rowIndex + ">";
        anchorStatus = "invalid";
    end
    anchorType = sourceToken(tbl, resolved.anchor_type, rowIndex);
    if strlength(anchorType) == 0
        anchorType = optionalText(entry.context, "default_anchor_type");
    end
    expectedOrder = numericOptional(tbl, resolved.expected_order, rowIndex);
    result = addOrValidateAnchor(result, rawAnchorKey, sourceKey, rowIndex, locator, ...
        anchorType, expectedOrder, anchorStatus);

    for streamIndex = 1:numel(streamColumns)
        actualField = actualFields(streamIndex);
        if strlength(actualField) == 0
            continue
        end
        value = sourceTableValue(tbl, actualField, rowIndex);
        if isMissing(value)
            continue
        end
        rule = streamColumns{streamIndex};
        observationStatus = anchorStatus;
        [observedNative, observedSeconds, issue] = normalizeTimeValue(value, nativeUnit, ...
            locator + ":" + actualField);
        result = addIssues(result, issue, sourceKey, recordKey);
        if ~isempty(issue)
            observationStatus = "invalid";
        end
        observationKey = sourceKey + "|observation:row:" + ...
            compose("%08d", rowIndex) + "|column:" + compose("%04d", streamIndex);
        result.anchor_observations(end + 1, :) = {observationKey, rawAnchorKey, ...
            sourceKey, rowIndex, locator + ":" + actualField, ...
            optionalText(rule, "stream_key"), string(rule.timebase_key), ...
            observedNative, observedSeconds, nativeUnit, timeTransform, actualField, ...
            actualResolutions(streamIndex), "primary", ...
            1, NaN, "", "", "layout.wide.stream_columns(" + streamIndex + ")", ...
            observationStatus};
    end
end
end

function result = populateFitPairs(result, entry, sourceKey)
if ~isfield(entry, "context")
    return
end
pairs = mappingSequence(entry.context, "fit_pairs");
observations = result.anchor_observations( ...
    result.anchor_observations.source_key == sourceKey, :);
for pairIndex = 1:numel(pairs)
    pair = pairs{pairIndex};
    sourceTimebase = string(pair.source_timebase_key);
    referenceTimebase = string(pair.reference_timebase_key);
    eligible = 0;
    anchorKeys = unique(observations.anchor_key);
    for anchorIndex = 1:numel(anchorKeys)
        key = anchorKeys(anchorIndex);
        sourceIncluded = observations.anchor_key == key & ...
            observations.timebase_key == sourceTimebase & ...
            observations.included_in_fit == 1 & observations.status ~= "invalid";
        referenceIncluded = observations.anchor_key == key & ...
            observations.timebase_key == referenceTimebase & ...
            observations.included_in_fit == 1 & observations.status ~= "invalid";
        if nnz(sourceIncluded) == 1 && nnz(referenceIncluded) == 1
            eligible = eligible + 1;
        end
    end
    status = "ready";
    if eligible == 0
        status = "no_fit_eligible_anchors";
    end
    result.anchor_fit_pairs(end + 1, :) = {sourceTimebase, referenceTimebase, ...
        eligible, status};
end
end

function result = addOrValidateAnchor(result, anchorKey, sourceKey, sourceRow, locator, ...
        anchorType, expectedOrder, status)
matches = result.anchors.source_key == sourceKey & result.anchors.anchor_key == anchorKey;
if ~any(matches)
    result.anchors(end + 1, :) = {anchorKey, sourceKey, sourceRow, locator, ...
        anchorType, expectedOrder, "logical_anchor", status};
    return
end
row = find(matches, 1);
typeConflict = strlength(anchorType) > 0 && ...
    strlength(result.anchors.anchor_type(row)) > 0 && ...
    result.anchors.anchor_type(row) ~= anchorType;
orderConflict = isfinite(expectedOrder) && isfinite(result.anchors.expected_order(row)) && ...
    result.anchors.expected_order(row) ~= expectedOrder;
if typeConflict || orderConflict
    issue = makeIssue("error", "ANCHOR_METADATA_CONFLICT", locator, ...
        "Repeated rows for one logical anchor disagree on anchor metadata.");
    result = addIssues(result, issue, sourceKey, anchorKey);
    result.anchors.status(row) = "invalid";
end
end

function [streamKey, timebaseKey, ok] = resolveIdentity(identity, context)
streamKey = "";
timebaseKey = "";
ok = false;
mappings = mappingSequence(context, "stream_timebases");
for index = 1:numel(mappings)
    mapping = mappings{index};
    candidates = [optionalText(mapping, "native_value"), ...
        optionalText(mapping, "stream_key"), optionalText(mapping, "timebase_key")];
    if ismember(identity, candidates)
        streamKey = optionalText(mapping, "stream_key");
        timebaseKey = optionalText(mapping, "timebase_key");
        ok = strlength(timebaseKey) > 0;
        return
    end
end
declared = textSequence(context, "declared_timebases");
if ismember(identity, declared)
    timebaseKey = identity;
    ok = true;
end
end

function result = resolveDuplicateInclusion(result, sourceKey)
rows = find(result.anchor_observations.source_key == sourceKey & ...
    strlength(result.anchor_observations.anchor_key) > 0 & ...
    strlength(result.anchor_observations.timebase_key) > 0);
if isempty(rows)
    return
end
groups = unique(result.anchor_observations.anchor_key(rows) + "|" + ...
    result.anchor_observations.timebase_key(rows));
for groupIndex = 1:numel(groups)
    groupRows = rows(result.anchor_observations.anchor_key(rows) + "|" + ...
        result.anchor_observations.timebase_key(rows) == groups(groupIndex));
    included = result.anchor_observations.included_in_fit(groupRows);
    primary = result.anchor_observations.observation_role(groupRows) == "primary";
    if sum(included == 1) > 1 || sum(primary) > 1
        issue = makeIssue("error", "ANCHOR_PRIMARY_AMBIGUOUS", groups(groupIndex), ...
            "More than one primary/included observation exists for one anchor/timebase.");
        result = addIssues(result, issue, sourceKey, "");
        result.anchor_observations.status(groupRows) = "invalid";
        continue
    end
    unresolved = groupRows(isnan(included));
    if isscalar(groupRows) && isscalar(unresolved)
        result.anchor_observations.included_in_fit(unresolved) = 1;
        if strlength(result.anchor_observations.observation_role(unresolved)) == 0
            result.anchor_observations.observation_role(unresolved) = "primary";
        end
    elseif numel(groupRows) > 1 && sum(included == 1) == 1
        result.anchor_observations.included_in_fit(unresolved) = 0;
        blankRoles = unresolved(strlength( ...
            result.anchor_observations.observation_role(unresolved)) == 0);
        result.anchor_observations.observation_role(blankRoles) = "replicate";
    elseif isscalar(unresolved)
        result.anchor_observations.included_in_fit(unresolved) = 1;
        if strlength(result.anchor_observations.observation_role(unresolved)) == 0
            result.anchor_observations.observation_role(unresolved) = "primary";
        end
    elseif numel(unresolved) > 1
        issue = makeIssue("error", "ANCHOR_PRIMARY_AMBIGUOUS", groups(groupIndex), ...
            "Duplicate observations have no explicit primary/inclusion resolution.");
        result = addIssues(result, issue, sourceKey, "");
        result.anchor_observations.status(groupRows) = "invalid";
    end
end
end

function tf = eventReferenceExists(eventContext, eventSource, eventReference)
tf = false;
if ~isstruct(eventContext) || ~isfield(eventContext, "events") || ...
        ~istable(eventContext.events) || isempty(eventContext.events)
    return
end
rows = eventContext.events;
matches = rows.native_event_id == eventReference;
if strlength(eventSource) > 0
    matches = matches & rows.source_key == eventSource;
end
tf = nnz(matches) == 1;
end

function [included, ok] = includedValue(tbl, field, rowIndex)
included = NaN;
ok = true;
if strlength(field) == 0
    return
end
raw = sourceTableValue(tbl, field, rowIndex);
if isMissing(raw)
    return
end
if islogical(raw) && isscalar(raw)
    included = double(raw);
elseif isnumeric(raw) && isscalar(raw) && ismember(double(raw), [0, 1])
    included = double(raw);
else
    token = lower(strtrim(sourceRawToken(raw)));
    if ismember(token, ["true", "yes", "1"])
        included = 1;
    elseif ismember(token, ["false", "no", "0"])
        included = 0;
    else
        ok = false;
    end
end
end

function result = reportUnmapped(tbl, columns, resolved, entry, location, result, sourceKey)
claimed = strings(0, 1);
names = string(fieldnames(resolved));
for index = 1:numel(names)
    claimed = [claimed; ruleLabels(profileRule(columns, names(index)))]; %#ok<AGROW>
    try
        actual = string(resolved.(char(names(index))));
        if isscalar(actual) && any(string(tbl.Properties.VariableNames) == actual)
            claimed(end + 1, 1) = actual; %#ok<AGROW>
        end
    catch
    end
end
result = addUnmappedIssues(tbl, claimed, entry, location, result, sourceKey);
end

function result = reportUnmappedWide(tbl, columns, resolved, streamColumns, actualFields, ...
        entry, location, result, sourceKey)
claimed = strings(0, 1);
names = string(fieldnames(resolved));
for index = 1:numel(names)
    claimed = [claimed; ruleLabels(profileRule(columns, names(index)))]; %#ok<AGROW>
    try
        actual = string(resolved.(char(names(index))));
        if isscalar(actual) && any(string(tbl.Properties.VariableNames) == actual)
            claimed(end + 1, 1) = actual; %#ok<AGROW>
        end
    catch
    end
end
for index = 1:numel(streamColumns)
    claimed = [claimed; ruleLabels(streamColumns{index})]; %#ok<AGROW>
end
claimed = [claimed; actualFields];
result = addUnmappedIssues(tbl, claimed, entry, location, result, sourceKey);
end

function result = addUnmappedIssues(tbl, claimed, entry, location, result, sourceKey)
variables = string(tbl.Properties.VariableNames);
unmapped = variables(~ismember(variables, unique(claimed)));
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

function result = updateSourceStatus(result, sourceKey)
issues = result.issues(result.issues.source_key == sourceKey, :);
status = "mapped";
if any(ismember(issues.severity, ["error", "fatal"]))
    status = "invalid";
elseif any(issues.severity == "warning")
    status = "mapped_with_warnings";
end
result.sources.status(result.sources.source_key == sourceKey) = status;
end

function value = numericOptional(tbl, field, rowIndex)
value = NaN;
if strlength(field) == 0
    return
end
raw = sourceTableValue(tbl, field, rowIndex);
if isMissing(raw)
    return
end
if isnumeric(raw) || islogical(raw)
    candidate = double(raw);
else
    candidate = str2double(string(raw));
end
if isscalar(candidate) && isfinite(candidate)
    value = candidate;
end
end

function value = sourceToken(tbl, field, rowIndex)
value = "";
if strlength(field) > 0
    value = sourceRawToken(sourceTableValue(tbl, field, rowIndex));
end
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

function values = textSequence(container, field)
values = strings(0, 1);
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
raw = container.(char(field));
if iscell(raw)
    values = strings(numel(raw), 1);
    for index = 1:numel(raw)
        values(index) = string(raw{index});
    end
else
    values = string(raw(:));
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
