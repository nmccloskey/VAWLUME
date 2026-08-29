function spec = deepsqueakExportArtifactSpec(profileDocument, artifactKey)
%DEEPSQUEAKEXPORTARTIFACTSPEC Compatibility wrapper for shared file mechanics.
arguments
    profileDocument (1,1) struct
    artifactKey (1,1) string
end
spec = extractorArtifactSpec(profileDocument, artifactKey, "DeepSqueak");
end
