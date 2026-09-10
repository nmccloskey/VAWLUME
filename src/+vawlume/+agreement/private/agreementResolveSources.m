function sources = agreementResolveSources(conn, recording, references, specification)
%AGREEMENTRESOLVESOURCES Resolve and validate each source pairwise analysis.
%
% One row per source analysis, in canonical order: ascending sorted extractor
% pair label, then source run_key. Order of the caller's references carries no
% meaning, so it is normalized here and the normalized order is what identity
% and reporting use.
%
% Each source is validated on its own terms. Set-level rules such as complete
% pair coverage belong to agreementValidateCoverage.

normalized = normalizeReferences(references);
rows = emptySources();
for index = 1:numel(normalized)
    rows(end + 1, :) = resolveOne(conn, recording, normalized(index), ...
        specification); %#ok<AGROW>
end
if height(rows) == 0
    error("vawlume:agreement:SourcesInvalid", ...
        "At least one source pairwise analysis is required.");
end
if height(rows) < specification.minimum_source_analyses
    error("vawlume:agreement:SourcesInvalid", ...
        "The agreement policy requires at least %d source analyses; %d were supplied.", ...
        specification.minimum_source_analyses, height(rows));
end
[distinct, ~, grouping] = unique(rows.analysis_run_id);
repeated = distinct(accumarray(grouping, 1) > 1);
if ~isempty(repeated)
    error("vawlume:agreement:DuplicateSourceAnalysis", ...
        "Source analysis %s was supplied more than once.", ...
        strjoin(string(repeated(:)'), ", "));
end
sources = sortrows(rows, ["pair_label", "run_key"]);
sources.source_ordinal = (1:height(sources))';
end

function normalized = normalizeReferences(references)
if isnumeric(references)
    values = references(:);
    normalized = struct("mode", {}, "value", {});
    for index = 1:numel(values)
        normalized(end + 1) = struct(mode="id", ...
            value=scalarPositiveInteger(values(index), "source analysis id")); %#ok<AGROW>
    end
    return
end
if isstring(references) || ischar(references) || iscellstr(references)
    values = string(references);
    values = values(:);
    normalized = struct("mode", {}, "value", {});
    for index = 1:numel(values)
        key = strtrim(values(index));
        if ismissing(key) || strlength(key) == 0
            error("vawlume:agreement:SourcesInvalid", ...
                "A source analysis run_key is empty.");
        end
        normalized(end + 1) = struct(mode="key", value=key); %#ok<AGROW>
    end
    return
end
if isstruct(references)
    normalized = struct("mode", {}, "value", {});
    for index = 1:numel(references)
        normalized(end + 1) = normalizeStruct(references(index)); %#ok<AGROW>
    end
    return
end
if iscell(references)
    normalized = struct("mode", {}, "value", {});
    for index = 1:numel(references)
        entry = normalizeReferences(references{index});
        if numel(entry) ~= 1
            error("vawlume:agreement:SourcesInvalid", ...
                "Each cell entry must reference exactly one source analysis.");
        end
        normalized(end + 1) = entry; %#ok<AGROW>
    end
    return
end
error("vawlume:agreement:SourcesInvalid", ...
    "sources must be analysis_run_id values, run_key values, or reference structs.");
end

function value = normalizeStruct(reference)
hasId = isfield(reference, "analysis_run_id");
hasKey = isfield(reference, "run_key");
if hasId == hasKey
    error("vawlume:agreement:SourcesInvalid", ...
        "A source struct must contain exactly one of analysis_run_id and run_key.");
end
if hasId
    value = struct(mode="id", value=scalarPositiveInteger( ...
        reference.analysis_run_id, "analysis_run_id"));
    return
end
key = strtrim(string(reference.run_key));
if ~isscalar(key) || ismissing(key) || strlength(key) == 0
    error("vawlume:agreement:SourcesInvalid", ...
        "A source struct run_key must be nonempty scalar text.");
end
value = struct(mode="key", value=key);
end

function row = resolveOne(conn, recording, reference, specification)
if reference.mode == "id"
    predicate = "ar.analysis_run_id=" + string(reference.value);
else
    predicate = "ar.run_key=" + sqlText(reference.value);
end
rows = fetch(conn, "SELECT ar.analysis_run_id, ar.project_id, ar.run_key, " + ...
    "ar.run_type, ar.status FROM analysis_runs ar WHERE " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:agreement:SourceAnalysisNotFound", ...
        "Source analysis '%s' does not exist.", string(reference.value));
end
if height(rows) ~= 1
    error("vawlume:agreement:SourceAnalysisAmbiguous", ...
        "Source analysis '%s' resolved to %d analyses; exactly one is required.", ...
        string(reference.value), height(rows));
end
analysisRunId = double(rows.analysis_run_id(1));
runKey = presentText(rows.run_key(1));
if double(rows.project_id(1)) ~= recording.project_id
    error("vawlume:agreement:SourceProjectMismatch", ...
        "Source analysis '%s' belongs to project %d, not project %d.", ...
        runKey, double(rows.project_id(1)), recording.project_id);
end
if presentText(rows.run_type(1)) ~= specification.required_run_type
    error("vawlume:agreement:SourceRunTypeInvalid", ...
        "Source analysis '%s' has run_type '%s'; the agreement policy requires '%s'.", ...
        runKey, presentText(rows.run_type(1)), specification.required_run_type);
end
if presentText(rows.status(1)) ~= specification.required_status
    error("vawlume:agreement:SourceAnalysisIncomplete", ...
        "Source analysis '%s' has status '%s'; the agreement policy requires '%s'.", ...
        runKey, presentText(rows.status(1)), specification.required_status);
end

pair = resolveRunPair(conn, recording, analysisRunId, runKey);
assertRecordingScope(conn, recording, analysisRunId, runKey);
specificationVersionId = resolveMatchingSpec(conn, analysisRunId, runKey);

pairLabel = strjoin(sort([pair.a.extractor_name, pair.b.extractor_name]), "|");
row = {analysisRunId, runKey, pairLabel, ...
    pair.a.extraction_run_id, pair.a.run_key, pair.a.extractor_id, ...
    pair.a.extractor_name, pair.b.extraction_run_id, pair.b.run_key, ...
    pair.b.extractor_id, pair.b.extractor_name, specificationVersionId, 0};
end

function pair = resolveRunPair(conn, recording, analysisRunId, runKey)
rows = fetch(conn, "SELECT arei.input_role, er.extraction_run_id, er.run_key, " + ...
    "ev.extractor_id, e.extractor_name " + ...
    "FROM analysis_run_extraction_inputs arei " + ...
    "JOIN extraction_runs er ON er.extraction_run_id=arei.extraction_run_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE arei.analysis_run_id=" + string(analysisRunId) + ...
    " ORDER BY arei.input_role");
if height(rows) ~= 2
    error("vawlume:agreement:SourceAnalysisIncomplete", ...
        "Source analysis '%s' declares %d extraction inputs; a pairwise analysis declares 2.", ...
        runKey, height(rows));
end
side = struct();
for index = 1:2
    entry = struct( ...
        extraction_run_id=double(rows.extraction_run_id(index)), ...
        run_key=presentText(rows.run_key(index)), ...
        extractor_id=double(rows.extractor_id(index)), ...
        extractor_name=presentText(rows.extractor_name(index)));
    if index == 1
        side.a = entry;
    else
        side.b = entry;
    end
end
if side.a.extractor_id == side.b.extractor_id
    error("vawlume:agreement:SameExtractorPair", ...
        "Source analysis '%s' compares two runs of extractor '%s'.", ...
        runKey, side.a.extractor_name);
end
for role = ["a", "b"]
    declared = fetch(conn, "SELECT COUNT(*) AS n FROM extraction_run_inputs " + ...
        "WHERE extraction_run_id=" + string(side.(role).extraction_run_id) + ...
        " AND recording_id=" + string(recording.recording_id));
    if double(declared.n(1)) == 0
        error("vawlume:agreement:SourceRecordingMismatch", ...
            "Source analysis '%s' uses extraction run '%s', which does not analyze recording %d.", ...
            runKey, side.(role).run_key, recording.recording_id);
    end
end
pair = side;
end

function assertRecordingScope(conn, recording, analysisRunId, runKey)
%ASSERTRECORDINGSCOPE Every stored row of the source analysis is this recording.
%
% A pairwise analysis stores its recording on its candidate and group rows
% rather than on the analysis, and an analysis may legitimately have none of
% either. Absence is therefore not an error; disagreement is.
for tableName = ["candidate_pairs", "match_groups"]
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName + ...
        " WHERE analysis_run_id=" + string(analysisRunId) + ...
        " AND recording_id<>" + string(recording.recording_id));
    if double(rows.n(1)) > 0
        error("vawlume:agreement:SourceRecordingMismatch", ...
            "Source analysis '%s' holds %d %s rows for another recording.", ...
            runKey, double(rows.n(1)), tableName);
    end
end
end

function value = resolveMatchingSpec(conn, analysisRunId, runKey)
rows = fetch(conn, "SELECT profile_version_id FROM analysis_run_profiles " + ...
    "WHERE analysis_run_id=" + string(analysisRunId) + ...
    " AND assignment_role='matching_spec'");
if height(rows) ~= 1
    error("vawlume:agreement:SourceSpecificationMissing", ...
        "Source analysis '%s' links %d matching specifications; exactly one is required.", ...
        runKey, height(rows));
end
value = double(rows.profile_version_id(1));
end

function rows = emptySources()
rows = table(zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["analysis_run_id", "run_key", "pair_label", ...
    "run_a_extraction_run_id", "run_a_key", "run_a_extractor_id", ...
    "run_a_extractor_name", "run_b_extraction_run_id", "run_b_key", ...
    "run_b_extractor_id", "run_b_extractor_name", ...
    "matching_specification_version_id", "source_ordinal"]);
end

function value = scalarPositiveInteger(raw, label)
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || raw <= 0 || ...
        raw ~= floor(raw)
    error("vawlume:agreement:InvalidIdentifier", ...
        "%s must be a positive integer.", label);
end
value = double(raw);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end
