function tests = test_eda_screen_responses
%TEST_EDA_SCREEN_RESPONSES Assembling a probe's responses from stored rows.
%
% The responses are what the screen is actually about, so the assertions here are
% about faithfulness rather than plumbing: exact support patterns are not binned,
% an absent category is an explicit zero, a fraction equals its stated counts,
% and a pooled fraction is recomputed from pooled counts rather than averaged.
%
% The pooling test is built so the two rules give DIFFERENT answers. A pooling
% test over recordings of equal size proves nothing, because both rules agree
% there and the wrong one would pass.
tests = functiontests(localfunctions);
end

% ---------------------------------------------------------- the contract ---

function testResponsesCoverEveryFamilyPerConfigurationAndRecording(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);

verifyEqual(testCase, summary.status, "summarized");
verifyEqual(testCase, numel(summary.configuration_ids), 2);
verifyEqual(testCase, sort(summary.recording_ids), [1 2]);

families = unique(summary.responses.response);
expected = ["agreement_groups_by_extractor_count"
    "agreement_groups_by_member_count"
    "agreement_groups_total"
    "ambiguous_groups"
    "coarse_support_groups"
    "detections_considered"
    "extractor_unique_fraction"
    "extractor_unique_groups"
    "group_change_from"
    "group_change_to"
    "group_retention_fraction"
    "pairwise_match_groups"
    "support_pattern_fraction"
    "support_pattern_groups"
    "unambiguous_one_to_one_groups"];
verifyEqual(testCase, families, expected);
verifyTrue(testCase, all(ismember(families, ...
    summary.response_vocabulary.response)));

% Both scopes are present and the key columns are declared.
verifyEqual(testCase, sort(unique(summary.responses.scope)), ...
    ["pooled"; "recording"]);
verifyTrue(testCase, ismember("qualifier_kind", summary.key_columns));

clear cleanup
end

function testEveryRowCarriesItsConfigurationsFactorLevel(testCase)
% A consumer filtering the long table for one response must not have to join
% back to the design to know which factor level produced each value.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);

verifyTrue(testCase, ismember("min_temporal_iou", ...
    string(summary.responses.Properties.VariableNames)));
verifyTrue(testCase, ismember("min_temporal_iou_level", ...
    string(summary.responses.Properties.VariableNames)));
verifyEqual(testCase, sort(unique(summary.responses.min_temporal_iou_level)), ...
    ["high"; "low"]);

clear cleanup
end

% ------------------------------------------------------- support patterns ---

function testExactSupportPatternsAreCountedWithoutBinningByCoarseK(testCase)
% Two groups can support the same NUMBER of extractor pairs while supporting
% different pairs. Binning them would report agreement that was never observed.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
loose = looseConfiguration(probe);

patterns = pooledRows(summary, "support_pattern_groups", loose);
verifyGreaterThan(testCase, height(patterns), 1);

% Every pattern names the extractor pairs it supports, never a count of them.
% A pair key joins two extractor keys, so a qualifier that is a bare number
% would mean the patterns had been binned by coarse K.
named = patterns(patterns.qualifier ~= "(none)", :);
verifyGreaterThan(testCase, height(named), 0);
for index = 1:height(named)
    qualifier = named.qualifier(index);
    verifyTrue(testCase, contains(qualifier, "--"), ...
        "'" + qualifier + "' does not name an extractor pair");
    verifyTrue(testCase, isnan(str2double(qualifier)), ...
        "'" + qualifier + "' is a bare count, so patterns were binned");
end

% The single-pair patterns are distinct rows even though each is 1 of 3.
singles = named(~contains(named.qualifier, "|"), :);
verifyGreaterThanOrEqual(testCase, height(singles), 2);
verifyEqual(testCase, numel(unique(singles.qualifier)), height(singles));

% The coarse count accompanies rather than replaces them: the two responses
% coexist and the coarse one sums to the same total.
coarse = pooledRows(summary, "coarse_support_groups", loose);
verifyEqual(testCase, sum(coarse.value), sum(patterns.value));
verifyTrue(testCase, all(~contains(coarse.qualifier, "|")));

clear cleanup
end

