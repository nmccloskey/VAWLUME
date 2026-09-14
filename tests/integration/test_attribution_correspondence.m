function tests = test_attribution_correspondence
%TEST_ATTRIBUTION_CORRESPONDENCE Phase 4.9 imported window to VAWLUME event.
%
% The claim is that an imported attribution claim can be related to a call
% VAWLUME knows about, across differing clocks and differing identifiers,
% without borrowing detector-matching's rule and without choosing between
% plausible answers.
%
% The load-bearing tests are the ones checked against a KNOWN transform rather
% than against whatever the correspondence layer returned, following Phase 3's
% practice throughout the alignment work: the expected aligned interval is
% computed in the test from the transform the fixture declared.
tests = functiontests({ ...
    @testClockRelationMustBeDeclared, ...
    @testSameClockCorrespondenceUsesNativeBasis, ...
    @testAlignedCorrespondenceMatchesAHandComputedTransform, ...
    @testAlignedBasisIsRecordedOnTheStoredRow, ...
    @testExtrapolatedEndpointSurvivesIntoStorage, ...
    @testOneWindowMayCorrespondToTwoEventsAndNeitherIsChosen, ...
    @testWindowBelowTheEligibilityFloorIsNotCorresponded, ...
    @testTouchingIntervalsAreNotCorresponded, ...
    @testEligibilityRuleIsAttributionsOwn, ...
    @testCorrespondenceEvidenceRecordsItsBasis, ...
    @testUnfittedTransformIsRefused, ...
    @testMissingTransformIsRefused, ...
    @testRunWithNoImportedWindowsIsRefused, ...
    @testPlanningWritesNothing, ...
    @testASecondApplyIsRefusedByName, ...
    @testPlanningStillWorksOnAnAppliedRun, ...
    @testAnEmptyCorrespondenceRunStillCommitsCleanly, ...
    @testOneRunMayCarryOneGroupUnderTwoExtentBases, ...
    @testExtentBasisAndIouBasisAreDistinctFields, ...
    @testAScalarExtentMethodStillWorks, ...
    @testARepeatedExtentBasisIsRefused, ...
    @testAnUnknownExtentBasisIsRefusedByName, ...
    @testEmptyIntersectionIsStillEmptyAndStillSkipped, ...
    @testViewShowsTheImportedClaimBesideItsCorrespondence, ...
    @testViewNamesTheExtentBasisOnlyWhereOneApplies, ...
    @testMatchingPackageIsUntouched});
end

% --- the clock question ---------------------------------------------------

function testClockRelationMustBeDeclared(testCase)
% Neither defaulting nor guessing is offered. A correspondence computed on
% incomparable clocks is a plausible number and a wrong one.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, ["w1,10.0,10.4,A,0.9,0.9"]);
verifyRefused(testCase, ...
    @() vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture)), ...
    "vawlume:attribution:ClockRelationUndeclared");
% Declaring both is equally undeclared.
verifyRefused(testCase, ...
    @() vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
        SameClock=true, AlignmentRun=fixture.alignment_run_id), ...
    "vawlume:attribution:ClockRelationUndeclared");
clear cleanup
end

function testSameClockCorrespondenceUsesNativeBasis(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% Detection 1 occupies [10.0, 10.5]; this window brackets it loosely.
importWindows(fixture, ["w1,9.9,10.6,A,0.9,0.9"]);
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

verifyEqual(testCase, height(result.correspondences), 1);
verifyEqual(testCase, result.iou_basis, "native");
verifyTrue(testCase, isnan(result.alignment_run_id));

% Checked against the arithmetic the test computes, not against what came back.
expectedOverlap = 10.5 - 10.0;
expectedIou = expectedOverlap / (10.6 - 9.9);
verifyEqual(testCase, double(result.correspondences.temporal_overlap_s(1)), ...
    expectedOverlap, AbsTol=1e-12);
verifyEqual(testCase, double(result.correspondences.temporal_iou(1)), ...
    expectedIou, AbsTol=1e-12);
clear cleanup
end

function testAlignedCorrespondenceMatchesAHandComputedTransform(testCase)
% The fixture declares scale 1.002 and offset 5.0 from the exporter's clock to
% the recording's. The expected aligned interval is computed here from those
% numbers, so the assertion tests the correspondence layer rather than agreeing
% with it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
nativeStart = 4.9;
nativeEnd = 5.6;
importWindows(fixture, sprintf("w1,%.6f,%.6f,A,0.9,0.9", nativeStart, nativeEnd));

result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    AlignmentRun=fixture.alignment_run_id, Apply=true);

