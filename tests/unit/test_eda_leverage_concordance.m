function tests = test_eda_leverage_concordance
%TEST_EDA_LEVERAGE_CONCORDANCE Contract §H categorisation and the two-probe table.
%
% Unit tier, against constructed effect tables. Both functions are pure given an
% effect table and a design, and constructing the tables directly is what makes
% it possible to put a value exactly on a cut point, or to build a response that
% is constant across the whole design, without arranging for real data to
% cooperate.
tests = functiontests({ ...
    @testEachCategoryIsProducedByItsOwnEffectTable, ...
    @testAConstantResponseIsInsufficientInformationForEveryFactor, ...
    @testAConstantResponseIsNotLowLeverageEvenWithAZeroEffect, ...
    @testAnUndefinedEstimateIsInsufficientInformation, ...
    @testTooFewSupportedRunsIsInsufficientInformation, ...
    @testAnInactiveFactorGetsARowRatherThanBeingOmitted, ...
    @testTheInteractionTriggerFiresOnAnInteractionEstimate, ...
    @testTheAliasTriggerFiresFromTheDesignAloneAtResolutionThree, ...
    @testTheAliasTriggerDoesNotFireAtResolutionFour, ...
    @testAZeroInteractionBesideAZeroEffectIsNotInteractionSuspected, ...
    @testCutPointsBehaveAtTheirBoundaries, ...
    @testInsufficientInformationOutranksTheInteractionTrigger, ...
    @testDirectionIsWithheldWhereItIsNotInterpretable, ...
    @testAnAliasedInteractionIsFlaggedAsAnAliasedSum, ...
    @testConcordanceReportsAgreementAndDivergencePerFactorPerResponse, ...
    @testConcordanceRefusesProbesWithDifferentFactorSets, ...
    @testAResponseSeenByOneProbeOnlyIsReportedNotDropped, ...
    @testDirectionAgreementIsOnlyClaimedWhereBothAreInterpretable, ...
    @testSupportPatternMovementComparesExactPatterns, ...
    @testNoCompositeScoreAppearsInAnyReturnedFieldName, ...
    @testTheCalibrationCautionTravelsWithTheOutput});
end

% ------------------------------------------------------- the five categories ---

function testEachCategoryIsProducedByItsOwnEffectTable(testCase)
% One constructed table per category, so no category is reached only as a
% fall-through from another's failure.
cases = { ...
    "high_leverage",            0.80, 1.00, 0.00; ...
    "moderate_leverage",        0.30, 1.00, 0.00; ...
    "low_leverage",             0.05, 1.00, 0.00; ...
    "interaction_suspected",    0.80, 1.00, 0.60; ...
    "insufficient_information", 0.00, 0.00, 0.00};

for index = 1:size(cases, 1)
    expected = cases{index, 1};
    effects = effectTable(struct(estimate=cases{index, 2}, ...
        range=cases{index, 3}, interaction=cases{index, 4}));
    result = vawlume.eda.leverageCategories(effects, designAt(4));
    verifyEqual(testCase, result.categories.category, expected, ...
        "Case " + index + " produced the wrong category.");
end

verifyEqual(testCase, sort(unique(edaCategoryVocabulary())), ...
    sort(["insufficient_information"; "interaction_suspected"; ...
    "high_leverage"; "moderate_leverage"; "low_leverage"]));
end

% -------------------------- the highest-consequence misclassification ---

function testAConstantResponseIsInsufficientInformationForEveryFactor(testCase)
%TESTACONSTANTRESPONSEIS... The defect that would report every factor as inert.
%
% Verified as a negative result: an implementation that categorises by |effect| /
% range alone - guarding only against division by zero and treating the result as
% 0 - returns `low_leverage` here for all four factors and this test fails. Part
% 8's handoff records that `detections_considered` is exactly this case on every
% real probe, because it is the denominator rather than a response to a
% threshold, so the wrong answer would appear in every run the workflow ever
% makes.
effects = fourFactorTable(zeros(1, 4), 0, zeros(1, 6));
result = vawlume.eda.leverageCategories(effects, designAt(4));

