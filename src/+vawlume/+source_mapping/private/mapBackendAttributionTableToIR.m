function result = mapBackendAttributionTableToIR(tbl, result, profileEntry, profileLocation, options)
%MAPBACKENDATTRIBUTIONTABLETOIR Map a localization backend's export into the IR.
%
% The database-free half of the backend adapter. It produces, at WINDOW grain:
%
%   attribution_windows                 one per distinct backend window
%   attribution_claims                  one per (window, claimed caller)
%   attribution_localization_estimates  one per distinct estimate
%   attribution_channel_evidence        one per (window, channel, evidence kind)
%   attribution_track_references        one per claim the backend tied to a track
%   attribution_native_attributes       one per (owner, declared attribute)
%   attribution_declared_inputs         one per declared uncertainty source
%
% Nothing here opens a database and nothing here relates a backend window to a
% VAWLUME event. The declared KEYS -- coordinate system, channel index, tracking
% stream and track, caller entity -- are carried as declared and resolved at
% intake, where an unknown one is refused.
%
% THE BACKEND'S NUMBERS ARE COPIED, NOT INTERPRETED. Coordinates, confidences,
% scores and channel values reach the IR exactly as the source carried them: a
% numeric cell passes through unchanged and a text cell is parsed once. No
% rescaling, clamping, unit conversion, frame transformation, or promotion of a
% score or confidence to a probability.
%
% A ROW IS ALL OR NOTHING. Everything a row contributes is staged and committed
% only if nothing in it is refused, so a refused row never leaves an orphan
% window, claim or estimate behind -- a fragment the backend did not say on its
% own. Every refusal is an issue naming the row and the reason; nothing is
% dropped silently.

context = profileEntry.context;
columns = profileEntry.columns;
sourceKey = options.SourceKey;
timebaseKey = string(context.window_timebase_key);
nativeUnit = string(context.native_time_unit);
exportingSystem = string(context.exporting_system);
exportingVersion = optionalText(context, "exporting_system_version");
producer = attributionProducerLabel(exportingSystem, exportingVersion);
semantics = renderedSemantics(profileEntry, producer);

hasCaller = isfield(columns, "caller_label");
resolution = containers.Map("KeyType", "char", "ValueType", "char");
if hasCaller
    resolution = attributionCallerLabelMap(profileEntry.caller_label_resolution);
end
trackStreamKey = optionalText(context, "tracking_stream_key");

localization = struct();
hasLocalization = isfield(profileEntry, "localization");
if hasLocalization
    localization = profileEntry.localization;
end
attachment = "window";
if hasLocalization && strlength(optionalText(localization, "attachment")) > 0
    attachment = optionalText(localization, "attachment");
end
contextFrameKey = optionalText(context, "coordinate_system_key");
confidenceRange = [];
if hasLocalization && isfield(localization, "confidence_range")
    confidenceRange = double(localization.confidence_range(:))';
end

channelEntries = {};
declaredChannels = [];
if isfield(profileEntry, "channel_evidence")
    channelBlock = profileEntry.channel_evidence;
    channelEntries = sequence(channelBlock.entries);
    declaredChannels = double(channelBlock.declared_channel_indices(:))';
end
attributeDeclarations = {};
if isfield(profileEntry, "native_attributes")
    attributeDeclarations = sequence(profileEntry.native_attributes);
end

windows = result.attribution_windows;
claims = result.attribution_claims;
estimates = result.attribution_localization_estimates;
channelRows = result.attribution_channel_evidence;
trackRows = result.attribution_track_references;
attributeRows = result.attribution_native_attributes;
mappedRows = 0;

