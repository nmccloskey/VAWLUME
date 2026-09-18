function result = leverageCategories(effects, design, options)
%LEVERAGECATEGORIES Contract §H's category for every factor on every response.
%
% RESULT = vawlume.eda.LEVERAGECATEGORIES(EFFECTS, DESIGN) categorises each
% factor's effect on each response relative to THAT RESPONSE'S OWN SPREAD across
% the design, so categories are comparable across responses measured in different
% units. EFFECTS is a vawlume.eda.mainEffects result; DESIGN is the
% vawlume.eda.screeningDesign it was estimated under.
%
% Name-value options:
%   Resolution                  the vawlume.eda.probeParameters record, so
%                               factors that were never screened are reported as
%                               `insufficient_information` rather than absent
%   InteractionRatio            default 0.50 (contract §H)
%   HighLeverageRatio           default 0.50 (contract §H)
%   ModerateLeverageRatio       default 0.20 (contract §H)
%   MinimumSupportedRuns        default 2 — a difference of means needs at least
%                               one high run and one low run
%
% THE CATEGORIES, IN PRECEDENCE ORDER:
%
%   insufficient_information  range == 0, or the estimate is undefined, or
%                             supported runs are below the floor, or the factor
%                             was inactive
%   interaction_suspected     an interaction estimate involving the factor has
%                             magnitude >= 0.5 x |effect| and is itself nonzero,
%                             OR the design's resolution aliases main effects
%   high_leverage             |effect| / range >= 0.50
%   moderate_leverage         0.20 <= |effect| / range < 0.50
%   low_leverage              |effect| / range < 0.20
%
% PRECEDENCE IS THE WHOLE POINT OF THE FIRST ROW. A response constant across
% every configuration - and Part 8's handoff flags that `detections_considered`
% is exactly that, by construction, because it is the denominator rather than a
% response to a threshold - gives every factor a main effect of zero. Dividing
% zero by a zero range and calling the result "small" would report every factor
% as inert. `insufficient_information` is checked first, and the zero
% `response_range` beside it is the signal a reader can verify.
%
% THE ALIAS TRIGGER READS THE DESIGN, NOT THE NUMBERS. At resolution III a main
% effect is confounded with a two-factor interaction, so the estimate is not the
% factor's effect at all and no magnitude computed from it means what it appears
% to. A screen that reported `low_leverage` for such a factor would be making a
% claim its design cannot support. That trigger fires from DESIGN.alias
% regardless of what the estimates look like.
%
% AT RESOLUTION IV an interaction estimate is the SUM OF ITS ALIASED PAIR rather
% than either member. When the interaction trigger fires, the result says whether
% the interaction that fired it is uniquely attributable, because "these two
% factors interact" and "one of these two pairs interacts" are different claims.
%
% THE CUT POINTS ARE A REPORTING CONVENTION, NOT AN INFERENTIAL THRESHOLD. The
% design has no replication and this MVP makes no distributional claim, so no
% p-value, confidence interval or significance test is computed and none should
% be inferred from a category boundary. RESULT.cut_point_note carries that
% sentence so it travels with the table.
%
% There is no aggregate. No factor is ranked, scored, or recommended, and no
% configuration is selected.
%
% This function is pure arithmetic over the effect table and the design metadata.

arguments
    effects (1,1) struct
    design (1,1) struct
    options.Resolution struct = struct([])
    options.InteractionRatio (1,1) double {mustBeNonnegative} = 0.50
    options.HighLeverageRatio (1,1) double {mustBeNonnegative} = 0.50
    options.ModerateLeverageRatio (1,1) double {mustBeNonnegative} = 0.20
    options.MinimumSupportedRuns (1,1) double {mustBeNonnegative} = 2
end

requireFields(effects, ["effects", "design_is_complete"]);
requireFields(design, ["factors", "alias"]);
if options.ModerateLeverageRatio > options.HighLeverageRatio
    error("vawlume:eda:LeverageCutPointsInverted", ...
        "The moderate cut point (%g) is above the high one (%g), which " + ...
        "would make every moderate row also high.", ...
        options.ModerateLeverageRatio, options.HighLeverageRatio);
end

table0 = effects.effects;
mainRows = table0(table0.effect_order == 1, :);
interactionRows = table0(table0.effect_order == 2, :);
mainEffectsAliased = aliasedMainEffects(design);

rows = emptyCategories();
for index = 1:height(mainRows)
    rows = [rows; categoriseOne(mainRows(index, :), interactionRows, ...
        design, mainEffectsAliased, options)]; %#ok<AGROW>
