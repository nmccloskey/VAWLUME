function linkage = resolveProfileLinkage( ...
        conn, irProfile, profileLinkagePath, repoRoot)
%RESOLVEPROFILELINKAGE Resolve the tracked project-default acquisition context.

linkage = emptyLinkage();
if strlength(profileLinkagePath) == 0
    return
end

repoRoot = normalizedRepoRoot(repoRoot);
profileLinkagePath = resolvedPath(profileLinkagePath, repoRoot);
document = readJson(profileLinkagePath, "profile linkage");
requireStructField(document, "project", "profile linkage");
requireStructField(document.project, "source_mapping_profile", ...
    "profile linkage project");
declaredMappingProfile = scalarText( ...
    document.project.source_mapping_profile, ...
    "profile linkage project.source_mapping_profile");
if declaredMappingProfile ~= string(irProfile.profile_key)
    error("vawlume:ingest:ProfileLinkageMismatch", ...
        "Profile linkage expects project mapping profile '%s'; the IR uses '%s'.", ...
        declaredMappingProfile, string(irProfile.profile_key));
end

requireStructField(document, "recordings", "profile linkage");
requireStructField(document.recordings, ...
    "default_recording_device_profile", "profile linkage recordings");
requireStructField(document.recordings, ...
    "default_experimental_setup_profile", "profile linkage recordings");
deviceKey = scalarText( ...
    document.recordings.default_recording_device_profile, ...
    "default_recording_device_profile");
setupKey = scalarText( ...
    document.recordings.default_experimental_setup_profile, ...
    "default_experimental_setup_profile");

descriptors = emptyDescriptors();
descriptors(end + 1, :) = profileDescriptor( ...
    repoRoot, "02_device_profiles", deviceKey, "recording_device");
descriptors(end + 1, :) = profileDescriptor( ...
    repoRoot, "03_setup_profiles", setupKey, "experimental_setup");
descriptors = sortrows(descriptors, "profile_key");

linkage.enabled = true;
linkage.source_path = profileLinkagePath;
linkage.content_uri = portablePath(profileLinkagePath, repoRoot);
linkage.checksum_sha256 = sha256File(profileLinkagePath);
linkage.mapping_profile_key = declaredMappingProfile;
linkage.profiles = resolveProfiles(conn, descriptors);
linkage.defaults = table( ...
    [deviceKey; setupKey], ...
    ["default_recording_device"; "default_experimental_setup"], ...
    ["recording_device"; "experimental_setup"], ...
    repmat("project_default", 2, 1), ...
    VariableNames=["profile_key", "project_assignment_role", ...
    "recording_assignment_role", "inheritance_source"]);
linkage.deferred_sections = deferredSections(document);
end

function descriptor = profileDescriptor( ...
        repoRoot, categoryDirectory, profileKey, expectedKind)
directory = fullfile(repoRoot, "config", categoryDirectory);
files = dir(fullfile(directory, "*.json"));
if isempty(files)
    error("vawlume:ingest:LinkedProfileNotFound", ...
        "No JSON profile artifacts were found in %s.", directory);
end
[~, order] = sort(string({files.name}));
files = files(order);

matches = {};
matchPaths = strings(0, 1);
for fileIndex = 1:numel(files)
    path = string(fullfile(files(fileIndex).folder, files(fileIndex).name));
    document = readJson(path, "linked profile bundle");
    items = profileItems(document, path);
    for itemIndex = 1:numel(items)
        item = items{itemIndex};
        if isstruct(item) && isfield(item, "profile") && ...
                isstruct(item.profile) && isfield(item.profile, "id") && ...
                scalarText(item.profile.id, "linked profile id") == profileKey
            matches{end + 1, 1} = item; %#ok<AGROW>
            matchPaths(end + 1, 1) = path; %#ok<AGROW>
        end
    end
end
if isempty(matches)
    error("vawlume:ingest:LinkedProfileNotFound", ...
        "Linked profile '%s' was not found under %s.", profileKey, directory);
elseif numel(matches) > 1
    error("vawlume:ingest:LinkedProfileAmbiguous", ...
        "Linked profile '%s' is declared by more than one tracked artifact.", ...
        profileKey);
end

item = matches{1};
path = matchPaths(1);
profile = item.profile;
for field = ["id", "name", "kind", "profile_schema_version", "profile_version"]
    requireStructField(profile, field, "linked profile envelope");
end
kind = scalarText(profile.kind, "linked profile kind");
if kind ~= expectedKind
    error("vawlume:ingest:LinkedProfileInvalid", ...
        "Linked profile '%s' has kind '%s'; expected '%s'.", ...
        profileKey, kind, expectedKind);
