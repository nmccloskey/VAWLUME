function root = alignmentRepoRoot(root)
%ALIGNMENTREPOROOT Resolve the repository root for relative profile paths.

root = string(root);
if strlength(root) == 0
    % private -> +ingest -> +vawlume -> src -> repository root
    root = string(fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath")))))));
end
root = alignmentCanonicalPath(root);
end