end

rows = [rows; inactiveFactorRows(options.Resolution, design, rows)];
rows = sortrows(rows, ["response", "qualifier", "secondary", "factor_name"]);

result = struct( ...
    status="categorised", ...
    probe_role=probeRole(design), ...
    exploration_run_key=explorationKey(effects), ...
    design_type=string(design.design_type), ...
    resolution_label=string(design.alias.resolution_label), ...
    main_effects_are_aliased=mainEffectsAliased, ...
    design_is_complete=logical(effects.design_is_complete), ...
    categories=rows, ...
    category_vocabulary=edaLeverageCategories(), ...
    category_counts=categoryCounts(rows), ...
    cut_points=struct( ...
        high_leverage_ratio=options.HighLeverageRatio, ...
        moderate_leverage_ratio=options.ModerateLeverageRatio, ...
        interaction_ratio=options.InteractionRatio, ...
        minimum_supported_runs=options.MinimumSupportedRuns), ...
    cut_point_note="The cut points are a REPORTING CONVENTION, not an " + ...
        "inferential threshold. No p-value, confidence interval or " + ...
        "significance test is computed: the design has no replication and " + ...
        "this MVP makes no distributional claim. A factor just either side " + ...
        "of a boundary differs in label, not in evidence.", ...
    ratio_definition="|main effect| divided by that response's own " + ...
        "max - min across the design runs", ...
    direction_definition="the sign of the main effect, which is the " + ...
        "response at the factor's HIGH PARAMETER VALUE minus the response " + ...
        "at its low one; strictness_direction says which of those is the " + ...
        "stricter setting", ...
    no_ranking="factors are categorised, never ranked, scored, or " + ...
        "recommended, and no configuration is selected", ...
    caution=edaCautionNote());
end

% -------------------------------------------------------- categorise one ---

function row = categoriseOne(effect, interactionRows, design, ...
    mainEffectsAliased, options)
letter = effect.effect;
factorName = factorNameFor(design, letter, effect.effect_name);
redundantFlag = redundantIn(options.Resolution, factorName);
supported = effect.high_run_count + effect.low_run_count;
[peakLabel, peakEstimate, peakUnique, peakAlias] = ...
    strongestInteraction(interactionRows, effect, letter);

range = effect.response_range;
estimate = effect.estimate;
ratio = NaN;
if isfinite(estimate) && isfinite(range) && range > 0
    ratio = abs(estimate) / range;
end
interactionRatio = NaN;
if isfinite(peakEstimate) && isfinite(estimate) && abs(estimate) > 0
    interactionRatio = abs(peakEstimate) / abs(estimate);
end

[category, reason] = decide(estimate, range, ratio, supported, ...
    peakEstimate, mainEffectsAliased, options);

direction = directionOf(estimate, category, mainEffectsAliased);

row = {effect.response, effect.qualifier_kind, effect.qualifier, ...
    effect.secondary_kind, effect.secondary, effect.value_kind, ...
    factorName, letter, estimate, range, effect.response_minimum, ...
    effect.response_maximum, ratio, category, reason, direction, ...
    strictnessOf(design, factorName), redundantFlag, supported, ...
    effect.configuration_count, peakLabel, peakEstimate, interactionRatio, ...
    peakUnique, peakAlias, mainEffectsAliased, ...
    string(effect.aliased_with), logical(effect.is_uniquely_attributable), ...
    logical(effect.design_is_complete)};
row = cell2table(row, VariableNames=categoryNames());
end

function [category, reason] = decide(estimate, range, ratio, supported, ...
    peakEstimate, mainEffectsAliased, options)
%DECIDE Contract §H's rules, in contract §H's order.
%
% Written as a straight cascade rather than as a set of predicates combined
% afterwards, because the precedence IS the specification: reordering these five
% blocks changes which claim the workflow makes about an inert response.

% 1. insufficient_information - outranks everything.
if ~isfinite(range)
    category = "insufficient_information";
    reason = "the response has no finite spread across the design";
    return
end
if range == 0
    category = "insufficient_information";
    reason = "the response is constant across every configuration, so its " + ...
        "range is zero and a zero effect carries no information about this " + ...
        "factor rather than evidence that the factor is inert";
    return
end
if ~isfinite(estimate)
    category = "insufficient_information";
    reason = "the main effect is undefined; the design has no run at one " + ...
        "of this factor's two levels with a finite response";
    return
