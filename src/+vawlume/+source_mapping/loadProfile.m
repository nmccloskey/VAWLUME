function loaded = loadProfile(profilePath, options)
%LOADPROFILE Load and lightly validate a VAWLUME mapping/profile YAML file.
%
% This loader is intentionally narrow for the prototype seed-registration
% path. It centralizes YAML loading and the identity checks future profile
% readers should share, without attempting to validate every profile feature.

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
validateProfileDocument(document, options.ExpectedKind);

loaded = struct();
loaded.document = document;
loaded.profile = document.profile;
loaded.source_path = profilePath;
loaded.relative_path = relativePath(profilePath, options.RepoRoot);
loaded.checksum_sha256 = sha256File(profilePath);
loaded.field_mappings = normalizeMappingSequence(document.field_mappings);
loaded.warnings = profileWarnings(document);
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

function validateProfileDocument(document, expectedKind)
if ~isstruct(document)
    error("vawlume:source_mapping:InvalidProfile", ...
        "Profile YAML must decode to a mapping/object.");
end

requiredTopLevel = ["profile", "extractor", "field_mapping_source", "field_mappings"];
for name = requiredTopLevel
    requireField(document, name, "profile document");
end

profile = document.profile;
requireText(profile, "id", "profile");
requireText(profile, "name", "profile");
kind = requireText(profile, "kind", "profile");
requireText(profile, "profile_schema_version", "profile");

if strlength(expectedKind) > 0 && kind ~= expectedKind
    error("vawlume:source_mapping:UnexpectedProfileKind", ...
        "Expected profile kind %s but found %s.", expectedKind, kind);
end

requireText(document.extractor, "name", "extractor");
requireField(document.extractor, "version_scope", "extractor");
requireText(document.extractor.version_scope, "preferred", "extractor.version_scope");
requireText(document.field_mapping_source, "artifact_key", "field_mapping_source");

mappings = normalizeMappingSequence(document.field_mappings);
if isempty(mappings)
    error("vawlume:source_mapping:InvalidFieldMappings", ...
        "field_mappings must be a nonempty sequence of mappings.");
end

for index = 1:numel(mappings)
    mapping = mappings{index};
    if ~isstruct(mapping)
        error("vawlume:source_mapping:InvalidFieldMappings", ...
            "field_mappings(%d) must be a mapping/object.", index);
    end
    context = "field_mappings(" + index + ")";
    requireText(mapping, "source_field", context);
    requireText(mapping, "target_level", context);
    requireText(mapping, "canonical_field", context);
    requireText(mapping, "data_type", context);
end
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

function warnings = profileWarnings(document)
warnings = strings(0, 1);
if ~isfield(document.profile, "profile_version") || isempty(document.profile.profile_version)
    warnings(end + 1, 1) = "Profile " + string(document.profile.id) + ...
        " has no profile.profile_version; seed registration uses extractor.version_scope.preferred as the profile version label.";
end
end

function requireField(value, name, context)
if ~isstruct(value) || ~isfield(value, name) || isempty(value.(name))
    error("vawlume:source_mapping:MissingProfileField", ...
        "Missing required %s.%s.", context, name);
end
end

function text = requireText(value, name, context)
requireField(value, name, context);
text = string(value.(name));
if numel(text) ~= 1 || ismissing(text) || strlength(text) == 0
    error("vawlume:source_mapping:InvalidProfileField", ...
        "Expected %s.%s to be a nonempty text scalar.", context, name);
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
