function tests = test_eda_screen_effects
%TEST_EDA_SCREEN_EFFECTS Change classification and per-response effect estimates.
%
% Both layers are pure, so every interesting case is constructible without a
% database and the arithmetic can be asserted exactly.
%
% Two assertions carry the most weight. The change classification must place
% every group in exactly one class on each side, or the counts stop adding up and
% a reader cannot tell a split from a reconfiguration. And the effect estimator
% must refuse an incomplete design rather than return a difference of means taken
% over unequal recording sets, which would be a real number that is not the
% quantity it claims to be.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repoRoot, "src");
testCase.TestData.repo_root = repoRoot;
testCase.TestData.source_path = sourcePath;
testCase.TestData.added_path = ~contains(path, sourcePath);
if testCase.TestData.added_path
    addpath(sourcePath);
end
end

function teardownOnce(testCase)
if testCase.TestData.added_path && contains(path, testCase.TestData.source_path)
    rmpath(testCase.TestData.source_path);
end
end

% ------------------------------------------------- change classification ---

function testIdenticalMemberSetsAreRetainedOnBothSides(testCase)
change = vawlume.eda.groupChanges({[1 2], 3}, {[2 1], 3});
verifyEqual(testCase, change.from_classes, ["retained"; "retained"]);
verifyEqual(testCase, change.to_classes, ["retained"; "retained"]);
verifyEqual(testCase, change.retained_group_count, 2);
% Member order is not identity: the same set in a different order is the same
% group.
verifyTrue(testCase, change.population.is_same_population);
end

function testDisjointSetsAreLostAndGained(testCase)
change = vawlume.eda.groupChanges({[1 2]}, {[3 4]});
verifyEqual(testCase, change.from_classes, "lost");
verifyEqual(testCase, change.to_classes, "gained");
end

function testOneGroupBecomingSeveralIsSplitFromAndSplitTo(testCase)
% The same event has opposite names from the two sides, and each side's counts
% must add up on their own.
change = vawlume.eda.groupChanges({[1 2 3]}, {[1 2], 3});
verifyEqual(testCase, change.from_classes, "split");
verifyEqual(testCase, change.to_classes, ["split"; "split"]);
verifyEqual(testCase, classCount(change, "split", "from_side"), 1);
verifyEqual(testCase, classCount(change, "split", "to_side"), 2);
end

function testSeveralGroupsBecomingOneIsMerged(testCase)
change = vawlume.eda.groupChanges({[1 2], 3}, {[1 2 3]});
verifyEqual(testCase, change.from_classes, ["merged"; "merged"]);
verifyEqual(testCase, change.to_classes, "merged");
end

function testStrictSubsetAndSupersetAreNotReconfigured(testCase)
% The contract reserves `reconfigured` for an overlap that is neither identical,
% subset, nor superset. A containment relation is a division of membership, so
% it is a split or a merge however many partners are visible.
shrunk = vawlume.eda.groupChanges({[1 2 3]}, {[1 2]});
verifyEqual(testCase, shrunk.from_classes, "split");
verifyNotEqual(testCase, shrunk.from_classes, "reconfigured");

grown = vawlume.eda.groupChanges({[1 2]}, {[1 2 3]});
verifyEqual(testCase, grown.from_classes, "merged");
verifyNotEqual(testCase, grown.from_classes, "reconfigured");
end

function testPartialOverlapIsReconfiguredOnBothSides(testCase)
% Two groups sharing some detections while neither contains the other are not a
% split, not a merge, and not unchanged. This is the case most likely to be
% handled by accident, which is why it has its own name.
change = vawlume.eda.groupChanges({[1 2], [3 4]}, {[1 3], [2 4]});
verifyEqual(testCase, change.from_classes, ["reconfigured"; "reconfigured"]);
verifyEqual(testCase, change.to_classes, ["reconfigured"; "reconfigured"]);
verifyTrue(testCase, change.population.is_same_population);
end

