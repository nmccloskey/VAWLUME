function tests = test_eda_support_pattern_rules
%TEST_EDA_SUPPORT_PATTERN_RULES The profiler's joins, vocabulary and coverage rules.
%
% Unit tier for the parts that are arithmetic or enumeration over a constructed
% profile: the pattern vocabulary, the cross-pattern guard, coverage, and the
% reference-configuration record. The registry joins and the real feature
% distributions need a database and live in test_eda_support_pattern_profile.
tests = functiontests({ ...
    @setupOnce, ...
    @teardownOnce, ...
    @testTheVocabularyEnumeratesEverySubsetForThreeExtractors, ...
    @testTheVocabularyIsArbitraryNRatherThanAListOfThree, ...
    @testTheReferenceConfigurationCarriesItsIdentityAndCalibrationState, ...
    @testAnUndeclaredCalibrationStatusIsUnknownNotCalibrated, ...
    @testTheReferenceResolverCannotBeHandedAProbeResult, ...
    @testTheReferenceDesignOverridesNoParameter, ...
    @testACrossPatternRequestIsRefusedForAnExtractorRestrictedFeature, ...
    @testDurationAndCentreFrequencyArePermittedAcrossAllPatterns, ...
    @testAnUnregisteredFeatureIsRefusedRatherThanReturnedEmpty, ...
    @testTheCrossPatternListingNamesBothHalvesOfTheRule, ...
    @testLowCoverageIsAnnotatedOnTheCrossPatternResult, ...
    @testNoRankingOrConfidenceWeightAppearsInAnyReturnedFieldName});
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
end

function teardownOnce(testCase)
if testCase.TestData.added_path && contains(path, testCase.TestData.source_path)
    rmpath(testCase.TestData.source_path);
end
end

% ------------------------------------------------------------ vocabulary ---

function testTheVocabularyEnumeratesEverySubsetForThreeExtractors(testCase)
%TESTTHEVOCABULARYENUMERATES... Conceptual spec §2.3's seven categories.
profile = constructedProfile();
vocabulary = profile.pattern_vocabulary;

verifyEqual(testCase, height(vocabulary), 7);
verifyEqual(testCase, sort(vocabulary.extractor_set_key), sort([ ...
    "deepsqueak"; "mupet"; "usvseg"; ...
    "deepsqueak|mupet"; "deepsqueak|usvseg"; "mupet|usvseg"; ...
    "deepsqueak|mupet|usvseg"]));

% The three singletons stay distinct. Keying on the supported PAIR pattern
% would merge them: a singleton's pair pattern is "(none)" whichever extractor
% produced it, which is exactly the collapse §2.3 forbids.
singletons = vocabulary.extractor_set_key(vocabulary.is_extractor_unique);
verifyEqual(testCase, numel(singletons), 3);
verifyEqual(testCase, numel(unique(singletons)), 3);

verifyEqual(testCase, nnz(vocabulary.is_complete_support), 1);
verifyEqual(testCase, vocabulary.extractor_set_key( ...
    vocabulary.is_complete_support), "deepsqueak|mupet|usvseg");
end

function testTheVocabularyIsArbitraryNRatherThanAListOfThree(testCase)
%TESTTHEVOCABULARYISARBITRARYN... Two extractors give three patterns.
two = constructedProfile(Extractors=["alpha", "beta"]);
verifyEqual(testCase, height(two.pattern_vocabulary), 3);
verifyEqual(testCase, sort(two.pattern_vocabulary.extractor_set_key), ...
    sort(["alpha"; "beta"; "alpha|beta"]));

four = constructedProfile(Extractors=["a", "b", "c", "d"]);
verifyEqual(testCase, height(four.pattern_vocabulary), 15);
verifyEqual(testCase, nnz(four.pattern_vocabulary.extractor_count == 1), 4);
verifyEqual(testCase, nnz(four.pattern_vocabulary.extractor_count == 2), 6);
verifyEqual(testCase, nnz(four.pattern_vocabulary.is_complete_support), 1);
end

% ------------------------------------------ the reference configuration ---

function testTheReferenceConfigurationCarriesItsIdentityAndCalibrationState(testCase)
reference = vawlume.eda.referenceConfiguration(RepoRoot=repoRootPath());

