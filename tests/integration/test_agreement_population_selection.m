function tests = test_agreement_population_selection
%TEST_AGREEMENT_POPULATION_SELECTION Analysis-ready agreement filters.
tests = functiontests(localfunctions);
end

function testDefaultSelectionReturnsGroupsAndNativeMembersReadOnly(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applied = applyAgreement(fixture, "agree-v1", fixture.pairwise);
before = counts(fixture.conn);

value = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-v1", project_key="phase1_synthetic_fixture"));
byId = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(analysis_run_id=applied.analysis.analysis_run_id));

verifyEqual(testCase, value.status, "selected");
verifyEqual(testCase, value.selected_group_count, 5);
verifyEqual(testCase, value.selected_member_count, 13);
verifyEqual(testCase, numel(unique(value.agreement_group_ids)), 5);
verifyEqual(testCase, numel(unique(value.detection_ids)), 13);
verifyEqual(testCase, value.agreement_group_ids, byId.agreement_group_ids);
verifyEqual(testCase, value.detection_ids, byId.detection_ids);
verifyEqual(testCase, counts(fixture.conn), before);
verifySubstring(testCase, value.identity_note, "native detections");
verifySubstring(testCase, value.interpretation_note, "not biological truth");

clear cleanup
end

function testExactPatternDoesNotMergeDifferentTwoOfThreeShapes(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
strictSources = applyStrictPairwise(fixture);
applyAgreement(fixture, "agree-strict", strictSources);
keys = groupKeys();

% Turn the surviving strict triangle into another valid 2-of-3 query shape by
% removing its MUPET--USVSEG support edge. The strict open chain already has a
% different 2-of-3 pattern. Both remain three-member connected components.
execute(fixture.conn, "DELETE FROM agreement_supporting_edges WHERE " + ...
    "agreement_supporting_edge_id=(SELECT agreement_supporting_edge_id " + ...
    "FROM v_agreement_supporting_edges WHERE agreement_run_key='agree-strict' " + ...
    "AND group_key=" + sqlText(keys.triangle) + ...
    " AND extractor_pair_key='mupet--usvseg')");

coarse = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-strict"), ExactSupportedPairCount=2, ...
    ExactPossiblePairCount=3);
verifyEqual(testCase, coarse.selected_group_count, 2);
verifyEqual(testCase, sort(coarse.groups.supported_extractor_pair_pattern), [ ...
    "deepsqueak--mupet|deepsqueak--usvseg"; ...
    "deepsqueak--usvseg|mupet--usvseg"]);

first = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-strict"), ExactSupportPattern= ...
    "deepsqueak--mupet|deepsqueak--usvseg");
second = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-strict"), ExactSupportPattern= ...
    "deepsqueak--usvseg|mupet--usvseg");
verifyEqual(testCase, first.selected_group_count, 1);
verifyEqual(testCase, second.selected_group_count, 1);
verifyNotEqual(testCase, first.agreement_group_ids, second.agreement_group_ids);
verifyEqual(testCase, first.groups.group_key, keys.triangle);
verifyEqual(testCase, second.groups.group_key, keys.chain);

clear cleanup
end

function testCompletenessCleanlinessAndMultiplicityRemainIndependent(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);
triple = "deepsqueak|mupet|usvseg";
keys = groupKeys();

complete = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-v1"), ExtractorSetKey=triple, ...
    Completeness="complete");
verifyEqual(testCase, complete.selected_group_count, 2);
verifyEqual(testCase, complete.selected_member_count, 8);

clean = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-v1"), ExtractorSetKey=triple, ...
    Completeness="complete", Cleanliness="clean", ...
    Multiplicity="one_per_extractor");
verifyEqual(testCase, clean.selected_group_count, 1);
verifyEqual(testCase, clean.selected_member_count, 3);
verifyEqual(testCase, clean.groups.group_key, keys.triangle);

split = vawlume.agreement.selectPopulation(fixture.conn, ...
    struct(run_key="agree-v1"), ExtractorSetKey=triple, ...
    Completeness="complete", Cleanliness="not_clean", ...
    Multiplicity="multiple_per_extractor");
