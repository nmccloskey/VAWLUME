function tests = test_backend_attribution_path
%TEST_BACKEND_ATTRIBUTION_PATH A backend run, end to end, through the Phase 4 functions.
%
% Verify-and-complete for Path B. Phase 4.13 recorded that run creation,
% correspondence, candidates and decisions already work for a run whose
% attribution_path is 'backend'. Each step here is a test, not a sentence in a
% handoff, and every step runs through the same public function the imported
% path uses:
%
%   createRun -> backendAttribution -> correspondWindows -> addCandidates
%   -> addEvidence -> decide
%
% The export makes all five decision statuses reachable from the backend's own
% numbers, and one event is the spatial ambiguity case: two localized sources,
% two candidates, nothing chooses.
tests = functiontests(localfunctions);
end

% --- 1. run creation --------------------------------------------------------

function testABackendRunIsCreatedThroughCreateRun(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
run = fetch(fixture.conn, "SELECT attribution_path AS path, status, method " + ...
    "FROM attribution_runs WHERE attribution_run_id=" + string(fixture.run_id));
verifyEqual(testCase, string(run.path), "backend");
verifyEqual(testCase, string(run.status), "planned");
targets = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_targets " + ...
    "WHERE attribution_run_id=" + string(fixture.run_id));
verifyEqual(testCase, double(targets.n), 5);
clear cleanup
end

function testANativeEstimateRunNeedsItsOwnProfileAndDeclarations(testCase)
% Revised at 6.8, which admits native_estimate (contract 06 D16). Before 6.8 this
% test asserted the path was refused outright. A native run with a backend run's
% spec is still refused, now for the two things a native run needs that a
% backend spec lacks: its declarations, and an estimator-kind profile.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = height(fetch(fixture.conn, "SELECT attribution_run_id FROM attribution_runs"));
spec = runSpec(fixture, "native-run", "native_estimate");
verifyError(testCase, @() vawlume.attribution.createRun(fixture.conn, ...
    struct(recording_id=1), spec, Apply=true), ...
    "vawlume:attribution:DeclaredInputsRequired");
spec.declared_inputs = table(["temporal_alignment"; "pose_localization"; ...
    "visual_identity"; "acoustic"], repmat("used", 4, 1), ...
    VariableNames=["input_dimension", "declaration"]);
verifyError(testCase, @() vawlume.attribution.createRun(fixture.conn, ...
    struct(recording_id=1), spec, Apply=true), ...
    "vawlume:attribution:NativeRunProfileRequired");
verifyError(testCase, @() vawlume.attribution.createRun(fixture.conn, ...
    struct(recording_id=1), setfield(runSpec(fixture, "bogus-run", "bogus"), ...
    "method", "x"), Apply=true), "vawlume:attribution:RunSpecInvalid");
verifyEqual(testCase, height(fetch(fixture.conn, ...
    "SELECT attribution_run_id FROM attribution_runs")), before);
clear cleanup
end

% --- 2. correspondence, on both clock declarations --------------------------

function testSameClockCorrespondenceRelatesEachBackendWindowToItsEvent(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), ...
    SameClock=true, Apply=true);
rows = fetch(fixture.conn, "SELECT w.native_window_id AS window, t.detection_id AS event, " + ...
    "c.iou_basis AS basis, c.temporal_iou AS iou " + ...
    "FROM attribution_window_correspondences c " + ...
    "JOIN imported_attribution_windows w ON w.imported_attribution_window_id = c.imported_attribution_window_id " + ...
    "JOIN attribution_targets t ON t.attribution_target_id = c.attribution_target_id " + ...
    "ORDER BY w.native_window_id");
