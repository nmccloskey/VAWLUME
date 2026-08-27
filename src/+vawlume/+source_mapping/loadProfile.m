function [loaded, report] = loadProfile(profilePath, options)
%LOADPROFILE Load and validate a VAWLUME mapping-profile JSON file.
%
% The loader preserves the Phase 1 seed-registration contract for
% extractor-output profiles while also accepting the Phase 2 project-input
% multi-profile document shape. JSON decoding remains centralized here.

arguments
    profilePath (1,1) string
    options.ExpectedKind (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

profilePath = normalizePath(profilePath);
if ~isfile(profilePath)
    error("vawlume:source_mapping:ProfileLoadFailed", ...
        "Profile file does not exist: %s", profilePath);
end

document = loadJsonProfile(profilePath);
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

function document = loadJsonProfile(profilePath)
try
    text = fileread(profilePath);
catch exception
    error("vawlume:source_mapping:ProfileLoadFailed", ...
        "Could not read JSON profile %s: %s", profilePath, exception.message);
end

duplicate = firstDuplicateJsonMember(text);
if duplicate.found
    error("vawlume:source_mapping:ProfileLoadFailed", ...
        "Could not load JSON profile %s: duplicate object member '%s' at line %d, column %d.", ...
        profilePath, duplicate.key, duplicate.line, duplicate.column);
end

try
    document = jsondecode(text);
catch exception
    error("vawlume:source_mapping:ProfileLoadFailed", ...
        "Could not decode JSON profile %s: %s", profilePath, exception.message);
end
end

function duplicate = firstDuplicateJsonMember(text)
duplicate = struct(found=false, key="", line=NaN, column=NaN);
text = char(string(text));
whitespace = [' ', char(9), newline, char(13)];
stack = struct("kind", {}, "state", {}, "keys", {});
index = 1;
while index <= numel(text)
    character = text(index);
    if ismember(character, whitespace)
        index = index + 1;
        continue
    end

    switch character
        case '{'
            stack(end + 1) = struct( ...
                kind="object", state="key_or_end", keys=strings(0, 1)); %#ok<AGROW>
            index = index + 1;
        case '['
            stack(end + 1) = struct( ...
                kind="array", state="value_or_end", keys=strings(0, 1)); %#ok<AGROW>
            index = index + 1;
        case '}'
            if ~isempty(stack) && stack(end).kind == "object"
                stack(end) = [];
                stack = markJsonValueConsumed(stack);
            end
            index = index + 1;
        case ']'
            if ~isempty(stack) && stack(end).kind == "array"
                stack(end) = [];
                stack = markJsonValueConsumed(stack);
            end
            index = index + 1;
        case ','
            if ~isempty(stack)
                if stack(end).kind == "object"
                    stack(end).state = "key_or_end";
                elseif stack(end).kind == "array"
                    stack(end).state = "value_or_end";
                end
            end
            index = index + 1;
        case ':'
            if ~isempty(stack) && stack(end).kind == "object"
                stack(end).state = "value";
            end
            index = index + 1;
        case '"'
            [lexeme, nextIndex, ok] = readJsonStringLexeme(text, index);
            if ~ok
                return
            end
            if ~isempty(stack) && stack(end).kind == "object" && ...
                    stack(end).state == "key_or_end"
                key = jsonStringKey(lexeme);
                if any(stack(end).keys == key)
                    [line, column] = lineColumnForIndex(text, index);
                    duplicate = struct( ...
                        found=true, key=key, line=line, column=column);
                    return
                end
                stack(end).keys(end + 1, 1) = key;
                stack(end).state = "colon";
            else
                stack = markJsonValueConsumed(stack);
            end
            index = nextIndex;
        otherwise
            index = skipJsonScalar(text, index);
            stack = markJsonValueConsumed(stack);
    end
end
end

function stack = markJsonValueConsumed(stack)
if isempty(stack)
    return
end
if stack(end).kind == "object" && stack(end).state == "value"
    stack(end).state = "comma_or_end";
elseif stack(end).kind == "array" && stack(end).state == "value_or_end"
    stack(end).state = "comma_or_end";
end
end

function [lexeme, nextIndex, ok] = readJsonStringLexeme(text, startIndex)
ok = false;
lexeme = "";
nextIndex = startIndex + 1;
escaped = false;
index = startIndex + 1;
while index <= numel(text)
    character = text(index);
    if escaped
        escaped = false;
    elseif character == '\'
        escaped = true;
    elseif character == '"'
        lexeme = text(startIndex:index);
        nextIndex = index + 1;
        ok = true;
        return
    end
    index = index + 1;
end
end

function key = jsonStringKey(lexeme)
content = lexeme(2:end - 1);
if ~contains(string(content), "\")
    key = string(content);
    return
end

decoded = strings(0, 1);
index = 1;
while index <= numel(content)
    character = content(index);
    if character ~= '\'
        decoded(end + 1, 1) = string(character); %#ok<AGROW>
        index = index + 1;
        continue
    end

    if index == numel(content)
        break
    end
    escape = content(index + 1);
    switch escape
        case {'"', '\', '/'}
            decoded(end + 1, 1) = string(escape); %#ok<AGROW>
            index = index + 2;
        case 'b'
            decoded(end + 1, 1) = string(char(8)); %#ok<AGROW>
            index = index + 2;
        case 'f'
            decoded(end + 1, 1) = string(char(12)); %#ok<AGROW>
            index = index + 2;
        case 'n'
            decoded(end + 1, 1) = string(newline); %#ok<AGROW>
            index = index + 2;
        case 'r'
            decoded(end + 1, 1) = string(char(13)); %#ok<AGROW>
            index = index + 2;
        case 't'
            decoded(end + 1, 1) = string(char(9)); %#ok<AGROW>
            index = index + 2;
        case 'u'
            if index + 5 <= numel(content)
                code = hex2dec(content(index + 2:index + 5));
                decoded(end + 1, 1) = string(char(code)); %#ok<AGROW>
                index = index + 6;
            else
                index = index + 2;
            end
        otherwise
            decoded(end + 1, 1) = string(escape); %#ok<AGROW>
            index = index + 2;
    end
end
key = join(decoded, "");
end

function nextIndex = skipJsonScalar(text, startIndex)
nextIndex = startIndex;
while nextIndex <= numel(text) && ~ismember(text(nextIndex), [',', '}', ']'])
    nextIndex = nextIndex + 1;
end
end

function [line, column] = lineColumnForIndex(text, index)
prefix = text(1:index - 1);
line = numel(strfind(prefix, newline)) + 1;
lastNewline = find(prefix == newline, 1, "last");
if isempty(lastNewline)
    column = index;
else
    column = index - lastNewline;
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
fileId = fopen(path, "rb");
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
