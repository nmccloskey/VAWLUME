function tests = test_integrated_fixture
%TEST_INTEGRATED_FIXTURE The shared Phase 7 session (vawlume.db.buildIntegratedFixture).
%
% The fixture is built once for this class: a build takes minutes, and every
% test below reads it without writing, except the refusal test, which writes
% nothing because it is refused, and the determinism test, which builds its own.
%
% Every agreement asserted here is circular: the builder wrote every path's
% input. What these tests establish is that the scene exists as the manifest
% says, through the public API, reproducibly.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
started = tic;
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=repoRoot);
testCase.TestData.build_seconds = toc(started);
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
testCase.TestData.repoRoot = repoRoot;
log(testCase, 1, sprintf("Integrated fixture built in %.1f s", ...
    testCase.TestData.build_seconds));
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ================================================================ manifest ===

function testTheManifestNamesEveryRunSceneAndProfile(testCase)
m = testCase.TestData.fixture.manifest;
verifyEqual(testCase, m.scenes.scene', ["separable", "unfittable", ...
    "model_mismatch", "coverage_gap", "symmetric", "identity_swap", "out_of_bracket"]);
for name = ["native_detections", "native_consensus", "imported", "backend"]
    run = m.runs.(name);
    verifyEqual(testCase, numel(run.target_ids), 7, name + " targets every scene");
    verifyTrue(testCase, isfinite(run.attribution_run_id));
end
verifyEqual(testCase, [m.runs.native_detections.attribution_path, ...
    m.runs.native_consensus.attribution_path, m.runs.imported.attribution_path, ...
    m.runs.backend.attribution_path], ...
    ["native_estimate", "native_estimate", "imported", "backend"]);
verifyEqual(testCase, [m.runs.imported.synthetic_claims, m.runs.backend.synthetic_claims, ...
    m.runs.native_detections.synthetic_claims], [true, true, false]);
verifyTrue(testCase, contains(m.boundary, "circular"));
verifyTrue(testCase, isfinite(m.profiles.estimator_settings_version_id));
verifyTrue(testCase, isfinite(m.alignment.audio.alignment_run_id));
verifyTrue(testCase, isfinite(m.alignment.tracking.alignment_run_id));
verifyEqual(testCase, m.alignment.audio.method, "affine");
verifyEqual(testCase, m.alignment.audio.anchors, 3);
verifyEqual(testCase, m.alignment.tracking.method, "piecewise_affine");
verifyEqual(testCase, height(m.correspondence.structure), 3);
end

function testOneTargetIsAttributedByAllThreePathsAndTwoEventSets(testCase)
f = testCase.TestData.fixture;
m = f.manifest;
k = m.scenes.scene == "separable";
detection = m.scenes.deepsqueak_detection_id(k);
paths = fetch(f.conn, "SELECT DISTINCT ar.attribution_path FROM attribution_targets t " + ...
    "JOIN attribution_runs ar ON ar.attribution_run_id = t.attribution_run_id " + ...
    "WHERE t.detection_id = " + string(detection));
verifyEqual(testCase, sort(string(paths.attribution_path))', ...
    ["backend", "imported", "native_estimate"]);
consensus = fetch(f.conn, "SELECT COUNT(*) AS n FROM attribution_targets t " + ...
    "JOIN attribution_runs ar ON ar.attribution_run_id = t.attribution_run_id " + ...
    "WHERE ar.attribution_path = 'native_estimate' AND t.consensus_event_id = " + ...
    string(m.scenes.consensus_event_id(k)));
verifyEqual(testCase, double(consensus.n), 1, ...
    "The same call is a native target over consensus events too.");
members = fetch(f.conn, "SELECT detection_id FROM consensus_event_members " + ...
    "WHERE consensus_event_id = " + string(m.scenes.consensus_event_id(k)));
verifyTrue(testCase, any(double(members.detection_id) == detection), ...
    "The consensus event is built from the DeepSqueak detection it stands beside.");
end

% ================================================================= scenes ===

function testTheNativeScenesBehaveAsBuilt(testCase)
f = testCase.TestData.fixture;
m = f.manifest;
r = vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id));
A = m.entities.A;
B = m.entities.B;
status = @(scene) decisionOf(r, targetOf(m, scene, "native_detection_target_id"));
scores = @(scene) candidateScores(r, targetOf(m, scene, "native_detection_target_id"), [A B]);

