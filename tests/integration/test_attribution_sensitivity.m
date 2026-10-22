function tests = test_attribution_sensitivity
%TEST_ATTRIBUTION_SENSITIVITY Itinerary 7.8: attribution-side sensitivity families.
%
% Contract 07 D1, D2, D6. On the 7.3 integrated fixture, one family varies each
% handle of method 1.0.0 once against the declared reference (the fixture's
% native DeepSqueak run):
%
%   decision_policy       selection_threshold -1 dB (stricter than -3)
%   estimator_settings    primary_instant_basis onset (the reference: midpoint)
%   normalization_policy  reference_type tone (generated, not shipped)
%   alignment_run         the audio clock refitted as an offset model, from the
%                         same anchors, through ingest.alignment and alignment.fit
%
% Every movement here is the generator's: synthetic and circular.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=root);
nativeBefore = nativeSnapshot(fixture.conn);
work = string(tempname);
mkdir(work);
testCase.TestData = struct(root=root, fixture=fixture, cleanup=cleanup, work=work, ...
    native_before=nativeBefore);
testCase.TestData.offset_run = offsetAudioFit(fixture, root);
spec = familySpec(testCase.TestData, "p78-family");
testCase.TestData.spec = spec;
testCase.TestData.state_before_plans = state(fixture.conn);
testCase.TestData.plan = vawlume.eda.attributionSensitivity(fixture.conn, spec, ...
    Print=false, RepoRoot=root);
testCase.TestData.plan_again = vawlume.eda.attributionSensitivity(fixture.conn, spec, ...
    Print=false, RepoRoot=root);
testCase.TestData.state_after_plans = state(fixture.conn);
testCase.TestData.printed = evalc("vawlume.eda.attributionSensitivity(fixture.conn, spec, RepoRoot=root);");
testCase.TestData.applied = vawlume.eda.attributionSensitivity(fixture.conn, spec, ...
    Apply=true, Print=false, RepoRoot=root);
testCase.TestData.summary = vawlume.eda.sensitivitySummary(fixture.conn, ...
    struct(analysis_run_id=testCase.TestData.applied.family_analysis_run_id));
end

function testTheSensitivityRunsLeaveEveryNativeTableUnchanged(testCase)
% Plan §12 integration check 2 (contract 07 D13, E8): planning and applying this
% sensitivity family wrote derived runs only. Every native row that existed when
% the fixture was built is byte-identical afterwards. New native rows (an
% alignment variant ingests its own clock evidence) are appends, not overwrites.
before = testCase.TestData.native_before;
after = nativeSnapshot(testCase.TestData.fixture.conn);
verifyNotEmpty(testCase, before.detections, "No native rows to compare.");
for name = string(fieldnames(before))'
    verifyGreaterThanOrEqual(testCase, height(after.(name)), height(before.(name)), ...
        "Native rows of " + name + " were deleted under the sensitivity runs.");
    verifyEqual(testCase, after.(name)(1:min(end, height(before.(name))), :), ...
        before.(name), "Native rows of " + name + " were overwritten under the sensitivity runs.");
end
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
if isfolder(testCase.TestData.work)
    rmdir(testCase.TestData.work, "s");
end
end

% ================================================================= plan ===

function testPlanningWritesNothingAndIsDeterministic(testCase)
t = testCase.TestData;
verifyEqual(testCase, t.state_after_plans, t.state_before_plans, "Planning wrote something.");
verifyEqual(testCase, t.plan.variants.configuration_id, t.plan_again.variants.configuration_id);
verifyEqual(testCase, t.plan.design_sha256, t.plan_again.design_sha256);
verifyEqual(testCase, height(t.plan.variants), 4);
verifyEqual(testCase, sort(t.plan.variants.handle), ["alignment_run"; "decision_policy"; ...
    "estimator_settings"; "normalization_policy"]);
verifyTrue(testCase, all(startsWith(t.plan.variants.configuration_id, "cfg-")));
% The cost is printed before anything runs.
verifySubstring(testCase, t.printed, "cost:");
verifySubstring(testCase, t.printed, "audio re-read: no");
for id = t.plan.variants.configuration_id'
    verifySubstring(testCase, t.printed, id);
end
end

