function value = edaCoverageCategories()
%EDACOVERAGECATEGORIES The disjoint coverage vocabulary, in reporting order.
%
% The governing contract fixes the first four. not_comparable_topology is added
% here because a fifth distinct fact exists in the data and the contract's own
% argument for having four categories rather than one applies to it: a feature
% discrepancy that was not computed because its match group is a split, merge,
% or unmatched group is not the same fact as an unregistered feature pair, and
% not the same fact as a measurement one extractor never exported. The matching
% specification restricts feature comparison to one_to_one groups, so this case
% is reached on ordinary data rather than being hypothetical.
%
% Every metric's counts across these categories sum to the surface's row count.
value = ["supported"; "not_eligible"; "not_measured"; ...
    "not_comparable_topology"; "non_finite"];
end
