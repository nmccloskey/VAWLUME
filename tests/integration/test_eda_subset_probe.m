function tests = test_eda_subset_probe
%TEST_EDA_SUBSET_PROBE The second sensitivity view, end to end, over the fixture.
%
% Integration tier because the claims are about wiring: that the subset probe
% runs through Part 7's runner and Part 8's response layer rather than through
% copies of them, that both probes land on one exploration run distinguishable by
% role, and that a configuration common to both is the same analysis rather than
% a second execution of the same thing.
%
% The fixture and both probes are built ONCE, in setupOnce. Six of these tests
% need an applied two-probe run, and rebuilding it per test spent about six
% minutes executing the same analyses repeatedly. Every test here reads the
% result and none mutates it, so one construction is both faster and a stronger
% check: the assertions are made against one run rather than against six runs
% that happen to agree.
tests = functiontests({ ...
    @setupOnce, @teardownOnce, ...
    @testTheRicherDesignCoversExactlyTheScreensFactors, ...
    @testADifferentFactorSetIsRefusedBeforeAnythingExecutes, ...
    @testTheSubsetBudgetBuysTheFullFactorialAndDeAliasesTheScreen, ...
    @testSizingUsesTheRealizedSubsetCountNotTheRequestedOne, ...
    @testBothProbesLandOnOneExplorationRunDistinguishableByRole, ...
    @testASharedConfigurationIsReusedRatherThanRecomputed, ...
    @testTheSubsetProbeUsesPartEightsResponseLayerUnchanged, ...
    @testConcordanceRunsOverTwoRealProbes, ...
    @testNoResponseFamilyWasReimplementedInThisPart, ...
    @testNothingOutsideTheEdaPackageNeededEditing});
end

% --------------------------------------------------------- shared fixture ---

function setupOnce(testCase)
%SETUPONCE Build the fixture and run both probes exactly once.
%
% Read-only afterwards. Every test inspects the result and none mutates it, so
% one construction serves all of them - and the assertions then describe one run
% rather than six runs that happen to agree.
[fixture, cleanup] = setUpFixture();
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
testCase.TestData.context = twoProbeContext(fixture, Apply=true);
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ------------------------------------------------------------ the design ---

function testTheRicherDesignCoversExactlyTheScreensFactors(testCase)
context = testCase.TestData.context;

verifyEqual(testCase, sort(context.subsetDesign.factors.factor_name), ...
    sort(context.screenDesign.factors.factor_name));
verifyEqual(testCase, context.subsetDesign.probe_role, "subset");
verifyTrue(testCase, context.subsetDesign.factor_parity.matches_screen);

% Design metadata is the same metadata Part 6 records, because the return IS a
% screeningDesign rather than a new shape.
for name = ["design_type", "configuration_count", "factors", "coding", ...
        "configurations", "alias", "generator_source", "budget"]
    verifyTrue(testCase, isfield(context.subsetDesign, name), ...
        "Subset design is missing Part 6 metadata field " + name + ".");
end
verifyTrue(testCase, isfield(context.subsetDesign.alias, "alias_table"));
verifyTrue(testCase, isfield(context.subsetDesign.alias, "resolution"));
end

function testADifferentFactorSetIsRefusedBeforeAnythingExecutes(testCase)
%TESTADIFFERENTFACTORSETISREFUSED... A short concordance table reads as agreement.
context = testCase.TestData.context;

% A screen that dropped a factor the subset probe keeps.
narrowed = context.screenDesign;
narrowed.factors = narrowed.factors(1, :);

verifyError(testCase, @() vawlume.eda.subsetDesign(context.resolution, ...
    narrowed, context.subsetDataset), "vawlume:eda:ProbeFactorsDiffer");
try
    vawlume.eda.subsetDesign(context.resolution, narrowed, ...
        context.subsetDataset);
catch err
    verifySubstring(testCase, err.message, "Only in the subset probe");
    verifySubstring(testCase, err.message, "reduce the fraction");
end
end

