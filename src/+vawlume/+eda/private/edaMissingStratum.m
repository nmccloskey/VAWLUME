function value = edaMissingStratum()
%EDAMISSINGSTRATUM The literal stratum value a missing field resolves to.
%
% Fixed by contract §I. A recording whose stratum field does not resolve is
% REPRESENTED, never dropped: it appears in the frame under this value, enters
% the summaries, and is eligible for sampling like any other stratum.
%
% One constant rather than a literal at each site, because the whole point is
% that the resolver, the meaningfulness decision, the allocator, and the subset
% record all agree on the same string. Two spellings would split one stratum in
% two and the split would look like a finding about the metadata.
value = "(missing)";
end
