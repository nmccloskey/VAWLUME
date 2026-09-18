function result = edaComparableFeatures(conn, extractorNames, options)
%EDACOMPARABLEFEATURES Discover characterization features through the registry only.
%
% RESULT = EDACOMPARABLEFEATURES(CONN, EXTRACTORNAMES) returns the feature
% equivalence classes that are REGISTERED as comparable across the participating
% extractors, and for each one the extractors it is comparable among.
%
% DISCOVERY IS THROUGH `v_cross_extractor_feature_pairs` WITH
% `consilience_eligible`, which is the same path consilienceFeatureAgreement
% uses. Nothing here joins on canonical name, and nothing here contains a feature
% name literal: the eligible set is data, so registering another relationship
% widens the comparison without a code change.
%
% THE SPECIFIC DEFECT THIS PREVENTS IS NOT HYPOTHETICAL, and the pilot registry
% demonstrates it. DeepSqueak registers "Peak Freq (kHz)" and USVSEG registers
% "maxfreq"; BOTH carry equivalence class `vocalization_peak_frequency`. They
% look comparable by every shortcut available - same equivalence class, same
% canonical concept, obviously similar names - and there is NO registered
% relationship between them, because nobody has established that DeepSqueak's
% peak frequency and USVSEG's maxfreq measure the same thing the same way. An
% implementation that grouped by equivalence class, or joined on canonical name,
% would silently produce a peak-frequency comparison that the registry declines
% to support. The matching specification's `forbid_canonical_name_only_join`
% exists for this, and so does this function.
%
% A CLASS IS COMPARABLE AMONG A SET OF EXTRACTORS ONLY IF EVERY PAIR IN THAT SET
% IS REGISTERED. Transitivity is not assumed: A~B and B~C registered does not
% make A~C comparable, because the relationships record pairwise judgements about
% measurement methods and nobody made the third one. Requiring the closure is the
% conservative reading and it is what keeps `vocalization_frequency_bandwidth` -
% registered for DeepSqueak-MUPET only - out of any set containing USVSEG.
%
% RESERVED TIMING CLASSES ARE EXCLUDED, EXCEPT DURATION. The matching
% specification reserves start time, end time and duration as primary evidence so
% temporal quantities are not double-counted when CLASSIFYING correspondence.
% Characterization is a different question - what kinds of detections occupy a
% pattern - so contract §K readmits duration here and only duration. Start and
% end time stay out because they are positions in a recording rather than
% properties of a call: "this call began at 41.2 s" characterizes nothing.

arguments
    conn
    extractorNames string
    options.RequireConsilienceEligible (1,1) logical = true
    options.ReservedTimingClasses string = ["vocalization_start_time", ...
        "vocalization_end_time", "vocalization_duration"]
    options.ReadmittedClasses string = "vocalization_duration"
end

names = unique(strtrim(extractorNames(:)));
names = names(strlength(names) > 0);

rows = fetch(conn, "SELECT feature_relationship_id, " + ...
    "IFNULL(relationship_type,'') AS relationship_type, " + ...
    "consilience_eligible, " + ...
    "IFNULL(comparison_method,'') AS comparison_method, " + ...
    "IFNULL(extractor_a_name,'') AS extractor_a_name, " + ...
    "IFNULL(extractor_b_name,'') AS extractor_b_name, " + ...
    "feature_a_id, feature_b_id, " + ...
    "IFNULL(feature_a_native_name,'') AS feature_a_native_name, " + ...
    "IFNULL(feature_b_native_name,'') AS feature_b_native_name, " + ...
    "IFNULL(feature_a_equivalence_class,'') AS feature_a_equivalence_class, " + ...
    "IFNULL(feature_b_equivalence_class,'') AS feature_b_equivalence_class, " + ...
    "IFNULL(feature_a_canonical_unit,'') AS feature_a_canonical_unit, " + ...
    "IFNULL(feature_b_canonical_unit,'') AS feature_b_canonical_unit " + ...
    "FROM v_cross_extractor_feature_pairs " + ...
    "ORDER BY feature_relationship_id");

pairs = collectPairs(rows, names, options);
classes = summarizeClasses(pairs, names, options);

result = struct( ...
    status="discovered", ...
    extractor_names=names', ...
    pairs=pairs, ...
    classes=classes, ...
    discovery_path="feature_relationships joined to extractor_features " + ...
        "through v_cross_extractor_feature_pairs, filtered to " + ...
        "consilience_eligible relationships", ...
    join_discipline="comparability is REGISTERED, never inferred: no join " + ...
        "on canonical name, no grouping by equivalence class alone, and no " + ...
        "feature name literal appears in this code", ...
    closure_rule="a class is comparable among a set of extractors only when " + ...
        "every unordered pair in that set has a registered eligible " + ...
        "relationship for it; transitivity is not assumed", ...
    reserved_timing_classes=options.ReservedTimingClasses, ...
    readmitted_classes=options.ReadmittedClasses, ...
    reservation_note="the matching specification reserves start time, end " + ...
        "time and duration as primary evidence so temporal quantities are " + ...
        "not double-counted when classifying correspondence. Contract §K " + ...
        "readmits DURATION for characterization, which is a different " + ...
        "question; start and end time remain excluded because they are " + ...
        "positions in a recording rather than properties of a call");
end

% ------------------------------------------------------------------ pairs ---

function pairs = collectPairs(rows, names, options)
%COLLECTPAIRS One row per registered relationship between participating extractors.
pairs = emptyPairs();
if isempty(rows) || height(rows) == 0
    return
