function record = probeParameters(surface, options, extras)
%PROBEPARAMETERS Resolve which threshold dimensions to screen, and at what values.
%
% RECORD = vawlume.eda.PROBEPARAMETERS(SURFACE) decides on its own which of the
% contract's threshold dimensions participate in a screen and what low and high
% values to probe each at, from the observed candidate-metric distributions in
% SURFACE. RECORD is the serializable account of every choice it made.
%
% RECORD = vawlume.eda.PROBEPARAMETERS(SURFACE, OPTIONS) applies a configuration
% from vawlume.eda.explorationOptions.
%
% Name-value extras:
%   ReferenceSpecPath        path to the reference configuration, read for
%                            comparison only
%   ReferencePlausibility    an already-read plausibility rule struct, as an
%                            alternative to the path
%   RedundancyFindings       the redundancy table from the dependency
%                            diagnostics, recorded beside the factors
%
% THE SYSTEM IS ALLOWED TO CHOOSE. It is not allowed to choose invisibly, and it
% is never allowed to choose in a way that could be described as optimizing.
% Every value here spans a plausible range so a screen can show how outcomes move
% across it. No value is optimal, recommended, or best, and nothing downstream may
% describe one that way.
%
% Two sources fix each factor's interval, in priority order: an explicit user
% override, otherwise quantiles of the observed metric. Quantile anchoring rather
% than fixed constants, because a hard-coded pair can sit entirely outside a
% dataset's observed range and produce a factor that reports zero leverage for a
% reason that has nothing to do with the science.
%
% A factor is reported INACTIVE WITH ITS REASON rather than screened at an
% arbitrary value when its metric has too little coverage to place a quantile, or
% when low and high resolve to the same value. An invariant design column
% silently destroys the design's balance and yields a main effect of exactly zero
% that looks like a finding.
%
% A FACTOR IS NEVER DEACTIVATED FOR BEING REDUNDANT with another. The conceptual
% specification forbids removing a scientifically requested dimension on the
% strength of a correlation statistic. A redundancy finding is recorded beside
% the factor, so the leverage report can be read in its light, and the factor is
% screened anyway.
%
% This function is pure and offline. It opens no database connection, writes no
% file, and runs no matching analysis: probe values come from distributions
% already computed, which is what makes the resolution cheap enough to inspect
% before anything is executed.

arguments
    surface (1,1) struct
    options (1,1) struct = vawlume.eda.explorationOptions()
    extras.ReferenceSpecPath (1,1) string = ""
    extras.ReferencePlausibility struct = struct.empty
    extras.RedundancyFindings = table.empty(0, 0)
end

options = vawlume.eda.explorationOptions(options);
policy = edaFactorPolicy();
redundancy = normalizeRedundancy(extras.RedundancyFindings);
reference = resolveReference(extras);
[seed, seedSource, seedBasis] = resolveSeed(surface, options);

if ~options.enabled
    record = disabledRecord(seed, seedSource, seedBasis, options, reference, ...
        redundancy);
    return
end

requireFields(surface, ["metrics", "metric_names"]);
factors = emptyFactors();
for index = 1:height(policy)
    factors(end + 1, :) = resolveFactor(surface, policy(index, :), options, ...
        reference, redundancy); %#ok<AGROW>
end

active = factors.is_active;
record = struct( ...
    status="resolved", ...
    exploration_enabled=true, ...
    seed=seed, ...
    seed_source=seedSource, ...
    seed_basis=seedBasis, ...
    analysis_budget=emptyToNaN(options.analysis_budget), ...
    analysis_budget_source=sourceOf(options.analysis_budget), ...
    subset_size=emptyToNaN(options.subset_size), ...
    subset_size_source=sourceOf(options.subset_size), ...
    factors=factors, ...
    active_factor_count=nnz(active), ...
    active_factor_names=factors.factor_name(active)', ...
    inactive_factor_names=factors.factor_name(~active)', ...
    design_feasibility=designFeasibility(nnz(active)), ...
    reference_configuration=reference, ...
    redundancy_findings=redundancy, ...
    inactive_reason_vocabulary=edaInactiveReasons()', ...
    policy=policyRecord(options), ...
    warnings=warningsFor(factors, reference), ...
    interpretation=interpretationFor(factors, reference, redundancy), ...
    language_note= ...
        "These are probe values spanning a plausible range. None is optimal, " + ...
        "recommended, or calibrated, and no downstream report may describe " + ...
        "one that way.", ...
    caution=edaCautionNote());
