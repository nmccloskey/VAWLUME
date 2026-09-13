function plan = attributionBuildDecisionPlan(conn, runRef, policyRef, options)
%ATTRIBUTIONBUILDDECISIONPLAN Apply a declared policy over stored candidates.
%
% Derived and re-derivable: nothing this produces is unrecoverable from the
% candidate rows plus the policy. It reads candidates and writes nothing.

repoRoot = resolveRepoRoot(options.RepoRoot);
policy = attributionLoadPolicy(policyPathOf(policyRef), repoRoot);

run = attributionResolveRun(conn, runRef);
% The policy profile is scoped to the run's project and cites the artifact by a
% repository-relative path, so a stored decision names a file a later reader can
% actually find rather than one machine's absolute path.
policy.project_id = run.project_id;
policy.content_uri = portableUri(policy.profile_path, repoRoot);
targets = attributionReadTargets(conn, run.attribution_run_id);
if isempty(targets) || height(targets) == 0
    error("vawlume:attribution:TargetSetEmpty", ...
        "Attribution run %s has no targets to decide.", run.run_key);
end

targets = selectRequestedTargets(targets, options.Targets);
exclusions = normalizeExclusions(options.Exclusions, targets, policy);

plan = struct();
plan.run = run;
plan.policy = policy;
plan.decisions = emptyDecisions();
plan.selections = emptySelections();
plan.has_conflicts = false;

for index = 1:height(targets)
    targetId = double(targets.attribution_target_id(index));
    candidates = attributionReadCandidates(conn, targetId);

    % A target with no candidates is an unfinished analysis, not an outcome.
    % Deciding it would report absence of evidence as evidence of absence.
    if height(candidates) == 0
        error("vawlume:attribution:NoCandidates", ...
            "Attribution target %d has no candidates. Add candidates before deciding.", ...
            targetId);
    end

    existing = existingDecision(conn, targetId, policy);
    outcome = decideOneTarget(candidates, policy, exclusionFor(exclusions, targetId));
    outcome.attribution_target_id = targetId;
    outcome.action = "create";
    if existing.exists
        % A completed decision is never rewritten in place. A different policy
        % version is a different decision, and both stay readable -- that is
        % what makes comparing policies over one body of evidence possible.
        outcome.action = "conflict";
        outcome.existing_decision_id = existing.attribution_decision_id;
        plan.has_conflicts = true;
    end
    plan.decisions = [plan.decisions; decisionRow(outcome)]; %#ok<AGROW>
    for selected = 1:numel(outcome.selected_candidate_ids)
        plan.selections = [plan.selections; selectionRow(targetId, ...
            outcome.selected_candidate_ids(selected), ...
            outcome.selection_role)]; %#ok<AGROW>
    end
end
end

% ------------------------------------------------------------- the rule ---

function outcome = decideOneTarget(candidates, policy, callerExclusion)
%DECIDEONETARGET The whole decision rule, in one readable place.

outcome = struct(decision_status="unassigned", selected_candidate_ids=[], ...
    selection_role="", applied_threshold=NaN, ...
    applied_threshold_semantics="", exclusion_reason="", ...
    contender_count=0, readable_count=0, top_value=NaN);

% 1. A caller-declared QC exclusion. VAWLUME does not invent QC failures from
%    the numbers; a person decides a target should not be attributed, and the
%    reason travels with the decision.
if strlength(callerExclusion) > 0
    outcome.decision_status = "excluded";
    outcome.exclusion_reason = callerExclusion;
    return
end

values = valuesRead(candidates, policy.reads);
semantics = semanticsRead(candidates, policy.reads);
readable = ~isnan(values);
if policy.requires_value_semantics
    readable = readable & strlength(semantics) > 0;
end
outcome.readable_count = nnz(readable);

% 2. The policy could not be applied at all. Distinct from unassigned, which
%    means the rule ran and nothing passed.
if outcome.readable_count == 0
    if policy.exclude_when_no_readable_value
        outcome.decision_status = "excluded";
        outcome.exclusion_reason = policy.no_readable_value_reason;
    else
        outcome.decision_status = "unassigned";
        outcome.applied_threshold = policy.selection_threshold;
        outcome.applied_threshold_semantics = thresholdSemantics( ...
            "selection_threshold", policy);
    end
    return
