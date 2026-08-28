function tests = test_project_intake_recordings
tests = functiontests({ ...
    @testAllProfilesMaterializePortableRecordingContext, ...
    @testRootRelocationReusesSourceRecordingAndLinks, ...
    @testDuplicateFilenamesInDifferentFoldersStayDistinct});
end

function testAllProfilesMaterializePortableRecordingContext(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = projectProfilePath(repoRoot);
cases = {
    "example.project.mouse_courtship.folder_driven", ...
        fullfile("control", "mouse_001", "baseline", ...
        "001_baseline_1.wav"), 2
    "example.project.rat_self_admin.filename_driven", ...
        "OXY_PR_R03_SA07_001.wav", 2
    "example.project.social_dyad.multi_subject", ...
        fullfile("cohort_01", "dyad_004", ...
        "D004_M012_F031_courtship.wav"), 3
    };

for caseIndex = 1:size(cases, 1)
    root = temporaryRoot();
    cleanupRoot = onCleanup(@() removeTree(root));
    relativePath = replace(string(cases{caseIndex, 2}), string(filesep), "/");
    touchFile(fullfile(root, cases{caseIndex, 2}));
    [conn, dbFile] = createDisposableDatabase(repoRoot);
    cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
    ir = vawlume.source_mapping.parse(profilePath, root, ...
        ProfileId=cases{caseIndex, 1}, RepoRoot=repoRoot);
    spec = struct( ...
        project_key="recording_integration_" + string(caseIndex), ...
        project_name="Recording integration " + string(caseIndex), ...
        description="Pass 4 recording integration case.");

    result = vawlume.ingest.project(conn, ir, spec, Apply=true);

    expectedStatus = "completed";
    if cases{caseIndex, 1} == ...
            "example.project.rat_self_admin.filename_driven"
        expectedStatus = "completed_with_warnings";
    end
    verifyEqual(testCase, result.status, expectedStatus);
    verifyEqual(testCase, result.source_ids.source_file_id, ...
        result.plan.sources.existing_source_file_id);
    verifyEqual(testCase, result.recording_ids.recording_id, ...
        result.plan.recordings.existing_recording_id);
    source = fetch(conn, ...
        "SELECT path_or_uri, relative_path, filename FROM source_files");
    verifyEqual(testCase, string(source.path_or_uri), relativePath);
    verifyEqual(testCase, string(source.relative_path), relativePath);
    verifyEqual(testCase, string(source.filename), ...
        string(ir.sources.filename));
    verifyEqual(testCase, scalar(conn, ...
        "SELECT native_recording_id IS NULL AS n FROM recordings"), 1);
    verifyEqual(testCase, scalar(conn, ...
        "SELECT COUNT(*) AS n FROM recording_entity_links"), ...
        cases{caseIndex, 3});

    context = fetch(conn, ...
        "SELECT source_relative_path, entity_type, entity_native_id, " + ...
        "link_type, CASE WHEN role_label IS NULL THEN '<empty>' " + ...
        "ELSE role_label END AS role_label " + ...
        "FROM v_recording_entity_context ORDER BY link_type, entity_native_id");
    verifyTrue(testCase, all(string(context.source_relative_path) == relativePath));
    verifyEqual(testCase, sum(string(context.link_type) == "context"), 1);
    if cases{caseIndex, 1} == "example.project.social_dyad.multi_subject"
        participants = context(string(context.link_type) == "participant", :);
        verifyEqual(testCase, string(participants.entity_type), ...
            ["animal"; "animal"]);
        verifyEqual(testCase, string(participants.entity_native_id), ...
            ["F031"; "M012"]);
        verifyEqual(testCase, string(participants.role_label), ...
            ["female_partner"; "male_partner"]);
    else
        participant = context(string(context.link_type) == "participant", :);
        verifyEqual(testCase, string(participant.entity_type), "animal");
        verifyEqual(testCase, string(participant.role_label), "<empty>");
    end
    if cases{caseIndex, 1} == ...
            "example.project.rat_self_admin.filename_driven"
        verifyEqual(testCase, ...
            result.plan.ingestion_files.parse_status, ...
            "parsed_with_warnings");
        verifyGreaterThanOrEqual(testCase, ...
            result.plan.ingestion_files.warning_count, 1);
    else
        verifyEqual(testCase, result.plan.ingestion_files.parse_status, "parsed");
    end
    verifyEqual(testCase, result.plan.ingestion_files.action, "create");
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_runs"), 1);
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_files"), 1);
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM extraction_runs"), 0);
    verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM detections"), 0);
    verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

    clear cleanupDb cleanupRoot
end
clear cleanupPath
end

function testRootRelocationReusesSourceRecordingAndLinks(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = projectProfilePath(repoRoot);
rootOne = temporaryRoot();
rootTwo = temporaryRoot();
cleanupRootOne = onCleanup(@() removeTree(rootOne));
cleanupRootTwo = onCleanup(@() removeTree(rootTwo));
relativeNative = fullfile("control", "mouse_001", "baseline", ...
    "001_baseline_1.wav");
relativePath = replace(string(relativeNative), string(filesep), "/");
touchFile(fullfile(rootOne, relativeNative));
touchFile(fullfile(rootTwo, relativeNative));
[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
irOne = vawlume.source_mapping.parse(profilePath, rootOne, ...
    ProfileId="example.project.mouse_courtship.folder_driven", ...
    RepoRoot=repoRoot);
irTwo = vawlume.source_mapping.parse(profilePath, rootTwo, ...
    ProfileId="example.project.mouse_courtship.folder_driven", ...
    RepoRoot=repoRoot);
spec = struct(project_key="relocated_recording", ...
    project_name="Relocated recording", ...
    description="Pass 4 source-root relocation case.");

verifyNotEqual(testCase, irOne.sources.runtime_path, ...
    irTwo.sources.runtime_path);
verifyEqual(testCase, ...
    removevars(irOne.sources, "runtime_path"), ...
    removevars(irTwo.sources, "runtime_path"));
verifyEqual(testCase, irOne.records, irTwo.records);
verifyEqual(testCase, irOne.relationships, irTwo.relationships);

first = vawlume.ingest.project(conn, irOne, spec, Apply=true);
second = vawlume.ingest.project(conn, irTwo, spec, Apply=true);

verifyEqual(testCase, first.applied_counts.source_files, 1);
verifyEqual(testCase, first.applied_counts.recordings, 1);
verifyEqual(testCase, first.applied_counts.recording_entity_links, 2);
verifyEqual(testCase, second.status, "completed");
verifyEqual(testCase, second.applied_counts.reused_source_files, 1);
verifyEqual(testCase, second.applied_counts.reused_recordings, 1);
verifyEqual(testCase, ...
    second.applied_counts.reused_recording_entity_links, 2);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM source_files"), 1);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM recordings"), 1);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM recording_entity_links"), 2);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_runs"), 2);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_files"), 2);
