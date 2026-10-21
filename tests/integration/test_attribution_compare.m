function tests = test_attribution_compare
%TEST_ATTRIBUTION_COMPARE Itinerary 7.6: vawlume.attribution.compare on one event set.
%
% Contract 07 D1, D3-D5. The 7.3 integrated fixture carries the cross-path
% scenes (one build per class); a small seeded database carries the rules that
% need runs the fixture does not have (two native runs, two settings versions,
% two decision policies, another recording).
%
% Every agreement asserted on the fixture is circular: this repository wrote
% every path's input. These tests show that the comparison joins and reports
% correctly, never that any run is right.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=root);
testCase.TestData.root = root;
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ====================================================== the three paths ===

function testThreePathsCompareOnTheirSharedTargets(testCase)
f = testCase.TestData.fixture;
m = f.manifest;
for pair = ["imported", "backend"; "imported", "native_detections"; "backend", "native_detections"]'
    c = compareRuns(f, pair(1), pair(2));
    label = pair(1) + " vs " + pair(2);
    verifyEqual(testCase, height(c.units), 7, label);
    verifyTrue(testCase, all(c.units.correspondence_unit == "one_to_one"), label);
    verifyEqual(testCase, c.units.event_id, sort(m.scenes.deepsqueak_detection_id), label);
    verifyEqual(testCase, c.status_counts.one_to_one_units(1), 7, label);
end
end

function testTheConstructedDisagreementIsReported(testCase)
% Separable, as stored: native and backend assign A (M012), imported assigns B
% (F031), each with status "assigned". (The 7.3 handoff's scene table lists
% backend as B; the stored claims are A 0.92 / B 0.15, so storage wins.)
f = testCase.TestData.fixture;
m = f.manifest;
event = m.scenes.deepsqueak_detection_id(m.scenes.scene == "separable");
expected = ["imported", "native_detections", "different", "disjoint"
    "imported", "backend", "different", "disjoint"
    "backend", "native_detections", "same", "equal"];
for k = 1:size(expected, 1)
    c = compareRuns(f, expected(k, 1), expected(k, 2));
    unit = c.units(c.units.event_id == event, :);
    label = expected(k, 1) + " vs " + expected(k, 2);
    verifyEqual(testCase, unit.top_entity_agreement, expected(k, 3), label);
    verifyEqual(testCase, unit.selected_set_relation, expected(k, 4), label);
    % Both statuses are "assigned", so the status cross-tab agrees; the
    % disagreement about WHO is the unit row's, and it is reported, not collapsed.
    verifyEqual(testCase, [unit.left_decision_status, unit.right_decision_status], ...
        ["assigned", "assigned"], label);
end
end

function testSimultaneousAgainstANativeStatusIsAStructuralEmpty(testCase)
f = testCase.TestData.fixture;
m = f.manifest;
event = m.scenes.deepsqueak_detection_id(m.scenes.scene == "symmetric");
c = compareRuns(f, "imported", "native_detections");
unit = c.units(c.units.event_id == event, :);
verifyEqual(testCase, [unit.left_decision_status, unit.right_decision_status], ...
    ["simultaneous", "ambiguous"]);
cell_ = c.status_crosstab(c.status_crosstab.left_decision_status == "simultaneous" & ...
    c.status_crosstab.right_decision_status == "ambiguous", :);
verifyEqual(testCase, [cell_.unit_count, string(cell_.cell_kind)], ["1", "structural_empty"]);
% Every cell with simultaneous on the native side is structurally empty.
native = c.status_crosstab(c.status_crosstab.right_decision_status == "simultaneous", :);
verifyTrue(testCase, all(native.cell_kind == "structural_empty"));
verifyEqual(testCase, c.sides.producible_statuses(2), "assigned,ambiguous,unassigned,excluded", ...
    "Derived from the native policy's rule key, not from a list of paths.");
% Against backend, whose rule can say simultaneous, the same pair is a disagreement.
c = compareRuns(f, "imported", "backend");
cell_ = c.status_crosstab(c.status_crosstab.left_decision_status == "simultaneous" & ...
    c.status_crosstab.right_decision_status == "ambiguous", :);
