function tests = test_eda_support_pattern_profile
%TEST_EDA_SUPPORT_PATTERN_PROFILE Characterization at the reference configuration.
%
% Integration tier because the claims are about the REGISTRY: which features are
% registered as comparable between which extractors, and what happens to a pair
% that looks comparable and is not. That cannot be reproduced against a hand-built
% table - it needs the relationship rows the profiler actually queries, and the
% pilot registry contains the exact trap the rule exists to prevent.
%
% The fixture and the reference run are built once. Every test reads the result
% and none mutates it.
tests = functiontests({ ...
    @setupOnce, @teardownOnce, ...
    @testEverySevenPatternIsPresentIncludingZeroCountOnes, ...
    @testPairwisePatternsAreNotCollapsedIntoACoarseCount, ...
    @testTheTwoVocabulariesAreReportedSeparatelyAndNotJoined, ...
    @testFeaturesAreDiscoveredThroughTheRegistryOnly, ...
    @testASimilarlyNamedUnregisteredPairProducesNoSummary, ...
    @testDurationIsPresentDespiteTheMatchingSpecReservingIt, ...
    @testOnlyDurationAndCentreFrequencyAreUniversallyComparable, ...
    @testAnExtractorRestrictedFeatureNeverReachesAnIneligiblePattern, ...
    @testCoverageEqualsContributingOverPopulation, ...
    @testAMissingMeasurementReducesCoverageAndDoesNotEnterTheDistribution, ...
    @testDistributionsComeFromPartThreesHelper, ...
    @testTheReferenceConfigurationIdentityAppearsInTheOutput, ...
    @testThresholdContextIsCarriedFromTheProbeAndNotRecomputed, ...
    @testTheSharedSpaceLimitationIsStatedInTheOutput, ...
    @testTheProfilerWritesNothingAndEditsNoGuardedFile});
end

% --------------------------------------------------------- shared fixture ---

function setupOnce(testCase)
[fixture, cleanup] = setUpFixture();
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
testCase.TestData.context = referenceRun(fixture);
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ------------------------------------------------- the seven exact patterns ---

function testEverySevenPatternIsPresentIncludingZeroCountOnes(testCase)
%TESTEVERYSEVENPATTERNISPRESENT... An absent row and a zero row differ.
context = testCase.TestData.context;
patterns = context.profile.patterns;

verifyEqual(testCase, height(patterns), 7);
verifyEqual(testCase, sort(patterns.extractor_set_key), sort([ ...
    "deepsqueak"; "mupet"; "usvseg"; ...
    "deepsqueak|mupet"; "deepsqueak|usvseg"; "mupet|usvseg"; ...
    "deepsqueak|mupet|usvseg"]));

% The fixture's geometry is hand-checkable: its counts are asserted exactly
% rather than as "some are nonzero", because a profiler that assigned every
% group to the three-way pattern would satisfy a weaker assertion.
expected = dictionary( ...
    ["deepsqueak", "mupet", "usvseg", "deepsqueak|mupet", ...
    "deepsqueak|usvseg", "mupet|usvseg", "deepsqueak|mupet|usvseg"], ...
    [0, 0, 1, 0, 1, 1, 2]);
for index = 1:height(patterns)
    key = patterns.extractor_set_key(index);
    verifyEqual(testCase, patterns.group_count(index), expected(key), ...
        "Pattern " + key + " has the wrong group count.");
end

% Three patterns were looked for and not found, and say so.
absent = patterns(patterns.is_absent, :);
verifyEqual(testCase, height(absent), 3);
verifyTrue(testCase, all(absent.group_count == 0));
verifyTrue(testCase, all(absent.detection_count == 0));

% Proportions state their denominator rather than leaving it implied.
verifyEqual(testCase, sum(patterns.group_count), context.profile.total_groups);
verifyEqual(testCase, sum(patterns.detection_count), ...
    context.profile.total_detections);
verifyTrue(testCase, all(patterns.group_denominator == ...
    context.profile.total_groups));
verifyEqual(testCase, sum(patterns.group_proportion), 1, AbsTol=1e-12);
end

