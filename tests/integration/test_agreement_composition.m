function tests = test_agreement_composition
%TEST_AGREEMENT_COMPOSITION Edge-preserving arbitrary-N composition over the fixture.
%
% Composition turns the exact candidate edges of a complete pairwise set into
% components over native detections. The claims this suite holds:
%
%   membership is connectivity, and connectivity is not completeness;
%   no transitive edge is ever invented to make a component look complete;
%   an extractor-unique detection survives as a single-member group;
%   ambiguous pairwise topology is carried, not coerced into agreement;
%   every stored edge is traceable back to its pairwise analysis and its
%   versioned matching specification.
%
% Two agreement runs are composed over the same three extractors. The first uses
% the tracked matching specification; the second uses a stricter temporal floor,
% which changes the pairwise candidate universe and so produces different
% component shapes. That second run is how the open-chain case reaches the
% database: the agreement layer never re-filters, it composes whatever universe
% the source specifications defined.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------- the composed graph ---

function testNodeSetAndEdgeUniverseAreExactAndFrozen(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planAgreement(fixture, "agree-v1", fixture.pairwise);

% Every detection of the three participating runs is a node, including the one
% no other extractor corroborated.
verifyEqual(testCase, result.node_count, 13);
verifyEqual(testCase, sort(result.nodes.selector), sort([ ...
    "fixture_deepsqueak_social_v1#1"; "fixture_deepsqueak_social_v1#2"; ...
    "fixture_deepsqueak_social_v1#3"; "fixture_mupet_social_v1#1"; ...
    "fixture_mupet_social_v1#2"; "fixture_mupet_social_v1#3"; ...
    "fixture_mupet_social_v1#4"; "fixture_usvseg_social_v1#1"; ...
    "fixture_usvseg_social_v1#2"; "fixture_usvseg_social_v1#3"; ...
    "fixture_usvseg_social_v1#4"; "fixture_usvseg_social_v1#5"; ...
    "fixture_usvseg_social_v1#6"]));
% The baseline recording's DeepSqueak detection is not a participant.
verifyFalse(testCase, any(contains(result.nodes.selector, "baseline")));

% The edge universe is exactly the stored candidate rows of the three sources.
stored = scalar(fixture.conn, "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "WHERE ar.run_key IN ('m_ds_mupet','m_ds_usvseg','m_mupet_usvseg')");
verifyEqual(testCase, result.edge_count, stored);
verifyEqual(testCase, result.edge_count, 11);
verifyEqual(testCase, sort(result.edges.candidate_pair_id), ...
    sort(candidatePairIds(fixture, fixture.pairwise)));

% The frozen eligibility rule, and why no status filter is applied.
verifyEqual(testCase, result.eligibility.edge_universe, ...
    "stored_candidate_pairs_of_declared_source_analyses");
verifyEqual(testCase, result.eligibility.status_filter, "none_applied");
verifyEqual(testCase, result.eligibility.transitive_edges, "never_synthesized");
verifyEqual(testCase, unique(result.edges.candidate_status), "eligible");

% That rule is only sound because every stored candidate edge participates in
% its own analysis's pairwise partition. Verified, not assumed.
verifyEqual(testCase, scalar(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "WHERE ar.run_key IN ('m_ds_mupet','m_ds_usvseg','m_mupet_usvseg') " + ...
    "AND NOT EXISTS (SELECT 1 FROM match_group_members a " + ...
    "JOIN match_group_members b ON b.match_group_id = a.match_group_id " + ...
    "JOIN match_groups mg ON mg.match_group_id = a.match_group_id " + ...
    "WHERE mg.analysis_run_id = cp.analysis_run_id " + ...
    "AND a.detection_id = cp.detection_a_id " + ...
    "AND b.detection_id = cp.detection_b_id)"), 0);
verifyFalse(testCase, any(result.edges.pairwise_match_type == "no_group_materialized"));

clear cleanup
end

function testComponentShapesStayDistinguishable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planAgreement(fixture, "agree-v1", fixture.pairwise);

verifyEqual(testCase, result.group_count, 5);
verifyEqual(testCase, result.singleton_count, 1);

% A complete triangle: three extractors, all three unordered pairs supported,
% nothing ambiguous.
triangle = groupFor(result, "fixture_deepsqueak_social_v1#1|" + ...
    "fixture_mupet_social_v1#1|fixture_usvseg_social_v1#1");
verifyEqual(testCase, triangle.member_count, 3);
verifyEqual(testCase, triangle.extractor_count, 3);
verifyEqual(testCase, triangle.support_edge_count, 3);
verifyEqual(testCase, triangle.supported_pair_labels, ...
    "DeepSqueak|MUPET;DeepSqueak|USVSEG;MUPET|USVSEG");
verifyEqual(testCase, triangle.unsupported_pair_labels, "");
verifyEqual(testCase, triangle.ambiguous_source_topologies, "");
verifyTrue(testCase, triangle.pair_support_complete);
verifyFalse(testCase, triangle.is_singleton);

% Complete at extractor-pair level and still ambiguous, which is the case a
% single flag would destroy. One long DeepSqueak call, two MUPET syllables, two
% USVSEG syllables: every pair is supported, and two of the three source
% analyses resolved one-to-many.
split = groupFor(result, "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#3|fixture_mupet_social_v1#4|" + ...
    "fixture_usvseg_social_v1#4|fixture_usvseg_social_v1#5");
verifyEqual(testCase, split.member_count, 5);
verifyEqual(testCase, split.extractor_count, 3);
verifyEqual(testCase, split.support_edge_count, 6);
verifyEqual(testCase, split.supported_pair_labels, ...
    "DeepSqueak|MUPET;DeepSqueak|USVSEG;MUPET|USVSEG");
verifyTrue(testCase, split.pair_support_complete);
verifyEqual(testCase, split.ambiguous_source_topologies, "one_to_many");

% Support is summarized per extractor pair, never by raw edge count: this
% component has six edges and three supported pairs.
verifyNotEqual(testCase, split.support_edge_count, ...
    numel(split.supported_pair_labels));

% Pair-only components: two extractors corroborate, the third reported nothing
% there. Complete for the pair it has, and not a three-extractor claim.
pairOnly = groupFor(result, ...
    "fixture_deepsqueak_social_v1#2|fixture_usvseg_social_v1#2");
verifyEqual(testCase, pairOnly.member_count, 2);
verifyEqual(testCase, pairOnly.extractor_count, 2);
verifyEqual(testCase, pairOnly.supported_pair_labels, "DeepSqueak|USVSEG");
verifyTrue(testCase, pairOnly.pair_support_complete);
verifyFalse(testCase, pairOnly.is_singleton);

% Single-extractor evidence survives as a group with no edges at all.
singleton = groupFor(result, "fixture_usvseg_social_v1#6");
verifyEqual(testCase, singleton.member_count, 1);
verifyEqual(testCase, singleton.extractor_count, 1);
verifyEqual(testCase, singleton.support_edge_count, 0);
verifyEqual(testCase, singleton.supported_pair_labels, "");
verifyEqual(testCase, singleton.unsupported_pair_labels, "");
verifyTrue(testCase, singleton.is_singleton);
verifyFalse(testCase, singleton.pair_support_complete);

% Members partition the node set exactly once.
verifyEqual(testCase, height(result.members), result.node_count);
verifyEqual(testCase, numel(unique(result.members.detection_id)), result.node_count);
verifyEqual(testCase, sum(result.groups.member_count), result.node_count);
verifyEqual(testCase, sum(result.groups.support_edge_count), result.edge_count);

clear cleanup
end

function testNoTransitiveEdgeIsInvented(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planAgreement(fixture, "agree-v1", fixture.pairwise);

% The five-member split component would need ten edges to be a clique over its
% members. It has six, and composition adds none of the missing four.
split = groupFor(result, "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#3|fixture_mupet_social_v1#4|" + ...
    "fixture_usvseg_social_v1#4|fixture_usvseg_social_v1#5");
verifyEqual(testCase, split.support_edge_count, 6);
verifyEqual(testCase, split.member_count * (split.member_count - 1) / 2, 10);

% Specifically, MUPET syllable 3 never gained an edge to USVSEG syllable 5
% despite both sitting in the component through the DeepSqueak call.
edges = componentEdges(result, split.component_ordinal);
verifyFalse(testCase, any(edges.selector_pair == ...
    "fixture_mupet_social_v1#3~fixture_usvseg_social_v1#5"));
verifyFalse(testCase, any(edges.selector_pair == ...
    "fixture_mupet_social_v1#4~fixture_usvseg_social_v1#4"));

% And every edge in the whole plan is a real stored candidate row.
verifyTrue(testCase, all(ismember(result.edges.candidate_pair_id, ...
    candidatePairIds(fixture, fixture.pairwise))));

clear cleanup
end

% ------------------------------------------------------------- persistence ---

function testApplyPersistsComponentsMembersAndExactEdges(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = applyAgreement(fixture, "agree-v1", fixture.pairwise);
conn = fixture.conn;

verifyEqual(testCase, result.status, "committed");
verifyFalse(testCase, result.composition_pending);
verifyEqual(testCase, result.applied_counts.agreement_groups, 5);
verifyEqual(testCase, result.applied_counts.agreement_group_members, 13);
verifyEqual(testCase, result.applied_counts.agreement_supporting_edges, 11);

% The run is completed only now that its components exist.
run = fetch(conn, "SELECT status, IFNULL(notes,'') AS notes FROM analysis_runs " + ...
    "WHERE run_key = 'agree-v1'");
verifyEqual(testCase, string(run.status(1)), "completed");
verifySubstring(testCase, string(run.notes(1)), ...
    "component_rule=connected_components_over_supporting_edges");
verifyFalse(testCase, contains(string(run.notes(1)), "composition_pending=true"));

% Stored groups carry identity and the derivation rule, and nothing summarising.
groups = fetch(conn, "SELECT group_key, derivation_method " + ...
    "FROM agreement_groups ORDER BY group_key");
verifyEqual(testCase, height(groups), 5);
verifyEqual(testCase, unique(string(groups.derivation_method)), ...
    "connected_components_over_supporting_edges");
% No note is written on a group at all. Identity is group_key, and a note is
% exactly where a stored summary would creep in unnoticed.
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM agreement_groups " + ...
    "WHERE notes IS NOT NULL AND notes <> ''"), 0);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n " + ...
    "FROM agreement_supporting_edges WHERE notes IS NOT NULL AND notes <> ''"), 0);

