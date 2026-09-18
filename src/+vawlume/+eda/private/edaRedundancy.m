function value = edaRedundancy(pairs, options)
%EDAREDUNDANCY Strongly associated metric pairs, reported with their consequence.
%
% A pair is reported when the magnitude of its Pearson OR its Spearman
% correlation reaches the threshold. Either alone is enough: a monotone but
% nonlinear pair can be nearly redundant for screening purposes while its Pearson
% coefficient is unremarkable, and refusing to report it because the linear
% measure disagreed would hide the collinearity that matters.
%
% The partial correlation is carried alongside. A pair with a strong marginal
% association and a near-zero partial is associated only through the other
% metrics, which is a materially different finding from two dimensions that
% duplicate each other directly - and it is the finding a screening design cares
% about, because controlling for the rest is what the design does.
%
% NOTHING IS PRUNED HERE, and this function returns no instruction to prune. The
% conceptual specification forbids deleting a scientifically requested dimension
% on the strength of a correlation statistic. The finding travels into the
% screening design's provenance and the leverage report's annotations; the factor
% set is fixed by the governing contract.

value = emptyRedundancy();
if height(pairs) == 0
    return
end

threshold = options.RedundancyThreshold;
pearson = abs(pairs.pearson);
spearman = abs(pairs.spearman);
strongest = max(pearson, spearman, "omitnan");
selected = strongest >= threshold;
if ~any(selected)
    return
end

chosen = pairs(selected, :);
strength = strongest(selected);
basis = repmat("both", height(chosen), 1);
basis(~(abs(chosen.pearson) >= threshold)) = "spearman_only";
basis(~(abs(chosen.spearman) >= threshold)) = "pearson_only";
basis(isnan(chosen.pearson)) = "spearman_only";
basis(isnan(chosen.spearman)) = "pearson_only";

for index = 1:height(chosen)
    value(end + 1, :) = {chosen.metric_a(index), chosen.metric_b(index), ...
        chosen.pearson(index), chosen.spearman(index), strength(index), ...
        basis(index), chosen.partial(index), ...
        chosen.observations(index), chosen.screening_relevance(index), ...
        consequence(chosen.partial(index), ...
            chosen.screening_relevance(index))}; %#ok<AGROW>
end
value = sortrows(value, "strongest_magnitude", "descend");
end

function value = consequence(partial, relevance)
if relevance == "both_screened_factors"
    head = "Both metrics correspond to screened factors, so their main " + ...
        "effects in the design cannot be attributed separately.";
else
    head = "At least one metric is not a screened factor, so this bears on " + ...
        "how the diagnostic is read rather than on the design's balance.";
end
if isnan(partial)
    tail = " The partial correlation is undefined, so whether the " + ...
        "association survives controlling for the other metrics is unknown.";
elseif abs(partial) < 0.3
    tail = " The partial correlation is weak, so the association appears to " + ...
        "run through the other metrics rather than directly between these two.";
else
    tail = " The partial correlation remains substantial, so the two " + ...
        "dimensions carry overlapping information directly.";
end
value = head + tail;
end

function value = emptyRedundancy()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), ...
    VariableNames=["metric_a", "metric_b", "pearson", "spearman", ...
    "strongest_magnitude", "basis", "partial", "observations", ...
    "screening_relevance", "consequence"]);
end
