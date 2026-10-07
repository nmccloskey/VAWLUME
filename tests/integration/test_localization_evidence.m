function tests = test_localization_evidence
%TEST_LOCALIZATION_EVIDENCE Promoting backend material onto VAWLUME targets.
%
% A backend's localization estimate, per-channel value and track reference are
% stored at intake against the backend's window. This suite promotes them onto
% attribution targets and candidates through vawlume.attribution.addEvidence --
% the one evidence entry point -- and asserts every refusal by identifier.
%
% The fixture runs the real path: backend intake, correspondence of the
% backend's windows to the run's targets on one clock, and candidate callers.
tests = functiontests(localfunctions);
end

% --- localization estimates are appendable as evidence ---------------------

function testAnEstimateIsAppendableAsCandidateEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.attribution.addEvidence(fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "arena_floor"), Apply=true);
verifyEqual(testCase, result.applied_count, 1);
stored = fetch(fixture.conn, "SELECT ev.evidence_dimension AS dimension, " + ...
    "typeof(ev.value_real) AS value_type, typeof(ev.value_units) AS units_type, " + ...
    "le.position_x AS x, le.confidence AS confidence, cs.coordinate_system_key AS frame, " + ...
    "le.position_semantics AS semantics " + ...
    "FROM attribution_evidence ev JOIN attribution_localization_estimates le " + ...
    "ON le.attribution_localization_estimate_id = ev.attribution_localization_estimate_id " + ...
    "JOIN coordinate_systems cs ON cs.coordinate_system_id = le.coordinate_system_id");
verifyEqual(testCase, string(stored.dimension), "source_localization");
% The row copies nothing; its frame, position, confidence and semantics are read
% through the estimate it cites.
verifyEqual(testCase, string(stored.value_type), "null");
verifyEqual(testCase, string(stored.units_type), "null");
verifyEqual(testCase, double(stored.x), 10);
verifyEqual(testCase, double(stored.confidence), 0.9);
verifyEqual(testCase, string(stored.frame), "arena_floor");
verifyTrue(testCase, contains(string(stored.semantics), "Example Localization Backend"));
clear cleanup
end

function testAnEstimateIsAppendableAsTargetEvidence(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.attribution.addEvidence(fixture.conn, ...
    struct(attribution_target_id=fixture.target_1), ...
    localizationRow(fixture.estimate_floor, "arena_floor"), Apply=true);
verifyEqual(testCase, result.applied_count, 1);
clear cleanup
end

% --- frames: declared, identical, never converted ---------------------------

function testAnEstimateWithNoDeclaredFrameIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
row = localizationRow(fixture.estimate_floor, "arena_floor");
row = rmfield(row, "coordinate_system_key");
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), row, Apply=true), ...
    "vawlume:attribution:LocalizationFrameRequired");
clear cleanup
end

function testAnUnknownFrameIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "no_such_frame"), Apply=true), ...
    "vawlume:attribution:LocalizationFrameUnknown");
clear cleanup
end

function testAnotherProjectsFrameIsADifferentRefusal(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "other_arena"), Apply=true), ...
    "vawlume:attribution:LocalizationFrameScopeMismatch");
clear cleanup
end

function testDeclaringAnotherFrameThanTheEstimatesIsRefusedByTheGeometryCheck(testCase)
% arena_volume is this project's frame and has the same unit as arena_floor.
% Similar metadata is not compatibility; the shared geometry primitive refuses.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "arena_volume"), Apply=true), ...
    "vawlume:geometry:CoordinateSystemMismatch");
clear cleanup
end

function testEstimatesInTwoFramesCannotMeetOnOneTarget(testCase)
% Each estimate is consistently declared, but they are in different frames, so
% reading them together would compare across frames.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
vawlume.attribution.addEvidence(fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "arena_floor"), Apply=true);
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "B"), ...
    localizationRow(fixture.estimate_volume, "arena_volume"), Apply=true), ...
    "vawlume:geometry:CoordinateSystemMismatch");
clear cleanup
end

function testNothingIsTransformedBetweenFrames(testCase)
% Promotion stores a citation; the estimate's coordinates are untouched.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
before = fetch(fixture.conn, "SELECT position_x, position_y, coordinate_system_id " + ...
    "FROM attribution_localization_estimates ORDER BY attribution_localization_estimate_id");