function testTheSubsetBudgetBuysTheFullFactorialAndDeAliasesTheScreen(testCase)
%TESTTHESUBSETBUDGETBUYSTHEFULLFACTORIAL... The point of the second probe.
%
% The screen is forced to four configurations, which over three factors is the
% half fraction C = AB: resolution III, where every main effect is aliased with a
% two-factor interaction. The subset budget affords all eight runs, which
% separates them. That de-aliasing is the single most valuable thing the subset can buy and
% it is reported explicitly rather than left for a reader to infer from the
% configuration counts.
context = testCase.TestData.context;

verifyEqual(testCase, context.screenDesign.design_type, ...
    "fractional_factorial");
verifyEqual(testCase, context.screenDesign.configuration_count, 4);
verifyFalse(testCase, context.screenDesign.alias. ...
    main_effects_clear_of_two_factor_interactions);

verifyEqual(testCase, context.subsetDesign.design_type, "full_factorial");
verifyEqual(testCase, context.subsetDesign.configuration_count, 8);
verifyTrue(testCase, all( ...
    context.subsetDesign.alias.alias_table.is_uniquely_attributable), ...
    "The full factorial recorded aliasing.");

comparison = context.subsetDesign.screen_comparison;
verifyTrue(testCase, comparison.full_factorial_affordable);
verifyGreaterThan(testCase, comparison.de_aliased_count, 0);
verifySubstring(testCase, comparison.note, "FULL FACTORIAL");
verifySubstring(testCase, comparison.note, ...
    "only on the subset's recordings");
end

function testSizingUsesTheRealizedSubsetCountNotTheRequestedOne(testCase)
%TESTSIZINGUSESTHEREALIZEDSUBSETCOUNT... A design sized for a request overruns.
% Re-sampled from the SHARED fixture rather than building a second one. A second
% setUpFixture here would take its own onCleanup, and that cleanup rmpath's the
% source tree when this test ends - which left every later test unable to resolve
% vawlume.eda.* at all. Nothing below writes, so the shared connection is safe.
context = testCase.TestData.context;
conn = testCase.TestData.fixture.conn;

strata = vawlume.eda.resolveStrata(conn, ...
    context.dataset.recordings.recording_id);
subset = vawlume.eda.sampleRecordings(strata, Seed=11, Size=9);
subsetDataset = vawlume.eda.resolveDataset(conn, ...
    struct(project_key="phase1_synthetic_fixture", ...
    recording_ids=subset.selected_recording_ids));
design = vawlume.eda.subsetDesign(context.resolution, context.screenDesign, ...
    subsetDataset, Subset=subset);

sizing = design.sizing;
verifyEqual(testCase, sizing.sized_against, "realized");
verifyEqual(testCase, sizing.subset_requested_size, 9);
verifyLessThan(testCase, sizing.subset_realized_size, 9);
verifyEqual(testCase, sizing.dataset_recording_count, ...
    subsetDataset.recording_count);

% The cost is the realized one, and the number the request would have implied
% is strictly larger. Asserting only the formula would be tautological - it
% would pass against an implementation that used the requested count, because
% the formula is the same either way and only the R differs.
cost = sizing.analysis_cost;
perRecording = cost.analyses_per_configuration_per_recording;
verifyEqual(testCase, cost.recording_count, subsetDataset.recording_count);
verifyEqual(testCase, cost.total_analyses, ...
    design.configuration_count * subsetDataset.recording_count * perRecording);

wouldHaveBeen = design.configuration_count * 9 * perRecording;
verifyLessThan(testCase, cost.total_analyses, wouldHaveBeen, ...
    "The cost matches a design sized against the requested count.");

verifySubstring(testCase, sizing.shortfall_note, "of a requested 9");
verifySubstring(testCase, sizing.rule, "never the basis of the sizing");
end

% --------------------------------------------------------------- execution ---

function testBothProbesLandOnOneExplorationRunDistinguishableByRole(testCase)
context = testCase.TestData.context;

verifyEqual(testCase, context.screenRun.probe_role, "whole_dataset");
verifyEqual(testCase, context.subsetRun.probe_role, "subset");
verifyEqual(testCase, context.screenRun.exploration_run_key, ...
    context.subsetRun.exploration_run_key);

% One analysis_runs row of type consilience_exploration, shared.
verifyEqual(testCase, context.screenRun.exploration_run.analysis_run_id, ...
    context.subsetRun.exploration_run.analysis_run_id);