verifyEqual(testCase, [cell_.unit_count, string(cell_.cell_kind)], ["1", "disagree"]);
end

function testCountsNeverIncludeStructuralEmptiesOrUndecidedTargets(testCase)
f = testCase.TestData.fixture;
for pair = ["imported", "native_detections"; "backend", "native_detections"]'
    c = compareRuns(f, pair(1), pair(2));
    counts = c.status_counts;
    verifyEqual(testCase, sum(counts.unit_count), counts.one_to_one_units(1));
    agreeing = counts.unit_count(counts.cell_kind == "agree");
    disagreeing = counts.unit_count(counts.cell_kind == "disagree");
    tab = c.status_crosstab;
    verifyEqual(testCase, agreeing, sum(tab.unit_count(tab.cell_kind == "agree")));
    verifyEqual(testCase, disagreeing, sum(tab.unit_count(tab.cell_kind == "disagree")));
    verifyFalse(testCase, any(tab.cell_kind == "agree" & ...
        (tab.left_decision_status == "excluded" | tab.right_decision_status == "excluded")));
end
end

function testImportedDeclaredInputsAreUnknown(testCase)
f = testCase.TestData.fixture;
c = compareRuns(f, "imported", "native_detections");
for dim = ["temporal_alignment", "pose_localization", "visual_identity", "acoustic"]
    verifyTrue(testCase, all(c.units.("left_declared_" + dim) == "unknown"), dim);
    verifyTrue(testCase, all(ismember(c.units.("right_declared_" + dim), ["used", "not_used"])), dim);
end
end

function testUnscoredCandidatesAndExclusionsCarryTheirReasons(testCase)
f = testCase.TestData.fixture;
m = f.manifest;
c = compareRuns(f, "imported", "native_detections");
for scene = ["coverage_gap", "identity_swap", "out_of_bracket"]
    target = m.scenes.native_detection_target_id(m.scenes.scene == scene);
    unit = c.units(cellfun(@(ids) isequal(ids, target), c.units.right_target_ids), :);
    verifyEqual(testCase, unit.top_entity_agreement, "right_unscored", scene);
    reasons = c.reasons(c.reasons.side == "right" & c.reasons.attribution_target_id == target, :);
    verifyGreaterThan(testCase, nnz(reasons.category == "unscored_candidate"), 0, scene);
    verifyEqual(testCase, unit.right_decision_status, "excluded", scene);
    verifyEqual(testCase, nnz(reasons.category == "excluded_decision"), 1, scene);
end
end

function testWindowsAndClaimsAreReportedNotDropped(testCase)
f = testCase.TestData.fixture;
c = compareRuns(f, "imported", "backend");
for side = ["left", "right"]
    windows = c.windows(c.windows.side == side, :);
    verifyEqual(testCase, height(windows), 7, side);
    counts = c.claim_counts(c.claim_counts.side == side, :);
    claims = c.claims(c.claims.side == side, :);
    verifyEqual(testCase, counts.claims_promoted + counts.claims_not_promoted, height(claims), side);
    verifyEqual(testCase, counts.windows_uncorresponded, ...
        nnz(windows.correspondence_status == "uncorresponded"), side);
end
c = compareRuns(f, "imported", "native_detections");
verifyEqual(testCase, height(c.windows(c.windows.side == "right", :)), 0, ...
    "A native run has no windows; the table is empty, not absent.");
end

% ============================================================== refusals ===

function testValuesAcrossPathsAreRefusedByName(testCase)
f = testCase.TestData.fixture;
c = compareRuns(f, "imported", "native_detections");
verifyTrue(testCase, all(c.units.score_comparability == "not_comparable:producer_scale"));
verifyEqual(testCase, height(c.scores), 0);
verifyError(testCase, @() compareRuns(f, "imported", "native_detections", ...
    CompareScores=true), "vawlume:attribution:ScoreNotComparable");
verifyError(testCase, @() compareRuns(f, "imported", "backend", CompareScores=true), ...
    "vawlume:attribution:ScoreNotComparable");
