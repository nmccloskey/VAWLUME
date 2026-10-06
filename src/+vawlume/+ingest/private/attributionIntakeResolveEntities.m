function [entityIds, unresolved] = attributionIntakeResolveEntities(conn, projectId, participantIds, claims)
%ATTRIBUTIONINTAKERESOLVEENTITIES Resolve declared caller entities against a participant set.
%
% The declaration is the profile's; this is where it meets the database. A
% declared entity that does not exist, or is not among PARTICIPANTIDS, is a
% surfaced problem and never a new entity. Every offending label is returned so
% the caller can name them all at once rather than one per re-run.
unresolved = strings(0, 1);
entityIds = NaN(height(claims), 1);
for index = 1:height(claims)
    nativeId = string(claims.entity_native_id(index));
    rows = fetch(conn, "SELECT entity_id FROM experimental_entities " + ...
        "WHERE project_id=" + string(projectId) + " AND native_id=" + ...
        sqlText(nativeId));
    if isempty(rows) || height(rows) == 0
        unresolved(end+1, 1) = string(claims.caller_label(index)) + ...
            " (declared as entity " + nativeId + ", which does not exist)"; %#ok<AGROW>
        continue
    end
    candidateId = double(rows.entity_id(1));
    if ~ismember(candidateId, participantIds)
        unresolved(end+1, 1) = string(claims.caller_label(index)) + ...
            " (entity " + nativeId + " is not a participant of this run)"; %#ok<AGROW>
        continue
    end
    entityIds(index) = candidateId;
end
unresolved = unique(unresolved, "stable");
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
