function result = mupet(conn, artifactPath, recordingRef, runSpec, options)
%MUPET Plan MUPET recording/run/profile/settings/artifact provenance.
%
% Planning is read-only. Phase 5 Pass 3 intentionally does not create an
% extraction run because event population is delivered atomically in Pass 4.
% Native processed .mat evidence is hashed and registered in the plan only; it
% is never parsed. MUPET dataset/workspace names remain extractor provenance and
% never create experimental hierarchy entities.

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
    error("vawlume:ingest:MupetApplyNotAvailable", ...
        "MUPET apply is deferred to Phase 5 Pass 4 so the run and its events can be committed atomically.");
end
result = mupetPlanResult(plan);
end