rows = fetch(testCase.TestData.fixture.conn, ...
    "SELECT COUNT(*) AS n FROM analysis_runs " + ...
    "WHERE run_type='consilience_exploration'");
verifyEqual(testCase, double(rows.n(1)), 1);

% The two probes' design records coexist under role-qualified version labels.
labels = fetch(testCase.TestData.fixture.conn, ...
    "SELECT version_label FROM " + ...
    "config_profile_versions WHERE version_label LIKE '%#%' " + ...
    "ORDER BY version_label");
verifyEqual(testCase, height(labels), 2);
verifyTrue(testCase, any(endsWith(string(labels.version_label), ...
    "#whole_dataset")));
verifyTrue(testCase, any(endsWith(string(labels.version_label), "#subset")));

% And the dependency roles distinguish the probes in the provenance.
roles = fetch(testCase.TestData.fixture.conn, ...
    "SELECT DISTINCT dependency_role FROM " + ...
    "analysis_run_sources ORDER BY dependency_role");
verifyTrue(testCase, any(string(roles.dependency_role) == ...
    "exploration_agreement_whole_dataset"));
end

function testASharedConfigurationIsReusedRatherThanRecomputed(testCase)
%TESTASHAREDCONFIGURATIONISREUSED... Same point, same analysis, by construction.
%
% `configuration_id` is a hash of the active parameter values, so a configuration
% in both designs is the SAME configuration. Under a shared exploration run key
% its analyses are found and reused, which is what makes a later concordance
% disagreement attributable to design and dataset rather than to two executions
% of one thing drifting apart.
context = testCase.TestData.context;

shared = context.subsetDesign.screen_comparison.shared_configuration_ids;
verifyNotEmpty(testCase, shared);

reused = context.subsetRun.manifest( ...
    ismember(context.subsetRun.manifest.configuration_id, shared) & ...
    ismember(context.subsetRun.manifest.recording_id, ...
    context.subsetDataset.recordings.recording_id), :);
verifyNotEmpty(testCase, reused);
verifyTrue(testCase, all(reused.status == "reused"), ...
    "A configuration shared with the screen was recomputed rather than reused.");

% The genuinely new configurations were committed, so reuse is not masking a
% probe that did no work.
fresh = context.subsetRun.manifest( ...
    ~ismember(context.subsetRun.manifest.configuration_id, shared), :);
verifyNotEmpty(testCase, fresh);
verifyTrue(testCase, all(ismember(fresh.status, ["committed", "reused"])));
verifyTrue(testCase, any(fresh.status == "committed"));
end

% --------------------------------------------------------------- responses ---

function testTheSubsetProbeUsesPartEightsResponseLayerUnchanged(testCase)
context = testCase.TestData.context;

screen = context.screenResponses;
subset = context.subsetResponses;

% Same tidy contract, same key columns, same vocabulary. Not "similar".
verifyEqual(testCase, subset.responses.Properties.VariableNames, ...
    screen.responses.Properties.VariableNames);
verifyEqual(testCase, subset.response_vocabulary, screen.response_vocabulary);
verifyEqual(testCase, subset.key_columns, screen.key_columns);

% The subset probe's recordings are a subset of the screen's, and its
% configurations are a superset.
verifyTrue(testCase, all(ismember(subset.recording_ids, ...
    screen.recording_ids)));
verifyTrue(testCase, all(ismember(screen.configuration_ids, ...
    subset.configuration_ids)));
end

function testConcordanceRunsOverTwoRealProbes(testCase)
context = testCase.TestData.context;

screenLeverage = vawlume.eda.leverageCategories(context.screenEffects, ...
    context.screenDesign, Resolution=context.resolution);
subsetLeverage = vawlume.eda.leverageCategories(context.subsetEffects, ...
    context.subsetDesign, Resolution=context.resolution);

