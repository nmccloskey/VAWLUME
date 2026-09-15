function tests = test_caller_attribution_demonstration
%TEST_CALLER_ATTRIBUTION_DEMONSTRATION Integrated synthetic Phase 4 example.
%
% Run the demonstration once: the individual tests then hold each printed claim
% against its returned evidence rather than relying on visual inspection.
%
% The load-bearing tests here are the ones that assert what must NOT appear. A
% demonstration fails quietly -- it shows a plausible number produced the wrong
% way, or shows only the paths that work -- so the checks that matter are that no
% field combines two evidence dimensions, that no claim was promoted into a
% candidate, and that the refusals actually refused.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testCase.TestData.repo_root = repoRoot;
testCase.TestData.example_path = fullfile(repoRoot, "examples");
addpath(testCase.TestData.example_path);
testCase.TestData.value = caller_attribution_demo(Print=false, RepoRoot=repoRoot);
end

function teardownOnce(testCase)
rmpath(testCase.TestData.example_path);
end

function testWorkflowCompletesAndCleansEveryArtifact(testCase)
value = testCase.TestData.value;
verifyTrue(testCase, value.temporary_artifacts_removed);
verifyEqual(testCase, height(value.foreign_key_check), 0);
% Dense tracking samples stay in the artifact; the identity statement is what
% Phase 4 reads, and it is a row rather than a trace.
verifyEqual(testCase, value.identity_evidence.dense_samples_stored, 0);
end

function testBothTargetKindsAreDemonstrated(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, unique(value.detection_report.targets.target_kind), ...
    "detection");
verifyEqual(testCase, unique(value.consensus_report.targets.target_kind), ...
    "consensus_event");
verifyEqual(testCase, height(value.detection_report.targets), 7);
verifyEqual(testCase, height(value.consensus_report.targets), 2);
% The consensus events were derived by the matching layer, not declared here.
verifyEqual(testCase, value.consensus.matching_status, "committed");
verifyEqual(testCase, numel(value.consensus.consensus_event_ids), 2);
end

function testTheRunIsPlannedBeforeItIsCreatedAndItsTargetSetVerifies(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, value.detection_run.preview_status, "planned");
verifyEqual(testCase, value.detection_run.status, "created");
% resolveTargets is read-only and agreed with what createRun stored.
verifyTrue(testCase, value.detection_run.stored_target_set_matches);
end

function testTheExporterClockIsRecoveredThroughTheSharedTransformApi(testCase)
value = testCase.TestData.value;
clock = value.exporter_clock;
verifyEqual(testCase, clock.method, "piecewise_affine");
% Estimated, never validated. The word is the claim.
verifyEqual(testCase, clock.status, "estimated");
verifyEqual(testCase, height(clock.recovered), 2);
verifyLessThan(testCase, max(clock.recovered.scale_absolute_error), 1e-12);
verifyLessThan(testCase, max(clock.recovered.offset_absolute_error_s), 1e-9);
% Every correspondence in the run rests on that transform and says so.
rows = value.correspondence.rows;
verifyTrue(testCase, all(rows.iou_basis == "aligned"));
verifyEqual(testCase, value.correspondence.alignment_run_id, ...
    clock.alignment_run_id);
end

function testTheDryRunWritesNothingAndReportsWhatItCouldNotMap(testCase)
value = testCase.TestData.value;
preview = value.import_preview;
verifyEqual(testCase, preview.status, "planned");
verifyTrue(testCase, preview.wrote_nothing);
verifyEqual(testCase, preview.window_count, 7);
verifyEqual(testCase, preview.claim_count, 8);
% Two source rows could not be mapped, and both are named rather than dropped.
verifyEqual(testCase, preview.unmapped_rows, 2);
verifyEqual(testCase, sort(preview.issues.code)', ...
    ["ATTRIBUTION_CALLER_LABEL_UNDECLARED", "ATTRIBUTION_WINDOW_REVERSED"]);
% Each issue names the source row it came from, so a reader can go and look.
verifyTrue(testCase, all(contains(lower(preview.issues.message), "row ")));
end

function testImportedNumbersKeepTheirValueAndTheirSemantics(testCase)
value = testCase.TestData.value;
claims = value.detection_report.imported_claims;
verifyEqual(testCase, height(claims), 8);
% Exactly the values the file carried, and no rescaling of either column.
verifyEqual(testCase, sort(claims.score(~isnan(claims.score)))', ...
    [0.31 0.44 0.52 0.55 0.66 0.73 0.91], AbsTol=1e-12);
