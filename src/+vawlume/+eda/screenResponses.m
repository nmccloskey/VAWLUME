function result = screenResponses(conn, runResult, design, options)
%SCREENRESPONSES The response variables an executed screening probe produced.
%
% RESULT = vawlume.eda.SCREENRESPONSES(CONN, RUNRESULT, DESIGN) reads the
% analyses a probe applied and returns, per configuration and recording, the
% responses the screen is about: detections considered, pairwise match counts,
% agreement-group counts, EXACT extractor-support pattern counts, extractor-unique
% counts and fractions, ambiguous-group counts, and cross-configuration change
% measures.
%
% Name-value options:
%   BaselineConfigurationId   the configuration change measures compare against;
%                             defaults to the design's first run
%   IncludeChangeMeasures     default true
%
% EVERYTHING HERE IS RECOMPUTED FROM STORED ROWS, and nothing is persisted. The
% quantities come from the agreement layer's own query views through
% vawlume.agreement.selectPopulation and from the stored match-group topology;
% this function's contribution is probe-level assembly, not new arithmetic.
%
% EXACT SUPPORT PATTERNS ARE NEVER BINNED BY COARSE K. Two groups can both
% support 2 of 3 extractor pairs while supporting DIFFERENT pairs, and collapsing
% them would report agreement that was never observed. A coarse count accompanies
% the exact pattern as its own response and never replaces it.
%
% A PATTERN ABSENT FROM ONE CONFIGURATION IS AN EXPLICIT ZERO where a sibling
% configuration observed it. Effects are differences across configurations, so a
% missing row would silently become a gap and the difference would be computed
% against nothing. The pattern vocabulary is the union over the probe's
% configurations, and the zeros are filled.
%
% POOLING SUMS COUNTS AND RECOMPUTES FRACTIONS FROM POOLED COUNTS. A matched
% fraction pooled by averaging per-recording fractions is a different quantity,
% and the difference grows with unequal recording sizes. Effects are estimated on
% the pooled response, so the rule propagates straight into the screen's headline
% numbers. Every fraction row carries its denominator.
%
% Nothing here names an extractor or assumes how many there are: support
% patterns, extractor keys and pair keys all come from the database.
%
% This function reads. It writes nothing, and it computes no effect estimate - a
% response and an effect are separate contracts, and the effect layer consumes
% this one.

arguments
    conn
    runResult (1,1) struct
    design (1,1) struct
    options.BaselineConfigurationId (1,1) string = ""
    options.IncludeChangeMeasures (1,1) logical = true
end

requireFields(runResult, ["manifest", "exploration_run_key"]);
requireFields(design, ["configurations", "factors"]);

units = usableUnits(runResult);
configurations = orderedConfigurations(design, units);
baseline = resolveBaseline(configurations, options);

perRecording = emptyResponses();
groupMembers = containers.Map("KeyType", "char", "ValueType", "any");

for index = 1:height(units)
    unit = units(index, :);
    [rows, members] = responsesForUnit(conn, runResult, unit);
    perRecording = [perRecording; rows]; %#ok<AGROW>
    groupMembers(memberKey(unit.configuration_id, unit.recording_id)) = members;
end

perRecording = [perRecording; matchingResponses(conn, runResult, units)];

if options.IncludeChangeMeasures && strlength(baseline) > 0
    perRecording = [perRecording; changeResponses(groupMembers, units, ...
        baseline)];
end

perRecording = zeroFill(perRecording, configurations, units);
pooled = poolAcrossRecordings(perRecording);
responses = [perRecording; pooled];
responses = attachFactorCoding(responses, design);
responses = sortrows(responses, ["response", "qualifier", "secondary", ...
    "configuration_id", "scope", "recording_id"]);

result = struct( ...
    status="summarized", ...
    exploration_run_key=runResult.exploration_run_key, ...
    configuration_ids=configurations', ...
    baseline_configuration_id=baseline, ...
    recording_ids=unique(units.recording_id)', ...
    responses=responses, ...
    wide=wideView(responses, configurations), ...
    response_vocabulary=edaResponseVocabulary(), ...
    change_class_vocabulary=edaChangeClasses()', ...
    support_pattern_vocabulary=patternVocabulary(perRecording), ...
    key_columns=["configuration_id", "recording_id", "scope", "response", ...
        "qualifier_kind", "qualifier", "secondary_kind", "secondary"], ...
    pooling_rule="counts are summed across recordings; every fraction is " + ...
        "recomputed from pooled numerator and denominator, never averaged " + ...
        "from per-recording fractions", ...
    zero_fill_rule="the response vocabulary is the union over the probe's " + ...
        "configurations, and a combination absent from one configuration is " + ...
        "an explicit zero rather than a missing row", ...
    design_completeness=completenessOf(runResult), ...
    caution=edaCautionNote());
