function facts = trackingArtifactFacts(artifactPath, sourceRoot)
%TRACKINGARTIFACTFACTS Provenance for the dense artifact VAWLUME does not store.
%
% The checksum is what makes a later window read verifiable: it identifies the
% exact file whose samples were summarized at registration time, so a silently
% replaced export is detectable rather than assumed equivalent.

artifactPath = string(artifactPath);
[~, stem, extension] = fileparts(artifactPath);

facts = struct();
facts.path_or_uri = replace(artifactPath, "\", "/");
facts.relative_path = trackingRelativePath(artifactPath, sourceRoot);
facts.filename = string(stem) + string(extension);
facts.file_format = lower(erase(string(extension), "."));
facts.size_bytes = NaN;
facts.checksum_sha256 = "";
facts.source_file_id = NaN;

if isfile(artifactPath)
    info = dir(artifactPath);
    facts.size_bytes = double(info(1).bytes);
    facts.checksum_sha256 = trackingSha256OfFile(artifactPath);
end
end

function value = trackingRelativePath(artifactPath, sourceRoot)
value = replace(artifactPath, "\", "/");
root = replace(string(sourceRoot), "\", "/");
if strlength(root) == 0
    return
end
if ~endsWith(root, "/")
    root = root + "/";
end
if startsWith(value, root)
    value = extractAfter(value, strlength(root));
end
end
