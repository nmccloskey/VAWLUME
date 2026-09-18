function tests = test_eda_exploration_runner
%TEST_EDA_EXPLORATION_RUNNER Executing a screening design, and its provenance.
%
% This is the only part of the exploratory workflow that writes to the database,
% and it writes through two apply paths that many stored contracts depend on. The
% tests are correspondingly broad: they check not only that a probe runs, but
% that a rerun writes nothing, that a dry run writes nothing, that a conflict is
% surfaced rather than resolved, and that a partial probe reports itself as an
% unbalanced design.
%
% The last of those matters most. Effect estimation assumes every design row was
% evaluated on the same recordings, so a probe that quietly lost a unit would
% produce effect estimates that are not the quantity they claim to be.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------ dataset validation ---

function testTheDatasetIsResolvedWithItsPairsDerivedInAscendingKeyOrder(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));

verifyEqual(testCase, dataset.recording_count, 2);
verifyEqual(testCase, dataset.extractor_keys, ...
    ["deepsqueak", "mupet", "usvseg"]);
verifyEqual(testCase, dataset.pairs_per_recording, 3);
verifyEqual(testCase, height(dataset.pairs), 6);

% Every pair is ascending by extractor_key, which is the one ordering rule.
verifyTrue(testCase, all(dataset.pairs.run_a_extractor_key < ...
    dataset.pairs.run_b_extractor_key));
verifyEqual(testCase, unique(dataset.pairs.extractor_pair_key), ...
    ["deepsqueak|mupet"; "deepsqueak|usvseg"; "mupet|usvseg"]);
verifyTrue(testCase, contains(dataset.pair_ordering, "ascending extractor_key"));

clear cleanup
end

function testARecordingThatCannotFormAPairIsExcludedAndReported(testCase)
% The stock fixture's second recording carries one extraction run. Excluding it
% silently would misstate the probe's coverage.
[fixture, cleanup] = setUpFixture(Prepare=false); %#ok<ASGLU>
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));

verifyEqual(testCase, dataset.recording_count, 1);
verifyEqual(testCase, height(dataset.excluded_recordings), 1);
verifyEqual(testCase, dataset.excluded_recordings.recording_id, 2);
verifyEqual(testCase, dataset.excluded_recordings.reason, ...
    "fewer_than_2_extraction_runs");

clear cleanup
end

function testTwoRunsFromOneExtractorAreRejectedBeforeAnyWrite(testCase)
% The agreement composer needs one run per extractor so an unordered pair names
% exactly one comparison. Catching it here costs a query; catching it there
% costs a probe's worth of written matching analyses first.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = analysisCount(fixture.conn);
execute(fixture.conn, "INSERT INTO extraction_runs(extraction_run_id, " + ...
    "project_id, extractor_version_id, run_key, status) " + ...
    "VALUES(90,1,1,'second_deepsqueak_social','imported')");
execute(fixture.conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id,input_role) VALUES(90,1,'source_audio')");
insertDetection(fixture.conn, 90, 1, "dup-1", 10.0, 10.05);

verifyError(testCase, @() vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture")), ...
    "vawlume:eda:RepeatedExtractorInRecording");
verifyEqual(testCase, analysisCount(fixture.conn), before);

clear cleanup
end

function testARunFromAnotherProjectIsRejected(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "INSERT INTO projects(project_id,project_key," + ...
    "project_name) VALUES(2,'other-project','Other')");
execute(fixture.conn, "INSERT INTO extraction_runs(extraction_run_id," + ...
    "project_id,extractor_version_id,run_key,status) " + ...
    "VALUES(91,2,1,'foreign_run','imported')");

verifyError(testCase, @() vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture", ...
    extraction_run_keys=["fixture_deepsqueak_social_v1", "foreign_run"])), ...
    "vawlume:eda:ExtractionRunNotInProject");

clear cleanup
end

% ------------------------------------------------------ cost and the budget ---

function testCostIsReportedInAnalysesAndTheCeilingBindsOnThem(testCase)
% The ceiling is on analyses, not configurations: for three extractors each
% configuration costs four analyses per recording, so a configuration count
% understates the real cost fourfold.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));

cost = vawlume.eda.probeCost(dataset, 8);
verifyEqual(testCase, cost.matching_analyses, 8 * 2 * 3);
verifyEqual(testCase, cost.agreement_analyses, 8 * 2);
verifyEqual(testCase, cost.total_analyses, 64);
verifyEqual(testCase, cost.analyses_per_configuration_per_recording, 4);

