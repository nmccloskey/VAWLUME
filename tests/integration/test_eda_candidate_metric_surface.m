function tests = test_eda_candidate_metric_surface
%TEST_EDA_CANDIDATE_METRIC_SURFACE The candidate-metric surface and its coverage.
%
% The surface assembles what the matcher stored and what the consilience layer
% computes. It defines no metric. These tests therefore concentrate on the three
% things assembly can get wrong: reading a value the matcher did not store,
% pooling two sign conventions into one distribution, and collapsing distinct
% reasons for a missing observation into one "missing" count.
%
% The fixture is the tracked three-extractor Phase 1 database, so band-edge
% classes really are unregistered for USVSEG and split groups really do occur.
tests = functiontests(localfunctions);
end

% -------------------------------------------------------------- assembly ---

function testProjectWideSurfaceSpansEveryUsableMatchingAnalysis(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);

verifyEqual(testCase, surface.status, "assembled");
verifyEqual(testCase, surface.analysis_count, 3);
verifyEqual(testCase, sort(surface.analyses.matching_run_key), ...
    ["pair_ds_mupet"; "pair_ds_usvseg"; "pair_mupet_usvseg"]);
verifyEqual(testCase, sort(unique(surface.metrics.extractor_pair_key)), ...
    ["deepsqueak|mupet"; "deepsqueak|usvseg"; "mupet|usvseg"]);
verifyEqual(testCase, height(surface.metrics), ...
    sum(surface.analyses.candidate_count));
verifyEqual(testCase, surface.candidate_count, height(surface.metrics));
verifyEqual(testCase, unique(surface.analyses.recording_id), 1);

clear cleanup
end

function testAnalysisWithoutResolvableDirectionIsExcludedAndReported(testCase)
% The tracked fixture carries a seeded cross_extractor_matching analysis whose
% input roles are deepsqueak_input / mupet_input and which links no matching
% specification. Its direction is not recoverable, so it must never be pooled
% under an assumed one - but one legacy row must not abort a whole-dataset
% diagnostic either. A project-wide sweep excludes it and says so.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);

excluded = surface.excluded_analyses;
verifyEqual(testCase, height(excluded), 1);
verifyEqual(testCase, excluded.matching_run_key(1), ...
    "fixture_cross_extractor_matching_v1");
verifyEqual(testCase, excluded.reason(1), "inputs_not_run_a_run_b");
verifyFalse(testCase, ismember("fixture_cross_extractor_matching_v1", ...
    surface.analyses.matching_run_key));

% Naming that same analysis explicitly raises instead: the caller asked for it.
verifyError(testCase, @() vawlume.eda.candidateMetrics(fixture.conn, ...
    "fixture_cross_extractor_matching_v1", RepoRoot=fixture.repo_root), ...
    "vawlume:eda:AnalysisUnusable");

clear cleanup
end

function testIncompleteOrNonMatchingAnalysesAreRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyError(testCase, @() vawlume.eda.candidateMetrics(fixture.conn, ...
    "fixture_behavior_audio_alignment_v1", RepoRoot=fixture.repo_root), ...
    "vawlume:eda:AnalysisNotMatching");
verifyError(testCase, @() vawlume.eda.candidateMetrics(fixture.conn, ...
    "no-such-analysis", RepoRoot=fixture.repo_root), ...
    "vawlume:eda:AnalysisNotFound");

clear cleanup
end

% --------------------------------------------- stored, never recomputed ---

function testTemporalMetricsFollowTheStoredRowNotTheDetectionBoundaries(testCase)
% Perturb one stored candidate row so it disagrees with the detection geometry
% it was derived from. A surface that reads storage reports the perturbed value;
% a surface that recomputes reports the original and has quietly introduced a
% second definition of the metric.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
target = fetch(fixture.conn, "SELECT cp.candidate_pair_id, cp.temporal_iou " + ...
    "FROM candidate_pairs cp JOIN analysis_runs ar " + ...
    "ON ar.analysis_run_id=cp.analysis_run_id " + ...
    "WHERE ar.run_key='pair_ds_mupet' ORDER BY cp.candidate_pair_id LIMIT 1");
