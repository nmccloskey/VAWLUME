function root = schemaRepositoryRoot()
%SCHEMAREPOSITORYROOT The repository root, derived from this file's location.
%
% Resolution never consults `pwd`: a loader whose default path depends on the
% working directory loads a different file depending on where MATLAB happens to
% be, which is the one failure mode a default path exists to prevent.
%
% Five levels up from src/+vawlume/+schema/private/<this file>.

root = string(fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath")))))));
end