vawlume.attribution.addEvidence(fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "arena_floor"), Apply=true);
after = fetch(fixture.conn, "SELECT position_x, position_y, coordinate_system_id " + ...
    "FROM attribution_localization_estimates ORDER BY attribution_localization_estimate_id");
verifyEqual(testCase, after, before);
clear cleanup
end

% --- the workflow refusals the schema cannot express ------------------------

function testASourceLocalizationRowWithoutAnEstimateIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
row = localizationRow(fixture.estimate_floor, "arena_floor");
row = rmfield(row, "attribution_localization_estimate_id");
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), row, Apply=true), ...
    "vawlume:attribution:LocalizationEstimateRequired");
clear cleanup
end

function testAnotherDimensionCitingAnEstimateIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
row = poseRow();
row.attribution_localization_estimate_id = fixture.estimate_floor;
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), row, Apply=true), ...
    "vawlume:attribution:LocalizationEstimateMisplaced");
clear cleanup
end

function testALocalizationRowCarryingAValueIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
row = localizationRow(fixture.estimate_floor, "arena_floor");
row.value_real = 10;
row.value_units = "cm";
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), row, Apply=true), ...
    "vawlume:attribution:EvidenceValueInvalid");
clear cleanup
end

function testAnEstimateWhoseWindowDoesNotCorrespondIsRefused(testCase)
% The s2 estimate was computed over a window that corresponds to target 2, not
% target 1.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, struct(attribution_target_id=fixture.target_1), ...
    localizationRow(fixture.estimate_s2, "arena_floor"), Apply=true), ...
    "vawlume:attribution:LocalizationNotCorresponded");
clear cleanup
end

function testAnEstimateTiedToAnotherCallerIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_tied_to_b, "arena_floor"), Apply=true), ...
    "vawlume:attribution:LocalizationCallerMismatch");
% ...and it does support the caller it was tied to.
result = vawlume.attribution.addEvidence(fixture.conn, candidateRef(fixture, "B"), ...
    localizationRow(fixture.estimate_tied_to_b, "arena_floor"), Apply=true);
verifyEqual(testCase, result.applied_count, 1);
clear cleanup
end

function testAnEstimateFromAnotherRunIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_other_run, "arena_floor"), Apply=true), ...
    "vawlume:attribution:LocalizationEstimateNotInRun");
clear cleanup
end

% --- channel citation --------------------------------------------------------

function testFoldedChannelEvidenceIsPromotedWithItsChannel(testCase)
% F5.3-1 option (a), closed here: intake kept the backend's per-channel value as
% window-owned native attributes; promotion writes it as evidence that names its
% recording channel relationally.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
native = fetch(fixture.conn, "SELECT attribute_name AS name, value_type AS type, " + ...
    "IFNULL(value_real,-999.0) AS value, IFNULL(value_text,'') AS text, " + ...
    "IFNULL(unit,'') AS unit, IFNULL(source_locator,'') AS locator " + ...
    "FROM attribution_native_attributes " + ...
    "WHERE attribute_name LIKE 'channel:1:backend_channel_power%' " + ...
    "AND imported_attribution_window_id=" + string(fixture.window_s1) + ...
    " ORDER BY attribute_name");
channel = fetch(fixture.conn, "SELECT recording_channel_id FROM recording_channels " + ...
    "WHERE recording_id=1 AND channel_index=1");
row = struct(evidence_dimension="acoustic", evidence_kind="backend_channel_power", ...
    value_real=double(native.value(1)), value_units=string(native.unit(1)), ...
    value_semantics=string(native.text(2)), ...
    recording_channel_id=double(channel.recording_channel_id(1)), ...
    source_locator=string(native.locator(1)));
vawlume.attribution.addEvidence(fixture.conn, candidateRef(fixture, "A"), row, Apply=true);
stored = fetch(fixture.conn, "SELECT ev.value_real AS value, rc.channel_index AS idx " + ...
    "FROM attribution_evidence ev JOIN recording_channels rc " + ...
    "ON rc.recording_channel_id = ev.recording_channel_id");
verifyEqual(testCase, double(stored.value), -41);
verifyEqual(testCase, double(stored.idx), 1);
clear cleanup
end

