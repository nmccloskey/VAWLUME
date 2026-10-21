function tests = test_qc_facts
%TEST_QC_FACTS Itinerary 7.10: vawlume.estimator.qcFacts on the 7.3 fixture.
%
% Contract 07 D8. The facts come from stored evidence through the pure method;
% they judge nothing and change nothing. The fixture's scenes are the cases:
% separable (nothing fires), symmetric (the predictions coincide), unfittable
% (the observed difference lies outside both predictions: the out-of-range
% scene, already in 7.3's fixture, so the fixture is unchanged) and model
% mismatch (a wrong animal fits; nothing fires, and the undetectable class is
% stated).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=root);
m = fixture.manifest;
testCase.TestData = struct(root=root, fixture=fixture, cleanup=cleanup);
testCase.TestData.before = stored(fixture.conn);
testCase.TestData.state_before = state(fixture.conn);
testCase.TestData.facts = vawlume.estimator.qcFacts(fixture.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id), RepoRoot=root);
testCase.TestData.consensus_facts = vawlume.estimator.qcFacts(fixture.conn, ...
    struct(attribution_run_id=m.runs.native_consensus.attribution_run_id), RepoRoot=root);
testCase.TestData.state_after = state(fixture.conn);
testCase.TestData.after = stored(fixture.conn);
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ================================================================ scenes ===

function testTheSeparableSceneFiresNothingAndReportsItsSeparation(testCase)
[row, candidates] = scene(testCase, "separable");
verifyEqual(testCase, row.status, "facts");
verifyFalse(testCase, row.observed_outside_predictions);
verifyFalse(testCase, row.no_candidate_within_tolerance);
verifyFalse(testCase, row.predictions_coincide);
verifyGreaterThan(testCase, row.prediction_gap_db, 10, "The separation is reported.");
verifyEqual(testCase, row.tolerance_db, row.prediction_gap_db / 2, AbsTol=1e-12);
A = testCase.TestData.fixture.manifest.entities.A;
verifyTrue(testCase, candidates.within_tolerance(candidates.entity_id == A), ...
    "A generated the call and fits within tolerance.");
end

function testTheSymmetricSceneReportsCoincidentPredictionsAndClaimsNoFailure(testCase)
row = scene(testCase, "symmetric");
verifyEqual(testCase, row.prediction_gap_db, 0);
verifyTrue(testCase, row.predictions_coincide);
verifyFalse(testCase, row.observed_outside_predictions, "No failure is claimed.");
verifyFalse(testCase, row.no_candidate_within_tolerance, "No failure is claimed.");
end

function testAnObservationOutsideBothPredictionsFiresWithItsMagnitude(testCase)
% The unfittable scene: its observed difference lies beyond both predictions.
[row, candidates] = scene(testCase, "unfittable");
verifyTrue(testCase, row.observed_outside_predictions);
verifyTrue(testCase, row.no_candidate_within_tolerance);
% The magnitude, from the stored distances and the observation directly.
predictions = 20 * log10(candidates.distance_b ./ candidates.distance_a);
expected = max([0, min(predictions) - row.observed_db, row.observed_db - max(predictions)]);
verifyEqual(testCase, row.outside_by_db, expected, AbsTol=1e-9);
verifyEqual(testCase, sort(candidates.predicted_db), sort(predictions), ...
    "qcFacts reports the method's own predictions.", AbsTol=1e-12);
log(testCase, 1, sprintf("unfittable: observed %.3f dB, predictions [%.3f %.3f], outside by %.3f dB", ...
    row.observed_db, predictions, row.outside_by_db));
end

function testTheModelMismatchSceneStatesTheUndetectableClass(testCase)
% B did not generate the call but fits within tolerance. Nothing fires, and no
% fact claims that the wrong animal was detected.
[row, candidates] = scene(testCase, "model_mismatch");
log(testCase, 1, sprintf("model_mismatch: observed %.3f dB, gap %.3f, margin %.3f, " + ...
    "outside %d, none within tolerance %d", row.observed_db, row.prediction_gap_db, ...
    row.acoustic_margin_db, row.observed_outside_predictions, row.no_candidate_within_tolerance));
verifyFalse(testCase, row.observed_outside_predictions);
verifyFalse(testCase, row.no_candidate_within_tolerance);
B = testCase.TestData.fixture.manifest.entities.B;
verifyTrue(testCase, candidates.within_tolerance(candidates.entity_id == B));
verifyEqual(testCase, row.undetectable_failure_class, ...
    "A wrong animal that fits well is not detectable from these facts. When an " + ...
    "unmodelled bias moves the observed difference toward the wrong candidate's " + ...
    "prediction by more than acoustic_margin_db and less than the gap, the wrong " + ...
    "animal scores best and every fact here looks ordinary.");