verifyTrue(testCase, all(contains(claims.score_semantics( ...
    ~isnan(claims.score)), "uncalibrated")));
% One window carrying two callers is two claims, not one row with both labels.
verifyEqual(testCase, nnz(claims.native_window_id == "w2"), 2);
verifyEqual(testCase, sort(claims.source_caller_label( ...
    claims.native_window_id == "w2"))', ["A" "B"]);
end

function testAClaimWithoutANumberKeepsNoNumber(testCase)
value = testCase.TestData.value;
claims = value.detection_report.imported_claims;
scoreless = claims(claims.native_window_id == "w5", :);
verifyEqual(testCase, height(scoreless), 1);
verifyTrue(testCase, isnan(scoreless.score(1)));
verifyTrue(testCase, isnan(scoreless.probability(1)));
% The label and the entity it resolved to survive; only the number is absent.
verifyEqual(testCase, scoreless.entity_native_id(1), "A");
verifyEqual(testCase, value.detection_report.qc.claims_without_score, 1);
end

function testCorrespondenceCrossesABreakpointAndPreservesExtrapolation(testCase)
value = testCase.TestData.value;
crossing = value.breakpoint_crossing;
verifyTrue(testCase, crossing.crosses_breakpoint);
verifyEqual(testCase, crossing.segments_crossed, 2);
% Aligned duration is not native duration under a piecewise clock.
verifyNotEqual(testCase, crossing.aligned_duration_s, crossing.native_duration_s);

rows = value.correspondence.rows;
% Exactly one endpoint in the whole run falls outside the anchored range, and
% the flag survives into storage rather than being dropped after use.
verifyEqual(testCase, nnz(rows.start_extrapolated == 1), 0);
verifyEqual(testCase, nnz(rows.end_extrapolated == 1), 1);
verifyEqual(testCase, rows.native_window_id(rows.end_extrapolated == 1), "w6");
end

function testAmbiguityAndNonCorrespondenceAreCountedNotResolved(testCase)
value = testCase.TestData.value;
verifyEqual(testCase, value.correspondence.ambiguous_window_count, 1);
verifyEqual(testCase, value.correspondence.windows_without_correspondence, 1);
% The ambiguous window produced two correspondences with different scores and
% nothing marking either as chosen.
rows = value.correspondence.rows;
ambiguous = rows(rows.native_window_id == "w1", :);
verifyEqual(testCase, height(ambiguous), 2);
verifyEqual(testCase, numel(unique(ambiguous.attribution_target_id)), 2);
verifyNotEqual(testCase, ambiguous.temporal_iou(1), ambiguous.temporal_iou(2));
names = lower(string(rows.Properties.VariableNames));
verifyFalse(testCase, any(contains(names, "chosen")));
verifyFalse(testCase, any(contains(names, "best")));
end

function testSeveralCandidatesPerTargetAndOneTargetWithNone(testCase)
value = testCase.TestData.value;
perTarget = value.candidates.per_target;
verifyEqual(testCase, max(perTarget.candidate_count), 3);
% A target with nothing is a fact QC reports, not a row that quietly vanishes.
without = value.detection_report.qc.targets_without_candidate;
verifyEqual(testCase, height(without), 1);
verifyEqual(testCase, without.attribution_target_id(1), ...
    value.candidates.target_without_candidates);
% And one candidate carries a label with no number at all.
candidates = value.detection_report.candidates;
verifyEqual(testCase, nnz(isnan(candidates.score)), 1);
verifyEqual(testCase, nnz(candidates.score == 1.0), 0);
end

function testNoImportedClaimWasPromotedIntoACandidate(testCase)
% The boundary the whole imported path rests on. A correspondence relates a
% window to an event; it does not carry the claim onto it.
value = testCase.TestData.value;
report = value.detection_report;
% Claims and candidates are different grains over different parents, and the
% candidate set was authored independently of which windows corresponded.
verifyEqual(testCase, height(report.imported_claims), 8);
verifyEqual(testCase, height(report.candidates), 14);
% Target 2 corresponds to an imported claim and still has no candidate.
corresponded = unique(report.claim_correspondences.attribution_target_id);
verifyTrue(testCase, ismember(value.candidates.target_without_candidates, ...
    corresponded));
withCandidates = unique(report.candidates.attribution_target_id);
verifyFalse(testCase, ismember(value.candidates.target_without_candidates, ...
    withCandidates));
end

function testTheFourDimensionsStaySeparateAndNothingCombinesThem(testCase)
value = testCase.TestData.value;
display = value.evidence.display;
verifyEqual(testCase, display.evidence_dimension', ...
    ["temporal_alignment" "pose_localization" "visual_identity" "acoustic"]);
% Four values on four scales with four meanings. Substitution cannot hide.
verifyEqual(testCase, numel(unique(display.value_units)), 4);
verifyEqual(testCase, numel(unique(display.value_real)), 4);
verifyEqual(testCase, numel(unique(value.evidence.semantics.value_semantics)), 4);
verifyFalse(testCase, value.evidence.combined_value_present);
verifyFalse(testCase, value.separation.combined_value_computed);
% Each row points back at where its number came from, relationally wherever the
% schema has a link. Pose confidence is the one that cannot: a tracking sample
% is a line in an artifact, not a row in this database.
provenance = value.evidence.provenance;
verifyEqual(testCase, nnz(provenance.pointer_kind == "relational"), 3);
verifyEqual(testCase, provenance.evidence_dimension( ...
    provenance.pointer_kind == "locator"), "pose_localization");
verifyTrue(testCase, all(strlength(provenance.points_at) > 0));
% No returned field is a function of more than one dimension. Asserted as a
% closed name list over every table the demonstration displays, so a combining
% field added later fails here rather than passing unnoticed.
forbidden = ["combined", "overall", "total_confidence", "caller_confidence", ...
    "weighted", "fused"];
for name = tableFieldNames(value)
    verifyFalse(testCase, any(contains(lower(name), forbidden)), ...
        "A displayed field must not read as a combination: " + name);
end
end

function testEvidenceByDimensionHasNoTotalOrCoverageFraction(testCase)
value = testCase.TestData.value;
byDimension = value.detection_report.qc.evidence_by_dimension;
verifyEqual(testCase, sort(string(byDimension.Properties.VariableNames)), ...
    ["candidate_level_count" "evidence_dimension" "row_count" ...
     "target_level_count"]);
% The four candidate-level dimensions are each present exactly once, beside the
% correspondence rows the correspondence layer wrote at target level.
candidateLevel = byDimension(byDimension.candidate_level_count > 0, :);
verifyEqual(testCase, sort(candidateLevel.evidence_dimension)', ...
    ["acoustic" "pose_localization" "temporal_alignment" "visual_identity"]);
verifyEqual(testCase, sort(candidateLevel.row_count)', [1 1 1 1]);
end

function testEveryDecisionStatusInTheVocabularyIsDemonstrated(testCase)
value = testCase.TestData.value;
statuses = value.decisions.shipped.decisions.decision_status;
verifyEqual(testCase, sort(unique(statuses))', ...
    ["ambiguous" "assigned" "excluded" "simultaneous" "unassigned"]);
% Ambiguous and simultaneous are opposite claims, not degrees of one. Both leave
% several contenders standing; only one of them selects any candidate.
simultaneous = value.decisions.shipped.decisions( ...
    statuses == "simultaneous", :);
ambiguous = value.decisions.shipped.decisions(statuses == "ambiguous", :);
verifyGreaterThan(testCase, simultaneous.contender_count(1), 1);
verifyGreaterThan(testCase, ambiguous.contender_count(1), 1);
verifyGreaterThan(testCase, simultaneous.selected_count(1), 1);
verifyEqual(testCase, ambiguous.selected_count(1), 0);
% An excluded decision carries the reason a person gave for it.
excluded = value.detection_report.decisions( ...
    value.detection_report.decisions.decision_status == "excluded", :);
verifyGreaterThan(testCase, strlength(excluded.exclusion_reason(1)), 0);
verifyFalse(testCase, any(statuses == "validated"));
end

function testTheDecisionMovesWithThePolicyAndTheCandidatesDoNot(testCase)
value = testCase.TestData.value;
comparison = value.decisions.comparison;
verifyGreaterThan(testCase, comparison.statuses_moved, 0);
verifyTrue(testCase, comparison.candidates_unchanged);
verifyNotEqual(testCase, comparison.shipped_policy, comparison.relaxed_policy);
% Both decisions remain readable: one row per (target, policy version).
decisions = value.detection_report.decisions;
verifyEqual(testCase, height(decisions), 12);
verifyEqual(testCase, numel(unique(decisions.policy_profile_version_id)), 2);
verifyTrue(testCase, all(strlength(decisions.policy_version_label) > 0));
end

function testTheGrainOfEveryReturnedTableIsStatedBesideItsCount(testCase)
% claim_correspondences is (claim, correspondence): the window carrying two
% claims appears twice there and once in correspondences. Counting the joined
% table is the easiest available mistake, so the demonstration names each grain.
value = testCase.TestData.value;
grain = value.detection_report.grain;
verifyEqual(testCase, height(grain), 8);
verifyTrue(testCase, all(strlength(grain.one_row_per) > 0));
correspondences = grain.row_count(grain.table_name == "correspondences");
joined = grain.row_count(grain.table_name == "claim_correspondences");
verifyEqual(testCase, correspondences, 7);
verifyEqual(testCase, joined, 8);
% QC counts correspondences from the unjoined table.
verifyEqual(testCase, value.detection_report.qc.correspondence_count, ...
    correspondences);
end

function testQcReportsFactsAndNoVerdict(testCase)
value = testCase.TestData.value;
qc = value.detection_report.qc;
forbidden = ["quality", "grade", "acceptab", "verdict", "combined", "score_"];
observed = lower(string(fieldnames(qc)));
for term = forbidden
    verifyFalse(testCase, any(contains(observed, term)), ...
        "QC must not read as a verdict: " + term);
end
% Correspondence scores are summarized per basis pair, never pooled run-wide.
byBasis = qc.correspondence_by_basis;
verifyTrue(testCase, ismember("iou_basis", ...
    string(byBasis.Properties.VariableNames)));
verifyTrue(testCase, ismember("target_extent_basis", ...
    string(byBasis.Properties.VariableNames)));
verifyTrue(testCase, contains(value.detection_report.qc_note, "judges nothing"));
end

function testTheRefusalsActuallyRefused(testCase)
% A path that shows only what works teaches a reader that everything works.
value = testCase.TestData.value;
refusals = value.refusals;
verifyEqual(testCase, height(refusals), 4);
verifyEqual(testCase, sort(refusals.identifier)', ...
    ["vawlume:attribution:CallerLabelUnresolved", ...
     "vawlume:attribution:ClockRelationUndeclared", ...
     "vawlume:attribution:CorrespondenceAlreadyApplied", ...
     "vawlume:attribution:RunNotWritable"]);
verifyTrue(testCase, all(strlength(refusals.message) > 0));
% The refused import named the offending label and wrote nothing.
verifyTrue(testCase, value.rejected_import.raised);
verifyTrue(testCase, contains(value.rejected_import.message, "D"));
verifyEqual(testCase, nnz(value.detection_report.imported_claims. ...
    source_caller_label == "D"), 0);
end

function testTheConsensusRunCompletesAndFreezesItsEvidence(testCase)
value = testCase.TestData.value;
consensusRun = value.consensus_run;
verifyEqual(testCase, consensusRun.iou_basis, "native");
verifyEqual(testCase, consensusRun.correspondence_count, 2);
verifyTrue(testCase, consensusRun.run_completed);
verifyEqual(testCase, consensusRun.run_status, "complete");
verifyEqual(testCase, consensusRun.analysis_status, "completed");
% Completion freezes the evidence but not the decision set, which is why the
% frozen-run refusal is about a candidate and not about a policy.
verifyTrue(testCase, any(value.refusals.identifier == ...
    "vawlume:attribution:RunNotWritable"));
end

% ---------------------------------------------------------------- helpers ---

function names = tableFieldNames(value)
%TABLEFIELDNAMES Every column name across the tables the demonstration displays.
names = strings(0, 1);
sources = {value.correspondence.rows, value.evidence.display, ...
    value.detection_report.candidates, value.detection_report.evidence, ...
    value.detection_report.imported_claims, ...
    value.detection_report.claim_correspondences, ...
    value.detection_report.decisions, ...
    value.detection_report.qc.evidence_by_dimension, ...
    value.detection_report.qc.correspondence_by_basis};
for index = 1:numel(sources)
    names = [names; string(sources{index}.Properties.VariableNames)']; %#ok<AGROW>
end
names = unique(names)';
end
