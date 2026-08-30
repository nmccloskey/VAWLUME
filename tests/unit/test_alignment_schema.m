function tests = test_alignment_schema
%TEST_ALIGNMENT_SCHEMA Phase 7 temporal-alignment relational invariants.
%
% Positive and negative probes over an empty schema. These assert what the schema
% itself enforces; invariants deliberately left to application code are named in
% docs/development/11_temporal_alignment_schema.md and tested in the pass that
% implements them, so nothing here pretends the database guards more than it does.
tests = functiontests({ ...
    @testRecordingNativeTimebaseIsSingularAndScoped, ...
    @testTimebaseAndStreamNamesAreUniqueWithinScope, ...
    @testStreamSourceRequiresExactlyOneReference, ...
    @testExternalEventAndCoverageIntervals, ...
    @testEventAttributesRecordExplicitMissingness, ...
    @testAlignmentSetOwnsOneReferenceTimebase, ...
    @testLogicalAnchorKeysAreUniquePerSet, ...
    @testAnchorObservationRedundancyRules, ...
    @testAnchorObservationEventMustShareTimebase, ...
    @testOneTransformPerSourceTimebaseInASet, ...
    @testResidualsStayInsideTheirRunAndAnchor});
end

% ------------------------------------------------------------- timebases ---

