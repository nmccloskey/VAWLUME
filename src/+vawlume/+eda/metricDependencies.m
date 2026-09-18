function result = metricDependencies(surface, options)
%METRICDEPENDENCIES How the candidate-matching metrics relate to one another.
%
% RESULT = vawlume.eda.METRICDEPENDENCIES(SURFACE) computes Pearson correlation,
% Spearman rank correlation, and partial correlation among the metrics of a
% vawlume.eda.candidateMetrics surface, each only where it is genuinely defined
% and each reporting its undefined cases with a reason.
%
% This answers whether the threshold dimensions about to be screened are largely
% redundant with one another - which is the difference between a four-factor
% screen and a two-factor screen wearing four labels.
%
% Name-value options:
%   Metrics                   subset of metric names; default every metric the
%                             surface names
%   ObservationMargin         complete cases must exceed the retained metric
%                             count by this margin for a partial correlation,
%                             default 10
%   MinimumPairObservations   floor below which a single correlation cell is
%                             undefined, default 3
%   ConditionNumberFloor      reciprocal-condition-number floor, default 1e-10
%   NearConstantTolerance     near-constant rule tolerance, default 1e-9
%   RedundancyThreshold       magnitude at or above which a pair is reported
%                             strongly redundant, default 0.90
%   ScreenedFactorMetrics     metric columns corresponding to the screened
%                             factors; default the four the contract screens
%
% MISSING VALUES follow a two-stage policy, and which stage ran is recorded in
% RESULT.observation_policy because the two give different matrices and a reader
% cannot tell them apart from the numbers alone.
%
%   primary   listwise deletion over the requested metrics. One sample for every
%             cell, which is what makes the three matrices comparable and what
%             the partial correlation requires: one invertible matrix needs one
%             consistent sample.
%   fallback  when the complete-case count falls below the floor, Pearson and
%             Spearman are computed pairwise and LABELLED pairwise, and the
%             partial matrix is reported entirely undefined.
%
% The fallback is expected rather than hypothetical. Feature-discrepancy columns
% are sparse wherever an extractor registers few comparable features, so listwise
% deletion across every metric can retain very few rows. RESULT.observation_policy
% names the metrics whose absences cost the most complete cases, so a caller can
% restrict `Metrics` and recover a usable partial correlation rather than being
% told only that it failed.
%
% These are EXPLORATORY DEPENDENCY MEASURES. Nothing here is evidence of a causal
% relationship. No p-value, confidence interval, or multiple-comparison
% correction is computed anywhere: these are dependency measures over a
% convenience sample of candidate pairs, and attaching inferential machinery
% would imply a sampling model this MVP does not have.
%
% Redundancy is REPORTED, never pruned. The conceptual specification forbids
% deleting a scientifically requested dimension on the strength of a correlation
% statistic. This function edits no factor set; it says what a reader of the
% leverage report needs to know.
%
% Implemented in base MATLAB: Pearson through `corrcoef`, Spearman through
% vawlume.eda.midRank, partial through `inv` and `rcond`. `corr` and
% `partialcorr` are Statistics and Machine Learning Toolbox functions in every
% release and are not called.
%
% This function is pure. It takes no connection, reads no database, and draws
% nothing.

arguments
    surface (1,1) struct
    options.Metrics (1,:) string = strings(1, 0)
    options.ObservationMargin (1,1) double {mustBeNonnegative} = 10
    options.MinimumPairObservations (1,1) double {mustBeNonnegative} = 3
    options.ConditionNumberFloor (1,1) double {mustBeNonnegative} = 1e-10
    options.NearConstantTolerance (1,1) double {mustBeNonnegative} = 1e-9
    options.RedundancyThreshold (1,1) double = 0.90
    options.ScreenedFactorMetrics (1,:) string = edaScreenedFactorMetrics()
end

requireFields(surface, ["metrics", "metric_names"]);
if options.RedundancyThreshold < 0 || options.RedundancyThreshold > 1
    error("vawlume:eda:RedundancyThresholdInvalid", ...
        "RedundancyThreshold must lie in [0, 1].");
end

names = resolveMetrics(surface, options.Metrics);
values = gather(surface, names);

completeRows = all(isfinite(values), 2);
completeN = nnz(completeRows);
listwiseSample = values(completeRows, :);

% Degeneracy is judged on the sample that will actually be used, because a
% column can be constant across the complete cases while varying across the full
% dataset, and it is the complete cases the listwise correlation sees.
if completeN > 0
    degeneracy = edaColumnDegeneracy(listwiseSample, names, ...
        options.NearConstantTolerance);
else
    degeneracy = edaColumnDegeneracy(values, names, ...
        options.NearConstantTolerance);
end
retainedCount = nnz(~degeneracy.is_degenerate);
required = retainedCount + options.ObservationMargin;

if completeN >= required && retainedCount >= 2
    mode = "listwise";
    sample = listwiseSample;
else
    mode = "pairwise";
    sample = values;
    degeneracy = edaColumnDegeneracy(values, names, ...
        options.NearConstantTolerance);