end
if supported < options.MinimumSupportedRuns
    category = "insufficient_information";
    reason = "only " + string(supported) + " design run(s) produced a " + ...
        "finite value for this response, below the floor of " + ...
        string(options.MinimumSupportedRuns);
    return
end

% 2. interaction_suspected - two triggers, either sufficient.
if mainEffectsAliased
    category = "interaction_suspected";
    reason = "the design's resolution aliases main effects with two-factor " + ...
        "interactions, so this estimate is not this factor's effect alone " + ...
        "and no magnitude computed from it can be read as leverage";
    return
end
if isfinite(peakEstimate) && abs(peakEstimate) > 0 && ...
        abs(peakEstimate) >= options.InteractionRatio * abs(estimate)
    category = "interaction_suspected";
    reason = "an interaction estimate involving this factor has magnitude " + ...
        sprintf("%.4g against a main effect of %.4g", ...
        abs(peakEstimate), abs(estimate)) + ", at or above the " + ...
        sprintf("%.2f", options.InteractionRatio) + " share the " + ...
        "convention treats as competing with the main effect";
    return
end

% 3-5. magnitude relative to the response's own spread.
if ratio >= options.HighLeverageRatio
    category = "high_leverage";
elseif ratio >= options.ModerateLeverageRatio
    category = "moderate_leverage";
else
    category = "low_leverage";
end
reason = sprintf("|effect| / response range = %.4g", ratio);
end

function [label, estimate, unique, aliasedWith] = strongestInteraction( ...
    interactionRows, effect, letter)
%STRONGESTINTERACTION The largest two-factor estimate this factor appears in.
%
% Matched on the effect LABEL's letters, not on the factor name: an interaction
% is labelled by the two design letters it multiplies, and a name-based match
% would break on any factor whose name contains another's.
label = "";
estimate = NaN;
unique = true;
aliasedWith = "";
if height(interactionRows) == 0 || strlength(letter) ~= 1
    return
end
selected = interactionRows(contains(interactionRows.effect, letter) & ...
    sameIdentity(interactionRows, effect), :);
if height(selected) == 0
    return
end
magnitudes = abs(selected.estimate);
if all(~isfinite(magnitudes))
    return
end
magnitudes(~isfinite(magnitudes)) = -Inf;
[~, at] = max(magnitudes);
label = selected.effect(at);
estimate = selected.estimate(at);
unique = logical(selected.is_uniquely_attributable(at));
aliasedWith = string(selected.aliased_with(at));
end

function mask = sameIdentity(rows, effect)
mask = rows.response == effect.response & ...
    rows.qualifier_kind == effect.qualifier_kind & ...
    rows.qualifier == effect.qualifier & ...
    rows.secondary_kind == effect.secondary_kind & ...
    rows.secondary == effect.secondary;
end

function value = directionOf(estimate, category, mainEffectsAliased)
%DIRECTIONOF The sign, stated only where it is interpretable.
%
% Withheld when the category says the estimate cannot be read as this factor's
% effect. A direction reported beside `insufficient_information` would be the one
% number a reader takes away from a row that says there is nothing to take.
if category == "insufficient_information" || mainEffectsAliased
    value = "not_interpretable";
    return
end
if ~isfinite(estimate) || estimate == 0
    value = "flat";
    return
end
if estimate > 0
    value = "increases_with_parameter";
    return
end
value = "decreases_with_parameter";
end

% ----------------------------------------------------- inactive factors ---

function rows = inactiveFactorRows(resolution, design, categorised)
%INACTIVEFACTORROWS A factor that was never screened still gets a row.
%
% Contract §H names an inactive factor as `insufficient_information`. Leaving it
% out instead would make the concordance table short in a way that reads as
% agreement: two probes that both omit a factor look like two probes that agree
% about it.
rows = emptyCategories();
if isempty(fieldnames(resolution)) || ~isfield(resolution, "factors")
    return
end
factors = resolution.factors;
if ~ismember("is_active", string(factors.Properties.VariableNames))
    return
end
inactive = factors(~factors.is_active, :);
if height(inactive) == 0 || height(categorised) == 0
    return
end

identities = unique(categorised(:, ["response", "qualifier_kind", ...
    "qualifier", "secondary_kind", "secondary", "value_kind"]), "rows");
