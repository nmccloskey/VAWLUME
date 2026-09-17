function selection = edaResolveAnalyses(conn, analysisRefs)
%EDARESOLVEANALYSES Resolve the matching analyses the surface will span.
%
% Accepts a string array of matching run_keys, a struct array of references, or
% a scalar struct carrying only project_key, which selects every completed
% cross_extractor_matching analysis in that project. The diagnostic battery is a
% full-dataset activity, so the project-wide form is the ordinary one.
%
% For each analysis this resolves the ordered run pair, both extractor keys, the
% linked matching specification's identity, and the sign-normalization decision
% that puts every signed difference on one axis.
%
% The ordered run pair comes from analysis_run_extraction_inputs.input_role.
% That is the only place run direction is recorded: candidate_pairs orders its
% two detection columns by detection id to satisfy a schema CHECK, and those
% columns carry no run meaning at all.
%
% An analysis that cannot supply direction or specification identity is never
% included with an assumed direction. How it is refused depends on how it was
% asked for:
%
%   named explicitly   raise, because the caller asked for that analysis
%   swept by project   exclude it, and report it in SELECTION.excluded with a
%                      reason, because one legacy or hand-seeded row should not
%                      abort a whole-dataset diagnostic
%
% The swept form is not silent about what it dropped. A dataset diagnostic that
% quietly analysed four of six analyses would misstate its own coverage.

[references, strict] = normalizeReferences(conn, analysisRefs);
analyses = emptyAnalyses();
excluded = emptyExcluded();
for index = 1:numel(references)
    [row, refusal] = resolveOne(conn, references{index}, strict);
    if isempty(refusal)
        analyses(end + 1, :) = row; %#ok<AGROW>
    else
        excluded(end + 1, :) = refusal; %#ok<AGROW>
    end
end
if height(analyses) == 0
    error("vawlume:eda:NoUsableAnalyses", ...
        "No selected matching analysis could supply run direction and " + ...
        "specification identity. %d were excluded.", height(excluded));
end
if numel(unique(analyses.analysis_run_id)) ~= height(analyses)
    error("vawlume:eda:AnalysisDuplicated", ...
        "The same matching analysis was selected more than once.");
end
analyses = sortrows(analyses, ["project_key", "matching_run_key"]);
selection = struct(analyses=analyses, excluded=excluded);
end

function [references, strict] = normalizeReferences(conn, analysisRefs)
strict = true;
if isstring(analysisRefs) || ischar(analysisRefs) || iscellstr(analysisRefs)
    keys = string(analysisRefs);
    keys = keys(:);
    if isempty(keys)
        error("vawlume:eda:SelectorInvalid", ...
            "At least one matching analysis must be selected.");
    end
    references = cell(numel(keys), 1);
    for index = 1:numel(keys)
        references{index} = struct(run_key=keys(index));
    end
    return
end
if ~isstruct(analysisRefs)
    error("vawlume:eda:SelectorInvalid", ...
        "analysisRefs must be run_key text or a struct array of references.");
end
if isscalar(analysisRefs) && isfield(analysisRefs, "project_key") && ...
        ~isfield(analysisRefs, "run_key") && ...
        ~isfield(analysisRefs, "analysis_run_id")
    references = projectWide(conn, analysisRefs.project_key);
    strict = false;
    return
end
references = num2cell(analysisRefs(:));
if isempty(references)
    error("vawlume:eda:SelectorInvalid", ...
        "At least one matching analysis must be selected.");
end
end

function references = projectWide(conn, projectKey)
rows = fetch(conn, "SELECT ar.analysis_run_id FROM analysis_runs ar " + ...
    "JOIN projects p ON p.project_id=ar.project_id " + ...
    "WHERE p.project_key=" + edaSqlText(projectKey) + ...
    " AND ar.run_type='cross_extractor_matching' AND ar.status='completed' " + ...
    "ORDER BY ar.run_key");
