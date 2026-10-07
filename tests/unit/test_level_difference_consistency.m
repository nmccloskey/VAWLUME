function tests = test_level_difference_consistency
%TEST_LEVEL_DIFFERENCE_CONSISTENCY Phase 6.8: the native method and its settings profile.
%
% Pure tests: no database. The scene is microphones a at (0,0) and b at (100,0),
% in cm, and two candidates. Distances are computed here, in the test, from those
% positions; the method only ever sees the distances.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = repositoryRoot();
addpath(fullfile(root, "src"));
testCase.TestData.root = root;
testCase.TestData.settings = vawlume.estimator.loadSettings(RepoRoot=root);
testCase.TestData.shipped = jsondecode(fileread(fullfile(root, "config", ...
    "10_estimator_settings", "native_level_difference_estimator_v1.json")));
testCase.TestData.scratch = string(tempname);
mkdir(testCase.TestData.scratch);
end

function teardownOnce(testCase)
if isfolder(testCase.TestData.scratch)
    rmdir(testCase.TestData.scratch, "s");
end
rmpath(fullfile(testCase.TestData.root, "src"));
end

% ------------------------------------------------------------- settings ---

function testTheShippedProfileStatesTheFiveConditions(testCase)
s = testCase.TestData.settings;
verifyEqual(testCase, s.profile_kind, "attribution_estimator_settings");
verifyEqual(testCase, [s.method_key s.method_version], ...
    ["vawlume.estimator.level_difference_consistency" "1.0.0"]);
verifyEqual(testCase, s.declared_inputs.input_dimension, ...
    ["temporal_alignment"; "pose_localization"; "visual_identity"; "acoustic"]);
verifyEqual(testCase, s.declared_inputs.declaration, repmat("used", 4, 1));
verifyTrue(testCase, all(strlength(s.declared_inputs.notes) > 0), "Every dimension has its role.");
verifyEqual(testCase, s.dimensions.source_localization.declaration, "not_used");
verifyEqual(testCase, s.score.what_this_is_not(1), "not a probability");
verifyEqual(testCase, s.scaling.comparability_scope, "within_recording");
verifyEqual(testCase, s.calibration_status.state, "uncalibrated");
verifyEqual(testCase, s.parameters.channel_pair, [1 2]);
verifyEqual(testCase, s.parameters.primary_instant_basis, "midpoint");
verifyEmpty(testCase, s.parameters.pose_confidence_gate);
verifyEqual(testCase, strlength(s.checksum_sha256), 64);
verifyEqual(testCase, s.content_uri, ...
    "config/10_estimator_settings/native_level_difference_estimator_v1.json");
end

function testEachRequiredBlockIsRefusedByNameWhenRemoved(testCase)
for block = ["profile", "method", "scope", "dimensions", "score", "scaling", ...
        "readability", "calibration_status", "parameters"]
    path = writeProfile(testCase, rmfield(testCase.TestData.shipped, block), block);
    verifyErrorNaming(testCase, path, "vawlume:estimator:SettingsBlockMissing", block);
end
end

function testAnUndeclaredDimensionIsRefused(testCase)
for dimension = ["temporal_alignment", "pose_localization", "visual_identity", ...
        "acoustic", "source_localization"]
    document = testCase.TestData.shipped;
    document.dimensions = rmfield(document.dimensions, dimension);
    path = writeProfile(testCase, document, "no-" + dimension);
    verifyErrorNaming(testCase, path, "vawlume:estimator:SettingsDimensionUndeclared", dimension);
end
end

function testAMissingParameterIsRefusedNotDefaulted(testCase)
for parameter = string(fieldnames(testCase.TestData.shipped.parameters))'
    document = testCase.TestData.shipped;
    document.parameters = rmfield(document.parameters, parameter);
    path = writeProfile(testCase, document, "no-" + parameter);
    verifyErrorNaming(testCase, path, "vawlume:estimator:SettingsParameterMissing", parameter);
end
end

function testClaimsThisVersionCannotSupportAreRefused(testCase)
cases = {
    @(d) setfield(d, "calibration_status", setfield(d.calibration_status, "state", "calibrated"))
    @(d) setfield(d, "score", setfield(d.score, "what_this_is_not", {'not calibrated'}))
    @(d) setfield(d, "score", setfield(d.score, "unit", "probability"))
    @(d) setfield(d, "scaling", setfield(d.scaling, "comparability_scope", "across_recordings"))
    @(d) setfield(d, "scope", setfield(d.scope, "candidate_count", 3))
    @(d) setfield(d, "profile", setfield(d.profile, "kind", "analysis_settings"))
    @(d) setfield(d, "parameters", setfield(d.parameters, "spreading_assumption", "cylindrical"))
    @(d) setfield(d, "dimensions", setfield(d.dimensions, "source_localization", ...
        struct(declaration="used", reason="x")))
    };
