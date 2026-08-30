function [detections, conflicts] = extractorClassifyDetections(conn, scope, routed, eventNoun)
%EXTRACTORCLASSIFYDETECTIONS Classify a routed event population read-only.
%
% Detection identity is the schema's UNIQUE(extraction_run_id, recording_id,
% source_artifact_id, native_event_id). Row order is never identity: the same
% export reordered produces the same population, and the source row survives
% only as provenance in the detection's notes and in each measurement's
% source_locator.
%
% Existing scientific rows are never updated in place. Identical evidence is
% reused; changed evidence under one run identity is an explicit conflict that a
% future migration workflow must resolve deliberately.
%
% SCOPE carries the resolved run/recording/artifact identity:
%   extraction_run_id  - NaN when the run does not exist yet
%   recording_id
%   source_artifact_id - NaN when the artifact will be created by this apply
%
% This core owns detections and their measurements, which every extractor
% populates identically. Evidence that only some extractors produce - review
% state, class labels - is layered by the extractor-specific resolver on top of
% the dispositions returned here.

arguments
    conn
    scope (1,1) struct
    routed (1,1) struct
    eventNoun (1,1) string = "event"
end

detections = {};
conflicts = strings(0, 1);
existing = existingDetections(conn, scope);

for index = 1:numel(routed.rows)
    row = routed.rows{index};
    [detection, rowConflicts] = classifyDetection(conn, scope, row, existing, eventNoun);
    detections{index, 1} = detection; %#ok<AGROW>
    conflicts = [conflicts; rowConflicts]; %#ok<AGROW>
end
end

function [detection, conflicts] = classifyDetection(conn, scope, row, existing, eventNoun)
conflicts = strings(0, 1);
detection = struct();
detection.source_row = row.source_row;
detection.native_event_id = row.native_event_id;
detection.start_time_s = row.start_time_s;
detection.end_time_s = row.end_time_s;
detection.duration_s = row.duration_s;
detection.detection_score = row.detection_score;
detection.source_artifact_id = scope.source_artifact_id;
detection.action = "create";
detection.detection_id = NaN;
detection.measurements = measurementDispositions(row.measurements);

match = matchExisting(existing, row.native_event_id);
if isempty(match)
    return
end

detection.detection_id = double(match.detection_id(1));
[compatible, message] = detectionIsCompatible(match, row);
if ~compatible
    detection.action = "conflict";
    conflicts(end + 1, 1) = capitalized(eventNoun) + " '" + row.native_event_id + ...
        "': " + message;
    return
end

detection.action = "reuse";
[detection, conflicts] = classifyMeasurements(conn, detection, conflicts, eventNoun);
end

function [detection, conflicts] = classifyMeasurements(conn, detection, conflicts, eventNoun)
%CLASSIFYMEASUREMENTS Compare every planned measurement against stored evidence.
%
% Presence is not enough. A stored row that exists but disagrees, is duplicated,
% or is absent is a conflict, because "the detection is already there" says
% nothing about whether the same evidence produced it.
stored = existingMeasurements(conn, detection.detection_id);
for index = 1:height(detection.measurements)
    featureId = detection.measurements.extractor_feature_id(index);
    match = stored(stored.extractor_feature_id == featureId, :);
    nativeName = string(detection.measurements.native_name(index));
    prefix = capitalized(eventNoun) + " '" + detection.native_event_id + ...
        "' measurement '" + nativeName + "': ";

    if isempty(match) || height(match) == 0
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = prefix + "the stored measurement is missing."; %#ok<AGROW>
        continue
    end
    if height(match) > 1
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = prefix + ...
            "more than one stored measurement uses this feature identity."; %#ok<AGROW>
        continue
    end
    [compatible, message] = measurementIsCompatible(match, ...
        detection.measurements(index, :), detection.source_artifact_id);
    if compatible
        detection.measurements.action(index) = "reuse";
    else
        detection.measurements.action(index) = "conflict";
        conflicts(end + 1, 1) = prefix + message; %#ok<AGROW>
    end
end
end

function [compatible, message] = detectionIsCompatible(match, row)
compatible = true;
message = "";
tolerance = 1e-9;

if ~valuesAgree(double(match.start_time_s(1)), row.start_time_s, tolerance) || ...
        ~valuesAgree(double(match.end_time_s(1)), row.end_time_s, tolerance)
    compatible = false;
    message = "existing timing differs from the imported evidence.";
    return
end
if ~valuesAgree(nullableReal(match.detection_score(1)), row.detection_score, tolerance)
    compatible = false;
    message = "existing detection score differs from the imported evidence.";
end
end

function [compatible, message] = measurementIsCompatible(match, planned, sourceArtifactId)
compatible = true;
message = "";
tolerance = 1e-9;

storedType = presentText(match.native_value_type(1));
if storedType ~= presentText(planned.native_value_type(1))
    compatible = false;
    message = "native value type changed from '" + storedType + "' to '" + ...
        presentText(planned.native_value_type(1)) + "'.";
    return
end
if presentText(match.native_raw_token(1)) ~= presentText(planned.native_raw_token(1))
    compatible = false;
    message = "native raw token changed.";
    return