function testPairwisePatternsAreNotCollapsedIntoACoarseCount(testCase)
%TESTPAIRWISEPATTERNSARENOTCOLLAPSED... Two-of-three is not one category.
%
% Verified as a negative result: binning by `extractor_count` gives four rows -
% one, two, three extractors and the absent case - and this test fails on the row
% count and on every pairwise key. Two groups can both be 2 of 3 while supporting
% DIFFERENT pairs, and merging them reports an agreement that was never observed.
context = testCase.TestData.context;
patterns = context.profile.patterns;

pairwise = patterns(patterns.extractor_count == 2, :);
verifyEqual(testCase, height(pairwise), 3, ...
    "The three two-extractor patterns were collapsed.");
verifyEqual(testCase, numel(unique(pairwise.extractor_set_key)), 3);

% Two of the three pairwise patterns are occupied here by DIFFERENT pairs, and
% they stay distinct rather than becoming one 2/3 row.
occupied = pairwise(pairwise.group_count > 0, :);
verifyEqual(testCase, height(occupied), 2);
verifyEqual(testCase, sort(occupied.extractor_set_key), ...
    sort(["deepsqueak|usvseg"; "mupet|usvseg"]));

% Every key names its extractors rather than a count, so no row can secretly be
% a coarse bin.
for key = patterns.extractor_set_key'
    verifyTrue(testCase, isnan(str2double(key)), ...
        "Pattern key '" + key + "' parses as a number, so it is a count.");
end

% The three singletons remain three.
singletons = patterns(patterns.is_extractor_unique, :);
verifyEqual(testCase, height(singletons), 3);
verifyEqual(testCase, numel(unique(singletons.extractor_set_key)), 3);
end

function testTheTwoVocabulariesAreReportedSeparatelyAndNotJoined(testCase)
%TESTTHETWOVOCABULARIESAREREPORTED... The pair pattern cannot key the seven.
context = testCase.TestData.context;
profile = context.profile;

% Both are present, and they are different vocabularies over the same groups.
verifyNotEmpty(testCase, profile.patterns);
verifyNotEmpty(testCase, profile.pair_patterns);
verifyTrue(testCase, ismember("(none)", ...
    profile.pair_patterns.supported_extractor_pair_pattern), ...
    "No singleton group carries the '(none)' pair pattern.");

% The pair-pattern vocabulary cannot express the seven categories: every
% singleton collapses onto '(none)' whichever extractor produced it, which is
% why `patterns` is keyed on the extractor set instead.
verifyLessThan(testCase, height(profile.pair_patterns), 7);
verifySubstring(testCase, profile.vocabulary_note, "MUST NOT BE JOINED");
verifySubstring(testCase, profile.vocabulary_note, ...
    "merge the three extractor-unique categories into one");

% Both tables state their own denominator.
verifyEqual(testCase, sum(profile.pair_patterns.group_count), ...
    profile.total_groups);
end

% ------------------------------------------------------- registry discipline ---

function testFeaturesAreDiscoveredThroughTheRegistryOnly(testCase)
context = testCase.TestData.context;
discovery = context.profile.feature_discovery;

verifySubstring(testCase, discovery.discovery_path, "feature_relationships");
verifySubstring(testCase, discovery.discovery_path, "consilience_eligible");
verifySubstring(testCase, discovery.join_discipline, "never inferred");

% Every discovered pair is an eligible registered relationship, and the
% equivalence class came from both sides agreeing.
verifyTrue(testCase, all(discovery.pairs.consilience_eligible));
verifyTrue(testCase, all(strlength(discovery.pairs.equivalence_class) > 0));

% No source file in this part contains a feature name literal, which is what
% makes the eligible set data rather than code.
root = repoRootPath();
for name = ["supportPatternProfile.m", "crossPatternComparison.m"]
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    for literal = ["Peak Freq", "maxfreq", "meanfreq", "Call Length", ...
            "syllable duration", "Delta Freq"]
        verifyEqual(testCase, numel(strfind(source, literal)), 0, ...
            name + " contains the feature name literal '" + literal + "'.");
    end
end
end

