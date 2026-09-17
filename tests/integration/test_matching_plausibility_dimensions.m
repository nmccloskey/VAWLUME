function tests = test_matching_plausibility_dimensions
%TEST_MATCHING_PLAUSIBILITY_DIMENSIONS Optional magnitude bounds on candidate evidence.
%
% The matching specification may declare max_abs_onset_difference_s,
% max_abs_offset_difference_s, and max_abs_duration_difference_s beside
% min_temporal_iou. Each is optional; absent means unconstrained. Each bounds
% the magnitude of a signed field vawlume.interval.relation already returns, so
% no second definition of onset, offset, or duration difference exists.
%
% Every gate test observes the same pair excluded and then, with the bound
% relaxed, admitted. A gate test that passed only because no pair sat near the
% boundary would prove nothing.
tests = functiontests(localfunctions);
end

% ------------------------------------------------- specification validation ---

function testEachDimensionIsAcceptedAtItsBounds(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

zeroBounds = planWithRule(fixture, "zero-bounds", ...
    ["max_abs_onset_difference_s", "max_abs_offset_difference_s", ...
    "max_abs_duration_difference_s"], [0, 0, 0]);
verifyEqual(testCase, zeroBounds.status, "planned");
verifyEqual(testCase, zeroBounds.candidate_count, 0);
verifyEqual(testCase, zeroBounds.plausibility_rule.max_abs_onset_difference_s, 0);

wideBounds = planWithRule(fixture, "wide-bounds", ...
    ["max_abs_onset_difference_s", "max_abs_offset_difference_s", ...
    "max_abs_duration_difference_s"], [1e6, 1e6, 1e6]);
verifyEqual(testCase, wideBounds.candidate_count, 3);

clear cleanup
end

function testOmittingEveryDimensionLoadsAndLeavesThemUnconstrained(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planNominal(fixture, "omitted-v1");

verifyEqual(testCase, result.status, "planned");
verifyEqual(testCase, result.candidate_count, 3);
rule = result.plausibility_rule;
verifyEqual(testCase, rule.min_temporal_iou, .10, AbsTol=1e-15);
verifyTrue(testCase, isnan(rule.max_abs_onset_difference_s));
verifyTrue(testCase, isnan(rule.max_abs_offset_difference_s));
verifyTrue(testCase, isnan(rule.max_abs_duration_difference_s));

clear cleanup
end

function testEachDimensionIsRejectedWithItsOwnIdentifier(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
cases = [
    struct(field="max_abs_onset_difference_s", ...
        identifier="vawlume:matching:MaxAbsOnsetDifferenceInvalid")
    struct(field="max_abs_offset_difference_s", ...
        identifier="vawlume:matching:MaxAbsOffsetDifferenceInvalid")
    struct(field="max_abs_duration_difference_s", ...
        identifier="vawlume:matching:MaxAbsDurationDifferenceInvalid")
    ];
% Negative; non-finite (1e999 decodes to Inf); text; logical; non-scalar; null.
literals = ["-0.01"; "1e999"; """0.01"""; "true"; "[0.01, 0.02]"; "null"];

for index = 1:numel(cases)
    for literalIndex = 1:numel(literals)
        path = writeRuleVariant(fixture, ...
            sprintf("invalid-%d-%d.json", index, literalIndex), ...
            cases(index).field, literals(literalIndex));
        verifyError(testCase, @() vawlume.matching.compare(fixture.conn, ...
            recordingRef(), nominalPair(), ...
            struct(run_key="invalid-v1", profile_path=path), ...
            RepoRoot=fixture.repo_root), cases(index).identifier, ...
            cases(index).field + " = " + literals(literalIndex));
    end
end

clear cleanup
end

% -------------------------------------------------------------- enforcement ---

function testOnsetBoundExcludesThenAdmitsTheSamePairForItsOwnReason(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Pair (1, 4) carries onset +.004 s, offset +.002 s, duration -.002 s and
% temporal_iou .885, so only the onset bound can reach it.
strict = planWithRule(fixture, "onset-strict", ...
    "max_abs_onset_difference_s", .0035);
verifyEqual(testCase, pairPresent(strict, 1, 4), false);
verifyEqual(testCase, strict.candidate_count, 1);

relaxed = planWithRule(fixture, "onset-relaxed", ...
    "max_abs_onset_difference_s", .0045);
verifyEqual(testCase, pairPresent(relaxed, 1, 4), true);
verifyEqual(testCase, relaxed.candidate_count, 2);

unbounded = planNominal(fixture, "onset-unbounded");
verifyEqual(testCase, unbounded.candidate_count, 3);

clear cleanup
end

function testOffsetBoundExcludesThenAdmitsTheSamePairForItsOwnReason(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Pair (3, 6) carries offset -.055 s while its onset is +.002 s, so with only
% the offset bound declared the exclusion cannot come from anywhere else.
strict = planWithRule(fixture, "offset-strict", ...
    "max_abs_offset_difference_s", .0300);
verifyEqual(testCase, pairPresent(strict, 3, 6), false);
verifyEqual(testCase, strict.candidate_count, 2);

relaxed = planWithRule(fixture, "offset-relaxed", ...
    "max_abs_offset_difference_s", .0600);
verifyEqual(testCase, pairPresent(relaxed, 3, 6), true);
verifyEqual(testCase, relaxed.candidate_count, 3);

clear cleanup
end

function testDurationBoundExcludesThenAdmitsTheSamePairForItsOwnReason(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Pair (3, 7) carries duration -.054 s while its offset is -.002 s.
strict = planWithRule(fixture, "duration-strict", ...
    "max_abs_duration_difference_s", .0300);
verifyEqual(testCase, pairPresent(strict, 3, 7), false);
verifyEqual(testCase, strict.candidate_count, 1);

relaxed = planWithRule(fixture, "duration-relaxed", ...
    "max_abs_duration_difference_s", .0600);
verifyEqual(testCase, pairPresent(relaxed, 3, 7), true);
verifyEqual(testCase, relaxed.candidate_count, 3);

clear cleanup
end

function testEqualMagnitudesOfOppositeSignAreTreatedIdentically(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
insertMirroredPairs(fixture.conn);

% Four pairs: onset +.005/-.005 with zero duration difference, and duration
% +.040/-.040 with zero offset difference. Each bound must move both members of
% a mirrored couple across the boundary together.
unbounded = planMirrored(fixture, "mirror-unbounded", strings(0, 1), []);
verifyEqual(testCase, unbounded.candidate_count, 4);
verifyEqual(testCase, sort(abs(unbounded.candidates.onset_difference_s)), ...
    [.005; .005; .040; .040], AbsTol=1e-9);
verifyEqual(testCase, sort(abs(unbounded.candidates.duration_difference_s)), ...
    [0; 0; .040; .040], AbsTol=1e-9);

onsetStrict = planMirrored(fixture, "mirror-onset-strict", ...
    "max_abs_onset_difference_s", .0045);
verifyEqual(testCase, onsetStrict.candidate_count, 0);
onsetRelaxed = planMirrored(fixture, "mirror-onset-relaxed", ...
    "max_abs_onset_difference_s", .0060);
verifyEqual(testCase, onsetRelaxed.candidate_count, 2);
verifyEqual(testCase, sort(onsetRelaxed.candidates.onset_difference_s), ...
    [-.005; .005], AbsTol=1e-9);

offsetStrict = planMirrored(fixture, "mirror-offset-strict", ...
    "max_abs_offset_difference_s", .0045);
verifyEqual(testCase, offsetStrict.candidate_count, 2);
verifyEqual(testCase, sort(offsetStrict.candidates.offset_difference_s), ...
    [0; 0], AbsTol=1e-9);

durationStrict = planMirrored(fixture, "mirror-duration-strict", ...
    "max_abs_duration_difference_s", .0300);
verifyEqual(testCase, durationStrict.candidate_count, 2);
verifyEqual(testCase, sort(durationStrict.candidates.duration_difference_s), ...
    [0; 0], AbsTol=1e-9);
durationRelaxed = planMirrored(fixture, "mirror-duration-relaxed", ...
    "max_abs_duration_difference_s", .0500);
verifyEqual(testCase, durationRelaxed.candidate_count, 4);
verifyEqual(testCase, sort(durationRelaxed.candidates.duration_difference_s), ...
    [-.040; 0; 0; .040], AbsTol=1e-9);

clear cleanup
end

function testBoundsOnlyRemoveCandidatesTheUnboundedRuleAdmits(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
insertMirroredPairs(fixture.conn);
unbounded = planMirrored(fixture, "subset-unbounded", strings(0, 1), []);
reference = pairKeys(unbounded);

bounded = planMirrored(fixture, "subset-bounded", ...
    ["max_abs_onset_difference_s", "max_abs_duration_difference_s"], ...
    [.0060, .0300]);
verifyTrue(testCase, all(ismember(pairKeys(bounded), reference)));
verifyLessThan(testCase, bounded.candidate_count, unbounded.candidate_count);

clear cleanup
end

% ------------------------------------------------------ stored gate evidence ---

function testIouOnlyDetailsAreByteIdenticalToTheEarlierContract(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planNominal(fixture, "details-iou-only");

for index = 1:height(result.candidates)
    detail = jsondecode(result.candidates.details_json(index));
    verifyEqual(testCase, string(fieldnames(detail))', ...
        ["evidence_direction", "run_a_extraction_run_id", ...
        "run_b_extraction_run_id", "run_a_detection_id", "run_b_detection_id", ...
        "schema_detection_order", "eligibility_rule", "min_temporal_iou"]);
    verifyTrue(testCase, endsWith(result.candidates.details_json(index), ...
        """eligibility_rule"":""positive_overlap_and_min_temporal_iou""," + ...
        """min_temporal_iou"":0.1}"));
end

clear cleanup
end

function testDeclaredGatesAreRecordedWithTheirValues(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = planWithRule(fixture, "details-bounded", ...
    ["max_abs_onset_difference_s", "max_abs_duration_difference_s"], ...
    [.0600, .0600]);
verifyEqual(testCase, result.candidate_count, 3);

detail = jsondecode(result.candidates.details_json(1));
verifyEqual(testCase, string(detail.eligibility_rule), ...
    "positive_overlap_and_min_temporal_iou_and_max_abs_onset_difference_s" + ...
    "_and_max_abs_duration_difference_s");
verifyEqual(testCase, detail.min_temporal_iou, .10, AbsTol=1e-15);
verifyEqual(testCase, detail.max_abs_onset_difference_s, .0600, AbsTol=1e-15);
verifyEqual(testCase, detail.max_abs_duration_difference_s, .0600, AbsTol=1e-15);
verifyFalse(testCase, isfield(detail, "max_abs_offset_difference_s"));
verifyEqual(testCase, string(fieldnames(detail))', ...
    ["evidence_direction", "run_a_extraction_run_id", ...
    "run_b_extraction_run_id", "run_a_detection_id", "run_b_detection_id", ...
    "schema_detection_order", "eligibility_rule", "min_temporal_iou", ...
    "max_abs_onset_difference_s", "max_abs_duration_difference_s"]);

clear cleanup
end

function testPersistedRowsCarryTheActiveGateRecord(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
path = ruleVariantPath(fixture, "persisted-bounded", ...
    "max_abs_onset_difference_s", .0600);
result = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key="persisted-bounded", profile_path=path), ...
    RepoRoot=fixture.repo_root, Apply=true);
verifyEqual(testCase, result.status, "committed");

stored = fetch(fixture.conn, "SELECT details_json FROM candidate_pairs " + ...
    "WHERE analysis_run_id=" + string(result.analysis.analysis_run_id) + ...
    " ORDER BY detection_a_id, detection_b_id");
verifyEqual(testCase, height(stored), 3);
for index = 1:height(stored)
    detail = jsondecode(string(stored.details_json(index)));
    verifyEqual(testCase, string(detail.eligibility_rule), ...
        "positive_overlap_and_min_temporal_iou_and_max_abs_onset_difference_s");
    verifyEqual(testCase, detail.max_abs_onset_difference_s, .06, AbsTol=1e-15);
end

clear cleanup
end

% ------------------------------------------------------ checksum consequence ---

function testChangingANewFieldChangesTheSpecificationChecksum(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
baseline = planNominal(fixture, "checksum-baseline");
declared = planWithRule(fixture, "checksum-declared", ...
    "max_abs_onset_difference_s", .0500);
nudged = planWithRule(fixture, "checksum-nudged", ...
    "max_abs_onset_difference_s", .0501);

verifyEqual(testCase, strlength(baseline.configuration.checksum_sha256), 64);
verifyNotEqual(testCase, declared.configuration.checksum_sha256, ...
    baseline.configuration.checksum_sha256);
verifyNotEqual(testCase, nudged.configuration.checksum_sha256, ...
    declared.configuration.checksum_sha256);

clear cleanup
end

function testANewFieldMakesAStoredAnalysisIdentityIncompatible(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
applied = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key="identity-v1"), RepoRoot=fixture.repo_root, Apply=true);
verifyEqual(testCase, applied.status, "committed");
before = countOf(fixture.conn, "candidate_pairs");

path = ruleVariantPath(fixture, "identity-conflict", ...
    "max_abs_onset_difference_s", .0500);
conflict = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key="identity-v1", profile_path=path), ...
    RepoRoot=fixture.repo_root, Apply=true);
verifyEqual(testCase, conflict.status, "conflict");
verifyFalse(testCase, conflict.committed);
verifyEqual(testCase, countOf(fixture.conn, "candidate_pairs"), before);

clear cleanup
end

function testTrackedBaseSpecificationDeclaresNoneOfTheNewDimensions(testCase)
% Part 2 deliberately left the tracked specification byte-unchanged: it is
% Part 11's reference configuration, and adding a field would change its
% checksum and so the identity of every analysis already recorded against it.
repoRoot = repoRootPath();
text = string(fileread(fullfile(repoRoot, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json")));
for field = ["max_abs_onset_difference_s", "max_abs_offset_difference_s", ...
        "max_abs_duration_difference_s"]
    verifyFalse(testCase, contains(text, field), field);
end
end

% ---------------------------------------------------------------- helpers ---

function insertMirroredPairs(conn)
% Run 3 (ds-2) against run 5 (other-1); both are empty in the base fixture.
intervalsA = [100.000 100.100; 200.000 200.100; 300.000 300.100; 400.000 400.100];
intervalsB = [100.005 100.105; 199.995 200.095; 299.960 300.100; 400.040 400.100];
for index = 1:height(intervalsA)
    insertDetection(conn, 3, 1, "mirror-a-" + index, ...
        intervalsA(index, 1), intervalsA(index, 2));
    insertDetection(conn, 5, 1, "mirror-b-" + index, ...
        intervalsB(index, 1), intervalsB(index, 2));
end
end

function result = planMirrored(fixture, name, fields, values)
path = ruleVariantPath(fixture, name, fields, values);
result = vawlume.matching.compare(fixture.conn, recordingRef(), ...
    struct(run_a="ds-2", run_b="other-1"), ...
    struct(run_key=name, profile_path=path), RepoRoot=fixture.repo_root);
end

function result = planWithRule(fixture, name, fields, values)
path = ruleVariantPath(fixture, name, fields, values);
result = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key=name, profile_path=path), RepoRoot=fixture.repo_root);
end

function path = ruleVariantPath(fixture, name, boundFields, values)
if isempty(boundFields)
    path = "";
    return
end
literals = strings(numel(boundFields), 1);
for index = 1:numel(boundFields)
    literals(index) = string(sprintf("%.17g", values(index)));
end
path = writeRuleVariant(fixture, name + ".json", boundFields, literals);
end

function path = writeRuleVariant(fixture, name, boundFields, literals)
%WRITERULEVARIANT Add plausibility-rule fields to a copy of the tracked spec.
%
% BOUNDFIELDS names the fields and LITERALS carries their raw JSON value text,
% so a test can supply a malformed value as easily as a valid number. Writing a
% variant rather than editing the tracked specification keeps Part 11's
% reference configuration byte-unchanged.
%
% Several lines carry min_temporal_iou; only the first lies inside
% candidate_generation.plausibility_rule, and the assertion proves that rather
% than trusting it. Matching on the value alone keeps this independent of the
% checkout's line endings.
text = string(fileread(fullfile(fixture.repo_root, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json")));
anchor = """min_temporal_iou"": 0.10";
at = strfind(text, anchor);
ruleAt = strfind(text, """plausibility_rule""");
afterRuleAt = strfind(text, """excluded_evidence""");
assert(~isempty(at) && at(1) > ruleAt(1) && at(1) < afterRuleAt(1));
eol = newline;
if contains(text, string(char(13)) + newline)
    eol = string(char(13)) + newline;
end
addition = anchor;
for index = 1:numel(boundFields)
    addition = addition + "," + eol + "      """ + boundFields(index) + ...
        """: " + literals(index);
end
text = extractBefore(text, at(1)) + addition + ...
    extractAfter(text, at(1) + strlength(anchor) - 1);
path = fullfile(fixture.scratch, name);
fileId = fopen(path, "w");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function value = pairPresent(result, runAId, runBId)
value = any(result.candidates.run_a_detection_id == runAId & ...
    result.candidates.run_b_detection_id == runBId);
end

function keys = pairKeys(result)
keys = string(result.candidates.run_a_detection_id) + "-" + ...
    string(result.candidates.run_b_detection_id);
end

function result = planNominal(fixture, runKey)
result = vawlume.matching.compare(fixture.conn, recordingRef(), nominalPair(), ...
    struct(run_key=runKey), RepoRoot=fixture.repo_root);
end

function ref = recordingRef()
ref = struct(recording_id=1);
end

function pair = nominalPair()
pair = struct(run_a="ds-1", run_b="mupet-1");
end

function insertDetection(conn, runId, recordingId, nativeId, startS, endS)
execute(conn, "INSERT INTO detections(extraction_run_id,recording_id," + ...
    "native_event_id,start_time_s,end_time_s,timing_basis) VALUES(" + ...
    string(runId) + "," + string(recordingId) + "," + sqlText(nativeId) + ...
    "," + sprintf("%.17g", startS) + "," + sprintf("%.17g", endS) + ...
    ",'profile_selected_event_geometry')");
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "plausibility.sqlite");
conn = sqlite(char(dbPath), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'project-a','Project A')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path,filename) VALUES" + ...
    "(1,1,'recording_audio','audio/rec1.wav','audio/rec1.wav','rec1.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'REC1')");
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key,extractor_name) " + ...
    "VALUES(1,'deepsqueak','DeepSqueak'),(2,'mupet','MUPET')," + ...
    "(3,'other','Other Extractor')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id,extractor_id," + ...
    "version_label) VALUES(1,1,'3.2.1'),(2,2,'2.1'),(3,3,'1.0')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key,status) VALUES" + ...
    "(1,1,1,'ds-1','imported'),(2,1,2,'mupet-1','imported')," + ...
    "(3,1,1,'ds-2','imported'),(5,1,3,'other-1','imported')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id,recording_id," + ...
    "input_role) VALUES(1,1,'source_audio'),(2,1,'source_audio')," + ...
    "(3,1,'source_audio'),(5,1,'source_audio')");

insertDetection(conn, 1, 1, "ds-1", 10.000, 10.050);
insertDetection(conn, 1, 1, "ds-2", 20.000, 20.040);
insertDetection(conn, 1, 1, "ds-3", 40.000, 40.100);
insertDetection(conn, 2, 1, "mupet-1", 10.004, 10.052);
insertDetection(conn, 2, 1, "mupet-2", 30.000, 30.035);
insertDetection(conn, 2, 1, "mupet-3", 40.002, 40.045);
insertDetection(conn, 2, 1, "mupet-4", 40.052, 40.098);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch);
end

function tearDown(conn, scratch, repoRoot)
try close(conn); catch; end
if isfolder(scratch), rmdir(scratch, "s"); end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