% The screen is resolution III, so every one of its main effects is aliased with
% a two-factor interaction. The claim that follows is not that every row is
% interaction_suspected - a response with no spread is insufficient_information
% whatever the design does, and that outranks the alias trigger - but that NO row
% is categorised by magnitude. A resolution-III design cannot support a leverage
% claim about any factor, and a single high_leverage row here would be the
% unearned confidence the alias trigger exists to prevent.
verifyTrue(testCase, screenLeverage.main_effects_are_aliased);
verifyFalse(testCase, any(ismember(screenLeverage.categories.category, ...
    ["high_leverage", "moderate_leverage", "low_leverage"])), ...
    "A resolution-III screen categorised a factor by effect magnitude.");
verifyTrue(testCase, any(screenLeverage.categories.category == ...
    "interaction_suspected"), ...
    "No row is interaction_suspected, so the previous assertion is vacuous.");

% The subset probe is a full factorial, so nothing is aliased there - and it does
% reach magnitude categories, which is what makes the screen's absence of them
% attributable to the design rather than to the fixture having no signal.
verifyFalse(testCase, subsetLeverage.main_effects_are_aliased);
verifyTrue(testCase, any(ismember(subsetLeverage.categories.category, ...
    ["high_leverage", "moderate_leverage", "low_leverage"])), ...
    "The full-factorial probe reached no magnitude category either, so the " + ...
    "screen's lack of one says nothing about aliasing.");

result = vawlume.eda.probeConcordance(screenLeverage, subsetLeverage, ...
    ScreenResponses=context.screenResponses, ...
    SubsetResponses=context.subsetResponses);

verifyEqual(testCase, result.status, "compared");
verifyNotEmpty(testCase, result.comparison);
verifyEqual(testCase, result.screen_probe_role, "whole_dataset");
verifyEqual(testCase, result.subset_probe_role, "subset");
verifyEqual(testCase, sum(result.category_contingency.factor_response_pairs), ...
    height(result.comparison));

% Every factor-response pair has exactly one row, and every category is in the
% fixed vocabulary on both sides.
identity = result.comparison(:, ["response", "qualifier", "secondary", ...
    "factor_name"]);
verifyEqual(testCase, height(unique(identity, "rows")), height(identity));
allowed = [result.category_vocabulary; "not_observed"];
verifyTrue(testCase, all(ismember(result.comparison.screen_category, allowed)));
verifyTrue(testCase, all(ismember(result.comparison.subset_category, allowed)));

verifySubstring(testCase, result.calibration_note, ...
    "does NOT establish that manual calibration is unnecessary");

reportFixtureFigures(context, screenLeverage, subsetLeverage, result);
end

function reportFixtureFigures(context, screenLeverage, subsetLeverage, result)
%REPORTFIXTUREFIGURES Print what the fixture actually produced.
%
% Printed rather than asserted. These are the numbers the handoff quotes for
% Parts 11, 14 and 15 - the support-pattern count ranges, which factors diverged,
% and what the subset bought - and a handoff that quoted them from memory would
% drift from the code the first time either changed.
fprintf("\n[part10] screen %s/%d cfg, subset %s/%d cfg, de-aliased %d\n", ...
    context.screenDesign.design_type, ...
    context.screenDesign.configuration_count, ...
    context.subsetDesign.design_type, ...
    context.subsetDesign.configuration_count, ...
    context.subsetDesign.screen_comparison.de_aliased_count);
fprintf("[part10] recordings: screen %d, subset %d (requested %g)\n", ...
    context.dataset.recording_count, context.subsetDataset.recording_count, ...
    context.subsetDesign.sizing.subset_requested_size);
fprintf("[part10] screen categories:\n");
disp(screenLeverage.category_counts);
fprintf("[part10] subset categories:\n");
disp(subsetLeverage.category_counts);
fprintf("[part10] contingency:\n");
disp(result.category_contingency);
fprintf("[part10] factor summary:\n");
disp(result.factor_summary);
fprintf("[part10] weak or aliased:\n");
disp(result.weak_or_aliased_factors);
fprintf("[part10] support-pattern movement, screen:\n");
disp(result.support_pattern_movement.screen_top);
fprintf("[part10] support-pattern movement, subset:\n");
disp(result.support_pattern_movement.subset_top);

