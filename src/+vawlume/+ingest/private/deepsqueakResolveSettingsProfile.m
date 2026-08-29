function settings = deepsqueakResolveSettingsProfile(conn, projectId, declared)
%DEEPSQUEAKRESOLVESETTINGSPROFILE Resolve an explicit extractor-settings profile.
%
% An extractor settings profile records how one run was configured. It is a
% different profile kind from the extractor-output mapping profile, which records
% how VAWLUME interprets that run's output, and the two are never conflated: they
% occupy separate columns on extraction_runs and separate config_profiles rows.
%
% Settings profiles are run evidence rather than shipped vocabulary, so they are
% registered against the project instead of the built-in namespace. When no
% settings evidence exists the relationship stays absent; no default
% configuration is ever substituted.

arguments
    conn
    projectId (1,1) double
    declared (1,1) struct
end

settings = struct( ...
    mode=declared.mode, ...
    status=declared.status, ...
    profile_action="none", ...
    version_action="none", ...
    profile_id=NaN, ...
    profile_version_id=NaN, ...
    profile_key="", ...
    version_label="", ...
    content_uri="", ...
    content_format="", ...
    checksum_sha256="", ...
    conflict_message="");

if declared.mode ~= "profile"
    return
end

profilePath = declared.profile_path;
if ~isfile(profilePath)
    error("vawlume:ingest:DeepSqueakSettingsNotFound", ...
        "Declared settings profile does not exist: %s", profilePath);
end

loaded = readSettingsProfile(profilePath);
settings.profile_key = firstNonempty(declared.profile_key, loaded.profile_key);
settings.version_label = firstNonempty(declared.version_label, loaded.version_label);
if strlength(settings.profile_key) == 0
    error("vawlume:ingest:DeepSqueakSettingsInvalid", ...
        ['Settings profile %s declares no profile id, and runSpec.settings ' ...
        'supplied no profile_key.'], profilePath);
end
if strlength(settings.version_label) == 0
    error("vawlume:ingest:DeepSqueakSettingsInvalid", ...
        ['Settings profile %s declares no profile_version, and ' ...
        'runSpec.settings supplied no version_label.'], profilePath);
end

settings.profile_name = firstNonempty(loaded.profile_name, settings.profile_key);
settings.content_uri = loaded.content_uri;
settings.content_format = loaded.content_format;
settings.checksum_sha256 = loaded.checksum_sha256;
settings.description = declared.description;

profileRows = fetch(conn, ...
    "SELECT profile_id, profile_kind FROM config_profiles " + ...
    "WHERE project_id = " + string(projectId) + ...
    " AND profile_key = " + sqlText(settings.profile_key));
if isempty(profileRows) || height(profileRows) == 0
    settings.profile_action = "create";
    settings.version_action = "create";
    return
end

settings.profile_id = double(profileRows.profile_id(1));
storedKind = string(profileRows.profile_kind(1));
if storedKind ~= "extractor_settings"
    settings.profile_action = "conflict";
    settings.conflict_message = "Project profile key '" + settings.profile_key + ...
        "' is already registered as kind '" + storedKind + ...
        "', not extractor_settings.";
    return
end
settings.profile_action = "reuse";

versionRows = fetch(conn, ...
    "SELECT profile_version_id, IFNULL(content_uri, '') AS content_uri, " + ...
    "IFNULL(checksum_sha256, '') AS checksum_sha256 " + ...
    "FROM config_profile_versions WHERE profile_id = " + string(settings.profile_id) + ...
    " AND version_label = " + sqlText(settings.version_label));
if isempty(versionRows) || height(versionRows) == 0
    settings.version_action = "create";
    return
end

settings.profile_version_id = double(versionRows.profile_version_id(1));
storedChecksum = string(versionRows.checksum_sha256(1));
if strlength(storedChecksum) > 0 && strlength(settings.checksum_sha256) > 0 && ...
        storedChecksum ~= settings.checksum_sha256
    settings.version_action = "conflict";
    settings.conflict_message = "Settings profile '" + settings.profile_key + ...
        "' version '" + settings.version_label + "' is registered with checksum " + ...
        storedChecksum + " but the supplied file has checksum " + ...
        settings.checksum_sha256 + ".";
    return
end
settings.version_action = "reuse";
end

function loaded = readSettingsProfile(profilePath)
% Identity and provenance only. A settings profile describes an external tool's
% configuration, so VAWLUME records what it is and hashes it, and does not claim
% to have validated its contents against a VAWLUME profile language.
loaded = struct(profile_key="", profile_name="", version_label="", ...
    content_uri="", content_format="", checksum_sha256="");

[~, ~, extension] = fileparts(profilePath);
loaded.content_format = lower(erase(string(extension), "."));
if ~ismember(loaded.content_format, ["yaml", "yml", "json", "toml"])
    loaded.content_format = "other";
end
loaded.content_uri = replace(string(profilePath), "\", "/");
loaded.checksum_sha256 = sha256OfFile(profilePath);

if loaded.content_format ~= "json"
    return
end
try
    document = jsondecode(fileread(profilePath));
catch exception
    error("vawlume:ingest:DeepSqueakSettingsInvalid", ...
        "Could not decode settings profile %s: %s", profilePath, exception.message);
end
if ~isstruct(document) || ~isfield(document, "profile") || ~isstruct(document.profile)
    return
end
loaded.profile_key = fieldText(document.profile, "id");
loaded.profile_name = fieldText(document.profile, "name");
loaded.version_label = fieldText(document.profile, "profile_version");
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

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end