expectedStart = fixture.scale * nativeStart + fixture.offset;
expectedEnd = fixture.scale * nativeEnd + fixture.offset;
verifyEqual(testCase, double(result.correspondences.aligned_start_s(1)), ...
    expectedStart, AbsTol=1e-12);
verifyEqual(testCase, double(result.correspondences.aligned_end_s(1)), ...
    expectedEnd, AbsTol=1e-12);

% And the overlap against detection 1 at [10.0, 10.5], hand-computed.
expectedOverlap = min(expectedEnd, 10.5) - max(expectedStart, 10.0);
verifyEqual(testCase, double(result.correspondences.temporal_overlap_s(1)), ...
    expectedOverlap, AbsTol=1e-12);
clear cleanup
end

function testAlignedBasisIsRecordedOnTheStoredRow(testCase)
% Aligned duration is not native duration under a piecewise clock, so an IoU on
% aligned intervals is not the IoU of the native ones. The row must say which.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,4.9,5.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    AlignmentRun=fixture.alignment_run_id, Apply=true);

stored = fetch(fixture.conn, "SELECT iou_basis, " + ...
    "IFNULL(alignment_run_id,-1) AS alignment_run_id, " + ...
    "IFNULL(aligned_start_s,-1.0) AS aligned_start_s " + ...
    "FROM attribution_window_correspondences");
verifyEqual(testCase, presentText(stored.iou_basis(1)), "aligned");
% An aligned basis names the transform it used; the schema requires it.
verifyEqual(testCase, double(stored.alignment_run_id(1)), fixture.alignment_run_id);
verifyTrue(testCase, double(stored.aligned_start_s(1)) > 0);
clear cleanup
end

