function tests = test_eda_screening_design
%TEST_EDA_SCREENING_DESIGN Design construction, alias structure, and materialization.
%
% No database, no audio, no figures. Every property that makes a screening design
% trustworthy is an exact integer or textual fact about a small matrix, so the
% assertions are exact rather than approximate: a failure here is a construction
% defect, never numerical drift.
%
% The alias tests carry the most weight. A screen that reports a main effect
% without disclosing what it is confounded with is worse than no screen, because
% it is read with more confidence than it has earned, and the alias table is the
% only place that disclosure lives.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repoRoot, "src");
testCase.TestData.repo_root = repoRoot;
testCase.TestData.source_path = sourcePath;
testCase.TestData.added_path = ~contains(path, sourcePath);
if testCase.TestData.added_path
    addpath(sourcePath);
end
testCase.TestData.scratch = string(tempname);
mkdir(testCase.TestData.scratch);
end

function teardownOnce(testCase)
if isfolder(testCase.TestData.scratch)
    rmdir(testCase.TestData.scratch, "s");
end
if testCase.TestData.added_path && contains(path, testCase.TestData.source_path)
    rmpath(testCase.TestData.source_path);
end
end

% ------------------------------------------------------- design selection ---

function testAFullFactorialIsUsedWhenItFitsTheBudget(testCase)
design = vawlume.eda.screeningDesign(recordWith(3));
verifyEqual(testCase, design.design_type, "full_factorial");
verifyEqual(testCase, design.fraction_exponent, 0);
verifyEqual(testCase, design.configuration_count, 8);
verifyEqual(testCase, design.full_factorial_size, 8);
verifyEmpty(testCase, design.alias.generators);
verifyEqual(testCase, design.alias.defining_relation, "I");
verifyEqual(testCase, design.alias.resolution_label, "full");
verifyTrue(testCase, all(design.alias.alias_table.is_uniquely_attributable));
verifyTrue(testCase, all(design.alias.alias_table.aliased_with == ""));
verifyTrue(testCase, contains(design.alias.note, "nothing is confounded"));
end

function testFourFactorsUnderTheContractBudgetGiveAFullFactorial(testCase)
% The contract's ceiling is 128 configurations, and 2^4 is 16, so the default
% path for the pilot factor set is the full factorial rather than a fraction.
design = vawlume.eda.screeningDesign(recordWith(4));
verifyEqual(testCase, design.design_type, "full_factorial");
verifyEqual(testCase, design.configuration_count, 16);
verifyEqual(testCase, design.budget.maximum_configurations, 128);
verifyFalse(testCase, design.budget.binds);
verifyTrue(testCase, ...
    design.alias.two_factor_interactions_uniquely_attributable);
end

function testABindingBudgetReducesTheFractionAndNotTheFactorSet(testCase)
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
verifyEqual(testCase, design.design_type, "fractional_factorial");
verifyEqual(testCase, design.fraction_exponent, 1);
verifyEqual(testCase, design.configuration_count, 8);

