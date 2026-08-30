function feature = consilienceFeatureAgreement(conn, analysis, specification)
%CONSILIENCEFEATUREAGREEMENT Registry-driven feature discovery and comparison.
%
% Pairings come from v_cross_extractor_feature_pairs, which joins
% feature_relationships to both extractors' registered features. Nothing here
% matches on canonical_name, and nothing here contains a feature name literal:
% the pair set is data, so registering another eligible relationship extends the
% comparison without a code change.

pairs = discoverPairs(conn, analysis, specification);
[comparisons, excluded] = comparePairs(conn, analysis, pairs);
summary = aggregate(comparisons, specification);
feature = struct(pairs=pairs, comparisons=comparisons, ...
    summary=summary, excluded_groups=excluded);
end

function pairs = discoverPairs(conn, analysis, specification)
% The view keeps registry NULLs faithfully, so every nullable text column is
% normalized here rather than in the view. MATLAB's SQLite fetch cannot return a
% NULL text column at all, so this is required, not stylistic.
rows = fetch(conn, "SELECT feature_relationship_id, relationship_type, " + ...
    "consilience_eligible, " + ...
    "IFNULL(comparison_method,'') AS comparison_method, " + ...
    "IFNULL(unit_normalization,'') AS unit_normalization, " + ...
    textColumns("a") + ", " + textColumns("b") + " " + ...
    "FROM v_cross_extractor_feature_pairs");
pairs = emptyPairs();
if height(rows) == 0
    return
end
names = [analysis.run_a.extractor_name, analysis.run_b.extractor_name];
for index = 1:height(rows)
    row = rows(index, :);
    aName = presentText(row.extractor_a_name);
    bName = presentText(row.extractor_b_name);
    if ~all(ismember([aName, bName], names))
        continue
    end
    % feature_a / feature_b follow the schema's ascending-id CHECK, which says
    % nothing about which extractor is run_a. Orient by extractor identity.
    if aName == analysis.run_a.extractor_name
        [runA, runB] = deal(sideOf(row, "a"), sideOf(row, "b"));
    else
        [runA, runB] = deal(sideOf(row, "b"), sideOf(row, "a"));
    end
    equivalenceClass = resolveEquivalenceClass(runA, runB, row);
    unitStatus = unitCompatibility(runA, runB);
    eligible = double(row.consilience_eligible(1)) == 1;
    isPrimaryTemporal = ismember(equivalenceClass, ...
        specification.primary_temporal_classes);
    pairs(end + 1, :) = { ...
        double(row.feature_relationship_id(1)), equivalenceClass, ...
        presentText(row.relationship_type(1)), eligible, ...
        isPrimaryTemporal, eligible && unitStatus == "compatible", ...
        unitStatus, presentText(row.comparison_method(1)), ...
        runA.extractor_name, runA.feature_id, runA.native_name, ...
        runA.canonical_name, runA.canonical_unit, runA.derivation_stage, ...
        runA.operational_variant, ...
        runB.extractor_name, runB.feature_id, runB.native_name, ...
        runB.canonical_name, runB.canonical_unit, runB.derivation_stage, ...
        runB.operational_variant, ...
        toleranceFor(specification, equivalenceClass)}; %#ok<AGROW>
end
if height(pairs) > 0
    pairs = sortrows(pairs, ["equivalence_class", "feature_relationship_id"]);
end
end

function value = textColumns(letter)
names = ["extractor_" + letter + "_name", ...
    "feature_" + letter + "_native_name", ...
    "feature_" + letter + "_canonical_name", ...
    "feature_" + letter + "_canonical_unit", ...
    "feature_" + letter + "_derivation_stage", ...
    "feature_" + letter + "_operational_variant", ...
    "feature_" + letter + "_equivalence_class"];
value = "feature_" + letter + "_id";
for name = names
    value = value + ", IFNULL(" + name + ",'') AS " + name;
end
end

function side = sideOf(row, letter)
side = struct( ...
    extractor_name=presentText(row.("extractor_" + letter + "_name")(1)), ...
    feature_id=double(row.("feature_" + letter + "_id")(1)), ...
    native_name=presentText(row.("feature_" + letter + "_native_name")(1)), ...
    canonical_name=presentText(row.("feature_" + letter + "_canonical_name")(1)), ...
    canonical_unit=presentText(row.("feature_" + letter + "_canonical_unit")(1)), ...
    derivation_stage=presentText(row.("feature_" + letter + "_derivation_stage")(1)), ...
    operational_variant=presentText(row.("feature_" + letter + "_operational_variant")(1)), ...
    equivalence_class=presentText(row.("feature_" + letter + "_equivalence_class")(1)));
end

function value = resolveEquivalenceClass(runA, runB, row)
if runA.equivalence_class == runB.equivalence_class
    value = runA.equivalence_class;
    return
end
% A registered relationship whose two features disagree on equivalence class is
% legal and informative: it is exactly how the power-like relationships are
% recorded. Report both rather than picking one.
value = runA.equivalence_class + "|" + runB.equivalence_class;
if strlength(strtrim(replace(value, "|", ""))) == 0
    value = "unclassified_relationship_" + string(row.feature_relationship_id(1));