function testASimilarlyNamedUnregisteredPairProducesNoSummary(testCase)
%TESTASIMILARLYNAMEDUNREGISTEREDPAIR... The test that proves the discipline.
%
% DeepSqueak registers "Peak Freq (kHz)" and USVSEG registers "maxfreq". BOTH
% carry equivalence class `vocalization_peak_frequency`. They look comparable by
% every shortcut available - same equivalence class, same evident concept,
% obviously similar meaning - and NO relationship between them is registered,
% because nobody established that they measure the same thing the same way.
%
% Verified as a negative result: an implementation that groups by equivalence
% class, or joins on canonical name, produces a peak-frequency summary here and
% this test fails. That is the exact defect the matching specification's
% `forbid_canonical_name_only_join` exists to prevent, and it is not
% hypothetical - it is what the pilot registry contains today.
context = testCase.TestData.context;
conn = testCase.TestData.fixture.conn;

% Both features exist, in the same equivalence class, on different extractors.
registered = fetch(conn, "SELECT e.extractor_key, xf.native_name " + ...
    "FROM extractor_features xf " + ...
    "JOIN extractor_versions ev " + ...
    "ON ev.extractor_version_id=xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE xf.equivalence_class='vocalization_peak_frequency' " + ...
    "ORDER BY e.extractor_key");
verifyEqual(testCase, height(registered), 2, ...
    "The fixture no longer contains the unregistered look-alike pair.");
verifyEqual(testCase, sort(string(registered.extractor_key)), ...
    sort(["deepsqueak"; "usvseg"]));

% And no relationship pairs them.
relationships = fetch(conn, "SELECT COUNT(*) AS n " + ...
    "FROM v_cross_extractor_feature_pairs " + ...
    "WHERE feature_a_equivalence_class='vocalization_peak_frequency' " + ...
    "AND feature_b_equivalence_class='vocalization_peak_frequency'");
verifyEqual(testCase, double(relationships.n(1)), 0);

% Therefore the profiler produces nothing for it, anywhere.
profile = context.profile;
verifyFalse(testCase, ismember("vocalization_peak_frequency", ...
    profile.feature_eligibility.equivalence_class));
verifyFalse(testCase, ismember("vocalization_peak_frequency", ...
    profile.features.equivalence_class));
verifyFalse(testCase, ismember("vocalization_peak_frequency", ...
    profile.feature_discovery.classes.equivalence_class));
verifyError(testCase, @() vawlume.eda.crossPatternComparison(profile, ...
    "vocalization_peak_frequency"), "vawlume:eda:FeatureNotRegistered");
end

function testDurationIsPresentDespiteTheMatchingSpecReservingIt(testCase)
%TESTDURATIONISPRESENTDESPITE... An over-cautious reading leaves one feature.
%
% The matching specification lists duration in
% `timing_classes_reserved_as_primary_evidence` and excludes it from the
% consilience support rule, so temporal evidence is not double-counted when
% CLASSIFYING correspondence. Characterization asks a different question, and
% contract §K readmits duration for it. Without this, the shared space across
% three extractors would be one feature wide.
context = testCase.TestData.context;
profile = context.profile;

verifyTrue(testCase, ismember("vocalization_duration", ...
    profile.feature_eligibility.equivalence_class));
row = profile.feature_eligibility( ...
    profile.feature_eligibility.equivalence_class == ...
    "vocalization_duration", :);
verifyTrue(testCase, row.is_cross_pattern_comparable);
verifyTrue(testCase, row.is_readmitted_timing_class);

% The reservation is still honoured for the classes it was actually about:
% start and end time are positions in a recording, not properties of a call.
for excluded = ["vocalization_start_time", "vocalization_end_time"]
    verifyFalse(testCase, ismember(excluded, ...
        profile.feature_eligibility.equivalence_class), ...
        excluded + " is being reported as a characterization feature.");
end
verifySubstring(testCase, profile.feature_discovery.reservation_note, ...
    "readmits DURATION");

% And duration actually carries values, not just a row.
summaries = profile.features(profile.features.equivalence_class == ...
    "vocalization_duration" & profile.features.pattern_population > 0, :);
verifyNotEmpty(testCase, summaries);
verifyGreaterThan(testCase, sum(summaries.contributing_detections), 0);
end

