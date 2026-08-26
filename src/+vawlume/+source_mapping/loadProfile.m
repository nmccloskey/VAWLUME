function [loaded, report] = loadProfile(profilePath, options)
%LOADPROFILE Load and validate a VAWLUME mapping-profile YAML file.
%
% The loader preserves the Phase 1 seed-registration contract for
% extractor-output profiles while also accepting the Phase 2 project-input
% multi-profile document shape. YAML parsing remains centralized through the
% established out-of-process PyYAML bridge.

arguments
    profilePath (1,1) string
    options.ExpectedKind (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.PythonExecutable (1,1) string = ""
end

profilePath = normalizePath(profilePath);
if ~isfile(profilePath)
    error("vawlume:source_mapping:ProfileNotFound", ...
        "Profile file does not exist: %s", profilePath);
end

document = loadYamlWithPyYaml(profilePath, options.PythonExecutable);
report = vawlume.source_mapping.validateProfile( ...
    document, ExpectedKind=options.ExpectedKind, SourcePath=profilePath);
throwIfValidationFailed(report);

profileDocuments = normalizeProfileDocuments(document);

loaded = struct();
loaded.document = document;
loaded.source_path = profilePath;
loaded.relative_path = relativePath(profilePath, options.RepoRoot);
loaded.checksum_sha256 = sha256File(profilePath);
loaded.profile_documents = profileDocuments;
loaded.profile_count = numel(profileDocuments);
loaded.profiles = cellfun(@(item) item.profile, profileDocuments, UniformOutput=false);
loaded.profile = loaded.profiles{1};
loaded.profile_ids = report.profile_ids;
loaded.profile_kinds = report.profile_kinds;
loaded.profile_schema_versions = report.profile_schema_versions;
loaded.profile_version_labels = report.profile_version_labels;
loaded.field_mappings = firstProfileFieldMappings(profileDocuments);
loaded.issues = report.issues;
loaded.report = report;
loaded.warnings = issueMessages(report, "warning");
end

function document = loadYamlWithPyYaml(profilePath, pythonExecutable)
pythonExecutable = resolvePythonExecutable(pythonExecutable);
loaderScript = fullfile(fileparts(mfilename("fullpath")), "private", "yaml_file_to_json.py");

command = quoteCommandArg(pythonExecutable) + " " + ...
    quoteCommandArg(loaderScript) + " " + quoteCommandArg(profilePath);
[status, output] = system(command);

if status ~= 0
    error("vawlume:source_mapping:YamlLoadFailed", ...
        "Could not load YAML profile %s using PyYAML subprocess.%s%s", ...
        profilePath, newline, output);
end

try
    document = jsondecode(output);
catch exception
    error("vawlume:source_mapping:YamlJsonDecodeFailed", ...
        "PyYAML output for %s was not valid JSON: %s", ...
        profilePath, exception.message);
end
end

function pythonExecutable = resolvePythonExecutable(pythonExecutable)
pythonExecutable = string(pythonExecutable);
if strlength(pythonExecutable) > 0
    pythonExecutable = normalizePath(pythonExecutable);
    return
end

try
    environment = pyenv;
    pythonExecutable = string(environment.Executable);
catch
    pythonExecutable = "";
end

if strlength(pythonExecutable) == 0
    pythonExecutable = "python";
end
end

function throwIfValidationFailed(report)
errors = filterIssues(report.issues, "error");
if isempty(errors)
    return
end

issue = errors(1);
identifier = issueIdentifier(issue.code);
error(identifier, ...
    "Profile validation failed for %s: %s [%s at %s].", ...
    report.source_path, issue.message, issue.code, issue.profile_location);
end

function mappings = normalizeMappingSequence(rawMappings)
if iscell(rawMappings)
    mappings = rawMappings(:);
elseif isstruct(rawMappings)
    mappings = num2cell(rawMappings(:));
else
    mappings = {};
end
end

function profileDocuments = normalizeProfileDocuments(document)
if isstruct(document) && isfield(document, "profiles")
    profileDocuments = normalizeMappingSequence(document.profiles);
else
    profileDocuments = {document};
end
end

function fieldMappings = firstProfileFieldMappings(profileDocuments)
firstDocument = profileDocuments{1};
if isstruct(firstDocument) && isfield(firstDocument, "field_mappings")
    fieldMappings = normalizeMappingSequence(firstDocument.field_mappings);
else
    fieldMappings = {};
end
end

function messages = issueMessages(report, severity)
issues = filterIssues(report.issues, severity);
messages = strings(numel(issues), 1);
for index = 1:numel(issues)
    issue = issues(index);
    messages(index) = issue.code + ": " + issue.message + " (" + issue.profile_location + ")";
end
end

function matches = filterIssues(issues, severity)
matches = struct("severity", {}, "code", {}, "profile_location", {}, "message", {});
for index = 1:numel(issues)
    if string(issues(index).severity) == severity
        matches(end + 1) = issues(index); %#ok<AGROW>
    end
end
end

function identifier = issueIdentifier(code)
switch string(code)
    case "PROFILE_INVALID_DOCUMENT"
        identifier = "vawlume:source_mapping:InvalidProfile";
    case "PROFILE_MISSING_FIELD"
        identifier = "vawlume:source_mapping:MissingProfileField";
    case "PROFILE_INVALID_FIELD"
        identifier = "vawlume:source_mapping:InvalidProfileField";
    case "PROFILE_UNEXPECTED_KIND"
        identifier = "vawlume:source_mapping:UnexpectedProfileKind";
    case "PROFILE_UNSUPPORTED_KIND"
        identifier = "vawlume:source_mapping:UnsupportedProfileKind";
    case "PROFILE_UNSUPPORTED_SCHEMA_VERSION"
        identifier = "vawlume:source_mapping:UnsupportedProfileSchemaVersion";
    case "PROFILE_INVALID_REGEX"
        identifier = "vawlume:source_mapping:InvalidProfileRegex";
    case "PROFILE_INVALID_FIELD_MAPPINGS"
        identifier = "vawlume:source_mapping:InvalidFieldMappings";
    case "PROFILE_INHERITANCE_UNSUPPORTED"
        identifier = "vawlume:source_mapping:UnsupportedProfileInheritance";
    case "PROFILE_UNKNOWN_TRANSFORM"
        identifier = "vawlume:source_mapping:UnknownTransform";
    otherwise
        identifier = "vawlume:source_mapping:ProfileValidationFailed";
end
end

function path = normalizePath(path)
path = string(path);
if strlength(path) == 0
    return
end
try
    path = string(java.io.File(char(path)).getCanonicalPath());
catch
    path = string(path);
end
end

function path = relativePath(path, repoRoot)
path = normalizePath(path);
repoRoot = normalizePath(repoRoot);
if strlength(repoRoot) == 0
    path = replace(path, filesep, "/");
    return
end

repoPrefix = repoRoot + string(filesep);
if startsWith(path, repoPrefix, "IgnoreCase", ispc)
    path = extractAfter(path, strlength(repoPrefix));
end
path = replace(path, filesep, "/");
end

function hash = sha256File(path)
fileId = fopen(path, "r");
if fileId < 0
    error("vawlume:source_mapping:FileReadFailed", ...
        "Could not open file for hashing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8")';

digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(bytes, "int8"));
hashBytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
delete(cleaner);
end

function value = quoteCommandArg(value)
value = string(value);
value = replace(value, """", """""");
value = """" + value + """";
end