for row = 1:height(tbl)
    locator = sourceKey + "#row=" + string(row);

    % --- the window: required, and every other element attaches to it -----
    [windowId, ok] = attributionRequiredCell(tbl, columns.native_window_id.source_field, row);
    if ~ok
        result = addRowIssue(result, sourceKey, locator, "ATTRIBUTION_WINDOW_ID_MISSING", ...
            "Row " + row + " carries no native window identifier and cannot be mapped.");
        continue
    end
    [startTime, okStart] = attributionNumericCell(tbl, columns.window_start.source_field, row);
    [endTime, okEnd] = attributionNumericCell(tbl, columns.window_end.source_field, row);
    if ~okStart || ~okEnd
        result = addRowIssue(result, sourceKey, locator, "ATTRIBUTION_WINDOW_BOUNDS_MISSING", ...
            "Row " + row + " (window " + windowId + ") has no usable start or end time.");
        continue
    end
    if endTime < startTime
        result = addRowIssue(result, sourceKey, locator, "ATTRIBUTION_WINDOW_REVERSED", ...
            "Row " + row + " (window " + windowId + ") ends before it starts.");
        continue
    end
    windowKey = sourceKey + ":window:" + windowId;
    existingWindow = find(windows.window_key == windowKey, 1);
    if ~isempty(existingWindow) && ...
            (windows.start_time_native(existingWindow) ~= startTime || ...
            windows.end_time_native(existingWindow) ~= endTime)
        result = addRowIssue(result, sourceKey, locator, "BACKEND_WINDOW_CONFLICT", ...
            "Row " + row + " gives window " + windowId + " bounds that differ from an " + ...
            "earlier row. Keeping either would silently discard what the other said.");
        continue
    end
    stagedWindow = windows([], :);
    if isempty(existingWindow)
        stagedWindow = windowRow(windowKey, sourceKey, row, locator, windowId, ...
            timebaseKey, startTime, endTime, nativeUnit, profileLocation);
    end

    % --- the claim: optional; a row with no caller carries none -----------
    stagedClaim = claims([], :);
    claimKey = "";
    if hasCaller
        [label, hasLabel] = attributionRequiredCell(tbl, columns.caller_label.source_field, row);
        [score, hasScore] = optionalNumeric(tbl, columns, "score", row);
        [probability, hasProbability] = optionalNumeric(tbl, columns, "probability", row);
        [~, hasTrack] = optionalText2(tbl, columns, "native_track_id", row);
        if ~hasLabel
            if hasScore || hasProbability || hasTrack
                result = addRowIssue(result, sourceKey, locator, ...
                    "BACKEND_NUMBER_WITHOUT_CALLER", ...
                    "Row " + row + " (window " + windowId + ") carries a caller score, " + ...
                    "probability or track but names no caller to attach it to.");
                continue
            end
        else
            if ~isKey(resolution, char(label))
                result = addRowIssue(result, sourceKey, locator, ...
                    "ATTRIBUTION_CALLER_LABEL_UNDECLARED", ...
                    "Caller label '" + label + "' (row " + row + ") is not declared in " + ...
                    "caller_label_resolution. VAWLUME does not infer which entity a " + ...
                    "label denotes.");
                continue
            end
            if hasProbability && (probability < 0 || probability > 1)
                result = addRowIssue(result, sourceKey, locator, ...
                    "ATTRIBUTION_PROBABILITY_OUT_OF_RANGE", ...
                    "Row " + row + " declares probability " + string(probability) + ...
                    ", which lies outside [0,1]. It is refused rather than clamped.");
                continue
            end
            claimKey = windowKey + ":claim:" + label;
            candidateClaim = claimRow(claimKey, windowKey, sourceKey, row, locator, ...
                label, string(resolution(char(label))), score, hasScore, ...
                probability, hasProbability, semantics, exportingSystem, ...
                exportingVersion, profileLocation);
            existingClaim = find(claims.claim_key == claimKey, 1);
            if isempty(existingClaim)
                stagedClaim = candidateClaim;
            elseif ~sameNumbers(claims(existingClaim, :), candidateClaim, ...
                    ["score", "probability"])
                result = addRowIssue(result, sourceKey, locator, "BACKEND_CLAIM_CONFLICT", ...
                    "Row " + row + " repeats caller " + label + " over window " + ...
                    windowId + " with a different score or probability.");
                continue
            end
        end
    end

    stagedTrack = trackRows([], :);
    if hasCaller && strlength(claimKey) > 0
        [trackId, hasTrack] = optionalText2(tbl, columns, "native_track_id", row);
        if hasTrack
            existingTrack = find(trackRows.claim_key == claimKey, 1);
            if isempty(existingTrack)
                stagedTrack = table(claimKey + ":track", claimKey, sourceKey, row, ...
                    locator, trackStreamKey, trackId, profileLocation, "reference", ...
                    VariableNames=trackRows.Properties.VariableNames);
            elseif trackRows.native_track_id(existingTrack) ~= trackId
                result = addRowIssue(result, sourceKey, locator, "BACKEND_TRACK_CONFLICT", ...
                    "Row " + row + " ties caller claim " + claimKey + " to track " + ...
                    trackId + ", but an earlier row tied it to " + ...
                    trackRows.native_track_id(existingTrack) + ".");
                continue
            end
        end
    end

    % --- the localization estimate: optional ------------------------------
    stagedEstimate = estimates([], :);
    estimateKey = "";
    if hasLocalization
        [x, hasX] = attributionNumericCell(tbl, localization.position_x.source_field, row);
        [y, hasY] = attributionNumericCell(tbl, localization.position_y.source_field, row);
        [z, hasZ] = optionalNumeric(tbl, localization, "position_z", row);
        [confidence, hasConfidenceValue] = optionalNumeric(tbl, localization, "confidence", row);
        if hasX ~= hasY
            result = addRowIssue(result, sourceKey, locator, "BACKEND_COORDINATE_AXIS_MISSING", ...
                "Row " + row + " (window " + windowId + ") reports one horizontal " + ...
                "coordinate without the other. Half a position is refused, not completed.");
            continue
        end
        if ~hasX && (hasZ || hasConfidenceValue)
            result = addRowIssue(result, sourceKey, locator, ...
                "BACKEND_CONFIDENCE_WITHOUT_POSITION", ...
                "Row " + row + " (window " + windowId + ") reports a height or a " + ...
                "localization confidence with no position to attach it to.");
            continue
        end
        if hasX
            frameKey = contextFrameKey;
            if isfield(localization, "coordinate_system")
                [rowFrame, hasRowFrame] = attributionRequiredCell(tbl, ...
                    localization.coordinate_system.source_field, row);
                frameKey = "";
                if hasRowFrame
                    frameKey = rowFrame;
                end
            end
            % The refusal this mapper exists to make: a coordinate without a
            % frame is not a weak coordinate, it is not a coordinate, and this
            % is the last place it can be caught before a table stores it.
            if strlength(frameKey) == 0
                result = addRowIssue(result, sourceKey, locator, ...
                    "BACKEND_COORDINATE_FRAME_MISSING", ...
                    "Row " + row + " (window " + windowId + ") reports a position with " + ...
                    "no declared coordinate system. Coordinates without a frame are refused.");
                continue
            end
            if hasConfidenceValue && ~isempty(confidenceRange) && ...
                    (confidence < confidenceRange(1) || confidence > confidenceRange(2))
                result = addRowIssue(result, sourceKey, locator, ...
                    "BACKEND_CONFIDENCE_OUT_OF_RANGE", ...
                    "Row " + row + " reports localization confidence " + ...
                    string(confidence) + ", outside the declared range [" + ...
                    string(confidenceRange(1)) + ", " + string(confidenceRange(2)) + ...
                    "]. It is refused rather than clamped.");
                continue
            end
            estimateClaimKey = "";
            if attachment == "claim"
                if strlength(claimKey) == 0
                    result = addRowIssue(result, sourceKey, locator, ...
                        "BACKEND_ESTIMATE_CLAIM_MISSING", ...
                        "Row " + row + " reports a position, and the profile attaches " + ...
                        "estimates to claims, but the row names no caller.");
                    continue
                end
                estimateClaimKey = claimKey;
            end
            [nativeEstimateId, hasNativeId] = optionalText2(tbl, localization, ...
                "native_estimate_id", row);
            [declaredOrdinal, hasDeclaredOrdinal] = optionalNumeric(tbl, localization, ...
                "estimate_ordinal", row);
            if hasDeclaredOrdinal && (declaredOrdinal < 1 || ...
                    declaredOrdinal ~= round(declaredOrdinal))
                result = addRowIssue(result, sourceKey, locator, ...
                    "BACKEND_ESTIMATE_ORDINAL_INVALID", ...
                    "Row " + row + " gives estimate ordinal " + string(declaredOrdinal) + ...
                    "; an ordinal is an integer of at least 1.");
                continue
            end
            ownerKey = windowKey;
            if strlength(estimateClaimKey) > 0
                ownerKey = estimateClaimKey;
            end
            if hasNativeId
                estimateKey = ownerKey + ":estimate:id:" + nativeEstimateId;
            elseif hasDeclaredOrdinal
                estimateKey = ownerKey + ":estimate:ordinal:" + string(declaredOrdinal);
            else
                % No producer identity: identical positions in one frame for one
                % owner are the same estimate repeated across a window's rows.
                estimateKey = ownerKey + ":estimate:at:" + frameKey + ":" + ...
                    exactText(x) + ":" + exactText(y) + ":" + exactText(z);
            end
            candidate = estimateRow(estimateKey, windowKey, estimateClaimKey, ...
                sourceKey, row, locator, declaredOrdinal, hasDeclaredOrdinal, ...
                nativeEstimateId, frameKey, x, y, z, confidence, hasConfidenceValue, ...
                semantics, profileLocation);
            existingEstimate = find(estimates.estimate_key == estimateKey, 1);
            if isempty(existingEstimate)
                if ~hasDeclaredOrdinal
                    candidate.estimate_ordinal = ...
                        sum(estimates.window_key == windowKey) + 1;
                elseif any(estimates.window_key == windowKey & ...
                        estimates.estimate_ordinal == declaredOrdinal)
                    result = addRowIssue(result, sourceKey, locator, ...
                        "BACKEND_ESTIMATE_CONFLICT", ...
                        "Row " + row + " reuses estimate ordinal " + ...
                        string(declaredOrdinal) + " within window " + windowId + ...
                        " for a different estimate.");
                    continue
                end
                stagedEstimate = candidate;
            elseif ~sameNumbers(estimates(existingEstimate, :), candidate, ...
                    ["position_x", "position_y", "position_z", "confidence"]) || ...
                    estimates.coordinate_system_key(existingEstimate) ~= frameKey
                result = addRowIssue(result, sourceKey, locator, "BACKEND_ESTIMATE_CONFLICT", ...
                    "Row " + row + " reports estimate " + estimateKey + " with a " + ...
                    "position, frame or confidence that differs from an earlier row.");
                continue
            end
        end
    end

    % --- per-channel evidence: optional ----------------------------------
    stagedChannels = channelRows([], :);
    refused = false;
    for entryIndex = 1:numel(channelEntries)
        item = channelEntries{entryIndex};
        valueField = string(item.value_field);
        [rawToken, hasValue] = attributionRequiredCell(tbl, valueField, row);
        if ~hasValue
            continue  % absence is absence: no row, never a zero
        end
        [channelValue, numericOk] = attributionNumericCell(tbl, valueField, row);
        if ~numericOk
            result = addRowIssue(result, sourceKey, locator, "BACKEND_CHANNEL_VALUE_INVALID", ...
                "Row " + row + " field " + valueField + " holds '" + rawToken + ...
                "', which is not a finite number.");
            refused = true;
            break
        end
        if isfield(item, "channel_index")
            channelIndex = double(item.channel_index);
        else
            [channelIndex, okIndex] = attributionNumericCell(tbl, ...
                string(item.channel_index_field), row);
            if ~okIndex
                channelIndex = NaN;
            end
        end
        if ~ismember(channelIndex, declaredChannels)
            result = addRowIssue(result, sourceKey, locator, "BACKEND_CHANNEL_UNDECLARED", ...
                "Row " + row + " reports evidence for channel " + string(channelIndex) + ...
                ", which the profile does not declare. A channel index is the " + ...
                "backend's assertion about the acquisition and must be declared.");
            refused = true;
            break
        end
        kind = string(item.evidence_kind);
        key = windowKey + ":channel:" + string(channelIndex) + ":" + kind;
        rendered = attributionRenderSemantics(string(item.value_semantics), producer);
        units = "";
        if isfield(item, "value_units")
            units = string(item.value_units);
        end
        candidate = table(key, windowKey, sourceKey, row, locator, channelIndex, kind, ...
            valueField, channelValue, rawToken, units, rendered, ...
            profileLocation + ".channel_evidence.entries[" + entryIndex + "]", "create", ...
            VariableNames=channelRows.Properties.VariableNames);
        existing = find(channelRows.channel_evidence_key == key, 1);
        if isempty(existing)
            if ~any(stagedChannels.channel_evidence_key == key)
                stagedChannels = [stagedChannels; candidate]; %#ok<AGROW>
            end
        elseif channelRows.value_real(existing) ~= channelValue
            result = addRowIssue(result, sourceKey, locator, ...
                "BACKEND_CHANNEL_EVIDENCE_CONFLICT", ...
                "Row " + row + " reports " + kind + " for channel " + ...
                string(channelIndex) + " of window " + windowId + ...
                " differently from an earlier row.");
            refused = true;
            break
        end
    end
    if refused
        continue
    end

    % --- native attributes: optional --------------------------------------
    stagedAttributes = attributeRows([], :);
    for declarationIndex = 1:numel(attributeDeclarations)
        declaration = attributeDeclarations{declarationIndex};
        owner = string(declaration.owner);
        switch owner
            case "window"
                ownerKey = windowKey;
            case "claim"
                ownerKey = claimKey;
            otherwise
                ownerKey = estimateKey;
        end
        field = string(declaration.source_field);
        rawToken = "";
        hasRaw = false;
        if ismember(field, string(tbl.Properties.VariableNames))
            [rawToken, hasRaw] = attributionRequiredCell(tbl, field, row);
        end
        if strlength(ownerKey) == 0
            if hasRaw
                result = addRowIssue(result, sourceKey, locator, ...
                    "BACKEND_ATTRIBUTE_OWNER_ABSENT", ...
                    "Row " + row + " carries native field " + field + ", declared as " + ...
                    owner + "-level, but the row has no " + owner + " to own it. " + ...
                    "The value is not preserved.", false);
            end
            continue
        end
        [typed, typeOk] = typedAttribute(rawToken, hasRaw, string(declaration.value_type));
        if ~typeOk
            result = addRowIssue(result, sourceKey, locator, "BACKEND_ATTRIBUTE_TYPE_INVALID", ...
                "Row " + row + " native field " + field + " holds '" + rawToken + ...
                "', which is not a valid " + string(declaration.value_type) + ".");
            refused = true;
            break
        end
        name = string(declaration.attribute_name);
        unit = "";
        if isfield(declaration, "unit")
            unit = string(declaration.unit);
        end
        key = ownerKey + ":attribute:" + name;
        candidate = table(key, owner, ownerKey, sourceKey, row, locator, name, field, ...
            typed.value_type, typed.value_text, typed.value_real, typed.value_integer, ...
            typed.value_boolean, rawToken, unit, ...
            profileLocation + ".native_attributes[" + declarationIndex + "]", "create", ...
            VariableNames=attributeRows.Properties.VariableNames);
        existing = find(attributeRows.attribute_key == key, 1);
        if isempty(existing)
            stagedAttributes = [stagedAttributes; candidate]; %#ok<AGROW>
        elseif attributeRows.value_type(existing) ~= typed.value_type || ...
                attributeRows.native_raw_token(existing) ~= rawToken
            result = addRowIssue(result, sourceKey, locator, "BACKEND_ATTRIBUTE_CONFLICT", ...
                "Row " + row + " gives native field " + name + " of " + ownerKey + ...
                " a value that differs from an earlier row.");
            refused = true;
            break
        end
    end
    if refused
        continue
    end

    % --- the row survived: commit everything it contributed --------------
    windows = [windows; stagedWindow]; %#ok<AGROW>
    claims = [claims; stagedClaim]; %#ok<AGROW>
    trackRows = [trackRows; stagedTrack]; %#ok<AGROW>
    estimates = [estimates; stagedEstimate]; %#ok<AGROW>
    channelRows = [channelRows; stagedChannels]; %#ok<AGROW>
    attributeRows = [attributeRows; stagedAttributes]; %#ok<AGROW>
    mappedRows = mappedRows + 1;
