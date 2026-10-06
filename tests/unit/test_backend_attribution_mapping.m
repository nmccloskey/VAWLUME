function tests = test_backend_attribution_mapping
%TEST_BACKEND_ATTRIBUTION_MAPPING The database-free half of the backend adapter.
%
% Maps synthetic localization-backend exports through the shipped
% attribution_backend_mapping template, or a variant of it built in memory,
% into the source-mapping IR. No database is opened anywhere in this suite or
% in the code it exercises; that is the property that makes the mapper
% auditable on its own.
%
% Refusals are asserted by issue CODE, and each refused row is checked to have
% contributed nothing: a row is all or nothing.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repoRoot = repoRoot;
testCase.TestData.profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "attribution", "generic_backend_attribution_profile.json");
end

% --- the shipped template --------------------------------------------------

function testShippedTemplateMapsAWellFormedExport(testCase)
ir = mapRows(testCase, shippedEntry(testCase), [
    row("s1", "1.0", "1.4", "A", "0.7", "t1", "10", "20", "0.9", "-41", "-45", "3.5")
    row("s1", "1.0", "1.4", "B", "0.2", "", "10", "20", "0.9", "-41", "-45", "3.5")
    row("s2", "2.0", "2.3", "", "", "", "30", "5", "", "-50", "", "")]);
verifyTrue(testCase, ir.valid_for_ingest);
verifyEmpty(testCase, ir.issues);
verifyEqual(testCase, height(ir.attribution_windows), 2);
verifyEqual(testCase, height(ir.attribution_claims), 2);
% One position repeated across a window's caller rows is one estimate.
verifyEqual(testCase, height(ir.attribution_localization_estimates), 2);
verifyEqual(testCase, height(ir.attribution_channel_evidence), 3);
verifyEqual(testCase, height(ir.attribution_track_references), 1);
verifyEqual(testCase, height(ir.attribution_native_attributes), 2);
verifyEqual(testCase, ir.summary.profile_kind, "attribution_backend_mapping");
end

function testShippedTemplateNamesRolesNotVendorColumns(testCase)
% The template's roles point at neutral field names, and nothing in it names a
% commercial backend.
text = lower(string(fileread(testCase.TestData.profilePath)));
for vendor = ["usvcam", "deepsqueak", "mupet", "usvseg", "avisoft", "sleap", "deeplabcut"]
    verifyFalse(testCase, contains(text, vendor), "Template names " + vendor);
end
end

% --- numbers arrive exactly ------------------------------------------------

function testCoordinatesAndConfidencesArriveBitIdentical(testCase)
% Awkward decimals: more digits than a double holds, a value with no exact
% binary form, and an exponent. The IR must hold exactly the double the text
% denotes -- compared exactly, never within a tolerance.
xText = "10.123456789012345678";
yText = "-0.30000000000000004";
confidenceText = "7.250000000000001e-3";
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", xText, yText, confidenceText, "", "", ""));
estimate = ir.attribution_localization_estimates;
verifyTrue(testCase, isequal(typecast(estimate.position_x, "uint64"), ...
    typecast(str2double(xText), "uint64")));
verifyTrue(testCase, isequal(typecast(estimate.position_y, "uint64"), ...
    typecast(str2double(yText), "uint64")));
verifyTrue(testCase, isequal(typecast(estimate.confidence, "uint64"), ...
    typecast(str2double(confidenceText), "uint64")));
end

function testNumericCellsPassThroughUnchanged(testCase)
% A table already holding doubles is not re-parsed or re-rounded.
tbl = rowsTable(row("s1", "1", "2", "A", "", "", "", "", "", "", "", ""));
tbl.source_x = 0.1 + 0.2;
tbl.source_y = pi;
ir = vawlume.source_mapping.mapTableToIR(tbl, shippedEntry(testCase), SourceKey="source:t");
verifyTrue(testCase, isequal(ir.attribution_localization_estimates.position_x, 0.1 + 0.2));
verifyTrue(testCase, isequal(ir.attribution_localization_estimates.position_y, pi));
end

