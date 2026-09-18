function tests = test_eda_example_sampling
%TEST_EDA_EXAMPLE_SAMPLING The gallery draw, the snippet geometry, and honesty.
%
% Integration tier because every claim here is about the database: which groups
% carry which exact support pattern, and what each extractor actually measured.
% The no-fabrication rule in particular can only be tested against the real
% registry, because the whole point is that USVSEG registers no band edges.
%
% One test reads a real WAV through readAudioWindow. The rest need a database and
% no audio, so the fixture writes the WAV once and only that test uses it.
tests = functiontests({ ...
    @setupOnce, @teardownOnce, ...
    @testTheSameSeedDrawsTheSameGallery, ...
    @testAnInterveningGlobalRngCallChangesNothing, ...
    @testAPatternWithTooFewGroupsIsReportedNotPadded, ...
    @testEveryPatternGetsACoverageRowIncludingEmptyOnes, ...
    @testTheInheritedExtractorSetFilterAgreesWithTheFrame, ...
    @testAnUnseededOrOversizedDrawIsRefused, ...
    @testTheWindowIsTheGroupExtentPlusPadding, ...
    @testClampingAtARecordingBoundaryIsRecorded, ...
    @testTheChannelIsNeverChosenBySignalContent, ...
    @testFrequencyBoundsAreDerivedFromMeasuredExtents, ...
    @testFrequencyBoundsAreDefaultedWhenNothingWasMeasured, ...
    @testTheMixedGroupProducesOneAnnotationPerExtentSource, ...
    @testADetectionWithACentreAndNoBandEdgesProducesNoRectangle, ...
    @testExtentsResolveByEquivalenceClassNotExtractorName, ...
    @testAClippedDetectionIsFlagged, ...
    @testTheApproximateExtentStatementIsCarried, ...
    @testTheReferenceIdentityTravelsWithEveryExample, ...
    @testAWindowIsReadFromRealAudioAndTransformed, ...
    @testNothingIsWrittenAndNoGuardedFileIsEdited});
end

% --------------------------------------------------------- shared fixture ---

function setupOnce(testCase)
[fixture, cleanup] = setUpFixture();
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
testCase.TestData.context = referenceRun(fixture);
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

% ---------------------------------------------------------------- sampling ---

function testTheSameSeedDrawsTheSameGallery(testCase)
context = testCase.TestData.context;
first = drawGallery(testCase, 7);
second = drawGallery(testCase, 7);

verifyEqual(testCase, first.examples.agreement_group_id, ...
    second.examples.agreement_group_id);
verifyEqual(testCase, first.examples.example_id, second.examples.example_id);
verifyEqual(testCase, first.examples.selection_key, ...
    second.examples.selection_key);
verifyEqual(testCase, first.seed, 7);
verifyEqual(testCase, first.random_stream_generator, "mt19937ar");
verifySubstring(testCase, first.ordering_key, "group_key");
verifyEqual(testCase, context.sample.target_per_pattern, 3);
end

function testAnInterveningGlobalRngCallChangesNothing(testCase)
%TESTANINTERVENINGGLOBALRNGCALL... The defect the local stream prevents.
%
% Part 9 recorded that an `rng(seed)`-based implementation is immune to this
% inbound test and is caught by the outbound one instead, so both directions are
% asserted here too.
first = drawGallery(testCase, 7);

rng(4242);
rand(13, 1);
rng("shuffle");
rand(3, 5);

second = drawGallery(testCase, 7);
verifyEqual(testCase, first.examples.agreement_group_id, ...
    second.examples.agreement_group_id);

% And the global generator is left exactly as it was found. Moved to a known
% state first, or the check is order-dependent and asserts nothing.
rng(20260918);
rand(2, 1);
before = rng();
drawGallery(testCase, 7);
after = rng();
verifyEqual(testCase, after.Seed, before.Seed);
verifyEqual(testCase, after.State, before.State);
end

function testAPatternWithTooFewGroupsIsReportedNotPadded(testCase)
%TESTAPATTERNWITHTOOFEWGROUPS... A balanced gallery would misrepresent the data.
context = testCase.TestData.context;
sample = context.sample;

short = sample.coverage(sample.coverage.is_short, :);
verifyNotEmpty(testCase, short);

for index = 1:height(short)
    row = short(index, :);
    verifyEqual(testCase, row.drawn, min(row.target, row.available), ...
        "Pattern " + row.extractor_set_key + " drew more than it had.");
    verifyEqual(testCase, row.shortfall, row.target - row.available);
    verifyGreaterThan(testCase, strlength(row.shortfall_reason), 0);
end

