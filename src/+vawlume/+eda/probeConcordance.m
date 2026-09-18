function result = probeConcordance(screenLeverage, subsetLeverage, options)
%PROBECONCORDANCE Compare the two sensitivity probes, factor by factor, response
%by response.
%
% RESULT = vawlume.eda.PROBECONCORDANCE(SCREENLEVERAGE, SUBSETLEVERAGE) takes two
% vawlume.eda.leverageCategories results - the whole-dataset screen and the
% subset probe - and returns a table a scientist reads row by row: where the two
% probes agree on leverage category, where they agree on the direction of an
% effect, which exact support patterns moved most in each, and where either probe
% can say nothing at all.
%
% Name-value options:
%   ScreenResponses / SubsetResponses   the vawlume.eda.screenResponses results.
%                                       Supplying them adds each support
%                                       pattern's observed group-count range to
%                                       the movement table, read off the response
%                                       rows rather than recomputed
%   TopPatterns                         how many moved-most patterns to compare,
%                                       default 5
%
% A TABLE, NOT A NUMBER. There is no concordance score, no agreement fraction, no
% ranking, and no recommended configuration - not as a default and not behind a
% flag. Contract §H and boundary 2 forbid a composite, and the reason is that a
% single number would be read as "the probes agree, so the screen is sound", which
% is precisely the inference this MVP cannot support. A contingency table of one
% probe's categories against the other's is included because it is a table: it
% shows where the mass sits without collapsing it.
%
% DISAGREEMENT IS INFORMATIVE, NOT ERROR. The two probes differ in BOTH design
% and dataset, so a divergence has at least three readings: the compact screen is
% misleading, the subset is unrepresentative, or the effect genuinely varies
% across recordings. Every disagreeing row carries those candidate explanations
% and this function adjudicates between none of them.
%
% A FACTOR MISSING FROM EITHER PROBE IS REFUSED. If one probe screened a factor
% the other did not, the concordance table would simply be short - and a short
% table reads as agreement rather than as the design failure it is. Responses are
% different: a support pattern observed in one probe and not the other is a real
% finding about the data, so those rows are reported with `presence` rather than
% refused.
%
% THE LIMIT OF ANY FINDING HERE, carried in RESULT.calibration_note and asserted
% by test: strong agreement between the two probes is informative but does NOT
% establish that manual calibration is unnecessary. It is the single most likely
% over-reading of this entire MVP.
%
% This function is pure. It selects no configuration and recommends nothing.

arguments
    screenLeverage (1,1) struct
    subsetLeverage (1,1) struct
    options.ScreenResponses struct = struct([])
    options.SubsetResponses struct = struct([])
    options.TopPatterns (1,1) double {mustBePositive} = 5
end

requireFields(screenLeverage, ["categories", "category_vocabulary"]);
requireFields(subsetLeverage, ["categories", "category_vocabulary"]);

screen = screenLeverage.categories;
subset = subsetLeverage.categories;
assertSameFactors(screen, subset);

rows = compareRows(screen, subset);
movement = patternMovement(options, rows);

result = struct( ...
    status="compared", ...
    screen_probe_role=roleOf(screenLeverage, "whole_dataset"), ...
    subset_probe_role=roleOf(subsetLeverage, "subset"), ...
    screen_design_type=fieldOr(screenLeverage, "design_type", ""), ...
    subset_design_type=fieldOr(subsetLeverage, "design_type", ""), ...
    screen_resolution_label=fieldOr(screenLeverage, "resolution_label", ""), ...
    subset_resolution_label=fieldOr(subsetLeverage, "resolution_label", ""), ...
    comparison=rows, ...
    category_vocabulary=edaLeverageCategories(), ...
    category_contingency=contingency(rows), ...
    factor_summary=factorSummary(rows), ...
    weak_or_aliased_factors=weakOrAliased(rows, screen, subset), ...
    support_pattern_movement=movement, ...
    divergence_explanations=explanations(), ...
    comparison_rule="one row per factor per response identity; categories " + ...
        "and directions are compared as produced, never re-derived", ...
    cut_point_note=fieldOr(screenLeverage, "cut_point_note", ""), ...
    calibration_note=calibrationNote(), ...
    no_composite="no concordance score, agreement fraction, ranking, " + ...
        "recommendation or selected configuration is computed here or " + ...
        "anywhere downstream of it; the deliverable is the table", ...
    caution=edaCautionNote());