end

% -------------------------------------------------------------- factors ---

function row = resolveFactor(surface, policy, options, reference, redundancy)
factorName = policy.factor_name;
metricName = policy.metric_name;
values = NaN(0, 1);
supported = 0;

present = ismember(metricName, string(surface.metrics.Properties.VariableNames));
if present
    column = double(surface.metrics.(metricName));
    values = column(isfinite(column));
    supported = numel(values);
end

override = [];
if isfield(options.threshold_ranges, factorName)
    override = options.threshold_ranges.(factorName);
end

low = NaN;
high = NaN;
lowQuantile = NaN;
highQuantile = NaN;
valueSource = "not_resolved";
reason = "";

if ismember(factorName, options.disabled_factors)
    reason = "disabled_by_user";
elseif ~isempty(override)
    % A user override does not need the metric: the caller has supplied the
    % interval directly and is entitled to probe a range the dataset is thin on.
    low = override(1);
    high = override(2);
    valueSource = "user_override";
elseif ~present
    reason = "metric_absent";
elseif supported < options.minimum_supported_observations
    reason = "insufficient_coverage";
else
    lowQuantile = policy.low_quantile;
    highQuantile = policy.high_quantile;
    low = vawlume.eda.sampleQuantile(values, lowQuantile);
    high = vawlume.eda.sampleQuantile(values, highQuantile);
    valueSource = "observed_quantile";
end

if strlength(reason) == 0 && isDegenerate(low, high, ...
        options.degenerate_interval_tolerance)
    reason = "degenerate_interval";
end
isActive = strlength(reason) == 0;
if ~isActive
    low = NaN;
    high = NaN;
end

[referenceValue, comparison] = compareToReference(reference, factorName, ...
    low, high, isActive);

row = {factorName, metricName, isActive, reason, low, high, ...
    lowQuantile, highQuantile, valueSource, supported, ...
    policy.strictness_direction, policy.unit, referenceValue, comparison, ...
    isRedundant(redundancy, metricName)};
end

function value = isDegenerate(low, high, tolerance)
value = true;
if ~isfinite(low) || ~isfinite(high)
    return
end
width = high - low;
if width <= 0
    return
end
value = width <= tolerance * max(1, max(abs([low high])));
end

function [referenceValue, comparison] = compareToReference(reference, ...
    factorName, low, high, isActive)
referenceValue = NaN;
if ~reference.available
    comparison = "reference_not_supplied";
    return
end
if isfield(reference.values, factorName)
    referenceValue = reference.values.(factorName);
end
if ~isfinite(referenceValue)
    % The tracked reference declares no bound on this dimension, so it is
    % unconstrained there and no interval can bracket it. Reporting this as a
    % failed bracket check would be wrong: the screen is exploring a region the
    % reference does not occupy, and every probed value is stricter than it.
    comparison = "reference_unconstrained";
    return
end
if ~isActive
    comparison = "factor_inactive";
    return
end
if referenceValue < low
    comparison = "reference_below_interval";
elseif referenceValue > high
    comparison = "reference_above_interval";
else
    comparison = "reference_within_interval";
end
end

function value = isRedundant(redundancy, metricName)
value = false;
if height(redundancy) == 0
    return
end
value = any(redundancy.metric_a == metricName | ...
    redundancy.metric_b == metricName);
end

