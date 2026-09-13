function tests = test_attribution_decisions
%TEST_ATTRIBUTION_DECISIONS Phase 4.6 policy-driven decisions over candidates.
%
% The decision layer's claim is that it is DERIVED and separable: everything it
% records follows from the candidate rows plus the declared policy, and changing
% the policy changes the decision while changing no candidate. The load-bearing
% test here is testDifferentThresholdChangesTheDecisionAndNoCandidate, because a
% layer that had quietly absorbed its own evidence would still pass every other
% test in this file.
%
% Every status is reached from constructed candidates, including unassigned and
% excluded, which are the easiest to leave untested because they look like
% failures rather than outcomes.
tests = functiontests({ ...
    @testAssignedRequiresSeparationNotMerelyAThreshold, ...
    @testSimultaneousSelectsEveryIndependentlyStrongContender, ...
    @testAmbiguousAndSimultaneousDifferOnlyByIndependentStrength, ...
    @testUnassignedWhenNothingIsSupportable, ...
    @testExcludedWhenThePolicyCannotBeApplied, ...
    @testCallerDeclaredExclusionCarriesItsReason, ...
    @testPlanningWritesNothing, ...
    @testDecidingTwiceUnderOnePolicyIsRefused, ...
    @testDifferentThresholdChangesTheDecisionAndNoCandidate, ...
    @testTheSamePolicyTwiceGivesTheSameDecision, ...
    @testDecisionIsInterpretableFromTheStoredRowAlone, ...
    @testNoCandidatesIsRefused, ...
    @testTargetOutsideTheRunIsRefused, ...
    @testExclusionWithoutAReasonIsRefused, ...
    @testCalibratedPolicyIsRefused, ...
    @testRunCompletesOnlyWhenEveryTargetIsDecided, ...
    @testCompletionFreezesEvidenceButNotDecisions, ...
    @testApplyIsAtomic, ...
    @testSchemaStillRefusesAnInconsistentSelection});
end

% --- statuses ------------------------------------------------------------

function testAssignedRequiresSeparationNotMerelyAThreshold(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% 0.90 clears the 0.5 threshold and the runner-up is far below it.
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
% 0.72 also clears 0.5, but 0.65 is within the 0.15 separation margin of it.
% Clearing a threshold is not the same as being distinguishable, and a layer
% that assigned here would be manufacturing confidence from a threshold.
scoreTarget(fixture, 2, [1 2 3], [0.72 0.65 0.10]);

result = decideAll(fixture, Targets=fixture.target_ids(1:2));
verifyEqual(testCase, statusFor(result, fixture, 1), "assigned");
verifyEqual(testCase, selectedCountFor(result, fixture, 1), 1);
verifyNotEqual(testCase, statusFor(result, fixture, 2), "assigned");

% The threshold recorded on an assignment is the one that actually bound it:
% separation, not the selection floor it had already cleared.
row = storedDecision(fixture, 1);
verifyEqual(testCase, row.applied_threshold, 0.15, AbsTol=1e-12);
verifyTrue(testCase, contains(row.applied_threshold_semantics, "separation_margin"));
clear cleanup
end

function testSimultaneousSelectsEveryIndependentlyStrongContender(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
% Both above the 0.7 co-occurrence bar and within the separation margin.
scoreTarget(fixture, 1, [1 2 3], [0.88 0.80 0.10]);
result = decideAll(fixture, Targets=fixture.target_ids(1));

verifyEqual(testCase, statusFor(result, fixture, 1), "simultaneous");
verifyEqual(testCase, selectedCountFor(result, fixture, 1), 2);

selected = selectedEntities(fixture, 1);
verifyEqual(testCase, sort(selected)', [1 2]);
clear cleanup
end

function testAmbiguousAndSimultaneousDifferOnlyByIndependentStrength(testCase)
% The distinction Q7 placed in the decision. Both targets have two contenders
% the policy cannot separate; only one pair is strong enough to claim that two
% animals called rather than that the evidence cannot tell them apart.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.88 0.80 0.10]);   % both above 0.7
scoreTarget(fixture, 2, [1 2 3], [0.60 0.55 0.10]);   % neither above 0.7
result = decideAll(fixture, Targets=fixture.target_ids(1:2));

verifyEqual(testCase, statusFor(result, fixture, 1), "simultaneous");
verifyEqual(testCase, statusFor(result, fixture, 2), "ambiguous");

% Same contender count on both. The count alone is not the claim; the schema's
% selection set is, and only one of them selects anybody.
verifyEqual(testCase, contenderCountFor(result, fixture, 1), 2);
verifyEqual(testCase, contenderCountFor(result, fixture, 2), 2);
verifyEqual(testCase, selectedCountFor(result, fixture, 1), 2);
verifyEqual(testCase, selectedCountFor(result, fixture, 2), 0);
clear cleanup
end

function testUnassignedWhenNothingIsSupportable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.30 0.20 0.10]);
result = decideAll(fixture, Targets=fixture.target_ids(1));