verifyError(testCase, @() vawlume.eda.probeCost(dataset, 8, ...
    MaximumAnalyses=32), "vawlume:eda:ProbeExceedsAnalysisBudget");
opted = vawlume.eda.probeCost(dataset, 8, MaximumAnalyses=32, ...
    AllowExceedingMaximum=true);
verifyTrue(testCase, opted.exceeded_maximum_by_opt_in);
verifyTrue(testCase, any(contains(opted.warnings, "explicit opt-in")));

% The refusal names the analysis count, not the configuration count.
try
    vawlume.eda.probeCost(dataset, 8, MaximumAnalyses=32);
    verifyFail(testCase, "expected a refusal");
catch exception
    verifyTrue(testCase, contains(exception.message, "64 analyses"));
    verifyTrue(testCase, contains(exception.message, ...
        "ceiling is on analyses, not configurations"));
end

clear cleanup
end

function testTheRunnerEnforcesTheCeilingBeforeWritingAnything(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
before = analysisCount(fixture.conn);
verifyError(testCase, @() vawlume.eda.runScreen(fixture.conn, dataset, ...
    materialized, RepoRoot=fixture.repo_root, Apply=true, ...
    MaximumAnalyses=4), "vawlume:eda:ProbeExceedsAnalysisBudget");
verifyEqual(testCase, analysisCount(fixture.conn), before);

clear cleanup
end

% ------------------------------------------------------------- execution ---

function testAProbeExecutesToTheAnalysisCountTheFormulaPredicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
before = analysisCount(fixture.conn);

result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

verifyEqual(testCase, result.status, "completed");
verifyEqual(testCase, height(materialized.index), 2);
verifyEqual(testCase, result.cost.total_analyses, 2 * 2 * 4);
verifyEqual(testCase, height(result.manifest), 16);
verifyEqual(testCase, result.status_counts.committed, 16);
verifyEqual(testCase, result.status_counts.failed, 0);

% One matching analysis per pair and one agreement analysis per recording, per
% configuration, plus the exploration run row itself.
verifyEqual(testCase, analysisCount(fixture.conn), before + 16 + 1);
verifyEqual(testCase, countWhere(fixture.conn, "analysis_runs", ...
    "run_type='cross_extractor_matching' AND run_key LIKE '" + ...
    materialized.exploration_run_key + "%'"), 12);
verifyEqual(testCase, countWhere(fixture.conn, "analysis_runs", ...
    "run_type='multi_extractor_agreement' AND run_key LIKE '" + ...
    materialized.exploration_run_key + "%'"), 4);

clear cleanup
end

function testRunKeysFollowTheContractTemplate(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

runKey = materialized.exploration_run_key;
configurationId = materialized.index.configuration_id(1);
matching = result.manifest(result.manifest.unit_kind == "matching" & ...
    result.manifest.configuration_id == configurationId & ...
    result.manifest.recording_id == 1, :);
verifyTrue(testCase, all(startsWith(matching.run_key, ...
    runKey + "/" + configurationId + "/m/r1/")));
verifyTrue(testCase, ismember(runKey + "/" + configurationId + ...
    "/m/r1/deepsqueak-mupet", matching.run_key));

agreement = result.manifest(result.manifest.unit_kind == "agreement" & ...
    result.manifest.configuration_id == configurationId & ...
    result.manifest.recording_id == 1, :);
verifyEqual(testCase, agreement.run_key, ...
    runKey + "/" + configurationId + "/a/r1");

% No timestamp, counter, or random suffix anywhere.
verifyFalse(testCase, any(contains(result.manifest.run_key, ...
    ["20", "T0", "Z"])));

clear cleanup
end

function testEachConfigurationRanUnderItsOwnSpecificationChecksum(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

stored = fetch(fixture.conn, "SELECT DISTINCT cpv.checksum_sha256 " + ...
    "FROM analysis_runs ar " + ...
    "JOIN analysis_run_profiles arp ON arp.analysis_run_id=ar.analysis_run_id " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=arp.profile_version_id " + ...
    "WHERE arp.assignment_role='matching_spec' AND ar.run_key LIKE '" + ...
    materialized.exploration_run_key + "%'");
verifyEqual(testCase, sort(string(stored.checksum_sha256)), ...
    sort(materialized.index.checksum_sha256));

clear cleanup
end

% ----------------------------------------------------------- dry running ---

function testADryRunPlansEverythingAndWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
before = tableCounts(fixture.conn);

result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root);

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.applied);
verifyEqual(testCase, height(result.manifest), 16);
verifyEqual(testCase, result.status_counts.planned, 16);
verifyEqual(testCase, result.status_counts.committed, 0);
verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, result.exploration_run.status, "not_applied");