end

function testDifferentEventSetsAreRefusedPointingToCorrespondence(testCase)
f = testCase.TestData.fixture;
try
    compareRuns(f, "native_detections", "native_consensus");
    verifyFail(testCase, "Detections against consensus events must be refused.");
catch failure
    verifyEqual(testCase, string(failure.identifier), ...
        "vawlume:attribution:CorrespondenceAnalysisRequired");
    verifySubstring(testCase, string(failure.message), "Correspondence option");
end
end

% ===================================================== read-only, stable ===

function testTheComparisonIsReadOnly(testCase)
f = testCase.TestData.fixture;
before = state(f.conn);
compareRuns(f, "imported", "native_detections");
compareRuns(f, "backend", "imported");
verifyEqual(testCase, state(f.conn), before, "data_version and total_changes unchanged");
end

function testTheComparisonIsDeterministicAcrossCallsAndRebuilds(testCase)
f = testCase.TestData.fixture;
first = compareRuns(f, "imported", "native_detections");
verifyEqual(testCase, compareRuns(f, "imported", "native_detections"), first);
[rebuilt, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=testCase.TestData.root); %#ok<ASGLU>
again = compareRuns(rebuilt, "imported", "native_detections");
% The two builds are row-identical (7.3), so ids agree; the policy paths do not
% enter the result.
verifyEqual(testCase, again, first);
end

% =================================================== the closed vocabulary ===

function testTheOutputIsAClosedVocabularyAndCombinesNothing(testCase)
% Guard (contract 07 D4, itinerary 7.6 C): every field and column is named in
% the closed list, none matches a combining name, and every categorical value
% is in its vocabulary.
f = testCase.TestData.fixture;
c = compareRuns(f, "imported", "native_detections");
names = outputNames(c);
unknown = setdiff(names, closedNames());
verifyEmpty(testCase, unknown, "Names outside the closed vocabulary: " + strjoin(unknown, ", "));
forbidden = names(~cellfun(@isempty, regexp(names, ...
    "best|winner|combined|consensus|overall|optimal|composite|agreement_score|preferred", "once")));
verifyEmpty(testCase, forbidden, "Combining names: " + strjoin(forbidden, ", "));
verifyTrue(testCase, all(ismember(c.units.top_entity_agreement, ["same", "different", ...
    "tie_left", "tie_right", "left_unscored", "right_unscored", "both_unscored", ...
    "orientation_unknown", "not_applicable_unit"])));
verifyTrue(testCase, all(ismember(c.units.selected_set_relation, ["equal", "disjoint", ...
    "subset", "superset", "overlap", "left_empty", "right_empty", "both_empty", ...
    "not_applicable_unit"])));
verifyTrue(testCase, all(ismember(c.status_crosstab.cell_kind, ["agree", "disagree", ...
    "structural_empty", "excluded", "undecided"])));
end

function testCompareWritesNothingAndCallsNoProducer(testCase)
% Static: no SQL write, and no call to a producer or decide, in compare or its
% private per-target helper.
root = testCase.TestData.root;
files = [fullfile(root, "src", "+vawlume", "+attribution", "compare.m"), ...
    fullfile(root, "src", "+vawlume", "+attribution", "private", "attributionCompareTargets.m")];
banned = ["\<INSERT\s", "\<UPDATE\s", "\<DELETE\s", "\<DROP\s", "\<ALTER\s", ...
    "sqlwrite\(", "sqlupdate\(", "execute\(", "decide\(", "addCandidates\(", ...
    "addEvidence\(", "createRun\(", "declareInputs\(", "correspondWindows\(", ...
    "vawlume\.estimator\.", "vawlume\.ingest\.", "vawlume\.acoustic\.", ...
    "vawlume\.alignment\.fit"];
for file = files
    code = codeLines(file);
    for pattern = banned
        hits = code(~cellfun(@isempty, regexp(code, pattern, "once")));
        verifyEmpty(testCase, hits, file + " matches " + pattern + ": " + strjoin(hits, " | "));
    end
end
end

% ========================================================= seeded rules ===