verifyEqual(testCase, height(result.categories), 4);
verifyTrue(testCase, all(result.categories.category == ...
    "insufficient_information"));
verifyTrue(testCase, all(result.categories.response_range == 0));
verifyTrue(testCase, all(contains(result.categories.category_reason, ...
    "constant across every configuration")));

% And the counts table agrees, so a consumer reading the summary is not told
% something different from the rows.
counts = result.category_counts;
verifyEqual(testCase, counts.factor_response_pairs( ...
    counts.category == "insufficient_information"), 4);
verifyEqual(testCase, counts.factor_response_pairs( ...
    counts.category == "low_leverage"), 0);
end

function testAConstantResponseIsNotLowLeverageEvenWithAZeroEffect(testCase)
%TESTACONSTANTRESPONSEISNOTLOWLEVERAGE... Stated as its own assertion.
%
% The previous test would still pass if `insufficient_information` were produced
% for the wrong reason. This one names the specific wrong answer and rules it
% out, because "zero effect over zero range" is exactly the shape that invites
% the ratio rules to be applied with a guard rather than skipped.
effects = effectTable(struct(estimate=0, range=0, interaction=0));
result = vawlume.eda.leverageCategories(effects, designAt(4));

verifyNotEqual(testCase, result.categories.category, "low_leverage");
verifyNotEqual(testCase, result.categories.category, "moderate_leverage");
verifyNotEqual(testCase, result.categories.category, "high_leverage");
verifyEqual(testCase, result.categories.category, "insufficient_information");
verifyTrue(testCase, isnan(result.categories.effect_ratio));
end

function testAnUndefinedEstimateIsInsufficientInformation(testCase)
effects = effectTable(struct(estimate=NaN, range=2, interaction=0));
result = vawlume.eda.leverageCategories(effects, designAt(4));
verifyEqual(testCase, result.categories.category, "insufficient_information");
verifySubstring(testCase, result.categories.category_reason, "undefined");
end

function testTooFewSupportedRunsIsInsufficientInformation(testCase)
effects = effectTable(struct(estimate=0.9, range=1, interaction=0, ...
    highRuns=1, lowRuns=0));
result = vawlume.eda.leverageCategories(effects, designAt(4));
verifyEqual(testCase, result.categories.category, "insufficient_information");
verifySubstring(testCase, result.categories.category_reason, "below the floor");

% Raising the floor turns an otherwise-high row uninformative, which is what
% makes the floor a stated convention rather than a hidden constant.
plenty = effectTable(struct(estimate=0.9, range=1, interaction=0, ...
    highRuns=4, lowRuns=4));
verifyEqual(testCase, ...
    vawlume.eda.leverageCategories(plenty, designAt(4)).categories.category, ...
    "high_leverage");
verifyEqual(testCase, vawlume.eda.leverageCategories(plenty, designAt(4), ...
    MinimumSupportedRuns=9).categories.category, ...
    "insufficient_information");
end

function testAnInactiveFactorGetsARowRatherThanBeingOmitted(testCase)
%TESTANINACTIVEFACTORGETSAROW... Absence would read as agreement downstream.
effects = effectTable(struct(estimate=0.8, range=1, interaction=0));
resolution = struct(factors=table( ...
    ["min_temporal_iou"; "max_abs_onset_delta_s"], ...
    [true; false], ["", "the metric placed no quantile"]', ...
    VariableNames=["factor_name", "is_active", "inactive_reason"]));

result = vawlume.eda.leverageCategories(effects, designAt(4), ...
    Resolution=resolution);
rows = result.categories;
verifyEqual(testCase, height(rows), 2);

inactive = rows(rows.factor_name == "max_abs_onset_delta_s", :);
verifyEqual(testCase, inactive.category, "insufficient_information");
verifySubstring(testCase, inactive.category_reason, "was not screened");
verifySubstring(testCase, inactive.category_reason, "placed no quantile");
verifyEqual(testCase, inactive.direction, "not_interpretable");
end