verifyEqual(testCase, reference.source, "tracked_default");
verifyEqual(testCase, reference.profile_key, "vawlume.matching.prototype.v1");
verifyEqual(testCase, reference.version_label, "0.1.0");
verifyEqual(testCase, strlength(reference.checksum_sha256), 64);

% Using a file as the reference does not make it calibrated, and the record
% says so in the specification's own words rather than a paraphrase.
verifyEqual(testCase, reference.calibration_status.state, ...
    "illustrative_prototype");
verifyTrue(testCase, reference.calibration_status.is_declared);
verifySubstring(testCase, reference.calibration_status.meaning, ...
    "None is empirically calibrated");
verifySubstring(testCase, reference.calibration_note, ...
    "does not calibrate it");
verifySubstring(testCase, reference.identity_line, "illustrative_prototype");
end

function testAnUndeclaredCalibrationStatusIsUnknownNotCalibrated(testCase)
%TESTANUNDECLAREDCALIBRATIONSTATUS... Silence is not a claim of calibration.
scratch = string(tempname);
mkdir(scratch);
cleanup = onCleanup(@() rmdir(scratch, "s"));
path = fullfile(scratch, "bare.json");
writeJson(path, struct(profile=struct(id="bare.spec", profile_version="9.9")));

reference = vawlume.eda.referenceConfiguration(SpecPath=path);
verifyEqual(testCase, reference.source, "caller_supplied");
verifyEqual(testCase, reference.calibration_status.state, "unknown");
verifyFalse(testCase, reference.calibration_status.is_declared);
verifySubstring(testCase, reference.calibration_status.meaning, ...
    "Absence of a statement is not evidence of calibration");

% A specification that cannot name itself cannot be cited as what an output
% was computed at, so it is refused rather than reported with a blank.
writeJson(fullfile(scratch, "anonymous.json"), ...
    struct(profile=struct(name="no id here")));
verifyError(testCase, @() vawlume.eda.referenceConfiguration( ...
    SpecPath=fullfile(scratch, "anonymous.json")), ...
    "vawlume:eda:ReferenceConfigurationInvalid");
verifyError(testCase, @() vawlume.eda.referenceConfiguration( ...
    SpecPath=fullfile(scratch, "absent.json")), ...
    "vawlume:eda:ReferenceConfigurationNotFound");
end

function testTheReferenceResolverCannotBeHandedAProbeResult(testCase)
%TESTTHEREFERENCERESOLVERCANNOTBEHANDED... Circularity made unreachable.
%
% Development plan §3.8 forbids choosing the reference configuration from the
% screen's results, because picking the configuration that maximizes three-way
% support and then describing three-way support would be circular. The way to
% obey a rule like that is to give the resolver no access to the quantity it
% would have to optimize: its entire input surface is a path.
names = string(fieldnames(struct( ...
    vawlume.eda.referenceConfiguration(RepoRoot=repoRootPath()))));
forbidden = ["design", "responses", "effects", "leverage", "concordance", ...
    "screen", "probe", "configuration_id", "support_pattern"];
for name = names'
    verifyFalse(testCase, any(contains(name, forbidden)), ...
        "The reference record exposes a probe-derived field: " + name);
end

% And the only options it accepts are a path and a root.
verifyError(testCase, @() vawlume.eda.referenceConfiguration( ...
    Design=struct()), "MATLAB:TooManyInputs", ...
    "The resolver accepted a design, which is the input that would make " + ...
    "choosing the reference from the screen possible.");
end

function testTheReferenceDesignOverridesNoParameter(testCase)
reference = vawlume.eda.referenceConfiguration(RepoRoot=repoRootPath());
design = vawlume.eda.referenceDesign(reference);

verifyEqual(testCase, design.design_type, "reference_configuration");
verifyEqual(testCase, design.configuration_count, 1);
verifyEqual(testCase, design.factor_count, 0);
verifyEqual(testCase, height(design.factors), 0, ...
    "The reference design names a factor, so it would override a parameter.");
verifyEqual(testCase, design.probe_role, "reference");

% The id is derived from the reference checksum, so the same file always
% resolves to the same configuration and the runner reuses rather than
% duplicates; a different file cannot be confused with it.
verifyTrue(testCase, startsWith( ...
    design.configurations.configuration_id(1), "ref-"));
again = vawlume.eda.referenceDesign(reference);
verifyEqual(testCase, again.configurations.configuration_id, ...
    design.configurations.configuration_id);