end
requireStructField(item, "linkage", "linked profile");
requireStructField(item.linkage, "may_link_to", "linked profile linkage");
mayLinkTo = string(item.linkage.may_link_to);
if ~any(mayLinkTo(:) == "recording")
    error("vawlume:ingest:LinkedProfileInvalid", ...
        "Linked profile '%s' does not declare recording linkage.", profileKey);
end
requireStructField(item, "provenance", "linked profile");
requireStructField(item.provenance, "checksum_profile", ...
    "linked profile provenance");
if ~isscalar(item.provenance.checksum_profile) || ...
        ~logical(item.provenance.checksum_profile)
    error("vawlume:ingest:LinkedProfileInvalid", ...
        "Linked profile '%s' does not require profile checksums.", profileKey);
end

descriptor = { ...
    profileKey, scalarText(profile.name, "linked profile name"), kind, ...
    scalarText(profile.profile_version, "linked profile version"), ...
    scalarText(profile.profile_schema_version, ...
    "linked profile schema version"), ...
    "json", portablePath(path, repoRoot), sha256File(path)};
end

function profiles = resolveProfiles(conn, descriptors)
count = height(descriptors);
profiles = table( ...
    descriptors.profile_key, descriptors.profile_name, ...
    descriptors.profile_kind, repmat("create", count, 1), NaN(count, 1), ...
    descriptors.version_label, descriptors.profile_schema_version, ...
    descriptors.content_format, descriptors.content_uri, ...
    descriptors.checksum_sha256, repmat("create", count, 1), ...
    NaN(count, 1), strings(count, 1), strings(count, 1), ...
    VariableNames=["profile_key", "profile_name", "profile_kind", ...
    "profile_action", "existing_profile_id", "version_label", ...
    "profile_schema_version", "content_format", "content_uri", ...
    "checksum_sha256", "version_action", ...
    "existing_profile_version_id", "profile_conflict_message", ...
    "version_conflict_message"]);

profileRows = fetch(conn, ...
    "SELECT profile_id, profile_key, profile_name, profile_kind, is_builtin " + ...
    "FROM config_profiles WHERE project_id IS NULL");
versionRows = fetch(conn, ...
    "SELECT profile_version_id, profile_id, version_label, " + ...
    nullableTextSql("profile_schema_version") + ", content_format, content_uri, " + ...
    nullableTextSql("checksum_sha256") + ", is_snapshot " + ...
    "FROM config_profile_versions");
if ~isempty(versionRows)
    versionRows = normalizeNullableText(versionRows, ...
        ["profile_schema_version", "checksum_sha256"]);
end

for index = 1:count
    matches = profileRows( ...
        string(profileRows.profile_key) == profiles.profile_key(index), :);
    if isempty(matches)
        continue
    elseif height(matches) > 1
        profiles.profile_action(index) = "conflict";
        profiles.version_action(index) = "skip";
        profiles.profile_conflict_message(index) = ...
            "Multiple built-in profiles share this logical key.";
        continue
    end
    profiles.existing_profile_id(index) = double(matches.profile_id(1));
    compatibleProfile = ...
        string(matches.profile_name(1)) == profiles.profile_name(index) && ...
        string(matches.profile_kind(1)) == profiles.profile_kind(index) && ...
        double(matches.is_builtin(1)) == 1;
    if ~compatibleProfile
        profiles.profile_action(index) = "conflict";
        profiles.version_action(index) = "skip";
        profiles.profile_conflict_message(index) = ...
            "Existing linked profile has incompatible name, kind, or scope.";
        continue
    end
    profiles.profile_action(index) = "reuse";
    if isempty(versionRows)
        continue
    end
    versionMatches = versionRows( ...
        double(versionRows.profile_id) == profiles.existing_profile_id(index) & ...
        string(versionRows.version_label) == profiles.version_label(index), :);
    if isempty(versionMatches)
        continue
    elseif height(versionMatches) > 1
        profiles.version_action(index) = "conflict";
        profiles.version_conflict_message(index) = ...
            "Multiple linked profile versions share this authored identity.";
        continue
    end
    profiles.existing_profile_version_id(index) = ...
        double(versionMatches.profile_version_id(1));
    compatibleVersion = ...
        string(versionMatches.profile_schema_version(1)) == ...
        profiles.profile_schema_version(index) && ...
        string(versionMatches.content_format(1)) == ...
        profiles.content_format(index) && ...
        string(versionMatches.content_uri(1)) == profiles.content_uri(index) && ...
        lower(string(versionMatches.checksum_sha256(1))) == ...
        profiles.checksum_sha256(index) && ...
        double(versionMatches.is_snapshot(1)) == 1;
    if compatibleVersion
        profiles.version_action(index) = "reuse";
    else
        profiles.version_action(index) = "conflict";
        profiles.version_conflict_message(index) = ...
            "Existing linked profile identity/version has incompatible provenance.";
    end