verifyNotEqual(testCase, first.ingestion_run_id, second.ingestion_run_id);
verifyEqual(testCase, string(fetch(conn, ...
    "SELECT path_or_uri FROM source_files").path_or_uri), relativePath);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupDb cleanupRootTwo cleanupRootOne cleanupPath
end

function testDuplicateFilenamesInDifferentFoldersStayDistinct(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = projectProfilePath(repoRoot);
root = temporaryRoot();
cleanupRoot = onCleanup(@() removeTree(root));
filename = "OXY_PR_R03_SA07_001.wav";
touchFile(fullfile(root, filename));
touchFile(fullfile(root, "copy", filename));
[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
ir = vawlume.source_mapping.parse(profilePath, root, ...
    ProfileId="example.project.rat_self_admin.filename_driven", ...
    RepoRoot=repoRoot);
spec = struct(project_key="duplicate_filenames", ...
    project_name="Duplicate filenames", ...
    description="Pass 4 duplicate-filename identity case.");

result = vawlume.ingest.project(conn, ir, spec, Apply=true);

verifyEqual(testCase, result.status, "completed_with_warnings");
verifyEqual(testCase, height(result.plan.sources), 2);
verifyEqual(testCase, height(result.plan.recordings), 2);
verifyEqual(testCase, height(result.plan.recording_links), 4);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM source_files"), 2);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM recordings"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM recording_entity_links"), 4);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(DISTINCT relative_path) AS n FROM source_files"), 2);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(DISTINCT filename) AS n FROM source_files"), 1);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_runs"), 1);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM ingestion_files"), 2);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupDb cleanupRoot cleanupPath
end

function [conn, dbFile] = createDisposableDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
end

function cleanupDatabase(conn, dbFile)
try
    close(conn);
catch
end
if isfile(dbFile)
    delete(dbFile);
end
end

function root = temporaryRoot()
root = string(tempname);
mkdir(root);
end

function touchFile(path)
parent = string(fileparts(path));
if ~isfolder(parent)
    mkdir(parent);
end
fileId = fopen(path, "w");
assert(fileId ~= -1, "Test fixture file could not be created.");
cleanupFile = onCleanup(@() fclose(fileId));
fwrite(fileId, uint8([]));
clear cleanupFile
end

function removeTree(root)
if isfolder(root)
    rmdir(root, "s");
end
end

function value = scalar(conn, sql)
result = fetch(conn, sql);
value = double(result{1, 1});
end

function path = projectProfilePath(repoRoot)
path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
end

function root = repoRootForTest()
thisFile = mfilename("fullpath");
root = string(fileparts(fileparts(fileparts(thisFile))));
end
