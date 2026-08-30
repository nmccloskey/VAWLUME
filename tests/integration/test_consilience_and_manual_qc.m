function tests = test_consilience_and_manual_qc
tests = functiontests({ ...
    @testEveryStatusRuleFiresOnItsOwnCase, ...
    @testIneligibleRelationshipsCannotChangeAStatus, ...
    @testMissingEligibleFeatureFollowsTheConfiguredPolicy, ...
    @testStatusCarriesItsEvidenceAndNoProbability, ...
    @testManualAdjudicationNeverOverwritesTheAutomatedStatus, ...
    @testManualReferenceIsIndependentOfExtractorCuration, ...
    @testManualPrecisionRecallAndBoundaryErrorAreExact, ...
    @testRecallRequiresDeclaredExhaustiveCoverage, ...
    @testContingencyComparesAutomatedStatusWithIndependentEvidence, ...
    @testAssessmentsPersistAtomicallyWithTheStatistics, ...
    @testFailureLeavesNoHalfWrittenAgreementAnalysis, ...
    @testRerunReusesAndChangedStatusConflicts, ...
    @testThresholdConfigurationsChangeOutcomesWithoutMutatingEachOther, ...
    @testSensitivityRefusesNonComparableInputsAndNamesNoWinner, ...
    @testConsilienceWritesNothingUpstreamAndNoScore});
end

% -------------------------------------------------------------- status rules ---