% ------------------------------------- the two interaction_suspected triggers ---

function testTheInteractionTriggerFiresOnAnInteractionEstimate(testCase)
%TESTTHEINTERACTIONTRIGGERFIRES... Trigger one, from the numbers.
%
% A main effect of 0.80 over a range of 1.00 is squarely high_leverage on
% magnitude alone. An interaction of 0.60 - at or above half the main effect -
% takes precedence, because the factor's effect is not separable from its
% partner's at that size.
effects = effectTable(struct(estimate=0.80, range=1.00, interaction=0.60));
result = vawlume.eda.leverageCategories(effects, designAt(4));
row = result.categories;

verifyEqual(testCase, row.category, "interaction_suspected");
verifyEqual(testCase, row.strongest_interaction, "AB");
verifyEqual(testCase, row.strongest_interaction_estimate, 0.60);
verifyEqual(testCase, row.interaction_to_main_ratio, 0.75, AbsTol=1e-12);
verifyFalse(testCase, row.main_effects_are_aliased);
verifySubstring(testCase, row.category_reason, "interaction estimate");
end

function testTheAliasTriggerFiresFromTheDesignAloneAtResolutionThree(testCase)
%TESTTHEALIASTRIGGERFIRESFROMTHEDESIGNALONE... Trigger two, from the design.
%
% Verified as a negative result: an implementation that ignores the alias
% structure and categorises on magnitude alone returns `high_leverage` here and
% this test fails. That is the defect that would have a resolution-III screen
% report unearned confidence about a main effect it cannot attribute - and
% nothing in the numbers would reveal it, because the estimate looks exactly like
% a clean large effect.
%
% No interaction estimate is present at all, so the trigger can only have come
% from the design.
effects = effectTable(struct(estimate=0.90, range=1.00, interaction=0));
result = vawlume.eda.leverageCategories(effects, designAt(3));
row = result.categories;

verifyEqual(testCase, row.category, "interaction_suspected");
verifyTrue(testCase, row.main_effects_are_aliased);
verifyTrue(testCase, isnan(row.strongest_interaction_estimate));
verifySubstring(testCase, row.category_reason, "aliases main effects");
verifyEqual(testCase, row.direction, "not_interpretable");

% The same numbers at resolution IV are high_leverage, so the difference is
% attributable to the design and to nothing else.
verifyEqual(testCase, ...
    vawlume.eda.leverageCategories(effects, designAt(4)).categories.category, ...
    "high_leverage");
end

function testTheAliasTriggerDoesNotFireAtResolutionFour(testCase)
% At resolution IV main effects are clear of two-factor interactions, so the
% design-side trigger must stay silent or every resolution-IV screen would report
% every factor as confounded.
effects = effectTable(struct(estimate=0.90, range=1.00, interaction=0));
for resolution = [4 5]
    result = vawlume.eda.leverageCategories(effects, designAt(resolution));
    verifyFalse(testCase, result.categories.main_effects_are_aliased);
    verifyEqual(testCase, result.categories.category, "high_leverage");
end
end

function testAZeroInteractionBesideAZeroEffectIsNotInteractionSuspected(testCase)
%TESTAZEROINTERACTIONBESIDEAZEROEFFECT... The 0 >= 0.5 x 0 trap.
%
% Contract §H's rule reads "magnitude >= 0.5 x |effect|". Taken literally, a
% factor with no effect and no interaction satisfies it - zero is not less than
% zero - and every inert factor on a varying response would be reported as
% interaction_suspected. The interaction must itself be nonzero for the trigger
% to mean anything.
effects = effectTable(struct(estimate=0, range=2, interaction=0));
result = vawlume.eda.leverageCategories(effects, designAt(4));

verifyEqual(testCase, result.categories.category, "low_leverage");
verifyEqual(testCase, result.categories.effect_ratio, 0);