function testExtrapolatedEndpointSurvivesIntoStorage(testCase)
% A correspondence resting on a time outside the anchored range is weaker
% evidence. Consuming the flag without recording it would hide that.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% The fixture anchors [1, 20] on the exporter's clock; 0.5 lies below it.
importWindows(fixture, "w1,0.5,5.6,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    AlignmentRun=fixture.alignment_run_id, Apply=true);

verifyEqual(testCase, height(result.correspondences), 1);
verifyEqual(testCase, double(result.correspondences.start_extrapolated(1)), 1);

stored = fetch(fixture.conn, "SELECT IFNULL(start_extrapolated,-1) AS s, " + ...
    "IFNULL(end_extrapolated,-1) AS e FROM attribution_window_correspondences");
verifyEqual(testCase, double(stored.s(1)), 1);
verifyEqual(testCase, double(stored.e(1)), 0);
clear cleanup
end

% --- ambiguity ------------------------------------------------------------

function testOneWindowMayCorrespondToTwoEventsAndNeitherIsChosen(testCase)
% A correspondence layer that picked a winner would destroy the evidence a
% reviewer needs.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% Detections occupy [10.0,10.5] and [10.6,11.0]; this window spans both.
importWindows(fixture, "w1,9.9,11.1,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

verifyEqual(testCase, height(result.correspondences), 2);
verifyEqual(testCase, result.ambiguous_window_count, 1);
% Both stored, with their own scores, and no selection column anywhere.
stored = fetch(fixture.conn, "SELECT attribution_target_id AS t, temporal_iou AS iou " + ...
    "FROM attribution_window_correspondences ORDER BY attribution_target_id");
verifyEqual(testCase, height(stored), 2);
verifyNotEqual(testCase, double(stored.iou(1)), double(stored.iou(2)));
clear cleanup
end

% --- the eligibility rule -------------------------------------------------

function testWindowBelowTheEligibilityFloorIsNotCorresponded(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% Overlaps detection 1 by 0.01 s inside a 20 s window: IoU far below 0.1.
importWindows(fixture, "w1,10.49,30.49,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true);
verifyEqual(testCase, height(result.correspondences), 0);
verifyEqual(testCase, result.windows_without_correspondence, 1);
% The window is still reported as considered, not silently absent.
verifyTrue(testCase, result.considered_pairs > 0);
clear cleanup
end

function testTouchingIntervalsAreNotCorresponded(testCase)
% Exact boundary contact has zero intersection. The primitive says so and the
% rule requires positive overlap.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.0,10.0,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true);
verifyEqual(testCase, height(result.correspondences), 0);
clear cleanup
end

function testEligibilityRuleIsAttributionsOwn(testCase)
% Declared in the attribution profile, and deliberately more permissive than
% detector matching: an attribution system's window often brackets a call
% loosely, because it was produced to localize a caller rather than delimit a
% vocalization.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true);

verifyEqual(testCase, result.rule.eligibility_rule, ...
    "positive_overlap_and_min_temporal_iou_on_declared_basis");
verifyEqual(testCase, result.rule.min_temporal_iou, 0.05, AbsTol=1e-12);
verifyEqual(testCase, result.rule.calibration_status, "illustrative_prototype");

% Not the matching specification's rule, and not tuned by it. The two floors
% coinciding would be a coincidence rather than a shared calibration, so this
% guards against a later pass "harmonizing" them.
matchingSpec = jsondecode(fileread(fullfile(fixture.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json")));
matchingFloor = matchingSpec.candidate_generation.plausibility_rule.min_temporal_iou;
verifyNotEqual(testCase, result.rule.min_temporal_iou, matchingFloor);
clear cleanup
end

function testCorrespondenceEvidenceRecordsItsBasis(testCase)
% An attribution result resting on a correspondence must let a reader see how
% good that correspondence was.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,4.9,5.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    AlignmentRun=fixture.alignment_run_id, Apply=true);

stored = fetch(fixture.conn, "SELECT evidence_dimension AS dim, " + ...
    "evidence_kind AS kind, IFNULL(value_semantics,'') AS semantics, " + ...
    "IFNULL(alignment_run_id,-1) AS run_id " + ...
    "FROM attribution_evidence");
verifyEqual(testCase, height(stored), 1);
verifyEqual(testCase, presentText(stored.dim(1)), "correspondence");
semantics = presentText(stored.semantics(1));
verifyTrue(testCase, contains(semantics, "aligned"));
verifyTrue(testCase, contains(semantics, "min_temporal_iou"));
verifyTrue(testCase, contains(semantics, "uncalibrated"));
verifyTrue(testCase, contains(semantics, "not a probability"));
% The aligned-basis caveat travels with the number.
verifyTrue(testCase, contains(semantics, "not the native-interval IoU"));
verifyEqual(testCase, double(stored.run_id(1)), fixture.alignment_run_id);
clear cleanup
end

% --- refusals -------------------------------------------------------------

function testUnfittedTransformIsRefused(testCase)
% A correspondence may only rest on a fitted transform. Resting on a registered
% one would produce a plausible number from no fit at all.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,4.9,5.6,A,0.9,0.9");
execute(fixture.conn, "UPDATE time_alignment_runs SET status='registered' " + ...
    "WHERE alignment_run_id=" + string(fixture.alignment_run_id));
verifyRefused(testCase, ...
    @() vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
        AlignmentRun=fixture.alignment_run_id), ...
    "vawlume:attribution:TransformNotUsable");
clear cleanup
end

function testMissingTransformIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,4.9,5.6,A,0.9,0.9");
verifyRefused(testCase, ...
    @() vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
        AlignmentRun=99999), ...
    "vawlume:attribution:TransformNotFound");
clear cleanup
end

function testRunWithNoImportedWindowsIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefused(testCase, ...
    @() vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
        SameClock=true), ...
    "vawlume:attribution:NoImportedWindows");
clear cleanup
end

function testPlanningWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true);
verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyEqual(testCase, height(result.correspondences), 1);
verifyEqual(testCase, correspondenceRowCount(fixture), 0);
verifyEqual(testCase, evidenceRowCount(fixture), 0);
clear cleanup
end

% --- the boundary ---------------------------------------------------------

