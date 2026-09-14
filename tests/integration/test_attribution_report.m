function tests = test_attribution_report
%TEST_ATTRIBUTION_REPORT Phase 4.10 attribution read-back and QC.
%
% The claim this suite defends is that the read surface is as honest as the
% representation behind it: every candidate appears, the evidence dimensions stay
% separate, absence stays absent, and QC states facts rather than verdicts.
%
% The load-bearing tests are the negative ones. A read surface fails quietly --
% it shows a number that is subtly the wrong number, or hides one that was never
% there -- so the checks that matter assert what must NOT appear, and each was
% verified able to fail by injecting the defect it targets.
tests = functiontests({ ...
    @testEveryCandidateAppearsAndNoneIsPrivileged, ...
    @testAllFourDimensionsAreSeparatelyIdentifiable, ...
    @testAMissingDimensionReadsAsAbsentRatherThanZero, ...
    @testNoReturnedFieldCombinesEvidenceDimensions, ...
    @testATargetWithoutCandidatesIsSurfacedAsAFact, ...
    @testAnEmptyRunReadsWithoutRaising, ...
    @testImportedClaimIsReadableBesideItsCorrespondence, ...
    @testAClaimWithoutAScoreReadsAsAbsent, ...
    @testAnAmbiguousWindowAppearsAgainstBothTargetsWithNeitherChosen, ...
    @testExtentBasesAreIdentifiableAndNeverPooled, ...
    @testNoReturnedFieldConflatesExtentBasisWithIouBasis, ...
    @testDecisionIsReadableWithThePolicyThatProducedIt, ...
    @testQcContainsNoVerdictThresholdOrQualityScore, ...
    @testTheReadSurfaceWritesNothing});
end

% --- candidates -----------------------------------------------------------

