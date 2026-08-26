function [sources, report] = discoverSources(profileInput, sourceRoot, options)
%DISCOVERSOURCES Discover project-input source files from profile rules.
%
% Discovery currently implements the project-input constructs used by the
% shipped example profiles: recursive filesystem scan, include globs, stable
% root-relative source identity, duplicate-rule warning, and deterministic
% sorting by normalized relative path. Matching is case-sensitive unless a
% future profile explicitly declares otherwise.

arguments
    profileInput
    sourceRoot (1,1) string
    options.ProfileId (1,1) string = ""
end

[profileEntry, profileLocation] = selectProjectInputProfile(profileInput, options.ProfileId);
sourceRoot = string(java.io.File(char(sourceRoot)).getCanonicalPath());
if ~isfolder(sourceRoot)
    error("vawlume:source_mapping:SourceRootNotFound", ...
        "Source root does not exist: %s", sourceRoot);
end

includeGlobs = includeGlobRules(profileEntry, profileLocation);
candidateFiles = listFilesRecursive(sourceRoot);

matchCount = 0;
matches = repmat(blankMatchRecord(), numel(candidateFiles) * numel(includeGlobs), 1);
for fileIndex = 1:numel(candidateFiles)
    pathInfo = vawlume.source_mapping.normalizeRelativePath(candidateFiles(fileIndex), sourceRoot);
    relativePath = pathInfo.relative_path;
    for globIndex = 1:numel(includeGlobs)
        if globMatches(relativePath, includeGlobs(globIndex))
            matchCount = matchCount + 1;
            matches(matchCount) = struct( ...
                runtime_path=pathInfo.runtime_path, ...
                relative_path=relativePath, ...
                filename=pathInfo.filename, ...
                extension=pathInfo.extension, ...
                rule_index=globIndex, ...
                rule_id=discoveryRuleId(globIndex), ...
                rule_glob=includeGlobs(globIndex));
        end
    end
end
matches = matches(1:matchCount);

matches = sortMatches(matches);
[sources, duplicateIssues] = deduplicateMatches(matches, profileEntry);
report = finalizeDiscoveryReport(profileEntry, sourceRoot, numel(candidateFiles), ...
    numel(matches), sources, duplicateIssues);
end

function globs = includeGlobRules(profileEntry, profileLocation)
if ~hasProfileField(profileEntry, "source") || ~isstruct(profileEntry.source) || ...
        ~hasProfileField(profileEntry.source, "include") || ...
        ~isstruct(profileEntry.source.include) || ...
        ~hasProfileField(profileEntry.source.include, "glob")
    error("vawlume:source_mapping:MissingDiscoveryGlob", ...
        "Project-input profile %s does not declare source.include.glob.", ...
        profileLocation);
end

globs = normalizeTextSequence(profileEntry.source.include.glob);
if isempty(globs)
    error("vawlume:source_mapping:MissingDiscoveryGlob", ...
        "Project-input profile %s source.include.glob is empty.", profileLocation);
end
end

function files = listFilesRecursive(rootPath)
files = strings(0, 1);
entries = dir(rootPath);
for index = 1:numel(entries)
    name = string(entries(index).name);
    if entries(index).isdir
        if name ~= "." && name ~= ".."
            childPath = string(fullfile(entries(index).folder, entries(index).name));
            files = [files; listFilesRecursive(childPath)]; %#ok<AGROW>
        end
    else
        files(end + 1, 1) = string(fullfile(entries(index).folder, entries(index).name)); %#ok<AGROW>
    end
end
end

