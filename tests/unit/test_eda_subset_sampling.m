function tests = test_eda_subset_sampling
%TEST_EDA_SUBSET_SAMPLING The draw, exhaustively, against hand-built frames.
%
% Unit tier and deliberately thorough: sampling is where a subtle bug is
% invisible in the output and fatal to the science. A subset that is quietly
% biased still has the right number of rows, still reports strata, and still
% reproduces under its own seed. Nothing about the result announces the defect,
% so the properties have to be asserted one at a time.
tests = functiontests({ ...
    @testIdenticalInputsReproduceTheIdenticalSubset, ...
    @testAnInterveningGlobalRngCallChangesNothing, ...
    @testTheGlobalGeneratorIsLeftExactlyAsItWasFound, ...
    @testShufflingTheFrameDoesNotChangeTheDrawnSet, ...
    @testADifferentSeedGivesADifferentSubset, ...
    @testNoSeedIsRefusedRatherThanInvented, ...
    @testTheDefaultSizeFollowsTheContractFormula, ...
    @testAFractionIsAcceptedAsAnAlternativeToACount, ...
    @testSizeAndFractionTogetherAreRefused, ...
    @testRequestingMoreThanExistsReturnsEverythingWithAFlag, ...
    @testRequestingMoreThanExistsCanRaiseInstead, ...
    @testPerStratumCountsSumToTheReportedTotal, ...
    @testLargestRemainderRoundingSumsWhereNaiveRoundingWouldNot, ...
    @testTheFloorPreservesARareStratumAndRecordsTheEffect, ...
    @testTheFloorTakesPrecedenceOverTheExactRequestedTotal, ...
    @testAnUnderFullStratumIsReportedShortNotPadded, ...
    @testNoFieldQualifyingFallsBackToPlainSamplingAndSaysSo, ...
    @testStratificationCanBeDisabledAndIsRecordedAsSuch, ...
    @testAForcedFieldOverridesTheAutomaticDecision, ...
    @testAForcedFieldThatWasNotResolvedIsRefused, ...
    @testTheSubsetRecordCarriesEverythingPartTenNeeds, ...
    @testTheSelectedSetIsAlwaysASubsetOfTheFrame});
end

% ------------------------------------------------------------ determinism ---

function testIdenticalInputsReproduceTheIdenticalSubset(testCase)
frame = balancedFrame();
first = vawlume.eda.sampleRecordings(frame, Seed=42, Size=6);
second = vawlume.eda.sampleRecordings(frame, Seed=42, Size=6);

% The full id list, not a count or a set summary. Two draws of six that agree on
% how many they took and disagree on which is exactly the failure a weaker
% assertion misses.
verifyEqual(testCase, first.selected_recording_ids, ...
    second.selected_recording_ids);
verifyEqual(testCase, first.selected.selection_key, ...
    second.selected.selection_key);
end

function testAnInterveningGlobalRngCallChangesNothing(testCase)
%TESTANINTERVENINGGLOBALRNGCALL... The specific defect the local stream prevents.
%
% Verified as a negative result: replacing the local RandStream with
% rng(seed); rand(n,1) makes this test fail, because the rng call between the two
% draws reseeds the generator the second draw would have used. Nothing in the
% output of the broken version looks wrong - it is a different valid-looking
% subset from the same seed.
frame = balancedFrame();
first = vawlume.eda.sampleRecordings(frame, Seed=42, Size=6);

rng(999);
rand(17, 1);
rng("shuffle");
rand(5, 3);

second = vawlume.eda.sampleRecordings(frame, Seed=42, Size=6);
verifyEqual(testCase, first.selected_recording_ids, ...
    second.selected_recording_ids);
end

function testTheGlobalGeneratorIsLeftExactlyAsItWasFound(testCase)
%TESTTHEGLOBALGENERATORISLEFT... The same rule read from the other direction.
%
% A sampler that seeds the global generator does not only read global state, it
% writes it: a user's own unseeded work after an exploration run silently changes
% because the exploration ran. Asserting the saved state round-trips catches that
% even if the draw itself were somehow made reproducible.
%
% The generator is moved to a KNOWN state that is not the one the sampler's own
% seed would produce, and moved off its seeded point by a draw. Without that, the
% test is order-dependent and worthless: an `rng(42)`-based sampler running
% straight after another `rng(42)`-based call leaves the global state exactly
% where it found it, and a bare before/after comparison passes. That is not
% hypothetical - it is what this test did before the two lines below were added.
rng(12345);
rand(3, 1);

