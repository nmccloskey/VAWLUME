function runId = trackingResolveAlignmentRun(conn, stream, referenceKey)
%TRACKINGRESOLVEALIGNMENTRUN Find a stored transform from this clock to another.
%
% Returns NaN when no usable transform exists. The caller reports that as a
% status rather than estimating one: the alignment layer owns transforms, and a
% reader that fitted its own would create a second authority that could disagree
% with the residuals persisted beside the first.
%
% Only a solved run qualifies. A run still 'registered' has no coefficients, and
% one 'rejected' or 'failed' was judged unusable - using either would return a
% plausible-looking number with nothing behind it.

runId = NaN;
rows = fetch(conn, "SELECT r.alignment_run_id, r.status " + ...
    "FROM time_alignment_runs r " + ...
    "JOIN timebases ref ON ref.timebase_id=r.target_timebase_id " + ...
    "WHERE r.source_timebase_id=" + string(stream.timebase_id) + ...
    " AND ref.timebase_name=" + trackingSqlText(referenceKey) + ...
    " AND r.status NOT IN ('rejected','failed','registered') " + ...
    "ORDER BY r.alignment_run_id DESC");

if isempty(rows) || height(rows) == 0
    return
end
runId = double(rows.alignment_run_id(1));
end
