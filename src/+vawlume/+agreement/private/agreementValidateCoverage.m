function [extractorRuns, coverage] = agreementValidateCoverage(sources, specification)
%AGREEMENTVALIDATECOVERAGE Require a complete unordered pairwise set.
%
% For N participating extraction runs there are N*(N-1)/2 unordered extractor
% pairs, and this pass requires every one of them exactly once. The reason is
% evidential rather than aesthetic: with a pair missing, an absent supporting
% edge in the composed result cannot be distinguished from a pair that was never
% assessed, and every agreement pattern read off the result would be ambiguous.
%
% Partial coverage is a later design question, not a silent allowance.

if specification.pairwise_coverage ~= "complete_unordered_pair_set"
    error("vawlume:agreement:CoveragePolicyUnsupported", ...
        "Only 'complete_unordered_pair_set' coverage is implemented, not '%s'.", ...
        specification.pairwise_coverage);
end

extractorRuns = participatingRuns(sources, specification);
observedPairs = height(sources);
runCount = height(extractorRuns);
expectedPairs = runCount * (runCount - 1) / 2;

pairLabels = sources.pair_label;
[distinct, ~, grouping] = unique(pairLabels);
occurrences = accumarray(grouping, 1);
repeated = distinct(occurrences > 1);
if ~isempty(repeated)
    error("vawlume:agreement:DuplicateExtractorPair", ...
        "Extractor pair %s is covered by more than one source analysis.", ...
        strjoin("'" + repeated(:)' + "'", ", "));
end

expectedLabels = unorderedPairLabels(extractorRuns.extractor_name);
missing = setdiff(expectedLabels, pairLabels);
if ~isempty(missing)
    error("vawlume:agreement:IncompletePairCoverage", ...
        "Pairwise coverage is incomplete: %d of %d unordered extractor pairs " + ...
        "are present, missing %s. An unassessed pair cannot be distinguished " + ...
        "from an absent supporting edge.", observedPairs, expectedPairs, ...
        strjoin("'" + missing(:)' + "'", ", "));
end
unexpected = setdiff(pairLabels, expectedLabels);
if ~isempty(unexpected)
    error("vawlume:agreement:IncompletePairCoverage", ...
        "Source analyses cover extractor pair %s, which is outside the " + ...
        "participating extractor set.", strjoin("'" + unexpected(:)' + "'", ", "));
end

% Two pairwise analyses run under different matching specifications have
% different candidate universes, so their edges answer different questions and
% must not be composed into one component.
if specification.require_identical_matching_specification_version
    versions = unique(sources.matching_specification_version_id);
    if numel(versions) ~= 1
        error("vawlume:agreement:SpecificationVersionMismatch", ...
            "Source analyses cite %d different matching specification " + ...
            "versions (%s); a composable set cites exactly one.", ...
            numel(versions), strjoin(string(versions(:)'), ", "));
    end
end

coverage = struct( ...
    participating_extractor_runs=runCount, ...
    expected_pairs=expectedPairs, ...
    observed_pairs=observedPairs, ...
    complete=true, ...
    pair_labels=sort(pairLabels), ...
    matching_specification_version_id=sources.matching_specification_version_id(1), ...
    rule=specification.pairwise_coverage);
end

function runs = participatingRuns(sources, specification)
%PARTICIPATINGRUNS One row per distinct extraction run across all sources.
ids = [sources.run_a_extraction_run_id; sources.run_b_extraction_run_id];
keys = [sources.run_a_key; sources.run_b_key];
extractorIds = [sources.run_a_extractor_id; sources.run_b_extractor_id];
names = [sources.run_a_extractor_name; sources.run_b_extractor_name];
[distinctIds, first] = unique(ids, "first");
runs = table(distinctIds, keys(first), extractorIds(first), names(first), ...
    VariableNames=["extraction_run_id", "run_key", "extractor_id", ...
    "extractor_name"]);
runs = sortrows(runs, ["extractor_name", "run_key"]);

if specification.require_distinct_extractor_per_run
    [distinctExtractors, ~, grouping] = unique(runs.extractor_id);
    occurrences = accumarray(grouping, 1);
    repeated = distinctExtractors(occurrences > 1);
    if ~isempty(repeated)
        offending = runs.extractor_name(ismember(runs.extractor_id, repeated));
        error("vawlume:agreement:RepeatedExtractor", ...
            "Extractor %s contributes more than one extraction run. This " + ...
            "Phase 1 path requires one run per extractor so that an " + ...
            "unordered extractor pair identifies exactly one comparison.", ...
            strjoin("'" + unique(offending(:))' + "'", ", "));
    end
end

if height(runs) < 2
    error("vawlume:agreement:SourcesInvalid", ...
        "An agreement run needs at least two participating extraction runs.");
end
end

function labels = unorderedPairLabels(names)
labels = strings(0, 1);
sorted = sort(names);
for left = 1:numel(sorted) - 1
    for right = left + 1:numel(sorted)
        labels(end + 1, 1) = strjoin(sort([sorted(left), sorted(right)]), "|"); %#ok<AGROW>
    end
end
labels = unique(labels);
end