function testSupportPatternCountsMatchTheAgreementViewExactly(testCase)
% Known input, known output: the counts must equal what the agreement layer's
% own view reports for the same analyses, not an approximation of it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
loose = looseConfiguration(probe);

stored = fetch(fixture.conn, "SELECT s.supported_extractor_pair_pattern " + ...
    "AS pattern, COUNT(*) AS n FROM v_agreement_group_summary s " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=s.analysis_run_id " + ...
    "WHERE ar.run_key LIKE '%/" + loose + "/a/r%' " + ...
    "GROUP BY s.supported_extractor_pair_pattern");
expected = containers.Map("KeyType", "char", "ValueType", "double");
for index = 1:height(stored)
    % MATLAB's SQLite interface returns an empty text column as <missing>, so
    % the group that supports no extractor pair arrives here as missing rather
    % than as "". The production path normalizes it through
    % agreement.selectPopulation; this direct query has to do the same.
    key = string(stored.pattern(index));
    if ismissing(key) || strlength(key) == 0
        key = "(none)";
    end
    expected(char(key)) = double(stored.n(index));
end

actual = pooledRows(summary, "support_pattern_groups", loose);
for index = 1:height(actual)
    key = char(actual.qualifier(index));
    if isKey(expected, key)
        verifyEqual(testCase, actual.value(index), expected(key), key);
    else
        verifyEqual(testCase, actual.value(index), 0, ...
            key + " should be an explicit zero");
    end
end
verifyEqual(testCase, sum(actual.value), ...
    sum(cell2mat(values(expected))));

clear cleanup
end

function testAPatternAbsentFromOneConfigurationIsAnExplicitZero(testCase)
% Effects are differences across configurations, so a missing row would silently
% shorten the vector the difference is computed over.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);

vocabulary = summary.support_pattern_vocabulary;
verifyGreaterThan(testCase, numel(vocabulary), 1);
for configurationIndex = 1:numel(summary.configuration_ids)
    configuration = summary.configuration_ids(configurationIndex);
    rows = pooledRows(summary, "support_pattern_groups", configuration);
    verifyEqual(testCase, sort(rows.qualifier), sort(reshape(vocabulary, [], 1)), ...
        "configuration " + configuration + " is missing a pattern row");
end

% At least one of those rows is a zero that was filled rather than observed,
% or this test is asserting over a probe where nothing changed.
allRows = summary.responses(summary.responses.response == ...
    "support_pattern_groups" & summary.responses.scope == "pooled", :);
verifyGreaterThan(testCase, nnz(allRows.value == 0), 0);

clear cleanup
end

% -------------------------------------------------- denominators and pooling ---