function testNativeScoresCompareOnlyUnderOneSettingsVersion(testCase)
s = seeded(testCase);
a = nativeRun(s, "native-a", s.settings_version, [-0.5 -6; -1 -1.2]);
b = nativeRun(s, "native-b", s.settings_version, [-0.7 -5; -1.1 -1.0]);
c = vawlume.attribution.compare(s.conn, a, b, CompareScores=true);
verifyTrue(testCase, all(c.units.score_comparability == "comparable"));
verifyEqual(testCase, height(c.scores), 4);
verifyEqual(testCase, c.scores.left_score(c.scores.unit_id == 1 & c.scores.entity_id == 1), -0.5);
verifyEqual(testCase, c.scores.right_score(c.scores.unit_id == 1 & c.scores.entity_id == 1), -0.7);
verifyEqual(testCase, c.units.top_entity_agreement, ["same"; "different"]);

v = nativeRun(s, "native-v2", s.variant_settings_version, [-0.5 -6; -1 -1.2]);
c = vawlume.attribution.compare(s.conn, a, v);
verifyTrue(testCase, all(c.units.score_comparability == "not_comparable:settings_profile_version"));
verifyError(testCase, @() vawlume.attribution.compare(s.conn, a, v, CompareScores=true), ...
    "vawlume:attribution:ScoreNotComparable");
end

function testARunWithSeveralDecisionSetsMustNameOne(testCase)
s = seeded(testCase);
a = nativeRun(s, "native-a", s.settings_version, [-0.5 -6; -1 -1.2]);
b = nativeRun(s, "native-b", s.settings_version, [-0.7 -5; -1.1 -1.0]);
vawlume.attribution.decide(s.conn, a, s.variant_policy, Apply=true, RepoRoot=s.root);
verifyError(testCase, @() vawlume.attribution.compare(s.conn, a, b), ...
    "vawlume:attribution:DecisionPolicyRequired");
versions = fetch(s.conn, "SELECT DISTINCT policy_profile_version_id AS id FROM " + ...
    "attribution_decisions ORDER BY id");
ids = double(versions.id);
c = vawlume.attribution.compare(s.conn, a, b, LeftPolicy=ids(2));
verifyEqual(testCase, c.sides.policy_profile_version_id(1), ids(2));
c = vawlume.attribution.compare(s.conn, a, b, LeftPolicy=struct( ...
    policy_profile_key="vawlume.attribution.decision.native_level_difference", ...
    policy_version_label=s.variant_policy_version));
verifyEqual(testCase, c.sides.policy_version_label(1), s.variant_policy_version);
verifyError(testCase, @() vawlume.attribution.compare(s.conn, a, b, LeftPolicy=999), ...
    "vawlume:attribution:DecisionPolicyNotFound");
end

function testRanksNeedADeclaredOrientation(testCase)
s = seeded(testCase);
unranked = importedRun(s, "imported-unranked", 1, false);
ranked = importedRun(s, "imported-ranked", 1, true);
c = vawlume.attribution.compare(s.conn, unranked, ranked);
verifyEqual(testCase, c.sides.rank_basis, ["candidate_rank"; "candidate_rank"]);
verifyTrue(testCase, all(c.units.top_entity_agreement == "orientation_unknown"), ...
    "No policy and no rank: no top entity is invented.");
other = importedRun(s, "imported-ranked-2", 1, true);
c = vawlume.attribution.compare(s.conn, ranked, other);
verifyTrue(testCase, all(c.units.top_entity_agreement == "same"));
verifyTrue(testCase, all(c.units.left_decision_status == "no_decision"));
verifyTrue(testCase, all(c.status_crosstab.cell_kind(c.status_crosstab.unit_count > 0) == "undecided"));
end

function testRunsOfDifferentRecordingsAreRefused(testCase)
s = seeded(testCase);
here = importedRun(s, "imported-here", 1, true);
there = importedRun(s, "imported-there", 2, true);
verifyError(testCase, @() vawlume.attribution.compare(s.conn, here, there), ...
    "vawlume:attribution:ComparisonRecordingMismatch");
