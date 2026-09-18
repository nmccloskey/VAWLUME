function result = sampleExamples(conn, analysisRef, reference, options)
%SAMPLEEXAMPLES Draw a small seeded gallery from each exact support pattern.
%
% RESULT = vawlume.eda.SAMPLEEXAMPLES(CONN, ANALYSISREF, REFERENCE, Seed=s) picks
% up to TargetPerPattern agreement groups from each exact extractor-set pattern
% at the reference configuration, and reports every pattern that could not supply
% that many.
%
% Name-value options:
%   Seed              the resolved seed. Required
%   TargetPerPattern  examples per pattern, 1-10, default 3 (contract §L)
%   RecordingId       restrict to one recording
%
% THIS IS A GALLERY, NOT A REVIEW POOL. Three per pattern over seven patterns is
% about twenty-one images - a set a person will actually look through. There is
% no verdict column, no notes column, and no re-import path, because a sampler
% that produced those would be the first half of an adjudication pipeline
% (boundary 3).
%
% A LOCAL RANDOM STREAM, NEVER `rng`, over a deterministically ordered frame -
% the same rule and the same reasoning as Part 9's recording subset. `rng(seed)`
% mutates global MATLAB state, so the draw stops being a function of its inputs
% and someone else's `rng` call between two galleries changes the second one.
%
% A PATTERN WITH TOO FEW MEMBERS YIELDS ALL OF THEM AND A REPORTED SHORTFALL. It
% is never padded from a neighbouring pattern to make the gallery look balanced:
% a gallery with three images per row where one row borrowed from another row
% misrepresents exactly the thing the gallery exists to show. Part 11's handoff
% already names which patterns come up short on the fixture.
%
% THE PATTERN IS THE EXTRACTOR SET, and the filter used is
% selectPopulation's existing `ExtractorSetKey`. Contract §L says "3 examples per
% exact support pattern" and counts seven patterns for three extractors, which
% are conceptual spec §2.3's extractor sets - so `ExactSupportPattern`, which
% filters on `supported_extractor_pair_pattern`, is the wrong inherited filter
% here even though the itinerary names it: every singleton's pair pattern is
% `(none)` whichever extractor produced it, so it cannot separate the three
% extractor-unique categories. See the Part 11 handoff, EXP-025. The pair pattern
% is still recorded per example, because the example index carries it.
%
% THE FILTER'S RESULT IS VERIFIED, NOT TRUSTED. `extractor_set_key` is built by
% the view with `group_concat` over an ordered subquery, and the ordering is not
% guaranteed to survive; a key ordered differently from the canonical form would
% select nothing and look like an empty pattern. Every selected group's extractor
% set is recomputed from its members and compared, so a mismatch raises instead
% of quietly producing a short gallery.
%
% This function reads and draws. It writes nothing and creates no figure.

arguments
    conn
    analysisRef (1,1) struct
    reference (1,1) struct
    options.Seed double = []
    options.TargetPerPattern (1,1) double = 3
    options.RecordingId (1,1) double = NaN
end

seed = resolveSeed(options.Seed);
target = resolveTarget(options.TargetPerPattern);
requireFields(reference, ["profile_key", "version_label", "checksum_sha256"]);

population = vawlume.agreement.selectPopulation(conn, analysisRef, ...
    RecordingId=options.RecordingId);
if height(population.groups) == 0
    error("vawlume:eda:ExamplePopulationEmpty", ...
        "The agreement analysis holds no group, so there is nothing to " + ...
        "illustrate.");
end

extractors = extractorKeys(population);
vocabulary = edaSupportPatternVocabulary(extractors);
frame = buildFrame(population);

[stream, generator] = openStream(seed);
selectionKey = rand(stream, height(frame), 1);
frame.selection_key = selectionKey;

[examples, coverage] = drawPerPattern(conn, analysisRef, vocabulary, frame, ...
    target, options);
examples = attachIdentity(examples, population, reference);

result = struct( ...
    status="sampled", ...
    seed=seed, ...
    random_stream_generator=generator, ...
    target_per_pattern=target, ...
    ordering_key=frameOrderingKey(), ...
    selection_rule="one uniform key per group drawn in frame order; each " + ...
        "pattern takes the groups holding its smallest keys", ...
    analysis_run_id=population.analysis.analysis_run_id, ...
    agreement_run_key=string(population.analysis.run_key), ...
    reference_configuration=referenceIdentity(reference), ...
    pattern_vocabulary=vocabulary(:, ["extractor_set_key", ...
        "extractor_set_label", "extractor_count"]), ...
    coverage=coverage, ...
    examples=examples, ...
    example_count=height(examples), ...
    short_patterns=coverage(coverage.is_short, :), ...
    empty_patterns=coverage(coverage.available == 0, :), ...
    shortfall_note=shortfallNote(coverage, target), ...
    no_padding="a pattern with fewer groups than the target yields all of " + ...
        "them and a reported shortfall; it is never borrowed from another " + ...
        "pattern to balance the gallery", ...
    no_stratification="no experimental-group stratification is applied " + ...
        "(conceptual spec §7.2); the only stratum is the exact support " + ...
        "pattern itself", ...
    caution=edaCautionNote());