end

declaredInputs = declaredInputRows(result.attribution_declared_inputs, ...
    profileEntry, profileLocation);

result.attribution_windows = windows;
result.attribution_claims = claims;
result.attribution_localization_estimates = estimates;
result.attribution_channel_evidence = channelRows;
result.attribution_track_references = trackRows;
result.attribution_native_attributes = attributeRows;
result.attribution_declared_inputs = declaredInputs;
result.summary = struct( ...
    profile_kind="attribution_backend_mapping", ...
    source_row_count=height(tbl), ...
    mapped_row_count=mappedRows, ...
    unmapped_row_count=height(tbl) - mappedRows, ...
    window_count=height(windows), ...
    claim_count=height(claims), ...
    estimate_count=height(estimates), ...
    channel_evidence_count=height(channelRows), ...
    track_reference_count=height(trackRows), ...
    native_attribute_count=height(attributeRows), ...
    declared_input_count=height(declaredInputs), ...
    coordinate_system_keys=unique(estimates.coordinate_system_key)', ...
    exporting_system=exportingSystem, ...
    exporting_system_version=exportingVersion, ...
    window_timebase_key=timebaseKey, ...
    timing_basis="native_to_backend", ...
    correspondence="none; backend windows are related to no VAWLUME event here", ...
    resolved_at_intake="coordinate_system_key, entity_native_id, channel_index, " + ...
        "tracking_stream_key/native_track_id");