function testMatchingPackageIsUntouched(testCase)
% The tripwire. Detector-to-detector matching and caller-estimate-to-call
% correspondence are different domains that compose shared primitives; they do
% not share domain logic, and neither grows a mode flag for the other.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
matchingRoot = fullfile(fixture.repo_root, "src", "+vawlume", "+matching");
files = dir(fullfile(matchingRoot, "**", "*.m"));
offenders = strings(0, 1);
for index = 1:numel(files)
    code = string(fileread(fullfile(files(index).folder, files(index).name)));
    if contains(code, "attribution") || contains(code, "imported_attribution")
        offenders(end+1, 1) = string(files(index).name); %#ok<AGROW>
    end
end
verifyEmpty(testCase, offenders, ...
    "The matching package must know nothing about attribution: " + ...
    strjoin(offenders, ", "));

% And nothing outside +alignment/ reads segment coefficients to do its own
% clock arithmetic.
correspondenceSource = string(fileread(fullfile(fixture.repo_root, "src", ...
    "+vawlume", "+attribution", "private", ...
    "attributionBuildCorrespondencePlan.m")));
verifyFalse(testCase, contains(correspondenceSource, "alignment_segments"));
verifyTrue(testCase, contains(correspondenceSource, ...
    "vawlume.alignment.applyTransformInterval"));
clear cleanup
end

% --- re-running (4.9b) ----------------------------------------------------

function testASecondApplyIsRefusedByName(testCase)
% Observed before the guard was written: the second apply hit
% UNIQUE(window, target), the Toolbox raised database:sqlite:interfaceError, and
% the transaction rolled back leaving one correspondence and one evidence row.
% Nothing was ever duplicated -- but the caller could not tell "already applied"
% from a real database fault. Now it can.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);
verifyEqual(testCase, correspondenceRowCount(fixture), 1);
verifyEqual(testCase, evidenceRowCount(fixture), 1);

verifyRefused(testCase, ...
    @() vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
        SameClock=true, Apply=true), ...
    "vawlume:attribution:CorrespondenceAlreadyApplied");

% Nothing appended, and nothing lost either.
verifyEqual(testCase, correspondenceRowCount(fixture), 1);
verifyEqual(testCase, evidenceRowCount(fixture), 1);
clear cleanup
end

function testPlanningStillWorksOnAnAppliedRun(testCase)
% The guard is on Apply, not on planning. Previewing what a different clock
% declaration would have produced is legitimate on an applied run, and planning
% writes nothing.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

preview = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    AlignmentRun=fixture.alignment_run_id);
verifyEqual(testCase, preview.status, "planned");
verifyFalse(testCase, preview.committed);
verifyEqual(testCase, preview.iou_basis, "aligned");
% And it wrote nothing: the applied native-basis row is untouched.
verifyEqual(testCase, correspondenceRowCount(fixture), 1);
stored = fetch(fixture.conn, "SELECT iou_basis FROM attribution_window_correspondences");
verifyEqual(testCase, presentText(stored.iou_basis(1)), "native");
clear cleanup
end

function testAnEmptyCorrespondenceRunStillCommitsCleanly(testCase)
% A run where the rule admits nothing is a legitimate empty result, and nothing
% opened a transaction. The guard must not turn that into an error -- the 4.9
% handoff records commit firing with no transaction open as a real failure mode.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% Far from both detections, so nothing clears the eligibility floor.
importWindows(fixture, "w1,500.0,501.0,A,0.9,0.9");
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

verifyEqual(testCase, result.status, "corresponded");
verifyEqual(testCase, height(result.correspondences), 0);
verifyEqual(testCase, result.windows_without_correspondence, 1);
verifyEqual(testCase, correspondenceRowCount(fixture), 0);
clear cleanup
end

% --- extent basis as an analytical choice (4.9b) --------------------------

function testOneRunMayCarryOneGroupUnderTwoExtentBases(testCase)
% The point of the pass. Comparing union against intersection used to require a
% second attribution run over a separately ingested copy of the same claims.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = addAgreementGroupRun(fixture, ["union_boundary_of_members", ...
    "mean_boundary_of_members"]);
importWindowsForRun(fixture, runId, "g1,9.9,11.1,A,0.7,0.7");
result = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=runId), SameClock=true, Apply=true);

% Two targets for one group, each with its own interval, each corresponded.
verifyEqual(testCase, height(result.correspondences), 2);
verifyEqual(testCase, sort(result.extent_bases)', ...
    ["mean_boundary_of_members" "union_boundary_of_members"]);
