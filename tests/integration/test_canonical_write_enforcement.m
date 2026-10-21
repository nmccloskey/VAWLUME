function tests = test_canonical_write_enforcement
%TEST_CANONICAL_WRITE_ENFORCEMENT Itinerary 7.4: the canonical writers enforce invariants 24 and 26.
%
% Contract 07 D9 and D10. Whoever the writer is:
%   - a native_estimate candidate carries no probability
%     (vawlume:attribution:NativeProbabilityRefused);
%   - a native pose or identity row cites a tracking identity association
%     (vawlume:attribution:NativeIdentityCitationRequired);
% each refused by name before any write, with the 7.2 schema triggers still the
% last line of defence when the API is bypassed. Imported and backend rows are
% accepted exactly as before. Every no-score reason is stored in order, and
% attribution_run_declared_inputs has one writer (P6-1).
%
% Each probe reaches its rule for its own reason: the entity has no candidate on
% the target, and the logged identifier shows which rule refused. Re-run
% verbatim as the 7.18 closure probe.
tests = functiontests(localfunctions);
end

function setup(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
file = string(tempname) + ".sqlite";
conn = sqlite(char(file), "create");
vawlume.db.applySchema(conn, fullfile(root, "schema", "schema.sql"));
seed(conn);
settings = vawlume.estimator.loadSettings(RepoRoot=root);
registered = vawlume.db.registerProfileVersion(conn, struct(project_id=1), struct( ...
    profile_key=settings.profile_key, profile_name=settings.profile_name, ...
    version_label=settings.version_label, content_path=settings.path, ...
    profile_kind=settings.profile_kind, ...
    profile_schema_version=settings.profile_schema_version), RepoRoot=root);
testCase.TestData = struct(root=root, conn=conn, file=file, settings=settings, ...
    estimator_version=registered.profile_version_id);
end

function teardown(testCase)
close(testCase.TestData.conn);
if isfile(testCase.TestData.file)
    delete(testCase.TestData.file);
end
rmpath(fullfile(testCase.TestData.root, "src"));
end

% ============================================================ invariant 24 ===

function testANativeProbabilityIsRefusedByNameBeforeAnyWrite(testCase)
t = testCase.TestData;
target = runTarget(t, "native_estimate");
verifyEqual(testCase, countOf(t.conn, "attribution_candidates"), 0, ...
    "The probe's entity has no candidate on the target: no conflict can intervene.");
probes = {
    struct(entity_id=1, score=-1, score_semantics="dB; not a probability", ...
        probability=0.5, probability_semantics="posterior")
    struct(entity_id=1, probability=0.5, probability_semantics="posterior")
    struct(entity_id=1, probability_semantics="posterior")};
for k = 1:numel(probes)
    for apply = [false, true]
        identifier = probeIdentifier(@() vawlume.attribution.addCandidates(t.conn, ...
            target, probes{k}, Apply=apply));
        log(testCase, 1, sprintf("native probability probe %d (Apply=%d): %s", ...
            k, apply, identifier));
        verifyEqual(testCase, identifier, "vawlume:attribution:NativeProbabilityRefused");
    end
end
verifyEqual(testCase, countOf(t.conn, "attribution_candidates"), 0, "Nothing was written.");
end

function testTheProbabilityTriggerIsStillTheLastLineOfDefence(testCase)
t = testCase.TestData;
target = runTarget(t, "native_estimate");
message = sqlFailure(t.conn, "INSERT INTO attribution_candidates(attribution_target_id," + ...
    "entity_id,candidate_status,probability,probability_semantics) VALUES(" + ...
    string(target.attribution_target_id) + ",1,'candidate',0.5,'posterior')");
log(testCase, 1, "direct insert: " + message);
verifyTrue(testCase, contains(message, "A native_estimate candidate carries no probability"));
vawlume.attribution.addCandidates(t.conn, target, ...
    struct(entity_id=2, score=-1, score_semantics="dB; not a probability"), Apply=true);
message = sqlFailure(t.conn, "UPDATE attribution_candidates SET probability=0.5, " + ...
    "probability_semantics='posterior' WHERE entity_id=2");
log(testCase, 1, "direct update: " + message);
verifyTrue(testCase, contains(message, "A native_estimate candidate carries no probability"));
end

function testAnImportedOrBackendProbabilityIsAcceptedAsBefore(testCase)
t = testCase.TestData;
for path = ["imported", "backend"]
    target = runTarget(t, path);
    result = vawlume.attribution.addCandidates(t.conn, target, ...
        struct(entity_id=1, score=0.8, score_semantics="exporter score", ...
        probability=0.7, probability_semantics="exporter posterior"), Apply=true);
    verifyEqual(testCase, result.status, "created", path);
    stored = fetch(t.conn, "SELECT probability, probability_semantics FROM " + ...
        "attribution_candidates WHERE attribution_target_id=" + ...
        string(target.attribution_target_id));
    verifyEqual(testCase, double(stored.probability), 0.7, path);
    verifyEqual(testCase, string(stored.probability_semantics), "exporter posterior", path);
end
end

% ============================================================ invariant 26 ===

function testANativeLabelOnlyPoseRowIsRefusedByNameBeforeAnyWrite(testCase)
t = testCase.TestData;
target = runTarget(t, "native_estimate");
candidate = vawlume.attribution.addCandidates(t.conn, target, ...
    struct(entity_id=1), Apply=true).candidates;
candidateRef = struct(attribution_candidate_id=candidate.attribution_candidate_id(1));
% The bogus external_event_id shows the path rule is reached before any
% source check would look the event up.
probes = {
    candidateRef, labelOnlyPoseRow()
    target, labelOnlyPoseRow()
    candidateRef, struct(evidence_dimension="visual_identity", ...
        evidence_kind="declared_label", value_text="A", value_units="category", ...
        value_semantics="user-declared label; producer=test", ...
        identity_statement_kind="declared_entity_link", external_event_id=999)};
for k = 1:size(probes, 1)
    for apply = [false, true]
        identifier = probeIdentifier(@() vawlume.attribution.addEvidence(t.conn, ...
            probes{k, 1}, probes{k, 2}, Apply=apply));
        log(testCase, 1, sprintf("native citation probe %d (Apply=%d): %s", ...
            k, apply, identifier));
        verifyEqual(testCase, identifier, ...
            "vawlume:attribution:NativeIdentityCitationRequired");
    end
end
verifyEqual(testCase, countOf(t.conn, "attribution_evidence"), 0, "Nothing was written.");
% Every other dimension is unaffected on a native run.
verifyEqual(testCase, vawlume.attribution.addEvidence(t.conn, target, ...
    plainEvidence(), Apply=true).status, "created");
end

function testTheCitationTriggerIsStillTheLastLineOfDefence(testCase)
t = testCase.TestData;
target = runTarget(t, "native_estimate");
message = sqlFailure(t.conn, "INSERT INTO attribution_evidence(attribution_target_id," + ...
    "evidence_dimension,evidence_kind,value_real,value_units,value_semantics," + ...
    "source_locator) VALUES(" + string(target.attribution_target_id) + ...
    ",'pose_localization','keypoint_confidence',0.73,'upstream_score','x'," + ...
    "'tracking.csv#time=10.0')");
log(testCase, 1, "direct insert: " + message);
verifyTrue(testCase, contains(message, ...
    "A native_estimate pose or identity evidence row must cite a tracking identity association"));
end

function testTheBackendDemonstrationsPoseRowIsAcceptedAsBefore(testCase)
% The backend demonstration's own label-only pose_localization row, on an
% imported and a backend candidate: accepted, exactly as before 7.4.
t = testCase.TestData;
for path = ["imported", "backend"]
    target = runTarget(t, path);
    candidate = vawlume.attribution.addCandidates(t.conn, target, ...
        struct(entity_id=1), Apply=true).candidates;
    result = vawlume.attribution.addEvidence(t.conn, ...
        struct(attribution_candidate_id=candidate.attribution_candidate_id(1)), ...
        labelOnlyPoseRow(), Apply=true);
    verifyEqual(testCase, result.status, "created", path);
    verifyEqual(testCase, result.applied_count, 1, path);
end
end

% ======================================================= no-score reasons ===

function testEveryNoScoreReasonIsStoredInTheProducersOrder(testCase)
t = testCase.TestData;
target = runTarget(t, "native_estimate");
batch = struct(entity_id={1; 2}, score={NaN; -0.5}, ...
    score_semantics={""; "dB; not a probability"}, ...
    no_score_reasons={["identity_changes_within_window", "alignment_extrapolated"]; ...
    strings(0, 1)});
result = vawlume.attribution.addCandidates(t.conn, target, batch, Apply=true);
verifyEqual(testCase, result.status, "created");
stored = fetch(t.conn, "SELECT c.entity_id, n.reason_ordinal, n.reason_code " + ...
    "FROM attribution_candidate_no_score_reasons n JOIN attribution_candidates c " + ...
    "ON c.attribution_candidate_id=n.attribution_candidate_id ORDER BY n.reason_ordinal");
verifyEqual(testCase, double(stored.entity_id), [1; 1]);
verifyEqual(testCase, double(stored.reason_ordinal), [1; 2]);
verifyEqual(testCase, string(stored.reason_code), ...
    ["identity_changes_within_window"; "alignment_extrapolated"], ...
    "Stored in the order given; nothing sorted.");

verifyEqual(testCase, vawlume.attribution.addCandidates(t.conn, target, batch, ...
    Apply=true).status, "reused", "Identical reasons reuse the candidate.");
reordered = batch;
reordered(1).no_score_reasons = flip(reordered(1).no_score_reasons);
verifyEqual(testCase, vawlume.attribution.addCandidates(t.conn, target, reordered, ...
    Apply=true).status, "conflict", "A different order is different content.");
verifyEqual(testCase, countOf(t.conn, "attribution_candidate_no_score_reasons"), 2);
end

function testAReasonOnAScoredCandidateOrARepeatedReasonIsRefused(testCase)
t = testCase.TestData;
target = runTarget(t, "native_estimate");
verifyError(testCase, @() vawlume.attribution.addCandidates(t.conn, target, ...
    struct(entity_id=1, score=-1, score_semantics="dB", ...
    no_score_reasons="track_not_covered"), Apply=true), ...
    "vawlume:attribution:CandidateSpecInvalid");
verifyError(testCase, @() vawlume.attribution.addCandidates(t.conn, target, ...
    struct(entity_id=1, no_score_reasons=["track_not_covered", "track_not_covered"]), ...
    Apply=true), "vawlume:attribution:CandidateSpecInvalid");
verifyEqual(testCase, countOf(t.conn, "attribution_candidates"), 0);
end

% ================================================ declared inputs (P6-1) ===

function testDeclaredInputsHaveOneWriter(testCase)
% Static: exactly one source file inserts into attribution_run_declared_inputs.
t = testCase.TestData;
files = dir(fullfile(t.root, "src", "**", "*.m"));
writers = strings(0, 1);
for k = 1:numel(files)
    text = string(fileread(fullfile(files(k).folder, files(k).name)));
    if contains(text, "InsertRow(conn, ""attribution_run_declared_inputs""") || ...
            contains(lower(text), "insert into attribution_run_declared_inputs")
        writers(end + 1, 1) = string(files(k).name); %#ok<AGROW>
    end
end
verifyEqual(testCase, writers, "declareInputs.m");
end

function testTheDeclaredInputWriterRefusesByName(testCase)
t = testCase.TestData;
imported = runOf(t, "imported");
verifyError(testCase, @() vawlume.attribution.declareInputs(t.conn, imported, ...
    t.settings.declared_inputs, DeclaredBy=1, Apply=true), ...
    "vawlume:attribution:DeclaredInputsNotAccepted");

backend = runOf(t, "backend");
two = table(["pose_localization"; "acoustic"], ["used"; "not_used"], ...
    VariableNames=["input_dimension", "declaration"]);
verifyError(testCase, @() vawlume.attribution.declareInputs(t.conn, backend, two, ...
    DeclaredBy=1, Apply=true), "vawlume:attribution:DeclaredInputsInvalid", ...
    "An input-mapping profile does not declare a backend run's inputs.");
verifyError(testCase, @() vawlume.attribution.declareInputs(t.conn, backend, ...
    two([1 1], :), DeclaredBy=2, Apply=true), "vawlume:attribution:DeclaredInputsInvalid");
planned = vawlume.attribution.declareInputs(t.conn, backend, two, DeclaredBy=2);
verifyEqual(testCase, [string(planned.status), countOf(t.conn, ...
    "attribution_run_declared_inputs")], ["planned", "0"], "Planning writes nothing.");
verifyEqual(testCase, vawlume.attribution.declareInputs(t.conn, backend, two, ...
    DeclaredBy=2, Apply=true).applied_count, 2);
verifyError(testCase, @() vawlume.attribution.declareInputs(t.conn, backend, two, ...
    DeclaredBy=2, Apply=true), "vawlume:attribution:DeclaredInputsInvalid", ...
    "Declarations are written once.");
stored = fetch(t.conn, "SELECT input_dimension, IFNULL(notes,'<NULL>') AS notes " + ...
    "FROM attribution_run_declared_inputs WHERE attribution_run_id=" + ...
    string(backend.attribution_run_id) + " ORDER BY input_dimension");
verifyEqual(testCase, string(stored.input_dimension), ["acoustic"; "pose_localization"]);
verifyEqual(testCase, string(stored.notes), ["<NULL>"; "<NULL>"], ...
    "A backend declaration states no notes: NULL, as before.");

native = runOf(t, "native_estimate");
verifyError(testCase, @() vawlume.attribution.declareInputs(t.conn, native, ...
    t.settings.declared_inputs, DeclaredBy=t.estimator_version, Apply=true), ...
    "vawlume:attribution:DeclaredInputsInvalid", ...
    "createRun already declared the native run's inputs through the same writer.");
verifyEqual(testCase, countOf(t.conn, "attribution_run_declared_inputs"), 6);
end

% --------------------------------------------------------------- helpers ---

function ref = runOf(t, path)
created = vawlume.attribution.createRun(t.conn, struct(recording_id=1), ...
    spec(t, path), Apply=true);
ref = struct(attribution_run_id=created.run.attribution_run_id);
end

function ref = runTarget(t, path)
created = vawlume.attribution.createRun(t.conn, struct(recording_id=1), ...
    spec(t, path), Apply=true);
ref = struct(attribution_target_id=created.targets.attribution_target_id(1));
end

function value = spec(t, path)
value = struct(run_key=path + "-run", attribution_path=path, method="External", ...
    settings_profile_version_id=1, target_set=struct(detection_ids=1), ...
    participating_entity_ids=[1 2], sources=struct(source_file_ids=2));
if path == "backend"
    value.settings_profile_version_id = 2;
elseif path == "native_estimate"
    value.method = "vawlume.estimator.level_difference_consistency 1.0.0";
    value.settings_profile_version_id = t.estimator_version;
    value.declared_inputs = t.settings.declared_inputs;
end
end

function row = labelOnlyPoseRow()
% The backend demonstration's pose row (examples/backend_localization_demo.m):
% a track named by a locator, no association.
row = struct(evidence_dimension="pose_localization", evidence_kind="keypoint_confidence", ...
    value_real=0.7300, value_units="upstream_score", ...
    value_semantics="Tracker-exported snout keypoint localization confidence; producer=Tracker X; uncalibrated; where a bodypart is, not where a sound came from", ...
    source_locator="tracking.csv#time=10.0");
end

function row = plainEvidence()
row = struct(evidence_dimension="acoustic", evidence_kind="level", value_real=0.5, ...
    value_units="dB", value_semantics="synthetic; producer=test", source_locator="row 1");
end

function identifier = probeIdentifier(action)
identifier = "<accepted>";
try
    action();
catch failure
    identifier = string(failure.identifier);
end
end

function message = sqlFailure(conn, statement)
message = "<accepted>";
try
    execute(conn, statement);
catch failure
    message = string(failure.message);
end
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function seed(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) VALUES(1,'p1','P')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role,path_or_uri,relative_path) VALUES" + ...
    "(1,1,'recording_audio','audio.wav','audio.wav'),(2,1,'attribution_output','c.csv','c.csv')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id,native_recording_id) " + ...
    "VALUES(1,1,1,'R1')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name,is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id,entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
execute(conn, "INSERT INTO recording_entity_links(recording_entity_link_id,recording_id,entity_id,link_type) " + ...
    "VALUES(1,1,1,'participant'),(2,1,2,'participant')");
execute(conn, "INSERT INTO config_profiles(profile_id,project_id,profile_key,profile_name,profile_kind) VALUES" + ...
    "(1,1,'imp','Imp','attribution_input_mapping'),(2,1,'bk','Bk','attribution_backend_mapping')");
execute(conn, "INSERT INTO config_profile_versions(profile_version_id,profile_id,version_label,content_format,content_uri,checksum_sha256,is_snapshot) VALUES" + ...
    "(1,1,'1','json','a.json','" + string(repmat('a', 1, 64)) + "',1),(2,2,'1','json','b.json','" + string(repmat('b', 1, 64)) + "',1)");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) VALUES(1,'ds','DS')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id,version_label) VALUES(1,1,'v1')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id,extractor_version_id,run_key) VALUES(1,1,1,'det')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id) VALUES(1,1)");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id,recording_id,start_time_s,end_time_s) " + ...
    "VALUES(1,1,1,1.0,1.1)");
end