function testAbsenceIsNaNNeverZero(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", ""));
verifyTrue(testCase, isnan(ir.attribution_localization_estimates.confidence));
verifyEqual(testCase, ir.attribution_localization_estimates.confidence_semantics, "");
verifyTrue(testCase, isnan(ir.attribution_localization_estimates.position_z));
% A label with no number is a legitimate claim; its score is NaN, never 1.0.
verifyTrue(testCase, isnan(ir.attribution_claims.score));
verifyEmpty(testCase, ir.attribution_channel_evidence);
end

% --- semantics name their producer -----------------------------------------

function testEveryStoredNumberCarriesProducerNamingSemantics(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "0.7", "", "10", "20", "0.9", "-41", "", ""));
producer = "Example Localization Backend";
verifyTrue(testCase, contains(ir.attribution_claims.score_semantics, producer));
verifyTrue(testCase, contains(ir.attribution_localization_estimates.position_semantics, producer));
verifyTrue(testCase, contains(ir.attribution_localization_estimates.confidence_semantics, producer));
verifyTrue(testCase, contains(ir.attribution_channel_evidence.value_semantics, producer));
verifyFalse(testCase, contains(ir.attribution_localization_estimates.position_semantics, "{producer}"));
end

% --- nothing is resolved against a database --------------------------------

function testDeclaredKeysAreCarriedNotResolved(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "t9", "10", "20", "", "-41", "", ""));
verifyEqual(testCase, ir.attribution_localization_estimates.coordinate_system_key, "arena_floor");
verifyEqual(testCase, ir.attribution_claims.entity_native_id, "A");
verifyEqual(testCase, ir.attribution_channel_evidence.channel_index, 1);
verifyEqual(testCase, ir.attribution_track_references.tracking_stream_key, "overhead_pose");
verifyEqual(testCase, ir.attribution_track_references.native_track_id, "t9");
% No database identifier column exists anywhere in the backend IR tables.
for name = ["attribution_localization_estimates", "attribution_channel_evidence", ...
        "attribution_track_references", "attribution_native_attributes", ...
        "attribution_windows", "attribution_claims"]
    columns = string(ir.(name).Properties.VariableNames);
    verifyFalse(testCase, any(endsWith(columns, "_id") & columns ~= "native_window_id" & ...
        columns ~= "native_estimate_id" & columns ~= "native_track_id" & ...
        columns ~= "entity_native_id"), name + " carries a resolved id");
end
end

function testTheMapperOpensNoDatabase(testCase)
% Tripwire 2, checked on CODE: comments are stripped first, because prose
% explaining that nothing touches a database would otherwise match.
path = fullfile(testCase.TestData.repoRoot, "src", "+vawlume", "+source_mapping", ...
    "private", "mapBackendAttributionTableToIR.m");
lines = splitlines(string(fileread(path)));
code = strjoin(regexprep(lines, "%.*$", ""), newline);
for call = ["sqlite(", "fetch(", "execute(", "exec(", "database(", "commit(", "sqlwrite("]
    verifyFalse(testCase, contains(code, call), "Mapper code calls " + call);
end
end

% --- section D refusals, each by name --------------------------------------

function testAReversedWindowIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "2", "1", "A", "", "", "10", "20", "", "", "", ""));
verifyRefusedRow(testCase, ir, "ATTRIBUTION_WINDOW_REVERSED");
end

function testAMissingWindowIdentifierIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("", "1", "2", "A", "", "", "10", "20", "", "", "", ""));
verifyRefusedRow(testCase, ir, "ATTRIBUTION_WINDOW_ID_MISSING");
end

function testACoordinateMissingAnAxisIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", "10", "", "", "", "", ""));
verifyRefusedRow(testCase, ir, "BACKEND_COORDINATE_AXIS_MISSING");
end

function testACoordinateWithNoDeclaredFrameIsRefused(testCase)
% The interesting refusal. The frame comes from a per-row field here, and this
% row leaves it empty: a coordinate without a frame is not a coordinate.
entry = shippedEntry(testCase);
entry.context = rmfield(entry.context, "coordinate_system_key");
entry.localization.coordinate_system = struct(source_field="frame");
tbl = rowsTable([
    row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", "")
    row("s2", "3", "4", "A", "", "", "11", "21", "", "", "", "")]);
