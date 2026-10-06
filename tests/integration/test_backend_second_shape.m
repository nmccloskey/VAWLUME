function tests = test_backend_second_shape
%TEST_BACKEND_SECOND_SHAPE Does the backend adapter generalize, or fit its first backend?
%
% Two structurally different synthetic backends, mapped through the same
% profile kind, the same mapper, the same intake and the same read surface, in
% one database over one recording:
%
%   shape 1  generic_backend_attribution_profile        shape 2  generic_array_backend_attribution_profile
%   2D, cm, frame in context                                     3D, mm, frame named per row
%   caller scores + one estimate per window                      no callers; several ranked sources per window
%   scalar localization confidence                               covariance terms, no scalar confidence
%   per-channel levels in wide columns                           per-channel levels as long rows
%   backend's own segment ids                                    re-used VAWLUME event ids, with times
%
% Neither shape is a real backend's format. Both were written by this
% repository. What this suite can show is that the representation does not
% depend on either; it cannot show that any real export maps.
tests = functiontests(localfunctions);
end

% --- shape 2, end to end ------------------------------------------------------

function testTheSecondShapeImportsThroughTheSameIntake(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = importArray(fixture);
verifyEqual(testCase, result.status, "imported");
verifyEqual(testCase, result.applied_counts.imported_attribution_windows, 2);
verifyEqual(testCase, result.applied_counts.imported_attribution_claims, 0);
verifyEqual(testCase, result.applied_counts.attribution_localization_estimates, 3);
verifyEmpty(testCase, result.issues);
clear cleanup
end

function testSeveralRankedSourcesAreKeptAndNoneIsPreferred(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importArray(fixture);
rows = fetch(fixture.conn, "SELECT le.native_estimate_id AS id, le.estimate_ordinal AS rank, " + ...
    "le.position_z AS z FROM attribution_localization_estimates le " + ...
    "JOIN imported_attribution_windows w ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "WHERE w.attribution_run_id=" + string(fixture.array_run) + " AND w.native_window_id='2' " + ...
    "ORDER BY le.estimate_ordinal");
verifyEqual(testCase, string(rows.id)', ["src-a" "src-b"]);
verifyEqual(testCase, double(rows.rank)', [1 2], "The producer's own ranks, as declared.");
verifyEqual(testCase, double(rows.z)', [15 12]);
clear cleanup
end

function testCovarianceIsPreservedAndNoScalarConfidenceIsInvented(testCase)
% The case the 5.1 contract named as most likely to have nowhere to go (D15).
% It goes to native attributes, term by term, and nothing derives a confidence.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importArray(fixture);
estimates = fetch(fixture.conn, "SELECT typeof(le.confidence) AS t FROM " + ...
    "attribution_localization_estimates le JOIN imported_attribution_windows w " + ...
    "ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "WHERE w.attribution_run_id=" + string(fixture.array_run));
verifyEqual(testCase, unique(string(estimates.t)), "null");
terms = fetch(fixture.conn, "SELECT a.attribute_name AS name, a.value_real AS value, a.unit " + ...
    "FROM attribution_native_attributes a JOIN attribution_localization_estimates le " + ...
    "ON le.attribution_localization_estimate_id = a.attribution_localization_estimate_id " + ...
    "WHERE le.native_estimate_id='src-a' ORDER BY a.attribute_name");
verifyEqual(testCase, string(terms.name)', ["position_covariance_xy" "position_variance_x" ...
    "position_variance_y" "position_variance_z"]);
verifyEqual(testCase, double(terms.value)', [0.5 4.0 4.5 9.0]);
verifyEqual(testCase, unique(string(terms.unit)), "mm^2");
clear cleanup
end

function testLongFormChannelLevelsLandOnTheirWindow(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importArray(fixture);
rows = fetch(fixture.conn, "SELECT a.attribute_name AS name, a.value_real AS value " + ...
    "FROM attribution_native_attributes a JOIN imported_attribution_windows w " + ...
    "ON w.imported_attribution_window_id = a.imported_attribution_window_id " + ...
    "WHERE w.attribution_run_id=" + string(fixture.array_run) + " AND w.native_window_id='2' " + ...
    "AND a.value_type='real' ORDER BY a.attribute_name");
verifyEqual(testCase, string(rows.name)', ["channel:1:array_channel_level" ...
    "channel:3:array_channel_level"]);
verifyEqual(testCase, double(rows.value)', [-41.5 -47]);
clear cleanup
end

function testAnEchoedEventIdIsNotAKey(testCase)
% The window re-uses event id "2" but reports the times of detection 1.
% Correspondence relates it to detection 1; the id decides nothing.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importArray(fixture);
vawlume.attribution.correspondWindows(fixture.conn, struct(attribution_run_id=fixture.array_run), ...
    SameClock=true, Apply=true);
rows = fetch(fixture.conn, "SELECT w.native_window_id AS window, t.detection_id AS event " + ...
    "FROM attribution_window_correspondences c " + ...
    "JOIN imported_attribution_windows w ON w.imported_attribution_window_id = c.imported_attribution_window_id " + ...
    "JOIN attribution_targets t ON t.attribution_target_id = c.attribution_target_id " + ...
    "WHERE w.attribution_run_id=" + string(fixture.array_run) + " ORDER BY w.native_window_id");
verifyEqual(testCase, string(rows.window)', ["1" "2"]);
verifyEqual(testCase, double(rows.event)', [2 1]);
clear cleanup
end

function testAPerRowFrameIsResolvedAndAFlatFrameUnderAHeightIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
source = writeArraySource(fixture, ...
    "1,2.0,2.5,s1,1,arena_floor,10,20,5,,,,,,");
verifyError(testCase, @() vawlume.ingest.backendAttribution(fixture.conn, ...
    struct(attribution_run_id=fixture.array_run), source, ...
    ProfilePath=fixture.array_profile, Apply=true), ...
    "vawlume:attribution:LocalizationDimensionMismatch");
verifyEqual(testCase, countOf(fixture, "imported_attribution_windows"), 0);
clear cleanup
end

function testAThreeDimensionalEstimateIsPromotedInItsOwnFrame(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importArray(fixture);
vawlume.attribution.correspondWindows(fixture.conn, struct(attribution_run_id=fixture.array_run), ...
    SameClock=true, Apply=true);
estimate = fetch(fixture.conn, "SELECT attribution_localization_estimate_id AS id " + ...
    "FROM attribution_localization_estimates WHERE native_estimate_id='src-a'");
target = targetFor(fixture, fixture.array_run, 1);
row = struct(evidence_dimension="source_localization", evidence_kind="array_source_location", ...
    attribution_localization_estimate_id=double(estimate.id(1)), ...
    coordinate_system_key="arena_volume");
result = vawlume.attribution.addEvidence(fixture.conn, struct(attribution_target_id=target), ...
    row, Apply=true);
verifyEqual(testCase, result.applied_count, 1);
row.coordinate_system_key = "arena_floor";
verifyError(testCase, @() vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_target_id=target), row, Apply=true), ...
    "vawlume:geometry:CoordinateSystemMismatch");
clear cleanup
end

% --- both backends, one database ------------------------------------------------

function testBothBackendsCoexistWithSeparateProvenance(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importFirst(fixture);
importArray(fixture);
provenance = fetch(fixture.conn, "SELECT w.attribution_run_id AS run, " + ...
    "COUNT(DISTINCT w.mapping_profile_version_id) AS versions, " + ...
    "MIN(p.profile_key) AS profile, MIN(v.checksum_sha256) AS checksum, " + ...
    "COUNT(DISTINCT w.source_file_id) AS files " + ...
    "FROM imported_attribution_windows w " + ...
    "JOIN config_profile_versions v ON v.profile_version_id = w.mapping_profile_version_id " + ...
    "JOIN config_profiles p ON p.profile_id = v.profile_id " + ...
    "GROUP BY w.attribution_run_id ORDER BY w.attribution_run_id");
verifyEqual(testCase, double(provenance.versions)', [1 1]);
verifyEqual(testCase, string(provenance.profile)', ["vawlume.attribution.generic_backend.v0_1" ...
    "vawlume.attribution.generic_array_backend.v0_1"]);
verifyNotEqual(testCase, string(provenance.checksum(1)), string(provenance.checksum(2)));
% No row of either run reaches the other run's windows.
crossed = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_localization_estimates le " + ...
    "JOIN imported_attribution_windows w ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "JOIN imported_attribution_claims c ON c.imported_attribution_claim_id = le.imported_attribution_claim_id " + ...
    "WHERE c.imported_attribution_window_id <> le.imported_attribution_window_id");
verifyEqual(testCase, double(crossed.n(1)), 0);
counts = fetch(fixture.conn, "SELECT w.attribution_run_id AS run, COUNT(*) AS n " + ...
    "FROM attribution_localization_estimates le JOIN imported_attribution_windows w " + ...
    "ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "GROUP BY w.attribution_run_id ORDER BY w.attribution_run_id");
verifyEqual(testCase, double(counts.n)', [2 3]);
clear cleanup
end

function testTheReadSurfaceIsTheSameForBothBackends(testCase)
% No per-backend branch: the same fields, the same table columns, the same QC
% fields, for two runs whose content differs in every axis above.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importFirst(fixture);
importArray(fixture);
first = vawlume.attribution.report(fixture.conn, struct(attribution_run_id=fixture.first_run));
second = vawlume.attribution.report(fixture.conn, struct(attribution_run_id=fixture.array_run));
verifyEqual(testCase, sort(string(fieldnames(second))), sort(string(fieldnames(first))));
verifyEqual(testCase, sort(string(fieldnames(second.qc))), sort(string(fieldnames(first.qc))));
for name = string(fieldnames(first))'
    if istable(first.(name))
        verifyEqual(testCase, string(second.(name).Properties.VariableNames), ...
            string(first.(name).Properties.VariableNames), name + " differs between backends");
    end
end
% And the content is each run's own: 2D without height, 3D with it.
verifyTrue(testCase, all(isnan(first.localization_estimates.position_z)));
verifyFalse(testCase, any(isnan(second.localization_estimates.position_z)));
verifyEqual(testCase, unique(string(first.localization_estimates.coordinate_system_key)), "arena_floor");
verifyEqual(testCase, unique(string(second.localization_estimates.coordinate_system_key)), "arena_volume");
clear cleanup
end

function testDecideWorksOverBothUnderOnePolicy(testCase)
% Shape 1 supplies caller scores; shape 2 supplies none, so its candidates are
% the run's participants named without a number and the same policy reports it
% could not be applied. Neither run's result is compared with the other's.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
importFirst(fixture);
importArray(fixture);
for run = [fixture.first_run fixture.array_run]
    vawlume.attribution.correspondWindows(fixture.conn, struct(attribution_run_id=run), ...
        SameClock=true, Apply=true);
end
for detection = [1 2]
    claims = fetch(fixture.conn, "SELECT cl.entity_id AS entity_id, cl.score AS score, " + ...
        "cl.score_semantics AS score_semantics FROM imported_attribution_claims cl " + ...
        "JOIN attribution_window_correspondences wc " + ...
        "ON wc.imported_attribution_window_id = cl.imported_attribution_window_id " + ...
        "WHERE wc.attribution_target_id=" + string(targetFor(fixture, fixture.first_run, detection)) + ...
        " AND cl.score IS NOT NULL");
    claims.score_semantics = string(claims.score_semantics);
    vawlume.attribution.addCandidates(fixture.conn, ...
        struct(attribution_target_id=targetFor(fixture, fixture.first_run, detection)), ...
        claims, Apply=true);
    vawlume.attribution.addCandidates(fixture.conn, ...
        struct(attribution_target_id=targetFor(fixture, fixture.array_run, detection)), ...
        table([1; 2], VariableNames="entity_id"), Apply=true);
end
vawlume.attribution.decide(fixture.conn, struct(attribution_run_id=fixture.first_run), Apply=true);
vawlume.attribution.decide(fixture.conn, struct(attribution_run_id=fixture.array_run), Apply=true);
decisions = fetch(fixture.conn, "SELECT t.attribution_run_id AS run, d.decision_status AS status, " + ...
    "d.policy_profile_version_id AS policy FROM attribution_decisions d " + ...
    "JOIN attribution_targets t ON t.attribution_target_id = d.attribution_target_id " + ...
    "ORDER BY t.attribution_run_id, t.detection_id");
verifyEqual(testCase, numel(unique(double(decisions.policy))), 1);
verifyEqual(testCase, string(decisions.status(double(decisions.run) == fixture.array_run))', ...
    ["excluded" "excluded"]);
verifyTrue(testCase, all(ismember(string(decisions.status(double(decisions.run) == fixture.first_run)), ...
    ["assigned", "simultaneous", "ambiguous", "unassigned"])));
clear cleanup
end

% --- what the profile language deliberately does not express ----------------------

function testAWideCallerBlockIsNotInterpreted(testCase)
% One row per window with a column per candidate is a different shape. Like the
% imported profile, the backend profile language has no grammar for it; a block
% attempting one is reported as unknown and is never silently interpreted.
document = jsondecode(fileread(firstProfilePath()));
entry = document.profiles;
entry.wide_callers = struct(columns=["score_A"; "score_B"]);
report = vawlume.source_mapping.validateProfile(entry, ExpectedKind="attribution_backend_mapping");
codes = string(report.issue_table.code);
verifyTrue(testCase, any(codes == "PROFILE_UNKNOWN_TOP_LEVEL_KEY"));
end

% --- tripwire 2: no backend product named anywhere in code --------------------------

function testNoColumnVocabularyOrFunctionNamesABackendProduct(testCase)
% Searched in CODE: SQL comments and MATLAB comments are stripped first, because
% prose explaining that VAWLUME is not shaped for a product would otherwise match.
% Every identifier, string literal, CHECK vocabulary member and file name counts.
root = repositoryRoot();
products = ["usvcam", "avisoft", "vocalmat", "sonotrack", "noldus", "ethovision", ...
    "ultravox", "batsound", "deepsonar"];
hits = strings(0, 1);
sql = splitlines(string(fileread(fullfile(root, "schema", "schema.sql"))));
sql = lower(strjoin(regexprep(sql, "--.*$", ""), newline));
for product = products
    if contains(sql, product)
        hits(end+1, 1) = "schema/schema.sql: " + product; %#ok<AGROW>
    end
end
files = dir(fullfile(root, "src", "**", "*.m"));
for index = 1:numel(files)
    lines = splitlines(string(fileread(fullfile(files(index).folder, files(index).name))));
    code = lower(strjoin(regexprep(lines, "%.*$", ""), newline) + " " + files(index).name);
    for product = products
        if contains(code, product)
            hits(end+1, 1) = string(files(index).name) + ": " + product; %#ok<AGROW>
        end
    end
end
configFiles = dir(fullfile(root, "config", "**", "*.json"));
for index = 1:numel(configFiles)
    name = lower(string(configFiles(index).name));
    for product = products
        if contains(name, product)
            hits(end+1, 1) = "config file name: " + configFiles(index).name; %#ok<AGROW>
        end
    end
end
verifyEmpty(testCase, hits, strjoin(hits, newline));
end

% ---------------------------------------------------------------- helpers ---

function result = importArray(fixture)
source = writeArraySource(fixture, [
    "2,1.0,1.5,src-a,1,arena_volume,120.5,80.25,15,4.0,4.5,9.0,0.5,,"
    "2,1.0,1.5,src-b,2,arena_volume,300,95,12,16,16,25,-1.25,,"
    "2,1.0,1.5,,,,,,,,,,,1,-41.5"
    "2,1.0,1.5,,,,,,,,,,,3,-47"
    "1,2.0,2.5,src-c,1,arena_volume,200,60,10,9,9,16,0,,"
    "1,2.0,2.5,,,,,,,,,,,2,-44"]);
result = vawlume.ingest.backendAttribution(fixture.conn, ...
    struct(attribution_run_id=fixture.array_run), source, ...
    ProfilePath=fixture.array_profile, Apply=true);
end

function result = importFirst(fixture)
path = fullfile(fixture.workspace, "first_" + string(java.util.UUID.randomUUID) + ".csv");
writeText(path, "segment_id,start_s,end_s,candidate,assignment_score,track,source_x," + ...
    "source_y,localization_confidence,mic1_power,mic2_power,err_major" + newline + ...
    "s1,1.0,1.5,A,0.95,t1,10,20,0.9,-41,-45,3.5" + newline + ...
    "s1,1.0,1.5,B,0.10,,10,20,0.9,-41,-45,3.5" + newline + ...
    "s2,2.0,2.5,A,0.60,,30,5,0.4,,," + newline + ...
    "s2,2.0,2.5,B,0.55,,30,5,0.4,,," + newline);
result = vawlume.ingest.backendAttribution(fixture.conn, ...
    struct(attribution_run_id=fixture.first_run), path, Apply=true);
end

function path = writeArraySource(fixture, rows)
path = fullfile(fixture.workspace, "array_" + string(java.util.UUID.randomUUID) + ".csv");
writeText(path, "event_ref,t_on,t_off,source_id,source_rank,frame,x_mm,y_mm,z_mm," + ...
    "var_x,var_y,var_z,cov_xy,mic,level_db" + newline + strjoin(rows, newline) + newline);
end

function id = targetFor(fixture, run, detection)
rows = fetch(fixture.conn, "SELECT attribution_target_id AS id FROM attribution_targets " + ...
    "WHERE attribution_run_id=" + string(run) + " AND detection_id=" + string(detection));
id = double(rows.id(1));
end

function value = countOf(fixture, tableName)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function path = firstProfilePath()
path = fullfile(repositoryRoot(), "config", "01_mapping_profiles", "attribution", ...
    "generic_backend_attribution_profile.json");
end

function writeText(path, text)
fileId = fopen(path, "w");
fprintf(fileId, "%s", text);
fclose(fileId);
end

function [fixture, cleanup] = setUpFixture()
root = repositoryRoot();
sourcePath = fullfile(root, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_second_shape_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
conn = sqlite(char(fullfile(workspace, "shapes.sqlite")), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(root, "schema", "schema.sql"));
seedFixture(conn);
settingsPath = fullfile(workspace, "settings.json");
writeText(settingsPath, "{""note"": ""synthetic""}");
settings = vawlume.db.registerProfileVersion(conn, struct(project_id=1), struct( ...
    profile_key="backend-settings", profile_name="Backend run settings", ...
    version_label="1.0.0", content_path=settingsPath));
runs = zeros(1, 2);
keys = ["first-shape", "array-shape"];
for index = 1:2
    created = vawlume.attribution.createRun(conn, struct(recording_id=1), struct( ...
        run_key=keys(index), attribution_path="backend", method="synthetic backend " + index, ...
        settings_profile_version_id=settings.profile_version_id, ...
        target_set=struct(detection_ids=[1 2]), participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1)), Apply=true);
    runs(index) = created.run.attribution_run_id;
end
fixture = struct(conn=conn, workspace=string(workspace), first_run=runs(1), ...
    array_run=runs(2), array_profile=string(fullfile(root, "config", ...
    "01_mapping_profiles", "attribution", "generic_array_backend_attribution_profile.json")));
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
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index) VALUES(1,1,1),(2,1,2),(3,1,3),(4,1,4)");
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) VALUES" + ...
    "(1,1,'arena_floor','Arena floor',2,'cm'),(2,1,'arena_volume','Arena volume',3,'mm')");
execute(conn, "INSERT INTO entity_types(entity_type_id,project_id,native_name," + ...
    "is_subject_like) VALUES(1,1,'subject',1)");
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(1,1,1,'A'),(2,1,1,'B')");
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
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5),(2,1,1,2.0,2.5)");
execute(conn, "INSERT INTO timebases(timebase_id,project_id,recording_id,timebase_name," + ...
    "timebase_kind,native_unit) VALUES(1,1,1,'video_clock','video_frames','s')");
execute(conn, "INSERT INTO external_streams(external_stream_id,project_id,recording_id," + ...
    "timebase_id,stream_name,stream_kind) VALUES(1,1,1,1,'overhead_pose','tracking')");
execute(conn, "INSERT INTO tracking_streams(external_stream_id,coordinate_system_id," + ...
    "native_time_basis) VALUES(1,1,'time')");
execute(conn, "INSERT INTO tracking_identity_associations(external_stream_id," + ...
    "native_track_id,entity_id,start_time_native,end_time_native,assignment_state," + ...
    "evidence_kind) VALUES(1,'t1',1,0,100,'assigned','manual_review')");
end

function root = repositoryRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
