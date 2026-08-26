function tests = test_phase1_acceptance_queries
tests = functiontests({@testPhase1AcceptanceQueriesAssertLogicalResults});
end

function testPhase1AcceptanceQueriesAssertLogicalResults(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createFixtureDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

queryFile = fullfile(repoRoot, "schema", "fixtures", "phase1_acceptance_queries.sql");
blocks = loadQueryBlocks(queryFile);
verifyEqual(testCase, numel(blocks), 14);

results = struct();
for index = 1:numel(blocks)
    block = blocks(index);
    rows = fetch(conn, block.sql);
    verifyEqual(testCase, height(rows), expectedRowCount(block.id), block.id + " row count");
    results.(block.id) = rows;
end

verifyDetectionRunQuery(testCase, results.Q01);
verifySharedRecordingQuery(testCase, results.Q02);
verifyFeatureRegistryQueries(testCase, results.Q03, results.Q04);
verifyProfileAndParticipantQueries(testCase, results.Q05, results.Q06);
verifyScopedNativeIdQuery(testCase, results.Q07);
verifyCandidateAndMembershipQueries(testCase, results.Q08, results.Q09, results.Q10);
verifyMeasurementQuery(testCase, results.Q11);
verifyAlignmentAndReviewQueries(testCase, results.Q12, results.Q13);
verifyProvenanceQuery(testCase, results.Q14);

clear cleanupPath cleanupDb
end

function verifyDetectionRunQuery(testCase, rows)
runs = textColumn(rows, "extraction_run_key");
verifyEqual(testCase, sum(runs == "fixture_deepsqueak_social_v1"), 3);
verifyEqual(testCase, sum(runs == "fixture_mupet_social_v1"), 4);
verifyEqual(testCase, sum(runs == "fixture_deepsqueak_baseline_v1"), 1);
verifyTrue(testCase, any(runs == "fixture_mupet_social_v1" & textColumn(rows, "native_event_id") == "4"));
end

function verifySharedRecordingQuery(testCase, rows)
verifyEqual(testCase, textColumn(rows, "native_recording_id"), "REC_SOCIAL_DYAD_01");
verifyEqual(testCase, numberColumn(rows, "deepsqueak_run_count"), 1);
verifyEqual(testCase, numberColumn(rows, "mupet_run_count"), 1);
verifyFalse(testCase, any(contains(textColumn(rows, "native_recording_id"), "BASELINE")));
end

function verifyFeatureRegistryQueries(testCase, featureRows, relationshipRows)
verifyEqual(testCase, sum(textColumn(featureRows, "extractor_name") == "DeepSqueak"), 14);
verifyEqual(testCase, sum(textColumn(featureRows, "extractor_name") == "MUPET"), 12);
verifyTrue(testCase, any(textColumn(featureRows, "native_name") == "Principle Frequency (kHz)" & ...
    textColumn(featureRows, "canonical_name") == "contour_median_frequency" & ...
    textColumn(featureRows, "transform_key") == "kHz_to_Hz"));
verifyTrue(testCase, any(textColumn(featureRows, "native_name") == "syllable duration (msec)" & ...
    textColumn(featureRows, "canonical_name") == "call_duration" & ...
    textColumn(featureRows, "transform_key") == "ms_to_s"));

eligible = numberColumn(relationshipRows, "consilience_eligible");
verifyEqual(testCase, sum(eligible == 1), 7);
verifyEqual(testCase, sum(eligible == 0 & textColumn(relationshipRows, "relationship_type") == "related"), 2);
end

function verifyProfileAndParticipantQueries(testCase, profileRows, participantRows)
verifyEqual(testCase, sum(textColumn(profileRows, "assignment_role") == "recording_device"), 2);
verifyEqual(testCase, sum(textColumn(profileRows, "assignment_role") == "experimental_setup"), 2);
verifyTrue(testCase, all(strlength(textColumn(profileRows, "checksum_sha256")) == 64));

roles = textColumn(participantRows, "role_label");
verifyEqual(testCase, sort(roles), sort(["dyad"; "female"; "male"; "session"]));
verifyEqual(testCase, sum(textColumn(participantRows, "entity_type") == "subject"), 2);
end

function verifyScopedNativeIdQuery(testCase, rows)
ids = textColumn(rows, "native_event_id");
verifyEqual(testCase, sum(ids == "1"), 3);
verifyEqual(testCase, sum(ids == "2"), 2);
verifyEqual(testCase, sum(ids == "3"), 2);
verifyTrue(testCase, all(strlength(textColumn(rows, "source_artifact_uri")) > 0));
end

function verifyCandidateAndMembershipQueries(testCase, candidateRows, membershipRows, splitRows)
verifyTrue(testCase, all(numberColumn(candidateRows, "same_recording_rule_ok") == 1));
verifyTrue(testCase, all(numberColumn(candidateRows, "different_run_rule_ok") == 1));

verifyEqual(testCase, sum(textColumn(membershipRows, "membership_layer") == "match_group"), 7);
verifyEqual(testCase, sum(textColumn(membershipRows, "membership_layer") == "consensus_event"), 5);

verifyEqual(testCase, numel(unique(numberColumn(splitRows, "match_group_id"))), 1);
verifyTrue(testCase, all(textColumn(splitRows, "match_type") == "one_to_many"));
verifyEqual(testCase, sum(textColumn(splitRows, "extractor_name") == "DeepSqueak"), 1);
verifyEqual(testCase, sum(textColumn(splitRows, "extractor_name") == "MUPET"), 2);
verifyTrue(testCase, any(textColumn(splitRows, "extractor_name") == "DeepSqueak" & textColumn(splitRows, "native_event_id") == "3"));
verifyTrue(testCase, any(textColumn(splitRows, "extractor_name") == "MUPET" & textColumn(splitRows, "native_event_id") == "4"));
end

function verifyMeasurementQuery(testCase, rows)
extractors = textColumn(rows, "extractor_name");
nativeNames = textColumn(rows, "native_name");
nativeIds = textColumn(rows, "native_event_id");

dsLow = extractors == "DeepSqueak" & nativeIds == "1" & nativeNames == "Low Freq (kHz)";
verifyClose(testCase, singleNumber(rows, "native_value_real", dsLow), 45.1, 1e-9);
verifyClose(testCase, singleNumber(rows, "canonical_value_real", dsLow), 45100, 1e-6);

mupetDuration = extractors == "MUPET" & nativeIds == "1" & nativeNames == "syllable duration (msec)";
verifyClose(testCase, singleNumber(rows, "native_value_real", mupetDuration), 48, 1e-9);
verifyClose(testCase, singleNumber(rows, "canonical_value_real", mupetDuration), 0.048, 1e-12);
verifyEqual(testCase, textColumn(rows(mupetDuration, :), "operational_variant"), "pre_noise_reduction");

missingInterval = extractors == "MUPET" & nativeIds == "4" & nativeNames == "inter-syllable interval (sec)";
verifyEqual(testCase, textColumn(rows(missingInterval, :), "native_raw_token"), "NA");
verifyEqual(testCase, textColumn(rows(missingInterval, :), "canonical_value_real"), "");
end

function verifyAlignmentAndReviewQueries(testCase, alignmentRows, reviewRows)
verifyTrue(testCase, all(abs(numberColumn(alignmentRows, "start_offset_s") - 0.55) < 1e-9));
verifyEqual(testCase, sort(textColumn(alignmentRows, "event_type")), sort(["male_approach"; "social_contact"]));

verifyTrue(testCase, any(textColumn(reviewRows, "review_target_type") == "detection" & ...
    textColumn(reviewRows, "manual_review_status") == "adjudicated_false_positive" & ...
    textColumn(reviewRows, "extractor_status_after") == "Accepted"));
verifyTrue(testCase, any(textColumn(reviewRows, "review_target_type") == "match_group" & ...
    contains(textColumn(reviewRows, "match_type_or_derivation"), "one_to_many")));
verifyTrue(testCase, any(textColumn(reviewRows, "review_target_type") == "consensus_event"));
end

function verifyProvenanceQuery(testCase, rows)
verifyEqual(testCase, sort(textColumn(rows, "extractor_name")), sort(["DeepSqueak"; "MUPET"]));
verifyEqual(testCase, unique(textColumn(rows, "native_recording_id")), "REC_SOCIAL_DYAD_01");
verifyTrue(testCase, all(strlength(textColumn(rows, "output_mapping_profile_checksum")) == 64));
verifyTrue(testCase, all(contains(textColumn(rows, "acquisition_profile_context"), "recording_device")));
verifyTrue(testCase, all(contains(textColumn(rows, "acquisition_profile_context"), "experimental_setup")));
end

function n = expectedRowCount(blockId)
switch string(blockId)
    case "Q01"
        n = 8;
    case "Q02"
        n = 1;
    case "Q03"
        n = 26;
    case "Q04"
        n = 9;
    case "Q05"
        n = 4;
    case "Q06"
        n = 4;
    case "Q07"
        n = 7;
    case "Q08"
        n = 3;
    case "Q09"
        n = 12;
    case "Q10"
        n = 3;
    case "Q11"
        n = 10;
    case "Q12"
        n = 2;
    case "Q13"
        n = 3;
    case "Q14"
        n = 2;
    otherwise
        error("vawlume:test:UnknownAcceptanceQuery", "No expected row count for %s.", blockId);
end
end

function blocks = loadQueryBlocks(queryFile)
lines = splitlines(string(fileread(queryFile)));
blocks = struct("id", {}, "title", {}, "lines", {}, "sql", {});
currentIndex = 0;

for index = 1:numel(lines)
    trimmed = strtrim(lines(index));
    tokens = regexp(char(trimmed), '^-- Q(\d{2}) - (.+)$', 'tokens', 'once');
    if ~isempty(tokens)
        currentIndex = currentIndex + 1;
        blocks(currentIndex).id = "Q" + string(tokens{1}); %#ok<AGROW>
        blocks(currentIndex).title = string(tokens{2}); %#ok<AGROW>
        blocks(currentIndex).lines = strings(0, 1); %#ok<AGROW>
        blocks(currentIndex).sql = ""; %#ok<AGROW>
    elseif currentIndex > 0
        blocks(currentIndex).lines(end + 1, 1) = lines(index);
    end
end

for index = 1:numel(blocks)
    sqlLines = blocks(index).lines;
    trimmed = strtrim(sqlLines);
    sqlLines = sqlLines(strlength(trimmed) > 0 & ~startsWith(trimmed, "--"));
    sql = strjoin(sqlLines, newline);
    sql = regexprep(sql, ";\s*$", "");
    blocks(index).sql = sql;
end
end

function values = textColumn(rows, variableName)
values = string(rows.(char(variableName)));
values = values(:);
values(ismissing(values)) = "";
end

function values = numberColumn(rows, variableName)
values = str2double(textColumn(rows, variableName));
end

function value = singleNumber(rows, variableName, mask)
values = numberColumn(rows, variableName);
values = values(mask);
if numel(values) ~= 1
    error("vawlume:test:SingleValueExpected", "Expected one value for %s, found %d.", variableName, numel(values));
end
value = values(1);
end

function verifyClose(testCase, actual, expected, tolerance)
verifyLessThanOrEqual(testCase, abs(actual - expected), tolerance);
end

function [conn, dbFile] = createFixtureDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
[conn, ~] = vawlume.db.createPhase1FixtureDatabase(dbFile, repoRoot);
end

function cleanupDatabase(conn, dbFile)
if isopen(conn)
    close(conn);
end
deleteIfExists(dbFile);
deleteIfExists(dbFile + "-journal");
deleteIfExists(dbFile + "-wal");
deleteIfExists(dbFile + "-shm");
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
