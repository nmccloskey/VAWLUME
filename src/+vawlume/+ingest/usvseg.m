function result = usvseg(conn, artifactPath, recordingRef, runSpec, options)
%USVSEG Plan or atomically apply a USVSEG syllable-export import.
%
% Planning is the default and writes nothing. Apply=true commits provenance,
% detections, measurements, and preserved unmapped source values together.
% USVSEG emits no version evidence, so runSpec.extractor_version is required.
% Optional runSpec.settings.artifact_path may identify usvseg_prm.mat; it is
% retained as weak application-scoped evidence, never asserted as verified
% run-scoped configuration.

arguments
    conn
    artifactPath (1,1) string
    recordingRef (1,1) struct
    runSpec (1,1) struct
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
    options.ArtifactRoot (1,1) string = ""
    options.RelativePath (1,1) string = ""
    options.ProfilePath (1,1) string = ""
    options.Profile = []
end

declaredVersion = "";
if isfield(runSpec,"extractor_version"), declaredVersion=string(runSpec.extractor_version); end
export = vawlume.ingest.usvsegExport(artifactPath, RepoRoot=options.RepoRoot, ...
    ArtifactRoot=options.ArtifactRoot, RelativePath=options.RelativePath, ...
    ProfilePath=options.ProfilePath, Profile=options.Profile, ...
    ExtractorVersion=declaredVersion);
plan = usvsegBuildPlan(conn, export, recordingRef, runSpec, ...
    [options.ArtifactRoot, options.RepoRoot]);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = usvsegApplyPlan(conn, plan);
    result = usvsegPlanResult(plan);
    result.status="committed"; result.committed=true; result.applied_counts=counts;
    return
end
result = usvsegPlanResult(plan);
end
