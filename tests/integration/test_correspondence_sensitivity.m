function tests = test_correspondence_sensitivity
%TEST_CORRESPONDENCE_SENSITIVITY Itinerary 7.9: matching-side sensitivity families.
%
% Contract 07 D3, D7. On the 7.3 integrated fixture, one family runs the
% reference configuration (the tracked matching specification, whose analyses
% the fixture already applied and which are reused) and two alternatives:
%
%   matching_temporal  min_temporal_iou 0.9 (the reference: 0.10)
%   matching_spectral  every discrepancy_tolerance relative_tolerance 0.001
%
% Each configuration's DeepSqueak-MUPET consensus events are measured,
% normalized and attributed natively, and compared with the reference's through
% their stored shared member detections. Synthetic and circular throughout.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
tracked = fullfile(root, "config", "05_matching_profiles", "prototype_matching_consilience_spec.json");
trackedBytes = fileread(tracked);
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=root);
work = string(tempname);
mkdir(work);
t = struct(root=root, fixture=fixture, cleanup=cleanup, work=work, tracked=tracked, ...
    tracked_bytes=trackedBytes);
t.spec = familySpec(t, "p79-family");
t.state_before_plan = state(fixture.conn);
t.plan = vawlume.eda.correspondenceSensitivity(fixture.conn, t.spec, Print=false, RepoRoot=root);
t.state_after_plan = state(fixture.conn);
spec = t.spec;
t.printed = evalc("vawlume.eda.correspondenceSensitivity(fixture.conn, spec, RepoRoot=root);");
t.applied = vawlume.eda.correspondenceSensitivity(fixture.conn, spec, Apply=true, ...
    Print=false, RepoRoot=root);
t.summary = vawlume.eda.sensitivitySummary(fixture.conn, ...
    struct(analysis_run_id=t.applied.family_analysis_run_id));
testCase.TestData = t;
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
if isfolder(testCase.TestData.work)
    rmdir(testCase.TestData.work, "s");
end
end

% ================================================================= plan ===

function testThePlanWritesNothingAndPrintsItsCost(testCase)
t = testCase.TestData;
verifyEqual(testCase, t.state_after_plan, t.state_before_plan, "Planning wrote something.");
verifyEqual(testCase, t.plan.configurations.handle, ...
    ["reference"; "matching_temporal"; "matching_spectral"]);
verifySubstring(testCase, t.printed, "cost:");
verifySubstring(testCase, t.printed, "measured from audio");
verifySubstring(testCase, t.printed, "EXP-050");
reference = t.plan.configurations(t.plan.configurations.handle == "reference", :);
verifyEqual(testCase, [reference.predicted_matching_analyses, ...
    reference.predicted_agreement_analyses], [0 0], ...
    "The reference configuration's analyses exist and are reused (same checksum).");
end

function testApplyExecutesThePlanAndMeasuresItsCost(testCase)
t = testCase.TestData;
p = t.plan.predicted;
e = t.applied.executed;
verifyEqual(testCase, e.matching_analyses, p.matching_analyses);
verifyEqual(testCase, e.agreement_analyses, p.agreement_analyses);
verifyEqual(testCase, e.attribution_runs, p.attribution_runs);
verifyEqual(testCase, e.family_records, 1);
c = t.applied.configurations;
verifyEqual(testCase, e.call_window_runs, sum(c.consensus_event_count), ...
    "One call-window measurement per attributed consensus event.");
verifyTrue(testCase, all(c.wall_seconds > 0));
for k = 1:height(c)
    log(testCase, 1, sprintf("%s %s: %d consensus events, %.1f s", c.handle(k), ...
        c.configuration_id(k), c.consensus_event_count(k), c.wall_seconds(k)));
end
reference = c(c.handle == "reference", :);
verifyEqual(testCase, reference.consensus_analysis_run_id, ...
    t.fixture.manifest.correspondence.consensus_source.analysis_run_id, ...
    "The reference configuration reused the fixture's own DS-MUPET analysis.");
end

function testTheTrackedSpecificationIsByteIdentical(testCase)
t = testCase.TestData;
verifyEqual(testCase, string(fileread(t.tracked)), string(t.tracked_bytes));
generated = dir(fullfile(t.work, "out", "p79-family", "matching_spec_*.json"));
verifyEqual(testCase, numel(generated), 2);
verifyEmpty(testCase, dir(fullfile(t.root, "config", "**", "*sens*")));
end

% ============================================================ the reach ===

function testATemporalVariantChangesTheUnitCategories(testCase)
% The merge (DeepSqueak reports two where MUPET reports one call whole) is a
% reference consensus event with two DeepSqueak members. Under min_temporal_iou
% 0.9 its unit is no longer one_to_one, and the attribution comparison is
% reported inside the unit.
t = testCase.TestData;
row = summaryRow(t, "matching_temporal");
verifyGreaterThan(testCase, row.units_one_to_many + row.units_many_to_one + ...
    row.units_many_to_many + row.units_unmatched_left + row.units_unmatched_right, 0);