function testRecordingNativeTimebaseIsSingularAndScoped(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>

% One native audio clock per recording is accepted.
execute(conn, insertTimebase("audio_native", 1, 1));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM timebases WHERE is_recording_native = 1"), 1);

% A second native clock on the same recording is not.
verifySqlFails(testCase, conn, insertTimebase("audio_native_duplicate", 1, 1));

% A non-native clock on the same recording is fine, and so is a second
% recording's own native clock.
execute(conn, insertTimebase("behaviour_clock", 1, 0));
execute(conn, insertTimebase("audio_native_two", 2, 1));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM timebases WHERE is_recording_native = 1"), 2);

% An external clock belonging to no recording is legal.
execute(conn, "INSERT INTO timebases(project_id, timebase_name, timebase_kind) " + ...
    "VALUES (1, 'neural_native', 'acquisition_clock')");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM timebases WHERE recording_id IS NULL"), 1);

% Native status without a recording is contradictory and rejected.
verifySqlFails(testCase, conn, ...
    "INSERT INTO timebases(project_id, timebase_name, timebase_kind, is_recording_native) " + ...
    "VALUES (1, 'orphan_native', 'acquisition_clock', 1)");

clear cleanup
end

function testTimebaseAndStreamNamesAreUniqueWithinScope(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
execute(conn, insertTimebase("audio_native", 1, 1));

% The same name under a different recording is a different clock.
execute(conn, insertTimebase("audio_native", 2, 1));
verifySqlFails(testCase, conn, insertTimebase("audio_native", 1, 0));

% Project-scoped clocks are unique too. This is the case a table-level UNIQUE
% over a nullable recording_id would have silently allowed to duplicate.
execute(conn, "INSERT INTO timebases(project_id, timebase_name, timebase_kind) " + ...
    "VALUES (1, 'neural_native', 'acquisition_clock')");
verifySqlFails(testCase, conn, ...
    "INSERT INTO timebases(project_id, timebase_name, timebase_kind) " + ...
    "VALUES (1, 'neural_native', 'acquisition_clock')");

execute(conn, insertStream("behaviour", 1, 1));
verifySqlFails(testCase, conn, insertStream("behaviour", 1, 1));
execute(conn, insertStream("behaviour", 2, 2));

clear cleanup
end

% ----------------------------------------------------- streams and events ---

function testStreamSourceRequiresExactlyOneReference(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
seedStream(conn);

% Exactly one of source_file_id / artifact_id identifies a source row.
execute(conn, "INSERT INTO external_stream_sources(external_stream_id, source_file_id, source_role) " + ...
    "VALUES (1, 1, 'events')");
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_stream_sources(external_stream_id, source_role) VALUES (1, 'anchors')");
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_stream_sources(external_stream_id, source_file_id, artifact_id, source_role) " + ...
    "VALUES (1, 1, 1, 'anchors')");

% Several sources per stream are legal: one logical stream may span exports.
execute(conn, "INSERT INTO external_stream_sources(external_stream_id, artifact_id, source_role) " + ...
    "VALUES (1, 1, 'anchors')");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM external_stream_sources WHERE external_stream_id = 1"), 2);

clear cleanup
end

function testExternalEventAndCoverageIntervals(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
seedStream(conn);

execute(conn, "INSERT INTO external_events(external_stream_id, native_event_id, " + ...
    "native_event_label, event_type, start_time_native, end_time_native) " + ...
    "VALUES (1, 'E1', 'Nose poke', 'nose_poke', 10.0, 10.5)");

% The native label survives normalization rather than being replaced by it.
verifyEqual(testCase, string(scalarText(conn, ...
    "SELECT native_event_label AS v FROM external_events WHERE native_event_id = 'E1'")), ...
    "Nose poke");

% An event may be an instant, but it may not end before it starts.
execute(conn, "INSERT INTO external_events(external_stream_id, native_event_id, " + ...
    "event_type, start_time_native) VALUES (1, 'E2', 'ttl_edge', 20.0)");
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_events(external_stream_id, native_event_id, event_type, " + ...
    "start_time_native, end_time_native) VALUES (1, 'E3', 'bad', 30.0, 29.0)");

% Coverage exists so a gap can be stated rather than assumed away: two observed
% windows with a dropout between them.
execute(conn, insertCoverage(1, 0, 100));
execute(conn, insertCoverage(2, 150, 200));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM external_stream_coverage WHERE external_stream_id = 1"), 2);

verifySqlFails(testCase, conn, insertCoverage(3, 60, 50));
verifySqlFails(testCase, conn, insertCoverage(1, 300, 400));
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_stream_coverage(external_stream_id, segment_index, " + ...
    "start_time_native, end_time_native, observation_status) " + ...
    "VALUES (1, 4, 300, 400, 'assumed')");

clear cleanup
end

function testEventAttributesRecordExplicitMissingness(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
seedStream(conn);
execute(conn, "INSERT INTO external_events(external_stream_id, native_event_id, " + ...
    "event_type, start_time_native) VALUES (1, 'E1', 'nose_poke', 10.0)");

execute(conn, "INSERT INTO external_event_attributes(external_event_id, attribute_name, " + ...
    "native_field_name, value_type, value_real, unit) " + ...
    "VALUES (1, 'confidence', 'Confidence', 'real', 0.82, 'ratio')");

% A field the source left blank is recorded as missing, keeping its raw token,
% rather than being coerced to zero.
execute(conn, "INSERT INTO external_event_attributes(external_event_id, attribute_name, " + ...
    "native_field_name, value_type, native_raw_token) " + ...
    "VALUES (1, 'prominence', 'Prominence', 'missing', 'NA')");
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM external_event_attributes " + ...
    "WHERE value_type = 'missing' AND value_real IS NULL"), 1);

% A missing value carrying a value, or a present value carrying none, is rejected.
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_event_attributes(external_event_id, attribute_name, value_type, value_real) " + ...
    "VALUES (1, 'bad_missing', 'missing', 1.0)");
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_event_attributes(external_event_id, attribute_name, value_type) " + ...
    "VALUES (1, 'bad_real', 'real')");
verifySqlFails(testCase, conn, ...
    "INSERT INTO external_event_attributes(external_event_id, attribute_name, value_type, value_real) " + ...
    "VALUES (1, 'confidence', 'real', 0.9)");

clear cleanup
end

% ------------------------------------------------------- alignment sets ---