% Nothing was borrowed: every drawn example belongs to the pattern it is
% filed under, checked against the members rather than against the label.
for index = 1:height(sample.examples)
    row = sample.examples(index, :);
    members = fetch(testCase.TestData.fixture.conn, ...
        "SELECT DISTINCT IFNULL(extractor_key,'') AS extractor_key " + ...
        "FROM v_agreement_group_members WHERE agreement_group_id=" + ...
        string(row.agreement_group_id) + " ORDER BY extractor_key");
    actual = strjoin(sort(string(members.extractor_key))', "|");
    verifyEqual(testCase, actual, row.extractor_set_key, ...
        "Example " + row.example_id + " is filed under a pattern its " + ...
        "members do not form.");
end

% Drawn never exceeds the target anywhere.
verifyTrue(testCase, all(sample.coverage.drawn <= sample.coverage.target));
verifyEqual(testCase, sum(sample.coverage.drawn), height(sample.examples));
verifySubstring(testCase, sample.no_padding, "never borrowed from another");
end

function testEveryPatternGetsACoverageRowIncludingEmptyOnes(testCase)
%TESTEVERYPATTERNGETSACOVERAGEROW... An absent row looks like an unsampled one.
context = testCase.TestData.context;
coverage = context.sample.coverage;

verifyEqual(testCase, height(coverage), 7);
verifyEqual(testCase, sort(coverage.extractor_set_key), sort([ ...
    "deepsqueak"; "mupet"; "usvseg"; "deepsqueak|mupet"; ...
    "deepsqueak|usvseg"; "mupet|usvseg"; "deepsqueak|mupet|usvseg"]));

empty = coverage(coverage.is_empty, :);
verifyEqual(testCase, height(empty), 3, ...
    "The fixture's three empty patterns are not all reported.");
verifyTrue(testCase, all(empty.drawn == 0));
verifyTrue(testCase, all(contains(empty.shortfall_reason, "no group")));
verifySubstring(testCase, context.sample.shortfall_note, ...
    "not a gap to be filled");
end

function testTheInheritedExtractorSetFilterAgreesWithTheFrame(testCase)
%TESTTHEINHERITEDEXTRACTORSETFILTER... Reuse, verified rather than assumed.
%
% The itinerary asks to reuse selectPopulation's existing filter. It is reused -
% and its result is compared against the extractor set recomputed from members,
% because `extractor_set_key` is built with group_concat over an ordered
% subquery whose ordering is not guaranteed. A differently ordered key would
% select nothing and look like an empty pattern: a gallery short by a whole
% category with no error anywhere.
context = testCase.TestData.context;
conn = testCase.TestData.fixture.conn;

for index = 1:height(context.sample.coverage)
    setKey = context.sample.coverage.extractor_set_key(index);
    filtered = vawlume.agreement.selectPopulation(conn, ...
        struct(run_key=context.agreement_run_key), ExtractorSetKey=setKey);
    verifyEqual(testCase, height(filtered.groups), ...
        context.sample.coverage.available(index), ...
        "The inherited filter and the frame disagree for " + setKey + ".");
end
end

function testAnUnseededOrOversizedDrawIsRefused(testCase)
context = testCase.TestData.context;
conn = testCase.TestData.fixture.conn;
ref = context.reference;
analysis = struct(run_key=context.agreement_run_key);

verifyError(testCase, @() vawlume.eda.sampleExamples(conn, analysis, ref), ...
    "vawlume:eda:ExampleSeedMissing");
verifyError(testCase, @() vawlume.eda.sampleExamples(conn, analysis, ref, ...
    Seed=1, TargetPerPattern=11), "vawlume:eda:ExampleTargetInvalid");
verifyError(testCase, @() vawlume.eda.sampleExamples(conn, analysis, ref, ...
    Seed=1, TargetPerPattern=0), "vawlume:eda:ExampleTargetInvalid");
end

% ----------------------------------------------------------- the geometry ---

function testTheWindowIsTheGroupExtentPlusPadding(testCase)
context = testCase.TestData.context;
prepared = prepare(testCase, context.three_way_example, ...
    PaddingPreS=0.02, PaddingPostS=0.03);

extent = prepared.group_extent;
window = prepared.window;

verifyEqual(testCase, extent.extent_method, "union_boundary_of_members");
verifyEqual(testCase, extent.source, "v_agreement_group_extent");
verifyEqual(testCase, window.requested_start_s, extent.start_time_s - 0.02, ...
    AbsTol=1e-12);
verifyEqual(testCase, window.requested_end_s, extent.end_time_s + 0.03, ...
    AbsTol=1e-12);
verifyEqual(testCase, window.actual_start_s, window.requested_start_s, ...
    AbsTol=1e-12);
verifyFalse(testCase, window.is_clamped_at_start);
verifyFalse(testCase, window.is_clamped_at_end);
verifyEqual(testCase, window.padding_pre_s, 0.02);
verifyEqual(testCase, window.padding_post_s, 0.03);

% The union extent really is the union of the members.
members = prepared.annotations;
verifyEqual(testCase, extent.start_time_s, min(members.start_time_s), ...
    AbsTol=1e-9);
verifyEqual(testCase, extent.end_time_s, max(members.end_time_s), AbsTol=1e-9);

% Zero padding is a legitimate request and gives the extent exactly.
tight = prepare(testCase, context.three_way_example, ...
    PaddingPreS=0, PaddingPostS=0);
verifyEqual(testCase, tight.window.actual_start_s, extent.start_time_s, ...
    AbsTol=1e-12);
verifyEqual(testCase, tight.window.actual_end_s, extent.end_time_s, ...
    AbsTol=1e-12);
end

function testClampingAtARecordingBoundaryIsRecorded(testCase)
%TESTCLAMPINGATARECORDINGBOUNDARY... An off-centre call and a clamped one differ.
context = testCase.TestData.context;

% Padding wider than the call's distance from the start of the recording.
early = prepare(testCase, context.three_way_example, ...
    PaddingPreS=1000, PaddingPostS=0.01);
verifyTrue(testCase, early.window.is_clamped_at_start);
verifyEqual(testCase, early.window.actual_start_s, 0);
verifyLessThan(testCase, early.window.requested_start_s, 0);
verifyFalse(testCase, early.window.is_symmetric);
verifyLessThan(testCase, early.window.realized_padding_pre_s, 1000);
verifySubstring(testCase, early.window.clamp_note, "not that the call sits");

% And at the end of the recording.
late = prepare(testCase, context.three_way_example, ...
    PaddingPreS=0.01, PaddingPostS=1e6);
verifyTrue(testCase, late.window.is_clamped_at_end);
verifyEqual(testCase, late.window.actual_end_s, ...
    late.recording.duration_s, AbsTol=1e-9);
verifyGreaterThan(testCase, late.window.requested_end_s, ...
    late.recording.duration_s);

% Requested is preserved unchanged in both, which is what makes the clamp
% visible rather than merely absorbed: the requested duration is the group
% extent plus both paddings, whatever the recording could actually supply.
verifyEqual(testCase, early.window.requested_duration_s, ...
    early.group_extent.duration_s + 1000 + 0.01, AbsTol=1e-9);
verifyGreaterThan(testCase, early.window.requested_duration_s, ...
    early.window.actual_duration_s);
end

function testTheChannelIsNeverChosenBySignalContent(testCase)
context = testCase.TestData.context;
prepared = prepare(testCase, context.three_way_example);

verifyEqual(testCase, prepared.channel.channel_index, 1);
verifyEqual(testCase, prepared.channel.selection_source, "only_channel");
verifySubstring(testCase, prepared.channel.selection_rule, ...
    "never chosen by signal energy");

% No function in this part reads samples before choosing a channel, which is
% the property that makes a content-dependent choice impossible rather than
% merely absent.
source = codeOnly(fileread(fullfile(repoRootPath(), "src", "+vawlume", ...
    "+eda", "prepareExample.m")));
channelBlock = extractBetween(source, "function value = resolveChannel", ...
    "function value = frequencyBounds");
verifyEqual(testCase, numel(strfind(string(channelBlock), "samples")), 0, ...
    "Channel selection reads samples.");
verifyEqual(testCase, numel(strfind(string(channelBlock), "readAudioWindow")), 0);
end

function testFrequencyBoundsAreDerivedFromMeasuredExtents(testCase)
context = testCase.TestData.context;
prepared = prepare(testCase, context.three_way_example, ...
    FrequencyMarginHz=5000);
bounds = prepared.frequency_bounds;

verifyEqual(testCase, bounds.source, "derived");
verifySubstring(testCase, bounds.detail, "measured frequency extremes");

measured = [prepared.annotations.frequency_min_hz; ...
    prepared.annotations.frequency_max_hz; ...
    prepared.annotations.frequency_center_hz; ...
    prepared.annotations.frequency_peak_hz];
measured = measured(isfinite(measured));
verifyNotEmpty(testCase, measured);
verifyEqual(testCase, bounds.low_hz, max(min(measured) - 5000, 0), ...
    AbsTol=1e-9);
verifyEqual(testCase, bounds.high_hz, min(max(measured) + 5000, ...
    bounds.nyquist_hz), AbsTol=1e-9);
verifyEqual(testCase, bounds.measured_value_count, numel(measured));

% Never above Nyquist, whatever the margin.
wide = prepare(testCase, context.three_way_example, ...
    FrequencyMarginHz=1e7);
verifyLessThanOrEqual(testCase, wide.frequency_bounds.high_hz, ...
    wide.frequency_bounds.nyquist_hz);
verifyTrue(testCase, wide.frequency_bounds.is_clamped_at_nyquist);
end

function testFrequencyBoundsAreDefaultedWhenNothingWasMeasured(testCase)
%TESTFREQUENCYBOUNDSAREDEFAULTED... A defaulted axis looks like a derived one.
%
% Built on a copy so the shared fixture keeps its measurements: every frequency
% measurement for one group's members is removed, which is the all-unavailable
% case a recording processed by a timing-only extractor would give.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
context = referenceRun(fixture);
groupId = context.three_way_example.agreement_group_id;

execute(fixture.conn, "DELETE FROM event_measurements WHERE detection_id IN " + ...
    "(SELECT detection_id FROM agreement_group_members " + ...
    "WHERE agreement_group_id=" + string(groupId) + ")");

prepared = vawlume.eda.prepareExample(fixture.conn, ...
    context.three_way_example, IncludeAudio=false, ...
    DefaultFrequencyLimitsHz=[25000, 95000]);
bounds = prepared.frequency_bounds;

verifyEqual(testCase, bounds.source, "defaulted");
verifyEqual(testCase, bounds.low_hz, 25000);
verifyEqual(testCase, bounds.high_hz, 95000);
verifyEqual(testCase, bounds.measured_value_count, 0);
verifySubstring(testCase, bounds.detail, "not from the data");
verifyTrue(testCase, all(prepared.annotations.frequency_extent_source == ...
    "unavailable"));
verifyTrue(testCase, all(~prepared.annotations.has_measured_band));
end

% ------------------------------------------------- annotations and honesty ---

function testTheMixedGroupProducesOneAnnotationPerExtentSource(testCase)
%TESTTHEMIXEDGROUPPRODUCES... The realistic DeepSqueak + MUPET + USVSEG case.
context = testCase.TestData.context;
prepared = prepare(testCase, context.three_way_example);
annotations = prepared.annotations;

verifyEqual(testCase, height(annotations), 3);
verifyEqual(testCase, sort(annotations.extractor_key), ...
    sort(["deepsqueak"; "mupet"; "usvseg"]));

% DeepSqueak and MUPET register band edges; USVSEG registers neither and
% reports a centre and a peak instead.
for key = ["deepsqueak", "mupet"]
    row = annotations(annotations.extractor_key == key, :);
    verifyEqual(testCase, row.frequency_extent_source, "band_edges", ...
        key + " did not produce a band-edge annotation.");
    verifyTrue(testCase, row.has_measured_band);
    verifyTrue(testCase, isfinite(row.frequency_min_hz));
    verifyTrue(testCase, isfinite(row.frequency_max_hz));
    verifyGreaterThan(testCase, row.frequency_max_hz, row.frequency_min_hz);
    verifySubstring(testCase, row.rendering, "rectangle");
end

usvseg = annotations(annotations.extractor_key == "usvseg", :);
verifyEqual(testCase, usvseg.frequency_extent_source, "center_and_peak");
verifyTrue(testCase, isfinite(usvseg.frequency_center_hz));
verifyTrue(testCase, isfinite(usvseg.frequency_peak_hz));
verifySubstring(testCase, usvseg.rendering, "two measured frequency markers");

% Every annotation carries the identity a caption needs.
verifyTrue(testCase, all(strlength(annotations.native_event_id) > 0));
verifyTrue(testCase, all(annotations.end_time_s > annotations.start_time_s));
verifyTrue(testCase, all(ismember(annotations.frequency_extent_source, ...
    prepared.extent_vocabulary)));
end

function testADetectionWithACentreAndNoBandEdgesProducesNoRectangle(testCase)
%TESTADETECTIONWITHACENTREANDNOBANDEDGES... Asserted as an ABSENCE.
%
% This is MVP success criterion 8 and the easiest defect in the part to ship by
% accident. Verified as a negative result: an implementation that fills the band
% from the centre value - `min = centre - width/2`, by any route, including from
% the coefficient of variation USVSEG does report - makes this test fail on
% `has_measured_band` and on both NaN assertions.
%
% The assertion is on the GEOMETRY, not on the tag. A tag can be correct while
% the band beside it is populated, and it is the band that gets drawn.
context = testCase.TestData.context;
prepared = prepare(testCase, context.three_way_example);
usvseg = prepared.annotations(prepared.annotations.extractor_key == ...
    "usvseg", :);

verifyEqual(testCase, height(usvseg), 1);
verifyFalse(testCase, usvseg.has_measured_band, ...
    "USVSEG acquired a measured band, which it does not report.");
verifyTrue(testCase, isnan(usvseg.frequency_min_hz), ...
    "A lower band edge was synthesized for USVSEG.");
verifyTrue(testCase, isnan(usvseg.frequency_max_hz), ...
    "An upper band edge was synthesized for USVSEG.");

% USVSEG's centre and peak ARE present, so the absence above is about the band
% and not about the annotation being empty.
verifyGreaterThan(testCase, usvseg.frequency_center_hz, 0);
verifyGreaterThan(testCase, usvseg.frequency_peak_hz, 0);

% And the registry agrees that it registers no band edges, so the absence is a
% property of the data rather than of this particular group.
registered = fetch(testCase.TestData.fixture.conn, ...
    "SELECT COUNT(*) AS n FROM extractor_features xf " + ...
    "JOIN extractor_versions ev " + ...
    "ON ev.extractor_version_id=xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE e.extractor_key='usvseg' AND xf.equivalence_class IN " + ...
    "('vocalization_frequency_min','vocalization_frequency_max')");
verifyEqual(testCase, double(registered.n(1)), 0);

% The coefficient of variation is never read at all, so it cannot become a
% width. Conceptual spec §7.4 names it as one of the forbidden routes.
source = codeOnly(fileread(fullfile(repoRootPath(), "src", "+vawlume", ...
    "+eda", "private", "edaMemberAnnotations.m")));
verifyEqual(testCase, numel(strfind(source, "vocalization_frequency_cv")), 0, ...
    "The annotation layer reads the coefficient of variation.");
end

function testExtentsResolveByEquivalenceClassNotExtractorName(testCase)
%TESTEXTENTSRESOLVEBYEQUIVALENCECLASS... An extractor added later just works.
%
% Demonstrated with an extractor named in no code path: a fourth extractor is
% registered with a band-edge feature pair, a detection of its own, and
% measurements, then added to an existing group. Its annotation comes out as
% `band_edges` without a line of code mentioning it.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
context = referenceRun(fixture);
groupId = context.three_way_example.agreement_group_id;
addFourthExtractor(fixture.conn, groupId);

prepared = vawlume.eda.prepareExample(fixture.conn, ...
    context.three_way_example, IncludeAudio=false);
annotations = prepared.annotations;

verifyEqual(testCase, height(annotations), 4);
newcomer = annotations(annotations.extractor_key == "fourthkit", :);
verifyEqual(testCase, height(newcomer), 1);
verifyEqual(testCase, newcomer.frequency_extent_source, "band_edges");
verifyTrue(testCase, newcomer.has_measured_band);
verifyEqual(testCase, newcomer.frequency_min_hz, 41000);
verifyEqual(testCase, newcomer.frequency_max_hz, 77000);

% And no source file in this part names any extractor.
root = repoRootPath();
for name = ["prepareExample.m", "sampleExamples.m", "spectrogramMatrix.m"]
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    for extractor = ["deepsqueak", "mupet", "usvseg", "fourthkit", ...
            "DeepSqueak", "MUPET", "USVSEG"]
        verifyEqual(testCase, numel(strfind(source, extractor)), 0, ...
            name + " names the extractor '" + extractor + "'.");
    end
end
source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", ...
    "private", "edaMemberAnnotations.m")));