pairId = double(target.candidate_pair_id(1));
original = double(target.temporal_iou(1));
perturbed = 0.123456;
verifyNotEqual(testCase, original, perturbed);
% %.17g, not string(): MATLAB's default numeric-to-string conversion keeps five
% significant digits, which would store 0.12346 and make this test compare the
% surface against a number the database never held.
execute(fixture.conn, "UPDATE candidate_pairs SET temporal_iou=" + ...
    string(sprintf("%.17g", perturbed)) + ", onset_difference_s=0.0777 " + ...
    "WHERE candidate_pair_id=" + string(pairId));

surface = surfaceOf(fixture);
row = surface.metrics(surface.metrics.candidate_pair_id == pairId, :);
verifyEqual(testCase, height(row), 1);
verifyEqual(testCase, row.temporal_iou, perturbed, AbsTol=1e-12);
verifyEqual(testCase, row.onset_difference_s, 0.0777, AbsTol=1e-12);
verifyEqual(testCase, row.abs_onset_difference_s, 0.0777, AbsTol=1e-12);

clear cleanup
end

function testAbsoluteVariantsAreTheMagnitudesOfTheSignedColumns(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);
metrics = surface.metrics;

for name = ["onset_difference_s", "offset_difference_s", "duration_difference_s"]
    verifyEqual(testCase, metrics.("abs_" + name), abs(metrics.(name)), ...
        name, AbsTol=1e-12);
end
verifyTrue(testCase, any(metrics.onset_difference_s < 0));
verifyTrue(testCase, all(metrics.abs_onset_difference_s >= 0));
verifyEqual(testCase, sort(surface.signed_metric_names), ...
    sort(["onset_difference_s", "offset_difference_s", "duration_difference_s"]));

clear cleanup
end

% ------------------------------------------------------ sign convention ---

function testReversedRunOrderYieldsTheSameNormalizedSignedEvidence(testCase)
% The same extractor pair analysed in both caller orders stores opposite signs.
% Normalized to ascending extractor_key, the two analyses must agree exactly.
% Without this normalization a pooled signed distribution would be bimodal for a
% reason that is not biological.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyPair(fixture, "forward_ds_mupet", dsRun(), mupetRun());
applyPair(fixture, "reverse_mupet_ds", mupetRun(), dsRun());

forward = vawlume.eda.candidateMetrics(fixture.conn, "forward_ds_mupet", ...
    RepoRoot=fixture.repo_root, IncludeFeatureDiscrepancies=false);
reverse = vawlume.eda.candidateMetrics(fixture.conn, "reverse_mupet_ds", ...
    RepoRoot=fixture.repo_root, IncludeFeatureDiscrepancies=false);

verifyEqual(testCase, forward.analyses.sign_normalization, "as_stored");
verifyEqual(testCase, reverse.analyses.sign_normalization, "negated");
verifyEqual(testCase, forward.analyses.extractor_pair_key, ...
    reverse.analyses.extractor_pair_key);

forwardRows = sortrows(forward.metrics, ["detection_a_id", "detection_b_id"]);
reverseRows = sortrows(reverse.metrics, ["detection_a_id", "detection_b_id"]);
verifyEqual(testCase, height(forwardRows), height(reverseRows));
for name = ["onset_difference_s", "offset_difference_s", "duration_difference_s"]
    verifyEqual(testCase, reverseRows.(name), forwardRows.(name), ...
        name, AbsTol=1e-12);
end
verifyEqual(testCase, reverseRows.lower_extractor_detection_id, ...
    forwardRows.lower_extractor_detection_id);

% The raw stored evidence really did differ in sign, so the agreement above is
% the normalization working rather than the two analyses being identical.
stored = storedOnsetDifferences(fixture, ["forward_ds_mupet", "reverse_mupet_ds"]);
verifyEqual(testCase, stored.reverse_mupet_ds, -stored.forward_ds_mupet, ...
    AbsTol=1e-12);

clear cleanup
end

function testLowerAndHigherExtractorDetectionIdsAreNotTheSchemaOrdering(testCase)
% detection_a_id is ascending detection id; extractor_key_a is ascending
% extractor key. They are different orderings, and the surface states the
% mapping rather than leaving a caller to assume they align.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);
metrics = surface.metrics;

verifyTrue(testCase, all(metrics.detection_a_id < metrics.detection_b_id));
paired = sort([metrics.lower_extractor_detection_id, ...
    metrics.higher_extractor_detection_id], 2);