end

% ---------------------------------------------------------- factor parity ---

function assertSameFactors(screen, subset)
screenNames = unique(screen.factor_name);
subsetNames = unique(subset.factor_name);
if isequal(sort(screenNames), sort(subsetNames))
    return
end
onlyScreen = setdiff(screenNames, subsetNames);
onlySubset = setdiff(subsetNames, screenNames);
error("vawlume:eda:ProbeFactorsDiffer", ...
    "The two probes categorised different factor sets, so they cannot be " + ...
    "compared factor by factor.%s%s A factor present in one probe and " + ...
    "absent from the other produces no concordance row at all, and a short " + ...
    "table reads as agreement rather than as the design failure it is.", ...
    listPart(" Only in the screen: ", onlyScreen), ...
    listPart(" Only in the subset probe: ", onlySubset));
end

function value = listPart(prefix, names)
value = "";
if isempty(names)
    return
end
value = prefix + strjoin(names', ", ") + ".";
end

% -------------------------------------------------------- the comparison ---

function rows = compareRows(screen, subset)
%COMPAREROWS The union of both probes' factor-response pairs, outer-joined.
%
% The UNION rather than the intersection. A response one probe observed and the
% other did not - a support pattern that appears only on the subset's recordings,
% say - is a finding about the data, and dropping it would hide exactly the kind
% of difference the second probe exists to reveal.
keys = ["response", "qualifier_kind", "qualifier", "secondary_kind", ...
    "secondary", "factor_name"];
screenKey = joinKey(screen, keys);
subsetKey = joinKey(subset, keys);
allKeys = unique([screenKey; subsetKey]);

rows = emptyComparison();
for index = 1:numel(allKeys)
    key = allKeys(index);
    left = screen(screenKey == key, :);
    right = subset(subsetKey == key, :);
    rows(end + 1, :) = compareOne(left, right); %#ok<AGROW>
end
rows = sortrows(rows, ["response", "qualifier", "secondary", "factor_name"]);
end

function row = compareOne(left, right)
presence = "both";
if height(left) == 0
    presence = "subset_only";
elseif height(right) == 0
    presence = "screen_only";
end

identity = left;
if height(identity) == 0
    identity = right;
end

screenCategory = pick(left, "category", "not_observed");
subsetCategory = pick(right, "category", "not_observed");
screenDirection = pick(left, "direction", "not_observed");
subsetDirection = pick(right, "direction", "not_observed");

categoriesAgree = presence == "both" && screenCategory == subsetCategory;
directionsComparable = presence == "both" && ...
    isInterpretable(screenDirection) && isInterpretable(subsetDirection);
directionsAgree = directionsComparable && screenDirection == subsetDirection;

eitherUninformative = ismember("insufficient_information", ...
    [screenCategory, subsetCategory]);
eitherInteraction = ismember("interaction_suspected", ...
    [screenCategory, subsetCategory]);

row = {identity.response(1), identity.qualifier_kind(1), ...
    identity.qualifier(1), identity.secondary_kind(1), ...
    identity.secondary(1), identity.value_kind(1), ...
    identity.factor_name(1), presence, ...
    screenCategory, subsetCategory, categoriesAgree, ...
    screenDirection, subsetDirection, directionsComparable, directionsAgree, ...
    pickNumeric(left, "main_effect"), pickNumeric(right, "main_effect"), ...
    pickNumeric(left, "effect_ratio"), pickNumeric(right, "effect_ratio"), ...
    pickNumeric(left, "response_range"), pickNumeric(right, "response_range"), ...
    eitherUninformative, eitherInteraction, ...
    note(presence, categoriesAgree, directionsComparable, directionsAgree, ...
    eitherUninformative)};
row = cell2table(row, VariableNames=comparisonNames());
end

function value = isInterpretable(direction)
value = ~ismember(direction, ["not_interpretable", "not_observed"]);
end

function value = note(presence, categoriesAgree, directionsComparable, ...
    directionsAgree, eitherUninformative)
%NOTE What this row says, and - when the probes differ - what it does not say.
%
% The explanations are named, not chosen between. Adjudicating would require
% knowing whether the subset is representative, which is the thing the subset was
% drawn to make plausible and cannot itself establish.
if presence ~= "both"
    value = "Observed in one probe only. The two probes run on different " + ...
        "recordings, so a response absent from one is about the data, not " + ...
        "a fault: the category from the probe that observed it stands " + ...
        "alone and is not evidence about the other.";
    return
end
if eitherUninformative
    value = "At least one probe reports insufficient_information, so this " + ...
        "pair is not an agreement or a disagreement. Neither probe is " + ...
        "making a claim about this factor on this response.";
    return
end
if categoriesAgree && directionsComparable && directionsAgree
    value = "Both probes agree on category and on direction. Informative, " + ...
        "and NOT evidence that manual calibration is unnecessary.";
    return
end
if categoriesAgree
    value = "Categories agree; direction does not, or is not comparable in " + ...
        "both probes. Read the two main effects rather than the labels.";
    return
end
value = "The probes DIVERGE on category. Three readings are available and " + ...
    "this table chooses between none of them: the compact screen may be " + ...
    "misleading; the subset may be unrepresentative of the dataset; or the " + ...
    "effect may genuinely vary across recordings.";
end

% ------------------------------------------------------------- summaries ---

function value = contingency(rows)
%CONTINGENCY Where the mass sits, without collapsing it to a number.
categories = [edaLeverageCategories(); "not_observed"];
screenCategory = strings(0, 1);
subsetCategory = strings(0, 1);
pairs = zeros(0, 1);
for left = 1:numel(categories)
    for right = 1:numel(categories)
        count = nnz(rows.screen_category == categories(left) & ...
            rows.subset_category == categories(right));
        if count == 0
            continue
        end
        screenCategory(end + 1, 1) = categories(left); %#ok<AGROW>
        subsetCategory(end + 1, 1) = categories(right); %#ok<AGROW>
        pairs(end + 1, 1) = count; %#ok<AGROW>
    end
end
value = table(screenCategory, subsetCategory, pairs, ...
    VariableNames=["screen_category", "subset_category", ...
    "factor_response_pairs"]);
end

function value = factorSummary(rows)
%FACTORSUMMARY Per factor, the counts behind its rows - counts, never a score.
factors = unique(rows.factor_name);
agreeing = zeros(numel(factors), 1);
diverging = zeros(numel(factors), 1);
uninformative = zeros(numel(factors), 1);
interaction = zeros(numel(factors), 1);
oneProbeOnly = zeros(numel(factors), 1);
total = zeros(numel(factors), 1);
for index = 1:numel(factors)
    selected = rows(rows.factor_name == factors(index), :);
    total(index) = height(selected);
    oneProbeOnly(index) = nnz(selected.presence ~= "both");
    uninformative(index) = nnz(selected.either_insufficient_information);
    interaction(index) = nnz(selected.either_interaction_suspected);
    comparable = selected.presence == "both" & ...
        ~selected.either_insufficient_information;
    agreeing(index) = nnz(comparable & selected.categories_agree);
    diverging(index) = nnz(comparable & ~selected.categories_agree);
end
value = table(factors, total, agreeing, diverging, uninformative, ...
    interaction, oneProbeOnly, ...
    VariableNames=["factor_name", "response_pairs", ...
    "categories_agree_pairs", "categories_diverge_pairs", ...
    "either_insufficient_information_pairs", ...
    "either_interaction_suspected_pairs", "one_probe_only_pairs"]);
end

function value = weakOrAliased(rows, screen, subset)
%WEAKORALIASED Which factors each probe found weak, confounded, or redundant.
%
% WEAK is this layer's own judgement: every informative row for that factor sits
% in `low_leverage`. "Every" rather than "most", because a factor that is weak on
% one response and strong on another is not a weak factor - it is a factor whose
% leverage depends on what you are measuring, which is a finding the summary must
% not flatten.
%
% REDUNDANT is not this layer's judgement at all. It is Part 4's, computed from
% the metric correlation surface and carried through unchanged; a second
% definition here would eventually disagree with it. EXP-011 records two fixture
% factors correlating at 0.997, which is exactly where two implementations would
% diverge.
factors = unique(rows.factor_name);
screenWeak = false(numel(factors), 1);
subsetWeak = false(numel(factors), 1);
screenAliased = false(numel(factors), 1);
subsetAliased = false(numel(factors), 1);
redundant = false(numel(factors), 1);
for index = 1:numel(factors)
    selected = rows(rows.factor_name == factors(index), :);
    informative = ~selected.either_insufficient_information;
    screenWeak(index) = any(informative) && ...
        all(selected.screen_category(informative) == "low_leverage");
    subsetWeak(index) = any(informative) && ...
        all(selected.subset_category(informative) == "low_leverage");
    screenAliased(index) = any(selected.screen_category == ...
        "interaction_suspected");
    subsetAliased(index) = any(selected.subset_category == ...
        "interaction_suspected");
    redundant(index) = redundantFlag(screen, factors(index)) || ...
        redundantFlag(subset, factors(index));
end
value = table(factors, screenWeak, subsetWeak, screenAliased, subsetAliased, ...
    screenWeak == subsetWeak, redundant, ...
    VariableNames=["factor_name", "screen_found_weak", "subset_found_weak", ...
    "screen_suspected_interaction", "subset_suspected_interaction", ...
    "probes_agree_on_weakness", "flagged_redundant_upstream"]);
end

function value = redundantFlag(categories, factorName)
value = false;
if ~ismember("factor_flagged_redundant", ...
        string(categories.Properties.VariableNames))
    return
end
selected = categories.factor_flagged_redundant( ...
    categories.factor_name == factorName);
value = ~isempty(selected) && any(logical(selected));
end

% ---------------------------------------------- support-pattern movement ---

function value = patternMovement(options, rows)
%PATTERNMOVEMENT Which EXACT support patterns moved most in each probe.
%
% Movement is the pattern's own range across the design - max minus min of its
% group count - which is the quantity already reported beside every effect. The
% patterns are exact `supported_extractor_pair_pattern` strings throughout and
% are never binned by a coarse supported-pair count: two patterns can both
% support two of three pairs while supporting DIFFERENT pairs, and comparing the
% probes on the coarse count would report agreement that was never observed.
screen = movementFrom(rows, "screen_response_range", options.TopPatterns);
subset = movementFrom(rows, "subset_response_range", options.TopPatterns);

patterns = unique([screen.qualifier; subset.qualifier]);
inScreen = ismember(patterns, screen.qualifier);
inSubset = ismember(patterns, subset.qualifier);
value = struct( ...
    top_count=options.TopPatterns, ...
    movement_definition="the pattern's group count at its maximum minus " + ...
        "its minimum across that probe's design runs", ...
    screen_top=screen, ...
    subset_top=subset, ...
    comparison=table(patterns, inScreen, inSubset, inScreen & inSubset, ...
        VariableNames=["support_pattern", "in_screen_top", ...
        "in_subset_top", "in_both"]), ...
    patterns_in_both=patterns(inScreen & inSubset)', ...
    observed_counts=observedCounts(options), ...
    exactness="patterns are exact supported_extractor_pair_pattern values " + ...
        "and are never binned by a coarse supported-pair count");
end

function value = observedCounts(options)
%OBSERVEDCOUNTS Each pattern's pooled group count, at its lowest and highest.
%
% Movement alone says how far a pattern's count travelled; this says between
% which values. Part 11 reports support-pattern characterization against a
% threshold context and needs the observed range, not only its width - a pattern
% that moved from 40 to 46 and one that moved from 1 to 7 have the same movement
% and are not the same finding.
%
% Empty when the response tables are not supplied, because this is read off them
% rather than re-derived: a second count here would be a second implementation of
% the response, which is the thing this part must not have.
value = emptyObserved();
value = [value; observedFrom(options.ScreenResponses, "whole_dataset")];
value = [value; observedFrom(options.SubsetResponses, "subset")];
end

function value = observedFrom(responses, probeRole)
value = emptyObserved();
if isempty(fieldnames(responses)) || ~isfield(responses, "responses")
    return
end
rows = responses.responses;
selected = rows(rows.response == "support_pattern_groups" & ...
    rows.scope == "pooled" & isfinite(rows.value), :);
if height(selected) == 0
    return
end
[patterns, ~, grouping] = unique(selected.qualifier);
lowest = accumarray(grouping, selected.value, [], @min);
highest = accumarray(grouping, selected.value, [], @max);
value = table(repmat(probeRole, numel(patterns), 1), patterns, ...
    lowest, highest, highest - lowest, ...
    VariableNames=["probe_role", "support_pattern", "lowest_group_count", ...
    "highest_group_count", "observed_movement"]);
end

function value = emptyObserved()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), VariableNames=["probe_role", "support_pattern", ...
    "lowest_group_count", "highest_group_count", "observed_movement"]);