verifyEqual(testCase, status("separable"), "assigned");
verifyEqual(testCase, selectedOf(r, targetOf(m, "separable", ...
    "native_detection_target_id")), A, "Self-consistency: A generated the call.");
s = scores("separable");
verifyGreaterThan(testCase, s(1), -0.05);

verifyEqual(testCase, status("unfittable"), "unassigned");

% The model-mismatch scene: B, which did not generate the call, fits within the
% selection threshold and is assigned. Nothing in the run flags it.
s = scores("model_mismatch");
verifyGreaterThan(testCase, s(2), s(1));
verifyEqual(testCase, status("model_mismatch"), "assigned");
verifyEqual(testCase, selectedOf(r, targetOf(m, "model_mismatch", ...
    "native_detection_target_id")), B);

verifyEqual(testCase, status("symmetric"), "ambiguous");
s = scores("symmetric");
verifyLessThan(testCase, abs(s(1) - s(2)), 1e-9);

verifyEqual(testCase, reasonsOf(r, targetOf(m, "coverage_gap", ...
    "native_detection_target_id")), ["track_covered_empty"; "track_covered_empty"]);
verifyEqual(testCase, reasonsOf(r, targetOf(m, "identity_swap", ...
    "native_detection_target_id")), ...
    ["identity_changes_within_window"; "identity_changes_within_window"]);
verifyEqual(testCase, reasonsOf(r, targetOf(m, "out_of_bracket", ...
    "native_detection_target_id")), ...
    ["alignment_extrapolated"; "alignment_extrapolated"]);
end

function testEveryNoScoreReasonIsStoredInTheMethodsOrder(testCase)
% Contract 07 D10 (itineraries 7.4, 7.5). Every unscored native candidate has
% its reasons in attribution_candidate_no_score_reasons, ordinals 1..n, and no
% notes token; report's no_score_reasons table shows exactly those rows. No
% scored candidate and no candidate of an external path states one.
f = testCase.TestData.fixture;
m = f.manifest;
rows = fetch(f.conn, "SELECT c.attribution_candidate_id, ar.attribution_path, " + ...
    "CASE WHEN c.score IS NULL THEN 1 ELSE 0 END AS unscored, " + ...
    "IFNULL(c.notes,'') AS notes, IFNULL(n.reason_ordinal,-1) AS reason_ordinal, " + ...
    "IFNULL(n.reason_code,'') AS reason_code, t.attribution_target_id " + ...
    "FROM attribution_candidates c " + ...
    "JOIN attribution_targets t ON t.attribution_target_id=c.attribution_target_id " + ...
    "JOIN attribution_runs ar ON ar.attribution_run_id=t.attribution_run_id " + ...
    "LEFT JOIN attribution_candidate_no_score_reasons n " + ...
    "ON n.attribution_candidate_id=c.attribution_candidate_id " + ...
    "ORDER BY c.attribution_candidate_id, n.reason_ordinal");
path = string(rows.attribution_path);
stated = double(rows.reason_ordinal) > 0;
verifyFalse(testCase, any(stated & path ~= "native_estimate"), ...
    "Imported and backend candidates state no reason.");
verifyFalse(testCase, any(stated & double(rows.unscored) == 0), ...
    "A scored candidate states no reason.");
native = path == "native_estimate" & double(rows.unscored) == 1;
ids = unique(double(rows.attribution_candidate_id(native)));
verifyGreaterThan(testCase, numel(ids), 0);
for id = ids'
    mine = rows(double(rows.attribution_candidate_id) == id, :);
    codes = string(mine.reason_code);
    verifyEqual(testCase, double(mine.reason_ordinal), (1:height(mine))', ...
        sprintf("candidate %d: ordinals 1..n, nothing unstated", id));
    notes = string(mine.notes(1));
    notes(ismissing(notes)) = "";   % SQLite's empty text arrives as <missing>
    verifyEqual(testCase, notes, "", ...
        sprintf("candidate %d: no notes token since 7.5", id));
    verifyNotEmpty(testCase, codes(1));