end

% ------------------------------------------------------------ unit reading ---

function [rows, members] = responsesForUnit(conn, ~, unit)
%RESPONSESFORUNIT Every agreement-derived response for one configuration-recording.
%
% The groups and their members come from vawlume.agreement.selectPopulation,
% which reads the agreement layer's own query views. Re-deriving support
% patterns, completeness or ambiguity here would be a second definition of
% quantities the view already computes.
population = vawlume.agreement.selectPopulation(conn, ...
    struct(analysis_run_id=unit.analysis_run_id));
groups = population.groups;
rows = emptyResponses();
members = memberSets(population);

total = height(groups);
rows(end + 1, :) = row(unit, "agreement_groups_total", "", "", "", "", ...
    total, NaN, "count");

rows = [rows; countsBy(unit, "agreement_groups_by_member_count", ...
    "member_count", string(groups.member_count))];
rows = [rows; countsBy(unit, "agreement_groups_by_extractor_count", ...
    "extractor_count", string(groups.extractor_count))];

% The exact pattern, verbatim from the view. An empty pattern means the group
% supports no extractor pair at all, which is what an extractor-unique detection
% looks like, and it is kept as its own named category rather than dropped.
patterns = groups.supported_extractor_pair_pattern;
patterns(strlength(patterns) == 0) = "(none)";
rows = [rows; countsBy(unit, "support_pattern_groups", "support_pattern", ...
    patterns)];
rows = [rows; fractionsBy(unit, "support_pattern_fraction", ...
    "support_pattern", patterns, total)];

% A coarse k-of-N count accompanies the exact pattern; it never replaces it.
rows = [rows; countsBy(unit, "coarse_support_groups", ...
    "supported_pair_count", string(groups.supported_extractor_pair_count))];

rows(end + 1, :) = row(unit, "ambiguous_groups", "", "", "", "", ...
    nnz(strlength(groups.ambiguous_pairwise_topology_pattern) > 0), NaN, ...
    "count");
rows(end + 1, :) = row(unit, "unambiguous_one_to_one_groups", "", "", "", ...
    "", nnz(groups.is_unambiguous_one_to_one), NaN, "count");

[uniqueRows, detections] = extractorUniqueResponses(conn, unit, groups, ...
    population);
rows = [rows; uniqueRows];
rows = [rows; detections];
end

function [rows, detectionRows] = extractorUniqueResponses(conn, unit, groups, ...
    population)
%EXTRACTORUNIQUERESPONSES Groups only one extractor contributed to, and the denominator.
%
% An extractor-unique group is evidence that one system detected something the
% others did not. It is NOT evidence that the detection is false: the evidential
% relationship is asymmetric, and the count is reported as an observation about
% the extractor set rather than as a defect count.
considered = detectionsConsidered(conn, unit);
rows = emptyResponses();
detectionRows = emptyResponses();
for index = 1:height(considered)
    key = considered.extractor_key(index);
    denominator = considered.detection_count(index);
    detectionRows(end + 1, :) = row(unit, "detections_considered", ...
        "extractor_key", key, "", "", denominator, NaN, "count"); %#ok<AGROW>
    selected = groups.is_extractor_unique & groups.extractor_set_key == key;
    count = nnz(selected);
    rows(end + 1, :) = row(unit, "extractor_unique_groups", ...
        "extractor_key", key, "", "", count, NaN, "count"); %#ok<AGROW>
    rows(end + 1, :) = row(unit, "extractor_unique_fraction", ...
        "extractor_key", key, "", "", fraction(count, denominator), ...
        denominator, "fraction"); %#ok<AGROW>
end
if height(population.members) == 0
    return
end
end

