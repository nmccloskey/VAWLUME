function result = edaFeatureDiscrepancy(conn, analysis, rows, repoRoot)
%EDAFEATUREDISCREPANCY Feature discrepancies and their coverage, per candidate row.
%
% Discrepancies come from vawlume.consilience.summarize's feature_comparisons.
% They are not recomputed by a fresh join. That function's docstring records
% that eligible pairs are discovered only through the registry - equivalence
% class plus feature_relationships with consilience_eligible - because a shared
% canonical name is neither necessary nor sufficient. Calling it inherits that
% discipline; reimplementing the join would quietly lose it.
%
% The value carried is the ABSOLUTE difference. A discrepancy is a magnitude, so
% it needs no direction, which keeps the feature half of the surface free of the
% sign-convention problem the temporal half has to resolve explicitly.
%
% RESULT.values is one column per eligible equivalence class, aligned to ROWS.
% RESULT.status is the matching coverage category for each of those cells, and
% is the only place the four-plus-one distinction is recorded per row:
%
%   supported                 computed and finite
%   not_measured              eligible, but one extractor exported no value
%   non_finite                computed but NaN or Inf
%   not_comparable_topology   the pair's match group is not one_to_one, so the
%                             specification never attempted the comparison
%   not_eligible              this extractor pair registers no eligible
%                             relationship for that equivalence class
%
% not_comparable_topology is the fifth category. The matching specification
% restricts feature comparison to one_to_one groups because averaging two MUPET
% syllables against one DeepSqueak call would need an aggregation model that
% does not exist, so a split, merge or many-to-many group yields no comparison
% at all. That is a different fact from an unregistered feature pair and a
% different fact from an unexported measurement, and collapsing it into either
% would misreport why a column is thin.

report = vawlume.consilience.summarize(conn, ...
    struct(analysis_run_id=analysis.analysis_run_id), RepoRoot=repoRoot);
[classes, primaryTemporal] = eligibleClasses(report.feature_pairs);
result = struct(classes=classes, primary_temporal=primaryTemporal, ...
    values=[], status=strings(height(rows), 0));
if isempty(classes)
    result.values = NaN(height(rows), 0);
    return
end

values = NaN(height(rows), numel(classes));
status = repmat("not_comparable_topology", height(rows), numel(classes));
rowIndex = pairIndex(rows.detection_a_id, rows.detection_b_id);

comparisons = report.feature_comparisons;
if height(comparisons) > 0
    comparisonKeys = pairIndex(comparisons.detection_a_id, ...
        comparisons.detection_b_id);
    for classIndex = 1:numel(classes)
        selected = comparisons.equivalence_class == classes(classIndex);
        if ~any(selected)
            continue
        end
        keys = comparisonKeys(selected);
        [found, where] = ismember(keys, rowIndex);
        if ~all(found)
            error("vawlume:eda:FeatureComparisonUnanchored", ...
                "Matching analysis '%s' reports a feature comparison for a " + ...
                "detection pair that has no stored candidate row.", ...
                analysis.matching_run_key);
        end
        absolute = double(comparisons.absolute_difference(selected));
        states = edaPresentText(comparisons.status(selected));
        cellStatus = repmat("non_finite", numel(where), 1);
        cellStatus(states == "not_computed_missing_measurement") = "not_measured";
        finite = states == "computed" & isfinite(absolute);
        cellStatus(finite) = "supported";
        values(where, classIndex) = absolute;
        status(where, classIndex) = cellStatus;
    end
end

result.values = values;
result.status = status;
end

function [classes, primaryTemporal] = eligibleClasses(pairs)
%ELIGIBLECLASSES Equivalence classes this extractor pair can actually compare.
%
% comparison_eligible is the registry's own conjunction of consilience
% eligibility and canonical-unit compatibility. A class absent from this list is
% not_eligible for every row of this analysis, which for the pilot set is how
% band edges behave on any pair containing USVSEG.
%
% primaryTemporal marks a class the matching specification reserves as primary
% temporal evidence - start time, end time, duration. Those are excluded from
% the consilience support rule so temporal evidence is not double-counted when
% classifying correspondence, and a discrepancy on one is a different quantity
% from the same-named stored candidate metric: this is the extractor's own
% exported measurement, while the candidate column is derived from stored
% detection boundaries. Both are reported, and the flag says which is which so
% the dependency layer does not read their agreement as a coincidence.
classes = strings(0, 1);
primaryTemporal = false(0, 1);
if height(pairs) == 0
    return
end
selected = pairs(logical(pairs.comparison_eligible), :);
if height(selected) == 0
    return
end
names = edaPresentText(selected.equivalence_class);
keep = strlength(names) > 0;
names = names(keep);
flags = logical(selected.primary_temporal_evidence(keep));
[classes, first] = unique(names);
primaryTemporal = flags(first);
end

function keys = pairIndex(first, second)
%PAIRINDEX An order-free key for one unordered detection pair.
%
% candidate_pairs orders its two columns by detection id; feature_comparisons
% orders its two by the caller's run roles. Joining them requires a key that
% does not depend on either ordering.
lower = min(double(first), double(second));
upper = max(double(first), double(second));
keys = string(lower) + "-" + string(upper);
end