other = reference;
other.checksum_sha256 = repmat('a', 1, 64);
verifyNotEqual(testCase, ...
    vawlume.eda.referenceDesign(other).configurations.configuration_id, ...
    design.configurations.configuration_id);

% A single configuration contrasts nothing, so nothing is estimable from it.
verifyEqual(testCase, height(design.alias.alias_table), 0);
verifySubstring(testCase, design.alias.note, "contrasts");
end

% --------------------------------------- the cross-pattern confounding rule ---

function testACrossPatternRequestIsRefusedForAnExtractorRestrictedFeature(testCase)
%TESTACROSSPATTERNREQUESTISREFUSED... The rule enforced, not advised.
%
% Verified as a negative result: an implementation that returns the rows for any
% registered feature - the natural one, since the rows exist and carry a flag -
% passes every other test here and fails this one. A bandwidth-by-pattern plot
% built from those rows compares populations that differ in whether the
% measurement exists at all, and looks entirely reasonable while doing it.
profile = constructedProfile();

verifyError(testCase, @() vawlume.eda.crossPatternComparison(profile, ...
    "vocalization_frequency_bandwidth"), ...
    "vawlume:eda:FeatureNotCrossPatternComparable");

try
    vawlume.eda.crossPatternComparison(profile, ...
        "vocalization_frequency_bandwidth");
catch err
    % The refusal has to say where the feature IS reportable, because the
    % caller usually has a real question and the answer is a within-pattern
    % summary rather than nothing.
    verifySubstring(testCase, err.message, "deepsqueak|mupet");
    verifySubstring(testCase, err.message, "IS reportable within pattern");
    verifySubstring(testCase, err.message, "extractor composition, not the calls");
end

% The restricted feature is still present in the profile, within its own
% patterns and labelled - refused on a cross-pattern axis, not deleted.
restricted = profile.features(profile.features.equivalence_class == ...
    "vocalization_frequency_bandwidth", :);
verifyNotEmpty(testCase, restricted);
verifyTrue(testCase, all(~restricted.is_cross_pattern_comparable));
verifyTrue(testCase, all(contains(restricted.comparability_scope, ...
    "EXTRACTOR-RESTRICTED")));
verifyFalse(testCase, any(contains(restricted.extractor_set_key, "usvseg")), ...
    "A USVSEG pattern carries a bandwidth row, which USVSEG cannot measure.");
end

function testDurationAndCentreFrequencyArePermittedAcrossAllPatterns(testCase)
%TESTDURATIONANDCENTREFREQUENCYARE... The other half of the rule.
%
% A guard so broad that nothing survives it is not a guard, it is a refusal to
% report. Duration in particular has to pass: the matching specification
% reserves it as primary evidence for CLASSIFYING correspondence, and contract §K
% readmits it for characterization, which is a different question. An
% over-cautious reading of that specification would leave one usable feature.
profile = constructedProfile();

for name = ["vocalization_duration", "vocalization_frequency_center"]
    result = vawlume.eda.crossPatternComparison(profile, name);
    verifyEqual(testCase, result.status, "comparable");
    verifyEqual(testCase, result.equivalence_class, name);
    verifyEqual(testCase, height(result.rows), 7, ...
        name + " is not reported for all seven patterns.");
    verifyTrue(testCase, all(result.rows.is_cross_pattern_comparable));
end

duration = vawlume.eda.crossPatternComparison(profile, ...
    "vocalization_duration");
verifyTrue(testCase, duration.is_readmitted_timing_class, ...
    "Duration is not marked as the readmitted timing class.");
end

function testAnUnregisteredFeatureIsRefusedRatherThanReturnedEmpty(testCase)
%TESTANUNREGISTEREDFEATUREISREFUSED... An empty result reads as "no difference".
profile = constructedProfile();
verifyError(testCase, @() vawlume.eda.crossPatternComparison(profile, ...
    "vocalization_peak_frequency"), "vawlume:eda:FeatureNotRegistered");

try
    vawlume.eda.crossPatternComparison(profile, "vocalization_peak_frequency");
catch err
    verifySubstring(testCase, err.message, "never inferred from a feature name");
end
end

function testTheCrossPatternListingNamesBothHalvesOfTheRule(testCase)
profile = constructedProfile();
listing = vawlume.eda.crossPatternComparison(profile);

verifyEqual(testCase, listing.status, "listed");
verifyEqual(testCase, sort(listing.cross_pattern_comparable), ...
    sort(["vocalization_duration", "vocalization_frequency_center"]));
