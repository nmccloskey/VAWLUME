function tests = test_agreement_query_views
%TEST_AGREEMENT_QUERY_VIEWS Exact and coarse arbitrary-N agreement queries.
%
% Exact candidate edges remain the authority. These tests prove that the query
% layer retains them one-for-one while deriving deterministic extractor-pair
% patterns, K-of-possible summaries, completeness, multiplicity, and pairwise
% topology as separate facts.
tests = functiontests(localfunctions);
end

function testLongMemberAndExactEdgeViewsPreserveAuthority(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);
conn = fixture.conn;
keys = groupKeys();

members = fetch(conn, "SELECT * FROM v_agreement_group_members " + ...
    "WHERE agreement_run_key='agree-v1'");
verifyEqual(testCase, height(members), 13);
verifyEqual(testCase, numel(unique(double(members.detection_id))), 13);

triangle = fetch(conn, "SELECT extraction_run_key, extractor_key, " + ...
    "native_event_id, start_time_s, end_time_s, duration_s " + ...
    "FROM v_agreement_group_members WHERE agreement_run_key='agree-v1' " + ...
    "AND group_key=" + sqlText(keys.triangle) + " ORDER BY extractor_key");
verifyEqual(testCase, string(triangle.extractor_key), ...
    ["deepsqueak"; "mupet"; "usvseg"]);
verifyEqual(testCase, string(triangle.native_event_id), ["1"; "1"; "1"]);
verifyEqual(testCase, double(triangle.duration_s), ...
    double(triangle.end_time_s) - double(triangle.start_time_s), AbsTol=1e-12);

edges = fetch(conn, "SELECT * FROM v_agreement_supporting_edges " + ...
    "WHERE agreement_run_key='agree-v1'");
verifyEqual(testCase, height(edges), 11);
verifyEqual(testCase, numel(unique(double(edges.candidate_pair_id))), 11);
verifyTrue(testCase, all(strlength(string(edges.detection_edge_key)) > 0));
verifyTrue(testCase, all(double(edges.source_analysis_run_id) > 0));

split = fetch(conn, "SELECT extractor_pair_key, pairwise_match_type, " + ...
    "pairwise_ambiguity_status, temporal_iou FROM " + ...
    "v_agreement_supporting_edges WHERE agreement_run_key='agree-v1' " + ...
    "AND group_key=" + sqlText(keys.split));
verifyEqual(testCase, height(split), 6);
verifyEqual(testCase, sort(unique(string(split.extractor_pair_key))), [ ...
    "deepsqueak--mupet"; "deepsqueak--usvseg"; "mupet--usvseg"]);
verifyTrue(testCase, any(string(split.pairwise_match_type) == "one_to_many"));
verifyTrue(testCase, any(string(split.pairwise_match_type) == "one_to_one"));
verifyTrue(testCase, all(~ismissing(double(split.temporal_iou))));

clear cleanup
end

function testBaselineSummariesKeepCompletenessMultiplicityAndAmbiguitySeparate(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);
keys = groupKeys();

triangle = summaryFor(fixture.conn, "agree-v1", keys.triangle);
verifyEqual(testCase, double(triangle.member_count), 3);
verifyEqual(testCase, double(triangle.extractor_count), 3);
verifyEqual(testCase, double(triangle.support_edge_count), 3);
verifyEqual(testCase, double(triangle.supported_extractor_pair_count), 3);
verifyEqual(testCase, double(triangle.possible_extractor_pair_count), 3);
verifyEqual(testCase, double(triangle.assessed_extractor_pair_count), 3);
verifyEqual(testCase, double(triangle.support_fraction), 1, AbsTol=1e-12);
verifyEqual(testCase, string(triangle.supported_extractor_pair_pattern), ...
    "deepsqueak--mupet|deepsqueak--usvseg|mupet--usvseg");
verifyEqual(testCase, double(triangle.is_extractor_pair_support_complete), 1);
verifyEqual(testCase, double(triangle.is_one_detection_per_extractor), 1);
verifyEqual(testCase, double(triangle.is_unambiguous_one_to_one), 1);
verifyEqual(testCase, presentText( ...
    triangle.ambiguous_pairwise_topology_pattern), "");

% Complete at extractor-pair level, but neither one detection per extractor nor
% unambiguous. Six exact edges reduce to three supported extractor pairs.
split = summaryFor(fixture.conn, "agree-v1", keys.split);
verifyEqual(testCase, double(split.member_count), 5);
verifyEqual(testCase, double(split.extractor_count), 3);
verifyEqual(testCase, double(split.support_edge_count), 6);
verifyEqual(testCase, double(split.supported_extractor_pair_count), 3);
verifyEqual(testCase, double(split.possible_extractor_pair_count), 3);
verifyEqual(testCase, double(split.is_extractor_pair_support_complete), 1);
verifyEqual(testCase, double(split.is_one_detection_per_extractor), 0);
verifyEqual(testCase, double(split.is_unambiguous_one_to_one), 0);
verifyEqual(testCase, string(split.ambiguous_pairwise_topology_pattern), ...
    "one_to_many");

