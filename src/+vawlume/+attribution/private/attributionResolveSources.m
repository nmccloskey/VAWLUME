function sources = attributionResolveSources(conn, recording, runSpec)
%ATTRIBUTIONRESOLVESOURCES Resolve direct run inputs and enforce their scope.

if ~isfield(runSpec, "sources") || ~isstruct(runSpec.sources) || ...
        ~isscalar(runSpec.sources)
    error("vawlume:attribution:RunSpecInvalid", ...
        "runSpec.sources must be a scalar struct naming direct inputs.");
end
spec = runSpec.sources;
sources = struct( ...
    source_file_ids=sourceIds(spec, "source_file_ids"), ...
    artifact_ids=sourceIds(spec, "artifact_ids"), ...
    external_stream_ids=sourceIds(spec, "external_stream_ids"), ...
    analysis_run_ids=sourceIds(spec, "analysis_run_ids"));
if all(structfun(@isempty, sources))
    error("vawlume:attribution:SourceSetEmpty", ...
        "An attribution run requires at least one direct source artifact, stream, file, or analysis.");
end

validateProjectRows(conn, "source_files", "source_file_id", ...
    sources.source_file_ids, recording);
validateProjectRows(conn, "artifacts", "artifact_id", ...
    sources.artifact_ids, recording);
validateProjectRows(conn, "analysis_runs", "analysis_run_id", ...
    sources.analysis_run_ids, recording);
if ~isempty(sources.external_stream_ids)
    rows = fetch(conn, "SELECT external_stream_id, project_id, " + ...
        "IFNULL(recording_id,-1) AS recording_id FROM external_streams " + ...
        "WHERE external_stream_id IN (" + idList(sources.external_stream_ids) + ")");
    if isempty(rows) || height(rows) ~= numel(sources.external_stream_ids)
        error("vawlume:attribution:SourceNotFound", ...
            "One or more external_stream_ids do not exist.");
    end
    streamRecording = double(rows.recording_id);
    wrongRecording = streamRecording >= 0 & ...
        streamRecording ~= recording.recording_id;
    if any(double(rows.project_id) ~= recording.project_id) || any(wrongRecording)
        error("vawlume:attribution:SourceOutsideRecording", ...
            "Every external stream must belong to the run's project and recording scope.");
    end
end
end

function ids = sourceIds(spec, field)
ids = zeros(0, 1);
if ~isfield(spec, field)
    return
end
raw = spec.(field);
if ~isnumeric(raw) || ~isvector(raw) || any(~isfinite(raw)) || ...
        any(raw < 1) || any(fix(raw) ~= raw)
    error("vawlume:attribution:RunSpecInvalid", ...
        "sources.%s must be positive integer identifiers.", field);
end
ids = unique(double(raw(:)));
end

function validateProjectRows(conn, tableName, idColumn, ids, recording)
if isempty(ids)
    return
end
rows = fetch(conn, "SELECT " + idColumn + ", project_id FROM " + ...
    tableName + " WHERE " + idColumn + " IN (" + idList(ids) + ")");
if isempty(rows) || height(rows) ~= numel(ids)
    error("vawlume:attribution:SourceNotFound", ...
        "One or more %s values do not exist.", idColumn);
end
if any(double(rows.project_id) ~= recording.project_id)
    error("vawlume:attribution:SourceOutsideRecording", ...
        "Every source must belong to project '%s'.", recording.project_key);
end
end

function value = idList(ids)
value = strjoin(string(ids'), ",");
end