end
for index = 1:height(rows)
    row = rows(index, :);
    aName = edaPresentText(row.extractor_a_name(1));
    bName = edaPresentText(row.extractor_b_name(1));
    if ~all(ismember([aName, bName], names))
        continue
    end
    eligible = double(row.consilience_eligible(1)) == 1;
    if options.RequireConsilienceEligible && ~eligible
        continue
    end
    equivalenceClass = resolveClass(row);
    if strlength(equivalenceClass) == 0
        continue
    end
    if isReserved(equivalenceClass, options)
        continue
    end
    % Orientation is by ascending extractor name, not by the view's a/b, which
    % follows the schema's ascending-feature-id CHECK and carries no meaning.
    ordered = sort([aName, bName]);
    pairs(end + 1, :) = {double(row.feature_relationship_id(1)), ...
        equivalenceClass, edaPresentText(row.relationship_type(1)), ...
        eligible, ordered(1), ordered(2), ...
        ordered(1) + "|" + ordered(2), ...
        edaPresentText(row.comparison_method(1)), ...
        unitOf(row)}; %#ok<AGROW>
end
if height(pairs) > 0
    pairs = sortrows(pairs, ["equivalence_class", "extractor_pair"]);
end
end

function value = resolveClass(row)
%RESOLVECLASS The equivalence class both sides agree on, or nothing.
%
% A relationship whose two features declare different equivalence classes is not
% a comparison of one quantity, and guessing which side to believe would invent
% a comparability judgement nobody made. Dropped rather than resolved.
a = edaPresentText(row.feature_a_equivalence_class(1));
b = edaPresentText(row.feature_b_equivalence_class(1));
value = "";
if strlength(a) > 0 && a == b
    value = a;
end
end

function value = isReserved(equivalenceClass, options)
value = ismember(equivalenceClass, options.ReservedTimingClasses) && ...
    ~ismember(equivalenceClass, options.ReadmittedClasses);
end

function value = unitOf(row)
a = edaPresentText(row.feature_a_canonical_unit(1));
b = edaPresentText(row.feature_b_canonical_unit(1));
value = a;
if strlength(value) == 0
    value = b;
end
end

% ---------------------------------------------------------------- classes ---

function classes = summarizeClasses(pairs, names, options)
%SUMMARIZECLASSES Per class, which extractors it is comparable among.
%
% `comparable_extractors` is the largest set whose every pair is registered, not
% the set of extractors that appear in any pair - see the closure rule in the
% header. `is_universally_comparable` is the flag contract §K's cross-pattern
% rule turns on: only a class comparable across the WHOLE participating set may
% be placed on a cross-pattern axis.
classes = emptyClasses();
if height(pairs) == 0
    return
end
distinct = unique(pairs.equivalence_class);
for index = 1:numel(distinct)
    name = distinct(index);
    selected = pairs(pairs.equivalence_class == name, :);
    comparable = closedExtractorSet(selected, names);
    classes(end + 1, :) = {name, ...
        {sort(comparable)'}, numel(comparable), ...
        strjoin(sort(comparable)', "|"), ...
        numel(comparable) == numel(names), ...
        height(selected), ...
        strjoin(unique(selected.relationship_type)', ", "), ...
        unitFor(selected), ...
        ismember(name, options.ReadmittedClasses)}; %#ok<AGROW>
end
classes = sortrows(classes, ["is_universally_comparable", ...
    "equivalence_class"], {'descend', 'ascend'});
end

function value = closedExtractorSet(pairsForClass, names)
%CLOSEDEXTRACTORSET The largest participating subset whose every pair is registered.
%
% Searched from the whole set downwards and stopped at the first closed subset,
% so the answer is the largest one. With at most a handful of extractors the
% enumeration is trivial, and the alternative - taking every extractor that
% appears in any pair - would call a class comparable across three extractors on
% the strength of two relationships.
registered = unique([pairsForClass.extractor_a; pairsForClass.extractor_b]);
candidates = names(ismember(names, registered));
count = numel(candidates);
for size = count:-1:2
    combinations = nchoosek(1:count, size);
    for index = 1:height(combinations)
        subset = candidates(combinations(index, :));
        if allPairsRegistered(subset, pairsForClass)
            value = subset;
            return
        end
    end
end
value = candidates;
if numel(value) > 1
    value = candidates(1);
end
end

function value = allPairsRegistered(subset, pairsForClass)
value = true;
for left = 1:(numel(subset) - 1)
    for right = (left + 1):numel(subset)
        ordered = sort([subset(left), subset(right)]);
        key = ordered(1) + "|" + ordered(2);
        if ~any(pairsForClass.extractor_pair == key)
            value = false;
            return
        end
    end
end
end

function value = unitFor(selected)
units = selected.canonical_unit(strlength(selected.canonical_unit) > 0);
value = "";
if ~isempty(units)
    value = units(1);
end
end

% -------------------------------------------------------------- plumbing ---

function value = emptyPairs()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), false(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), ...
    VariableNames=["feature_relationship_id", "equivalence_class", ...
    "relationship_type", "consilience_eligible", "extractor_a", ...
    "extractor_b", "extractor_pair", "comparison_method", "canonical_unit"]);
end

function value = emptyClasses()
value = table(strings(0, 1), cell(0, 1), zeros(0, 1), strings(0, 1), ...
    false(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), false(0, 1), ...
    VariableNames=["equivalence_class", "comparable_extractors", ...
    "comparable_extractor_count", "comparable_extractor_key", ...
    "is_universally_comparable", "registered_pair_count", ...
    "relationship_types", "canonical_unit", "is_readmitted_timing_class"]);
end