clear cleanup
end

% ------------------------------------------------ reuse, conflict, failure ---

function testRerunningAnExecutedProbeWritesNothingNew(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);
before = tableCounts(fixture.conn);

again = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

verifyEqual(testCase, again.status, "completed");
verifyEqual(testCase, again.status_counts.reused, 16);
verifyEqual(testCase, again.status_counts.committed, 0);
verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, again.exploration_run.status, "reused");

clear cleanup
end

function testAGenuinelyDifferentSpecificationProducesNewAnalyses(testCase)
% The reuse test proves nothing unless a different specification is seen to
% produce new work. Same dataset, a different design, so different
% configuration identifiers and different run keys.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, first] = probeInputs(fixture);
vawlume.eda.runScreen(fixture.conn, dataset, first, ...
    RepoRoot=fixture.repo_root, Apply=true);
beforeSecond = analysisCount(fixture.conn);

[~, second] = probeInputs(fixture, Shift=0.01);
verifyNotEqual(testCase, second.exploration_run_key, first.exploration_run_key);
outcome = vawlume.eda.runScreen(fixture.conn, dataset, second, ...
    RepoRoot=fixture.repo_root, Apply=true);

verifyEqual(testCase, outcome.status_counts.committed, 16);
verifyEqual(testCase, outcome.status_counts.reused, 0);
verifyEqual(testCase, analysisCount(fixture.conn), beforeSecond + 16 + 1);

clear cleanup
end

function testAChangedSpecificationUnderAStableRunKeyIsAConflict(testCase)
% Rewrite a generated specification's bytes without changing its name, so the
% run key is identical and only the checksum differs. The runner must surface
% that and leave the stored analysis exactly as it was.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

targetPath = materialized.index.specification_path(1);
originalChecksum = storedChecksumFor(fixture, materialized, 1);
document = jsondecode(fileread(targetPath));
document.candidate_generation.plausibility_rule.min_temporal_iou = 0.42;
writeJson(targetPath, document);

before = tableCounts(fixture.conn);
result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

verifyEqual(testCase, result.status, "completed_with_problems");
verifyGreaterThan(testCase, result.status_counts.conflict, 0);
conflicted = result.manifest(result.manifest.status == "conflict", :);
verifyTrue(testCase, all(conflicted.configuration_id == ...
    materialized.index.configuration_id(1)));
verifyTrue(testCase, any(contains(conflicted.detail, "checksum")), ...
    "The conflict must fire on the checksum, not incidentally on an input.");

% Nothing was written, and the stored analysis still cites its original bytes.
verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, storedChecksumFor(fixture, materialized, 1), ...
    originalChecksum);

clear cleanup
end

function testAnIncompletePairwiseSetSkipsItsCompositionAndMarksIt(testCase)
% Force one pair of one recording to fail by pointing its extraction run at a
% detection with impossible geometry. The composer would refuse the incomplete
% set anyway, but with a message about missing coverage rather than about the
% pair that actually failed.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
execute(fixture.conn, "INSERT INTO detections(extraction_run_id," + ...
    "recording_id,native_event_id,start_time_s,end_time_s,timing_basis) " + ...
    "VALUES(4,1,'bad-geometry',5.0,5.0,'profile_selected_event_geometry')");

result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

verifyEqual(testCase, result.status, "completed_with_problems");
verifyGreaterThan(testCase, result.status_counts.failed, 0);
verifyGreaterThan(testCase, result.status_counts.skipped, 0);

skipped = result.manifest(result.manifest.status == "skipped", :);
verifyTrue(testCase, all(skipped.unit_kind == "agreement"));
verifyTrue(testCase, all(skipped.recording_id == 1));
verifyTrue(testCase, all(contains(skipped.detail, "Pairwise set incomplete")));

% Recording 2 is untouched, so its compositions still succeed.
untouched = result.manifest(result.manifest.recording_id == 2 & ...
    result.manifest.unit_kind == "agreement", :);
