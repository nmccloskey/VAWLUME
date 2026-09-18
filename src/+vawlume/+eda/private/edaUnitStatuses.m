function value = edaUnitStatuses()
%EDAUNITSTATUSES What can become of one unit of probe work.
%
%   planned     dry run; the unit was resolved and validated, nothing written
%   committed   newly applied
%   reused      an identical analysis already existed under this run key, and
%               was left alone. A REUSE IS A SUCCESS, and is reported distinctly
%               so a rerun's output shows what was actually new
%   conflict    an analysis exists under this run key with different inputs or a
%               different checksum. Never resolved by rewriting the existing
%               analysis; surfaced for a human to diagnose
%   failed      the unit raised
%   skipped     not attempted, because something it depends on failed - an
%               agreement composition whose pairwise set is incomplete
value = ["planned"; "committed"; "reused"; "conflict"; "failed"; "skipped"];
end
