function value = edaUndefinedReasons()
%EDAUNDEFINEDREASONS The fixed vocabulary for an undefined dependency cell.
%
% Fixed by the governing contract. An undefined cell is NaN *plus* one of these,
% and the reason is first-class output rather than a log line: a reader seeing an
% undefined partial correlation needs to know whether the metric was constant in
% this dataset or whether the matrix was too ill-conditioned to invert, because
% those imply different next steps.
%
% "" is the reason of a cell that is defined.
value = ["constant_column"; "near_constant_column"; ...
    "insufficient_observations"; "ill_conditioned"; ...
    "no_overlapping_observations"];
end