% The factor set is untouched: all four factors still appear.
verifyEqual(testCase, design.factor_count, 4);
verifyEqual(testCase, height(design.factors), 4);
verifyEqual(testCase, design.factors.design_letter', ["A", "B", "C", "D"]);
verifyTrue(testCase, any(contains(design.decision_path, ...
    "THE FACTOR SET IS NOT REDUCED")));
end

function testADesignThatCannotFitAnyTabulatedFractionIsRefused(testCase)
verifyError(testCase, @() vawlume.eda.screeningDesign(recordWith(4), ...
    MaximumConfigurations=2), "vawlume:eda:DesignExceedsBudget");
% The opt-in exists, and taking it is recorded rather than silent.
design = vawlume.eda.screeningDesign(recordWith(4), ...
    MaximumConfigurations=2, AllowExceedingMaximum=true);
verifyTrue(testCase, design.budget.exceeded_maximum_by_opt_in);
verifyTrue(testCase, any(contains(design.warnings, "explicit opt-in")));
end

function testNoActiveFactorIsRefusedRatherThanProducingAnEmptyDesign(testCase)
record = recordWith(4);
record.factors.is_active(:) = false;
verifyError(testCase, @() vawlume.eda.screeningDesign(record), ...
    "vawlume:eda:NoActiveFactors");
end

% ------------------------------------------------------------- the matrix ---

function testTheDesignMatrixIsBalancedAndOrthogonal(testCase)
% Balance means each factor sits at its low value in exactly as many runs as its
% high value. Orthogonality means no two factor columns share information. Both
% are what make main effects estimable, and both are exact.
for maximum = [128, 8]
    design = vawlume.eda.screeningDesign(recordWith(4), ...
        MaximumConfigurations=maximum);
    coding = design.coding;
    verifyEqual(testCase, sum(coding, 1), zeros(1, 4), ...
        "unbalanced at budget " + string(maximum));
    product = coding' * coding;
    verifyEqual(testCase, product, design.configuration_count * eye(4), ...
        "not orthogonal at budget " + string(maximum));
    verifyTrue(testCase, all(ismember(coding(:), [-1, 1])));
end
end

function testTheGeneratorHoldsInTheConstructedMatrix(testCase)
% D is defined as ABC, so its column must equal the element-wise product of the
% A, B and C columns exactly.
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
coding = design.coding;
verifyEqual(testCase, coding(:, 4), coding(:, 1) .* coding(:, 2) .* coding(:, 3));
verifyEqual(testCase, design.alias.generators, "D=ABC");
end

function testRowOrderIsDeterministicYatesOrder(testCase)
design = vawlume.eda.screeningDesign(recordWith(3));
% First factor alternates fastest, starting all-low.
verifyEqual(testCase, design.coding(:, 1)', [-1 1 -1 1 -1 1 -1 1]);
verifyEqual(testCase, design.coding(:, 2)', [-1 -1 1 1 -1 -1 1 1]);
verifyEqual(testCase, design.coding(:, 3)', [-1 -1 -1 -1 1 1 1 1]);
verifyEqual(testCase, design.configurations.run_order', 1:8);
end

% ------------------------------------------------------- alias structure ---

function testTheStandardFourFactorHalfFractionHasItsKnownAliasStructure(testCase)
% 2^(4-1) with D = ABC: defining relation I = ABCD, resolution IV. Main effects
% are aliased with three-factor interactions and two-factor interactions are
% aliased in pairs. These are published values, not values this code chose.
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
alias = design.alias;

verifyEqual(testCase, alias.defining_relation, "I = ABCD");
verifyEqual(testCase, alias.resolution, 4);
verifyEqual(testCase, alias.resolution_label, "IV");

verifyEqual(testCase, aliasOf(alias, "A"), "BCD");
verifyEqual(testCase, aliasOf(alias, "B"), "ACD");
verifyEqual(testCase, aliasOf(alias, "C"), "ABD");
verifyEqual(testCase, aliasOf(alias, "D"), "ABC");
verifyEqual(testCase, aliasOf(alias, "AB"), "CD");
verifyEqual(testCase, aliasOf(alias, "AC"), "BD");
verifyEqual(testCase, aliasOf(alias, "AD"), "BC");

verifyTrue(testCase, alias.main_effects_clear_of_two_factor_interactions);
verifyFalse(testCase, alias.two_factor_interactions_uniquely_attributable);
end

function testTheAliasTableCoversEveryMainEffectAndTwoFactorInteraction(testCase)
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
table = design.alias.alias_table;
verifyEqual(testCase, nnz(table.effect_order == 1), 4);
verifyEqual(testCase, nnz(table.effect_order == 2), 6);
verifyEqual(testCase, height(table), 10);
verifyEqual(testCase, sort(table.effect(table.effect_order == 1)), ...
    ["A"; "B"; "C"; "D"]);
verifyEqual(testCase, sort(table.effect(table.effect_order == 2)), ...
    ["AB"; "AC"; "AD"; "BC"; "BD"; "CD"]);
end

function testTheResolutionConsequenceIsStatedForAProgrammaticReader(testCase)
% A concordance report reads this to decide whether an interaction estimate is
% attributable or only suspected, so it must be a field rather than prose alone.
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
verifyFalse(testCase, ...
    design.alias.two_factor_interactions_uniquely_attributable);
verifyTrue(testCase, contains(design.alias.note, "ALIASED IN PAIRS"));
verifyTrue(testCase, any(contains(design.warnings, "interaction SUSPECTED")));

full = vawlume.eda.screeningDesign(recordWith(4));
verifyTrue(testCase, full.alias.two_factor_interactions_uniquely_attributable);
end

function testAResolutionThreeDesignSaysMainEffectsAreAliased(testCase)
% 2^(5-2) with D=AB, E=AC is resolution III: a main effect cannot be attributed
% to its factor alone, and the output has to say so in capital letters.
design = vawlume.eda.screeningDesign(recordWith(5), MaximumConfigurations=8);
verifyEqual(testCase, design.configuration_count, 8);
verifyEqual(testCase, design.alias.resolution, 3);
verifyEqual(testCase, design.alias.resolution_label, "III");
verifyTrue(testCase, contains(design.alias.note, ...
    "MAIN EFFECTS ARE ALIASED WITH TWO-FACTOR INTERACTIONS"));
verifyFalse(testCase, ...
    design.alias.main_effects_clear_of_two_factor_interactions);
end

% ------------------------------------------------- configuration identity ---

function testConfigurationIdentifiersAreDistinctAndDeterministic(testCase)
first = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
second = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);

identifiers = first.configurations.configuration_id;
verifyEqual(testCase, numel(unique(identifiers)), numel(identifiers));
verifyEqual(testCase, identifiers, second.configurations.configuration_id);
verifyEqual(testCase, first.coding, second.coding);
verifyTrue(testCase, all(startsWith(identifiers, "cfg-")));
verifyTrue(testCase, all(strlength(identifiers) == 14));
end

function testTheConfigurationTableCarriesFullParameterValuesBesideTheId(testCase)
% The identifier is a handle for joining responses; it is never the record of
% what was run.
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
configurations = design.configurations;
names = design.factors.factor_name;
for index = 1:numel(names)
    verifyTrue(testCase, ismember(names(index), ...
        string(configurations.Properties.VariableNames)), names(index));
    verifyTrue(testCase, ismember(names(index) + "_level", ...
        string(configurations.Properties.VariableNames)));
end

% Every value equals its factor's low or high, matching the coding.
for row = 1:height(configurations)
    for column = 1:numel(names)
        expected = design.factors.low_value(column);
        if design.coding(row, column) > 0
            expected = design.factors.high_value(column);
        end
        verifyEqual(testCase, configurations.(names(column))(row), expected, ...
            AbsTol=1e-12);
    end
end
end

function testIdentifiersFollowFromTheValuesNotTheRowPosition(testCase)
% Two designs whose factor values differ must produce different identifiers,
% and a design whose values match must reproduce them.
base = recordWith(4);
shifted = base;
shifted.factors.high_value(1) = shifted.factors.high_value(1) + 0.01;

original = vawlume.eda.screeningDesign(base, MaximumConfigurations=8);
moved = vawlume.eda.screeningDesign(shifted, MaximumConfigurations=8);
verifyNotEqual(testCase, sort(original.configurations.configuration_id), ...
    sort(moved.configurations.configuration_id));

% The all-low row is unaffected by a change to a high value, so its identity is
% stable across the two designs.
verifyEqual(testCase, original.configurations.configuration_id(1), ...
    moved.configurations.configuration_id(1));
end

% ------------------------------------------------------- materialization ---

function testEveryConfigurationBecomesAFileWithADistinctChecksum(testCase)
[design, materialized] = materializeFixture(testCase, 8);
verifyEqual(testCase, materialized.status, "materialized");
verifyEqual(testCase, height(materialized.index), 8);
verifyEqual(testCase, numel(unique(materialized.index.checksum_sha256)), 8);
for index = 1:height(materialized.index)
    verifyTrue(testCase, isfile(materialized.index.specification_path(index)));
end
verifyEqual(testCase, materialized.configuration_count, ...
    design.configuration_count);
verifyTrue(testCase, all(contains(materialized.index.specification_path, ...
    materialized.exploration_run_key)));
end

function testRewritingAConfigurationProducesIdenticalBytes(testCase)
% The specification checksum is the analysis identity, so serialization drift
% would make an honest rerun look like a conflict.
[~, first] = materializeFixture(testCase, 8);
[~, second] = materializeFixture(testCase, 8);
verifyEqual(testCase, second.index.checksum_sha256, first.index.checksum_sha256);
verifyEqual(testCase, second.exploration_run_key, first.exploration_run_key);
end

function testOnlyTheActiveFactorsDifferFromTheBaseSpecification(testCase)
% Everything else - algorithm, assignment model, consensus policy, feature
% eligibility, manual-QC rule - is copied unchanged. That is what makes a
% response attributable to the design.
[~, materialized] = materializeFixture(testCase, 8);
base = jsondecode(fileread(materialized.base_specification.path));
generated = jsondecode(fileread(materialized.index.specification_path(1)));

verifyEqual(testCase, rmfield(base, ["candidate_generation", "profile"]), ...
    rmfield(generated, ["candidate_generation", "profile"]));
verifyEqual(testCase, rmfield(base.candidate_generation, "plausibility_rule"), ...
    rmfield(generated.candidate_generation, "plausibility_rule"));
verifyEqual(testCase, rmfield(base.profile, "profile_version"), ...
    rmfield(generated.profile, "profile_version"));

% Fields of the plausibility rule that are not screened factors survive too.
verifyEqual(testCase, ...
    generated.candidate_generation.plausibility_rule.require_positive_overlap, ...
    base.candidate_generation.plausibility_rule.require_positive_overlap);
end

function testTheGeneratedValuesEqualTheConfigurationRow(testCase)
[design, materialized] = materializeFixture(testCase, 8);
names = design.factors.factor_name;
for row = 1:height(materialized.index)
    generated = jsondecode(fileread( ...
        materialized.index.specification_path(row)));
    rule = generated.candidate_generation.plausibility_rule;
    for column = 1:numel(names)
        % Exact equality, not a tolerance: the written value must be the same
        % double the configuration table holds, or the checksum identifies a
        % configuration that was not run.
        verifyEqual(testCase, rule.(names(column)), ...
            materialized.index.(names(column))(row), ...
            names(column) + " row " + string(row));
    end
end
end

function testTheProfileVersionEncodesTheConfigurationIdentifier(testCase)
[~, materialized] = materializeFixture(testCase, 8);
expected = materialized.base_specification.profile_version + "+exp." + ...
    materialized.index.configuration_id;
verifyEqual(testCase, materialized.index.profile_version, expected);
end

function testGeneratedFilesLandUnderTheRuntimeRootNotTrackedConfiguration(testCase)
[~, materialized] = materializeFixture(testCase, 8);
verifyTrue(testCase, contains(materialized.specification_directory, ...
    "exploration"));
verifyFalse(testCase, any(contains(materialized.index.specification_path, ...
    fullfile("config", "05_matching_profiles"))));
end

function testTheRunKeyTemplateAndProvenanceAreCarried(testCase)
[design, materialized] = materializeFixture(testCase, 8);
template = materialized.run_key_template;
verifyTrue(testCase, startsWith(template.matching, ...
    materialized.exploration_run_key));
verifyTrue(testCase, contains(template.matching, ...
    "<configuration_id>/m/r<recording_id>/<key_a>-<key_b>"));
verifyTrue(testCase, contains(template.agreement, ...
    "<configuration_id>/a/r<recording_id>"));
verifyEqual(testCase, template.pair_ordering, ...
    "ascending extractor_key; run_a is the lower key");

provenance = materialized.provenance;
verifyEqual(testCase, provenance.defining_relation, ...
    design.alias.defining_relation);
verifyEqual(testCase, provenance.resolution_label, "IV");
verifyEqual(testCase, height(provenance.alias_table), 10);
verifyTrue(testCase, strlength(provenance.base_specification.checksum_sha256) == 64);
verifyEqual(testCase, provenance.base_specification.calibration_state, ...
    "illustrative_prototype");
end

function testAMalformedBaseSpecificationIsRefusedHereNotMidProbe(testCase)
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
path = fullfile(testCase.TestData.scratch, "broken.json");
writeText(path, jsonencode(struct(profile=struct(profile_version="1"))));
verifyError(testCase, @() vawlume.eda.materializeConfigurations(design, ...
    BaseSpecPath=path, OutputRoot=testCase.TestData.scratch), ...
    "vawlume:eda:BaseSpecificationInvalid");

writeText(path, "{not json");
verifyError(testCase, @() vawlume.eda.materializeConfigurations(design, ...
    BaseSpecPath=path, OutputRoot=testCase.TestData.scratch), ...
    "vawlume:eda:BaseSpecificationInvalid");
end

function testAnInvalidExplorationRunKeyIsRefused(testCase)
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
verifyError(testCase, @() vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=testCase.TestData.repo_root, ...
    OutputRoot=testCase.TestData.scratch, ...
    ExplorationRunKey="has/slash"), "vawlume:eda:ExplorationRunKeyInvalid");
end

% ------------------------------------------------------------- contract ---

function testNoToolboxFunctionIsCalledInTheConstruction(testCase)
root = testCase.TestData.repo_root;
files = [dir(fullfile(root, "src", "+vawlume", "+eda", "*.m"));
    dir(fullfile(root, "src", "+vawlume", "+eda", "private", "*.m"))];
forbidden = ["fracfact", "ff2n", "fullfact", "hadamard", "corr", ...
    "partialcorr", "quantile", "prctile", "iqr"];
for index = 1:numel(files)
    text = string(fileread(fullfile(files(index).folder, files(index).name)));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for name = forbidden
        verifyFalse(testCase, ...
            ~isempty(regexp(body, "(?<![\w.])" + name + "\s*\(", "once")), ...
            files(index).name + " calls " + name);
    end
end
end

function testNeitherDesignNorMaterializationOpensADatabase(testCase)
root = testCase.TestData.repo_root;
for name = ["screeningDesign.m", "materializeConfigurations.m"]
    text = string(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    body = regexprep(text, "^\s*%.*$", "", "lineanchors");
    for forbidden = ["fetch(", "execute(", "sqlwrite(", "sqlite(", ...
            "vawlume.matching.compare"]
        verifyFalse(testCase, contains(body, forbidden), ...
            name + " contains " + forbidden);
    end
end
end

function testNoRandomizationOrBlockingIsApplied(testCase)
design = vawlume.eda.screeningDesign(recordWith(4), MaximumConfigurations=8);
verifyTrue(testCase, contains(design.randomization, "none"));
verifyFalse(testCase, ismember("block", ...
    string(design.configurations.Properties.VariableNames)));
end

% ---------------------------------------------------------------- helpers ---

function [design, materialized] = materializeFixture(testCase, maximum)
design = vawlume.eda.screeningDesign(recordWith(4), ...
    MaximumConfigurations=maximum);
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=testCase.TestData.repo_root, ...
    OutputRoot=testCase.TestData.scratch);
end

function record = recordWith(k)
%RECORDWITH A minimal probe-resolution record carrying k active factors.
%
% Built by hand rather than derived from a surface: the design layer consumes the
% record's shape, and constructing it directly is what keeps these tests unit
% tests.
policy = [ ...
    "min_temporal_iou", "temporal_iou", "larger_is_stricter", "ratio"
    "max_abs_onset_difference_s", "abs_onset_difference_s", "smaller_is_stricter", "seconds"
    "max_abs_offset_difference_s", "abs_offset_difference_s", "smaller_is_stricter", "seconds"
    "max_abs_duration_difference_s", "abs_duration_difference_s", "smaller_is_stricter", "seconds"
    "extra_factor_e", "metric_e", "smaller_is_stricter", "seconds"];
lows = [0.10; 0.002; 0.003; 0.004; 0.005];
highs = [0.50; 0.020; 0.030; 0.040; 0.050];
factors = table(policy(1:k, 1), policy(1:k, 2), true(k, 1), repmat("", k, 1), ...
    lows(1:k), highs(1:k), policy(1:k, 3), policy(1:k, 4), ...
    repmat("observed_quantile", k, 1), ...
    VariableNames=["factor_name", "metric_name", "is_active", ...
    "inactive_reason", "low_value", "high_value", "strictness_direction", ...
    "unit", "value_source"]);
record = struct(status="resolved", factors=factors, seed=42);
end

function value = aliasOf(alias, effect)
value = alias.alias_table.aliased_with(alias.alias_table.effect == effect);
end

function writeText(path, text)
fileId = fopen(path, "wb");
assert(fileId >= 0);
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, unicode2native(string(text), "UTF-8"), "uint8");
delete(cleaner);
end
