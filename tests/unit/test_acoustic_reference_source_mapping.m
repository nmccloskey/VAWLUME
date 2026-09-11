function tests = test_acoustic_reference_source_mapping
tests = functiontests({ ...
    @testShippedProfileReusesExternalEventMapping, ...
    @testToneNoiseAndUserDefinedIntervalsMapWithoutAParser});
end

function testShippedProfileReusesExternalEventMapping(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[loaded, report] = vawlume.source_mapping.loadProfile(profilePath(repoRoot), ...
    ExpectedKind="external_stream_mapping", RepoRoot=repoRoot);

verifyTrue(testCase, report.is_valid);
verifyEqual(testCase, loaded.profile_kinds, "external_stream_mapping");
verifyEqual(testCase, loaded.profile_schema_versions, "0.3-draft");
verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
verifyFalse(testCase, any(loaded.profile_kinds == "acoustic_reference_mapping"));

clear cleanupPath
end

function testToneNoiseAndUserDefinedIntervalsMapWithoutAParser(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

ir = vawlume.source_mapping.mapTableToIR(referenceTable(), ...
    profilePath(repoRoot), RepoRoot=repoRoot);

verifyTrue(testCase, ir.valid_for_ingest);
verifyEqual(testCase, height(ir.events), 3);
verifyEqual(testCase, ir.events.native_event_label, ...
    ["LOW_TONE"; "WHITE_NOISE"; "colony_chirp_train"]);
verifyEqual(testCase, ir.events.normalized_event_key, ...
    ["tone"; "noise"; "colony_chirp_train"]);
verifyEqual(testCase, ir.events.start_time_s, [1; 4; 7]);
verifyEqual(testCase, ir.events.end_time_s, [2; 6; 7]);

minimum = ir.event_attributes(ir.event_attributes.attribute_name == ...
    "frequency_min_hz", :);
maximum = ir.event_attributes(ir.event_attributes.attribute_name == ...
    "frequency_max_hz", :);
verifyEqual(testCase, minimum.value_real(1), 18000);
verifyEqual(testCase, maximum.value_real(1), 22000);
verifyEqual(testCase, minimum.value_type(2:3), ["missing"; "missing"]);
verifyEqual(testCase, maximum.value_type(2:3), ["missing"; "missing"]);

channels = ir.event_attributes(ir.event_attributes.attribute_name == ...
    "channel_index", :);
verifyEqual(testCase, channels.value_integer([1 3]), [1; 2]);
verifyEqual(testCase, channels.value_type(2), "missing");

% This ordinary event-table mapping produces no synchronization-anchor IR.
verifyEqual(testCase, height(ir.anchors), 0);
verifyEqual(testCase, height(ir.anchor_observations), 0);

clear cleanupPath
end

function value = referenceTable()
value = table( ...
    ["tone-01"; "noise-01"; "custom-01"], ...
    ["LOW_TONE"; "WHITE_NOISE"; "colony_chirp_train"], ...
    [1; 4; 7], [2; 6; 7], ...
    ["18000"; ""; "NA"], ["22000"; ""; "N/A"], ...
    [1; NaN; 2], ...
    VariableNames=["reference_id", "reference_label", "start_time_s", ...
    "end_time_s", "frequency_min_hz", "frequency_max_hz", "channel_index"]);
end

function value = profilePath(repoRoot)
value = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "external_streams", "acoustic_reference_event_mapping_profile.json");
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
