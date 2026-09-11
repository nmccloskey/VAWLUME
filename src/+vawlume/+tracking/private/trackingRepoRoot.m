function root = trackingRepoRoot(supplied)
%TRACKINGREPOROOT Resolve the repository root for profile-relative paths.
root = string(supplied);
if strlength(root) > 0
    return
end
packageDir = fileparts(fileparts(mfilename("fullpath")));
vawlumeDir = fileparts(packageDir);
srcDir = fileparts(vawlumeDir);
root = string(fileparts(srcDir));
end