before = rng();
vawlume.eda.sampleRecordings(balancedFrame(), Seed=42, Size=6);
after = rng();

verifyEqual(testCase, after.Type, before.Type);
verifyEqual(testCase, after.Seed, before.Seed);
verifyEqual(testCase, after.State, before.State);
end

function testShufflingTheFrameDoesNotChangeTheDrawnSet(testCase)
%TESTSHUFFLINGTHEFRAME... Reproducible given a stated ordering key.
%
% A different property from determinism: two callers holding the same recordings
% in different row orders must draw the same subset. The sampler re-sorts by the
% ordering key rather than trusting the order it was handed.
frame = balancedFrame();
expected = vawlume.eda.sampleRecordings(frame, Seed=42, Size=6);

shuffled = frame;
order = [9 3 12 1 7 5 11 2 8 4 10 6]';
shuffled.recordings = frame.recordings(order, :);
shuffled.strata = frame.strata(randperm(height(frame.strata)), :);

actual = vawlume.eda.sampleRecordings(shuffled, Seed=42, Size=6);
verifyEqual(testCase, actual.selected_recording_ids, ...
    expected.selected_recording_ids);
end

function testADifferentSeedGivesADifferentSubset(testCase)
%TESTADIFFERENTSEEDGIVES... Otherwise the seed is decoration.
frame = balancedFrame();
subsets = strings(0, 1);
for seed = 1:12
    result = vawlume.eda.sampleRecordings(frame, Seed=seed, Size=6);
    subsets(end + 1) = strjoin(string(result.selected_recording_ids), ","); %#ok<AGROW>
end
verifyGreaterThan(testCase, numel(unique(subsets)), 1);
end

function testNoSeedIsRefusedRatherThanInvented(testCase)
verifyError(testCase, ...
    @() vawlume.eda.sampleRecordings(balancedFrame(), Size=4), ...
    "vawlume:eda:SubsetSeedMissing");
verifyError(testCase, ...
    @() vawlume.eda.sampleRecordings(balancedFrame(), Seed=-1), ...
    "vawlume:eda:SubsetSeedInvalid");
verifyError(testCase, ...
    @() vawlume.eda.sampleRecordings(balancedFrame(), Seed=1.5), ...
    "vawlume:eda:SubsetSeedInvalid");
end

% ------------------------------------------------------------------- size ---

function testTheDefaultSizeFollowsTheContractFormula(testCase)
% max(4, min(12, ceil(0.25 R))) clamped to R, exercised across the three
% regimes the formula has: the floor of 4, the proportional middle, the cap of
% 12, and the clamp for a frame smaller than the floor.
expectations = [3 3; 8 4; 12 4; 20 5; 48 12; 80 12];
for index = 1:size(expectations, 1)
    count = expectations(index, 1);
    frame = plainFrame(count);
    result = vawlume.eda.sampleRecordings(frame, Seed=1);
    verifyEqual(testCase, result.requested_size, expectations(index, 2), ...
        "Frame of " + count + " sized wrongly.");
    verifyEqual(testCase, result.realized_size, expectations(index, 2));
    verifySubstring(testCase, result.size_rule, "max(4, min(12,");
end
end

function testAFractionIsAcceptedAsAnAlternativeToACount(testCase)
frame = plainFrame(20);
result = vawlume.eda.sampleRecordings(frame, Seed=1, Fraction=0.25);
verifyEqual(testCase, result.requested_size, 5);
verifyEqual(testCase, result.realized_size, 5);
verifySubstring(testCase, result.size_rule, "Fraction");

% Rounds up, so a fraction never silently resolves to nothing.
tiny = vawlume.eda.sampleRecordings(plainFrame(7), Seed=1, Fraction=0.01);
verifyEqual(testCase, tiny.requested_size, 1);
end

