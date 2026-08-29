function routed = deepsqueakRouteEventValues(ir, dictionary, artifactKey)
%DEEPSQUEAKROUTEEVENTVALUES Route mapped IR evidence to its relational destination.
%
% Routing follows declared semantics, never column names. Two authorities decide,
% and neither lives in this file:
%
%   the registered feature dictionary - a value whose native field is a
%       registered extractor_feature is an event measurement, because seed
%       registration promoted exactly the profile's event_measurement mappings
%       into that dictionary;
%   the profile's semantic_role - carried through the IR, deciding which values
%       additionally populate detection identity, detection geometry, detection
%       score, review state, or a class label.
%
% A value may have two destinations. Score is both a registered measurement and
% the detection's indexed confidence; start and end times are both measurements
% and the detection's canonical event geometry. That duplication is deliberate:
% the detection columns exist for indexing and matching, while the measurement
% rows retain native units, transforms, and operational definitions.

arguments
    ir (1,1) struct
    dictionary (1,1) struct
    artifactKey (1,1) string
end

routed = struct();
routed.rows = {};
routed.unregistered_fields = strings(0, 1);

values = ir.values;
if height(values) == 0
    return
end

sourceRows = sort(unique(values.source_row(~isnan(values.source_row))));
unregistered = strings(0, 1);
for index = 1:numel(sourceRows)
    sourceRow = sourceRows(index);
    rowValues = values(values.source_row == sourceRow, :);
    row = routeOneRow(rowValues, sourceRow, dictionary, artifactKey);
    routed.rows{index, 1} = row;
    unregistered = [unregistered; row.unregistered_fields]; %#ok<AGROW>
end
routed.unregistered_fields = unique(unregistered);
end

function row = routeOneRow(rowValues, sourceRow, dictionary, artifactKey)
row = struct();
row.source_row = sourceRow;
row.native_event_id = "";
row.native_event_id_status = "absent";
row.start_time_s = NaN;
row.end_time_s = NaN;
row.duration_s = NaN;
row.frequency_min = NaN;
row.frequency_max = NaN;
row.frequency_bandwidth = NaN;
row.detection_score = NaN;
row.review_raw_token = "";
row.review_status = "";
row.review_present = false;
row.label_raw_token = "";
row.label_present = false;
row.measurements = emptyMeasurementTable();
row.unregistered_fields = strings(0, 1);
row.provenance_fields = strings(0, 1);

for index = 1:height(rowValues)
    value = table2struct(rowValues(index, :));
    consumed = applySemanticRole(row, value);
    row = consumed.row;

    featureIndex = matchFeature(dictionary, value, artifactKey);
    if ~isnan(featureIndex)
        row.measurements(end + 1, :) = measurementRow(value, dictionary, featureIndex);
        continue
    end
    if consumed.handled
        continue
    end
    if string(value.semantic_role) == "artifact_locator"
        row.provenance_fields(end + 1, 1) = string(value.native_field);
        continue
    end
    row.unregistered_fields(end + 1, 1) = string(value.native_field);
end

row = applyGeometry(row);
end

function result = applySemanticRole(row, value)
%APPLYSEMANTICROLE Populate detection-level fields declared by semantic role.
result = struct(row=row, handled=false);
switch string(value.semantic_role)
    case "identifier"
        result.row.native_event_id = identifierText(value);
        if string(value.status) == "missing" || strlength(result.row.native_event_id) == 0
            result.row.native_event_id_status = "missing";
        else
            result.row.native_event_id_status = "present";
        end
        result.handled = true;
    case "curation_state"
        % DeepSqueak's accept flag is extractor review state, never a biological
        % truth claim, so it populates curation evidence and nothing else.
        result.row.review_present = true;
        result.row.review_raw_token = string(value.raw_value);
        result.row.review_status = string(value.normalized_value_text);
        result.handled = true;
    case "native_class_or_manual_label"
        result.row.label_present = string(value.status) ~= "missing";
        result.row.label_raw_token = string(value.normalized_value_text);
        if strlength(result.row.label_raw_token) == 0
            result.row.label_raw_token = string(value.raw_value);
        end
        result.handled = true;
    case "detector_model_score"
        % Also a registered measurement; the detection column is the indexed
        % copy used for ordering and matching.
        result.row.detection_score = numericValue(value);
