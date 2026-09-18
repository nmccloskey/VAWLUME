function annotations = edaMemberAnnotations(conn, members, windowBounds, options)
%EDAMEMBERANNOTATIONS One annotation specification per member, measurements only.
%
% ANNOTATIONS = EDAMEMBERANNOTATIONS(CONN, MEMBERS, WINDOWBOUNDS) returns, for
% each member detection of an agreement group, what that extractor actually
% measured: its identity, its native event id, its measured time extent, whatever
% frequency values it reported, and the contract §L extent-source value that says
% which of those exist.
%
% NOTHING IS SYNTHESIZED. A detection with a centre frequency and no band edges
% yields NO band - not a band centred on the value, not a band of some default
% width, not a band inferred from the coefficient of variation, and not a band
% derived from call geometry. Conceptual spec §7.4 and development plan §3.10
% name each of those routes by name because each is individually tempting, and
% MVP success criterion 8 turns on none of them being taken. A fabricated extent
% is indistinguishable from a measured one once it is drawn, and showing what
% each extractor actually reported is the image's entire purpose.
%
% The pilot set makes this concrete rather than hypothetical. DeepSqueak and
% MUPET register `vocalization_frequency_min` and `vocalization_frequency_max`,
% so their annotations are rectangles. USVSEG registers neither - it reports
% `meanfreq`, `maxfreq` and `cvfreq` - so its annotation is a time extent with
% two markers, and it must stay that way. The temptation to make the gallery
% uniform by giving USVSEG a band is exactly the defect the tripwire forbids.
%
% EXTENTS ARE RESOLVED BY EQUIVALENCE CLASS, NEVER BY EXTRACTOR NAME. The path is
% event_measurements -> extractor_features.extractor_feature_id ->
% extractor_features.equivalence_class. No extractor is named anywhere in this
% file, so an extractor added later works without a code change (boundary 8).
%
% IT IS NOT `v_event_measurements_long`. That view exposes
% `canonical_features.canonical_name` and has NO equivalence_class column, so
% resolving through it would mean joining by canonical name - reintroducing
% exactly the join the matching specification forbids through
% `forbid_canonical_name_only_join`, and the one the repository has already
% learned the cost of.
%
% CLIPPING IS RECORDED PER DETECTION. A call whose extent runs past the snippet
% window is a different thing from a short call, and in the image they look the
% same: both stop at the edge. The flag says which.

arguments
    conn
    members table
    windowBounds (1,2) double
    options.CanonicalOnly (1,1) logical = true
end

annotations = emptyAnnotations();
if height(members) == 0
    return
end

measurements = readFrequencyMeasurements(conn, members.detection_id, options);

for index = 1:height(members)
    member = members(index, :);
    values = valuesFor(measurements, member.detection_id);
    source = extentSource(values);
    [clipped, outside] = clipping(member, windowBounds);
    annotations(end + 1, :) = { ...
        member.detection_id, member.agreement_group_id, ...
        member.extractor_key, member.extractor_name, ...
        member.native_event_id, ...
        member.start_time_s, member.end_time_s, ...
        member.end_time_s - member.start_time_s, ...
        source, hasBand(values), ...
        values.frequency_min_hz, values.frequency_max_hz, ...
        values.frequency_center_hz, values.frequency_peak_hz, ...
        renderingFor(source), clipped, outside, ...
        values.unit}; %#ok<AGROW>
end
annotations = sortrows(annotations, ["extractor_key", "detection_id"]);
end

% ----------------------------------------------------------- measurements ---

function value = readFrequencyMeasurements(conn, detectionIds, options)
%READFREQUENCYMEASUREMENTS The four frequency classes, by equivalence class.
%
% CANONICAL VALUES ONLY, for the reason Part 11 recorded as EXP-027: across the
% pilot extractors the native units differ from the canonical ones - every
% frequency is native kHz against canonical Hz - so a native fallback would place
% a 60 kHz marker at 60 Hz on the axis. A measurement with no canonical value is
% treated as absent, which for drawing purposes it is.
value = emptyMeasurements();
ids = unique(double(detectionIds(:)));
if isempty(ids)
    return
end
classes = frequencyClasses();
valueExpression = "em.canonical_value_real";
if ~options.CanonicalOnly
    valueExpression = "IFNULL(em.canonical_value_real, em.native_value_real)";
end