tbl.frame = ["arena_floor"; ""];
ir = vawlume.source_mapping.mapTableToIR(tbl, entry, SourceKey="source:t");
verifyEqual(testCase, ir.issues.code, "BACKEND_COORDINATE_FRAME_MISSING");
verifyTrue(testCase, contains(ir.issues.location, "#row=2"));
verifyFalse(testCase, ir.valid_for_ingest);
% Row 2 contributed nothing at all: no estimate, and no orphan window either.
verifyEqual(testCase, ir.attribution_windows.native_window_id, "s1");
verifyEqual(testCase, ir.attribution_localization_estimates.coordinate_system_key, "arena_floor");
end

function testAConfidenceOutsideTheDeclaredRangeIsRefused(testCase)
entry = shippedEntry(testCase);
entry.localization.confidence_range = [0; 1];
ir = mapRows(testCase, entry, ...
    row("s1", "1", "2", "A", "", "", "10", "20", "1.5", "", "", ""));
verifyRefusedRow(testCase, ir, "BACKEND_CONFIDENCE_OUT_OF_RANGE");
end

function testAnUndeclaredCallerLabelIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "Z", "0.4", "", "10", "20", "", "", "", ""));
verifyRefusedRow(testCase, ir, "ATTRIBUTION_CALLER_LABEL_UNDECLARED");
end

function testAnUndeclaredChannelIndexIsRefused(testCase)
entry = shippedEntry(testCase);
entry.channel_evidence.entries = struct(channel_index_field="mic", ...
    value_field="mic1_power", evidence_kind="backend_channel_power", ...
    value_units="dB", value_semantics="per-channel power; producer={producer}");
tbl = rowsTable(row("s1", "1", "2", "A", "", "", "10", "20", "", "-41", "", ""));
tbl.mic = "7";
ir = vawlume.source_mapping.mapTableToIR(tbl, entry, SourceKey="source:t");
verifyRefusedRow(testCase, ir, "BACKEND_CHANNEL_UNDECLARED");
end

function testAProbabilityOutsideTheUnitIntervalIsRefused(testCase)
entry = shippedEntry(testCase);
entry.columns.probability = struct(source_field="p");
tbl = rowsTable(row("s1", "1", "2", "A", "", "", "", "", "", "", "", ""));
tbl.p = "1.4";
ir = vawlume.source_mapping.mapTableToIR(tbl, entry, SourceKey="source:t");
verifyRefusedRow(testCase, ir, "ATTRIBUTION_PROBABILITY_OUT_OF_RANGE");
end

function testAScoreWithNoCallerIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "", "0.4", "", "", "", "", "", "", ""));
verifyRefusedRow(testCase, ir, "BACKEND_NUMBER_WITHOUT_CALLER");
end

function testAConfidenceWithNoPositionIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", "", "", "0.8", "", "", ""));
verifyRefusedRow(testCase, ir, "BACKEND_CONFIDENCE_WITHOUT_POSITION");
end

function testANativeValueOfTheWrongTypeIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", "wide"));
verifyRefusedRow(testCase, ir, "BACKEND_ATTRIBUTE_TYPE_INVALID");
end

% --- disagreements are refused, never resolved by keeping the first ---------

function testAWindowRepeatedWithOtherBoundsIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), [
    row("s1", "1", "2", "A", "", "", "", "", "", "", "", "")
    row("s1", "1", "2.5", "B", "", "", "", "", "", "", "", "")]);
verifyEqual(testCase, ir.issues.code, "BACKEND_WINDOW_CONFLICT");
verifyEqual(testCase, ir.attribution_claims.caller_label, "A");
end

function testAClaimRepeatedWithAnotherScoreIsRefused(testCase)
ir = mapRows(testCase, shippedEntry(testCase), [
    row("s1", "1", "2", "A", "0.7", "", "", "", "", "", "", "")
    row("s1", "1", "2", "A", "0.6", "", "", "", "", "", "", "")]);
verifyEqual(testCase, ir.issues.code, "BACKEND_CLAIM_CONFLICT");
verifyEqual(testCase, ir.attribution_claims.score, 0.7);
end

