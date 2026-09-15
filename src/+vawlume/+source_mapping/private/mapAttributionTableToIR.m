function result = mapAttributionTableToIR(tbl, result, profileEntry, profileLocation, options)
%MAPATTRIBUTIONTABLETOIR Map an imported caller-attribution table into the IR.
%
% Produces one attribution_windows row per distinct native window and one
% attribution_claims row per source row. Nothing here touches the database, and
% nothing here relates an imported window to a VAWLUME event: that is
% correspondence work with its own eligibility rule, and doing it during mapping
% would make every import quietly assert a match.
%
% THE EXPORTING SYSTEM'S NUMBERS ARE COPIED, NOT INTERPRETED. No rescaling, no
% renormalization, no clamping, and no promotion of a score to a probability
% because it happened to fall in [0,1]. A re-normalized imported score is
% unauditable forever, because the original is gone.

context = profileEntry.context;
columns = profileEntry.columns;
resolution = callerLabelMap(profileEntry);

sourceKey = options.SourceKey;
timebaseKey = string(context.window_timebase_key);
nativeUnit = string(context.native_time_unit);
exportingSystem = string(context.exporting_system);
exportingVersion = optionalContextText(context, "exporting_system_version");
% Rendered, not copied: a stored semantics string names its producer. F4-1.
semantics = valueSemantics(profileEntry, ...
    producerLabel(exportingSystem, exportingVersion));

windows = result.attribution_windows;
claims = result.attribution_claims;
seenWindows = strings(0, 1);

for row = 1:height(tbl)
    locator = sourceKey + "#row=" + string(row);
    [windowId, ok] = requiredCell(tbl, columns.native_window_id.source_field, row);
    if ~ok
        result = addRowIssue(result, sourceKey, locator, ...
            "ATTRIBUTION_WINDOW_ID_MISSING", ...
            "Row " + row + " carries no native window identifier and cannot be mapped.");
        continue
    end
    [startTime, okStart] = numericCell(tbl, columns.window_start.source_field, row);
    [endTime, okEnd] = numericCell(tbl, columns.window_end.source_field, row);
    if ~okStart || ~okEnd
        result = addRowIssue(result, sourceKey, locator, ...
            "ATTRIBUTION_WINDOW_BOUNDS_MISSING", ...
            "Row " + row + " (window " + windowId + ") has no usable start or end time.");
        continue
    end
    if endTime < startTime
        result = addRowIssue(result, sourceKey, locator, ...
            "ATTRIBUTION_WINDOW_REVERSED", ...
            "Row " + row + " (window " + windowId + ") ends before it starts.");
        continue
    end
    [label, okLabel] = requiredCell(tbl, columns.caller_label.source_field, row);
    if ~okLabel
        result = addRowIssue(result, sourceKey, locator, ...
            "ATTRIBUTION_CALLER_LABEL_MISSING", ...
            "Row " + row + " (window " + windowId + ") names no caller.");
        continue
    end

    % Declared resolution only. A label VAWLUME has not been told about is a
    % surfaced problem, not a licence to guess which animal it means.
    entityNativeId = "";
    if isKey(resolution, char(label))
        entityNativeId = string(resolution(char(label)));
    else
        result = addRowIssue(result, sourceKey, locator, ...
            "ATTRIBUTION_CALLER_LABEL_UNDECLARED", ...
            "Caller label '" + label + "' (row " + row + ") is not declared in " + ...
            "caller_label_resolution. VAWLUME does not infer which entity a label " + ...
            "denotes.");
        continue
    end

    [score, hasScore] = optionalNumericCell(tbl, columns, "score", row);
    [probability, hasProbability] = optionalNumericCell(tbl, columns, ...
        "probability", row);
    if hasProbability && (probability < 0 || probability > 1)
        % Refused rather than clamped. Clamping would silently rewrite the
        % exporter's claim into one it never made.
        result = addRowIssue(result, sourceKey, locator, ...
            "ATTRIBUTION_PROBABILITY_OUT_OF_RANGE", ...
            "Row " + row + " declares probability " + string(probability) + ...
            ", which lies outside [0,1]. It is refused rather than clamped.");
        continue
    end

    % The window is appended only once a claim about it survives validation.
    % Adding it earlier would leave an orphan window in the plan whenever the
    % only claim naming it was refused -- a time span nobody asserted anything
    % about, which is not a thing the exporting system said.
    windowKey = sourceKey + ":window:" + windowId;
    if ~ismember(windowKey, seenWindows)
        seenWindows(end+1, 1) = windowKey; %#ok<AGROW>
        windows = [windows; windowRow(windowKey, sourceKey, row, locator, ...
            windowId, timebaseKey, startTime, endTime, nativeUnit, ...
            profileLocation)]; %#ok<AGROW>
    end

    claimKey = windowKey + ":claim:" + label;
    claims = [claims; claimRow(claimKey, windowKey, sourceKey, row, locator, ...
        label, entityNativeId, score, hasScore, probability, hasProbability, ...
        semantics, exportingSystem, exportingVersion, profileLocation)]; %#ok<AGROW>
