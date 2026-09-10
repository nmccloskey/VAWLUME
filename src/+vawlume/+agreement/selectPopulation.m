function result = selectPopulation(conn, analysisRef, options)
%SELECTPOPULATION Select agreement groups and their native detection members.
%
% RESULT = vawlume.agreement.selectPopulation(CONN, ANALYSISREF) returns every
% persisted group for one completed multi-extractor agreement analysis and the
% native detections belonging to those groups.
%
% ANALYSISREF selects exactly one agreement analysis:
%
%   struct(analysis_run_id=17)
%   struct(run_key="agreement-v1")
%   struct(project_key="project-a", run_key="agreement-v1")
%
% Name-value filters:
%   ExactSupportPattern      exact supported_extractor_pair_pattern
%   MinSupportedPairCount   minimum coarse K
%   ExactSupportedPairCount exact coarse K
%   ExactPossiblePairCount  exact C(N,2)
%   Completeness            "any", "complete", or "incomplete"
%   Cleanliness             "any", "clean", or "not_clean"
%   Multiplicity            "any", "one_per_extractor", or
%                           "multiple_per_extractor"
%   Uniqueness              "any", "extractor_unique", or "corroborated"
%   ExtractorSetKey         exact extractor_set_key
%   RecordingId             optional recording scope
%   EntityId                optional recording-linked entity scope
%
% ExactSupportPattern equality is independent of coarse K. Two components can
% both be 2 of 3 while supporting different extractor pairs; this API only
% merges them when the caller asks for the coarse count.
%
% RESULT.groups contains one row per selected agreement group. RESULT.members
% contains every native detection member of those groups. A split/merge group is
% never collapsed to one event and no consensus timing is invented. EntityId is
% recording-context scope only: it does not assert that the linked entity
% emitted any selected detection.
%
% This function is read-only. Agreement strength is methodological evidence,
% not a calibrated confidence probability or a biological truth label.
%
% SQL NULL is normalized at this read boundary: a singleton's support fraction
% becomes MATLAB NaN, and a NULL text column - native_recording_id for a
% recording whose intake recovered no native identifier - becomes "".

arguments
    conn
    analysisRef (1,1) struct
    options.ExactSupportPattern (1,1) string = ""
    options.MinSupportedPairCount (1,1) double = NaN
    options.ExactSupportedPairCount (1,1) double = NaN
    options.ExactPossiblePairCount (1,1) double = NaN
    options.Completeness (1,1) string {mustBeMember(options.Completeness, ...
        ["any", "complete", "incomplete"])} = "any"
    options.Cleanliness (1,1) string {mustBeMember(options.Cleanliness, ...
        ["any", "clean", "not_clean"])} = "any"
    options.Multiplicity (1,1) string {mustBeMember(options.Multiplicity, ...
        ["any", "one_per_extractor", "multiple_per_extractor"])} = "any"
    options.Uniqueness (1,1) string {mustBeMember(options.Uniqueness, ...
        ["any", "extractor_unique", "corroborated"])} = "any"
    options.ExtractorSetKey (1,1) string = ""
    options.RecordingId (1,1) double = NaN
    options.EntityId (1,1) double = NaN
end

validateOptions(options);
analysis = resolveAnalysis(conn, analysisRef);
predicates = buildPredicates(analysis.analysis_run_id, options);
whereClause = strjoin(predicates, " AND ");

groups = fetch(conn, groupQuery() + " WHERE " + whereClause + ...
    " ORDER BY s.group_key");
groups = normalizeGroups(groups);

if height(groups) == 0
    memberScope = "0";
    groupIds = zeros(0, 1);
