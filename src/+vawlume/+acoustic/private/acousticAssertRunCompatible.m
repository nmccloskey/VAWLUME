function acousticAssertRunCompatible(row, runType, status, options, conflictId)
%ACOUSTICASSERTRUNCOMPATIBLE Refuse to reuse a run whose provenance differs.
%
% ROW is the stored analysis_runs row under options.RunKey. A reuse is only a
% reuse when type, status and every declared provenance field are the same;
% anything else raises CONFLICTID rather than adopting the stored run.
actual = [acousticPresentText(row.run_type(1)), acousticPresentText(row.status(1)), ...
    acousticPresentText(row.run_label(1)), acousticPresentText(row.vawlume_version(1)), ...
    acousticPresentText(row.source_commit(1)), acousticPresentText(row.notes(1))];
expected = [runType, status, options.RunLabel, ...
    options.VawlumeVersion, options.SourceCommit, options.Notes];
if ~isequal(actual, expected)
    error(conflictId, "%s", "RunKey '" + options.RunKey + ...
        "' already identifies an analysis run with different provenance or status.");
end
end
