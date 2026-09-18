function value = edaLeverageCategories()
%EDALEVERAGECATEGORIES Contract §H's five categories, in precedence order.
%
% ORDER IS PRECEDENCE, top to bottom, and it is load-bearing.
% `insufficient_information` outranks everything because a response that is
% constant across the entire design yields a main effect of exactly zero for
% every factor, and zero over a range of zero is not a small effect - it is no
% information. Categorising it by magnitude would report every factor as inert,
% which is the highest-consequence misclassification available in this MVP.
%
% One vocabulary, stated once, so the categoriser, the concordance table and any
% figure that follows all spell the categories the same way. Two spellings would
% make the two probes disagree about a factor purely on text.
value = [ ...
    "insufficient_information"
    "interaction_suspected"
    "high_leverage"
    "moderate_leverage"
    "low_leverage"];
end