% A nonzero interaction beside a zero main effect DOES fire: the factor moves
% the response only in combination, which is exactly what the category says.
combined = effectTable(struct(estimate=0, range=2, interaction=0.4));
verifyEqual(testCase, ...
    vawlume.eda.leverageCategories(combined, designAt(4)).categories.category, ...
    "interaction_suspected");
end

function testCutPointsBehaveAtTheirBoundaries(testCase)
% Just inside and just outside each cut point. The boundaries are inclusive
% below, per contract §H's ">=" in both rules.
range = 1.0;
expectations = { ...
    0.50,        "high_leverage"; ...
    0.50 - 1e-9, "moderate_leverage"; ...
    0.20,        "moderate_leverage"; ...
    0.20 - 1e-9, "low_leverage"};
for index = 1:size(expectations, 1)
    effects = effectTable(struct(estimate=expectations{index, 1}, ...
        range=range, interaction=0));
    result = vawlume.eda.leverageCategories(effects, designAt(4));
    verifyEqual(testCase, result.categories.category, ...
        expectations{index, 2}, ...
        "Ratio " + expectations{index, 1} + " classified wrongly.");
end

% Negative effects classify on magnitude, not on sign.
negative = effectTable(struct(estimate=-0.8, range=1, interaction=0));
result = vawlume.eda.leverageCategories(negative, designAt(4));
verifyEqual(testCase, result.categories.category, "high_leverage");
verifyEqual(testCase, result.categories.direction, "decreases_with_parameter");

verifyError(testCase, @() vawlume.eda.leverageCategories( ...
    effectTable(struct(estimate=0.5, range=1, interaction=0)), designAt(4), ...
    HighLeverageRatio=0.2, ModerateLeverageRatio=0.5), ...
    "vawlume:eda:LeverageCutPointsInverted");
end

function testInsufficientInformationOutranksTheInteractionTrigger(testCase)
% Precedence, asserted where the two could both apply: a constant response with
% a large interaction estimate beside it is still no information.
effects = effectTable(struct(estimate=0, range=0, interaction=5));
result = vawlume.eda.leverageCategories(effects, designAt(3));
verifyEqual(testCase, result.categories.category, "insufficient_information");
end

function testDirectionIsWithheldWhereItIsNotInterpretable(testCase)
positive = effectTable(struct(estimate=0.8, range=1, interaction=0));
verifyEqual(testCase, vawlume.eda.leverageCategories(positive, ...
    designAt(4)).categories.direction, "increases_with_parameter");

constant = effectTable(struct(estimate=0, range=0, interaction=0));
verifyEqual(testCase, vawlume.eda.leverageCategories(constant, ...
    designAt(4)).categories.direction, "not_interpretable");

aliased = effectTable(struct(estimate=0.8, range=1, interaction=0));
verifyEqual(testCase, vawlume.eda.leverageCategories(aliased, ...
    designAt(3)).categories.direction, "not_interpretable");
end

function testAnAliasedInteractionIsFlaggedAsAnAliasedSum(testCase)
%TESTANALIASEDINTERACTIONISFLAGGED... "AB interacts" and "AB or CD" differ.
effects = effectTable(struct(estimate=0.8, range=1, interaction=0.6, ...
    interactionUnique=false, interactionAlias="CD"));
row = vawlume.eda.leverageCategories(effects, designAt(4)).categories;

verifyEqual(testCase, row.category, "interaction_suspected");
verifyFalse(testCase, row.interaction_is_uniquely_attributable);
verifyEqual(testCase, row.interaction_aliased_with, "CD");

clean = effectTable(struct(estimate=0.8, range=1, interaction=0.6, ...
    interactionUnique=true, interactionAlias=""));
verifyTrue(testCase, vawlume.eda.leverageCategories(clean, ...
    designAt(4)).categories.interaction_is_uniquely_attributable);
end

% --------------------------------------------------------- concordance ---

function testConcordanceReportsAgreementAndDivergencePerFactorPerResponse(testCase)
screen = leverageFrom([0.80 0.05], ["r_one" "r_two"], "whole_dataset");
subset = leverageFrom([0.80 0.60], ["r_one" "r_two"], "subset");
result = vawlume.eda.probeConcordance(screen, subset);

