function tests = test_eda_probe_parameters
%TEST_EDA_PROBE_PARAMETERS The probe-parameter resolver and its configuration surface.
%
% This is where the promise of a light configuration surface is kept or broken.
% The system is allowed to choose its own probe values; it is not allowed to
% choose invisibly, and it is never allowed to choose in a way that could be
% described as optimizing.
%
% Two tests carry disproportionate weight. The unknown-field test stops a
% misspelled override from producing a run that looks configured and is not. The
% anti-pruning test stops a future "improvement" that drops a redundant factor,
% which the conceptual specification forbids and which nothing else would catch.
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

% --------------------------------------------- the configuration surface ---

function testDefaultsAreReturnedAndDocumented(testCase)
options = vawlume.eda.explorationOptions();
verifyTrue(testCase, options.enabled);
verifyTrue(testCase, isempty(options.seed));
verifyTrue(testCase, isempty(options.analysis_budget));
verifyTrue(testCase, isempty(options.subset_size));
verifyEqual(testCase, options.minimum_supported_observations, 10);
verifyEqual(testCase, options.disabled_factors, strings(0, 1));
end

function testAnUnknownOptionFieldIsRejectedNotIgnored(testCase)
% A silently dropped override produces a run that looks configured and is not,
% and the record would faithfully report the default that was actually used.
verifyError(testCase, @() vawlume.eda.explorationOptions( ...
    struct(sed=42)), "vawlume:eda:UnknownOption");
verifyError(testCase, @() vawlume.eda.explorationOptions( ...
    struct(seed=42, subsetsize=8)), "vawlume:eda:UnknownOption");
% The correctly spelled neighbours still work, so the rejection is about the
% name rather than about strictness in general.
verifyEqual(testCase, vawlume.eda.explorationOptions( ...
    struct(seed=42, subset_size=8)).subset_size, 8);
end

function testMalformedOptionValuesAreRefused(testCase)
verifyError(testCase, @() vawlume.eda.explorationOptions(struct(seed=-1)), ...
    "vawlume:eda:OptionInvalid");
verifyError(testCase, @() vawlume.eda.explorationOptions(struct(seed=1.5)), ...
    "vawlume:eda:OptionInvalid");
verifyError(testCase, @() vawlume.eda.explorationOptions( ...
    struct(subset_size=0)), "vawlume:eda:OptionInvalid");
verifyError(testCase, @() vawlume.eda.explorationOptions( ...
    struct(disabled_factors="not_a_factor")), "vawlume:eda:UnknownFactor");
verifyError(testCase, @() vawlume.eda.explorationOptions( ...
    struct(threshold_ranges=struct(nope=[1 2]))), "vawlume:eda:UnknownFactor");
end

function testAThresholdRangeMustBeOrderedAndInBounds(testCase)
% Reordering silently would invert the design's factor coding, so an unordered
% pair is refused rather than sorted.
verifyError(testCase, @() vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.5 0.2]))), ...
    "vawlume:eda:ThresholdRangeInvalid");
verifyError(testCase, @() vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.2 1.5]))), ...
    "vawlume:eda:ThresholdRangeInvalid");
verifyError(testCase, @() vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(max_abs_onset_difference_s=[-1 1]))), ...
    "vawlume:eda:ThresholdRangeInvalid");
verifyError(testCase, @() vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.2 0.3 0.4]))), ...
    "vawlume:eda:ThresholdRangeInvalid");
end

% ---------------------------------------------------------- determinism ---

function testIdenticalInputsProduceIdenticalRecords(testCase)
surface = standardSurface();
first = vawlume.eda.probeParameters(surface);
second = vawlume.eda.probeParameters(surface);
verifyEqual(testCase, first.factors, second.factors);
verifyEqual(testCase, first.seed, second.seed);
verifyEqual(testCase, first.active_factor_names, second.active_factor_names);
end