verifyEqual(testCase, string(rows.window)', ["s1" "s2" "s3" "s4" "s5"]);
verifyEqual(testCase, double(rows.event)', 1:5);
verifyEqual(testCase, unique(string(rows.basis)), "native");
verifyEqual(testCase, double(rows.iou)', ones(1, 5), AbsTol=1e-12);
verifyEqual(testCase, height(result.correspondences), 5);
clear cleanup
end

function testAlignedCorrespondenceRelatesABackendOnItsOwnClock(testCase)
% A second backend run whose export is on the backend's clock: native time t
% lands at 1.0*t + 5.0 on the recording's. The transform is the fitted one in
% the fixture, reached only through AlignmentRun.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
second = createBackendRun(fixture, "backend-own-clock");
source = writeSource(fixture, "s1,-4.0,-3.5,A,0.95,10,20" + newline + ...
    "s2,-3.0,-2.5,A,0.85,10,20");
% The anchors bound [-9, 20] on the source clock, so nothing is extrapolated.
vawlume.ingest.backendAttribution(fixture.conn, struct(attribution_run_id=second), ...
    source, Apply=true);
result = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=second), AlignmentRun=fixture.alignment_run_id, Apply=true);
verifyEqual(testCase, height(result.correspondences), 2);
stored = fetch(fixture.conn, "SELECT c.iou_basis AS basis, c.aligned_start_s AS s, " + ...
    "c.alignment_run_id AS run FROM attribution_window_correspondences c " + ...
    "JOIN attribution_targets t ON t.attribution_target_id = c.attribution_target_id " + ...
    "WHERE t.attribution_run_id=" + string(second) + " ORDER BY c.aligned_start_s");
verifyEqual(testCase, unique(string(stored.basis)), "aligned");
verifyEqual(testCase, double(stored.s)', [1.0 2.0], AbsTol=1e-12);
verifyEqual(testCase, unique(double(stored.run)), fixture.alignment_run_id);
clear cleanup
end

function testTheEligibilityRuleComesFromTheBackendProfile(testCase)
% A stricter rule in the backend's own profile suppresses a correspondence the
% shipped rule makes, so the rule correspondWindows applied is the one the
% backend import registered -- not the imported template's, not a constant.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeSource(fixture, "s1,1.1,1.6,A,0.95,10,20");   % IoU 0.5/0.6 with event 1
lenient = createBackendRun(fixture, "lenient-rule");
vawlume.ingest.backendAttribution(fixture.conn, struct(attribution_run_id=lenient), ...
    source, Apply=true);
strict = createBackendRun(fixture, "strict-rule");
vawlume.ingest.backendAttribution(fixture.conn, struct(attribution_run_id=strict), ...
    source, Apply=true, ProfilePath=variantProfile(fixture, @withStrictRule));
lenientResult = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=lenient), SameClock=true, Apply=true);
strictResult = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=strict), SameClock=true, Apply=true);
verifyEqual(testCase, height(lenientResult.correspondences), 1);
verifyEqual(testCase, height(strictResult.correspondences), 0);
clear cleanup
end

function testAWindowSpanningTwoEventsCorrespondsToBothAndNeitherIsChosen(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
wide = createBackendRun(fixture, "wide-window");
vawlume.ingest.backendAttribution(fixture.conn, struct(attribution_run_id=wide), ...
    writeSource(fixture, "w,1.2,2.3,A,0.9,10,20"), Apply=true);
result = vawlume.attribution.correspondWindows(fixture.conn, ...
    struct(attribution_run_id=wide), SameClock=true, Apply=true);
verifyEqual(testCase, height(result.correspondences), 2);
clear cleanup
end

% --- 3. candidates ------------------------------------------------------------

function testBackendScoresBecomeCandidatesOnlyThroughAddCandidates(testCase)
% Tripwire 3, at run time: intake and correspondence wrote no candidate; the
% only candidates are the ones addCandidates wrote, and they carry the backend's
% numbers and semantics unchanged.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), SameClock=true, Apply=true);
verifyEqual(testCase, countOf(fixture, "attribution_candidates"), 0);
written = promoteClaims(fixture);
verifyEqual(testCase, countOf(fixture, "attribution_candidates"), written);
stored = fetch(fixture.conn, "SELECT c.score AS candidate, cl.score AS claim, " + ...
    "c.score_semantics AS semantics FROM attribution_candidates c " + ...
    "JOIN attribution_targets t ON t.attribution_target_id = c.attribution_target_id " + ...
    "JOIN attribution_window_correspondences wc ON wc.attribution_target_id = t.attribution_target_id " + ...
    "JOIN imported_attribution_claims cl ON cl.imported_attribution_window_id = " + ...
    "wc.imported_attribution_window_id AND cl.entity_id = c.entity_id " + ...
    "WHERE c.score IS NOT NULL");
verifyTrue(testCase, isequal(double(stored.candidate), double(stored.claim)));
verifyTrue(testCase, all(contains(string(stored.semantics), "Example Localization Backend")));
clear cleanup
end

