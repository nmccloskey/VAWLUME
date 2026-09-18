function result = edaCorrelationMatrices(sample, names, mode, degeneracy, options)
%EDACORRELATIONMATRICES Pearson and Spearman matrices with per-cell counts and reasons.
%
% Pearson comes from `corrcoef`, which is base MATLAB. Spearman is the Pearson
% correlation of mid-ranks, computed through vawlume.eda.midRank, because
% `corr(...,"type","Spearman")` is a Statistics and Machine Learning Toolbox
% function in every release.
%
% Both are returned, always, side by side. The matching metrics are bounded and
% skewed - a temporal IoU lives in [0, 1] with a hard edge at its own gate - so
% Pearson measures something real but easily misread, and Spearman is the robust
% companion. Reporting one alone invites the reader to treat it as *the*
% dependency.
%
% Every cell carries its own observation count. A correlation computed on 11
% pairs and one computed on 11,000 are indistinguishable as numbers.
%
% MODE is "listwise" or "pairwise". Under listwise every cell shares one
% complete-case sample, which is what makes the three matrices comparable and is
% required for the partial correlation to have one invertible matrix. Under
% pairwise each cell uses its own jointly-finite subset, so the cells are not
% mutually consistent and the matrix need not be positive semi-definite - which
% is reported, not patched.
%
% Ranks are taken WITHIN the sample each cell uses. Ranking a full column and
% then subsetting gives a different and wrong answer, because a rank is a
% statement about position in a particular sample.
%
% These are exploratory dependency measures. Nothing here is evidence of a causal
% relationship and no output may describe it as one.

count = numel(names);
pearson = NaN(count);
spearman = NaN(count);
observations = zeros(count);
reason = repmat("", count, count);

for i = 1:count
    for j = i:count
        [p, s, n, why] = cellValue(sample, i, j, mode, degeneracy, options);
        pearson(i, j) = p;
        pearson(j, i) = p;
        spearman(i, j) = s;
        spearman(j, i) = s;
        observations(i, j) = n;
        observations(j, i) = n;
        reason(i, j) = why;
        reason(j, i) = why;
    end
end

result = struct( ...
    pearson=pearson, ...
    spearman=spearman, ...
    observations=observations, ...
    undefined_reason=reason, ...
    deletion=string(mode));
end

function [p, s, n, why] = cellValue(sample, i, j, mode, degeneracy, options)
p = NaN;
s = NaN;

if mode == "listwise"
    x = sample(:, i);
    y = sample(:, j);
    n = size(sample, 1);
    why = degenerateReason(degeneracy, i, j);
    if strlength(why) > 0
        return
    end
    if n < options.MinimumPairObservations
        why = "insufficient_observations";
        return
    end
else
    joint = isfinite(sample(:, i)) & isfinite(sample(:, j));
    n = nnz(joint);
    if n == 0
        why = "no_overlapping_observations";
        return
    end
    x = sample(joint, i);
    y = sample(joint, j);
    if n < options.MinimumPairObservations
        why = "insufficient_observations";
        return
    end
    % Degeneracy is judged on the jointly-finite subset, which is the sample
    % this cell is actually computed on. A column that varies overall can be
    % constant within one pair's overlap.
    why = pairDegeneracy(x, y, options.NearConstantTolerance);
    if strlength(why) > 0
        return
    end
end

if i == j
    p = 1;
    s = 1;
    return
end
p = pearsonOf(x, y);
s = pearsonOf(vawlume.eda.midRank(x), vawlume.eda.midRank(y));
end

function why = degenerateReason(degeneracy, i, j)
why = "";
for index = unique([i, j])
    if degeneracy.is_degenerate(index)
        why = degeneracy.reason(index);
        return
    end
end
end

function why = pairDegeneracy(x, y, tolerance)
why = "";
for values = [x, y]
    span = max(values) - min(values);
    if span == 0
        why = "constant_column";
        return
    end
    if span <= tolerance * max(1, abs(median(values)))
        why = "near_constant_column";
        return
    end
end
end

function value = pearsonOf(x, y)
%PEARSONOF Base-MATLAB Pearson correlation of two guarded, finite vectors.
matrix = corrcoef(x, y);
value = matrix(1, 2);
end