if isempty(rows) || height(rows) == 0
    error("vawlume:eda:NoMatchingAnalyses", ...
        "Project '%s' has no completed cross_extractor_matching analysis. " + ...
        "The surface reads analyses that already exist; it does not run " + ...
        "matching.", string(projectKey));
end
references = cell(height(rows), 1);
for index = 1:height(rows)
    references{index} = struct( ...
        analysis_run_id=double(rows.analysis_run_id(index)));
end
end

function [row, refusal] = resolveOne(conn, reference, strict)
refusal = {};
analysis = locateAnalysis(conn, reference);

[pair, reason, detail] = resolveRunPair(conn, analysis.analysis_run_id);
if strlength(reason) > 0
    [row, refusal] = refuse(analysis, strict, reason, detail);
    return
end
[specification, reason, detail] = resolveSpecification(conn, analysis);
if strlength(reason) > 0
    [row, refusal] = refuse(analysis, strict, reason, detail);
    return
end

% Ascending extractor_key is the workflow's one ordering rule. Every signed
% difference downstream is higher-key minus lower-key, whatever order the
% caller happened to pass to vawlume.matching.compare.
if pair.run_a_extractor_key < pair.run_b_extractor_key
    lower = "run_a";
    higher = "run_b";
    signNormalization = "as_stored";
elseif pair.run_a_extractor_key > pair.run_b_extractor_key
    lower = "run_b";
    higher = "run_a";
    signNormalization = "negated";
else
    [row, refusal] = refuse(analysis, strict, "same_extractor_key", ...
        "Both sides resolve to extractor_key '" + ...
        pair.run_a_extractor_key + "'.");
    return
end

row = {analysis.analysis_run_id, analysis.project_id, analysis.project_key, ...
    analysis.run_key, NaN, ...
    pair.run_a_extraction_run_id, pair.run_b_extraction_run_id, ...
    pair.run_a_extractor_key, pair.run_b_extractor_key, ...
    pair.(lower + "_extractor_key"), pair.(higher + "_extractor_key"), ...
    pair.(lower + "_extractor_key") + "|" + pair.(higher + "_extractor_key"), ...
    pair.(lower + "_extraction_run_id"), pair.(higher + "_extraction_run_id"), ...
    signNormalization, specification.profile_key, specification.version_label, ...
    specification.checksum_sha256, ...
    edaConfigurationId(specification.version_label), 0};
end

function [row, refusal] = refuse(analysis, strict, reason, detail)
if strict
    error("vawlume:eda:AnalysisUnusable", ...
        "Matching analysis '%s' cannot be read by the candidate-metric " + ...
        "surface (%s): %s", analysis.run_key, reason, detail);
end
row = {};
refusal = {analysis.analysis_run_id, analysis.project_key, ...
    analysis.run_key, reason, detail};
end

function analysis = locateAnalysis(conn, reference)
if ~isstruct(reference) || ~isscalar(reference)
    error("vawlume:eda:SelectorInvalid", ...
        "Each analysis reference must be a scalar struct.");
end
hasId = isfield(reference, "analysis_run_id");
hasKey = isfield(reference, "run_key");
if hasId == hasKey
    error("vawlume:eda:SelectorInvalid", ...
        "Each reference must contain exactly one of analysis_run_id or run_key.");
end
if hasId
    value = reference.analysis_run_id;
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value <= 0 || fix(value) ~= value
        error("vawlume:eda:SelectorInvalid", ...
            "analysis_run_id must be a positive scalar integer.");
    end
    predicate = "ar.analysis_run_id=" + string(double(value));
else
    predicate = "ar.run_key=" + edaSqlText(reference.run_key);
    if isfield(reference, "project_key")
        predicate = predicate + " AND p.project_key=" + ...
            edaSqlText(reference.project_key);
    end
end
rows = fetch(conn, "SELECT ar.analysis_run_id, ar.project_id, p.project_key, " + ...
    "ar.run_key, ar.run_type, ar.status FROM analysis_runs ar " + ...
    "JOIN projects p ON p.project_id=ar.project_id WHERE " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:eda:AnalysisNotFound", ...
        "No analysis run matches the supplied reference.");