else
    groupIds = groups.agreement_group_id;
    memberScope = "m.agreement_group_id IN (" + ...
        strjoin(string(groupIds'), ",") + ")";
end
members = fetch(conn, memberQuery() + " WHERE m.analysis_run_id=" + ...
    string(analysis.analysis_run_id) + " AND " + memberScope + ...
    " ORDER BY m.group_key, m.extractor_key, m.extraction_run_key, " + ...
    "m.native_event_id, m.detection_id");
members = normalizeMembers(members);

result = struct( ...
    status="selected", ...
    analysis=analysis, ...
    filters=filterSummary(options), ...
    groups=groups, ...
    members=members, ...
    agreement_group_ids=groupIds, ...
    detection_ids=members.detection_id, ...
    selected_group_count=height(groups), ...
    selected_member_count=height(members), ...
    identity_note="groups are derived components; members are native detections", ...
    interpretation_note="extractor agreement is evidence, not biological truth");
end

function validateOptions(options)
for field = ["MinSupportedPairCount", "ExactSupportedPairCount", ...
        "ExactPossiblePairCount"]
    value = options.(field);
    if ~isnan(value) && (~isfinite(value) || value < 0 || value ~= fix(value))
        error("vawlume:agreement:PopulationFilterInvalid", ...
            "%s must be NaN or a nonnegative integer.", field);
    end
end
for field = ["RecordingId", "EntityId"]
    value = options.(field);
    if ~isnan(value) && (~isfinite(value) || value <= 0 || value ~= fix(value))
        error("vawlume:agreement:PopulationFilterInvalid", ...
            "%s must be NaN or a positive integer.", field);
    end
end
if ismissing(options.ExactSupportPattern) || ismissing(options.ExtractorSetKey)
    error("vawlume:agreement:PopulationFilterInvalid", ...
        "Text filters must not be missing strings.");
end
if ~isnan(options.MinSupportedPairCount) && ...
        ~isnan(options.ExactSupportedPairCount) && ...
        options.ExactSupportedPairCount < options.MinSupportedPairCount
    error("vawlume:agreement:PopulationFilterConflict", ...
        "ExactSupportedPairCount cannot be below MinSupportedPairCount.");
end
end

function analysis = resolveAnalysis(conn, reference)
hasId = isfield(reference, "analysis_run_id");
hasKey = isfield(reference, "run_key");
if hasId == hasKey
    error("vawlume:agreement:AnalysisRefInvalid", ...
        "analysisRef must contain exactly one of analysis_run_id or run_key.");
end
if hasId
    value = reference.analysis_run_id;
    validateattributes(value, {'numeric'}, ...
        {'scalar', 'finite', 'positive', 'integer'}, mfilename, ...
        'analysis_run_id');
    predicate = "ar.analysis_run_id=" + string(double(value));
else
    predicate = "ar.run_key=" + sqlText(reference.run_key);
    if isfield(reference, "project_key")
        predicate = predicate + " AND p.project_key=" + ...
            sqlText(reference.project_key);
    end
end
rows = fetch(conn, "SELECT ar.analysis_run_id, ar.project_id, ar.run_key, " + ...
    "ar.run_type, ar.status, p.project_key FROM analysis_runs ar " + ...
    "JOIN projects p ON p.project_id=ar.project_id WHERE " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:agreement:AnalysisNotFound", ...
        "No analysis run matches analysisRef.");
end
if height(rows) ~= 1
    error("vawlume:agreement:AnalysisAmbiguous", ...
        "analysisRef matched %d analysis runs; add project_key.", height(rows));
end
if presentText(rows.run_type(1)) ~= "multi_extractor_agreement"
    error("vawlume:agreement:AnalysisTypeInvalid", ...
        "Analysis '%s' has run_type '%s', not multi_extractor_agreement.", ...
        presentText(rows.run_key(1)), presentText(rows.run_type(1)));
end
if presentText(rows.status(1)) ~= "completed"
    error("vawlume:agreement:AnalysisNotCompleted", ...
        "Agreement analysis '%s' has status '%s'; selection requires completed.", ...
        presentText(rows.run_key(1)), presentText(rows.status(1)));
end
analysis = struct( ...
    analysis_run_id=double(rows.analysis_run_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    project_key=presentText(rows.project_key(1)), ...
    run_key=presentText(rows.run_key(1)), ...
    run_type=presentText(rows.run_type(1)), ...
    status=presentText(rows.status(1)));
end

function predicates = buildPredicates(analysisId, options)
predicates = "s.analysis_run_id=" + string(analysisId);
if strlength(options.ExactSupportPattern) > 0
    predicates(end + 1) = "s.supported_extractor_pair_pattern=" + ...
        sqlText(options.ExactSupportPattern);
end
if ~isnan(options.MinSupportedPairCount)
    predicates(end + 1) = "s.supported_extractor_pair_count>=" + ...
        string(options.MinSupportedPairCount);
end
if ~isnan(options.ExactSupportedPairCount)
    predicates(end + 1) = "s.supported_extractor_pair_count=" + ...
        string(options.ExactSupportedPairCount);
end
if ~isnan(options.ExactPossiblePairCount)
    predicates(end + 1) = "s.possible_extractor_pair_count=" + ...
        string(options.ExactPossiblePairCount);
end
if options.Completeness ~= "any"
    predicates(end + 1) = "s.is_extractor_pair_support_complete=" + ...
        string(double(options.Completeness == "complete"));
end
if options.Cleanliness ~= "any"
    predicates(end + 1) = "s.is_unambiguous_one_to_one=" + ...
        string(double(options.Cleanliness == "clean"));
end
if options.Multiplicity ~= "any"
    predicates(end + 1) = "s.is_one_detection_per_extractor=" + ...
        string(double(options.Multiplicity == "one_per_extractor"));
end
if options.Uniqueness ~= "any"
    predicates(end + 1) = "s.is_extractor_unique=" + ...
        string(double(options.Uniqueness == "extractor_unique"));
end
if strlength(options.ExtractorSetKey) > 0
    predicates(end + 1) = "s.extractor_set_key=" + ...
        sqlText(options.ExtractorSetKey);
end
if ~isnan(options.RecordingId)
    predicates(end + 1) = "s.recording_id=" + string(options.RecordingId);
end
if ~isnan(options.EntityId)
    predicates(end + 1) = "EXISTS (SELECT 1 FROM recording_entity_links rel " + ...
        "WHERE rel.recording_id=s.recording_id AND rel.entity_id=" + ...
        string(options.EntityId) + ")";
end
end

function value = groupQuery()
% Text columns are selected through IFNULL because MATLAB's Database Toolbox
% raises "Unexpected NULL" while building the result set, before normalizeText
% could map a NULL to "". native_recording_id in particular is NULL for any
% recording whose intake profile recovered no native identifier.
value = "SELECT s.agreement_group_id, s.analysis_run_id, " + ...
    selectText("s", groupTextColumns()) + ", " + ...
    "s.recording_id, s.member_count, " + ...
    "s.extraction_run_count, s.extractor_count, " + ...
    "s.support_edge_count, s.supported_extractor_pair_count, " + ...
    "s.possible_extractor_pair_count, s.assessed_extractor_pair_count, " + ...
    "IFNULL(s.support_fraction,-1) AS support_fraction, " + ...
    "s.is_extractor_pair_support_complete, " + ...
    "s.is_pairwise_assessment_complete, " + ...
    "s.is_one_detection_per_extractor, s.is_unambiguous_one_to_one, " + ...
    "s.is_singleton, " + ...
    "s.is_extractor_unique FROM v_agreement_group_summary s";
end

function value = memberQuery()
value = "SELECT m.agreement_group_id, m.analysis_run_id, " + ...
    selectText("m", memberTextColumns()) + ", " + ...
    "m.recording_id, m.detection_id, " + ...
    "m.extraction_run_id, m.extractor_id, m.extractor_version_id, " + ...
    "m.start_time_s, m.end_time_s, m.duration_s " + ...
    "FROM v_agreement_group_members m";
end

function value = groupTextColumns()
value = ["agreement_run_key", "native_recording_id", ...
    "group_key", "derivation_method", "extractor_set_key", ...
    "extractor_set_label", "extraction_run_set_key", ...
    "supported_extractor_pair_pattern", "supported_extractor_pair_label", ...
    "unsupported_extractor_pair_pattern", "unsupported_extractor_pair_label", ...
    "pairwise_topology_pattern", "ambiguous_pairwise_topology_pattern"];
end

function value = memberTextColumns()
value = ["agreement_run_key", "native_recording_id", ...
    "group_key", "derivation_method", "member_role", ...
    "extraction_run_key", "extractor_key", "extractor_name", ...
    "extractor_version", "native_event_id", "event_subtype"];
end

function value = selectText(alias, names)
items = "IFNULL(" + alias + "." + names + ",'') AS " + names;
value = strjoin(items, ", ");
end

function rows = normalizeGroups(rows)
rows = normalizeText(rows, groupTextColumns());
rows = normalizeNumbers(rows, ["agreement_group_id", "analysis_run_id", ...
    "recording_id", "member_count", "extraction_run_count", ...
    "extractor_count", "support_edge_count", ...
    "supported_extractor_pair_count", "possible_extractor_pair_count", ...
    "assessed_extractor_pair_count", "support_fraction"]);
rows.support_fraction(rows.support_fraction < 0) = NaN;
for field = ["is_extractor_pair_support_complete", ...
        "is_pairwise_assessment_complete", ...
        "is_one_detection_per_extractor", "is_unambiguous_one_to_one", ...
        "is_singleton", "is_extractor_unique"]
    rows.(field) = logical(rows.(field));
end
end

function rows = normalizeMembers(rows)
rows = normalizeText(rows, memberTextColumns());
rows = normalizeNumbers(rows, ["agreement_group_id", "analysis_run_id", ...
    "recording_id", "detection_id", "extraction_run_id", "extractor_id", ...
    "extractor_version_id", "start_time_s", "end_time_s", "duration_s"]);
end

function rows = normalizeText(rows, names)
for name = names
    rows.(name) = presentText(rows.(name));
end
end

function rows = normalizeNumbers(rows, names)
for name = names
    rows.(name) = double(rows.(name));
end
end

function value = filterSummary(options)
value = struct( ...
    exact_support_pattern=options.ExactSupportPattern, ...
    minimum_supported_pair_count=options.MinSupportedPairCount, ...
    exact_supported_pair_count=options.ExactSupportedPairCount, ...
    exact_possible_pair_count=options.ExactPossiblePairCount, ...
    completeness=options.Completeness, ...
    cleanliness=options.Cleanliness, ...
    multiplicity=options.Multiplicity, ...
    uniqueness=options.Uniqueness, ...
    extractor_set_key=options.ExtractorSetKey, ...
    recording_id=options.RecordingId, ...
    entity_id=options.EntityId);
end

function value = sqlText(raw)
raw = string(raw);
if ~isscalar(raw) || ismissing(raw)
    error("vawlume:agreement:PopulationFilterInvalid", ...
        "SQL text selectors must be present scalar strings.");
end
value = "'" + replace(raw, "'", "''") + "'";
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