% --------------------------------------------------------------- inputs ---

function reference = resolveReference(extras)
if ~isempty(extras.ReferencePlausibility)
    reference = edaReferencePlausibility(extras.ReferencePlausibility);
    return
end
reference = edaReferencePlausibility(extras.ReferenceSpecPath);
end

function value = normalizeRedundancy(supplied)
if istable(supplied) && all(ismember(["metric_a", "metric_b"], ...
        string(supplied.Properties.VariableNames)))
    value = supplied;
    return
end
if istable(supplied) && height(supplied) == 0
    value = table(strings(0, 1), strings(0, 1), ...
        VariableNames=["metric_a", "metric_b"]);
    return
end
error("vawlume:eda:RedundancyFindingsInvalid", ...
    "RedundancyFindings must be the dependency diagnostics' redundancy " + ...
    "table, carrying metric_a and metric_b.");
end

function [seed, source, basis] = resolveSeed(surface, options)
if ~isempty(options.seed)
    seed = options.seed;
    source = "user";
    basis = "";
    return
end
[seed, basis] = edaDeterministicSeed(surface);
source = "derived_from_dataset_identity";
end

% -------------------------------------------------------------- reports ---

function value = designFeasibility(activeCount)
possible = activeCount >= 3;
if possible
    note = "At least three active factors, so an interaction-aware screening " + ...
        "design is constructible.";
else
    note = "FEWER THAN THREE ACTIVE FACTORS. An interaction-aware screening " + ...
        "design is not constructible below three: a design over one or two " + ...
        "factors can only perturb them one at a time, which the conceptual " + ...
        "specification's screening requirement explicitly rules out. The " + ...
        "design layer will have nothing to screen.";
end
value = struct( ...
    active_factor_count=activeCount, ...
    interaction_aware_screen_possible=possible, ...
    minimum_for_interaction_aware_screen=3, ...
    note=note);
end

function value = warningsFor(factors, reference)
value = strings(0, 1);
activeCount = nnz(factors.is_active);
if activeCount < 3
    value(end + 1, 1) = "Only " + string(activeCount) + " of " + ...
        string(height(factors)) + " contract factors are active; an " + ...
        "interaction-aware screen needs at least three.";
end
inactive = factors(~factors.is_active, :);
for index = 1:height(inactive)
    value(end + 1, 1) = "Factor '" + inactive.factor_name(index) + ...
        "' is inactive: " + inactive.inactive_reason(index) + "."; %#ok<AGROW>
end
unconstrained = factors(factors.reference_comparison == ...
    "reference_unconstrained", :);