end
for scene = ["coverage_gap", "identity_swap", "out_of_bracket"]
    target = targetOf(m, scene, "native_detection_target_id");
    mine = rows(double(rows.attribution_target_id) == target, :);
    log(testCase, 1, scene + ": " + strjoin(string(mine.reason_code), ", "));
end
% report shows every stored reason, in stored order, for every run.
stored = rows(stated, :);
read = table();
for name = ["native_detections", "native_consensus", "imported", "backend"]
    r = vawlume.attribution.report(f.conn, ...
        struct(attribution_run_id=m.runs.(name).attribution_run_id));
    read = [read; r.no_score_reasons(:, ["attribution_candidate_id", ...
        "reason_ordinal", "reason_code"])]; %#ok<AGROW>
end
read = sortrows(read, ["attribution_candidate_id", "reason_ordinal"]);
verifyEqual(testCase, read.attribution_candidate_id, double(stored.attribution_candidate_id));
verifyEqual(testCase, read.reason_ordinal, double(stored.reason_ordinal));
verifyEqual(testCase, read.reason_code, string(stored.reason_code));
end

% ============================================================ read-back ===

function testEveryPathReadsBackThroughOneFieldSet(testCase)
% Invariant 16 over the 7.3 fixture's four runs (7.5). Every table-valued field
% is FOUND, not listed, so a table added later is compared without an edit. A
% path-only key, column or QC field fails here.
f = testCase.TestData.fixture;
m = f.manifest;
reports = struct();
for name = ["native_detections", "native_consensus", "imported", "backend"]
    reports.(name) = vawlume.attribution.report(f.conn, ...
        struct(attribution_run_id=m.runs.(name).attribution_run_id));
end
names = @(s) sort(string(fieldnames(s)))';
columns = @(t) sort(string(t.Properties.VariableNames));
reference = reports.native_detections;
tables = names(reference);
tables = tables(arrayfun(@(n) istable(reference.(n)), tables));
verifyTrue(testCase, all(ismember(["windows", "no_score_reasons"], tables)));
for name = ["native_consensus", "imported", "backend"]
    r = reports.(name);
    verifyEqual(testCase, names(r), names(reference), name + " top-level fields");
    verifyEqual(testCase, names(r.qc), names(reference.qc), name + " QC fields");
    for table_ = tables(ismember(tables, names(r)))   % a missing key failed above
        verifyEqual(testCase, columns(r.(table_)), columns(reference.(table_)), ...
            name + " " + table_ + " columns");
    end
end
% Present for every path; empty where the path writes none.
verifyEqual(testCase, height(reports.native_detections.windows), 0);
verifyGreaterThan(testCase, height(reports.imported.windows), 0);
verifyGreaterThan(testCase, height(reports.backend.windows), 0);
verifyGreaterThan(testCase, height(reports.native_detections.no_score_reasons), 0);
verifyEqual(testCase, height(reports.imported.no_score_reasons), 0);
end

function testTargetsNameTheirStoredEvent(testCase)
% 7.5a: report.targets carries each target's stored event id, so two runs over
% one event set meet on it without SQL of their own (contract 07 D3).
f = testCase.TestData.fixture;
m = f.manifest;
for name = ["native_detections", "imported", "backend"]
    r = vawlume.attribution.report(f.conn, ...
        struct(attribution_run_id=m.runs.(name).attribution_run_id), Tables="targets");
    verifyEqual(testCase, sort(r.targets.detection_id), sort(m.scenes.deepsqueak_detection_id), name);
    verifyTrue(testCase, all(isnan(r.targets.consensus_event_id) & ...
        isnan(r.targets.agreement_group_id) & r.targets.agreement_extent_method == ""), name);
end
r = vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.native_consensus.attribution_run_id), Tables="targets");
verifyEqual(testCase, sort(r.targets.consensus_event_id), sort(m.scenes.consensus_event_id));
verifyTrue(testCase, all(isnan(r.targets.detection_id)));
end

