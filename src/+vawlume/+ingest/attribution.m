function result = attribution(conn, runRef, sourcePath, options)
%ATTRIBUTION Plan or atomically import one external caller-attribution table.
%
% RESULT = vawlume.ingest.attribution(CONN, RUNREF, SOURCEPATH) maps an external
% attribution table through its declared profile, resolves every caller label
% against the run's participating entities, and reports what would be created.
% Planning is the default and writes nothing.
%
% RESULT = vawlume.ingest.attribution(..., Apply=true) commits a conflict-free
% plan in one transaction covering the source-file and profile-version
% provenance, the imported windows, and the candidate callers and evidence they
% imply.
%
% RUNREF contains attribution_run_id, or project_key and run_key. The run must be
% `planned` with attribution_path `imported`.
%
% **The exporting system's numbers are stored exactly as the file carried them.**
% No rescaling, no renormalization, no clamping, and no promotion of a score to a
% probability because it happened to fall in [0,1]. A re-normalized imported
% score is unauditable forever, because the original is gone. Each stored number
% carries the profile's declared semantics, which say what it meant *there*.
%
% **Caller labels resolve only as the profile declares.** A label is a string in
% somebody else's file; nothing here infers which entity it denotes from string
% similarity, and nothing creates an entity to accommodate an unrecognized one. A
% label resolving to an entity outside the run's participating set is refused by
% name (`vawlume:attribution:CallerLabelUnresolved`), and the error lists every
% offending label rather than dropping those rows.
%
% **Imported windows are related to no VAWLUME event here.** They land with their
% native timing intact, on the exporting system's own clock. Associating them
% with a detection or consensus event is correspondence work with its own
% eligibility rule and its own explicit transform.
%
% **No candidate or evidence row is written.** A candidate belongs to
% (target, entity); an imported claim belongs to (window, entity). Mapping one
% onto the other requires knowing which window refers to which event, which is
% correspondence and has not happened. The claims come back in RESULT.claims
% with their values intact; they have nowhere to be stored until correspondence
% exists, which is recorded as a finding rather than worked around.
%
% **An import applies once per run.** Evidence is append-only and a second apply
% would duplicate rather than reconcile, so a run already carrying imported
% windows is refused (`vawlume:attribution:ImportAlreadyApplied`).
%
% Name-value arguments:
%   Apply        persist the plan (default false)
%   ProfilePath  mapping profile (default: the shipped generic profile)
%   RepoRoot     repository root, inferred from this file by default
%
% See also VAWLUME.ATTRIBUTION.ADDCANDIDATES, VAWLUME.ATTRIBUTION.ADDEVIDENCE,
% VAWLUME.SOURCE_MAPPING.PREVIEW

arguments
    conn
    runRef (1,1) struct
    sourcePath (1,1) string
    options.Apply (1,1) logical = false
    options.ProfilePath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

plan = attributionImportBuildPlan(conn, runRef, sourcePath, options);
result = importResult(plan);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = attributionImportApplyPlan(conn, plan);
    result = importResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    result.status = "imported";
end
end

function result = importResult(plan)
if plan.has_conflicts
    status = "conflict";
else
    status = "planned";
end
result = struct( ...
    status=status, ...
    committed=false, ...
    attribution_run_id=plan.run.attribution_run_id, ...
    run_key=plan.run.run_key, ...
    source=plan.source, ...
    profile=plan.profile, ...
    exporting_system=plan.exporting_system, ...
    windows=plan.windows, ...
    claims=plan.claims, ...
    unmapped_rows=plan.unmapped_rows, ...
    issues=plan.issues, ...
    has_conflicts=plan.has_conflicts, ...
    timing_basis="native_to_exporting_system", ...
    correspondence="none; 4.9 relates these windows to VAWLUME events", ...
    proves="an external attribution table was read and stored with its provenance", ...
    does_not_prove=["that any claimed caller called"; ...
        "that the exporting system's numbers are calibrated"; ...
        "that these windows refer to calls VAWLUME detected"]);
end
