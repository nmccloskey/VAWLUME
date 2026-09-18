function dataset = resolveDataset(conn, selector, options)
%RESOLVEDATASET Fix and validate the recordings and runs a probe will execute over.
%
% DATASET = vawlume.eda.RESOLVEDATASET(CONN, SELECTOR) resolves the project, the
% participating recordings, and for each recording the extraction runs - one per
% extractor - that a screening probe will compare, and validates all of it before
% anything is executed.
%
% SELECTOR is a struct:
%   struct(project_key="my-project")                 every usable recording
%   struct(project_key="...", recording_ids=[1 2])   an explicit recording set
%   struct(project_key="...", extraction_run_keys=[...])
%                                                    restrict to named runs
%
% Name-value options:
%   MinimumExtractorsPerRecording   default 2; a recording below it cannot form
%                                   even one extractor pair
%   RequireUniformExtractorSet      default true; every recording must carry the
%                                   same extractor set
%
% EVERYTHING IS VALIDATED UP FRONT, deliberately. The matcher and the agreement
% composer are per recording, so a probe is a loop, and a defect discovered at
% configuration 6 of 8, recording 14 of 20, leaves a half-executed probe whose
% partial state a human then has to interpret. Every failure this function can
% detect without executing anything - a recording with fewer than two runs, two
% runs from one extractor, a run in another project, a recording with no
% detections - is reported here instead.
%
% THE PAIR LIST IS DERIVED, NEVER SUPPLIED. The agreement composer requires the
% complete unordered pairwise set for its N runs and refuses an incomplete one -
% after the matching analyses have already been written. Deriving the pair list
% from the resolved runs makes that refusal impossible to reach by accident.
%
% Pairs are ordered by ASCENDING extractor_key, with the lower key as run_a. That
% is the workflow's one ordering rule, and it is the same rule the candidate
% metric surface normalizes signed differences to. An inconsistent ordering
% produces bimodal signed distributions that look like findings.
%
% This function reads and validates. It writes nothing.

arguments
    conn
    selector (1,1) struct
    options.MinimumExtractorsPerRecording (1,1) double {mustBePositive} = 2
    options.RequireUniformExtractorSet (1,1) logical = true
end

project = resolveProject(conn, selector);
runs = resolveRuns(conn, project, selector);
recordings = resolveRecordings(conn, project, runs, selector);
[recordings, runs, excluded] = applyMinimum(recordings, runs, options);
assertDistinctExtractors(runs);
extractorSet = assertUniformity(recordings, runs, options);
pairs = buildPairs(runs);

dataset = struct( ...
    status="resolved", ...
    project_id=project.project_id, ...
    project_key=project.project_key, ...
    recordings=recordings, ...
    runs=runs, ...
    pairs=pairs, ...
    excluded_recordings=excluded, ...
    recording_count=height(recordings), ...
    extractor_keys=extractorSet, ...
    extractor_count=numel(extractorSet), ...
    pairs_per_recording=numel(extractorSet) * (numel(extractorSet) - 1) / 2, ...
    pair_ordering="ascending extractor_key; run_a is the lower key", ...
    signed_difference_direction= ...
        "higher extractor_key value minus lower extractor_key value", ...
    detection_count=sum(runs.detection_count));
end

% ---------------------------------------------------------------- project ---

function project = resolveProject(conn, selector)
if ~isfield(selector, "project_key")
    error("vawlume:eda:DatasetSelectorInvalid", ...
        "The dataset selector must name a project_key.");
end
rows = fetch(conn, "SELECT project_id, project_key FROM projects " + ...
    "WHERE project_key=" + edaSqlText(selector.project_key));
if isempty(rows) || height(rows) ~= 1
    error("vawlume:eda:ProjectNotFound", ...
        "No project matches project_key '%s'.", string(selector.project_key));
end
project = struct(project_id=double(rows.project_id(1)), ...
    project_key=edaPresentText(rows.project_key(1)));
end

% ------------------------------------------------------------------- runs ---