% Members are native detections; edges are exact candidate pairs.
verifyEqual(testCase, countOf(conn, "agreement_group_members"), 13);
verifyEqual(testCase, countOf(conn, "agreement_supporting_edges"), 11);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n " + ...
    "FROM agreement_supporting_edges ase " + ...
    "JOIN candidate_pairs cp ON cp.candidate_pair_id = ase.candidate_pair_id"), 11);

% Every stored edge traces back to its pairwise analysis and that analysis's
% versioned matching specification.
trace = fetch(conn, "SELECT DISTINCT ar.run_key, cp.profile_key, " + ...
    "cpv.version_label, cpv.checksum_sha256 " + ...
    "FROM agreement_supporting_edges ase " + ...
    "JOIN candidate_pairs pair ON pair.candidate_pair_id = ase.candidate_pair_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = pair.analysis_run_id " + ...
    "JOIN analysis_run_profiles arp ON arp.analysis_run_id = ar.analysis_run_id " + ...
    "AND arp.assignment_role = 'matching_spec' " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id ORDER BY ar.run_key");
verifyEqual(testCase, string(trace.run_key), ...
    ["m_ds_mupet"; "m_ds_usvseg"; "m_mupet_usvseg"]);
verifyEqual(testCase, unique(string(trace.profile_key)), ...
    "vawlume.matching.prototype.v1");
verifyEqual(testCase, unique(string(trace.version_label)), "0.1.0");
verifyEqual(testCase, numel(unique(string(trace.checksum_sha256))), 1);

% Native detections and pairwise evidence are untouched by composition.
verifyEqual(testCase, countOf(conn, "detections"), 14);
verifyEqual(testCase, countOf(conn, "candidate_pairs"), 14);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testRerunReusesComponentsAndChangedEvidenceConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = applyAgreement(fixture, "agree-v1", fixture.pairwise);
after = counts(fixture.conn);

% Identity is the stored group_key, so a rerun in a different source order
% resolves to the same components and writes nothing.
second = applyAgreement(fixture, "agree-v1", flip(fixture.pairwise));
verifyEqual(testCase, second.status, "reused");
verifyFalse(testCase, second.composition_pending);
verifyEqual(testCase, second.applied_counts.agreement_groups, 0);
verifyEqual(testCase, second.applied_counts.reused_agreement_groups, 5);
verifyEqual(testCase, second.applied_counts.reused_agreement_group_members, 13);
verifyEqual(testCase, second.applied_counts.reused_agreement_supporting_edges, 11);
verifyEqual(testCase, counts(fixture.conn), after);
verifyEqual(testCase, second.analysis.analysis_run_id, first.analysis.analysis_run_id);

% Removing a stored supporting edge makes the derived content disagree with the
% evidence, and that is a conflict rather than a silent repair.
execute(fixture.conn, "DELETE FROM agreement_supporting_edges " + ...
    "WHERE candidate_pair_id = (SELECT MIN(candidate_pair_id) " + ...
    "FROM agreement_supporting_edges)");
conflicted = planAgreement(fixture, "agree-v1", fixture.pairwise);
verifyEqual(testCase, conflicted.status, "conflict");
verifyTrue(testCase, any(contains(conflicted.conflicts, "supporting-edge count differs")));
attempted = applyAgreement(fixture, "agree-v1", fixture.pairwise);
verifyEqual(testCase, attempted.status, "conflict");
verifyFalse(testCase, attempted.committed);

clear cleanup
end

function testComposingIntoAPendingBoundaryCompletesItRatherThanDuplicating(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
conn = fixture.conn;

% Simulate the provenance-only boundary an earlier pass applied: the analysis
% run, its policy, inputs, and lineage exist, with status 'started' and no
% components. Composition must complete that run, not create a second one.
boundary = applyAgreement(fixture, "agree-v1", fixture.pairwise);
execute(conn, "DELETE FROM agreement_supporting_edges");
execute(conn, "DELETE FROM agreement_group_members");
execute(conn, "DELETE FROM agreement_groups");
execute(conn, "UPDATE analysis_runs SET status = 'started' " + ...
    "WHERE analysis_run_id = " + string(boundary.analysis.analysis_run_id));

pending = planAgreement(fixture, "agree-v1", fixture.pairwise);
verifyFalse(testCase, pending.has_conflicts);
verifyEqual(testCase, pending.analysis.action, "reuse");
verifyEqual(testCase, pending.analysis.graph_action, "create");
verifyTrue(testCase, pending.composition_pending);

completed = applyAgreement(fixture, "agree-v1", fixture.pairwise);
verifyEqual(testCase, completed.status, "committed");
verifyEqual(testCase, completed.analysis.analysis_run_id, ...
    boundary.analysis.analysis_run_id);
verifyEqual(testCase, completed.applied_counts.analysis_runs, 0);
verifyEqual(testCase, completed.applied_counts.reused_analysis_runs, 1);
verifyEqual(testCase, completed.applied_counts.agreement_groups, 5);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM analysis_runs " + ...
    "WHERE run_type = 'multi_extractor_agreement'"), 1);