pairOnly = summaryFor(fixture.conn, "agree-v1", keys.pair_only);
verifyEqual(testCase, double(pairOnly.member_count), 2);
verifyEqual(testCase, double(pairOnly.extractor_count), 2);
verifyEqual(testCase, double(pairOnly.supported_extractor_pair_count), 1);
verifyEqual(testCase, double(pairOnly.possible_extractor_pair_count), 1);
verifyEqual(testCase, string(pairOnly.supported_extractor_pair_pattern), ...
    "deepsqueak--usvseg");
verifyEqual(testCase, double(pairOnly.is_extractor_pair_support_complete), 1);
verifyEqual(testCase, double(pairOnly.is_unambiguous_one_to_one), 1);

singleton = summaryFor(fixture.conn, "agree-v1", keys.singleton);
verifyEqual(testCase, double(singleton.member_count), 1);
verifyEqual(testCase, double(singleton.extractor_count), 1);
verifyEqual(testCase, double(singleton.support_edge_count), 0);
verifyEqual(testCase, double(singleton.possible_extractor_pair_count), 0);
verifyEqual(testCase, double(singleton.supported_extractor_pair_count), 0);
verifyEqual(testCase, double(singleton.is_extractor_pair_support_complete), 0);
verifyEqual(testCase, double(singleton.is_unambiguous_one_to_one), 0);
verifyEqual(testCase, double(singleton.is_singleton), 1);
verifyEqual(testCase, double(singleton.is_extractor_unique), 1);
verifyEqual(testCase, scalar(fixture.conn, ...
    "SELECT IFNULL(support_fraction,-1) AS n FROM v_agreement_group_summary " + ...
    "WHERE agreement_run_key='agree-v1' AND group_key=" + ...
    sqlText(keys.singleton)), -1);

clear cleanup
end

