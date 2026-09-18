function result = sampleRecordings(strata, options)
%SAMPLERECORDINGS Draw a reproducible recording subset, stratified when it can be.
%
% RESULT = vawlume.eda.SAMPLERECORDINGS(STRATA, Seed=s) takes a
% vawlume.eda.resolveStrata result and returns the selected recording ids
% together with the serializable record of how they were selected: the seed, the
% fields considered and why each was rejected, the per-stratum requested and
% realized counts, the allocation rule, the rare-stratum rule's effect, the
% ordering key, and whether the run fell back to plain random sampling.
%
% Name-value options:
%   Seed                   the resolved seed. Required
%   Size                   recording count. Default max(4, min(12, ceil(0.25R)))
%   Fraction               a share of the frame, as an alternative to Size
%   Stratify               attempt stratification at all. Default true
%   Field                  force one stratum field instead of deciding
%   MinimumCoverage        default 0.60   (contract §I)
%   MinimumDistinctValues  default 2      (contract §I)
%   MaximumStratumShare    default 0.90   (contract §I)
%   MinimumPerStratum      default 1, the floor that preserves rare strata
%   OnExcessRequest        "return_all" (default) or "raise"
%
% A LOCAL RANDOM STREAM, NEVER `rng`. `rng(seed)` mutates global MATLAB state, so
% the draw stops being a function of its inputs: a user's later unseeded work
% silently changes, and - worse in the other direction - anyone else's `rng` call
% landing between two draws changes the second one. Neither failure leaves a
% trace in the output. A local RandStream makes the subset depend on the seed and
% the frame and nothing else, which is tested directly.
%
% ONE UNIFORM KEY PER RECORDING, DRAWN IN FRAME ORDER; each stratum then takes
% the recordings holding its smallest keys. Drawing per stratum in sequence would
% work too and is worse: the stream position when a stratum is reached would then
% depend on how many places the strata before it took, so adding one recording to
% an unrelated stratum would reshuffle every stratum after it. Here a recording's
% key depends only on its position in the ordered frame.
%
% THE FRAME IS RE-SORTED HERE even though the resolver already sorted it. That is
% what makes the result independent of the row order the caller hands over, which
% is a different property from determinism and is separately tested.
%
% AN UNDER-FULL STRATUM IS REPORTED SHORT. Its unused places are not given to a
% neighbour: a stratified sample whose strata are secretly unequal is worse than
% an honestly unbalanced one, because the reader interprets it as balanced.
%
% REQUESTING MORE RECORDINGS THAN EXIST RETURNS THE WHOLE FRAME with
% `requested_exceeds_frame` set, rather than raising. The caller sizing a subset
% cannot know the frame's size before resolving it, and a run that dies at the
% sampler after resolving strata has spent the work and produced nothing; the
% flag carries the fact to the record, where Part 10 reads the realized size
% anyway. Pass OnExcessRequest="raise" for the strict behaviour.
%
% This function performs no query, writes nothing, draws no figure, and never
% consults an extractor-support pattern - a subset may not be stratified by an
% output of the analysis it exists to probe.

arguments
    strata (1,1) struct
    options.Seed double = []
    options.Size double = []
    options.Fraction double = []
    options.Stratify (1,1) logical = true
    options.Field string = ""
    options.MinimumCoverage (1,1) double ...
        {mustBeNonnegative, mustBeLessThanOrEqual(options.MinimumCoverage, 1)} = 0.60
    options.MinimumDistinctValues (1,1) double {mustBePositive} = 2
    options.MaximumStratumShare (1,1) double ...
        {mustBeNonnegative, mustBeLessThanOrEqual(options.MaximumStratumShare, 1)} = 0.90
    options.MinimumPerStratum (1,1) double {mustBeNonnegative} = 1
    options.OnExcessRequest (1,1) string ...
        {mustBeMember(options.OnExcessRequest, ["return_all", "raise"])} = "return_all"
end

