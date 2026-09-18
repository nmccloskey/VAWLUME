function report = edaColumnDegeneracy(sample, names, tolerance)
%EDACOLUMNDEGENERACY Flag columns that cannot carry a correlation, before computing one.
%
% A constant column has no correlation with anything: the answer is undefined,
% not zero, and a near-constant column produces one that is numerical noise
% wearing a plausible value. Both make a correlation matrix singular by
% construction, so they are detected before any inversion rather than caught
% afterwards.
%
% The rule is the one the distribution layer records, applied to THE SAMPLE
% ACTUALLY USED. That distinction matters: under listwise deletion a column can
% be constant across the complete cases while varying across the full dataset,
% and it is the complete cases the correlation is computed on.
%
%   constant       max - min == 0
%   near-constant  max - min <= tolerance * max(1, abs(median))
%
% Columns with no finite observation in the sample are reported
% no_overlapping_observations rather than constant: nothing was observed, which
% is not the same as observing the same value repeatedly.

count = numel(names);
isConstant = false(count, 1);
isNearConstant = false(count, 1);
reason = repmat("", count, 1);
observations = zeros(count, 1);

for index = 1:count
    values = sample(:, index);
    values = values(isfinite(values));
    observations(index) = numel(values);
    if isempty(values)
        reason(index) = "no_overlapping_observations";
        continue
    end
    span = max(values) - min(values);
    if span == 0
        isConstant(index) = true;
        reason(index) = "constant_column";
        continue
    end
    if span <= tolerance * max(1, abs(median(values)))
        isNearConstant(index) = true;
        reason(index) = "near_constant_column";
    end
end

report = table(names(:), observations, isConstant, isNearConstant, ...
    strlength(reason) > 0, reason, ...
    VariableNames=["metric_name", "observations", "is_constant", ...
    "is_near_constant", "is_degenerate", "reason"]);
end
