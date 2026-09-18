function [seed, basis] = edaDeterministicSeed(surface)
%EDADETERMINISTICSEED Resolve a seed from dataset identity when the user gives none.
%
% Reproducibility is a requirement, not a nicety: an unseeded run must be as
% reproducible after the fact as a seeded one. This derives a seed from the
% identity of the analyses being explored - their project keys and matching run
% keys, sorted - so the same dataset always resolves to the same seed and the
% BASIS string is recorded alongside it, making the derivation reconstructible
% rather than merely repeatable.
%
% Derived from the dataset rather than fixed at a constant. A constant default
% would be equally reproducible, but it would give every project the same draw
% order, so a user who never sets a seed would get the same positional pattern of
% "random" selections in every study they run. Under a fixed ordering key that
% systematically favours the same end of the frame each time.
%
% A polynomial rolling hash over the UTF-8 bytes, computed in DOUBLE arithmetic
% under a modulus small enough that every intermediate product stays below 2^53.
% Integer arithmetic would be the obvious choice and is the wrong one: MATLAB
% saturates integer overflow rather than wrapping it, so a uint64 multiply in a
% hash silently pins at intmax and collapses every long name onto the same
% value. The first version of this function did exactly that and produced the
% same suspiciously round seed for every dataset.
%
% The hash needs to be stable and well-mixed, not cryptographic: nothing here
% defends against an adversary choosing a dataset name to steer a sample.

if isfield(surface, "analyses") && istable(surface.analyses) && ...
        height(surface.analyses) > 0
    parts = string(surface.analyses.project_key) + "/" + ...
        string(surface.analyses.matching_run_key);
    basis = strjoin(sort(parts)', "|");
else
    basis = "(no analyses)";
end

bytes = double(unicode2native(char(basis), "UTF-8"));
modulus = 2147483647;      % 2^31 - 1, and a Mersenne prime
multiplier = 1000003;      % hash * multiplier < 2^51, comfortably exact in double
hash = 2166136261;
for index = 1:numel(bytes)
    hash = mod(hash * multiplier + bytes(index), modulus);
end
seed = hash;
end