function value = detectionsConsidered(conn, unit)
%DETECTIONSCONSIDERED The denominator, per extractor, stated rather than implied.
rows = fetch(conn, "SELECT e.extractor_key, (SELECT COUNT(*) FROM detections d " + ...
    "WHERE d.extraction_run_id=ari.extraction_run_id AND d.recording_id=" + ...
    string(unit.recording_id) + ") AS detection_count " + ...
    "FROM analysis_run_extraction_inputs ari " + ...
    "JOIN extraction_runs er ON er.extraction_run_id=ari.extraction_run_id " + ...
    "JOIN extractor_versions ev " + ...
    "ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE ari.analysis_run_id=" + string(unit.analysis_run_id) + ...
    " ORDER BY e.extractor_key");
value = table(edaPresentText(rows.extractor_key), ...
    double(rows.detection_count), ...
    VariableNames=["extractor_key", "detection_count"]);
end

function rows = matchingResponses(conn, runResult, units)
%MATCHINGRESPONSES Pairwise topology counts, read from the stored match groups.
%
% match_groups.match_type is the topology the matcher assigned and stored. Taking
% it from there is reading stored evidence, not recomputing it: deriving topology
% again from candidate_pairs would be a second definition of a classification the
% assignment layer already made.
rows = emptyResponses();
manifest = runResult.manifest;
matching = manifest(manifest.unit_kind == "matching" & ...
    ismember(manifest.status, ["committed", "reused"]), :);
for index = 1:height(matching)
    unit = matching(index, :);
    if ~any(units.configuration_id == unit.configuration_id & ...
            units.recording_id == unit.recording_id)
        continue
    end
    counts = fetch(conn, "SELECT match_type, COUNT(*) AS n FROM match_groups " + ...
        "WHERE analysis_run_id=" + string(unit.analysis_run_id) + ...
        " GROUP BY match_type ORDER BY match_type");
    for row_index = 1:height(counts)
        rows(end + 1, :) = row(unit, "pairwise_match_groups", ...
            "extractor_pair_key", unit.extractor_pair_key, "match_type", ...
            edaPresentText(counts.match_type(row_index)), ...
            double(counts.n(row_index)), NaN, "count"); %#ok<AGROW>
    end
end
end

% ------------------------------------------------------------ change measures ---

function rows = changeResponses(groupMembers, units, baseline)
rows = emptyResponses();
recordings = unique(units.recording_id);
for recordingIndex = 1:numel(recordings)
    recordingId = recordings(recordingIndex);
    baselineKey = memberKey(baseline, recordingId);
    if ~isKey(groupMembers, baselineKey)
        continue
    end
    from = groupMembers(baselineKey);
    selected = units(units.recording_id == recordingId, :);
    for index = 1:height(selected)
        unit = selected(index, :);
        to = groupMembers(memberKey(unit.configuration_id, recordingId));
        change = vawlume.eda.groupChanges(from, to, ...
            RequireSamePopulation=true);
        for classIndex = 1:height(change.counts)
            className = change.counts.change_class(classIndex);
            rows(end + 1, :) = row(unit, "group_change_from", ...
                "change_class", className, "baseline_configuration_id", ...
                baseline, change.counts.from_side(classIndex), NaN, ...
                "count"); %#ok<AGROW>
            rows(end + 1, :) = row(unit, "group_change_to", ...
                "change_class", className, "baseline_configuration_id", ...
                baseline, change.counts.to_side(classIndex), NaN, ...
                "count"); %#ok<AGROW>
        end
        rows(end + 1, :) = row(unit, "group_retention_fraction", "", "", ...
            "baseline_configuration_id", baseline, ...
            fraction(change.retained_group_count, change.from_group_count), ...
            change.from_group_count, "fraction"); %#ok<AGROW>
    end
end
end

% ------------------------------------------------------- shaping and pooling ---

function value = zeroFill(rows, configurations, units)
%ZEROFILL A combination one configuration observed is an explicit zero in the rest.
%
% Without this a support pattern seen only at the loose end of a factor would
% have no row at the strict end, and the difference of means that estimates the
% factor's effect would be computed over a shorter vector - silently, and in the
% direction that understates the effect.
if height(rows) == 0
    value = rows;
    return
