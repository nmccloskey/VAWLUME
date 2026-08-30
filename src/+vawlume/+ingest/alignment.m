function result = alignment(conn, manifestPath, options)
%ALIGNMENT Plan or atomically register one multimodal alignment session.
%
% RESULT = vawlume.ingest.alignment(CONN, MANIFESTPATH) reads a session alignment
% manifest, maps the external event and anchor tables it names through their
% declared profiles, resolves every identity against the database, and classifies
% each row as create, reuse, or conflict. Planning is the default and writes
% nothing.
%
% RESULT = vawlume.ingest.alignment(..., Apply=true) commits a conflict-free plan
% in one transaction covering the manifest and source provenance, the mapping
% profile versions, the declared timebases, the alignment analysis run and its
% alignment set, the external streams with their coverage, events and attributes,
% the logical anchors with their per-clock observations, and one registered
% pairwise transform run per participating source clock.
%
% **No transform is fitted here.** No `alignment_segments` row, residual, or
% aligned timestamp is created, and each pairwise run is stored with status
% 'registered' so nothing claims a fit it does not have. Fitting is the next
% stage's work.
%
% The recording's native audio timebase is ensured rather than assumed. Every
% recording created before this capability existed has none, and requiring manual
% SQL to align one would make each fresh database a special case. A recording that
% already resolves a native clock keeps it; a second one is never created.
%
% Name-value options:
%   Apply       commit a conflict-free plan (default false)
%   RepoRoot    root for repository-relative mapping-profile paths
%   SourceRoot  root for manifest-relative data paths, defaulting to the
%               manifest's own directory
%   Tables      struct mapping a stream_key, or "anchors", to an in-memory table
%   RunSpec     optional struct with run_key, run_label, vawlume_version,
%               source_commit
%
% Mapping semantics stay in VAWLUME.SOURCE_MAPPING. Nothing here reinterprets a
% column, chooses a timestamp, normalizes a label, or invents a native event ID.

arguments
    conn
    manifestPath (1,1) string
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
    options.SourceRoot (1,1) string = ""
    options.Tables (1,1) struct = struct()
    options.RunSpec (1,1) struct = struct()
end

bundle = vawlume.ingest.alignmentManifest(manifestPath, ...
    RepoRoot=options.RepoRoot, SourceRoot=options.SourceRoot, ...
    Tables=options.Tables);
plan = alignmentBuildPlan(conn, bundle, options.RunSpec);

if options.Apply
    if ~bundle.valid_for_ingest
        error("vawlume:ingest:AlignmentNotReady", ...
            ['The mapped alignment inputs are not ready for ingest. Structured ' ...
            'issues remain in the result; correct the source or profile rather ' ...
            'than registering partial evidence.']);
    end
    if ~plan.has_conflicts
        [plan, appliedCounts] = alignmentApplyPlan(conn, plan);
        result = alignmentPlanResult(plan);
        result.status = plan.status;
        result.committed = true;
        result.applied_counts = appliedCounts;
        return
    end
end

result = alignmentPlanResult(plan);
end