function testEveryCandidateAppearsAndNoneIsPrivileged(testCase)
% A read surface showing the top candidate and hiding the rest has quietly
% reintroduced the single caller_id the representation exists to avoid.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
addThreeCandidates(fixture, fixture.target_ids(1));

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, height(value.candidates), 3);
verifyEqual(testCase, sort(value.candidates.entity_native_id)', ["A" "B" "C"]);
% Each keeps its own number AND the sentence that interprets it.
verifyEqual(testCase, sort(value.candidates.score)', [10.0 10.0 42.7]);
verifyTrue(testCase, all(strlength(value.candidates.score_semantics) > 0));
verifyTrue(testCase, all(contains(value.candidates.score_semantics, ...
    "not a probability")));
% Nothing in the returned shape marks one candidate as the answer.
names = string(value.candidates.Properties.VariableNames);
verifyFalse(testCase, any(contains(lower(names), "best")));
verifyFalse(testCase, any(contains(lower(names), "winner")));
verifyFalse(testCase, any(contains(lower(names), "selected")));
clear cleanup
end

% --- the four dimensions --------------------------------------------------

function testAllFourDimensionsAreSeparatelyIdentifiable(testCase)
% The claim 4.5 tested at the storage layer, now at the read layer -- which is
% where it would actually be lost.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = addThreeCandidates(fixture, fixture.target_ids(1));
addFourDimensions(fixture, candidateId);

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, height(value.evidence), 4);
verifyEqual(testCase, sort(value.evidence.evidence_dimension)', ...
    ["acoustic" "pose_localization" "temporal_alignment" "visual_identity"]);
% Each carries its own units and its own semantics, not a shared one.
verifyEqual(testCase, numel(unique(value.evidence.value_units)), 4);
verifyEqual(testCase, numel(unique(value.evidence.value_semantics)), 4);
% And QC counts them separately rather than summing them into a coverage score.
byDimension = value.qc.evidence_by_dimension;
verifyEqual(testCase, height(byDimension), 4);
verifyEqual(testCase, sort(byDimension.row_count)', [1 1 1 1]);
clear cleanup
end

function testAMissingDimensionReadsAsAbsentRatherThanZero(testCase)
% A candidate with no acoustic evidence has none. A zero would claim a
% measurement was made.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = addThreeCandidates(fixture, fixture.target_ids(1));
addThreeDimensions(fixture, candidateId);

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

dimensions = value.evidence.evidence_dimension;
verifyFalse(testCase, any(dimensions == "acoustic"));
verifyEqual(testCase, height(value.evidence), 3);
% Absent, not present-and-zero: no row exists, and QC reports no acoustic line.
byDimension = value.qc.evidence_by_dimension;
verifyFalse(testCase, any(byDimension.evidence_dimension == "acoustic"));
verifyEqual(testCase, height(byDimension), 3);
clear cleanup
end

function testNoReturnedFieldCombinesEvidenceDimensions(testCase)
% The negative check. Verified able to fail by adding a combining field.
%
% Asserted as a closed field list rather than a blocklist of suspicious names:
% a blocklist passes for any combining field somebody names imaginatively, while
% a closed list fails for every field that was not deliberately contracted.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = addThreeCandidates(fixture, fixture.target_ids(1));
addFourDimensions(fixture, candidateId);

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, sort(string(fieldnames(value)))', expectedReportFields());
verifyEqual(testCase, sort(string(fieldnames(value.qc)))', expectedQcFields());
% Every evidence row belongs to exactly one dimension from the closed
% vocabulary. A row spanning two would have to invent a value outside it.
allowed = ["temporal_alignment", "pose_localization", "visual_identity", ...
    "acoustic", "correspondence", "imported_composite"];
verifyTrue(testCase, all(ismember(value.evidence.evidence_dimension, allowed)));
% And the per-dimension QC table has no total, coverage, or combined column.
verifyEqual(testCase, ...
    sort(string(value.qc.evidence_by_dimension.Properties.VariableNames)), ...
    ["candidate_level_count" "evidence_dimension" "row_count" ...
     "target_level_count"]);
clear cleanup
end

% --- absence --------------------------------------------------------------

function testATargetWithoutCandidatesIsSurfacedAsAFact(testCase)
% Reported with enough identity to act on, and reported as a count of nothing
% rather than as a problem.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
addThreeCandidates(fixture, fixture.target_ids(1));

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

without = value.qc.targets_without_candidate;
verifyEqual(testCase, height(without), 1);
verifyEqual(testCase, without.attribution_target_id(1), fixture.target_ids(2));
verifyEqual(testCase, without.target_kind(1), "detection");
% And the per-target count says zero rather than omitting the row.
perTarget = value.qc.candidates_per_target;
verifyEqual(testCase, height(perTarget), 2);
verifyEqual(testCase, sort(perTarget.candidate_count)', [0 3]);
clear cleanup
end

function testAnEmptyRunReadsWithoutRaising(testCase)
% The empty-set NULL trap makes this a real failure mode rather than a
% formality: the Database Toolbox raises on any SQL NULL in a result set,
% including MIN()/MAX() over nothing.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, height(value.candidates), 0);
verifyEqual(testCase, height(value.evidence), 0);
verifyEqual(testCase, height(value.imported_claims), 0);
verifyEqual(testCase, height(value.correspondences), 0);
verifyEqual(testCase, height(value.decisions), 0);
% QC over nothing is still well formed, and still says nothing judgemental.
verifyEqual(testCase, value.qc.candidate_count, 0);
verifyEqual(testCase, value.qc.claims_without_score, 0);
verifyEqual(testCase, value.qc.windows_without_correspondence, 0);
verifyEqual(testCase, height(value.qc.correspondence_by_basis), 0);
verifyEqual(testCase, height(value.qc.targets_without_candidate), 2);
clear cleanup
end

% --- the imported claim, beside the event it reached ----------------------

function testImportedClaimIsReadableBesideItsCorrespondence(testCase)
% The nine elements of the imported story, together, in one row. Before 4.9a
% gave the claim's number a home this was unaskable: intake parsed the score and
% discarded it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9137,0.8812");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

value = vawlume.attribution.report(fixture.conn, runRef(fixture));
story = value.claim_correspondences;

verifyEqual(testCase, height(story), 1);
verifyEqual(testCase, story.source_caller_label(1), "A");          % 1, 2
verifyEqual(testCase, story.claimed_entity_native_id(1), "A");
verifyEqual(testCase, story.claim_score(1), 0.9137);               % 3
verifyTrue(testCase, contains(story.claim_score_semantics(1), "uncalibrated"));
verifyEqual(testCase, story.native_window_id(1), "w1");            % 4
verifyEqual(testCase, story.target_kind(1), "detection");          % 5
verifyEqual(testCase, story.detection_id(1), 1);
verifyTrue(testCase, story.temporal_iou(1) > 0);                   % 6
verifyEqual(testCase, story.iou_basis(1), "native");               % 7
verifyEqual(testCase, story.target_extent_basis(1), "");
verifyTrue(testCase, isnan(story.alignment_run_id(1)));            % 8
verifyEqual(testCase, story.start_extrapolated(1), NaN);
verifyEqual(testCase, value.qc.windows_without_correspondence, 0); % 9
clear cleanup
end

function testAClaimWithoutAScoreReadsAsAbsent(testCase)
% Not zero, and not one. The read layer must not be where a name finally
% acquires certainty.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,,");

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, height(value.imported_claims), 1);
verifyTrue(testCase, isnan(value.imported_claims.score(1)));
verifyTrue(testCase, isnan(value.imported_claims.probability(1)));
verifyEqual(testCase, value.qc.claims_without_score, 1);
% The label and its resolved entity survive; only the number is absent.
verifyEqual(testCase, value.imported_claims.source_caller_label(1), "A");
verifyEqual(testCase, value.imported_claims.entity_native_id(1), "A");
verifyEqual(testCase, value.qc.claims_without_resolved_entity, 0);
clear cleanup
end

function testAnAmbiguousWindowAppearsAgainstBothTargetsWithNeitherChosen(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% Detections occupy [10.0,10.5] and [10.6,11.0]; this window spans both.
importWindows(fixture, "w1,9.9,11.1,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, height(value.correspondences), 2);
story = value.claim_correspondences;
verifyEqual(testCase, height(story), 2);
% One claim, two targets, two different scores, and nothing marking a winner.
verifyEqual(testCase, numel(unique(story.imported_attribution_claim_id)), 1);
verifyEqual(testCase, numel(unique(story.attribution_target_id)), 2);
verifyNotEqual(testCase, story.temporal_iou(1), story.temporal_iou(2));
names = string(story.Properties.VariableNames);
verifyFalse(testCase, any(contains(lower(names), "chosen")));
verifyFalse(testCase, any(contains(lower(names), "preferred")));
verifyEqual(testCase, value.qc.windows_with_multiple_correspondences, 1);
clear cleanup
end

% --- extent basis ---------------------------------------------------------

function testExtentBasesAreIdentifiableAndNeverPooled(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = addAgreementGroupRun(fixture, ["union_boundary_of_members", ...
    "mean_boundary_of_members"]);
importWindowsForRun(fixture, runId, "g1,9.9,11.1,A,0.7,0.7");
vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=runId), SameClock=true, Apply=true);

value = vawlume.attribution.report(fixture.conn, ...
    struct(attribution_run_id=runId));

verifyEqual(testCase, height(value.correspondences), 2);
verifyEqual(testCase, sort(value.correspondences.target_extent_basis)', ...
    ["mean_boundary_of_members" "union_boundary_of_members"]);
% The score summary is per basis pair. Two bases means two rows, never one
% pooled row averaging quantities measured against different intervals.
byBasis = value.qc.correspondence_by_basis;
verifyEqual(testCase, height(byBasis), 2);
verifyEqual(testCase, sort(byBasis.target_extent_basis)', ...
    ["mean_boundary_of_members" "union_boundary_of_members"]);
verifyEqual(testCase, sort(byBasis.correspondence_count)', [1 1]);
% The two rest on different intervals, so their observed scores differ.
verifyNotEqual(testCase, byBasis.temporal_iou_median(1), ...
    byBasis.temporal_iou_median(2));
clear cleanup
end

function testNoReturnedFieldConflatesExtentBasisWithIouBasis(testCase)
% The second negative check. Verified able to fail by adding such a field.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = addAgreementGroupRun(fixture, "union_boundary_of_members");
importWindowsForRun(fixture, runId, "g1,9.9,11.1,A,0.7,0.7");
vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=runId), SameClock=true, Apply=true);

value = vawlume.attribution.report(fixture.conn, ...
    struct(attribution_run_id=runId));

% Across every returned table, a field naming a "basis" is exactly one of the
% two. Anything else is a combined field by another name.
observed = strings(0, 1);
for name = ["correspondences", "claim_correspondences"]
    columns = string(value.(name).Properties.VariableNames);
    observed = [observed; columns(contains(columns, "basis"))']; %#ok<AGROW>
end
columns = string(value.qc.correspondence_by_basis.Properties.VariableNames);
observed = [observed; columns(contains(columns, "basis"))'];
verifyEqual(testCase, sort(unique(observed))', ...
    ["iou_basis" "target_extent_basis"]);
% And both are present with different values, so neither is a copy of the other.
verifyEqual(testCase, value.correspondences.iou_basis(1), "native");
verifyEqual(testCase, value.correspondences.target_extent_basis(1), ...
    "union_boundary_of_members");
clear cleanup
end

% --- decisions ------------------------------------------------------------

function testDecisionIsReadableWithThePolicyThatProducedIt(testCase)
% A decision without its policy is not a decision.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
addThreeCandidates(fixture, fixture.target_ids(1));
vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
    Apply=true, Targets=fixture.target_ids(1));

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, height(value.decisions), 1);
verifyTrue(testCase, strlength(value.decisions.decision_status(1)) > 0);
% The policy that bound it is recoverable, by version and by key.
verifyTrue(testCase, value.decisions.policy_profile_version_id(1) > 0);
verifyTrue(testCase, strlength(value.decisions.policy_version_label(1)) > 0);
verifyTrue(testCase, strlength(value.decisions.policy_profile_key(1)) > 0);
% No status means validated, and the threshold is not calibrated.
verifyNotEqual(testCase, value.decisions.decision_status(1), "validated");
verifyTrue(testCase, any(value.qc.decision_status_counts.count == 1));
clear cleanup
end

% --- QC judges nothing ----------------------------------------------------

function testQcContainsNoVerdictThresholdOrQualityScore(testCase)
% Every QC field is a count, a membership, or an observed range. The closed
% field list is what stops a grade being added later without anyone noticing.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = addThreeCandidates(fixture, fixture.target_ids(1));
addFourDimensions(fixture, candidateId);
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

value = vawlume.attribution.report(fixture.conn, runRef(fixture));

verifyEqual(testCase, sort(string(fieldnames(value.qc)))', expectedQcFields());
forbidden = ["quality", "grade", "acceptab", "pass", "fail", "verdict", ...
    "confidence_overall", "combined"];
observed = lower(string(fieldnames(value.qc)));
for term = forbidden
    verifyFalse(testCase, any(contains(observed, term)), ...
        "QC field names must not read as a verdict: " + term);
end
% The note says in words what QC cannot tell a reader.
verifyTrue(testCase, contains(value.qc_note, "judges nothing"));
verifyTrue(testCase, contains(value.qc_note, "whether any claimed caller called"));
clear cleanup
end

function testTheReadSurfaceWritesNothing(testCase)
% The tripwire. A read surface that needed a write would have exceeded scope.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
candidateId = addThreeCandidates(fixture, fixture.target_ids(1));
addFourDimensions(fixture, candidateId);
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

before = rowCensus(fixture);
vawlume.attribution.report(fixture.conn, runRef(fixture));
vawlume.attribution.report(fixture.conn, runRef(fixture));
after = rowCensus(fixture);

verifyEqual(testCase, after, before, ...
    "Reporting must not change any stored row count.");
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function value = expectedReportFields()
value = sort(["attribution_run_id", "run_key", "project_key", "recording_id", ...
    "native_recording_id", "attribution_path", "method", "status", ...
    "analysis_status", "settings_profile_version_id", ...
    "participating_entity_ids", "provenance", "targets", "candidates", ...
    "evidence", "imported_claims", "correspondences", ...
    "claim_correspondences", "decisions", "decision_selections", "qc", ...
    "dimension_separation_note", "absence_note", "basis_note", "qc_note", ...
    "source"]);
end

function value = expectedQcFields()
value = sort(["target_count", "candidate_count", "evidence_count", ...
    "imported_window_count", "imported_claim_count", "correspondence_count", ...
    "decision_count", "targets_without_candidate", ...
    "targets_with_empty_extent", "candidates_per_target", ...
    "candidate_status_counts", "decision_status_counts", ...
    "evidence_by_dimension", "claims_without_score", ...
    "claims_without_probability", "claims_without_resolved_entity", ...
    "imported_label_resolution", "windows_without_correspondence", ...
    "windows_with_multiple_correspondences", "correspondence_by_basis"]);
end

function value = rowCensus(fixture)
tables = ["attribution_targets", "attribution_candidates", ...
    "attribution_evidence", "attribution_decisions", ...
    "attribution_decision_candidates", "imported_attribution_windows", ...
    "imported_attribution_claims", "attribution_window_correspondences"];
value = zeros(numel(tables), 1);
for index = 1:numel(tables)
    rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM " + tables(index));
    value(index) = double(rows.n(1));
end
end

function value = runRef(fixture)
value = struct(attribution_run_id=fixture.attribution_run_id);
end

function candidateId = addThreeCandidates(fixture, targetId)
% Ranks [1;2;2], not [1;2;3]: equal scores must tie. The candidate layer
% enforces that ranks agree with scores, and a fixture has no business
% contradicting it to look tidier.
candidates = table([1; 2; 3], [1; 2; 2], [42.7; 10.0; 10.0], ...
    repmat(scoreSemantics(), 3, 1), [0.81; 0.12; 0.07], ...
    repmat(probabilitySemantics(), 3, 1), ["A"; "B"; "C"], ...
    VariableNames=["entity_id", "candidate_rank", "score", ...
    "score_semantics", "probability", "probability_semantics", ...
    "source_label"]);
created = vawlume.attribution.addCandidates(fixture.conn, ...
    struct(attribution_target_id=targetId), candidates, Apply=true);
candidateId = created.candidates.attribution_candidate_id(1);
end

function value = scoreSemantics()
value = "External Caller 2.0 raw margin; producer=External Caller 2.0; " + ...
    "range=unbounded; uncalibrated; higher is better; not a probability";
end

function value = probabilitySemantics()
value = "Exporter-labelled caller probability; producer=External Caller 2.0; " + ...
    "range=[0,1]; calibration=exporter-claimed and not validated by VAWLUME";
end

function addFourDimensions(fixture, candidateId)
vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_candidate_id=candidateId), dimensionRows(4), Apply=true);
end

function addThreeDimensions(fixture, candidateId)
vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_candidate_id=candidateId), dimensionRows(3), Apply=true);
end