verifyEqual(testCase, paired, [metrics.detection_a_id, metrics.detection_b_id]);
verifyTrue(testCase, all(metrics.extractor_key_a < metrics.extractor_key_b));

runs = fetch(fixture.conn, "SELECT detection_id, extraction_run_id " + ...
    "FROM detections");
runOf = containers.Map(double(runs.detection_id), ...
    double(runs.extraction_run_id));
for index = 1:height(metrics)
    analysis = surface.analyses(surface.analyses.analysis_run_id == ...
        metrics.analysis_run_id(index), :);
    verifyEqual(testCase, ...
        runOf(metrics.lower_extractor_detection_id(index)), ...
        analysis.lower_extraction_run_id);
end

clear cleanup
end

% -------------------------------------------------- coverage accounting ---

function testCoverageCategoriesPartitionEveryMetric(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);
coverage = surface.coverage;

verifyEqual(testCase, unique(coverage.total), height(surface.metrics));
totals = coverage.supported + coverage.not_eligible + coverage.not_measured + ...
    coverage.not_comparable_topology + coverage.non_finite;
verifyEqual(testCase, totals, coverage.total);
verifyEqual(testCase, sort(surface.coverage_categories), ...
    sort(["supported", "not_eligible", "not_measured", ...
    "not_comparable_topology", "non_finite"]));

clear cleanup
end

function testNotEligibleFiresWhereTheRegistryHasNoComparableFeaturePair(testCase)
% Band edges are registered for DeepSqueak and MUPET and not for USVSEG, so
% every candidate row of a USVSEG pair reports not_eligible for those classes.
% This is the availability confounding the conceptual specification warns about,
% visible as a coverage fact rather than as a silent gap.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);

bandEdge = "discrepancy_vocalization_frequency_min";
verifyTrue(testCase, ismember(bandEdge, surface.feature_metric_names));
row = surface.coverage(surface.coverage.metric_name == bandEdge, :);
usvsegRows = nnz(contains(surface.metrics.extractor_pair_key, "usvseg"));
verifyGreaterThan(testCase, usvsegRows, 0);
verifyEqual(testCase, row.not_eligible, usvsegRows);

% Duration and centre frequency are registered for all three, so neither is
% ever not_eligible.
for name = ["discrepancy_vocalization_duration", ...
        "discrepancy_vocalization_frequency_center"]
    shared = surface.coverage(surface.coverage.metric_name == name, :);
    verifyEqual(testCase, shared.not_eligible, 0, name);
end

clear cleanup
end

function testNotComparableTopologyFiresOnGroupsTheSpecificationExcludes(testCase)
% The matching specification restricts feature comparison to one_to_one groups.
% A candidate row in a split, merge or many-to-many group therefore has no
% comparison at all, which is a different fact from an unregistered pair and a
% different fact from an unexported measurement.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);

shared = surface.coverage(surface.coverage.metric_name == ...
    "discrepancy_vocalization_duration", :);
verifyGreaterThan(testCase, shared.not_comparable_topology, 0);

ambiguous = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=cp.analysis_run_id " + ...
    "JOIN match_group_members ma ON ma.detection_id=cp.detection_a_id " + ...
    "JOIN match_groups mg ON mg.match_group_id=ma.match_group_id " + ...
    "AND mg.analysis_run_id=cp.analysis_run_id " + ...
    "WHERE ar.run_key LIKE 'pair_%' AND mg.match_type<>'one_to_one'");
verifyEqual(testCase, shared.not_comparable_topology, double(ambiguous.n(1)));

clear cleanup
end

function testNonFiniteFiresOnAStoredRowWhoseMetricIsNull(testCase)
% vawlume.interval.relation returns NaN temporal_iou for two coincident
% zero-duration intervals, and the matcher refuses such geometry upstream, so
% the reachable form of this case is a stored row whose metric column is NULL.
% The surface must report the row as present with the value absent.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
target = fetch(fixture.conn, "SELECT cp.candidate_pair_id FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=cp.analysis_run_id " + ...
    "WHERE ar.run_key='pair_ds_mupet' ORDER BY cp.candidate_pair_id LIMIT 1");
pairId = double(target.candidate_pair_id(1));
execute(fixture.conn, "UPDATE candidate_pairs SET temporal_iou=NULL " + ...
    "WHERE candidate_pair_id=" + string(pairId));