bases = sort(presentText(result.correspondences.target_extent_basis))';
verifyEqual(testCase, bases, ...
    ["mean_boundary_of_members" "union_boundary_of_members"]);

% The two rest on different intervals, so their scores differ. Neither
% overwrote the other.
ious = double(result.correspondences.temporal_iou);
verifyNotEqual(testCase, ious(1), ious(2));
clear cleanup
end

function testExtentBasisAndIouBasisAreDistinctFields(testCase)
% The negative check. iou_basis says native-or-aligned; target_extent_basis says
% which derivation gave the group an interval at all. A field spanning both
% would let a reader attribute a drift artefact to an extent choice.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = addAgreementGroupRun(fixture, "union_boundary_of_members");
importWindowsForRun(fixture, runId, "g1,9.9,11.1,A,0.7,0.7");
result = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=runId), SameClock=true, Apply=true);

names = string(result.correspondences.Properties.VariableNames);
verifyTrue(testCase, ismember("iou_basis", names));
verifyTrue(testCase, ismember("target_extent_basis", names));
% No third field conflates them. A name containing "basis" must be exactly one
% of the two; anything else would be a combined field by another name.
basisNames = names(contains(names, "basis"));
verifyEqual(testCase, sort(basisNames), ["iou_basis" "target_extent_basis"]);
% And they carry different values here, so neither is a copy of the other.
verifyEqual(testCase, presentText(result.correspondences.iou_basis(1)), "native");
verifyEqual(testCase, presentText( ...
    result.correspondences.target_extent_basis(1)), "union_boundary_of_members");
clear cleanup
end

function testAScalarExtentMethodStillWorks(testCase)
% Inherited callers pass a scalar. This pass adds a capability; it does not get
% to break them to do it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = addAgreementGroupRun(fixture, "union_boundary_of_members");
stored = fetch(fixture.conn, "SELECT agreement_extent_method AS m " + ...
    "FROM attribution_targets WHERE attribution_run_id=" + string(runId));
verifyEqual(testCase, height(stored), 1);
verifyEqual(testCase, presentText(stored.m(1)), "union_boundary_of_members");
clear cleanup
end

function testARepeatedExtentBasisIsRefused(testCase)
% A caller naming a basis twice believed something about this run that is not
% true. Deduplicating quietly would hide the misunderstanding.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefused(testCase, ...
    @() addAgreementGroupRun(fixture, ["union_boundary_of_members", ...
        "union_boundary_of_members"]), ...
    "vawlume:attribution:TargetSpecInvalid");
clear cleanup
end

function testAnUnknownExtentBasisIsRefusedByName(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefused(testCase, ...
    @() addAgreementGroupRun(fixture, ["union_boundary_of_members", ...
        "median_boundary_of_members"]), ...
    "vawlume:attribution:TargetSpecInvalid");
clear cleanup
end

function testEmptyIntersectionIsStillEmptyAndStillSkipped(testCase)
% Inherited behaviour, proven not to have regressed now that a run may hold
% several bases. The fixture's two detections do not overlap, so the
% intersection extent is empty -- and an empty extent has no interval to compare
% against. Skipped, never compared against an invented one.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runId = addAgreementGroupRun(fixture, ["union_boundary_of_members", ...
    "intersection_boundary_of_members"]);
importWindowsForRun(fixture, runId, "g1,9.9,11.1,A,0.7,0.7");

extent = fetch(fixture.conn, "SELECT extent_is_empty AS e, gap_s AS g " + ...
    "FROM v_agreement_group_extent WHERE agreement_group_id=1 " + ...
    "AND extent_method='intersection_boundary_of_members'");
verifyEqual(testCase, double(extent.e(1)), 1);
verifyTrue(testCase, double(extent.g(1)) > 0);

result = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=runId), SameClock=true, Apply=true);

% Only the union target corresponded. The empty one produced nothing at all --
% not a zero-length interval, not a NaN score, no row.
verifyEqual(testCase, height(result.correspondences), 1);
verifyEqual(testCase, presentText( ...
    result.correspondences.target_extent_basis(1)), "union_boundary_of_members");
clear cleanup
end

% --- the read surface (4.9a) ---------------------------------------------

function testViewShowsTheImportedClaimBesideItsCorrespondence(testCase)
% The join 4.10 depends on: the exporter's caller claim and its number, beside
% the correspondence that reaches a VAWLUME event. Before the claims table this
% was unaskable -- the number was parsed at intake and discarded.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9137,0.8812");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