verifyEqual(testCase, statusFor(result, fixture, 1), "unassigned");
verifyEqual(testCase, selectedCountFor(result, fixture, 1), 0);

% Unassigned is an outcome of the rule running, so it records the threshold
% that bound it. Excluded is not, and records a reason instead.
row = storedDecision(fixture, 1);
verifyEqual(testCase, row.applied_threshold, 0.5, AbsTol=1e-12);
verifyEqual(testCase, row.exclusion_reason, "");
clear cleanup
end

function testExcludedWhenThePolicyCannotBeApplied(testCase)
% Distinct from unassigned: the rule did not run at all, because no candidate
% carried the value it reads. Reporting that as unassigned would present an
% absence of evidence as evidence of absence.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
execute(fixture.conn, "INSERT INTO attribution_candidates(" + ...
    "attribution_target_id,entity_id,source_label) VALUES(" + ...
    string(fixture.target_ids(1)) + ",1,'label only, no score')");
result = decideAll(fixture, Targets=fixture.target_ids(1));

verifyEqual(testCase, statusFor(result, fixture, 1), "excluded");
row = storedDecision(fixture, 1);
verifyTrue(testCase, contains(row.exclusion_reason, "no candidate carried"));
verifyTrue(testCase, isnan(row.applied_threshold));
clear cleanup
end

function testCallerDeclaredExclusionCarriesItsReason(testCase)
% VAWLUME does not invent QC failures from the numbers. A person declares one,
% and the reason travels with the decision.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.95 0.10 0.05]);
reason = "channel 2 clipped throughout this call; upstream scores untrustworthy";
result = decideAll(fixture, Targets=fixture.target_ids(1), ...
    Exclusions=struct(attribution_target_id=fixture.target_ids(1), reason=reason));

% Would have been assigned on its numbers alone.
verifyEqual(testCase, statusFor(result, fixture, 1), "excluded");
verifyEqual(testCase, storedDecision(fixture, 1).exclusion_reason, reason);
verifyEqual(testCase, selectedCountFor(result, fixture, 1), 0);
clear cleanup
end

% --- derived and re-derivable --------------------------------------------

function testPlanningWritesNothing(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
before = decisionRowCount(fixture);
result = vawlume.attribution.decide(fixture.conn, runRef(fixture), ...
    struct(), Targets=fixture.target_ids(1));

verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyEqual(testCase, height(result.decisions), 1);
verifyEqual(testCase, decisionRowCount(fixture), before);
clear cleanup
end

function testDifferentThresholdChangesTheDecisionAndNoCandidate(testCase)
% The test that proves the layers are actually separate. A decision layer that
% had absorbed its evidence would have to rewrite a candidate to change its mind.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.88 0.80 0.10]);

before = candidateFingerprint(fixture, 1);
first = decideAll(fixture, Targets=fixture.target_ids(1));
verifyEqual(testCase, statusFor(first, fixture, 1), "simultaneous");

% Raise only the co-occurrence bar above both contenders. Nothing else moves.
strictPolicy = variantPolicy(fixture, "0.2.0", struct( ...
    co_occurrence_threshold=0.95));
second = vawlume.attribution.decide(fixture.conn, runRef(fixture), ...
    struct(profile_path=strictPolicy), Apply=true, ...
    Targets=fixture.target_ids(1));

verifyEqual(testCase, statusFor(second, fixture, 1), "ambiguous");
verifyEqual(testCase, candidateFingerprint(fixture, 1), before, ...
    "A decision must never alter the candidates it was derived from.");

