function result = mainEffects(responses, design, options)
%MAINEFFECTS Per-factor effect estimates, per response, in the response's own units.
%
% RESULT = vawlume.eda.MAINEFFECTS(RESPONSES, DESIGN) estimates each active
% factor's main effect on EACH RESPONSE SEPARATELY, as the difference of response
% means between the factor's high-level and low-level runs, reported alongside
% that response's spread across the design.
%
% RESPONSES is a vawlume.eda.screenResponses result; DESIGN is the
% vawlume.eda.screeningDesign it was run under.
%
% Name-value options:
%   OnIncompleteDesign   "refuse" (default) or "label". An incomplete design
%                        means some row was not evaluated on every recording
%   IncludeInteractions  estimate two-factor interactions too, default true
%
% SEVERAL TRANSPARENT NUMBERS PER FACTOR PER RESPONSE, NEVER ONE SCORE. There is
% deliberately no normalized effect size aggregated across responses: that is a
% composite score under another name, and it is the single most likely way this
% layer goes wrong. A reader compares an effect against its own response's range,
% which is reported beside it, and forms their own judgement.
%
% NO P-VALUES, CONFIDENCE INTERVALS, OR SIGNIFICANCE TESTS. The design has no
% replication and this MVP makes no distributional claim, so an interval would
% describe a sampling model that does not exist.
%
% EVERY ESTIMATE CARRIES ITS ALIAS. At resolution IV a main effect is clear of
% two-factor interactions while the two-factor interactions are aliased in pairs,
% so an interaction estimate from such a design is the SUM of its aliased pair
% rather than either member. `is_uniquely_attributable` says which, and a
% consumer deciding whether an interaction is measured or merely suspected should
% read that field rather than infer it from the resolution.
%
% AN INCOMPLETE DESIGN IS REFUSED BY DEFAULT. Effect estimates assume every
% design row was evaluated on the same recordings; where a unit failed, the
% difference of means is taken over unequal sets and the number is not the
% quantity it claims to be. "label" computes anyway and marks every row, which is
% for a caller who has read the completeness report and wants the estimate with
% its caveat attached. Nothing returns a silently biased number.
%
% This function is pure arithmetic over the response table and the design.

arguments
    responses (1,1) struct
    design (1,1) struct
    options.OnIncompleteDesign (1,1) string ...
        {mustBeMember(options.OnIncompleteDesign, ["refuse", "label"])} = "refuse"
    options.IncludeInteractions (1,1) logical = true
end

requireFields(responses, ["responses", "design_completeness"]);
requireFields(design, ["configurations", "factors", "coding", "alias"]);

completeness = responses.design_completeness;
isComplete = isfield(completeness, "is_complete") && completeness.is_complete;
if ~isComplete && options.OnIncompleteDesign == "refuse"
    error("vawlume:eda:DesignIncomplete", ...
        "The probe's design is incomplete, so a main effect would be a " + ...
        "difference of means over unequal recording sets rather than the " + ...
        "quantity it claims to be. Re-run the missing units, or pass " + ...
        "OnIncompleteDesign=""label"" to compute anyway with every row " + ...
        "marked. %s", completenessNote(completeness));
end

pooled = responses.responses(responses.responses.scope == "pooled", :);
if height(pooled) == 0
    error("vawlume:eda:NoPooledResponses", ...
        "There are no pooled response rows to estimate effects from.");
end

configurations = design.configurations.configuration_id;
effects = effectDefinitions(design, options.IncludeInteractions);
identities = unique(pooled(:, ["response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary", "value_kind"]), "rows");

rows = emptyEffects();
for index = 1:height(identities)
    identity = identities(index, :);
    values = responseVector(pooled, identity, configurations);
    if isempty(values)
        continue
    end
    rows = [rows; estimateFor(identity, values, effects, configurations, ...
        isComplete)]; %#ok<AGROW>
end

result = struct( ...
    status="estimated", ...
    exploration_run_key=explorationKey(responses), ...
    design_type=design.design_type, ...
    resolution_label=design.alias.resolution_label, ...
    configuration_count=numel(configurations), ...
    design_is_complete=isComplete, ...
    incomplete_design_policy=options.OnIncompleteDesign, ...
    effects=rows, ...
    effect_definition="difference of response means between a factor's " + ...
        "high-level and low-level runs, in the response's own units", ...
    interaction_note=design.alias.note, ...
    no_composite_score="effects are reported per factor per response and " + ...
        "are never aggregated into one number across responses", ...
    inference_note="no p-value, confidence interval, or significance test " + ...
        "is computed; the design has no replication", ...
    caution=edaCautionNote());