verifyTrue(testCase, all(untouched.status == "committed"));

clear cleanup
end

function testAPartialProbeReportsTheDesignAsIncomplete(testCase)
% Effect estimation assumes every design row was evaluated on the same
% recordings. This is the signal that lets the estimation layer refuse.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
execute(fixture.conn, "INSERT INTO detections(extraction_run_id," + ...
    "recording_id,native_event_id,start_time_s,end_time_s,timing_basis) " + ...
    "VALUES(4,1,'bad-geometry',5.0,5.0,'profile_selected_event_geometry')");

result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);
completeness = result.design_completeness;

verifyFalse(testCase, completeness.is_complete);
verifyLessThan(testCase, completeness.completed_agreement_units, ...
    completeness.expected_agreement_units);
verifyEqual(testCase, completeness.balanced_recording_ids, 2);
verifyEqual(testCase, completeness.balanced_recording_count, 1);
verifyEqual(testCase, completeness.total_recording_count, 2);
verifyTrue(testCase, contains(completeness.note, "THIS DESIGN IS INCOMPLETE"));

clear cleanup
end

function testACompleteProbeReportsTheDesignAsBalanced(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

completeness = result.design_completeness;
verifyTrue(testCase, completeness.is_complete);
verifyEqual(testCase, completeness.balanced_recording_count, 2);
verifyEqual(testCase, completeness.completed_agreement_units, ...
    completeness.expected_agreement_units);

clear cleanup
end

% ------------------------------------------------------------ provenance ---

function testOneExplorationRunLinksTheProbesAgreementAnalyses(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);

exploration = result.exploration_run;
verifyEqual(testCase, exploration.status, "created");
verifyEqual(testCase, exploration.run_type, "consilience_exploration");
verifyEqual(testCase, exploration.linked_source_analyses, 4);

stored = fetch(fixture.conn, "SELECT run_type, run_key, status " + ...
    "FROM analysis_runs WHERE analysis_run_id=" + ...
    string(exploration.analysis_run_id));
verifyEqual(testCase, string(stored.run_type(1)), "consilience_exploration");
verifyEqual(testCase, string(stored.run_key(1)), ...
    materialized.exploration_run_key);
verifyEqual(testCase, string(stored.status(1)), "completed");

% Every linked source is one of the probe's agreement analyses.
sources = fetch(fixture.conn, "SELECT ar.run_type, ar.run_key " + ...
    "FROM analysis_run_sources ars " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id=ars.source_analysis_run_id " + ...
    "WHERE ars.analysis_run_id=" + string(exploration.analysis_run_id));
verifyEqual(testCase, height(sources), 4);
verifyTrue(testCase, all(string(sources.run_type) == ...
    "multi_extractor_agreement"));
verifyTrue(testCase, all(contains(string(sources.run_key), "/a/r")));

clear cleanup
end

function testTheDesignRecordIsRegisteredAsAChecksumBearingProfileVersion(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[dataset, materialized] = probeInputs(fixture);
result = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true);
profile = result.exploration_run.design_profile;

stored = fetch(fixture.conn, "SELECT cp.profile_kind, cpv.content_format, " + ...
    "cpv.checksum_sha256, arp.assignment_role FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE arp.analysis_run_id=" + ...
    string(result.exploration_run.analysis_run_id));
verifyEqual(testCase, height(stored), 1);
verifyEqual(testCase, string(stored.profile_kind(1)), "analysis_settings");
verifyEqual(testCase, string(stored.content_format(1)), "json");
verifyEqual(testCase, string(stored.assignment_role(1)), "exploration_design");
verifyEqual(testCase, string(stored.checksum_sha256(1)), ...
    profile.checksum_sha256);

% The record is readable and carries the automatic choices.
record = jsondecode(fileread(profile.content_uri));
verifyEqual(testCase, string(record.exploration_run_key), ...
    materialized.exploration_run_key);
verifyEqual(testCase, numel(record.configuration_ids), 2);
verifyTrue(testCase, isfield(record.probe_resolution, "seed"));
verifyTrue(testCase, isfield(record.probe_resolution, "strictness_direction"));
verifyFalse(testCase, any(contains(lower(string(fieldnames(record))), ...
    "final_threshold")));

clear cleanup
end

function testNoFinalThresholdFieldExistsAnywhereInTheRunner(testCase)
root = repoRootPath();
for name = ["runScreen.m", "resolveDataset.m", "probeCost.m"]
    text = string(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    verifyFalse(testCase, contains(lower(text), "final_threshold"), name);
    verifyFalse(testCase, contains(lower(text), "selected_threshold"), name);
    verifyFalse(testCase, contains(lower(text), "best_configuration"), name);
end
end

% ---------------------------------------------------------------- helpers ---

function [dataset, materialized] = probeInputs(fixture, options)
%PROBEINPUTS A small real probe: one screened factor, so two configurations.
%
% One active factor, not four. These tests exercise the RUNNER - that it loops
% configurations by recordings by pairs, reuses, conflicts, and reports - and the
% design's statistical properties are Part 6's to prove. A four-factor design
% would cost sixteen configurations, sixty-four analyses per recording pair set,
% and minutes per test, to assert nothing this layer owns.
%
% min_temporal_iou is the factor that varies, so the two configurations really do
% admit different candidate sets rather than differing only on paper.
arguments
    fixture
    options.Shift (1,1) double = 0
end
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));
resolution = vawlume.eda.probeParameters( ...
    struct(metrics=table(zeros(0, 1), VariableNames="temporal_iou"), ...
    metric_names="temporal_iou"), ...
    vawlume.eda.explorationOptions(struct( ...
        threshold_ranges=struct( ...
            min_temporal_iou=[0.05 0.40] + options.Shift), ...
        disabled_factors=["max_abs_onset_difference_s", ...
            "max_abs_offset_difference_s", ...
            "max_abs_duration_difference_s"])));