function testEveryStatusRuleFiresOnItsOwnCase(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
assessments = report.consilience;

verifyEqual(testCase, height(assessments), 6);
verifyEqual(testCase, sort(assessments.automated_status), sort([ ...
    "matched_feature_supported"; "matched_feature_discrepant"; ...
    "ambiguous_split_merge"; "single_extractor"; "single_extractor"; ...
    "single_extractor"]));

% One-to-one with four supporting comparisons inside tolerance.
supported = statusOf(assessments, "matched_feature_supported");
verifyEqual(testCase, supported.match_type, "one_to_one");
verifyEqual(testCase, supported.supporting_available, 4);
verifyEqual(testCase, supported.supporting_within, 4);
verifyEqual(testCase, supported.supporting_outside, 0);
verifySubstring(testCase, supported.automated_rule, "meeting the configured minimum of 2");

% One-to-one where the extrema agree but the derived bandwidth does not. The
% features that triggered the status are preserved, not just the verdict.
discrepant = statusOf(assessments, "matched_feature_discrepant");
verifyEqual(testCase, discrepant.match_type, "one_to_one");
verifyEqual(testCase, discrepant.supporting_within, 3);
verifyEqual(testCase, discrepant.supporting_outside, 1);
verifyEqual(testCase, discrepant.discrepant_classes, ...
    "vocalization_frequency_bandwidth");

% Ambiguous topology outranks feature evidence: a split component never earns a
% feature-supported status by averaging its members.
ambiguous = statusOf(assessments, "ambiguous_split_merge");
verifyEqual(testCase, ambiguous.match_type, "one_to_many");
verifyEqual(testCase, ambiguous.supporting_available, 0);
verifySubstring(testCase, ambiguous.automated_rule, "no aggregation model");

% Unmatched means no eligible correspondence, and the rule says so explicitly.
unmatched = assessments(assessments.automated_status == "single_extractor", :);
verifyEqual(testCase, height(unmatched), 3);
verifyEqual(testCase, unique(unmatched.match_type), "unmatched");
verifySubstring(testCase, unmatched.automated_rule(1), "not a false positive");

counts = report.consilience_status_counts;
verifyEqual(testCase, statusCount(counts, "matched_feature_supported"), 1);
verifyEqual(testCase, statusCount(counts, "matched_feature_discrepant"), 1);
verifyEqual(testCase, statusCount(counts, "ambiguous_split_merge"), 1);
verifyEqual(testCase, statusCount(counts, "single_extractor"), 3);
verifyEqual(testCase, statusCount(counts, "temporally_matched"), 0);
end

function testIneligibleRelationshipsCannotChangeAStatus(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = summarizeNominal(fixture);

% Drive both power-like measurements far apart on the supported pair. They are
% registered as related with consilience_eligible = 0, so nothing about the
% status may move.
execute(fixture.conn, "UPDATE event_measurements SET canonical_value_real = -999 " + ...
    "WHERE extractor_feature_id IN (SELECT extractor_feature_id " + ...
    "FROM extractor_features WHERE native_name IN " + ...
    "('Mean Power (dB/Hz)', 'total syllable energy (dB)', " + ...
    "'peak syllable amplitude (dB)'))");
after = summarizeNominal(fixture);

verifyEqual(testCase, after.consilience.automated_status, ...
    before.consilience.automated_status);
verifyEqual(testCase, after.consilience.supporting_within, ...
    before.consilience.supporting_within);
verifyEqual(testCase, after.consilience.supporting_outside, ...
    before.consilience.supporting_outside);

% The ineligible pairs are still discoverable; they simply never score.
ineligible = after.feature_pairs(~after.feature_pairs.consilience_eligible, :);
verifyEqual(testCase, height(ineligible), 2);
verifyFalse(testCase, any(contains(string(after.feature_comparisons.equivalence_class), ...
    "power")));
end

function testMissingEligibleFeatureFollowsTheConfiguredPolicy(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = summarizeNominal(fixture);
supportedGroup = statusOf(before.consilience, "matched_feature_supported");

% Remove three of the four supporting measurements from the DeepSqueak side of
% the supported pair, leaving the temporal correspondence untouched.
execute(fixture.conn, "DELETE FROM event_measurements WHERE event_measurement_id IN (" + ...
    "SELECT em.event_measurement_id FROM event_measurements em " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN detections d ON d.detection_id = em.detection_id " + ...
    "WHERE d.detection_id = " + string(supportedGroup.match_group_id * 0 + ...
    firstMemberDetection(fixture.conn, supportedGroup.match_group_id, "run_a")) + ...
    " AND xf.native_name IN ('Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)'))");
after = summarizeNominal(fixture);
downgraded = after.consilience(after.consilience.match_group_id == ...
    supportedGroup.match_group_id, :);

% Missing evidence is not disagreement: nothing becomes discrepant.
verifyEqual(testCase, downgraded.supporting_outside, 0);
verifyEqual(testCase, downgraded.supporting_missing, 3);
verifyEqual(testCase, downgraded.supporting_within, 1);

% It only reduces the count of available support, so the group falls back to the
% temporal baseline rather than being called a discrepancy.
verifyEqual(testCase, downgraded.automated_status, "temporally_matched");
verifySubstring(testCase, downgraded.automated_rule, "not a discrepancy");
verifyEqual(testCase, after.specification.missing_feature_policy, "not_a_discrepancy");

% The temporal correspondence is untouched by a missing measurement.
verifyEqual(testCase, after.temporal_agreement.group_count, ...
    before.temporal_agreement.group_count);
end

function testStatusCarriesItsEvidenceAndNoProbability(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarize(fixture, "match-nominal", true);

% A NULL score is the assertion here, so it is counted in SQL rather than
% fetched: MATLAB's SQLite fetch cannot return a NULL numeric column.
nulls = fetch(fixture.conn, "SELECT COUNT(*) AS total, " + ...
    "SUM(CASE WHEN score IS NULL THEN 1 ELSE 0 END) AS null_scores, " + ...
    "SUM(CASE WHEN consensus_event_id IS NULL THEN 1 ELSE 0 END) AS null_consensus, " + ...
    "SUM(CASE WHEN match_group_id IS NOT NULL THEN 1 ELSE 0 END) AS group_targets " + ...
    "FROM consilience_assessments");
verifyEqual(testCase, double(nulls.total(1)), 6);

% Every assessment targets a match group, and no score is stored, because a
% consilience status is a categorical evidence summary rather than a probability.
verifyEqual(testCase, double(nulls.null_scores(1)), 6);
verifyEqual(testCase, double(nulls.null_consensus(1)), 6);
verifyEqual(testCase, double(nulls.group_targets(1)), 6);

rows = fetch(fixture.conn, "SELECT ca.match_group_id, ca.status, " + ...
    "ca.rationale_json FROM consilience_assessments ca " + ...
    "ORDER BY ca.match_group_id");
verifyEqual(testCase, height(rows), 6);

rationale = jsondecode(char(rows.rationale_json(1)));
verifyEqual(testCase, string(rationale.rule_set.profile_key), ...
    report.specification.profile_key);
verifyEqual(testCase, string(rationale.rule_set.checksum_sha256), ...
    report.specification.checksum_sha256);
verifyEqual(testCase, string(rationale.rule_set.algorithm_key), ...
    "detection_and_feature_agreement");
verifyEqual(testCase, string(rationale.matching_analysis.run_key), "match-nominal");
verifyGreaterThan(testCase, strlength(string(rationale.automated_rule)), 0);
verifyEqual(testCase, rationale.feature_evidence.minimum_required, 2);
verifyTrue(testCase, rationale.feature_evidence.ineligible_relationships_excluded);
verifySubstring(testCase, string(rationale.score_omitted_reason), ...
    "not a calibrated probability");
verifyFalse(testCase, report.specification.icc_enabled);
end

% ------------------------------------------------------------------ manual QC ---

function testManualAdjudicationNeverOverwritesTheAutomatedStatus(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarize(fixture, "match-nominal", true);
assessments = report.consilience;

supported = statusOf(assessments, "matched_feature_supported");
verifyEqual(testCase, supported.manual_status, "adjudicated_positive");
verifyEqual(testCase, supported.effective_status, "adjudicated_positive");
verifyEqual(testCase, supported.automated_status, "matched_feature_supported");

adjudicatedNegative = assessments(assessments.manual_status == ...
    "adjudicated_negative", :);
verifyEqual(testCase, height(adjudicatedNegative), 1);
verifyEqual(testCase, adjudicatedNegative.automated_status, "single_extractor");
verifyEqual(testCase, adjudicatedNegative.effective_status, "adjudicated_negative");

% Groups nobody reviewed keep the automated status as their effective status.
unreviewed = assessments(assessments.manual_status == "not_reviewed", :);
verifyEqual(testCase, height(unreviewed), 4);
verifyEqual(testCase, unreviewed.effective_status, unreviewed.automated_status);

% What persists is the automated status. The manual verdict stays in its own
% manual_reviews row, so manual review never destroys the algorithmic result.
stored = fetch(fixture.conn, "SELECT ca.status FROM consilience_assessments ca " + ...
    "JOIN manual_reviews mr ON mr.match_group_id = ca.match_group_id " + ...
    "WHERE mr.review_status = 'adjudicated_negative'");
verifyEqual(testCase, height(stored), 1);
verifyEqual(testCase, string(stored.status(1)), "single_extractor");
verifyNotEqual(testCase, string(stored.status(1)), "adjudicated_negative");

% The effective status is reported, never stored.
statuses = fetch(fixture.conn, "SELECT DISTINCT status FROM consilience_assessments");
verifyFalse(testCase, any(contains(string(statuses.status), "adjudicated")));
end

function testManualReferenceIsIndependentOfExtractorCuration(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
crossReference = report.manual_qc.curation_cross_reference;

% The fixture makes DeepSqueak's own accept flag disagree with the independent
% reference in both directions: an accepted call the reviewer did not mark, and
% a rejected call the reviewer did.
accepted = crossReference(string(crossReference.curation_status) == "accepted", :);
rejected = crossReference(string(crossReference.curation_status) == "rejected", :);
verifyEqual(testCase, accepted.detection_count, 3);
verifyEqual(testCase, accepted.reference_supported, 2);
verifyEqual(testCase, accepted.reference_absent, 1);
verifyEqual(testCase, rejected.detection_count, 1);
verifyEqual(testCase, rejected.reference_supported, 1);
verifyEqual(testCase, rejected.reference_absent, 0);

% MUPET contributes no curation rows at all, so the cross-reference is
% DeepSqueak-only by construction rather than by filtering.
verifyEqual(testCase, unique(string(crossReference.extractor_name)), "DeepSqueak");

% Curation never reaches the status rules or the reference matching.
source = "";
files = dir(fullfile(fixture.repo_root, "src", "+vawlume", "+consilience", ...
    "**", "*.m"));
for index = 1:numel(files)
    source = source + string(fileread(fullfile(files(index).folder, ...
        files(index).name)));
end
verifyFalse(testCase, contains(source, "classification_assignments"));
verifyFalse(testCase, contains(source, "detection_score"));
classifier = string(fileread(fullfile(fixture.repo_root, "src", "+vawlume", ...
    "+consilience", "private", "consilienceClassify.m")));
verifyFalse(testCase, contains(classifier, "curation_events"));
verifyFalse(testCase, contains(classifier, "Accepted"));
end

function testManualPrecisionRecallAndBoundaryErrorAreExact(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
perRun = report.manual_qc.per_run;

verifyTrue(testCase, report.manual_qc.reference_available);
verifyEqual(testCase, report.manual_qc.reference_event_count, 4);
verifyEqual(testCase, height(perRun), 2);

% DeepSqueak: 4 detections, 3 match a reference event, 1 does not, and one
% reference event no extractor found.
deepsqueak = perRun(1, :);
verifyEqual(testCase, deepsqueak.detection_count, 4);
verifyEqual(testCase, deepsqueak.true_positives, 3);
verifyEqual(testCase, deepsqueak.false_positives, 1);
verifyEqual(testCase, deepsqueak.false_negatives, 1);
verifyEqual(testCase, deepsqueak.precision, 0.75, AbsTol=1e-12);
verifyEqual(testCase, deepsqueak.recall, 0.75, AbsTol=1e-12);

% MUPET: 6 detections, 3 match. Its extra syllables are reviewed disagreements,
% so its precision differs from DeepSqueak's while recall matches.
mupet = perRun(2, :);
verifyEqual(testCase, mupet.detection_count, 6);
verifyEqual(testCase, mupet.true_positives, 3);
verifyEqual(testCase, mupet.false_positives, 3);
verifyEqual(testCase, mupet.false_negatives, 1);
verifyEqual(testCase, mupet.precision, 0.5, AbsTol=1e-12);
verifyEqual(testCase, mupet.recall, 0.75, AbsTol=1e-12);

% Each reference event is used at most once, so the split component's two
% syllables cannot both claim the same reference event.
links = report.manual_qc.links;
mupetLinks = links(string(links.run_role) == "run_b", :);
verifyEqual(testCase, numel(unique(mupetLinks.manual_reference_event_id)), 3);
verifyEqual(testCase, height(mupetLinks), 3);

% Boundary error is reported per link and signed against the reference.
verifyEqual(testCase, deepsqueak.mean_absolute_onset_error_s, ...
    mean(abs(links.onset_error_s(string(links.run_role) == "run_a"))), AbsTol=1e-12);
verifyGreaterThan(testCase, deepsqueak.mean_absolute_onset_error_s, 0);

% The missed reference event is reported for both runs, not silently dropped.
missed = report.manual_qc.unmatched_reference_events;
verifyEqual(testCase, numel(unique(string(missed.native_reference_id))), 1);
verifyEqual(testCase, unique(string(missed.native_reference_id)), "r4");

% The detection-to-reference rule is stated and is separate from the
% extractor-to-extractor rule, so neither can be tuned through the other.
verifyEqual(testCase, report.manual_qc.matching_rule.min_temporal_iou, 0.10);
verifySubstring(testCase, report.manual_qc.matching_rule.purpose, ...
    "separate from the");
verifyTrue(testCase, any(contains(report.manual_qc.caution, ...
    "not scientific performance evidence")));
end

function testRecallRequiresDeclaredExhaustiveCoverage(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
verifyEqual(testCase, report.manual_qc.coverage, "exhaustive_over_recording");
verifyTrue(testCase, report.manual_qc.recall_reportable);

% Under a specification that declares only partial coverage, a detection with no
% overlapping reference event might simply lie in an unreviewed region. Precision
% survives that; recall does not, and is withheld rather than guessed.
% The variant needs its own profile identity as well as its own content: a
% changed file under an existing profile key and version is an identity
% conflict, which is the immutable-configuration contract working correctly.
partialPath = writeSpecVariant(fixture, "partial.json", ...
    {'"coverage": "exhaustive_over_recording"', '"vawlume.matching.prototype.v1"'}, ...
    {'"coverage": "partial"', '"vawlume.matching.prototype.partial"'});
applyMatching(fixture, "match-partial", partialPath);
partial = vawlume.consilience.summarize(fixture.conn, ...
    struct(run_key="match-partial"), RepoRoot=fixture.repo_root);

verifyEqual(testCase, partial.manual_qc.coverage, "partial");
verifyFalse(testCase, partial.manual_qc.recall_reportable);
verifyTrue(testCase, all(isnan(partial.manual_qc.per_run.recall)));
verifyTrue(testCase, all(isnan(partial.manual_qc.per_run.false_negatives)));
verifyEqual(testCase, partial.manual_qc.per_run.precision(1), 0.75, AbsTol=1e-12);

% Nothing recall-derived reaches persistence under partial coverage either.
partialApplied = vawlume.consilience.summarize(fixture.conn, ...
    struct(run_key="match-partial"), RepoRoot=fixture.repo_root, Apply=true);
verifyTrue(testCase, partialApplied.committed);
names = fetch(fixture.conn, "SELECT statistic_name FROM agreement_statistics ags " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = ags.analysis_run_id " + ...
    "WHERE ar.run_key LIKE 'match-partial%'");
verifyFalse(testCase, any(contains(string(names.statistic_name), "recall")));
verifyTrue(testCase, any(contains(string(names.statistic_name), "precision")));
end

function testContingencyComparesAutomatedStatusWithIndependentEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarizeNominal(fixture);
contingency = report.manual_qc.contingency;

verifyEqual(testCase, sum(contingency.group_count), 6);
supported = contingencyFor(contingency, "matched_feature_supported");
verifyEqual(testCase, supported.reference_supported, 1);
verifyEqual(testCase, supported.reference_absent, 0);
verifyEqual(testCase, supported.adjudicated_positive, 1);

discrepant = contingencyFor(contingency, "matched_feature_discrepant");
verifyEqual(testCase, discrepant.reference_supported, 1);

% The interesting row: single-extractor groups split between reference-supported
% and reference-absent, which is exactly why single_extractor cannot mean
% false positive.
single = contingencyFor(contingency, "single_extractor");
verifyEqual(testCase, single.group_count, 3);
verifyEqual(testCase, single.reference_absent, 3);
verifyEqual(testCase, single.adjudicated_negative, 1);

verifyTrue(testCase, any(contains(report.terminology_note, "not a false positive")));
verifyTrue(testCase, any(contains(report.manual_qc.caution, ...
    "not scientific performance evidence")));
end

% ----------------------------------------------------------------- persistence ---

function testAssessmentsPersistAtomicallyWithTheStatistics(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
report = summarize(fixture, "match-nominal", true);

verifyEqual(testCase, report.applied_counts.consilience_assessments, 6);
verifyGreaterThan(testCase, report.applied_counts.agreement_statistics, 0);
child = fetch(fixture.conn, "SELECT analysis_run_id, status FROM analysis_runs " + ...
    "WHERE run_type = 'cross_extractor_agreement'");
verifyEqual(testCase, height(child), 1);
verifyEqual(testCase, string(child.status(1)), "completed");
verifyEqual(testCase, countOf(fixture.conn, "consilience_assessments"), 6);

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
end

function testFailureLeavesNoHalfWrittenAgreementAnalysis(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% A failure while writing assessments must not leave a completed agreement
% analysis carrying only some statuses.
execute(fixture.conn, "CREATE TRIGGER trg_fail_assessment " + ...
    "BEFORE INSERT ON consilience_assessments FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced assessment failure'); END");
threw = false;
try
    summarize(fixture, "match-nominal", true);
catch
    threw = true;
end
execute(fixture.conn, "DROP TRIGGER IF EXISTS trg_fail_assessment");
verifyTrue(testCase, threw);

% The statistics were written before the assessments in the same transaction, so
% rolling back must remove them too. A partially populated analysis claiming
% completion is exactly what this guards against.
verifyEqual(testCase, countOf(fixture.conn, "consilience_assessments"), 0);
verifyEqual(testCase, countOf(fixture.conn, "agreement_statistics"), 0);
verifyEqual(testCase, countWhere(fixture.conn, "analysis_runs", ...
    "run_type = 'cross_extractor_agreement'"), 0);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

% The matching analysis it summarizes is untouched by the failed apply.
verifyEqual(testCase, countWhere(fixture.conn, "analysis_runs", ...
    "run_type = 'cross_extractor_matching' AND status = 'completed'"), 1);
verifyEqual(testCase, countOf(fixture.conn, "match_groups"), 6);

% The connection is usable and the whole apply succeeds afterwards.
recovered = summarize(fixture, "match-nominal", true);
verifyTrue(testCase, recovered.committed);
verifyEqual(testCase, countOf(fixture.conn, "consilience_assessments"), 6);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);
end

function testRerunReusesAndChangedStatusConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = summarize(fixture, "match-nominal", true);
before = countOf(fixture.conn, "consilience_assessments");

second = summarize(fixture, "match-nominal", true);
verifyEqual(testCase, second.status, "reused");
verifyEqual(testCase, second.applied_counts.consilience_assessments, 0);
verifyEqual(testCase, second.applied_counts.reused_consilience_assessments, before);
verifyEqual(testCase, countOf(fixture.conn, "consilience_assessments"), before);
verifyEqual(testCase, second.agreement_analysis.analysis_run_id, ...
    first.agreement_analysis.analysis_run_id);

% A stored status is never repaired in place.
execute(fixture.conn, "UPDATE consilience_assessments " + ...
    "SET status = 'temporally_matched' WHERE status = 'single_extractor'");
verifyError(testCase, @() summarize(fixture, "match-nominal", true), ...
    "vawlume:consilience:AgreementConflict");
stillWrong = countWhere(fixture.conn, "consilience_assessments", ...
    "status = 'temporally_matched'");
verifyEqual(testCase, stillWrong, 3);
verifyEqual(testCase, countOf(fixture.conn, "consilience_assessments"), before);
end

% ------------------------------------------------------------------ sensitivity ---

function testThresholdConfigurationsChangeOutcomesWithoutMutatingEachOther(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyMatching(fixture, "match-strict", specVariant(fixture, "strict", 0.50));
applyMatching(fixture, "match-permissive", specVariant(fixture, "permissive", 0.05));

report = vawlume.consilience.sensitivity(fixture.conn, ...
    ["match-strict", "match-nominal", "match-permissive"], ...
    RepoRoot=fixture.repo_root);
comparison = report.comparison;
verifyEqual(testCase, height(comparison), 3);
verifyEqual(testCase, comparison.min_temporal_iou, [0.05; 0.10; 0.50], AbsTol=1e-12);

% Each configuration carries its own checksum-bearing specification identity.
verifyEqual(testCase, numel(unique(string(comparison.profile_key))), 3);
verifyEqual(testCase, numel(unique(string(comparison.checksum))), 3);
verifyFalse(testCase, any(strlength(string(comparison.checksum)) == 0));

permissive = configurationFor(comparison, "match-permissive");
illustrative = configurationFor(comparison, "match-nominal");
strict = configurationFor(comparison, "match-strict");

% Loosening the threshold admits a weak-overlap pair the default leaves apart.
verifyEqual(testCase, permissive.candidate_count, 5);
verifyEqual(testCase, illustrative.candidate_count, 4);
verifyEqual(testCase, permissive.one_to_one_groups, 3);
verifyEqual(testCase, illustrative.one_to_one_groups, 2);

% Tightening it dissolves the split component into unmatched detections.
verifyEqual(testCase, strict.candidate_count, 2);
verifyEqual(testCase, strict.one_to_many_groups, 0);
verifyEqual(testCase, illustrative.one_to_many_groups, 1);
verifyGreaterThan(testCase, strict.unmatched_groups, illustrative.unmatched_groups);

% Each analysis keeps its own rows. Adding configurations mutates none of them.
verifyEqual(testCase, illustrative.one_to_one_groups, 2);
verifyEqual(testCase, illustrative.feature_supported_groups, 1);
verifyEqual(testCase, illustrative.feature_discrepant_groups, 1);
runs = fetch(fixture.conn, "SELECT run_key, COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "GROUP BY run_key ORDER BY run_key");
verifyEqual(testCase, height(runs), 3);
verifyEqual(testCase, countWhere(fixture.conn, "analysis_runs", ...
    "run_type = 'cross_extractor_matching'"), 3);

% Manual precision and recall are computed against the reference, not against
% the other extractor, so the extractor-to-extractor threshold does not move
% them. That independence is the point of separating the two rules.
verifyEqual(testCase, unique(comparison.run_a_precision), 0.75, AbsTol=1e-12);
verifyEqual(testCase, unique(comparison.run_a_recall), 0.75, AbsTol=1e-12);
end

function testSensitivityRefusesNonComparableInputsAndNamesNoWinner(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyMatching(fixture, "match-strict", specVariant(fixture, "strict", 0.50));

report = vawlume.consilience.sensitivity(fixture.conn, ...
    ["match-nominal", "match-strict"], RepoRoot=fixture.repo_root);
verifyEqual(testCase, report.varied_parameter, ...
    "candidate_generation.plausibility_rule.min_temporal_iou");
verifyTrue(testCase, any(contains(report.held_constant, "input extraction runs")));

% No output names a best, optimal, calibrated, or validated configuration.
verifyTrue(testCase, any(contains(report.caution, "uncalibrated threshold")));
verifyTrue(testCase, any(contains(report.caution, "fitting a threshold to a fixture")));
verifyFalse(testCase, ismember("recommended", string(report.comparison.Properties.VariableNames)));
verifyFalse(testCase, ismember("optimal", string(report.comparison.Properties.VariableNames)));
source = string(fileread(fullfile(fixture.repo_root, "src", "+vawlume", ...
    "+consilience", "sensitivity.m")));
verifyFalse(testCase, contains(source, "[~, best]"));
verifyFalse(testCase, contains(source, "max(f1"));

% One configuration is not a comparison.
verifyError(testCase, @() vawlume.consilience.sensitivity(fixture.conn, ...
    "match-nominal", RepoRoot=fixture.repo_root), ...
    "vawlume:consilience:SensitivityNeedsConfigurations");

% Comparing analyses over different inputs would produce a table whose rows are
% not attributable to the threshold, so it is refused.
secondRun = fetch(fixture.conn, "SELECT extraction_run_id FROM extraction_runs " + ...
    "WHERE run_key = 'ds-second'");
verifyEqual(testCase, height(secondRun), 1);
strictAnalysis = fetch(fixture.conn, "SELECT analysis_run_id FROM analysis_runs " + ...
    "WHERE run_key = 'match-strict'");
verifyEqual(testCase, height(strictAnalysis), 1);
execute(fixture.conn, "UPDATE analysis_run_extraction_inputs SET extraction_run_id = " + ...
    string(double(secondRun.extraction_run_id(1))) + " WHERE input_role = 'run_a' " + ...
    "AND analysis_run_id = " + string(double(strictAnalysis.analysis_run_id(1))));
verifyError(testCase, @() vawlume.consilience.sensitivity(fixture.conn, ...
    ["match-nominal", "match-strict"], RepoRoot=fixture.repo_root), ...
    "vawlume:consilience:SensitivityInputsDiffer");
end

% -------------------------------------------------------------- immutability ---

function testConsilienceWritesNothingUpstreamAndNoScore(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = upstreamFingerprint(fixture.conn);
referenceBefore = countOf(fixture.conn, "manual_reference_events");
reviewsBefore = countOf(fixture.conn, "manual_reviews");

summarizeNominal(fixture);
verifyEqual(testCase, upstreamFingerprint(fixture.conn), before);

summarize(fixture, "match-nominal", true);
verifyEqual(testCase, upstreamFingerprint(fixture.conn), before);
verifyEqual(testCase, countOf(fixture.conn, "manual_reference_events"), referenceBefore);
verifyEqual(testCase, countOf(fixture.conn, "manual_reviews"), reviewsBefore);
verifyEqual(testCase, countOf(fixture.conn, "match_groups"), 6);
verifyEqual(testCase, countOf(fixture.conn, "candidate_pairs"), 4);

% Consilience authors no manual evidence of its own. Reference events and
% reviews are reviewer input; writing them here would make the reference
% dependent on the thing it is meant to evaluate.
source = "";
files = dir(fullfile(fixture.repo_root, "src", "+vawlume", "+consilience", ...
    "**", "*.m"));
for index = 1:numel(files)
    source = source + string(fileread(fullfile(files(index).folder, ...
        files(index).name)));
end
for table = ["manual_reference_events", "manual_reviews", "detections", ...
        "event_measurements", "curation_events", "match_groups", ...
        "candidate_pairs", "consensus_events", "extraction_runs"]
    verifyFalse(testCase, contains(source, "INSERT INTO " + table), table);
    verifyFalse(testCase, contains(source, "UPDATE " + table), table);
    verifyFalse(testCase, contains(source, "DELETE FROM " + table), table);
end
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

function row = statusOf(assessments, status)
selected = assessments.automated_status == status;
assert(nnz(selected) == 1, "Expected one %s assessment, found %d.", ...
    status, nnz(selected));
row = table2struct(assessments(selected, :));
end

function value = statusCount(counts, status)
selected = string(counts.status) == status;
assert(any(selected), "No status-count row for %s.", status);
value = counts.group_count(find(selected, 1));
end

function row = contingencyFor(contingency, status)
selected = string(contingency.automated_status) == status;
assert(nnz(selected) == 1, "Expected one contingency row for %s.", status);
row = table2struct(contingency(selected, :));
end

function row = configurationFor(comparison, runKey)
selected = string(comparison.run_key) == runKey;
assert(nnz(selected) == 1, "Expected one configuration row for %s.", runKey);
row = table2struct(comparison(selected, :));
end

function value = firstMemberDetection(conn, groupId, role)
rows = fetch(conn, "SELECT detection_id FROM match_group_members " + ...
    "WHERE match_group_id = " + string(groupId) + " AND member_role = '" + ...
    role + "' ORDER BY detection_id");
value = double(rows.detection_id(1));
end

function path = specVariant(fixture, name, iou)
old = string(sprintf('"min_temporal_iou": 0.10\n    }'));
new = string(sprintf('"min_temporal_iou": %g\n    }', iou));
path = writeSpecVariant(fixture, name + ".json", {old, ...
    '"vawlume.matching.prototype.v1"'}, {new, ...
    '"vawlume.matching.prototype.' + name + '"'});
end

function path = writeSpecVariant(fixture, name, oldValues, newValues)
% Line endings are normalized to LF before matching. The tracked JSON is stored
% with LF but `.gitattributes` sets `* text=auto`, so a Windows checkout gives it
% CRLF, and a search pattern spanning a line break would then match nothing.
text = string(fileread(fullfile(fixture.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json")));
text = replace(text, sprintf("\r\n"), newline);
for index = 1:numel(oldValues)
    assert(count(text, string(oldValues{index})) == 1, ...
        "Expected exactly one occurrence of the replaced specification text.");
    text = replace(text, string(oldValues{index}), string(newValues{index}));
end
path = fullfile(fixture.scratch, name);
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function applyMatching(fixture, runKey, profilePath)
% Asserted rather than assumed: compare returns a conflict result instead of
% throwing, so an unapplied configuration would otherwise show up much later as
% a missing analysis.
result = vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a="ds-imported", run_b="mupet-imported"), ...
    struct(run_key=runKey, profile_path=profilePath), ...
    RepoRoot=fixture.repo_root, Apply=true);
assert(result.committed, "Matching '%s' did not commit: %s %s", runKey, ...
    result.status, strjoin(result.conflicts, "; "));
end

function ref = recordingRef()
ref = struct(project_key="consilience-project", ...
    source_relative_path="audio/REC_A.wav");
end

function value = upstreamFingerprint(conn)
value = fetch(conn, "SELECT d.detection_id, d.start_time_s, d.end_time_s, " + ...
    "COUNT(em.event_measurement_id) AS measurements, " + ...
    "IFNULL(SUM(em.canonical_value_real), 0) AS canonical_total " + ...
    "FROM detections d LEFT JOIN event_measurements em " + ...
    "ON em.detection_id = d.detection_id GROUP BY d.detection_id " + ...
    "ORDER BY d.detection_id");
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function value = countWhere(conn, tableName, predicate)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName + " WHERE " + predicate);
value = double(rows.n(1));
end

function verifySubstring(testCase, actual, expected)
verifyTrue(testCase, contains(string(actual), expected), ...
    "Expected '" + expected + "' inside '" + string(actual) + "'.");
end

% ---------------------------------------------------------------- fixture ---

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE Two real imports, one matching analysis, and independent review.
%
% The geometry gives one feature-supported 1:1 component, one feature-discrepant
% 1:1 component, one split component, and unmatched detections on both sides,
% plus a weak-overlap pair that only a permissive threshold admits.
%
% The manual reference is authored here as reviewer input. It deliberately
% disagrees with DeepSqueak's accept flag in both directions and contains one
% event neither extractor found.
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
conn = sqlite(char(fullfile(scratch, "consilience.sqlite")), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('consilience-project','Consilience Project')");
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

ref = recordingRef();
vawlume.ingest.deepsqueak(conn, dsPath, ref, ...
    struct(run_key="ds-imported", extractor_version="3.2.1"), ...
    RepoRoot=repoRoot, ArtifactRoot=dsRoot, Apply=true);
vawlume.ingest.mupet(conn, mupetPath, ref, ...
    struct(run_key="mupet-imported", extractor_version="2.1", ...
        settings=struct(config_path=configPath)), ...
    RepoRoot=repoRoot, ArtifactRoot=mupetRoot, Apply=true);

% A second DeepSqueak run, used only to prove sensitivity refuses to compare
% analyses over different inputs. It gets its own export filename: writecell
% stamps a creation time into the workbook, so two byte-different files under one
% portable path would be an artifact-checksum conflict, which is the identity
% contract working rather than something to work around.
secondRoot = fullfile(scratch, "deepsqueak_second");
secondPath = fullfile(secondRoot, "exports", "REC_A_Stats_session2.xlsx");
writeCells(secondPath, deepSqueakCells());
secondResult = vawlume.ingest.deepsqueak(conn, secondPath, ref, ...
    struct(run_key="ds-second", extractor_version="3.2.1"), ...
    RepoRoot=repoRoot, ArtifactRoot=secondRoot, Apply=true);
assert(secondResult.committed, "Second DeepSqueak run did not commit: %s", ...
    strjoin(secondResult.conflicts, "; "));

insertReferenceEvents(conn);
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);
vawlume.matching.compare(conn, ref, ...
    struct(run_a="ds-imported", run_b="mupet-imported"), ...
    struct(run_key="match-nominal"), RepoRoot=repoRoot, Apply=true);
insertAdjudications(conn);
end

function insertReferenceEvents(conn)
% r1 and r2 support the two one-to-one components; r3 covers the split region;
% r4 is an event neither extractor found.
events = { ...
    "r1", 10.002, 10.051; ...
    "r2", 20.001, 20.041; ...
    "r3", 40.001, 40.099; ...
    "r4", 60.000, 60.050};
for index = 1:size(events, 1)
    execute(conn, "INSERT INTO manual_reference_events(recording_id," + ...
        "reference_set_key,native_reference_id,reviewer_label," + ...
        "start_time_s,end_time_s) VALUES(1,'prototype_manual_reference_v1','" + ...
        events{index, 1} + "','reviewer_1'," + string(events{index, 2}) + ...
        "," + string(events{index, 3}) + ")");
end
end

function insertAdjudications(conn)
% Independent adjudication on two groups. Both must leave the automated status
% intact; only the reported effective status changes.
supported = fetch(conn, "SELECT mg.match_group_id FROM match_groups mg " + ...
    "JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id " + ...
    "JOIN detections d ON d.detection_id = mgm.detection_id " + ...
    "WHERE mg.match_type = 'one_to_one' AND d.native_event_id = '1' " + ...
    "AND mgm.member_role = 'run_a'");
unmatchedDeepSqueak = fetch(conn, "SELECT mg.match_group_id FROM match_groups mg " + ...
    "JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id " + ...
    "WHERE mg.match_type = 'unmatched' AND mgm.member_role = 'run_a'");
analysisRun = fetch(conn, "SELECT analysis_run_id FROM analysis_runs " + ...
    "WHERE run_key = 'match-nominal'");
runId = double(analysisRun.analysis_run_id(1));
execute(conn, "INSERT INTO manual_reviews(analysis_run_id,match_group_id," + ...
    "reviewer_label,review_status) VALUES(" + string(runId) + "," + ...
    string(double(supported.match_group_id(1))) + ...
    ",'reviewer_1','adjudicated_positive')");
execute(conn, "INSERT INTO manual_reviews(analysis_run_id,match_group_id," + ...
    "reviewer_label,review_status) VALUES(" + string(runId) + "," + ...
    string(double(unmatchedDeepSqueak.match_group_id(1))) + ...
    ",'reviewer_1','adjudicated_negative')");
end

function cells = deepSqueakCells()
% Call 1 pairs cleanly with syllable 1. Call 2 pairs with syllable 2 but their
% derived bandwidths disagree while the extrema agree. Call 3 overlaps syllable 3
% only weakly, so only a permissive threshold links them; DeepSqueak accepted it
% and the reviewer did not. Call 4 spans syllables 4 and 5; DeepSqueak rejected
% it and the reviewer did mark it.
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
    {detectionFile, 3, 'class_b', 1, 0.7010, 30.000, 30.040, 0.040, ...
        59.0, 48.0, 70.0, 22.0, 2.6, 4.0, 1.09, -70.8, 0.74, 59.5}
    {detectionFile, 4, 'class_b', 0, 0.2107, 40.000, 40.100, 0.100, ...
        63.5, 42.0, 84.0, 42.0, 4.4, -8.25, 1.40, -69.3, 0.69, 64.2}
];
end

function cells = mupetCells()
headers = {'Syllable number', 'Syllable start time (sec)', ...
    'Syllable end time (sec)', 'inter-syllable interval (sec)', ...
    'syllable duration (msec)', 'starting frequency (kHz)', ...
    'final frequency (kHz)', 'minimum frequency (kHz)', ...
    'maximum frequency (kHz)', 'mean frequency (kHz)', ...
    'frequency bandwidth (kHz)', 'total syllable energy (dB)', ...
    'peak syllable amplitude (dB)'};
cells = [
    headers
    {1, 10.004, 10.052, 9.950, 48.0, 45.0, 62.0, 46.0, 79.0, 63.0, 33.0, 12.5, -18}
    {2, 20.002, 20.042, 9.991, 40.0, 46.0, 59.0, 47.0, 77.0, 61.5, 30.0, 11.5, -19}
    {3, 30.033, 30.095, 9.907, 62.0, 47.0, 61.0, 45.0, 75.0, 60.0, 30.0, 10.5, -20}
    {4, 40.002, 40.045, 0.007, 43.0, 47.0, 61.0, 42.5, 84.5, 63.0, 42.0, 10.5, -20}
    {5, 40.052, 40.098, 9.902, 46.0, 48.0, 62.0, 43.0, 83.0, 62.5, 40.0, 9.5, -21}
    {6, 50.000, 50.035, 'NA', 35.0, 46.0, 60.0, 50.5, 72.5, 61.0, 22.0, 11.0, -19}
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