requireFields(strata, ["recordings", "strata", "fields"]);
frame = edaOrderFrame(strata.recordings);
frameSize = height(frame);
if frameSize == 0
    error("vawlume:eda:SubsetFrameEmpty", ...
        "The sampling frame holds no recording.");
end

seed = resolveSeed(options.Seed);
[requestedSize, sizeRule] = resolveSize(options, frameSize);
[drawSize, exceeds] = applyExcessPolicy(requestedSize, frameSize, options);

decision = edaStratumQualification(strata.fields, options);
[decision, field, fallbackReason] = chooseField(decision, options);
isStratified = strlength(field) > 0;

[stream, generator] = openStream(seed);
selectionKey = rand(stream, frameSize, 1);

if isStratified
    assignment = stratumOf(strata.strata, field, frame);
    [allocation, rare] = allocate(assignment, drawSize, options);
    selected = drawStratified(frame, selectionKey, assignment, allocation);
else
    assignment = strings(frameSize, 1);
    allocation = emptyAllocation();
    rare = noRareEffect();
    selected = drawPlain(frame, selectionKey, drawSize);
end

chosen = frame(selected, :);
chosen.stratum_value = assignment(selected);
chosen.selection_key = selectionKey(selected);
chosen = edaOrderFrame(chosen);

if isStratified
    allocation.realized_count = realizedPerStratum(allocation, chosen);
    allocation.is_under_full = allocation.realized_count < allocation.requested_count;
end

result = struct( ...
    status="sampled", ...
    seed=seed, ...
    random_stream_generator=generator, ...
    selection_rule="one uniform key per recording drawn in frame order; " + ...
        "each stratum takes the recordings holding its smallest keys", ...
    ordering_key=edaFrameOrderingKey(), ...
    frame_size=frameSize, ...
    requested_size=requestedSize, ...
    size_rule=sizeRule, ...
    realized_size=height(chosen), ...
    requested_exceeds_frame=exceeds, ...
    excess_request_policy=options.OnExcessRequest, ...
    is_stratified=isStratified, ...
    stratum_field=field, ...
    fallback_reason=fallbackReason, ...
    stratification_statement=statement(isStratified, field, fallbackReason), ...
    fields_considered=decision, ...
    allocation=allocation, ...
    allocation_rule="proportional to stratum size with largest-remainder " + ...
        "rounding, then a floor of " + string(options.MinimumPerStratum) + ...
        " per stratum, then trimming from the largest strata to the total", ...
    rare_stratum_rule="every qualifying stratum receives at least " + ...
        string(options.MinimumPerStratum) + " recording; a stratum smaller " + ...
        "than its allocation is reported short with its actual count and is " + ...
        "never padded from a neighbour", ...
    rare_stratum_effect=rare, ...
    under_full_strata=underFull(allocation), ...
    qualification_thresholds=struct( ...
        minimum_coverage=options.MinimumCoverage, ...
        minimum_distinct_values=options.MinimumDistinctValues, ...
        maximum_stratum_share=options.MaximumStratumShare, ...
        minimum_per_stratum=options.MinimumPerStratum), ...
    missing_representation=edaMissingStratum(), ...
    selected=chosen, ...
    selected_recording_ids=chosen.recording_id, ...
    caution=edaCautionNote());
end

% ------------------------------------------------------------ the request ---

function seed = resolveSeed(supplied)
if isempty(supplied)
    error("vawlume:eda:SubsetSeedMissing", ...
        "A subset draw needs an explicit seed. Reproducibility is a " + ...
        "requirement here, not a nicety, and a sampler that invented its " + ...
        "own default would produce a record that cannot be replayed. " + ...
        "Resolve one with vawlume.eda.probeParameters and pass it.");
end
if ~isscalar(supplied) || ~isfinite(supplied) || supplied < 0 || ...
        fix(supplied) ~= supplied
    error("vawlume:eda:SubsetSeedInvalid", ...
        "Seed must be a nonnegative integer scalar.");