f = testCase.TestData.facts;
names = lower([string(f.targets.Properties.VariableNames), ...
    string(f.candidates.Properties.VariableNames), string(fieldnames(f))']);
% The one permitted name: the itinerary's statement of what cannot be seen.
names = names(names ~= "undetectable_failure_class");
verifyFalse(testCase, any(contains(names, ["wrong", "detected", "verdict", "correct", ...
    "quality", "valid", "pass", "fail"])), "No fact names a verdict.");
verifyTrue(testCase, all(f.targets.undetectable_failure_class == f.undetectable_failure_class), ...
    "The undetectable class is stated on every row.");
end

function testUnscoredTargetsHaveNoFactsAndTheirReason(testCase)
for name = ["coverage_gap", "identity_swap", "out_of_bracket"]
    row = scene(testCase, name);
    verifyEqual(testCase, row.status, "no_facts", name);
    verifyGreaterThan(testCase, strlength(row.reason), 0, name);
end
verifyEqual(testCase, scene(testCase, "identity_swap").reason, "identity_changes_within_window");
end

function testThePositionalMarginMovesThePredictionToTheBoundary(testCase)
f = testCase.TestData.facts;
for k = 1:height(f.candidates)
    c = f.candidates(k, :);
    row = f.targets(f.targets.attribution_target_id == c.attribution_target_id, :);
    if row.predictions_coincide
        continue
    end
    movedA = 20 * log10(c.distance_b / (c.distance_a + c.positional_margin_a));
    movedB = 20 * log10((c.distance_b + c.positional_margin_b) / c.distance_a);
    verifyEqual(testCase, [movedA, movedB], [row.ranking_boundary_db, row.ranking_boundary_db], ...
        sprintf("target %d entity %d", c.attribution_target_id, c.entity_id), AbsTol=1e-9);
end
verifyTrue(testCase, all(f.candidates.distance_unit == "cm"), "In the frame's unit.");
end

function testConsensusTargetsReadTheSame(testCase)
a = testCase.TestData.facts.targets;
b = testCase.TestData.consensus_facts.targets;
verifyEqual(testCase, b.status, a.status, "The consensus run's scenes mirror the detections'.");
verifyEqual(testCase, b.observed_outside_predictions, a.observed_outside_predictions);
end

% ======================================================= refusal, read-only ===

function testANonNativeRunIsRefused(testCase)
t = testCase.TestData;
m = t.fixture.manifest;
for name = ["imported", "backend"]
    verifyError(testCase, @() vawlume.estimator.qcFacts(t.fixture.conn, ...
        struct(attribution_run_id=m.runs.(name).attribution_run_id), RepoRoot=t.root), ...
        "vawlume:estimator:QcFactsNotNative", name);
end
end

function testNothingIsWrittenOrChanged(testCase)
t = testCase.TestData;
verifyEqual(testCase, t.state_after, t.state_before, "data_version and total_changes");
verifyEqual(testCase, t.after, t.before, "Stored scores and decisions are unchanged.");
end

function testItReadsOnlyStorage(testCase)
% Static guard: no audio, tracking-artifact or alignment reader, and no write,
% in qcFacts or the prediction helpers it calls.
folder = fullfile(testCase.TestData.root, "src", "+vawlume", "+estimator");
files = [fullfile(folder, "qcFacts.m"), ...
    fullfile(folder, "private", "estimatorPredictedDifferenceDb.m"), ...
    fullfile(folder, "private", "estimatorDistanceForPrediction.m")];
banned = ["audioread", "audioinfo", "vawlume\.acoustic\.(measure|estimate|normalize|register|read)", ...
    "vawlume\.tracking\.", "vawlume\.alignment\.", "readWindow", "candidateGeometry", ...
    "positionsAtInstants", "eventReferenceInstants", "sqlwrite", "execute\(", ...
    "\<INSERT\s", "\<UPDATE\s", "\<DELETE\s"];
for file = files
    lines = splitlines(string(fileread(file)));
    lines = lines(~startsWith(strtrim(lines), "%"));
    code = regexprep(lines, "%.*$", "");
    for pattern = banned
        hits = code(~cellfun(@isempty, regexp(code, pattern, "once")));
        verifyEmpty(testCase, hits, file + " matches " + pattern + ": " + strjoin(hits, " | "));
    end
end
end

% --------------------------------------------------------------- helpers ---

function [row, candidates] = scene(testCase, name)
t = testCase.TestData;
m = t.fixture.manifest;
target = m.scenes.native_detection_target_id(m.scenes.scene == name);
row = t.facts.targets(t.facts.targets.attribution_target_id == target, :);
candidates = t.facts.candidates(t.facts.candidates.attribution_target_id == target, :);
end

function value = stored(conn)
value = struct( ...
    candidates=fetch(conn, "SELECT attribution_candidate_id, IFNULL(score,-1e308) AS score " + ...
        "FROM attribution_candidates ORDER BY attribution_candidate_id"), ...
    decisions=fetch(conn, "SELECT attribution_decision_id, decision_status FROM " + ...
        "attribution_decisions ORDER BY attribution_decision_id"));
end

function value = state(conn)
version = fetch(conn, "PRAGMA data_version");
changes = fetch(conn, "SELECT total_changes() AS n");
value = [double(version{1, 1}), double(changes.n(1))];
end
