function tests = test_agreement_summaries
tests = functiontests({ ...
    @testDetectionDenominatorsPartitionEachRunExactly, ...
    @testTopologyCountsSeparateGroupsFromDetections, ...
    @testTemporalAgreementReusesStoredCandidateEvidence, ...
    @testFeaturePairsComeFromTheRegistryNotFromCanonicalNames, ...
    @testCanonicalNameJoinMissesCentralFrequencyAndTheRegistryFindsIt, ...
    @testPowerEnergyAndAmplitudeStayIneligible, ...
    @testOneToOneFeatureDifferencesAreExact, ...
    @testAmbiguousAndUnmatchedGroupsAreExcludedNotAveraged, ...
    @testMissingMeasurementIsAbsentEvidenceNotDisagreement, ...
    @testExportedDurationComparisonIsNotTheBoundaryDerivedDelta, ...
    @testAggregateSummariesAndDeferredAssociation, ...
    @testPersistenceScopesStatisticsToAChildAnalysisRun, ...
    @testRerunReusesAndChangedStatisticsConflict, ...
    @testSummarizeNeverMutatesUpstreamRows, ...
    @testSpecificationIsResolvedFromTheAnalysisAndChecksumChecked, ...
    @testReportRefusesIncompleteOrNonMatchingAnalyses});
end

% ------------------------------------------------------ detection agreement ---

function testDetectionDenominatorsPartitionEachRunExactly(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);

perRun = report.detection_agreement;
verifyEqual(testCase, height(perRun), 2);
verifyEqual(testCase, string(perRun.run_role), ["run_a"; "run_b"]);
verifyEqual(testCase, string(perRun.extractor_name), ["DeepSqueak"; "MUPET"]);

% The DeepSqueak run has 3 calls: one in a 1:1 component, one spanning two
% MUPET syllables, and one with no counterpart at all.
deepsqueak = perRun(1, :);
verifyEqual(testCase, deepsqueak.total_detections, 3);
verifyEqual(testCase, deepsqueak.in_one_to_one_groups, 1);
verifyEqual(testCase, deepsqueak.in_ambiguous_groups, 1);
verifyEqual(testCase, deepsqueak.unmatched_detections, 1);
verifyEqual(testCase, deepsqueak.in_cross_extractor_groups, 2);

% The MUPET run has 4 syllables: one 1:1, two inside the split component, one
% with no counterpart.
mupet = perRun(2, :);
verifyEqual(testCase, mupet.total_detections, 4);
verifyEqual(testCase, mupet.in_one_to_one_groups, 1);
verifyEqual(testCase, mupet.in_ambiguous_groups, 2);
verifyEqual(testCase, mupet.unmatched_detections, 1);
verifyEqual(testCase, mupet.in_cross_extractor_groups, 3);

% Each run's four count columns partition that run exactly once, and every
% proportion uses that run's own denominator rather than a pooled one.
for index = 1:2
    row = perRun(index, :);
    verifyEqual(testCase, row.in_one_to_one_groups + row.in_ambiguous_groups + ...
        row.unmatched_detections, row.total_detections);
    verifyEqual(testCase, row.proportion_one_to_one, ...
        row.in_one_to_one_groups / row.total_detections, AbsTol=1e-12);
    verifyEqual(testCase, row.proportion_unmatched, ...
        row.unmatched_detections / row.total_detections, AbsTol=1e-12);
end

% The two runs have different denominators, so the same numerator gives
% different proportions. That is exactly why a single percentage is refused.
verifyEqual(testCase, deepsqueak.proportion_unmatched, 1/3, AbsTol=1e-12);
verifyEqual(testCase, mupet.proportion_unmatched, 1/4, AbsTol=1e-12);

% The pooled figure is published with its own definition and a caution, and is
% never presented as an agreement rate.
verifyEqual(testCase, report.symmetric_coverage.numerator, 5);
verifyEqual(testCase, report.symmetric_coverage.denominator, 7);
verifyEqual(testCase, report.symmetric_coverage.pooled_matched_coverage, 5/7, ...
    AbsTol=1e-12);
verifyTrue(testCase, contains(report.symmetric_coverage.caution, "not an agreement rate"));

% No output invites false-positive language for an unmatched detection.
verifyTrue(testCase, any(contains(report.terminology_note, "not a false positive")));
end

