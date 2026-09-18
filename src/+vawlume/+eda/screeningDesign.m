function design = screeningDesign(resolution, options)
%SCREENINGDESIGN Turn resolved factors and probe values into a bounded design.
%
% DESIGN = vawlume.eda.SCREENINGDESIGN(RESOLUTION) builds an explicit,
% interaction-aware set of configurations from a vawlume.eda.probeParameters
% record: a full two-level factorial when it fits the configuration budget,
% otherwise the largest fitting fraction, with its generators, defining relation,
% resolution and complete alias structure recorded beside it.
%
% Name-value options:
%   WarnAtConfigurations     configuration count at which the design is flagged
%                            as large, default 32
%   MaximumConfigurations    ceiling the design must fit, default 128
%   AllowExceedingMaximum    explicit opt-in past the ceiling, default false
%
% REDUCE THE FRACTION, NEVER THE FACTOR SET. When the budget binds, the response
% is a smaller fraction - accepting more aliasing and disclosing it - not
% dropping a factor. Dropping one silently converts a screen of four dimensions
% into a screen of three and removes a dimension the user asked about; the
% aliasing is at least visible in the output.
%
% The alias structure is the reason this function is not just a Cartesian
% product. A screen that reports a main effect without disclosing what it is
% confounded with is read with more confidence than it has earned, so every main
% effect and every two-factor interaction appears in DESIGN.alias.alias_table
% with what it is aliased with, and the resolution's consequence is stated in
% words a report can quote.
%
% Factor coding is -1 for the low parameter value and +1 for the high one. LOW
% AND HIGH NAME THE PARAMETER VALUE, NEVER THE STRICTNESS: a larger
% min_temporal_iou is stricter while a larger max_abs_ bound is looser, and each
% factor's strictness direction is carried through so effect signs stay
% interpretable downstream.
%
% This function is pure. It opens no database connection and writes no file;
% materializing the configurations as specification files is a separate step, so
% a caller can inspect a design before anything is written.
%
% No configuration here is optimal, recommended, or best. The design exists to
% show how outcomes move across a plausible range.

arguments
    resolution (1,1) struct
    options.WarnAtConfigurations (1,1) double {mustBePositive} = 32
    options.MaximumConfigurations (1,1) double {mustBePositive} = 128
    options.AllowExceedingMaximum (1,1) logical = false
end

requireFields(resolution, ["factors", "status"]);
active = activeFactors(resolution);
k = height(active);
if k < 1
    error("vawlume:eda:NoActiveFactors", ...
        "No factor is active, so there is nothing to screen. The probe " + ...
        "resolution record explains why each was excluded.");
end

selection = selectFraction(k, options);
[coding, letters] = buildCoding(k, selection);
assertBalancedAndOrthogonal(coding, selection);

alias = edaAliasStructure(k, selection.generators);
configurations = configurationTable(active, coding, letters);
assertDistinctIdentifiers(configurations);

design = struct( ...
    status="constructed", ...
    design_type=selection.design_type, ...
    factor_count=k, ...
    fraction_exponent=selection.p, ...
    configuration_count=height(configurations), ...
    full_factorial_size=2^k, ...
    factors=factorMap(active, letters), ...
    coding=coding, ...
    coding_convention="-1 is the low parameter value, +1 is the high one; " + ...
        "low and high name the parameter value, not the strictness", ...
    row_order="Yates order: the first factor alternates fastest, so two " + ...
        "expansions of one design agree row for row", ...
    configurations=configurations, ...
    alias=alias, ...
    generator_source=selection.generator_source, ...
    decision_path=selection.decision_path, ...
    budget=struct( ...
        warn_at_configurations=options.WarnAtConfigurations, ...
        maximum_configurations=options.MaximumConfigurations, ...
        exceeded_maximum_by_opt_in=selection.exceeded, ...
        binds=selection.p > 0), ...
    analysis_cost_rule="configurations x recordings x (N(N-1)/2 matching + " + ...
        "1 agreement) analyses, for N extractors. The dataset is not known " + ...
        "here, so the analysis ceiling is enforced where it is resolved.", ...
    probe_resolution=resolution, ...
    randomization="none; the computation is deterministic, so there is no " + ...
        "experimental noise to randomize against and no blocking is applied", ...
    warnings=warningsFor(selection, alias, options, height(configurations)), ...
    caution=edaCautionNote());
