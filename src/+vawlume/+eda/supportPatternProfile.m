function result = supportPatternProfile(conn, analysisRef, reference, options)
%SUPPORTPATTERNPROFILE What kinds of detections occupy each exact support pattern.
%
% RESULT = vawlume.eda.SUPPORTPATTERNPROFILE(CONN, ANALYSISREF, REFERENCE) takes
% one completed agreement analysis - computed at the reference configuration
% REFERENCE identifies - and reports, for every EXACT extractor-set pattern, how
% many groups and detections it holds, and how the registered comparable features
% are distributed within it, with coverage beside every summary.
%
% ANALYSISREF selects the agreement analysis, in vawlume.agreement.selectPopulation's
% own form: struct(analysis_run_id=...), struct(run_key=...), or
% struct(project_key=..., run_key=...).
%
% Name-value options:
%   RecordingId          restrict to one recording
%   ThresholdContext     a vawlume.eda.probeConcordance result, whose observed
%                        support-pattern count ranges are carried through
%   LowCoverageThreshold default 0.50 (contract §K)
%   MinimumObservations  below this many contributing detections the statistics
%                        are reported undefined rather than computed, default 2
%
% THE PATTERN IS THE EXTRACTOR SET, NOT THE SUPPORTED PAIR PATTERN. Conceptual
% spec §2.3's seven categories for three extractors - DeepSqueak only, MUPET
% only, USVSEG only, the three pairs, and the three-way set - are extractor sets.
% A singleton group's `supported_extractor_pair_pattern` is "(none)" whichever
% extractor produced it, so keying on the pair pattern would merge the three
% "X only" categories into one and lose exactly the distinction §2.3 requires.
% Both vocabularies are reported; they are never joined. See RESULT.vocabulary_note.
%
% EVERY PATTERN GETS A ROW, INCLUDING ZERO-COUNT ONES. The vocabulary is
% enumerated from the participating extractor keys rather than observed, because
% a reader has to be able to see that a pattern was looked for and not found. An
% absent row and a zero row look the same in a table and mean different things.
%
% COMPARABILITY IS REGISTERED, NEVER INFERRED. Features are discovered through
% feature_relationships and consilience_eligible only. The pilot registry
% contains the trap: DeepSqueak's "Peak Freq (kHz)" and USVSEG's "maxfreq" share
% the equivalence class `vocalization_peak_frequency` and are not registered as
% comparable, so no peak-frequency summary is produced for that pair - and an
% implementation that grouped by equivalence class would have produced one.
%
% FEATURE AVAILABILITY IS CONFOUNDED WITH SUPPORT PATTERN, and this is the most
% consequential rule here. A pattern's members come from specific extractors by
% definition, so bandwidth exists for a DeepSqueak-MUPET group and cannot exist
% for any pattern containing USVSEG. A bandwidth-by-pattern plot would compare
% populations that differ in whether the measurement exists at all, and the
% apparent difference would be the extractor composition rather than the calls.
% Every feature row therefore carries `is_cross_pattern_comparable`, and
% vawlume.eda.crossPatternComparison REFUSES a restricted feature rather than
% trusting a caller to read the flag.
%
% COVERAGE TRAVELS WITH EVERY SUMMARY, and is annotated rather than filtered. A
% duration distribution computed from 9 detections and one computed from 4,000
% look identical in a figure. Below the threshold the row is marked
% `low_coverage` and reported anyway: a low-coverage feature is itself a finding
% about the extractor set, not a row to drop.
%
% THIS IS CHARACTERIZATION, NOT RANKING. Nothing here scores a support pattern,
% orders the patterns by anything but their own vocabulary, or assigns a
% confidence weight from support count. A detection reported by one extractor
% only has not been shown to be false.
%
% This function reads. It writes nothing.