function testAnUnseededRunRecordsASeedThatReproducesIt(testCase)
surface = standardSurface();
unseeded = vawlume.eda.probeParameters(surface);
verifyEqual(testCase, unseeded.seed_source, "derived_from_dataset_identity");
verifyTrue(testCase, isfinite(unseeded.seed));
verifyGreaterThanOrEqual(testCase, unseeded.seed, 0);
verifyTrue(testCase, strlength(unseeded.seed_basis) > 0, ...
    "The derivation must be reconstructible, not merely repeatable.");

replayed = vawlume.eda.probeParameters(surface, ...
    vawlume.eda.explorationOptions(struct(seed=unseeded.seed)));
verifyEqual(testCase, replayed.seed, unseeded.seed);
verifyEqual(testCase, replayed.seed_source, "user");
verifyEqual(testCase, replayed.factors, unseeded.factors);
end

function testDifferentDatasetsResolveDifferentSeeds(testCase)
% Derived from dataset identity rather than fixed, so a user who never sets a
% seed does not get the same positional draw pattern in every study.
a = standardSurface("project-a", "pair_ds_mupet");
b = standardSurface("project-a", "pair_ds_usvseg");
c = standardSurface("project-b", "pair_ds_mupet");
seeds = [vawlume.eda.probeParameters(a).seed, ...
    vawlume.eda.probeParameters(b).seed, ...
    vawlume.eda.probeParameters(c).seed];
verifyEqual(testCase, numel(unique(seeds)), 3);
% A round power-of-two seed would signal an overflow-saturated hash.
verifyFalse(testCase, any(seeds == 2^30 - 1 | seeds == 0));
end

% ----------------------------------------------- resolving probe values ---

function testDerivedValuesUseTheContractsQuantileAnchors(testCase)
% min_temporal_iou spans q(0.10) to q(0.50) of temporal_iou; each max_abs_ bound
% spans q(0.50) to q(0.95) of its own absolute metric.
values = (1:100)' / 100;
surface = surfaceWith(values, values, values, values);
record = vawlume.eda.probeParameters(surface);

expectedLow = vawlume.eda.sampleQuantile(values, 0.10);
expectedHigh = vawlume.eda.sampleQuantile(values, 0.50);
iou = factorOf(record, "min_temporal_iou");
verifyEqual(testCase, iou.low_value, expectedLow, AbsTol=1e-12);
verifyEqual(testCase, iou.high_value, expectedHigh, AbsTol=1e-12);
verifyEqual(testCase, iou.low_quantile, 0.10, AbsTol=1e-12);
verifyEqual(testCase, iou.high_quantile, 0.50, AbsTol=1e-12);
verifyEqual(testCase, iou.value_source, "observed_quantile");
verifyEqual(testCase, iou.supported_observations, 100);
verifyEqual(testCase, iou.strictness_direction, "larger_is_stricter");

onset = factorOf(record, "max_abs_onset_difference_s");
verifyEqual(testCase, onset.low_value, ...
    vawlume.eda.sampleQuantile(values, 0.50), AbsTol=1e-12);
verifyEqual(testCase, onset.high_value, ...
    vawlume.eda.sampleQuantile(values, 0.95), AbsTol=1e-12);
verifyEqual(testCase, onset.strictness_direction, "smaller_is_stricter");
end

function testAnOverrideWinsAndANonOverriddenFactorStaysDerived(testCase)
surface = standardSurface();
options = vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.2 0.7])));
record = vawlume.eda.probeParameters(surface, options);

overridden = factorOf(record, "min_temporal_iou");
verifyEqual(testCase, overridden.value_source, "user_override");
verifyEqual(testCase, [overridden.low_value, overridden.high_value], ...
    [0.2 0.7], AbsTol=1e-12);
verifyTrue(testCase, isnan(overridden.low_quantile));

derived = factorOf(record, "max_abs_onset_difference_s");
verifyEqual(testCase, derived.value_source, "observed_quantile");
verifyEqual(testCase, derived.low_quantile, 0.50, AbsTol=1e-12);
end

