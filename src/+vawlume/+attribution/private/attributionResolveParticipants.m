function [entityIds, entities, links] = attributionResolveParticipants( ...
        conn, recording, runSpec)
%ATTRIBUTIONRESOLVEPARTICIPANTS Resolve subjects through recording links.

allEntities = fetch(conn, "SELECT DISTINCT e.entity_id, " + ...
    "IFNULL(e.native_id,'') AS native_id, et.native_name AS entity_type " + ...
    "FROM recording_entity_links rel JOIN experimental_entities e " + ...
    "ON e.entity_id=rel.entity_id JOIN entity_types et " + ...
    "ON et.entity_type_id=e.entity_type_id " + ...
    "WHERE rel.recording_id=" + string(recording.recording_id) + ...
    " ORDER BY e.entity_id");
available = zeros(0, 1);
if ~isempty(allEntities)
    available = double(allEntities.entity_id);
end
if isfield(runSpec, "participating_entity_ids")
    requested = identifierVector(runSpec.participating_entity_ids);
    if isempty(requested)
        error("vawlume:attribution:ParticipantSetEmpty", ...
            "An attribution run requires at least one participating entity.");
    end
    if any(~ismember(requested, available))
        error("vawlume:attribution:EntityNotInRecording", ...
            "Every participating entity must be linked to recording %d.", ...
            recording.recording_id);
    end
    entityIds = requested;
else
    entityIds = available;
end
if isempty(entityIds)
    error("vawlume:attribution:ParticipantSetEmpty", ...
        "Recording %d has no linked participating entities.", ...
        recording.recording_id);
end

entities = allEntities(ismember(double(allEntities.entity_id), entityIds), :);
entities.entity_id = double(entities.entity_id);
entities.native_id = presentText(entities.native_id);
entities.entity_type = presentText(entities.entity_type);

links = fetch(conn, "SELECT recording_entity_link_id, entity_id, link_type, " + ...
    "IFNULL(role_label,'') AS role_label, " + ...
    "IFNULL(start_time_s,-1.7976931348623157e+308) AS start_time_s, " + ...
    "IFNULL(end_time_s,-1.7976931348623157e+308) AS end_time_s " + ...
    "FROM recording_entity_links WHERE recording_id=" + ...
    string(recording.recording_id) + " AND entity_id IN (" + ...
    idList(entityIds) + ") ORDER BY entity_id, recording_entity_link_id");
links.recording_entity_link_id = double(links.recording_entity_link_id);
links.entity_id = double(links.entity_id);
links.link_type = presentText(links.link_type);
links.role_label = presentText(links.role_label);
links.start_time_s = absentRealToNaN(links.start_time_s);
links.end_time_s = absentRealToNaN(links.end_time_s);
end

function value = identifierVector(raw)
if ~isnumeric(raw) || ~isvector(raw) || any(~isfinite(raw)) || ...
        any(raw < 1) || any(fix(raw) ~= raw)
    error("vawlume:attribution:RunSpecInvalid", ...
        "participating_entity_ids must be positive integer identifiers.");
end
value = unique(double(raw(:)));
end

function value = idList(ids)
value = strjoin(string(ids'), ",");
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function value = absentRealToNaN(raw)
value = double(raw);
value(value < -1e307) = NaN;
end