function testTheParticipantRuleStillHoldsForBackendCandidates(testCase)
% Entity 3 exists but is not linked to the recording.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), SameClock=true, Apply=true);
verifyError(testCase, @() vawlume.attribution.addCandidates(fixture.conn, ...
    struct(attribution_target_id=fixture.targets(1)), ...
    table(3, 0.9, "s", VariableNames=["entity_id", "score", "score_semantics"]), ...
    Apply=true), "vawlume:attribution:CandidateNotInRun");
clear cleanup
end

function testRankMustAgreeWithTheBackendScore(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), SameClock=true, Apply=true);
candidates = table([1; 2], [0.95; 0.10], ["s"; "s"], [2; 1], ...
    VariableNames=["entity_id", "score", "score_semantics", "candidate_rank"]);
verifyError(testCase, @() vawlume.attribution.addCandidates(fixture.conn, ...
    struct(attribution_target_id=fixture.targets(1)), candidates, Apply=true), ...
    "vawlume:attribution:CandidateRankConflict");
clear cleanup
end

% --- 4. decisions: all five statuses over backend candidates ------------------

function testAllFiveStatusesAreReachableOverBackendCandidates(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runFullPath(fixture);
decisions = fetch(fixture.conn, "SELECT t.detection_id AS event, d.decision_status AS status, " + ...
    "IFNULL(d.applied_threshold,-1.0) AS threshold, d.policy_profile_version_id AS policy, " + ...
    "(SELECT COUNT(*) FROM attribution_decision_candidates dc " + ...
    " WHERE dc.attribution_decision_id = d.attribution_decision_id) AS selected " + ...
    "FROM attribution_decisions d JOIN attribution_targets t " + ...
    "ON t.attribution_target_id = d.attribution_target_id ORDER BY t.detection_id");
verifyEqual(testCase, string(decisions.status)', ...
    ["assigned" "simultaneous" "ambiguous" "unassigned" "excluded"]);
verifyEqual(testCase, double(decisions.selected)', [1 2 0 0 0]);
% Each decision retains the policy that produced it, and every decision the rule
% actually ran for records the threshold that bound it.
verifyEqual(testCase, numel(unique(double(decisions.policy))), 1);
verifyTrue(testCase, all(double(decisions.threshold(1:4)) > 0));
verifyEqual(testCase, double(decisions.threshold(5)), -1.0);
clear cleanup
end

function testTheRunCompletesAndFreezesItsEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runFullPath(fixture);
run = fetch(fixture.conn, "SELECT status FROM attribution_runs WHERE attribution_run_id=" + ...
    string(fixture.run_id));
verifyEqual(testCase, string(run.status), "complete");
verifyError(testCase, @() vawlume.attribution.addCandidates(fixture.conn, ...
    struct(attribution_target_id=fixture.targets(4)), ...
    table(1, 0.99, "s", VariableNames=["entity_id", "score", "score_semantics"]), ...
    Apply=true), "vawlume:attribution:RunNotWritable");
verifyError(testCase, @() vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_target_id=fixture.targets(4)), localizationRow(fixture.estimates(4)), ...
    Apply=true), "vawlume:attribution:RunNotWritable");
clear cleanup
end

% --- D. ambiguity over a spatial backend ---------------------------------------

function testTwoLocalizedSourcesGiveTwoCandidatesAndNothingChooses(testCase)
% The backend localized two plausible sources for the s3 call, one per claimed
% caller. Both become candidates with their own localization evidence; the
% decision is ambiguous; both candidates remain, neither is selected, and both
% estimates remain readable.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
runFullPath(fixture);
target = fixture.targets(3);
candidates = fetch(fixture.conn, "SELECT c.entity_id AS entity, c.candidate_status AS status, " + ...
    "le.position_x AS x FROM attribution_candidates c " + ...
    "JOIN attribution_evidence ev ON ev.attribution_candidate_id = c.attribution_candidate_id " + ...
    "AND ev.evidence_dimension = 'source_localization' " + ...
    "JOIN attribution_localization_estimates le " + ...
    "ON le.attribution_localization_estimate_id = ev.attribution_localization_estimate_id " + ...
    "WHERE c.attribution_target_id=" + string(target) + " ORDER BY c.entity_id");
