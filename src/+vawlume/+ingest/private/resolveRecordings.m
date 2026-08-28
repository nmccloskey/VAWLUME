function recordings = resolveRecordings(conn, irRecords, project, sources)
%RESOLVERECORDINGS Resolve explicit source-recording rows through source identity.

records = irRecords(string(irRecords.record_scope) == "source_recording", :);
records = sortrows(records, "record_key");
count = height(records);
recordings = table( ...
    string(records.record_key), repmat("create", count, 1), NaN(count, 1), ...
    repmat(project.existing_project_id, count, 1), ...
    string(records.source_key), NaN(count, 1), strings(count, 1), ...
    strings(count, 1), strings(count, 1), ...
    VariableNames=["record_key", "action", "existing_recording_id", ...
    "project_id", "source_key", "source_file_id", ...
    "native_recording_id", "checksum_sha256", "conflict_message"]);

for index = 1:count
    sourceIndex = find(sources.source_key == recordings.source_key(index), 1);
    recordings.source_file_id(index) = ...
        sources.existing_source_file_id(sourceIndex);
    recordings.checksum_sha256(index) = sources.checksum_sha256(sourceIndex);
    recordings.native_recording_id(index) = explicitNativeId(records(index, :));
    if sources.action(sourceIndex) == "conflict" || ...
            sources.action(sourceIndex) == "skip" || project.action == "conflict"
        recordings.action(index) = "skip";
    end
end

if isempty(recordings) || project.action ~= "reuse"
    return
end

rows = fetch(conn, "SELECT recording_id, project_id, source_file_id, " + ...
    nullableTextSql("native_recording_id") + ", " + ...
    nullableTextSql("checksum_sha256") + " FROM recordings");
if isempty(rows)
    return
end
rows = normalizeNullableText(rows, ...
    ["native_recording_id", "checksum_sha256"]);
rows = rows(double(rows.project_id) == project.existing_project_id, :);
for index = 1:height(recordings)
    if recordings.action(index) ~= "create" || ...
            isnan(recordings.source_file_id(index))
        continue
    end
    match = rows(double(rows.source_file_id) == ...
        recordings.source_file_id(index), :);
    if isempty(match)
        continue
    end
    recordings.existing_recording_id(index) = double(match.recording_id(1));
    compatible = ...
        compatibleOptional(string(match.native_recording_id(1)), ...
        recordings.native_recording_id(index)) && ...
        compatibleOptional(string(match.checksum_sha256(1)), ...
        recordings.checksum_sha256(index));
    if compatible
        recordings.action(index) = "reuse";
    else
        recordings.action(index) = "conflict";
        recordings.conflict_message(index) = ...
            "Existing source recording has incompatible native identity or checksum.";
    end
end
end

function value = explicitNativeId(record)
value = "";
if string(record.mapping_rule) ~= "source.relative_path"
    value = string(record.native_identifier);
end
end

function value = compatibleOptional(stored, proposed)
value = strlength(stored) == 0 || strlength(proposed) == 0 || stored == proposed;
end

function value = nullableTextSql(column)
value = "CASE WHEN " + column + " IS NULL OR length(" + column + ...
    ") = 0 THEN '<empty-text>' ELSE " + column + " END AS " + column + ...
    ", " + column + " IS NULL OR length(" + column + ") = 0 AS " + ...
    column + "_is_empty";
end

function rows = normalizeNullableText(rows, columns)
for column = columns
    maskName = column + "_is_empty";
    rows.(column)(double(rows.(maskName)) == 1) = "";
end
end
