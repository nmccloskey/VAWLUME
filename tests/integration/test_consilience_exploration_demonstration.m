function tests = test_consilience_exploration_demonstration
%TEST_CONSILIENCE_EXPLORATION_DEMONSTRATION The runnable exploration workflow.
%
% Integration tier, because the claims are about wiring: that one call carries a
% dataset from the reference configuration through diagnostics, both sensitivity
% probes, concordance, support-pattern characterization and a rendered gallery to
% an exported bundle - and that every automatic choice it made along the way is
% reproducible.
%
% The demonstration is built and run TWICE in setupOnce: once for the content
% assertions and once so determinism is a comparison of two independent runs
% rather than of one run against itself. Each run builds its own database from
% the tracked Phase 1 fixture, so there is no shared state between them and no
% analysis is reused across them.
tests = functiontests({ ...
    @setupOnce, ...
    @testTheWorkflowRunsEveryStageEndToEnd, ...
    @testTheDesignsAndTheirCostAreWhatTheyClaim, ...
    @testTheSubsetIsStratifiedAndSmallerThanTheFrame, ...
    @testExactSupportPatternsSurviveToTheGallery, ...
    @testTheExportedBundleIsComplete, ...
    @testTwoRunsProduceIdenticalAutomaticChoices, ...
    @testOneStageRunsWithoutExecutingAProbe, ...
    @testTheDemonstrationWritesNothingIntoTheRepository, ...
    @testTheWorkflowTemplateParsesAndIsRetargetableFromItsConfigurationBlock});
end

function setupOnce(testCase)
repoRoot = repoRootPath();
examplePath = fullfile(repoRoot, "examples");
addpath(examplePath);
testCase.TestData.cleanup = onCleanup(@() rmpath(examplePath));
testCase.TestData.repo_root = repoRoot;
testCase.TestData.status_before = gitStatus(repoRoot);
testCase.TestData.first = consilience_exploration_demo(Print=false, ...
    RepoRoot=repoRoot);
testCase.TestData.second = consilience_exploration_demo(Print=false, ...
    RepoRoot=repoRoot);
testCase.TestData.status_after = gitStatus(repoRoot);
end

% ------------------------------------------------------------ the workflow ---

function testTheWorkflowRunsEveryStageEndToEnd(testCase)
value = testCase.TestData.first;

verifyEqual(testCase, value.status, "completed");
verifyEqual(testCase, value.stages.stage', ["dataset", "reference", ...
    "diagnostics", "probe", "screen", "subset", "concordance", ...
    "support_patterns", "examples", "exports"]);
verifyTrue(testCase, all(value.stages.status == "completed"));

verifyEqual(testCase, value.dataset.recording_count, 6);
verifyEqual(testCase, value.dataset.extractor_keys, ...
    ["deepsqueak", "mupet", "usvseg"]);
verifyEqual(testCase, value.dataset.pairs_per_recording, 3);
verifyEqual(testCase, value.dataset.excluded_recording_count, 0);

% The diagnostics read the reference run's candidate pairs. They exist only
% because the reference configuration was applied first, which is why that
% stage leads rather than follows.
verifyGreaterThan(testCase, value.diagnostics.candidate_count, 0);
verifyGreaterThan(testCase, value.diagnostics.metric_count, 2);
verifyTrue(testCase, ismember(value.diagnostics.observation_policy, ...
    ["listwise", "pairwise"]));

% The workflow chose the factors and their probe values; the user supplied a
% seed, a subset size, and one factor to leave out.
verifyEqual(testCase, value.probe.seed, 20260918);
verifyEqual(testCase, value.probe.seed_source, "user");
verifyEqual(testCase, sort(value.probe.active_factor_names), ...
    ["max_abs_offset_difference_s", "max_abs_onset_difference_s", ...
    "min_temporal_iou"]);
verifyEqual(testCase, value.probe.inactive_factor_names, ...
    "max_abs_duration_difference_s");
factors = value.probe.factors;
verifyEqual(testCase, factors.inactive_reason(~factors.is_active), ...
    "disabled_by_user");
verifyTrue(testCase, all(factors.value_source(factors.is_active) == ...
    "observed_quantile"));
end

function testTheDesignsAndTheirCostAreWhatTheyClaim(testCase)
value = testCase.TestData.first;