patterns = context.screenResponses.support_pattern_vocabulary;
fprintf("[part10] screen support-pattern vocabulary: %s\n", ...
    strjoin(string(patterns(:))', ", "));
rows = context.screenResponses.responses;
counts = rows(rows.response == "support_pattern_groups" & ...
    rows.scope == "pooled", :);
fprintf("[part10] pooled support-pattern group counts: min %g, max %g\n", ...
    min(counts.value), max(counts.value));
end

% ---------------------------------------------------------------- tripwire ---

function testNoResponseFamilyWasReimplementedInThisPart(testCase)
%TESTNORESPONSEFAMILYWASREIMPLEMENTED... Two implementations would diverge.
%
% Two implementations of "exact support-pattern count" would eventually disagree,
% and the disagreement would surface as a false concordance finding: the two
% probes appearing to differ because the code differs, not because the data do.
% The check is that Part 10's files contain no response arithmetic at all - no
% query, no counting - which is the property that makes a second implementation
% impossible rather than merely absent today.
% The tokens are the DATA-ACCESS VERBS, not column names. `probeConcordance`
% names `supported_extractor_pair_pattern` in a returned explanatory string -
% saying that the patterns it compares are exact rather than binned by a coarse
% count is worth saying - and a scan that could not tell a sentence from a query
% would force that explanation out. Once a file issues no query and calls into no
% other package, it cannot recompute a response whatever it mentions.
root = repoRootPath();
forbidden = ["SELECT ", "INSERT INTO", "UPDATE ", "DELETE FROM", ...
    "fetch(", "execute(", "sqlite(", ...
    "vawlume.agreement.", "vawlume.matching.", "vawlume.consilience."];
for name = ["subsetDesign.m", "leverageCategories.m", "probeConcordance.m"]
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", ...
        name)));
    for token = forbidden
        verifyEqual(testCase, numel(strfind(source, token)), 0, ...
            name + " contains '" + token + "'.");
    end
end