function value = dimensionRows(count)
% Four dimensions, each with its own kind, units and semantics. Truncating to
% three leaves acoustic absent -- which is the point of the absence test.
value = table( ...
    ["temporal_alignment"; "pose_localization"; "visual_identity"; "acoustic"], ...
    ["propagated_bound"; "keypoint_confidence"; ...
     "reidentification_similarity"; "channel_rms_ratio"], ...
    [0.002; 0.73; 0.55; 0.42], ...
    ["s"; "upstream_score"; "cosine_similarity"; "ratio"], ...
    ["Largest contributing anchor uncertainty on the reference clock; uncalibrated; not a confidence interval"; ...
     "Tracker-exported keypoint localization confidence; producer=Tracker X; range=[0,1]; uncalibrated; not caller probability"; ...
     "Appearance-embedding cosine similarity; producer=ReID X; range=[-1,1]; uncalibrated; not caller probability"; ...
     "Native channel 1 to channel 2 RMS ratio; producer=measurement export; range=nonnegative; uncalibrated; not caller probability"], ...
    ["alignment_run:1"; "tracking.csv#frame=120"; "reid.json#track=A"; ...
     "audio.wav#samples=1000:2000"], ...
    ["" ; ""; "identity_association"; ""], [NaN; NaN; 90; NaN], ...
    VariableNames=["evidence_dimension", "evidence_kind", "value_real", ...
    "value_units", "value_semantics", "source_locator", ...
    "identity_statement_kind", "tracking_identity_association_id"]);
