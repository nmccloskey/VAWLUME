function tests = test_external_alignment_source_mapping
tests = functiontests({ ...
    @testShippedExternalAndAnchorProfilesLoad, ...
    @testBehaviorEventsPreserveSemanticsAttributesCoverageAndPreview, ...
    @testNeuralMillisecondsNormalizeWithoutLosingNativeTime, ...
    @testMalformedExternalEventsProduceStructuredIssues, ...
    @testLongAndWideLayoutsNormalizeEquivalently, ...
    @testDuplicateObservationsRequireExplicitResolution, ...
    @testAnchorProblemsProduceStructuredIssues, ...
    @testEventLinkedAnchorReferencesUseMappedSourceContext, ...
    @testWideMissingDeclaredColumnIsStructured, ...
    @testProfileValidationRejectsUnsupportedUnitsAndUnknownTargets});
end

function testShippedExternalAndAnchorProfilesLoad(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
cases = {
    externalProfilePath(repoRoot, "behavior_video"), "external_stream_mapping"
    externalProfilePath(repoRoot, "neural_ttl"), "external_stream_mapping"
    anchorProfilePath(repoRoot, "long"), "alignment_anchor_mapping"
    anchorProfilePath(repoRoot, "wide"), "alignment_anchor_mapping"
    };

for index = 1:size(cases, 1)
    [loaded, report] = vawlume.source_mapping.loadProfile( ...
        cases{index, 1}, ExpectedKind=cases{index, 2}, RepoRoot=repoRoot);
    verifyTrue(testCase, report.is_valid);
    verifyEqual(testCase, loaded.profile_kinds, cases{index, 2});
    verifyEqual(testCase, loaded.profile_schema_versions, "0.3-draft");
    verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
    verifyEqual(testCase, strlength(loaded.checksum_sha256), 64);
end

clear cleanupPath
end

function testBehaviorEventsPreserveSemanticsAttributesCoverageAndPreview(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

ir = vawlume.source_mapping.mapTableToIR(behaviorTable(), ...
    externalProfilePath(repoRoot, "behavior_video"), RepoRoot=repoRoot);

verifyTrue(testCase, ir.valid_for_ingest);
verifyEqual(testCase, ir.ir_schema_version, "0.2-draft");
verifyEqual(testCase, height(ir.streams), 1);
verifyEqual(testCase, height(ir.events), 3);
verifyEqual(testCase, height(ir.event_attributes), 3);
verifyEqual(testCase, height(ir.coverage), 2);
verifyEqual(testCase, ir.events.native_event_label, ...
    ["Intruder enters"; "Sniffing"; "SYNC_FLASH"]);
verifyEqual(testCase, ir.events.normalized_event_key, ...
    ["female_entry"; "investigation"; "sync_marker"]);
verifyEqual(testCase, ir.events.end_time_s(2), ir.events.start_time_s(2));
verifyEqual(testCase, ir.event_attributes.attribute_name, repmat("zone", 3, 1));
verifyEqual(testCase, ir.coverage.start_time_s, [0; 300]);
verifyEqual(testCase, ir.coverage.end_time_s, [240; 600]);
verifyEqual(testCase, ir.coverage.observation_status, repmat("observed", 2, 1));
verifyEqual(testCase, ir.events.start_column_resolution, repmat("exact", 3, 1));

aliasTable = renamevars(behaviorTable(), "start_time_s", "timestamp_s");
aliasIR = vawlume.source_mapping.mapTableToIR(aliasTable, ...
    externalProfilePath(repoRoot, "behavior_video"), RepoRoot=repoRoot);
verifyTrue(testCase, aliasIR.valid_for_ingest);
verifyEqual(testCase, aliasIR.events.start_source_field, repmat("timestamp_s", 3, 1));
verifyEqual(testCase, aliasIR.events.start_column_resolution, repmat("alias", 3, 1));

report = vawlume.source_mapping.preview(ir);
verifyEqual(testCase, report.verdict, "READY FOR INGEST");
verifyEqual(testCase, report.external_streams.event_count, 3);
verifyEqual(testCase, report.external_streams.coverage_segment_count, 2);
verifyTrue(testCase, contains(report.text, "EXTERNAL EVENT STREAMS"));
verifyTrue(testCase, contains(report.text, "female_entry"));

clear cleanupPath
end

function testNeuralMillisecondsNormalizeWithoutLosingNativeTime(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

ir = neuralIR(repoRoot);
verifyTrue(testCase, ir.valid_for_ingest);
verifyEqual(testCase, ir.events.start_time_native, [121482; 602911; 1017000]);
verifyEqual(testCase, ir.events.start_time_s, [121.482; 602.911; 1017], ...
    AbsTol=1e-12);
verifyEqual(testCase, ir.events.native_time_unit, repmat("ms", 3, 1));
verifyEqual(testCase, ir.events.time_transform, repmat("ms_to_s", 3, 1));
amplitude = ir.event_attributes(ir.event_attributes.attribute_name == "amplitude", :);
verifyEqual(testCase, amplitude.value_real, [5; 4.8; 5.1]);
channel = ir.event_attributes(ir.event_attributes.attribute_name == "channel", :);
verifyEqual(testCase, channel.value_integer, [1; 1; 1]);
verifyEqual(testCase, ir.coverage.end_time_native, 650000);
verifyEqual(testCase, ir.coverage.end_time_s, 650);

clear cleanupPath
end

function testMalformedExternalEventsProduceStructuredIssues(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profile = externalProfilePath(repoRoot, "behavior_video");

bad = behaviorTable();
bad.event_id(2) = bad.event_id(1);
bad.start_time_s(1) = Inf;
bad.end_time_s(3) = bad.start_time_s(3) - 1;
ir = vawlume.source_mapping.mapTableToIR(bad, profile, RepoRoot=repoRoot);
verifyFalse(testCase, ir.valid_for_ingest);
verifyTrue(testCase, all(ismember( ...
    ["TIMESTAMP_INVALID", "EVENT_INTERVAL_INVALID", "NATIVE_EVENT_ID_DUPLICATE"], ...
    ir.issues.code)));
verifyTrue(testCase, all(ir.issues.affects_validity));

missingTimestamp = removevars(behaviorTable(), "start_time_s");
missing = vawlume.source_mapping.mapTableToIR(missingTimestamp, profile, RepoRoot=repoRoot);
verifyFalse(testCase, missing.valid_for_ingest);
verifyTrue(testCase, any(missing.issues.code == "TIMESTAMP_COLUMN_MISSING"));

[loaded, ~] = vawlume.source_mapping.loadProfile(profile);
coverageProfile = loaded.document;
coverageProfile.coverage.segments(1).end_time_native = -1;
badCoverage = vawlume.source_mapping.mapTableToIR( ...
    behaviorTable(), coverageProfile);
verifyFalse(testCase, badCoverage.valid_for_ingest);
verifyTrue(testCase, any(badCoverage.issues.code == "COVERAGE_INTERVAL_INVALID"));

clear cleanupPath
end

function testLongAndWideLayoutsNormalizeEquivalently(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

long = vawlume.source_mapping.mapTableToIR(longAnchorTable(), ...
    anchorProfilePath(repoRoot, "long"), RepoRoot=repoRoot);
wide = vawlume.source_mapping.mapTableToIR(wideAnchorTable(), ...
    anchorProfilePath(repoRoot, "wide"), RepoRoot=repoRoot);

verifyTrue(testCase, long.valid_for_ingest);
verifyTrue(testCase, wide.valid_for_ingest);
verifyEqual(testCase, long.anchors.anchor_key, wide.anchors.anchor_key);
verifyEqual(testCase, normalizedObservations(long), normalizedObservations(wide));
verifyEqual(testCase, long.anchor_fit_pairs(:, 1:3), wide.anchor_fit_pairs(:, 1:3));
verifyEqual(testCase, long.anchor_fit_pairs.fit_eligible_anchor_count, [3; 3]);
verifyEqual(testCase, height(long.anchor_observations), 9);
verifyEqual(testCase, height(wide.anchor_observations), 9);
verifyTrue(testCase, contains(vawlume.source_mapping.preview(long).text, ...
    "ALIGNMENT ANCHORS"));

clear cleanupPath
end

function testDuplicateObservationsRequireExplicitResolution(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
profile = anchorProfilePath(repoRoot, "long");

resolved = longAnchorTable();
resolved = [resolved; resolved(2, :)];
resolved.timestamp_s(end) = resolved.timestamp_s(end) + 0.004;
resolved.role(end) = "replicate";
resolved.include(end) = false;
ir = vawlume.source_mapping.mapTableToIR(resolved, profile, RepoRoot=repoRoot);
verifyTrue(testCase, ir.valid_for_ingest);
rows = ir.anchor_observations.anchor_key == "sync01" & ...
    ir.anchor_observations.timebase_key == "video_native";
verifyEqual(testCase, height(ir.anchor_observations(rows, :)), 2);
verifyEqual(testCase, sort(ir.anchor_observations.included_in_fit(rows)), [0; 1]);

ambiguous = resolved;
ambiguous.role(rowsForLongVideoDuplicate(ambiguous)) = "";
ambiguous.include(rowsForLongVideoDuplicate(ambiguous)) = false;
% Missing inclusion is represented by a string table so the mapper sees no
% explicit choice rather than interpreting false as an exclusion.
ambiguous.include = string(ambiguous.include);
ambiguous.include(rowsForLongVideoDuplicate(ambiguous)) = "";
unresolved = vawlume.source_mapping.mapTableToIR(ambiguous, profile, RepoRoot=repoRoot);
verifyFalse(testCase, unresolved.valid_for_ingest);
verifyTrue(testCase, any(unresolved.issues.code == "ANCHOR_PRIMARY_AMBIGUOUS"));
verifyEqual(testCase, height(unresolved.anchor_observations), 10);

multiplePrimary = resolved;
multiplePrimary.role(end) = "primary";
multiplePrimary.include(end) = true;
invalidPrimary = vawlume.source_mapping.mapTableToIR( ...
    multiplePrimary, profile, RepoRoot=repoRoot);
verifyFalse(testCase, invalidPrimary.valid_for_ingest);
verifyTrue(testCase, any(invalidPrimary.issues.code == "ANCHOR_PRIMARY_AMBIGUOUS"));

clear cleanupPath
end

function testAnchorProblemsProduceStructuredIssues(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

tbl = table("", "unknown_clock", 1, "bad_role", "maybe", 0.01, "", ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
ir = vawlume.source_mapping.mapTableToIR(tbl, anchorProfilePath(repoRoot, "long"), ...
    RepoRoot=repoRoot);

verifyFalse(testCase, ir.valid_for_ingest);
verifyTrue(testCase, all(ismember(["ANCHOR_KEY_MISSING", ...
    "ANCHOR_IDENTITY_UNDECLARED", "ANCHOR_ROLE_INVALID", ...
    "ANCHOR_INCLUDED_INVALID"], ir.issues.code)));
verifyEqual(testCase, height(ir.anchor_observations), 1);

clear cleanupPath
end

function testEventLinkedAnchorReferencesUseMappedSourceContext(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
events = neuralIR(repoRoot);
tbl = longAnchorTable();
neuralRows = tbl.stream == "neural";
tbl.event_id(neuralRows) = ["n1"; "n2"; "n3"];

linked = vawlume.source_mapping.mapTableToIR(tbl, ...
    anchorProfilePath(repoRoot, "long"), RepoRoot=repoRoot, EventContext=events);
verifyTrue(testCase, linked.valid_for_ingest);
verifyEqual(testCase, linked.anchor_observations.event_native_event_id(neuralRows), ...
    ["n1"; "n2"; "n3"]);

tbl.event_id(find(neuralRows, 1)) = "missing_event";
unresolved = vawlume.source_mapping.mapTableToIR(tbl, ...
    anchorProfilePath(repoRoot, "long"), RepoRoot=repoRoot, EventContext=events);
verifyFalse(testCase, unresolved.valid_for_ingest);
verifyTrue(testCase, any(unresolved.issues.code == "EVENT_REFERENCE_UNRESOLVED"));

clear cleanupPath
end

function testWideMissingDeclaredColumnIsStructured(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

tbl = removevars(wideAnchorTable(), "neural");
ir = vawlume.source_mapping.mapTableToIR(tbl, anchorProfilePath(repoRoot, "wide"), ...
    RepoRoot=repoRoot);
verifyFalse(testCase, ir.valid_for_ingest);
verifyTrue(testCase, any(ir.issues.code == "WIDE_STREAM_COLUMN_MISSING"));
verifyEqual(testCase, height(ir.anchor_observations), 6);

clear cleanupPath
end

function testProfileValidationRejectsUnsupportedUnitsAndUnknownTargets(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));
[loaded, ~] = vawlume.source_mapping.loadProfile( ...
    externalProfilePath(repoRoot, "behavior_video"));
document = loaded.document;

document.context.native_time_unit = "frames";
report = vawlume.source_mapping.validateProfile(document, ...
    ExpectedKind="external_stream_mapping");
verifyFalse(testCase, report.is_valid);
verifyTrue(testCase, any(string(report.issue_table.code) == "TIME_UNIT_UNSUPPORTED"));

document = loaded.document;
document.normalized_event_mapping.mappings(1).normalized_value = "unknown_target";
report = vawlume.source_mapping.validateProfile(document, ...
    ExpectedKind="external_stream_mapping");
verifyFalse(testCase, report.is_valid);
verifyTrue(testCase, any(string(report.issue_table.code) == ...
    "NORMALIZED_EVENT_TARGET_UNKNOWN"));

clear cleanupPath
end

function tbl = behaviorTable()
tbl = table( ...
    ["b1"; "b2"; "b3"], ...
    ["Intruder enters"; "Sniffing"; "SYNC_FLASH"], ...
    [10; 20; 30], [12; NaN; 30], ["F01"; "M01"; ""], ...
    ["door"; "center"; "sync"], ...
    VariableNames=["event_id", "event", "start_time_s", "end_time_s", ...
    "subject", "zone"]);
end

function ir = neuralIR(repoRoot)
tbl = table(["n1"; "n2"; "n3"], repmat("TTL1_HIGH", 3, 1), ...
    [121482; 602911; 1017000], [5; 4.8; 5.1], [1; 1; 1], ...
    VariableNames=["pulse_id", "marker", "timestamp_ms", "amplitude_v", "channel"]);
ir = vawlume.source_mapping.mapTableToIR(tbl, ...
    externalProfilePath(repoRoot, "neural_ttl"), RepoRoot=repoRoot);
end

function tbl = longAnchorTable()
markers = repelem(["sync01"; "sync02"; "sync03"], 3);
streams = repmat(["audio"; "video"; "neural"], 3, 1);
timestamps = [4.216; 67.833; 121.482; 485.638; 549.275; 602.911; ...
    900.000; 963.000; 1017.000];
tbl = table(markers, streams, timestamps, repmat("primary", 9, 1), ...
    true(9, 1), 0.002 * ones(9, 1), strings(9, 1), ...
    VariableNames=["marker", "stream", "timestamp_s", "role", "include", ...
    "uncertainty_s", "event_id"]);
end

function tbl = wideAnchorTable()
tbl = table(["sync01"; "sync02"; "sync03"], [4.216; 485.638; 900], ...
    [67.833; 549.275; 963], [121.482; 602.911; 1017], ...
    VariableNames=["marker", "audio", "video", "neural"]);
end

function rows = rowsForLongVideoDuplicate(tbl)
rows = tbl.marker == "sync01" & tbl.stream == "video";
end

function value = normalizedObservations(ir)
value = sortrows(ir.anchor_observations(:, ["anchor_key", "stream_key", ...
    "timebase_key", "observed_time_native", "observed_time_s", ...
    "included_in_fit"]), ["anchor_key", "timebase_key"]);
end

function path = externalProfilePath(repoRoot, name)
path = fullfile(repoRoot, "config", "01_mapping_profiles", "external_streams", ...
    name + "_event_mapping_profile.json");
end

function path = anchorProfilePath(repoRoot, layout)
path = fullfile(repoRoot, "config", "01_mapping_profiles", "alignment_anchors", ...
    layout + "_anchor_mapping_profile.json");
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