function testAnEstimateRepeatedWithAnotherConfidenceIsRefused(testCase)
entry = shippedEntry(testCase);
entry.localization.native_estimate_id = struct(source_field="est");
tbl = rowsTable([
    row("s1", "1", "2", "A", "", "", "10", "20", "0.9", "", "", "")
    row("s1", "1", "2", "B", "", "", "10", "20", "0.8", "", "", "")]);
tbl.est = ["e1"; "e1"];
ir = vawlume.source_mapping.mapTableToIR(tbl, entry, SourceKey="source:t");
verifyEqual(testCase, ir.issues.code, "BACKEND_ESTIMATE_CONFLICT");
verifyEqual(testCase, ir.attribution_localization_estimates.confidence, 0.9);
end

% --- estimates: identity, ordinals and attachment --------------------------

function testDistinctPositionsInOneWindowAreDistinctEstimates(testCase)
% Two plausible sources for one window: both kept, ordered as the file gave
% them, and neither preferred.
ir = mapRows(testCase, shippedEntry(testCase), [
    row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", "")
    row("s1", "1", "2", "B", "", "", "40", "25", "", "", "", "")]);
estimates = ir.attribution_localization_estimates;
verifyEqual(testCase, estimates.estimate_ordinal', [1 2]);
verifyEqual(testCase, unique(estimates.ordinal_source), "source_order");
verifyEqual(testCase, estimates.claim_key, ["";""]);
end

function testClaimAttachedEstimatesBelongToTheirClaims(testCase)
entry = shippedEntry(testCase);
entry.localization.attachment = "claim";
ir = mapRows(testCase, entry, [
    row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", "")
    row("s1", "1", "2", "B", "", "", "10", "20", "", "", "", "")]);
estimates = ir.attribution_localization_estimates;
verifyEqual(testCase, height(estimates), 2);
verifyEqual(testCase, estimates.claim_key, ir.attribution_claims.claim_key);
end

function testADeclaredOrdinalIsKeptAndMarkedDeclared(testCase)
entry = shippedEntry(testCase);
entry.localization.estimate_ordinal = struct(source_field="rank");
tbl = rowsTable(row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", ""));
tbl.rank = "3";
ir = vawlume.source_mapping.mapTableToIR(tbl, entry, SourceKey="source:t");
verifyEqual(testCase, ir.attribution_localization_estimates.estimate_ordinal, 3);
verifyEqual(testCase, ir.attribution_localization_estimates.ordinal_source, "declared");
end

% --- every element plan section 10 lists is optional -----------------------

function testAWindowsOnlyBackendMaps(testCase)
entry = minimalEntry(testCase);
report = vawlume.source_mapping.validateProfile(entry, ...
    ExpectedKind="attribution_backend_mapping");
verifyTrue(testCase, report.is_valid);
ir = mapRows(testCase, entry, row("s1", "1", "2", "", "", "", "", "", "", "", "", ""));
verifyTrue(testCase, ir.valid_for_ingest);
verifyEqual(testCase, height(ir.attribution_windows), 1);
verifyEmpty(testCase, ir.attribution_claims);
verifyEmpty(testCase, ir.attribution_localization_estimates);
end

function testALocalizationOnlyBackendMaps(testCase)
entry = minimalEntry(testCase);
shipped = shippedEntry(testCase);
entry.context.coordinate_system_key = "arena_floor";
entry.localization = shipped.localization;
entry.value_semantics = struct(position=shipped.value_semantics.position, ...
    confidence=shipped.value_semantics.confidence);
verifyTrue(testCase, vawlume.source_mapping.validateProfile(entry).is_valid);
ir = mapRows(testCase, entry, row("s1", "1", "2", "", "", "", "10", "20", "0.5", "", "", ""));
verifyEqual(testCase, height(ir.attribution_localization_estimates), 1);
verifyEmpty(testCase, ir.attribution_claims);
end

function testAScoringOnlyBackendMaps(testCase)
entry = shippedEntry(testCase);
entry = rmfield(entry, ["localization", "channel_evidence", "native_attributes"]);
entry.columns = rmfield(entry.columns, "native_track_id");
verifyTrue(testCase, vawlume.source_mapping.validateProfile(entry).is_valid);
ir = mapRows(testCase, entry, row("s1", "1", "2", "A", "0.7", "", "10", "20", "", "", "", ""));
verifyEqual(testCase, height(ir.attribution_claims), 1);
verifyEmpty(testCase, ir.attribution_localization_estimates);
end

% --- declared inputs: three states -----------------------------------------

function testDeclaredInputsKeepUndeclaredDistinctFromNotUsed(testCase)
entry = shippedEntry(testCase);
entry.declared_inputs.declarations = struct(acoustic="used", visual_identity="not_used");
ir = mapRows(testCase, entry, row("s1", "1", "2", "A", "", "", "", "", "", "", "", ""));
declared = sortrows(ir.attribution_declared_inputs, "input_dimension");
verifyEqual(testCase, declared.input_dimension, ["acoustic"; "visual_identity"]);
verifyEqual(testCase, declared.declaration, ["used"; "not_used"]);
% pose_localization and temporal_alignment were not declared: no row, not 'not_used'.
verifyFalse(testCase, any(ismember(declared.input_dimension, ...
    ["pose_localization", "temporal_alignment"])));
end

function testTheTemplateDeclaresNothing(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", "", "", "", "", "", ""));
verifyEmpty(testCase, ir.attribution_declared_inputs);
end

% --- native attributes ------------------------------------------------------

function testAnAbsentNativeValueIsRecordedAsMissing(testCase)
entry = shippedEntry(testCase);
entry.native_attributes = struct(attribute_name="quality_flag", source_field="flag", ...
    owner="window", value_type="text");
tbl = rowsTable(row("s1", "1", "2", "A", "", "", "", "", "", "", "", ""));
tbl.flag = "";
ir = vawlume.source_mapping.mapTableToIR(tbl, entry, SourceKey="source:t");
verifyEqual(testCase, ir.attribution_native_attributes.value_type, "missing");
verifyEqual(testCase, ir.attribution_native_attributes.owner_kind, "window");
end

function testANativeValueKeepsItsRawToken(testCase)
ir = mapRows(testCase, shippedEntry(testCase), ...
    row("s1", "1", "2", "A", "", "", "10", "20", "", "", "", "3.50"));
attribute = ir.attribution_native_attributes;
verifyEqual(testCase, attribute.owner_kind, "estimate");
verifyEqual(testCase, attribute.value_real, 3.5);
verifyEqual(testCase, attribute.native_raw_token, "3.50");
end

% --- profile-level refusals -------------------------------------------------

function testALocalizationBlockWithNoFrameIsRefusedAtLoad(testCase)
entry = shippedEntry(testCase);
entry.context = rmfield(entry.context, "coordinate_system_key");
verifyProfileIssue(testCase, entry, "PROFILE_COORDINATE_SYSTEM_UNDECLARED");
end

function testAJsonNativeAttributeTypeIsRefused(testCase)
entry = shippedEntry(testCase);
entry.native_attributes.value_type = "json";
verifyProfileIssue(testCase, entry, "PROFILE_INVALID_FIELD");
end

function testADeclaredInputOutsideTheFourSourcesIsRefused(testCase)
entry = shippedEntry(testCase);
entry.declared_inputs.declarations = struct(source_localization="used");
verifyProfileIssue(testCase, entry, "PROFILE_INVALID_FIELD");
end

function testADeclarationOfUnknownIsRefused(testCase)
% Unknown is expressed by leaving the source out, never stored.
entry = shippedEntry(testCase);
entry.declared_inputs.declarations = struct(acoustic="unknown");
verifyProfileIssue(testCase, entry, "PROFILE_INVALID_FIELD");
end

function testAFixedChannelOutsideTheDeclaredSetIsRefused(testCase)
entry = shippedEntry(testCase);
entry.channel_evidence.entries(1).channel_index = 5;
verifyProfileIssue(testCase, entry, "PROFILE_INVALID_FIELD");
end

function testAScoreWithoutACallerColumnIsRefused(testCase)
entry = shippedEntry(testCase);
entry.columns = rmfield(entry.columns, ["caller_label", "native_track_id"]);
verifyProfileIssue(testCase, entry, "PROFILE_INVALID_FIELD");
end

function testATrackWithoutATrackingStreamIsRefused(testCase)
entry = shippedEntry(testCase);
entry.context = rmfield(entry.context, "tracking_stream_key");
verifyProfileIssue(testCase, entry, "PROFILE_MISSING_FIELD");
end

function testAProfileCannotOptOutOfPreservingValues(testCase)
entry = shippedEntry(testCase);
entry.mapping_policy.preserve_source_values = false;
verifyProfileIssue(testCase, entry, "PROFILE_INVALID_FIELD");
end

function testAProfileWithoutItsWindowColumnsIsRefused(testCase)
entry = shippedEntry(testCase);
entry.columns = rmfield(entry.columns, "window_start");
verifyProfileIssue(testCase, entry, "PROFILE_MISSING_FIELD");
end

% --- the dry run -------------------------------------------------------------

function testThePreviewReportsTheBackendMaterialPerFrame(testCase)
ir = mapRows(testCase, shippedEntry(testCase), [
    row("s1", "1", "2", "A", "0.7", "", "10", "20", "0.9", "-41", "", "")
    row("s2", "3", "4", "A", "", "", "15", "25", "", "", "", "")]);
report = vawlume.source_mapping.preview(ir);
verifyEqual(testCase, report.backend_attribution.estimate_count, 2);
verifyEqual(testCase, report.backend_attribution.estimates_without_confidence, 1);
verifyEqual(testCase, report.backend_attribution.estimates_by_frame.coordinate_system_key, "arena_floor");
verifyTrue(testCase, contains(report.text, "BACKEND ATTRIBUTION"));
verifyTrue(testCase, contains(report.text, "none declared (unknown, not 'not used')"));
verifyEqual(testCase, report.verdict, "READY FOR INGEST");
end

% --- helpers -----------------------------------------------------------------

function entry = shippedEntry(testCase)
document = jsondecode(fileread(testCase.TestData.profilePath));
entry = document.profiles;
if iscell(entry)
    entry = entry{1};
end
entry = entry(1);
end

function entry = minimalEntry(testCase)
% Only what plan section 10 cannot do without: the backend's own window.
shipped = shippedEntry(testCase);
entry = struct();
entry.profile = shipped.profile;
entry.source = shipped.source;
entry.context = rmfield(shipped.context, ["coordinate_system_key", "tracking_stream_key"]);
entry.columns = struct(native_window_id=shipped.columns.native_window_id, ...
    window_start=shipped.columns.window_start, window_end=shipped.columns.window_end);
entry.value_semantics = struct();
end

function values = row(segment, startS, endS, candidate, score, track, x, y, ...
        confidence, mic1, mic2, errMajor)
values = [segment, startS, endS, candidate, score, track, x, y, confidence, ...
    mic1, mic2, errMajor];
end

function tbl = rowsTable(rows)
names = ["segment_id", "start_s", "end_s", "candidate", "assignment_score", "track", ...
    "source_x", "source_y", "localization_confidence", "mic1_power", "mic2_power", ...
    "err_major"];
tbl = array2table(rows, VariableNames=names);
end

function ir = mapRows(~, entry, rows)
ir = vawlume.source_mapping.mapTableToIR(rowsTable(rows), entry, SourceKey="source:t");
end

function verifyRefusedRow(testCase, ir, code)
verifyEqual(testCase, ir.issues.code, string(code));
verifyTrue(testCase, ir.issues.affects_validity);
verifyFalse(testCase, ir.valid_for_ingest);
% All or nothing: the refused row left no fragment behind.
verifyEmpty(testCase, ir.attribution_windows);
verifyEmpty(testCase, ir.attribution_claims);
verifyEmpty(testCase, ir.attribution_localization_estimates);
verifyEmpty(testCase, ir.attribution_channel_evidence);
verifyEmpty(testCase, ir.attribution_native_attributes);
end

function verifyProfileIssue(testCase, entry, code)
report = vawlume.source_mapping.validateProfile(entry, ...
    ExpectedKind="attribution_backend_mapping");
verifyFalse(testCase, report.is_valid);
codes = string(report.issue_table.code);
verifyTrue(testCase, any(codes == code), ...
    "Expected " + code + "; got: " + strjoin(codes, ", "));
end