rows = result.comparison;
verifyEqual(testCase, height(rows), 2);

agreeing = rows(rows.response == "r_one", :);
verifyEqual(testCase, agreeing.presence, "both");
verifyEqual(testCase, agreeing.screen_category, "high_leverage");
verifyEqual(testCase, agreeing.subset_category, "high_leverage");
verifyTrue(testCase, agreeing.categories_agree);
verifyTrue(testCase, agreeing.directions_agree);

diverging = rows(rows.response == "r_two", :);
verifyEqual(testCase, diverging.screen_category, "low_leverage");
verifyEqual(testCase, diverging.subset_category, "high_leverage");
verifyFalse(testCase, diverging.categories_agree);

% Divergence is presented with its candidate readings and adjudicated by none.
verifySubstring(testCase, diverging.reading, "DIVERGE");
verifySubstring(testCase, diverging.reading, "chooses between none");
verifyEqual(testCase, numel(result.divergence_explanations), 3);
verifySubstring(testCase, strjoin(result.divergence_explanations, " "), ...
    "unrepresentative");
verifySubstring(testCase, strjoin(result.divergence_explanations, " "), ...
    "genuinely vary across recordings");

% The contingency table is a table of counts, and it sums to the rows.
verifyEqual(testCase, sum(result.category_contingency.factor_response_pairs), 2);
end

function testConcordanceRefusesProbesWithDifferentFactorSets(testCase)
%TESTCONCORDANCEREFUSES... A short table would read as agreement.
screen = leverageFrom(0.8, "r_one", "whole_dataset");
subset = leverageFrom(0.8, "r_one", "subset");
subset.categories.factor_name(:) = "a_different_factor";

verifyError(testCase, @() vawlume.eda.probeConcordance(screen, subset), ...
    "vawlume:eda:ProbeFactorsDiffer");
try
    vawlume.eda.probeConcordance(screen, subset);
catch err
    verifySubstring(testCase, err.message, "Only in the screen");
    verifySubstring(testCase, err.message, "Only in the subset probe");
    verifySubstring(testCase, err.message, "reads as agreement");
end

% The same refusal guards design construction, before anything is executed.
verifyError(testCase, @() vawlume.eda.subsetDesign( ...
    struct(status="resolved", factors=table()), ...
    struct(factors=table("x", VariableNames="factor_name"), ...
    design_type="full_factorial", alias=struct(), configurations=table()), ...
    struct(recordings=table(), pairs=table(), recording_count=0, ...
    extractor_keys="a")), "vawlume:eda:SubsetProbeEmpty");
end

function testAResponseSeenByOneProbeOnlyIsReportedNotDropped(testCase)
%TESTARESPONSESEENBYONEPROBEONLY... A support pattern the subset never saw.
%
% The probes run on different recordings, so a response present in one and absent
% from the other is a finding about the data. Dropping it would hide exactly the
% kind of difference the second probe exists to reveal.
screen = leverageFrom([0.8 0.4], ["r_one" "r_only_in_screen"], "whole_dataset");
subset = leverageFrom(0.8, "r_one", "subset");
result = vawlume.eda.probeConcordance(screen, subset);

rows = result.comparison;
verifyEqual(testCase, height(rows), 2);
onlyScreen = rows(rows.response == "r_only_in_screen", :);
verifyEqual(testCase, onlyScreen.presence, "screen_only");
verifyEqual(testCase, onlyScreen.subset_category, "not_observed");
verifyFalse(testCase, onlyScreen.categories_agree);
verifyFalse(testCase, onlyScreen.directions_comparable);
verifySubstring(testCase, onlyScreen.reading, "one probe only");
verifyTrue(testCase, isnan(onlyScreen.subset_main_effect));
end