verifyEqual(testCase, double(candidates.entity)', [1 2]);
verifyEqual(testCase, double(candidates.x)', [10 40], ...
    "Each candidate keeps its own localized source.");
verifyEqual(testCase, unique(string(candidates.status)), "candidate", ...
    "Neither candidate is marked selected or rejected.");
decision = fetch(fixture.conn, "SELECT decision_status AS status FROM attribution_decisions " + ...
    "WHERE attribution_target_id=" + string(target));
verifyEqual(testCase, string(decision.status), "ambiguous");
clear cleanup
end

function testNoWritePathPromotesAnEstimateIntoACandidate(testCase)
% Tripwire 3, statically: the only code that inserts candidates is the
% candidate-plan apply, and no code that reads localization estimates writes one.
root = repositoryRoot();
files = dir(fullfile(root, "src", "**", "*.m"));
writers = strings(0, 1);
readersThatWrite = strings(0, 1);
for index = 1:numel(files)
    text = string(fileread(fullfile(files(index).folder, files(index).name)));
    code = strjoin(regexprep(splitlines(text), "%.*$", ""), newline);
    writesCandidates = contains(code, """attribution_candidates""") && ...
        (contains(code, "InsertRow") || contains(code, "sqlwrite"));
    if writesCandidates
        writers(end+1, 1) = string(files(index).name); %#ok<AGROW>
        if contains(code, "attribution_localization_estimates")
            readersThatWrite(end+1, 1) = string(files(index).name); %#ok<AGROW>
        end
    end
end
verifyEqual(testCase, writers, "attributionApplyCandidatePlan.m");
verifyEmpty(testCase, readersThatWrite);
end

% ---------------------------------------------------------------- helpers ---

function runFullPath(fixture)
vawlume.attribution.correspondWindows(fixture.conn, runRef(fixture), SameClock=true, Apply=true);
promoteClaims(fixture);
% Each candidate on s3 receives the estimate its producer tied to it.
for entity = [1 2]
    candidate = fetch(fixture.conn, "SELECT attribution_candidate_id AS id " + ...
        "FROM attribution_candidates WHERE attribution_target_id=" + ...
        string(fixture.targets(3)) + " AND entity_id=" + string(entity));
    estimate = fetch(fixture.conn, "SELECT le.attribution_localization_estimate_id AS id " + ...
        "FROM attribution_localization_estimates le JOIN imported_attribution_claims c " + ...
        "ON c.imported_attribution_claim_id = le.imported_attribution_claim_id " + ...
        "JOIN imported_attribution_windows w ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
        "WHERE w.native_window_id='s3' AND w.attribution_run_id=" + string(fixture.run_id) + ...
        " AND c.entity_id=" + string(entity));
    vawlume.attribution.addEvidence(fixture.conn, ...
        struct(attribution_candidate_id=double(candidate.id(1))), ...
        localizationRow(double(estimate.id(1))), Apply=true);
end
vawlume.attribution.decide(fixture.conn, runRef(fixture), Apply=true);
end

function written = promoteClaims(fixture)
% The explicit promotion: for each target, the claims over the window that
% corresponds to it become candidates, numbers and semantics copied unchanged.
written = 0;
for target = fixture.targets
    claims = fetch(fixture.conn, "SELECT cl.entity_id AS entity_id, " + ...
        "IFNULL(cl.score,-999.0) AS score, IFNULL(cl.score_semantics,'') AS semantics, " + ...
        "cl.source_caller_label AS label FROM imported_attribution_claims cl " + ...
        "JOIN attribution_window_correspondences wc " + ...
        "ON wc.imported_attribution_window_id = cl.imported_attribution_window_id " + ...
        "WHERE wc.attribution_target_id=" + string(target) + " ORDER BY cl.entity_id");
    if height(claims) == 0
        continue
    end
    rows = struct([]);
    for index = 1:height(claims)
        row = struct(entity_id=double(claims.entity_id(index)), ...
            source_label=string(claims.label(index)));
        if double(claims.score(index)) ~= -999.0
            row.score = double(claims.score(index));
            row.score_semantics = string(claims.semantics(index));
        end
        rows = [rows, row]; %#ok<AGROW>
    end
    if all(arrayfun(@(r) isfield(r, "score"), rows))
        candidates = struct2table(rows(:));
    else
        candidates = table([rows.entity_id]', [rows.source_label]', ...
            VariableNames=["entity_id", "source_label"]);
    end
    vawlume.attribution.addCandidates(fixture.conn, ...
        struct(attribution_target_id=target), candidates, Apply=true);
    written = written + height(candidates);
end
end

function row = localizationRow(estimateId)
row = struct(evidence_dimension="source_localization", ...
    evidence_kind="backend_source_location", ...
    attribution_localization_estimate_id=estimateId, coordinate_system_key="arena_floor");
end

function value = runRef(fixture)
value = struct(attribution_run_id=fixture.run_id);
end

function value = countOf(fixture, tableName)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function spec = runSpec(fixture, runKey, path)
spec = struct(run_key=runKey, attribution_path=path, ...
    method="Example Localization Backend", ...
    settings_profile_version_id=fixture.settings_version_id, ...
    target_set=struct(detection_ids=1:5), participating_entity_ids=[1 2], ...
    sources=struct(source_file_ids=1));
end

function id = createBackendRun(fixture, runKey)
created = vawlume.attribution.createRun(fixture.conn, struct(recording_id=1), ...
    runSpec(fixture, runKey, "backend"), Apply=true);
id = created.run.attribution_run_id;
end

function path = writeSource(fixture, rows)
path = fullfile(fixture.workspace, "export_" + string(java.util.UUID.randomUUID) + ".csv");
fileId = fopen(path, "w");
fprintf(fileId, "segment_id,start_s,end_s,candidate,assignment_score,source_x,source_y\n");
fprintf(fileId, "%s\n", rows);
fclose(fileId);
end

function path = variantProfile(fixture, mutate)
document = jsondecode(fileread(fixture.profile_path));
entry = mutate(document.profiles);
entry.profile.id = "test.backend.path." + strrep(string(java.util.UUID.randomUUID), "-", "");
document.profiles = entry;
path = fullfile(fixture.workspace, "profile_" + string(java.util.UUID.randomUUID) + ".json");
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document, PrettyPrint=true));
fclose(fileId);
end

