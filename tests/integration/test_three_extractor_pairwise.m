function tests = test_three_extractor_pairwise
%TEST_THREE_EXTRACTOR_PAIRWISE All three extractor pairs over one recording.
%
% The Phase 1 fixture now runs DeepSqueak, MUPET, and USVSEG on
% REC_SOCIAL_DYAD_01. This suite proves the claim that matters before any
% arbitrary-N agreement layer exists: a third extractor participates in the
% correspondence system as an ordinary pairwise peer.
%
% Every analysis here is produced by the existing public matcher, separately,
% for one unordered extractor pair at a time. Nothing in this suite asks
% vawlume.matching.compare to accept more than two runs, and it asserts that
% each analysis stays a two-run analysis.
%
% Detections are selected by extraction-run key plus native event id. Generated
% detection ids appear only where the schema's own ordering rule is under test.
tests = functiontests(localfunctions);
end

% ---------------------------------------------------- pairwise peer status ---

function testEveryUnorderedPairIsAnOrdinaryTwoRunAnalysis(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);

% One analysis per unordered pair, each of run_type cross_extractor_matching,
% each with exactly two ordered extraction inputs.
inputs = fetch(fixture.conn, ...
    "SELECT ar.run_key, arei.input_role, er.run_key AS extraction_run_key, " + ...
    "e.extractor_name FROM analysis_run_extraction_inputs arei " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = arei.analysis_run_id " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = arei.extraction_run_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE ar.run_key LIKE 'pair_%' ORDER BY ar.run_key, arei.input_role");
verifyEqual(testCase, height(inputs), 6);
verifyEqual(testCase, string(inputs.run_key), [ ...
    "pair_ds_mupet"; "pair_ds_mupet"; ...
    "pair_ds_usvseg"; "pair_ds_usvseg"; ...
    "pair_mupet_usvseg"; "pair_mupet_usvseg"]);
verifyEqual(testCase, string(inputs.input_role), repmat(["run_a"; "run_b"], 3, 1));
verifyEqual(testCase, string(inputs.extractor_name), [ ...
    "DeepSqueak"; "MUPET"; "DeepSqueak"; "USVSEG"; "MUPET"; "USVSEG"]);

% The three analyses cover all three unordered pairs exactly once.
verifyEqual(testCase, sort(pairLabels(inputs)), ...
    sort(["DeepSqueak|MUPET"; "DeepSqueak|USVSEG"; "MUPET|USVSEG"]));

% No matching analysis in the database has more than two extraction inputs,
% including the fixture's own stored DeepSqueak/MUPET analysis.
widest = fetch(fixture.conn, ...
    "SELECT MAX(input_count) AS n FROM (SELECT COUNT(*) AS input_count " + ...
    "FROM analysis_run_extraction_inputs arei " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = arei.analysis_run_id " + ...
    "WHERE ar.run_type = 'cross_extractor_matching' GROUP BY ar.analysis_run_id)");
verifyEqual(testCase, double(widest.n(1)), 2);

runTypes = fetch(fixture.conn, "SELECT DISTINCT run_type FROM analysis_runs " + ...
    "WHERE run_key LIKE 'pair_%'");