function testEveryFractionEqualsItsCountsOverItsStatedDenominator(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
responses = summary.responses;

fractions = responses(responses.value_kind == "fraction" & ...
    responses.response == "extractor_unique_fraction", :);
verifyGreaterThan(testCase, height(fractions), 0);
for index = 1:height(fractions)
    row = fractions(index, :);
    counts = responses(responses.response == "extractor_unique_groups" & ...
        responses.scope == row.scope & ...
        responses.configuration_id == row.configuration_id & ...
        responses.qualifier == row.qualifier, :);
    if row.scope == "recording"
        counts = counts(counts.recording_id == row.recording_id, :);
    end
    verifyEqual(testCase, height(counts), 1);
    verifyEqual(testCase, row.value, counts.value / row.denominator, ...
        AbsTol=1e-12);
end

% Every fraction row states a denominator; no count row pretends to have one.
verifyTrue(testCase, all(isfinite(fractions.denominator)));
verifyTrue(testCase, all(isnan(responses.denominator( ...
    responses.value_kind == "count"))));

clear cleanup
end

function testPooledFractionsAreRecomputedFromPooledCountsNotAveraged(testCase)
% The fixture's two recordings carry deliberately unequal detection counts, so
% the mean of per-recording fractions and the fraction of pooled counts give
% different answers. A pooling test over equal recordings would pass under
% either rule and prove nothing.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
responses = summary.responses;

denominators = responses(responses.response == "detections_considered" & ...
    responses.scope == "recording", :);
firstRecording = sum(denominators.value(denominators.recording_id == 1));
secondRecording = sum(denominators.value(denominators.recording_id == 2));
verifyNotEqual(testCase, firstRecording, secondRecording, ...
    "The two recordings must differ in size for this test to mean anything.");

examined = 0;
for configurationIndex = 1:numel(summary.configuration_ids)
    configuration = summary.configuration_ids(configurationIndex);
    keys = unique(responses.qualifier(responses.response == ...
        "extractor_unique_fraction"));
    for keyIndex = 1:numel(keys)
        perRecording = responses(responses.response == ...
            "extractor_unique_fraction" & responses.scope == "recording" & ...
            responses.configuration_id == configuration & ...
            responses.qualifier == keys(keyIndex), :);
        pooled = responses(responses.response == ...
            "extractor_unique_fraction" & responses.scope == "pooled" & ...
            responses.configuration_id == configuration & ...
            responses.qualifier == keys(keyIndex), :);
        verifyEqual(testCase, height(pooled), 1);

        numerator = sum(perRecording.value .* perRecording.denominator);
        denominator = sum(perRecording.denominator);
        verifyEqual(testCase, pooled.value, numerator / denominator, ...
            AbsTol=1e-12);
        verifyEqual(testCase, pooled.denominator, denominator, AbsTol=1e-12);

        naive = mean(perRecording.value);
        if abs(naive - pooled.value) > 1e-9
            examined = examined + 1;
        end
    end
end
verifyGreaterThan(testCase, examined, 0, ...
    "No fraction distinguished the two pooling rules, so this test did not " + ...
    "exercise the rule it exists to check.");
verifyTrue(testCase, contains(summary.pooling_rule, "never averaged"));

clear cleanup
end

function testPooledCountsAreSumsOfPerRecordingCounts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
responses = summary.responses;
configuration = summary.configuration_ids(1);

perRecording = responses(responses.response == "agreement_groups_total" & ...
    responses.scope == "recording" & ...
    responses.configuration_id == configuration, :);
pooled = responses(responses.response == "agreement_groups_total" & ...
    responses.scope == "pooled" & ...
    responses.configuration_id == configuration, :);
verifyEqual(testCase, height(perRecording), 2);
verifyEqual(testCase, pooled.value, sum(perRecording.value));

clear cleanup
end

% ------------------------------------------------------- change measures ---

function testChangeMeasuresConserveGroupCountsOnBothSides(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
responses = summary.responses;

for configurationIndex = 1:numel(summary.configuration_ids)
    configuration = summary.configuration_ids(configurationIndex);
    for recordingId = summary.recording_ids
        fromRows = responses(responses.response == "group_change_from" & ...
            responses.scope == "recording" & ...
            responses.configuration_id == configuration & ...
            responses.recording_id == recordingId, :);
        baselineTotal = totalGroups(responses, ...
            summary.baseline_configuration_id, recordingId);
        verifyEqual(testCase, sum(fromRows.value), baselineTotal, ...
            "from-side classes must partition the baseline's groups");

        toRows = responses(responses.response == "group_change_to" & ...
            responses.scope == "recording" & ...
            responses.configuration_id == configuration & ...
            responses.recording_id == recordingId, :);
        verifyEqual(testCase, sum(toRows.value), ...
            totalGroups(responses, configuration, recordingId), ...
            "to-side classes must partition this configuration's groups");
    end
end

clear cleanup
end

function testTheBaselineComparesToItselfAsFullyRetained(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
baseline = summary.baseline_configuration_id;

retained = pooledRows(summary, "group_change_from", baseline);
retainedCount = retained.value(retained.qualifier == "retained");
verifyEqual(testCase, retainedCount, ...
    pooledScalar(summary, "agreement_groups_total", baseline));

fractionRow = pooledRows(summary, "group_retention_fraction", baseline);
verifyEqual(testCase, fractionRow.value, 1, AbsTol=1e-12);

clear cleanup
end

function testAStricterConfigurationSplitsGroupsRatherThanLosingThem(testCase)
% Two configurations of one agreement analysis partition the same detections, so
% a stricter threshold can only divide groups - never make detections vanish.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
strict = strictConfiguration(probe);

rows = pooledRows(summary, "group_change_from", strict);
verifyEqual(testCase, rows.value(rows.qualifier == "lost"), 0);
verifyEqual(testCase, rows.value(rows.qualifier == "gained"), 0);
verifyGreaterThan(testCase, rows.value(rows.qualifier == "split"), 0);

verifyGreaterThan(testCase, ...
    pooledScalar(summary, "agreement_groups_total", strict), ...
    pooledScalar(summary, "agreement_groups_total", ...
    summary.baseline_configuration_id));

clear cleanup
end

% ------------------------------------------------------- effects on a probe ---

function testEffectsAreEstimatedFromThePooledResponses(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
effects = vawlume.eda.mainEffects(summary, probe.design);

verifyTrue(testCase, effects.design_is_complete);
row = effects.effects(effects.effects.response == "agreement_groups_total" & ...
    effects.effects.effect == "A", :);
verifyEqual(testCase, height(row), 1);

loose = pooledScalar(summary, "agreement_groups_total", ...
    looseConfiguration(probe));
strict = pooledScalar(summary, "agreement_groups_total", ...
    strictConfiguration(probe));
verifyEqual(testCase, row.estimate, strict - loose, AbsTol=1e-12);
verifyEqual(testCase, row.response_range, abs(strict - loose), AbsTol=1e-12);

clear cleanup
end

function testAConstantResponseIsVisibleAsAZeroRange(testCase)
% detections_considered cannot vary with a matching threshold: it is the
% denominator, not a response to it. Its zero range is how a consumer tells "no
% information" from "no leverage".
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
effects = vawlume.eda.mainEffects(summary, probe.design);

rows = effects.effects(effects.effects.response == "detections_considered", :);
verifyGreaterThan(testCase, height(rows), 0);
verifyEqual(testCase, rows.estimate, zeros(height(rows), 1), AbsTol=1e-12);
verifyEqual(testCase, rows.response_range, zeros(height(rows), 1), AbsTol=1e-12);

clear cleanup
end

% ------------------------------------------------------------ arbitrary N ---

function testTheSameFunctionsRunOverATwoExtractorRecording(testCase)
% One extractor pair instead of three, through the same code path, with no
% function naming an extractor or assuming how many there are.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture, Runs=["fixture_deepsqueak_social_v1", ...
    "fixture_mupet_social_v1"], Recordings=1);
summary = vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);

verifyEqual(testCase, probe.dataset.extractor_count, 2);
verifyEqual(testCase, probe.dataset.pairs_per_recording, 1);
verifyGreaterThan(testCase, height(summary.responses), 0);

patterns = pooledRows(summary, "support_pattern_groups", ...
    summary.configuration_ids(1));
verifyGreaterThan(testCase, height(patterns), 0);
% With two extractors there is exactly one pair, so no pattern names two.
verifyFalse(testCase, any(contains(patterns.qualifier, "|")));

effects = vawlume.eda.mainEffects(summary, probe.design);
verifyGreaterThan(testCase, height(effects.effects), 0);

clear cleanup
end

% ------------------------------------------------------------- refusals ---

function testADryRunProducesNoResponses(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture, Apply=false);
verifyError(testCase, @() vawlume.eda.screenResponses(fixture.conn, ...
    probe.run, probe.design), "vawlume:eda:NoUsableAgreementAnalyses");

clear cleanup
end

function testAnUnknownBaselineIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
verifyError(testCase, @() vawlume.eda.screenResponses(fixture.conn, ...
    probe.run, probe.design, BaselineConfigurationId="cfg-nonexistent"), ...
    "vawlume:eda:BaselineConfigurationNotPresent");

clear cleanup
end

function testNothingIsWrittenWhileSummarizing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
probe = runProbe(fixture);
before = tableCounts(fixture.conn);
vawlume.eda.screenResponses(fixture.conn, probe.run, probe.design);
verifyEqual(testCase, tableCounts(fixture.conn), before);

root = repoRootPath();
for name = ["screenResponses.m", "mainEffects.m", "groupChanges.m"]
    text = string(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for forbidden = ["INSERT INTO", "UPDATE ", "DELETE FROM", "sqlwrite("]
        verifyFalse(testCase, contains(body, forbidden), ...
            name + " contains " + forbidden);
    end
end

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function probe = runProbe(fixture, options)
arguments
    fixture
    options.Apply (1,1) logical = true
    options.Runs (1,:) string = strings(1, 0)
    options.Recordings (1,:) double = []
end
selector = struct(project_key="phase1_synthetic_fixture");
if ~isempty(options.Runs)
    selector.extraction_run_keys = options.Runs;
end
if ~isempty(options.Recordings)
    selector.recording_ids = options.Recordings;
end
dataset = vawlume.eda.resolveDataset(fixture.conn, selector);

% One screened factor spanning a wide IoU range, so the two configurations
% genuinely group the detections differently rather than differing on paper.
resolution = vawlume.eda.probeParameters( ...
    struct(metrics=table(zeros(0, 1), VariableNames="temporal_iou"), ...
    metric_names="temporal_iou"), ...
    vawlume.eda.explorationOptions(struct( ...
        threshold_ranges=struct(min_temporal_iou=[0.05 0.95]), ...
        disabled_factors=["max_abs_onset_difference_s", ...
            "max_abs_offset_difference_s", ...
            "max_abs_duration_difference_s"])));
design = vawlume.eda.screeningDesign(resolution);
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
run = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=options.Apply);
probe = struct(dataset=dataset, design=design, materialized=materialized, ...
    run=run);
end

function value = looseConfiguration(probe)
%LOOSECONFIGURATION The run at the low min_temporal_iou, which is the -1 level.
value = probe.design.configurations.configuration_id( ...
    probe.design.coding(:, 1) < 0);
value = value(1);
end

function value = strictConfiguration(probe)
value = probe.design.configurations.configuration_id( ...
    probe.design.coding(:, 1) > 0);
value = value(1);
end

function value = pooledRows(summary, response, configuration)
rows = summary.responses;
value = rows(rows.response == response & rows.scope == "pooled" & ...
    rows.configuration_id == configuration, :);
end

function value = pooledScalar(summary, response, configuration)
rows = pooledRows(summary, response, configuration);
value = rows.value(1);
end

function value = totalGroups(responses, configuration, recordingId)
rows = responses(responses.response == "agreement_groups_total" & ...
    responses.scope == "recording" & ...
    responses.configuration_id == configuration & ...
    responses.recording_id == recordingId, :);
value = rows.value(1);
end

function counts = tableCounts(conn)
names = ["analysis_runs", "agreement_groups", "agreement_group_members", ...
    "candidate_pairs", "match_groups", "config_profiles", ...
    "config_profile_versions", "detections"];
counts = struct();
for name = names
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + name);
    counts.(name) = double(rows.n(1));
end
end

function insertDetection(conn, runId, recordingId, nativeId, startS, endS)
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES(" + ...
    string(runId) + "," + string(recordingId) + ",'" + nativeId + "'," + ...
    sprintf("%.17g", startS) + "," + sprintf("%.17g", endS) + ...
    ",'profile_selected_event_geometry')");
end

function prepareSecondRecording(conn)
%PREPARESECONDRECORDING A second recording, deliberately smaller than the first.
%
% The size difference is load-bearing. Pooled fractions and averaged
% per-recording fractions agree exactly when recordings are the same size, so a
% fixture with equal recordings would pass under either pooling rule and the
% pooling test would assert nothing.
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key,status) VALUES" + ...
    "(80,1,2,'fixture_mupet_baseline_v1','imported')," + ...
    "(81,1,3,'fixture_usvseg_baseline_v1','imported')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id,input_role) VALUES(80,2,'source_audio'),(81,2,'source_audio')");
insertDetection(conn, 3, 2, "ds-baseline-2", 20.000, 20.060);
insertDetection(conn, 80, 2, "mupet-baseline-1", 10.004, 10.052);
insertDetection(conn, 81, 2, "usvseg-baseline-1", 10.002, 10.049);
insertDetection(conn, 81, 2, "usvseg-baseline-3", 30.000, 30.040);
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "screen-responses.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
prepareSecondRecording(conn);
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
