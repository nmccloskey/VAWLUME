function result = resolveTargets(conn, runRef, targetSpec, options)
%RESOLVETARGETS Resolve and verify one attribution run's explicit event set.
%
% RESULT = VAWLUME.ATTRIBUTION.RESOLVETARGETS(CONN, RUNREF, TARGETSPEC)
% is read-only. RUNREF contains attribution_run_id, or project_key plus
% run_key. TARGETSPEC has the same shape as createRun's target_set.
%
% The result reports the event-set identity, resolved event rows, stored target
% rows, and whether they are identical. By default a mismatch raises
% vawlume:attribution:TargetSetConflict; set RequireStoredMatch=false to inspect
% both sides without accepting or mutating either one.
%
% This function never appends targets to a run. The supported write path is
% createRun(..., Apply=true), which creates the run and its entire target set
% atomically so no targetless partial run can survive.
%
% See also VAWLUME.ATTRIBUTION.CREATERUN

arguments
    conn
    runRef (1,1) struct
    targetSpec (1,1) struct
    options.RequireStoredMatch (1,1) logical = true
end

run = attributionResolveRun(conn, runRef);
recording = struct(recording_id=run.recording_id, ...
    project_id=run.project_id, project_key=run.project_key, ...
    native_recording_id=run.native_recording_id, ...
    source_relative_path=run.source_relative_path);
resolved = attributionResolveTargetSet(conn, recording, targetSpec);
stored = attributionReadTargets(conn, run.attribution_run_id);
matches = attributionTargetsEqual(stored, resolved.targets);
if options.RequireStoredMatch && ~matches
    error("vawlume:attribution:TargetSetConflict", ...
        "The supplied target set differs from attribution run '%s'.", run.run_key);
end

result = struct(status="resolved", committed=false, run=run, ...
    event_set=resolved.event_set, targets=resolved.targets, ...
    stored_targets=stored, target_count=height(resolved.targets), ...
    matches_stored=matches);
end
