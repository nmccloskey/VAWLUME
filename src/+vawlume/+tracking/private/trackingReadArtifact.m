function [tbl, artifactPath] = trackingReadArtifact(artifactPath, sourceRoot, supplied)
%TRACKINGREADARTIFACT Read one canonicalized tracking export into memory.
%
% Reading the whole artifact into MATLAB is expected. The dense-data policy is
% about SQLite, not about memory: the mapper needs the entity, bodypart and time
% columns to derive the trace inventory and the observed span, and both of those
% are summaries. Bounded window access at query time is a separate concern.
%
% A caller may supply an already-read table instead, which is how a test exercises
% the mapping contract without writing a file. The artifact path is still
% resolved and checksummed, because provenance is about the file either way.

artifactPath = string(artifactPath);
if ~trackingIsAbsolutePath(artifactPath)
    artifactPath = string(fullfile(sourceRoot, artifactPath));
end

if ~isempty(supplied)
    tbl = supplied;
    return
end

if ~isfile(artifactPath)
    error("vawlume:tracking:ArtifactNotFound", ...
        "No tracking artifact exists at '%s'.", artifactPath);
end

[~, ~, extension] = fileparts(artifactPath);
switch lower(string(extension))
    case {".csv", ".txt", ".tsv"}
        try
            tbl = readtable(artifactPath, TextType="string", ...
                VariableNamingRule="preserve");
        catch exception
            error("vawlume:tracking:ArtifactUnreadable", ...
                "The tracking artifact '%s' could not be read as a delimited " + ...
                "table: %s", artifactPath, exception.message);
        end
    otherwise
        error("vawlume:tracking:ArtifactUnsupported", ...
            "Tracking artifacts are read as delimited text in this prototype; " + ...
            "'%s' is not supported. Canonicalize the upstream export rather " + ...
            "than adding a vendor reader here.", extension);
end

if height(tbl) == 0
    error("vawlume:tracking:ArtifactEmpty", ...
        "The tracking artifact '%s' contains no rows.", artifactPath);
end
end