function testDirectionAgreementIsOnlyClaimedWhereBothAreInterpretable(testCase)
% Opposite signs, same category: the categories agree and the directions do not,
% which is a distinction a single "agrees" column would lose.
screen = leverageFrom(0.8, "r_one", "whole_dataset");
subset = leverageFrom(-0.8, "r_one", "subset");
rows = vawlume.eda.probeConcordance(screen, subset).comparison;
verifyTrue(testCase, rows.categories_agree);
verifyTrue(testCase, rows.directions_comparable);
verifyFalse(testCase, rows.directions_agree);
verifySubstring(testCase, rows.reading, "direction does not");

% A constant response on one side makes the pair neither agreement nor
% disagreement, and the row says so rather than scoring it either way.
flat = leverageFrom(0, "r_one", "subset", 0);
rows = vawlume.eda.probeConcordance(screen, flat).comparison;
verifyTrue(testCase, rows.either_insufficient_information);
verifyFalse(testCase, rows.directions_comparable);
verifySubstring(testCase, rows.reading, "not an agreement or a disagreement");
end

function testSupportPatternMovementComparesExactPatterns(testCase)
%TESTSUPPORTPATTERNMOVEMENT... Exact patterns, never a coarse supported count.
screen = patternLeverage(["DS--MU", "DS--US", "MU--US"], [9 5 1], ...
    "whole_dataset");
subset = patternLeverage(["DS--MU", "DS--US", "MU--US"], [8 2 6], "subset");
result = vawlume.eda.probeConcordance(screen, subset, TopPatterns=2);

movement = result.support_pattern_movement;
verifyEqual(testCase, movement.screen_top.qualifier, ["DS--MU"; "DS--US"]);
verifyEqual(testCase, movement.subset_top.qualifier, ["DS--MU"; "MU--US"]);
verifyEqual(testCase, movement.patterns_in_both, "DS--MU");

comparison = movement.comparison;
verifyTrue(testCase, comparison.in_both(comparison.support_pattern == "DS--MU"));
verifyFalse(testCase, comparison.in_both(comparison.support_pattern == "DS--US"));

% Every compared qualifier names an extractor pair rather than a bare count, so
% the comparison cannot silently have been made on a coarse K.
for pattern = comparison.support_pattern'
    verifySubstring(testCase, pattern, "--");
    verifyTrue(testCase, isnan(str2double(pattern)), ...
        "Pattern '" + pattern + "' parses as a number, so it is a coarse " + ...
        "count rather than an exact support pattern.");
end
verifySubstring(testCase, movement.exactness, "never binned");
end

% ----------------------------------------------------- what must not appear ---

function testNoCompositeScoreAppearsInAnyReturnedFieldName(testCase)
%TESTNOCOMPOSITESCOREAPPEARS... Asserted on names, not by reading the output.
%
% Boundary 2 and contract §H forbid a composite. The check is on the returned
% field and column names because that is the surface a consumer binds to: a
% number named `concordance_score` would be used as one whatever its docstring
% said, and a figure in Part 14 would plot it.
forbidden = ["score", "composite", "overall", "recommend", "recommended", ...
    "optimal", "best", "selected_threshold", "selected_configuration", ...
    "ranking", "rank", "concordance_rate", "agreement_fraction", ...
    "agreement_score", "stability_score"];

screen = leverageFrom([0.8 0.2], ["r_one" "r_two"], "whole_dataset");
subset = leverageFrom([0.8 0.6], ["r_one" "r_two"], "subset");
concordance = vawlume.eda.probeConcordance(screen, subset);
leverage = vawlume.eda.leverageCategories( ...
    effectTable(struct(estimate=0.8, range=1, interaction=0)), designAt(4));

for name = collectNames(concordance)'
    verifyFalse(testCase, any(strcmpi(name, forbidden)), ...
        "Concordance exposes a forbidden name: " + name);
end
for name = collectNames(leverage)'
    verifyFalse(testCase, any(strcmpi(name, forbidden)), ...
        "Leverage exposes a forbidden name: " + name);
end

verifySubstring(testCase, concordance.no_composite, "no concordance score");
verifySubstring(testCase, leverage.no_ranking, "never ranked");
end