for k = 1:numel(cases)
    path = writeProfile(testCase, cases{k}(testCase.TestData.shipped), "claim" + k);
    verifyError(testCase, @() vawlume.estimator.loadSettings(path), ...
        "vawlume:estimator:SettingsInvalid");
end
gated = testCase.TestData.shipped;
gated.parameters.pose_confidence_gate = 0.8;
verifyError(testCase, @() vawlume.estimator.loadSettings( ...
    writeProfile(testCase, gated, "gated")), "vawlume:estimator:SettingsGateNotImplemented");
end

% ------------------------------------------------------------ the method ---

function testSelfConsistencyTheTrueCandidateScoresHighest(testCase)
% SELF-CONSISTENCY, NOT ACCURACY. The observed difference is generated from
% candidate A's position under the method's own spherical-spreading assumption,
% so A must fit perfectly. This shows the arithmetic is the stated one; it says
% nothing about real animals.
[entities, geometry, positions] = scene([20 10; 70 30]);
observed = predicted(positions(1, :));
result = method(testCase, entities, geometry, difference(observed));
c = result.candidates;
verifyEqual(testCase, c.status, ["scored"; "scored"]);
verifyEqual(testCase, c.score(1), 0, AbsTol=1e-12);
verifyLessThan(testCase, c.score(2), c.score(1));
% Every intermediate, and their arithmetic.
verifyEqual(testCase, c.distance_a, [hypot(20, 10); hypot(70, 30)], AbsTol=1e-12);
verifyEqual(testCase, c.distance_b, [hypot(80, 10); hypot(30, 30)], AbsTol=1e-12);
verifyEqual(testCase, c.predicted_difference_db, 20 * log10(c.distance_b ./ c.distance_a));
verifyEqual(testCase, c.discrepancy_db, observed - c.predicted_difference_db);
verifyEqual(testCase, c.score, -abs(c.discrepancy_db));
verifyEqual(testCase, c.observed_difference_db, [observed; observed]);
verifyEqual(testCase, c.score(2), -abs(observed - predicted(positions(2, :))), AbsTol=1e-12);
verifyEqual(testCase, result.score_unit, "dB");
verifyEqual(testCase, result.score_orientation, "higher_is_stronger");
end

function testTheRatioMakesTheScoreScaleFree(testCase)
% D17: only d_b / d_a enters, so a frame in mm gives the same scores as one in cm.
[entities, cm] = scene([20 10; 70 30]);
[~, mm] = scene([200 100; 700 300], [1000 0]);
mm.unit(:) = "mm";
observed = 4.2;
inCm = method(testCase, entities, cm, difference(observed));
inMm = method(testCase, entities, mm, difference(observed));
verifyEqual(testCase, inMm.candidates.score, inCm.candidates.score, AbsTol=1e-12);
end

function testSymmetricGeometryCannotSeparateTheCandidates(testCase)
% Both candidates on the perpendicular bisector: each is equidistant from both
% microphones, so each predicts 0 dB. Whatever was observed, the method cannot
% tell them apart, and it does not pretend to: the scores are equal.
[entities, geometry] = scene([50 10; 50 40]);
for observed = [0, 3, -7.5]
    result = method(testCase, entities, geometry, difference(observed));
    verifyEqual(testCase, result.candidates.predicted_difference_db, [0; 0], AbsTol=1e-12);
    verifyEqual(testCase, result.candidates.score(1), result.candidates.score(2));
end
end