end
if height(rows) ~= 1
    error("vawlume:eda:AnalysisAmbiguous", ...
        "A reference matched %d analysis runs; supply project_key or " + ...
        "analysis_run_id.", height(rows));
end
runType = edaPresentText(rows.run_type(1));
if runType ~= "cross_extractor_matching"
    error("vawlume:eda:AnalysisNotMatching", ...
        "The candidate-metric surface requires a cross_extractor_matching " + ...
        "analysis; '%s' has run_type '%s'.", ...
        edaPresentText(rows.run_key(1)), runType);
end
status = edaPresentText(rows.status(1));
if status ~= "completed"
    error("vawlume:eda:AnalysisIncomplete", ...
        "Matching analysis '%s' has status '%s'; the surface reads " + ...
        "completed analyses only.", edaPresentText(rows.run_key(1)), status);
end
analysis = struct( ...
    analysis_run_id=double(rows.analysis_run_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    project_key=edaPresentText(rows.project_key(1)), ...
    run_key=edaPresentText(rows.run_key(1)));
end

function [pair, reason, detail] = resolveRunPair(conn, analysisRunId)
pair = struct();
reason = "";
detail = "";
rows = fetch(conn, "SELECT ari.input_role, ari.extraction_run_id, " + ...
    "e.extractor_key FROM analysis_run_extraction_inputs ari " + ...
    "JOIN extraction_runs er ON er.extraction_run_id=ari.extraction_run_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE ari.analysis_run_id=" + string(analysisRunId) + ...
    " ORDER BY ari.input_role");
if isempty(rows) || height(rows) == 0
    roles = strings(0, 1);
else
    roles = edaPresentText(rows.input_role);
end
if ~isequal(sort(roles), ["run_a"; "run_b"])
    reason = "inputs_not_run_a_run_b";
    detail = "Declared input roles are [" + strjoin(roles', ", ") + ...
        "]; run direction is not recoverable without exactly one run_a " + ...
        "and one run_b.";
    return
end
for role = ["run_a", "run_b"]
    index = find(roles == role, 1);
    pair.(role + "_extraction_run_id") = double(rows.extraction_run_id(index));
    pair.(role + "_extractor_key") = edaPresentText(rows.extractor_key(index));
end
end

function [specification, reason, detail] = resolveSpecification(conn, analysis)
specification = struct();
reason = "";
detail = "";
rows = fetch(conn, "SELECT cp.profile_key, cpv.version_label, " + ...
    "IFNULL(cpv.checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE arp.analysis_run_id=" + string(analysis.analysis_run_id) + ...
    " AND arp.assignment_role='matching_spec'");
if isempty(rows) || height(rows) ~= 1
    reason = "matching_spec_not_linked";
    detail = "The analysis links " + string(height(rows)) + ...
        " matching_spec profile versions; exactly one identifies the " + ...
        "configuration that produced its candidates.";
    return
end
specification = struct( ...
    profile_key=edaPresentText(rows.profile_key(1)), ...
    version_label=edaPresentText(rows.version_label(1)), ...
    checksum_sha256=edaPresentText(rows.checksum_sha256(1)));
end

function value = emptyAnalyses()
value = table(zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), ...
    VariableNames=["analysis_run_id", "project_id", "project_key", ...
    "matching_run_key", "recording_id", ...
    "run_a_extraction_run_id", "run_b_extraction_run_id", ...
    "run_a_extractor_key", "run_b_extractor_key", ...
    "extractor_key_a", "extractor_key_b", "extractor_pair_key", ...
    "lower_extraction_run_id", "higher_extraction_run_id", ...
    "sign_normalization", "matching_profile_key", "matching_profile_version", ...
    "matching_checksum_sha256", "configuration_id", "candidate_count"]);
end

function value = emptyExcluded()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), VariableNames=["analysis_run_id", "project_key", ...
    "matching_run_key", "reason", "detail"]);
end