end

result.attribution_windows = windows;
result.attribution_claims = claims;
result.summary = struct( ...
    profile_kind="attribution_input_mapping", ...
    source_row_count=height(tbl), ...
    window_count=height(windows), ...
    claim_count=height(claims), ...
    unmapped_row_count=height(tbl) - height(claims), ...
    exporting_system=exportingSystem, ...
    exporting_system_version=exportingVersion, ...
    window_timebase_key=timebaseKey, ...
    timing_basis="native_to_exporting_system", ...
    correspondence="none; imported windows are related to no VAWLUME event here");
result.valid_for_ingest = ~any(result.issues.affects_validity) && height(claims) > 0;
end

% ---------------------------------------------------------------- helpers ---

function row = windowRow(windowKey, sourceKey, sourceRow, locator, windowId, ...
        timebaseKey, startTime, endTime, nativeUnit, mappingRule)
row = table(windowKey, sourceKey, sourceRow, locator, string(windowId), ...
    timebaseKey, startTime, endTime, nativeUnit, mappingRule, "create", ...
    VariableNames=["window_key", "source_key", "source_row", "source_locator", ...
    "native_window_id", "timebase_key", "start_time_native", "end_time_native", ...
    "native_time_unit", "mapping_rule", "status"]);
end

function row = claimRow(claimKey, windowKey, sourceKey, sourceRow, locator, ...
        label, entityNativeId, score, hasScore, probability, hasProbability, ...
        semantics, exportingSystem, exportingVersion, mappingRule)
% A label carrying no number records NaN for both, never 1.0. Converting a name
% into certainty is the specific failure this refuses.
scoreValue = NaN;
scoreSemantics = "";
if hasScore
    scoreValue = score;
    scoreSemantics = semantics.score;
end
probabilityValue = NaN;
probabilitySemantics = "";
if hasProbability
    probabilityValue = probability;
    probabilitySemantics = semantics.probability;
end
row = table(claimKey, windowKey, sourceKey, sourceRow, locator, ...
    string(label), string(entityNativeId), scoreValue, scoreSemantics, ...
    probabilityValue, probabilitySemantics, exportingSystem, exportingVersion, ...
    mappingRule, "create", ...
    VariableNames=["claim_key", "window_key", "source_key", "source_row", ...
    "source_locator", "caller_label", "entity_native_id", "score", ...
    "score_semantics", "probability", "probability_semantics", ...
    "exporting_system", "exporting_system_version", "mapping_rule", "status"]);
end