design = vawlume.eda.screeningDesign(resolution);
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
end

function value = storedChecksumFor(fixture, materialized, row)
runKey = materialized.exploration_run_key + "/" + ...
    materialized.index.configuration_id(row) + "/m/r1/deepsqueak-mupet";
stored = fetch(fixture.conn, "SELECT cpv.checksum_sha256 " + ...
    "FROM analysis_runs ar " + ...
    "JOIN analysis_run_profiles arp ON arp.analysis_run_id=ar.analysis_run_id " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=arp.profile_version_id " + ...
    "WHERE ar.run_key='" + runKey + "'");
value = string(stored.checksum_sha256(1));
end

function writeJson(path, document)
text = jsonencode(document, PrettyPrint=true);
fileId = fopen(path, "wb");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, unicode2native(text, "UTF-8"), "uint8");
delete(cleaner);
end

function value = analysisCount(conn)
value = countWhere(conn, "analysis_runs", "1=1");
end

function value = countWhere(conn, tableName, predicate)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName + ...
    " WHERE " + predicate);
value = double(rows.n(1));
end

function counts = tableCounts(conn)
names = ["analysis_runs", "analysis_run_sources", "analysis_run_profiles", ...
    "analysis_run_extraction_inputs", "candidate_pairs", "match_groups", ...
    "match_group_members", "consensus_events", "agreement_groups", ...
    "agreement_group_members", "agreement_supporting_edges", ...
    "config_profiles", "config_profile_versions", "detections"];
counts = struct();
for name = names
    counts.(name) = countWhere(conn, name, "1=1");
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
%PREPARESECONDRECORDING Give the fixture's second recording a full extractor set.
%
% The stock fixture runs all three extractors on one recording and DeepSqueak
% alone on the other. A screening design needs at least two recordings to show
% that a probe loops over them and that one recording's failure does not
% unbalance the other, so MUPET and USVSEG runs are added here.
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key,status) VALUES" + ...
    "(80,1,2,'fixture_mupet_baseline_v1','imported')," + ...
    "(81,1,3,'fixture_usvseg_baseline_v1','imported')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id,input_role) VALUES(80,2,'source_audio'),(81,2,'source_audio')");
insertDetection(conn, 3, 2, "ds-baseline-2", 20.000, 20.060);
insertDetection(conn, 80, 2, "mupet-baseline-1", 10.004, 10.052);
insertDetection(conn, 80, 2, "mupet-baseline-2", 20.002, 20.058);
insertDetection(conn, 81, 2, "usvseg-baseline-1", 10.002, 10.049);
insertDetection(conn, 81, 2, "usvseg-baseline-2", 20.006, 20.055);
end

function [fixture, cleanup] = setUpFixture(options)
arguments
    options.Prepare (1,1) logical = true
end
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "exploration-runner.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
if options.Prepare
    prepareSecondRecording(conn);
end
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