function testInsufficientCoverageDeactivatesTheFactorWithItsReason(testCase)
% Nine supported observations: below the floor at which q(0.95) stops being a
% clamp to the observed maximum, so a quantile cannot honestly be placed.
thin = [(1:9)' / 10; NaN(30, 1)];
full = rand(39, 1);
surface = surfaceWith(full, thin, full, full);
record = vawlume.eda.probeParameters(surface);

onset = factorOf(record, "max_abs_onset_difference_s");
verifyFalse(testCase, onset.is_active);
verifyEqual(testCase, onset.inactive_reason, "insufficient_coverage");
verifyTrue(testCase, isnan(onset.low_value));
verifyEqual(testCase, onset.supported_observations, 9);

verifyEqual(testCase, record.active_factor_count, 3);
verifyTrue(testCase, any(contains(record.warnings, "insufficient_coverage")));
end

function testAMissingMetricColumnDeactivatesTheFactorWithItsReason(testCase)
surface = standardSurface();
surface.metrics.abs_duration_difference_s = [];
surface.metric_names = setdiff(surface.metric_names, ...
    "abs_duration_difference_s", "stable");
record = vawlume.eda.probeParameters(surface);
duration = factorOf(record, "max_abs_duration_difference_s");
verifyFalse(testCase, duration.is_active);
verifyEqual(testCase, duration.inactive_reason, "metric_absent");
end

function testADegenerateIntervalDeactivatesTheFactorWithItsReason(testCase)
% A constant metric gives low == high. An invariant design column silently
% destroys the design's balance and yields a main effect of exactly zero that
% looks like a finding, so the factor is refused rather than shipped.
constant = 0.25 * ones(40, 1);
surface = surfaceWith(constant, rand(40, 1), rand(40, 1), rand(40, 1));
record = vawlume.eda.probeParameters(surface);

iou = factorOf(record, "min_temporal_iou");
verifyFalse(testCase, iou.is_active);
verifyEqual(testCase, iou.inactive_reason, "degenerate_interval");
verifyTrue(testCase, isnan(iou.low_value));
verifyEqual(testCase, record.active_factor_count, 3);
end

function testAUserOverrideCanAlsoBeDegenerateAndIsRefused(testCase)
surface = standardSurface();
options = vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.3 0.3])));
record = vawlume.eda.probeParameters(surface, options);
iou = factorOf(record, "min_temporal_iou");
verifyFalse(testCase, iou.is_active);
verifyEqual(testCase, iou.inactive_reason, "degenerate_interval");
end

function testAUserDisabledFactorIsInactiveWithItsOwnReason(testCase)
surface = standardSurface();
options = vawlume.eda.explorationOptions(struct( ...
    disabled_factors="max_abs_offset_difference_s"));
record = vawlume.eda.probeParameters(surface, options);
offset = factorOf(record, "max_abs_offset_difference_s");
verifyFalse(testCase, offset.is_active);
verifyEqual(testCase, offset.inactive_reason, "disabled_by_user");
verifyEqual(testCase, record.active_factor_count, 3);
end