function testWindowsAreReadBackAsStored(testCase)
% I-3: one row per stored window, native times verbatim, and every
% correspondence's window is one of them.
f = testCase.TestData.fixture;
m = f.manifest;
for name = ["imported", "backend"]
    runId = m.runs.(name).attribution_run_id;
    r = vawlume.attribution.report(f.conn, struct(attribution_run_id=runId));
    stored = fetch(f.conn, "SELECT imported_attribution_window_id, start_time_native, " + ...
        "end_time_native FROM imported_attribution_windows WHERE attribution_run_id=" + ...
        string(runId) + " ORDER BY imported_attribution_window_id");
    verifyEqual(testCase, r.windows.imported_attribution_window_id, ...
        double(stored.imported_attribution_window_id), name);
    verifyEqual(testCase, r.windows.start_time_native, double(stored.start_time_native), name);
    verifyEqual(testCase, r.windows.end_time_native, double(stored.end_time_native), name);
    verifyEqual(testCase, r.qc.imported_window_count, height(r.windows), name);
    verifyTrue(testCase, all(ismember(r.correspondences.imported_attribution_window_id, ...
        r.windows.imported_attribution_window_id)), name);
    verifyTrue(testCase, all(ismember(r.imported_claims.imported_attribution_window_id, ...
        r.windows.imported_attribution_window_id)), name);
end
end

function testPagesConcatenateToTheFullRead(testCase)
% I-6: Targets= slices, concatenated, give every target-grained table of the full
% read with no row lost or duplicated; each page holds only its targets; QC is
% the whole run's whatever the filter; Tables= projects.
f = testCase.TestData.fixture;
m = f.manifest;
grained = ["targets", "candidates", "no_score_reasons", "evidence", ...
    "correspondences", "claim_correspondences", "decisions", "decision_selections"];
keys = struct(targets="attribution_target_id", ...
    candidates="attribution_candidate_id", ...
    no_score_reasons=["attribution_candidate_id", "reason_ordinal"], ...
    evidence="attribution_evidence_id", ...
    correspondences="attribution_window_correspondence_id", ...
    claim_correspondences=["attribution_window_correspondence_id", ...
        "imported_attribution_claim_id"], ...
    decisions="attribution_decision_id", ...
    decision_selections=["attribution_decision_id", "attribution_candidate_id"]);
for name = ["native_detections", "imported", "backend"]
    ref = struct(attribution_run_id=m.runs.(name).attribution_run_id);
    full = vawlume.attribution.report(f.conn, ref);
    ids = full.targets.attribution_target_id';
    for pageSize = [1, 3]
        pages = struct();
        for table_ = grained
            pages.(table_) = full.(table_)([], :);
        end
        for first = 1:pageSize:numel(ids)
            slice = ids(first:min(first + pageSize - 1, end));
            page = vawlume.attribution.report(f.conn, ref, Targets=slice, Tables=grained);
            verifyFalse(testCase, isfield(page, "qc"), "Tables= projects qc away.");
            verifyFalse(testCase, isfield(page, "windows"));
            for table_ = grained
                verifyTrue(testCase, all(ismember(page.(table_).attribution_target_id, slice)), ...
                    sprintf("%s %s page holds only its targets", name, table_));
                pages.(table_) = [pages.(table_); page.(table_)];
            end
        end
        for table_ = grained
            label = sprintf("%s %s, pages of %d", name, table_, pageSize);
            verifyEqual(testCase, height(pages.(table_)), height(full.(table_)), label);
            verifyEqual(testCase, sortrows(pages.(table_), keys.(table_)), ...
                sortrows(full.(table_), keys.(table_)), label);
        end
    end
    filtered = vawlume.attribution.report(f.conn, ref, Targets=ids(1));
    verifyEqual(testCase, filtered.qc, full.qc, name + ": QC describes the whole run");
    verifyEqual(testCase, filtered.windows, full.windows, name + ": windows are run-grained");
end
other = m.runs.imported.target_ids(1);
verifyError(testCase, @() vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id), ...
    Targets=other), "vawlume:attribution:TargetNotFound");
verifyError(testCase, @() vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id), ...
    Tables="candidate"), "MATLAB:validators:mustBeMember");
end

function testTheOutOfBracketCallReachesBracketExtrapolatedTrue(testCase)
% Closes the Phase 6 ledger item: the flag had only ever been exercised as false.
f = testCase.TestData.fixture;
m = f.manifest;
target = targetOf(m, "out_of_bracket", "native_detection_target_id");
rows = fetch(f.conn, "SELECT IFNULL(value_semantics,'') AS s FROM attribution_evidence " + ...
    "WHERE attribution_target_id = " + string(target) + ...
    " AND evidence_kind = 'bodypoint_microphone_distance'");