end

correlations = edaCorrelationMatrices(sample, names, mode, degeneracy, options);

if mode == "listwise"
    partial = edaPartialCorrelation(correlations.pearson, names, degeneracy, ...
        completeN, options);
else
    partial = edaPartialCorrelation(NaN(numel(names)), names, degeneracy, ...
        0, options);
    partial.detail = "Listwise deletion retained " + string(completeN) + ...
        " complete cases against a floor of " + string(required) + ...
        ", so the marginals fell back to pairwise deletion and no single " + ...
        "consistent sample exists to invert.";
end

pairs = pairTable(names, correlations, partial, options);
redundancy = edaRedundancy(pairs, options);

result = struct( ...
    status="computed", ...
    metric_names=names, ...
    metric_count=numel(names), ...
    row_count=size(values, 1), ...
    observation_policy=observationPolicy(mode, completeN, required, ...
        retainedCount, values, names, options), ...
    degeneracy=degeneracy, ...
    excluded_metrics=degeneracy(degeneracy.is_degenerate, ...
        ["metric_name", "observations", "reason"]), ...
    pearson=correlations.pearson, ...
    spearman=correlations.spearman, ...
    correlation_observations=correlations.observations, ...
    correlation_undefined_reason=correlations.undefined_reason, ...
    partial=partial, ...
    pairs=pairs, ...
    redundancy=redundancy, ...
    undefined_reason_vocabulary=edaUndefinedReasons()', ...
    measure_semantics=measureSemantics(), ...
    interpretation=interpretation(redundancy, mode, partial), ...
    statistics_implementation= ...
        "base MATLAB; corrcoef, vawlume.eda.midRank, inv and rcond only", ...
    inference_note= ...
        "No p-value, confidence interval, or multiple-comparison correction " + ...
        "is computed. These are exploratory dependency measures over a " + ...
        "convenience sample of candidate pairs, not hypothesis tests.", ...
    caution=edaCautionNote());
end

% ---------------------------------------------------------------- inputs ---

function names = resolveMetrics(surface, requested)
available = string(surface.metric_names(:))';
if isempty(requested)
    names = available;
else
    unknown = requested(~ismember(requested, available));
    if ~isempty(unknown)
        error("vawlume:eda:MetricNotPresent", ...
            "The surface does not name metric(s): %s.", ...
            strjoin(unknown, ", "));
    end
    names = requested;
end
if numel(unique(names)) ~= numel(names)
    error("vawlume:eda:MetricNotDistinct", ...
        "Requested metrics must be distinct.");
end
if numel(names) < 2
    error("vawlume:eda:TooFewMetrics", ...
        "Dependency diagnostics need at least two metrics; %d was requested.", ...
        numel(names));
end
end

function values = gather(surface, names)
present = string(surface.metrics.Properties.VariableNames);
values = NaN(height(surface.metrics), numel(names));
for index = 1:numel(names)
    if ~ismember(names(index), present)
        error("vawlume:eda:MetricNotPresent", ...
            "Metric '%s' is named by the surface but absent from its table.", ...
            names(index));
    end
    values(:, index) = double(surface.metrics.(names(index)));
end
end

% --------------------------------------------------------------- outputs ---

function value = observationPolicy(mode, completeN, required, retainedCount, ...
    values, names, options)
if mode == "listwise"
    description = "Listwise deletion: every cell shares one complete-case " + ...
        "sample, so the three matrices are mutually comparable.";
else
    description = "Pairwise deletion: each cell uses its own jointly-finite " + ...
        "subset. The cells are not mutually consistent, the matrix need not " + ...
        "be positive semi-definite, and the partial correlation is undefined.";
end
value = struct( ...
    mode=string(mode), ...
    deletion=string(mode), ...
    complete_case_n=completeN, ...
    required_minimum=required, ...
    retained_metric_count=retainedCount, ...
    observation_margin=options.ObservationMargin, ...
    minimum_pair_observations=options.MinimumPairObservations, ...
    condition_number_floor=options.ConditionNumberFloor, ...
    near_constant_tolerance=options.NearConstantTolerance, ...
    limiting_metrics=limitingMetrics(values, names), ...
    description=description);
end

function value = limitingMetrics(values, names)
%LIMITINGMETRICS Which metrics cost the complete cases, by three complementary counts.
%
% Naming the culprit matters more than reporting that the complete-case sample
% was small: a caller who knows which metrics are starving the listwise sample
% can restrict `Metrics` and recover a usable partial correlation.
%
% One count is not enough, because the interesting case has several culprits at
% once. For the pilot extractor set, every band-edge feature is unavailable on
% exactly the same rows - those of any pair containing an extractor that
% registers no band edges - so no single one of them is *uniquely* responsible
% for any lost row and an attribution that only counts unique blame names nobody
% at all. Three counts are reported:
%
%   non_finite_rows             rows where this metric alone is absent. Always
%                               names a sparse column, whether or not others
%                               share its absences.
%   complete_cases_lost_alone   rows finite in every OTHER metric and absent
%                               here. Precise blame; zero when culprits overlap.
%   complete_cases_without_it   complete cases that would remain if this metric
%                               were dropped. Directly actionable, and still
%                               flat when a whole group must go together.
%
% Sorted by non_finite_rows descending, so the sparse columns lead the table in
% every case including the overlapping one.
count = numel(names);
finite = isfinite(values);
absent = zeros(count, 1);
lostAlone = zeros(count, 1);
withoutIt = zeros(count, 1);

