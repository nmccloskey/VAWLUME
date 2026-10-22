function result = compare(conn, leftRunRef, rightRunRef, options)
%COMPARE Report where two attribution runs agree and where they differ, per target.
%
% Status: experimental (usage guide, "Status of public functions").
%
% RESULT = VAWLUME.ATTRIBUTION.COMPARE(CONN, LEFTRUNREF, RIGHTRUNREF) compares
% two stored runs over the same recording and the same event set, target by
% target, and returns deterministic tidy tables (contract 07 D1, D3-D5). Each
% RUNREF is attribution_run_id, or project_key plus run_key.
%
% A COMPARISON IS NOT A COMBINATION. It reports agreement and disagreement and
% produces no merged caller, consensus decision, combined score, "best" run or
% composite agreement score. Disagreement is reported, never collapsed.
%
% READ-ONLY. Each run is read through vawlume.attribution.report. The only other
% reads are each side's registered decision-policy row, to re-read the policy
% file that orients its ranks, and, with Correspondence, the named analysis's
% stored membership rows (read-only SQL, contract 07 D1). Nothing is written,
% recomputed, re-matched or re-decided, and no producer, matching or agreement
% function, or decide is called.
%
% SYNTHETIC AGREEMENT IS CIRCULAR. Two runs agreeing on data this repository
% generated shows that the machinery joins correctly, never that either run is
% right. Agreement is not accuracy on any data without independent ground truth.
%
% Name-value options:
%   LeftPolicy, RightPolicy  which decision set to read for that side: a policy
%                 profile version id, or a struct with policy_profile_key and
%                 optionally policy_version_label. Required when the run carries
%                 decisions under more than one policy version
%   CompareScores false (default). true adds the scores table, and is refused
%                 unless the two runs' scores are on one scale (below)
%   Correspondence  the ONE stored analysis that joins two different event sets
%                 (contract 07 D3): struct(analysis_run_id=...) or
%                 struct(run_key=...) in the runs' project. Its stored rows
%                 are the only join, read through
%                   detections vs detections  match_group_members (a
%                     cross_extractor_matching analysis) or agreement_group_members
%                     (a multi_extractor_agreement analysis, restricted to the
%                     two runs' extractors)
%                   detections vs consensus events  consensus_event_members of
%                     the matching analysis that produced those events
%                   detections vs agreement groups  agreement_group_members
%                   consensus events of two matching analyses (configurations
%                     P and Q)  their shared member detections, through both
%                     analyses' consensus_event_members:
%                     struct(shared_member_detections=true), since the two
%                     analyses are the runs' own target sources (itinerary 7.9)
%                 A unit is one connected component of those rows restricted to
%                 the two runs' targets. Nothing is re-matched and nothing is
%                 forced 1:1; no "latest analysis" is ever assumed
%   RepoRoot      repository root for relative policy URIs; inferred by default
%
% REFUSED BY NAME, BEFORE ANY TABLE IS BUILT:
%   runs of different recordings          vawlume:attribution:ComparisonRecordingMismatch
%   runs over different event sets        vawlume:attribution:CorrespondenceAnalysisRequired
%     (different extractors, detections against consensus events, different
%     configurations) with no Correspondence named
%   a named analysis that is missing, of another project, not complete, of
%     another kind, not built over both runs' event sets, without rows on
%     the recording, or named for one event set; shared member detections
%     between analyses over different extraction runs
%                                         vawlume:attribution:CorrespondenceAnalysisInvalid
%   decisions under several policy versions, none named
%                                         vawlume:attribution:DecisionPolicyRequired
%   a named policy that decided nothing on that run
%                                         vawlume:attribution:DecisionPolicyNotFound
%   CompareScores=true across scales      vawlume:attribution:ScoreNotComparable
%     Scores compare only under the same attribution path, method (which names
%     its version), settings-profile version and recording. Native scores are
%     dB discrepancies comparable within one recording under one settings
%     version; imported and backend scores are on their producers' scales.
%
% RESULT FIELDS
%
%   sides          one row per side: run identity, path, method, settings
%                  version, event set, the decision policy read (id, key,
%                  version, read status, rule key, producible statuses) and the
%                  rank basis
%   correspondence what joined the targets: kind (same_event_set,
%                  matching_membership, agreement_membership,
%                  consensus_membership, shared_member_detections), the analysis
%                  id (NaN for shared members; the key names both), key and type, and a
%                  value note
%   units          one row per unit; unit_id numbers them in order. On one
%                  event set: ordered by event kind, event id and extent basis;
%                  each unit is one event (one_to_one, or unmatched_left /
%                  unmatched_right for an event only one run targets). Across
%                  event sets: ordered by smallest left target id, then
%                  smallest right; event_kind is correspondence_component and
%                  event_id NaN, and the target ids carry identity. Columns,
%                  each a closed vocabulary:
%
%     correspondence_unit    one_to_one, one_to_many, many_to_one, many_to_many,
%                            unmatched_left, unmatched_right
%     left_target_ids, right_target_ids   every stored id (cells), never collapsed
%     top_entity_agreement   same, different, tie_left, tie_right, left_unscored,
%                            right_unscored, both_unscored, orientation_unknown,
%                            not_applicable_unit. Precedence: orientation_unknown,
%                            then both_/left_/right_unscored, then tie_left, then
%                            tie_right. A tie means several candidates share the
%                            top value; none is picked
%     selected_set_relation  equal, disjoint, subset, superset, overlap,
%                            left_empty, right_empty, both_empty,
%                            not_applicable_unit (left relative to right)
%     left_decision_status, right_decision_status   the stored status under the
%                            side's policy, or no_decision; no_counterpart for
%                            the side an unmatched unit lacks;
%                            not_applicable_unit for a side with several
%                            targets in the unit
%     left_declared_<dim>, right_declared_<dim>    used, not_used or unknown for
%                            temporal_alignment, pose_localization,
%                            visual_identity and acoustic. No row is unknown,
%                            never not_used: an imported run declares nothing
%     score_comparability    comparable, or not_comparable:<reason>
%                            (producer_scale, method, settings_profile_version)
%
%   pairs          one row per (left target, right target) inside a unit with
%                  several targets on a side, with the per-target values; and
%                  one row per target of an unmatched unit, its own decision
%                  against no_counterpart (NaN for the missing target). Never
%                  promoted to unit agreement, never a representative target,
%                  and an unmatched target is neither a disagreement nor dropped
%   status_crosstab  every (left status, right status) cell over one_to_one
%                  units, with unit_count and cell_kind, decided in this order:
%                  structural_empty (a status one side's decision rule cannot
%                  produce, such as simultaneous against a native run's
%                  threshold_with_separation; every such cell, whatever the
%                  other side holds); undecided (no_decision on a side);
%                  excluded (excluded on a side: the policy could not be
%                  applied, a statement that nothing was decided); agree;
%                  disagree. The
%                  statuses each side can produce come from its policy's rule key
%   status_counts  unit_count per cell_kind, beside the one_to_one denominator.
%                  Only agree and disagree are agreement or disagreement; the
%                  other three never are. No percentage is offered
%   reasons        per side: each unscored candidate's stored reasons, in order
%                  (unscored_candidate), and each excluded decision's reason
%                  (excluded_decision)
%   windows        per side, every imported or backend window, corresponded or
%                  uncorresponded (none is dropped), with its stored
%                  correspondences' targets
%   claims         per side, every window claim; promoted when its entity is a
%                  candidate on a target its window corresponds to. An
%                  unpromoted claim is never compared as a candidate
%   claim_counts   per side: claims_promoted, claims_not_promoted,
%                  windows_uncorresponded
%   scores         only with CompareScores=true: per one_to_one unit or
%                  within-unit pair and entity, each side's stored score and
%                  semantics, side by side. Across event sets the two targets
%                  are different measured windows of one call
%                  (correspondence.value_note)
%   lineage_note, comparison_note, source
%
% See also VAWLUME.ATTRIBUTION.REPORT, VAWLUME.MATCHING.COMPARE

arguments
    conn
    leftRunRef (1,1) struct
    rightRunRef (1,1) struct
    options.LeftPolicy = []
    options.RightPolicy = []
    options.CompareScores (1,1) logical = false
    options.Correspondence = []
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
leftReport = vawlume.attribution.report(conn, leftRunRef);
rightReport = vawlume.attribution.report(conn, rightRunRef);
assertSameRecording(leftReport, rightReport);
if isempty(options.Correspondence)
    assertSameEventSet(leftReport, rightReport);
    unitList = sameSetUnits(leftReport, rightReport);
    correspondence = struct(kind="same_event_set", analysis_run_id=NaN, ...
        analysis_run_key="", analysis_run_type="", value_note="");
else
    [analysis, components] = attributionCorrespondenceUnits(conn, leftReport, ...
        rightReport, options.Correspondence);
    unitList = componentUnits(components);
    correspondence = struct(kind=analysis.kind, analysis_run_id=analysis.analysis_run_id, ...
        analysis_run_key=analysis.run_key, analysis_run_type=analysis.run_type, ...
        value_note="Targets in two event sets are different measured windows of " + ...
        "the same call where a stored analysis joins them; even a comparable score " + ...
        "pair was computed over different windows.");
end
left = sideOf(conn, leftReport, options.LeftPolicy, repoRoot, "left");
right = sideOf(conn, rightReport, options.RightPolicy, repoRoot, "right");
comparability = scoreComparability(leftReport, rightReport);
if options.CompareScores && comparability ~= "comparable"
    error("vawlume:attribution:ScoreNotComparable", ...
        "Runs %d and %d are %s: scores compare only under one attribution path, " + ...
        "method, settings-profile version and recording. Native scores are " + ...
        "comparable within one recording under one settings-profile version; " + ...
        "imported and backend scores are on their producers' scales. Compare " + ...
        "ranks, selected sets and statuses instead (CompareScores=false).", ...
        leftReport.attribution_run_id, rightReport.attribution_run_id, comparability);
end

[units, pairs] = unitTable(left, right, unitList, comparability);
result = struct( ...
    sides=[sideRow(left); sideRow(right)], ...
    correspondence=correspondence, ...
    units=units, ...
    pairs=pairs, ...
    status_crosstab=crosstab(units, left, right), ...
    status_counts=table(), ...
    reasons=[reasonRows(left); reasonRows(right)], ...
    windows=[windowRows(left); windowRows(right)], ...
    claims=[claimRows(left); claimRows(right)], ...
    claim_counts=table(), ...
    scores=emptyScores(), ...
    lineage_note=lineageNote(), ...
    comparison_note=comparisonNote(), ...
    source="vawlume.attribution.report of each run; each side's registered decision policy");
result.status_counts = statusCounts(result.status_crosstab, units);
result.claim_counts = [claimCounts(left, result); claimCounts(right, result)];
if options.CompareScores
    result.scores = scoreRows(units, pairs, left, right);
end
end

% ------------------------------------------------------------- refusals ---

function assertSameRecording(left, right)
if left.recording_id ~= right.recording_id
    error("vawlume:attribution:ComparisonRecordingMismatch", ...
        "Run %d is on recording %d and run %d on recording %d; a comparison is " + ...
        "within one recording.", left.attribution_run_id, left.recording_id, ...
        right.attribution_run_id, right.recording_id);
end
end

function assertSameEventSet(left, right)
a = eventSet(left);
b = eventSet(right);
if a ~= b
    error("vawlume:attribution:CorrespondenceAnalysisRequired", ...
        "Run %d targets %s and run %d targets %s. Targets in different event sets " + ...
        "correspond only through a stored, named analysis: pass it with " + ...
        "compare's Correspondence option (itinerary 7.7). Nothing re-matches " + ...
        "targets on the fly.", left.attribution_run_id, a, ...
        right.attribution_run_id, b);
end
end

function value = eventSet(r)
% The event set a run's targets come from, as its provenance recorded it.
p = r.provenance;
value = string(p.target_kind) + " of " + string(p.target_source_kind) + " " + ...
    string(p.target_source_id);
end

function value = scoreComparability(left, right)
if left.attribution_path ~= right.attribution_path
    value = "not_comparable:producer_scale";
elseif left.method ~= right.method
    value = "not_comparable:method";
elseif ~isequaln(left.settings_profile_version_id, right.settings_profile_version_id)
    value = "not_comparable:settings_profile_version";
else
    value = "comparable";
end
end

% ---------------------------------------------------------------- sides ---

function side = sideOf(conn, r, policyRef, repoRoot, label)
side = struct(label=label, report=r);
decisions = r.decisions;
versions = unique(decisions.policy_profile_version_id);
if isempty(policyRef)
    if numel(versions) > 1
        error("vawlume:attribution:DecisionPolicyRequired", ...
            "Run %d carries decisions under %d policy versions (%s); name one with " + ...
            "%sPolicy.", r.attribution_run_id, numel(versions), ...
            strjoin(string(versions'), ", "), upperFirst(label));
    end
    chosen = versions;
else
    chosen = namedPolicy(r, policyRef, label);
end
side.policy_profile_version_id = NaN;
side.policy_profile_key = "";
side.policy_version_label = "";
side.decisions = decisions([], :);
side.selections = r.decision_selections([], :);
side.policy = struct(read_status="no_decisions", rule_key="", reads="", ...
    producible_statuses=["assigned", "ambiguous", "unassigned", "excluded", "simultaneous"]);
if ~isempty(chosen)
    side.decisions = decisions(decisions.policy_profile_version_id == chosen, :);
    side.selections = r.decision_selections(ismember( ...
        r.decision_selections.attribution_decision_id, ...
        side.decisions.attribution_decision_id), :);
    side.policy_profile_version_id = chosen;
    side.policy_profile_key = side.decisions.policy_profile_key(1);
    side.policy_version_label = side.decisions.policy_version_label(1);
    side.policy = policyStatement(conn, chosen, repoRoot);
end
% Rank basis (D4): the policy's declared reads column, ordered
% higher_is_stronger; otherwise candidate_rank where a target's candidates all
% carry one; otherwise orientation_unknown, per target.
if side.policy.read_status == "read"
    side.rank_basis = side.policy.reads;
else
    side.rank_basis = "candidate_rank";
end
end

function chosen = namedPolicy(r, ref, label)
decisions = r.decisions;
if isnumeric(ref) && isscalar(ref)
    hit = decisions.policy_profile_version_id == ref;
elseif isstruct(ref) && isscalar(ref) && isfield(ref, "policy_profile_key")
    hit = decisions.policy_profile_key == string(ref.policy_profile_key);
    if isfield(ref, "policy_version_label")
        hit = hit & decisions.policy_version_label == string(ref.policy_version_label);
    end
else
    error("vawlume:attribution:DecisionPolicyNotFound", ...
        "%sPolicy must be a policy profile version id or a struct with " + ...
        "policy_profile_key (and optionally policy_version_label).", upperFirst(label));
end
chosen = unique(decisions.policy_profile_version_id(hit));
if isempty(chosen)
    error("vawlume:attribution:DecisionPolicyNotFound", ...
        "The %s policy decided nothing on run %d.", label, r.attribution_run_id);
end
if numel(chosen) > 1
    error("vawlume:attribution:DecisionPolicyRequired", ...
        "The %s policy names %d versions on run %d; add policy_version_label.", ...
        label, numel(chosen), r.attribution_run_id);
end
end

function value = policyStatement(conn, versionId, repoRoot)
% The decision policy, re-read from its registered file only while the file
% still matches its stored checksum: a statement read from a changed file would
% not be the policy that decided.
value = struct(read_status="", rule_key="", reads="", ...
    producible_statuses=["assigned", "ambiguous", "unassigned", "excluded", "simultaneous"]);
rows = fetch(conn, "SELECT content_uri, IFNULL(checksum_sha256,'') AS checksum " + ...
    "FROM config_profile_versions WHERE profile_version_id=" + string(versionId));
if isempty(rows) || height(rows) == 0
    value.read_status = "no_policy_row";
    return
end
path = string(rows.content_uri(1));
if ~vawlume.internal.resolvePath(path, Mode="isAbsolute")
    path = fullfile(repoRoot, path);
end
if ~isfile(path)
    value.read_status = "file_not_found";
    return
end
if attributionSha256OfFile(path) ~= string(rows.checksum(1))
    value.read_status = "checksum_mismatch";
    return
end
policy = attributionLoadPolicy(path, repoRoot);
value.read_status = "read";
value.rule_key = policy.rule_key;
value.reads = policy.reads;
value.producible_statuses = policy.producible_statuses;
end

function row = sideRow(side)
r = side.report;
p = r.provenance;
row = table(string(side.label), r.attribution_run_id, string(r.run_key), ...
    string(r.attribution_path), string(r.method), r.settings_profile_version_id, ...
    r.recording_id, string(p.target_kind), string(p.target_source_kind), ...
    double(p.target_source_id), side.policy_profile_version_id, ...
    string(side.policy_profile_key), string(side.policy_version_label), ...
    string(side.policy.read_status), string(side.policy.rule_key), ...
    strjoin(side.policy.producible_statuses, ","), string(side.rank_basis), ...
    VariableNames=["side", "attribution_run_id", "run_key", "attribution_path", ...
    "method", "settings_profile_version_id", "recording_id", "target_kind", ...
    "target_source_kind", "target_source_id", "policy_profile_version_id", ...
    "policy_profile_key", "policy_version_label", "policy_read_status", ...
    "policy_rule_key", "producible_statuses", "rank_basis"]);
end

% ---------------------------------------------------------------- units ---

function [units, pairs] = unitTable(left, right, unitList, comparability)
% One row per unit, in UNITLIST's order. A one_to_one unit is compared as a
% unit. A unit with several targets on a side keeps not_applicable_unit and
% reports every (left, right) target pair in PAIRS, never promoted. An
% unmatched unit reports each target's own decision against no_counterpart,
% in PAIRS too; it is neither a disagreement nor dropped.
units = emptyUnits();
pairs = emptyPairs();
for k = 1:numel(unitList)
    item = unitList(k);
    leftIds = item.left_target_ids;
    rightIds = item.right_target_ids;
    row = struct(unit_id=k, event_kind=item.event_kind, event_id=item.event_id, ...
        agreement_extent_method=item.agreement_extent_method);
    row.left_target_ids = {leftIds};
    row.right_target_ids = {rightIds};
    row.correspondence_unit = unitType(numel(leftIds), numel(rightIds));
    row.top_entity_agreement = "not_applicable_unit";
    row.selected_set_relation = "not_applicable_unit";
    row.left_decision_status = sideStatus(left, leftIds);
    row.right_decision_status = sideStatus(right, rightIds);
    if row.correspondence_unit == "one_to_one"
        pair = attributionCompareTargets(left, right, leftIds, rightIds);
        row.top_entity_agreement = pair.top_entity_agreement;
        row.selected_set_relation = pair.selected_set_relation;
        row.left_decision_status = pair.left_decision_status;
        row.right_decision_status = pair.right_decision_status;
    elseif isempty(rightIds) || isempty(leftIds)
        for id = leftIds
            pairs(end + 1, :) = {k, id, NaN, "not_applicable_unit", ...
                "not_applicable_unit", statusOf(left, id), "no_counterpart", ...
                comparability}; %#ok<AGROW>
        end
        for id = rightIds
            pairs(end + 1, :) = {k, NaN, id, "not_applicable_unit", ...
                "not_applicable_unit", "no_counterpart", statusOf(right, id), ...
                comparability}; %#ok<AGROW>
        end
    else
        for l = leftIds
            for r = rightIds
                pair = attributionCompareTargets(left, right, l, r);
                pairs(end + 1, :) = {k, l, r, pair.top_entity_agreement, ...
                    pair.selected_set_relation, pair.left_decision_status, ...
                    pair.right_decision_status, comparability}; %#ok<AGROW>
            end
        end
    end
    for dim = dimensions()
        row.("left_declared_" + dim) = declared(left.report, dim);
        row.("right_declared_" + dim) = declared(right.report, dim);
    end
    row.score_comparability = comparability;
    added = struct2table(row, AsArray=true);
    units = [units; added(:, unitColumns())]; %#ok<AGROW>
end
end

function value = unitType(leftCount, rightCount)
% Contract 07 D3's counts, the ones matchingBuildGroups applies.
if leftCount == 0
    value = "unmatched_right";
elseif rightCount == 0
    value = "unmatched_left";
elseif leftCount == 1 && rightCount == 1
    value = "one_to_one";
elseif leftCount == 1
    value = "one_to_many";
elseif rightCount == 1
    value = "many_to_one";
else
    value = "many_to_many";
end
end

function value = sideStatus(side, ids)
% A unit-level status exists only for a single target; a side with no target
% in the unit has no counterpart, which is not "no decision".
if isempty(ids)
    value = "no_counterpart";
elseif ~isscalar(ids)
    value = "not_applicable_unit";
else
    value = statusOf(side, ids);
end
end

function list = sameSetUnits(leftReport, rightReport)
% One unit per event key shared or not; ordered by event kind, id and basis.
leftKeys = eventKeys(leftReport.targets);
rightKeys = eventKeys(rightReport.targets);
keys = sortKeys([leftKeys; rightKeys]);
list = struct(event_kind={}, event_id={}, agreement_extent_method={}, ...
    left_target_ids={}, right_target_ids={});
for k = 1:height(keys)
    key = keys(k, :);
    list(end + 1) = struct(event_kind=key.event_kind, event_id=key.event_id, ...
        agreement_extent_method=key.agreement_extent_method, ...
        left_target_ids=matching(leftReport.targets, leftKeys, key)', ...
        right_target_ids=matching(rightReport.targets, rightKeys, key)'); %#ok<AGROW>
end
end

function list = componentUnits(components)
% Across event sets a unit has no single event; its targets carry identity.
list = struct(event_kind={}, event_id={}, agreement_extent_method={}, ...
    left_target_ids={}, right_target_ids={});
for k = 1:numel(components)
    list(end + 1) = struct(event_kind="correspondence_component", event_id=NaN, ...
        agreement_extent_method="", left_target_ids=components(k).left_target_ids, ...
        right_target_ids=components(k).right_target_ids); %#ok<AGROW>
end
end

function keys = eventKeys(targets)
kind = targets.target_kind;
id = targets.detection_id;
id(kind == "consensus_event") = targets.consensus_event_id(kind == "consensus_event");
id(kind == "agreement_group") = targets.agreement_group_id(kind == "agreement_group");
keys = table(kind, id, targets.agreement_extent_method, ...
    VariableNames=["event_kind", "event_id", "agreement_extent_method"]);
end

function keys = sortKeys(all)
keys = sortrows(unique(all), ["event_kind", "event_id", "agreement_extent_method"]);
end

function ids = matching(targets, keys, key)
hit = keys.event_kind == key.event_kind & keys.event_id == key.event_id & ...
    keys.agreement_extent_method == key.agreement_extent_method;
ids = sort(targets.attribution_target_id(hit));
end

function value = statusOf(side, ids)
if isempty(ids)
    value = "no_decision";
    return
end
decision = side.decisions(side.decisions.attribution_target_id == ids(1), :);
if height(decision) == 0
    value = "no_decision";
else
    value = decision.decision_status(1);
end
end

function value = declared(r, dim)
rows = r.declared_inputs(r.declared_inputs.input_dimension == dim, :);
if height(rows) == 0
    value = "unknown";
else
    value = rows.declaration(1);
end
end

function value = dimensions()
value = ["temporal_alignment", "pose_localization", "visual_identity", "acoustic"];
end

function names = unitColumns()
names = ["unit_id", "correspondence_unit", "event_kind", "event_id", ...
    "agreement_extent_method", "left_target_ids", "right_target_ids", ...
    "top_entity_agreement", "selected_set_relation", "left_decision_status", ...
    "right_decision_status"];
for side = ["left", "right"]
    names = [names, side + "_declared_" + dimensions()]; %#ok<AGROW>
end
names = [names, "score_comparability"];
end

function units = emptyUnits()
names = unitColumns();
units = table();
for name = names
    if ismember(name, ["unit_id", "event_id"])
        units.(name) = zeros(0, 1);
    elseif ismember(name, ["left_target_ids", "right_target_ids"])
        units.(name) = cell(0, 1);
    else
        units.(name) = strings(0, 1);
    end
end
end

function pairs = emptyPairs()
pairs = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["unit_id", "left_target_id", "right_target_id", ...
    "top_entity_agreement", "selected_set_relation", "left_decision_status", ...
    "right_decision_status", "score_comparability"]);
end

% ------------------------------------------------------------- cross-tab ---

function value = crosstab(units, left, right)
statuses = ["assigned", "ambiguous", "unassigned", "excluded", "simultaneous", ...
    "no_decision"];
both = intersect(left.policy.producible_statuses, right.policy.producible_statuses);
oneToOne = units(units.correspondence_unit == "one_to_one", :);
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["left_decision_status", "right_decision_status", ...
    "unit_count", "cell_kind"]);
for l = statuses
    for r = statuses
        if (l ~= "no_decision" && ~ismember(l, both)) || ...
                (r ~= "no_decision" && ~ismember(r, both))
            % One side's rule cannot produce this status, so the cell is not a
            % place the two runs could agree or disagree, whatever the other
            % side holds.
            kind = "structural_empty";
        elseif l == "no_decision" || r == "no_decision"
            kind = "undecided";
        elseif l == "excluded" || r == "excluded"
            % The policy could not be applied on that side (or a QC exclusion was
            % declared): a statement that nothing was decided, not a claim about
            % who called, so it is its own category and never a disagreement.
            kind = "excluded";
        elseif l == r
            kind = "agree";
        else
            kind = "disagree";
        end
        count = nnz(oneToOne.left_decision_status == l & oneToOne.right_decision_status == r);
        value(end + 1, :) = {l, r, count, kind}; %#ok<AGROW>
    end
end
end

function value = statusCounts(crosstab, units)
kinds = ["agree"; "disagree"; "structural_empty"; "excluded"; "undecided"];
counts = zeros(numel(kinds), 1);
for k = 1:numel(kinds)
    counts(k) = sum(crosstab.unit_count(crosstab.cell_kind == kinds(k)));
end
value = table(kinds, counts, repmat(nnz(units.correspondence_unit == "one_to_one"), ...
    numel(kinds), 1), VariableNames=["cell_kind", "unit_count", "one_to_one_units"]);
end

% ------------------------------------------------------ reasons and windows ---

function value = reasonRows(side)
r = side.report;
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), VariableNames=["side", "attribution_target_id", "entity_id", ...
    "category", "reason_ordinal", "reason_code"]);
n = r.no_score_reasons;
for k = 1:height(n)
    value(end + 1, :) = {side.label, n.attribution_target_id(k), n.entity_id(k), ...
        "unscored_candidate", n.reason_ordinal(k), n.reason_code(k)}; %#ok<AGROW>
end
excluded = side.decisions(side.decisions.decision_status == "excluded", :);
for k = 1:height(excluded)
    value(end + 1, :) = {side.label, excluded.attribution_target_id(k), NaN, ...
        "excluded_decision", 1, excluded.exclusion_reason(k)}; %#ok<AGROW>
end
end

function value = windowRows(side)
r = side.report;
value = table(strings(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    cell(0, 1), VariableNames=["side", "imported_attribution_window_id", ...
    "native_window_id", "correspondence_count", "correspondence_status", ...
    "corresponded_target_ids"]);
for k = 1:height(r.windows)
    id = r.windows.imported_attribution_window_id(k);
    targets = sort(r.correspondences.attribution_target_id( ...
        r.correspondences.imported_attribution_window_id == id));
    status = "corresponded";
    if isempty(targets)
        status = "uncorresponded";
    end
    value(end + 1, :) = {side.label, id, r.windows.native_window_id(k), ...
        numel(targets), status, {targets'}}; %#ok<AGROW>
end
end

function value = claimRows(side)
r = side.report;
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    false(0, 1), VariableNames=["side", "imported_attribution_claim_id", ...
    "imported_attribution_window_id", "source_caller_label", "entity_id", "promoted"]);
for k = 1:height(r.imported_claims)
    claim = r.imported_claims(k, :);
    targets = r.correspondences.attribution_target_id( ...
        r.correspondences.imported_attribution_window_id == claim.imported_attribution_window_id);
    promoted = ~isnan(claim.entity_id) && any( ...
        ismember(r.candidates.attribution_target_id, targets) & ...
        r.candidates.entity_id == claim.entity_id);
    value(end + 1, :) = {side.label, claim.imported_attribution_claim_id, ...
        claim.imported_attribution_window_id, claim.source_caller_label, ...
        claim.entity_id, promoted}; %#ok<AGROW>
end
end

function value = claimCounts(side, result)
claims = result.claims(result.claims.side == side.label, :);
windows = result.windows(result.windows.side == side.label, :);
value = table(string(side.label), nnz(claims.promoted), nnz(~claims.promoted), ...
    nnz(windows.correspondence_status == "uncorresponded"), ...
    VariableNames=["side", "claims_promoted", "claims_not_promoted", ...
    "windows_uncorresponded"]);
end

% --------------------------------------------------------------- scores ---

function value = scoreRows(units, pairs, left, right)
% Side by side, per (unit, left target, right target, entity): one_to_one units
% and every within-unit pair. Never a difference, never a pooled value.
value = emptyScores();
oneToOne = units(units.correspondence_unit == "one_to_one", :);
couples = [oneToOne.unit_id, cellfun(@(x) x(1), oneToOne.left_target_ids), ...
    cellfun(@(x) x(1), oneToOne.right_target_ids)];
both = pairs(~isnan(pairs.left_target_id) & ~isnan(pairs.right_target_id), :);
couples = [couples; both.unit_id, both.left_target_id, both.right_target_id];
for k = 1:size(couples, 1)
    l = left.report.candidates(left.report.candidates.attribution_target_id == couples(k, 2), :);
    r = right.report.candidates(right.report.candidates.attribution_target_id == couples(k, 3), :);
    for entity = union(l.entity_id, r.entity_id)'
        [ls, lsem] = scoreOf(l, entity);
        [rs, rsem] = scoreOf(r, entity);
        value(end + 1, :) = {couples(k, 1), couples(k, 2), couples(k, 3), entity, ...
            ls, rs, lsem, rsem}; %#ok<AGROW>
    end
end
value = sortrows(value, ["unit_id", "left_target_id", "right_target_id", "entity_id"]);
end

function [score, semantics] = scoreOf(rows, entity)
hit = rows(rows.entity_id == entity, :);
score = NaN;
semantics = "";
if height(hit) > 0
    score = hit.score(1);
    semantics = hit.score_semantics(1);
end
end

function value = emptyScores()
value = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), strings(0, 1), VariableNames=["unit_id", ...
    "left_target_id", "right_target_id", "entity_id", "left_score", ...
    "right_score", "left_score_semantics", "right_score_semantics"]);
end

% ---------------------------------------------------------------- notes ---

function value = lineageNote()
value = "A native run's lineage runs through analysis_run_sources (its inputs " + ...
    "and its settings profile), not parent_attribution_run_id. The method's " + ...
    "intermediates are not stored, and this comparison does not recompute them.";
end

function value = comparisonNote()
value = "This comparison reports where two runs agree and where they differ. " + ...
    "It combines nothing and chooses nothing: no merged caller, no consensus " + ...
    "decision, no combined score and no preferred run. Agreement between two " + ...
    "runs shows that they agree, not that either is right; on data this " + ...
    "repository generated it is circular. structural_empty cells are statuses " + ...
    "one run's rule cannot produce, excluded cells are targets a side could " + ...
    "not decide, and undecided cells lack a decision on a side; none counts as " + ...
    "agreement or disagreement. An undeclared input is unknown, never not_used.";
end

function value = upperFirst(text)
text = char(text);
value = string([upper(text(1)), text(2:end)]);
end