result.valid_for_ingest = ~any(result.issues.affects_validity) && height(windows) > 0;
end

% ---------------------------------------------------------------- helpers ---

function semantics = renderedSemantics(profileEntry, producer)
semantics = struct(score="", probability="", position="", confidence="");
if ~isfield(profileEntry, "value_semantics")
    return
end
declared = profileEntry.value_semantics;
for field = ["score", "probability", "position", "confidence"]
    if isfield(declared, field)
        semantics.(field) = attributionRenderSemantics(string(declared.(field)), producer);
    end
end
end

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
% A label carrying no number records NaN for both, never 1.0.
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

function row = estimateRow(estimateKey, windowKey, claimKey, sourceKey, sourceRow, ...
        locator, ordinal, hasOrdinal, nativeId, frameKey, x, y, z, confidence, ...
        hasConfidence, semantics, mappingRule)
ordinalSource = "source_order";
if hasOrdinal
    ordinalSource = "declared";
else
    ordinal = NaN;  % assigned by the caller once the estimate is known to be new
end
confidenceValue = NaN;
confidenceSemantics = "";
if hasConfidence
    confidenceValue = confidence;
    confidenceSemantics = semantics.confidence;
end
row = table(estimateKey, windowKey, claimKey, sourceKey, sourceRow, locator, ...
    ordinal, ordinalSource, string(nativeId), frameKey, x, y, z, ...
    semantics.position, confidenceValue, confidenceSemantics, mappingRule, "create", ...
    VariableNames=["estimate_key", "window_key", "claim_key", "source_key", ...
    "source_row", "source_locator", "estimate_ordinal", "ordinal_source", ...
    "native_estimate_id", "coordinate_system_key", "position_x", "position_y", ...
    "position_z", "position_semantics", "confidence", "confidence_semantics", ...
    "mapping_rule", "status"]);