for extractor = ["deepsqueak", "mupet", "usvseg", "DeepSqueak", "MUPET", "USVSEG"]
    verifyEqual(testCase, numel(strfind(source, extractor)), 0, ...
        "edaMemberAnnotations names the extractor '" + extractor + "'.");
end

% It is not v_event_measurements_long either, which has no equivalence_class
% column and would force a canonical-name join.
verifyEqual(testCase, numel(strfind(source, "v_event_measurements_long")), 0);
verifyGreaterThan(testCase, numel(strfind(source, "equivalence_class")), 0);
end

function testAClippedDetectionIsFlagged(testCase)
%TESTACLIPPEDDETECTIONISFLAGGED... A clipped call and a short one look the same.
context = testCase.TestData.context;

% Negative padding is not offered, so the window is narrowed by preparing with
% zero padding and then checking a member that starts before the union end.
tight = prepare(testCase, context.three_way_example, ...
    PaddingPreS=0, PaddingPostS=0);
verifyTrue(testCase, all(~tight.annotations.is_clipped_by_window), ...
    "A member is clipped by a window that spans the union of all members.");

% Clipping is reachable through the recording-duration clamp, which is the
% real scenario: the metadata declares a duration and a detection runs past it.
% On a copy, the declared duration is pulled back inside the group's extent, so
% the window ends before the last member does.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
copyContext = referenceRun(fixture);
extent = vawlume.eda.prepareExample(fixture.conn, ...
    copyContext.three_way_example, IncludeAudio=false).group_extent;
