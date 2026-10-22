function runIds = trackingResolveAlignmentRun(conn, stream, referenceKey)
%TRACKINGRESOLVEALIGNMENTRUN Every stored transform from this clock to another.
%
% Returns the ids of every usable run, ascending, and an empty array when none
% exists. The caller decides what several mean; it never takes the newest one
% silently (P6-4, contract 07 D17). It reports "no usable transform" as a
% status rather than estimating one: the alignment layer owns transforms, and a
% reader that fitted its own would create a second authority that could
% disagree with the residuals persisted beside the first.
%
% Only a solved run qualifies. A run still 'registered' has no coefficients, and
% one 'rejected' or 'failed' was judged unusable - using either would return a
% plausible-looking number with nothing behind it.

runIds = zeros(0, 1);
rows = fetch(conn, "SELECT r.alignment_run_id, r.status " + ...
    "FROM time_alignment_runs r " + ...
    "JOIN timebases ref ON ref.timebase_id=r.target_timebase_id " + ...
    "WHERE r.source_timebase_id=" + string(stream.timebase_id) + ...
    " AND ref.timebase_name=" + trackingSqlText(referenceKey) + ...
    " AND r.status NOT IN ('rejected','failed','registered') " + ...
    "ORDER BY r.alignment_run_id");

if isempty(rows) || height(rows) == 0
    return
end
runIds = double(rows.alignment_run_id(:));
end
