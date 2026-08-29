function spec = mupetExportArtifactSpec(profileDocument, artifactKey)
%MUPETEXPORTARTIFACTSPEC Compatibility wrapper for shared file mechanics.
arguments
    profileDocument (1,1) struct
    artifactKey (1,1) string
end
spec = extractorArtifactSpec(profileDocument, artifactKey, "Mupet");
if spec.file_format ~= "csv" || strlength(spec.delimiter) ~= 1
    error("vawlume:ingest:MupetArtifactUnsupported", ...
        "Profile declares unsupported CSV mechanics for artifact '%s'.", spec.artifact_key);
end
end