c = comparisonOf(t, "matching_temporal");
merge = mergeConsensusEvent(t);
target = targetOfEvent(t, referenceRunId(t), merge);
unit = c.units(cellfun(@(ids) ismember(target, ids), c.units.left_target_ids), :);
verifyNotEqual(testCase, unit.correspondence_unit, "one_to_one", ...
    "The merge's unit changes category under the stricter threshold.");
inside = c.pairs(c.pairs.unit_id == unit.unit_id, :);
verifyGreaterThan(testCase, height(inside), 0, "Its attribution comparison is reported.");
log(testCase, 1, sprintf("merge unit under min_temporal_iou 0.9: %s; summary: %d one_to_one, " + ...
    "%d one_to_many, %d many_to_one, %d unmatched_left, %d unmatched_right; lost %d, gained %d", ...
    unit.correspondence_unit, row.units_one_to_one, row.units_one_to_many, ...
    row.units_many_to_one, row.units_unmatched_left, row.units_unmatched_right, ...
    row.targets_lost, row.targets_gained));
end

function testASpectralVariantLeavesEveryEventSetIdentical(testCase)
% Demonstrated, not assumed (contract 07 D7, E5): discrepancy_tolerance governs
% classification only. Member sets of match groups, agreement groups and
% consensus events are identical to the reference's; the classification moves.
t = testCase.TestData;
c = t.applied.configurations;
reference = c(c.handle == "reference", :);
spectral = c(c.handle == "matching_spectral", :);
conn = t.fixture.conn;
refIds = reference.matching_analysis_run_ids{1};
specIds = spectral.matching_analysis_run_ids{1};
for k = 1:numel(refIds)
    verifyEqual(testCase, memberSets(conn, "match_groups", "match_group_members", ...
        "match_group_id", specIds(k)), memberSets(conn, "match_groups", ...
        "match_group_members", "match_group_id", refIds(k)), "match groups, pair " + k);
end
verifyEqual(testCase, memberSets(conn, "consensus_events", "consensus_event_members", ...
    "consensus_event_id", spectral.consensus_analysis_run_id), memberSets(conn, ...
    "consensus_events", "consensus_event_members", "consensus_event_id", ...
    reference.consensus_analysis_run_id), "consensus events");
verifyEqual(testCase, memberSets(conn, "agreement_groups", "agreement_group_members", ...
    "agreement_group_id", spectral.agreement_analysis_run_id), memberSets(conn, ...
    "agreement_groups", "agreement_group_members", "agreement_group_id", ...
    reference.agreement_analysis_run_id), "agreement groups");
% The classification is what the tolerance governs.
before = statuses(conn, reference.consensus_analysis_run_id);
after = statuses(conn, spectral.consensus_analysis_run_id);
verifyNotEqual(testCase, after, before, ...
    "A 0.001 relative tolerance changes the consilience classification.");
log(testCase, 1, "classification reference: " + strjoin(before, ",") + ...
    " | spectral: " + strjoin(after, ","));
% And attribution is identical: every unit one_to_one with equal selections.
row = summaryRow(t, "matching_spectral");
verifyEqual(testCase, row.units_one_to_one, height(comparisonOf(t, "matching_spectral").units));
verifyEqual(testCase, row.sets_equal + row.sets_both_empty, row.units_one_to_one);
verifyEqual(testCase, row.sets_differ, 0);
verifyEqual(testCase, row.status_disagree, 0);
verifyEqual(testCase, row.top_same + row.top_tie + row.top_unscored, row.units_one_to_one);
verifyEqual(testCase, row.scores_changed, 0);
end

% ============================================== reported, refused, guard ===

function testReportedRowsAndRefusals(testCase)
t = testCase.TestData;
rows = t.summary.rows;
duration = rows(rows.handle == "matching_duration", :);
verifyEqual(testCase, duration.status, "not_variable");
verifySubstring(testCase, duration.reason, "CAL-001");
conn = t.fixture.conn;
plan = @(spec) vawlume.eda.correspondenceSensitivity(conn, spec, Print=false, RepoRoot=t.root);
bad = t.spec;
bad.family_key = "p79-bad";
bad.variants = struct(handle="matching_duration", value=struct(max_s=0.1));
verifyError(testCase, @() plan(bad), "vawlume:eda:SensitivityHandleNotVariable");
bad.variants = struct(handle="matching_spectral", value=struct(absolute_tolerance=1));
verifyError(testCase, @() plan(bad), "vawlume:eda:SensitivityHandleUnknown");
bad.variants = struct(handle="decision_policy", value=struct(selection_threshold=-1));
verifyError(testCase, @() plan(bad), "vawlume:eda:SensitivityHandleUnknown", ...
    "Attribution-side handles belong to attributionSensitivity.");
verifyError(testCase, @() plan(rmfield(t.spec, "reference")), ...
    "vawlume:eda:SensitivityReferenceRequired");
other = t.spec;
other.variants = other.variants(1);
verifyError(testCase, @() plan(other), "vawlume:eda:SensitivityFamilyConflict");
end