end
end

function status = unitCompatibility(runA, runB)
if strlength(runA.canonical_unit) == 0 || strlength(runB.canonical_unit) == 0
    status = "unit_unknown";
elseif runA.canonical_unit == runB.canonical_unit
    status = "compatible";
else
    status = "incompatible";
end
end

function value = toleranceFor(specification, equivalenceClass)
value = NaN;
tolerances = specification.tolerances;
if height(tolerances) == 0
    return
end
selected = tolerances.equivalence_class == equivalenceClass;
if any(selected)
    value = tolerances.relative_tolerance(find(selected, 1));
end
end

function [comparisons, excluded] = comparePairs(conn, analysis, pairs)
comparisons = emptyComparisons();
excluded = emptyExcluded();
groups = fetch(conn, "SELECT mg.match_group_id, mg.match_type " + ...
    "FROM match_groups mg WHERE mg.analysis_run_id=" + ...
    string(analysis.analysis_run_id) + " ORDER BY mg.match_group_id");
if height(groups) == 0
    return
end
members = fetch(conn, "SELECT mgm.match_group_id, mgm.detection_id, " + ...
    "IFNULL(mgm.member_role,'') AS member_role FROM match_group_members mgm " + ...
    "JOIN match_groups mg ON mg.match_group_id=mgm.match_group_id " + ...
    "WHERE mg.analysis_run_id=" + string(analysis.analysis_run_id));
memberRoles = presentText(members.member_role);
matchTypes = presentText(groups.match_type);

eligiblePairs = pairs;
if height(eligiblePairs) > 0
    eligiblePairs = eligiblePairs(eligiblePairs.comparison_eligible, :);
end

for index = 1:height(groups)
    groupId = groups.match_group_id(index);
    matchType = matchTypes(index);
    if matchType ~= "one_to_one"
        excluded(end + 1, :) = {groupId, matchType, exclusionReason(matchType)}; %#ok<AGROW>
        continue
    end
    selected = members.match_group_id == groupId;
    detectionA = members.detection_id(selected & memberRoles == "run_a");
    detectionB = members.detection_id(selected & memberRoles == "run_b");
    for pairIndex = 1:height(eligiblePairs)
        pair = eligiblePairs(pairIndex, :);
        valueA = canonicalValue(conn, detectionA, pair.feature_a_id);
        valueB = canonicalValue(conn, detectionB, pair.feature_b_id);
        [status, signedDifference, absoluteDifference, relativeDifference, ...
            pairMean, withinTolerance] = compareValues(valueA, valueB, ...
            pair.relative_tolerance);
        comparisons(end + 1, :) = { ...
            groupId, matchType, pair.equivalence_class, ...
            pair.relationship_type, pair.feature_relationship_id, ...
            detectionA, pair.extractor_a_name, pair.feature_a_id, ...
            pair.feature_a_native_name, pair.feature_a_canonical_name, ...
            pair.feature_a_operational_variant, valueA, ...
            detectionB, pair.extractor_b_name, pair.feature_b_id, ...
            pair.feature_b_native_name, pair.feature_b_canonical_name, ...
            pair.feature_b_operational_variant, valueB, ...
            pair.feature_a_canonical_unit, signedDifference, ...
            absoluteDifference, relativeDifference, pairMean, ...
            pair.relative_tolerance, withinTolerance, status, ...
            pair.primary_temporal_evidence}; %#ok<AGROW>
    end
end
end

function reason = exclusionReason(matchType)
if matchType == "unmatched"
    reason = "not_computed_unmatched";
else
    reason = "not_computed_split_merge";
end
end

function value = canonicalValue(conn, detectionId, featureId)
value = NaN;
if isempty(detectionId) || isempty(featureId)
    return
end
rows = fetch(conn, "SELECT em.native_value_type, " + ...
    "IFNULL(em.canonical_value_real, 1e308) AS canonical_value_real " + ...
    "FROM event_measurements em WHERE em.detection_id=" + ...
    string(detectionId(1)) + " AND em.extractor_feature_id=" + ...
    string(featureId(1)));
if height(rows) ~= 1
    return
end
if presentText(rows.native_value_type(1)) == "missing"
    return
end
candidate = double(rows.canonical_value_real(1));
if candidate < 1e307
    value = candidate;
end
end

function [status, signedDifference, absoluteDifference, relativeDifference, ...
    pairMean, withinTolerance] = compareValues(valueA, valueB, tolerance)
signedDifference = NaN;
absoluteDifference = NaN;
relativeDifference = NaN;
pairMean = NaN;
withinTolerance = NaN;
if isnan(valueA) || isnan(valueB)
    % A measurement one extractor never exported is absent evidence. Scoring it
    % as disagreement would manufacture a discrepancy out of a missing column.
    status = "not_computed_missing_measurement";
    return
end
status = "computed";
signedDifference = valueB - valueA;
absoluteDifference = abs(signedDifference);
pairMean = (valueA + valueB) / 2;