function testApplyExecutesExactlyThePlan(testCase)
t = testCase.TestData;
predicted = t.plan.predicted;
executed = t.applied.executed;
for name = ["attribution_runs", "decisions", "normalization_runs", "profile_versions", ...
        "family_records"]
    verifyEqual(testCase, executed.(name), predicted.(name), name);
end
verifyEqual(testCase, t.applied.status, "applied");
end

function testTheFamilyIsRecordedWithItsDeclaredReference(testCase)
t = testCase.TestData;
conn = t.fixture.conn;
family = fetch(conn, "SELECT run_type, run_key, status FROM analysis_runs WHERE " + ...
    "analysis_run_id=" + string(t.applied.family_analysis_run_id));
verifyEqual(testCase, [string(family.run_type), string(family.run_key)], ...
    ["attribution_sensitivity", "p78-family"]);
sources = fetch(conn, "SELECT s.dependency_role, a.attribution_run_id FROM " + ...
    "analysis_run_sources s JOIN attribution_runs a ON a.analysis_run_id=s.source_analysis_run_id " + ...
    "WHERE s.analysis_run_id=" + string(t.applied.family_analysis_run_id) + " ORDER BY a.attribution_run_id");
roles = string(sources.dependency_role);
verifyEqual(testCase, double(sources.attribution_run_id(roles == "sensitivity_reference")), ...
    t.fixture.manifest.runs.native_detections.attribution_run_id);
verifyEqual(testCase, nnz(roles == "sensitivity_variant"), 3, ...
    "Three run variants; the policy variant is a decision set on the reference run.");
design = fetch(conn, "SELECT COUNT(*) AS n FROM analysis_run_profiles WHERE analysis_run_id=" + ...
    string(t.applied.family_analysis_run_id) + " AND assignment_role='sensitivity_design'");
verifyEqual(testCase, double(design.n), 1);
% A re-apply of the same design is reused; another design under the key conflicts.
again = vawlume.eda.attributionSensitivity(conn, t.spec, Apply=true, Print=false, RepoRoot=t.root);
verifyEqual(testCase, again.status, "reused");
other = t.spec;
other.variants = other.variants(1);
verifyError(testCase, @() vawlume.eda.attributionSensitivity(conn, other, Print=false, ...
    RepoRoot=t.root), "vawlume:eda:SensitivityFamilyConflict");
end

function testGeneratedProfilesAreOutsideConfigAndLabelled(testCase)
t = testCase.TestData;
files = dir(fullfile(t.work, "out", "p78-family", "*.json"));
verifyGreaterThanOrEqual(testCase, numel(files), 5, "policy, 2 settings, normalization policy, design");
versions = fetch(t.fixture.conn, "SELECT version_label, content_uri FROM config_profile_versions " + ...
    "WHERE version_label LIKE '%+sens.cfg-%'");
verifyEqual(testCase, height(versions), 4);
verifyFalse(testCase, any(contains(string(versions.content_uri), "config/")));
shipped = dir(fullfile(t.root, "config", "**", "*sens*"));
verifyEmpty(testCase, shipped, "Nothing generated is written under config/.");
end

% ============================================================ movement ===

function testAStricterThresholdTurnsAssignedIntoUnassigned(testCase)
t = testCase.TestData;
m = t.fixture.manifest;
c = comparisonOf(t, "decision_policy");
target = m.scenes.native_detection_target_id(m.scenes.scene == "model_mismatch");
unit = c.units(cellfun(@(ids) isequal(ids, target), c.units.left_target_ids), :);
verifyEqual(testCase, [unit.left_decision_status, unit.right_decision_status], ...
    ["assigned", "unassigned"], "B fits within 3 dB but not within 1 dB.");
row = summaryRow(t, "decision_policy");
verifyGreaterThanOrEqual(testCase, row.status_disagree, 1);
verifyEqual(testCase, row.score_comparability, "comparable");
verifyEqual(testCase, row.scores_changed, 0, "A policy variant re-decides; no score moves.");
verifyEqual(testCase, row.variant_kind, "decision_set");
end

function testAnInstantBasisVariantLeavesTheSymmetricSceneAmbiguous(testCase)
t = testCase.TestData;
m = t.fixture.manifest;
c = comparisonOf(t, "estimator_settings");
target = m.scenes.native_detection_target_id(m.scenes.scene == "symmetric");
unit = c.units(cellfun(@(ids) isequal(ids, target), c.units.left_target_ids), :);
verifyEqual(testCase, [unit.left_decision_status, unit.right_decision_status], ...
    ["ambiguous", "ambiguous"]);