value = value(1:count, :);
end

function importWindows(fixture, rows)
importWindowsForRun(fixture, fixture.attribution_run_id, rows);
end

function importWindowsForRun(fixture, runId, rows)
path = fullfile(fixture.workspace, "caller_" + ...
    string(java.util.UUID.randomUUID) + ".csv");
fileId = fopen(path, "w");
fprintf(fileId, "window_id,start_s,end_s,caller,score,probability\n");
for index = 1:numel(rows)
    fprintf(fileId, "%s\n", rows(index));
end
fclose(fileId);
vawlume.ingest.attribution(fixture.conn, ...
    struct(attribution_run_id=runId), path, Apply=true);
end

function runId = addAgreementGroupRun(fixture, extentMethods)
% A second run over the same recording, targeting an agreement group spanning
% both detections under one or several named extents.
conn = fixture.conn;
if isempty(fetch(conn, "SELECT agreement_group_id FROM agreement_groups"))
    execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id," + ...
        "run_type,run_key) VALUES(11,1,'multi_extractor_agreement','agree-1')");
    execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
        "extraction_run_id) VALUES(11,1)");
    execute(conn, "INSERT INTO agreement_groups(agreement_group_id," + ...
        "analysis_run_id,recording_id,group_key,derivation_method) " + ...
        "VALUES(1,11,1,'g1','connected_component')");
    execute(conn, "INSERT INTO agreement_group_members(agreement_group_id," + ...
        "detection_id) VALUES(1,1),(1,2)");