end

function value = movementFrom(rows, column, top)
selected = rows(rows.response == "support_pattern_groups" & ...
    rows.qualifier_kind == "support_pattern" & ...
    isfinite(rows.(column)), :);
if height(selected) == 0
    value = emptyMovement();
    return
end
[patterns, ~, grouping] = unique(selected.qualifier);
ranges = accumarray(grouping, selected.(column), [], @max);
ranked = sortrows(table(patterns, ranges, ...
    VariableNames=["qualifier", "movement"]), ...
    ["movement", "qualifier"], {'descend', 'ascend'});
value = ranked(1:min(top, height(ranked)), :);
end

function value = emptyMovement()
value = table(strings(0, 1), zeros(0, 1), ...
    VariableNames=["qualifier", "movement"]);
end

% -------------------------------------------------------------- plumbing ---

function value = explanations()
value = [ ...
    "The compact whole-dataset screen may be misleading, because its " + ...
        "fraction aliases effects the subset probe can separate."; ...
    "The subset may be unrepresentative of the dataset, because it is " + ...
        "small and was drawn to be reproducible rather than to be " + ...
        "sufficient."; ...
    "The effect may genuinely vary across recordings, in which case both " + ...
        "probes are right about their own data."];
end

function value = calibrationNote()
value = "Agreement between the two sensitivity probes is informative, but " + ...
    "it does NOT establish that manual calibration is unnecessary. The " + ...
    "probes share every assumption of the matching and agreement layers, " + ...
    "so they cannot detect an error common to both, and neither probe " + ...
    "observes ground truth at any point.";