cut = extent.start_time_s + 0.25 * (extent.end_time_s - extent.start_time_s);
execute(fixture.conn, "UPDATE recordings SET duration_s=" + ...
    sprintf("%.17g", cut) + " WHERE recording_id=1");

prepared = vawlume.eda.prepareExample(fixture.conn, ...
    copyContext.three_way_example, IncludeAudio=false, PaddingPreS=0, ...
    PaddingPostS=0);
clipped = prepared.annotations;

verifyTrue(testCase, prepared.window.is_clamped_at_end);
verifyTrue(testCase, any(clipped.is_clipped_by_window), ...
    "No member was flagged as clipped by a window the recording cut short.");
flagged = clipped(clipped.is_clipped_by_window, :);
verifyTrue(testCase, all(flagged.outside_window_s > 0));
verifyTrue(testCase, all(clipped.outside_window_s( ...
    ~clipped.is_clipped_by_window) == 0));

% A clipped annotation and a short call are different facts, and the first is
% recorded rather than left to the picture.
verifyGreaterThan(testCase, max(flagged.outside_window_s), 0);
end

function testTheApproximateExtentStatementIsCarried(testCase)
%TESTTHEAPPROXIMATEEXTENTSTATEMENT... A rectangle is not a segmentation.
context = testCase.TestData.context;
prepared = prepare(testCase, context.three_way_example);