arguments
    conn
    analysisRef (1,1) struct
    reference (1,1) struct
    options.RecordingId (1,1) double = NaN
    options.ThresholdContext struct = struct([])
    options.LowCoverageThreshold (1,1) double {mustBeNonnegative} = 0.50
    options.MinimumObservations (1,1) double {mustBeNonnegative} = 2
end

requireFields(reference, ["profile_key", "version_label", ...
    "checksum_sha256", "calibration_status"]);

population = vawlume.agreement.selectPopulation(conn, analysisRef, ...
    RecordingId=options.RecordingId);
if height(population.members) == 0
    error("vawlume:eda:SupportPopulationEmpty", ...
        "The agreement analysis holds no detection, so there is no " + ...
        "population to characterize.");
end

extractors = extractorTable(population);
vocabulary = edaSupportPatternVocabulary(extractors.extractor_key);
assignment = assignGroups(population, vocabulary);

patterns = patternCounts(vocabulary, assignment, population);
pairPatterns = pairPatternCounts(population);
detections = detectionsPerExtractor(population);

discovery = edaComparableFeatures(conn, extractors.extractor_name);
eligibility = featureEligibility(discovery, vocabulary, extractors);
measurements = readMeasurements(conn, population, discovery);
features = featureSummaries(vocabulary, assignment, population, ...
    eligibility, measurements, extractors, options);

result = struct( ...
    status="profiled", ...
    analysis_run_id=population.analysis.analysis_run_id, ...
    agreement_run_key=string(population.analysis.run_key), ...
    reference_configuration=referenceIdentity(reference), ...
    extractors=extractors, ...
    extractor_count=height(extractors), ...
    detections_considered=detections, ...
    total_detections=sum(detections.detection_count), ...
    total_groups=height(population.groups), ...
    patterns=patterns, ...
    pattern_vocabulary=vocabulary(:, ["extractor_set_key", ...
        "extractor_set_label", "extractor_count", "is_extractor_unique", ...
        "is_complete_support"]), ...
    pair_patterns=pairPatterns, ...
    vocabulary_note="`patterns` is keyed on the EXTRACTOR SET - conceptual " + ...
        "spec §2.3's seven categories for three extractors. `pair_patterns` " + ...
        "is keyed on `supported_extractor_pair_pattern`, which says which " + ...
        "pairs corroborated each other. THE TWO ARE DIFFERENT VOCABULARIES " + ...
        "OVER THE SAME GROUPS AND MUST NOT BE JOINED: every singleton has " + ...
        "pair pattern '(none)' whichever extractor produced it, so a join " + ...
        "would merge the three extractor-unique categories into one.", ...
    feature_discovery=discovery, ...
    feature_eligibility=eligibility, ...
    features=features, ...
    shared_space_limitation=sharedSpaceLimitation(eligibility, extractors), ...
    coverage_policy="coverage is contributing detections over pattern " + ...
        "population, reported per feature per pattern. Summaries below " + ...
        string(options.LowCoverageThreshold) + " coverage are ANNOTATED " + ...
        "`low_coverage` and reported anyway, never filtered: a low-coverage " + ...
        "feature is itself a finding about the extractor set.", ...
    low_coverage_threshold=options.LowCoverageThreshold, ...
    threshold_context=thresholdContext(options, pairPatterns), ...
    interpretation_note=interpretationNote(), ...
    caution=edaCautionNote());
end

% ------------------------------------------------------------- population ---

function value = extractorTable(population)
%EXTRACTORTABLE The participating extractors, from the data.
members = population.members;
[keys, at] = unique(members.extractor_key);
value = table(keys, members.extractor_name(at), ...
    VariableNames=["extractor_key", "extractor_name"]);
value = sortrows(value, "extractor_key");
end