end
run = vawlume.attribution.createRun(conn, struct(recording_id=1), ...
    struct(run_key="phase410-group", attribution_path="imported", ...
        method="External Caller 2.0", settings_profile_version_id=1, ...
        target_set=struct(agreement_group_ids=1, ...
            agreement_extent_method=extentMethods), ...
        participating_entity_ids=[1 2 3], ...
        sources=struct(source_file_ids=1), ...
        notes="Agreement-group run for the 4.10 read surface."), Apply=true);
runId = run.run.attribution_run_id;
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_report_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "report.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedFixture(conn);

run = vawlume.attribution.createRun(conn, struct(recording_id=1), ...
    struct(run_key="phase410-run", attribution_path="imported", ...
        method="External Caller 2.0", settings_profile_version_id=1, ...
        target_set=struct(detection_ids=[1 2]), ...
        participating_entity_ids=[1 2 3], ...
        sources=struct(source_file_ids=1), ...
        notes="Synthetic Phase 4.10 fixture."), Apply=true);

targets = fetch(conn, "SELECT attribution_target_id FROM attribution_targets " + ...
    "WHERE attribution_run_id=" + string(run.run.attribution_run_id) + ...
    " ORDER BY attribution_target_id");

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
    attribution_run_id=run.run.attribution_run_id, ...
    target_ids=double(targets.attribution_target_id));
