function settings = deepsqueakResolveSettingsProfile(conn, projectId, declared)
%DEEPSQUEAKRESOLVESETTINGSPROFILE Compatibility wrapper for shared resolution.
settings = extractorResolveSettingsProfile(conn, projectId, declared, "DeepSqueak");
end