row = summaryRow(t, "estimator_settings");
verifyEqual(testCase, row.score_comparability, "not_comparable:settings_profile_version", ...
    "A settings variant is refused a value comparison; ranks and sets carry it.");
verifyTrue(testCase, isnan(row.scores_changed));
% The stored scores, read directly, show whether the basis moved them. With the
% fixture's stationary animals the distances do not depend on the instant.
variant = variantOf(t, "estimator_settings");
left = scoresOf(t, t.fixture.manifest.runs.native_detections.attribution_run_id, target);
right = scoresOf(t, variant.attribution_run_id, unit.right_target_ids{1});
log(testCase, 1, sprintf("symmetric scores midpoint [%g %g], onset [%g %g]", left, right));
end

function testTheToneNormalizationChangesNormalizedValues(testCase)
t = testCase.TestData;
variant = variantOf(t, "normalization_policy");
reference = t.fixture.manifest.runs.native_detections.attribution_run_id;
a = normalizedLevels(t, reference);
b = normalizedLevels(t, variant.attribution_run_id);
verifyEqual(testCase, numel(a), numel(b));
verifyGreaterThan(testCase, nnz(abs(a - b) > 1e-12), 0, ...
    "Dividing by the tone family's estimate changes the normalized levels.");
row = summaryRow(t, "normalization_policy");
verifyEqual(testCase, row.status, "variant");
verifyEqual(testCase, row.one_to_one_units, 7);
end

function testAnAlignmentVariantRunsAndKeepsTheBracketFact(testCase)
t = testCase.TestData;
m = t.fixture.manifest;
row = summaryRow(t, "alignment_run");
verifyEqual(testCase, row.score_comparability, "comparable", ...
    "Same method and settings: the values may be set side by side.");
verifyFalse(testCase, isnan(row.scores_changed));
% The out-of-bracket call reaches bracket_extrapolated = true through the real
% path in the variant run too (7.3's scene closes the ledger item; this shows
% the variant carries it).
variant = variantOf(t, "alignment_run");
target = m.scenes.native_detection_target_id(m.scenes.scene == "out_of_bracket");
c = comparisonOf(t, "alignment_run");
unit = c.units(cellfun(@(ids) isequal(ids, target), c.units.left_target_ids), :);
rows = fetch(t.fixture.conn, "SELECT value_semantics FROM attribution_evidence WHERE " + ...
    "attribution_target_id=" + string(unit.right_target_ids{1}) + ...
    " AND evidence_kind='bodypoint_microphone_distance'");
verifyTrue(testCase, any(contains(string(rows.value_semantics), "bracket_extrapolated=true")));
used = fetch(t.fixture.conn, "SELECT DISTINCT alignment_run_id FROM attribution_evidence e " + ...
    "JOIN attribution_targets g ON g.attribution_target_id=e.attribution_target_id " + ...
    "WHERE g.attribution_run_id=" + string(variant.attribution_run_id) + ...
    " AND e.alignment_run_id IS NOT NULL");
verifyTrue(testCase, ismember(t.offset_run, double(used.alignment_run_id)), ...
    "The variant's clock evidence cites the alternative fit.");
end

% ============================================== reported and refused ===

function testHandlesThatAreNotVariedAreRowsWithTheirReason(testCase)
t = testCase.TestData;
rows = t.summary.rows;
expected = ["call_band", "not_exercised"; "dimension_declarations", "not_variable"; ...
    "identity_uncertainty", "not_measurable"; "pose_confidence_gate", "not_variable"; ...
    "positional_error", "reported_elsewhere"; "temporal_uncertainty_gate_s", "not_variable"];
for k = 1:size(expected, 1)
    row = rows(rows.handle == expected(k, 1), :);
    verifyEqual(testCase, height(row), 1, expected(k, 1));
    verifyEqual(testCase, row.status, expected(k, 2), expected(k, 1));
    verifyGreaterThan(testCase, strlength(row.reason), 20, expected(k, 1));
end
verifySubstring(testCase, rows.reason(rows.handle == "positional_error"), "qcFacts");
end