end

% ------------------------------------------------------- fraction choice ---

function selection = selectFraction(k, options)
fullSize = 2^k;
path = strings(0, 1);
path(end + 1, 1) = "Full two-level factorial over " + string(k) + ...
    " active factors is " + string(fullSize) + " configurations.";

if fullSize <= options.MaximumConfigurations
    path(end + 1, 1) = "That fits the ceiling of " + ...
        string(options.MaximumConfigurations) + ", so the full factorial is " + ...
        "used and nothing is confounded.";
    selection = struct(design_type="full_factorial", p=0, ...
        generators=strings(1, 0), generator_source="not applicable", ...
        decision_path=path, exceeded=false);
    return
end

path(end + 1, 1) = "That exceeds the ceiling of " + ...
    string(options.MaximumConfigurations) + ", so the fraction is reduced. " + ...
    "THE FACTOR SET IS NOT REDUCED: dropping a factor would remove a " + ...
    "dimension the caller asked about, while a smaller fraction discloses " + ...
    "its cost as aliasing.";

for p = 1:(k - 1)
    [generators, source] = edaGeneratorCatalog(k, p);
    if isempty(generators)
        path(end + 1, 1) = "No standard maximum-resolution generator set is " + ...
            "tabulated for 2^(" + string(k) + "-" + string(p) + "), so that " + ...
            "fraction is skipped rather than invented."; %#ok<AGROW>
        continue
    end
    size = 2^(k - p);
    if size > options.MaximumConfigurations
        path(end + 1, 1) = "2^(" + string(k) + "-" + string(p) + ") is " + ...
            string(size) + " configurations, still above the ceiling."; %#ok<AGROW>
        continue
    end
    path(end + 1, 1) = "2^(" + string(k) + "-" + string(p) + ") is " + ...
        string(size) + " configurations, which fits. Generators: " + ...
        strjoin(generators, ", ") + "."; %#ok<AGROW>
    selection = struct(design_type="fractional_factorial", p=p, ...
        generators=generators, generator_source=source, ...
        decision_path=path, exceeded=false);
    return
end

if options.AllowExceedingMaximum
    path(end + 1, 1) = "No tabulated fraction fits, and the caller opted in " + ...
        "explicitly, so the full factorial is used above the ceiling.";
    selection = struct(design_type="full_factorial", p=0, ...
        generators=strings(1, 0), generator_source="not applicable", ...
        decision_path=path, exceeded=true);
    return
end

error("vawlume:eda:DesignExceedsBudget", ...
    "A design over %d factors needs %d configurations at its smallest " + ...
    "tabulated fraction, above the ceiling of %d. Raise " + ...
    "MaximumConfigurations, or pass AllowExceedingMaximum. The factor set " + ...
    "is not reduced to fit a budget.", k, 2^k, options.MaximumConfigurations);
end

% ------------------------------------------------------------- the matrix ---

function [coding, letters] = buildCoding(k, selection)
letters = edaFactorLetters(k);
base = k - selection.p;
rows = 2^base;
coding = zeros(rows, k);
for row = 1:rows
    for column = 1:base
        coding(row, column) = 2 * bitget(row - 1, column) - 1;
    end
end
for index = 1:selection.p
    generator = selection.generators(index);
    parts = split(generator, "=");
    added = strtrim(parts(1));
    target = find(letters == added, 1);
    if isempty(target)
        error("vawlume:eda:GeneratorInvalid", ...
            "Generator '%s' defines a factor outside the active set.", generator);
    end
    product = ones(rows, 1);
    for name = edaLettersOf(parts(2))
        source = find(letters == name, 1);
        if isempty(source) || source > base
            error("vawlume:eda:GeneratorInvalid", ...
                "Generator '%s' refers to '%s', which is not a base factor.", ...
                generator, name);
        end
        product = product .* coding(:, source);
    end
    coding(:, target) = product;
end
end

function assertBalancedAndOrthogonal(coding, selection)
%ASSERTBALANCEDANDORTHOGONAL The two properties that make main effects estimable.
%
% Balance means each factor is at its low value in exactly as many runs as its
% high value, so a main effect is not contaminated by an unequal split.
% Orthogonality means no two factor columns carry overlapping information, so
% their effects can be separated. Both are exact integer properties of a correct
% two-level design, so they are asserted exactly rather than to a tolerance: a
% failure is a construction defect, not numerical drift.
if any(sum(coding, 1) ~= 0)
    error("vawlume:eda:DesignNotBalanced", ...
        "A factor column does not sum to zero, so the design is unbalanced " + ...
        "and its main effects are not cleanly estimable.");