end
counts = rows(rows.value_kind == "count", :);
identities = unique(counts(:, ["response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary"]), "rows");
recordings = unique(units.recording_id);
existing = counts.response + "|" + counts.qualifier + "|" + ...
    counts.secondary + "|" + counts.configuration_id + "|" + ...
    string(counts.recording_id);

additions = emptyResponses();
for index = 1:height(identities)
    identity = identities(index, :);
    for configurationIndex = 1:numel(configurations)
        configurationId = configurations(configurationIndex);
        for recordingIndex = 1:numel(recordings)
            recordingId = recordings(recordingIndex);
            if ~any(units.configuration_id == configurationId & ...
                    units.recording_id == recordingId)
                continue
            end
            key = identity.response + "|" + identity.qualifier + "|" + ...
                identity.secondary + "|" + configurationId + "|" + ...
                string(recordingId);
            if any(existing == key)
                continue
            end
            unit = table(configurationId, recordingId, ...
                VariableNames=["configuration_id", "recording_id"]);
            unit.exploration_run_key = rows.exploration_run_key(1);
            additions(end + 1, :) = row(unit, identity.response, ...
                identity.qualifier_kind, identity.qualifier, ...
                identity.secondary_kind, identity.secondary, 0, NaN, ...
                "count"); %#ok<AGROW>
        end
    end
end
value = [rows; additions];
end

function value = poolAcrossRecordings(rows)
%POOLACROSSRECORDINGS Sum counts; recompute every fraction from pooled counts.
%
% A fraction is never averaged across recordings. The mean of per-recording
% fractions and the fraction of pooled counts are different quantities, and they
% diverge exactly when recordings differ in size - which is the normal case. The
% effect estimates are computed on these pooled values, so choosing the wrong
% rule here would move the screen's headline numbers rather than a footnote.
value = emptyResponses();
if height(rows) == 0
    return
end
counts = rows(rows.value_kind == "count", :);
fractions = rows(rows.value_kind == "fraction", :);

value = [value; poolCounts(counts)];
value = [value; poolFractions(fractions)];
end

function value = poolCounts(counts)
value = emptyResponses();
if height(counts) == 0
    return
end
[keys, ~, grouping] = unique(counts(:, ["exploration_run_key", ...
    "configuration_id", "response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary"]), "rows");
totals = accumarray(grouping, counts.value);
for index = 1:height(keys)
    value(end + 1, :) = pooledRow(keys(index, :), totals(index), NaN, ...
        "count"); %#ok<AGROW>
end
end

function value = poolFractions(fractions)
value = emptyResponses();
if height(fractions) == 0
    return
end
[keys, ~, grouping] = unique(fractions(:, ["exploration_run_key", ...
    "configuration_id", "response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary"]), "rows");
denominators = accumarray(grouping, fractions.denominator, [], @sum, NaN);
numerators = accumarray(grouping, ...
    fractions.value .* fractions.denominator, [], @sum, NaN);
for index = 1:height(keys)
    value(end + 1, :) = pooledRow(keys(index, :), ...
        fraction(numerators(index), denominators(index)), ...
        denominators(index), "fraction"); %#ok<AGROW>
end
end

function value = attachFactorCoding(rows, design)
%ATTACHFACTORCODING Each row carries the design point it came from.
%
% Denormalized deliberately. A consumer filtering the long table for one response
% should not have to join back to the design to know which factor level produced
% each value, and the effect layer reads the coding straight off these rows.
names = design.factors.factor_name;
configurations = design.configurations;
for index = 1:numel(names)
    values = NaN(height(rows), 1);
    levels = strings(height(rows), 1);
    for configurationIndex = 1:height(configurations)
        selected = rows.configuration_id == ...
            configurations.configuration_id(configurationIndex);
        values(selected) = configurations.(names(index))(configurationIndex);
        levels(selected) = ...
            configurations.(names(index) + "_level")(configurationIndex);
    end
    rows.(names(index)) = values;
    rows.(names(index) + "_level") = levels;
end
value = rows;
end

function value = wideView(responses, configurations)
%WIDEVIEW One row per configuration, for a human rather than for a filter.
%
% Derived from the long form rather than computed alongside it, so the two cannot
% disagree. Only pooled scalar responses appear: a wide table cannot hold a
% qualifier without gaining a column per qualifier value, which is exactly the
% growth the long form exists to avoid.
pooled = responses(responses.scope == "pooled" & ...
    responses.qualifier_kind == "" & responses.secondary_kind == "", :);
