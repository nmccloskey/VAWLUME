function decision = edaStratumQualification(fields, thresholds)
%EDASTRATUMQUALIFICATION Decide automatically which stratum fields are usable.
%
% DECISION = EDASTRATUMQUALIFICATION(FIELDS, THRESHOLDS) adds `qualifies`,
% `rejection_reason` and `is_selected` to a vawlume.eda.resolveStrata field
% summary. Contract §I fixes the first three rules; the fourth is added here and
% is flagged in the Part 9 handoff as a contract gap.
%
%   coverage_fraction      >= thresholds.MinimumCoverage
%   distinct_value_count   >= thresholds.MinimumDistinctValues
%   largest_stratum_share  <= thresholds.MaximumStratumShare
%   stratum_count          <  recording_count                    [added here]
%
% A field the resolver could not resolve uniquely is rejected here rather than
% raising, carrying the resolver's own message - which names the recording and
% the disagreeing values - as its reason. See vawlume.eda.resolveStrata's
% OnMultiValued for when that is a rejection and when it stops the run.
%
% THE FOURTH RULE EXISTS BECAUSE THE FIRST THREE ADMIT A FIELD THAT IS NO
% GROUPING AT ALL. A field taking a distinct value on every recording - a native
% identifier, a timestamp, a per-animal code - has full coverage, many distinct
% values, and a largest share of 1/R. It passes every stated criterion and then
% produces R strata of one recording each, at which point the floor of one per
% stratum selects the entire dataset and the "subset" is the population. That is
% not a hypothetical: `recording` is in the grammar, and an ingested animal id is
% the most natural thing a user would reach for.
%
% EVERY FAILING REASON IS REPORTED, not just the first. The decision is automatic,
% so the record has to be enough for a reader to re-derive it; a field rejected
% only for coverage reads as fixable by ingesting more metadata, and one that
% also has a single dominant value does not.
%
% AMONG QUALIFYING FIELDS THE MOST BALANCED WINS - lowest dominant share, then
% highest coverage, then the field name. Balance rather than coverage, because
% the allocation is what the subset record will be read through, and a field with
% one large stratum and one small one buys less than an even split. The tie-break
% chain ends at the name so the choice never depends on discovery order.

arguments
    fields table
    thresholds (1,1) struct
end

decision = fields;
if height(decision) == 0
    decision.qualifies = false(0, 1);
    decision.rejection_reason = strings(0, 1);
    decision.is_selected = false(0, 1);
    return
end

qualifies = false(height(decision), 1);
reasons = strings(height(decision), 1);
for index = 1:height(decision)
    row = decision(index, :);
    failures = strings(0, 1);
    if ~row.is_resolvable
        % The only reason reported. An unresolved field has no counts, so its
        % coverage reads 0 and its distinct-value count reads 0 - stating those
        % beside the real reason would describe the field as sparse metadata
        % when the metadata is present and the field is ambiguous, which points
        % a reader at the wrong fix.
        reasons(index) = "not_uniquely_resolvable (" + ...
            row.resolution_note + ")";
        continue
    end
    if row.coverage_fraction < thresholds.MinimumCoverage
        failures(end + 1) = sprintf(...
            "coverage_below_minimum (%.2f < %.2f)", ...
            row.coverage_fraction, thresholds.MinimumCoverage); %#ok<AGROW>
    end
    if row.distinct_value_count < thresholds.MinimumDistinctValues
        failures(end + 1) = sprintf(...
            "fewer_than_%d_distinct_values (%d)", ...
            thresholds.MinimumDistinctValues, ...
            row.distinct_value_count); %#ok<AGROW>
    end
    if row.largest_stratum_share > thresholds.MaximumStratumShare
        failures(end + 1) = sprintf(...
            "dominant_stratum_exceeds_maximum_share ('%s' holds %.2f > %.2f)", ...
            row.largest_stratum, row.largest_stratum_share, ...
            thresholds.MaximumStratumShare); %#ok<AGROW>
    end
    if row.stratum_count >= row.recording_count
        failures(end + 1) = sprintf(...
            "every_recording_in_its_own_stratum (%d strata over %d recordings)", ...
            row.stratum_count, row.recording_count); %#ok<AGROW>
    end
    qualifies(index) = isempty(failures);
    if ~isempty(failures)
        reasons(index) = strjoin(failures, "; ");
    end
end

decision.qualifies = qualifies;
decision.rejection_reason = reasons;
decision.is_selected = false(height(decision), 1);

candidates = find(qualifies);
if isempty(candidates)
    return
end
ranking = table(decision.largest_stratum_share(candidates), ...
    -decision.coverage_fraction(candidates), decision.field(candidates), ...
    candidates, ...
    VariableNames=["dominance", "coverage", "field", "index"]);
ranking = sortrows(ranking, ["dominance", "coverage", "field"]);
chosen = ranking.index(1);
decision.is_selected(chosen) = true;

others = setdiff(candidates, chosen);
decision.rejection_reason(others) = "qualified_but_not_selected ('" + ...
    decision.field(chosen) + "' is more evenly divided)";
end