verifyEqual(testCase, textOf(conn, "SELECT status FROM analysis_runs " + ...
    "WHERE run_key = 'agree-v1'"), "completed");

clear cleanup
end

% ------------------------------------- the source universe decides the shape ---

function testStricterSourceSpecificationYieldsTheOpenChainCase(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
strictKeys = applyStrictPairwise(fixture);
result = applyAgreement(fixture, "agree-strict", strictKeys);

% A higher temporal floor in the *matching* specification removes candidate
% rows, so the composed shapes change. The agreement layer applied no threshold
% of its own; it composed the universe those source analyses defined.
verifyEqual(testCase, result.node_count, 13);
verifyEqual(testCase, result.edge_count, 8);
verifyEqual(testCase, result.group_count, 6);

% The open chain: three extractors in one component, two of the three unordered
% pairs supported, and every present link unambiguous. Partial support and
% ambiguity are different dimensions, and this row has one without the other.
chain = groupFor(result, "fixture_deepsqueak_social_v1#3|" + ...
    "fixture_mupet_social_v1#4|fixture_usvseg_social_v1#5");
verifyEqual(testCase, chain.member_count, 3);
verifyEqual(testCase, chain.extractor_count, 3);
verifyEqual(testCase, chain.support_edge_count, 2);
verifyEqual(testCase, chain.supported_pair_labels, ...
    "DeepSqueak|USVSEG;MUPET|USVSEG");
verifyEqual(testCase, chain.unsupported_pair_labels, "DeepSqueak|MUPET");
verifyFalse(testCase, chain.pair_support_complete);
verifyEqual(testCase, chain.ambiguous_source_topologies, "");
verifyFalse(testCase, chain.is_singleton);

% The missing DeepSqueak/MUPET link is genuinely absent, not stored as an edge.
edges = componentEdges(result, chain.component_ordinal);
verifyFalse(testCase, any(edges.pair_label == "DeepSqueak|MUPET"));

% The triangle at the other locus survives the stricter floor unchanged, so the
% difference is attributable to the evidence rather than to the composition.
triangle = groupFor(result, "fixture_deepsqueak_social_v1#1|" + ...
    "fixture_mupet_social_v1#1|fixture_usvseg_social_v1#1");
verifyEqual(testCase, triangle.support_edge_count, 3);
verifyTrue(testCase, triangle.pair_support_complete);

% Both agreement runs coexist, each with its own lineage and components.
applyAgreement(fixture, "agree-v1", fixture.pairwise);
verifyEqual(testCase, scalar(fixture.conn, "SELECT COUNT(*) AS n " + ...
    "FROM analysis_runs WHERE run_type = 'multi_extractor_agreement'"), 2);
verifyEqual(testCase, countOf(fixture.conn, "agreement_groups"), 11);
verifyEqual(testCase, countOf(fixture.conn, "agreement_supporting_edges"), 19);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testIncoherentSourceEvidenceIsRefusedRatherThanComposed(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
conn = fixture.conn;

% The eligibility rule assumes every stored candidate edge participates in its
% own analysis's pairwise partition. Break that and composition refuses, which
% is what a future rejected-candidate state would trip.
execute(conn, "DELETE FROM match_group_members WHERE detection_id = " + ...
    "(SELECT detection_a_id FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "WHERE ar.run_key = 'm_ds_mupet' LIMIT 1) " + ...
    "AND match_group_id IN (SELECT match_group_id FROM match_groups mg " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "WHERE ar.run_key = 'm_ds_mupet')");
verifyError(testCase, @() planAgreement(fixture, "agree-broken", fixture.pairwise), ...
    "vawlume:agreement:EdgeOutsidePairwisePartition");

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function result = planAgreement(fixture, runKey, sources)
result = vawlume.agreement.compose(fixture.conn, socialRef(), sources, ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root);
end

function result = applyAgreement(fixture, runKey, sources)
result = vawlume.agreement.compose(fixture.conn, socialRef(), sources, ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root, Apply=true);
end

function ref = socialRef()
ref = struct(project_key="phase1_synthetic_fixture", ...
    source_relative_path="synthetic/recordings/session_social_dyad_01.wav");
end

function row = groupFor(result, groupKey)
selected = result.groups.group_key == groupKey;
assert(nnz(selected) == 1, "Expected exactly one component '" + groupKey + "'.");
row = table2struct(result.groups(selected, :));
end

function edges = componentEdges(result, componentOrdinal)
edges = result.support_edges(result.support_edges.component_ordinal == ...
    componentOrdinal, :);
lookup = dictionary(result.nodes.detection_id, result.nodes.selector);
edges.selector_pair = strings(height(edges), 1);
for index = 1:height(edges)
    endpoints = sort([lookup(edges.node_a(index)), lookup(edges.node_b(index))]);
    edges.selector_pair(index) = endpoints(1) + "~" + endpoints(2);
end
end

function ids = candidatePairIds(fixture, runKeys)
list = "('" + strjoin(runKeys(:)', "','") + "')";
rows = fetch(fixture.conn, "SELECT cp.candidate_pair_id FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "WHERE ar.run_key IN " + list + " ORDER BY cp.candidate_pair_id");
ids = double(rows.candidate_pair_id);
end

function keys = applyStrictPairwise(fixture)
%APPLYSTRICTPAIRWISE The same three pairs under a higher temporal floor.
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

function value = counts(conn)
names = ["analysis_runs", "analysis_run_sources", "agreement_groups", ...
    "agreement_group_members", "agreement_supporting_edges", ...
    "candidate_pairs", "match_groups", "detections"];
value = struct();
for name = names
    value.(name) = countOf(conn, name);
end
end

function value = countOf(conn, tableName)
value = scalar(conn, "SELECT COUNT(*) AS n FROM " + tableName);
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function value = textOf(conn, sql)
rows = fetch(conn, sql);
column = rows.(rows.Properties.VariableNames{1});
if iscell(column)
    value = string(column{1});
else
    value = string(column(1));
end
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "composition.sqlite");
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
    ref = struct(project_key="phase1_synthetic_fixture", ...
        source_relative_path="synthetic/recordings/session_social_dyad_01.wav");
    pairs = { ...
        {"m_ds_mupet", "fixture_deepsqueak_social_v1", "fixture_mupet_social_v1"}, ...
        {"m_ds_usvseg", "fixture_deepsqueak_social_v1", "fixture_usvseg_social_v1"}, ...
        {"m_mupet_usvseg", "fixture_mupet_social_v1", "fixture_usvseg_social_v1"}};
    for index = 1:numel(pairs)
        spec = pairs{index};
        vawlume.matching.compare(conn, ref, ...
            struct(run_a=spec{2}, run_b=spec{3}), struct(run_key=spec{1}), ...
            RepoRoot=repoRoot, Apply=true);
    end
    delete(closer);
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