function tf = globMatches(relativePath, globPattern)
relativePath = replace(string(relativePath), "\", "/");
tf = ~isempty(regexp(char(relativePath), char(globToRegex(globPattern)), "once"));
end

function expression = globToRegex(globPattern)
text = char(string(globPattern));
expression = "^";
index = 1;
while index <= numel(text)
    character = text(index);
    if character == '*'
        nextIsStar = index < numel(text) && text(index + 1) == '*';
        if nextIsStar
            nextIsSlash = index + 2 <= numel(text) && isSlash(text(index + 2));
            if nextIsSlash
                expression = expression + "(?:.*/)?";
                index = index + 3;
            else
                expression = expression + ".*";
                index = index + 2;
            end
        else
            expression = expression + "[^/]*";
            index = index + 1;
        end
    elseif character == '?'
        expression = expression + "[^/]";
        index = index + 1;
    elseif isSlash(character)
        expression = expression + "/";
        index = index + 1;
    else
        expression = expression + regexptranslate("escape", character);
        index = index + 1;
    end
end
expression = expression + "$";
end

function tf = isSlash(character)
tf = character == '/' || character == '\';
end

function matches = sortMatches(matches)
if isempty(matches)
    return
end
keys = strings(numel(matches), 1);
for index = 1:numel(matches)
    keys(index) = matches(index).relative_path + "|" + pad(string(matches(index).rule_index), 12, "left", "0");
end
[~, order] = sort(keys);
matches = matches(order);
end

function [sources, duplicateIssues] = deduplicateMatches(matches, profileEntry)
sources = emptySourceRecord();
duplicateIssues = emptyIssueArray();
if isempty(matches)
    return
end

relativePaths = strings(numel(matches), 1);
for index = 1:numel(matches)
    relativePaths(index) = matches(index).relative_path;
end
uniqueRelativePaths = unique(relativePaths, "stable");

for pathIndex = 1:numel(uniqueRelativePaths)
    relativePath = uniqueRelativePaths(pathIndex);
    selected = matches(relativePaths == relativePath);
    rules = strings(numel(selected), 1);
    globs = strings(numel(selected), 1);
    for selectedIndex = 1:numel(selected)
        rules(selectedIndex) = selected(selectedIndex).rule_id;
        globs(selectedIndex) = selected(selectedIndex).rule_glob;
    end

    issues = emptyIssueArray();
    if numel(selected) > 1
        issue = makeIssue("warning", "SOURCE_DUPLICATE_DISCOVERY", ...
            "source.include.glob", ...
            "Source was selected by more than one discovery rule: " + relativePath + ".");
        issues = issue;
        duplicateIssues = appendIssue(duplicateIssues, issue);
    end

    firstMatch = selected(1);
    sourceKey = "source:" + firstMatch.relative_path;
    sources(pathIndex) = struct( ...
        source_key=sourceKey, ...
        runtime_path=firstMatch.runtime_path, ...
        relative_path=firstMatch.relative_path, ...
        filename=firstMatch.filename, ...
        extension=firstMatch.extension, ...
        declared_source_type=string(profileEntry.profile.kind), ...
        artifact_type="source_audio", ...
        discovery_rule_id=firstMatch.rule_id, ...
        discovery_rules=rules, ...
        discovery_globs=globs, ...
        duplicate_rule_count=numel(selected), ...
        issues=issues);
end
end

function issues = appendIssue(issues, issue)
if isempty(issues)
    issues = issue;
else
    issues(numel(issues) + 1) = issue;
end
end

function report = finalizeDiscoveryReport(profileEntry, sourceRoot, scannedFileCount, ...
        rawMatchCount, sources, issues)
report = struct();
report.profile_id = string(profileEntry.profile.id);
report.profile_kind = string(profileEntry.profile.kind);
report.source_root = sourceRoot;
report.scanned_file_count = scannedFileCount;
report.raw_match_count = rawMatchCount;
report.source_count = numel(sources);
report.issues = issues;
report.issue_table = sourceMappingIssuesToTable(issues);
report.warning_count = issueCount(issues, "warning");
report.error_count = issueCount(issues, "error");
report.is_valid = report.error_count == 0;
report.sort_key = "relative_path";
report.case_sensitive_matching = true;
report.symlink_policy = "existing paths canonicalized with Java getCanonicalPath; no separate symlink metadata";
end

function count = issueCount(issues, severity)
count = 0;
for index = 1:numel(issues)
    if string(issues(index).severity) == severity
        count = count + 1;
    end
end
end

function id = discoveryRuleId(index)
id = "include.glob(" + string(index) + ")";
end

function record = blankMatchRecord()
record = struct( ...
    runtime_path="", ...
    relative_path="", ...
    filename="", ...
    extension="", ...
    rule_index=NaN, ...
    rule_id="", ...
    rule_glob="");
end

function record = emptySourceRecord()
record = blankSourceRecord();
record = record([]);
end

function record = blankSourceRecord()
record = struct( ...
    source_key="", ...
    runtime_path="", ...
    relative_path="", ...
    filename="", ...
    extension="", ...
    declared_source_type="", ...
    artifact_type="", ...
    discovery_rule_id="", ...
    discovery_rules=strings(0, 1), ...
    discovery_globs=strings(0, 1), ...
    duplicate_rule_count=0, ...
    issues=emptyIssueArray());
end