end
end

function items = profileItems(document, path)
if ~isstruct(document) || ~isscalar(document) || ~isfield(document, "profiles")
    error("vawlume:ingest:LinkedProfileInvalid", ...
        "Linked profile artifact must contain a profiles collection: %s", path);
end
raw = document.profiles;
if iscell(raw)
    items = raw(:);
elseif isstruct(raw)
    items = num2cell(raw(:));
else
    error("vawlume:ingest:LinkedProfileInvalid", ...
        "Linked profile artifact has an invalid profiles collection: %s", path);
end
end

function sections = deferredSections(document)
sections = strings(0, 1);
for field = ["extractor_outputs", "extraction_run_context"]
    if isfield(document, field)
        sections(end + 1, 1) = field; %#ok<AGROW>
    end
end
end

function value = emptyLinkage()
value = struct( ...
    enabled=false, source_path="", content_uri="", checksum_sha256="", ...
    mapping_profile_key="", profiles=emptyProfiles(), ...
    defaults=emptyDefaults(), deferred_sections=strings(0, 1));
end

function value = emptyDescriptors()
value = table( ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["profile_key", "profile_name", "profile_kind", ...
    "version_label", "profile_schema_version", "content_format", ...
    "content_uri", "checksum_sha256"]);
end

function value = emptyProfiles()
value = table( ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    NaN(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), NaN(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    VariableNames=["profile_key", "profile_name", "profile_kind", ...
    "profile_action", "existing_profile_id", "version_label", ...
    "profile_schema_version", "content_format", "content_uri", ...
    "checksum_sha256", "version_action", ...
    "existing_profile_version_id", "profile_conflict_message", ...
    "version_conflict_message"]);
end

function value = emptyDefaults()
value = table( ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["profile_key", "project_assignment_role", ...
    "recording_assignment_role", "inheritance_source"]);
end

function document = readJson(path, label)
if ~isfile(path)
    error("vawlume:ingest:ProfileLinkageNotFound", ...
        "%s file does not exist: %s", label, path);
end
try
    document = jsondecode(fileread(path));
catch exception
    error("vawlume:ingest:ProfileLinkageInvalid", ...
        "Could not decode %s JSON %s: %s", label, path, exception.message);
end
end

function requireStructField(value, field, label)
if ~isstruct(value) || ~isscalar(value) || ~isfield(value, char(field))
    error("vawlume:ingest:ProfileLinkageInvalid", ...
        "%s requires field '%s'.", label, field);
end
end

function value = scalarText(value, label)
try
    value = string(value);
catch
    value = strings(0, 1);
end
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("vawlume:ingest:ProfileLinkageInvalid", ...
        "%s must be nonempty scalar text.", label);
end
end

function path = resolvedPath(path, repoRoot)
path = string(path);
if ~isfile(path)
    path = fullfile(repoRoot, path);
end
path = normalizedPath(path);
end

function root = normalizedRepoRoot(root)
if strlength(root) == 0
    privateDirectory = fileparts(mfilename("fullpath"));
    ingestDirectory = fileparts(privateDirectory);
    vawlumeDirectory = fileparts(ingestDirectory);
    sourceDirectory = fileparts(vawlumeDirectory);
    root = fileparts(sourceDirectory);
end
root = normalizedPath(root);
end

function path = normalizedPath(path)
try
    path = string(java.io.File(char(path)).getCanonicalPath());
catch
    path = string(path);
end
end

function path = portablePath(path, repoRoot)
path = normalizedPath(path);
prefix = normalizedPath(repoRoot) + string(filesep);
if startsWith(path, prefix, "IgnoreCase", ispc)
    path = extractAfter(path, strlength(prefix));
end
path = replace(path, string(filesep), "/");
end

function hash = sha256File(path)
fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:ingest:ProfileLinkageInvalid", ...
        "Could not open profile artifact for hashing: %s", path);
end
cleanupFile = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8")';
digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(bytes, "int8"));
hashBytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
clear cleanupFile
end

function value = nullableTextSql(column)
value = "CASE WHEN " + column + " IS NULL OR length(" + column + ...
    ") = 0 THEN '<empty-text>' ELSE " + column + " END AS " + column + ...
    ", " + column + " IS NULL OR length(" + column + ") = 0 AS " + ...
    column + "_is_empty";
end

function rows = normalizeNullableText(rows, columns)
for column = columns
    maskName = column + "_is_empty";
    rows.(column)(double(rows.(maskName)) == 1) = "";
end
end
