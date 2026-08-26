function [entry, location] = selectProjectInputProfile(profileInput, profileId)
%SELECTPROJECTINPUTPROFILE Resolve a validated project-input profile entry.

profileId = string(profileId);
[documents, locations] = profileDocuments(profileInput);
if isempty(documents)
    error("vawlume:source_mapping:InvalidProfileInput", ...
        "Expected a loaded profile bundle or a profile document with a profile envelope.");
end

selectedIndex = 0;
if strlength(profileId) > 0
    for index = 1:numel(documents)
        document = documents{index};
        if isstruct(document) && hasProfileField(document, "profile") && ...
                hasProfileField(document.profile, "id") && ...
                string(document.profile.id) == profileId
            selectedIndex = index;
            break
        end
    end
    if selectedIndex == 0
        error("vawlume:source_mapping:ProfileIdNotFound", ...
            "Project-input profile id was not found: %s", profileId);
    end
elseif isscalar(documents)
    selectedIndex = 1;
else
    error("vawlume:source_mapping:ProfileSelectionRequired", ...
        "Profile input contains %d profiles; supply ProfileId.", numel(documents));
end

entry = documents{selectedIndex};
location = locations(selectedIndex);
if ~isstruct(entry) || ~hasProfileField(entry, "profile")
    error("vawlume:source_mapping:InvalidProfileInput", ...
        "Selected profile entry does not contain a profile envelope.");
end

kind = "";
if hasProfileField(entry.profile, "kind")
    kind = string(entry.profile.kind);
end
if kind ~= "project_input"
    error("vawlume:source_mapping:UnexpectedProfileKind", ...
        "Expected project_input profile but found %s.", kind);
end
end

function [documents, locations] = profileDocuments(profileInput)
documents = {};
locations = strings(0, 1);

if isstruct(profileInput) && hasProfileField(profileInput, "profile_documents")
    documents = normalizeMappingSequence(profileInput.profile_documents);
    locations = profileLocations(documents, true);
elseif isstruct(profileInput) && hasProfileField(profileInput, "profiles")
    documents = normalizeMappingSequence(profileInput.profiles);
    locations = profileLocations(documents, true);
elseif isstruct(profileInput) && hasProfileField(profileInput, "profile")
    documents = {profileInput};
    locations = "profile_document";
end
end

function locations = profileLocations(documents, isProfilesList)
locations = strings(numel(documents), 1);
for index = 1:numel(documents)
    if isProfilesList
        locations(index) = "profiles(" + index + ")";
    else
        locations(index) = "profile_document";
    end
end
end