function runs = resolveRuns(conn, project, selector)
%RESOLVERUNS One row per (recording, extraction run) the probe may use.
%
% Scoped to the project in the query rather than filtered afterwards, so a run
% belonging to another project is never a candidate in the first place. The
% detection count comes along because a recording with no detections is a
% defect worth naming before a probe spends analyses discovering it.
predicate = "er.project_id=" + string(project.project_id);
if isfield(selector, "extraction_run_keys") && ...
        ~isempty(selector.extraction_run_keys)
    keys = string(selector.extraction_run_keys(:))';
    predicate = predicate + " AND er.run_key IN (" + ...
        strjoin(arrayfun(@edaSqlText, keys), ", ") + ")";
end
if isfield(selector, "recording_ids") && ~isempty(selector.recording_ids)
    ids = double(selector.recording_ids(:))';
    predicate = predicate + " AND eri.recording_id IN (" + ...
        strjoin(string(ids), ",") + ")";
end

rows = fetch(conn, "SELECT eri.recording_id, er.extraction_run_id, " + ...
    "er.run_key, e.extractor_id, e.extractor_key, e.extractor_name, " + ...
    "(SELECT COUNT(*) FROM detections d WHERE " + ...
    "d.extraction_run_id=er.extraction_run_id AND " + ...
    "d.recording_id=eri.recording_id) AS detection_count " + ...
    "FROM extraction_run_inputs eri " + ...
    "JOIN extraction_runs er ON er.extraction_run_id=eri.extraction_run_id " + ...
    "JOIN extractor_versions ev " + ...
    "ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE " + predicate + " ORDER BY eri.recording_id, e.extractor_key");
if isempty(rows) || height(rows) == 0
    error("vawlume:eda:DatasetEmpty", ...
        "Project '%s' has no extraction run covering any selected recording.", ...
        project.project_key);
end

runs = table(double(rows.recording_id), double(rows.extraction_run_id), ...
    edaPresentText(rows.run_key), double(rows.extractor_id), ...
    edaPresentText(rows.extractor_key), edaPresentText(rows.extractor_name), ...
    double(rows.detection_count), ...
    VariableNames=["recording_id", "extraction_run_id", "run_key", ...
    "extractor_id", "extractor_key", "extractor_name", "detection_count"]);
runs = sortrows(runs, ["recording_id", "extractor_key"]);