function testEachRefusalIsNamed(testCase)
t = testCase.TestData;
conn = t.fixture.conn;
plan = @(spec) vawlume.eda.attributionSensitivity(conn, spec, Print=false, RepoRoot=t.root);
noReference = rmfield(t.spec, "reference");
verifyError(testCase, @() plan(noReference), "vawlume:eda:SensitivityReferenceRequired");
mismatch = t.spec;
mismatch.reference.run_spec.run_key = "not-the-reference";
verifyError(testCase, @() plan(mismatch), "vawlume:eda:SensitivityReferenceRequired");
gate = t.spec;
gate.family_key = "p78-gate";
gate.variants = struct(handle="pose_confidence_gate", value=struct(value=0.5));
verifyError(testCase, @() plan(gate), "vawlume:eda:SensitivityHandleNotVariable");
unknown = gate;
unknown.variants = struct(handle="spreading_assumption", value=struct(model="cylindrical"));
verifyError(testCase, @() plan(unknown), "vawlume:eda:SensitivityHandleUnknown");
factor = gate;
factor.variants = struct(handle="estimator_settings", value=struct(bodypart="tail"));
verifyError(testCase, @() plan(factor), "vawlume:eda:SensitivityHandleUnknown");
end

% ================================================ the summary selects nothing ===

function testTheSummarySelectsNothing(testCase)
% Guard (contract 07 E4, itinerary 7.8 D): no column, cell or note names a
% variant best, optimal, recommended, stable, validated or calibrated, and rows
% are ordered by handle and value, never by outcome.
t = testCase.TestData;
s = t.summary;
verifyEmpty(testCase, forbiddenWords(s), "Forbidden words in the summary: " + ...
    strjoin(forbiddenWords(s), ", "));
verifyEqual(testCase, s.rows(:, ["handle", "handle_value"]), ...
    sortrows(s.rows(:, ["handle", "handle_value"])), "Ordered by handle and value only.");
end

function testTheExportCarriesProvenance(testCase)
t = testCase.TestData;
path = fullfile(t.work, "export", "p78_summary.csv");
vawlume.eda.sensitivitySummary(t.fixture.conn, ...
    struct(analysis_run_id=t.applied.family_analysis_run_id), Export=path);
lines = splitlines(string(fileread(path)));
header = jsondecode(extractAfter(lines(1), "# vawlume_table_export="));
p = header.provenance;
verifyEqual(testCase, double(p.family_analysis_run_id), t.applied.family_analysis_run_id);
verifyEqual(testCase, double(p.reference_attribution_run_id), ...
    t.fixture.manifest.runs.native_detections.attribution_run_id);
verifyEqual(testCase, numel(p.variant_policy_profile_version_ids), 4);
verifyEqual(testCase, string(p.schema_version), "0.14-draft");
end

% --------------------------------------------------------------- helpers ---

function spec = familySpec(t, key)
f = t.fixture;
m = f.manifest;
runs = m.acoustic.detection_normalization_runs;
runSpec = struct(run_key="p7-native-ds", ...
    settings_profile_version_id=m.profiles.estimator_settings_version_id, ...
    target_set=struct(detection_ids=m.scenes.deepsqueak_detection_id'), ...
    participating_entity_ids=[m.entities.A m.entities.B], ...
    clock=struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
        audio_alignment_run_id=m.alignment.audio.alignment_run_id), ...
    tracking=struct(stream=struct(project_key=m.project_key, stream_name="arena_tracking"), ...
        alignment_run_id=m.alignment.tracking.alignment_run_id, ...
        source_root=fullfile(f.root, "tracking")), ...
    normalization_runs=runs(:, ["detection_id", "analysis_run_id"]));
spec = struct(family_key=key, output_root=fullfile(t.work, "out"), ...
    reference=struct(attribution_run_id=m.runs.native_detections.attribution_run_id, ...
        run_spec=runSpec, decision_policy=fullfile(t.root, "config", ...
        "08_attribution_policies", "native_level_difference_decision_policy.json")), ...
    variants=[struct(handle="decision_policy", value=struct(selection_threshold=-1)), ...
        struct(handle="estimator_settings", value=struct(primary_instant_basis="onset")), ...
        struct(handle="normalization_policy", value=struct(reference_type="tone")), ...
        struct(handle="alignment_run", value=struct(audio_alignment_run_id=t.offset_run))]);
end

