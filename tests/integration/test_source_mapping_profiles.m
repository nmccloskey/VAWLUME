function tests = test_source_mapping_profiles
tests = functiontests({ ...
    @testAllProjectProfilesProduceDeterministicIR, ...
    @testBuiltinExtractorProfilesMapAtGenericFieldLevel, ...
    @testProjectConflictPreservesBothCandidates, ...
    @testNoDiscoveredSourceInvalidatesIR});
end

function testBuiltinExtractorProfilesMapAtGenericFieldLevel(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

deepSqueak = vawlume.source_mapping.mapTableToIR( ...
    oneDeepSqueakRow(), extractorProfilePath(repoRoot, "deepsqueak"), ...
    SourceKey="extractor:deepsqueak:integration", RepoRoot=repoRoot);
verifyTrue(testCase, deepSqueak.valid_for_ingest);
verifyEqual(testCase, height(deepSqueak.records), 1);
frequency = deepSqueak.values( ...
    deepSqueak.values.canonical_field == "contour_median_frequency", :);
verifyEqual(testCase, frequency.normalized_value_real, 55000);
verifyEqual(testCase, frequency.transform_key, "kHz_to_Hz");

mupet = vawlume.source_mapping.mapTableToIR( ...
    oneMupetRow(), extractorProfilePath(repoRoot, "mupet"), ...
    SourceKey="extractor:mupet:integration", RepoRoot=repoRoot);
verifyTrue(testCase, mupet.valid_for_ingest);
verifyEqual(testCase, height(mupet.records), 1);
interval = mupet.values(mupet.values.canonical_field == "inter_call_interval", :);
verifyEqual(testCase, interval.raw_value, "NA");
verifyEqual(testCase, interval.normalized_value_type, "missing");
verifyTrue(testCase, any(mupet.issues.code == "MISSING_TOKEN_NORMALIZED"));

clear cleanupPath
end

function testAllProjectProfilesProduceDeterministicIR(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profilePath = projectProfilePath(repoRoot);

cases = {
    "example.project.mouse_courtship.folder_driven", ...
        fullfile("control", "mouse_001", "baseline", "001_baseline_1.wav")
    "example.project.rat_self_admin.filename_driven", ...
        "OXY_PR_R03_SA07_001.wav"
    "example.project.social_dyad.multi_subject", ...
        fullfile("cohort_01", "dyad_004", "D004_M012_F031_courtship.wav")
    };

for caseIndex = 1:size(cases, 1)
    root = temporaryRoot("VAWLUME IR profile");
    cleanupRoot = onCleanup(@() removeTree(root));
    touchFile(fullfile(root, cases{caseIndex, 2}));

    first = vawlume.source_mapping.parse( ...
        profilePath, root, ProfileId=cases{caseIndex, 1}, RepoRoot=repoRoot);
    second = vawlume.source_mapping.parse( ...
        profilePath, root, ProfileId=cases{caseIndex, 1}, RepoRoot=repoRoot);

    verifyTrue(testCase, first.valid_for_ingest);
    verifyEqual(testCase, first.profile.profile_key, cases{caseIndex, 1});
    verifyEqual(testCase, first.profile.profile_version_source, "not_declared");
    verifyEqual(testCase, height(first.sources), 1);
    verifyGreaterThan(testCase, height(first.records), 0);
    verifyGreaterThan(testCase, height(first.values), 0);
    verifyEqual(testCase, first.sources.source_key, second.sources.source_key);
    verifyEqual(testCase, first.records, second.records);
    verifyEqual(testCase, first.values, second.values);
    verifyEqual(testCase, first.relationships, second.relationships);
    verifyEqual(testCase, first.issues, second.issues);
    verifyFalse(testCase, any(contains(first.records.record_key, string(root))));

    if cases{caseIndex, 1} == "example.project.mouse_courtship.folder_driven"
        verifyEqual(testCase, height(first.records), 5);
        verifyEqual(testCase, height(first.relationships), 4);
        verifyTrue(testCase, any(first.issues.code == "VALUE_CORROBORATED"));
    elseif cases{caseIndex, 1} == "example.project.rat_self_admin.filename_driven"
        phenotype = first.values(first.values.canonical_field == "group_id", :);
        verifyEqual(testCase, phenotype.raw_value, "PR");
        verifyEqual(testCase, phenotype.normalized_value_text, "punishment_resistant");
        verifyTrue(testCase, any(first.issues.code == "SOURCE_DUPLICATE_DISCOVERY"));
    else
        roles = sort(first.relationships.role_label(strlength(first.relationships.role_label) > 0));
        verifyEqual(testCase, roles, ["female_partner"; "male_partner"]);
        verifyEqual(testCase, height(first.records), 7);
        verifyEqual(testCase, height(first.relationships), 6);
    end

    clear cleanupRoot
end

clear cleanupPath
end

function testProjectConflictPreservesBothCandidates(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
root = temporaryRoot("VAWLUME IR conflict");
cleanupRoot = onCleanup(@() removeTree(root));
touchFile(fullfile(root, "control", "mouse_001", "courtship", ...
    "002_courtship_1.wav"));

result = vawlume.source_mapping.parse( ...
    projectProfilePath(repoRoot), root, ...
    ProfileId="example.project.mouse_courtship.folder_driven", ...
    RepoRoot=repoRoot);

conflicts = result.values(result.values.consolidation_status == "conflict", :);
verifyFalse(testCase, result.valid_for_ingest);
verifyEqual(testCase, result.summary.conflict_count, 1);
verifyEqual(testCase, sum(result.issues.code == "VALUE_CONFLICT"), 1);
verifyEqual(testCase, sort(conflicts.raw_value), ["001"; "002"]);
verifyEqual(testCase, unique(conflicts.evidence_count), 2);

clear cleanupPath cleanupRoot
end

function testNoDiscoveredSourceInvalidatesIR(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
root = temporaryRoot("VAWLUME IR empty");
cleanupRoot = onCleanup(@() removeTree(root));

result = vawlume.source_mapping.parse( ...
    projectProfilePath(repoRoot), root, ...
    ProfileId="example.project.mouse_courtship.folder_driven", ...
    RepoRoot=repoRoot);

verifyFalse(testCase, result.valid_for_ingest);
verifyEmpty(testCase, result.sources);
verifyEqual(testCase, sum(result.issues.code == "SOURCE_NOT_FOUND"), 1);
verifyEqual(testCase, result.summary.error_count, 1);

clear cleanupPath cleanupRoot
end

function path = projectProfilePath(repoRoot)
path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.yaml");
end

function path = extractorProfilePath(repoRoot, name)
path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", name, name + "_output_mapping_profile.yaml");
end

function tbl = oneDeepSqueakRow()
tbl = table( ...
    "calls_001.mat", 1, "USV", 1, 0.95, 0.100, 0.148, 0.048, ...
    55, 40, 80, 40, 4.5, 2.1, 76, 1.2, -35, 0.8, ...
    VariableNames=[
    "File"
    "ID"
    "Label"
    "Accepted"
    "Score"
    "Begin Time (s)"
    "End Time (s)"
    "Call Length (s)"
    "Principal Frequency (kHz)"
    "Low Freq (kHz)"
    "High Freq (kHz)"
    "Delta Freq (kHz)"
    "Frequency Standard Deviation (kHz)"
    "Slope (kHz/s)"
    "Peak Freq (kHz)"
    "Sinuosity"
    "Mean Power (dB/Hz)"
    "Tonality"
    ]);
end

function tbl = oneMupetRow()
tbl = table( ...
    1, 0.100, 0.148, "NA", 48, 45, 60, 40, 75, 55, 35, 12.5, -18, ...
    VariableNames=[
    "Syllable number"
    "Syllable start time (sec)"
    "Syllable end time (sec)"
    "inter-syllable interval (sec)"
    "syllable duration (msec)"
    "starting frequency (kHz)"
    "final frequency (kHz)"
    "minimum frequency (kHz)"
    "maximum frequency (kHz)"
    "mean frequency (kHz)"
    "frequency bandwidth (kHz)"
    "total syllable energy (dB)"
    "peak syllable amplitude (dB)"
    ]);
end

function root = temporaryRoot(label)
root = fullfile(tempdir, char(label + " " + string(java.util.UUID.randomUUID)));
mkdir(root);
end

function touchFile(path)
folder = fileparts(path);
if ~isfolder(folder)
    mkdir(folder);
end
fileId = fopen(path, "w");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "");
clear cleaner
end

function removeTree(path)
if isfolder(path)
    rmdir(path, "s");
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
