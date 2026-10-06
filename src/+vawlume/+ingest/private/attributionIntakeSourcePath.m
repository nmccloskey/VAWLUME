function value = attributionIntakeSourcePath(sourcePath, repoRoot)
%ATTRIBUTIONINTAKESOURCEPATH Canonical absolute path of an attribution source file.
%
% A relative path is read against the repository root, as every intake path does.
if ~java.io.File(char(sourcePath)).isAbsolute()
    sourcePath = fullfile(repoRoot, sourcePath);
end
value = string(java.io.File(char(sourcePath)).getCanonicalPath());
end