for index = 1:count
    others = true(1, count);
    others(index) = false;
    absent(index) = nnz(~finite(:, index));
    if count == 1
        lostAlone(index) = absent(index);
        withoutIt(index) = size(values, 1);
        continue
    end
    completeElsewhere = all(finite(:, others), 2);
    lostAlone(index) = nnz(completeElsewhere & ~finite(:, index));
    withoutIt(index) = nnz(completeElsewhere);
end

value = sortrows(table(names(:), absent, lostAlone, withoutIt, ...
    VariableNames=["metric_name", "non_finite_rows", ...
    "complete_cases_lost_alone", "complete_cases_without_it"]), ...
    ["non_finite_rows", "complete_cases_lost_alone"], "descend");
end

function value = pairTable(names, correlations, partial, options)
%PAIRTABLE The tidy long form: one row per unordered metric pair.
%
% The matrices are what a heatmap consumes; this is what a test asserts on, what
% gets exported, and what a reader filters.
count = numel(names);
rows = cell(0, 1);
screened = options.ScreenedFactorMetrics;
for i = 1:(count - 1)
    for j = (i + 1):count
        relevance = screeningRelevance(names(i), names(j), screened);
        rows{end + 1, 1} = {names(i), names(j), ...
            correlations.pearson(i, j), correlations.spearman(i, j), ...
            correlations.observations(i, j), ...
            correlations.undefined_reason(i, j), ...
            partial.matrix(i, j), partial.undefined_reason(i, j), ...
            relevance}; %#ok<AGROW>
    end
end
value = emptyPairs();
for index = 1:numel(rows)
    value(end + 1, :) = rows{index}; %#ok<AGROW>
end
end

function value = screeningRelevance(a, b, screened)
inA = ismember(a, screened);
inB = ismember(b, screened);
if inA && inB
    value = "both_screened_factors";
elseif inA || inB
    value = "one_screened_factor";
else
    value = "neither_screened_factor";
end
end

function value = emptyPairs()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["metric_a", "metric_b", "pearson", "spearman", ...
    "observations", "correlation_undefined_reason", "partial", ...
    "partial_undefined_reason", "screening_relevance"]);
end

function value = measureSemantics()
value = [ ...
    "Pearson and Spearman are exploratory dependency measures, not evidence " + ...
        "of a causal relationship."; ...
    "Spearman is the Pearson correlation of mid-ranks, so it measures " + ...
        "monotone association and is the robust companion to Pearson on " + ...
        "bounded, skewed metrics such as a gated temporal IoU."; ...
    "A partial correlation controls only for the other RETAINED metrics in " + ...
        "this run. It does not control for anything unmeasured, and " + ...
        "restricting the metric set changes what it means."; ...
    "An undefined cell is NaN with a reason. It is not zero, and it must " + ...
        "not be read as absence of association."];
end

function value = interpretation(redundancy, mode, partial)
value = strings(0, 1);
if height(redundancy) == 0
    value(end + 1, 1) = "No metric pair reached the redundancy threshold.";
else
    value(end + 1, 1) = string(height(redundancy)) + " metric pair(s) " + ...
        "reached the redundancy threshold. Two strongly collinear factors " + ...
        "in a screening design produce main effects that cannot be " + ...
        "attributed separately, so a leverage report over these dimensions " + ...
        "should be read with that in mind.";
    screened = redundancy(redundancy.screening_relevance == ...
        "both_screened_factors", :);
    if height(screened) > 0
        value(end + 1, 1) = "Of those, " + string(height(screened)) + ...
            " pair(s) are between two SCREENED FACTORS: " + ...
            strjoin(screened.metric_a + " ~ " + screened.metric_b, "; ") + ...
            ". This does not change the factor set, which the contract " + ...
            "fixes, but it changes how the screen's main effects should be " + ...
            "read.";
    end
end
value(end + 1, 1) = "Nothing was pruned. Redundancy is reported so the " + ...
    "screening design and its report can be read in its light; the factor " + ...
    "set is fixed by the governing contract, not by a correlation statistic.";
if mode == "pairwise"
    value(end + 1, 1) = "Marginal correlations used pairwise deletion, so " + ...
        "their cells rest on different samples and the matrix need not be " + ...
        "positive semi-definite. The partial correlation is undefined: " + ...
        partial.detail;
end
end

function requireFields(surface, names)
missingNames = names(~isfield(surface, names));
if ~isempty(missingNames)
    error("vawlume:eda:SurfaceInvalid", ...
        "The supplied surface is missing required field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