semantics = string(rows.s);
verifyNotEmpty(testCase, semantics);
verifyTrue(testCase, all(contains(semantics, "bracket_extrapolated=true")));
verifyTrue(testCase, all(contains(semantics, "event_extrapolated=false")), ...
    "The call itself is inside the audio clock's anchors; only tracking is not.");
other = fetch(f.conn, "SELECT COUNT(*) AS n FROM attribution_evidence " + ...
    "WHERE attribution_target_id = " + string(targetOf(m, "separable", ...
    "native_detection_target_id")) + " AND value_semantics LIKE '%bracket_extrapolated=true%'");
verifyEqual(testCase, double(other.n), 0);
end

function testImportedRunCarriesTheStructuralEmptyAndADisagreement(testCase)
f = testCase.TestData.fixture;
m = f.manifest;
imported = vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.imported.attribution_run_id));
native = vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.native_detections.attribution_run_id));
verifyEqual(testCase, decisionOf(imported, targetOf(m, "symmetric", ...
    "imported_target_id")), "simultaneous", ...
    "A status the native path cannot produce: a structural empty for comparison.");
verifyEqual(testCase, decisionOf(native, targetOf(m, "symmetric", ...
    "native_detection_target_id")), "ambiguous");
verifyEqual(testCase, selectedOf(imported, targetOf(m, "separable", ...
    "imported_target_id")), m.entities.B);
verifyEqual(testCase, selectedOf(native, targetOf(m, "separable", ...
    "native_detection_target_id")), m.entities.A, ...
    "The imported and native selections disagree on the separable call.");
backend = vawlume.attribution.report(f.conn, ...
    struct(attribution_run_id=m.runs.backend.attribution_run_id));
verifyEqual(testCase, decisionOf(backend, targetOf(m, "separable", ...
    "backend_target_id")), "assigned");
verifyEqual(testCase, sort(string(backend.declared_inputs.input_dimension))', ...
    ["acoustic", "pose_localization", "visual_identity"]);
verifyEmpty(testCase, imported.declared_inputs, "An imported run declares nothing.");
end

function testTheCorrespondenceScenesProduceTheirUnits(testCase)
% D3's units, read from the stored topology of the named analysis. Left is
% DeepSqueak in every scene.
f = testCase.TestData.fixture;
structure = f.manifest.correspondence.structure;
for k = 1:height(structure)
    left = structure.left_detection_ids{k};
    right = structure.right_detection_ids{k};
    groups = fetch(f.conn, "SELECT mg.match_type FROM match_groups mg " + ...
        "JOIN match_group_members mgm ON mgm.match_group_id = mg.match_group_id " + ...
        "WHERE mg.analysis_run_id = " + string(structure.analysis_run_id(k)) + ...
        " AND mgm.detection_id = " + string(left(1)));
    stored = string(groups.match_type);
    switch structure.expected_unit(k)
        case "one_to_many"
            verifyEqual(testCase, [numel(left), numel(right)], [1 2]);
            verifyEqual(testCase, stored, "one_to_many");
        case "many_to_one"
            verifyEqual(testCase, [numel(left), numel(right)], [2 1]);
            verifyEqual(testCase, stored, "many_to_one");
        case "unmatched_left"
            verifyEqual(testCase, [numel(left), numel(right)], [1 0]);
            verifyEqual(testCase, stored, "unmatched");
    end
end
end

function testTheRealShapeTokensSurviveAsRawTokens(testCase)
f = testCase.TestData.fixture;
t = f.manifest.real_shape_tokens;
for token = [t.mupet_terminal_interval, t.usvseg_nan]
    rows = fetch(f.conn, "SELECT IFNULL(native_raw_token,'') AS raw, " + ...
        "IFNULL(native_value_real,-999.0) AS native, " + ...
        "IFNULL(canonical_value_real,-999.0) AS canonical FROM event_measurements " + ...
        "WHERE detection_id = " + string(token.detection_id) + ...
        " AND native_raw_token = '" + token.raw_token + "'");
    verifyEqual(testCase, height(rows), 1, token.raw_token + " is stored once, raw");
    verifyEqual(testCase, double(rows.native), -999.0, "No numeric payload: absence.");
    verifyEqual(testCase, double(rows.canonical), -999.0, "Never zero.");
