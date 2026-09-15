function result = registerProfileVersion(conn, projectRef, spec, options)
%REGISTERPROFILEVERSION Register one checksum-bearing configuration profile version.
%
%   result = VAWLUME.DB.REGISTERPROFILEVERSION(conn, projectRef, spec)
%
% A configuration profile version is how VAWLUME cites the settings an analysis
% ran under: `attribution_runs`, `attribution_decisions` and
% `imported_attribution_windows` all reference one by ID, and the checksum is
% what makes that citation mean something years later. Until this function
% existed, no public path created one -- every test seeded the two rows by SQL
% and usage guide §7.7 carried the same workaround, so a user could not create
% an attribution run without hand-writing INSERTs.
%
% PROJECTREF selects the owning project with exactly one of:
%
%   struct(project_id=3)
%   struct(project_key="my_project")
%
% SPEC requires:
%
%   profile_key     project-scoped immutable identity for the profile
%   profile_name    human-readable name
%   version_label   the version being registered, e.g. "1.0.0"
%   content_path    path to the file being registered
%
% and optionally accepts profile_kind (default "analysis_settings"),
% profile_schema_version, content_format (default inferred from the extension),
% description, notes, and is_snapshot (default true).
%
% THE FILE IS HASHED, NOT COPIED. VAWLUME stores the path and the digest; the
% bytes stay where they are. A stored `content_uri` is repository-relative when
% the file lives under the repository root and absolute otherwise, matching the
% rule the import path already uses, so a profile registered from `config/` is as
% portable as an imported one and a profile registered from elsewhere is honest
% about being machine-local.
%
% RE-REGISTERING AN IDENTICAL VERSION REUSES IT. Re-registering the same
% version_label over different bytes raises
% `vawlume:db:ProfileVersionConflict` rather than rewriting: decisions and
% imported windows already cite that version by ID, and changing what it denotes
% underneath them would silently re-point evidence. Publish a new version_label
% instead.
%
% PROFILE_KIND IS VALIDATED AGAINST THE SCHEMA, not against a list copied into
% MATLAB. The vocabulary is read from the live `config_profiles` definition, so
% adding a kind to the schema does not require editing this function.
%
% This function registers a profile version and nothing else. It reads no
% profile content, validates no profile grammar, and assigns the version to no
% analysis. Each layer that consumes a profile still validates its own.
%
% See also VAWLUME.DB.REGISTERBUILTINSEMANTICS, VAWLUME.ATTRIBUTION.CREATERUN

arguments
    conn
    projectRef (1,1) struct
    spec (1,1) struct
    options.RepoRoot (1,1) string = ""
end

repoRoot = resolveRepoRoot(options.RepoRoot);
project = resolveProject(conn, projectRef);
declared = normalizeSpec(spec, repoRoot);
assertKindDeclared(conn, declared.profile_kind);

existing = fetch(conn, "SELECT p.profile_id AS profile_id, " + ...
    "IFNULL(v.profile_version_id,-1) AS version_id, " + ...
    "IFNULL(v.checksum_sha256,'') AS checksum, " + ...
    "p.profile_kind AS profile_kind " + ...
    "FROM config_profiles p LEFT JOIN config_profile_versions v " + ...
    "  ON v.profile_id = p.profile_id AND v.version_label=" + ...
    sqlText(declared.version_label) + ...
    " WHERE p.project_id=" + string(project.project_id) + ...
    " AND p.profile_key=" + sqlText(declared.profile_key));

if height(existing) > 0
    profileId = double(existing.profile_id(1));
    storedKind = presentText(existing.profile_kind(1));
    % The kind belongs to the profile, not the version. Registering a second
    % version under a different kind would make the profile mean two things.
    if storedKind ~= declared.profile_kind
        error("vawlume:db:ProfileKindConflict", ...
            "Profile '%s' is already registered as kind '%s'. Register a " + ...
            "different profile_key rather than redefining this one.", ...
            declared.profile_key, storedKind);
    end
    versionId = double(existing.version_id(1));
    if versionId > 0
        stored = presentText(existing.checksum(1));
        if stored ~= "" && stored ~= declared.checksum_sha256
            error("vawlume:db:ProfileVersionConflict", ...
                "Profile '%s' version '%s' is already registered with a " + ...
                "different checksum. Decisions and imported windows cite this " + ...
                "version by ID; publish a new version_label rather than " + ...
                "editing one that is already referenced.", ...
                declared.profile_key, declared.version_label);
        end
        result = profileResult(profileId, versionId, project, declared, "reused");
        return
    end
else
    profileId = dbInsertRow(conn, "config_profiles", struct( ...
        project_id=project.project_id, ...
        profile_key=declared.profile_key, ...
        profile_name=declared.profile_name, ...
        profile_kind=declared.profile_kind, ...
        description=declared.description), "profile_id");
end

versionId = dbInsertRow(conn, "config_profile_versions", struct( ...
    profile_id=profileId, ...
    version_label=declared.version_label, ...
    profile_schema_version=declared.profile_schema_version, ...
    content_format=declared.content_format, ...
    content_uri=declared.content_uri, ...
    checksum_sha256=declared.checksum_sha256, ...
    is_snapshot=declared.is_snapshot, ...
    notes=declared.notes), "profile_version_id");

result = profileResult(profileId, versionId, project, declared, "created");
end

% ---------------------------------------------------------------- helpers ---

function declared = normalizeSpec(spec, repoRoot)
required = ["profile_key", "profile_name", "version_label", "content_path"];
allowed = [required, "profile_kind", "profile_schema_version", ...
    "content_format", "description", "notes", "is_snapshot"];
