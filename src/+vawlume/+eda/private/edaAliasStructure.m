function structure = edaAliasStructure(k, generators)
%EDAALIASSTRUCTURE Defining relation, resolution, and what every effect is confounded with.
%
% This is not bookkeeping. A screen that reports a main effect without disclosing
% what it is confounded with is worse than no screen, because it is read with
% more confidence than it has earned. The design exists to screen dimensions and
% expose possible interaction dependence; it is NOT expected to resolve every
% two-factor interaction, and where it cannot, the output has to say so.
%
% Effects are represented as bit masks over the k factors, so an effect is a
% subset and aliasing is the symmetric difference of subsets. A generator
% "D=ABC" contributes the defining word ABCD: the columns of D and of ABC are
% identical, so their product is the all-plus column, which is the identity.
%
% The DEFINING RELATION is the group those words generate under symmetric
% difference, including the identity word I. The RESOLUTION is the length of the
% shortest word in it other than I. Two effects are aliased exactly when their
% symmetric difference is a word of the defining relation, so every effect's
% aliases are found by combining it with each non-identity word.
%
% A full factorial has no generators, so the group is {I} alone, nothing is
% aliased, and every effect is uniquely attributable. The alias table is still
% emitted with empty alias entries, so a consumer reads one shape whichever
% design ran.

letters = edaFactorLetters(k);
words = definingRelation(k, generators);
resolution = resolutionOf(words, k);

effects = effectMasks(k);
count = numel(effects);
effectName = strings(count, 1);
effectOrder = zeros(count, 1);
aliasedWith = strings(count, 1);
aliasCount = zeros(count, 1);
uniquelyAttributable = false(count, 1);

for index = 1:count
    mask = effects(index);
    effectName(index) = maskName(mask, letters);
    effectOrder(index) = popcount(mask);
    aliases = aliasesOf(mask, words);
    aliasCount(index) = numel(aliases);
    uniquelyAttributable(index) = isempty(aliases);
    if ~isempty(aliases)
        names = arrayfun(@(value) maskName(value, letters), aliases);
        aliasedWith(index) = strjoin(sort(names), " = ");
    end
end

aliasTable = table(effectName, effectOrder, aliasedWith, aliasCount, ...
    uniquelyAttributable, ...
    VariableNames=["effect", "effect_order", "aliased_with", "alias_count", ...
    "is_uniquely_attributable"]);

structure = struct( ...
    generators=generators(:)', ...
    defining_relation=definingRelationText(words, letters), ...
    defining_relation_word_count=numel(words), ...
    resolution=resolution, ...
    resolution_label=resolutionLabel(resolution), ...
    alias_table=aliasTable, ...
    main_effects_clear_of_two_factor_interactions= ...
        all(aliasTable.is_uniquely_attributable(aliasTable.effect_order == 1)) || ...
        resolution >= 4, ...
    two_factor_interactions_uniquely_attributable= ...
        all(aliasTable.is_uniquely_attributable(aliasTable.effect_order == 2)), ...
    note=aliasNote(resolution, isempty(generators)));
end

function words = definingRelation(k, generators)
words = uint32(0);
for index = 1:numel(generators)
    word = generatorWord(k, generators(index));
    words = unique([words; bitxor(words, word)]);
end
words = sort(words);
end

function word = generatorWord(k, generator)
parts = split(string(generator), "=");
if numel(parts) ~= 2
    error("vawlume:eda:GeneratorInvalid", ...
        "Generator '%s' is not of the form 'D=ABC'.", generator);
end
letters = edaFactorLetters(k);
added = strtrim(parts(1));
base = strtrim(parts(2));
word = uint32(0);
for name = [added, edaLettersOf(base)]
    position = find(letters == name, 1);
    if isempty(position)
        error("vawlume:eda:GeneratorInvalid", ...
            "Generator '%s' names factor '%s', which is outside the %d " + ...
            "active factors.", generator, name, k);
    end
    word = bitxor(word, bitshift(uint32(1), position - 1));
end
end

function value = resolutionOf(words, k)
nonIdentity = words(words ~= 0);
if isempty(nonIdentity)
    % A full factorial confounds nothing. Reporting an infinite resolution is
    % the honest encoding: there is no shortest word because there are no words.
    value = Inf;
    return
end
value = double(min(arrayfun(@popcount, nonIdentity)));
if value > k
    value = Inf;
end
end

function value = resolutionLabel(resolution)
if ~isfinite(resolution)
    value = "full";
    return
end
numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"];
if resolution >= 1 && resolution <= numel(numerals)
    value = numerals(resolution);
else
    value = string(resolution);
end
end

function masks = effectMasks(k)
masks = uint32([]);
for first = 1:k
    masks(end + 1, 1) = bitshift(uint32(1), first - 1); %#ok<AGROW>
end
for first = 1:(k - 1)
    for second = (first + 1):k
        masks(end + 1, 1) = bitor(bitshift(uint32(1), first - 1), ...
            bitshift(uint32(1), second - 1)); %#ok<AGROW>
    end
end
end

function aliases = aliasesOf(mask, words)
aliases = uint32([]);
for index = 1:numel(words)
    if words(index) == 0
        continue
    end
    aliases(end + 1, 1) = bitxor(mask, words(index)); %#ok<AGROW>
end
aliases = unique(aliases);
aliases = aliases(aliases ~= mask & aliases ~= 0);
end

function value = maskName(mask, letters)
selected = false(1, numel(letters));
for index = 1:numel(letters)
    selected(index) = bitget(mask, index) == 1;
end
if ~any(selected)
    value = "I";
    return
end
value = strjoin(letters(selected), "");
end

function value = definingRelationText(words, letters)
names = arrayfun(@(word) maskName(word, letters), words);
value = strjoin(["I", sort(names(names ~= "I"))'], " = ");
end

function value = popcount(mask)
value = 0;
for index = 1:32
    value = value + double(bitget(mask, index));
end
end

function value = aliasNote(resolution, isFull)
if isFull
    value = "Full factorial: nothing is confounded. Every main effect and " + ...
        "every two-factor interaction is uniquely attributable.";
    return
end
if resolution >= 5
    value = "Resolution " + resolutionLabel(resolution) + ": main effects " + ...
        "and two-factor interactions are clear of each other and of other " + ...
        "two-factor interactions.";
elseif resolution == 4
    value = "Resolution IV: main effects are clear of two-factor " + ...
        "interactions, but TWO-FACTOR INTERACTIONS ARE ALIASED IN PAIRS AND " + ...
        "CANNOT BE SEPARATED. An interaction estimate from this design is " + ...
        "the sum of its aliased pair, not either member alone.";
else
    value = "Resolution " + resolutionLabel(resolution) + ": MAIN EFFECTS " + ...
        "ARE ALIASED WITH TWO-FACTOR INTERACTIONS. A main effect from this " + ...
        "design cannot be attributed to its factor alone.";
end
end