% Three factors capped at four configurations is the half fraction: resolution
% III, main effects aliased with two-factor interactions.
verifyEqual(testCase, value.screen.design_type, "fractional_factorial");
verifyEqual(testCase, value.screen.configuration_count, 4);
verifyEqual(testCase, value.screen.design_resolution, 3);
verifyFalse(testCase, ...
    value.screen.main_effects_clear_of_two_factor_interactions);

% Cost is configurations x recordings x (pairs + 1), reported before execution.
verifyEqual(testCase, value.screen.predicted_analyses, 4 * 6 * 4);
verifyEqual(testCase, value.screen.executed_units, 4 * 6 * 4);

% The subset budget affords the full factorial, and that is the point of it.
verifyEqual(testCase, value.subset.probe.design_type, "full_factorial");
verifyEqual(testCase, value.subset.probe.configuration_count, 8);
verifyEqual(testCase, value.subset.probe.predicted_analyses, 8 * 3 * 4);
verifyGreaterThan(testCase, value.subset.de_aliased_count, 0);

% A resolution-III screen makes no leverage claim about any factor, and the
% full-factorial probe does - so the screen's silence is attributable to its
% design rather than to a fixture with no signal.
verifyTrue(testCase, value.honest_degenerate_cases. ...
    screen_makes_no_leverage_claim);
verifyTrue(testCase, value.honest_degenerate_cases. ...
    screen_main_effects_are_aliased);
subsetCounts = value.subset.probe.leverage_counts;
verifyGreaterThan(testCase, sum(subsetCounts.factor_response_pairs( ...
    ismember(subsetCounts.category, ["high_leverage", "moderate_leverage", ...
    "low_leverage"]))), 0);

% Concordance is a table with one row per factor per response identity, and
% carries the statement it exists to prevent being forgotten.
verifyGreaterThan(testCase, value.concordance.comparison_row_count, 0);
verifyFalse(testCase, value.concordance.composite_score_returned);
verifyTrue(testCase, contains(value.concordance.calibration_note, ...
    "does NOT establish that manual calibration is unnecessary"));
end

function testTheSubsetIsStratifiedAndSmallerThanTheFrame(testCase)
value = testCase.TestData.first.subset;

verifyTrue(testCase, value.is_stratified);
verifyEqual(testCase, value.stratum_field, "recording_attribute:genotype");
verifyEqual(testCase, value.fallback_reason, "");
verifyEqual(testCase, value.requested_size, 3);
verifyEqual(testCase, value.realized_size, 3);
verifyEqual(testCase, numel(value.selected_recording_ids), 3);
verifyLessThan(testCase, value.realized_size, ...
    testCase.TestData.first.dataset.recording_count);

% One recording carries no genotype, and "(missing)" is a stratum rather than a
% dropped row. The floor of one per stratum is what puts it in the sample.
verifyEqual(testCase, sort(value.allocation.stratum_value)', ...
    ["(missing)", "KO", "WT"]);
verifyEqual(testCase, sum(value.allocation.realized_count), 3);
end

function testExactSupportPatternsSurviveToTheGallery(testCase)
value = testCase.TestData.first;
support = value.support_patterns;

% Seven extractor-set patterns for three extractors, every one present -
% including the ones nothing occupies, because an absent row and a zero row
% look identical in a table and mean different things.
verifyEqual(testCase, support.pattern_count, 7);
verifyEqual(testCase, support.absent_pattern_count, 3);
verifyEqual(testCase, support.patterns.extractor_set_label', ...
    ["deepsqueak", "mupet", "usvseg", "deepsqueak + mupet", ...
    "deepsqueak + usvseg", "mupet + usvseg", "deepsqueak + mupet + usvseg"]);