if isfield(selector, "extraction_run_keys") && ...
        ~isempty(selector.extraction_run_keys)
    requested = unique(string(selector.extraction_run_keys(:)));
    missingKeys = setdiff(requested, unique(runs.run_key));
    if ~isempty(missingKeys)
        error("vawlume:eda:ExtractionRunNotInProject", ...
            "Extraction run(s) %s do not belong to project '%s' or cover no " + ...
            "selected recording. A run from another project is refused here " + ...
            "rather than failing inside a probe.", ...
            strjoin(missingKeys', ", "), project.project_key);
    end
end
end

% ------------------------------------------------------------ recordings ---

function recordings = resolveRecordings(conn, project, runs, selector)
ids = unique(runs.recording_id);
rows = fetch(conn, "SELECT r.recording_id, " + ...
    "IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
    "IFNULL(sf.relative_path,'') AS source_relative_path " + ...
    "FROM recordings r JOIN source_files sf " + ...
    "ON sf.source_file_id=r.source_file_id " + ...
    "WHERE r.project_id=" + string(project.project_id) + ...
    " AND r.recording_id IN (" + strjoin(string(ids'), ",") + ") " + ...
    "ORDER BY r.recording_id");
recordings = table(double(rows.recording_id), ...
    edaPresentText(rows.native_recording_id), ...
    edaPresentText(rows.source_relative_path), ...
    VariableNames=["recording_id", "native_recording_id", ...
    "source_relative_path"]);

if isfield(selector, "recording_ids") && ~isempty(selector.recording_ids)
    requested = unique(double(selector.recording_ids(:)));
    missingIds = setdiff(requested, recordings.recording_id);
    if ~isempty(missingIds)
        error("vawlume:eda:RecordingNotInProject", ...
            "Recording(s) %s are not in project '%s' or carry no extraction " + ...
            "run.", strjoin(string(missingIds'), ", "), project.project_key);
    end
end
end

function [recordings, runs, excluded] = applyMinimum(recordings, runs, options)
%APPLYMINIMUM Drop recordings that cannot form a pair, and say which.
%
% Excluding is reported rather than silent: a probe that quietly analysed six of
% twenty recordings would misstate its own coverage, and the count is what
% Part 8's balance check rests on.
excluded = emptyExcluded();
keep = true(height(recordings), 1);
for index = 1:height(recordings)
    id = recordings.recording_id(index);
    selected = runs(runs.recording_id == id, :);
    if height(selected) < options.MinimumExtractorsPerRecording
        keep(index) = false;
        excluded(end + 1, :) = {id, recordings.native_recording_id(index), ...
            "fewer_than_" + string(options.MinimumExtractorsPerRecording) + ...
            "_extraction_runs", "Carries " + string(height(selected)) + ...
            " run(s)."}; %#ok<AGROW>
        continue
    end
    if any(selected.detection_count == 0)
        empty = selected.extractor_key(selected.detection_count == 0);
        keep(index) = false;
        excluded(end + 1, :) = {id, recordings.native_recording_id(index), ...
            "extraction_run_without_detections", ...
            "Run(s) for " + strjoin(empty', ", ") + " hold no detection for " + ...
            "this recording."}; %#ok<AGROW>
    end
end
recordings = recordings(keep, :);
runs = runs(ismember(runs.recording_id, recordings.recording_id), :);
if height(recordings) == 0
    error("vawlume:eda:DatasetEmpty", ...
        "No recording survived validation; %d were excluded. A probe over no " + ...
        "recording would produce an empty design rather than an error later.", ...
        height(excluded));
end
end

function assertDistinctExtractors(runs)
%ASSERTDISTINCTEXTRACTORS One run per extractor per recording.
%
% The agreement composer requires it, because it is what makes an unordered
% extractor pair name exactly one comparison. Catching it here costs a query;
% catching it there costs a probe's worth of written matching analyses first.
ids = unique(runs.recording_id);
for index = 1:numel(ids)
    selected = runs(runs.recording_id == ids(index), :);
    [distinct, ~, grouping] = unique(selected.extractor_key);
    occurrences = accumarray(grouping, 1);
    repeated = distinct(occurrences > 1);
    if ~isempty(repeated)
        error("vawlume:eda:RepeatedExtractorInRecording", ...
            "Recording %d carries more than one extraction run for " + ...
            "extractor(s) %s. One run per extractor is what makes an " + ...
            "unordered extractor pair name exactly one comparison; select " + ...
            "explicit extraction_run_keys to disambiguate.", ...
            ids(index), strjoin(repeated', ", "));
    end
end
end

function extractorSet = assertUniformity(recordings, runs, options)
sets = strings(height(recordings), 1);
for index = 1:height(recordings)
    selected = runs(runs.recording_id == recordings.recording_id(index), :);
    sets(index) = strjoin(sort(selected.extractor_key)', "|");
end
distinct = unique(sets);
if options.RequireUniformExtractorSet && numel(distinct) > 1
    error("vawlume:eda:ExtractorSetNotUniform", ...
        "Recordings carry different extractor sets (%s). A screen whose " + ...
        "recordings compare different extractor pairs produces responses " + ...
        "that are not commensurable; select a uniform subset or set " + ...
        "RequireUniformExtractorSet to false deliberately.", ...
        strjoin("'" + distinct' + "'", ", "));
end
extractorSet = unique(runs.extractor_key)';
end

function pairs = buildPairs(runs)
%BUILDPAIRS Every unordered extractor pair per recording, in ascending key order.
pairs = emptyPairs();
ids = unique(runs.recording_id);
for index = 1:numel(ids)
    selected = sortrows(runs(runs.recording_id == ids(index), :), ...
        "extractor_key");
    for left = 1:(height(selected) - 1)
        for right = (left + 1):height(selected)
            lower = selected(left, :);
            higher = selected(right, :);
            pairs(end + 1, :) = {ids(index), ...
                lower.extractor_key, higher.extractor_key, ...
                lower.extractor_key + "|" + higher.extractor_key, ...
                lower.run_key, higher.run_key, ...
                lower.extraction_run_id, higher.extraction_run_id}; %#ok<AGROW>
        end
    end
end
end

% -------------------------------------------------------------- plumbing ---

function value = emptyPairs()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["recording_id", "run_a_extractor_key", ...
    "run_b_extractor_key", "extractor_pair_key", "run_a_key", "run_b_key", ...
    "run_a_extraction_run_id", "run_b_extraction_run_id"]);
end

function value = emptyExcluded()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["recording_id", "native_recording_id", "reason", "detail"]);
end