function testOnlyDurationAndCentreFrequencyAreUniversallyComparable(testCase)
%TESTONLYDURATIONANDCENTREFREQUENCY... Contract §K's table, as registered.
context = testCase.TestData.context;
eligibility = context.profile.feature_eligibility;

universal = sort(eligibility.equivalence_class( ...
    eligibility.is_cross_pattern_comparable));
verifyEqual(testCase, universal, sort([ ...
    "vocalization_duration"; "vocalization_frequency_center"]));

% The extractor-restricted classes are the DeepSqueak-MUPET frequency triple,
% and each names the extractors it is comparable among.
restricted = eligibility(~eligibility.is_cross_pattern_comparable, :);
verifyEqual(testCase, sort(restricted.equivalence_class), sort([ ...
    "vocalization_frequency_bandwidth"; "vocalization_frequency_max"; ...
    "vocalization_frequency_min"]));
verifyTrue(testCase, all(restricted.comparable_extractor_key == ...
    "DeepSqueak|MUPET"));

% Transitivity is not assumed: bandwidth is registered for DeepSqueak-MUPET
% only, so no set containing USVSEG is eligible for it.
for index = 1:height(restricted)
    eligiblePatterns = string(restricted.eligible_patterns{index}(:))';
    verifyFalse(testCase, any(contains(eligiblePatterns, "usvseg")), ...
        restricted.equivalence_class(index) + " is eligible in a USVSEG " + ...
        "pattern, which cannot measure it.");
    verifyEqual(testCase, sort(eligiblePatterns), ...
        sort(["deepsqueak", "deepsqueak|mupet", "mupet"]));
end
end

function testAnExtractorRestrictedFeatureNeverReachesAnIneligiblePattern(testCase)
%TESTANEXTRACTORRESTRICTEDFEATURENEVER... Contract §K's confounding rule.
context = testCase.TestData.context;
profile = context.profile;

restricted = profile.features(~profile.features.is_cross_pattern_comparable, :);
verifyNotEmpty(testCase, restricted);
verifyFalse(testCase, any(contains(restricted.extractor_set_key, "usvseg")));

% The universally comparable ones do reach all seven, which is the other half:
% a guard that leaves nothing comparable is not a guard.
for name = ["vocalization_duration", "vocalization_frequency_center"]
    rows = profile.features(profile.features.equivalence_class == name, :);
    verifyEqual(testCase, height(rows), 7, ...
        name + " is not reported for every pattern.");
end

verifyError(testCase, @() vawlume.eda.crossPatternComparison(profile, ...
    "vocalization_frequency_bandwidth"), ...
    "vawlume:eda:FeatureNotCrossPatternComparable");
verifyEqual(testCase, vawlume.eda.crossPatternComparison(profile, ...
    "vocalization_duration").status, "comparable");
end

% ---------------------------------------------------------------- coverage ---

function testCoverageEqualsContributingOverPopulation(testCase)
context = testCase.TestData.context;
features = context.profile.features;
verifyNotEmpty(testCase, features);

for index = 1:height(features)
    row = features(index, :);
    verifyEqual(testCase, row.contributing_detections + row.not_eligible + ...
        row.not_measured + row.non_finite, row.pattern_population, ...
        "Coverage categories do not partition " + row.extractor_set_key + ...
        " / " + row.equivalence_class + ".");
    if row.pattern_population == 0
        % An empty pattern is not a low-coverage one. Zero over zero is not a
        % small fraction: there is nothing there to cover, and labelling it
        % low_coverage would report the feature as poorly measured where the
        % pattern simply has no members.
        verifyEqual(testCase, row.coverage_label, "no_population");
        verifyFalse(testCase, row.is_low_coverage, ...
            "Empty pattern " + row.extractor_set_key + " is marked " + ...
            "low_coverage, which conflates absent with thinly measured.");
        continue
    end
    verifyEqual(testCase, row.coverage_fraction, ...
        row.contributing_detections / row.pattern_population, AbsTol=1e-12);
    verifyEqual(testCase, row.is_low_coverage, ...
        row.coverage_fraction < context.profile.low_coverage_threshold);