end
box = fetch(f.conn, "SELECT ef.native_name AS name, em.native_value_real AS v " + ...
    "FROM event_measurements em JOIN extractor_features ef " + ...
    "ON ef.extractor_feature_id = em.extractor_feature_id " + ...
    "WHERE em.detection_id = " + string(t.deepsqueak_zero_height.detection_id) + ...
    " AND ef.native_name IN ('Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)')");
values = containers.Map(cellstr(string(box.name)), num2cell(double(box.v)));
verifyEqual(testCase, values('Low Freq (kHz)'), values('High Freq (kHz)'));
verifyEqual(testCase, values('Delta Freq (kHz)'), 0, ...
    "A zero-height box is stored literally, never widened.");
end

function testTheSecondMicrophoneIsRefusedByTheNativePath(testCase)
% The real rig's separately started microphone is its own recording. Pairing its
% call with the session's tracking and normalization is refused by name.
f = testCase.TestData.fixture;
m = f.manifest;
detection = fetch(f.conn, "SELECT d.detection_id FROM detections d " + ...
    "WHERE d.recording_id = " + string(m.second_microphone_recording_id) + ...
    " ORDER BY d.start_time_s LIMIT 1");
detection = double(detection.detection_id(1));
normalization = m.acoustic.detection_normalization_runs;
spec = struct(run_key="p7-refused-secondmic", ...
    settings_profile_version_id=m.profiles.estimator_settings_version_id, ...
    target_set=struct(detection_ids=detection), ...
    participating_entity_ids=[m.entities.A m.entities.B], ...
    clock=struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
        audio_alignment_run_id=m.alignment.audio.alignment_run_id), ...
    tracking=struct(stream=struct(project_key=m.project_key, stream_name="arena_tracking"), ...
        alignment_run_id=m.alignment.tracking.alignment_run_id, ...
        source_root=f.root + "/tracking"), ...
    normalization_runs=table(detection, normalization.analysis_run_id(1), ...
        VariableNames=["detection_id", "analysis_run_id"]));
before = fetch(f.conn, "SELECT COUNT(*) AS n FROM attribution_runs");
verifyError(testCase, @() vawlume.estimator.attributeCallers(f.conn, ...
    struct(recording_id=m.second_microphone_recording_id), spec, Apply=true, ...
    RepoRoot=f.repo_root), "vawlume:estimator:InputRecordingMismatch");
after = fetch(f.conn, "SELECT COUNT(*) AS n FROM attribution_runs");
verifyEqual(testCase, double(after.n), double(before.n));
end

function testTheDatabaseIsConsistentAndCarriesTheCsvValues(testCase)
f = testCase.TestData.fixture;
verifyEmpty(testCase, fetch(f.conn, "PRAGMA foreign_key_check"));
description = fetch(f.conn, "SELECT description FROM projects WHERE project_key = '" + ...
    f.manifest.project_key + "'");
text = string(description.description(1));
verifyTrue(testCase, contains(text, char(8212)), "A non-ASCII character.");
verifyTrue(testCase, contains(text, newline), "An embedded newline.");
verifyEqual(testCase, text, f.manifest.csv_values.project_description);
end

% =========================================================== reproducible ===

function testTwoBuildsAreIdenticalAndCleanupRemovesEverything(testCase)
root = string(fullfile(tempdir, "vawlume_fixture_determinism_" + ...
    string(java.util.UUID.randomUUID)));
saved = string(tempname) + ".sqlite";
removeSaved = onCleanup(@() deleteIfPresent(saved));

[first, firstCleanup] = vawlume.db.buildIntegratedFixture(Root=root, ...
    RepoRoot=testCase.TestData.repoRoot); %#ok<ASGLU> held until cleared below
firstHashes = artifactHashes(root);
close(first.conn);
copyfile(first.database_path, saved);
clear firstCleanup
verifyFalse(testCase, isfolder(root), "Cleanup removes the whole build root.");

[second, secondCleanup] = vawlume.db.buildIntegratedFixture(Root=root, ...
    RepoRoot=testCase.TestData.repoRoot); %#ok<ASGLU> held until cleared below