end

readableValues = values(readable);
readableIds = candidates.attribution_candidate_id(readable);
top = max(readableValues);
outcome.top_value = top;

% 3. Nothing supportable. The rule ran; the selection threshold bound.
if top < policy.selection_threshold
    outcome.decision_status = "unassigned";
    outcome.applied_threshold = policy.selection_threshold;
    outcome.applied_threshold_semantics = thresholdSemantics( ...
        "selection_threshold", policy);
    return
end

% 4. Contenders are the candidates this policy cannot separate from the top.
%    Clearing the selection threshold alone never produces an assignment while
%    another candidate remains this close -- that is what stops a threshold
%    quietly manufacturing confidence.
isContender = readableValues >= top - policy.separation_margin;
contenderValues = readableValues(isContender);
contenderIds = readableIds(isContender);
outcome.contender_count = numel(contenderIds);

if outcome.contender_count == 1
    outcome.decision_status = "assigned";
    outcome.selected_candidate_ids = contenderIds;
    outcome.selection_role = "sole_supported_candidate";
    outcome.applied_threshold = policy.separation_margin;
    outcome.applied_threshold_semantics = thresholdSemantics( ...
        "separation_margin", policy);
    return
end

% 5. Several contenders. Claiming that more than one animal called requires
%    each of them to be independently strong, not merely close to each other.
if all(contenderValues >= policy.co_occurrence_threshold)
    outcome.decision_status = "simultaneous";
    outcome.selected_candidate_ids = contenderIds;
    outcome.selection_role = "co_occurring_candidate";
    outcome.applied_threshold = policy.co_occurrence_threshold;
    outcome.applied_threshold_semantics = thresholdSemantics( ...
        "co_occurrence_threshold", policy);
    return
end

% 6. Close together and not each independently strong: the evidence cannot
%    separate them. A statement about the evidence, not about the world.
outcome.decision_status = "ambiguous";
outcome.applied_threshold = policy.co_occurrence_threshold;
outcome.applied_threshold_semantics = thresholdSemantics( ...
    "co_occurrence_threshold", policy);
end

% ---------------------------------------------------------------- helpers ---

function value = thresholdSemantics(which, policy)
% Which threshold actually bound this decision. The profile version carries the
% whole policy, but a policy declares several thresholds and the profile alone
% does not say which one decided this row.
switch which
    case "selection_threshold"
        detail = "minimum value a candidate must reach to be supportable";
    case "separation_margin"
        detail = "how far below the top a candidate stays indistinguishable from it";
    otherwise
        detail = "value every contender must independently reach before " + ...
            "more than one caller is claimed";
end
value = which + " of " + policy.profile_key + "@" + policy.version_label + ...
    " read over candidate " + policy.reads + "; " + detail + ...
    "; illustrative and uncalibrated, not a probability";
end

function values = valuesRead(candidates, reads)
if reads == "probability"
    values = double(candidates.probability);
else
    values = double(candidates.score);
end
end

function values = semanticsRead(candidates, reads)
if reads == "probability"
    values = string(candidates.probability_semantics);
else
    values = string(candidates.score_semantics);
end
end

function existing = existingDecision(conn, targetId, policy)
existing = struct(exists=false, attribution_decision_id=NaN);
rows = fetch(conn, "SELECT d.attribution_decision_id AS id " + ...
    "FROM attribution_decisions d " + ...
    "JOIN config_profile_versions v " + ...
    "  ON v.profile_version_id = d.policy_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id " + ...
    "WHERE d.attribution_target_id=" + string(targetId) + ...
    " AND p.profile_key=" + sqlText(policy.profile_key) + ...
    " AND v.version_label=" + sqlText(policy.version_label));
if height(rows) > 0
    existing.exists = true;
    existing.attribution_decision_id = double(rows.id(1));
end
end

function targets = selectRequestedTargets(targets, requested)
if isempty(requested)
    return
