function plan = attributionImportBuildPlan(conn, runRef, sourcePath, options)
%ATTRIBUTIONIMPORTBUILDPLAN Read, map and resolve an imported attribution table.
%
% Reads the database and the source file; writes neither.

repoRoot = resolveRepoRoot(options.RepoRoot);
profilePath = options.ProfilePath;
if strlength(profilePath) == 0
    profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
        "attribution", "generic_imported_attribution_profile.json");
end

resolvedSource = resolveSourcePath(sourcePath, repoRoot);
loaded = vawlume.source_mapping.loadProfile(profilePath, RepoRoot=repoRoot);
assertProfileUsable(loaded, profilePath);

run = attributionImportResolveRun(conn, runRef);
assertRunImportable(conn, run);

tbl = readSourceTable(resolvedSource);
ir = vawlume.source_mapping.mapTableToIR(tbl, loaded, ...
    SourceKey="source:" + filenameOf(resolvedSource), ...
    RuntimePath=resolvedSource, RepoRoot=repoRoot);

claims = ir.attribution_claims;
windows = ir.attribution_windows;

% Resolution is declared in the profile; this is where the declaration meets the
% database. A label whose declared entity is not among the run's participating
% entities is a surfaced problem, not a new entity, and every offending label is
% named at once rather than one per re-run.
[claims, unresolved] = resolveEntities(conn, run, claims);
if ~isempty(unresolved)
    error("vawlume:attribution:CallerLabelUnresolved", ...
        "These caller labels resolve to no participating entity of run %s: %s. " + ...
        "Declare them in the profile's caller_label_resolution map, or add the " + ...
        "entities to the run. VAWLUME does not create an entity to accommodate " + ...
        "an imported label.", run.run_key, strjoin(unresolved, ", "));
end

plan = struct();
plan.run = run;
plan.repo_root = repoRoot;
plan.source = struct( ...
    runtime_path=resolvedSource, ...
    relative_path=portableUri(resolvedSource, repoRoot), ...
    filename=filenameOf(resolvedSource), ...
    checksum_sha256=attributionImportSha256(resolvedSource), ...
    source_row_count=height(tbl));
plan.profile = struct( ...
    profile_path=string(loaded.source_path), ...
    profile_key=string(loaded.profile.id), ...
    profile_name=string(loaded.profile.name), ...
    profile_kind=string(loaded.profile.kind), ...
    profile_schema_version=string(loaded.profile.profile_schema_version), ...
    version_label=string(loaded.profile.profile_version), ...
    checksum_sha256=string(loaded.checksum_sha256), ...
    content_uri=portableUri(string(loaded.source_path), repoRoot));
plan.exporting_system = exportingSystemOf(claims, loaded);
plan.windows = windows;
plan.claims = claims;
plan.issues = ir.issues;
plan.unmapped_rows = height(tbl) - height(claims);
plan.has_conflicts = false;

if height(claims) == 0
    error("vawlume:attribution:ImportEmpty", ...
        "No row of %s could be mapped into an attribution claim. " + ...
        "Inspect the plan's issues rather than re-running.", plan.source.filename);
end
end

% ---------------------------------------------------------------- helpers ---

function assertProfileUsable(loaded, profilePath)
if string(loaded.profile.kind) ~= "attribution_input_mapping"
    error("vawlume:attribution:ProfileKindInvalid", ...
        "%s declares kind %s; an attribution import requires attribution_input_mapping.", ...
        profilePath, string(loaded.profile.kind));
end
if height(loaded.issues) > 0 && any(loaded.issues.severity == "error")
    error("vawlume:attribution:ProfileInvalid", ...
        "Mapping profile %s has validation errors and cannot be used.", profilePath);
end
end

function assertRunImportable(conn, run)
if run.attribution_path ~= "imported"
    error("vawlume:attribution:RunPathMismatch", ...
        "Run %s declares attribution_path %s; only an imported run accepts an import.", ...
        run.run_key, run.attribution_path);
end
if run.status ~= "planned" || run.analysis_status ~= "started"
    error("vawlume:attribution:RunNotWritable", ...
        "An import may only be applied while attribution status is planned and analysis status is started.");
end
% Evidence rows have no natural key, so a second apply would append duplicates
% rather than reconcile them. Refusing is honest; silently appending is not.
existing = fetch(conn, "SELECT COUNT(*) AS n FROM imported_attribution_windows " + ...
    "WHERE attribution_run_id=" + string(run.attribution_run_id));
if double(existing.n(1)) > 0
    error("vawlume:attribution:ImportAlreadyApplied", ...
        "Run %s already carries %d imported windows. Evidence is append-only, " + ...
        "so a second import would duplicate rather than reconcile. Create a new run.", ...
        run.run_key, double(existing.n(1)));
end
end

function [claims, unresolved] = resolveEntities(conn, run, claims)
unresolved = strings(0, 1);
if height(claims) == 0
    claims.entity_id = zeros(0, 1);
    return
end
entityIds = NaN(height(claims), 1);
for index = 1:height(claims)
    nativeId = string(claims.entity_native_id(index));
    rows = fetch(conn, "SELECT entity_id FROM experimental_entities " + ...
        "WHERE project_id=" + string(run.project_id) + " AND native_id=" + ...
        sqlText(nativeId));
    if isempty(rows) || height(rows) == 0
        unresolved(end+1, 1) = string(claims.caller_label(index)) + ...
            " (declared as entity " + nativeId + ", which does not exist)"; %#ok<AGROW>
        continue
    end
    candidateId = double(rows.entity_id(1));
    if ~ismember(candidateId, run.participating_entity_ids)
        unresolved(end+1, 1) = string(claims.caller_label(index)) + ...
            " (entity " + nativeId + " is not a participant of this run)"; %#ok<AGROW>
        continue
    end
    entityIds(index) = candidateId;
end
unresolved = unique(unresolved, "stable");
claims.entity_id = entityIds;
end

function value = exportingSystemOf(claims, loaded)
value = struct(name="", version="");
if height(claims) > 0
    value.name = string(claims.exporting_system(1));
    value.version = string(claims.exporting_system_version(1));
    return
end
context = loaded.profile_documents{1}.context;
value.name = string(context.exporting_system);
if isfield(context, "exporting_system_version")
    value.version = string(context.exporting_system_version);
end
end

function tbl = readSourceTable(path)
if ~isfile(path)
    error("vawlume:attribution:SourceNotFound", ...
        "Attribution source table does not exist: %s", path);
end
try
    tbl = readtable(path, TextType="string", VariableNamingRule="preserve");
catch exception
    error("vawlume:attribution:SourceUnreadable", ...
        "Could not read attribution source table %s: %s", path, exception.message);
end
end

function value = resolveSourcePath(sourcePath, repoRoot)
if ~java.io.File(char(sourcePath)).isAbsolute()
    sourcePath = fullfile(repoRoot, sourcePath);
end
value = string(java.io.File(char(sourcePath)).getCanonicalPath());
end

function root = resolveRepoRoot(root)
root = string(root);
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath"))))));
end
root = string(java.io.File(char(root)).getCanonicalPath());
end

function value = portableUri(path, repoRoot)
path = replace(string(path), "\", "/");
root = strip(replace(string(repoRoot), "\", "/"), "right", "/");
prefix = root + "/";
if startsWith(lower(path), lower(prefix))
    value = extractAfter(path, strlength(prefix));
else
    value = path;
end
end

function value = filenameOf(path)
[~, name, ext] = fileparts(string(path));
value = name + ext;
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