% A FILTER NAMES ONE FAMILY; A RE-IMPLEMENTATION NEEDS THE VOCABULARY. The
% concordance layer legitimately mentions `support_pattern_groups`, because it
% has to select those rows to compare support-pattern movement. What it must not
% do is enumerate the families, which is what a second response layer would have
% to do, so the check is on how many it names rather than on whether it names
% any.
families = edaFamilyNames();
for name = ["subsetDesign.m", "leverageCategories.m", "probeConcordance.m"]
    source = string(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    named = families(arrayfun(@(f) contains(source, f), families));
    verifyLessThanOrEqual(testCase, numel(named), 1, ...
        name + " names " + numel(named) + " response families (" + ...
        strjoin(named, ", ") + "), which is a vocabulary rather than a " + ...
        "filter.");
end

% And no NEW file enumerates the families. Two files legitimately do -
% edaResponseVocabulary.m declares the vocabulary and screenResponses.m produces
% the rows - and both predate this part. A third would be a second response
% layer, which is the thing that would eventually disagree with the first and
% surface as a false concordance finding.
allowed = ["edaResponseVocabulary.m"; "screenResponses.m"];
enumerating = strings(0, 1);
files = dir(fullfile(root, "src", "+vawlume", "+eda", "**", "*.m"));
for index = 1:numel(files)
    source = string(fileread(fullfile(files(index).folder, files(index).name)));
    if sum(arrayfun(@(f) contains(source, f), families)) >= 5
        enumerating(end + 1, 1) = string(files(index).name); %#ok<AGROW>
    end
end
verifyEqual(testCase, sort(enumerating), sort(allowed), ...
    "The set of files enumerating the response vocabulary changed.");
end

function value = edaFamilyNames()
value = ["detections_considered"; "pairwise_match_groups"; ...
    "agreement_groups_total"; "agreement_groups_by_member_count"; ...
    "agreement_groups_by_extractor_count"; "support_pattern_groups"; ...
    "support_pattern_fraction"; "coarse_support_groups"; ...
    "extractor_unique_groups"; "extractor_unique_fraction"; ...
    "ambiguous_groups"; "unambiguous_one_to_one_groups"; ...
    "group_change_from"; "group_change_to"; "group_retention_fraction"];
end

function testNothingOutsideTheEdaPackageNeededEditing(testCase)
%TESTNOTHINGOUTSIDETHEEDAPACKAGE... The itinerary's tripwire, as a check.
%
% Asserted against the working tree rather than trusted: the claim is that Part
% 10 touched no file under +matching, +agreement or schema/, and a claim about
% what was not edited is worth a test that can catch a later edit too.
root = repoRootPath();
[status, output] = system("git -C """ + root + """ status --porcelain");
verifyEqual(testCase, status, 0, "git status failed.");

changed = strtrim(splitlines(string(output)));
changed = changed(strlength(changed) > 0);
guarded = ["src/+vawlume/+matching/", "src/+vawlume/+agreement/", "schema/"];
for line = changed'
    path = extractAfter(line, 3);
    for prefix = guarded
        verifyFalse(testCase, startsWith(path, prefix), ...
            "Part 10 modified a guarded path: " + path);
    end
end
end

% ---------------------------------------------------------------- helpers ---

function context = twoProbeContext(fixture, options)
%TWOPROBECONTEXT Both probes of one exploration run, over the fixture.
%
% Three factors, and the screen is forced to four configurations so it is a
% genuine resolution-III fraction with its main effects aliased. The subset probe
% then affords the full factorial under its own budget, which is the situation
% the second probe exists for. Both designs come from the same probeParameters resolution, which is what
% guarantees the factor sets match.
arguments
    fixture
    options.Apply (1,1) logical = true
end

selector = struct(project_key="phase1_synthetic_fixture");
dataset = vawlume.eda.resolveDataset(fixture.conn, selector);

resolution = vawlume.eda.probeParameters( ...
    struct(metrics=table(zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["temporal_iou", "abs_onset_difference_s", ...
    "abs_offset_difference_s"]), ...
    metric_names=["temporal_iou", "abs_onset_difference_s", ...
    "abs_offset_difference_s"]), ...
    vawlume.eda.explorationOptions(struct( ...
        threshold_ranges=struct(min_temporal_iou=[0.05 0.95], ...
            max_abs_onset_difference_s=[0.05 0.50], ...
            max_abs_offset_difference_s=[0.05 0.50]), ...
        disabled_factors="max_abs_duration_difference_s")));

screenDesign = vawlume.eda.screeningDesign(resolution, ...
    MaximumConfigurations=4);
materialized = vawlume.eda.materializeConfigurations(screenDesign, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
screenRun = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=options.Apply, ...
    ProbeRole="whole_dataset");

strata = vawlume.eda.resolveStrata(fixture.conn, ...
    dataset.recordings.recording_id);
subset = vawlume.eda.sampleRecordings(strata, Seed=11);

subsetDataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture", ...
    recording_ids=subset.selected_recording_ids));
subsetDesign = vawlume.eda.subsetDesign(resolution, screenDesign, ...
    subsetDataset, Subset=subset);

% The SAME exploration run key, so the two probes share one exploration run and
% a configuration common to both is one analysis rather than two.
subsetMaterialized = vawlume.eda.materializeConfigurations(subsetDesign, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch, ...
    ExplorationRunKey=materialized.exploration_run_key);
subsetRun = vawlume.eda.runScreen(fixture.conn, subsetDataset, ...
    subsetMaterialized, RepoRoot=fixture.repo_root, Apply=options.Apply, ...
    ProbeRole="subset");

context = struct(dataset=dataset, resolution=resolution, ...
    screenDesign=screenDesign, screenRun=screenRun, ...
    subset=subset, subsetDataset=subsetDataset, ...
    subsetDesign=subsetDesign, subsetRun=subsetRun);

if ~options.Apply
    return
end

context.screenResponses = vawlume.eda.screenResponses(fixture.conn, ...
    screenRun, screenDesign);
context.subsetResponses = vawlume.eda.screenResponses(fixture.conn, ...
    subsetRun, subsetDesign);
context.screenEffects = vawlume.eda.mainEffects(context.screenResponses, ...
    screenDesign, OnIncompleteDesign="label");
context.subsetEffects = vawlume.eda.mainEffects(context.subsetResponses, ...
    subsetDesign, OnIncompleteDesign="label");
end

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function value = codeOnly(source)
lines = splitlines(string(source));
value = strjoin(lines(~startsWith(strtrim(lines), "%")), newline);
end

% ---------------------------------------------------------------- fixture ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "subset-probe.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
prepareAdditionalRecordings(conn);
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);
end

function path = fixtureTemplate(repoRoot)
persistent value
if isempty(value) || ~isfile(value)
    value = string(tempname) + ".sqlite";
    [conn, ~] = vawlume.db.createPhase1FixtureDatabase(value, repoRoot);
    close(conn);
end
path = value;
end

function tearDown(conn, scratch, repoRoot)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

function prepareAdditionalRecordings(conn)
%PREPAREADDITIONALRECORDINGS Enough usable recordings for a subset to be a subset.
%
% The phase-1 fixture carries two recordings and only one survives
% resolveDataset's validation, so a "subset" of it would be the whole thing and
% every claim about sizing, reuse and concordance would be vacuous. Six
% recordings, each carrying all three extractors with overlapping detections,
% make the subset genuinely smaller than the frame.
%
% Recording sizes differ on purpose. Equal recordings would let a pooled fraction
% and an averaged one agree exactly, and the response layer's pooling rule would
% go untested through this path too.
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key,status) VALUES" + ...
    "(80,1,2,'fixture_mupet_baseline_v1','imported')," + ...
    "(81,1,3,'fixture_usvseg_baseline_v1','imported')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id,input_role) VALUES(80,2,'source_audio'),(81,2,'source_audio')");
insertDetection(conn, 3, 2, "ds-baseline-2", 20.000, 20.060);
insertDetection(conn, 80, 2, "mupet-baseline-1", 20.004, 20.052);
insertDetection(conn, 81, 2, "usvseg-baseline-1", 20.002, 20.049);
insertDetection(conn, 81, 2, "usvseg-baseline-3", 30.000, 30.040);

sourceFileId = nextId(conn, "source_files", "source_file_id");
runId = 90;
for recordingId = 3:6
    native = sprintf("REC_EXTRA_%02d", recordingId);
    execute(conn, "INSERT INTO source_files(source_file_id,project_id," + ...
        "file_role,path_or_uri,relative_path,filename) VALUES(" + ...
        string(sourceFileId) + ",1,'recording_audio','audio/" + native + ...
        ".wav','audio/" + native + ".wav','" + native + ".wav')");
    execute(conn, "INSERT INTO recordings(recording_id,project_id," + ...
        "source_file_id,native_recording_id) VALUES(" + string(recordingId) + ...
        ",1," + string(sourceFileId) + ",'" + native + "')");
    sourceFileId = sourceFileId + 1;

    % One run per extractor version, so every recording carries the same
    % extractor set and resolveDataset's uniformity check is satisfied.
    for versionId = 1:3
        execute(conn, "INSERT INTO extraction_runs(extraction_run_id," + ...
            "project_id,extractor_version_id,run_key,status) VALUES(" + ...
            string(runId) + ",1," + string(versionId) + ",'fixture_extra_r" + ...
            string(recordingId) + "_v" + string(versionId) + "','imported')");
        execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
            "recording_id,input_role) VALUES(" + string(runId) + "," + ...
            string(recordingId) + ",'source_audio')");
        callCount = 2 + mod(recordingId + versionId, 3);
        for call = 1:callCount
            base = 5 * call + 0.01 * versionId;
            insertDetection(conn, runId, recordingId, ...
                sprintf("extra-r%d-v%d-%d", recordingId, versionId, call), ...
                base, base + 0.05 + 0.005 * versionId);
        end
        runId = runId + 1;
    end
end
end

function value = nextId(conn, tableName, column)
rows = fetch(conn, "SELECT IFNULL(MAX(" + column + "),0) + 1 AS n FROM " + ...
    tableName);
value = double(rows.n(1));
end

function insertDetection(conn, runId, recordingId, nativeId, startS, endS)
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES(" + ...
    string(runId) + "," + string(recordingId) + ",'" + nativeId + "'," + ...
    sprintf("%.17g", startS) + "," + sprintf("%.17g", endS) + ...
    ",'profile_selected_event_geometry')");
end