verifyEqual(testCase, split.selected_group_count, 1);
verifyEqual(testCase, split.selected_member_count, 5);
verifyEqual(testCase, split.groups.group_key, keys.split);
verifyEqual(testCase, numel(unique(split.members.detection_id)), 5);

clear cleanup
end

function testCoarseStrengthUniquenessAndScopesAreComposable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);
conn = fixture.conn;

supported = vawlume.agreement.selectPopulation(conn, ...
    struct(run_key="agree-v1"), MinSupportedPairCount=1);
verifyEqual(testCase, supported.selected_group_count, 4);

pairOnly = vawlume.agreement.selectPopulation(conn, ...
    struct(run_key="agree-v1"), ExactSupportedPairCount=1, ...
    ExactPossiblePairCount=1);
verifyEqual(testCase, pairOnly.selected_group_count, 2);
verifyTrue(testCase, all(pairOnly.groups.support_fraction == 1));

uniqueOnly = vawlume.agreement.selectPopulation(conn, ...
    struct(run_key="agree-v1"), Uniqueness="extractor_unique");
verifyEqual(testCase, uniqueOnly.selected_group_count, 1);
verifyEqual(testCase, uniqueOnly.selected_member_count, 1);
verifyTrue(testCase, uniqueOnly.groups.is_singleton);
verifyTrue(testCase, isnan(uniqueOnly.groups.support_fraction));

ids = fetch(conn, "SELECT ee.entity_id, ee.native_id FROM experimental_entities ee " + ...
    "WHERE ee.native_id IN ('SUBJ_M01','SUBJ_OBS01') ORDER BY ee.native_id");
maleId = double(ids.entity_id(string(ids.native_id) == "SUBJ_M01"));
observerId = double(ids.entity_id(string(ids.native_id) == "SUBJ_OBS01"));
male = vawlume.agreement.selectPopulation(conn, struct(run_key="agree-v1"), ...
    EntityId=maleId);
observer = vawlume.agreement.selectPopulation(conn, struct(run_key="agree-v1"), ...
    EntityId=observerId);
verifyEqual(testCase, male.selected_group_count, 5);
verifyEqual(testCase, observer.selected_group_count, 0);
verifyEqual(testCase, observer.selected_member_count, 0);

socialId = scalar(conn, "SELECT recording_id AS n FROM recordings " + ...
    "WHERE native_recording_id='REC_SOCIAL_DYAD_01'");
baselineId = scalar(conn, "SELECT recording_id AS n FROM recordings " + ...
    "WHERE native_recording_id='REC_BASELINE_M01'");
social = vawlume.agreement.selectPopulation(conn, struct(run_key="agree-v1"), ...
    RecordingId=socialId);
baseline = vawlume.agreement.selectPopulation(conn, struct(run_key="agree-v1"), ...
    RecordingId=baselineId);
verifyEqual(testCase, social.selected_group_count, 5);
verifyEqual(testCase, baseline.selected_group_count, 0);

clear cleanup
end

function testInvalidAnalysisAndFilterRequestsAreNamed(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);

verifyError(testCase, @() vawlume.agreement.selectPopulation( ...
    fixture.conn, struct()), "vawlume:agreement:AnalysisRefInvalid");
verifyError(testCase, @() vawlume.agreement.selectPopulation( ...
    fixture.conn, struct(run_key="m_ds_mupet")), ...
    "vawlume:agreement:AnalysisTypeInvalid");
verifyError(testCase, @() vawlume.agreement.selectPopulation( ...
    fixture.conn, struct(run_key="agree-v1"), ...
    MinSupportedPairCount=3, ExactSupportedPairCount=2), ...
    "vawlume:agreement:PopulationFilterConflict");
verifyError(testCase, @() vawlume.agreement.selectPopulation( ...
    fixture.conn, struct(run_key="agree-v1"), RecordingId=0), ...
    "vawlume:agreement:PopulationFilterInvalid");

