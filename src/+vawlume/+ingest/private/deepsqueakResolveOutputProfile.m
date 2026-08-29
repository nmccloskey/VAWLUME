function profile = deepsqueakResolveOutputProfile(conn, irProfile)
%DEEPSQUEAKRESOLVEOUTPUTPROFILE Resolve the exact registered output-mapping version.
%
% Provenance is taken from the IR the adapter already produced, so the profile
% JSON is never reopened or reinterpreted here. The registered version must
% already exist, because the same seed registration also creates the
% extractor_features and feature_mappings that event measurements depend on: an
% unregistered profile means the semantic layer is absent, not that this
% importer should invent it.

arguments
    conn
    irProfile (1,1) struct
end

profile = struct();
profile.profile_key = string(irProfile.profile_key);
profile.profile_kind = string(irProfile.profile_kind);
profile.version_label = string(irProfile.profile_version);
profile.profile_schema_version = string(irProfile.profile_schema_version);
profile.content_format = string(irProfile.profile_content_format);
profile.content_uri = string(irProfile.profile_path);
profile.checksum_sha256 = string(irProfile.profile_checksum);
profile.action = "reuse";
profile.conflict_message = "";
profile.profile_id = NaN;
profile.profile_version_id = NaN;

if profile.profile_kind ~= "extractor_output"
    error("vawlume:ingest:DeepSqueakProfileUnsupported", ...
        "Expected an extractor_output mapping profile, found '%s'.", ...
        profile.profile_kind);
end

profileRows = fetch(conn, ...
    "SELECT profile_id, profile_kind FROM config_profiles " + ...
    "WHERE profile_key = " + sqlText(profile.profile_key) + ...
    " AND project_id IS NULL");
if isempty(profileRows) || height(profileRows) == 0
    error("vawlume:ingest:DeepSqueakProfileUnregistered", ...
        ['Output mapping profile ''%s'' is not registered. Run ' ...
        'vawlume.db.registerBuiltinSemantics before importing extractor output.'], ...
        profile.profile_key);
end
profile.profile_id = double(profileRows.profile_id(1));

storedKind = string(profileRows.profile_kind(1));
if storedKind ~= profile.profile_kind
    profile.action = "conflict";
    profile.conflict_message = "Registered profile kind '" + storedKind + ...
        "' does not match the IR profile kind '" + profile.profile_kind + "'.";
    return
end

versionRows = fetch(conn, ...
    "SELECT profile_version_id, version_label, " + ...
    "IFNULL(profile_schema_version, '') AS profile_schema_version, " + ...
    "IFNULL(content_format, '') AS content_format, " + ...
    "IFNULL(content_uri, '') AS content_uri, " + ...
    "IFNULL(checksum_sha256, '') AS checksum_sha256 " + ...
    "FROM config_profile_versions WHERE profile_id = " + string(profile.profile_id) + ...
    " AND version_label = " + sqlText(profile.version_label));
if isempty(versionRows) || height(versionRows) == 0
    error("vawlume:ingest:DeepSqueakProfileUnregistered", ...
        ['Output mapping profile ''%s'' has no registered version ''%s''. Run ' ...
        'vawlume.db.registerBuiltinSemantics for the current tracked profile.'], ...
        profile.profile_key, profile.version_label);
end

profile.profile_version_id = double(versionRows.profile_version_id(1));
storedChecksum = string(versionRows.checksum_sha256(1));
storedUri = string(versionRows.content_uri(1));
storedSchemaVersion = string(versionRows.profile_schema_version(1));

% The checksum is the load-bearing comparison: an edited profile carrying the
% same version label is a semantic-drift conflict, not a silent reuse.
if strlength(storedChecksum) > 0 && strlength(profile.checksum_sha256) > 0 && ...
        storedChecksum ~= profile.checksum_sha256
    profile.action = "conflict";
    profile.conflict_message = "Registered profile version '" + ...
        profile.version_label + "' has checksum " + storedChecksum + ...
        " but the loaded profile has checksum " + profile.checksum_sha256 + ".";
    return
end

if strlength(storedSchemaVersion) > 0 && strlength(profile.profile_schema_version) > 0 && ...
        storedSchemaVersion ~= profile.profile_schema_version
    profile.action = "conflict";
    profile.conflict_message = "Registered profile version '" + ...
        profile.version_label + "' declares profile-language version " + ...
        storedSchemaVersion + " but the loaded profile declares " + ...
        profile.profile_schema_version + ".";
    return
end

profile.registered_content_uri = storedUri;
profile.registered_checksum_sha256 = storedChecksum;
end

function text = sqlText(value)
text = "'" + replace(string(value), "'", "''") + "'";
end