end

% Annotate, do not filter: every eligible pattern keeps its row whatever its
% coverage, because a low-coverage feature is a finding about the extractor set.
verifySubstring(testCase, context.profile.coverage_policy, "ANNOTATED");
verifySubstring(testCase, context.profile.coverage_policy, "never filtered");

% The warning a figure caption would carry separates the two facts too.
warning = vawlume.eda.crossPatternComparison(context.profile, ...
    "vocalization_duration").coverage_warning;
verifySubstring(testCase, warning, "hold no detection at all");
verifySubstring(testCase, warning, "absence of members, not a thinly measured");
verifyEqual(testCase, numel(strfind(warning, "0% of 0")), 0, ...
    "An empty pattern is reported as a coverage percentage of nothing.");
end

function testAMissingMeasurementReducesCoverageAndDoesNotEnterTheDistribution(testCase)
%TESTAMISSINGMEASUREMENTREDUCESCOVERAGE... Absent is not zero.
%
% One detection's duration measurement is deleted from a copy of the fixture, so
% the same population yields one fewer contributing detection and an unchanged
% count of everything else. A distribution that silently treated the absence as
% a value would keep its coverage at 1 and shift its median.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
context = referenceRun(fixture);
before = durationRow(context.profile, "deepsqueak|mupet|usvseg");

