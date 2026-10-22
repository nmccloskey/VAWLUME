function [runId, payload, action] = acousticFindOrCreateRun(conn, projectId, runKey, ...
        create, reuse)
%ACOUSTICFINDORCREATERUN One transaction: reuse the run under RUNKEY, or create it.
%
% The persistence skeleton the call-window, reference and normalization
% producers share. RUNKEY is looked up in PROJECTID. When no run exists,
% [runId, payload] = CREATE() writes everything the producer owns and the
% transaction commits. When one exists, payload = REUSE(runId, row) must verify
% that the stored run holds exactly what this call would have written, and raise
% otherwise; nothing is written. Any error rolls the transaction back and
% restores the connection's AutoCommit setting before rethrowing.
oldAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
try
    existing = fetch(conn, "SELECT analysis_run_id, run_type, status, " + ...
        "IFNULL(run_label,'') AS run_label, IFNULL(vawlume_version,'') AS vawlume_version, " + ...
        "IFNULL(source_commit,'') AS source_commit, IFNULL(notes,'') AS notes " + ...
        "FROM analysis_runs WHERE project_id=" + string(projectId) + ...
        " AND run_key=" + acousticSqlText(runKey));
    if isempty(existing) || height(existing) == 0
        [runId, payload] = create();
        action = "created";
        commit(conn);
    else
        runId = double(existing.analysis_run_id(1));
        payload = reuse(runId, existing(1, :));
        action = "reused";
    end
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end