function testPartialPatternNamesTheMissingPair(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
strictKeys = applyStrictPairwise(fixture);
applyAgreement(fixture, "agree-strict", strictKeys);
keys = groupKeys();

chain = summaryFor(fixture.conn, "agree-strict", keys.chain);
verifyEqual(testCase, double(chain.member_count), 3);
verifyEqual(testCase, double(chain.extractor_count), 3);
verifyEqual(testCase, double(chain.support_edge_count), 2);
verifyEqual(testCase, double(chain.supported_extractor_pair_count), 2);
verifyEqual(testCase, double(chain.possible_extractor_pair_count), 3);
verifyEqual(testCase, double(chain.assessed_extractor_pair_count), 3);
verifyEqual(testCase, double(chain.support_fraction), 2/3, AbsTol=1e-12);
verifyEqual(testCase, string(chain.supported_extractor_pair_pattern), ...
    "deepsqueak--usvseg|mupet--usvseg");
verifyEqual(testCase, string(chain.unsupported_extractor_pair_pattern), ...
    "deepsqueak--mupet");
verifyEqual(testCase, double(chain.is_extractor_pair_support_complete), 0);
verifyEqual(testCase, double(chain.is_pairwise_assessment_complete), 1);
verifyEqual(testCase, double(chain.is_one_detection_per_extractor), 1);
verifyEqual(testCase, double(chain.is_unambiguous_one_to_one), 1);

pairs = fetch(fixture.conn, "SELECT extractor_pair_key, is_assessed, " + ...
    "is_supported, source_analysis_count, source_analysis_run_key " + ...
    "FROM v_agreement_extractor_pair_support " + ...
    "WHERE agreement_run_key='agree-strict' AND group_key=" + ...
    sqlText(keys.chain) + " ORDER BY extractor_pair_key");
verifyEqual(testCase, string(pairs.extractor_pair_key), [ ...
    "deepsqueak--mupet"; "deepsqueak--usvseg"; "mupet--usvseg"]);
verifyEqual(testCase, double(pairs.is_assessed), [1; 1; 1]);
verifyEqual(testCase, double(pairs.source_analysis_count), [1; 1; 1]);
verifyEqual(testCase, double(pairs.is_supported), [0; 1; 1]);
verifyEqual(testCase, string(pairs.source_analysis_run_key(1)), "s_ds_mupet");

clear cleanup
end

function testStoredQuerySummaryMatchesCompositionPlanDimensions(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = applyAgreement(fixture, "agree-v1", fixture.pairwise);

for index = 1:height(result.groups)
    planned = result.groups(index, :);
    queried = summaryFor(fixture.conn, "agree-v1", planned.group_key);
    supportedCount = delimitedCount(planned.supported_pair_labels, ";");
    possibleCount = supportedCount + ...
        delimitedCount(planned.unsupported_pair_labels, ";");

    verifyEqual(testCase, double(queried.member_count), planned.member_count);
    verifyEqual(testCase, double(queried.extractor_count), planned.extractor_count);
    verifyEqual(testCase, double(queried.support_edge_count), ...
        planned.support_edge_count);
    verifyEqual(testCase, double(queried.supported_extractor_pair_count), ...
        supportedCount);
    verifyEqual(testCase, double(queried.possible_extractor_pair_count), ...
        possibleCount);
    verifyEqual(testCase, logical(queried.is_extractor_pair_support_complete), ...
        planned.pair_support_complete);
    verifyEqual(testCase, logical(queried.is_one_detection_per_extractor), ...
        planned.member_count == planned.extractor_count);
    verifyEqual(testCase, logical(queried.is_singleton), planned.is_singleton);
    verifyEqual(testCase, strlength(presentText( ...
        queried.ambiguous_pairwise_topology_pattern)) > 0, ...
        strlength(planned.ambiguous_source_topologies) > 0);
end

clear cleanup
end

function testSummaryUsesCombinatoricsRatherThanAThreeExtractorConstant(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);
fourKey = extendTriangleToFourthExtractor(fixture);

summary = summaryFor(fixture.conn, "agree-v1", fourKey);
verifyEqual(testCase, double(summary.member_count), 4);
verifyEqual(testCase, double(summary.extractor_count), 4);
verifyEqual(testCase, double(summary.support_edge_count), 6);
verifyEqual(testCase, double(summary.supported_extractor_pair_count), 6);
verifyEqual(testCase, double(summary.possible_extractor_pair_count), 6);
verifyEqual(testCase, double(summary.assessed_extractor_pair_count), 6);
verifyEqual(testCase, double(summary.support_fraction), 1, AbsTol=1e-12);
verifyEqual(testCase, string(summary.extractor_set_key), ...
    "deepsqueak|fourth|mupet|usvseg");
verifyEqual(testCase, double(summary.is_extractor_pair_support_complete), 1);
verifyEqual(testCase, double(summary.is_one_detection_per_extractor), 1);
verifyEqual(testCase, double(summary.is_unambiguous_one_to_one), 1);
verifyEqual(testCase, scalar(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM v_agreement_extractor_pair_support " + ...
    "WHERE agreement_run_key='agree-v1' AND group_key=" + sqlText(fourKey)), 6);

clear cleanup
end

function fourKey = extendTriangleToFourthExtractor(fixture)
conn = fixture.conn;
keys = groupKeys();
triangle = fetch(conn, "SELECT agreement_group_id, analysis_run_id, recording_id " + ...
    "FROM agreement_groups WHERE group_key=" + sqlText(keys.triangle));
groupId = double(triangle.agreement_group_id(1));
agreementId = double(triangle.analysis_run_id(1));
recordingId = double(triangle.recording_id(1));
projectId = scalar(conn, "SELECT project_id AS n FROM analysis_runs WHERE " + ...
    "analysis_run_id=" + string(agreementId));

execute(conn, "INSERT INTO extractors(extractor_key,extractor_name) " + ...
    "VALUES('fourth','Fourth')");
extractorId = lastId(conn);
execute(conn, "INSERT INTO extractor_versions(extractor_id,version_label) " + ...
    "VALUES(" + string(extractorId) + ",'1.0')");
versionId = lastId(conn);
execute(conn, "INSERT INTO extraction_runs(project_id,extractor_version_id," + ...
    "run_key,status) VALUES(" + string(projectId) + "," + string(versionId) + ...
    ",'fixture_fourth_social_v1','imported')");
runId = lastId(conn);
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id," + ...
    "input_role) VALUES(" + string(runId) + "," + string(recordingId) + ...
    ",'source_audio')");
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES(" + ...
    string(runId) + "," + string(recordingId) + ...
    ",'1',10.003,10.051,'profile_selected_event_geometry')");
fourthDetection = lastId(conn);
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
    "extraction_run_id,input_role) VALUES(" + string(agreementId) + "," + ...
    string(runId) + ",'agreement_input')");

fourKey = keys.triangle + "|fixture_fourth_social_v1#1";
selectors = sort(split(fourKey, "|"));
fourKey = strjoin(selectors, "|");
execute(conn, "UPDATE agreement_groups SET group_key=" + sqlText(fourKey) + ...
    " WHERE agreement_group_id=" + string(groupId));
