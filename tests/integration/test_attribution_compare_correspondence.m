function tests = test_attribution_compare_correspondence
%TEST_ATTRIBUTION_COMPARE_CORRESPONDENCE Itinerary 7.7: compare across event sets.
%
% Contract 07 D3. On the 7.3 integrated fixture, runs over DeepSqueak, MUPET and
% USVSEG detections and over consensus events are compared through ONE named
% analysis's stored membership rows. The fixture's own runs target only the
% seven attribution scenes, so setupOnce writes four native_estimate runs over
% every DeepSqueak, MUPET and USVSEG detection and every DeepSqueak-MUPET
% consensus event, through createRun / addCandidates / decide, with synthetic
% scores. They exercise the join; their scores mean nothing, and every
% agreement here is circular.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=root);
testCase.TestData.root = root;
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
m = fixture.manifest;
analyses = m.correspondence.matching_analyses;
testCase.TestData.analysis = struct( ...
    ds_mupet=analyses.analysis_run_id(analyses.run_key == "p7-match-ds-mupet"), ...
    ds_usvseg=analyses.analysis_run_id(analyses.run_key == "p7-match-ds-usvseg"), ...
    mupet_usvseg=analyses.analysis_run_id(analyses.run_key == "p7-match-mupet-usvseg"), ...
    agreement=m.correspondence.agreement.analysis_run_id, ...
    consensus=m.correspondence.consensus_source.analysis_run_id);
conn = fixture.conn;
testCase.TestData.runs = struct( ...
    ds=allEventRun(testCase, "p77-native-ds-all", "detection_ids", detectionsOf(conn, "p7-ds")), ...
    mupet=allEventRun(testCase, "p77-native-mupet-all", "detection_ids", detectionsOf(conn, "p7-mupet")), ...
    usvseg=allEventRun(testCase, "p77-native-usvseg-all", "detection_ids", detectionsOf(conn, "p7-usvseg")), ...
    consensus=allEventRun(testCase, "p77-native-consensus-all", "consensus_event_ids", ...
        consensusOf(conn, testCase.TestData.analysis.consensus)));
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ============================================== the manifest's scenes ===