victim = fetch(fixture.conn, "SELECT em.event_measurement_id AS id " + ...
    "FROM event_measurements em " + ...
    "JOIN extractor_features xf " + ...
    "ON xf.extractor_feature_id=em.extractor_feature_id " + ...
    "WHERE xf.equivalence_class='vocalization_duration' " + ...
    "AND em.detection_id IN (" + strjoin(string( ...
    threeWayDetectionIds(fixture.conn, context)'), ",") + ") LIMIT 1");
verifyEqual(testCase, height(victim), 1);
execute(fixture.conn, "DELETE FROM event_measurements " + ...
    "WHERE event_measurement_id=" + string(double(victim.id(1))));

after = durationRow(profileOnly(fixture, context), "deepsqueak|mupet|usvseg");

verifyEqual(testCase, after.pattern_population, before.pattern_population, ...
    "The population changed, so the comparison is not about the measurement.");
verifyEqual(testCase, after.contributing_detections, ...
    before.contributing_detections - 1);
verifyEqual(testCase, after.not_measured, before.not_measured + 1);
verifyLessThan(testCase, after.coverage_fraction, before.coverage_fraction);
end

function testDistributionsComeFromPartThreesHelper(testCase)
%TESTDISTRIBUTIONSCOMEFROMPARTTHREES... Not a second summary implementation.
context = testCase.TestData.context;
features = context.profile.features;

populated = features(features.contributing_detections >= 2, :);
verifyNotEmpty(testCase, populated);

% Distributions, not just means: a median with an interquartile range is what
% answers "what kinds of detections occupy this pattern".
for name = ["minimum", "q25", "median", "q75", "maximum", ...
        "interquartile_range"]
    verifyTrue(testCase, ismember(name, ...
        string(features.Properties.VariableNames)), ...
        "The feature table has no " + name + " column.");
end
verifyFalse(testCase, ismember("mean", ...
    string(features.Properties.VariableNames)));

for index = 1:height(populated)
    row = populated(index, :);
    verifyLessThanOrEqual(testCase, row.minimum, row.median);
    verifyLessThanOrEqual(testCase, row.median, row.maximum);
    verifyEqual(testCase, row.interquartile_range, row.q75 - row.q25, ...
        AbsTol=1e-12);
end

% Too few observations reports undefined statistics rather than a median of
% one, and keeps its row.
thin = features(features.contributing_detections == 1, :);
if height(thin) > 0
    verifyTrue(testCase, all(isnan(thin.median)));
    verifyGreaterThan(testCase, height(thin), 0);
end
end

% ------------------------------------------------------- identity and context ---

function testTheReferenceConfigurationIdentityAppearsInTheOutput(testCase)
context = testCase.TestData.context;
identity = context.profile.reference_configuration;

verifyEqual(testCase, identity.profile_key, "vawlume.matching.prototype.v1");
verifyEqual(testCase, identity.version_label, "0.1.0");
verifyEqual(testCase, identity.checksum_sha256, ...
    context.reference.checksum_sha256);
verifyEqual(testCase, identity.calibration_state, "illustrative_prototype");
verifySubstring(testCase, identity.calibration_note, "does not calibrate it");

% The same identity reaches a cross-pattern result, because that is what a
% figure is built from and a figure travels without its run.
comparison = vawlume.eda.crossPatternComparison(context.profile, ...
    "vocalization_duration");
verifyEqual(testCase, comparison.reference_configuration.profile_key, ...
    identity.profile_key);
verifyEqual(testCase, comparison.reference_configuration.calibration_state, ...
    "illustrative_prototype");

% The analysis really was run at the reference specification, not at something
% resembling it: the generated spec carries the reference version label.
verifySubstring(testCase, context.materialized.index.profile_version(1), ...
    "0.1.0+exp.ref-");
verifyEqual(testCase, context.design.factor_count, 0, ...
    "The reference run overrode a parameter.");
end

function testThresholdContextIsCarriedFromTheProbeAndNotRecomputed(testCase)
%TESTTHRESHOLDCONTEXTISCARRIED... Ranges come from Part 10, not from here.
context = testCase.TestData.context;

% Without a probe result there is no context, and the profile says so rather
% than inventing one.
verifyEqual(testCase, context.profile.threshold_context.status, "absent");

supplied = struct(support_pattern_movement=struct( ...
    observed_counts=table( ...
    ["whole_dataset"; "whole_dataset"], ...
    ["(none)"; "deepsqueak--mupet"], [3; 1], [9; 4], [6; 3], ...
    VariableNames=["probe_role", "support_pattern", "lowest_group_count", ...
    "highest_group_count", "observed_movement"])));
carried = vawlume.eda.supportPatternProfile(testCase.TestData.fixture.conn, ...
    struct(run_key=context.agreement_run_key), context.reference, ...
    ThresholdContext=supplied);

verifyEqual(testCase, carried.threshold_context.status, "carried");
verifyEqual(testCase, carried.threshold_context.ranges, ...
    supplied.support_pattern_movement.observed_counts, ...
    "The ranges were altered rather than carried.");
verifySubstring(testCase, carried.threshold_context.source, ...
    "probeConcordance");
verifySubstring(testCase, carried.threshold_context.note, "NOT recomputed");

% Carried under the PROBE's key, which is the pair pattern, and the note says
% it must not be joined to the extractor-set table.
verifyEqual(testCase, carried.threshold_context.keyed_on, ...
    "supported_extractor_pair_pattern");
verifySubstring(testCase, carried.threshold_context.note, ...
    "NOT with `patterns`");
end

function testTheSharedSpaceLimitationIsStatedInTheOutput(testCase)
%TESTTHESHAREDSPACELIMITATIONISSTATED... A limitation, not a result.
context = testCase.TestData.context;
limitation = context.profile.shared_space_limitation;

verifyEqual(testCase, limitation.universally_comparable_count, 2);
verifyEqual(testCase, sort(limitation.universally_comparable), ...
    sort(["vocalization_duration", "vocalization_frequency_center"]));
verifyEqual(testCase, limitation.extractor_restricted_count, 3);
verifySubstring(testCase, limitation.statement, "METHODOLOGICAL LIMITATION");
verifySubstring(testCase, limitation.statement, ...
    "not a result about vocalizations");
verifySubstring(testCase, limitation.statement, ...
    "not closed by harmonizing features the registry does not declare");

% The interpretation note bounds what may be said from the table, and it
% travels in the output because the table will travel without the code.
note = strjoin(context.profile.interpretation_note, " ");
verifySubstring(testCase, note, "has NOT been shown to be false");
verifySubstring(testCase, note, "Not permitted");
verifySubstring(testCase, note, "numeric weight follows from support count");
verifySubstring(testCase, note, "Permitted reading");
end

% ---------------------------------------------------------------- tripwire ---

function testTheProfilerWritesNothingAndEditsNoGuardedFile(testCase)
%TESTTHEPROFILERWRITESNOTHING... Part 11 characterizes; it stores nothing.
%
% The guarded paths matter here for a specific reason: the shared feature space
% is thin, and the tempting fix is to register another feature relationship to
% widen it. The itinerary is explicit that a too-thin shared space is a finding
% for the ledger, not a mapping to add.
root = repoRootPath();
files = ["referenceConfiguration.m", "referenceDesign.m", ...
    "supportPatternProfile.m", "crossPatternComparison.m"];
for name = files
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    for token = ["INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE ", "DROP "]
        verifyEqual(testCase, numel(strfind(source, token)), 0, ...
            name + " contains '" + token + "'.");
    end
end

[status, output] = system("git -C """ + root + """ status --porcelain");
verifyEqual(testCase, status, 0, "git status failed.");
changed = strtrim(splitlines(string(output)));
changed = changed(strlength(changed) > 0);
guarded = ["src/+vawlume/+consilience/", "config/01_mapping_profiles/", ...
    "schema/"];
for line = changed'
    path = extractAfter(line, 3);
    for prefix = guarded
        verifyFalse(testCase, startsWith(path, prefix), ...
            "Part 11 modified a guarded path: " + path);
    end
end

% And the observable version: profiling changes no row.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
context = referenceRun(fixture);
before = tableCounts(fixture.conn);
vawlume.eda.supportPatternProfile(fixture.conn, ...
    struct(run_key=context.agreement_run_key), context.reference);
vawlume.eda.crossPatternComparison(context.profile, "vocalization_duration");
verifyEqual(testCase, tableCounts(fixture.conn), before);
end

% ---------------------------------------------------------------- helpers ---

function context = referenceRun(fixture)
%REFERENCERUN Apply the reference configuration through Part 7's runner.
%
% Contract §J: the reference configuration is applied like any other
% configuration, never silently substituted by a probe configuration that
% resembles it. vawlume.eda.referenceDesign makes it a one-configuration design
% with no factors, so materializeConfigurations copies the reference
% specification with nothing overridden.
reference = vawlume.eda.referenceConfiguration(RepoRoot=fixture.repo_root);
design = vawlume.eda.referenceDesign(reference);
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
run = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true, ProbeRole="reference");

agreement = run.manifest.run_key(run.manifest.unit_kind == "agreement" & ...
    ismember(run.manifest.status, ["committed", "reused"]));
profile = vawlume.eda.supportPatternProfile(fixture.conn, ...
    struct(run_key=agreement(1)), reference);

context = struct(reference=reference, design=design, dataset=dataset, ...
    materialized=materialized, run=run, ...
    agreement_run_key=agreement(1), profile=profile);
end

function value = profileOnly(fixture, context)
value = vawlume.eda.supportPatternProfile(fixture.conn, ...
    struct(run_key=context.agreement_run_key), context.reference);
end

function value = durationRow(profile, setKey)
value = profile.features( ...
    profile.features.equivalence_class == "vocalization_duration" & ...
    profile.features.extractor_set_key == setKey, :);
end

function value = threeWayDetectionIds(conn, context)
%THREEWAYDETECTIONIDS The member detections of the complete-support pattern.
%
% Read back through the same selector the profiler uses, so the deletion below
% lands on a detection the profile actually counts rather than on one that
% happens to share an id.
population = vawlume.agreement.selectPopulation(conn, ...
    struct(run_key=context.agreement_run_key));
members = population.members;
ids = unique(members.agreement_group_id);
value = [];
for index = 1:numel(ids)
    selected = members(members.agreement_group_id == ids(index), :);
    if numel(unique(selected.extractor_key)) == 3
        value = [value; selected.detection_id]; %#ok<AGROW>
    end
end
end

function value = tableCounts(conn)
names = ["detections", "event_measurements", "agreement_groups", ...
    "feature_relationships", "extractor_features", "analysis_runs"];
value = zeros(numel(names), 1);
for index = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(index));
    value(index) = double(rows.n(1));
end
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
dbPath = fullfile(scratch, "support-pattern.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch));
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

function tearDown(conn, scratch)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
end

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