end

function rows = declaredInputRows(rows, profileEntry, profileLocation)
if ~isfield(profileEntry, "declared_inputs") || ...
        ~isfield(profileEntry.declared_inputs, "declarations")
    return
end
declarations = profileEntry.declared_inputs.declarations;
if ~isstruct(declarations)
    return
end
names = string(fieldnames(declarations));
for index = 1:numel(names)
    rows(end+1, :) = {names(index), string(declarations.(names(index))), ...
        profileLocation + ".declared_inputs.declarations." + names(index)}; %#ok<AGROW>
end
end

function [typed, ok] = typedAttribute(rawToken, hasRaw, valueType)
% Absence is recorded as 'missing', which stays distinguishable from a field
% that was never preserved. A present token that is not the declared type is
% refused rather than coerced.
typed = struct(value_type="missing", value_text="", value_real=NaN, ...
    value_integer=NaN, value_boolean=NaN);
ok = true;
if ~hasRaw
    return
end
switch valueType
    case "text"
        typed.value_type = "text";
        typed.value_text = rawToken;
    case "real"
        value = str2double(rawToken);
        ok = isfinite(value);
        typed.value_type = "real";
        typed.value_real = value;
    case "integer"
        value = str2double(rawToken);
        ok = isfinite(value) && value == round(value);
        typed.value_type = "integer";
        typed.value_integer = value;
    case "boolean"
        token = lower(rawToken);
        ok = ismember(token, ["true", "false", "1", "0"]);
        typed.value_type = "boolean";
        typed.value_boolean = double(ismember(token, ["true", "1"]));
    otherwise
        ok = false;