verifySubstring(testCase, prepared.approximate_extent_note, ...
    "APPROXIMATE EXTENT");
verifySubstring(testCase, prepared.approximate_extent_note, ...
    "not the extractor's native segmentation contour");
verifyEqual(testCase, sort(prepared.extent_vocabulary), sort([ ...
    "band_edges", "center_only", "peak_only", "center_and_peak", ...
    "unavailable"]));
verifySubstring(testCase, prepared.draws_nothing, "no figure");
end

function testTheReferenceIdentityTravelsWithEveryExample(testCase)
context = testCase.TestData.context;
sample = context.sample;

verifyEqual(testCase, sample.reference_configuration.profile_key, ...
    "vawlume.matching.prototype.v1");
verifyEqual(testCase, sample.reference_configuration.calibration_state, ...
    "illustrative_prototype");
verifyTrue(testCase, all(sample.examples.reference_profile_key == ...
    "vawlume.matching.prototype.v1"));
verifyTrue(testCase, all(strlength( ...
    sample.examples.reference_checksum_sha256) == 64));

prepared = prepare(testCase, context.three_way_example);
verifyEqual(testCase, prepared.reference_configuration.profile_key, ...
    "vawlume.matching.prototype.v1");
end

% ------------------------------------------------------------- real audio ---

