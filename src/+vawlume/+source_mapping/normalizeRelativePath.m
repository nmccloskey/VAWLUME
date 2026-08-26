function info = normalizeRelativePath(path, sourceRoot, options)
%NORMALIZERELATIVEPATH Normalize a runtime path against a source root.
%
% The semantic relative path uses "/" separators and preserves case. Existing
% filesystem paths are canonicalized with Java before root containment is
% checked, so symlinks are resolved by the host filesystem when Java can
% resolve them.

arguments
    path (1,1) string
    sourceRoot (1,1) string
    options.MustBeInsideRoot (1,1) logical = true
end

runtimePath = canonicalPath(path);
rootPath = canonicalPath(sourceRoot);
isInside = isInsideRoot(runtimePath, rootPath);

if ~isInside && options.MustBeInsideRoot
    error("vawlume:source_mapping:PathOutsideRoot", ...
        "Path is outside source root. Path: %s Root: %s", runtimePath, rootPath);
end

relativePath = "";
if isInside
    relativePath = relativeFromRoot(runtimePath, rootPath);
end

[~, filename, extension] = fileparts(runtimePath);
if strlength(extension) > 0
    filename = filename + extension;
end

issues = emptyIssueArray();
if ~isInside
    issues = makeIssue("error", "SOURCE_PATH_OUTSIDE_ROOT", "sourceRoot", ...
        "Path is outside the supplied source root.");
end

info = struct( ...
    runtime_path=runtimePath, ...
    source_root=rootPath, ...
    relative_path=relativePath, ...
    filename=filename, ...
    extension=string(extension), ...
    is_inside_root=isInside, ...
    issues=issues);
end

function path = canonicalPath(path)
path = string(path);
if strlength(path) == 0
    return
end
try
    path = string(java.io.File(char(path)).getCanonicalPath());
catch
    try
        path = string(java.io.File(char(path)).getAbsolutePath());
    catch
        path = string(path);
    end
end
end

function tf = isInsideRoot(path, rootPath)
path = stripTrailingSeparators(path);
rootPath = stripTrailingSeparators(rootPath);

if ispc
    pathForCompare = lower(path);
    rootForCompare = lower(rootPath);
else
    pathForCompare = path;
    rootForCompare = rootPath;
end

if pathForCompare == rootForCompare
    tf = true;
    return
end

prefix = rootForCompare + string(filesep);
tf = startsWith(pathForCompare, prefix);
end

function path = stripTrailingSeparators(path)
path = string(path);
while strlength(path) > 1 && (endsWith(path, "/") || endsWith(path, "\"))
    path = extractBefore(path, strlength(path));
end
end

function relativePath = relativeFromRoot(path, rootPath)
rootPath = stripTrailingSeparators(rootPath);
if path == rootPath
    relativePath = "";
    return
end

prefixLength = strlength(rootPath + string(filesep));
relativePath = extractAfter(path, prefixLength);
relativePath = replace(relativePath, "\", "/");
relativePath = replace(relativePath, string(filesep), "/");
relativePath = regexprep(relativePath, "/+", "/");
end

function issues = emptyIssueArray()
issues = struct("severity", {}, "code", {}, "profile_location", {}, "message", {});
end

function issue = makeIssue(severity, code, profileLocation, message)
issue = struct( ...
    severity=string(severity), ...
    code=string(code), ...
    profile_location=string(profileLocation), ...
    message=string(message));
end
