function [profile, entry, location] = profileProvenance(profileInput, profileId)
%PROFILEPROVENANCE Select one profile and expose its provenance contract.

profileId = string(profileId);
[documents, locations] = profileDocuments(profileInput);
if isempty(documents)
    error("vawlume:source_mapping:InvalidProfileInput", ...
        "Expected a loaded profile bundle or a profile document with a profile envelope.");
end

selectedIndex = 0;
if strlength(profileId) > 0
    for index = 1:numel(documents)
        candidate = documents{index};
        if isstruct(candidate) && hasProfileField(candidate, "profile") && ...
                hasProfileField(candidate.profile, "id") && ...
                string(candidate.profile.id) == profileId
            selectedIndex = index;
            break
        end
    end
    if selectedIndex == 0
        error("vawlume:source_mapping:ProfileIdNotFound", ...
            "Profile id was not found: %s", profileId);
    end
elseif isscalar(documents)
    selectedIndex = 1;
else
    error("vawlume:source_mapping:ProfileSelectionRequired", ...
        "Profile input contains %d profiles; supply ProfileId.", numel(documents));
end

entry = documents{selectedIndex};
location = locations(selectedIndex);
envelope = entry.profile;

version = optionalText(envelope, "profile_version");
versionSource = "profile.profile_version";
if strlength(version) == 0 && hasProfileField(entry, "extractor") && ...
        isstruct(entry.extractor) && hasProfileField(entry.extractor, "version_scope") && ...
        isstruct(entry.extractor.version_scope)
    version = optionalText(entry.extractor.version_scope, "preferred");
    if strlength(version) > 0
        versionSource = "extractor.version_scope.preferred";
    end
end
if strlength(version) == 0
    versionSource = "not_declared";
end

runtimePath = inputText(profileInput, "source_path");
portablePath = inputText(profileInput, "relative_path");
if strlength(portablePath) == 0
    portablePath = replace(runtimePath, "\", "/");
end

profile = struct();
profile.profile_key = string(envelope.id);
profile.profile_kind = string(envelope.kind);
profile.profile_version = version;
profile.profile_version_source = versionSource;
profile.profile_schema_version = string(envelope.profile_schema_version);
profile.profile_path = portablePath;
profile.profile_runtime_path = runtimePath;
profile.profile_checksum = inputText(profileInput, "checksum_sha256");
end

function [documents, locations] = profileDocuments(profileInput)
documents = {};
locations = strings(0, 1);
if isstruct(profileInput) && hasProfileField(profileInput, "profile_documents")
    documents = normalizeMappingSequence(profileInput.profile_documents);
    locations = profileLocations(numel(documents), true);
elseif isstruct(profileInput) && hasProfileField(profileInput, "profiles")
    documents = normalizeMappingSequence(profileInput.profiles);
    locations = profileLocations(numel(documents), true);
elseif isstruct(profileInput) && hasProfileField(profileInput, "profile")
    documents = {profileInput};
    locations = "profile_document";
end
end

function locations = profileLocations(count, isList)
locations = strings(count, 1);
for index = 1:count
    if isList
        locations(index) = "profiles(" + index + ")";
    else
        locations(index) = "profile_document";
    end
end
end

function value = inputText(container, field)
value = "";
if ~isstruct(container) || ~hasProfileField(container, field)
    return
end
try
    candidate = string(container.(char(field)));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = candidate;
end
end
