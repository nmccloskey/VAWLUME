function tests = test_eda_generated_specifications
%TEST_EDA_GENERATED_SPECIFICATIONS Generated specifications load through the real matcher.
%
% The exploration package cannot call the matcher's specification loader: it is
% private to that package, and exposing it would mean editing a package this
% itinerary's tripwire puts out of bounds. So the round trip that matters is
% asserted here, through the only public door - vawlume.matching.compare with an
% explicit profile_path - on a small fixture database.
%
% A specification that writes cleanly but LOADS differently is the worst failure
% available in this layer. It produces a plausible screen whose axes are silently
% wrong, and nothing downstream could detect it: the responses would be real
% numbers computed under parameters nobody chose. That is what these tests exist
% to rule out.
tests = functiontests(localfunctions);
end

function testEveryGeneratedSpecificationLoadsWithItsOwnFactorValues(testCase)
% compare() returns the plausibility rule its own loader parsed, so this
% compares what the matcher read against what the design intended, value by
% value, for every configuration.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[design, materialized] = materialize(fixture);
names = design.factors.factor_name;

for row = 1:height(materialized.index)
    result = planWith(fixture, materialized.index.specification_path(row), ...
        "probe-" + string(row));
    loaded = result.plausibility_rule;
    for column = 1:numel(names)
        verifyEqual(testCase, loaded.(names(column)), ...
            materialized.index.(names(column))(row), ...
            names(column) + " row " + string(row));
    end
end
end

function testTheMatchersChecksumAgreesWithTheReportedOne(testCase)
% The exploration package reports a checksum for convenience; the matcher's is
% authoritative for analysis identity. They must be the same value, and this
% asserts it on a real generated file rather than assuming it.
[~, cleanupHandle] = deal([], []); %#ok<ASGLU>
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[~, materialized] = materialize(fixture);

for row = 1:height(materialized.index)
    result = planWith(fixture, materialized.index.specification_path(row), ...
        "checksum-" + string(row));
    verifyEqual(testCase, result.configuration.checksum_sha256, ...
        materialized.index.checksum_sha256(row));
end
end

function testEachConfigurationIsADistinctAnalysisIdentity(testCase)
% Distinct checksums mean distinct analysis identities, so two configurations
% applied under their own run keys coexist rather than colliding.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[~, materialized] = materialize(fixture);
paths = materialized.index.specification_path;

first = applyWith(fixture, paths(1), runKeyFor(materialized, 1));
second = applyWith(fixture, paths(2), runKeyFor(materialized, 2));
verifyEqual(testCase, first.status, "committed");
verifyEqual(testCase, second.status, "committed");

% Scoped to this design's run keys. The fixture ships a seeded
% cross_extractor_matching analysis of its own, so an unscoped count would be
% counting a row this test did not create.
analyses = fetch(fixture.conn, "SELECT run_key FROM analysis_runs " + ...
    "WHERE run_type='cross_extractor_matching' AND run_key LIKE '" + ...
    materialized.exploration_run_key + "%' ORDER BY run_key");
verifyEqual(testCase, height(analyses), 2);
verifyEqual(testCase, sort(string(analyses.run_key)), ...
    sort([runKeyFor(materialized, 1); runKeyFor(materialized, 2)]));

% Scoped to the versions the two matching analyses actually linked. The fixture
% ships extractor, device and setup profiles of its own, so an unscoped query
% would be counting rows that have nothing to do with this design.
versions = fetch(fixture.conn, "SELECT DISTINCT cpv.version_label " + ...
    "FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=arp.profile_version_id " + ...
    "WHERE arp.assignment_role='matching_spec' ORDER BY cpv.version_label");
verifyEqual(testCase, height(versions), 2);
verifyTrue(testCase, all(contains(string(versions.version_label), "+exp.cfg-")));
end

function testTheProfileVersionNamesTheConfigurationInStoredProvenance(testCase)
% A human reading analysis_runs later must be able to name the configuration
% without recomputing a checksum.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[~, materialized] = materialize(fixture);
applyWith(fixture, materialized.index.specification_path(1), ...
    runKeyFor(materialized, 1));

stored = fetch(fixture.conn, "SELECT cpv.version_label FROM analysis_runs ar " + ...
    "JOIN analysis_run_profiles arp ON arp.analysis_run_id=ar.analysis_run_id " + ...
    "JOIN config_profile_versions cpv " + ...
    "ON cpv.profile_version_id=arp.profile_version_id " + ...
    "WHERE arp.assignment_role='matching_spec'");
verifyEqual(testCase, height(stored), 1);
verifyEqual(testCase, string(stored.version_label(1)), ...
    materialized.index.profile_version(1));
verifyTrue(testCase, contains(string(stored.version_label(1)), ...
    materialized.index.configuration_id(1)));
end

function testAGeneratedSpecificationStillEnforcesTheGatesItDeclares(testCase)
% The point of materializing a configuration is that it changes what the matcher
% admits. A file that loaded cleanly but gated identically to the base would
% mean the screen varied nothing.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
[design, materialized] = materialize(fixture);

counts = zeros(height(materialized.index), 1);
for row = 1:height(materialized.index)
    result = planWith(fixture, materialized.index.specification_path(row), ...
        "gate-" + string(row));
    counts(row) = result.candidate_count;
end
verifyGreaterThan(testCase, numel(unique(counts)), 1, ...
    "Every configuration admitted the same candidates, so the design varies " + ...
    "nothing the matcher responds to.");

% The strictest row admits no more than the most permissive one.
verifyEqual(testCase, design.coding(1, :), -ones(1, height(design.factors)));
end

% ---------------------------------------------------------------- helpers ---

function [design, materialized] = materialize(fixture)
%MATERIALIZE A four-factor half fraction over intervals the fixture data spans.
%
% The probe intervals are supplied as explicit overrides rather than derived, so
% this suite tests materialization and loading rather than re-testing the
% resolver, and so the values are known to straddle the fixture's candidates.
options = vawlume.eda.explorationOptions(struct( ...
    threshold_ranges=struct( ...
        min_temporal_iou=[0.05 0.40], ...
        max_abs_onset_difference_s=[0.002 0.060], ...
        max_abs_offset_difference_s=[0.002 0.060], ...
        max_abs_duration_difference_s=[0.002 0.060])));
surface = struct(metrics=table(zeros(0, 1), VariableNames="temporal_iou"), ...
    metric_names="temporal_iou");
resolution = vawlume.eda.probeParameters(surface, options);
design = vawlume.eda.screeningDesign(resolution, MaximumConfigurations=8);
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
end

function value = runKeyFor(materialized, row)
value = materialized.exploration_run_key + "-" + ...
    materialized.index.configuration_id(row);
end

function result = planWith(fixture, specPath, runKey)
result = vawlume.matching.compare(fixture.conn, recordingRef(), pair(), ...
    struct(run_key=runKey, profile_path=specPath), ...
    RepoRoot=fixture.repo_root);
end

function result = applyWith(fixture, specPath, runKey)
result = vawlume.matching.compare(fixture.conn, recordingRef(), pair(), ...
    struct(run_key=runKey, profile_path=specPath), ...
    RepoRoot=fixture.repo_root, Apply=true);
end

function ref = recordingRef()
ref = struct(project_key="phase1_synthetic_fixture", ...
    source_relative_path="synthetic/recordings/session_social_dyad_01.wav");
end

function value = pair()
value = struct(run_a="fixture_deepsqueak_social_v1", ...
    run_b="fixture_mupet_social_v1");
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "generated-specs.sqlite");
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
