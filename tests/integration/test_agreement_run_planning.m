function tests = test_agreement_run_planning
%TEST_AGREEMENT_RUN_PLANNING The arbitrary-N agreement analysis boundary.
%
% vawlume.agreement.compose takes source pairwise analyses, not runs. This suite
% covers the analysis boundary half: that the sources form a composable set, that
% the derived run's identity and many-parent lineage are right, and that the
% policy and inputs are linked under their own roles.
%
% What gets composed from those sources, and the component shapes it produces,
% belong to test_agreement_composition.
%
% The compatibility rule this suite holds hardest is complete pairwise coverage.
% With a pair missing, an absent supporting edge in a later composition could not
% be distinguished from a pair that was never assessed, so the set is refused
% rather than composed into an unreadable result.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------------- planning ---

function testPlanNormalizesSourcesAndReportsCoverageWithoutWriting(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = counts(fixture.conn);

% Source order carries no meaning, so the plan normalizes it. The same three
% analyses in a different order produce the same canonical plan.
forward = planAgreement(fixture, "agree-v1", fixture.pairwise);
shuffled = planAgreement(fixture, "agree-v1", flip(fixture.pairwise));

verifyEqual(testCase, forward.status, "planned");
verifyFalse(testCase, forward.committed);
verifyFalse(testCase, forward.has_conflicts);
% A plan has composed nothing into the database yet, whatever it computed.
verifyTrue(testCase, forward.composition_pending);
verifyEqual(testCase, forward.sources.run_key, shuffled.sources.run_key);
verifyEqual(testCase, forward.sources.source_ordinal, [1; 2; 3]);
verifyEqual(testCase, forward.sources.run_key, ...
    ["m_ds_mupet"; "m_ds_usvseg"; "m_mupet_usvseg"]);
verifyEqual(testCase, forward.sources.pair_label, ...
    ["DeepSqueak|MUPET"; "DeepSqueak|USVSEG"; "MUPET|USVSEG"]);

% Participating extraction runs are derived from the sources, one per extractor.
verifyEqual(testCase, forward.extractor_runs.extractor_name, ...
    ["DeepSqueak"; "MUPET"; "USVSEG"]);
verifyEqual(testCase, forward.extractor_runs.run_key, [ ...
    "fixture_deepsqueak_social_v1"; "fixture_mupet_social_v1"; ...
    "fixture_usvseg_social_v1"]);

% Coverage is reported as the exact pair set, not just a count.
verifyEqual(testCase, forward.coverage.participating_extractor_runs, 3);
verifyEqual(testCase, forward.coverage.expected_pairs, 3);
verifyEqual(testCase, forward.coverage.observed_pairs, 3);
verifyTrue(testCase, forward.coverage.complete);
verifyEqual(testCase, forward.coverage.pair_labels, ...
    ["DeepSqueak|MUPET"; "DeepSqueak|USVSEG"; "MUPET|USVSEG"]);
verifyEqual(testCase, forward.coverage.rule, "complete_unordered_pair_set");

% Every source cites the one matching specification version, which is what makes
% their candidate universes comparable.
verifyEqual(testCase, numel(unique(forward.sources.matching_specification_version_id)), 1);
verifyEqual(testCase, forward.coverage.matching_specification_version_id, ...
    forward.sources.matching_specification_version_id(1));

% The agreement policy governs composition and declares no threshold of its own.
verifyEqual(testCase, forward.specification.profile_key, ...
    "vawlume.agreement.multi_extractor.v0_1");
verifyEqual(testCase, forward.specification.assignment_role, ...
    "multi_extractor_agreement_spec");
verifyEqual(testCase, strlength(forward.specification.checksum_sha256), 64);
verifyEqual(testCase, forward.specification.component_rule, ...
    "connected_components_over_supporting_edges");
verifyTrue(testCase, forward.specification.singleton_inclusion);
verifyFalse(testCase, forward.specification.feature_support_is_admission_criterion);
verifyEqual(testCase, forward.specification.clique_completeness, "reported_not_required");
verifyEqual(testCase, forward.analysis.run_type, "multi_extractor_agreement");
verifyEqual(testCase, forward.analysis.action, "create");

verifyEqual(testCase, counts(fixture.conn), before);

clear cleanup
end

% ------------------------------------------------------------ persistence ---

function testApplyPersistsPolicyInputsAndEveryPairwiseParent(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = applyAgreement(fixture, "agree-v1", fixture.pairwise);
conn = fixture.conn;

verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.applied_counts.config_profiles, 1);
verifyEqual(testCase, result.applied_counts.config_profile_versions, 1);
verifyEqual(testCase, result.applied_counts.analysis_runs, 1);
verifyEqual(testCase, result.applied_counts.analysis_run_profiles, 1);
verifyEqual(testCase, result.applied_counts.analysis_run_extraction_inputs, 3);
verifyEqual(testCase, result.applied_counts.analysis_run_sources, 3);

% Composition happens in the same call and is asserted in detail elsewhere.
% What matters here is that the boundary and the components are one transaction:
% the run is completed only because its components exist.
verifyEqual(testCase, result.applied_counts.agreement_groups, 5);
verifyEqual(testCase, result.applied_counts.agreement_group_members, 13);
verifyEqual(testCase, result.applied_counts.agreement_supporting_edges, 11);
verifyFalse(testCase, result.composition_pending);

run = fetch(conn, "SELECT run_type, status, IFNULL(run_label,'') AS run_label, " + ...
    "IFNULL(parent_analysis_run_id,-1) AS parent, IFNULL(notes,'') AS notes " + ...
    "FROM analysis_runs WHERE run_key = 'agree-v1'");
verifyEqual(testCase, height(run), 1);
verifyEqual(testCase, string(run.run_type(1)), "multi_extractor_agreement");
verifyEqual(testCase, string(run.status(1)), "completed");
verifyEqual(testCase, string(run.run_label(1)), "Three-extractor agreement");
% Many parents cannot live in one parent column, so that column stays NULL.
verifyEqual(testCase, double(run.parent(1)), -1);
verifySubstring(testCase, string(run.notes(1)), ...
    "multi_extractor_agreement_composition@0.1.0");
verifySubstring(testCase, string(run.notes(1)), ...
    "component_rule=connected_components_over_supporting_edges");

% Every pairwise parent is recorded, in canonical order, through the lineage
% relation rather than by being rewritten as a child.
lineage = fetch(conn, "SELECT source.run_key, ars.dependency_role, " + ...
    "IFNULL(ars.notes,'') AS notes FROM analysis_run_sources ars " + ...
    "JOIN analysis_runs child ON child.analysis_run_id = ars.analysis_run_id " + ...
    "JOIN analysis_runs source ON source.analysis_run_id = ars.source_analysis_run_id " + ...
    "WHERE child.run_key = 'agree-v1' ORDER BY source.run_key");
verifyEqual(testCase, string(lineage.run_key), ...
    ["m_ds_mupet"; "m_ds_usvseg"; "m_mupet_usvseg"]);
verifyEqual(testCase, unique(string(lineage.dependency_role)), "pairwise_source");
verifySubstring(testCase, string(lineage.notes(1)), "DeepSqueak|MUPET");

inputs = fetch(conn, "SELECT er.run_key, arei.input_role " + ...
    "FROM analysis_run_extraction_inputs arei " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = arei.extraction_run_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = arei.analysis_run_id " + ...
    "WHERE ar.run_key = 'agree-v1' ORDER BY er.run_key");
verifyEqual(testCase, string(inputs.run_key), [ ...
    "fixture_deepsqueak_social_v1"; "fixture_mupet_social_v1"; ...
    "fixture_usvseg_social_v1"]);
verifyEqual(testCase, unique(string(inputs.input_role)), "agreement_input");

% The policy is linked under its own role. 'agreement_spec' already means the
% matching specification of a pairwise agreement-statistics run.
profile = fetch(conn, "SELECT cp.profile_key, cp.profile_kind, cpv.version_label, " + ...
    "cpv.content_uri, cpv.checksum_sha256, arp.assignment_role " + ...
    "FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = arp.analysis_run_id " + ...
    "WHERE ar.run_key = 'agree-v1'");
verifyEqual(testCase, height(profile), 1);
verifyEqual(testCase, string(profile.assignment_role(1)), ...
    "multi_extractor_agreement_spec");
verifyEqual(testCase, string(profile.profile_key(1)), ...
    "vawlume.agreement.multi_extractor.v0_1");
verifyEqual(testCase, string(profile.profile_kind(1)), "consilience_policy");
verifyEqual(testCase, string(profile.content_uri(1)), ...
    "config/07_agreement_profiles/prototype_multi_extractor_agreement_spec.json");
verifyEqual(testCase, strlength(string(profile.checksum_sha256(1))), 64);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testSourcePairwiseEvidenceIsReadNeverRewritten(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = pairwiseState(fixture.conn);
beforeCounts = counts(fixture.conn);
applyAgreement(fixture, "agree-v1", fixture.pairwise);

% Composition consumes the pairwise analyses as evidence. Their rows, status,
% notes, and their own empty parent column are untouched.
verifyEqual(testCase, pairwiseState(fixture.conn), before);
after = counts(fixture.conn);
verifyEqual(testCase, after.candidate_pairs, beforeCounts.candidate_pairs);
verifyEqual(testCase, after.match_groups, beforeCounts.match_groups);

% Exactly three parents, and the derived run is reachable from each source.
verifyEqual(testCase, countOf(fixture.conn, "analysis_run_sources"), 3);
derived = fetch(fixture.conn, "SELECT COUNT(DISTINCT ars.analysis_run_id) AS n " + ...
    "FROM analysis_run_sources ars " + ...
    "JOIN analysis_runs source ON source.analysis_run_id = ars.source_analysis_run_id " + ...
    "WHERE source.run_type = 'cross_extractor_matching'");
verifyEqual(testCase, double(derived.n(1)), 1);

clear cleanup
end

% --------------------------------------------------------------- identity ---

function testRerunWithIdenticalInputsReusesTheSameAnalysisIdentity(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
first = applyAgreement(fixture, "agree-v1", fixture.pairwise);
after = counts(fixture.conn);

second = applyAgreement(fixture, "agree-v1", flip(fixture.pairwise));
verifyEqual(testCase, second.status, "reused");
verifyTrue(testCase, second.committed);
verifyEqual(testCase, second.analysis.analysis_run_id, ...
    first.analysis.analysis_run_id);
verifyEqual(testCase, second.applied_counts.analysis_runs, 0);
verifyEqual(testCase, second.applied_counts.analysis_run_sources, 0);
verifyEqual(testCase, second.applied_counts.reused_analysis_runs, 1);
verifyEqual(testCase, second.applied_counts.reused_analysis_run_sources, 3);
verifyEqual(testCase, counts(fixture.conn), after);

clear cleanup
end

function testChangedPolicyOrSourceSetConflictsRatherThanRewriting(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAgreement(fixture, "agree-v1", fixture.pairwise);
after = counts(fixture.conn);

% Same profile version label, different file. The stored checksum is the
% authority, so this is a conflict rather than a silent redefinition.
variantPath = writeSpecVariant(fixture, "changed_policy.json", ...
    "recorded_per_edge_never_used_to_exclude", ...
    "recorded_per_edge_and_used_to_exclude_ambiguous_components");
changed = planAgreement(fixture, "agree-v1", fixture.pairwise, variantPath);
verifyEqual(testCase, changed.status, "conflict");
verifyTrue(testCase, changed.has_conflicts);
verifyTrue(testCase, any(contains(changed.conflicts, "checksum")));

% Apply on a conflicting plan reports the conflict and writes nothing, the same
% way the pairwise matcher does. It does not raise, and it does not overwrite.
attempted = applyAgreement(fixture, "agree-v1", fixture.pairwise, variantPath);
verifyEqual(testCase, attempted.status, "conflict");
verifyFalse(testCase, attempted.committed);
verifyEqual(testCase, counts(fixture.conn), after);

% A different but equally complete source set under the same run_key is also a
% conflict: the run identity includes which analyses it was composed from.
alternates = applyAlternatePairwise(fixture);
different = planAgreement(fixture, "agree-v1", alternates);
verifyEqual(testCase, different.status, "conflict");
verifyTrue(testCase, any(contains(different.conflicts, ...
    "different set of source pairwise analyses")));
blocked = applyAgreement(fixture, "agree-v1", alternates);
verifyEqual(testCase, blocked.status, "conflict");
verifyFalse(testCase, blocked.committed);
verifyEqual(testCase, countOf(fixture.conn, "analysis_run_sources"), 3);

% A second agreement run over the alternate set coexists with the first.
coexisting = applyAgreement(fixture, "agree-v2", alternates);
verifyEqual(testCase, coexisting.status, "committed");
verifyEqual(testCase, countOf(fixture.conn, "analysis_run_sources"), 6);
verifyEqual(testCase, counts(fixture.conn).analysis_runs, ...
    after.analysis_runs + 3 + 1);

clear cleanup
end

% ---------------------------------------------------------- compatibility ---

function testIncompatibleSourceSetsAreRejectedWithActionableIdentifiers(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = counts(fixture.conn);

% An unassessed pair must never masquerade as a missing supporting edge.
verifyError(testCase, @() planAgreement(fixture, "agree-partial", ...
    ["m_ds_mupet", "m_ds_usvseg"]), ...
    "vawlume:agreement:IncompletePairCoverage");
% Two extractors have exactly one unordered pair, so a single pairwise analysis
% is already a complete set. The degenerate N=2 case is legal rather than
% special-cased, and its composed result would simply be the pairwise partition.
degenerate = planAgreement(fixture, "agree-single", "m_ds_mupet");
verifyFalse(testCase, degenerate.has_conflicts);
verifyEqual(testCase, degenerate.coverage.participating_extractor_runs, 2);
verifyEqual(testCase, degenerate.coverage.expected_pairs, 1);
verifyEqual(testCase, degenerate.coverage.observed_pairs, 1);
verifyTrue(testCase, degenerate.coverage.complete);

verifyError(testCase, @() planAgreement(fixture, "agree-dup", ...
    ["m_ds_mupet", "m_ds_mupet", "m_ds_usvseg"]), ...
    "vawlume:agreement:DuplicateSourceAnalysis");
verifyError(testCase, @() planAgreement(fixture, "agree-empty", strings(0, 1)), ...
    "vawlume:agreement:SourcesInvalid");
verifyError(testCase, @() planAgreement(fixture, "agree-missing", ...
    ["m_ds_mupet", "m_ds_usvseg", "no_such_analysis"]), ...
    "vawlume:agreement:SourceAnalysisNotFound");

% A derived agreement run is not a pairwise source.
applyAgreement(fixture, "agree-v1", fixture.pairwise);
verifyError(testCase, @() planAgreement(fixture, "agree-nested", "agree-v1"), ...
    "vawlume:agreement:SourceRunTypeInvalid");

% An incomplete source analysis cannot be composed: its evidence may be partial.
execute(fixture.conn, "UPDATE analysis_runs SET status = 'failed' " + ...
    "WHERE run_key = 'm_ds_usvseg'");
verifyError(testCase, @() planAgreement(fixture, "agree-failed", fixture.pairwise), ...
    "vawlume:agreement:SourceAnalysisIncomplete");
execute(fixture.conn, "UPDATE analysis_runs SET status = 'completed' " + ...
    "WHERE run_key = 'm_ds_usvseg'");

% The recording is a caller assertion validated against the sources.
verifyError(testCase, @() vawlume.agreement.compose(fixture.conn, ...
    baselineRef(), fixture.pairwise, struct(run_key="agree-other-recording"), ...
    RepoRoot=fixture.repo_root), "vawlume:agreement:SourceRecordingMismatch");

verifyEqual(testCase, counts(fixture.conn).analysis_run_sources, ...
    before.analysis_run_sources + 3);

clear cleanup
end

function testExtractorAndSpecificationCompatibilityIsEnforced(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
conn = fixture.conn;

% A second DeepSqueak run on the same recording, paired with USVSEG. The set is
% pairwise-complete over four runs only if DeepSqueak may appear twice, and this
% Phase 1 path requires one run per extractor so that an unordered extractor
% pair names exactly one comparison.
secondDeepSqueak = insertSecondDeepSqueakRun(conn);
vawlume.matching.compare(conn, socialRef(), ...
    struct(run_a=secondDeepSqueak, run_b="fixture_usvseg_social_v1"), ...
    struct(run_key="m_ds2_usvseg"), RepoRoot=fixture.repo_root, Apply=true);
verifyError(testCase, @() planAgreement(fixture, "agree-two-ds", ...
    ["m_ds_mupet", "m_ds2_usvseg"]), "vawlume:agreement:RepeatedExtractor");

% A hand-written analysis comparing two runs of one extractor is refused even
% though the matcher would never have produced it.
sameExtractor = insertSameExtractorAnalysis(conn, secondDeepSqueak);
verifyError(testCase, @() planAgreement(fixture, "agree-same-extractor", ...
    sameExtractor), "vawlume:agreement:SameExtractorPair");

% Two analyses under different matching specification versions have different
% candidate universes, so a mixed-specification set is refused.
variantPath = writeMatchingSpecVariant(fixture);
vawlume.matching.compare(conn, socialRef(), ...
    struct(run_a="fixture_deepsqueak_social_v1", run_b="fixture_usvseg_social_v1"), ...
    struct(run_key="m_ds_usvseg_strict", profile_path=variantPath), ...
    RepoRoot=fixture.repo_root, Apply=true);
mixed = ["m_ds_mupet", "m_ds_usvseg_strict", "m_mupet_usvseg"];
verifyError(testCase, @() planAgreement(fixture, "agree-mixed-spec", mixed), ...
    "vawlume:agreement:SpecificationVersionMismatch");

% The same set under one specification is accepted, which shows the rejection
% was about specification identity and not about the analyses themselves.
accepted = planAgreement(fixture, "agree-uniform-spec", fixture.pairwise);
verifyFalse(testCase, accepted.has_conflicts);

clear cleanup
end

function testAgreementPolicyMayNotDeclareItsOwnThresholds(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The candidate universe is already bounded by each source analysis's versioned
% min_temporal_iou floor. A policy file that adds a threshold here would create a
% second authority that can silently re-filter that evidence.
withThreshold = writeSpecVariant(fixture, "with_threshold.json", ...
    """second_threshold_forbidden"": true", ...
    """second_threshold_forbidden"": true, ""min_temporal_iou"": 0.25");
verifyError(testCase, @() planAgreement(fixture, "agree-threshold", ...
    fixture.pairwise, withThreshold), ...
    "vawlume:agreement:SpecificationDeclaresThreshold");

% Nor may it turn feature support into an admission criterion.
gated = writeSpecVariant(fixture, "gated.json", ...
    """feature_support_is_admission_criterion"": false", ...
    """feature_support_is_admission_criterion"": true");
verifyError(testCase, @() planAgreement(fixture, "agree-gated", ...
    fixture.pairwise, gated), "vawlume:agreement:SpecificationInvalid");

% Nor may it relax the complete-coverage rule by renaming it.
relaxed = writeSpecVariant(fixture, "relaxed.json", ...
    """pairwise_coverage"": ""complete_unordered_pair_set""", ...
    """pairwise_coverage"": ""any_available_pairs""");
verifyError(testCase, @() planAgreement(fixture, "agree-relaxed", ...
    fixture.pairwise, relaxed), "vawlume:agreement:CoveragePolicyUnsupported");

missing = fullfile(fixture.scratch, "absent.json");
verifyError(testCase, @() planAgreement(fixture, "agree-absent", ...
    fixture.pairwise, missing), "vawlume:agreement:SpecificationNotFound");

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function result = planAgreement(fixture, runKey, sources, profilePath)
spec = struct(run_key=runKey);
if nargin >= 4
    spec.profile_path = profilePath;
end
result = vawlume.agreement.compose(fixture.conn, socialRef(), sources, spec, ...
    RepoRoot=fixture.repo_root);
end

function result = applyAgreement(fixture, runKey, sources, profilePath)
spec = struct(run_key=runKey, run_label="Three-extractor agreement");
if nargin >= 4
    spec.profile_path = profilePath;
end
result = vawlume.agreement.compose(fixture.conn, socialRef(), sources, spec, ...
    RepoRoot=fixture.repo_root, Apply=true);
end

function ref = socialRef()
ref = struct(project_key="phase1_synthetic_fixture", ...
    source_relative_path="synthetic/recordings/session_social_dyad_01.wav");
end

function ref = baselineRef()
ref = struct(project_key="phase1_synthetic_fixture", ...
    source_relative_path="synthetic/recordings/session_baseline_m01.wav");
end

function keys = applyAlternatePairwise(fixture)
%APPLYALTERNATEPAIRWISE A second, equally complete pairwise set over the same runs.
pairs = { ...
    {"m2_ds_mupet", "fixture_deepsqueak_social_v1", "fixture_mupet_social_v1"}, ...
    {"m2_ds_usvseg", "fixture_deepsqueak_social_v1", "fixture_usvseg_social_v1"}, ...
    {"m2_mupet_usvseg", "fixture_mupet_social_v1", "fixture_usvseg_social_v1"}};
keys = strings(numel(pairs), 1);
for index = 1:numel(pairs)
    spec = pairs{index};
    vawlume.matching.compare(fixture.conn, socialRef(), ...
        struct(run_a=spec{2}, run_b=spec{3}), struct(run_key=spec{1}), ...
        RepoRoot=fixture.repo_root, Apply=true);
    keys(index) = spec{1};
end
end

function runKey = insertSecondDeepSqueakRun(conn)
%INSERTSECONDDEEPSQUEAKRUN A legal second run of an extractor already present.
runKey = "fixture_deepsqueak_social_v2";
versionId = scalar(conn, "SELECT ev.extractor_version_id AS n " + ...
    "FROM extractor_versions ev JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE e.extractor_name = 'DeepSqueak'");
projectId = scalar(conn, "SELECT project_id AS n FROM projects " + ...
    "WHERE project_key = 'phase1_synthetic_fixture'");
recordingId = scalar(conn, "SELECT recording_id AS n FROM recordings " + ...
    "WHERE native_recording_id = 'REC_SOCIAL_DYAD_01'");
execute(conn, "INSERT INTO extraction_runs(project_id,extractor_version_id," + ...
    "run_key,status) VALUES(" + string(projectId) + "," + string(versionId) + ...
    ",'" + runKey + "','imported')");
runId = scalar(conn, "SELECT last_insert_rowid() AS n");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id,input_role) VALUES(" + string(runId) + "," + ...
    string(recordingId) + ",'source_audio')");
end

function runKey = insertSameExtractorAnalysis(conn, secondDeepSqueak)
%INSERTSAMEEXTRACTORANALYSIS An analysis the matcher would refuse to create.
runKey = "m_ds_ds";
projectId = scalar(conn, "SELECT project_id AS n FROM projects " + ...
    "WHERE project_key = 'phase1_synthetic_fixture'");
execute(conn, "INSERT INTO analysis_runs(project_id,run_type,run_key,status) " + ...
    "VALUES(" + string(projectId) + ",'cross_extractor_matching','" + ...
    runKey + "','completed')");
analysisRunId = scalar(conn, "SELECT last_insert_rowid() AS n");
first = scalar(conn, "SELECT extraction_run_id AS n FROM extraction_runs " + ...
    "WHERE run_key = 'fixture_deepsqueak_social_v1'");
second = scalar(conn, "SELECT extraction_run_id AS n FROM extraction_runs " + ...
    "WHERE run_key = '" + secondDeepSqueak + "'");
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
    "extraction_run_id,input_role) VALUES(" + string(analysisRunId) + "," + ...
    string(first) + ",'run_a'),(" + string(analysisRunId) + "," + ...
    string(second) + ",'run_b')");
profileVersionId = scalar(conn, "SELECT profile_version_id AS n " + ...
    "FROM analysis_run_profiles WHERE assignment_role = 'matching_spec' LIMIT 1");
execute(conn, "INSERT INTO analysis_run_profiles(analysis_run_id," + ...
    "profile_version_id,assignment_role) VALUES(" + string(analysisRunId) + "," + ...
    string(profileVersionId) + ",'matching_spec')");
end

function path = writeSpecVariant(fixture, name, oldText, newText)
source = fullfile(fixture.repo_root, "config", "07_agreement_profiles", ...
    "prototype_multi_extractor_agreement_spec.json");
text = string(fileread(source));
assert(contains(text, oldText), "Variant anchor not found: " + oldText);
path = fullfile(fixture.scratch, name);
writeText(path, replace(text, oldText, newText));
end

function path = writeMatchingSpecVariant(fixture)
%WRITEMATCHINGSPECVARIANT A distinct matching specification version.
source = fullfile(fixture.repo_root, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json");
text = string(fileread(source));
text = replace(text, """profile_version"": ""0.1.0""", """profile_version"": ""0.1.1""");
text = replace(text, """min_temporal_iou"": 0.10", """min_temporal_iou"": 0.25");
path = fullfile(fixture.scratch, "strict_matching_spec.json");
writeText(path, text);
end

function writeText(path, value)
fileId = fopen(path, "w");
assert(fileId >= 0);
closer = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", value);
delete(closer);
end

function value = counts(conn)
names = ["analysis_runs", "analysis_run_profiles", ...
    "analysis_run_extraction_inputs", "analysis_run_sources", ...
    "config_profiles", "config_profile_versions", "candidate_pairs", ...
    "match_groups", "agreement_groups", "agreement_group_members", ...
    "agreement_supporting_edges"];
value = struct();
for name = names
    value.(name) = countOf(conn, name);
end
end

function value = pairwiseState(conn)
%PAIRWISESTATE Everything about the source analyses that must not change.
rows = fetch(conn, "SELECT ar.run_key, ar.status, IFNULL(ar.notes,'') AS notes, " + ...
    "IFNULL(ar.parent_analysis_run_id,-1) AS parent, " + ...
    "(SELECT COUNT(*) FROM candidate_pairs cp WHERE cp.analysis_run_id = ar.analysis_run_id) AS candidates, " + ...
    "(SELECT COUNT(*) FROM match_groups mg WHERE mg.analysis_run_id = ar.analysis_run_id) AS groups, " + ...
    "(SELECT COUNT(*) FROM consensus_events ce WHERE ce.analysis_run_id = ar.analysis_run_id) AS consensus " + ...
    "FROM analysis_runs ar WHERE ar.run_type = 'cross_extractor_matching' " + ...
    "ORDER BY ar.run_key");
value = struct( ...
    run_key=string(rows.run_key), status=string(rows.status), ...
    notes=string(rows.notes), parent=double(rows.parent), ...
    candidates=double(rows.candidates), groups=double(rows.groups), ...
    consensus=double(rows.consensus));
end

function value = countOf(conn, tableName)
value = scalar(conn, "SELECT COUNT(*) AS n FROM " + tableName);
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE The three-extractor fixture with all three pairwise analyses applied.
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "agreement.sqlite");
copyfile(pairwiseTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    pairwise=["m_ds_mupet"; "m_ds_usvseg"; "m_mupet_usvseg"]);
end

function path = pairwiseTemplate(repoRoot)
%PAIRWISETEMPLATE Fixture plus the three pairwise analyses, built once.
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