function testSizeAndFractionTogetherAreRefused(testCase)
verifyError(testCase, @() vawlume.eda.sampleRecordings(plainFrame(10), ...
    Seed=1, Size=4, Fraction=0.5), "vawlume:eda:SubsetSizeAmbiguous");
verifyError(testCase, @() vawlume.eda.sampleRecordings(plainFrame(10), ...
    Seed=1, Fraction=1.5), "vawlume:eda:SubsetSizeInvalid");
verifyError(testCase, @() vawlume.eda.sampleRecordings(plainFrame(10), ...
    Seed=1, Size=0), "vawlume:eda:SubsetSizeInvalid");
end

function testRequestingMoreThanExistsReturnsEverythingWithAFlag(testCase)
%TESTREQUESTINGMORETHANEXISTS... The documented choice, asserted as documented.
frame = plainFrame(6);
result = vawlume.eda.sampleRecordings(frame, Seed=1, Size=25);

verifyTrue(testCase, result.requested_exceeds_frame);
verifyEqual(testCase, result.requested_size, 25);
verifyEqual(testCase, result.realized_size, 6);
verifyEqual(testCase, result.excess_request_policy, "return_all");
verifyEqual(testCase, sort(result.selected_recording_ids), (1:6)');
end

function testRequestingMoreThanExistsCanRaiseInstead(testCase)
verifyError(testCase, @() vawlume.eda.sampleRecordings(plainFrame(6), ...
    Seed=1, Size=25, OnExcessRequest="raise"), ...
    "vawlume:eda:SubsetLargerThanFrame");
end

% ------------------------------------------------------------- allocation ---

function testPerStratumCountsSumToTheReportedTotal(testCase)
frame = balancedFrame();
for requested = 3:11
    result = vawlume.eda.sampleRecordings(frame, Seed=5, Size=requested);
    verifyEqual(testCase, sum(result.allocation.realized_count), ...
        result.realized_size, ...
        "Allocation does not sum at a request of " + requested + ".");
    verifyEqual(testCase, height(result.selected), result.realized_size);

    % And the realized counts are what the selected rows actually show, not a
    % separate arithmetic that happens to agree.
    for index = 1:height(result.allocation)
        stratum = result.allocation.stratum_value(index);
        verifyEqual(testCase, nnz(result.selected.stratum_value == stratum), ...
            result.allocation.realized_count(index));
    end
end
end

function testLargestRemainderRoundingSumsWhereNaiveRoundingWouldNot(testCase)
%TESTLARGESTREMAINDERROUNDING... Rounding is where proportional allocation leaks.
%
% Three strata of five and one of one, over a request of seven: the exact shares
% are 2.1875, 2.1875, 2.1875 and 0.4375. Rounding each to nearest gives 2+2+2+0 =
% 6, one short of the request, and the rare stratum is the one that disappears.
% Largest remainder floors everything and hands the shortfall to the largest
% fractional part, which is the rare stratum.
frame = frameFromStrata(["A" "A" "A" "A" "A" "B" "B" "B" "B" "B" ...
    "C" "C" "C" "C" "C" "D"]);
result = vawlume.eda.sampleRecordings(frame, Seed=5, Size=7);

allocation = sortrows(result.allocation, "stratum_value");
verifyEqual(testCase, allocation.proportional_share, ...
    [2.1875; 2.1875; 2.1875; 0.4375], AbsTol=1e-12);
verifyEqual(testCase, round(allocation.proportional_share), [2; 2; 2; 0]);
verifyEqual(testCase, sum(round(allocation.proportional_share)), 6);

verifyEqual(testCase, allocation.largest_remainder_count, [2; 2; 2; 1]);
verifyEqual(testCase, sum(allocation.requested_count), 7);
verifyEqual(testCase, result.realized_size, 7);

% The floor did not have to act here: largest remainder already gave the rare
% stratum its place, so the two rules are tested apart from one another.
verifyEqual(testCase, sum(allocation.floor_added), 0);
verifyFalse(testCase, result.rare_stratum_effect.floor_changed_allocation);
end

function testTheFloorPreservesARareStratumAndRecordsTheEffect(testCase)
%TESTTHEFLOORPRESERVESARARESTRATUM... And says so, which is the other half.
%
% Nine A, one B, over a request of four. Proportional gives B 0.36 of a place and
% largest remainder does not reach it, so without the floor the rare stratum is
% dropped from a sample that still reports itself as stratified.
frame = frameFromStrata(["A" "A" "A" "A" "A" "A" "A" "A" "A" "B"]);
result = vawlume.eda.sampleRecordings(frame, Seed=5, Size=4);

allocation = sortrows(result.allocation, "stratum_value");
verifyEqual(testCase, allocation.largest_remainder_count, [4; 0]);
verifyEqual(testCase, allocation.floor_added, [0; 1]);
verifyEqual(testCase, allocation.trimmed, [1; 0]);
verifyEqual(testCase, allocation.requested_count, [3; 1]);
verifyEqual(testCase, sum(allocation.realized_count), 4);
verifyEqual(testCase, nnz(result.selected.stratum_value == "B"), 1);

effect = result.rare_stratum_effect;
verifyTrue(testCase, effect.floor_changed_allocation);
verifyEqual(testCase, effect.strata_raised_by_floor, "B");
verifyEqual(testCase, effect.places_added_by_floor, 1);
verifyEqual(testCase, effect.places_removed_by_trimming, 1);
verifyEqual(testCase, effect.allocated_total, 4);
verifyFalse(testCase, effect.total_raised_above_request);
end

function testTheFloorTakesPrecedenceOverTheExactRequestedTotal(testCase)
%TESTTHEFLOORTAKESPRECEDENCE... Five strata cannot fit in three places.
%
% Trimming can only go down to the floor, so a frame with more strata than the
% requested size allocates more than was requested rather than dropping a
% stratum. The alternative - dropping the smallest strata to hit the number -
% would silently delete exactly the groups the floor exists to protect.
frame = frameFromStrata(["A" "A" "B" "B" "C" "C" "D" "D" "E" "E"]);
result = vawlume.eda.sampleRecordings(frame, Seed=5, Size=3);

verifyEqual(testCase, height(result.allocation), 5);
verifyEqual(testCase, result.allocation.requested_count, ones(5, 1));
verifyEqual(testCase, result.realized_size, 5);
verifyEqual(testCase, result.requested_size, 3);
verifyTrue(testCase, result.rare_stratum_effect.total_raised_above_request);
verifyEqual(testCase, result.rare_stratum_effect.allocated_total, 5);
verifySubstring(testCase, result.rare_stratum_effect.note, ...
    "rather than dropping a rare stratum");
end

function testAnUnderFullStratumIsReportedShortNotPadded(testCase)
%TESTANUNDERFULLSTRATUMISREPORTEDSHORT... Never topped up from a neighbour.
%
% Verified as a negative result: an implementation that redistributed the
% shortfall to the strata with places left made this test fail on
% realized_size - it returned nine, the requested number, with stratum B holding
% one recording against a requested three and A and C quietly holding four each.
% That version's own record called the sample stratified with three per stratum.
%
% Under a floor of three, B has only one recording to give. It is reported at one
% against a request of three, and the total comes back short.
frame = frameFromStrata(["A" "A" "A" "A" "A" "B" "C" "C" "C" "C" "C" "C"]);
result = vawlume.eda.sampleRecordings(frame, Seed=5, Size=9, ...
    MinimumPerStratum=3);

allocation = sortrows(result.allocation, "stratum_value");
verifyEqual(testCase, allocation.requested_count, [3; 3; 3]);
verifyEqual(testCase, allocation.realized_count, [3; 1; 3]);
verifyEqual(testCase, allocation.is_under_full, [false; true; false]);

% Short, not padded: the unused places do not reappear in A or C.
verifyEqual(testCase, result.realized_size, 7);
verifyEqual(testCase, nnz(result.selected.stratum_value == "A"), 3);
verifyEqual(testCase, nnz(result.selected.stratum_value == "C"), 3);
verifyEqual(testCase, nnz(result.selected.stratum_value == "B"), 1);

underFull = result.under_full_strata;
verifyEqual(testCase, height(underFull), 1);
verifyEqual(testCase, underFull.stratum_value, "B");
verifyEqual(testCase, underFull.realized_count, 1);
verifyEqual(testCase, underFull.stratum_size, 1);
end

% ---------------------------------------------------------- the fallback ---

function testNoFieldQualifyingFallsBackToPlainSamplingAndSaysSo(testCase)
%TESTNOFIELDQUALIFYING... Not a "stratified" sample with one stratum.
frame = plainFrame(12);
frame.fields.coverage_fraction(1) = 0.2;
result = vawlume.eda.sampleRecordings(frame, Seed=4, Size=5);

verifyFalse(testCase, result.is_stratified);
verifyEqual(testCase, result.stratum_field, "");
verifySubstring(testCase, result.fallback_reason, "no recording-level field");
verifySubstring(testCase, result.stratification_statement, "NOT STRATIFIED");
verifySubstring(testCase, result.stratification_statement, ...
    "plain seeded random sample");
verifyEqual(testCase, height(result.allocation), 0);
verifyEqual(testCase, result.realized_size, 5);

% And the fallback is still a proper draw, not everything-up-to-five.
verifyEqual(testCase, numel(unique(result.selected_recording_ids)), 5);
end

function testStratificationCanBeDisabledAndIsRecordedAsSuch(testCase)
result = vawlume.eda.sampleRecordings(balancedFrame(), Seed=4, Size=5, ...
    Stratify=false);
verifyFalse(testCase, result.is_stratified);
verifySubstring(testCase, result.fallback_reason, "disabled by the caller");
verifyTrue(testCase, all(result.fields_considered.rejection_reason == ...
    "stratification_disabled_by_caller"));
end

function testAForcedFieldOverridesTheAutomaticDecision(testCase)
frame = twoFieldFrame();
automatic = vawlume.eda.sampleRecordings(frame, Seed=4, Size=6);
verifyEqual(testCase, automatic.stratum_field, "recording_attribute:even");

forced = vawlume.eda.sampleRecordings(frame, Seed=4, Size=6, ...
    Field="recording_attribute:lopsided");
verifyEqual(testCase, forced.stratum_field, "recording_attribute:lopsided");
verifyTrue(testCase, forced.is_stratified);
verifySubstring(testCase, ...
    forced.fields_considered.rejection_reason( ...
    forced.fields_considered.field == "recording_attribute:even"), ...
    "the caller named");
end

function testAForcedFieldThatWasNotResolvedIsRefused(testCase)
verifyError(testCase, @() vawlume.eda.sampleRecordings(balancedFrame(), ...
    Seed=4, Field="recording_attribute:absent"), ...
    "vawlume:eda:StratumFieldNotResolved");
end

% ------------------------------------------------------- the subset record ---

function testTheSubsetRecordCarriesEverythingPartTenNeeds(testCase)
result = vawlume.eda.sampleRecordings(balancedFrame(), Seed=77, Size=6);

required = ["seed", "random_stream_generator", "ordering_key", "frame_size", ...
    "requested_size", "size_rule", "realized_size", "requested_exceeds_frame", ...
    "excess_request_policy", "is_stratified", "stratum_field", ...
    "fallback_reason", "stratification_statement", "fields_considered", ...
    "allocation", "allocation_rule", "rare_stratum_rule", ...
    "rare_stratum_effect", "under_full_strata", "qualification_thresholds", ...
    "missing_representation", "selected", "selected_recording_ids", "caution"];
for name = required
    verifyTrue(testCase, isfield(result, name), "Missing field " + name + ".");
end

verifyEqual(testCase, result.seed, 77);
verifyEqual(testCase, result.random_stream_generator, "mt19937ar");
verifySubstring(testCase, result.ordering_key, "native_recording_id");
verifySubstring(testCase, result.allocation_rule, "largest-remainder");
verifySubstring(testCase, result.rare_stratum_rule, "never padded");
verifyEqual(testCase, result.missing_representation, "(missing)");
verifyClass(testCase, result.selected_recording_ids, "double");
verifyEqual(testCase, result.selected.Properties.VariableNames, ...
    {'recording_id', 'native_recording_id', 'stratum_value', 'selection_key'});

% Serializable: the whole record survives a round trip through JSON, which is
% what Part 7's provenance writer will do with it.
encoded = jsonencode(result);
verifyClass(testCase, encoded, "char");
decoded = jsondecode(encoded);
verifyEqual(testCase, decoded.seed, 77);
verifyEqual(testCase, numel(decoded.selected_recording_ids), 6);
end

function testTheSelectedSetIsAlwaysASubsetOfTheFrame(testCase)
%TESTTHESELECTEDSETISALWAYS... The invariant every other assertion rests on.
frame = balancedFrame();
for seed = 1:20
    for requested = [1 4 7 11 12]
        result = vawlume.eda.sampleRecordings(frame, Seed=seed, Size=requested);
        ids = result.selected_recording_ids;
        verifyEqual(testCase, numel(unique(ids)), numel(ids));
        verifyTrue(testCase, all(ismember(ids, frame.recordings.recording_id)));
        verifyLessThanOrEqual(testCase, numel(ids), height(frame.recordings));
        verifyEqual(testCase, ids, sort(ids));
    end
end
end

% ---------------------------------------------------------------- helpers ---

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function frame = balancedFrame()
%BALANCEDFRAME Twelve recordings in three strata of four.
frame = frameFromStrata(["A" "A" "A" "A" "B" "B" "B" "B" "C" "C" "C" "C"]);
end

function frame = plainFrame(count)
%PLAINFRAME A frame whose only field cannot qualify, forcing the fallback.
frame = frameFromStrata(repmat("A", 1, count));
end

function frame = twoFieldFrame()
%TWOFIELDFRAME Two qualifying fields of different balance.
even = frameFromStrata(["A" "A" "A" "A" "A" "A" "B" "B" "B" "B" "B" "B"], ...
    "recording_attribute:even");
lopsided = frameFromStrata(["X" "X" "X" "X" "X" "X" "X" "X" "X" "Y" "Y" "Y"], ...
    "recording_attribute:lopsided");
frame = even;
frame.strata = [even.strata; lopsided.strata];
frame.fields = [even.fields; lopsided.fields];
end

function frame = frameFromStrata(values, field)
%FRAMEFROMSTRATA Build a resolveStrata-shaped result without a database.
%
% Hand-built on purpose. The draw's properties are arithmetic over a frame, so
% forcing every case through a real database would make the interesting shapes -
% five strata under a request of three, a stratum of one under a floor of three -
% an exercise in fixture construction rather than in sampling.
arguments
    values string
    field (1,1) string = "recording_attribute:group"
end

values = values(:);
count = numel(values);
ids = (1:count)';
natives = compose("REC_%02d", ids);

recordings = table(ids, string(natives), ...
    VariableNames=["recording_id", "native_recording_id"]);
strata = table(ids, repmat(field, count, 1), values, ...
    values == "(missing)", ...
    VariableNames=["recording_id", "field", "stratum_value", "is_missing"]);

[groups, ~, grouping] = unique(values);
occurrences = accumarray(grouping, 1);
[peak, at] = max(occurrences);
resolved = nnz(values ~= "(missing)");

fields = table(field, "recording_attribute", count, resolved, ...
    count - resolved, resolved / count, ...
    numel(unique(values(values ~= "(missing)"))), numel(groups), ...
    groups(at), peak / count, true, "", ...
    VariableNames=["field", "kind", "recording_count", "resolved_count", ...
    "missing_count", "coverage_fraction", "distinct_value_count", ...
    "stratum_count", "largest_stratum", "largest_stratum_share", ...
    "is_resolvable", "resolution_note"]);

frame = struct( ...
    status="resolved", ...
    recording_count=count, ...
    recordings=recordings, ...
    strata=strata, ...
    fields=fields, ...
    field_discovery="hand-built test frame", ...
    multi_valued_policy="reject", ...
    missing_representation="(missing)", ...
    ordering_key="ascending native_recording_id, ties broken by ascending recording_id", ...
    resolution_note="hand-built test frame", ...
    forbidden_fields="hand-built test frame");
end