function testAChannelFromAnotherRecordingIsRefused(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
row = acousticRow();
row.recording_channel_id = fixture.foreign_channel;
verifyRefusedWritingNothing(testCase, fixture, @() vawlume.attribution.addEvidence( ...
    fixture.conn, candidateRef(fixture, "A"), row, Apply=true), ...
    "vawlume:attribution:EvidenceChannelScopeMismatch");
clear cleanup
end

% --- the dimensions stay separate --------------------------------------------

function testLocalizationAndPoseAreSeparatelyIdentifiableOnOneCandidate(testCase)
% A sound-source position and a bodypart position on one candidate: different
% dimensions, different units, different semantics, and neither derived from
% the other.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
ref = candidateRef(fixture, "A");
vawlume.attribution.addEvidence(fixture.conn, ref, poseRow(), Apply=true);
vawlume.attribution.addEvidence(fixture.conn, ref, ...
    localizationRow(fixture.estimate_floor, "arena_floor"), Apply=true);
rows = fetch(fixture.conn, "SELECT ev.evidence_dimension AS dimension, " + ...
    "IFNULL(ev.value_units, cs.unit) AS units, " + ...
    "IFNULL(ev.value_semantics, le.position_semantics) AS semantics " + ...
    "FROM attribution_evidence ev " + ...
    "LEFT JOIN attribution_localization_estimates le " + ...
    "ON le.attribution_localization_estimate_id = ev.attribution_localization_estimate_id " + ...
    "LEFT JOIN coordinate_systems cs ON cs.coordinate_system_id = le.coordinate_system_id " + ...
    "WHERE ev.attribution_candidate_id=" + string(ref.attribution_candidate_id) + ...
    " ORDER BY ev.evidence_dimension");
verifyEqual(testCase, string(rows.dimension)', ["pose_localization" "source_localization"]);
verifyEqual(testCase, string(rows.units)', ["upstream_score" "cm"]);
verifyNotEqual(testCase, string(rows.semantics(1)), string(rows.semantics(2)));
verifyTrue(testCase, contains(string(rows.semantics(2)), "not a bodypart position"));
clear cleanup
end

function testAllFiveDimensionsCoexistUncombinedOnOneCandidate(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
ref = candidateRef(fixture, "A");
temporal = struct(evidence_dimension="temporal_alignment", evidence_kind="propagated_bound", ...
    value_real=0.002, value_units="s", value_semantics="uncalibrated bound", ...
    source_locator="alignment report");
identity = struct(evidence_dimension="visual_identity", evidence_kind="identity_association", ...
    value_text="assigned", value_units="category", value_semantics="manual review", ...
    identity_statement_kind="identity_association", ...
    tracking_identity_association_id=fixture.association_t1);
vawlume.attribution.addEvidence(fixture.conn, ref, temporal, Apply=true);
vawlume.attribution.addEvidence(fixture.conn, ref, poseRow(), Apply=true);
vawlume.attribution.addEvidence(fixture.conn, ref, identity, Apply=true);
vawlume.attribution.addEvidence(fixture.conn, ref, acousticRow(), Apply=true);
vawlume.attribution.addEvidence(fixture.conn, ref, ...
    localizationRow(fixture.estimate_floor, "arena_floor"), Apply=true);
rows = fetch(fixture.conn, "SELECT evidence_dimension AS d FROM attribution_evidence " + ...
    "WHERE attribution_candidate_id=" + string(ref.attribution_candidate_id));
verifyEqual(testCase, sort(string(rows.d))', sort(["temporal_alignment" ...
    "pose_localization" "visual_identity" "acoustic" "source_localization"]));
% Five rows for five dimensions, and no sixth row that combines any of them.
verifyEqual(testCase, height(rows), 5);
clear cleanup
end

% --- negative checks: nothing combines the dimensions ------------------------

function testTheEvidenceWriteSurfaceHasNoCombiningField(testCase)
% A closed list, not a blocklist: a combining field added under any name changes
% this list and fails here. The returned plan, and the stored table, both.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
result = vawlume.attribution.addEvidence(fixture.conn, candidateRef(fixture, "A"), ...
    localizationRow(fixture.estimate_floor, "arena_floor"));
verifyEqual(testCase, sort(string(result.evidence.Properties.VariableNames)), ...
    sort(["attribution_evidence_id", "attribution_target_id", ...
    "attribution_candidate_id", "evidence_ordinal", "evidence_dimension", ...
    "evidence_kind", "value_real", "value_text", "value_units", "value_semantics", ...
    "identity_statement_kind", "tracking_identity_association_id", ...
    "external_event_id", "alignment_run_id", "source_file_id", ...
    "mapping_profile_version_id", "source_locator", "notes", ...
    "attribution_localization_estimate_id", "coordinate_system_key", ...
    "coordinate_system_id", "recording_channel_id", "derived_measurement_id", ...
    "action"]));
% derived_measurement_id joined the PLAN output at 6.8, when addEvidence began
% accepting the citation (contract 06 D15). Like the stored column below, it is
% an identifier, never a value derived from two dimensions.
columns = fetch(fixture.conn, "SELECT name FROM pragma_table_info('attribution_evidence')");
verifyEqual(testCase, sort(string(columns.name))', sort(["attribution_evidence_id", ...
    "attribution_target_id", "attribution_candidate_id", "evidence_dimension", ...
    "evidence_kind", "value_real", "value_text", "value_units", "value_semantics", ...
    "identity_statement_kind", "tracking_identity_association_id", ...
    "external_event_id", "alignment_run_id", "source_file_id", ...
    "mapping_profile_version_id", "source_locator", "notes", ...
    "recording_channel_id", "attribution_localization_estimate_id", ...
    "derived_measurement_id"]));