if height(unconstrained) > 0
    value(end + 1, 1) = "The reference configuration declares no bound on " + ...
        strjoin(unconstrained.factor_name', ", ") + ", so no probed " + ...
        "interval can bracket it there and every probed configuration is " + ...
        "stricter than the reference on those dimensions.";
end
outside = factors(ismember(factors.reference_comparison, ...
    ["reference_below_interval", "reference_above_interval"]), :);
for index = 1:height(outside)
    value(end + 1, 1) = "The reference configuration's value for '" + ...
        outside.factor_name(index) + "' lies outside the probed interval (" + ...
        outside.reference_comparison(index) + "). The screen is still " + ...
        "informative, but it does not bracket the configuration the " + ...
        "support-pattern characterization uses."; %#ok<AGROW>
end
if reference.available && strlength(reference.calibration_state) > 0 && ...
        reference.calibration_state ~= "calibrated"
    value(end + 1, 1) = "The reference configuration's calibration status is '" + ...
        reference.calibration_state + "'. Using it as a reference does not " + ...
        "make it calibrated, and probing around it does not either.";
end
end

function value = interpretationFor(factors, reference, redundancy)
value = strings(0, 1);
value(end + 1, 1) = string(nnz(factors.is_active)) + " of " + ...
    string(height(factors)) + " contract factors are active. Low and high " + ...
    "name the parameter value, never the strictness: a larger " + ...
    "min_temporal_iou is stricter while a larger max_abs_ bound is looser, " + ...
    "and each factor's direction is recorded beside it.";
if height(redundancy) > 0
    flagged = factors(factors.flagged_redundant, :);
    if height(flagged) > 0
        value(end + 1, 1) = "The dependency diagnostics flagged " + ...
            strjoin(flagged.factor_name', ", ") + " as strongly associated " + ...
            "with another metric. NO FACTOR WAS REMOVED FOR THIS. The " + ...
            "finding is recorded so the leverage report can be read in its " + ...
            "light; two collinear factors produce main effects that cannot " + ...
            "be attributed separately.";
    end
end
if ~reference.available
    value(end + 1, 1) = "No reference configuration was supplied, so no " + ...
        "probed interval was compared against one.";
end
end

function value = policyRecord(options)
value = struct( ...
    factor_set_source="governing contract, not the data", ...
    value_sources="user override, otherwise observed-metric quantile", ...
    quantile_definition= ...
        "linear interpolation between order statistics, with the i-th of n " + ...
        "placed at cumulative probability (i-0.5)/n and probabilities " + ...
        "outside that range clamped to the extreme order statistics", ...
    minimum_supported_observations=options.minimum_supported_observations, ...
    minimum_supported_observations_rationale= ...
        "q(0.95) first stops being a clamp to the observed maximum at n = 10", ...
    degenerate_interval_rule= ...
        "high - low <= tolerance * max(1, max(abs([low high]))), tolerance " + ...
        string(options.degenerate_interval_tolerance), ...
    redundancy_policy= ...
        "recorded beside the factor; never a reason to deactivate it", ...
    optimization="none; no objective function and no selection among values");
end

% -------------------------------------------------------------- plumbing ---

function record = disabledRecord(seed, seedSource, seedBasis, options, ...
    reference, redundancy)
record = struct( ...
    status="disabled", ...
    exploration_enabled=false, ...
    seed=seed, ...
    seed_source=seedSource, ...
    seed_basis=seedBasis, ...
    analysis_budget=emptyToNaN(options.analysis_budget), ...
    analysis_budget_source=sourceOf(options.analysis_budget), ...
    subset_size=emptyToNaN(options.subset_size), ...
    subset_size_source=sourceOf(options.subset_size), ...
    factors=emptyFactors(), ...
    active_factor_count=0, ...
    active_factor_names=strings(1, 0), ...
    inactive_factor_names=strings(1, 0), ...
    design_feasibility=designFeasibility(0), ...
    reference_configuration=reference, ...
    redundancy_findings=redundancy, ...
    inactive_reason_vocabulary=edaInactiveReasons()', ...
    policy=policyRecord(options), ...
    warnings="Exploration is disabled; no factor was resolved.", ...
    interpretation="Exploration is disabled.", ...
    language_note= ...
        "These are probe values spanning a plausible range. None is optimal, " + ...
        "recommended, or calibrated, and no downstream report may describe " + ...
        "one that way.", ...
    caution=edaCautionNote());
end

function value = emptyToNaN(value)
if isempty(value)
    value = NaN;
end
end

function value = sourceOf(supplied)
if isempty(supplied)
    value = "default";
else
    value = "user";
end
end

function value = emptyFactors()
value = table(strings(0, 1), strings(0, 1), false(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    false(0, 1), ...
    VariableNames=["factor_name", "metric_name", "is_active", ...
    "inactive_reason", "low_value", "high_value", "low_quantile", ...
    "high_quantile", "value_source", "supported_observations", ...
    "strictness_direction", "unit", "reference_value", ...
    "reference_comparison", "flagged_redundant"]);
end

function requireFields(surface, names)
missingNames = names(~isfield(surface, names));
if ~isempty(missingNames)
    error("vawlume:eda:SurfaceInvalid", ...
        "The supplied surface is missing required field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