function testEveryInactiveReasonComesFromTheFixedVocabulary(testCase)
surface = surfaceWith(0.25 * ones(40, 1), [(1:5)' / 10; NaN(35, 1)], ...
    rand(40, 1), rand(40, 1));
options = vawlume.eda.explorationOptions(struct( ...
    disabled_factors="max_abs_offset_difference_s"));
record = vawlume.eda.probeParameters(surface, options);

reasons = record.factors.inactive_reason(~record.factors.is_active);
verifyEqual(testCase, numel(reasons), 3);
verifyTrue(testCase, all(ismember(reasons, record.inactive_reason_vocabulary)));
verifyEqual(testCase, sort(reasons), ...
    sort(["degenerate_interval"; "insufficient_coverage"; "disabled_by_user"]));
end

% ----------------------------------------------------------- anti-pruning ---

function testARedundantFactorStaysActiveAndTheFindingIsRecorded(testCase)
% The conceptual specification forbids removing a scientifically requested
% dimension on the strength of a correlation statistic. This is the test that
% stops a future "improvement" from doing it.
surface = standardSurface();
redundancy = table("temporal_iou", "abs_onset_difference_s", ...
    VariableNames=["metric_a", "metric_b"]);
record = vawlume.eda.probeParameters(surface, ...
    vawlume.eda.explorationOptions(), RedundancyFindings=redundancy);

verifyEqual(testCase, record.active_factor_count, 4, ...
    "No factor may be deactivated for being redundant.");
verifyTrue(testCase, factorOf(record, "min_temporal_iou").is_active);
verifyTrue(testCase, factorOf(record, "min_temporal_iou").flagged_redundant);
verifyTrue(testCase, ...
    factorOf(record, "max_abs_onset_difference_s").flagged_redundant);
verifyFalse(testCase, ...
    factorOf(record, "max_abs_offset_difference_s").flagged_redundant);

verifyEqual(testCase, height(record.redundancy_findings), 1);
verifyTrue(testCase, any(contains(record.interpretation, ...
    "NO FACTOR WAS REMOVED")));
verifyFalse(testCase, any(ismember(record.factors.inactive_reason, ...
    ["redundant", "redundancy"])));
end

% ------------------------------------------------- reference comparison ---

function testTheReferenceValueIsComparedToEachProbedInterval(testCase)
surface = standardSurface();
reference = struct(min_temporal_iou=0.35);
record = vawlume.eda.probeParameters(surface, ...
    vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.2 0.7]))), ...
    ReferencePlausibility=reference);
iou = factorOf(record, "min_temporal_iou");
verifyEqual(testCase, iou.reference_value, 0.35, AbsTol=1e-12);
verifyEqual(testCase, iou.reference_comparison, "reference_within_interval");
end

function testAReferenceOutsideTheIntervalIsReportedNotHidden(testCase)
surface = standardSurface();
below = vawlume.eda.probeParameters(surface, ...
    vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.5 0.7]))), ...
    ReferencePlausibility=struct(min_temporal_iou=0.10));
verifyEqual(testCase, factorOf(below, "min_temporal_iou").reference_comparison, ...
    "reference_below_interval");
verifyTrue(testCase, any(contains(below.warnings, "outside the probed interval")));

above = vawlume.eda.probeParameters(surface, ...
    vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct(min_temporal_iou=[0.1 0.2]))), ...
    ReferencePlausibility=struct(min_temporal_iou=0.90));
verifyEqual(testCase, factorOf(above, "min_temporal_iou").reference_comparison, ...
    "reference_above_interval");
end

function testAnUnconstrainedReferenceDimensionIsNotAFailedBracketCheck(testCase)
% The tracked reference configuration declares min_temporal_iou and none of the
% three max_abs_ bounds. "Unconstrained" is not a point on the axis, so no
% interval can bracket it, and reporting three bracket failures would be wrong.
surface = standardSurface();
record = vawlume.eda.probeParameters(surface, ...
    vawlume.eda.explorationOptions(), ...
    ReferencePlausibility=struct(min_temporal_iou=0.10));

for name = ["max_abs_onset_difference_s", "max_abs_offset_difference_s", ...
        "max_abs_duration_difference_s"]
    row = factorOf(record, name);
    verifyEqual(testCase, row.reference_comparison, ...
        "reference_unconstrained", name);
    verifyTrue(testCase, isnan(row.reference_value), name);
end
verifyTrue(testCase, any(contains(record.warnings, "declares no bound on")));
verifyTrue(testCase, any(contains(record.warnings, "stricter than the reference")));
end