% Temporal metrics only. vawlume.consilience.summarize cannot read a candidate
% row whose temporal metric is NULL - consilienceDetectionAgreement selects
% cp.temporal_iou without IFNULL and MATLAB raises while building the result
% set - so requesting feature discrepancies here would fail inside that package
% rather than testing this one. Recorded as an issue for the part that owns it.
surface = vawlume.eda.candidateMetrics(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"), ...
    RepoRoot=fixture.repo_root, IncludeFeatureDiscrepancies=false);
row = surface.metrics(surface.metrics.candidate_pair_id == pairId, :);
verifyEqual(testCase, height(row), 1);
verifyTrue(testCase, isnan(row.temporal_iou));
coverage = surface.coverage(surface.coverage.metric_name == "temporal_iou", :);
verifyEqual(testCase, coverage.non_finite, 1);
verifyEqual(testCase, coverage.supported, height(surface.metrics) - 1);
verifyEqual(testCase, coverage.total, height(surface.metrics));

% The neighbouring metrics of that same row stay supported: one absent value
% does not remove the row.
overlap = surface.coverage(surface.coverage.metric_name == ...
    "temporal_overlap_s", :);
verifyEqual(testCase, overlap.supported, height(surface.metrics));

clear cleanup
end

function testNotMeasuredFiresWhenOneExtractorExportedNoValue(testCase)
% An eligible feature pair whose measurement one side never exported is absent
% evidence, not disagreement. Deleting one measurement leaves the comparison
% eligible and uncomputed.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
before = surfaceOf(fixture);
metric = "discrepancy_vocalization_frequency_center";
baseline = before.coverage(before.coverage.metric_name == metric, :);
verifyGreaterThan(testCase, baseline.supported, 0);

victim = oneSupportedMeasurement(fixture, before, metric);
execute(fixture.conn, "DELETE FROM event_measurements WHERE detection_id=" + ...
    string(victim.detection_id) + " AND extractor_feature_id=" + ...
    string(victim.feature_id));

after = surfaceOf(fixture);
row = after.coverage(after.coverage.metric_name == metric, :);

% One detection participates in two pairwise analyses, so removing its
% measurement moves every candidate row that pair appears in. The invariant is
% the exchange: supported cells become not_measured, none are lost, and
% eligibility is untouched because the registry did not change.
verifyEqual(testCase, baseline.not_measured, 0);
verifyGreaterThan(testCase, row.not_measured, 0);
verifyEqual(testCase, row.supported + row.not_measured, ...
    baseline.supported + baseline.not_measured);
verifyEqual(testCase, row.not_eligible, baseline.not_eligible);
verifyEqual(testCase, row.not_comparable_topology, ...
    baseline.not_comparable_topology);
verifyEqual(testCase, row.total, baseline.total);

% The moved rows are exactly those whose pair includes the stripped detection.
affected = nnz(after.metrics.detection_a_id == victim.detection_id | ...
    after.metrics.detection_b_id == victim.detection_id);
verifyLessThanOrEqual(testCase, row.not_measured, affected);

clear cleanup
end

% ------------------------------------------------------- gate provenance ---

function testTheActiveGateRecordTravelsWithTheRows(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);

verifyEqual(testCase, height(surface.gates), 3);
verifyEqual(testCase, unique(surface.gates.eligibility_rule), ...
    "positive_overlap_and_min_temporal_iou");
verifyEqual(testCase, unique(surface.gates.min_temporal_iou), 0.10, ...
    AbsTol=1e-12);
for name = ["max_abs_onset_difference_s", "max_abs_offset_difference_s", ...
        "max_abs_duration_difference_s"]
    verifyTrue(testCase, all(isnan(surface.gates.(name))), name);
end
verifyEqual(testCase, unique(surface.metrics.eligibility_rule), ...
    "positive_overlap_and_min_temporal_iou");
verifyEqual(testCase, sum(surface.gates.candidate_rows), ...
    height(surface.metrics));

clear cleanup
end

function testADeclaredBoundIsCarriedFromTheStoredGateRecord(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
path = boundedSpecPath(fixture, 0.0600);
vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a=dsRun(), run_b=mupetRun()), ...
    struct(run_key="bounded_ds_mupet", profile_path=path), ...
    RepoRoot=fixture.repo_root, Apply=true);

surface = vawlume.eda.candidateMetrics(fixture.conn, "bounded_ds_mupet", ...
    RepoRoot=fixture.repo_root, IncludeFeatureDiscrepancies=false);