end
seed = double(supplied);
end

function [value, rule] = resolveSize(options, frameSize)
%RESOLVESIZE Contract §I's size policy: a count, or a fraction, or the default.
%
% Not derived from an analysis budget. A budget-derived size would change
% whenever the design changed, making two runs incomparable for a reason the user
% never chose.
if ~isempty(options.Size) && ~isempty(options.Fraction)
    error("vawlume:eda:SubsetSizeAmbiguous", ...
        "Size and Fraction both name the subset's size. Pass one.");
end
if ~isempty(options.Size)
    if ~isscalar(options.Size) || ~isfinite(options.Size) || ...
            options.Size < 1 || fix(options.Size) ~= options.Size
        error("vawlume:eda:SubsetSizeInvalid", ...
            "Size must be a positive integer recording count.");
    end
    value = double(options.Size);
    rule = "recording count supplied by the caller";
    return
end
if ~isempty(options.Fraction)
    if ~isscalar(options.Fraction) || ~isfinite(options.Fraction) || ...
            options.Fraction <= 0 || options.Fraction > 1
        error("vawlume:eda:SubsetSizeInvalid", ...
            "Fraction must lie in (0, 1].");
    end
    value = max(1, ceil(options.Fraction * frameSize));
    rule = sprintf("ceil(%.4g x %d) from the caller's Fraction", ...
        options.Fraction, frameSize);
    return
end
value = min(max(4, min(12, ceil(0.25 * frameSize))), frameSize);
rule = sprintf("max(4, min(12, ceil(0.25 x %d))) clamped to %d", ...
    frameSize, frameSize);
end

function [drawSize, exceeds] = applyExcessPolicy(requestedSize, frameSize, options)
exceeds = requestedSize > frameSize;
if ~exceeds
    drawSize = requestedSize;
    return
end
if options.OnExcessRequest == "raise"
    error("vawlume:eda:SubsetLargerThanFrame", ...
        "A subset of %d recordings was requested from a frame of %d. Pass " + ...
        "OnExcessRequest=""return_all"" to take the whole frame with the " + ...
        "shortfall recorded instead.", requestedSize, frameSize);
end
drawSize = frameSize;
end

% ------------------------------------------------------- the field choice ---

function [decision, field, reason] = chooseField(decision, options)
field = "";
reason = "";
if ~options.Stratify
    decision.is_selected(:) = false;
    if height(decision) > 0
        decision.rejection_reason(:) = "stratification_disabled_by_caller";
    end
    reason = "stratification was disabled by the caller";
    return
