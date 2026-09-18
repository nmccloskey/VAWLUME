function value = edaInactiveReasons()
%EDAINACTIVEREASONS Why a contract factor did not enter the screening design.
%
% A factor is never dropped silently and never screened at an arbitrary value.
% Each of these is a finding about the dataset or the request, and each belongs
% in the run's provenance.
%
%   disabled_by_user          the caller excluded it explicitly
%   metric_absent             the surface carries no column for its metric
%   insufficient_coverage     too few supported observations to place a quantile
%   degenerate_interval       low and high resolved to the same value, so the
%                             design column would never vary
%
% NOTE that "redundant with another factor" is deliberately absent. The
% conceptual specification forbids removing a scientifically requested dimension
% on the strength of a correlation statistic; a redundancy finding is recorded
% beside the factor and the factor is screened anyway.
value = ["disabled_by_user"; "metric_absent"; "insufficient_coverage"; ...
    "degenerate_interval"];
end