end

% ---------------------------------------------------------- effect columns ---

function value = effectDefinitions(design, includeInteractions)
%EFFECTDEFINITIONS The contrast column for every effect the design can estimate.
%
% A main effect's contrast is its own factor column. A two-factor interaction's
% contrast is the element-wise product of the two, which is what makes the same
% difference-of-means formula estimate it.
letters = design.factors.design_letter;
names = design.factors.factor_name;
coding = design.coding;
aliasTable = design.alias.alias_table;

value = struct("name", {}, "label", {}, "order", {}, "contrast", {}, ...
    "alias", {}, "unique", {});
for index = 1:numel(letters)
    value(end + 1) = definition(letters(index), names(index), 1, ...
        coding(:, index), aliasTable); %#ok<AGROW>
end
if ~includeInteractions
    return
end
for left = 1:(numel(letters) - 1)
    for right = (left + 1):numel(letters)
        label = letters(left) + letters(right);
        value(end + 1) = definition(label, ...
            names(left) + " x " + names(right), 2, ...
            coding(:, left) .* coding(:, right), aliasTable); %#ok<AGROW>
    end
end
end

function value = definition(label, name, order, contrast, aliasTable)
selected = aliasTable.effect == label;
alias = "";
unique = true;
if any(selected)
    alias = aliasTable.aliased_with(find(selected, 1));
    unique = aliasTable.is_uniquely_attributable(find(selected, 1));
end
value = struct("name", name, "label", label, "order", order, ...
    "contrast", contrast, "alias", alias, "unique", unique);
end

% ------------------------------------------------------------- estimation ---

function rows = estimateFor(identity, values, effects, configurations, isComplete)
rows = emptyEffects();
observed = values(isfinite(values));
if isempty(observed)
    return
end
spread = max(observed) - min(observed);

for index = 1:numel(effects)
    effect = effects(index);
    high = effect.contrast > 0 & isfinite(values);
    low = effect.contrast < 0 & isfinite(values);
    if ~any(high) || ~any(low)
        estimate = NaN;
    else
        estimate = mean(values(high)) - mean(values(low));
    end
    rows(end + 1, :) = {identity.response, identity.qualifier_kind, ...
        identity.qualifier, identity.secondary_kind, identity.secondary, ...
        identity.value_kind, effect.label, effect.name, effect.order, ...
        estimate, spread, min(observed), max(observed), ...
        numel(configurations), nnz(high), nnz(low), effect.alias, ...
        effect.unique, isComplete}; %#ok<AGROW>
end
end

function values = responseVector(pooled, identity, configurations)
%RESPONSEVECTOR One value per configuration, in the design's own row order.
%
% NaN where a configuration has no row for this response. The zero-filling
% performed upstream means a count identity always has a value everywhere, so a
% NaN here signals a genuinely missing unit rather than an unobserved category -
% and the estimate for that effect is then reported undefined rather than
% computed over a shorter vector.
values = NaN(numel(configurations), 1);
selected = pooled.response == identity.response & ...
    pooled.qualifier_kind == identity.qualifier_kind & ...
    pooled.qualifier == identity.qualifier & ...
    pooled.secondary_kind == identity.secondary_kind & ...
    pooled.secondary == identity.secondary;
matching = pooled(selected, :);
for index = 1:numel(configurations)
    row = matching.value(matching.configuration_id == configurations(index));
    if ~isempty(row)
        values(index) = row(1);
    end
end
end

% ---------------------------------------------------------------- plumbing ---

function value = completenessNote(completeness)
value = "";
if isfield(completeness, "note")
    value = string(completeness.note);
end
end

function value = explorationKey(responses)
value = "";
if isfield(responses, "exploration_run_key")
    value = string(responses.exploration_run_key);
end
end

function value = emptyEffects()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), false(0, 1), ...
    false(0, 1), ...
    VariableNames=["response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary", "value_kind", "effect", "effect_name", ...
    "effect_order", "estimate", "response_range", "response_minimum", ...
    "response_maximum", "configuration_count", "high_run_count", ...
    "low_run_count", "aliased_with", "is_uniquely_attributable", ...
    "design_is_complete"]);
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:EffectInputInvalid", ...
        "A required input is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