end
if strlength(options.Field) > 0
    match = decision.field == options.Field;
    if ~any(match)
        error("vawlume:eda:StratumFieldNotResolved", ...
            "Field '%s' was requested but was not resolved. Resolved " + ...
            "field(s): %s.", options.Field, ...
            strjoin(decision.field', ", "));
    end
    decision.is_selected(:) = false;
    decision.is_selected(match) = true;
    decision.rejection_reason(match) = "";
    decision.rejection_reason(~match) = "not_selected (the caller named '" + ...
        options.Field + "')";
    field = options.Field;
    return
end
if any(decision.is_selected)
    field = decision.field(decision.is_selected);
    field = field(1);
    return
end
reason = "no recording-level field qualified as a stratum";
if height(decision) == 0
    reason = "no recording-level stratum field was resolved";
end
end

function value = statement(isStratified, field, reason)
if isStratified
    value = "Stratified on '" + field + "'.";
    return
end
value = "NOT STRATIFIED: " + reason + ", so this is a plain seeded random " + ...
    "sample of the frame. It is reported as such rather than as a " + ...
    "stratified sample with one stratum.";
end

% ---------------------------------------------------------- the allocation ---

function assignment = stratumOf(strata, field, frame)
%STRATUMOF The chosen field's stratum value for each frame row, in frame order.
selected = strata(strata.field == field, :);
[found, at] = ismember(frame.recording_id, selected.recording_id);
if ~all(found)
    error("vawlume:eda:StratumValueMissing", ...
        "Field '%s' carries no stratum value for recording(s) %s. Every " + ...
        "recording in the frame resolves every field, missing included.", ...
        field, strjoin(string(frame.recording_id(~found)'), ", "));
end
assignment = selected.stratum_value(at);
end

function [allocation, rare] = allocate(assignment, drawSize, options)
[labels, ~, grouping] = unique(assignment);
sizes = accumarray(grouping, 1);
allocation = edaAllocateStrata(labels, sizes, drawSize, ...
    options.MinimumPerStratum);

raised = allocation.stratum_value(allocation.floor_added > 0);
rare = struct( ...
    rule="a floor of " + string(options.MinimumPerStratum) + ...
        " recording(s) per stratum", ...
    floor_changed_allocation=~isempty(raised), ...
    strata_raised_by_floor=raised, ...
    places_added_by_floor=sum(allocation.floor_added), ...
    places_removed_by_trimming=sum(allocation.trimmed), ...
    requested_total=drawSize, ...
    allocated_total=sum(allocation.requested_count), ...
    total_raised_above_request=sum(allocation.requested_count) > drawSize, ...
    note="the floor only raises; trimming takes the excess back from the " + ...
        "largest strata but never below the floor, so a frame with more " + ...
        "strata than the requested size allocates more than was requested " + ...
        "rather than dropping a rare stratum");
end

function value = realizedPerStratum(allocation, chosen)
value = zeros(height(allocation), 1);
for index = 1:height(allocation)
    value(index) = nnz(chosen.stratum_value == allocation.stratum_value(index));
end
end

function value = underFull(allocation)
if height(allocation) == 0
    value = allocation;
    return
end
value = allocation(allocation.is_under_full, :);
end

% ---------------------------------------------------------------- the draw ---

function [stream, generator] = openStream(seed)
%OPENSTREAM A local stream, recorded by name so the draw is fully specified.
generator = "mt19937ar";
stream = RandStream(generator, Seed=seed);
end

function selected = drawPlain(frame, selectionKey, drawSize)
[~, order] = sort(selectionKey);
selected = sort(order(1:min(drawSize, height(frame))));
end

function selected = drawStratified(frame, selectionKey, assignment, allocation)
selected = zeros(0, 1);
for index = 1:height(allocation)
    members = find(assignment == allocation.stratum_value(index));
    if isempty(members)
        continue
    end
    [~, order] = sort(selectionKey(members));
    take = min(allocation.requested_count(index), numel(members));
    selected = [selected; members(order(1:take))]; %#ok<AGROW>
end
selected = sort(selected);
if numel(unique(selected)) ~= numel(selected)
    error("vawlume:eda:SubsetSelectionRepeated", ...
        "A recording was selected by two strata, so the strata do not " + ...
        "partition the frame.");
end
if ~isempty(frame) && any(selected > height(frame))
    error("vawlume:eda:SubsetSelectionOutOfFrame", ...
        "A selected index lies outside the frame.");
end
end

% -------------------------------------------------------------- plumbing ---

function value = noRareEffect()
value = struct( ...
    rule="not applied; the sample is not stratified", ...
    floor_changed_allocation=false, ...
    strata_raised_by_floor=strings(0, 1), ...
    places_added_by_floor=0, ...
    places_removed_by_trimming=0, ...
    requested_total=0, ...
    allocated_total=0, ...
    total_raised_above_request=false, ...
    note="a plain seeded random sample has no strata to preserve");
end

function value = emptyAllocation()
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
    VariableNames=["stratum_value", "stratum_size", "proportional_share", ...
    "largest_remainder_count", "floor_added", "trimmed", ...
    "requested_count", "realized_count", "is_under_full"]);
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:SubsetInputInvalid", ...
        "The stratum resolution is missing field(s): %s. Pass a " + ...
        "vawlume.eda.resolveStrata result.", strjoin(missingNames, ", "));
end
end