rows = fetch(fixture.conn, "SELECT native_window_id AS w, target_kind AS kind, " + ...
    "iou_basis, source_caller_label AS label, claim_score AS score, " + ...
    "claim_score_semantics AS semantics, claim_probability AS probability " + ...
    "FROM v_attribution_window_correspondences");

verifyEqual(testCase, height(rows), 1);
verifyEqual(testCase, presentText(rows.w(1)), "w1");
verifyEqual(testCase, presentText(rows.kind(1)), "detection");
verifyEqual(testCase, presentText(rows.iou_basis(1)), "native");
% The claim arrives whole: label, number, and the sentence that interprets it.
verifyEqual(testCase, presentText(rows.label(1)), "A");
verifyEqual(testCase, double(rows.score(1)), 0.9137);
verifyEqual(testCase, double(rows.probability(1)), 0.8812);
verifyTrue(testCase, contains(presentText(rows.semantics(1)), "uncalibrated"));
clear cleanup
end

function testViewNamesTheExtentBasisOnlyWhereOneApplies(testCase)
% target_extent_basis says which derivation supplied an agreement group's
% interval. A detection carries its own, so the column is NULL there rather than
% carrying a basis that would imply a choice nobody made.
%
% It is a different fact from iou_basis, which says whether the IoU was computed
% on native or aligned intervals. Both appear; neither is the other.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importWindows(fixture, "w1,9.9,10.6,A,0.9,0.9");
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);

groupRunId = addAgreementGroupRun(fixture);
importWindowsForRun(fixture, groupRunId, "g1,9.9,11.1,A,0.7,0.7");
vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=groupRunId), SameClock=true, Apply=true);

rows = fetch(fixture.conn, "SELECT target_kind AS kind, " + ...
    "IFNULL(target_extent_basis,'') AS basis, iou_basis " + ...
    "FROM v_attribution_window_correspondences ORDER BY target_kind");

verifyEqual(testCase, height(rows), 2);
verifyEqual(testCase, presentText(rows.kind)', ["agreement_group" "detection"]);
verifyEqual(testCase, presentText(rows.basis)', ["union_boundary_of_members" ""]);
% Both bases are present and distinct; nothing collapses them into one column.
verifyEqual(testCase, presentText(rows.iou_basis)', ["native" "native"]);
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function runId = addAgreementGroupRun(fixture, extentMethods)
% A second attribution run over the same recording, targeting an agreement group
% under one or several named extents.
%
% The group spans both detections, which do NOT overlap. So its union extent is
% [10.0, 11.0] and a window bracketing both plausibly refers to it, while its
% intersection extent is empty -- which is what makes this fixture useful for
% both the multi-basis case and the empty-extent case.
if nargin < 2
    extentMethods = "union_boundary_of_members";
end
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
    struct(run_key="phase49b-group", attribution_path="imported", ...
        method="External Caller 2.0", settings_profile_version_id=1, ...
        target_set=struct(agreement_group_ids=1, ...
            agreement_extent_method=extentMethods), ...
        participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1), ...
        notes="Agreement-group target set for extent-basis work."), ...
    Apply=true);
runId = run.run.attribution_run_id;
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

function verifyRefused(testCase, action, identifier)
refused = false;
observed = "";
try
    action();
catch err
    refused = true;
    observed = string(err.identifier);
end
verifyTrue(testCase, refused, "Expected a refusal identified as " + identifier);
verifyEqual(testCase, observed, string(identifier));
end

function value = runRef(fixture)
value = struct(attribution_run_id=fixture.attribution_run_id);
end

function importWindows(fixture, rows)
path = fullfile(fixture.workspace, "caller_" + ...
    string(java.util.UUID.randomUUID) + ".csv");
fileId = fopen(path, "w");
fprintf(fileId, "window_id,start_s,end_s,caller,score,probability\n");
for index = 1:numel(rows)
    fprintf(fileId, "%s\n", rows(index));
end
fclose(fileId);
vawlume.ingest.attribution(fixture.conn, runRef(fixture), path, Apply=true);
end

function value = correspondenceRowCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n " + ...
    "FROM attribution_window_correspondences");
