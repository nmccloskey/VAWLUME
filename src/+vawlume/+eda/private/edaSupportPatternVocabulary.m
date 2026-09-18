function value = edaSupportPatternVocabulary(extractorKeys)
%EDASUPPORTPATTERNVOCABULARY Every exact extractor-set pattern for N extractors.
%
% VALUE = EDASUPPORTPATTERNVOCABULARY(EXTRACTORKEYS) enumerates all 2^N - 1
% non-empty subsets of the participating extractor set, in ascending size then
% ascending key order, as the `extractor_set_key` spelling the database uses:
% member keys sorted ascending and joined with "|".
%
% For the three-extractor pilot this is conceptual spec §2.3's seven categories:
% DeepSqueak only, MUPET only, USVSEG only, the three pairs, and the three-way
% set. THE VOCABULARY IS ENUMERATED, NOT OBSERVED, so a pattern with no groups
% still gets a row. A reader must be able to see that a pattern was looked for
% and not found; an absent row and a zero-count row look the same in a table and
% mean completely different things.
%
% DERIVED FROM THE DATABASE'S OWN EXTRACTOR KEYS, never from a list of three.
% Two extractors give three patterns and four give fifteen, and nothing here
% assumes the pilot set.
%
% THIS IS THE EXTRACTOR SET, NOT THE SUPPORTED PAIR PATTERN. The two are
% different vocabularies over the same groups and the database carries both:
% `extractor_set_key` says which extractors contributed a member, while
% `supported_extractor_pair_pattern` says which pairs actually corroborated each
% other. A singleton group has pair pattern "(none)" whichever extractor it came
% from, so the pair pattern alone cannot tell "DeepSqueak only" from "USVSEG
% only" - which is exactly what §2.3 requires to stay distinguishable. Joining
% the two vocabularies on a shared name would silently merge those three
% categories into one.

arguments
    extractorKeys string
end

keys = unique(strtrim(extractorKeys(:)));
keys = keys(strlength(keys) > 0);
if isempty(keys)
    error("vawlume:eda:ExtractorSetEmpty", ...
        "No extractor key was supplied, so there is no support-pattern " + ...
        "vocabulary to enumerate.");
end
if numel(keys) > 16
    error("vawlume:eda:ExtractorSetTooLarge", ...
        "%d extractors would enumerate %d patterns. The exact vocabulary " + ...
        "grows as 2^N and stops being readable long before it stops being " + ...
        "computable.", numel(keys), 2^numel(keys) - 1);
end

count = numel(keys);
setKey = strings(0, 1);
setLabel = strings(0, 1);
members = cell(0, 1);
memberCount = zeros(0, 1);

for size = 1:count
    combinations = nchoosek(1:count, size);
    for index = 1:height(combinations)
        selected = keys(combinations(index, :));
        setKey(end + 1, 1) = strjoin(sort(selected)', "|"); %#ok<AGROW>
        setLabel(end + 1, 1) = strjoin(sort(selected)', " + "); %#ok<AGROW>
        members{end + 1, 1} = sort(selected)'; %#ok<AGROW>
        memberCount(end + 1, 1) = size; %#ok<AGROW>
    end
end

isUnique = memberCount == 1;
isComplete = memberCount == count;
value = table(setKey, setLabel, members, memberCount, isUnique, isComplete, ...
    VariableNames=["extractor_set_key", "extractor_set_label", ...
    "extractor_keys", "extractor_count", "is_extractor_unique", ...
    "is_complete_support"]);
end