verifyTrue(testCase, ismember("vocalization_frequency_bandwidth", ...
    listing.extractor_restricted));
verifySubstring(testCase, listing.rule, "ENTIRE");
verifySubstring(testCase, listing.rule, "never across patterns");
end

% ---------------------------------------------------------------- coverage ---

function testLowCoverageIsAnnotatedOnTheCrossPatternResult(testCase)
%TESTLOWCOVERAGEISANNOTATED... A thin pattern and a fat one look identical.
%
% A cross-pattern comparison is exactly the shape that gets plotted, and a
% summary from three detections beside one from four hundred is the same height
% of bar. The warning travels with the result so it can reach a caption.
profile = constructedProfile();
result = vawlume.eda.crossPatternComparison(profile, "vocalization_duration");

verifyTrue(testCase, ismember("usvseg", result.low_coverage_patterns));
verifySubstring(testCase, result.coverage_warning, "LOW COVERAGE");
verifySubstring(testCase, result.coverage_warning, "not comparable evidence");

% Annotated, not filtered: the thin pattern keeps its row.
thin = result.rows(result.rows.extractor_set_key == "usvseg", :);
verifyEqual(testCase, height(thin), 1);
verifyTrue(testCase, thin.is_low_coverage);
verifyEqual(testCase, thin.coverage_label, "low_coverage");
verifyEqual(testCase, thin.contributing_detections, 2);
verifyEqual(testCase, thin.pattern_population, 10);
verifyEqual(testCase, thin.coverage_fraction, 0.2, AbsTol=1e-12);

% Coverage arithmetic is contributing over population, and the disjoint
% categories account for every member of the population exactly once.
for index = 1:height(result.rows)
    row = result.rows(index, :);
    verifyEqual(testCase, row.contributing_detections + row.not_eligible + ...
        row.not_measured + row.non_finite, row.pattern_population, ...
        "Coverage categories do not partition pattern " + ...
        row.extractor_set_key + ".");
    if row.pattern_population > 0
        verifyEqual(testCase, row.coverage_fraction, ...
            row.contributing_detections / row.pattern_population, ...
            AbsTol=1e-12);
    end
end
end

% ----------------------------------------------------- what must not appear ---

function testNoRankingOrConfidenceWeightAppearsInAnyReturnedFieldName(testCase)
%TESTNORANKINGORCONFIDENCEWEIGHT... Support count is not a confidence.
%
% Conceptual spec §10.4 forbids support-weighted confidence models and numeric
% weights derived from support count alone. Asserted on the field and column
% names because that is the surface a consumer binds to and a figure plots.
forbidden = ["confidence", "weight", "score", "rank", "ranking", "quality", ...
    "validity", "reliability", "best", "recommended", "is_valid", ...
    "is_true", "correctness"];
profile = constructedProfile();
for name = collectNames(profile)'
    verifyFalse(testCase, any(strcmpi(name, forbidden)), ...
        "The profile exposes a forbidden name: " + name);
end

% The interpretation note itself is asserted against the REAL profiler output
% in test_eda_support_pattern_profile. Asserting it here would be circular:
% the note in a constructed profile is one this test wrote.
end

% ---------------------------------------------------------------- helpers ---

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function names = collectNames(value)
names = strings(0, 1);
if isstruct(value)
    for name = string(fieldnames(value))'
        names(end + 1, 1) = name; %#ok<AGROW>
        names = [names; collectNames(value.(name))]; %#ok<AGROW>
    end
    return