function testEachSidePartitionsExactly(testCase)
% Conservation: every baseline group receives exactly one class and the classes
% sum to the baseline group count; likewise for the comparison side.
change = vawlume.eda.groupChanges({[1 2], 3, [4 5], 6}, ...
    {[1 2], [3 4], 5, 6});
verifyEqual(testCase, sum(change.counts.from_side), change.from_group_count);
verifyEqual(testCase, sum(change.counts.to_side), change.to_group_count);
verifyEqual(testCase, numel(change.from_classes), 4);
verifyEqual(testCase, numel(change.to_classes), 4);
verifyTrue(testCase, all(ismember(change.from_classes, ...
    change.class_vocabulary)));
verifyTrue(testCase, all(ismember(change.to_classes, ...
    change.class_vocabulary)));
end

function testComparingGroupKeysIsRefused(testCase)
% A group key is unique within one analysis run and carries no meaning across
% two, so joining configurations on it would match unrelated groups silently.
verifyError(testCase, @() vawlume.eda.groupChanges( ...
    {"grp-a", "grp-b"}, {"grp-a", "grp-b"}), ...
    "vawlume:eda:GroupKeyComparisonRefused");
verifyError(testCase, @() vawlume.eda.groupChanges( ...
    {'grp-a'}, {'grp-a'}), "vawlume:eda:GroupKeyComparisonRefused");
end

function testDifferingPopulationsAreRefusedWhenRequired(testCase)
% Two configurations of one agreement analysis partition the same detections, so
% a mismatch means the sides are not comparable rather than that grouping
% changed.
verifyError(testCase, @() vawlume.eda.groupChanges({[1 2]}, {[3 4]}, ...
    RequireSamePopulation=true), "vawlume:eda:ChangePopulationMismatch");
change = vawlume.eda.groupChanges({[1 2], 3}, {[1 2 3]}, ...
    RequireSamePopulation=true);
verifyTrue(testCase, change.population.is_same_population);
end

function testAnEmptyGroupIsRefused(testCase)
verifyError(testCase, @() vawlume.eda.groupChanges({[]}, {1}), ...
    "vawlume:eda:GroupMembersEmpty");
end

% ---------------------------------------------------- effect estimation ---

function testMainEffectsAreDifferencesOfMeansInTheResponsesOwnUnits(testCase)
% Two factors, full factorial, responses chosen so each effect is exact:
%   values 10 20 14 24 over runs (A-,B-) (A+,B-) (A-,B+) (A+,B+)
%   A: mean(20,24) - mean(10,14) = 22 - 12 = 10
%   B: mean(14,24) - mean(10,20) = 19 - 15 =  4
%   AB: mean(10,24) - mean(20,14) = 17 - 17 = 0
design = twoFactorDesign();
responses = responsesFor(design, "groups", [10 20 14 24]);
result = vawlume.eda.mainEffects(responses, design);

verifyEqual(testCase, estimateOf(result, "groups", "A"), 10, AbsTol=1e-12);
verifyEqual(testCase, estimateOf(result, "groups", "B"), 4, AbsTol=1e-12);
verifyEqual(testCase, estimateOf(result, "groups", "AB"), 0, AbsTol=1e-12);
verifyEqual(testCase, rowOf(result, "groups", "A").response_range, 14);
verifyEqual(testCase, rowOf(result, "groups", "A").response_minimum, 10);
verifyEqual(testCase, rowOf(result, "groups", "A").response_maximum, 24);
verifyEqual(testCase, rowOf(result, "groups", "A").high_run_count, 2);
verifyEqual(testCase, rowOf(result, "groups", "A").low_run_count, 2);
end

function testAConstantResponseGivesZeroEffectsAndZeroRange(testCase)
% A response constant across the whole design has a zero main effect for every
% factor. That is not low leverage - it is no information - and the zero range
% beside it is how a consumer tells the two apart.
design = twoFactorDesign();
responses = responsesFor(design, "flat", [7 7 7 7]);
result = vawlume.eda.mainEffects(responses, design);

verifyEqual(testCase, estimateOf(result, "flat", "A"), 0, AbsTol=1e-12);
verifyEqual(testCase, estimateOf(result, "flat", "B"), 0, AbsTol=1e-12);
verifyEqual(testCase, rowOf(result, "flat", "A").response_range, 0);
end