end

function tearDown(conn, workspace, sourcePath, addedPath)
try, close(conn); catch, end %#ok<NOCOM>
if isfolder(workspace), rmdir(workspace, "s"); end
if addedPath && contains(path, sourcePath)
    rmpath(sourcePath);
end
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'p1','Project 1')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','audio.wav','audio.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'C')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES" + ...
    "(1,1,1,'participant'),(2,1,2,'participant'),(3,1,3,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key," + ...
    "profile_name,profile_kind) VALUES" + ...
    "(1,1,'import-settings','Import settings','analysis_settings')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id," + ...
    "version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1.0.0','json','config/settings.json'," + ...
    "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(1,1)");
% Two detections, adjacent but not touching, so one loose window can plausibly
% refer to either and their agreement group has an empty intersection extent.
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id," + ...
    "recording_id,start_time_s,end_time_s) VALUES(1,1,1,10.0,10.5),(2,1,1,10.6,11.0)");
% An identity association for visual-identity evidence to rest on. A-1: an
% identity-derived evidence row must name which kind of statement it rests on
% and point at the row it read, so this is not optional scaffolding.
execute(conn, "INSERT INTO timebases(timebase_id,project_id,recording_id," + ...
    "timebase_name,timebase_kind,native_unit) " + ...
    "VALUES(90,1,1,'identity_video_native','video_clock','s')");
execute(conn, "INSERT INTO external_streams(external_stream_id,project_id," + ...
    "recording_id,timebase_id,stream_name,stream_kind) " + ...
    "VALUES(90,1,1,90,'identity-video-track','tracking')");
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) " + ...
    "VALUES(90,1,'identity_arena','Arena frame',2,'m')");
execute(conn, "INSERT INTO tracking_streams(external_stream_id," + ...
    "coordinate_system_id,native_time_basis) VALUES(90,90,'time')");
execute(conn, "INSERT INTO tracking_series(external_stream_id," + ...
    "native_track_id,native_bodypart_label) VALUES(90,'track0','snout')");
execute(conn, "INSERT INTO tracking_identity_associations(" + ...
    "tracking_identity_association_id,external_stream_id,native_track_id," + ...
    "entity_id,start_time_native,end_time_native,assignment_state," + ...
    "evidence_kind) VALUES(90,90,'track0',1,0,20,'assigned','manual_assertion')");
end

function root = repoRootForTest()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