function testSplitMergeAndMissAreTheManifestsUnits(testCase)
% The 7.3 structure scenes, DeepSqueak on the left: split -> one_to_many,
% merge -> many_to_one, miss -> unmatched_left, each from its named analysis.
t = testCase.TestData;
structure = t.fixture.manifest.correspondence.structure;
for k = 1:height(structure)
    scene = structure(k, :);
    other = "mupet";
    if scene.pair == "deepsqueak_usvseg"
        other = "usvseg";
    end
    c = compareRuns(t, "ds", other, scene.analysis_run_id);
    leftTargets = targetsOf(t, "ds", scene.left_detection_ids{1});
    unit = unitHolding(c, leftTargets);
    verifyEqual(testCase, unit.correspondence_unit, scene.expected_unit, scene.scene);
    verifyEqual(testCase, unit.left_target_ids{1}, sort(leftTargets(:))', scene.scene);
    right = sort(targetsOf(t, other, scene.right_detection_ids{1}));
    verifyEqual(testCase, unit.right_target_ids{1}, reshape(right, 1, []), scene.scene);
    log(testCase, 1, scene.scene + ": " + unit.correspondence_unit + ...
        " via " + c.correspondence.analysis_run_key);
end
end

function testSeveralTargetsOnASideAreReportedAsPairsNeverPromoted(testCase)
t = testCase.TestData;
structure = t.fixture.manifest.correspondence.structure;
split = structure(structure.scene == "split", :);
c = compareRuns(t, "ds", "mupet", split.analysis_run_id);
unit = unitHolding(c, targetsOf(t, "ds", split.left_detection_ids{1}));
verifyEqual(testCase, [unit.top_entity_agreement, unit.selected_set_relation], ...
    ["not_applicable_unit", "not_applicable_unit"], "No representative target.");
verifyEqual(testCase, unit.right_decision_status, "not_applicable_unit");
pairs = c.pairs(c.pairs.unit_id == unit.unit_id, :);
verifyEqual(testCase, height(pairs), numel(unit.left_target_ids{1}) * numel(unit.right_target_ids{1}));
verifyTrue(testCase, all(ismember(pairs.right_target_id, unit.right_target_ids{1})));
verifyTrue(testCase, all(pairs.right_decision_status ~= "not_applicable_unit"), ...
    "Each pair carries the target's own status.");
% The cross-tab counts only one_to_one units: pairs are never promoted.
verifyEqual(testCase, sum(c.status_crosstab.unit_count), nnz(c.units.correspondence_unit == "one_to_one"));
end

function testAnUnmatchedTargetHasNoCounterpartAndIsKept(testCase)
t = testCase.TestData;
structure = t.fixture.manifest.correspondence.structure;
miss = structure(structure.scene == "miss", :);
c = compareRuns(t, "ds", "mupet", miss.analysis_run_id);
unit = unitHolding(c, targetsOf(t, "ds", miss.left_detection_ids{1}));
verifyEqual(testCase, unit.correspondence_unit, "unmatched_left");
verifyEqual(testCase, unit.right_decision_status, "no_counterpart");
verifyNotEqual(testCase, unit.left_decision_status, "no_counterpart");
pairs = c.pairs(c.pairs.unit_id == unit.unit_id, :);
verifyEqual(testCase, height(pairs), 1);
verifyTrue(testCase, isnan(pairs.right_target_id));
verifyEqual(testCase, pairs.right_decision_status, "no_counterpart");
% Every target of both runs appears in exactly one unit: nothing is dropped.
for side = ["left", "right"]
    ids = [c.units.(side + "_target_ids"){:}];
    run = "ds";
    if side == "right", run = "mupet"; end
    verifyEqual(testCase, sort(ids(:)), sort(allTargets(t, run)), side);
end
end

% =============================================== the join is the stored one ===

function testUnitsAreExactlyTheStoredComponents(testCase)
% For every named analysis the units equal the connected components of its
% stored membership rows, computed here independently from SQL.
t = testCase.TestData;
a = t.analysis;
cases = {"ds", "mupet", a.ds_mupet, "match"
    "ds", "usvseg", a.ds_usvseg, "match"
    "mupet", "usvseg", a.mupet_usvseg, "match"
    "ds", "mupet", a.agreement, "agreement"
    "ds", "usvseg", a.agreement, "agreement"
    "mupet", "usvseg", a.agreement, "agreement"};
for k = 1:size(cases, 1)
    c = compareRuns(t, cases{k, 1}, cases{k, 2}, cases{k, 3});
    expected = storedComponents(t, cases{k, 1}, cases{k, 2}, cases{k, 3}, cases{k, 4});
    verifyEqual(testCase, unitSignature(c), expected, ...
        sprintf("%s vs %s through analysis %d", cases{k, 1}, cases{k, 2}, cases{k, 3}));
end
end

function testAStricterAnalysisChangesTheUnitsExactlyAsItsRowsChange(testCase)
% A second DeepSqueak-MUPET analysis under a stricter matching specification
% (min_temporal_iou 0.9). The units follow its stored rows, not the first's.
t = testCase.TestData;
spec = jsondecode(fileread(fullfile(t.root, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json")));
spec.profile.profile_version = '0.1.0-p77-strict';
spec.candidate_generation.plausibility_rule.min_temporal_iou = 0.9;
work = string(tempname);
mkdir(work);
cleanup = onCleanup(@() rmdir(work, "s"));
path = fullfile(work, "strict_matching_spec.json");
fid = fopen(path, "w");
fwrite(fid, jsonencode(spec, PrettyPrint=true));
fclose(fid);
recording = vawlume.attribution.report(t.fixture.conn, t.runs.ds, Tables="targets").recording_id;
strict = vawlume.matching.compare(t.fixture.conn, struct(recording_id=recording), ...
    struct(run_a="p7-ds", run_b="p7-mupet"), ...
    struct(run_key="p77-match-ds-mupet-strict", profile_path=path), ...
    RepoRoot=t.root, Apply=true);
strictId = double(strict.analysis.analysis_run_id);
loose = compareRuns(t, "ds", "mupet", t.analysis.ds_mupet);
tight = compareRuns(t, "ds", "mupet", strictId);
verifyEqual(testCase, unitSignature(tight), storedComponents(t, "ds", "mupet", strictId, "match"));
verifyEqual(testCase, unitSignature(loose), storedComponents(t, "ds", "mupet", t.analysis.ds_mupet, "match"));
verifyNotEqual(testCase, unitSignature(tight), unitSignature(loose), ...
    "The stricter analysis stores different groups, so the units differ.");
log(testCase, 1, sprintf("DS-MUPET units: %d default, %d strict; types default %s / strict %s", ...
    height(loose.units), height(tight.units), ...
    strjoin(unique(loose.units.correspondence_unit)', ","), ...
    strjoin(unique(tight.units.correspondence_unit)', ",")));
end

function testDetectionsAgainstConsensusEventsThroughConsensusMembership(testCase)
t = testCase.TestData;
c = compareRuns(t, "ds", "consensus", t.analysis.consensus);
verifyEqual(testCase, c.correspondence.kind, "consensus_membership");
verifyEqual(testCase, unitSignature(c), ...
    storedComponents(t, "ds", "consensus", t.analysis.consensus, "consensus"));
% The fixture's own native runs: DeepSqueak detections against consensus
% events, one recording, one settings version, so values may be compared and
% the note says they are different windows of the call.
m = t.fixture.manifest;
c = vawlume.attribution.compare(t.fixture.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id), ...
    struct(attribution_run_id=m.runs.native_consensus.attribution_run_id), ...
    Correspondence=struct(analysis_run_id=t.analysis.consensus), CompareScores=true);
verifyTrue(testCase, all(c.units.score_comparability == "comparable"));
verifyGreaterThan(testCase, height(c.scores), 0);
verifySubstring(testCase, c.correspondence.value_note, "different measured windows");
log(testCase, 1, "native DS vs native consensus units: " + ...
    strjoin(c.units.correspondence_unit', ","));
end

% ============================================================== refusals ===

function testEachRefusalIsNamed(testCase)
t = testCase.TestData;
a = t.analysis;
verifyError(testCase, @() vawlume.attribution.compare(t.fixture.conn, t.runs.ds, ...
    t.runs.mupet), "vawlume:attribution:CorrespondenceAnalysisRequired");
invalid = "vawlume:attribution:CorrespondenceAnalysisInvalid";
otherKind = fetch(t.fixture.conn, "SELECT analysis_run_id FROM analysis_runs " + ...
    "WHERE run_type='temporal_alignment' ORDER BY analysis_run_id LIMIT 1");
bad = {a.ds_usvseg, "an analysis that does not take MUPET as an input"
    999999, "no such analysis"
    double(otherKind.analysis_run_id(1)), "an analysis of another kind"};
for k = 1:size(bad, 1)
    verifyError(testCase, @() compareRuns(t, "ds", "mupet", bad{k, 1}), invalid, bad{k, 2});
end
byKey = vawlume.attribution.compare(t.fixture.conn, t.runs.ds, t.runs.mupet, ...
    Correspondence=struct(run_key="p7-match-ds-mupet"));
verifyEqual(testCase, byKey.correspondence.analysis_run_id, a.ds_mupet, ...
    "A run_key reference names the same analysis.");
verifyError(testCase, @() compareRuns(t, "ds", "ds", a.ds_mupet), invalid, ...
    "Correspondence named for one event set.");
verifyError(testCase, @() compareRuns(t, "consensus", "consensus", a.ds_mupet), invalid);
verifyError(testCase, @() vawlume.attribution.compare(t.fixture.conn, t.runs.ds, ...
    t.runs.mupet, Correspondence="p7-match-ds-mupet"), invalid);
end

% ======================================================== read-only, guard ===

function testTheJoinIsReadOnlyAndCallsNoMatchingOrIntervalCode(testCase)
t = testCase.TestData;
before = state(t.fixture.conn);
compareRuns(t, "ds", "mupet", t.analysis.ds_mupet);
compareRuns(t, "ds", "consensus", t.analysis.consensus);
verifyEqual(testCase, state(t.fixture.conn), before);
% Static guard: no matching/agreement/consilience/interval call and no interval
% arithmetic in compare or its helpers; no SQL write either.
folder = fullfile(t.root, "src", "+vawlume", "+attribution");
files = [fullfile(folder, "compare.m"), ...
    fullfile(folder, "private", "attributionCompareTargets.m"), ...
    fullfile(folder, "private", "attributionCorrespondenceUnits.m")];
banned = ["vawlume\.matching\.", "vawlume\.agreement\.", "vawlume\.consilience\.", ...
    "vawlume\.interval\.", "start_time", "end_time", "temporal_overlap", ...
    "overlap_s", "_iou\>", ...
    "\<INSERT\s", "\<UPDATE\s", "\<DELETE\s", "sqlwrite\(", "execute\("];
for file = files
    code = codeLines(file);
    for pattern = banned
        hits = code(~cellfun(@isempty, regexp(code, pattern, "once")));
        verifyEmpty(testCase, hits, file + " matches " + pattern + ": " + strjoin(hits, " | "));
    end
end
end

% --------------------------------------------------------------- helpers ---

function c = compareRuns(t, left, right, analysisId, varargin)
c = vawlume.attribution.compare(t.fixture.conn, t.runs.(left), t.runs.(right), ...
    "Correspondence", struct(analysis_run_id=analysisId), varargin{:});
end

function ref = allEventRun(testCase, key, column, eventIds)
% A native_estimate run over every event of one set, through the canonical
% writers, decided under the shipped native policy. Synthetic scores.
f = testCase.TestData.fixture;
m = f.manifest;
root = testCase.TestData.root;
settings = vawlume.estimator.loadSettings(RepoRoot=root);
recording = vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id), ...
    Tables="targets").recording_id;
created = vawlume.attribution.createRun(f.conn, struct(recording_id=recording), struct( ...
    run_key=key, attribution_path="native_estimate", ...
    method="vawlume.estimator.level_difference_consistency 1.0.0", ...
    settings_profile_version_id=m.profiles.estimator_settings_version_id, ...
    target_set=struct(column, eventIds(:)'), participating_entity_ids=[m.entities.A m.entities.B], ...
    sources=struct(analysis_run_ids=testCase.TestData.analysis.ds_mupet), ...
    declared_inputs=settings.declared_inputs), Apply=true);
for k = 1:height(created.targets)
    id = created.targets.attribution_target_id(k);
    a = -mod(id, 3) * 0.5;
    vawlume.attribution.addCandidates(f.conn, struct(attribution_target_id=id), ...
        struct(entity_id={m.entities.A; m.entities.B}, score={a; a - 1 - mod(id, 5)}, ...
        score_semantics={"synthetic dB; not a probability"; "synthetic dB; not a probability"}), ...
        Apply=true);
end
ref = struct(attribution_run_id=created.run.attribution_run_id);
vawlume.attribution.decide(f.conn, ref, fullfile(root, "config", "08_attribution_policies", ...
    "native_level_difference_decision_policy.json"), Apply=true, RepoRoot=root);
end

function ids = detectionsOf(conn, runKey)
rows = fetch(conn, "SELECT d.detection_id FROM detections d JOIN extraction_runs er " + ...
    "ON er.extraction_run_id=d.extraction_run_id WHERE er.run_key='" + runKey + ...
    "' ORDER BY d.detection_id");
ids = double(rows.detection_id);
end

function ids = consensusOf(conn, analysisId)
rows = fetch(conn, "SELECT consensus_event_id FROM consensus_events WHERE analysis_run_id=" + ...
    string(analysisId) + " ORDER BY consensus_event_id");
ids = double(rows.consensus_event_id);
end

function ids = targetsOf(t, run, eventIds)
targets = vawlume.attribution.report(t.fixture.conn, t.runs.(run), Tables="targets").targets;
column = "detection_id";
if run == "consensus", column = "consensus_event_id"; end
ids = targets.attribution_target_id(ismember(targets.(column), eventIds));
end

function ids = allTargets(t, run)
ids = vawlume.attribution.report(t.fixture.conn, t.runs.(run), Tables="targets").targets.attribution_target_id;
end

function unit = unitHolding(c, leftTargets)
hit = cellfun(@(ids) any(ismember(leftTargets, ids)), c.units.left_target_ids);
unit = c.units(hit, :);
end

function value = unitSignature(c)
% Each unit as "left ids | right ids", sorted: comparable with storedComponents.
value = strings(height(c.units), 1);
for k = 1:height(c.units)
    value(k) = strjoin(string(c.units.left_target_ids{k}), ",") + "|" + ...
        strjoin(string(c.units.right_target_ids{k}), ",");
end
value = sort(value);
end

function value = storedComponents(t, left, right, analysisId, kind)
% The expected units, independently: connected components of the analysis's
% stored rows over the two runs' targets, by repeated label propagation.
conn = t.fixture.conn;
lt = vawlume.attribution.report(conn, t.runs.(left), Tables="targets").targets;
rt = vawlume.attribution.report(conn, t.runs.(right), Tables="targets").targets;
switch kind
    case "match"
        rows = fetch(conn, "SELECT m.match_group_id AS g, m.detection_id AS d FROM match_group_members m " + ...
            "JOIN match_groups g ON g.match_group_id=m.match_group_id WHERE g.analysis_run_id=" + string(analysisId));
    case "agreement"
        rows = fetch(conn, "SELECT m.agreement_group_id AS g, m.detection_id AS d FROM agreement_group_members m " + ...
            "JOIN agreement_groups g ON g.agreement_group_id=m.agreement_group_id WHERE g.analysis_run_id=" + string(analysisId));
    case "consensus"
        rows = fetch(conn, "SELECT m.consensus_event_id AS g, m.detection_id AS d FROM consensus_event_members m " + ...
            "JOIN consensus_events c ON c.consensus_event_id=m.consensus_event_id WHERE c.analysis_run_id=" + string(analysisId));
end
groups = double(rows.g);
members = double(rows.d);
% Label each target by the set of groups it belongs to; merge labels that share
% a group until stable.
leftIds = lt.attribution_target_id;
rightIds = rt.attribution_target_id;
leftEvents = lt.detection_id;
if kind == "consensus"
    rightEvents = rt.consensus_event_id;
    rightGroups = arrayfun(@(e) e, rightEvents, UniformOutput=false);
else
    rightEvents = rt.detection_id;
    rightGroups = arrayfun(@(e) groups(members == e)', rightEvents, UniformOutput=false);
end
leftGroups = arrayfun(@(e) groups(members == e)', leftEvents, UniformOutput=false);
nodes = [leftGroups; rightGroups];
label = (1:numel(nodes))';
changed = true;
while changed
    changed = false;
    for i = 1:numel(nodes)
        for j = i + 1:numel(nodes)
            if label(i) ~= label(j) && ~isempty(intersect(nodes{i}, nodes{j}))
                label(label == label(j)) = label(i);
                changed = true;
            end
        end
    end
end
isLeft = [true(numel(leftIds), 1); false(numel(rightIds), 1)];
ids = [leftIds; rightIds];
value = strings(0, 1);
for l = unique(label)'
    inUnit = label == l;
    value(end + 1, 1) = strjoin(string(sort(ids(inUnit & isLeft)))', ",") + "|" + ...
        strjoin(string(sort(ids(inUnit & ~isLeft)))', ","); %#ok<AGROW>
end
value = sort(value);
end

function value = state(conn)
version = fetch(conn, "PRAGMA data_version");
changes = fetch(conn, "SELECT total_changes() AS n");
value = [double(version{1, 1}), double(changes.n(1))];
end

function code = codeLines(file)
lines = splitlines(string(fileread(file)));
lines = lines(~startsWith(strtrim(lines), "%"));
code = regexprep(lines, "%.*$", "");
code = code(strlength(strtrim(code)) > 0)';
end