end
if ~valuesAgree(nullableReal(match.native_value_real(1)), planned.native_value_real(1), tolerance) || ...
        ~valuesAgree(nullableReal(match.native_value_integer(1)), planned.native_value_integer(1), tolerance) || ...
        ~valuesAgree(nullableReal(match.canonical_value_real(1)), planned.canonical_value_real(1), tolerance) || ...
        ~valuesAgree(nullableReal(match.canonical_value_integer(1)), planned.canonical_value_integer(1), tolerance) || ...
        presentText(match.native_value_text(1)) ~= presentText(planned.native_value_text(1)) || ...
        presentText(match.canonical_value_text(1)) ~= presentText(planned.canonical_value_text(1))
    compatible = false;
    message = "stored value differs from the imported value.";
    return
end

if double(match.source_artifact_id(1)) ~= sourceArtifactId || ...
        double(match.canonical_feature_id(1)) ~= double(planned.canonical_feature_id(1)) || ...
        presentText(match.native_unit(1)) ~= presentText(planned.native_unit(1)) || ...
        presentText(match.canonical_unit(1)) ~= presentText(planned.canonical_unit(1)) || ...
        presentText(match.transform_key(1)) ~= presentText(planned.transform_key(1)) || ...
        presentText(match.operational_variant(1)) ~= presentText(planned.operational_variant(1)) || ...
        presentText(match.source_locator(1)) ~= presentText(planned.source_locator(1))
    compatible = false;
    message = "stored feature or provenance fields differ from the imported evidence.";
end
end

function tf = valuesAgree(stored, planned, tolerance)
if isnan(stored) && isnan(planned)
    tf = true;
    return
end
if isnan(stored) || isnan(planned)
    tf = false;
    return
end
tf = abs(stored - planned) <= tolerance;
end

function value = nullableReal(stored)
%NULLABLEREAL Map the SQL NULL sentinel back to NaN.
%
% MATLAB's SQLite fetch errors on NULL columns, so nullable reals are selected
% through IFNULL with an out-of-range sentinel. Converting it back here keeps
% "absent" distinct from any real measured value.
value = double(stored);
if value >= 1e307
    value = NaN;
end
end

function dispositions = measurementDispositions(measurements)
dispositions = measurements;
dispositions.action = repmat("create", height(measurements), 1);
end

function rows = existingDetections(conn, scope)
% A run that does not exist yet can have no detections, so the lookup is skipped
% rather than issued against an unresolved identifier.
if isnan(scope.extraction_run_id)
    rows = table();
    return
end
rows = fetch(conn, ...
    "SELECT detection_id, IFNULL(native_event_id, '') AS native_event_id, " + ...
    "start_time_s, end_time_s, IFNULL(detection_score, 1e308) AS detection_score " + ...
    "FROM detections WHERE extraction_run_id = " + string(scope.extraction_run_id) + ...
    " AND recording_id = " + string(scope.recording_id) + ...
    " AND IFNULL(source_artifact_id, -1) = " + string(artifactIdOrMissing(scope.source_artifact_id)));
end

function value = artifactIdOrMissing(artifactId)
if isnan(artifactId)
    value = -1;
else
    value = artifactId;
end
end

function match = matchExisting(existing, nativeEventId)
match = [];
if isempty(existing) || height(existing) == 0 || strlength(nativeEventId) == 0
    return
end
matches = presentText(existing.native_event_id) == nativeEventId;
if any(matches)
    match = existing(find(matches, 1), :);
end
end

function rows = existingMeasurements(conn, detectionId)
rows = fetch(conn, ...
    "SELECT extractor_feature_id, IFNULL(canonical_feature_id, -1) AS canonical_feature_id, " + ...
    "IFNULL(source_artifact_id, -1) AS source_artifact_id, native_value_type, " + ...
    "IFNULL(native_raw_token, '') AS native_raw_token, " + ...
    "IFNULL(native_value_real, 1e308) AS native_value_real, " + ...
    "IFNULL(native_value_integer, 1e308) AS native_value_integer, " + ...
    "IFNULL(native_value_text, '') AS native_value_text, " + ...
    "IFNULL(canonical_value_real, 1e308) AS canonical_value_real, " + ...
    "IFNULL(canonical_value_integer, 1e308) AS canonical_value_integer, " + ...
    "IFNULL(canonical_value_text, '') AS canonical_value_text, " + ...
    "IFNULL(native_unit, '') AS native_unit, " + ...
    "IFNULL(canonical_unit, '') AS canonical_unit, " + ...
    "IFNULL(transform_key, '') AS transform_key, " + ...
    "IFNULL(operational_variant, '') AS operational_variant, " + ...
    "IFNULL(source_locator, '') AS source_locator " + ...
    "FROM event_measurements WHERE detection_id = " + string(detectionId));
end

function text = capitalized(noun)
%CAPITALIZED Start a diagnostic sentence with the extractor's own event noun.
text = string(noun);
if strlength(text) > 0
    characters = char(text);
    characters(1) = upper(characters(1));
    text = string(characters);
end
end

function text = presentText(value)
%PRESENTTEXT Normalize a fetched text value to a comparable string.
%
% MATLAB's SQLite fetch returns <missing> rather than "" for an empty text
% value, even one produced by IFNULL, and every comparison against a missing
% string is false. Normalizing keeps "absent" and "empty" comparable.
text = string(value);
text(ismissing(text)) = "";
end