function testAWindowIsReadFromRealAudioAndTransformed(testCase)
%TESTAWINDOWISREADFROMREALAUDIO... The one test that touches a WAV.
%
% Everything else here is geometry over database rows. This is the test that
% proves the geometry reaches `readAudioWindow` correctly and that the samples it
% returns transform into a matrix whose settings regenerate it.
context = testCase.TestData.context;
fixture = testCase.TestData.fixture;

prepared = vawlume.eda.prepareExample(fixture.conn, ...
    context.three_way_example, PaddingPreS=0.02, PaddingPostS=0.02, ...
    SourceRoot=fixture.source_root);

audio = prepared.audio;
verifyEqual(testCase, audio.status, "covered_populated");
verifyGreaterThan(testCase, audio.sample_count, 0);
verifyEqual(testCase, audio.sample_rate_hz, fixture.sample_rate_hz);
verifyEqual(testCase, audio.channel_index, 1);

% The window reached readAudioWindow unchanged.
verifyEqual(testCase, audio.requested_interval_s, ...
    [prepared.window.actual_start_s, prepared.window.actual_end_s], ...
    AbsTol=1e-12);

spectrogram = prepared.spectrogram;
verifyEqual(testCase, spectrogram.status, "computed");
verifyGreaterThan(testCase, spectrogram.frame_count, 0);
verifyGreaterThan(testCase, spectrogram.bin_count, 0);
verifyEqual(testCase, size(spectrogram.matrix), ...
    [spectrogram.bin_count, spectrogram.frame_count]);

% The band the settings asked for is the band that came back.
verifyGreaterThanOrEqual(testCase, min(spectrogram.frequency_hz), ...
    prepared.frequency_bounds.low_hz - 1e-6);
verifyLessThanOrEqual(testCase, max(spectrogram.frequency_hz), ...
    prepared.frequency_bounds.high_hz + 1e-6);

% The record regenerates the matrix from the same samples.
regenerated = vawlume.eda.spectrogramMatrix(audio.samples, ...
    audio.sample_rate_hz, Settings=spectrogram.settings);
verifyEqual(testCase, regenerated.matrix, spectrogram.matrix);

% The window record's padding and channel reached the settings, because the
% example index carries one record rather than two.
verifyEqual(testCase, spectrogram.settings.padding_pre_s, 0.02);
verifyEqual(testCase, spectrogram.settings.channel_index, 1);

% The synthetic tone is where it was written, which is what says the samples
% belong to this example rather than to some other part of the recording.
[~, peakBin] = max(mean(spectrogram.matrix, 2));
verifyEqual(testCase, spectrogram.frequency_hz(peakBin), ...
    fixture.tone_hz, AbsTol=4000);
