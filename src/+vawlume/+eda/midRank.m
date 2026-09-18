function ranks = midRank(values)
%MIDRANK Ranks with tied values assigned their average rank.
%
% RANKS = vawlume.eda.MIDRANK(VALUES) returns the rank of each element of
% VALUES, where a run of equal values receives the mean of the ranks that run
% occupies. Four values 10 20 20 30 rank as 1 2.5 2.5 4.
%
% This exists so Spearman correlation can be computed in base MATLAB as the
% Pearson correlation of mid-ranks. `tiedrank` lives in MATLAB's shared
% statistics library and is not safely assumed present, and `corr(...,"type",
% "Spearman")` is a Statistics and Machine Learning Toolbox function in every
% release.
%
% Mid-ranks, not ordinal ranks, are the definition Spearman requires. Assigning
% tied values consecutive ranks by position would make the coefficient depend on
% the order the samples happened to arrive in, which for a bounded metric with a
% hard edge at its own threshold - a temporal IoU gated at 0.1 - is not a rare
% case. Ties are the norm there, not the exception.
%
% VALUES must be finite: a rank is undefined for a value that has no position in
% the ordering, and silently dropping NaN would return a vector of a different
% length than the caller passed. The caller filters first and is the only party
% that knows which sample the rank is meant to be taken within.

arguments
    values {mustBeNumeric, mustBeReal}
end

flat = double(values(:));
if any(~isfinite(flat))
    error("vawlume:eda:RankRequiresFiniteValues", ...
        "midRank requires finite values; filter the sample before ranking, " + ...
        "because the rank of a value depends on which sample it is ranked in.");
end

n = numel(flat);
ranks = zeros(n, 1);
if n == 0
    ranks = reshape(ranks, size(values));
    return
end

[sorted, order] = sort(flat);
assigned = zeros(n, 1);
first = 1;
while first <= n
    last = first;
    while last < n && sorted(last + 1) == sorted(first)
        last = last + 1;
    end
    assigned(first:last) = (first + last) / 2;
    first = last + 1;
end
ranks(order) = assigned;
ranks = reshape(ranks, size(values));
end