rows = fetch(conn, "SELECT em.detection_id, " + ...
    "IFNULL(xf.equivalence_class,'') AS equivalence_class, " + ...
    valueExpression + " AS value, " + ...
    "IFNULL(em.canonical_unit,'') AS unit " + ...
    "FROM event_measurements em " + ...
    "JOIN extractor_features xf " + ...
    "ON xf.extractor_feature_id=em.extractor_feature_id " + ...
    "WHERE em.detection_id IN (" + strjoin(string(ids'), ",") + ") " + ...
    "AND xf.equivalence_class IN (" + ...
    strjoin(arrayfun(@edaSqlText, classes), ", ") + ")");
if isempty(rows) || height(rows) == 0
    return
end
value = table(double(rows.detection_id), ...
    edaPresentText(rows.equivalence_class), double(rows.value), ...
    edaPresentText(rows.unit), ...
    VariableNames=["detection_id", "equivalence_class", "value", "unit"]);
value = value(isfinite(value.value), :);
end

function value = frequencyClasses()
%FREQUENCYCLASSES The four classes an annotation can draw from.
%
% `vocalization_frequency_cv` is deliberately absent. It is a coefficient of
% variation, not a frequency, and the only thing it could contribute to a picture
% is a synthesized band width - which is named in conceptual spec §7.4 as a route
% that must not be taken. Reading it here at all would put the temptation one
% line away.
value = ["vocalization_frequency_min", "vocalization_frequency_max", ...
    "vocalization_frequency_center", "vocalization_peak_frequency"];
end

function value = valuesFor(measurements, detectionId)
value = struct(frequency_min_hz=NaN, frequency_max_hz=NaN, ...
    frequency_center_hz=NaN, frequency_peak_hz=NaN, unit="");
if height(measurements) == 0
    return
end
selected = measurements(measurements.detection_id == detectionId, :);
if height(selected) == 0
    return
end
value.frequency_min_hz = pick(selected, "vocalization_frequency_min");
value.frequency_max_hz = pick(selected, "vocalization_frequency_max");
value.frequency_center_hz = pick(selected, "vocalization_frequency_center");
value.frequency_peak_hz = pick(selected, "vocalization_peak_frequency");
units = unique(selected.unit(strlength(selected.unit) > 0));
if ~isempty(units)
    value.unit = units(1);
end
end

function value = pick(selected, equivalenceClass)
value = NaN;
matched = selected.value(selected.equivalence_class == equivalenceClass);
if ~isempty(matched)
    value = matched(1);
end
end

% --------------------------------------------------------- the vocabulary ---

function value = extentSource(values)
%EXTENTSOURCE Contract §L's value for what this detection actually measured.
%
% BAND EDGES REQUIRE BOTH. One edge without the other is not a band: an upper
% bound alone says nothing about where the call starts in frequency, and drawing
% a rectangle from it to the axis floor would be a synthesized extent with an
% invented lower edge. A lone edge is reported as the marker it is.
hasMin = isfinite(values.frequency_min_hz);
hasMax = isfinite(values.frequency_max_hz);
hasCenter = isfinite(values.frequency_center_hz);
hasPeak = isfinite(values.frequency_peak_hz);

if hasMin && hasMax
    value = "band_edges";
    return
end
if hasCenter && hasPeak
    value = "center_and_peak";
    return
end
if hasCenter
    value = "center_only";
    return
end
if hasPeak
    value = "peak_only";
    return
end
% A lone band edge falls here: measured, reportable as a marker, and not a band.
if hasMin || hasMax
    value = "peak_only";
    return
end
value = "unavailable";
end

function value = hasBand(values)
%HASBAND The single predicate a renderer may draw a rectangle from.
%
% Both edges measured, and nothing else. Exposed as its own column so Part 13
% never has to interpret the vocabulary string, and so a test can assert the
% ABSENCE of a band rather than the presence of a tag - a tag can be right while
% the geometry beside it is wrong.
value = isfinite(values.frequency_min_hz) && isfinite(values.frequency_max_hz);
end

function value = renderingFor(source)
switch source
    case "band_edges"
        value = "rectangle from measured band edges";
    case "center_and_peak"
        value = "time extent with two measured frequency markers";
    case {"center_only", "peak_only"}
        value = "time extent with one measured frequency marker";
    otherwise
        value = "time extent only, spanning the displayed frequency axis";
end
end

% ------------------------------------------------------------------ clipping ---

function [clipped, outside] = clipping(member, windowBounds)
%CLIPPING Whether this detection runs past the snippet window, and by how much.
%
% A clipped annotation and a short call are the same picture - both stop at the
% edge - so the difference has to be recorded rather than left to the image.
before = max(windowBounds(1) - member.start_time_s, 0);
after = max(member.end_time_s - windowBounds(2), 0);
outside = before + after;
clipped = outside > 0;
end

% -------------------------------------------------------------- plumbing ---

function value = emptyMeasurements()
value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["detection_id", "equivalence_class", "value", "unit"]);
end

function value = emptyAnnotations()
value = table(zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    false(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), false(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["detection_id", "agreement_group_id", "extractor_key", ...
    "extractor_name", "native_event_id", "start_time_s", "end_time_s", ...
    "duration_s", "frequency_extent_source", "has_measured_band", ...
    "frequency_min_hz", "frequency_max_hz", "frequency_center_hz", ...
    "frequency_peak_hz", "rendering", "is_clipped_by_window", ...
    "outside_window_s", "frequency_unit"]);
end