function testTheCalibrationCautionTravelsWithTheOutput(testCase)
%TESTTHECALIBRATIONCAUTIONTRAVELS... The most likely over-reading of the MVP.
screen = leverageFrom(0.8, "r_one", "whole_dataset");
subset = leverageFrom(0.8, "r_one", "subset");
result = vawlume.eda.probeConcordance(screen, subset);

verifySubstring(testCase, result.calibration_note, ...
    "does NOT establish that manual calibration is unnecessary");
verifySubstring(testCase, result.cut_point_note, "reporting convention");
verifyGreaterThanOrEqual(testCase, numel(result.caution), 4);
verifySubstring(testCase, strjoin(result.caution, " "), ...
    "methodological evidence, not ground truth");

% And an agreeing row says it too, because a reader scanning the table may never
% reach the struct field beside it.
verifySubstring(testCase, result.comparison.reading, ...
    "NOT evidence that manual calibration is unnecessary");
end

% ---------------------------------------------------------------- helpers ---

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function value = edaCategoryVocabulary()
result = vawlume.eda.leverageCategories( ...
    effectTable(struct(estimate=0.8, range=1, interaction=0)), designAt(4));
value = result.category_vocabulary;
end

function names = collectNames(value)
%COLLECTNAMES Every struct field and every table column, recursively.
names = strings(0, 1);
if isstruct(value)
    for name = string(fieldnames(value))'
        names(end + 1, 1) = name; %#ok<AGROW>
        names = [names; collectNames(value.(name))]; %#ok<AGROW>
    end
    return
