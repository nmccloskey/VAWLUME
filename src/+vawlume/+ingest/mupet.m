function result = mupet(conn, artifactPath, recordingRef, runSpec, options)
%MUPET Plan or atomically apply a MUPET per-syllable CSV import.
%
% RESULT = vawlume.ingest.mupet(CONN, ARTIFACTPATH, RECORDINGREF, RUNSPEC) reads
% one supported MUPET per-syllable CSV, resolves it against a recording project
% intake already established, and classifies the extractor, output mapping
% profile, settings, artifacts, extraction run, syllable detections, and event
% measurements as create, reuse, or conflict. Planning is the default and writes
% nothing.
%
% RESULT = vawlume.ingest.mupet(..., Apply=true) commits a conflict-free plan in
% one transaction covering the run and its complete syllable population, so an
% extraction run never exists without the syllables it produced.
%
% Settings provenance is required to apply. MUPET's segmentation and filtering
% behaviour is settings-dependent and MUPET itself reprocesses a recording when
% its configuration changes, so a run without its exact settings evidence is not
% reproducible. Supply either the native config.csv or a VAWLUME extractor
% settings JSON; no default configuration is ever substituted and publication
% defaults are never inserted.
%
% No curation or classification rows are created. The per-syllable CSV exports no
% row-level review state and no class label, and surviving MUPET's programmatic
% duration/energy/amplitude filtering is not a reviewed state. Those filter
% thresholds are recorded once as run-level settings provenance.
%
% Native processed .mat evidence is hashed and registered but never parsed, and
% is never accepted as settings evidence. MUPET dataset/workspace names remain
% extractor provenance and never create experimental hierarchy entities.

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

context = mupetValidateRunContext(recordingRef, runSpec);
configPath = "";
settingsRelativePath = "";
if context.settings.mode == "config_csv"
    configPath = context.settings.config_path;
    settingsRelativePath = context.settings.relative_path;
end
export = vawlume.ingest.mupetExport(artifactPath, RepoRoot=options.RepoRoot, ...
    ArtifactRoot=options.ArtifactRoot, RelativePath=options.RelativePath, ...
    ProfilePath=options.ProfilePath, Profile=options.Profile, ...
    ExtractorVersion=context.run.extractor_version, SettingsConfigPath=configPath, ...
    SettingsArtifactRoot=options.ArtifactRoot, SettingsRelativePath=settingsRelativePath);
plan = mupetBuildPlan(conn, export, recordingRef, runSpec, ...
    [options.ArtifactRoot, options.RepoRoot]);
if options.Apply
    if ~plan.provenance_complete
        error("vawlume:ingest:MupetSettingsRequired", ...
            "MUPET apply requires native config.csv or a VAWLUME settings JSON.");
    end
    if ~plan.has_conflicts
        [plan, appliedCounts] = mupetApplyPlan(conn, plan);
        result = mupetPlanResult(plan);
        result.status = "committed";
        result.committed = true;
        result.applied_counts = appliedCounts;
        return
    end
end
result = mupetPlanResult(plan);
end