% Both decisions survive, which is what lets a later phase compare policies
% over one body of evidence.
stored = fetch(fixture.conn, "SELECT decision_status AS s FROM attribution_decisions " + ...
    "WHERE attribution_target_id=" + string(fixture.target_ids(1)) + ...
    " ORDER BY attribution_decision_id");
verifyEqual(testCase, sort(string(stored.s))', sort(["simultaneous" "ambiguous"]));
clear cleanup
end

function testTheSamePolicyTwiceGivesTheSameDecision(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
first = vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
    Targets=fixture.target_ids(1));
second = vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
    Targets=fixture.target_ids(1));
verifyEqual(testCase, first.decisions.decision_status, second.decisions.decision_status);
verifyEqual(testCase, first.decisions.applied_threshold, ...
    second.decisions.applied_threshold, AbsTol=1e-12);
clear cleanup
end

function testDecisionIsInterpretableFromTheStoredRowAlone(testCase)
% A decision read back years later must be readable without this code: which
% policy, which version, which content, and which threshold bound it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
decideAll(fixture, Targets=fixture.target_ids(1));

row = fetch(fixture.conn, "SELECT d.decision_status AS status, " + ...
    "IFNULL(d.applied_threshold,-1.0) AS threshold, " + ...
    "IFNULL(d.applied_threshold_semantics,'') AS semantics, " + ...
    "p.profile_key AS policy_key, v.version_label AS version, " + ...
    "IFNULL(v.checksum_sha256,'') AS checksum, " + ...
    "IFNULL(v.content_uri,'') AS uri, p.profile_kind AS kind " + ...
    "FROM attribution_decisions d " + ...
    "JOIN config_profile_versions v ON v.profile_version_id=d.policy_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id=v.profile_id " + ...
    "WHERE d.attribution_target_id=" + string(fixture.target_ids(1)));

verifyEqual(testCase, string(row.kind(1)), "attribution_policy");
verifyEqual(testCase, string(row.version(1)), "0.1.0");
verifyEqual(testCase, strlength(string(row.checksum(1))), 64);
verifyTrue(testCase, contains(string(row.uri(1)), "08_attribution_policies"));
verifyTrue(testCase, contains(string(row.semantics(1)), "uncalibrated"));
verifyTrue(testCase, contains(string(row.semantics(1)), "not a probability"));
clear cleanup
end

% --- refusals ------------------------------------------------------------

function testNoCandidatesIsRefused(testCase)
% A target with no candidates is an unfinished analysis, not an outcome.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefused(testCase, ...
    @() vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
        Targets=fixture.target_ids(1)), ...
    "vawlume:attribution:NoCandidates");
clear cleanup
end

function testDecidingTwiceUnderOnePolicyIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
decideAll(fixture, Targets=fixture.target_ids(1));

repeat = vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
    Targets=fixture.target_ids(1));
verifyEqual(testCase, repeat.status, "conflict");
verifyTrue(testCase, repeat.has_conflicts);
verifyEqual(testCase, string(repeat.decisions.action(1)), "conflict");

% Apply on a conflicting plan writes nothing rather than replacing the first.
before = decisionRowCount(fixture);
applied = vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
    Apply=true, Targets=fixture.target_ids(1));
verifyEqual(testCase, applied.status, "conflict");
verifyEqual(testCase, decisionRowCount(fixture), before);
clear cleanup
end

function testTargetOutsideTheRunIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefused(testCase, ...
    @() vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
        Targets=99999), ...
    "vawlume:attribution:TargetNotInRun");
clear cleanup
end

function testExclusionWithoutAReasonIsRefused(testCase)
% An excluded decision that does not say why is not a QC record.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
verifyRefused(testCase, ...
    @() vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
        Targets=fixture.target_ids(1), ...
        Exclusions=struct(attribution_target_id=fixture.target_ids(1), reason="  ")), ...
    "vawlume:attribution:ExclusionInvalid");
clear cleanup
end