end

% --------------------------------------------------------------- helpers ---

function c = compareRuns(f, left, right, varargin)
m = f.manifest;
c = vawlume.attribution.compare(f.conn, ...
    struct(attribution_run_id=m.runs.(left).attribution_run_id), ...
    struct(attribution_run_id=m.runs.(right).attribution_run_id), varargin{:});
end

function value = state(conn)
version = fetch(conn, "PRAGMA data_version");
changes = fetch(conn, "SELECT total_changes() AS n");
value = [double(version{1, 1}), double(changes.n(1))];
end

function names = outputNames(c)
names = string(fieldnames(c))';
for field = string(fieldnames(c))'
    if istable(c.(field))
        names = [names, string(c.(field).Properties.VariableNames)]; %#ok<AGROW>
    end
end
names = unique(names);
end

function names = closedNames()
dims = ["temporal_alignment", "pose_localization", "visual_identity", "acoustic"];
names = ["sides", "units", "pairs", "status_crosstab", "status_counts", "reasons", ...
    "windows", "claims", "claim_counts", "scores", "lineage_note", "comparison_note", ...
    "source", ...
    "side", "attribution_run_id", "run_key", "attribution_path", "method", ...
    "settings_profile_version_id", "recording_id", "target_kind", ...
    "target_source_kind", "target_source_id", "policy_profile_version_id", ...
    "policy_profile_key", "policy_version_label", "policy_read_status", ...
    "policy_rule_key", "producible_statuses", "rank_basis", ...
    "unit_id", "correspondence_unit", "event_kind", "event_id", ...
    "agreement_extent_method", "left_target_ids", "right_target_ids", ...
    "top_entity_agreement", "selected_set_relation", "left_decision_status", ...
    "right_decision_status", "left_declared_" + dims, "right_declared_" + dims, ...
    "score_comparability", "left_target_id", "right_target_id", ...
    "unit_count", "cell_kind", "one_to_one_units", ...
    "attribution_target_id", "entity_id", "category", "reason_ordinal", "reason_code", ...
    "imported_attribution_window_id", "native_window_id", "correspondence_count", ...
    "correspondence_status", "corresponded_target_ids", ...
    "imported_attribution_claim_id", "source_caller_label", "promoted", ...
    "claims_promoted", "claims_not_promoted", "windows_uncorresponded", ...
    "left_score", "right_score", "left_score_semantics", "right_score_semantics"];
end

function code = codeLines(file)
lines = splitlines(string(fileread(file)));
lines = lines(~startsWith(strtrim(lines), "%"));
code = regexprep(lines, "%.*$", "");
code = code(strlength(strtrim(code)) > 0)';
end

