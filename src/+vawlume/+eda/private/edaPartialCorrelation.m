function result = edaPartialCorrelation(correlation, names, degeneracy, completeN, options)
%EDAPARTIALCORRELATION Partial correlations by precision-matrix scaling, guarded first.
%
% Asks whether a metric retains a relationship with another after controlling for
% every other retained metric. From the correlation matrix R over the retained
% metrics, the precision matrix P = inv(R) gives
%
%   partial(i,j) = -P(i,j) / sqrt( P(i,i) * P(j,j) )
%
% `inv` and `rcond` are base MATLAB. `partialcorr` is a Statistics and Machine
% Learning Toolbox function in every release and is not called.
%
% EVERY GUARD IS APPLIED BEFORE THE INVERSION, not as exception handling around
% it. That ordering is the point: a matrix that passes `inv` without raising can
% still yield partial correlations that are numerical noise carrying four decimal
% places, and catching an error afterwards would not detect it.
%
%   constant and near-constant columns are excluded by name before R is formed
%   fewer than two retained metrics leave nothing to control for
%   complete cases must exceed the retained metric count by a stated margin
%   the reciprocal condition number is tested against a floor before inverting
%
% NO RIDGE OR SHRINKAGE REGULARIZATION, by default or otherwise. Regularizing
% converts a singular matrix into a finite, plausible-looking number, which is
% exactly the failure the conceptual specification names when it requires
% undefined values to be reported rather than silently regularized into an
% apparently precise statistic. An undefined partial correlation is the honest
% answer, and it carries a reason saying which guard fired.
%
% The matrix returned is full size, with rows and columns for excluded metrics
% present and undefined, so all three dependency matrices share one shape and one
% ordering and Part 14 can draw them on the same axes. Only the retained
% submatrix is inverted.

names = string(names(:))';
count = numel(names);
retained = ~degeneracy.is_degenerate(:)';
retainedCount = nnz(retained);
required = retainedCount + options.ObservationMargin;

matrix = NaN(count);
conditionNumber = NaN;

if retainedCount < 2
    result = assemble(matrix, "undefined", "insufficient_observations", ...
        "Fewer than two metrics survived the degeneracy guards, so there " + ...
        "is nothing to control for.", names, degeneracy, retained, ...
        completeN, required, conditionNumber);
    return
end
if completeN < required
    result = assemble(matrix, "undefined", "insufficient_observations", ...
        "Complete-case observations (" + string(completeN) + ") are below " + ...
        "the floor of " + string(required) + " for " + ...
        string(retainedCount) + " retained metrics.", names, degeneracy, ...
        retained, completeN, required, conditionNumber);
    return
end

R = correlation(retained, retained);
if any(~isfinite(R(:)))
    result = assemble(matrix, "undefined", "insufficient_observations", ...
        "The correlation matrix over retained metrics contains an " + ...
        "undefined entry, so it cannot be inverted.", names, degeneracy, ...
        retained, completeN, required, conditionNumber);
    return
end
conditionNumber = rcond(R);
if ~isfinite(conditionNumber) || conditionNumber < options.ConditionNumberFloor
    result = assemble(matrix, "undefined", "ill_conditioned", ...
        "Reciprocal condition number " + string(conditionNumber) + ...
        " is below the floor " + string(options.ConditionNumberFloor) + ...
        "; the correlation matrix is too close to singular to invert " + ...
        "meaningfully.", names, degeneracy, retained, completeN, required, ...
        conditionNumber);
    return
end

P = inv(R);
diagonal = diag(P);
scaled = -P ./ sqrt(diagonal * diagonal');
scaled(1:(retainedCount + 1):end) = 1;
matrix(retained, retained) = scaled;

result = assemble(matrix, "computed", "", "", names, degeneracy, retained, ...
    completeN, required, conditionNumber);
end

function result = assemble(matrix, status, reason, detail, names, degeneracy, ...
    retained, completeN, required, conditionNumber)
count = numel(names);
undefinedReason = repmat("", count, count);
if status ~= "computed"
    undefinedReason(:) = reason;
end
% A metric's own degeneracy outranks the matrix-level reason. A reader looking
% at a constant column's row needs to see that the column was constant, not that
% the matrix was ill-conditioned: the column-level fact is both more specific and
% more actionable.
for index = 1:count
    if retained(index)
        continue
    end
    undefinedReason(index, :) = degeneracy.reason(index);
    undefinedReason(:, index) = degeneracy.reason(index);
end
result = struct( ...
    matrix=matrix, ...
    status=string(status), ...
    reason=string(reason), ...
    detail=string(detail), ...
    undefined_reason=undefinedReason, ...
    source="pearson", ...
    retained_metric_names=names(retained), ...
    excluded_metric_names=names(~retained), ...
    complete_case_n=completeN, ...
    required_minimum=required, ...
    reciprocal_condition_number=conditionNumber, ...
    regularization="none");
end