function testNoOutputRanksOrRecommends(testCase)
% The 7.8 guard, over this pass's summary and printed plan.
t = testCase.TestData;
s = t.summary;
texts = [string(s.rows.Properties.VariableNames)'; string(s.note); string(t.printed)];
for name = string(s.rows.Properties.VariableNames)
    if isstring(s.rows.(name))
        texts = [texts; s.rows.(name)]; %#ok<AGROW>
    end
end
hits = regexp(lower(texts), ...
    "(?<![a-z])(best|optimal|recommended|stable|validated|calibrated)(?![a-z])", "match");
words = unique([hits{:}]);
verifyEmpty(testCase, words, "Forbidden words: " + strjoin(words, ", "));
verifyEqual(testCase, s.rows(:, ["handle", "handle_value"]), ...
    sortrows(s.rows(:, ["handle", "handle_value"])));
end

% --------------------------------------------------------------- helpers ---

function spec = familySpec(t, key)
f = t.fixture;
m = f.manifest;
runSpec = struct(settings_profile_version_id=m.profiles.estimator_settings_version_id, ...
    participating_entity_ids=[m.entities.A m.entities.B], ...
    clock=struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
        audio_alignment_run_id=m.alignment.audio.alignment_run_id), ...
    tracking=struct(stream=struct(project_key=m.project_key, stream_name="arena_tracking"), ...
        alignment_run_id=m.alignment.tracking.alignment_run_id, ...
        source_root=fullfile(f.root, "tracking")));
spec = struct(family_key=key, output_root=fullfile(t.work, "out"), ...
    recording_id=m.recording_id, extraction_runs=["p7-ds", "p7-mupet", "p7-usvseg"], ...
    consensus_pair=["p7-ds", "p7-mupet"], ...
    reference=struct(run_spec=runSpec, decision_policy=fullfile(t.root, "config", ...
        "08_attribution_policies", "native_level_difference_decision_policy.json"), ...
        measurement=struct(channels=[1 2], band_hz=[200 300], ...
        source_root=fullfile(f.root, "project"), response_run_id=m.acoustic.response_run_id)), ...
    variants=[struct(handle="matching_temporal", value=struct(min_temporal_iou=0.9)), ...
        struct(handle="matching_spectral", value=struct(relative_tolerance=0.001))]);
end

function c = comparisonOf(t, handle)
id = t.applied.configurations.configuration_id(t.applied.configurations.handle == handle);
c = t.summary.comparisons([t.summary.comparisons.configuration_id] == id).comparison;
end

function row = summaryRow(t, handle)
row = t.summary.rows(t.summary.rows.handle == handle, :);
end

function id = referenceRunId(t)
c = t.applied.configurations;
id = c.attribution_run_id(c.handle == "reference");
end

function event = mergeConsensusEvent(t)
% The reference DS-MUPET consensus event holding the merge scene's two
% DeepSqueak detections (manifest structure, DeepSqueak side).
structure = t.fixture.manifest.correspondence.structure;
merge = structure.left_detection_ids{structure.scene == "merge"};
rows = fetch(t.fixture.conn, "SELECT m.consensus_event_id FROM consensus_event_members m " + ...
    "JOIN consensus_events c ON c.consensus_event_id=m.consensus_event_id WHERE " + ...
    "c.analysis_run_id=" + string(t.fixture.manifest.correspondence.consensus_source.analysis_run_id) + ...
    " AND m.detection_id IN (" + strjoin(string(merge), ",") + ")");
event = unique(double(rows.consensus_event_id));
event = event(1);
end

function id = targetOfEvent(t, runId, eventId)
targets = vawlume.attribution.report(t.fixture.conn, struct(attribution_run_id=runId), ...
    Tables="targets").targets;
id = targets.attribution_target_id(targets.consensus_event_id == eventId);
end

function value = memberSets(conn, owner, members, key, analysisId)
% Every container's member detections as sorted text, the containers sorted:
% comparable across two analyses whose container ids differ.
rows = fetch(conn, "SELECT m." + key + " AS id, m.detection_id FROM " + members + " m JOIN " + ...
    owner + " o ON o." + key + "=m." + key + " WHERE o.analysis_run_id=" + string(analysisId) + ...
    " ORDER BY m." + key + ", m.detection_id");
ids = double(rows.id);
value = strings(0, 1);
for id = unique(ids)'
    value(end + 1, 1) = strjoin(string(double(rows.detection_id(ids == id)))', ","); %#ok<AGROW>
end
value = sort(value);
end

function value = statuses(conn, analysisId)
% The automated consilience classification of every match group, read-only,
% under the analysis's own stored specification (vawlume.consilience.summarize),
% in match-group order.
report = vawlume.consilience.summarize(conn, struct(analysis_run_id=analysisId));
a = sortrows(report.consilience, "match_group_id");
value = string(a.automated_status)';
end

function value = state(conn)
version = fetch(conn, "PRAGMA data_version");
changes = fetch(conn, "SELECT total_changes() AS n");
value = [double(version{1, 1}), double(changes.n(1))];
end