end
product = coding' * coding;
offDiagonal = product - diag(diag(product));
if any(offDiagonal(:) ~= 0)
    error("vawlume:eda:DesignNotOrthogonal", ...
        "Two factor columns are not orthogonal, so their effects cannot be " + ...
        "separated. Design type %s.", selection.design_type);
end
end

% -------------------------------------------------------------- the table ---

function value = configurationTable(active, coding, letters)
rows = height(coding);
k = height(active);
configurationId = strings(rows, 1);
identityPayload = strings(rows, 1);
codingText = strings(rows, 1);
parameters = zeros(rows, k);

for row = 1:rows
    values = zeros(1, k);
    for column = 1:k
        if coding(row, column) < 0
            values(column) = active.low_value(column);
        else
            values(column) = active.high_value(column);
        end
    end
    identity = edaConfigurationIdentity(active.factor_name, values);
    configurationId(row) = identity.configuration_id;
    identityPayload(row) = identity.identity_payload;
    codingText(row) = strjoin(letters + codeSign(coding(row, :)), " ");
    parameters(row, :) = values;
end

value = table((1:rows)', configurationId, codingText, identityPayload, ...
    VariableNames=["run_order", "configuration_id", "factor_coding", ...
    "identity_payload"]);
for column = 1:k
    value.(active.factor_name(column)) = parameters(:, column);
end
for column = 1:k
    value.(active.factor_name(column) + "_level") = ...
        levelLabel(coding(:, column));
end
end

function value = codeSign(codes)
value = strings(1, numel(codes));
value(codes < 0) = "-";
value(codes >= 0) = "+";
end

function value = levelLabel(codes)
value = repmat("low", numel(codes), 1);
value(codes >= 0) = "high";
end

function assertDistinctIdentifiers(configurations)
identifiers = configurations.configuration_id;
if numel(unique(identifiers)) == numel(identifiers)
    return
end
[~, first] = unique(identifiers, "stable");
duplicated = unique(identifiers(setdiff(1:numel(identifiers), first)));
error("vawlume:eda:ConfigurationIdCollision", ...
    "Configuration identifier(s) %s appear on more than one design row. " + ...
    "An identifier is what joins a response back to the configuration that " + ...
    "produced it, so a collision is refused rather than resolved by " + ...
    "appending an index.", strjoin(duplicated', ", "));
end

function value = factorMap(active, letters)
value = table(letters(:), active.factor_name, active.metric_name, ...
    active.low_value, active.high_value, active.strictness_direction, ...
    active.unit, active.value_source, ...
    VariableNames=["design_letter", "factor_name", "metric_name", ...
    "low_value", "high_value", "strictness_direction", "unit", ...
    "value_source"]);
end

% -------------------------------------------------------------- plumbing ---

function value = activeFactors(resolution)
factors = resolution.factors;
if height(factors) == 0
    value = factors;
    return
end
value = factors(factors.is_active, :);
end

function value = warningsFor(selection, alias, options, count)
value = strings(0, 1);
if selection.exceeded
    value(end + 1, 1) = "The design exceeds the configuration ceiling of " + ...
        string(options.MaximumConfigurations) + " by explicit opt-in.";
end
if count >= options.WarnAtConfigurations
    value(end + 1, 1) = string(count) + " configurations is at or above the " + ...
        "warning threshold of " + string(options.WarnAtConfigurations) + ...
        ". Every configuration multiplies into one matching analysis per " + ...
        "extractor pair per recording plus one agreement analysis.";
end
if selection.p > 0
    value(end + 1, 1) = alias.note;
    if ~alias.two_factor_interactions_uniquely_attributable
        value(end + 1, 1) = "Two-factor interaction estimates from this " + ...
            "design are aliased sums, not individual interactions. A " + ...
            "concordance report must treat them as interaction SUSPECTED " + ...
            "rather than interaction measured.";
    end
end
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:ResolutionRecordInvalid", ...
        "The probe resolution record is missing required field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