% Relative difference is reported only where the specification declares a
% relative tolerance for that equivalence class, which is its statement that
% proportional comparison is the intended rule there. It is deliberately not
% universal: an onset at 10.000 s versus 10.004 s differs by 0.04% only because
% the recording happens to start where it does, and that number would say
% nothing about boundary agreement.
if isnan(tolerance)
    return
end
if pairMean == 0
    return
end
relativeDifference = absoluteDifference / abs(pairMean);
withinTolerance = double(relativeDifference <= tolerance);
end

function summary = aggregate(comparisons, specification)
summary = emptySummary();
if height(comparisons) == 0
    return
end
computed = comparisons(comparisons.status == "computed", :);
classes = unique(computed.equivalence_class);
for index = 1:numel(classes)
    selected = computed(computed.equivalence_class == classes(index), :);
    signed = selected.signed_difference;
    absolute = selected.absolute_difference;
    n = numel(signed);
    [correlationKind, correlation] = association(selected, ...
        specification.secondary_minimum_n);
    summary(end + 1, :) = {classes(index), ...
        selected.relationship_type(1), selected.feature_a_id(1), ...
        selected.feature_b_id(1), selected.canonical_unit(1), n, ...
        mean(signed), median(signed), mean(absolute), median(absolute), ...
        standardDeviation(signed), interquartileRange(absolute), ...
        min(signed), max(signed), correlationKind, correlation, ...
        nnz(selected.within_tolerance == 0), ...
        nnz(isnan(selected.within_tolerance)), ...
        selected.primary_temporal_evidence(1)}; %#ok<AGROW>
end
if height(summary) > 0
    summary = sortrows(summary, "equivalence_class");
end
end

function [kind, value] = association(selected, minimumN)
%ASSOCIATION Secondary characterization only, and only when N supports it.
%
% Correlation over a handful of synthetic pairs describes the fixture, not the
% extractors. Below the specification's minimum it is deliberately not computed
% rather than reported with a caveat nobody reads.
kind = "not_computed_insufficient_n";
value = NaN;
if height(selected) < minimumN
    return
end
a = selected.value_a;
b = selected.value_b;
if numel(unique(a)) < 2 || numel(unique(b)) < 2
    kind = "not_computed_no_variance";
    return
end
kind = "pearson";
correlation = corrcoef(a, b);
value = correlation(1, 2);
end

function value = standardDeviation(values)
if numel(values) < 2
    value = NaN;
    return
end
value = std(values);
end

function value = interquartileRange(values)
if numel(values) < 2
    value = NaN;
    return
end
quartiles = prctile(values, [25 75]);
value = quartiles(2) - quartiles(1);
end

function value = emptyPairs()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), false(0, 1), ...
    false(0, 1), false(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), zeros(0, 1), ...
    VariableNames=["feature_relationship_id", "equivalence_class", ...
    "relationship_type", "consilience_eligible", "primary_temporal_evidence", ...
    "comparison_eligible", "unit_status", "comparison_method", ...
    "extractor_a_name", "feature_a_id", "feature_a_native_name", ...
    "feature_a_canonical_name", "feature_a_canonical_unit", ...
    "feature_a_derivation_stage", "feature_a_operational_variant", ...
    "extractor_b_name", "feature_b_id", "feature_b_native_name", ...
    "feature_b_canonical_name", "feature_b_canonical_unit", ...
    "feature_b_derivation_stage", "feature_b_operational_variant", ...
    "relative_tolerance"]);
end

function value = emptyComparisons()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), strings(0, 1), false(0, 1), ...
    VariableNames=["match_group_id", "match_type", "equivalence_class", ...
    "relationship_type", "feature_relationship_id", ...
    "detection_a_id", "extractor_a_name", "feature_a_id", ...
    "feature_a_native_name", "feature_a_canonical_name", ...
    "feature_a_operational_variant", "value_a", ...
    "detection_b_id", "extractor_b_name", "feature_b_id", ...
    "feature_b_native_name", "feature_b_canonical_name", ...
    "feature_b_operational_variant", "value_b", ...
    "canonical_unit", "signed_difference", "absolute_difference", ...
    "relative_difference", "pair_mean", "relative_tolerance", ...
    "within_tolerance", "status", "primary_temporal_evidence"]);
end

function value = emptyExcluded()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["match_group_id", "match_type", "reason"]);
end

function value = emptySummary()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
    VariableNames=["equivalence_class", "relationship_type", "feature_a_id", ...
    "feature_b_id", "canonical_unit", "n_pairs", "mean_signed_bias", ...
    "median_signed_bias", "mean_absolute_difference", ...
    "median_absolute_difference", "std_signed_bias", ...
    "iqr_absolute_difference", "minimum_signed", "maximum_signed", ...
    "association_kind", "association_value", "outside_tolerance_count", ...
    "tolerance_not_applicable_count", "primary_temporal_evidence"]);
end

function value = presentText(value)
value = string(value);
value(ismissing(value)) = "";
end