function testEveryEstimateCarriesItsAliasAndAttributability(testCase)
design = twoFactorDesign();
result = vawlume.eda.mainEffects(responsesFor(design, "groups", ...
    [10 20 14 24]), design);
effects = result.effects;

verifyTrue(testCase, all(ismember(["A", "B", "AB"], effects.effect)));
% A full factorial confounds nothing, so every effect is uniquely attributable
% and no alias is recorded.
verifyTrue(testCase, all(effects.is_uniquely_attributable));
verifyTrue(testCase, all(effects.aliased_with == ""));
verifyEqual(testCase, unique(effects.effect_order( ...
    ismember(effects.effect, ["A", "B"]))), 1);
verifyEqual(testCase, unique(effects.effect_order(effects.effect == "AB")), 2);
end

function testAnAliasedInteractionIsLabelledWithThePairItCannotSeparate(testCase)
% At resolution IV an interaction estimate is the sum of its aliased pair, not
% either member. A consumer deciding whether an interaction is measured or only
% suspected reads is_uniquely_attributable rather than inferring it.
design = fourFactorHalfFraction();
responses = responsesFor(design, "groups", 1:8);
result = vawlume.eda.mainEffects(responses, design);

interaction = rowOf(result, "groups", "AB");
verifyEqual(testCase, interaction.aliased_with, "CD");
verifyFalse(testCase, interaction.is_uniquely_attributable);

main = rowOf(result, "groups", "A");
verifyEqual(testCase, main.aliased_with, "BCD");
verifyTrue(testCase, contains(result.interaction_note, "ALIASED IN PAIRS"));
end

function testAnIncompleteDesignIsRefusedByDefault(testCase)
design = twoFactorDesign();
responses = responsesFor(design, "groups", [10 20 14 24]);
responses.design_completeness.is_complete = false;
responses.design_completeness.note = "THIS DESIGN IS INCOMPLETE. 1 unit missing.";

verifyError(testCase, @() vawlume.eda.mainEffects(responses, design), ...
    "vawlume:eda:DesignIncomplete");

% "label" computes anyway and marks every row, for a caller who has read the
% completeness report. It never returns a silently biased number.
labelled = vawlume.eda.mainEffects(responses, design, ...
    OnIncompleteDesign="label");
verifyFalse(testCase, labelled.design_is_complete);
verifyFalse(testCase, any(labelled.effects.design_is_complete));
verifyEqual(testCase, labelled.incomplete_design_policy, "label");
end

function testNoCompositeScoreOrInferentialMachineryIsProduced(testCase)
design = twoFactorDesign();
result = vawlume.eda.mainEffects(responsesFor(design, "groups", ...
    [10 20 14 24]), design);

columns = string(result.effects.Properties.VariableNames);
for banned = ["p_value", "pvalue", "confidence", "significance", "score", ...
        "normalized", "standardized"]
    verifyFalse(testCase, any(contains(columns, banned, IgnoreCase=true)), ...
        banned);
end
verifyTrue(testCase, contains(result.no_composite_score, "never aggregated"));
verifyTrue(testCase, contains(result.inference_note, "no p-value"));

% Every effect is reported against its own response, never pooled across them.
verifyEqual(testCase, numel(unique(result.effects.response)), 1);
end

function testEffectsAreEstimatedSeparatelyForEachResponse(testCase)
design = twoFactorDesign();
responses = responsesFor(design, "groups", [10 20 14 24]);
second = responsesFor(design, "ambiguous", [4 4 1 1]);
responses.responses = [responses.responses; second.responses];
result = vawlume.eda.mainEffects(responses, design);

verifyEqual(testCase, estimateOf(result, "groups", "A"), 10, AbsTol=1e-12);
verifyEqual(testCase, estimateOf(result, "ambiguous", "A"), 0, AbsTol=1e-12);
verifyEqual(testCase, estimateOf(result, "ambiguous", "B"), -3, AbsTol=1e-12);
verifyEqual(testCase, numel(unique(result.effects.response)), 2);
end