end

function value = joinKey(rows, keys)
value = strings(height(rows), 1);
for index = 1:numel(keys)
    value = value + string(rows.(keys(index))) + char(31);
end
end

function value = pick(rows, column, fallback)
value = string(fallback);
if height(rows) > 0
    value = string(rows.(column)(1));
end
end

function value = pickNumeric(rows, column)
value = NaN;
if height(rows) > 0
    value = double(rows.(column)(1));
end
end

function value = roleOf(leverage, fallback)
value = string(fallback);
if isfield(leverage, "probe_role")
    value = string(leverage.probe_role);
end
end

function value = fieldOr(source, name, fallback)
value = string(fallback);
if isfield(source, name)
    value = string(source.(name));
end
end

function value = comparisonNames()
value = ["response", "qualifier_kind", "qualifier", "secondary_kind", ...
    "secondary", "value_kind", "factor_name", "presence", ...
    "screen_category", "subset_category", "categories_agree", ...
    "screen_direction", "subset_direction", "directions_comparable", ...
    "directions_agree", "screen_main_effect", "subset_main_effect", ...
    "screen_effect_ratio", "subset_effect_ratio", "screen_response_range", ...
    "subset_response_range", "either_insufficient_information", ...
    "either_interaction_suspected", "reading"];
end

function value = emptyComparison()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), false(0, 1), strings(0, 1), ...
    strings(0, 1), false(0, 1), false(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
    false(0, 1), strings(0, 1), VariableNames=comparisonNames());
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:ConcordanceInputInvalid", ...
        "A required input is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