% derived_measurement_id (0.13-draft) is a citation of the measurement a row
% reports, not a combined value: it holds an identifier, never a number derived
% from two dimensions. Added here deliberately, which is what a closed list is for.
clear cleanup
end

function testNoSourceComputesADistanceAngleOrTransform(testCase)
% Tripwire 2, revised at 6.3 into a PACKAGE BOUNDARY. Checked on ARITHMETIC rather
% than on function names: string literals and comments are stripped, then every
% line in src/ that squares-and-roots, takes a norm, an angle or a trig function,
% or interpolates is listed.
%
% Phase 6 lifts the prohibition on spatial arithmetic for one package only
% (docs/design/06_native_estimator_contract.md D3). The invariant this test now
% enforces, word for word, is revised invariant 19:
%
%   Spatial arithmetic (distance, norm, angle, and position interpolation)
%   occurs only in src/+vawlume/+geometry/. A distance is computed only between
%   positions whose frames pass the shared identity rule. No coordinate is
%   transformed, rescaled or converted between frames anywhere in src/.
%
% +geometry/ is permitted as a PACKAGE: it owns frames and assertCompatible, so
% the package that decides whether two frames may be related is the only one
% that relates them. Every other hit stays a PER-LINE exemption with its reason,
% so no non-spatial exemption can widen into a home for spatial arithmetic.
%
% What this cannot see: arithmetic written without any listed function, such as
% a hand-written linear interpolation. The package boundary, code review and the
% sweep's reading cover that; this test catches the named operations.
root = repositoryRoot();
[permittedHome, other] = arithmeticHits(root);
verifyNotEmpty(testCase, permittedHome, ...
    "No spatial arithmetic was found even in +geometry/. Either the spatial " + ...
    "primitives moved or the pattern stopped matching anything; a guard that " + ...
    "finds nothing anywhere proves nothing.");
verifyEqual(testCase, sort(other), sort(permittedArithmetic()), ...
    "Spatial-looking arithmetic outside src/+vawlume/+geometry/ (revised " + ...
    "invariant 19 permits it only there):" + newline + ...
    strjoin(setdiff(other, permittedArithmetic()), newline) + newline + ...
    "Listed exemptions no longer found:" + newline + ...
    strjoin(setdiff(permittedArithmetic(), other), newline));
end

function testTheArithmeticScannerSeesWhatItShould(testCase)
% The scanner's own regressions, each a way the Phase 5 version was blind:
%  * \b is NOT a word boundary in MATLAB regexp (it is \< and \>), so the
%    Phase 5 pattern's \bnorm, \bdot, \bacos, \basin and \batan never matched;
%  * comments were stripped before strings, so a % inside a string hid the code
%    after it (F5.10-8);
%  * the trig family and interpolation functions were absent (F5.10-8).
pattern = arithmeticPattern();
mustMatch = ["d = norm(v);", "a = acos(c);", "a = asind(c);", "a = atan(c);", ...
    "y = cos(t);", "y = sind(t);", "y = tan(t);", "r = deg2rad(d);", ...
    "p = interp1(t, x, q);", "d = dot(a, b);", "c = cross(a, b);", ...
    "d = hypot(dx, dy);", "R = quat2rotm(q);"];