function testMalformedInputsAreRefused(testCase)
design = twoFactorDesign();
responses = responsesFor(design, "groups", [10 20 14 24]);
verifyError(testCase, @() vawlume.eda.mainEffects( ...
    rmfield(responses, "responses"), design), "vawlume:eda:EffectInputInvalid");
verifyError(testCase, @() vawlume.eda.mainEffects(responses, ...
    rmfield(design, "alias")), "vawlume:eda:EffectInputInvalid");

empty = responses;
empty.responses = empty.responses([], :);
verifyError(testCase, @() vawlume.eda.mainEffects(empty, design), ...
    "vawlume:eda:NoPooledResponses");
end

function testNothingNamesAnExtractorOrAssumesThreeOfThem(testCase)
root = testCase.TestData.repo_root;
files = ["screenResponses.m", "mainEffects.m", "groupChanges.m", ...
    fullfile("private", "edaResponseVocabulary.m"), ...
    fullfile("private", "edaChangeClasses.m")];
for index = 1:numel(files)
    text = string(fileread(fullfile(root, "src", "+vawlume", "+eda", ...
        files(index))));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for banned = ["deepsqueak", "mupet", "usvseg"]
        verifyFalse(testCase, contains(lower(body), banned), ...
            files(index) + " names " + banned);
    end
end
end

% ---------------------------------------------------------------- helpers ---

function design = twoFactorDesign()
%TWOFACTORDESIGN A full 2^2 factorial, built the way the design layer builds one.
design = vawlume.eda.screeningDesign(resolutionWith(2));
end

function design = fourFactorHalfFraction()
design = vawlume.eda.screeningDesign(resolutionWith(4), ...
    MaximumConfigurations=8);
end

function record = resolutionWith(k)
policy = [ ...
    "min_temporal_iou", "temporal_iou", "larger_is_stricter", "ratio"
    "max_abs_onset_difference_s", "abs_onset_difference_s", "smaller_is_stricter", "seconds"
    "max_abs_offset_difference_s", "abs_offset_difference_s", "smaller_is_stricter", "seconds"
    "max_abs_duration_difference_s", "abs_duration_difference_s", "smaller_is_stricter", "seconds"];
lows = [0.10; 0.002; 0.003; 0.004];
highs = [0.50; 0.020; 0.030; 0.040];
factors = table(policy(1:k, 1), policy(1:k, 2), true(k, 1), repmat("", k, 1), ...
    lows(1:k), highs(1:k), policy(1:k, 3), policy(1:k, 4), ...
    repmat("observed_quantile", k, 1), ...
    VariableNames=["factor_name", "metric_name", "is_active", ...
    "inactive_reason", "low_value", "high_value", "strictness_direction", ...
    "unit", "value_source"]);
record = struct(status="resolved", factors=factors, seed=1);
end

function responses = responsesFor(design, name, values)
%RESPONSESFOR A minimal pooled response table, one value per design run.
configurations = design.configurations.configuration_id;
count = numel(configurations);
rows = table(repmat("exp-test", count, 1), configurations, NaN(count, 1), ...
    repmat("pooled", count, 1), repmat(string(name), count, 1), ...
    repmat("", count, 1), repmat("", count, 1), repmat("", count, 1), ...
    repmat("", count, 1), double(values(:)), NaN(count, 1), ...
    repmat("count", count, 1), ...
    VariableNames=["exploration_run_key", "configuration_id", ...
    "recording_id", "scope", "response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary", "value", "denominator", "value_kind"]);
responses = struct(exploration_run_key="exp-test", responses=rows, ...
    design_completeness=struct(is_complete=true, note="complete"));
end

function value = rowOf(result, response, effect)
value = result.effects(result.effects.response == response & ...
    result.effects.effect == effect, :);
end

function value = estimateOf(result, response, effect)
value = rowOf(result, response, effect).estimate;
end

function value = classCount(change, className, side)
value = change.counts.(side)(change.counts.change_class == className);
end