function testTopologyCountsSeparateGroupsFromDetections(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
topology = report.topology;

verifyEqual(testCase, topologyValue(topology, "one_to_one", "group_count"), 1);
verifyEqual(testCase, topologyValue(topology, "one_to_many", "group_count"), 1);
verifyEqual(testCase, topologyValue(topology, "many_to_one", "group_count"), 0);
verifyEqual(testCase, topologyValue(topology, "many_to_many", "group_count"), 0);
verifyEqual(testCase, topologyValue(topology, "unmatched", "group_count"), 2);

% The split component is one group holding three detections. Reporting it as
% three matches, or as two independent one-to-one matches, is the error this
% separation exists to prevent.
verifyEqual(testCase, topologyValue(topology, "one_to_many", "detection_count"), 3);
verifyEqual(testCase, topologyValue(topology, "one_to_many", "run_a_detections"), 1);
verifyEqual(testCase, topologyValue(topology, "one_to_many", "run_b_detections"), 2);
verifyNotEqual(testCase, topologyValue(topology, "one_to_many", "group_count"), ...
    topologyValue(topology, "one_to_many", "detection_count"));

verifyEqual(testCase, sum(topology.detection_count), 7);
verifyEqual(testCase, height(report.topology_participation), 10);
end

function testTemporalAgreementReusesStoredCandidateEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
temporal = report.temporal_agreement;

verifyEqual(testCase, temporal.group_count, 1);
verifyEqual(testCase, height(temporal.rows), 1);
verifySubstring(testCase, temporal.source, "stored candidate_pairs evidence");

% Every reported delta equals the candidate row written at generation time. The
% point is that agreement never recomputes the evidence with its own formula.
stored = fetch(fixture.conn, ...
    "SELECT temporal_overlap_s, temporal_iou, onset_difference_s, " + ...
    "offset_difference_s, duration_difference_s FROM candidate_pairs cp " + ...
    "JOIN match_group_members a ON a.detection_id = cp.detection_a_id " + ...
    "JOIN match_group_members b ON b.detection_id = cp.detection_b_id " + ...
    "JOIN match_groups mg ON mg.match_group_id = a.match_group_id " + ...
    "WHERE mg.match_type = 'one_to_one' AND b.match_group_id = a.match_group_id");
verifyEqual(testCase, height(stored), 1);
row = temporal.rows(1, :);
verifyEqual(testCase, row.temporal_overlap_s, double(stored.temporal_overlap_s(1)), ...
    AbsTol=1e-12);
verifyEqual(testCase, row.temporal_iou, double(stored.temporal_iou(1)), AbsTol=1e-12);
verifyEqual(testCase, row.onset_difference_s, ...
    double(stored.onset_difference_s(1)), AbsTol=1e-12);
verifyEqual(testCase, row.offset_difference_s, ...
    double(stored.offset_difference_s(1)), AbsTol=1e-12);
verifyEqual(testCase, row.duration_difference_s, ...
    double(stored.duration_difference_s(1)), AbsTol=1e-12);

% Signed differences follow the stored evidence direction, run_b minus run_a.
verifySubstring(testCase, report.analysis.direction, "run_b minus run_a");
verifyEqual(testCase, row.onset_difference_s, 0.004, AbsTol=1e-9);
verifyEqual(testCase, height(temporal.summary), 5);
end

% ------------------------------------------------------- feature discovery ---

function testFeaturePairsComeFromTheRegistryNotFromCanonicalNames(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
pairs = report.feature_pairs;

% Nine registered DeepSqueak/MUPET relationships: seven eligible, two not.
verifyEqual(testCase, height(pairs), 9);
verifyEqual(testCase, nnz(pairs.consilience_eligible), 7);
verifyEqual(testCase, nnz(pairs.comparison_eligible), 7);

% Every pair keeps both extractors' distinct native and canonical identity. No
% row collapses the two sides into one anonymous value.
verifyEqual(testCase, unique(string(pairs.extractor_a_name)), "DeepSqueak");
verifyEqual(testCase, unique(string(pairs.extractor_b_name)), "MUPET");
verifyFalse(testCase, any(pairs.feature_a_id == pairs.feature_b_id));
verifyFalse(testCase, any(strlength(string(pairs.feature_a_native_name)) == 0));
verifyFalse(testCase, any(strlength(string(pairs.feature_b_native_name)) == 0));

% The classes the pass specification names are all discoverable.
classes = string(pairs.equivalence_class);
for expected = ["vocalization_duration", "vocalization_frequency_min", ...
        "vocalization_frequency_max", "vocalization_frequency_bandwidth", ...
        "vocalization_frequency_center"]
    verifyTrue(testCase, ismember(expected, classes), expected);
end

% Timing classes are marked as primary temporal evidence so a later consilience
% pass does not count them twice, once as candidate evidence and once as
% independent feature support.
primary = classes(pairs.primary_temporal_evidence);
verifyEqual(testCase, sort(primary), ["vocalization_duration"; ...
    "vocalization_end_time"; "vocalization_start_time"]);

% No feature name literal drives discovery. The registry does.
source = fileread(fullfile(fixture.repo_root, "src", "+vawlume", ...
    "+consilience", "private", "consilienceFeatureAgreement.m"));
for forbidden = ["Principle Frequency", "mean frequency (kHz)", ...
        "frequency_center", "contour_median_frequency", "Delta Freq"]
    verifyFalse(testCase, contains(string(source), forbidden), forbidden);
end
end

function testCanonicalNameJoinMissesCentralFrequencyAndTheRegistryFindsIt(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The naive approach: pair features whose canonical names are equal. It finds
% six concepts and silently returns nothing at all for central frequency.
byName = fetch(fixture.conn, ...
    "SELECT DISTINCT cf.canonical_name FROM extractor_features xa " + ...
    "JOIN feature_mappings fma ON fma.extractor_feature_id = xa.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = fma.canonical_feature_id " + ...
    "JOIN feature_mappings fmb ON fmb.canonical_feature_id = cf.canonical_feature_id " + ...
    "JOIN extractor_features xb ON xb.extractor_feature_id = fmb.extractor_feature_id " + ...
    "JOIN extractor_versions eva ON eva.extractor_version_id = xa.extractor_version_id " + ...
    "JOIN extractor_versions evb ON evb.extractor_version_id = xb.extractor_version_id " + ...
    "WHERE eva.extractor_id <> evb.extractor_id ORDER BY cf.canonical_name");
names = string(byName.canonical_name);
verifyEqual(testCase, numel(names), 6);
verifyFalse(testCase, ismember("frequency_center", names));
verifyFalse(testCase, ismember("contour_median_frequency", names));

% The registry route finds it, and keeps both methods distinct while doing so.
report = summarizeNominal(fixture);
centre = report.feature_pairs( ...
    string(report.feature_pairs.equivalence_class) == "vocalization_frequency_center", :);
verifyEqual(testCase, height(centre), 1);
verifyEqual(testCase, string(centre.feature_a_canonical_name), "contour_median_frequency");
verifyEqual(testCase, string(centre.feature_b_canonical_name), "frequency_center");
verifyNotEqual(testCase, string(centre.feature_a_canonical_name), ...
    string(centre.feature_b_canonical_name));
verifyEqual(testCase, string(centre.relationship_type), "comparable");
verifyNotEqual(testCase, string(centre.relationship_type), "transform_equivalent");
verifyTrue(testCase, centre.consilience_eligible);

% Comparable is not identical: the two derivation stages stay different.
verifyEqual(testCase, string(centre.feature_a_derivation_stage), "contour_derived");
verifyEqual(testCase, string(centre.feature_b_derivation_stage), "spectral_filterbank");

% The pair is genuinely compared, so the discovery is not merely decorative.
comparison = report.feature_comparisons( ...
    string(report.feature_comparisons.equivalence_class) == ...
    "vocalization_frequency_center", :);
verifyEqual(testCase, height(comparison), 1);
verifyEqual(testCase, string(comparison.status), "computed");
end

function testPowerEnergyAndAmplitudeStayIneligible(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
pairs = report.feature_pairs;

% Both power-like relationships are discoverable as related, and neither is
% eligible, so neither reaches any comparison or summary row.
ineligible = pairs(~pairs.consilience_eligible, :);
verifyEqual(testCase, height(ineligible), 2);
verifyEqual(testCase, unique(string(ineligible.relationship_type)), "related");
verifyEqual(testCase, unique(string(ineligible.extractor_a_name)), "DeepSqueak");
verifyEqual(testCase, sort(string(ineligible.feature_b_canonical_name)), ...
    ["peak_amplitude"; "total_energy"]);
verifyFalse(testCase, any(ineligible.comparison_eligible));

% They are also unit-incompatible, which the report states rather than papering
% over with an ad hoc conversion.
verifyEqual(testCase, unique(string(ineligible.unit_status)), "incompatible");

classes = string(report.feature_comparisons.equivalence_class);
verifyFalse(testCase, any(contains(classes, "power")));
verifyFalse(testCase, any(contains(classes, "amplitude")));
verifyFalse(testCase, any(contains(classes, "energy")));
verifyFalse(testCase, any(contains(string(report.feature_summary.equivalence_class), ...
    "power")));

% Eligibility comes from the registry column, not from a name list in code.
stored = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM feature_relationships " + ...
    "WHERE consilience_eligible = 0");
verifyEqual(testCase, double(stored.n(1)), 2);
end

% -------------------------------------------------------- feature agreement ---

function testOneToOneFeatureDifferencesAreExact(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
comparisons = report.feature_comparisons;

% Seven eligible pairs on the single one-to-one group.
verifyEqual(testCase, height(comparisons), 7);
verifyEqual(testCase, unique(string(comparisons.match_type)), "one_to_one");
verifyEqual(testCase, unique(string(comparisons.status)), "computed");

% Signed difference is run_b minus run_a, in canonical units, with both native
% values retained beside it.
minimum = comparisonFor(comparisons, "vocalization_frequency_min");
verifyEqual(testCase, minimum.value_a, 45000, AbsTol=1e-9);
verifyEqual(testCase, minimum.value_b, 46000, AbsTol=1e-9);
verifyEqual(testCase, minimum.signed_difference, 1000, AbsTol=1e-9);
verifyEqual(testCase, minimum.absolute_difference, 1000, AbsTol=1e-9);
verifyEqual(testCase, minimum.pair_mean, 45500, AbsTol=1e-9);
verifyEqual(testCase, string(minimum.canonical_unit), "Hz");

maximum = comparisonFor(comparisons, "vocalization_frequency_max");
verifyEqual(testCase, maximum.signed_difference, -1000, AbsTol=1e-9);
verifyEqual(testCase, maximum.absolute_difference, 1000, AbsTol=1e-9);

% Relative difference and the tolerance verdict appear only where the
% specification declares a relative tolerance for that class.
verifyEqual(testCase, minimum.relative_tolerance, 0.10, AbsTol=1e-12);
verifyEqual(testCase, minimum.relative_difference, 1000/45500, AbsTol=1e-12);
verifyEqual(testCase, minimum.within_tolerance, 1);

onset = comparisonFor(comparisons, "vocalization_start_time");
verifyTrue(testCase, isnan(onset.relative_tolerance));
verifyTrue(testCase, isnan(onset.relative_difference));
verifyTrue(testCase, isnan(onset.within_tolerance));
verifyEqual(testCase, onset.signed_difference, 0.004, AbsTol=1e-9);

% A discrepancy beyond tolerance is flagged rather than smoothed.
bandwidth = comparisonFor(comparisons, "vocalization_frequency_bandwidth");
verifyEqual(testCase, bandwidth.value_a, 35000, AbsTol=1e-9);
verifyEqual(testCase, bandwidth.value_b, 15000, AbsTol=1e-9);
verifyEqual(testCase, bandwidth.signed_difference, -20000, AbsTol=1e-9);
verifyEqual(testCase, bandwidth.within_tolerance, 0);
end

function testAmbiguousAndUnmatchedGroupsAreExcludedNotAveraged(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);

% Only the one-to-one group produces comparisons.
verifyEqual(testCase, numel(unique(report.feature_comparisons.match_group_id)), 1);

excluded = report.excluded_groups;
verifyEqual(testCase, height(excluded), 3);
splitRows = excluded(string(excluded.match_type) == "one_to_many", :);
verifyEqual(testCase, height(splitRows), 1);
verifyEqual(testCase, string(splitRows.reason), "not_computed_split_merge");
verifyEqual(testCase, ...
    unique(string(excluded(string(excluded.match_type) == "unmatched", :).reason)), ...
    "not_computed_unmatched");

% The two MUPET syllables inside the split component were never averaged to
% manufacture a value to compare against the one DeepSqueak call.
splitGroupId = splitRows.match_group_id(1);
verifyFalse(testCase, any(report.feature_comparisons.match_group_id == splitGroupId));
verifyEqual(testCase, sum(report.feature_summary.n_pairs), 7);
end

function testMissingMeasurementIsAbsentEvidenceNotDisagreement(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Remove one side of one eligible pair on the matched DeepSqueak call, leaving
% the temporal correspondence untouched.
execute(fixture.conn, "DELETE FROM event_measurements WHERE event_measurement_id IN (" + ...
    "SELECT em.event_measurement_id FROM event_measurements em " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "WHERE xf.native_name = 'Low Freq (kHz)' AND d.native_event_id = '1' " + ...
    "AND d.extraction_run_id = (SELECT extraction_run_id FROM extraction_runs " + ...
    "WHERE run_key = 'ds-imported'))");
report = summarize(fixture, "match-nominal");

minimum = comparisonFor(report.feature_comparisons, "vocalization_frequency_min");
verifyEqual(testCase, string(minimum.status), "not_computed_missing_measurement");
verifyTrue(testCase, isnan(minimum.value_a));
verifyTrue(testCase, isnan(minimum.signed_difference));
verifyTrue(testCase, isnan(minimum.absolute_difference));

% Absent evidence is not a discrepancy: the pair is not counted as outside
% tolerance, and it drops out of the aggregate rather than biasing it.
verifyTrue(testCase, isnan(minimum.within_tolerance));
classes = string(report.feature_summary.equivalence_class);
verifyFalse(testCase, ismember("vocalization_frequency_min", classes));
verifyEqual(testCase, sum(report.feature_summary.n_pairs), 6);

% The group itself is still matched. A missing column does not unmatch a pair.
verifyEqual(testCase, report.temporal_agreement.group_count, 1);
verifyEqual(testCase, report.detection_agreement.in_one_to_one_groups(1), 1);
end

function testExportedDurationComparisonIsNotTheBoundaryDerivedDelta(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);

% Two different quantities share the word duration. The temporal evidence uses
% boundary-derived durations; the feature comparison uses MUPET's exported
% pre-noise-reduction duration. The fixture makes them disagree deliberately.
boundaryDelta = report.temporal_agreement.rows.duration_difference_s(1);
featureDelta = comparisonFor(report.feature_comparisons, ...
    "vocalization_duration").signed_difference;
verifyEqual(testCase, boundaryDelta, -0.002, AbsTol=1e-9);
verifyEqual(testCase, featureDelta, -0.008, AbsTol=1e-9);
verifyNotEqual(testCase, boundaryDelta, featureDelta);

% The operational variant that makes them different quantities is carried on the
% comparison row rather than left for a reader to infer.
duration = comparisonFor(report.feature_comparisons, "vocalization_duration");
verifyEqual(testCase, string(duration.feature_b_operational_variant), ...
    "pre_noise_reduction");
verifyEqual(testCase, string(duration.feature_a_operational_variant), "");
verifyTrue(testCase, duration.primary_temporal_evidence);
end

function testAggregateSummariesAndDeferredAssociation(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
summary = report.feature_summary;

verifyEqual(testCase, height(summary), 7);
verifyEqual(testCase, unique(summary.n_pairs), 1);
bandwidth = summaryFor(summary, "vocalization_frequency_bandwidth");
verifyEqual(testCase, bandwidth.mean_signed_bias, -20000, AbsTol=1e-9);
verifyEqual(testCase, bandwidth.median_signed_bias, -20000, AbsTol=1e-9);
verifyEqual(testCase, bandwidth.mean_absolute_difference, 20000, AbsTol=1e-9);
verifyEqual(testCase, bandwidth.outside_tolerance_count, 1);
verifyEqual(testCase, string(bandwidth.canonical_unit), "Hz");

% With one matched event, dispersion is undefined rather than reported as zero.
verifyTrue(testCase, isnan(bandwidth.std_signed_bias));
verifyTrue(testCase, isnan(bandwidth.iqr_absolute_difference));

% Correlation is secondary and is not computed below the specification's
% minimum. On a synthetic fixture it would characterise the fixture.
verifyEqual(testCase, unique(string(summary.association_kind)), ...
    "not_computed_insufficient_n");
verifyTrue(testCase, all(isnan(summary.association_value)));
verifyEqual(testCase, report.specification.secondary_minimum_n, 10);

% ICC is deliberately deferred, and the reason travels with the report.
verifyFalse(testCase, report.specification.icc_enabled);
verifyGreaterThan(testCase, strlength(report.specification.icc_reason), 0);
end

% ------------------------------------------------------------- persistence ---

function testPersistenceScopesStatisticsToAChildAnalysisRun(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyEqual(testCase, countOf(fixture.conn, "agreement_statistics"), 0);
report = summarize(fixture, "match-nominal", true);

verifyTrue(testCase, report.committed);
verifyEqual(testCase, report.status, "committed");
verifyEqual(testCase, report.applied_counts.analysis_runs, 1);
verifyGreaterThan(testCase, report.applied_counts.agreement_statistics, 0);

child = fetch(fixture.conn, "SELECT run_type, run_key, status, " + ...
    "parent_analysis_run_id, IFNULL(notes,'') AS notes FROM analysis_runs " + ...
    "WHERE run_type = 'cross_extractor_agreement'");
verifyEqual(testCase, height(child), 1);
verifyEqual(testCase, string(child.status(1)), "completed");
verifyEqual(testCase, double(child.parent_analysis_run_id(1)), ...
    report.analysis.analysis_run_id);
verifySubstring(testCase, string(child.run_key(1)), "match-nominal:agreement:");

% The child records the agreement algorithm version separately from the matching
% algorithm, and states that per-pair rows were deliberately not persisted.
notes = jsondecode(char(child.notes(1)));
verifyEqual(testCase, string(notes.algorithm_key), "detection_and_feature_agreement");
verifyFalse(testCase, notes.per_pair_rows_persisted);
verifyEqual(testCase, string(notes.specification_checksum_sha256), ...
    report.specification.checksum_sha256);

% Statistics use the schema's own kinds, and feature rows carry both feature IDs
% so each aggregate stays traceable to the exact registered pair.
kinds = fetch(fixture.conn, "SELECT statistic_kind, COUNT(*) AS n " + ...
    "FROM agreement_statistics GROUP BY statistic_kind ORDER BY statistic_kind");
verifyEqual(testCase, sort(string(kinds.statistic_kind)), ...
    ["detection_agreement"; "feature_agreement"; "matching_diagnostic"]);
featureRows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM agreement_statistics " + ...
    "WHERE statistic_kind = 'feature_agreement' AND (feature_a_id IS NULL " + ...
    "OR feature_b_id IS NULL)");
verifyEqual(testCase, double(featureRows.n(1)), 0);

% Per-pair comparison rows exist in the report but nowhere in the database.
verifyEqual(testCase, height(report.feature_comparisons), 7);
verifyEqual(testCase, countOf(fixture.conn, "consilience_assessments"), 0);
verifyEqual(testCase, countOf(fixture.conn, "manual_reviews"), 0);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
end

function testRerunReusesAndChangedStatisticsConflict(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = summarize(fixture, "match-nominal", true);
before = countOf(fixture.conn, "agreement_statistics");

second = summarize(fixture, "match-nominal", true);
verifyEqual(testCase, second.status, "reused");
verifyEqual(testCase, second.applied_counts.agreement_statistics, 0);
verifyEqual(testCase, second.applied_counts.reused_agreement_statistics, before);
verifyEqual(testCase, countOf(fixture.conn, "agreement_statistics"), before);
verifyEqual(testCase, second.agreement_analysis.analysis_run_id, ...
    first.agreement_analysis.analysis_run_id);
verifyEqual(testCase, countOf(fixture.conn, "analysis_runs"), 2);

% A stored summary is never repaired in place. Corrupting one value makes the
% next apply conflict rather than silently overwrite it.
execute(fixture.conn, "UPDATE agreement_statistics SET statistic_value = 42 " + ...
    "WHERE statistic_name = 'run_a.total_detections'");
verifyError(testCase, @() summarize(fixture, "match-nominal", true), ...
    "vawlume:consilience:AgreementConflict");
stillWrong = fetch(fixture.conn, "SELECT statistic_value FROM agreement_statistics " + ...
    "WHERE statistic_name = 'run_a.total_detections'");
verifyEqual(testCase, double(stillWrong.statistic_value(1)), 42);
verifyEqual(testCase, countOf(fixture.conn, "agreement_statistics"), before);
end

function testSummarizeNeverMutatesUpstreamRows(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = upstreamFingerprint(fixture.conn);

% The read-only default writes nothing at all, not even the derived analysis.
countsBefore = allCounts(fixture.conn);
summarizeNominal(fixture);
verifyEqual(testCase, allCounts(fixture.conn), countsBefore);
verifyEqual(testCase, upstreamFingerprint(fixture.conn), before);

% Applying writes only the agreement rows and still leaves upstream untouched.
summarize(fixture, "match-nominal", true);
verifyEqual(testCase, upstreamFingerprint(fixture.conn), before);
countsAfter = allCounts(fixture.conn);
verifyEqual(testCase, countsAfter.detections, countsBefore.detections);
verifyEqual(testCase, countsAfter.event_measurements, countsBefore.event_measurements);
verifyEqual(testCase, countsAfter.candidate_pairs, countsBefore.candidate_pairs);
verifyEqual(testCase, countsAfter.match_groups, countsBefore.match_groups);
verifyEqual(testCase, countsAfter.consensus_events, countsBefore.consensus_events);
verifyGreaterThan(testCase, countsAfter.agreement_statistics, 0);

% No consilience source file writes to an upstream table.
source = "";
files = dir(fullfile(fixture.repo_root, "src", "+vawlume", "+consilience", ...
    "**", "*.m"));
for index = 1:numel(files)
    source = source + string(fileread(fullfile(files(index).folder, ...
        files(index).name)));
end
for table = ["detections", "event_measurements", "curation_events", ...
        "classification_assignments", "extraction_runs", "artifacts", ...
        "extractor_features", "feature_relationships", "match_groups", ...
        "candidate_pairs", "consensus_events"]
    verifyFalse(testCase, contains(source, "UPDATE " + table), table);
    verifyFalse(testCase, contains(source, "DELETE FROM " + table), table);
    verifyFalse(testCase, contains(source, "INSERT INTO " + table), table);
end
end

% ---------------------------------------------------------- provenance guard ---

function testSpecificationIsResolvedFromTheAnalysisAndChecksumChecked(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);

% The caller never supplies the specification. It is the exact registered
% version the matching analysis linked.
stored = fetch(fixture.conn, "SELECT cp.profile_key, cpv.version_label, " + ...
    "cpv.checksum_sha256 FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE arp.assignment_role = 'matching_spec'");
verifyEqual(testCase, report.specification.profile_key, string(stored.profile_key(1)));
verifyEqual(testCase, report.specification.version_label, ...
    string(stored.version_label(1)));
verifyEqual(testCase, report.specification.checksum_sha256, ...
    string(stored.checksum_sha256(1)));

% If the file behind that registration changes, agreement refuses rather than
% summarizing groups under a specification that did not produce them.
execute(fixture.conn, "UPDATE config_profile_versions " + ...
    "SET checksum_sha256 = 'deadbeef' || substr(checksum_sha256, 9)");
verifyError(testCase, @() summarizeNominal(fixture), ...
    "vawlume:consilience:SpecificationChanged");
end

function testReportRefusesIncompleteOrNonMatchingAnalyses(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

verifyError(testCase, @() vawlume.consilience.summarize(fixture.conn, ...
    struct(run_key="no-such-analysis"), RepoRoot=fixture.repo_root), ...
    "vawlume:consilience:AnalysisNotFound");
verifyError(testCase, @() vawlume.consilience.summarize(fixture.conn, ...
    struct(run_key="match-nominal", analysis_run_id=1), ...
    RepoRoot=fixture.repo_root), "vawlume:consilience:AnalysisRefInvalid");

execute(fixture.conn, "INSERT INTO analysis_runs(project_id,run_type,run_key,status) " + ...
    "VALUES(1,'external_time_alignment','alignment-1','completed')");
verifyError(testCase, @() vawlume.consilience.summarize(fixture.conn, ...
    struct(run_key="alignment-1"), RepoRoot=fixture.repo_root), ...
    "vawlume:consilience:AnalysisNotMatching");

execute(fixture.conn, "UPDATE analysis_runs SET status = 'started' " + ...
    "WHERE run_key = 'match-nominal'");
verifyError(testCase, @() summarizeNominal(fixture), ...
    "vawlume:consilience:AnalysisIncomplete");
end

% ---------------------------------------------------------------- helpers ---

function report = summarizeNominal(fixture)
report = summarize(fixture, "match-nominal");
end

function report = summarize(fixture, runKey, apply)
if nargin < 3
    apply = false;
end
report = vawlume.consilience.summarize(fixture.conn, struct(run_key=runKey), ...
    RepoRoot=fixture.repo_root, Apply=apply);
end

function value = topologyValue(topology, matchType, column)
row = topology(string(topology.match_type) == matchType, :);
assert(height(row) == 1, "Expected one topology row for %s.", matchType);
value = row.(column);
end

function row = comparisonFor(comparisons, equivalenceClass)
selected = string(comparisons.equivalence_class) == equivalenceClass;
assert(nnz(selected) == 1, "Expected one comparison for %s, found %d.", ...
    equivalenceClass, nnz(selected));
row = table2struct(comparisons(selected, :));
end

function row = summaryFor(summary, equivalenceClass)
selected = string(summary.equivalence_class) == equivalenceClass;
assert(nnz(selected) == 1, "Expected one summary for %s, found %d.", ...
    equivalenceClass, nnz(selected));
row = table2struct(summary(selected, :));
end

function value = upstreamFingerprint(conn)
value = fetch(conn, "SELECT d.detection_id, d.start_time_s, d.end_time_s, " + ...
    "COUNT(em.event_measurement_id) AS measurements, " + ...
    "IFNULL(SUM(em.canonical_value_real), 0) AS canonical_total " + ...
    "FROM detections d LEFT JOIN event_measurements em " + ...
    "ON em.detection_id = d.detection_id GROUP BY d.detection_id " + ...
    "ORDER BY d.detection_id");
end

function value = allCounts(conn)
names = ["analysis_runs", "analysis_run_profiles", "agreement_statistics", ...
    "candidate_pairs", "match_groups", "match_group_members", ...
    "consensus_events", "consilience_assessments", "manual_reviews", ...
    "detections", "event_measurements"];
value = struct();
for name = names
    value.(name) = countOf(conn, name);
end
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function verifySubstring(testCase, actual, expected)
verifyTrue(testCase, contains(string(actual), expected), ...
    "Expected '" + expected + "' inside '" + string(actual) + "'.");
end

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE One recording, two real imports, one completed matching analysis.
%
% The geometry gives exactly one unambiguous 1:1 component, one 1:2 split
% component, and one unmatched detection on each side, so every denominator in
% the detection-agreement report has something to distinguish.
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
conn = sqlite(char(fullfile(scratch, "agreement.sqlite")), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('agreement-project','Agreement Project')");
execute(conn, "INSERT INTO source_files(project_id,file_role,path_or_uri," + ...
    "relative_path,filename) VALUES(1,'recording_audio','audio/REC_A.wav'," + ...
    "'audio/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO recordings(project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,'REC_A')");

dsRoot = fullfile(scratch, "deepsqueak");
mupetRoot = fullfile(scratch, "mupet");
dsPath = fullfile(dsRoot, "exports", "REC_A_Stats.xlsx");
mupetPath = fullfile(mupetRoot, "CSV", "REC_A.csv");
configPath = fullfile(mupetRoot, "config.csv");
writeCells(dsPath, deepSqueakCells());
writeCells(mupetPath, mupetCells());
writeText(configPath, strjoin(mupetConfigLines(), newline) + newline);

ref = struct(project_key="agreement-project", ...
    source_relative_path="audio/REC_A.wav");
vawlume.ingest.deepsqueak(conn, dsPath, ref, ...
    struct(run_key="ds-imported", extractor_version="3.2.1"), ...
    RepoRoot=repoRoot, ArtifactRoot=dsRoot, Apply=true);
vawlume.ingest.mupet(conn, mupetPath, ref, ...
    struct(run_key="mupet-imported", extractor_version="2.1", ...
        settings=struct(config_path=configPath)), ...
    RepoRoot=repoRoot, ArtifactRoot=mupetRoot, Apply=true);
vawlume.matching.compare(conn, ref, ...
    struct(run_a="ds-imported", run_b="mupet-imported"), ...
    struct(run_key="match-nominal"), RepoRoot=repoRoot, Apply=true);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);
end

function cells = deepSqueakCells()
% Call 1 pairs one-to-one with syllable 1; call 2 has no MUPET counterpart;
% call 3 spans syllables 3 and 4. Call 1's bandwidth is deliberately far from
% MUPET's so one eligible comparison falls outside tolerance.
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
detectionFile = 'synthetic/deepsqueak/REC_A_detections.mat';
cells = [
    headers
    {detectionFile, 1, 'class_a', 1, 0.9134, 10.000, 10.050, 0.050, ...
        62.0, 45.0, 80.0, 35.0, 3.2, -120.5, 1.12, -71.4, 0.78, 63.0}
    {detectionFile, 2, 'class_a', 1, 0.8021, 20.000, 20.040, 0.040, ...
        61.0, 50.0, 72.0, 22.0, 2.1, 15.0, 1.05, -70.1, 0.81, 61.5}
    {detectionFile, 3, 'class_b', 0, 0.2107, 40.000, 40.100, 0.100, ...
        63.5, 42.0, 84.0, 42.0, 4.4, -8.25, 1.40, -69.3, 0.69, 64.2}
];
end

function cells = mupetCells()
% Syllable 1's exported duration is 42 ms against a 48 ms boundary span, which
% is what a pre-noise-reduction duration legitimately does and is what makes the
% exported-duration comparison a different quantity from the boundary delta.
headers = {'Syllable number', 'Syllable start time (sec)', ...
    'Syllable end time (sec)', 'inter-syllable interval (sec)', ...
    'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', ...
    'maximum frequency (kHz)', 'mean frequency (kHz)', ...
    'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
cells = [
    headers
    {1, 10.004, 10.052, 19.948, 42.0, 45.0, 62.0, 46.0, 79.0, 63.0, 15.0, 12.5, -18}
    {2, 30.000, 30.035, 10.002, 34.7, 46.0, 59.0, 50.5, 72.5, 61.0, 22.0, 11.5, -19}
    {3, 40.002, 40.045, 0.007, 42.6, 47.0, 61.0, 42.5, 84.5, 63.0, 42.0, 10.5, -20}
    {4, 40.052, 40.098, 'NA', 45.8, 48.0, 62.0, 43.0, 83.0, 62.5, 40.0, 9.5, -21}
];
end

function lines = mupetConfigLines()
lines = ["noise-reduction,5"; "minimum-syllable-duration,008"; ...
    "maximum-syllable-duration,200"; "minimum-syllable-total-energy,-15"; ...
    "minimum-syllable-peak-amplitude,-25"; "minimum-syllable-distance,5"; ...
    "sample-frequency,250000"; "minimum-usv-frequency,30000"; ...
    "maximum-usv-frequency,120000"; "number-filterbank-filters,64"; ...
    "filterbank-type,1"];
end

function writeCells(path, cells)
makeParent(path);
if isfile(path), delete(path); end
writecell(cells, path);
end

function writeText(path, value)
makeParent(path);
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", value);
delete(cleaner);
end

function makeParent(path)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
end

function tearDown(conn, scratch, repoRoot)
try close(conn); catch; end
if isfolder(scratch), rmdir(scratch, "s"); end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