end
end

function row = applyGeometry(row)
%APPLYGEOMETRY Select detection geometry by profile-declared equivalence class.
%
% Equivalence classes rather than canonical field names or native column labels
% are the selector, because they are the extractor-independent vocabulary the
% profiles and the seeded feature relationships already share. That keeps the
% same selection working unchanged for a second extractor.
for index = 1:height(row.measurements)
    measurement = table2struct(row.measurements(index, :));
    switch string(measurement.equivalence_class)
        case "vocalization_start_time"
            row.start_time_s = measurement.canonical_value_real;
        case "vocalization_end_time"
            row.end_time_s = measurement.canonical_value_real;
        case "vocalization_duration"
            row.duration_s = measurement.canonical_value_real;
        case "vocalization_frequency_min"
            row.frequency_min = measurement.canonical_value_real;
        case "vocalization_frequency_max"
            row.frequency_max = measurement.canonical_value_real;
        case "vocalization_frequency_bandwidth"
            row.frequency_bandwidth = measurement.canonical_value_real;
    end
end
end

function featureIndex = matchFeature(dictionary, value, artifactKey)
featureIndex = NaN;
if isempty(dictionary.keys)
    return
end
key = string(value.native_field) + "|" + artifactKey + "|" + ...
    string(value.derivation_stage) + "|" + string(value.operational_variant);
matches = find(dictionary.keys == key, 1);
if ~isempty(matches)
    featureIndex = matches;
end
end

function row = measurementRow(value, dictionary, featureIndex)
feature = dictionary.features(featureIndex, :);
canonicalFeatureId = double(feature.canonical_feature_id(1));

row = {
    double(feature.extractor_feature_id(1)), ...
    canonicalFeatureId, ...
    string(feature.native_name(1)), ...
    string(value.canonical_field), ...
    string(value.equivalence_class), ...
    string(value.native_value_type), ...
    string(value.raw_value), ...
    value.native_value_real, ...
    value.native_value_integer, ...
    string(value.native_value_text), ...
    string(value.native_unit), ...
    normalizedReal(value), ...
    normalizedInteger(value), ...
    normalizedText(value), ...
    string(value.canonical_unit), ...
    string(value.transform_key), ...
    string(value.operational_variant), ...
    sourceLocator(value)};
end

function result = normalizedReal(value)
if string(value.normalized_value_type) == "real"
    result = value.normalized_value_real;
else
    result = NaN;
end
end

function result = normalizedInteger(value)
if string(value.normalized_value_type) == "integer"
    result = value.normalized_value_integer;
else
    result = NaN;
end
end

function result = normalizedText(value)
if string(value.normalized_value_type) == "text"
    result = string(value.normalized_value_text);
else
    result = "";
end
end

function locator = sourceLocator(value)
locator = "row=" + string(value.source_row) + "; column=" + ...
    string(value.actual_source_field);
end

function text = identifierText(value)
switch string(value.normalized_value_type)
    case "integer"
        text = string(value.normalized_value_integer);
    case "real"
        text = string(value.normalized_value_real);
    case "text"
        text = string(value.normalized_value_text);
    otherwise
        text = "";
end
end

function result = numericValue(value)
switch string(value.normalized_value_type)
    case "real"
        result = value.normalized_value_real;
    case "integer"
        result = double(value.normalized_value_integer);
    otherwise
        result = NaN;
end
end

function value = emptyMeasurementTable()
value = table( ...
    NaN(0, 1), NaN(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), NaN(0, 1), NaN(0, 1), strings(0, 1), ...
    strings(0, 1), NaN(0, 1), NaN(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=[ ...
    "extractor_feature_id", "canonical_feature_id", "native_name", ...
    "canonical_field", "equivalence_class", "native_value_type", ...
    "native_raw_token", "native_value_real", "native_value_integer", ...
    "native_value_text", "native_unit", "canonical_value_real", ...
    "canonical_value_integer", "canonical_value_text", "canonical_unit", ...
    "transform_key", "operational_variant", "source_locator"]);
end