value = double(rows.n(1));
end

function value = evidenceRowCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_evidence");
value = double(rows.n(1));
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_corr_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "corr.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

scale = 1.002;
offset = 5.0;
seedFixture(conn, scale, offset);

run = vawlume.attribution.createRun(conn, struct(recording_id=1), ...
    struct(run_key="phase49-corr", attribution_path="imported", ...
        method="External Caller 2.0", settings_profile_version_id=1, ...
        target_set=struct(detection_ids=[1 2]), ...
        participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1), ...
        notes="Synthetic Phase 4.9 fixture."), Apply=true);

alignmentRun = fetch(conn, "SELECT alignment_run_id FROM time_alignment_runs LIMIT 1");

fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
    attribution_run_id=run.run.attribution_run_id, ...
    alignment_run_id=double(alignmentRun.alignment_run_id(1)), ...
    scale=scale, offset=offset);
end

function tearDown(conn, workspace, sourcePath, addedPath)
try, close(conn); catch, end %#ok<NOCOM>
if isfolder(workspace), rmdir(workspace, "s"); end
if addedPath && contains(path, sourcePath)
    rmpath(sourcePath);
end
end

function seedFixture(conn, scale, offset)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'p1','Project 1')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','audio.wav','audio.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES(1,1,1,'participant'),(2,1,2,'participant')");
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
% refer to either.
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id," + ...
    "recording_id,start_time_s,end_time_s) VALUES(1,1,1,10.0,10.5),(2,1,1,10.6,11.0)");

% A fitted affine transform from the exporter's clock to the recording's,
% anchored over [1,20] on the source clock so a time below 1 is extrapolated.
execute(conn, "INSERT INTO timebases(timebase_id,project_id,recording_id," + ...
    "timebase_name,timebase_kind,is_recording_native,native_unit) VALUES" + ...
    "(1,1,1,'audio_native','recording_clock',1,'s')," + ...
    "(2,1,1,'attribution_native','external_device_clock',0,'s')");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type," + ...
    "run_key) VALUES(9,1,'temporal_alignment','align-1')");
execute(conn, "INSERT INTO alignment_sets(alignment_set_id,analysis_run_id," + ...
    "recording_id,alignment_set_key,reference_timebase_id) VALUES(1,9,1,'set1',1)");
execute(conn, "INSERT INTO time_alignment_runs(alignment_run_id,alignment_set_id," + ...
    "source_timebase_id,target_timebase_id,method,status,n_anchors_used) " + ...
    "VALUES(1,1,2,1,'affine','estimated',4)");
execute(conn, "INSERT INTO alignment_segments(alignment_run_id,segment_index," + ...
    "source_start,source_end,scale,offset_s) VALUES(1,1,NULL,NULL," + ...
    string(scale) + "," + string(offset) + ")");
% Anchors bound the fitted range, so an endpoint below 1 reads as extrapolated.
execute(conn, "INSERT INTO alignment_anchors(alignment_anchor_id," + ...
    "alignment_set_id,anchor_key,anchor_type) VALUES(1,1,'a1','ttl_edge')," + ...
    "(2,1,'a2','ttl_edge')");
execute(conn, "INSERT INTO alignment_anchor_observations(alignment_anchor_id," + ...
    "timebase_id,observed_time_native,observation_role,included_in_fit) VALUES" + ...
    "(1,2,1.0,'primary',1),(2,2,20.0,'primary',1)," + ...
    "(1,1," + string(scale * 1.0 + offset) + ",'primary',1)," + ...
    "(2,1," + string(scale * 20.0 + offset) + ",'primary',1)");
execute(conn, "INSERT INTO alignment_anchor_residuals(alignment_run_id," + ...
    "alignment_anchor_id,source_observation_id,reference_observation_id," + ...
    "observed_source_time,observed_reference_time,predicted_reference_time," + ...
    "residual_s,included_in_fit) VALUES" + ...
    "(1,1,1,3,1.0," + string(scale * 1.0 + offset) + "," + ...
    string(scale * 1.0 + offset) + ",0.0,1)," + ...
    "(1,2,2,4,20.0," + string(scale * 20.0 + offset) + "," + ...
    string(scale * 20.0 + offset) + ",0.0,1)");
end

function root = repoRootForTest()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