function testAlignmentSetOwnsOneReferenceTimebase(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
execute(conn, insertAnalysisRun("align-1"));
execute(conn, insertAlignmentSet(1, 3));

verifyEqual(testCase, scalar(conn, ...
    "SELECT reference_timebase_id AS n FROM alignment_sets WHERE alignment_set_id = 1"), 3);

% The analysis run is the alignment set's identity, so it cannot be shared.
execute(conn, insertAnalysisRun("align-2"));
verifySqlFails(testCase, conn, insertAlignmentSet(1, 1));
execute(conn, insertAlignmentSet(2, 1));

% At most one manifest reference, and a manifest is optional while assembling.
execute(conn, insertAnalysisRun("align-3"));
verifySqlFails(testCase, conn, ...
    "INSERT INTO alignment_sets(analysis_run_id, reference_timebase_id, " + ...
    "manifest_source_file_id, manifest_artifact_id) VALUES (3, 3, 1, 1)");

clear cleanup
end

function testLogicalAnchorKeysAreUniquePerSet(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
execute(conn, insertAnalysisRun("align-1"));
execute(conn, insertAlignmentSet(1, 3));
execute(conn, insertAnalysisRun("align-2"));
execute(conn, insertAlignmentSet(2, 3));

execute(conn, insertAnchor(1, "sync_01"));
verifySqlFails(testCase, conn, insertAnchor(1, "sync_01"));

% The same key in a different alignment set is a different logical anchor.
execute(conn, insertAnchor(2, "sync_01"));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM alignment_anchors WHERE anchor_key = 'sync_01'"), 2);

clear cleanup
end

function testAnchorObservationRedundancyRules(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
execute(conn, insertAnalysisRun("align-1"));
execute(conn, insertAlignmentSet(1, 3));
execute(conn, insertAnchor(1, "sync_01"));

% One logical anchor observed on three clocks: the case a pairwise
% source/target-time row could not express at all.
execute(conn, insertObservation(1, 1, 12.004, "primary", 1));
execute(conn, insertObservation(1, 2, 11.876, "primary", 1));
execute(conn, insertObservation(1, 3, 302.551, "primary", 1));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(DISTINCT timebase_id) AS n FROM alignment_anchor_observations " + ...
    "WHERE alignment_anchor_id = 1"), 3);

% A redundant reading on a clock already used is legal as QC evidence, but only
% while it is excluded from the fit.
execute(conn, insertObservation(1, 1, 12.006, "replicate", 0));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM alignment_anchor_observations " + ...
    "WHERE alignment_anchor_id = 1 AND timebase_id = 1"), 2);

% Two *included* readings on one clock would silently become two statistical
% anchors, so that is rejected.
verifySqlFails(testCase, conn, insertObservation(1, 1, 12.008, "primary", 1));

% A row marked excluded may not also claim to be in the fit.
verifySqlFails(testCase, conn, insertObservation(1, 2, 11.9, "excluded", 1));

% A timestamp-only observation, with no external event, stays legal for a
% manually identified marker edge.
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM alignment_anchor_observations WHERE external_event_id IS NULL"), 4);

clear cleanup
end