function result = addRowIssue(result, sourceKey, locator, code, message)
% Reported, never dropped silently. A preview that hides what it could not read
% is worse than one that reads nothing.
issue = table("issue:" + string(height(result.issues) + 1), "error", ...
    string(code), sourceKey, "", locator, "", string(message), true, ...
    VariableNames=["issue_key", "severity", "code", "source_key", ...
    "record_key", "location", "field_or_rule", "message", "affects_validity"]);
result.issues = [result.issues; issue];
end

function semantics = valueSemantics(profileEntry, producer)
%VALUESEMANTICS Render the declared semantics; do not merely copy them.
%
% A stored semantics string must NAME the system that produced the number. The
% shipped profile used to say "producer declared in context.exporting_system",
% which is a pointer into a file rather than a value: a reader holding only the
% database got a sentence that referred to something they could not see. F4-1.
%
% Two mechanisms, because a profile VAWLUME did not ship cannot be relied on to
% cooperate:
%
%   1. {producer} is substituted wherever the profile declares it, so an author
%      controls where the name appears in their own sentence.
%   2. If the rendered string still does not contain the exporting system's name,
%      "; producer=<name>" is appended.
%
% The append looks like VAWLUME editing somebody's declaration and is not. This
% string is PROSE VAWLUME COMPOSES from facts the profile declared -- the system
% name is `context.exporting_system`, in the same file. Composing two
% declarations is not inventing one. The rule that forbids recomputation governs
% the NUMBER, and no number is touched here or anywhere in this function.
semantics = struct(score="", probability="");
if ~isfield(profileEntry, "value_semantics")
    return
end
declared = profileEntry.value_semantics;
for field = ["score", "probability"]
    if isfield(declared, field)
        semantics.(field) = renderSemantics(string(declared.(field)), producer);
    end
end
end

function value = renderSemantics(declared, producer)
value = strtrim(declared);
if strlength(value) == 0 || strlength(producer) == 0
    return
end
value = replace(value, "{producer}", producer);
if ~contains(value, producer)
    value = value + "; producer=" + producer;
end
end

function value = producerLabel(exportingSystem, exportingVersion)
%PRODUCERLABEL How the exporting system is named inside a semantics string.
%
% The version joins the name only when one was actually declared. The shipped
% template's default is the literal "unknown", and rendering "Example System
% unknown" would put a disclaimer where a reader expects a version -- worse than
% emitting nothing, because it reads like a version somebody chose.
value = strtrim(string(exportingSystem));
version = strtrim(string(exportingVersion));
if strlength(value) == 0
    value = "";
    return
end
if strlength(version) > 0 && lower(version) ~= "unknown"
    value = value + " " + version;
end
end

function map = callerLabelMap(profileEntry)
map = containers.Map("KeyType", "char", "ValueType", "char");
declared = profileEntry.caller_label_resolution.map;
if isstruct(declared)
    entries = num2cell(declared(:));
elseif iscell(declared)
    entries = declared(:);
else
    entries = {};
end
for index = 1:numel(entries)
    item = entries{index};
    map(char(string(item.caller_label))) = char(string(item.entity_native_id));
end
end

function value = optionalContextText(context, field)
value = "";
if isfield(context, field)
    value = string(context.(field));
end
end

function [value, ok] = requiredCell(tbl, field, row)
value = "";
ok = false;
name = string(field);
if ~ismember(name, string(tbl.Properties.VariableNames))
    return
end
raw = tbl.(name)(row);
value = strtrim(string(raw));
ok = strlength(value) > 0 && ~ismissing(value);
end

function [value, ok] = numericCell(tbl, field, row)
value = NaN;
ok = false;
name = string(field);
if ~ismember(name, string(tbl.Properties.VariableNames))
    return
end
raw = tbl.(name)(row);
if isnumeric(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
ok = ~isnan(value) && isfinite(value);
end

function [value, ok] = optionalNumericCell(tbl, columns, name, row)
value = NaN;
ok = false;
if ~isfield(columns, name)
    return
end
[value, ok] = numericCell(tbl, columns.(name).source_field, row);
end
