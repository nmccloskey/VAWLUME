function recording = attributionResolveRecording(conn, recordingRef)
%ATTRIBUTIONRESOLVERECORDING Resolve one established recording.

hasId = isfield(recordingRef, "recording_id");
hasPortable = isfield(recordingRef, "project_key") && ...
    isfield(recordingRef, "source_relative_path");
if hasId == hasPortable
    error("vawlume:attribution:RecordingRefInvalid", ...
        "recordingRef must contain recording_id, or project_key plus source_relative_path.");
end
if hasId
    id = positiveInteger(recordingRef.recording_id, "recordingRef.recording_id");
    predicate = "r.recording_id=" + string(id);
else
    projectKey = scalarText(recordingRef.project_key, "recordingRef.project_key");
    relativePath = scalarText(recordingRef.source_relative_path, ...
        "recordingRef.source_relative_path");
    predicate = "p.project_key=" + sqlText(projectKey) + ...
        " AND sf.relative_path=" + sqlText(relativePath);
end
rows = fetch(conn, "SELECT r.recording_id, r.project_id, p.project_key, " + ...
    "IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
    "IFNULL(sf.relative_path,'') AS source_relative_path " + ...
    "FROM recordings r JOIN projects p ON p.project_id=r.project_id " + ...
    "JOIN source_files sf ON sf.source_file_id=r.source_file_id " + ...
    "WHERE " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:attribution:RecordingNotFound", ...
        "No established recording matches recordingRef.");
end
if height(rows) ~= 1
    error("vawlume:attribution:RecordingAmbiguous", ...
        "recordingRef matched %d recordings.", height(rows));
end
recording = struct(recording_id=double(rows.recording_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    project_key=presentText(rows.project_key(1)), ...
    native_recording_id=presentText(rows.native_recording_id(1)), ...
    source_relative_path=presentText(rows.source_relative_path(1)));
end

function value = positiveInteger(raw, label)
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || ...
        raw < 1 || fix(raw) ~= raw
    error("vawlume:attribution:RecordingRefInvalid", ...
        "%s must be a positive integer.", label);
end
value = double(raw);
end

function value = scalarText(raw, label)
try
    value = strtrim(string(raw));
catch
    error("vawlume:attribution:RecordingRefInvalid", ...
        "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("vawlume:attribution:RecordingRefInvalid", ...
        "%s must be nonempty scalar text.", label);
end
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function value = sqlText(raw)
value = "'" + replace(string(raw), "'", "''") + "'";
end
