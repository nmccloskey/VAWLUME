function value = attributionIntakeSourcePath(sourcePath, repoRoot)
%ATTRIBUTIONINTAKESOURCEPATH Canonical absolute path of an attribution source file.
%
% A relative path is read against the repository root, as every intake path does.
value = vawlume.internal.resolvePath(sourcePath, Base=repoRoot);
end