verifyEqual(testCase, support.patterns.group_count', [0 0 1 0 1 1 2]);
verifyEqual(testCase, support.patterns.detection_count', [0 0 1 0 2 2 8]);

% The pair-pattern vocabulary cannot express those seven categories, which is
% why the profile keys on the extractor set and reports the pair pattern beside
% it without ever joining them.
verifyLessThan(testCase, support.pair_pattern_row_count, support.pattern_count);

% Only duration and centre frequency are comparable across every pattern.
verifyEqual(testCase, sort(support.cross_pattern_comparable), ...
    ["vocalization_duration", "vocalization_frequency_center"]);
verifyEqual(testCase, sort(support.extractor_restricted), ...
    ["vocalization_frequency_bandwidth", "vocalization_frequency_max", ...
    "vocalization_frequency_min"]);

examples = value.examples;
verifyEqual(testCase, examples.recording_id, 1);
verifyEqual(testCase, examples.target_per_pattern, 2);
verifyEqual(testCase, examples.example_count, 5);
verifyEqual(testCase, examples.success_count, 5);
verifyEqual(testCase, examples.failure_count, 0);
verifyEqual(testCase, examples.image_count, 5);
verifyEqual(testCase, examples.index_row_count, 5);
verifyEqual(testCase, examples.index_column_count, 22);

% Six of the seven patterns could not supply two examples, and the shortfall is
% reported rather than made up from a neighbouring pattern.
verifyEqual(testCase, height(examples.short_patterns), 6);
verifyEqual(testCase, height(examples.empty_patterns), 3);
verifyTrue(testCase, all(examples.short_patterns.drawn <= ...
    examples.short_patterns.available));

% USVSEG registers no band edges, so its annotations are a time extent plus the
% measurements it did make. No band is ever synthesized.
verifyTrue(testCase, ismember("center_and_peak", ...
    examples.frequency_extent_sources));
verifyTrue(testCase, ismember("band_edges", examples.frequency_extent_sources));
end

function testTheExportedBundleIsComplete(testCase)
value = testCase.TestData.first.exports;

verifyGreaterThan(testCase, value.table_count, 10);
for name = ["metric_distributions", "probe_factors", "screen_responses", ...
        "screen_leverage", "subset_leverage", "probe_concordance", ...
        "support_pattern_counts", "support_pattern_features", "example_index"]
    verifyTrue(testCase, ismember(name, value.table_names), ...
        "Export '" + name + "' is missing from the bundle.");
end
verifyGreaterThanOrEqual(testCase, value.figure_count, 13);
verifyTrue(testCase, value.provenance_written);
verifyGreaterThan(testCase, value.provenance_bytes, 2000);

% One figure family cannot be drawn on any input: renderMetricCoverageTable
% builds a uitable and the raster export path uses `print`, which refuses a
% figure carrying a UI control. The run records the refusal and keeps going
% rather than abandoning the whole set, and the coverage counts it would have
% shown are in metric_distributions.csv regardless.
undrawn = testCase.TestData.first.exports.figures_not_drawn;
verifyEqual(testCase, undrawn.name, "metric_coverage");
verifyTrue(testCase, contains(undrawn.path(1), "not drawn"));
end

% ------------------------------------------------------------- determinism ---

function testTwoRunsProduceIdenticalAutomaticChoices(testCase)
%TESTTWORUNSPRODUCEIDENTICAL... Two independent runs, not one run twice.
%
% Every random draw in this workflow takes an explicit or deterministically
% resolved seed, and every design is constructed rather than searched. Two runs
% over the same data must therefore agree exactly - on the exploration run key,
% the configuration identities, which recordings the subset drew, and which
% groups the gallery illustrates.
first = testCase.TestData.first;
second = testCase.TestData.second;

verifyEqual(testCase, second.exploration_run_key, first.exploration_run_key);
verifyEqual(testCase, second.probe.seed, first.probe.seed);
verifyEqual(testCase, second.probe.factors, first.probe.factors);

verifyEqual(testCase, second.screen.configuration_ids, ...
    first.screen.configuration_ids);
verifyEqual(testCase, second.subset.probe.configuration_ids, ...
    first.subset.probe.configuration_ids);
verifyEqual(testCase, second.subset.selected_recording_ids, ...
    first.subset.selected_recording_ids);
verifyEqual(testCase, second.subset.allocation, first.subset.allocation);

verifyEqual(testCase, second.examples.example_ids, ...
    first.examples.example_ids);
verifyEqual(testCase, second.examples.image_paths, ...
    first.examples.image_paths);

verifyEqual(testCase, second.support_patterns.patterns, ...
    first.support_patterns.patterns);
verifyEqual(testCase, second.screen.leverage_counts, ...
    first.screen.leverage_counts);
verifyEqual(testCase, second.subset.probe.leverage_counts, ...
    first.subset.probe.leverage_counts);
verifyEqual(testCase, second.concordance.contingency, ...
    first.concordance.contingency);
end

% --------------------------------------------------------- stage skipping ---

function testOneStageRunsWithoutExecutingAProbe(testCase)
value = testCase.TestData.first.stage_skipping;

verifyEqual(testCase, value.requested, "diagnostics");
verifyEqual(testCase, value.stages_run, ...
    ["dataset", "reference", "diagnostics"]);
verifyFalse(testCase, value.design_built);
verifyFalse(testCase, value.probe_executed);

% Apply=false builds both designs, prices them, and writes no analysis, no
% export and no provenance record. The prices must match what the real run then
% executed, or the estimate was not an estimate of this probe.
planning = testCase.TestData.first.planning;
verifyEqual(testCase, planning.status, "planned");
verifyEqual(testCase, planning.screen_design_type, ...
    testCase.TestData.first.screen.design_type);
verifyEqual(testCase, planning.screen_predicted_analyses, ...
    testCase.TestData.first.screen.predicted_analyses);
verifyEqual(testCase, planning.subset_predicted_analyses, ...
    testCase.TestData.first.subset.probe.predicted_analyses);
verifyTrue(testCase, planning.nothing_exported);
verifyTrue(testCase, any(contains(planning.skipped_reasons, ...
    "nothing to export")));

% "completed" means every REQUESTED stage completed. A stage nobody asked for is
% recorded as not_requested rather than as a skip, so a deliberately partial run
% does not read as a degraded one - the stage table says exactly what ran.
verifyEqual(testCase, value.status, "completed");
end

% ----------------------------------------------------------------- hygiene ---

function testTheDemonstrationWritesNothingIntoTheRepository(testCase)
%TESTTHEDEMONSTRATIONWRITESNOTHING... Asserted against the tree, not claimed.
%
% Compared before and after rather than against an empty status, so the check
% works in a working tree that already carries uncommitted work.
verifyTrue(testCase, testCase.TestData.first.temporary_artifacts_removed);
verifyTrue(testCase, testCase.TestData.second.temporary_artifacts_removed);
verifyEqual(testCase, testCase.TestData.status_after, ...
    testCase.TestData.status_before, ...
    "The demonstration changed the working tree.");

% Its workspace lived under the system temporary directory, not beside the
% source it ran from.
verifyTrue(testCase, startsWith(testCase.TestData.first.workspace_root, ...
    string(tempdir)));
verifyFalse(testCase, isfolder(testCase.TestData.first.workspace_root));
end

% ---------------------------------------------------------------- template ---

function testTheWorkflowTemplateParsesAndIsRetargetableFromItsConfigurationBlock(testCase)
%TESTTHEWORKFLOWTEMPLATEPARSES... Parsed, not executed, and why.
%
% The template opens a database at a path the caller supplies, so executing it
% here would mean inventing that database - which is what the demonstration is
% for. What the template owes this test is that it parses, that everything a
% user must change is in section 1, and that no later section hard-codes a value
% section 1 already names.
path = fullfile(repoRootPath(), "examples", "templates", ...
    "consilience_exploration_workflow_template.m");
verifyTrue(testCase, isfile(path));

messages = checkcode(path, "-struct");
if isempty(messages)
    parseErrors = strings(0, 1);
else
    text0 = string({messages.message});
    parseErrors = text0(contains(text0, "Parse error"));
end
verifyEmpty(testCase, parseErrors, "The workflow template does not parse: " + ...
    strjoin(parseErrors, "; "));

text = string(fileread(path));
sectionTwo = strfind(text, "%% 2.");
verifyNotEmpty(testCase, sectionTwo);
configurationBlock = extractBefore(text, sectionTwo(1));
remainder = extractAfter(text, sectionTwo(1));

for name = ["repoRoot", "databasePath", "projectKey", "sourceRoot", ...
        "outputRoot", "explorationConfiguration", ...
        "screenConfigurationCeiling", "subsetConfigurationCeiling", ...
        "analysisCeiling"]
    verifyTrue(testCase, contains(configurationBlock, name + " "), ...
        "Configurable value '" + name + "' is not set in section 1.");
end

% Nothing after the configuration block may carry a value a user would have to
% find and edit.
verifyFalse(testCase, contains(remainder, "C:\"), ...
    "A path literal appears outside the configuration block.");
verifyFalse(testCase, contains(remainder, """my_project"""), ...
    "The project key appears outside the configuration block.");

% Ten numbered sections, in the development plan's order.
headings = regexp(text, "^%% (\d+)\.", "tokens", "lineanchors");
numbers = cellfun(@(t) double(string(t{1})), headings);
verifyEqual(testCase, numbers, 1:10);
end

% ----------------------------------------------------------------- helpers ---

function value = gitStatus(repoRoot)
[status, output] = system("git -C """ + repoRoot + """ status --porcelain");
if status ~= 0
    value = "(git unavailable)";
    return
end
value = sort(strtrim(splitlines(string(output))));
value = value(strlength(value) > 0);
end

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