for factorIndex = 1:height(inactive)
    name = inactive.factor_name(factorIndex);
    if ismember(name, categorised.factor_name)
        continue
    end
    detail = inactiveDetail(inactive(factorIndex, :));
    for index = 1:height(identities)
        identity = identities(index, :);
        rows(end + 1, :) = {identity.response, identity.qualifier_kind, ...
            identity.qualifier, identity.secondary_kind, identity.secondary, ...
            identity.value_kind, name, "", NaN, NaN, NaN, NaN, NaN, ...
            "insufficient_information", detail, "not_interpretable", ...
            strictnessOf(design, name), redundantIn(resolution, name), ...
            0, 0, "", NaN, NaN, true, "", false, "", true, false}; %#ok<AGROW>
    end
end
end

function value = inactiveDetail(row)
value = "the factor was not screened, so this probe says nothing about it";
if ismember("inactive_reason", string(row.Properties.VariableNames)) && ...
        strlength(row.inactive_reason) > 0
    value = value + " (" + string(row.inactive_reason) + ")";
end
end

% -------------------------------------------------------------- plumbing ---

function value = aliasedMainEffects(design)
%ALIASEDMAINEFFECTS Whether the design confounds main effects with interactions.
%
% Read from the alias structure rather than from the resolution number alone, so
% a design whose table says a particular main effect is not uniquely attributable
% is believed even if its resolution label suggests otherwise.
alias = design.alias;
if isfield(alias, "main_effects_clear_of_two_factor_interactions")
    value = ~logical(alias.main_effects_clear_of_two_factor_interactions);
    return
end
value = isfield(alias, "resolution") && isfinite(alias.resolution) && ...
    alias.resolution < 4;
end

function value = factorNameFor(design, letter, fallback)
match = design.factors.design_letter == letter;
if any(match)
    value = string(design.factors.factor_name(find(match, 1)));
    return
end
value = string(fallback);
end

function value = redundantIn(resolution, factorName)
%REDUNDANTIN Whether Part 4 flagged this factor as redundant with another.
%
% Carried through rather than re-derived. Part 4 computes redundancy from the
% metric correlation surface, and a second judgement here would be a second
% definition of the same thing - EXP-011 records two fixture factors correlating
% at 0.997, which is exactly the case where two implementations could disagree.
%
% The itinerary asks which factors each probe found weak OR REDUNDANT. Weakness
% is this layer's own judgement; redundancy is not, and the flag says which.
value = false;
if isempty(fieldnames(resolution)) || ~isfield(resolution, "factors")
    return
end
factors = resolution.factors;
if ~ismember("flagged_redundant", string(factors.Properties.VariableNames))
    return
end
match = factors.factor_name == factorName;
if any(match)
    value = logical(factors.flagged_redundant(find(match, 1)));
end
end

function value = strictnessOf(design, factorName)
value = "";
if ~ismember("strictness_direction", ...
        string(design.factors.Properties.VariableNames))
    return
end
match = design.factors.factor_name == factorName;
if any(match)
    value = string(design.factors.strictness_direction(find(match, 1)));
end
end

function value = categoryCounts(rows)
categories = edaLeverageCategories();
counts = zeros(numel(categories), 1);
for index = 1:numel(categories)
    counts(index) = nnz(rows.category == categories(index));
end
value = table(categories, counts, ...
    VariableNames=["category", "factor_response_pairs"]);
end

function value = probeRole(design)
value = "whole_dataset";
if isfield(design, "probe_role")
    value = string(design.probe_role);
end
end

function value = explorationKey(effects)
value = "";
if isfield(effects, "exploration_run_key")
    value = string(effects.exploration_run_key);
end
end

function value = categoryNames()
value = ["response", "qualifier_kind", "qualifier", "secondary_kind", ...
    "secondary", "value_kind", "factor_name", "design_letter", ...
    "main_effect", "response_range", "response_minimum", "response_maximum", ...
    "effect_ratio", "category", "category_reason", "direction", ...
    "strictness_direction", "factor_flagged_redundant", "supported_runs", ...
    "configuration_count", ...
    "strongest_interaction", "strongest_interaction_estimate", ...
    "interaction_to_main_ratio", "interaction_is_uniquely_attributable", ...
    "interaction_aliased_with", "main_effects_are_aliased", ...
    "main_effect_aliased_with", "main_effect_is_uniquely_attributable", ...
    "design_is_complete"];
end

function value = emptyCategories()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    false(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), false(0, 1), strings(0, 1), false(0, 1), strings(0, 1), ...
    false(0, 1), false(0, 1), VariableNames=categoryNames());
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:LeverageInputInvalid", ...
        "A required input is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