end

% ------------------------------------------------------------------ frame ---

function value = extractorKeys(population)
value = unique(population.members.extractor_key);
end

function frame = buildFrame(population)
%BUILDFRAME One row per group, in the stated deterministic order.
%
% The extractor set is RECOMPUTED from the members rather than read from the
% view's `extractor_set_key`, for the reason in the header: the view builds that
% key with group_concat over an ordered subquery and the order is not guaranteed.
% The members are the ground truth and the sort here is explicit.
groups = population.groups;
members = population.members;
setKey = strings(height(groups), 1);
memberCount = zeros(height(groups), 1);
for index = 1:height(groups)
    id = groups.agreement_group_id(index);
    selected = members(members.agreement_group_id == id, :);
    setKey(index) = strjoin(sort(unique(selected.extractor_key))', "|");
    memberCount(index) = height(selected);
end

frame = table(groups.agreement_group_id, groups.group_key, ...
    groups.recording_id, groups.native_recording_id, setKey, ...
    groups.supported_extractor_pair_pattern, memberCount, ...
    VariableNames=["agreement_group_id", "group_key", "recording_id", ...
    "native_recording_id", "extractor_set_key", ...
    "supported_extractor_pair_pattern", "member_count"]);
frame = sortrows(frame, ["recording_id", "group_key", "agreement_group_id"]);
end

function value = frameOrderingKey()
%FRAMEORDERINGKEY The stated order the random keys are assigned in.
%
% `group_key` leads rather than `agreement_group_id`, for the same reason Part 9
% ordered on the native recording id: the surrogate id is assigned by insertion
% order, so re-running an analysis in a different order would reshuffle the
% gallery under an unchanged seed. `group_key` is derived from the grouping
% itself; the surrogate id breaks ties.
value = "ascending recording_id, then group_key, then agreement_group_id";
end

% ------------------------------------------------------------------- draw ---

function [examples, coverage] = drawPerPattern(conn, analysisRef, vocabulary, ...
    frame, target, options)
examples = emptyExamples();
coverage = emptyCoverage();

for index = 1:height(vocabulary)
    setKey = vocabulary.extractor_set_key(index);
    selected = frame(frame.extractor_set_key == setKey, :);
    verifyInheritedFilter(conn, analysisRef, setKey, selected, options);

    available = height(selected);
    taken = min(target, available);
    if taken > 0
        [~, order] = sort(selected.selection_key);
        chosen = sortrows(selected(order(1:taken), :), ...
            ["recording_id", "group_key"]);
        for at = 1:height(chosen)
            examples(end + 1, :) = {exampleId(setKey, at), setKey, ...
                vocabulary.extractor_set_label(index), ...
                chosen.agreement_group_id(at), chosen.group_key(at), ...
                chosen.recording_id(at), chosen.native_recording_id(at), ...
                chosen.supported_extractor_pair_pattern(at), ...
                chosen.member_count(at), chosen.selection_key(at), ...
                at, taken}; %#ok<AGROW>
        end
    end

    coverage(end + 1, :) = {setKey, ...
        vocabulary.extractor_set_label(index), target, available, taken, ...
        max(target - available, 0), available < target, available == 0, ...
        shortfallReason(available, target)}; %#ok<AGROW>
end
end

function verifyInheritedFilter(conn, analysisRef, setKey, selected, options)
%VERIFYINHERITEDFILTER selectPopulation's own filter must agree with the frame.
%
% The itinerary asks to reuse the inherited selector rather than writing a new
% one, and this is that reuse - with the result checked instead of assumed. If
% the view's `extractor_set_key` is ever ordered differently from the canonical
% sorted form, the filter silently returns nothing and the pattern looks empty:
% a gallery short by a whole category, with no error anywhere.
filtered = vawlume.agreement.selectPopulation(conn, analysisRef, ...
    ExtractorSetKey=setKey, RecordingId=options.RecordingId);
% Reshaped to columns before comparing. An empty result from either side can be
% 0x0 or 0x1 depending on how it was built, and isequal distinguishes those -
% which would report a mismatch for two patterns that both correctly hold
% nothing, exactly the case this fixture is full of.
inherited = reshape(sort(double(filtered.groups.agreement_group_id)), [], 1);
recomputed = reshape(sort(double(selected.agreement_group_id)), [], 1);
if isequal(inherited, recomputed)
    return
end
error("vawlume:eda:ExtractorSetKeyFilterMismatch", ...
    "selectPopulation's ExtractorSetKey filter returned %d group(s) for " + ...
    "pattern '%s' while recomputing the extractor set from members returned " + ...
    "%d. The stored extractor_set_key is not in the canonical " + ...
    "ascending-joined form, so the inherited filter cannot be trusted to " + ...
    "select this pattern.", numel(inherited), setKey, numel(recomputed));
end

function value = exampleId(setKey, ordinal)
%EXAMPLEID Stable within a pattern and readable in a filename.
value = replace(setKey, "|", "-") + "-" + string(ordinal);
end

% -------------------------------------------------------------- reporting ---

function value = shortfallReason(available, target)
if available == 0
    value = "no group carries this exact support pattern in this analysis";
    return
end
if available < target
    value = "only " + string(available) + " group(s) carry this pattern, " + ...
        "below the target of " + string(target);
    return
end
value = "";
end

function value = shortfallNote(coverage, target)
short = coverage(coverage.is_short, :);
if height(short) == 0
    value = "Every pattern supplied the full target of " + string(target) + ...
        " example(s).";
    return
end
empty = short(short.available == 0, :);
parts = "Of " + string(height(coverage)) + " patterns, " + ...
    string(height(short)) + " could not supply " + string(target) + ...
    " example(s): " + strjoin(short.extractor_set_label' + " (" + ...
    string(short.available') + ")", "; ") + ".";
if height(empty) > 0
    parts = parts + " " + string(height(empty)) + " of those hold no group " + ...
        "at all. An empty category is a finding about the dataset at this " + ...
        "configuration, not a gap to be filled.";
end
value = parts + " These are reported rather than padded.";
end

% -------------------------------------------------------------- plumbing ---

function examples = attachIdentity(examples, population, reference)
if height(examples) == 0
    return
end
examples.agreement_run_key = repmat(string(population.analysis.run_key), ...
    height(examples), 1);
examples.reference_profile_key = repmat(string(reference.profile_key), ...
    height(examples), 1);
examples.reference_version_label = repmat(string(reference.version_label), ...
    height(examples), 1);
examples.reference_checksum_sha256 = repmat( ...
    string(reference.checksum_sha256), height(examples), 1);
end

function seed = resolveSeed(supplied)
if isempty(supplied)
    error("vawlume:eda:ExampleSeedMissing", ...
        "An example draw needs an explicit seed. A gallery nobody can " + ...
        "reproduce cannot be checked against the data it claims to " + ...
        "illustrate. Resolve one with vawlume.eda.probeParameters and pass it.");
end
if ~isscalar(supplied) || ~isfinite(supplied) || supplied < 0 || ...
        fix(supplied) ~= supplied
    error("vawlume:eda:ExampleSeedInvalid", ...
        "Seed must be a nonnegative integer scalar.");
end
seed = double(supplied);
end

function value = resolveTarget(target)
if ~isfinite(target) || target < 1 || target > 10 || fix(target) ~= target
    error("vawlume:eda:ExampleTargetInvalid", ...
        "TargetPerPattern must be an integer in 1..10 (contract §L). A " + ...
        "gallery larger than that stops being something a person looks " + ...
        "through and starts being a review pool.");
end
value = double(target);
end

function [stream, generator] = openStream(seed)
generator = "mt19937ar";
stream = RandStream(generator, Seed=seed);
end

function value = referenceIdentity(reference)
value = struct( ...
    profile_key=string(reference.profile_key), ...
    version_label=string(reference.version_label), ...
    checksum_sha256=string(reference.checksum_sha256), ...
    calibration_state=calibrationState(reference), ...
    identity_line=identityLine(reference));
end

function value = calibrationState(reference)
value = "unknown";
if isfield(reference, "calibration_status") && ...
        isfield(reference.calibration_status, "state")
    value = string(reference.calibration_status.state);
end
end

function value = identityLine(reference)
value = string(reference.profile_key) + " " + string(reference.version_label);
if isfield(reference, "identity_line")
    value = string(reference.identity_line);
end
end

function value = emptyExamples()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["example_id", "extractor_set_key", "extractor_set_label", ...
    "agreement_group_id", "group_key", "recording_id", ...
    "native_recording_id", "supported_extractor_pair_pattern", ...
    "member_count", "selection_key", "ordinal_in_pattern", ...
    "drawn_from_pattern"]);
end

function value = emptyCoverage()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), false(0, 1), strings(0, 1), ...
    VariableNames=["extractor_set_key", "extractor_set_label", "target", ...
    "available", "drawn", "shortfall", "is_short", "is_empty", ...
    "shortfall_reason"]);
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:ReferenceIdentityMissing", ...
        "The reference configuration record is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
