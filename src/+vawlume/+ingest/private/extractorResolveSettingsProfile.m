function settings = extractorResolveSettingsProfile(conn, projectId, declared, errorToken)
%EXTRACTORRESOLVESETTINGSPROFILE Resolve explicit project-scoped settings JSON.

arguments
    conn
    projectId (1,1) double
    declared (1,1) struct
    errorToken (1,1) string
end

settings = struct(mode=declared.mode, status=declared.status, ...
    profile_action="none", version_action="none", profile_id=NaN, ...
    profile_version_id=NaN, profile_key="", version_label="", ...
    content_uri="", content_format="", checksum_sha256="", conflict_message="");
if declared.mode ~= "profile"
    return
end

profilePath = declared.profile_path;
if ~isfile(profilePath)
    error(errorId(errorToken, "SettingsNotFound"), ...
        "Declared settings profile does not exist: %s", profilePath);
end
loaded = readSettingsProfile(profilePath, errorToken);
requiredFormat = optionalField(declared, "required_format");
if strlength(requiredFormat) > 0 && loaded.content_format ~= requiredFormat
    error(errorId(errorToken, "SettingsUnsupported"), ...
        "Settings profile must use %s format: %s", requiredFormat, profilePath);
end
requiredKind = optionalField(declared, "required_kind");
if strlength(requiredKind) > 0 && loaded.profile_kind ~= requiredKind
    error(errorId(errorToken, "SettingsInvalid"), ...
        "Settings profile %s must declare profile.kind '%s'.", profilePath, requiredKind);
end
settings.profile_key = firstNonempty(declared.profile_key, loaded.profile_key);
settings.version_label = firstNonempty(declared.version_label, loaded.version_label);
if strlength(settings.profile_key) == 0
    error(errorId(errorToken, "SettingsInvalid"), ...
        "Settings profile %s declares no profile id and runSpec supplies no profile_key.", profilePath);
end
if strlength(settings.version_label) == 0
    error(errorId(errorToken, "SettingsInvalid"), ...
        "Settings profile %s declares no profile_version and runSpec supplies no version_label.", profilePath);
end
settings.profile_name = firstNonempty(loaded.profile_name, settings.profile_key);
settings.content_uri = loaded.content_uri;
settings.content_format = loaded.content_format;
settings.checksum_sha256 = loaded.checksum_sha256;
settings.description = declared.description;

rows = fetch(conn, "SELECT profile_id, profile_kind FROM config_profiles " + ...
    "WHERE project_id = " + string(projectId) + ...
    " AND profile_key = " + sqlText(settings.profile_key));
if isempty(rows) || height(rows) == 0
    settings.profile_action = "create";
    settings.version_action = "create";
    return
end
settings.profile_id = double(rows.profile_id(1));
if string(rows.profile_kind(1)) ~= "extractor_settings"
    settings.profile_action = "conflict";
    settings.conflict_message = "Project profile key '" + settings.profile_key + ...
        "' is already registered as kind '" + string(rows.profile_kind(1)) + ...
        "', not extractor_settings.";
    return
end
settings.profile_action = "reuse";
versions = fetch(conn, "SELECT profile_version_id, IFNULL(checksum_sha256, '') AS checksum_sha256 " + ...
    "FROM config_profile_versions WHERE profile_id = " + string(settings.profile_id) + ...
    " AND version_label = " + sqlText(settings.version_label));
if isempty(versions) || height(versions) == 0
    settings.version_action = "create";
    return
end
settings.profile_version_id = double(versions.profile_version_id(1));
storedChecksum = string(versions.checksum_sha256(1));
if strlength(storedChecksum) > 0 && strlength(settings.checksum_sha256) > 0 && ...
        storedChecksum ~= settings.checksum_sha256
    settings.version_action = "conflict";
    settings.conflict_message = "Settings profile '" + settings.profile_key + ...
        "' version '" + settings.version_label + "' is registered with checksum " + ...
        storedChecksum + " but the supplied file has checksum " + settings.checksum_sha256 + ".";
    return
end
settings.version_action = "reuse";
end

function loaded = readSettingsProfile(path, errorToken)
loaded = struct(profile_key="", profile_name="", profile_kind="", version_label="", ...
    content_uri=replace(string(path), "\", "/"), content_format="", ...
    checksum_sha256=sha256OfFile(path));
[~,~,extension] = fileparts(path);
loaded.content_format = lower(erase(string(extension), "."));
if ~ismember(loaded.content_format, ["yaml", "yml", "json", "toml"])
    loaded.content_format = "other";
end
if loaded.content_format ~= "json"
    return
end
try
    document = jsondecode(fileread(path));
catch exception
    error(errorId(errorToken, "SettingsInvalid"), ...
        "Could not decode settings profile %s: %s", path, exception.message);
end
if ~isstruct(document) || ~isfield(document, "profile") || ~isstruct(document.profile)
    return
end
loaded.profile_key = fieldText(document.profile, "id");
loaded.profile_name = fieldText(document.profile, "name");
loaded.profile_kind = fieldText(document.profile, "kind");
loaded.version_label = fieldText(document.profile, "profile_version");
end

function value = optionalField(container, field)
value = "";
if isfield(container, char(field))
    try
        candidate = string(container.(char(field)));
        if isscalar(candidate) && ~ismissing(candidate)
            value = strtrim(candidate);
        end
    catch
    end
end
end

function value = fieldText(container, field)
value = "";
if ~isfield(container, char(field))
    return
end
try
    candidate = string(container.(char(field)));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = strtrim(candidate);
end
end
function value = firstNonempty(first, second)
value = string(first);
if strlength(value) == 0
    value = string(second);
end
end
function value = errorId(token, suffix)
value = "vawlume:ingest:" + token + suffix;
end
function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