verifyEqual(testCase, artifactHashes(root), firstHashes, ...
    "Every artifact the build writes is byte-identical across builds.");
differences = contentDifferences(second.conn, saved);
verifyEmpty(testCase, differences, strjoin(differences, newline));
verifyEqual(testCase, second.manifest.scenes, first.manifest.scenes);
clear secondCleanup
verifyFalse(testCase, isfolder(root));
end

% ================================================================ helpers ===

function id = targetOf(m, scene, column)
id = m.scenes.(column)(m.scenes.scene == scene);
end

function value = decisionOf(report, targetId)
value = string(report.decisions.decision_status( ...
    report.decisions.attribution_target_id == targetId));
end

function value = selectedOf(report, targetId)
selected = report.decision_selections(report.decision_selections.attribution_target_id == ...
    targetId, :);
candidates = report.candidates(ismember(report.candidates.attribution_candidate_id, ...
    selected.attribution_candidate_id), :);
value = double(candidates.entity_id)';
end

function value = candidateScores(report, targetId, entities)
c = report.candidates(report.candidates.attribution_target_id == targetId, :);
value = arrayfun(@(e) c.score(c.entity_id == e), entities);
end

function value = reasonsOf(report, targetId)
% Each candidate's first stated reason, in report's candidate order (7.5: from
% the no_score_reasons table; "" where a candidate states none).
c = report.candidates(report.candidates.attribution_target_id == targetId, :);
first = report.no_score_reasons(report.no_score_reasons.reason_ordinal == 1, :);
value = strings(height(c), 1);
[found, at] = ismember(c.attribution_candidate_id, first.attribution_candidate_id);
value(found) = first.reason_code(at(found));
end

function value = artifactHashes(root)
listing = dir(fullfile(root, "**", "*"));
listing = listing(~[listing.isdir]);
names = strings(0, 1);
hashes = strings(0, 1);
for k = 1:numel(listing)
    full = string(fullfile(listing(k).folder, listing(k).name));
    if endsWith(full, ".sqlite") || contains(full, ".sqlite-"), continue, end
    names(end + 1, 1) = extractAfter(replace(full, "\", "/"), ...
        strlength(replace(root, "\", "/")) + 1); %#ok<AGROW>
    hashes(end + 1, 1) = sha256Of(full); %#ok<AGROW>
end
[names, order] = sort(names);
value = table(names, hashes(order), VariableNames=["path", "sha256"]);
end

function value = sha256Of(path)
digest = java.security.MessageDigest.getInstance("SHA-256");
fileId = fopen(path, "r");
bytes = fread(fileId, Inf, "*uint8");
fclose(fileId);
digest.update(typecast(bytes, "int8"));
value = string(reshape(dec2hex(typecast(digest.digest(), "uint8"), 2)', 1, []));
end

function differences = contentDifferences(conn, savedPath)
% Row content of every table, compared by SQL so NULLs never reach MATLAB.
% Columns that record WHEN something happened are the only exclusions.
execute(conn, "ATTACH DATABASE '" + replace(savedPath, "'", "''") + "' AS prior");
detach = onCleanup(@() execute(conn, "DETACH DATABASE prior"));
tables = fetch(conn, "SELECT name FROM sqlite_master WHERE type='table' " + ...
    "AND name NOT LIKE 'sqlite_%' ORDER BY name");
differences = strings(0, 1);
for name = string(tables.name)'
    columns = fetch(conn, "SELECT name FROM pragma_table_info('" + name + "')");
    columns = string(columns.name);
    columns = columns(~endsWith(columns, "_at_utc"));
    list = strjoin("""" + columns + """", ", ");
    for direction = ["main", "prior"; "prior", "main"]'
        n = fetch(conn, "SELECT COUNT(*) AS n FROM (SELECT " + list + " FROM " + ...
            direction(1) + "." + name + " EXCEPT SELECT " + list + " FROM " + ...
            direction(2) + "." + name + ")");
        if double(n.n) > 0
            differences(end + 1, 1) = sprintf("%s: %d row(s) in %s only", ...
                name, double(n.n), direction(1)); %#ok<AGROW>
        end
    end
end
clear detach
end

function deleteIfPresent(path)
if isfile(path), delete(path); end
end