function testAnchorObservationEventMustShareTimebase(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
seedStream(conn);
execute(conn, "INSERT INTO external_events(external_stream_id, native_event_id, " + ...
    "event_type, start_time_native) VALUES (1, 'TTL1', 'ttl_edge', 12.004)");
execute(conn, insertAnalysisRun("align-1"));
execute(conn, insertAlignmentSet(1, 3));
execute(conn, insertAnchor(1, "sync_01"));

% The stream seeded above lives on timebase 1, so an observation on timebase 1
% may cite its event.
execute(conn, "INSERT INTO alignment_anchor_observations(alignment_anchor_id, " + ...
    "timebase_id, external_event_id, observed_time_native) VALUES (1, 1, 1, 12.004)");

% Citing that same event from an observation claiming a different clock is the
% error this trigger exists to catch.
verifySqlFails(testCase, conn, ...
    "INSERT INTO alignment_anchor_observations(alignment_anchor_id, " + ...
    "timebase_id, external_event_id, observed_time_native) VALUES (1, 2, 1, 11.876)");

clear cleanup
end

% ------------------------------------------------ transforms and residuals ---

function testOneTransformPerSourceTimebaseInASet(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
execute(conn, insertAnalysisRun("align-1"));
execute(conn, insertAlignmentSet(1, 3));

execute(conn, insertRun(1, 1, 3, "offset"));
execute(conn, insertRun(1, 2, 3, "affine"));

% A second transform for the same source clock in one set would give two answers
% to the same question.
verifySqlFails(testCase, conn, insertRun(1, 1, 3, "affine"));

% The target column is a convenience copy of the set's reference and is
% trigger-enforced to match it.
verifySqlFails(testCase, conn, insertRun(1, 4, 1, "offset"));

% A clock cannot be aligned to itself, and the method vocabulary is closed.
verifySqlFails(testCase, conn, insertRun(1, 3, 3, "offset"));
verifySqlFails(testCase, conn, insertRun(1, 4, 3, "dynamic_time_warping"));

% piecewise_affine remains representable even though fitting it is deferred.
execute(conn, insertRun(1, 4, 3, "piecewise_affine"));
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM time_alignment_runs WHERE alignment_set_id = 1"), 3);

clear cleanup
end

function testResidualsStayInsideTheirRunAndAnchor(testCase)
[conn, cleanup] = setUpSchema(); %#ok<ASGLU>
seedTimebases(conn);
execute(conn, insertAnalysisRun("align-1"));
execute(conn, insertAlignmentSet(1, 3));
execute(conn, insertRun(1, 1, 3, "offset"));
execute(conn, insertAnchor(1, "sync_01"));
execute(conn, insertAnchor(1, "sync_02"));
execute(conn, insertObservation(1, 1, 10.0, "primary", 1));   % obs 1, source clock
execute(conn, insertObservation(1, 3, 310.0, "primary", 1));  % obs 2, reference clock
execute(conn, insertObservation(2, 1, 20.0, "primary", 1));   % obs 3, other anchor
execute(conn, insertObservation(1, 2, 9.5, "primary", 1));    % obs 4, uninvolved clock

execute(conn, insertResidual(1, 1, 1, 2, 10.0, 310.0, 310.0, 0));

% One residual per anchor per fit.
verifySqlFails(testCase, conn, insertResidual(1, 1, 1, 2, 10.0, 310.0, 310.0, 0));

% Both observations must belong to the anchor the residual names.
verifySqlFails(testCase, conn, insertResidual(1, 2, 1, 2, 10.0, 310.0, 310.0, 0));

% The source observation must sit on the run's source clock, and the reference
% observation on its target clock.
verifySqlFails(testCase, conn, insertResidual(1, 2, 3, 4, 20.0, 9.5, 320.0, 0));

% A residual cannot pair an observation with itself.
verifySqlFails(testCase, conn, insertResidual(1, 2, 3, 3, 20.0, 20.0, 320.0, 0));

% Excluding a residual requires saying why.
verifySqlFails(testCase, conn, ...
    "INSERT INTO alignment_anchor_residuals(alignment_run_id, alignment_anchor_id, " + ...
    "source_observation_id, reference_observation_id, observed_source_time, " + ...
    "observed_reference_time, predicted_reference_time, residual_s, included_in_fit) " + ...
    "VALUES (1, 2, 3, 2, 20.0, 310.0, 320.0, -10.0, 0)");

verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ----------------------------------------------------------------- setup ---

function [conn, cleanup] = setUpSchema()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
cleanup = onCleanup(@() tearDown(conn, dbFile, fullfile(repoRoot, "src")));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));

execute(conn, "INSERT INTO projects(project_key, project_name) " + ...
    "VALUES ('alignment_schema_test', 'Alignment schema test')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri) " + ...
    "VALUES (1, 'external_event_log', 'synthetic/behaviour.csv')");
execute(conn, "INSERT INTO artifacts(project_id, artifact_type, path_or_uri) " + ...
    "VALUES (1, 'external_anchor_log', 'synthetic/anchors.csv')");
for index = 1:2
    execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri) " + ...
        "VALUES (1, 'recording_audio', 'synthetic/rec" + string(index) + ".wav')");
    execute(conn, "INSERT INTO recordings(project_id, source_file_id, native_recording_id) " + ...
        "VALUES (1, " + string(index + 1) + ", 'REC_" + string(index) + "')");
end
end

function tearDown(conn, dbFile, sourcePath)
if isopen(conn)
    close(conn);
end
if isfile(dbFile)
    delete(dbFile);
end
rmpath(sourcePath);
end

function seedTimebases(conn)
%SEEDTIMEBASES Clocks 1 and 2 are recording-scoped; 3 and 4 are project-scoped.
execute(conn, insertTimebase("audio_native", 1, 1));
execute(conn, insertTimebase("video_native", 1, 0));
execute(conn, "INSERT INTO timebases(project_id, timebase_name, timebase_kind) " + ...
    "VALUES (1, 'neural_native', 'acquisition_clock')");