value = table(configurations(:), VariableNames="configuration_id");
names = unique(pooled.response);
for index = 1:numel(names)
    column = NaN(numel(configurations), 1);
    for configurationIndex = 1:numel(configurations)
        selected = pooled.response == names(index) & ...
            pooled.configuration_id == configurations(configurationIndex);
        if any(selected)
            column(configurationIndex) = pooled.value(find(selected, 1));
        end
    end
    value.(names(index)) = column;
end
end

% ---------------------------------------------------------------- plumbing ---

function value = usableUnits(runResult)
manifest = runResult.manifest;
value = manifest(manifest.unit_kind == "agreement" & ...
    ismember(manifest.status, ["committed", "reused"]), :);
if height(value) == 0
    error("vawlume:eda:NoUsableAgreementAnalyses", ...
        "The run manifest holds no committed or reused agreement analysis, " + ...
        "so there is nothing to summarize. A dry run produces no responses.");
end
end

function value = orderedConfigurations(design, units)
value = design.configurations.configuration_id;
value = value(ismember(value, unique(units.configuration_id)));
end

function value = resolveBaseline(configurations, options)
if strlength(options.BaselineConfigurationId) > 0
    value = options.BaselineConfigurationId;
    if ~ismember(value, configurations)
        error("vawlume:eda:BaselineConfigurationNotPresent", ...
            "Baseline configuration '%s' is not among the probe's executed " + ...
            "configurations.", value);
    end
    return
end
if isempty(configurations)
    value = "";
    return
end
value = configurations(1);
end

function value = memberSets(population)
value = {};
groups = population.groups;
members = population.members;
for index = 1:height(groups)
    selected = members.detection_id(members.agreement_group_id == ...
        groups.agreement_group_id(index));
    value{end + 1, 1} = double(selected(:))'; %#ok<AGROW>
end
end

function value = memberKey(configurationId, recordingId)
value = char(string(configurationId) + "#" + string(recordingId));
end

function value = countsBy(unit, response, qualifierKind, values)
value = emptyResponses();
if isempty(values)
    return
end
categories = unique(values);
for index = 1:numel(categories)
    value(end + 1, :) = row(unit, response, qualifierKind, ...
        categories(index), "", "", nnz(values == categories(index)), NaN, ...
        "count"); %#ok<AGROW>
end
end

function value = fractionsBy(unit, response, qualifierKind, values, denominator)
value = emptyResponses();
if isempty(values)
    return
end
categories = unique(values);
for index = 1:numel(categories)
    value(end + 1, :) = row(unit, response, qualifierKind, ...
        categories(index), "", "", ...
        fraction(nnz(values == categories(index)), denominator), ...
        denominator, "fraction"); %#ok<AGROW>
end
end

function value = fraction(numerator, denominator)
if ~isfinite(denominator) || denominator == 0
    value = NaN;
    return
end
value = numerator / denominator;
end

function value = row(unit, response, qualifierKind, qualifier, ...
    secondaryKind, secondary, measurement, denominator, valueKind)
value = {string(unit.exploration_run_key), string(unit.configuration_id), ...
    double(unit.recording_id), "recording", string(response), ...
    string(qualifierKind), string(qualifier), string(secondaryKind), ...
    string(secondary), double(measurement), double(denominator), ...
    string(valueKind)};
end

function value = pooledRow(key, measurement, denominator, valueKind)
value = {key.exploration_run_key, key.configuration_id, NaN, "pooled", ...
    key.response, key.qualifier_kind, key.qualifier, key.secondary_kind, ...
    key.secondary, double(measurement), double(denominator), ...
    string(valueKind)};
end

function value = patternVocabulary(rows)
selected = rows(rows.response == "support_pattern_groups", :);
value = unique(selected.qualifier)';
end

function value = completenessOf(runResult)
value = struct(is_complete=false, note="not reported by the run result");
if isfield(runResult, "design_completeness")
    value = runResult.design_completeness;
end
end

function value = emptyResponses()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["exploration_run_key", "configuration_id", ...
    "recording_id", "scope", "response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary", "value", "denominator", "value_kind"]);
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:ResponseInputInvalid", ...
        "A required input is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
