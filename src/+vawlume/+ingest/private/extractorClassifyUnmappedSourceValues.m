function [detections, conflicts] = extractorClassifyUnmappedSourceValues(conn, scope, detections, eventNoun)
%EXTRACTORCLASSIFYUNMAPPEDSOURCEVALUES Classify preserved unclaimed evidence.

arguments
    conn
    scope (1,1) struct
    detections (:,1) cell
    eventNoun (1,1) string = "event"
end

conflicts = strings(0,1);
for index = 1:numel(detections)
    detection = detections{index};
    if ~isfield(detection, "unmapped_values") || detection.action ~= "reuse"
        continue
    end
    stored = fetch(conn, "SELECT IFNULL(source_artifact_id,-1) AS source_artifact_id, " + ...
        "native_field_name, IFNULL(raw_value_text,'') AS raw_value_text, " + ...
        "IFNULL(native_unit,'') AS native_unit, IFNULL(source_locator,'') AS source_locator, " + ...
        "IFNULL(reason_unmapped,'') AS reason_unmapped, " + ...
        "IFNULL(mapping_profile_version_id,-1) AS mapping_profile_version_id " + ...
        "FROM unmapped_source_values WHERE detection_id=" + string(detection.detection_id));
    planned = detection.unmapped_values;
    for rowIndex = 1:height(planned)
        key = string(planned.native_field_name(rowIndex));
        locator = string(planned.source_locator(rowIndex));
        match = table();
        if ~isempty(stored) && height(stored) > 0
            match = stored(string(stored.native_field_name) == key & ...
                presentText(stored.source_locator) == locator,:);
        end
        prefix = capitalized(eventNoun) + " '" + detection.native_event_id + ...
            "' unmapped field '" + key + "': ";
        if height(match) ~= 1
            planned.action(rowIndex) = "conflict";
            if height(match) == 0, detail = "the stored value is missing."; ...
            else, detail = "more than one stored value uses this source identity."; end
            conflicts(end+1,1) = prefix + detail; %#ok<AGROW>
        elseif compatible(match, planned(rowIndex,:), scope)
            planned.action(rowIndex) = "reuse";
        else
            planned.action(rowIndex) = "conflict";
            conflicts(end+1,1) = prefix + "stored value or provenance differs."; %#ok<AGROW>
        end
    end
    if height(stored) ~= height(planned)
        conflicts(end+1,1) = capitalized(eventNoun) + " '" + detection.native_event_id + ...
            "': stored unmapped-source value count differs from the export."; %#ok<AGROW>
    end
    detection.unmapped_values = planned;
    detections{index} = detection;
end
end

function tf = compatible(stored, planned, scope)
tf = presentText(stored.raw_value_text(1)) == string(planned.raw_value_text(1)) && ...
    presentText(stored.native_unit(1)) == string(planned.native_unit(1)) && ...
    presentText(stored.reason_unmapped(1)) == string(planned.reason_unmapped(1)) && ...
    double(stored.source_artifact_id(1)) == optionalId(scope.source_artifact_id) && ...
    double(stored.mapping_profile_version_id(1)) == optionalId(scope.mapping_profile_version_id);
end

function value = optionalId(value), if isnan(value), value=-1; end, end
function text = presentText(value), text=string(value); text(ismissing(text))=""; end
function text = capitalized(noun)
text=string(noun); if strlength(text)>0, c=char(text); c(1)=upper(c(1)); text=string(c); end
end
