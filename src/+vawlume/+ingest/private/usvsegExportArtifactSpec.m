function spec = usvsegExportArtifactSpec(profileDocument, artifactKey)
%USVSEGEXPORTARTIFACTSPEC Guard profile-declared USVSEG CSV mechanics.
arguments
    profileDocument (1,1) struct
    artifactKey (1,1) string
end

spec = extractorArtifactSpec(profileDocument, artifactKey, "Usvseg");
if spec.file_format ~= "csv" || strlength(spec.delimiter) ~= 1 || ...
        spec.header_row ~= 1 || strlength(spec.header_literal) == 0
    error("vawlume:ingest:UsvsegArtifactUnsupported", ...
        "Profile declares unsupported CSV mechanics for artifact '%s'.", ...
        spec.artifact_key);
end
end