verifyEqual(testCase, surface.gates.eligibility_rule, ...
    "positive_overlap_and_min_temporal_iou_and_max_abs_onset_difference_s");
verifyEqual(testCase, surface.gates.max_abs_onset_difference_s, 0.0600, ...
    AbsTol=1e-12);
verifyTrue(testCase, isnan(surface.gates.max_abs_offset_difference_s));

clear cleanup
end

function testInconsistentDirectionEvidenceIsRefusedRatherThanPooled(testCase)
% The two records of run direction - input_role and details_json - must agree.
% If they disagree, every signed metric on the analysis is suspect and the
% surface refuses rather than choosing one.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
target = fetch(fixture.conn, "SELECT cp.candidate_pair_id, cp.details_json " + ...
    "FROM candidate_pairs cp JOIN analysis_runs ar " + ...
    "ON ar.analysis_run_id=cp.analysis_run_id " + ...
    "WHERE ar.run_key='pair_ds_mupet' ORDER BY cp.candidate_pair_id LIMIT 1");
record = jsondecode(string(target.details_json(1)));
record.run_a_extraction_run_id = record.run_a_extraction_run_id + 100;
execute(fixture.conn, "UPDATE candidate_pairs SET details_json='" + ...
    replace(string(jsonencode(record)), "'", "''") + "' " + ...
    "WHERE candidate_pair_id=" + string(double(target.candidate_pair_id(1))));

verifyError(testCase, @() vawlume.eda.candidateMetrics(fixture.conn, ...
    "pair_ds_mupet", RepoRoot=fixture.repo_root, ...
    IncludeFeatureDiscrepancies=false), "vawlume:eda:DirectionInconsistent");

clear cleanup
end

% ------------------------------------------------------------ read-only ---

function testTheSurfaceWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
before = databaseCounts(fixture.conn);
surfaceOf(fixture);
verifyEqual(testCase, databaseCounts(fixture.conn), before);

matchingRoot = fullfile(fixture.repo_root, "src", "+vawlume", "+eda");
files = dir(fullfile(matchingRoot, "**", "*.m"));
source = "";
for index = 1:numel(files)
    source = source + newline + ...
        string(fileread(fullfile(files(index).folder, files(index).name)));
end
for forbidden = ["INSERT INTO", "UPDATE ", "DELETE FROM", "DROP ", ...
        "CREATE VIEW", "CREATE TABLE", "sqlwrite", "AutoCommit"]
    verifyFalse(testCase, contains(source, forbidden), forbidden);
end

clear cleanup
end

% ------------------------------------------------- composition with Part 4 ---

function testDependencyDiagnosticsComposeWithTheSurface(testCase)
% The dependency layer is the surface's first real consumer. On real pilot data
% the feature-discrepancy columns are sparse enough to force the pairwise
% fallback, which is the behaviour the itinerary predicted and the reason the
% Metrics option exists.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);
surface = surfaceOf(fixture);

whole = vawlume.eda.metricDependencies(surface);
verifyEqual(testCase, whole.observation_policy.mode, "pairwise");
verifyEqual(testCase, whole.partial.status, "undefined");
verifyEqual(testCase, whole.partial.reason, "insufficient_observations");

% The limiting metrics are the band-edge feature columns, which is exactly the
% availability confounding the conceptual specification warns about, arriving
% here as a named cause rather than an unexplained failure. They are absent on
% the same rows as each other, so no one of them is uniquely to blame and only
% the absence count names them - which is why three counts are reported.
limiting = whole.observation_policy.limiting_metrics;
verifyGreaterThan(testCase, limiting.non_finite_rows(1), 0);
verifyTrue(testCase, startsWith(limiting.metric_name(1), "discrepancy_"));
verifyEqual(testCase, limiting.non_finite_rows( ...
    limiting.metric_name == "temporal_iou"), 0);

% Restricting to the four screened factors' metrics, whose coverage is complete,
% recovers a computable partial correlation.
screened = ["temporal_iou", "abs_onset_difference_s", ...
    "abs_offset_difference_s", "abs_duration_difference_s"];
restricted = vawlume.eda.metricDependencies(surface, Metrics=screened, ...
    ObservationMargin=0);
