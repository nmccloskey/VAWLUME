function plan = attributionBuildCandidatePlan(conn, targetRef, inputCandidates)
%ATTRIBUTIONBUILDCANDIDATEPLAN Validate candidates without selecting among them.

[plan.target, plan.run] = attributionResolveTarget(conn, targetRef);
assertWritableRun(plan.run);
plan.candidates = normalizeCandidates(inputCandidates, ...
    plan.target.attribution_target_id);
if ~all(ismember(plan.candidates.entity_id, ...
        plan.run.participating_entity_ids))
    rejected = plan.candidates.entity_id(~ismember( ...
        plan.candidates.entity_id, plan.run.participating_entity_ids));
    error("vawlume:attribution:CandidateNotInRun", ...
        "Candidate entities are outside the run's snapshotted participant set: %s.", ...
        strjoin(string(unique(rejected)), ", "));
end

stored = attributionReadCandidates(conn, plan.target.attribution_target_id);
plan.conflicts = strings(0, 1);
for index = 1:height(plan.candidates)
    existingIndex = find(stored.entity_id == plan.candidates.entity_id(index));
    if isempty(existingIndex)
        continue
    end
    storedRow = stored(existingIndex(1), :);
    plan.candidates.attribution_candidate_id(index) = ...
        storedRow.attribution_candidate_id;
    if candidateRowsEqual(storedRow, plan.candidates(index, :))
        plan.candidates.action(index) = "reuse";
    else
        plan.candidates.action(index) = "conflict";
        plan.conflicts(end + 1, 1) = "Candidate entity " + ...
            string(plan.candidates.entity_id(index)) + ...
            " already exists for this target with different stored content.";
    end
end
plan.has_conflicts = ~isempty(plan.conflicts);

planned = plan.candidates(plan.candidates.action ~= "conflict", :);
newRows = planned(planned.action == "create", :);
combined = [stored; newRows];
validateRankAgreement(combined);
end

function assertWritableRun(run)
if run.status ~= "planned" || run.analysis_status ~= "started"
    error("vawlume:attribution:RunNotWritable", ...
        "Candidates may only be appended while attribution status is planned and analysis status is started.");
end
end

function candidates = normalizeCandidates(raw, targetId)
rows = rowTable(raw, "candidates");
if height(rows) == 0
    error("vawlume:attribution:CandidateSetEmpty", ...
        "At least one candidate row is required.");
end
allowed = ["entity_id", "candidate_status", "candidate_rank", "score", ...
    "score_semantics", "probability", "probability_semantics", ...
    "source_label", "notes"];
unknown = setdiff(string(rows.Properties.VariableNames), allowed);
if ~isempty(unknown)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "Unknown candidate fields: %s.", strjoin(unknown, ", "));
end
if ~ismember("entity_id", string(rows.Properties.VariableNames))
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "Every candidate requires entity_id.");
end
count = height(rows);
entityIds = numericColumn(rows, "entity_id", NaN(count, 1));
if any(~isfinite(entityIds) | entityIds < 1 | fix(entityIds) ~= entityIds)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "Every entity_id must be a positive integer.");
end
if numel(unique(entityIds)) ~= count
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "A candidate batch may name an entity only once per target.");
end
statuses = textColumn(rows, "candidate_status", repmat("candidate", count, 1));
if any(statuses ~= "candidate")
    error("vawlume:attribution:CandidateStatusInvalid", ...
        "Phase 4.5 stores candidates only; selected and rejected are decision-layer states.");
end
ranks = numericColumn(rows, "candidate_rank", NaN(count, 1));
scores = numericColumn(rows, "score", NaN(count, 1));
scoreSemantics = textColumn(rows, "score_semantics", strings(count, 1));
probabilities = numericColumn(rows, "probability", NaN(count, 1));
probabilitySemantics = textColumn(rows, "probability_semantics", strings(count, 1));

if any(~isnan(scores) & ~isfinite(scores))
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "A stored score must be finite.");
end
if any(~isnan(scores) & strlength(scoreSemantics) == 0)
    error("vawlume:attribution:ScoreSemanticsRequired", ...
        "Every stored score requires score_semantics.");
end
if any(isnan(scores) & strlength(scoreSemantics) > 0)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "score_semantics cannot describe an absent score.");
end
if any(~isnan(probabilities) & ~isfinite(probabilities)) || ...
        any(probabilities < 0 | probabilities > 1)
    error("vawlume:attribution:ProbabilityOutOfRange", ...
        "Every stored probability must be finite and within [0, 1].");