execute(conn, "INSERT INTO agreement_group_members(agreement_group_id," + ...
    "detection_id,member_role) VALUES(" + string(groupId) + "," + ...
    string(fourthDetection) + ",'member')");

peers = fetch(conn, "SELECT detection_id, extraction_run_id, extractor_key " + ...
    "FROM v_agreement_group_members WHERE agreement_group_id=" + ...
    string(groupId) + " AND detection_id<>" + string(fourthDetection));
for index = 1:height(peers)
    sourceKey = "q_" + string(peers.extractor_key(index)) + "_fourth";
    execute(conn, "INSERT INTO analysis_runs(project_id,run_type,run_key,status) " + ...
        "VALUES(" + string(projectId) + ",'cross_extractor_matching'," + ...
        sqlText(sourceKey) + ",'completed')");
    sourceId = lastId(conn);
    execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
        "extraction_run_id,input_role) VALUES(" + string(sourceId) + "," + ...
        string(peers.extraction_run_id(index)) + ",'run_a'),(" + ...
        string(sourceId) + "," + string(runId) + ",'run_b')");
    first = min(double(peers.detection_id(index)), fourthDetection);
    second = max(double(peers.detection_id(index)), fourthDetection);
    execute(conn, "INSERT INTO candidate_pairs(analysis_run_id,recording_id," + ...
        "detection_a_id,detection_b_id,temporal_overlap_s,temporal_iou," + ...
        "candidate_status) VALUES(" + string(sourceId) + "," + ...
        string(recordingId) + "," + string(first) + "," + string(second) + ...
        ",0.047,0.90,'eligible')");
    candidateId = lastId(conn);
    execute(conn, "INSERT INTO match_groups(analysis_run_id,recording_id," + ...
        "match_type,ambiguity_status) VALUES(" + string(sourceId) + "," + ...
        string(recordingId) + ",'one_to_one','unambiguous')");
    matchGroupId = lastId(conn);
    execute(conn, "INSERT INTO match_group_members(match_group_id,detection_id," + ...
        "member_role) VALUES(" + string(matchGroupId) + "," + string(first) + ...
        ",'run_a'),(" + string(matchGroupId) + "," + string(second) + ",'run_b')");
    execute(conn, "INSERT INTO analysis_run_sources(analysis_run_id," + ...
        "source_analysis_run_id,dependency_role) VALUES(" + ...
        string(agreementId) + "," + string(sourceId) + ",'pairwise_source')");
    execute(conn, "INSERT INTO agreement_supporting_edges(agreement_group_id," + ...
        "candidate_pair_id) VALUES(" + string(groupId) + "," + ...
        string(candidateId) + ")");
end
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

function row = summaryFor(conn, runKey, groupKey)
rows = fetch(conn, "SELECT member_count, extraction_run_count, " + ...
    "extractor_count, extractor_set_key, support_edge_count, " + ...
    "supported_extractor_pair_count, possible_extractor_pair_count, " + ...
    "assessed_extractor_pair_count, IFNULL(support_fraction,-1) AS " + ...
    "support_fraction, supported_extractor_pair_pattern, " + ...
    "unsupported_extractor_pair_pattern, " + ...
    "is_extractor_pair_support_complete, is_pairwise_assessment_complete, " + ...
    "is_one_detection_per_extractor, is_unambiguous_one_to_one, " + ...
    "ambiguous_pairwise_topology_pattern, is_singleton, " + ...
    "is_extractor_unique FROM v_agreement_group_summary WHERE " + ...
    "agreement_run_key=" + sqlText(runKey) + " AND group_key=" + ...
    sqlText(groupKey));
assert(height(rows) == 1);
row = rows(1, :);
end

function keys = groupKeys()
keys = struct();
keys.triangle = "fixture_deepsqueak_social_v1#1|" + ...
    "fixture_mupet_social_v1#1|fixture_usvseg_social_v1#1";
keys.split = "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#3|fixture_mupet_social_v1#4|" + ...
    "fixture_usvseg_social_v1#4|fixture_usvseg_social_v1#5";
keys.pair_only = "fixture_deepsqueak_social_v1#2|" + ...
    "fixture_usvseg_social_v1#2";
keys.singleton = "fixture_usvseg_social_v1#6";
keys.chain = "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#4|fixture_usvseg_social_v1#5";
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
dbPath = fullfile(scratch, "agreement_queries.sqlite");
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

function value = lastId(conn)
value = scalar(conn, "SELECT last_insert_rowid() AS n");
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function value = delimitedCount(text, delimiter)
text = presentText(text);
if strlength(text) == 0
    value = 0;
else
    value = numel(split(text, delimiter));
end
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