execute(conn, "INSERT INTO timebases(project_id, timebase_name, timebase_kind) " + ...
    "VALUES (1, 'operant_clock', 'controller_clock')");
end

function seedStream(conn)
%SEEDSTREAM One event stream on clock 1. Call seedTimebases first.
execute(conn, insertStream("behaviour", 1, 1));
end

% ------------------------------------------------------- statement builders ---

function sql = insertTimebase(name, recordingId, isNative)
sql = "INSERT INTO timebases(project_id, recording_id, timebase_name, " + ...
    "timebase_kind, is_recording_native) VALUES (1, " + string(recordingId) + ...
    ", '" + name + "', 'acquisition_clock', " + string(isNative) + ")";
end

function sql = insertStream(name, recordingId, timebaseId)
sql = "INSERT INTO external_streams(project_id, recording_id, timebase_id, " + ...
    "stream_name, stream_kind) VALUES (1, " + string(recordingId) + ", " + ...
    string(timebaseId) + ", '" + name + "', 'event')";
end

function sql = insertCoverage(segmentIndex, startTime, endTime)
sql = "INSERT INTO external_stream_coverage(external_stream_id, segment_index, " + ...
    "start_time_native, end_time_native) VALUES (1, " + string(segmentIndex) + ...
    ", " + string(startTime) + ", " + string(endTime) + ")";
end

function sql = insertAnalysisRun(runKey)
sql = "INSERT INTO analysis_runs(project_id, run_type, run_key) " + ...
    "VALUES (1, 'external_time_alignment', '" + runKey + "')";
end

function sql = insertAlignmentSet(analysisRunId, referenceTimebaseId)
sql = "INSERT INTO alignment_sets(analysis_run_id, reference_timebase_id) " + ...
    "VALUES (" + string(analysisRunId) + ", " + string(referenceTimebaseId) + ")";
end

function sql = insertAnchor(alignmentSetId, anchorKey)
sql = "INSERT INTO alignment_anchors(alignment_set_id, anchor_key, anchor_type) " + ...
    "VALUES (" + string(alignmentSetId) + ", '" + anchorKey + "', 'ttl_pulse')";
end

function sql = insertObservation(anchorId, timebaseId, observedTime, role, included)
sql = "INSERT INTO alignment_anchor_observations(alignment_anchor_id, timebase_id, " + ...
    "observed_time_native, observation_role, included_in_fit) VALUES (" + ...
    string(anchorId) + ", " + string(timebaseId) + ", " + string(observedTime) + ...
    ", '" + role + "', " + string(included) + ")";
end

function sql = insertRun(alignmentSetId, sourceTimebaseId, targetTimebaseId, method)
sql = "INSERT INTO time_alignment_runs(alignment_set_id, source_timebase_id, " + ...
    "target_timebase_id, method) VALUES (" + string(alignmentSetId) + ", " + ...
    string(sourceTimebaseId) + ", " + string(targetTimebaseId) + ", '" + method + "')";
end

function sql = insertResidual(runId, anchorId, sourceObs, referenceObs, ...
        sourceTime, referenceTime, predicted, residual)
sql = "INSERT INTO alignment_anchor_residuals(alignment_run_id, alignment_anchor_id, " + ...
    "source_observation_id, reference_observation_id, observed_source_time, " + ...
    "observed_reference_time, predicted_reference_time, residual_s) VALUES (" + ...
    string(runId) + ", " + string(anchorId) + ", " + string(sourceObs) + ", " + ...
    string(referenceObs) + ", " + string(sourceTime) + ", " + string(referenceTime) + ...
    ", " + string(predicted) + ", " + string(residual) + ")";
end

% ----------------------------------------------------------------- helpers ---

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function value = scalarText(conn, sql)
rows = fetch(conn, sql);
column = rows.(rows.Properties.VariableNames{1});
if iscell(column)
    value = string(column{1});
else
    value = string(column(1));
end
end

function verifySqlFails(testCase, conn, sql)
didFail = false;
try
    execute(conn, sql);
catch
    didFail = true;
end
verifyTrue(testCase, didFail, "Expected SQL to be rejected: " + sql);
end

function repoRoot = repoRootForTest()
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