function testModelMismatchIsAFindingNotAPass(testCase)
% A FINDING, NOT A CORRECTNESS ASSERTION. A rodent call is directional (contract
% 06 D7's dominant expected failure). Here candidate A calls, but its head adds a
% directivity bias to the observed difference that spherical spreading does not
% model. The method's ranking is recorded for each bias; only the labelling of
% the output is asserted.
[entities, geometry, positions] = scene([20 10; 70 30]);
truth = predicted(positions(1, :));
other = predicted(positions(2, :));
biases = [0, 6, -6, -8, -9, -12];
rows = strings(0, 1);
labels = ["A (true)", "B (wrong)"];
for bias = biases
    result = method(testCase, entities, geometry, difference(truth + bias));
    c = result.candidates;
    verifyEqual(testCase, c.status, ["scored"; "scored"]);
    verifyTrue(testCase, all(contains(c.score_semantics, "not a probability")));
    [~, best] = max(c.score);
    rows(end + 1, 1) = sprintf("bias %+5.1f dB: score A %7.2f, B %7.2f -> %s ranks first", ...
        bias, c.score(1), c.score(2), labels(best)); %#ok<AGROW>
end
log(testCase, 1, sprintf("Model-mismatch finding (A predicts %.2f dB, B %.2f dB; " + ...
    "they swap where the bias passes the midpoint, %.2f dB from A):\n%s", ...
    truth, other, (other - truth) / 2, strjoin(rows, newline)));
end

function testEachNoScoreReason(testCase)
[entities, geometry] = scene([20 10; 70 30]);
d = difference(5);
for identity = ["identity_no_track", "identity_multiple_tracks", ...
        "identity_changes_within_window", "identity_partial_window", "identity_unresolved"]
    e = entities;
    e.has_geometry(2) = false;
    e.reason(2) = identity;
    g = geometry(geometry.entity_id ~= 2, :);
    c = method(testCase, e, g, d).candidates;
    verifyEqual(testCase, c.status, ["scored"; "unscored"]);
    verifyEqual(testCase, c.no_score_reason(2), identity);
    verifyTrue(testCase, isnan(c.score(2)), "No default score.");
end
for rowReason = ["track_not_covered", "track_covered_empty", "bodypart_missing", "channel_unplaced"]
    c = method(testCase, entities, notComputed(geometry, 2, 2, rowReason), d).candidates;
    verifyEqual(testCase, c.no_score_reason(2), rowReason);
end
c = method(testCase, entities, notComputed(geometry, 2, 1, "position_missing"), d).candidates;
verifyEqual(testCase, [c.no_score_reason(2) c.geometry_reason_detail(2)], ...
    ["track_not_covered" "position_missing"]);
extrapolated = geometry;
extrapolated.bracket_extrapolated(extrapolated.entity_id == 1 & extrapolated.channel_index == 1) = true;
verifyEqual(testCase, method(testCase, entities, extrapolated, d).candidates.no_score_reason(1), ...
    "alignment_extrapolated");
pixels = geometry;
pixels.unit(:) = "px";
verifyEqual(testCase, method(testCase, entities, pixels, d).candidates.no_score_reason, ...
    ["frame_unit_not_accepted"; "frame_unit_not_accepted"]);
degenerate = geometry;
degenerate.distance(degenerate.entity_id == 1 & degenerate.channel_index == 2) = 0;
verifyEqual(testCase, method(testCase, entities, degenerate, d).candidates.no_score_reason(1), ...
    "distance_degenerate");
missing = difference(NaN, "refused", "b_missing");
verifyEqual(testCase, method(testCase, entities, geometry, missing).candidates.no_score_reason, ...
    ["acoustic_unavailable"; "acoustic_unavailable"]);
clipped = difference(NaN, "refused", "a_clipped");
c = method(testCase, entities, pixels, clipped).candidates;
verifyEqual(testCase, c.no_score_reason, ["frame_unit_not_accepted"; "frame_unit_not_accepted"]);
verifyEqual(testCase, c.no_score_reasons{1}, ["frame_unit_not_accepted"; "acoustic_clipped"], ...
    "Every applicable reason is kept, in contract order.");
verifyTrue(testCase, all(isnan(c.score)));
end

function testOtherCountsAndPairsAreRefused(testCase)
[entities, geometry] = scene([20 10; 70 30; 40 50]);
verifyError(testCase, @() method(testCase, entities, geometry, difference(1)), ...
    "vawlume:estimator:ScopeUnsupported");
verifyError(testCase, @() method(testCase, entities(1, :), geometry, difference(1)), ...
    "vawlume:estimator:ScopeUnsupported");
[entities, geometry] = scene([20 10; 70 30]);
swapped = difference(1);
swapped.channel_index_a = 2;
swapped.channel_index_b = 1;
verifyError(testCase, @() method(testCase, entities, geometry, swapped), ...
    "vawlume:estimator:ChannelPairMismatch");
other = difference(1);
other.channel_index_b = 3;
verifyError(testCase, @() method(testCase, entities, geometry, other), ...
    "vawlume:estimator:ChannelPairMismatch");
lenient = difference(1);
lenient.refuse_clipped_channels = false;
verifyError(testCase, @() method(testCase, entities, geometry, lenient), ...
    "vawlume:estimator:MethodInputInvalid");
verifyError(testCase, @() method(testCase, entities, geometry(geometry.channel_index == 1, :), ...
    difference(1)), "vawlume:estimator:MethodInputInvalid");
end

function testTheScoreIsNeverAProbability(testCase)
[entities, geometry] = scene([20 10; 70 30]);
result = method(testCase, entities, geometry, difference(2));
names = lower([string(fieldnames(result))', ...
    string(result.candidates.Properties.VariableNames)]);
verifyFalse(testCase, any(contains(names, "probab")));
for phrase = ["vawlume.estimator.level_difference_consistency 1.0.0", "dB", ...
        "higher_is_stronger", "uncalibrated", "within_recording", "not a probability"]
    verifyTrue(testCase, contains(result.score_semantics, phrase), phrase);
end
verifyTrue(testCase, all(result.candidates.score <= 0));
end

function testTheMethodFileIsPure(testCase)
% Tripwire 3: no database call and no file read in the method's code (comments
% and string literals stripped first).
path = fullfile(testCase.TestData.root, "src", "+vawlume", "+estimator", ...
    "levelDifferenceConsistency.m");
