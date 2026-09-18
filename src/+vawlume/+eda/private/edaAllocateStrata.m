function allocation = edaAllocateStrata(labels, sizes, total, minimumPerStratum)
%EDAALLOCATESTRATA Contract §I's allocation: proportional, floored, trimmed.
%
% ALLOCATION = EDAALLOCATESTRATA(LABELS, SIZES, TOTAL, MINIMUMPERSTRATUM) returns
% one row per stratum carrying every intermediate quantity, so the reader can see
% how the requested total became the realized one instead of being handed a
% column of counts to trust.
%
% Three steps, in the contract's order:
%
%   1. Proportional to stratum size, rounded by LARGEST REMAINDER. Rounding is
%      exactly where proportional allocation quietly stops summing to the
%      requested total: with three equal strata and a request of two, naive
%      rounding gives 1+1+1 = 3. Largest remainder floors everything and then
%      hands the shortfall to the strata with the largest fractional parts, so
%      the counts sum to the request by construction.
%   2. A FLOOR of MINIMUMPERSTRATUM per stratum, which is what preserves a rare
%      stratum that proportional allocation rounded to zero.
%   3. TRIMMING from the largest strata back to the total, because the floor can
%      only raise. A stratum already at the floor is never trimmed below it -
%      that would undo step 2 - so when the floor alone exceeds the request the
%      total rises and the row set says by how much.
%
% REALIZED IS CAPPED AT THE STRATUM'S ACTUAL SIZE AND THE SHORTFALL IS NOT
% REDISTRIBUTED. An under-full stratum is reported short with its real count. The
% tempting move is to give its unused places to a neighbour so the totals match
% the request; that produces a sample the reader will read as balanced and which
% is not, which is worse than an honestly unbalanced one.
%
% Every tie is broken deterministically - larger stratum first, then label in
% ascending order - because a tie broken by MATLAB's sort stability would make
% the allocation depend on the order the strata happened to be discovered in.

arguments
    labels string
    sizes double
    total (1,1) double
    minimumPerStratum (1,1) double
end

labels = labels(:);
sizes = sizes(:);
count = numel(labels);
if count == 0
    allocation = emptyAllocation();
    return
end

population = sum(sizes);
exactShare = total * sizes / population;
base = floor(exactShare);
remainder = exactShare - base;

deficit = round(total - sum(base));
order = tieBreakOrder(remainder, sizes, labels);
awarded = false(count, 1);
if deficit > 0
    awarded(order(1:min(deficit, count))) = true;
end
requested = base + double(awarded);
afterRounding = requested;

floored = max(requested, minimumPerStratum);
floorRaised = floored - requested;
requested = floored;

trimmed = zeros(count, 1);
while sum(requested) > total
    reducible = find(requested > minimumPerStratum);
    if isempty(reducible)
        break
    end
    pick = reducible(trimTarget(sizes(reducible), requested(reducible), ...
        labels(reducible)));
    requested(pick) = requested(pick) - 1;
    trimmed(pick) = trimmed(pick) + 1;
end

realized = min(requested, sizes);

allocation = table(labels, sizes, exactShare, afterRounding, floorRaised, ...
    trimmed, requested, realized, realized < requested, ...
    VariableNames=["stratum_value", "stratum_size", "proportional_share", ...
    "largest_remainder_count", "floor_added", "trimmed", ...
    "requested_count", "realized_count", "is_under_full"]);
end

function order = tieBreakOrder(remainder, sizes, labels)
%TIEBREAKORDER Which stratum receives the next remainder place.
%
% Largest fractional part first; then the larger stratum, because a place awarded
% to the larger stratum moves the realized proportions less; then the label, so
% two identical strata still resolve in a stated order rather than whichever the
% resolver happened to emit first.
ranking = table(-remainder, -sizes, labels, (1:numel(labels))', ...
    VariableNames=["remainder", "size", "label", "index"]);
ranking = sortrows(ranking, ["remainder", "size", "label"]);
order = ranking.index;
end

function position = trimTarget(sizes, requested, labels)
%TRIMTARGET Which stratum gives up the next place when trimming to the total.
%
% The largest stratum, since it is the one whose proportional share a single
% place changes least, then the one currently holding the most, then the label.
ranking = table(-sizes, -requested, labels, (1:numel(labels))', ...
    VariableNames=["size", "requested", "label", "index"]);
ranking = sortrows(ranking, ["size", "requested", "label"]);
position = ranking.index(1);
end

function value = emptyAllocation()
value = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
    VariableNames=["stratum_value", "stratum_size", "proportional_share", ...
    "largest_remainder_count", "floor_added", "trimmed", ...
    "requested_count", "realized_count", "is_under_full"]);
end