for line = mustMatch
    verifyNotEmpty(testCase, regexp(stripCode(line), pattern, "once"), ...
        "The pattern missed: " + line);
end
mustNotMatch = ["n = normalize(x);", "z = zcrossings(x);", "x = dotted(1);", ...
    "s = cosine_similarity;", "t = tangent;", "adequate = 1;", ...
    "label = 'sqrt(x)';", "label = ""hypot(a,b)"";", "% d = norm(v);"];
for line = mustNotMatch
    verifyEmpty(testCase, regexp(stripCode(line), pattern, "once"), ...
        "The pattern matched non-arithmetic: " + line);
end
% Strings stripped BEFORE comments: a % inside a string must not hide code.
verifyNotEmpty(testCase, regexp(stripCode("s = ""50%""; d = norm(v);"), pattern, "once"));
verifyNotEmpty(testCase, regexp(stripCode("s = '50%'; d = norm(v);"), pattern, "once"));
% A transpose is not the start of a char array.
verifyEqual(testCase, stripCode("y = x' * sqrt(z)'; % note"), "y = x' * sqrt(z)';");
% Text after a continuation is a comment.
verifyEqual(testCase, strtrim(stripCode("a = b + ... sqrt(c)")), "a = b +");
end

% ---------------------------------------------------------------- helpers ---