end
if istable(value)
    names = [names; string(value.Properties.VariableNames)'];
end
end

% ------------------------------------------------------------- constructors ---

function design = designAt(resolution)
%DESIGNAT A four-factor design whose alias structure states a chosen resolution.
%
% Constructed rather than built by screeningDesign, so a test can put a design at
% resolution III without arranging for a factor count and fraction that happen to
% produce one. The fields are exactly those leverageCategories reads.
letters = ["A"; "B"; "C"; "D"];
names = ["min_temporal_iou"; "max_abs_onset_delta_s"; ...
    "max_abs_offset_delta_s"; "min_frequency_overlap"];
design = struct( ...
    design_type=ternary(resolution >= 5, "full_factorial", ...
        "fractional_factorial"), ...
    configuration_count=8, ...
    factors=table(letters, names, ...
        ["stricter_when_larger"; "looser_when_larger"; ...
        "looser_when_larger"; "stricter_when_larger"], ...
        VariableNames=["design_letter", "factor_name", ...
        "strictness_direction"]), ...
    alias=struct( ...
        resolution=resolution, ...
        resolution_label="R" + string(resolution), ...
        main_effects_clear_of_two_factor_interactions=resolution >= 4, ...
        two_factor_interactions_uniquely_attributable=resolution >= 5, ...
        alias_table=table(strings(0, 1), strings(0, 1), zeros(0, 1), ...
            false(0, 1), VariableNames=["effect", "aliased_with", ...
            "effect_order", "is_uniquely_attributable"])));
end

function value = ternary(condition, whenTrue, whenFalse)
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end

function effects = effectTable(spec)
%EFFECTTABLE One response, one factor's main effect, one AB interaction.
defaults = struct(estimate=0, range=1, interaction=0, highRuns=4, ...
    lowRuns=4, interactionUnique=true, interactionAlias="", ...
    response="r_one");
spec = fill(spec, defaults);

rows = effectRow("A", "min_temporal_iou", 1, spec.estimate, spec, true, "");
if isfinite(spec.interaction) && spec.interaction ~= 0
    rows = [rows; effectRow("AB", "min_temporal_iou x b", 2, ...
        spec.interaction, spec, spec.interactionUnique, ...
        spec.interactionAlias)];
end
effects = struct(status="estimated", effects=rows, design_is_complete=true, ...
    exploration_run_key="test-run");
end

function effects = fourFactorTable(estimates, range, interactions)
%FOURFACTORTABLE Four main effects on one response, for the constant-response case.
rows = emptyEffectRows();
letters = ["A" "B" "C" "D"];
names = ["min_temporal_iou", "max_abs_onset_delta_s", ...
    "max_abs_offset_delta_s", "min_frequency_overlap"];
spec = struct(range=range, highRuns=4, lowRuns=4, response="r_one");
for index = 1:4
    rows = [rows; effectRow(letters(index), names(index), 1, ...
        estimates(index), spec, true, "")]; %#ok<AGROW>
end
labels = ["AB" "AC" "AD" "BC" "BD" "CD"];
for index = 1:numel(labels)
    if interactions(index) == 0
        continue
    end
    rows = [rows; effectRow(labels(index), labels(index), 2, ...
        interactions(index), spec, true, "")]; %#ok<AGROW>
end
effects = struct(status="estimated", effects=rows, design_is_complete=true, ...
    exploration_run_key="test-run");
end

function row = effectRow(label, name, order, estimate, spec, unique, alias)
row = cell2table({spec.response, "", "", "", "", "count", label, name, ...
    order, estimate, spec.range, 0, spec.range, 8, spec.highRuns, ...
    spec.lowRuns, string(alias), logical(unique), true}, ...
    VariableNames=effectNames());
end

function leverage = leverageFrom(estimates, responses, role, range)
%LEVERAGEFROM A leverageCategories result for one factor across responses.
arguments
    estimates double
    responses string
    role (1,1) string
    range double = 1
end
if isscalar(range)
    range = repmat(range, size(estimates));
end
rows = emptyCategoryRows();
for index = 1:numel(estimates)
    spec = struct(estimate=estimates(index), range=range(index), ...
        interaction=0, response=responses(index));
    single = vawlume.eda.leverageCategories(effectTable(spec), designAt(4));
    rows = [rows; single.categories]; %#ok<AGROW>
end
leverage = struct(status="categorised", probe_role=role, ...
    design_type="fractional_factorial", resolution_label="RIV", ...
    categories=rows, category_vocabulary=edaCategoryVocabulary(), ...
    cut_point_note="The cut points are a reporting convention.");
end

function leverage = patternLeverage(patterns, ranges, role)
%PATTERNLEVERAGE Support-pattern responses with stated movement per pattern.
rows = emptyCategoryRows();
for index = 1:numel(patterns)
    spec = struct(estimate=0.5 * ranges(index), range=ranges(index), ...
        interaction=0, response="support_pattern_groups");
    effects = effectTable(spec);
    effects.effects.qualifier_kind(:) = "support_pattern";
    effects.effects.qualifier(:) = patterns(index);
    single = vawlume.eda.leverageCategories(effects, designAt(4));
    rows = [rows; single.categories]; %#ok<AGROW>
end
leverage = struct(status="categorised", probe_role=role, ...
    design_type="fractional_factorial", resolution_label="RIV", ...
    categories=rows, category_vocabulary=edaCategoryVocabulary(), ...
    cut_point_note="The cut points are a reporting convention.");
end

function value = fill(spec, defaults)
value = defaults;
for name = string(fieldnames(spec))'
    value.(name) = spec.(name);
end
end

function value = effectNames()
value = ["response", "qualifier_kind", "qualifier", "secondary_kind", ...
    "secondary", "value_kind", "effect", "effect_name", "effect_order", ...
    "estimate", "response_range", "response_minimum", "response_maximum", ...
    "configuration_count", "high_run_count", "low_run_count", ...
    "aliased_with", "is_uniquely_attributable", "design_is_complete"];
end

function value = emptyEffectRows()
value = cell2table(cell(0, numel(effectNames())), ...
    VariableNames=effectNames());
end

function value = emptyCategoryRows()
result = vawlume.eda.leverageCategories( ...
    effectTable(struct(estimate=0.8, range=1, interaction=0)), designAt(4));
value = result.categories([], :);
end