function entry = withStrictRule(entry)
entry.correspondence.min_temporal_iou = 0.9;
end

function entry = claimAttachedMinimal(entry)
% A backend whose every position belongs to the caller on its row, reporting no
% channels, tracks or native fields.
entry.localization.attachment = "claim";
entry.localization = rmfield(entry.localization, "confidence");
entry.value_semantics = rmfield(entry.value_semantics, "confidence");
entry.columns = rmfield(entry.columns, "native_track_id");
entry = rmfield(entry, ["channel_evidence", "native_attributes"]);
end

function [fixture, cleanup] = setUpFixture()
root = repositoryRoot();
sourcePath = fullfile(root, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_backend_path_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
conn = sqlite(char(fullfile(workspace, "path.sqlite")), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(root, "schema", "schema.sql"));
seedFixture(conn);

settingsPath = fullfile(workspace, "settings.json");
fileId = fopen(settingsPath, "w");
fprintf(fileId, "{""note"": ""synthetic""}");
fclose(fileId);
settings = vawlume.db.registerProfileVersion(conn, struct(project_id=1), struct( ...
    profile_key="backend-settings", profile_name="Backend run settings", ...
    version_label="1.0.0", content_path=settingsPath));

fixture = struct(conn=conn, workspace=string(workspace), ...
    settings_version_id=settings.profile_version_id, alignment_run_id=1, ...
    profile_path=string(fullfile(root, "config", "01_mapping_profiles", ...
    "attribution", "generic_backend_attribution_profile.json")));
% The main fixture profile is shared with the variant helpers, so it is written
% into the fixture after the struct exists.
fixture.profile_path = variantProfile(fixture, @claimAttachedMinimal);

fixture.run_id = createBackendRun(fixture, "backend-path");
% One call per event:
%   s1 assigned, s2 simultaneous, s3 ambiguous with two localized sources,
%   s4 unassigned, s5 excluded (the backend named a caller and gave no score).
source = writeSource(fixture, [
    "s1,1.0,1.5,A,0.95,10,20"
    "s1,1.0,1.5,B,0.10,40,25"
    "s2,2.0,2.5,A,0.85,10,20"
    "s2,2.0,2.5,B,0.80,40,25"
    "s3,3.0,3.5,A,0.60,10,20"
    "s3,3.0,3.5,B,0.55,40,25"
    "s4,4.0,4.5,A,0.30,10,20"
    "s4,4.0,4.5,B,0.20,40,25"
    "s5,5.0,5.5,A,,10,20"]);
vawlume.ingest.backendAttribution(conn, runRef(fixture), source, Apply=true, ...
    ProfilePath=fixture.profile_path);

targets = fetch(conn, "SELECT attribution_target_id AS id FROM attribution_targets " + ...
    "WHERE attribution_run_id=" + string(fixture.run_id) + " ORDER BY detection_id");
fixture.targets = double(targets.id)';
estimates = fetch(conn, "SELECT MIN(le.attribution_localization_estimate_id) AS id " + ...
    "FROM attribution_localization_estimates le JOIN imported_attribution_windows w " + ...
    "ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "WHERE w.attribution_run_id=" + string(fixture.run_id) + ...
    " GROUP BY w.native_window_id ORDER BY w.native_window_id");
fixture.estimates = double(estimates.id)';
end

function tearDown(conn, workspace, sourcePath, addedPath)
try, close(conn); catch, end %#ok<NOCOM>
if isfolder(workspace), rmdir(workspace, "s"); end
if addedPath && contains(path, sourcePath)
    rmpath(sourcePath);
end
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p1','Project 1')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','audio.wav','audio.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) VALUES" + ...
    "(1,1,'arena_floor','Arena floor',2,'cm')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
% Entity 3 exists but is not a participant.
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B'),(3,1,1,'C')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id," + ...
    "recording_id,entity_id,link_type) VALUES(1,1,1,'participant'),(2,1,2,'participant')");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'ds','DeepSqueak')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key) VALUES(1,1,1,'e1')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id," + ...
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5),(2,1,1,2.0,2.5)," + ...
    "(3,1,1,3.0,3.5),(4,1,1,4.0,4.5),(5,1,1,5.0,5.5)");