code = strings(0, 1);
for line = splitlines(string(fileread(path)))'
    code(end + 1, 1) = stripCode(line); %#ok<AGROW>
end
forbidden = "\<(fetch|exec|execute|sqlite|sqlread|sqlwrite|fileread|fopen|fread|" + ...
    "load|readtable|readmatrix|jsondecode|webread|dir|audioread)\s*\(";
hits = code(~cellfun(@isempty, regexp(cellstr(code), forbidden, "once")));
verifyEmpty(testCase, hits, strjoin(hits, newline));
verifyNotEmpty(testCase, regexp('x = fetch(conn, q);', forbidden, "once"), ...
    "The pattern itself must be able to fire.");
end

% --------------------------------------------------------------- helpers ---

function result = method(testCase, entities, geometry, d)
result = vawlume.estimator.levelDifferenceConsistency(entities, geometry, d, ...
    testCase.TestData.settings);
end

function [entities, geometry, positions] = scene(positions, micB)
% Rows as vawlume.estimator.candidateGeometry returns them (the columns the
% method reads), on the midpoint basis, microphones a=(0,0), b=micB.
if nargin < 2
    micB = [100 0];
end
count = size(positions, 1);
entities = table((1:count)', true(count, 1), strings(count, 1), ...
    "track" + string((0:count - 1)'), (101:100 + count)', ...
    VariableNames=["entity_id", "has_geometry", "reason", "native_track_id", ...
    "tracking_identity_association_id"]);
geometry = table();
mics = [0 0; micB];
for k = 1:count
    for channel = 1:2
        geometry = [geometry; table(k, channel, "midpoint", ...
            hypot(positions(k, 1) - mics(channel, 1), positions(k, 2) - mics(channel, 2)), ...
            "cm", "computed", "", false, false, VariableNames=["entity_id", ...
            "channel_index", "instant_basis", "distance", "unit", "status", "reason", ...
            "event_extrapolated", "bracket_extrapolated"])]; %#ok<AGROW>
    end
end
end

function value = predicted(position)
value = 20 * log10(hypot(position(1) - 100, position(2)) / hypot(position(1), position(2)));
end

function g = notComputed(geometry, entity, channel, reason)
g = geometry;
mask = g.entity_id == entity & g.channel_index == channel;
g.status(mask) = "not_computed";
g.reason(mask) = reason;
g.distance(mask) = NaN;
end

function d = difference(value, status, reasons)
% Shaped as vawlume.acoustic.levelDifference's result.
if nargin < 2
    status = "computed";
    reasons = strings(0, 1);
end
d = struct(status=string(status), reason="", reasons=string(reasons(:)), value=value, ...
    unit="dB", channel_index_a=1, channel_index_b=2, refuse_clipped_channels=true);
if ~isempty(d.reasons)
    d.reason = d.reasons(1);
end
end

function path = writeProfile(testCase, document, name)
path = fullfile(testCase.TestData.scratch, name + ".json");
fileId = fopen(path, "w");
fwrite(fileId, jsonencode(document));
fclose(fileId);
path = string(path);
end

function verifyErrorNaming(testCase, path, identifier, name)
try
    vawlume.estimator.loadSettings(path);
    verifyFail(testCase, "Expected " + identifier + " for " + name);
catch exception
    verifyEqual(testCase, string(exception.identifier), identifier, name);
    verifySubstring(testCase, string(exception.message), name);
end
end

function code = stripCode(line)
% Strings first, then everything from a comment on.
code = regexprep(line, '"([^"]|"")*"', '""');
code = regexprep(code, "(^|[\s=(,;\[{])'([^']|'')*'", "$1''");
code = regexprep(code, "%.*$", "");
end

function root = repositoryRoot()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