function testCalibratedPolicyIsRefused(testCase)
% No calibrated threshold ships, and a policy claiming calibration must name
% the evidence that calibrated it. Nothing in this prototype can.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
claimed = variantPolicy(fixture, "9.9.9", struct(), "calibrated");
verifyRefused(testCase, ...
    @() vawlume.attribution.decide(fixture.conn, runRef(fixture), ...
        struct(profile_path=claimed), Targets=fixture.target_ids(1)), ...
    "vawlume:attribution:PolicyNotIllustrative");
clear cleanup
end

% --- run completion ------------------------------------------------------

function testRunCompletesOnlyWhenEveryTargetIsDecided(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
for index = 1:numel(fixture.target_ids)
    scoreTarget(fixture, index, [1 2 3], [0.90 0.40 0.10]);
end

partial = decideAll(fixture, Targets=fixture.target_ids(1));
verifyFalse(testCase, partial.run_completed);
verifyEqual(testCase, runStatus(fixture), "planned");

complete = decideAll(fixture, Targets=fixture.target_ids(2:end));
verifyTrue(testCase, complete.run_completed);
verifyEqual(testCase, runStatus(fixture), "complete");
verifyEqual(testCase, analysisStatus(fixture), "completed");
clear cleanup
end

function testCompletionFreezesEvidenceButNotDecisions(testCase)
% Completion freezes the evidence a decision was derived from, so a later
% policy compares against the same candidates rather than a moved target. It
% deliberately does not freeze the decision set: comparing policies over one
% body of evidence is the point of keeping the layers apart.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
for index = 1:numel(fixture.target_ids)
    scoreTarget(fixture, index, [1 2 3], [0.88 0.80 0.10]);
end
decideAll(fixture);
verifyEqual(testCase, runStatus(fixture), "complete");

% Evidence is frozen.
verifyRefused(testCase, ...
    @() vawlume.attribution.addCandidates(fixture.conn, ...
        struct(attribution_target_id=fixture.target_ids(1)), ...
        struct(entity_id=4), Apply=true), ...
    "vawlume:attribution:RunNotWritable");

% A further policy is not.
strictPolicy = variantPolicy(fixture, "0.3.0", struct(co_occurrence_threshold=0.95));
second = vawlume.attribution.decide(fixture.conn, runRef(fixture), ...
    struct(profile_path=strictPolicy), Apply=true);
verifyEqual(testCase, second.status, "decided");
verifyEqual(testCase, statusFor(second, fixture, 1), "ambiguous");
clear cleanup
end

% --- atomicity and schema agreement --------------------------------------

function testApplyIsAtomic(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
for index = 1:numel(fixture.target_ids)
    scoreTarget(fixture, index, [1 2 3], [0.90 0.40 0.10]);
end
before = decisionRowCount(fixture);

% Keyed on a condition certain to be reached: the third decision insert of this
% run, whatever order the targets take. An ordering assumption here would make
% the test pass vacuously.
execute(fixture.conn, "CREATE TRIGGER trg_induced_decision_failure " + ...
    "BEFORE INSERT ON attribution_decisions FOR EACH ROW " + ...
    "WHEN (SELECT COUNT(*) FROM attribution_decisions) >= 2 " + ...
    "BEGIN SELECT RAISE(ABORT,'induced late decision failure'); END");
threw = false;
try
    decideAll(fixture);
catch
    threw = true;
end
execute(fixture.conn, "DROP TRIGGER trg_induced_decision_failure");

verifyTrue(testCase, threw, "The induced failure must propagate.");
verifyEqual(testCase, decisionRowCount(fixture), before, ...
    "A failed apply must leave no partial decision.");
verifyEqual(testCase, selectionRowCount(fixture), 0);
verifyEqual(testCase, runStatus(fixture), "planned");
clear cleanup
end

function testSchemaStillRefusesAnInconsistentSelection(testCase)
% The public path cannot produce these, because the policy chooses the
% selection set rather than the caller naming it. The schema guards remain the
% backstop for direct SQL, and this asserts they are still armed.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
scoreTarget(fixture, 1, [1 2 3], [0.90 0.40 0.10]);
scoreTarget(fixture, 2, [1 2 3], [0.90 0.40 0.10]);
decideAll(fixture, Targets=fixture.target_ids(1));

decisionId = fetch(fixture.conn, "SELECT attribution_decision_id AS id " + ...
    "FROM attribution_decisions WHERE attribution_target_id=" + ...
    string(fixture.target_ids(1)));
otherCandidate = fetch(fixture.conn, "SELECT attribution_candidate_id AS id " + ...
    "FROM attribution_candidates WHERE attribution_target_id=" + ...
    string(fixture.target_ids(2)) + " LIMIT 1");

refused = false;
try
    execute(fixture.conn, "INSERT INTO attribution_decision_candidates(" + ...
        "attribution_decision_id,attribution_candidate_id) VALUES(" + ...
        string(double(decisionId.id(1))) + "," + ...
        string(double(otherCandidate.id(1))) + ")");
catch err
    refused = true;
    verifyTrue(testCase, contains(err.message, "different attribution target"));
end
verifyTrue(testCase, refused, ...
    "A selection naming another target's candidate must still be refused.");
clear cleanup
end

% ---------------------------------------------------------------- helpers ---

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
% The identifier matters as much as the refusal: a refusal from an unrelated
% guard would prove nothing about the rule under test.
verifyEqual(testCase, observed, string(identifier));
end

function result = decideAll(fixture, varargin)
result = vawlume.attribution.decide(fixture.conn, runRef(fixture), struct(), ...
    "Apply", true, varargin{:});
end

function value = runRef(fixture)
value = struct(attribution_run_id=fixture.attribution_run_id);
end

function scoreTarget(fixture, targetIndex, entities, scores)
semantics = "external system posterior-like score, uncalibrated, " + ...
    "meaningful on [0,1], not a calibrated probability";
rows = struct('entity_id', {}, 'score', {}, 'score_semantics', {});
for index = 1:numel(entities)
    rows(index) = struct(entity_id=entities(index), score=scores(index), ...
        score_semantics=semantics);
end
vawlume.attribution.addCandidates(fixture.conn, ...
    struct(attribution_target_id=fixture.target_ids(targetIndex)), rows, Apply=true);
end

function value = statusFor(result, fixture, targetIndex)
match = double(result.decisions.attribution_target_id) == fixture.target_ids(targetIndex);
value = string(result.decisions.decision_status(match));
end

function value = selectedCountFor(result, fixture, targetIndex)
match = double(result.decisions.attribution_target_id) == fixture.target_ids(targetIndex);
value = double(result.decisions.selected_count(match));
end

function value = contenderCountFor(result, fixture, targetIndex)
match = double(result.decisions.attribution_target_id) == fixture.target_ids(targetIndex);
value = double(result.decisions.contender_count(match));
end

function row = storedDecision(fixture, targetIndex)
stored = fetch(fixture.conn, "SELECT decision_status AS status, " + ...
    "CASE WHEN applied_threshold IS NULL THEN 1 ELSE 0 END AS threshold_missing, " + ...
    "IFNULL(applied_threshold,-1.0) AS applied_threshold, " + ...
    "IFNULL(applied_threshold_semantics,'') AS applied_threshold_semantics, " + ...
    "IFNULL(exclusion_reason,'') AS exclusion_reason " + ...
    "FROM attribution_decisions WHERE attribution_target_id=" + ...
    string(fixture.target_ids(targetIndex)) + " ORDER BY attribution_decision_id LIMIT 1");
threshold = double(stored.applied_threshold(1));
if double(stored.threshold_missing(1)) == 1
    threshold = NaN;
end
row = struct(status=presentText(stored.status(1)), applied_threshold=threshold, ...
    applied_threshold_semantics=presentText(stored.applied_threshold_semantics(1)), ...
    exclusion_reason=presentText(stored.exclusion_reason(1)));
end

function value = presentText(raw)
% An IFNULL that produced an empty string comes back as <missing> from the
% Database Toolbox, not as "". Normalising here keeps the assertions about
% absence readable.
value = string(raw);
value(ismissing(value)) = "";
end

function value = selectedEntities(fixture, targetIndex)
rows = fetch(fixture.conn, "SELECT c.entity_id AS e " + ...
    "FROM attribution_decision_candidates dc " + ...
    "JOIN attribution_candidates c " + ...
    "  ON c.attribution_candidate_id = dc.attribution_candidate_id " + ...
    "JOIN attribution_decisions d " + ...
    "  ON d.attribution_decision_id = dc.attribution_decision_id " + ...
    "WHERE d.attribution_target_id=" + string(fixture.target_ids(targetIndex)));
value = double(rows.e);
end

function value = candidateFingerprint(fixture, targetIndex)
rows = fetch(fixture.conn, "SELECT entity_id, candidate_status, " + ...
    "IFNULL(candidate_rank,-1) AS candidate_rank, IFNULL(score,-1.0) AS score, " + ...
    "IFNULL(score_semantics,'') AS score_semantics, " + ...
    "IFNULL(probability,-1.0) AS probability, " + ...
    "IFNULL(source_label,'') AS source_label " + ...
    "FROM attribution_candidates WHERE attribution_target_id=" + ...
    string(fixture.target_ids(targetIndex)) + " ORDER BY entity_id");
value = string(jsonencode(rows));
end

function value = decisionRowCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_decisions");
value = double(rows.n(1));
end

function value = selectionRowCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_decision_candidates");
value = double(rows.n(1));
end

function value = runStatus(fixture)
rows = fetch(fixture.conn, "SELECT status FROM attribution_runs " + ...
    "WHERE attribution_run_id=" + string(fixture.attribution_run_id));
value = string(rows.status(1));
end

function value = analysisStatus(fixture)
rows = fetch(fixture.conn, "SELECT a.status AS status FROM analysis_runs a " + ...
    "JOIN attribution_runs r ON r.analysis_run_id = a.analysis_run_id " + ...
    "WHERE r.attribution_run_id=" + string(fixture.attribution_run_id));
value = string(rows.status(1));
end

function path = variantPolicy(fixture, versionLabel, overrides, calibrationState)
%VARIANTPOLICY Write a policy differing from the shipped one in stated ways.
if nargin < 4
    calibrationState = "illustrative_prototype";
end
document = jsondecode(fileread(fullfile(fixture.repo_root, "config", ...
    "08_attribution_policies", "prototype_attribution_decision_policy.json")));
document.profile.profile_version = char(versionLabel);
document.calibration_status.state = char(calibrationState);
names = string(fieldnames(overrides));
for index = 1:numel(names)
    document.thresholds.(names(index)) = overrides.(names(index));
end
path = fullfile(fixture.workspace, "policy_" + versionLabel + ".json");
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document, PrettyPrint=true));
fclose(fileId);
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
% Add src/ only if it is absent, and remove it only if this fixture added it.
% Removing a path the caller supplied breaks every later test in the suite that
% assumed it was there, and passes in isolation.
sourcePath = fullfile(repoRoot, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_decide_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
dbFile = fullfile(workspace, "decide.sqlite");
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
seedFixture(conn);

spec = struct(run_key="phase46-run", attribution_path="imported", ...
    method="External Caller 2.0", settings_profile_version_id=1, ...
    target_set=struct(detection_ids=[1 2 3]), ...
    participating_entity_ids=[1 2 3], ...
    sources=struct(source_file_ids=2), ...
    notes="Synthetic Phase 4.6 fixture.");
run = vawlume.attribution.createRun(conn, struct(recording_id=1), spec, Apply=true);

targets = fetch(conn, "SELECT attribution_target_id AS id FROM attribution_targets " + ...
    "ORDER BY attribution_target_id");
fixture = struct(conn=conn, workspace=string(workspace), ...
    repo_root=string(repoRoot), ...
    attribution_run_id=run.run.attribution_run_id, ...
    target_ids=double(targets.id)');
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
    "path_or_uri,relative_path) VALUES" + ...
    "(1,1,'recording_audio','audio.wav','audio.wav')," + ...
    "(2,1,'attribution_output','caller.csv','caller.csv')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'C'),(4,1,1,'D')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES" + ...
    "(1,1,1,'participant'),(2,1,2,'participant'),(3,1,3,'participant')," + ...
    "(4,1,4,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key," + ...
    "profile_name,profile_kind) VALUES" + ...
    "(1,1,'caller-input','Caller input mapping','attribution_input_mapping')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id," + ...
    "version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1.0.0','json','config/caller.json'," + ...
    "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) " + ...
    "VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES" + ...
    "(1,1,1,1.0,1.5),(2,1,1,2.0,2.5),(3,1,1,3.0,3.5)");
end

function root = repoRootForTest()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
