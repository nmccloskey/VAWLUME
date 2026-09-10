function result = usvseg(conn, artifactPath, recordingRef, runSpec, options)
%USVSEG Plan or atomically apply a USVSEG syllable-export import.
%
% RESULT = vawlume.ingest.usvseg(CONN, ARTIFACTPATH, RECORDINGREF, RUNSPEC)
% reads one USVSEG `<stem>_dat.csv` event export, resolves it against a
% recording project intake already established, and classifies the extractor,
% output mapping profile, artifacts, extraction run, syllable detections, event
% measurements, and preserved unmapped source values as create, reuse, or
% conflict. Planning is the default and writes nothing.
%
% RECORDINGREF names the recording explicitly, using the same selectors as the
% other extractor importers:
%
%   struct(recording_id=1)
%   struct(project_key="project-a", source_relative_path="audio/rec1.wav")
%
% The recording is never inferred from the CSV basename. USVSEG names every
% output after its input file's stem, but that correspondence is a naming
% convention rather than recorded provenance.
%
% RESULT = vawlume.ingest.usvseg(..., Apply=true) commits a conflict-free plan
% in one transaction covering the run and its complete syllable population, so
% an extraction run never exists without the syllables it produced.
%
% USVSEG writes no version string into any output, so
% RUNSPEC.extractor_version is required caller evidence and is assessed against
% the mapping profile's declared scope. A missing declaration raises
% vawlume:ingest:UsvsegVersionRequired; an out-of-scope one raises
% vawlume:ingest:UsvsegVersionIncompatible.
%
% Settings evidence is optional. USVSEG writes usvseg_prm.mat when the
% application closes, holding whatever parameters were active at that moment,
% and not beside the CSV it may or may not correspond to. Requiring it would
% refuse ordinary correct output. Supply it through
% RUNSPEC.settings.artifact_path to have it hashed and registered as
% application-scoped weak evidence; it never becomes the run's
% settings_profile_version_id and is never presented as the verified
% configuration of the run. Absent settings are recorded as unavailable rather
% than filled from published USVSEG defaults.
%
% A header-only export is a valid zero-detection segmentation pass and commits
% run and artifact provenance with no detections. Source columns the profile
% does not claim are preserved row by row in unmapped_source_values rather than
% discarded, while an unexpected curation or classification column is refused:
% USVSEG exports no review or class evidence, so such a column means the
% artifact is not what this profile describes.
%
% No curation, classification, detection-score, or frequency-bound row is
% created. USVSEG exports none of them, and none may be synthesized from the
% columns it does export.
%
% How this importer's requirements compare with the other shipped extractors,
% which differ in exactly two places, is documented in
% docs/development/21_usvseg_import.md.
%
% See also VAWLUME.INGEST.USVSEGEXPORT.

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