function s = seeded(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
file = string(tempname) + ".sqlite";
conn = sqlite(char(file), "create");
work = string(tempname);
mkdir(work);
testCase.addTeardown(@() closeAndDelete(conn, file, work));
vawlume.db.applySchema(conn, fullfile(root, "schema", "schema.sql"));
seed(conn);
settings = vawlume.estimator.loadSettings(RepoRoot=root);
registered = vawlume.db.registerProfileVersion(conn, struct(project_id=1), ...
    settingsSpec(settings, settings.version_label, settings.path), RepoRoot=root);
% A second, deliberately different settings version: a copy under another label.
document = jsondecode(fileread(settings.path));
document.profile.profile_version = char(settings.version_label + "-variant");
variantPath = fullfile(work, "estimator_settings_variant.json");
writeText(variantPath, jsonencode(document, PrettyPrint=true));
variant = vawlume.db.registerProfileVersion(conn, struct(project_id=1), ...
    settingsSpec(settings, settings.version_label + "-variant", variantPath), RepoRoot=root);
% A second decision policy version: the native policy under another label.
policyPath = fullfile(root, "config", "08_attribution_policies", ...
    "native_level_difference_decision_policy.json");
policy = jsondecode(fileread(policyPath));
policy.profile.profile_version = char(string(policy.profile.profile_version) + "-variant");
variantPolicy = fullfile(work, "native_policy_variant.json");
writeText(variantPolicy, jsonencode(policy, PrettyPrint=true));
s = struct(root=root, conn=conn, settings=settings, ...
    settings_version=registered.profile_version_id, ...
    variant_settings_version=variant.profile_version_id, policy=policyPath, ...
    variant_policy=variantPolicy, variant_policy_version=string(policy.profile.profile_version));
end

function spec = settingsSpec(settings, label, path)
spec = struct(profile_key=settings.profile_key, profile_name=settings.profile_name, ...
    version_label=label, content_path=path, profile_kind=settings.profile_kind, ...
    profile_schema_version=settings.profile_schema_version);
end

function ref = nativeRun(s, key, settingsVersion, scores)
% A native_estimate run over detections 1 and 2, written through the canonical
% writers and decided under the shipped native policy.
created = vawlume.attribution.createRun(s.conn, struct(recording_id=1), struct( ...
    run_key=key, attribution_path="native_estimate", ...
    method="vawlume.estimator.level_difference_consistency 1.0.0", ...
    settings_profile_version_id=settingsVersion, target_set=struct(detection_ids=[1 2]), ...
    participating_entity_ids=[1 2], sources=struct(source_file_ids=1), ...
    declared_inputs=s.settings.declared_inputs), Apply=true);
for k = 1:2
    vawlume.attribution.addCandidates(s.conn, ...
        struct(attribution_target_id=created.targets.attribution_target_id(k)), ...
        struct(entity_id={1; 2}, score={scores(k, 1); scores(k, 2)}, ...
        score_semantics={"dB; not a probability"; "dB; not a probability"}), Apply=true);
end
ref = struct(attribution_run_id=created.run.attribution_run_id);
vawlume.attribution.decide(s.conn, ref, s.policy, Apply=true, RepoRoot=s.root);
end

function ref = importedRun(s, key, recordingId, withRank)
detections = [1 2];
if recordingId == 2
    detections = 3;
end
created = vawlume.attribution.createRun(s.conn, struct(recording_id=recordingId), struct( ...
    run_key=key, attribution_path="imported", method="External", ...
    settings_profile_version_id=1, target_set=struct(detection_ids=detections), ...
    participating_entity_ids=[1 2], sources=struct(source_file_ids=2)), Apply=true);
for k = 1:numel(detections)
    rows = struct(entity_id={1; 2}, score={0.9; 0.2}, ...
        score_semantics={"exporter score"; "exporter score"});
    if withRank
        [rows.candidate_rank] = deal(1, 2);
    end
    vawlume.attribution.addCandidates(s.conn, ...
        struct(attribution_target_id=created.targets.attribution_target_id(k)), rows, Apply=true);
end
ref = struct(attribution_run_id=created.run.attribution_run_id);
end

function writeText(path, text)
fid = fopen(path, "w");
fwrite(fid, text);
fclose(fid);
end

function closeAndDelete(conn, file, work)
close(conn);
if isfile(file), delete(file); end
if isfolder(work), rmdir(work, "s"); end
end

function seed(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p1','P')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri,relative_path) VALUES" + ...
    "(1,1,'recording_audio','audio.wav','audio.wav'),(2,1,'attribution_output','c.csv','c.csv')," + ...
    "(3,1,'recording_audio','other.wav','other.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id,native_recording_id) " + ...
    "VALUES(1,1,1,'R1'),(2,1,3,'R2')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name,is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id,entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id,recording_id,entity_id,link_type) " + ...
    "VALUES(1,1,1,'participant'),(2,1,2,'participant'),(3,2,1,'participant'),(4,2,2,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name,profile_kind) VALUES" + ...
    "(1,1,'imp','Imp','attribution_input_mapping')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id,version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1','json','a.json','" + string(repmat('a', 1, 64)) + "',1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) VALUES(1,'ds','DS')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id,extractor_version_id,run_key) VALUES(1,1,1,'det')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1),(1,2)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id,start_time_s,end_time_s) " + ...
    "VALUES(1,1,1,1.0,1.1),(2,1,1,2.0,2.1),(3,1,2,1.0,1.1)");
end