execute(fixture.conn, "INSERT INTO analysis_runs(project_id,run_type,run_key," + ...
    "status) SELECT project_id,'multi_extractor_agreement','agree-pending'," + ...
    "'started' FROM analysis_runs WHERE run_key='agree-v1'");
verifyError(testCase, @() vawlume.agreement.selectPopulation( ...
    fixture.conn, struct(run_key="agree-pending")), ...
    "vawlume:agreement:AnalysisNotCompleted");

clear cleanup
end

function result = applyAgreement(fixture, runKey, sources)
result = vawlume.agreement.compose(fixture.conn, socialRef(), sources, ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root, Apply=true);
end

function keys = applyStrictPairwise(fixture)
variant = writeStrictMatchingSpec(fixture);
pairs = { ...
    {"s_ds_mupet", "fixture_deepsqueak_social_v1", "fixture_mupet_social_v1"}, ...
    {"s_ds_usvseg", "fixture_deepsqueak_social_v1", "fixture_usvseg_social_v1"}, ...
    {"s_mupet_usvseg", "fixture_mupet_social_v1", "fixture_usvseg_social_v1"}};
keys = strings(numel(pairs), 1);
for index = 1:numel(pairs)
    spec = pairs{index};
    vawlume.matching.compare(fixture.conn, socialRef(), ...
        struct(run_a=spec{2}, run_b=spec{3}), ...
        struct(run_key=spec{1}, profile_path=variant), ...
        RepoRoot=fixture.repo_root, Apply=true);
    keys(index) = spec{1};
end
end

function path = writeStrictMatchingSpec(fixture)
source = fullfile(fixture.repo_root, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json");
text = string(fileread(source));
text = replace(text, """profile_version"": ""0.1.0""", """profile_version"": ""0.1.1""");
text = replace(text, """min_temporal_iou"": 0.10", """min_temporal_iou"": 0.47");
path = fullfile(fixture.scratch, "strict_matching_spec.json");
fileId = fopen(path, "w");
assert(fileId >= 0);
closer = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(closer);
end

function keys = groupKeys()
keys = struct();
keys.triangle = "fixture_deepsqueak_social_v1#1|" + ...
    "fixture_mupet_social_v1#1|fixture_usvseg_social_v1#1";
keys.split = "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#3|fixture_mupet_social_v1#4|" + ...
    "fixture_usvseg_social_v1#4|fixture_usvseg_social_v1#5";
keys.chain = "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#4|fixture_usvseg_social_v1#5";
end

function value = counts(conn)
names = ["analysis_runs", "agreement_groups", "agreement_group_members", ...
    "agreement_supporting_edges", "detections", "event_measurements"];
value = struct();
for name = names
    value.(name) = scalar(conn, "SELECT COUNT(*) AS n FROM " + name);
end
end

function ref = socialRef()
ref = struct(project_key="phase1_synthetic_fixture", ...
    source_relative_path="synthetic/recordings/session_social_dyad_01.wav");
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "agreement_population.sqlite");
copyfile(pairwiseTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    pairwise=["m_ds_mupet"; "m_ds_usvseg"; "m_mupet_usvseg"]);
end

function path = pairwiseTemplate(repoRoot)
persistent value
if isempty(value) || ~isfile(value)
    value = string(tempname) + ".sqlite";
    [conn, ~] = vawlume.db.createPhase1FixtureDatabase(value, repoRoot);
    closer = onCleanup(@() close(conn));
    pairs = { ...
        {"m_ds_mupet", "fixture_deepsqueak_social_v1", "fixture_mupet_social_v1"}, ...
        {"m_ds_usvseg", "fixture_deepsqueak_social_v1", "fixture_usvseg_social_v1"}, ...
        {"m_mupet_usvseg", "fixture_mupet_social_v1", "fixture_usvseg_social_v1"}};
    for index = 1:numel(pairs)
        spec = pairs{index};
        vawlume.matching.compare(conn, socialRef(), ...
            struct(run_a=spec{2}, run_b=spec{3}), struct(run_key=spec{1}), ...
            RepoRoot=repoRoot, Apply=true);
    end
    delete(closer);
end
path = value;
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
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