verifyEqual(testCase, string(runTypes.run_type), "cross_extractor_matching");
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testAllThreePairsShareOneVersionedSpecification(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
results = applyAllPairs(fixture);

% Each analysis records the threshold it used through the same checksum-bearing
% profile version. The threshold is never a matcher constant.
specs = fetch(fixture.conn, ...
    "SELECT ar.run_key, cp.profile_key, cp.profile_kind, cpv.version_label, " + ...
    "cpv.content_uri, cpv.checksum_sha256, arp.assignment_role " + ...
    "FROM analysis_run_profiles arp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = arp.analysis_run_id " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE ar.run_key LIKE 'pair_%' ORDER BY ar.run_key");
verifyEqual(testCase, height(specs), 3);
verifyEqual(testCase, unique(string(specs.assignment_role)), "matching_spec");
verifyEqual(testCase, unique(string(specs.profile_kind)), "consilience_policy");
verifyEqual(testCase, unique(string(specs.content_uri)), ...
    "config/05_matching_profiles/prototype_matching_consilience_spec.json");
verifyEqual(testCase, numel(unique(string(specs.checksum_sha256))), 1);
verifyTrue(testCase, all(strlength(string(specs.checksum_sha256)) == 64));

% One specification row is reused rather than duplicated per analysis.
verifyEqual(testCase, countWhere(fixture.conn, "config_profiles", ...
    "profile_kind = 'consilience_policy'"), 1);

for name = string(fieldnames(results))'
    verifyEqual(testCase, results.(name).min_temporal_iou, 0.10, AbsTol=1e-15);
end

clear cleanup
end

% -------------------------------------------------------- temporal evidence ---

function testCandidateEvidenceUsesTheFrozenTemporalFormulas(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
results = applyAllPairs(fixture);

% DeepSqueak/MUPET is unchanged by the arrival of a third extractor.
expectCandidates(testCase, fixture, results.ds_mupet, ...
    ["1|1", "3|3", "3|4"], ...
    [.046, .043, .046], ...
    [.046/.052, .43, .46], ...
    [.004, .002, .052], ...
    [.002, -.055, -.002], ...
    [-.002, -.057, -.054]);

% DeepSqueak/USVSEG. The 20 s DeepSqueak event that MUPET missed now has a
% counterpart, and the long call spans both USVSEG syllables.
expectCandidates(testCase, fixture, results.ds_usvseg, ...
    ["1|1", "2|2", "3|4", "3|5"], ...
    [.047, .039, .042, .049], ...
    [.047/.050, .039/.041, .42, .49], ...
    [.002, .001, .001, .050], ...
    [-.001, .001, -.057, -.001], ...
    [-.003, 0, -.058, -.051]);

% MUPET/USVSEG. Two syllable-level extractors agree one-to-one four times.
expectCandidates(testCase, fixture, results.mupet_usvseg, ...
    ["1|1", "2|3", "3|4", "4|5"], ...
    [.045, .034, .041, .046], ...
    [.045/.050, .034/.036, .041/.044, .046/.049], ...
    [-.002, .001, -.001, -.002], ...
    [-.003, .001, -.002, .001], ...
    [-.001, 0, -.001, .003]);

% Every candidate row keeps candidate_score identical to temporal_iou, is
% eligible under the one stated rule, and stores its detections in ascending
% detection_id order regardless of caller direction.
for name = string(fieldnames(results))'
    rows = results.(name).candidates;
    verifyEqual(testCase, rows.candidate_score, rows.temporal_iou, AbsTol=1e-15);
    verifyEqual(testCase, unique(rows.candidate_status), "eligible");
    verifyTrue(testCase, all(rows.detection_a_id < rows.detection_b_id));
    detail = jsondecode(rows.details_json(1));
    verifyEqual(testCase, string(detail.evidence_direction), "run_a_to_run_b");
    verifyEqual(testCase, string(detail.eligibility_rule), ...
        "positive_overlap_and_min_temporal_iou");
    verifyEqual(testCase, detail.min_temporal_iou, .10, AbsTol=1e-15);
end

clear cleanup
end

function testTopologyVocabularyIsUnchangedAcrossAllThreePairs(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
results = applyAllPairs(fixture);

verifyEqual(testCase, string(results.ds_mupet.groups.match_type), ...
    ["one_to_one"; "unmatched"; "one_to_many"; "unmatched"]);
verifyEqual(testCase, string(results.ds_usvseg.groups.match_type), ...
    ["one_to_one"; "one_to_one"; "one_to_many"; "unmatched"; "unmatched"]);
verifyEqual(testCase, string(results.mupet_usvseg.groups.match_type), ...
    ["one_to_one"; "one_to_one"; "one_to_one"; "one_to_one"; "unmatched"; "unmatched"]);

% Only the four existing topology names appear, and ambiguity status stays
% bound to topology exactly as before.
for name = string(fieldnames(results))'
    groups = results.(name).groups;
    verifyTrue(testCase, all(ismember(string(groups.match_type), ...
        ["one_to_one", "one_to_many", "many_to_one", "many_to_many", "unmatched"])));
    unambiguous = string(groups.match_type) == "one_to_one";
    verifyEqual(testCase, unique(string(groups.ambiguity_status(unambiguous))), ...
        "unambiguous");
    ambiguous = ismember(string(groups.match_type), ...
        ["one_to_many", "many_to_one", "many_to_many"]);
    if any(ambiguous)
        verifyEqual(testCase, unique(string(groups.ambiguity_status(ambiguous))), ...
            "ambiguous");
    end
    unmatched = string(groups.match_type) == "unmatched";
    verifyEqual(testCase, unique(string(groups.ambiguity_status(unmatched))), ...
        "unmatched");
end

% The 10 s locus converges in all three pairs: a one-to-one group holding
% exactly the two detections that pair compares.
verifyEqual(testCase, componentFor(fixture, "pair_ds_mupet", ...
    "fixture_deepsqueak_social_v1", "1"), ...
    "one_to_one:fixture_deepsqueak_social_v1#1,fixture_mupet_social_v1#1");
verifyEqual(testCase, componentFor(fixture, "pair_ds_usvseg", ...
    "fixture_deepsqueak_social_v1", "1"), ...
    "one_to_one:fixture_deepsqueak_social_v1#1,fixture_usvseg_social_v1#1");
verifyEqual(testCase, componentFor(fixture, "pair_mupet_usvseg", ...
    "fixture_mupet_social_v1", "1"), ...
    "one_to_one:fixture_mupet_social_v1#1,fixture_usvseg_social_v1#1");

% Partial support. MUPET event 3 and USVSEG event 5 sit inside the same long
% DeepSqueak call but never overlap each other, so that trio is supported by
% two of the three pairs rather than three.
verifyEqual(testCase, componentFor(fixture, "pair_mupet_usvseg", ...
    "fixture_mupet_social_v1", "3"), ...
    "one_to_one:fixture_mupet_social_v1#3,fixture_usvseg_social_v1#4");
verifyEqual(testCase, componentFor(fixture, "pair_ds_usvseg", ...
    "fixture_deepsqueak_social_v1", "3"), ...
    "one_to_many:fixture_deepsqueak_social_v1#3," + ...
    "fixture_usvseg_social_v1#4,fixture_usvseg_social_v1#5");
verifyEqual(testCase, componentFor(fixture, "pair_ds_mupet", ...
    "fixture_deepsqueak_social_v1", "3"), ...
    "one_to_many:fixture_deepsqueak_social_v1#3," + ...
    "fixture_mupet_social_v1#3,fixture_mupet_social_v1#4");

% Single-extractor evidence stays single-extractor evidence in both pairs that
% could have corroborated it, and is never promoted to a consensus event.
verifyEqual(testCase, componentFor(fixture, "pair_ds_usvseg", ...
    "fixture_usvseg_social_v1", "6"), ...
    "unmatched:fixture_usvseg_social_v1#6");
verifyEqual(testCase, componentFor(fixture, "pair_mupet_usvseg", ...
    "fixture_usvseg_social_v1", "6"), ...
    "unmatched:fixture_usvseg_social_v1#6");
verifyEqual(testCase, countWhere(fixture.conn, "consensus_events ce " + ...
    "JOIN match_groups mg ON mg.match_group_id = ce.match_group_id", ...
    "mg.match_type = 'unmatched'"), 0);

% Consensus derivation stays topology-driven: mean boundary for the
% unambiguous groups, union boundary for the ambiguity-preserving ones.
methods = fetch(fixture.conn, ...
    "SELECT mg.match_type, ce.derivation_method, COUNT(*) AS n " + ...
    "FROM consensus_events ce " + ...
    "JOIN match_groups mg ON mg.match_group_id = ce.match_group_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = ce.analysis_run_id " + ...
    "WHERE ar.run_key LIKE 'pair_%' GROUP BY mg.match_type, ce.derivation_method " + ...
    "ORDER BY mg.match_type");
verifyEqual(testCase, string(methods.match_type), ["one_to_many"; "one_to_one"]);
verifyEqual(testCase, string(methods.derivation_method), ...
    ["union_boundary_of_members"; "mean_boundary_of_members"]);
verifyEqual(testCase, double(methods.n), [2; 7]);

clear cleanup
end

% ------------------------------------------------------------ pair ordering ---

function testReversingPairOrderFlipsOnlySignedEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
forward = applyPair(fixture, "pair_ds_usvseg", dsRun(), usvsegRun());
reversed = applyPair(fixture, "reversed_ds_usvseg", usvsegRun(), dsRun());

% Symmetric quantities are untouched by direction.
verifyEqual(testCase, reversed.candidates.temporal_overlap_s, ...
    forward.candidates.temporal_overlap_s, AbsTol=1e-12);
verifyEqual(testCase, reversed.candidates.temporal_iou, ...
    forward.candidates.temporal_iou, AbsTol=1e-15);
verifyEqual(testCase, reversed.candidates.candidate_score, ...
    forward.candidates.candidate_score, AbsTol=1e-15);

% Signed B-minus-A evidence is exactly negated.
for name = ["onset_difference_s", "offset_difference_s", "duration_difference_s"]
    verifyEqual(testCase, reversed.candidates.(name), ...
        -forward.candidates.(name), AbsTol=1e-12);
end

% Schema-side detection ordering is independent of caller direction.
verifyEqual(testCase, reversed.candidates.detection_a_id, ...
    forward.candidates.detection_a_id);
verifyEqual(testCase, reversed.candidates.detection_b_id, ...
    forward.candidates.detection_b_id);

% The partition itself is direction-free; only the relative topology name
% changes, because run_a and run_b swapped sides.
verifyEqual(testCase, componentMemberSets(reversed), componentMemberSets(forward));
verifyEqual(testCase, string(reversed.groups.match_type), ...
    ["one_to_one"; "one_to_one"; "many_to_one"; "unmatched"; "unmatched"]);
verifyEqual(testCase, reversed.unmatched_counts, struct(run_a=2, run_b=0));
verifyEqual(testCase, forward.unmatched_counts, struct(run_a=0, run_b=2));

% Consensus geometry is identical, so reversal is a labelling change and not a
% different derived result.
verifyEqual(testCase, sort(reversed.consensus_events.start_time_s), ...
    sort(forward.consensus_events.start_time_s), AbsTol=1e-12);
verifyEqual(testCase, sort(reversed.consensus_events.end_time_s), ...
    sort(forward.consensus_events.end_time_s), AbsTol=1e-12);

clear cleanup
end

% ------------------------------------------------------------- edge scoping ---

function testCandidatesAndEdgesStayScopedToTheirProducingAnalysis(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);

% Each analysis owns its own candidate, group, member, and consensus rows.
scoped = fetch(fixture.conn, ...
    "SELECT ar.run_key, " + ...
    "(SELECT COUNT(*) FROM candidate_pairs cp WHERE cp.analysis_run_id = ar.analysis_run_id) AS candidates, " + ...
    "(SELECT COUNT(*) FROM match_groups mg WHERE mg.analysis_run_id = ar.analysis_run_id) AS groups, " + ...
    "(SELECT COUNT(*) FROM consensus_events ce WHERE ce.analysis_run_id = ar.analysis_run_id) AS consensus " + ...
    "FROM analysis_runs ar WHERE ar.run_type = 'cross_extractor_matching' " + ...
    "ORDER BY ar.run_key");
verifyEqual(testCase, string(scoped.run_key), [ ...
    "fixture_cross_extractor_matching_v1"; "pair_ds_mupet"; ...
    "pair_ds_usvseg"; "pair_mupet_usvseg"]);
verifyEqual(testCase, double(scoped.candidates), [3; 3; 4; 4]);
verifyEqual(testCase, double(scoped.groups), [4; 4; 5; 6]);
verifyEqual(testCase, double(scoped.consensus), [2; 2; 3; 4]);

% No candidate edge reaches outside the two extraction runs its own analysis
% declared as inputs.
leaked = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "JOIN detections d ON d.detection_id IN (cp.detection_a_id, cp.detection_b_id) " + ...
    "WHERE d.extraction_run_id NOT IN (" + ...
    "SELECT arei.extraction_run_id FROM analysis_run_extraction_inputs arei " + ...
    "WHERE arei.analysis_run_id = ar.analysis_run_id)");
verifyEqual(testCase, double(leaked.n(1)), 0);

% The same detection can belong to several analyses, and each membership stays
% inside its own analysis. The 10 s DeepSqueak call is in two of them.
memberships = fetch(fixture.conn, ...
    "SELECT ar.run_key FROM match_group_members mgm " + ...
    "JOIN match_groups mg ON mg.match_group_id = mgm.match_group_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "JOIN v_detection_core vc ON vc.detection_id = mgm.detection_id " + ...
    "WHERE vc.extraction_run_key = 'fixture_deepsqueak_social_v1' " + ...
    "AND vc.native_event_id = '1' AND ar.run_key LIKE 'pair_%' " + ...
    "ORDER BY ar.run_key");
verifyEqual(testCase, string(memberships.run_key), ["pair_ds_mupet"; "pair_ds_usvseg"]);

% Every match group and consensus event belongs to the same recording as its
% own members, and the stored fixture analysis is untouched by the new ones.
verifyEqual(testCase, countWhere(fixture.conn, "match_groups mg " + ...
    "JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id " + ...
    "JOIN detections d ON d.detection_id = mgm.detection_id", ...
    "d.recording_id <> mg.recording_id"), 0);
verifyEqual(testCase, countWhere(fixture.conn, "candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id", ...
    "ar.run_key = 'fixture_cross_extractor_matching_v1'"), 3);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ----------------------------------------------------- pairwise consilience ---

function testPairwiseConsilienceRunsWhereRelationshipsExist(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);

dsMupet = summarizePair(fixture, "pair_ds_mupet");
dsUsvseg = summarizePair(fixture, "pair_ds_usvseg");
mupetUsvseg = summarizePair(fixture, "pair_mupet_usvseg");

% Comparability comes from the registry, pair by pair. USVSEG exports no
% frequency extent, so it shares only the three timing classes and the central
% frequency class with each of the other two extractors.
verifyEqual(testCase, height(dsMupet.feature_pairs), 9);
verifyEqual(testCase, nnz(dsMupet.feature_pairs.consilience_eligible), 7);
verifyEqual(testCase, height(dsUsvseg.feature_pairs), 4);
verifyEqual(testCase, nnz(dsUsvseg.feature_pairs.consilience_eligible), 4);
verifyEqual(testCase, height(mupetUsvseg.feature_pairs), 4);
verifyEqual(testCase, nnz(mupetUsvseg.feature_pairs.consilience_eligible), 4);
for report = [dsUsvseg, mupetUsvseg]
    verifyEqual(testCase, sort(string(report.feature_pairs.equivalence_class)), sort([ ...
        "vocalization_duration"; "vocalization_end_time"; ...
        "vocalization_frequency_center"; "vocalization_start_time"]));
    verifyEqual(testCase, unique(string(report.feature_pairs.extractor_b_name)), "USVSEG");
end

% Each report keeps its own two denominators. There is no pooled three-run
% figure anywhere in these summaries.
verifyEqual(testCase, string(dsUsvseg.detection_agreement.extractor_name), ...
    ["DeepSqueak"; "USVSEG"]);
verifyEqual(testCase, dsUsvseg.detection_agreement.total_detections, [3; 6]);
verifyEqual(testCase, dsUsvseg.detection_agreement.unmatched_detections, [0; 2]);
verifyEqual(testCase, string(mupetUsvseg.detection_agreement.extractor_name), ...
    ["MUPET"; "USVSEG"]);
verifyEqual(testCase, mupetUsvseg.detection_agreement.total_detections, [4; 6]);
verifyEqual(testCase, mupetUsvseg.detection_agreement.in_one_to_one_groups, [4; 4]);
for report = [dsMupet, dsUsvseg, mupetUsvseg]
    verifyEqual(testCase, height(report.detection_agreement), 2);
    row = report.detection_agreement;
    verifyEqual(testCase, row.in_one_to_one_groups + row.in_ambiguous_groups + ...
        row.unmatched_detections, row.total_detections);
end

% Quantitative comparison stays restricted to unambiguous one-to-one groups:
% one eligible feature pair per group per report, ambiguous and unmatched
% groups excluded rather than averaged.
verifyEqual(testCase, height(dsUsvseg.feature_comparisons), 8);
verifyEqual(testCase, height(mupetUsvseg.feature_comparisons), 16);
verifyEqual(testCase, height(dsUsvseg.excluded_groups), 3);
verifyEqual(testCase, height(mupetUsvseg.excluded_groups), 2);
verifyTrue(testCase, any(contains(string(dsUsvseg.excluded_groups.reason), ...
    "not_computed_split_merge")));

% An honest consequence of USVSEG's export surface rather than a defect: with
% only one non-timing eligible feature pair, a USVSEG group cannot reach the
% specification's minimum supporting comparisons, so it stays temporally
% matched instead of being called feature supported.
verifyEqual(testCase, dsUsvseg.specification.minimum_supporting_comparisons, 2);
verifyEqual(testCase, statusCount(dsUsvseg, "temporally_matched"), 2);
verifyEqual(testCase, statusCount(dsUsvseg, "matched_feature_supported"), 0);
verifyEqual(testCase, statusCount(mupetUsvseg, "temporally_matched"), 4);
verifyEqual(testCase, statusCount(mupetUsvseg, "matched_feature_supported"), 0);
verifyEqual(testCase, statusCount(dsMupet, "matched_feature_supported"), 1);
verifyEqual(testCase, statusCount(dsUsvseg, "single_extractor"), 2);
verifyEqual(testCase, statusCount(dsUsvseg, "ambiguous_split_merge"), 1);
verifyEqual(testCase, statusCount(mupetUsvseg, "ambiguous_split_merge"), 0);

% Temporal agreement is read back from the stored pairwise candidate rows, not
% recomputed, and never spans two analyses.
verifyEqual(testCase, dsUsvseg.temporal_agreement.group_count, 2);
verifyEqual(testCase, mupetUsvseg.temporal_agreement.group_count, 4);
for report = [dsMupet, dsUsvseg, mupetUsvseg]
    verifySubstring(testCase, report.temporal_agreement.source, ...
        "stored candidate_pairs evidence");
end

clear cleanup
end

% -------------------------------------------------------- no N-run widening ---

function testMatcherStillRefusesAnythingButOneUnorderedPair(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% A run pair is two runs. A third selector is not an input the public matcher
% accepts, and offering one does not widen the analysis.
verifyError(testCase, @() applyRunPair(fixture, "three_runs", ...
    struct(run_a=dsRun(), run_c=usvsegRun())), ...
    "vawlume:matching:RunPairInvalid");
overreach = applyRunPair(fixture, "pair_with_extra_run", ...
    struct(run_a=dsRun(), run_b=mupetRun(), run_c=usvsegRun()));
verifyEqual(testCase, overreach.applied_counts.analysis_run_extraction_inputs, 2);
verifyEqual(testCase, overreach.candidate_count, 3);
verifyEqual(testCase, countWhere(fixture.conn, "candidate_pairs cp " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = cp.analysis_run_id " + ...
    "JOIN detections d ON d.detection_id IN (cp.detection_a_id, cp.detection_b_id) " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id", ...
    "ar.run_key = 'pair_with_extra_run' AND er.run_key = 'fixture_usvseg_social_v1'"), 0);

% The existing legality rules apply to the third extractor exactly as they do
% to the other two.
verifyError(testCase, @() applyPair(fixture, "same_run", usvsegRun(), usvsegRun()), ...
    "vawlume:matching:SameExtractionRun");
verifyError(testCase, @() applyPair(fixture, "cross_recording", ...
    "fixture_deepsqueak_baseline_v1", usvsegRun()), ...
    "vawlume:matching:RunRecordingMismatch");

% No group or consensus row in the database mixes three extractors, so nothing
% here quietly anticipates the arbitrary-N agreement layer.
applyAllPairs(fixture);
widest = fetch(fixture.conn, ...
    "SELECT MAX(extractor_count) AS n FROM (SELECT COUNT(DISTINCT vc.extractor_name) " + ...
    "AS extractor_count FROM match_group_members mgm " + ...
    "JOIN v_detection_core vc ON vc.detection_id = mgm.detection_id " + ...
    "GROUP BY mgm.match_group_id)");
verifyEqual(testCase, double(widest.n(1)), 2);

clear cleanup
end

% -------------------------------------------------- agreement test substrate ---

function testFixtureSelectorsSurviveIntoEveryPairwiseResult(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applyAllPairs(fixture);

% Extraction-run key plus native event id selects exactly one detection, for
% all three extractors, and reaches every pairwise result through joins alone.
selectors = [ ...
    "fixture_deepsqueak_social_v1", "1"; ...
    "fixture_deepsqueak_social_v1", "2"; ...
    "fixture_deepsqueak_social_v1", "3"; ...
    "fixture_mupet_social_v1", "1"; ...
    "fixture_mupet_social_v1", "2"; ...
    "fixture_mupet_social_v1", "3"; ...
    "fixture_mupet_social_v1", "4"; ...
    "fixture_usvseg_social_v1", "1"; ...
    "fixture_usvseg_social_v1", "2"; ...
    "fixture_usvseg_social_v1", "3"; ...
    "fixture_usvseg_social_v1", "4"; ...
    "fixture_usvseg_social_v1", "5"; ...
    "fixture_usvseg_social_v1", "6"];
for index = 1:height(selectors)
    verifyEqual(testCase, countWhere(fixture.conn, "v_detection_core vc", ...
        "vc.extraction_run_key = " + sqlText(selectors(index, 1)) + ...
        " AND vc.native_event_id = " + sqlText(selectors(index, 2))), 1, ...
        selectors(index, 1) + "#" + selectors(index, 2));
end

% Which pairwise analyses each fixture event participates in, keyed only by
% those selectors. This is the substrate a later agreement pass reads: the
% three-extractor convergence at 10 s, the two events only one pair
% corroborates, the split locus, and the USVSEG-unique event.
participation = fetch(fixture.conn, ...
    "SELECT vc.extraction_run_key || '#' || vc.native_event_id AS selector, " + ...
    "GROUP_CONCAT(ar.run_key, ',') AS analyses FROM match_group_members mgm " + ...
    "JOIN match_groups mg ON mg.match_group_id = mgm.match_group_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "JOIN v_detection_core vc ON vc.detection_id = mgm.detection_id " + ...
    "WHERE ar.run_key LIKE 'pair_%' " + ...
    "GROUP BY vc.extraction_run_key, vc.native_event_id " + ...
    "ORDER BY selector");
verifyEqual(testCase, height(participation), 13);
verifyEqual(testCase, string(participation.analyses( ...
    string(participation.selector) == "fixture_usvseg_social_v1#1")), ...
    "pair_ds_usvseg,pair_mupet_usvseg");
verifyEqual(testCase, string(participation.analyses( ...
    string(participation.selector) == "fixture_deepsqueak_social_v1#2")), ...
    "pair_ds_mupet,pair_ds_usvseg");

% Corroboration is countable per event without any new table: the number of
% cross-extractor groups a detection joins across the three pairwise analyses.
verifyEqual(testCase, corroborationCount(fixture, "fixture_deepsqueak_social_v1", "1"), 2);
verifyEqual(testCase, corroborationCount(fixture, "fixture_usvseg_social_v1", "1"), 2);
verifyEqual(testCase, corroborationCount(fixture, "fixture_deepsqueak_social_v1", "2"), 1);
verifyEqual(testCase, corroborationCount(fixture, "fixture_mupet_social_v1", "2"), 1);
verifyEqual(testCase, corroborationCount(fixture, "fixture_usvseg_social_v1", "6"), 0);

% Counting corroboration this way is not an agreement group, and this pass
% created no agreement layer to hold one. The only agreement table in the
% schema is still the pairwise, analysis-scoped one, and nothing wrote to it.
verifyEqual(testCase, countWhere(fixture.conn, "sqlite_master", ...
    "type = 'table' AND name LIKE '%agreement%'"), 1);
verifyEqual(testCase, countWhere(fixture.conn, "agreement_statistics", "1 = 1"), 0);

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function results = applyAllPairs(fixture)
results = struct();
results.ds_mupet = applyPair(fixture, "pair_ds_mupet", dsRun(), mupetRun());
results.ds_usvseg = applyPair(fixture, "pair_ds_usvseg", dsRun(), usvsegRun());
results.mupet_usvseg = applyPair(fixture, "pair_mupet_usvseg", mupetRun(), usvsegRun());
end

function result = applyPair(fixture, runKey, runA, runB)
result = applyRunPair(fixture, runKey, struct(run_a=runA, run_b=runB));
end

function result = applyRunPair(fixture, runKey, runPair)
result = vawlume.matching.compare(fixture.conn, recordingRef(), runPair, ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root, Apply=true);
end

function report = summarizePair(fixture, runKey)
report = vawlume.consilience.summarize(fixture.conn, struct(run_key=runKey), ...
    RepoRoot=fixture.repo_root);
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

function expectCandidates(testCase, fixture, result, selectorPairs, overlap, iou, ...
        onset, offset, duration)
%EXPECTCANDIDATES Assert one pair's candidate rows by run-scoped native ids.
verifyEqual(testCase, result.candidate_count, numel(selectorPairs));
verifyEqual(testCase, height(result.candidates), numel(selectorPairs));
verifyEqual(testCase, candidateSelectors(fixture, result), selectorPairs(:));
verifyEqual(testCase, result.candidates.temporal_overlap_s, overlap(:), AbsTol=1e-12);
verifyEqual(testCase, result.candidates.temporal_iou, iou(:), AbsTol=1e-12);
verifyEqual(testCase, result.candidates.onset_difference_s, onset(:), AbsTol=1e-12);
verifyEqual(testCase, result.candidates.offset_difference_s, offset(:), AbsTol=1e-12);
verifyEqual(testCase, result.candidates.duration_difference_s, duration(:), AbsTol=1e-12);
end

function values = candidateSelectors(fixture, result)
%CANDIDATESELECTORS Native run-A/run-B event ids for each candidate row.
lookup = nativeEventIds(fixture);
values = strings(height(result.candidates), 1);
for index = 1:height(result.candidates)
    values(index) = lookup(result.candidates.run_a_detection_id(index)) + "|" + ...
        lookup(result.candidates.run_b_detection_id(index));
end
end

function map = nativeEventIds(fixture)
%NATIVEEVENTIDS Detection id to native event id, so expectations read natively.
rows = fetch(fixture.conn, ...
    "SELECT detection_id, native_event_id FROM v_detection_core " + ...
    "WHERE project_key = 'phase1_synthetic_fixture'");
map = dictionary(double(rows.detection_id), string(rows.native_event_id));
end

function value = componentFor(fixture, analysisKey, runKey, nativeEventId)
%COMPONENTFOR Topology and native membership of one detection's match group.
rows = fetch(fixture.conn, ...
    "SELECT mg.match_type, member.extraction_run_key || '#' || " + ...
    "member.native_event_id AS selector FROM match_groups mg " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "JOIN match_group_members anchor ON anchor.match_group_id = mg.match_group_id " + ...
    "JOIN v_detection_core seed ON seed.detection_id = anchor.detection_id " + ...
    "JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id " + ...
    "JOIN v_detection_core member ON member.detection_id = mgm.detection_id " + ...
    "WHERE ar.run_key = " + sqlText(analysisKey) + ...
    " AND seed.extraction_run_key = " + sqlText(runKey) + ...
    " AND seed.native_event_id = " + sqlText(nativeEventId) + ...
    " ORDER BY selector");
if height(rows) == 0
    value = "";
    return
end
value = string(rows.match_type(1)) + ":" + ...
    strjoin(unique(string(rows.selector))', ",");
end

function value = corroborationCount(fixture, runKey, nativeEventId)
%CORROBORATIONCOUNT Cross-extractor groups this detection joins in the pairs.
value = countWhere(fixture.conn, ...
    "match_group_members mgm " + ...
    "JOIN match_groups mg ON mg.match_group_id = mgm.match_group_id " + ...
    "JOIN analysis_runs ar ON ar.analysis_run_id = mg.analysis_run_id " + ...
    "JOIN v_detection_core vc ON vc.detection_id = mgm.detection_id", ...
    "ar.run_key LIKE 'pair_%' AND mg.match_type <> 'unmatched' " + ...
    "AND vc.extraction_run_key = " + sqlText(runKey) + ...
    " AND vc.native_event_id = " + sqlText(nativeEventId));
end

function values = componentMemberSets(result)
values = strings(height(result.groups), 1);
for index = 1:height(result.groups)
    ids = sort(result.group_members.detection_id( ...
        result.group_members.component_ordinal == ...
        result.groups.component_ordinal(index)));
    values(index) = strjoin(string(ids'), ",");
end
values = sort(values);
end

function value = statusCount(report, status)
counts = report.consilience_status_counts;
selected = string(counts.status) == status;
value = double(counts.group_count(selected));
end

function value = countWhere(conn, fromClause, predicate)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + fromClause + ...
    " WHERE " + predicate);
value = double(rows.n(1));
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "three-extractor.sqlite");
% The Phase 1 fixture is deterministic, so it is built once per test session
% and copied. Every test still gets its own writable database.
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

function labels = pairLabels(inputs)
runKeys = unique(string(inputs.run_key));
labels = strings(numel(runKeys), 1);
for index = 1:numel(runKeys)
    selected = sort(string(inputs.extractor_name(string(inputs.run_key) == runKeys(index))));
    labels(index) = strjoin(selected', "|");
end
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