function id = offsetAudioFit(f, root)
% A second alignment set over the same audio anchors, declared with the offset
% model, ingested and fitted through the public path.
folder = fullfile(f.root, "alignment");
manifest = jsondecode(fileread(fullfile(folder, "audio_alignment_manifest.json")));
manifest.manifest.alignment_key = 'p78_audio_clock_offset';
manifest.method = 'offset';
path = fullfile(folder, "audio_offset_alignment_manifest.json");
fid = fopen(path, "w");
fwrite(fid, jsonencode(manifest, PrettyPrint=true));
fclose(fid);
vawlume.ingest.alignment(f.conn, path, RepoRoot=root, SourceRoot=string(folder), Apply=true);
key = f.manifest.project_key;
vawlume.alignment.fit(f.conn, struct(project_key=key, run_key="p78_audio_clock_offset"), ...
    SourceTimebase="audio_native", Apply=true);
qc = vawlume.alignment.report(f.conn, struct(project_key=key, run_key="p78_audio_clock_offset"));
id = double(qc.transforms.alignment_run_id(qc.transforms.source_timebase_key == "audio_native"));
end

function c = comparisonOf(t, handle)
id = t.applied.variants.configuration_id(t.applied.variants.handle == handle);
c = t.summary.comparisons([t.summary.comparisons.configuration_id] == id).comparison;
end

function row = summaryRow(t, handle)
row = t.summary.rows(t.summary.rows.handle == handle, :);
end

function v = variantOf(t, handle)
v = t.applied.variants(t.applied.variants.handle == handle, :);
end

function values = scoresOf(t, runId, targetId)
r = vawlume.attribution.report(t.fixture.conn, struct(attribution_run_id=runId), ...
    Targets=targetId, Tables="candidates");
values = sortrows(r.candidates, "entity_id").score';
end

function values = normalizedLevels(t, runId)
rows = fetch(t.fixture.conn, "SELECT e.value_real FROM attribution_evidence e JOIN " + ...
    "attribution_targets g ON g.attribution_target_id=e.attribution_target_id WHERE " + ...
    "g.attribution_run_id=" + string(runId) + " AND e.evidence_kind='call_band_power_normalized' " + ...
    "ORDER BY g.detection_id, e.recording_channel_id");
values = double(rows.value_real);
end

function words = forbiddenWords(s)
texts = [string(s.rows.Properties.VariableNames)'; string(s.note)];
for name = string(s.rows.Properties.VariableNames)
    if isstring(s.rows.(name))
        texts = [texts; s.rows.(name)]; %#ok<AGROW>
    end
end
% Letters only on either side: an underscore separates (best_variant), and
% "uncalibrated" or "unstable" are not the claim.
hits = regexp(lower(texts), "(?<![a-z])(best|optimal|recommended|stable|validated|calibrated)(?![a-z])", ...
    "match");
words = unique([hits{:}]);
end

function value = state(conn)
version = fetch(conn, "PRAGMA data_version");
changes = fetch(conn, "SELECT total_changes() AS n");
value = [double(version{1, 1}), double(changes.n(1))];
end

% ------------------------------------- plan §12 check 2 (contract 07 D13, E8) ---

function snapshot = nativeSnapshot(conn)
% Every column of every native table, type-faithful (REAL bit-exact by
% printf %!.17g, BLOB as hex, NULL as a token), in rowid order.
snapshot = struct();
for name = ["detections", "event_measurements", "external_events", ...
        "external_streams", "external_stream_sources", "external_stream_coverage", ...
        "tracking_streams", "tracking_series", "tracking_identity_associations", ...
        "imported_attribution_windows", "imported_attribution_claims", ...
        "attribution_localization_estimates", "artifacts", "source_files", ...
        "alignment_anchor_observations", "extraction_runs"]
    columns = string(fetch(conn, "SELECT name FROM pragma_table_info('" + name + ...
        "')").name)';
    projections = "IFNULL('V' || CASE typeof(""" + columns + """) " + ...
        "WHEN 'real' THEN printf('%!.17g', """ + columns + """) " + ...
        "WHEN 'blob' THEN hex(""" + columns + """) " + ...
        "ELSE CAST(""" + columns + """ AS TEXT) END, 'N')";
    rows = fetch(conn, "SELECT " + strjoin(projections + " AS c" + ...
        (1:numel(columns)), ", ") + " FROM """ + name + """ ORDER BY rowid");
    snapshot.(name) = string(table2cell(rows));
end
end