end

% ---------------------------------------------------------------- tripwire ---

function testNothingIsWrittenAndNoGuardedFileIsEdited(testCase)
%TESTNOTHINGISWRITTEN... Part 12 computes; it stores nothing and draws nothing.
%
% The guarded paths matter for a named reason: the tempting way to make the
% gallery uniform is to add frequency-extent mappings to the USVSEG profile so
% every annotation is a rectangle. The extractor does not report them, so that
% would fabricate data and fail MVP success criterion 8.
root = repoRootPath();
files = ["sampleExamples.m", "prepareExample.m", "spectrogramMatrix.m"];
for name = files
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    for token = ["INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE ", "DROP "]
        verifyEqual(testCase, numel(strfind(source, token)), 0, ...
            name + " contains '" + token + "'.");
    end
end

[status, output] = system("git -C """ + root + """ status --porcelain");
verifyEqual(testCase, status, 0, "git status failed.");
changed = strtrim(splitlines(string(output)));
changed = changed(strlength(changed) > 0);
guarded = ["src/+vawlume/+acoustic/", "config/01_mapping_profiles/", ...
    "schema/", "src/+vawlume/+consilience/"];
for line = changed'
    path = extractAfter(line, 3);
    for prefix = guarded
        verifyFalse(testCase, startsWith(path, prefix), ...
            "Part 12 modified a guarded path: " + path);
    end
end

% And observably: sampling and preparing change no row.
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
context = referenceRun(fixture);
before = tableCounts(fixture.conn);
vawlume.eda.sampleExamples(fixture.conn, ...
    struct(run_key=context.agreement_run_key), context.reference, Seed=2);
vawlume.eda.prepareExample(fixture.conn, context.three_way_example, ...
    IncludeAudio=false);
verifyEqual(testCase, tableCounts(fixture.conn), before);
end

% ---------------------------------------------------------------- helpers ---

function value = drawGallery(testCase, seed)
context = testCase.TestData.context;
value = vawlume.eda.sampleExamples(testCase.TestData.fixture.conn, ...
    struct(run_key=context.agreement_run_key), context.reference, Seed=seed);
end

function value = prepare(testCase, example, varargin)
% IncludeAudio is passed positionally in the cell so it precedes no name=value
% pair: MATLAB refuses a name=value argument followed by any other input, and
% `varargin{:}` counts as one.
value = vawlume.eda.prepareExample(testCase.TestData.fixture.conn, ...
    example, "IncludeAudio", false, varargin{:});
end

function value = tableCounts(conn)
names = ["detections", "event_measurements", "agreement_groups", ...
    "agreement_group_members", "analysis_runs", "extractor_features"];
value = zeros(numel(names), 1);
for index = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(index));
    value(index) = double(rows.n(1));
end
end

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function value = codeOnly(source)
lines = splitlines(string(source));
value = strjoin(lines(~startsWith(strtrim(lines), "%")), newline);
end

function addFourthExtractor(conn, groupId)
%ADDFOURTHEXTRACTOR An extractor named in no code path, with band edges.
%
% Registered end to end - extractor, version, run, detection, features,
% measurements - and attached to an existing group, so its annotation has to come
% out of the same registry path as every other. Its band edges are distinctive
% values so the test can tell them from a neighbour's.
execute(conn, "INSERT INTO extractors(extractor_id,extractor_key," + ...
    "extractor_name) VALUES(90,'fourthkit','FourthKit')");
execute(conn, "INSERT INTO extractor_versions(extractor_version_id," + ...
    "extractor_id,version_label) VALUES(90,90,'1.0')");
execute(conn, "INSERT INTO extraction_runs(extraction_run_id,project_id," + ...
    "extractor_version_id,run_key,status) " + ...
    "VALUES(90,1,90,'fixture_fourthkit_v1','imported')");
execute(conn, "INSERT INTO extraction_run_inputs(extraction_run_id," + ...
    "recording_id,input_role) VALUES(90,1,'source_audio')");

reference = fetch(conn, "SELECT d.recording_id, d.start_time_s, d.end_time_s " + ...
    "FROM agreement_group_members m JOIN detections d " + ...
    "ON d.detection_id=m.detection_id WHERE m.agreement_group_id=" + ...
    string(groupId) + " LIMIT 1");
execute(conn, "INSERT INTO detections(detection_id,extraction_run_id," + ...
    "recording_id,native_event_id,start_time_s,end_time_s,timing_basis) " + ...
    "VALUES(900,90," + string(double(reference.recording_id(1))) + ...
    ",'fourthkit-1'," + sprintf("%.17g", double(reference.start_time_s(1))) + ...
    "," + sprintf("%.17g", double(reference.end_time_s(1))) + ...
    ",'profile_selected_event_geometry')");

execute(conn, "INSERT INTO extractor_features(extractor_feature_id," + ...
    "extractor_version_id,native_name,equivalence_class,native_unit) " + ...
    "VALUES(900,90,'lo_hz','vocalization_frequency_min','Hz')," + ...
    "(901,90,'hi_hz','vocalization_frequency_max','Hz')");
execute(conn, "INSERT INTO event_measurements(detection_id," + ...
    "extractor_feature_id,native_value_type,native_value_real," + ...
    "native_unit,canonical_value_real,canonical_unit) " + ...
    "VALUES(900,900,'real',41,'kHz',41000,'Hz')," + ...
    "(900,901,'real',77,'kHz',77000,'Hz')");

% The schema refuses a member whose extraction run is not an input to the
% analysis, which is correct: a group may only contain detections the analysis
% actually considered. So the run is registered as an input first, exactly as a
% genuine four-extractor analysis would have it.
execute(conn, "INSERT INTO analysis_run_extraction_inputs(analysis_run_id," + ...
    "extraction_run_id,input_role) SELECT analysis_run_id, 90, 'input' " + ...
    "FROM agreement_groups WHERE agreement_group_id=" + string(groupId));
execute(conn, "INSERT INTO agreement_group_members(agreement_group_id," + ...
    "detection_id,member_role) VALUES(" + string(groupId) + ",900,'member')");
end

% ---------------------------------------------------------------- fixture ---

function context = referenceRun(fixture)
reference = vawlume.eda.referenceConfiguration(RepoRoot=fixture.repo_root);
design = vawlume.eda.referenceDesign(reference);
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
run = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true, ProbeRole="reference");
agreement = run.manifest.run_key(run.manifest.unit_kind == "agreement" & ...
    ismember(run.manifest.status, ["committed", "reused"]));

sample = vawlume.eda.sampleExamples(fixture.conn, ...
    struct(run_key=agreement(1)), reference, Seed=5);
threeWay = sample.examples(sample.examples.extractor_set_key == ...
    "deepsqueak|mupet|usvseg", :);
context = struct(reference=reference, agreement_run_key=agreement(1), ...
    run=run, sample=sample, three_way_example=threeWay(1, :));
end

function [fixture, cleanup] = setUpFixture()
%SETUPFIXTURE The phase-1 fixture, plus one synthesized WAV.
%
% THE WAV IS NOT COMMITTED. It is synthesized here deterministically, following
% `test_acoustic_reference_measurement`'s precedent: repository policy keeps
% research audio out and allows small deterministic fixtures, and a tone written
% by three lines of arithmetic is more inspectable than a committed binary.
%
% The recording's declared sample rate is lowered to 192 kHz on this copy only.
% The fixture declares 384 kHz over 60 seconds, which is 23 million samples and
% about 46 MB of WAV for a test that reads 150 milliseconds of it; 192 kHz still
% puts Nyquist at 96 kHz, above the fixture's 80 kHz call band, so nothing the
% test asserts about frequency is distorted by the change.
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "examples.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch));

sampleRate = 192000;
toneHz = 62000;
execute(conn, "UPDATE recordings SET sample_rate_hz=" + string(sampleRate) + ...
    " WHERE recording_id=1");

sourceRoot = fullfile(scratch, "source");
audioPath = fullfile(sourceRoot, "synthetic", "recordings", ...
    "session_social_dyad_01.wav");
mkdir(fileparts(audioPath));
writeToneWav(audioPath, sampleRate, toneHz);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    source_root=string(sourceRoot), audio_path=string(audioPath), ...
    sample_rate_hz=sampleRate, tone_hz=toneHz);
end

function writeToneWav(path, sampleRate, toneHz)
%WRITETONEWAV A short ultrasonic tone burst covering the fixture's first call.
%
% 10.2 seconds so the window around the fixture's earliest group (about 9.95 to
% 10.10 s) is fully covered, and no longer: the file is 2 million samples as it
% is. The burst is amplitude-tapered so its edges do not transform into
% broadband clicks that would dominate the spectrum the test inspects.
durationS = 10.2;
n = round(durationS * sampleRate);
t = (0:(n - 1))' / sampleRate;
samples = zeros(n, 1);

burst = t >= 9.98 & t <= 10.09;
local = t(burst) - 9.98;
taper = sin(pi * local / (local(end) - local(1))) .^ 2;
samples(burst) = 0.7 * taper .* sin(2 * pi * toneHz * t(burst));

audiowrite(char(path), samples, sampleRate, BitsPerSample=16);
end

function path = fixtureTemplate(repoRoot)
persistent value
if isempty(value) || ~isfile(value)
    value = string(tempname) + ".sqlite";
    [conn, ~] = vawlume.db.createPhase1FixtureDatabase(value, repoRoot);
    close(conn);
end
path = value;
end

function tearDown(conn, scratch)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
end

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