end
if any(~isnan(probabilities) & strlength(probabilitySemantics) == 0)
    error("vawlume:attribution:ProbabilitySemanticsRequired", ...
        "Every stored probability requires probability_semantics.");
end
if any(isnan(probabilities) & strlength(probabilitySemantics) > 0)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "probability_semantics cannot describe an absent probability.");
end
if any(~isnan(ranks) & (~isfinite(ranks) | ranks < 1 | fix(ranks) ~= ranks))
    error("vawlume:attribution:CandidateRankInvalid", ...
        "candidate_rank must be absent or a positive integer.");
end
if any(~isnan(ranks) & isnan(scores))
    error("vawlume:attribution:CandidateRankInvalid", ...
        "candidate_rank is a presentation of score and requires a score.");
end

candidates = table(NaN(count, 1), repmat(targetId, count, 1), ...
    (1:count)', entityIds, statuses, ranks, scores, scoreSemantics, ...
    probabilities, probabilitySemantics, ...
    rawTextColumn(rows, "source_label", strings(count, 1)), ...
    rawTextColumn(rows, "notes", strings(count, 1)), ...
    repmat("create", count, 1), ...
    VariableNames=["attribution_candidate_id", "attribution_target_id", ...
    "candidate_ordinal", "entity_id", "candidate_status", ...
    "candidate_rank", "score", "score_semantics", "probability", ...
    "probability_semantics", "source_label", "notes", "action"]);
validateRankAgreement(candidates);
end

function rows = rowTable(raw, label)
if istable(raw)
    rows = raw;
elseif isstruct(raw)
    try
        rows = struct2table(raw(:));
    catch
        error("vawlume:attribution:CandidateSpecInvalid", ...
            "%s must be a table or a scalar-valued struct array.", label);
    end
else
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "%s must be a table or struct array.", label);
end
end

function value = numericColumn(rows, name, fallback)
if ~ismember(name, string(rows.Properties.VariableNames))
    value = fallback;
    return
end
value = rows.(name);
if ~isnumeric(value) || numel(value) ~= height(rows)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "%s must contain one numeric value per candidate.", name);
end
value = double(value(:));
end

function value = textColumn(rows, name, fallback)
if ~ismember(name, string(rows.Properties.VariableNames))
    value = fallback;
    return
end
try
    value = strtrim(string(rows.(name)));
catch
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "%s must contain one text value per candidate.", name);
end
if numel(value) ~= height(rows)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "%s must contain one text value per candidate.", name);
end
value = value(:);
value(ismissing(value)) = "";
end

function value = rawTextColumn(rows, name, fallback)
if ~ismember(name, string(rows.Properties.VariableNames))
    value = fallback;
    return
end
try
    value = string(rows.(name));
catch
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "%s must contain one text value per candidate.", name);
end
if numel(value) ~= height(rows)
    error("vawlume:attribution:CandidateSpecInvalid", ...
        "%s must contain one text value per candidate.", name);
end
value = value(:);
value(ismissing(value)) = "";
end

function validateRankAgreement(candidates)
ranked = candidates(~isnan(candidates.candidate_rank), :);
for left = 1:height(ranked)
    for right = left + 1:height(ranked)
        scoreLeft = ranked.score(left);
        scoreRight = ranked.score(right);
        rankLeft = ranked.candidate_rank(left);
        rankRight = ranked.candidate_rank(right);
        contradiction = (scoreLeft == scoreRight && rankLeft ~= rankRight) || ...
            (scoreLeft > scoreRight && rankLeft >= rankRight) || ...
            (scoreLeft < scoreRight && rankLeft <= rankRight);
        if contradiction
            error("vawlume:attribution:CandidateRankConflict", ...
                "Supplied ranks contradict the stored scores. Equal scores must tie; a higher score must have a lower rank.");
        end
    end
end
end

function okay = candidateRowsEqual(stored, planned)
okay = stored.entity_id == planned.entity_id && ...
    stored.candidate_status == planned.candidate_status && ...
    sameNumber(stored.candidate_rank, planned.candidate_rank) && ...
    sameNumber(stored.score, planned.score) && ...
    stored.score_semantics == planned.score_semantics && ...
    sameNumber(stored.probability, planned.probability) && ...
    stored.probability_semantics == planned.probability_semantics && ...
    stored.source_label == planned.source_label && stored.notes == planned.notes;
end

function okay = sameNumber(left, right)
okay = (isnan(left) && isnan(right)) || left == right;
end
