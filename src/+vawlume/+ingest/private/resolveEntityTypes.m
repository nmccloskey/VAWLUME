function entityTypes = resolveEntityTypes(conn, irRecords, project)
%RESOLVEENTITYTYPES Resolve IR-declared entity and membership level types.

records = irRecords(ismember(string(irRecords.record_scope), ...
    ["entity", "membership"]), :);
identityRows = unique(records(:, ["native_level", "canonical_level"]), "rows");
nativeLevels = unique(string(identityRows.native_level));
count = numel(nativeLevels);
entityTypes = table( ...
    "entity_type:" + nativeLevels, repmat("create", count, 1), ...
    NaN(count, 1), repmat(project.existing_project_id, count, 1), ...
    nativeLevels, strings(count, 1), NaN(count, 1), ...
    false(count, 1), false(count, 1), strings(count, 1), ...
    VariableNames=["entity_type_key", "action", "existing_entity_type_id", ...
    "project_id", "native_name", "canonical_role", "hierarchy_order", ...
    "is_biological_unit", "is_subject_like", "conflict_message"]);

for index = 1:count
    roles = unique(string(identityRows.canonical_level( ...
        string(identityRows.native_level) == nativeLevels(index))));
    if numel(roles) ~= 1
        entityTypes.action(index) = "conflict";
        entityTypes.conflict_message(index) = ...
            "One native entity type maps to multiple canonical roles in the IR.";
    else
        entityTypes.canonical_role(index) = roles;
    end
end

if project.action == "conflict"
    entityTypes.action(entityTypes.action ~= "conflict") = "skip";
    return
elseif project.action ~= "reuse"
    return
end

rows = fetch(conn, "SELECT entity_type_id, project_id, native_name, " + ...
    "IFNULL(canonical_role, '') AS canonical_role, " + ...
    "hierarchy_order IS NULL AS hierarchy_order_is_null, " + ...
    "is_biological_unit, is_subject_like FROM entity_types");
if isempty(rows)
    return
end
rows = rows(double(rows.project_id) == project.existing_project_id, :);
for index = 1:height(entityTypes)
    if entityTypes.action(index) == "conflict"
        continue
    end
    match = rows(string(rows.native_name) == entityTypes.native_name(index), :);
    if isempty(match)
        continue
    end
    entityTypes.existing_entity_type_id(index) = double(match.entity_type_id(1));
    compatible = ...
        string(match.canonical_role(1)) == entityTypes.canonical_role(index) && ...
        double(match.is_biological_unit(1)) == 0 && ...
        double(match.is_subject_like(1)) == 0 && ...
        double(match.hierarchy_order_is_null(1)) == 1;
    if compatible
        entityTypes.action(index) = "reuse";
    else
        entityTypes.action(index) = "conflict";
        entityTypes.conflict_message(index) = ...
            "Existing native entity type has incompatible canonical metadata.";
    end
end
end