function assignment = assignGroups(population, vocabulary)
%ASSIGNGROUPS Each group's exact extractor-set pattern.
%
% Recomputed from the members rather than read from `extractor_set_key`, for one
% reason: the view builds that key with group_concat over a subquery whose ORDER
% BY is not guaranteed to survive, and a differently ordered key would not match
% the enumerated vocabulary and would silently produce an unknown pattern. The
% members are the ground truth, and the sort here is explicit.
groups = population.groups;
members = population.members;
setKey = strings(height(groups), 1);
detectionCount = zeros(height(groups), 1);
for index = 1:height(groups)
    id = groups.agreement_group_id(index);
    selected = members(members.agreement_group_id == id, :);
    setKey(index) = strjoin(sort(unique(selected.extractor_key))', "|");
    detectionCount(index) = height(selected);
end

unknown = setKey(~ismember(setKey, vocabulary.extractor_set_key));
if ~isempty(unknown)
    error("vawlume:eda:SupportPatternUnknown", ...
        "Group extractor set(s) %s are not in the enumerated vocabulary. " + ...
        "The vocabulary is every non-empty subset of the participating " + ...
        "extractors, so this means a member carries an extractor key the " + ...
        "population did not report.", strjoin(unique(unknown)', ", "));
end

assignment = table(groups.agreement_group_id, setKey, detectionCount, ...
    VariableNames=["agreement_group_id", "extractor_set_key", ...
    "detection_count"]);
end

function patterns = patternCounts(vocabulary, assignment, population)
%PATTERNCOUNTS One row per enumerated pattern, zero-count rows included.
totalGroups = height(population.groups);
totalDetections = height(population.members);

groupCount = zeros(height(vocabulary), 1);
detectionCount = zeros(height(vocabulary), 1);
for index = 1:height(vocabulary)
    selected = assignment.extractor_set_key == ...
        vocabulary.extractor_set_key(index);
    groupCount(index) = nnz(selected);
    detectionCount(index) = sum(assignment.detection_count(selected));
end

patterns = table(vocabulary.extractor_set_key, ...
    vocabulary.extractor_set_label, vocabulary.extractor_count, ...
    vocabulary.is_extractor_unique, vocabulary.is_complete_support, ...
    groupCount, share(groupCount, totalGroups), ...
    detectionCount, share(detectionCount, totalDetections), ...
    repmat(totalGroups, height(vocabulary), 1), ...
    repmat(totalDetections, height(vocabulary), 1), ...
    groupCount == 0, ...
    VariableNames=["extractor_set_key", "extractor_set_label", ...
    "extractor_count", "is_extractor_unique", "is_complete_support", ...
    "group_count", "group_proportion", "detection_count", ...
    "detection_proportion", "group_denominator", "detection_denominator", ...
    "is_absent"]);
end

function value = pairPatternCounts(population)
%PAIRPATTERNCOUNTS The complementary vocabulary, reported beside but never joined.
groups = population.groups;
patterns = groups.supported_extractor_pair_pattern;
patterns(strlength(patterns) == 0) = "(none)";
[distinct, ~, grouping] = unique(patterns);
counts = accumarray(grouping, 1);
value = table(distinct, counts, share(counts, height(groups)), ...
    repmat(height(groups), numel(distinct), 1), ...
    VariableNames=["supported_extractor_pair_pattern", "group_count", ...
    "group_proportion", "group_denominator"]);
end

function value = detectionsPerExtractor(population)
members = population.members;
[keys, at] = unique(members.extractor_key);
counts = zeros(numel(keys), 1);
unique_counts = zeros(numel(keys), 1);
for index = 1:numel(keys)
    selected = members.extractor_key == keys(index);
    counts(index) = nnz(selected);
    ids = unique(members.agreement_group_id(selected));
    unique_counts(index) = nnz(arrayfun(@(id) ...
        isscalar(unique(members.extractor_key( ...
        members.agreement_group_id == id))), ids));
end
value = table(keys, members.extractor_name(at), counts, unique_counts, ...
    VariableNames=["extractor_key", "extractor_name", "detection_count", ...
    "extractor_unique_group_count"]);
value = sortrows(value, "extractor_key");
end

% ------------------------------------------------------ feature eligibility ---

function value = featureEligibility(discovery, vocabulary, extractors)
%FEATUREELIGIBILITY Which patterns each registered class may be summarized in.
%
% A class is summarizable within a pattern when every extractor contributing to
% that pattern is in the class's comparable set. It is CROSS-PATTERN comparable
% only when its comparable set covers the whole participating extractor set -
% contract §K's rule, and the reason a bandwidth-by-pattern axis is forbidden.
value = emptyEligibility();
classes = discovery.classes;
nameByKey = containers.Map(cellstr(extractors.extractor_key), ...
    cellstr(extractors.extractor_name));

for index = 1:height(classes)
    row = classes(index, :);
    comparable = string(row.comparable_extractors{1}(:))';
    eligiblePatterns = strings(0, 1);
    for at = 1:height(vocabulary)
        keys = string(vocabulary.extractor_keys{at}(:))';
        names = string(cellfun(@(k) nameByKey(k), cellstr(keys), ...
            UniformOutput=false));
        if all(ismember(names, comparable))
            eligiblePatterns(end + 1, 1) = ...
                vocabulary.extractor_set_key(at); %#ok<AGROW>
        end
    end
    value(end + 1, :) = {row.equivalence_class, ...
        {comparable}, row.comparable_extractor_key, ...
        row.is_universally_comparable, ...
        row.is_universally_comparable, ...
        {eligiblePatterns}, numel(eligiblePatterns), height(vocabulary), ...
        scopeLabel(row.is_universally_comparable), ...
        row.canonical_unit, row.is_readmitted_timing_class, ...
        row.registered_pair_count}; %#ok<AGROW>
end
if height(value) > 0
    value = sortrows(value, ["is_cross_pattern_comparable", ...
        "equivalence_class"], {'descend', 'ascend'});
end
end

function value = scopeLabel(isUniversal)
if isUniversal
    value = "comparable across every support pattern";
    return
end
value = "EXTRACTOR-RESTRICTED: reportable only within patterns whose " + ...
    "contributing extractors all register it, and never on a cross-pattern axis";
end

% ------------------------------------------------------------ measurements ---

function value = readMeasurements(conn, population, discovery)
%READMEASUREMENTS Every registered-comparable measurement for the population.
%
% Scoped to the feature ids the registry named, so a measurement of an
% unregistered feature never enters the table at all. The equivalence class comes
% from `extractor_features`, not from `v_event_measurements_long`, which exposes
% `canonical_features.canonical_name` and carries no equivalence_class column -
% resolution goes event_measurements -> extractor_feature_id -> equivalence_class.
value = emptyMeasurements();
if height(discovery.pairs) == 0
    return
end
detectionIds = unique(population.members.detection_id);
classes = unique(discovery.classes.equivalence_class);
if isempty(detectionIds) || isempty(classes)
    return
end

% ONLY THE CANONICAL VALUE IS READ, and there is deliberately no fallback to
% `native_value_real`. The pilot registry makes the reason concrete: DeepSqueak
% stores duration natively in seconds while MUPET and USVSEG store it in
% milliseconds, and all three store centre frequency in kHz against a canonical
% Hz. A fallback would put seconds and milliseconds into one distribution - a
% thousandfold error that would appear as a spectacular difference in call
% duration between support patterns and would be entirely an artifact of which
% extractor exported the row. A measurement with no canonical value is counted
% as absent instead, which is what it is for a comparison.
rows = fetch(conn, "SELECT em.detection_id, " + ...
    "IFNULL(xf.equivalence_class,'') AS equivalence_class, " + ...
    "em.canonical_value_real AS value, " + ...
    "IFNULL(em.canonical_unit,'') AS unit, " + ...
    "CASE WHEN em.canonical_value_real IS NULL THEN 1 ELSE 0 END " + ...
    "AS canonical_missing " + ...
    "FROM event_measurements em " + ...
    "JOIN extractor_features xf " + ...
    "ON xf.extractor_feature_id=em.extractor_feature_id " + ...
    "WHERE em.detection_id IN (" + strjoin(string(detectionIds'), ",") + ") " + ...
    "AND xf.equivalence_class IN (" + ...
    strjoin(arrayfun(@edaSqlText, classes'), ", ") + ")");
if isempty(rows) || height(rows) == 0
    return
end
value = table(double(rows.detection_id), ...
    edaPresentText(rows.equivalence_class), double(rows.value), ...
    edaPresentText(rows.unit), double(rows.canonical_missing) == 1, ...
    VariableNames=["detection_id", "equivalence_class", "value", "unit", ...
    "canonical_missing"]);
assertOneUnitPerClass(value);
end

function assertOneUnitPerClass(measurements)
%ASSERTONEUNITPERCLASS Two canonical units in one class is not one distribution.
%
% The canonical unit is what makes three extractors' measurements of the same
% quantity commensurable, so two of them within one equivalence class means the
% values are not on one scale and the median of them means nothing. Raised rather
% than normalized here: converting would be a unit judgement this layer is not
% entitled to make, and the registry is where it belongs.
present = measurements(strlength(measurements.unit) > 0, :);
if height(present) == 0
    return
end
classes = unique(present.equivalence_class);
for index = 1:numel(classes)
    units = unique(present.unit(present.equivalence_class == classes(index)));
    if numel(units) > 1
        error("vawlume:eda:CanonicalUnitNotUnique", ...
            "Feature class '%s' carries %d canonical units (%s) across the " + ...
            "population, so its values are not on one scale and no " + ...
            "distribution over them is meaningful. Normalization belongs in " + ...
            "the feature registry, not here.", ...
            classes(index), numel(units), strjoin(sort(units)', ", "));
    end
end
end

% -------------------------------------------------------- feature summaries ---

function features = featureSummaries(vocabulary, assignment, population, ...
    eligibility, measurements, extractors, options)
%FEATURESUMMARIES One distribution per feature per pattern it is eligible in.
%
% Distributions rather than means, through Part 3's vawlume.eda.metricDistributions
% rather than a second summary implementation. The scientific question is what
% KINDS of detections occupy a pattern, and a median with an interquartile range
% answers it where a mean does not.
features = emptyFeatures();
if height(eligibility) == 0 || height(vocabulary) == 0
    return
end
members = population.members;
nameByKey = containers.Map(cellstr(extractors.extractor_key), ...
    cellstr(extractors.extractor_name));

for patternIndex = 1:height(vocabulary)
    setKey = vocabulary.extractor_set_key(patternIndex);
    groupIds = assignment.agreement_group_id( ...
        assignment.extractor_set_key == setKey);
    selected = members(ismember(members.agreement_group_id, groupIds), :);
    eligible = eligibility(cellfun(@(p) ismember(setKey, p), ...
        eligibility.eligible_patterns), :);
    if height(eligible) == 0
        continue
    end
    features = [features; summariesForPattern(vocabulary(patternIndex, :), ...
        selected, eligible, measurements, nameByKey, options)]; %#ok<AGROW>
end
end

function rows = summariesForPattern(pattern, selected, eligible, ...
    measurements, nameByKey, options)
rows = emptyFeatures();
population = height(selected);
names = eligible.equivalence_class;
missingCanonical = zeros(numel(names), 1);

values = NaN(max(population, 1), numel(names));
coverage = edaEmptyFeatureCoverage();
for index = 1:numel(names)
    [column, counts] = valuesFor(names(index), selected, measurements, ...
        eligible(index, :), nameByKey);
    if population > 0
        values(1:population, index) = column;
    end
    coverage(end + 1, :) = {names(index), "feature", counts.supported, ...
        counts.not_eligible, counts.not_measured, 0, counts.non_finite, ...
        population}; %#ok<AGROW>
    missingCanonical(index) = counts.missing_canonical;
end

% The surface is shaped exactly as vawlume.eda.candidateMetrics builds one, so
% Part 3's summarizer serves this layer unchanged rather than acquiring a second
% implementation. Every feature here is a `feature` metric and none is an
% absolute value: these are measured call properties, not signed differences
% between two extractors' measurements of one call, which is what `is_absolute`
% distinguishes on the candidate surface.
surface = struct( ...
    metrics=array2table(values(1:max(population, 0), :), ...
        VariableNames=names'), ...
    metric_names=names', ...
    feature_metric_names=names', ...
    absolute_metric_names=strings(1, 0), ...
    coverage=coverage);
if population == 0
    surface.metrics = array2table(zeros(0, numel(names)), ...
        VariableNames=names');
end
distributions = vawlume.eda.metricDistributions(surface, ...
    MinimumSupportedObservations=options.MinimumObservations);

for index = 1:numel(names)
    distribution = distributions.distributions( ...
        distributions.distributions.metric_name == names(index), :);
    counts = coverage(coverage.metric_name == names(index), :);
    fraction = 0;
    if population > 0
        fraction = counts.supported / population;
    end
    rows(end + 1, :) = {pattern.extractor_set_key, ...
        pattern.extractor_set_label, names(index), ...
        eligible.canonical_unit(index), ...
        eligible.is_cross_pattern_comparable(index), ...
        eligible.comparability_scope(index), ...
        eligible.is_readmitted_timing_class(index), ...
        population, counts.supported, counts.not_eligible, ...
        counts.not_measured, missingCanonical(index), counts.non_finite, ...
        fraction, ...
        population > 0 && fraction < options.LowCoverageThreshold, ...
        coverageLabel(fraction, population, options), ...
        distribution.statistics_status, distribution.minimum, ...
        distribution.q0_250, distribution.median, distribution.q0_750, ...
        distribution.maximum, ...
        distribution.q0_750 - distribution.q0_250}; %#ok<AGROW>
end
end

function [column, counts] = valuesFor(equivalenceClass, selected, ...
    measurements, eligible, nameByKey)
%VALUESFOR One value per member detection, and why each is absent when it is.
%
% THE COVERAGE CATEGORIES CARRY THE CONFOUNDING. A detection whose extractor does
% not register the class at all is `not_eligible` - the measurement could never
% have existed. A detection whose extractor registers it but exported no value is
% `not_measured` - it could have existed and does not. Summing them into one
% "missing" count would hide exactly the fact contract §K is about: that a
% pattern containing USVSEG has no bandwidth because USVSEG does not measure
% bandwidth, not because those particular calls lacked one.
population = height(selected);
column = NaN(population, 1);
counts = struct(supported=0, not_eligible=0, not_measured=0, ...
    non_finite=0, missing_canonical=0);
if population == 0
    return
end
comparable = string(eligible.comparable_extractors{1}(:))';
rows = measurements(measurements.equivalence_class == equivalenceClass, :);

for index = 1:population
    extractorName = string(nameByKey(char(selected.extractor_key(index))));
    if ~ismember(extractorName, comparable)
        counts.not_eligible = counts.not_eligible + 1;
        continue
    end
    match = rows(rows.detection_id == selected.detection_id(index), :);
    if height(match) == 0
        counts.not_measured = counts.not_measured + 1;
        continue
    end
    if match.canonical_missing(1)
        % The row exists and carries only a native value in the extractor's
        % own unit. Counted as absent rather than used: see readMeasurements.
        counts.not_measured = counts.not_measured + 1;
        counts.missing_canonical = counts.missing_canonical + 1;
        continue
    end
    if ~isfinite(match.value(1))
        counts.non_finite = counts.non_finite + 1;
        continue
    end
    column(index) = match.value(1);
    counts.supported = counts.supported + 1;
end
end

function value = coverageLabel(fraction, population, options)
%COVERAGELABEL Absent, thinly covered, or reported - three facts, not two.
%
% AN EMPTY PATTERN IS NOT A LOW-COVERAGE ONE. Coverage is contributing detections
% over pattern population, and zero over zero is not a small fraction: there is
% nothing there to cover. Labelling it `low_coverage` would tell a reader the
% feature is poorly measured in that pattern when the truth is that the pattern
% has no members at all - the same conflation of "absent" with "small" this whole
% part exists to prevent, appearing in its own coverage column. `is_low_coverage`
% is false for these rows for the same reason.
if population == 0
    value = "no_population";
    return
end
if fraction < options.LowCoverageThreshold
    value = "low_coverage";
    return
end
value = "reported";
end

% --------------------------------------------------------------- narrative ---

function value = sharedSpaceLimitation(eligibility, extractors)
%SHAREDSPACELIMITATION The thinness of the shared space, as a stated finding.
%
% Conceptual spec §2.7 requires this to be acknowledged as a methodological
% limitation rather than closed by speculative harmonization. It is computed from
% what the registry actually declares, so it stays true if a relationship is
% registered later - and it is a sentence rather than a number because the number
% alone ("2") does not tell a reader what to do about it.
universal = eligibility.equivalence_class(eligibility.is_cross_pattern_comparable);
restricted = eligibility.equivalence_class(~eligibility.is_cross_pattern_comparable);
names = strjoin(sort(extractors.extractor_name)', ", ");

text = "Across the participating extractors (" + names + ") only " + ...
    string(numel(universal)) + " registered feature class(es) are " + ...
    "comparable throughout: " + listOrNone(universal) + ". ";
if ~isempty(restricted)
    text = text + string(numel(restricted)) + " further class(es) are " + ...
        "registered for some extractors only (" + listOrNone(restricted) + ...
        ") and are reported WITHIN eligible patterns, never across them. ";
end
text = text + "This thinness is a METHODOLOGICAL LIMITATION of the " + ...
    "extractor set, not a result about vocalizations, and it is not closed " + ...
    "by harmonizing features the registry does not declare comparable.";

value = struct( ...
    universally_comparable=sort(universal)', ...
    universally_comparable_count=numel(universal), ...
    extractor_restricted=sort(restricted)', ...
    extractor_restricted_count=numel(restricted), ...
    statement=text);
end

function value = thresholdContext(options, pairPatterns)
%THRESHOLDCONTEXT Pattern count ranges carried from the probes, not recomputed.
%
% Development plan §3.8 wants the range a pattern's count took across the
% sensitivity probes beside its characterization: a pattern whose count is stable
% is a different kind of finding from one that triples between the probe's low and
% high settings. Kept to ranges, deliberately - the same section is explicit that
% this must not turn every characterization plot into a multidimensional sweep.
%
% CARRIED UNDER THE PROBE'S OWN KEY, which is the SUPPORTED PAIR PATTERN and not
% the extractor set this profile is keyed on. The two vocabularies are not
% joined; doing so would attach a pair pattern's range to an extractor-set row
% that does not correspond to it.
value = struct( ...
    status="absent", ...
    source="", ...
    keyed_on="supported_extractor_pair_pattern", ...
    ranges=emptyThresholdRanges(), ...
    note="No probe result was supplied, so no threshold context is " + ...
        "reported. Pass ThresholdContext= a vawlume.eda.probeConcordance " + ...
        "result to carry the observed ranges.");
if isempty(fieldnames(options.ThresholdContext))
    return
end
context = options.ThresholdContext;
if ~isfield(context, "support_pattern_movement")
    return
end
movement = context.support_pattern_movement;
if ~isfield(movement, "observed_counts") || ...
        height(movement.observed_counts) == 0
    return
end
observed = movement.observed_counts;
value.status = "carried";
value.source = "vawlume.eda.probeConcordance support_pattern_movement";
value.ranges = observed;
value.probe_patterns_observed = unique(observed.support_pattern)';
value.profile_patterns_observed = pairPatterns.supported_extractor_pair_pattern';
value.note = "Ranges are the counts each supported-pair pattern took across " + ...
    "the probes' configurations, carried from Part 10 and NOT recomputed " + ...
    "here. They are keyed on `supported_extractor_pair_pattern`, so they " + ...
    "align with `pair_patterns` and NOT with `patterns`, which is keyed on " + ...
    "the extractor set. Do not join them to a pattern row.";
end

function value = interpretationNote()
%INTERPRETATIONNOTE What may and may not be said from this table.
%
% Carried in the output rather than left to a docstring, because this is the part
% of the MVP whose results most invite a narrative and the table will travel
% without the code.
value = [ ...
    "This is detection-profile characterization within one dataset at one " + ...
        "named configuration. Nothing here establishes that one support " + ...
        "class is better, more valid, or more confident than another."; ...
    "Permitted reading: within this dataset, detections in one support " + ...
        "pattern differed in their duration distribution from those in " + ...
        "another. The denominators and coverage beside each summary are " + ...
        "part of that statement, not decoration."; ...
    "Not permitted: that an extractor is inherently specialized for a call " + ...
        "type, that a support class carries more confidence, or that any " + ...
        "numeric weight follows from support count."; ...
    "The evidential asymmetry holds here as everywhere: a detection " + ...
        "reported by one extractor only has NOT been shown to be false, and " + ...
        "an extractor-unique pattern is not an error category."];
end

% -------------------------------------------------------------- plumbing ---

function value = referenceIdentity(reference)
value = struct( ...
    profile_key=string(reference.profile_key), ...
    version_label=string(reference.version_label), ...
    checksum_sha256=string(reference.checksum_sha256), ...
    calibration_state=string(reference.calibration_status.state), ...
    identity_line=identityOr(reference), ...
    calibration_note=noteOr(reference));
end

function value = identityOr(reference)
value = string(reference.profile_key) + " " + string(reference.version_label);
if isfield(reference, "identity_line")
    value = string(reference.identity_line);
end
end

function value = noteOr(reference)
value = "";
if isfield(reference, "calibration_note")
    value = string(reference.calibration_note);
end
end

function value = listOrNone(names)
if isempty(names)
    value = "none";
    return
end
value = strjoin(sort(names)', ", ");
end

function value = share(counts, total)
value = zeros(numel(counts), 1);
if total > 0
    value = counts / total;
end
end

function value = emptyThresholdRanges()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), VariableNames=["probe_role", "support_pattern", ...
    "lowest_group_count", "highest_group_count", "observed_movement"]);
end

function value = emptyEligibility()
value = table(strings(0, 1), cell(0, 1), strings(0, 1), false(0, 1), ...
    false(0, 1), cell(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), false(0, 1), zeros(0, 1), ...
    VariableNames=["equivalence_class", "comparable_extractors", ...
    "comparable_extractor_key", "is_universally_comparable", ...
    "is_cross_pattern_comparable", "eligible_patterns", ...
    "eligible_pattern_count", "pattern_count", "comparability_scope", ...
    "canonical_unit", "is_readmitted_timing_class", "registered_pair_count"]);
end

function value = emptyMeasurements()
value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["detection_id", "equivalence_class", "value", "unit"]);
end

function value = emptyFeatures()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    false(0, 1), strings(0, 1), false(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    false(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["extractor_set_key", "extractor_set_label", ...
    "equivalence_class", "canonical_unit", "is_cross_pattern_comparable", ...
    "comparability_scope", "is_readmitted_timing_class", ...
    "pattern_population", "contributing_detections", "not_eligible", ...
    "not_measured", "missing_canonical_value", "non_finite", ...
    "coverage_fraction", "is_low_coverage", ...
    "coverage_label", "statistics_status", "minimum", "q25", "median", ...
    "q75", "maximum", "interquartile_range"]);
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:ReferenceIdentityMissing", ...
        "The reference configuration record is missing field(s): %s. Pass " + ...
        "a vawlume.eda.referenceConfiguration result.", ...
        strjoin(missingNames, ", "));
end
end