function testTheTrackedReferenceConfigurationIsReadableAndCarriesItsStatus(testCase)
% Reading it is the real path Part 7 uses, and the calibration status must
% travel with the identity: using a file as a reference does not calibrate it.
specPath = fullfile(testCase.TestData.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json");
record = vawlume.eda.probeParameters(standardSurface(), ...
    vawlume.eda.explorationOptions(), ReferenceSpecPath=specPath);

reference = record.reference_configuration;
verifyTrue(testCase, reference.available);
verifyEqual(testCase, reference.profile_key, "vawlume.matching.prototype.v1");
verifyEqual(testCase, reference.calibration_state, "illustrative_prototype");
verifyEqual(testCase, reference.values.min_temporal_iou, 0.10, AbsTol=1e-12);
verifyTrue(testCase, isnan(reference.values.max_abs_onset_difference_s));
verifyTrue(testCase, any(contains(record.warnings, "illustrative_prototype")));
end

function testAnAbsentReferenceIsReportedRatherThanAssumed(testCase)
record = vawlume.eda.probeParameters(standardSurface());
verifyFalse(testCase, record.reference_configuration.available);
verifyEqual(testCase, record.reference_configuration.unavailable_reason, ...
    "not_supplied");
verifyTrue(testCase, all(record.factors.reference_comparison == ...
    "reference_not_supplied"));
verifyTrue(testCase, any(contains(record.interpretation, ...
    "No reference configuration was supplied")));
end

% ---------------------------------------------------- design feasibility ---

function testFewerThanThreeActiveFactorsIsReportedProminently(testCase)
constant = 0.25 * ones(40, 1);
surface = surfaceWith(constant, constant, rand(40, 1), rand(40, 1));
options = vawlume.eda.explorationOptions(struct( ...
    disabled_factors="max_abs_offset_difference_s"));
record = vawlume.eda.probeParameters(surface, options);

verifyEqual(testCase, record.active_factor_count, 1);
verifyFalse(testCase, record.design_feasibility.interaction_aware_screen_possible);
verifyEqual(testCase, record.design_feasibility.minimum_for_interaction_aware_screen, 3);
verifyTrue(testCase, contains(record.design_feasibility.note, ...
    "FEWER THAN THREE ACTIVE FACTORS"));
verifyTrue(testCase, contains(record.warnings(1), "interaction-aware screen"), ...
    "The feasibility warning must lead, not trail the inactive-factor list.");
end

function testFourActiveFactorsReportsTheScreenAsConstructible(testCase)
record = vawlume.eda.probeParameters(standardSurface());
verifyEqual(testCase, record.active_factor_count, 4);
verifyTrue(testCase, record.design_feasibility.interaction_aware_screen_possible);
verifyEqual(testCase, sort(record.active_factor_names), ...
    sort(["min_temporal_iou", "max_abs_onset_difference_s", ...
    "max_abs_offset_difference_s", "max_abs_duration_difference_s"]));
end

% ------------------------------------------------------- the record itself ---

function testTheRecordCarriesTheBudgetSubsetSizeAndTheirSources(testCase)
record = vawlume.eda.probeParameters(standardSurface(), ...
    vawlume.eda.explorationOptions(struct(analysis_budget=250, subset_size=8)));
verifyEqual(testCase, record.analysis_budget, 250);
verifyEqual(testCase, record.analysis_budget_source, "user");
verifyEqual(testCase, record.subset_size, 8);
verifyEqual(testCase, record.subset_size_source, "user");

defaulted = vawlume.eda.probeParameters(standardSurface());
verifyTrue(testCase, isnan(defaulted.analysis_budget));
verifyEqual(testCase, defaulted.analysis_budget_source, "default");
end

function testDisablingExplorationYieldsAWellFormedEmptyRecord(testCase)
record = vawlume.eda.probeParameters(standardSurface(), ...
    vawlume.eda.explorationOptions(struct(enabled=false)));
verifyEqual(testCase, record.status, "disabled");
verifyFalse(testCase, record.exploration_enabled);
verifyEqual(testCase, record.active_factor_count, 0);
verifyEqual(testCase, height(record.factors), 0);
verifyTrue(testCase, isfinite(record.seed));
end

function testNothingInTheOutputDescribesAProbeValueAsOptimal(testCase)
% The language matters here as much as the arithmetic: a downstream report that
% inherits the word "recommended" from this record would describe an
% uncalibrated probe value as a setting.
specPath = fullfile(testCase.TestData.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json");
record = vawlume.eda.probeParameters(standardSurface(), ...
    vawlume.eda.explorationOptions(), ReferenceSpecPath=specPath);

pieces = [record.warnings(:); record.interpretation(:); ...
    record.language_note(:); record.caution(:)];
policyFields = struct2cell(record.policy);
for index = 1:numel(policyFields)
    pieces(end + 1, 1) = string(policyFields{index}); %#ok<AGROW>
end
for index = 1:height(record.factors)
    pieces(end + 1, 1) = record.factors.value_source(index); %#ok<AGROW>
    pieces(end + 1, 1) = record.factors.inactive_reason(index); %#ok<AGROW>
end
% Every sentence that uses one of these words must also negate it. Matching
% fixed denial phrases would only test the phrasings I happened to write; this
% tests the property, which is that the word never appears as an assertion
% about a probe value.
sentences = lower(split(strjoin(pieces, " "), [". ", "; "]));
for banned = ["optimal", "recommended", "best"]
    offending = sentences(contains(sentences, banned) & ...
        ~contains(sentences, ["no ", "none", "not ", "never"]));
    verifyEmpty(testCase, offending, ...
        "'" + banned + "' is asserted rather than denied in: " + ...
        strjoin(offending, " | "));
end
verifyEqual(testCase, record.policy.optimization, ...
    "none; no objective function and no selection among values");
end

function testTheResolverTouchesNoDatabaseAndWritesNothing(testCase)
root = testCase.TestData.repo_root;
files = ["src/+vawlume/+eda/probeParameters.m"
         "src/+vawlume/+eda/explorationOptions.m"
         "src/+vawlume/+eda/private/edaFactorPolicy.m"
         "src/+vawlume/+eda/private/edaDeterministicSeed.m"
         "src/+vawlume/+eda/private/edaReferencePlausibility.m"
         "src/+vawlume/+eda/private/edaInactiveReasons.m"];
for index = 1:numel(files)
    text = string(fileread(fullfile(root, replace(files(index), "/", filesep))));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for forbidden = ["fetch(", "execute(", "sqlwrite(", "sqlite(", ...
            "vawlume.matching.compare", "fopen(", "fwrite(", "writetable("]
        verifyFalse(testCase, contains(body, forbidden), ...
            files(index) + " contains " + forbidden);
    end
end
end

% ---------------------------------------------------------------- helpers ---

function surface = standardSurface(projectKey, runKey)
arguments
    projectKey (1,1) string = "project-a"
    runKey (1,1) string = "pair_ds_mupet"
end
rng(17);
n = 40;
surface = surfaceWith(rand(n, 1) * 0.8 + 0.1, abs(randn(n, 1)) * 0.01, ...
    abs(randn(n, 1)) * 0.01, abs(randn(n, 1)) * 0.02);
surface.analyses = table(projectKey, runKey, ...
    VariableNames=["project_key", "matching_run_key"]);
end

function surface = surfaceWith(iou, onset, offset, duration)
metrics = table(iou(:), onset(:), offset(:), duration(:), ...
    VariableNames=["temporal_iou", "abs_onset_difference_s", ...
    "abs_offset_difference_s", "abs_duration_difference_s"]);
surface = struct(metrics=metrics, ...
    metric_names=string(metrics.Properties.VariableNames));
end

function row = factorOf(record, name)
row = record.factors(record.factors.factor_name == name, :);
end
