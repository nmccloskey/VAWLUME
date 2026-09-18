function options = explorationOptions(supplied)
%EXPLORATIONOPTIONS Validate the exploration workflow's light configuration surface.
%
% OPTIONS = vawlume.eda.EXPLORATIONOPTIONS() returns the defaults.
% OPTIONS = vawlume.eda.EXPLORATIONOPTIONS(SUPPLIED) validates a scalar struct of
% user settings against them and returns the completed configuration.
%
% A normal invocation of the exploratory workflow supplies little more than
% "exploration on", a seed, and optionally a budget. Everything else is resolved
% deterministically and reported, so the surface stays small on purpose.
%
%   enabled                         run the exploration at all. Default true.
%   seed                            random seed. Default [], meaning resolve one
%                                   deterministically from dataset identity and
%                                   record it.
%   analysis_budget                 optional ceiling override, carried to the
%                                   design and execution layers. Default [].
%   subset_size                     optional recording count for the richer
%                                   probe, carried through. Default [].
%   threshold_ranges                per-factor [low high] overrides, as a struct
%                                   keyed by the matching specification's own
%                                   field names. Default struct().
%   disabled_factors                factor names to exclude from the screen.
%                                   Default strings(0,1).
%   minimum_supported_observations  below this many supported observations a
%                                   factor's metric cannot place a quantile and
%                                   the factor is reported inactive. Default 10.
%   degenerate_interval_tolerance   relative width at or below which a probed
%                                   interval counts as degenerate. Default 1e-9.
%
% A STRUCT, not a long positional signature, because this is what a JSON
% configuration decodes to and because a growing signature is where optional
% arguments go to be passed in the wrong order.
%
% AN UNKNOWN FIELD IS REJECTED, NEVER IGNORED. A misspelled override that is
% silently dropped produces a run that looks configured and is not, and nothing
% downstream can detect the difference: the record would faithfully report the
% default that was actually used, and the reader would believe it was their
% value. Rejecting costs one error message and removes a whole class of silent
% wrong answers.
%
% The default for minimum_supported_observations is 10 for a concrete reason
% rather than as a round number. Under the workflow's quantile definition the
% i-th of n order statistics sits at (i-0.5)/n, so q(0.95) first stops being a
% clamp to the observed maximum at n = 10. Below that, the "high" probe value is
% the largest observation whatever the requested quantile, and calling it a
% quantile would overstate what the data supports.

arguments
    supplied (1,1) struct = struct()
end

options = defaults();
known = string(fieldnames(options));
givenNames = string(fieldnames(supplied));

unknown = givenNames(~ismember(givenNames, known));
if ~isempty(unknown)
    error("vawlume:eda:UnknownOption", ...
        "Unknown exploration option(s): %s. Known options are: %s.", ...
        strjoin(unknown, ", "), strjoin(sort(known)', ", "));
end

for name = givenNames'
    options.(name) = supplied.(name);
end

options.enabled = validateLogical(options.enabled, "enabled");
options.seed = validateOptionalSeed(options.seed);
options.analysis_budget = validateOptionalCount(options.analysis_budget, ...
    "analysis_budget");
options.subset_size = validateOptionalCount(options.subset_size, "subset_size");
options.disabled_factors = validateFactorNames(options.disabled_factors);
options.threshold_ranges = validateThresholdRanges(options.threshold_ranges);
options.minimum_supported_observations = validatePositive( ...
    options.minimum_supported_observations, "minimum_supported_observations");
options.degenerate_interval_tolerance = validateNonNegative( ...
    options.degenerate_interval_tolerance, "degenerate_interval_tolerance");
end

function value = defaults()
value = struct( ...
    enabled=true, ...
    seed=[], ...
    analysis_budget=[], ...
    subset_size=[], ...
    threshold_ranges=struct(), ...
    disabled_factors=strings(0, 1), ...
    minimum_supported_observations=10, ...
    degenerate_interval_tolerance=1e-9);
end

function value = validateLogical(value, name)
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value)
    error("vawlume:eda:OptionInvalid", "%s must be a logical scalar.", name);
end
value = logical(value);
end

function value = validateOptionalSeed(value)
if isempty(value)
    value = [];
    return
end
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        value < 0 || fix(value) ~= value
    error("vawlume:eda:OptionInvalid", ...
        "seed must be empty or a nonnegative integer.");
end
value = double(value);
end

function value = validateOptionalCount(value, name)
if isempty(value)
    value = [];
    return
end
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        value < 1 || fix(value) ~= value
    error("vawlume:eda:OptionInvalid", ...
        "%s must be empty or a positive integer.", name);
end
value = double(value);
end

function value = validatePositive(value, name)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value < 1
    error("vawlume:eda:OptionInvalid", ...
        "%s must be a finite scalar of at least 1.", name);
end
value = double(value);
end

function value = validateNonNegative(value, name)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value < 0
    error("vawlume:eda:OptionInvalid", ...
        "%s must be a finite nonnegative scalar.", name);
end
value = double(value);
end

function value = validateFactorNames(value)
if isempty(value)
    value = strings(0, 1);
    return
end
try
    value = string(value);
catch
    error("vawlume:eda:OptionInvalid", ...
        "disabled_factors must be text naming contract factors.");
end
value = value(:);
known = edaFactorPolicy().factor_name;
unknown = value(~ismember(value, known));
if ~isempty(unknown)
    error("vawlume:eda:UnknownFactor", ...
        "disabled_factors names unknown factor(s): %s. The screened factor " + ...
        "set is fixed by the governing contract: %s.", ...
        strjoin(unknown', ", "), strjoin(known', ", "));
end
end

function value = validateThresholdRanges(value)
if ~isstruct(value) || ~isscalar(value)
    error("vawlume:eda:OptionInvalid", ...
        "threshold_ranges must be a scalar struct keyed by factor name.");
end
known = edaFactorPolicy();
names = string(fieldnames(value));
unknown = names(~ismember(names, known.factor_name));
if ~isempty(unknown)
    error("vawlume:eda:UnknownFactor", ...
        "threshold_ranges names unknown factor(s): %s. The screened factor " + ...
        "set is fixed by the governing contract: %s.", ...
        strjoin(unknown', ", "), strjoin(known.factor_name', ", "));
end
for name = names'
    range = value.(name);
    if ~isnumeric(range) || numel(range) ~= 2 || any(~isfinite(range))
        error("vawlume:eda:ThresholdRangeInvalid", ...
            "threshold_ranges.%s must be a finite two-element [low high].", ...
            name);
    end
    range = double(range(:))';
    if range(1) > range(2)
        error("vawlume:eda:ThresholdRangeInvalid", ...
            "threshold_ranges.%s must be ordered [low high]; %g > %g. Low " + ...
            "and high name the parameter value, not the strictness, and " + ...
            "reordering silently would invert the design's factor coding.", ...
            name, range(1), range(2));
    end
    selected = known(known.factor_name == name, :);
    if range(1) < selected.minimum_value || range(2) > selected.maximum_value
        error("vawlume:eda:ThresholdRangeInvalid", ...
            "threshold_ranges.%s must lie within [%g, %g] for this factor.", ...
            name, selected.minimum_value, selected.maximum_value);
    end
    value.(name) = range;
end
end
