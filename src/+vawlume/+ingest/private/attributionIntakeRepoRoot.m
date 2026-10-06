function root = attributionIntakeRepoRoot(root)
%ATTRIBUTIONINTAKEREPOROOT The canonical repository root an attribution intake resolves against.
%
% Shared by every attribution intake path. An empty ROOT means the repository
% this file lives in.
root = string(root);
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath"))))));
end
root = string(java.io.File(char(root)).getCanonicalPath());
end