end
if istable(value)
    names = [names; string(value.Properties.VariableNames)'];
end
end

function writeJson(path, document)
handle = fopen(path, "w");
fwrite(handle, jsonencode(document, PrettyPrint=true));
fclose(handle);
end

function value = repoRootPath()
value = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

% ------------------------------------------------------------- constructors ---

function profile = constructedProfile(options)
%CONSTRUCTEDPROFILE A profile shaped like supportPatternProfile's, built by hand.
%
% Hand-built so a test can put a specific coverage fraction on a specific
% pattern, and so the arbitrary-N cases - two extractors, four extractors - do
% not each need a fixture database with that many extractors registered. The real
% registry joins and the real distributions are exercised against a database in
% test_eda_support_pattern_profile; what is tested here is the arithmetic and the
% rules built on top of them.
arguments
    options.Extractors string = ["deepsqueak", "mupet", "usvseg"]
end

keys = sort(options.Extractors(:));
vocabulary = patternVocabulary(keys);

universal = ["vocalization_duration", "vocalization_frequency_center"];
restrictedTo = keys(1:min(2, numel(keys)));
eligibility = emptyEligibility();
for name = universal
    eligibility = [eligibility; eligibilityRow(name, keys, vocabulary, ...
        true, name == "vocalization_duration")]; %#ok<AGROW>
end
if numel(keys) >= 3
    eligibility = [eligibility; eligibilityRow( ...
        "vocalization_frequency_bandwidth", restrictedTo, vocabulary, ...
        false, false)];
end
eligibility = coerceEligibility(eligibility);

features = emptyFeatures();
for index = 1:height(vocabulary)
    setKey = vocabulary.extractor_set_key(index);
    population = populationFor(setKey);
    for at = 1:height(eligibility)
        if ~ismember(setKey, string(eligibility.eligible_patterns{at}(:)))
            continue
        end
        contributing = contributingFor(setKey, population);
        features = [features; featureRow(vocabulary(index, :), ...
            eligibility(at, :), population, contributing)]; %#ok<AGROW>
    end
end

features = coerceFeatures(features);

profile = struct( ...
    status="profiled", ...
    reference_configuration=struct( ...
        profile_key="vawlume.matching.prototype.v1", ...
        version_label="0.1.0", ...
        checksum_sha256=repmat('b', 1, 64), ...
        calibration_state="illustrative_prototype", ...
        identity_line="vawlume.matching.prototype.v1 0.1.0 " + ...
            "(illustrative_prototype)", ...
        calibration_note="a reference is not a calibration"), ...
    pattern_vocabulary=vocabulary, ...
    patterns=vocabulary, ...
    feature_eligibility=eligibility, ...
    features=features, ...
    interpretation_note=interpretationNote(), ...
    caution="agreement is methodological evidence, not ground truth");
end

function value = coerceEligibility(value)
%COERCEELIGIBILITY Give the assembled rows the column TYPES the real table has.
%
% An empty cell2table has cell columns, and concatenating typed rows onto it
% leaves everything a cell - so `is_cross_pattern_comparable` arrives as a cell
% column and logical indexing on it fails. The production code found this, not
% the test: a constructed table has to match the real one in type as well as in
% column name, or it exercises something the profiler never produces.
value.equivalence_class = asString(value.equivalence_class);
value.comparable_extractor_key = asString(value.comparable_extractor_key);
value.comparability_scope = asString(value.comparability_scope);
value.canonical_unit = asString(value.canonical_unit);
value.is_universally_comparable = asLogical(value.is_universally_comparable);
value.is_cross_pattern_comparable = asLogical(value.is_cross_pattern_comparable);
value.is_readmitted_timing_class = asLogical(value.is_readmitted_timing_class);
value.eligible_pattern_count = asDouble(value.eligible_pattern_count);
value.pattern_count = asDouble(value.pattern_count);
value.registered_pair_count = asDouble(value.registered_pair_count);
end

function value = asString(value)
if iscell(value)
    value = string(value);
end
value = string(value(:));
end

function value = asLogical(value)
if iscell(value)
    value = cell2mat(value);
end
value = logical(value(:));
end

function value = asDouble(value)
if iscell(value)
    value = cell2mat(value);
end
value = double(value(:));
end

function value = coerceFeatures(value)
%COERCEFEATURES The same type correction, for the feature rows.
for name = ["extractor_set_key", "extractor_set_label", "equivalence_class", ...
        "canonical_unit", "comparability_scope", "coverage_label", ...
        "statistics_status"]
    value.(name) = asString(value.(name));
end
for name = ["is_cross_pattern_comparable", "is_readmitted_timing_class", ...
        "is_low_coverage"]
    value.(name) = asLogical(value.(name));
end
for name = ["pattern_population", "contributing_detections", "not_eligible", ...
        "not_measured", "missing_canonical_value", "non_finite", ...
        "coverage_fraction", "minimum", "q25", "median", "q75", "maximum", ...
        "interquartile_range"]
    value.(name) = asDouble(value.(name));
end
end

function value = populationFor(setKey)
%POPULATIONFOR Deliberately unequal, so coverage has something to distinguish.
value = 10;
if contains(setKey, "|")
    value = 40;
end
end

function value = contributingFor(setKey, population)
% The usvseg-only pattern is thin on purpose: 2 of 10 is 0.2 coverage, below the
% 0.50 threshold, so the low-coverage annotation has a case to fire on.
value = population;
if setKey == "usvseg"
    value = 2;
end
end

function value = patternVocabulary(keys)
setKey = strings(0, 1);
setLabel = strings(0, 1);
members = cell(0, 1);
memberCount = zeros(0, 1);
count = numel(keys);
for size = 1:count
    combinations = nchoosek(1:count, size);
    for index = 1:height(combinations)
        selected = sort(keys(combinations(index, :)));
        setKey(end + 1, 1) = strjoin(selected', "|"); %#ok<AGROW>
        setLabel(end + 1, 1) = strjoin(selected', " + "); %#ok<AGROW>
        members{end + 1, 1} = selected'; %#ok<AGROW>
        memberCount(end + 1, 1) = size; %#ok<AGROW>
    end
end
value = table(setKey, setLabel, members, memberCount, memberCount == 1, ...
    memberCount == count, ...
    VariableNames=["extractor_set_key", "extractor_set_label", ...
    "extractor_keys", "extractor_count", "is_extractor_unique", ...
    "is_complete_support"]);
end

function row = eligibilityRow(name, comparable, vocabulary, isUniversal, ...
    isReadmitted)
eligible = strings(0, 1);
for index = 1:height(vocabulary)
    keys = string(vocabulary.extractor_keys{index}(:))';
    if all(ismember(keys, comparable))
        eligible(end + 1, 1) = vocabulary.extractor_set_key(index); %#ok<AGROW>
    end
end
scope = "EXTRACTOR-RESTRICTED: reportable only within patterns whose " + ...
    "contributing extractors all register it, and never on a cross-pattern axis";
if isUniversal
    scope = "comparable across every support pattern";
end
row = cell2table({name, {sort(comparable)'}, strjoin(sort(comparable)', "|"), ...
    isUniversal, isUniversal, {eligible}, numel(eligible), ...
    height(vocabulary), scope, "s", isReadmitted, numel(comparable)}, ...
    VariableNames=eligibilityNames());
end

function row = featureRow(pattern, eligible, population, contributing)
fraction = 0;
if population > 0
    fraction = contributing / population;
end
label = "reported";
if fraction < 0.50
    label = "low_coverage";
end
if population == 0
    label = "no_population";
end
row = cell2table({pattern.extractor_set_key, pattern.extractor_set_label, ...
    eligible.equivalence_class, eligible.canonical_unit, ...
    eligible.is_cross_pattern_comparable, eligible.comparability_scope, ...
    eligible.is_readmitted_timing_class, population, contributing, ...
    population - contributing, 0, 0, 0, fraction, fraction < 0.50, label, ...
    "computed", 0.01, 0.02, 0.03, 0.04, 0.05, 0.02}, ...
    VariableNames=featureNames());
end

function value = interpretationNote()
value = [ ...
    "This is detection-profile characterization within one dataset."; ...
    "Not permitted: that a support class carries more confidence, or that " + ...
        "any numeric weight follows from support count."; ...
    "A detection reported by one extractor only has NOT been shown to be false."];
end

function value = eligibilityNames()
value = ["equivalence_class", "comparable_extractors", ...
    "comparable_extractor_key", "is_universally_comparable", ...
    "is_cross_pattern_comparable", "eligible_patterns", ...
    "eligible_pattern_count", "pattern_count", "comparability_scope", ...
    "canonical_unit", "is_readmitted_timing_class", "registered_pair_count"];
end

function value = featureNames()
value = ["extractor_set_key", "extractor_set_label", "equivalence_class", ...
    "canonical_unit", "is_cross_pattern_comparable", "comparability_scope", ...
    "is_readmitted_timing_class", "pattern_population", ...
    "contributing_detections", "not_eligible", "not_measured", ...
    "missing_canonical_value", "non_finite", "coverage_fraction", ...
    "is_low_coverage", "coverage_label", "statistics_status", "minimum", ...
    "q25", "median", "q75", "maximum", "interquartile_range"];
end

function value = emptyEligibility()
value = cell2table(cell(0, numel(eligibilityNames())), ...
    VariableNames=eligibilityNames());
end

function value = emptyFeatures()
value = cell2table(cell(0, numel(featureNames())), ...
    VariableNames=featureNames());
end