end
end

function same = sameNumbers(existing, candidate, names)
same = true;
for name = names
    same = same && isequaln(existing.(name), candidate.(name));
end
end

function text = exactText(value)
% Enough digits to round-trip a double, so two positions share a key only when
% they are the same number.
if isnan(value)
    text = "none";
else
    text = string(sprintf("%.17g", value));
end
end

function [value, ok] = optionalNumeric(tbl, container, name, row)
value = NaN;
ok = false;
if ~isfield(container, name)
    return
end
[value, ok] = attributionNumericCell(tbl, container.(name).source_field, row);
end

function [value, ok] = optionalText2(tbl, container, name, row)
value = "";
ok = false;
if ~isfield(container, name)
    return
end
[value, ok] = attributionRequiredCell(tbl, container.(name).source_field, row);
end

function value = optionalText(container, field)
value = "";
if isfield(container, field)
    value = strtrim(string(container.(field)));
end
end

function items = sequence(raw)
if iscell(raw)
    items = raw(:);
elseif isstruct(raw)
    items = num2cell(raw(:));
else
    items = {};
end
end

function result = addRowIssue(result, sourceKey, locator, code, message, affectsValidity)
% Reported, never dropped silently. A refused row is an error that keeps the
% plan from being applied; an unpreserved field on an otherwise sound row is a
% warning, because the row itself is still exactly what the backend said.
if nargin < 6
    affectsValidity = true;
end
severity = "error";
if ~affectsValidity
    severity = "warning";
end
issue = table("issue:" + string(height(result.issues) + 1), severity, ...
    string(code), sourceKey, "", locator, "", string(message), affectsValidity, ...
    VariableNames=["issue_key", "severity", "code", "source_key", ...
    "record_key", "location", "field_or_rule", "message", "affects_validity"]);
result.issues = [result.issues; issue];
end
