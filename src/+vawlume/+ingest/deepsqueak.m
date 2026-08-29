function result = deepsqueak(conn, artifactPath, recordingRef, runSpec, options)
%DEEPSQUEAK Plan or atomically apply a DeepSqueak call-statistics import.
%
% RESULT = vawlume.ingest.deepsqueak(CONN, ARTIFACTPATH, RECORDINGREF, RUNSPEC)
% reads a DeepSqueak Excel call-statistics export, resolves it against an
% already-established recording, and classifies the extractor, output mapping
% profile, settings, model, extraction run, and artifacts as create, reuse, or
% conflict. Planning is the default and writes nothing.
%
% RESULT = vawlume.ingest.deepsqueak(..., Apply=true) commits a conflict-free
% plan in one transaction.
%
% RECORDINGREF selects one recording that project intake already created, using
% exactly one of:
%
%   recordingRef = struct(recording_id=42)
%   recordingRef = struct(project_key="proj", source_relative_path="raw/REC_A.wav")
%
% The workbook basename, the export's File column, and folder conventions are
% never used to infer the recording. This function does not create projects,
% source files, recordings, entities, or participant links; it consumes the graph
% project intake established.
%
% RUNSPEC declares what a call-statistics export cannot state about itself:
%
%   runSpec.run_key            (required) stable identity of this extraction run,
%                              unique within the project
%   runSpec.extractor_version  (required) the DeepSqueak version that produced
%                              the export; required because the tracked profile
%                              declares extractor.version_required_at_ingest
%   runSpec.run_label          optional display label
%   runSpec.notes              optional free text
%   runSpec.started_at_utc     optional, only when genuinely known; never
%   runSpec.completed_at_utc   inferred from file timestamps
%   runSpec.status             optional extraction-run status, default "imported"
%   runSpec.settings           optional, either
%                                struct(profile_path=..., version_label=...) for
%                                a VAWLUME extractor-settings profile, or
%                                struct(artifact_path=..., native_type=...) for
%                                an external native settings file
%   runSpec.model              optional struct(artifact_path=..., model_label=...)
%   runSpec.native_artifact    optional struct(artifact_path=...) for the
%                              DeepSqueak .mat detection container, which is
%                              registered but not parsed
%
% Absent settings or model evidence is recorded as unavailable. No default
% configuration is substituted and no detector model is inferred from the
% DeepSqueak version, the machine's defaults, or the export's score column.
%
% Name-value options:
%   Apply         commit a conflict-free plan (default false)
%   RepoRoot      repository root, used to locate the tracked profile and to
%                 derive portable artifact paths
%   ArtifactRoot  root that artifact portable paths are taken from
%   RelativePath  explicit portable path for the export
%   ProfilePath   mapping profile JSON, defaulting to the tracked DeepSqueak one
%   Profile       an already-loaded profile bundle, so importing many exports
%                 does not reload and revalidate the same JSON each time
%   Sheet         explicit worksheet, overriding the profile's selector
%
% Artifact identity is a portable path plus a content checksum, so relocating an
% unchanged export reuses its artifact row rather than duplicating it, and the
% same portable path carrying different content is an explicit conflict.
%
% This pass establishes the run and provenance graph. Detections and measurements
% are inserted by a later pass inside this same transaction, so a failure there
% cannot leave an orphaned extraction run behind.
%
% See also VAWLUME.INGEST.DEEPSQUEAKEXPORT, VAWLUME.INGEST.PROJECT.

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
    options.Sheet (1,1) string = ""
end

declaredVersion = "";
if isfield(runSpec, "extractor_version")
    declaredVersion = string(runSpec.extractor_version);
end

export = vawlume.ingest.deepsqueakExport(artifactPath, ...
    RepoRoot=options.RepoRoot, ...
    ArtifactRoot=options.ArtifactRoot, ...
    RelativePath=options.RelativePath, ...
    ProfilePath=options.ProfilePath, ...
    Profile=options.Profile, ...
    Sheet=options.Sheet, ...
    ExtractorVersion=declaredVersion);

roots = [options.ArtifactRoot, options.RepoRoot];
plan = deepsqueakBuildPlan(conn, export, recordingRef, runSpec, roots);

if options.Apply && ~plan.has_conflicts
    [plan, appliedCounts] = deepsqueakApplyPlan(conn, plan);
    result = deepsqueakPlanResult(plan);
    result.status = "committed";
    result.committed = true;
    result.applied_counts = appliedCounts;
    return
end

result = deepsqueakPlanResult(plan);
end