% A fitted affine transform from the backend's clock to the recording's,
% t_recording = 1.0 * t_backend + 5.0, anchored over [-9, 20] on the backend clock.
execute(conn, "INSERT INTO timebases(timebase_id,project_id,recording_id," + ...
    "timebase_name,timebase_kind,is_recording_native,native_unit) VALUES" + ...
    "(1,1,1,'audio_native','recording_clock',1,'s')," + ...
    "(2,1,1,'backend_native','external_device_clock',0,'s')");
execute(conn, "INSERT INTO analysis_runs(analysis_run_id,project_id,run_type,run_key) " + ...
    "VALUES(90,1,'temporal_alignment','align-1')");
execute(conn, "INSERT INTO alignment_sets(alignment_set_id,analysis_run_id,recording_id," + ...
    "alignment_set_key,reference_timebase_id) VALUES(1,90,1,'set1',1)");
execute(conn, "INSERT INTO time_alignment_runs(alignment_run_id,alignment_set_id," + ...
    "source_timebase_id,target_timebase_id,method,status,n_anchors_used) " + ...
    "VALUES(1,1,2,1,'affine','estimated',2)");
execute(conn, "INSERT INTO alignment_segments(alignment_run_id,segment_index," + ...
    "source_start,source_end,scale,offset_s) VALUES(1,1,NULL,NULL,1.0,5.0)");
execute(conn, "INSERT INTO alignment_anchors(alignment_anchor_id,alignment_set_id," + ...
    "anchor_key,anchor_type) VALUES(1,1,'a1','ttl_edge'),(2,1,'a2','ttl_edge')");
execute(conn, "INSERT INTO alignment_anchor_observations(alignment_anchor_id," + ...
    "timebase_id,observed_time_native,observation_role,included_in_fit) VALUES" + ...
    "(1,2,-9.0,'primary',1),(2,2,20.0,'primary',1),(1,1,-4.0,'primary',1),(2,1,25.0,'primary',1)");
execute(conn, "INSERT INTO alignment_anchor_residuals(alignment_run_id," + ...
    "alignment_anchor_id,source_observation_id,reference_observation_id," + ...
    "observed_source_time,observed_reference_time,predicted_reference_time," + ...
    "residual_s,included_in_fit) VALUES" + ...
    "(1,1,1,3,-9.0,-4.0,-4.0,0.0,1),(1,2,2,4,20.0,25.0,25.0,0.0,1)");
end

function root = repositoryRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