unknown = setdiff(string(fieldnames(spec))', allowed);
if ~isempty(unknown)
    error("vawlume:db:ProfileSpecInvalid", ...
        "Unknown profile spec fields: %s.", strjoin(unknown, ", "));
end
for field = required
    if ~isfield(spec, field) || strlength(strtrim(string(spec.(field)))) == 0
        error("vawlume:db:ProfileSpecInvalid", ...
            "Profile spec requires nonempty %s.", field);
    end
end

contentPath = string(spec.content_path);
if ~java.io.File(char(contentPath)).isAbsolute()
    contentPath = fullfile(repoRoot, contentPath);
end
contentPath = string(java.io.File(char(contentPath)).getCanonicalPath());
if ~isfile(contentPath)
    error("vawlume:db:ProfileContentNotFound", ...
        "Profile content does not exist: %s", contentPath);
end

declared = struct( ...
    profile_key=strtrim(string(spec.profile_key)), ...
    profile_name=strtrim(string(spec.profile_name)), ...
    version_label=strtrim(string(spec.version_label)), ...
    profile_kind=optionalTextOr(spec, "profile_kind", "analysis_settings"), ...
    profile_schema_version=optionalTextOr(spec, "profile_schema_version", ""), ...
    content_path=contentPath, ...
    content_uri=portableUri(contentPath, repoRoot), ...
    content_format=contentFormat(spec, contentPath), ...
    checksum_sha256=dbSha256OfFile(contentPath), ...
    description=optionalTextOr(spec, "description", ""), ...
    notes=optionalTextOr(spec, "notes", ""), ...
    is_snapshot=snapshotFlag(spec));
end

function value = contentFormat(spec, contentPath)
%CONTENTFORMAT The stored format, inferred from the extension unless declared.
%
% Inferred rather than defaulted to json, because a caller registering a .toml
% and getting 'json' recorded would have a row that misdescribes its own file.
value = optionalTextOr(spec, "content_format", "");
if strlength(value) > 0
    return
end
[~, ~, extension] = fileparts(contentPath);
value = lower(erase(string(extension), "."));
if ~ismember(value, ["yaml", "yml", "json", "toml"])
    value = "other";
end
end

function value = snapshotFlag(spec)
value = 1;
if isfield(spec, "is_snapshot")
    raw = spec.is_snapshot;
    if ~isscalar(raw) || ~(islogical(raw) || isnumeric(raw))
        error("vawlume:db:ProfileSpecInvalid", ...
            "is_snapshot must be a logical scalar.");
    end
    value = double(logical(raw));
end
end

function assertKindDeclared(conn, kind)
%ASSERTKINDDECLARED Check the kind against the schema's own vocabulary.
%
% Read from the live table definition rather than from a list duplicated here. A
% second copy of a closed vocabulary is a second thing to keep consistent and a
% new way for this function to disagree with the database it writes to.
%
% If the CHECK clause cannot be located -- a schema reshaped in a way this does
% not anticipate -- pre-validation is skipped and the database's own CHECK is
% left to refuse. Degrading to a less friendly error is correct; degrading to
% accepting an invalid kind would not be.
rows = fetch(conn, "SELECT IFNULL(sql,'') AS sql FROM sqlite_master " + ...
    "WHERE type='table' AND name='config_profiles'");
if height(rows) == 0
    return
end
clause = regexp(string(rows.sql(1)), ...
    "profile_kind\s+TEXT[^(]*CHECK\s*\(\s*profile_kind\s+IN\s*\(([^)]*)\)", ...
    "tokens", "once");
if isempty(clause)
    return
end
declared = strtrim(erase(split(string(clause{1}), ","), "'"));
declared = declared(strlength(declared) > 0);
if ismember(kind, declared)
    return
end
error("vawlume:db:ProfileKindInvalid", ...
    "profile_kind '%s' is not one of: %s.", kind, strjoin(sort(declared), ", "));
end

function project = resolveProject(conn, projectRef)
hasId = isfield(projectRef, "project_id");
hasKey = isfield(projectRef, "project_key");
if hasId == hasKey
    error("vawlume:db:ProjectSelectorInvalid", ...
        "projectRef must contain exactly one of project_id or project_key.");
end
if hasId
    predicate = "project_id=" + string(double(projectRef.project_id));
else
    predicate = "project_key=" + sqlText(projectRef.project_key);
end
rows = fetch(conn, "SELECT project_id, project_key FROM projects WHERE " + predicate);
if height(rows) ~= 1
    error("vawlume:db:ProjectNotFound", ...
        "No single project matches the supplied reference.");
end
project = struct(project_id=double(rows.project_id(1)), ...
    project_key=string(rows.project_key(1)));
end

function result = profileResult(profileId, versionId, project, declared, status)
result = struct( ...
    status=string(status), ...
    project_id=project.project_id, ...
    project_key=project.project_key, ...
    profile_id=profileId, ...
    profile_version_id=versionId, ...
    profile_key=declared.profile_key, ...
    profile_kind=declared.profile_kind, ...
    version_label=declared.version_label, ...
    content_uri=declared.content_uri, ...
    content_format=declared.content_format, ...
    checksum_sha256=declared.checksum_sha256, ...
    boundary="A registered version records which settings an analysis cited. " + ...
        "It does not validate the profile's grammar; each consuming layer does.");
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

function root = resolveRepoRoot(root)
root = string(root);
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
root = string(java.io.File(char(root)).getCanonicalPath());
end

function value = optionalTextOr(spec, field, fallback)
value = string(fallback);
if isfield(spec, field)
    candidate = strtrim(string(spec.(field)));
    if isscalar(candidate) && ~ismissing(candidate) && strlength(candidate) > 0
        value = candidate;
    end
end
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