end
requested = double(requested(:));
keep = ismember(double(targets.attribution_target_id), requested);
missing = setdiff(requested, double(targets.attribution_target_id));
if ~isempty(missing)
    error("vawlume:attribution:TargetNotInRun", ...
        "Target %d does not belong to this attribution run.", missing(1));
end
targets = targets(keep, :);
end

function exclusions = normalizeExclusions(raw, targets, policy)
exclusions = struct(attribution_target_id={}, reason={});
if isempty(raw)
    return
end
if ~policy.permits_caller_exclusions
    error("vawlume:attribution:ExclusionNotPermitted", ...
        "This policy does not permit caller-declared exclusions.");
end
rows = struct2table(raw, AsArray=true);
for index = 1:height(rows)
    if ~ismember("attribution_target_id", string(rows.Properties.VariableNames)) || ...
            ~ismember("reason", string(rows.Properties.VariableNames))
        error("vawlume:attribution:ExclusionInvalid", ...
            "Each exclusion requires attribution_target_id and reason.");
    end
    targetId = double(rows.attribution_target_id(index));
    reason = strtrim(string(rows.reason(index)));
    % An excluded decision that does not say why is not a QC record.
    if strlength(reason) == 0
        error("vawlume:attribution:ExclusionInvalid", ...
            "Exclusion of target %d requires a nonempty reason.", targetId);
    end
    if ~ismember(targetId, double(targets.attribution_target_id))
        error("vawlume:attribution:TargetNotInRun", ...
            "Excluded target %d does not belong to this attribution run.", targetId);
    end
    exclusions(end+1) = struct(attribution_target_id=targetId, reason=reason); %#ok<AGROW>
end
end

function reason = exclusionFor(exclusions, targetId)
reason = "";
for index = 1:numel(exclusions)
    if exclusions(index).attribution_target_id == targetId
        reason = exclusions(index).reason;
        return
    end
end
end

function row = decisionRow(outcome)
row = table(outcome.attribution_target_id, string(outcome.decision_status), ...
    outcome.applied_threshold, string(outcome.applied_threshold_semantics), ...
    string(outcome.exclusion_reason), numel(outcome.selected_candidate_ids), ...
    outcome.contender_count, outcome.readable_count, outcome.top_value, ...
    string(outcome.action), ...
    VariableNames=["attribution_target_id", "decision_status", ...
    "applied_threshold", "applied_threshold_semantics", "exclusion_reason", ...
    "selected_count", "contender_count", "readable_count", "top_value", "action"]);
end

function row = selectionRow(targetId, candidateId, role)
row = table(targetId, candidateId, string(role), ...
    VariableNames=["attribution_target_id", "attribution_candidate_id", ...
    "selection_role"]);
end

function value = emptyDecisions()
value = table('Size', [0 10], ...
    'VariableTypes', ["double", "string", "double", "string", "string", ...
    "double", "double", "double", "double", "string"], ...
    'VariableNames', ["attribution_target_id", "decision_status", ...
    "applied_threshold", "applied_threshold_semantics", "exclusion_reason", ...
    "selected_count", "contender_count", "readable_count", "top_value", "action"]);
end

function value = emptySelections()
value = table('Size', [0 3], ...
    'VariableTypes', ["double", "double", "string"], ...
    'VariableNames', ["attribution_target_id", "attribution_candidate_id", ...
    "selection_role"]);
end

function root = resolveRepoRoot(root)
root = string(root);
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath"))))));
end
root = string(java.io.File(char(root)).getCanonicalPath());
end

function value = policyPathOf(policyRef)
value = "";
if isstring(policyRef) || ischar(policyRef)
    value = string(policyRef);
    return
end
if isstruct(policyRef) && isfield(policyRef, "profile_path")
    value = string(policyRef.profile_path);
end
end

function value = portableUri(path, repoRoot)
path = replace(string(path), "\\", "/");
root = strip(replace(string(repoRoot), "\\", "/"), "right", "/");
prefix = root + "/";
if startsWith(lower(path), lower(prefix))
    value = extractAfter(path, strlength(prefix));
else
    value = path;
end
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