verifyEqual(testCase, restricted.observation_policy.mode, "listwise");
verifyEqual(testCase, restricted.observation_policy.complete_case_n, ...
    height(surface.metrics));
verifyEqual(testCase, restricted.metric_names, screened);
verifyEqual(testCase, height(restricted.pairs), 6);
verifyEqual(testCase, numel(restricted.caution), 4);

% Whatever the outcome, nothing was pruned and no factor was removed.
verifyTrue(testCase, any(contains(restricted.interpretation, ...
    "Nothing was pruned")));

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function surface = surfaceOf(fixture)
surface = vawlume.eda.candidateMetrics(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"), RepoRoot=fixture.repo_root);
end

function value = oneSupportedMeasurement(fixture, surface, metric)
%ONESUPPORTEDMEASUREMENT A detection and feature whose value backs one supported cell.
klass = surface.feature_metrics.equivalence_class( ...
    surface.feature_metrics.metric_name == metric);
rows = fetch(fixture.conn, "SELECT em.detection_id, em.extractor_feature_id " + ...
    "FROM event_measurements em JOIN extractor_features ef " + ...
    "ON ef.extractor_feature_id=em.extractor_feature_id " + ...
    "WHERE ef.equivalence_class='" + klass + "' " + ...
    "AND em.detection_id IN (" + strjoin(string(unique( ...
    surface.metrics.detection_a_id)'), ",") + ") " + ...
    "ORDER BY em.detection_id LIMIT 1");
value = struct(detection_id=double(rows.detection_id(1)), ...
    feature_id=double(rows.extractor_feature_id(1)));
end

function value = storedOnsetDifferences(fixture, runKeys)
value = struct();
for runKey = runKeys
    rows = fetch(fixture.conn, "SELECT cp.onset_difference_s " + ...
        "FROM candidate_pairs cp JOIN analysis_runs ar " + ...
        "ON ar.analysis_run_id=cp.analysis_run_id WHERE ar.run_key='" + ...
        runKey + "' ORDER BY cp.detection_a_id, cp.detection_b_id");
    value.(runKey) = double(rows.onset_difference_s);
end
end

function path = boundedSpecPath(fixture, bound)
text = string(fileread(fullfile(fixture.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json")));
anchor = """min_temporal_iou"": 0.10";
at = strfind(text, anchor);
ruleAt = strfind(text, """plausibility_rule""");
afterRuleAt = strfind(text, """excluded_evidence""");
assert(~isempty(at) && at(1) > ruleAt(1) && at(1) < afterRuleAt(1));
eol = newline;
if contains(text, string(char(13)) + newline)
    eol = string(char(13)) + newline;
end
addition = anchor + "," + eol + "      ""max_abs_onset_difference_s"": " + ...
    string(sprintf("%.17g", bound));
text = extractBefore(text, at(1)) + addition + ...
    extractAfter(text, at(1) + strlength(anchor) - 1);
path = fullfile(fixture.scratch, "bounded.json");
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function counts = databaseCounts(conn)
names = ["candidate_pairs", "match_groups", "match_group_members", ...
    "consensus_events", "analysis_runs", "analysis_run_profiles", ...
    "agreement_statistics", "consilience_assessments", "event_measurements", ...
    "detections", "config_profiles", "config_profile_versions"];
counts = struct();
for name = names
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + name);
    counts.(name) = double(rows.n(1));
end
end

function results = applyAllPairs(fixture)
results = struct();
results.ds_mupet = applyPair(fixture, "pair_ds_mupet", dsRun(), mupetRun());
results.ds_usvseg = applyPair(fixture, "pair_ds_usvseg", dsRun(), usvsegRun());
results.mupet_usvseg = applyPair(fixture, "pair_mupet_usvseg", mupetRun(), ...
    usvsegRun());
end

function result = applyPair(fixture, runKey, runA, runB)
result = vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a=runA, run_b=runB), struct(run_key=runKey), ...
    RepoRoot=fixture.repo_root, Apply=true);
end

function ref = recordingRef()
ref = struct(project_key="phase1_synthetic_fixture", ...
    source_relative_path="synthetic/recordings/session_social_dyad_01.wav");
end

function value = dsRun()
value = "fixture_deepsqueak_social_v1";
end

function value = mupetRun()
value = "fixture_mupet_social_v1";
end

function value = usvsegRun()
value = "fixture_usvseg_social_v1";
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "eda-surface.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
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