function [permittedHome, other] = arithmeticHits(root)
files = dir(fullfile(root, "src", "**", "*.m"));
pattern = arithmeticPattern();
home = "src/+vawlume/+geometry/";
permittedHome = strings(0, 1);
other = strings(0, 1);
for index = 1:numel(files)
    path = fullfile(files(index).folder, files(index).name);
    relative = replace(extractAfter(string(path), strlength(string(root)) + 1), "\", "/");
    lines = splitlines(string(fileread(path)));
    inBlockComment = false;
    for lineNumber = 1:numel(lines)
        trimmed = strtrim(lines(lineNumber));
        if trimmed == "%{"
            inBlockComment = true;
            continue
        elseif trimmed == "%}"
            inBlockComment = false;
            continue
        elseif inBlockComment
            continue
        end
        code = strtrim(stripCode(lines(lineNumber)));
        if ~isempty(regexp(code, pattern, "once"))
            % Keyed on file and code, not line number, so unrelated edits above a
            % permitted hit do not churn this list.
            if startsWith(relative, home)
                permittedHome(end+1, 1) = relative + " | " + code; %#ok<AGROW>
            else
                other(end+1, 1) = relative + " | " + code; %#ok<AGROW>
            end
        end
    end
end
end

function pattern = arithmeticPattern()
% \< is MATLAB's start-of-word anchor. \b is not a word boundary in MATLAB regexp.
pattern = "(\<sqrt\s*\(|\<hypot\s*\(|\<atan2d?\s*\(|\<norm\s*\(|\<vecnorm\s*\(|" + ...
    "\<pdist2?\s*\(|\<acosd?\s*\(|\<asind?\s*\(|\<atand?\s*\(|\<cosd?\s*\(|" + ...
    "\<sind?\s*\(|\<tand?\s*\(|\<secd?\s*\(|\<cscd?\s*\(|\<cotd?\s*\(|" + ...
    "\<deg2rad\s*\(|\<rad2deg\s*\(|\<cross\s*\(|\<dot\s*\(|\<interp[123n]\s*\(|" + ...
    "griddedInterpolant|scatteredInterpolant|\<rotm\w*\s*\(|\<quat\w*\s*\(|" + ...
    "\w+2rotm\s*\(|\w+2quat\s*\()";
end

function code = stripCode(line)
% Remove string literals, then everything from a comment or a continuation on.
% A single quote starts a char array only where a transpose is impossible: at the
% start of the line, or after an operator, comma, bracket opener or space that
% does not follow a value. Strings are removed BEFORE the comment is found, so a
% '%' inside a string never hides the code after it.
chars = char(line);
out = blanks(0);
index = 1;
count = numel(chars);
while index <= count
    c = chars(index);
    if c == '"'
        [index, ~] = skipQuoted(chars, index, '"');
        continue
    elseif c == '''' && ~isTranspose(out)
        [index, ~] = skipQuoted(chars, index, '''');
        continue
    elseif c == '%'
        break
    elseif c == '.' && index + 2 <= count && all(chars(index:index+2) == '...')
        break
    end
    out(end+1) = c; %#ok<AGROW>
    index = index + 1;
end
code = strtrim(string(out));
end

function [index, closed] = skipQuoted(chars, index, quote)
% Advance past a quoted literal; a doubled quote is an escaped quote.
index = index + 1;
closed = false;
while index <= numel(chars)
    if chars(index) == quote
        if index < numel(chars) && chars(index + 1) == quote
            index = index + 2;
            continue
        end
        index = index + 1;
        closed = true;
        return
    end
    index = index + 1;
end
end

function value = isTranspose(previous)
% A quote is a transpose when it directly follows a value: an identifier
% character, a closing bracket, a dot, or another transpose.
value = false;
if isempty(previous)
    return
end
last = previous(end);
value = isletter(last) || (last >= '0' && last <= '9') || ...
    any(last == ['_', ')', ']', '}', '.', '''']);
end

function value = permittedArithmetic()
% Every hit OUTSIDE src/+vawlume/+geometry/, and why it is not spatial. Kept
% exhaustive: an unlisted hit, or a listed one that vanished, fails the test and
% must be read. Never widen an entry into a package: these are exemptions for
% specific non-spatial lines, and +geometry/ is the only spatial home.
value = [
    % RMS amplitude of an audio window: acoustic, not spatial. The one shared
    % core of reference and call-window measurement since 6.6.
    % (String literals are stripped before matching, so the unit label is absent.)
    "src/+vawlume/+acoustic/private/acousticWindowMetrics.m | sqrt(mean(samples .^ 2)), }];"
    % Clock-fit residual RMSE, in seconds, inside +alignment/: temporal.
    "src/+vawlume/+alignment/solveTransform.m | rmse_s=sqrt(mean(residual .^ 2)),"
    "src/+vawlume/+alignment/private/alignmentFitBuildPlan.m | value.rmse_s(segment) = sqrt(mean(residual(rows) .^ 2));"
    % Precision-matrix normalization for a partial correlation: statistics.
    "src/+vawlume/+eda/private/edaPartialCorrelation.m | scaled = -P ./ sqrt(diagonal * diagonal');"
    % Linear interpolation between order statistics for a sample quantile:
    % statistics over a sorted value vector, not positions. Invisible to the
    % Phase 5 pattern, which had no interpolation term (found at 6.3).
    "src/+vawlume/+eda/sampleQuantile.m | interpolated = interp1(positions, ordered, requested, );"
    % Periodic Hann window coefficients for a spectrogram: signal processing,
    % not an angle. Invisible to the Phase 5 pattern, which had no cos term.
    "src/+vawlume/+eda/spectrogramMatrix.m | value = 0.5 * (1 - cos(2 * pi * n / length));"
    ];
end
function row = localizationRow(estimateId, frameKey)
row = struct(evidence_dimension="source_localization", ...
    evidence_kind="backend_source_location", ...
    attribution_localization_estimate_id=estimateId, ...
    coordinate_system_key=frameKey);
end

function row = poseRow()
row = struct(evidence_dimension="pose_localization", ...
    evidence_kind="keypoint_confidence", value_real=0.73, ...
    value_units="upstream_score", ...
    value_semantics="upstream snout keypoint localization confidence; not a sound source", ...
    source_locator="pose export row 12");
end

function row = acousticRow()
row = struct(evidence_dimension="acoustic", evidence_kind="channel_rms_ratio", ...
    value_real=0.42, value_units="ratio", value_semantics="channel 1 to 2 rms ratio", ...
    source_locator="measurement 3");
end

function ref = candidateRef(fixture, label)
ref = struct(attribution_candidate_id=fixture.("candidate_" + label));
end

function verifyRefusedWritingNothing(testCase, fixture, action, identifier)
before = evidenceCount(fixture);
refused = false;
observed = "";
try
    action();
catch err
    refused = true;
    observed = string(err.identifier);
end
verifyTrue(testCase, refused, "Expected a refusal identified as " + identifier);
verifyEqual(testCase, observed, string(identifier));
verifyEqual(testCase, evidenceCount(fixture), before, "A refusal must write nothing.");
end

function value = evidenceCount(fixture)
rows = fetch(fixture.conn, "SELECT COUNT(*) AS n FROM attribution_evidence");
value = double(rows.n(1));
end

function [fixture, cleanup] = setUpFixture()
root = repositoryRoot();
sourcePath = fullfile(root, "src");
addedPath = ~contains(path, sourcePath);
if addedPath
    addpath(sourcePath);
end
workspace = fullfile(tempdir, "vawlume_localization_" + string(java.util.UUID.randomUUID));
mkdir(workspace);
conn = sqlite(char(fullfile(workspace, "localization.sqlite")), "create");
cleanup = onCleanup(@() tearDown(conn, workspace, sourcePath, addedPath));
vawlume.db.applySchema(conn, fullfile(root, "schema", "schema.sql"));
seedFixture(conn);

settingsPath = fullfile(workspace, "settings.json");
writeText(settingsPath, "{""note"": ""synthetic""}");
settings = vawlume.db.registerProfileVersion(conn, struct(project_id=1), struct( ...
    profile_key="backend-settings", profile_name="Backend run settings", ...
    version_label="1.0.0", content_path=settingsPath));
runs = zeros(1, 2);
for index = 1:2
    created = vawlume.attribution.createRun(conn, struct(recording_id=1), struct( ...
        run_key="localization-run-" + index, attribution_path="backend", ...
        method="Example Localization Backend", ...
        settings_profile_version_id=settings.profile_version_id, ...
        target_set=struct(detection_ids=[1 2]), participating_entity_ids=[1 2], ...
        sources=struct(source_file_ids=1)), Apply=true);
    runs(index) = created.run.attribution_run_id;
end

% Run 1: a two-window export; s1 carries callers A and B and one estimate.
source = fullfile(workspace, "export.csv");
writeText(source, "segment_id,start_s,end_s,candidate,assignment_score,track," + ...
    "source_x,source_y,localization_confidence,mic1_power,mic2_power,err_major" + newline + ...
    "s1,1.0,1.4,A,0.7,t1,10,20,0.9,-41,-45,3.5" + newline + ...
    "s1,1.0,1.4,B,0.2,,10,20,0.9,-41,-45,3.5" + newline + ...
    "s2,2.0,2.3,,,,30,5,,,," + newline);
vawlume.ingest.backendAttribution(conn, struct(attribution_run_id=runs(1)), source, Apply=true);
% Run 2 imports the same file, so its estimates belong to another run.
vawlume.ingest.backendAttribution(conn, struct(attribution_run_id=runs(2)), source, Apply=true);
for index = 1:2
    vawlume.attribution.correspondWindows(conn, struct(attribution_run_id=runs(index)), ...
        SameClock=true, Apply=true);
end

targets = fetch(conn, "SELECT attribution_target_id AS id, detection_id AS d " + ...
    "FROM attribution_targets WHERE attribution_run_id=" + string(runs(1)) + ...
    " ORDER BY detection_id");
target1 = double(targets.id(1));
candidates = table([1; 2], VariableNames="entity_id");
added = vawlume.attribution.addCandidates(conn, ...
    struct(attribution_target_id=target1), candidates, Apply=true);
candidateIds = double(added.candidates.attribution_candidate_id);

estimates = fetch(conn, "SELECT le.attribution_localization_estimate_id AS id, " + ...
    "w.native_window_id AS window, w.attribution_run_id AS run " + ...
    "FROM attribution_localization_estimates le JOIN imported_attribution_windows w " + ...
    "ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "ORDER BY le.attribution_localization_estimate_id");
pick = @(run, window) double(estimates.id(estimates.run == run & ...
    string(estimates.window) == window));
estimateFloor = pick(runs(1), "s1");
estimateS2 = pick(runs(1), "s2");
estimateOtherRun = pick(runs(2), "s1");

% Two estimates the shipped template cannot produce: one in the 3D frame, and one
% the producer tied to caller B. Both over run 1's window s1.
window = fetch(conn, "SELECT imported_attribution_window_id AS id FROM imported_attribution_windows " + ...
    "WHERE attribution_run_id=" + string(runs(1)) + " AND native_window_id='s1'");
claimB = fetch(conn, "SELECT imported_attribution_claim_id AS id FROM imported_attribution_claims " + ...
    "WHERE imported_attribution_window_id=" + string(double(window.id(1))) + ...
    " AND source_caller_label='B'");
execute(conn, "INSERT INTO attribution_localization_estimates(" + ...
    "imported_attribution_window_id,estimate_ordinal,coordinate_system_id,position_x," + ...
    "position_y,position_semantics) VALUES(" + string(double(window.id(1))) + ...
    ",2,2,11,21,'estimated sound source; producer=Second Backend')");
estimateVolume = fetch(conn, "SELECT last_insert_rowid() AS id");
execute(conn, "INSERT INTO attribution_localization_estimates(" + ...
    "imported_attribution_window_id,imported_attribution_claim_id,estimate_ordinal," + ...
    "coordinate_system_id,position_x,position_y,position_semantics) VALUES(" + ...
    string(double(window.id(1))) + "," + string(double(claimB.id(1))) + ...
    ",3,1,12,22,'estimated sound source of B; producer=Second Backend')");
estimateTied = fetch(conn, "SELECT last_insert_rowid() AS id");

fixture = struct(conn=conn, workspace=string(workspace), target_1=target1, ...
    candidate_A=candidateIds(1), candidate_B=candidateIds(2), ...
    estimate_floor=estimateFloor, estimate_s2=estimateS2, ...
    estimate_other_run=estimateOtherRun, ...
    estimate_volume=double(estimateVolume.id(1)), ...
    estimate_tied_to_b=double(estimateTied.id(1)), ...
    foreign_channel=3, association_t1=1, window_s1=double(window.id(1)));
end

function tearDown(conn, workspace, sourcePath, addedPath)
try, close(conn); catch, end %#ok<NOCOM>
if isfolder(workspace), rmdir(workspace, "s"); end
if addedPath && contains(path, sourcePath)
    rmpath(sourcePath);
end
end

function writeText(path, text)
fileId = fopen(path, "w");
fprintf(fileId, "%s", text);
fclose(fileId);
end

function seedFixture(conn)
execute(conn, "INSERT INTO projects(project_id,project_key,project_name) " + ...
    "VALUES(1,'p1','Project 1'),(2,'p2','Project 2')");
execute(conn, "INSERT INTO source_files(source_file_id,project_id,file_role," + ...
    "path_or_uri,relative_path) VALUES(1,1,'recording_audio','audio.wav','audio.wav')," + ...
    "(2,1,'recording_audio','audio2.wav','audio2.wav')");
execute(conn, "INSERT INTO recordings(recording_id,project_id,source_file_id," + ...
    "native_recording_id) VALUES(1,1,1,'R1'),(2,1,2,'R2')");
% Channel 3 belongs to recording 2, not to the run's recording.
execute(conn, "INSERT INTO recording_channels(recording_channel_id,recording_id," + ...
    "channel_index) VALUES(1,1,1),(2,1,2),(3,2,1)");
execute(conn, "INSERT INTO coordinate_systems(coordinate_system_id,project_id," + ...
    "coordinate_system_key,coordinate_system_name,dimensionality,unit) VALUES" + ...
    "(1,1,'arena_floor','Arena floor',2,'cm'),(2,1,'arena_volume','Arena volume',3,'cm')," + ...
    "(3,2,'other_arena','Another experiment',2,'cm')");
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
    "start_time_s,end_time_s) VALUES(1,1,1,1.0,1.5),(2,1,1,2.0,2.4)");
execute(conn, "INSERT INTO timebases(timebase_id,project_id,recording_id,timebase_name," + ...
    "timebase_kind,native_unit) VALUES(1,1,1,'video_clock','video_frames','s')");
execute(conn, "INSERT INTO external_streams(external_stream_id,project_id,recording_id," + ...
    "timebase_id,stream_name,stream_kind) VALUES(1,1,1,1,'overhead_pose','tracking')");
execute(conn, "INSERT INTO tracking_streams(external_stream_id,coordinate_system_id," + ...
    "native_time_basis) VALUES(1,1,'time')");
execute(conn, "INSERT INTO tracking_identity_associations(" + ...
    "tracking_identity_association_id,external_stream_id,native_track_id,entity_id," + ...
    "start_time_native,end_time_native,assignment_state,evidence_kind) VALUES" + ...
    "(1,1,'t1',1,0,100,'assigned','manual_review')");
end

function root = repositoryRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
