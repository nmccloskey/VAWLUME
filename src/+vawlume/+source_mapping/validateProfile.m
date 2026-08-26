function report = validateProfile(document, options)
%VALIDATEPROFILE Validate decoded VAWLUME source-mapping profile content.
%
% This function validates the profile language currently used by tracked
% project-input and extractor-output mapping profiles. It deliberately stops
% at profile structure and executable declaration preflight; source discovery,
% source parsing, transforms, and database ingestion belong to later passes.

arguments
    document
    options.ExpectedKind (1,1) string = ""
    options.SourcePath (1,1) string = ""
end

report = emptyReport(options.SourcePath);

if ~isstruct(document)
    addIssue("error", "PROFILE_INVALID_DOCUMENT", "document", ...
        "Profile YAML must decode to a mapping/object.");
    report = finalizeReport(report);
    return
end

[profileDocuments, profileLocations] = profileEntries(document);
if isempty(profileDocuments)
    report = finalizeReport(report);
    return
end

report.profile_count = numel(profileDocuments);
for profileIndex = 1:numel(profileDocuments)
    validateProfileEntry(profileDocuments{profileIndex}, profileLocations(profileIndex));
end

report = finalizeReport(report);

    function validateProfileEntry(entry, location)
        if ~isstruct(entry)
            addIssue("error", "PROFILE_INVALID_DOCUMENT", location, ...
                "Each profile entry must decode to a mapping/object.");
            appendProfileMetadata("", "", "", "");
            return
        end

        validateUnsupportedInheritance(entry, location);

        if ~hasField(entry, "profile")
            addIssue("error", "PROFILE_MISSING_FIELD", location + ".profile", ...
                "Missing required profile envelope.");
            appendProfileMetadata("", "", "", "");
            return
        end

        profile = entry.profile;
        [profileId, hasId] = requiredText(profile, "id", location + ".profile.id");
        [~, hasName] = requiredText(profile, "name", location + ".profile.name");
        [kind, hasKind] = requiredText(profile, "kind", location + ".profile.kind");
        [schemaVersion, hasSchemaVersion] = requiredText(profile, ...
            "profile_schema_version", location + ".profile.profile_schema_version");

        if hasKind
            if ~ismember(kind, ["project_input", "extractor_output"])
                addIssue("error", "PROFILE_UNSUPPORTED_KIND", location + ".profile.kind", ...
                    "Unsupported source_mapping profile kind: " + kind + ".");
            elseif strlength(options.ExpectedKind) > 0 && kind ~= options.ExpectedKind
                addIssue("error", "PROFILE_UNEXPECTED_KIND", location + ".profile.kind", ...
                    "Expected profile kind " + options.ExpectedKind + " but found " + kind + ".");
            end
        end

        if hasSchemaVersion && schemaVersion ~= "0.1-draft"
            addIssue("error", "PROFILE_UNSUPPORTED_SCHEMA_VERSION", ...
                location + ".profile.profile_schema_version", ...
                "Unsupported mapping-profile schema version: " + schemaVersion + ".");
        end

        versionLabel = profileVersionLabel(entry, profile, kind, location);
        appendProfileMetadata(profileId, kind, schemaVersion, versionLabel);

        if ~(hasId && hasName && hasKind && hasSchemaVersion)
            return
        end

        validateTopLevelKeys(entry, kind, location);

        switch kind
            case "project_input"
                validateProjectInputProfile(entry, location);
            case "extractor_output"
                validateExtractorOutputProfile(entry, location);
        end
    end

    function validateProjectInputProfile(entry, location)
        requireMapping(entry, "source", location + ".source");
        requireMapping(entry, "hierarchy", location + ".hierarchy");
        if ~hasField(entry, "mappings")
            addIssue("error", "PROFILE_MISSING_FIELD", location + ".mappings", ...
                "Project-input profiles must declare mappings.");
            return
        end

        levels = strings(0, 1);
        membershipLevels = strings(0, 1);
        if hasField(entry, "hierarchy") && isstruct(entry.hierarchy)
            levels = validateHierarchyLevels(entry.hierarchy, location + ".hierarchy");
            membershipLevels = validateMembershipLevels(entry.hierarchy, levels, ...
                location + ".hierarchy");
        end

        mappings = normalizeSequence(entry.mappings);
        if isempty(mappings)
            addIssue("error", "PROFILE_INVALID_FIELD", location + ".mappings", ...
                "Project-input mappings must be a nonempty sequence.");
            return
        end

        for mappingIndex = 1:numel(mappings)
            mappingLocation = location + ".mappings(" + mappingIndex + ")";
            mapping = mappings{mappingIndex};
            if ~isstruct(mapping)
                addIssue("error", "PROFILE_INVALID_FIELD", mappingLocation, ...
                    "Each project-input mapping must be a mapping/object.");
                continue
            end

            [targetLevel, hasTarget] = requiredText(mapping, "target_level", ...
                mappingLocation + ".target_level");
            if hasTarget && ~ismember(targetLevel, levels)
                addIssue("error", "PROFILE_INVALID_FIELD", mappingLocation + ".target_level", ...
                    "Mapping target_level does not reference a declared hierarchy level: " + targetLevel + ".");
            end

            [sourceType, hasSourceType] = requiredText(mapping, "source_type", ...
                mappingLocation + ".source_type");
            if ~hasSourceType
                continue
            end

            switch sourceType
                case "literal"
                    requireField(mapping, "value", mappingLocation + ".value");
                case "path_component"
                    [pattern, hasPattern] = requiredText(mapping, "path_component_regex", ...
                        mappingLocation + ".path_component_regex");
                    captureNames = strings(0, 1);
                    if hasPattern
                        captureNames = validateRegex(pattern, ...
                            mappingLocation + ".path_component_regex");
                    end
                    if ~requireField(mapping, "capture_group", mappingLocation + ".capture_group")
                        continue
                    end
                    validateCaptureGroup(mapping.capture_group, captureNames, ...
                        mappingLocation + ".capture_group");
                case "filename"
                    [pattern, hasPattern] = requiredText(mapping, "filename_regex", ...
                        mappingLocation + ".filename_regex");
                    captureNames = strings(0, 1);
                    if hasPattern
                        captureNames = validateRegex(pattern, mappingLocation + ".filename_regex");
                    end
                    if requireMapping(mapping, "captures", mappingLocation + ".captures")
                        validateCaptureMap(mapping.captures, captureNames, levels, ...
                            membershipLevels, mappingLocation + ".captures");
                    end
                otherwise
                    addIssue("error", "PROFILE_INVALID_FIELD", mappingLocation + ".source_type", ...
                        "Unsupported project-input mapping source_type: " + sourceType + ".");
            end
        end
    end

    function levels = validateHierarchyLevels(hierarchy, location)
        levels = strings(0, 1);
        if ~hasField(hierarchy, "levels")
            addIssue("error", "PROFILE_MISSING_FIELD", location + ".levels", ...
                "Project-input hierarchy must declare levels.");
            return
        end

        rawLevels = normalizeSequence(hierarchy.levels);
        if isempty(rawLevels)
            addIssue("error", "PROFILE_INVALID_FIELD", location + ".levels", ...
                "Project-input hierarchy levels must be a nonempty sequence.");
            return
        end

        parents = strings(0, 1);
        parentLocations = strings(0, 1);
        for levelIndex = 1:numel(rawLevels)
            level = rawLevels{levelIndex};
            levelLocation = location + ".levels(" + levelIndex + ")";
            if ~isstruct(level)
                addIssue("error", "PROFILE_INVALID_FIELD", levelLocation, ...
                    "Each hierarchy level must be a mapping/object.");
                continue
            end
            [nativeName, hasNativeName] = requiredText(level, "native_name", ...
                levelLocation + ".native_name");
            requiredText(level, "canonical_role", levelLocation + ".canonical_role");
            if hasNativeName
                levels(end + 1, 1) = nativeName; %#ok<AGROW>
            end
            parent = optionalText(level, "parent");
            if strlength(parent) > 0
                parents(end + 1, 1) = parent; %#ok<AGROW>
                parentLocations(end + 1, 1) = levelLocation + ".parent"; %#ok<AGROW>
            end
        end

        if numel(unique(levels)) ~= numel(levels)
            addIssue("error", "PROFILE_INVALID_FIELD", location + ".levels", ...
                "Hierarchy level native_name values must be unique.");
        end

        for parentIndex = 1:numel(parents)
            if ~ismember(parents(parentIndex), levels)
                addIssue("error", "PROFILE_INVALID_FIELD", parentLocations(parentIndex), ...
                    "Hierarchy parent does not reference a declared level: " + parents(parentIndex) + ".");
            end
        end
    end

    function membershipLevels = validateMembershipLevels(hierarchy, levels, location)
        membershipLevels = strings(0, 1);
        if ~hasField(hierarchy, "membership_levels")
            return
        end

        rawMembershipLevels = normalizeSequence(hierarchy.membership_levels);
        for membershipIndex = 1:numel(rawMembershipLevels)
            item = rawMembershipLevels{membershipIndex};
            itemLocation = location + ".membership_levels(" + membershipIndex + ")";
            if ~isstruct(item)
                addIssue("error", "PROFILE_INVALID_FIELD", itemLocation, ...
                    "Each membership level must be a mapping/object.");
                continue
            end
            [nativeName, hasNativeName] = requiredText(item, "native_name", ...
                itemLocation + ".native_name");
            requiredText(item, "canonical_role", itemLocation + ".canonical_role");
            [relationTo, hasRelationTo] = requiredText(item, "relation_to", ...
                itemLocation + ".relation_to");
            if hasNativeName
                membershipLevels(end + 1, 1) = nativeName; %#ok<AGROW>
            end
            if hasRelationTo && ~ismember(relationTo, levels)
                addIssue("error", "PROFILE_INVALID_FIELD", itemLocation + ".relation_to", ...
                    "membership_levels.relation_to must reference a declared hierarchy level: " + relationTo + ".");
            end
        end
    end

    function validateCaptureGroup(captureGroup, captureNames, location)
        if isnumeric(captureGroup)
            if isempty(captureGroup) || ~isscalar(captureGroup) || captureGroup < 1
                addIssue("error", "PROFILE_INVALID_FIELD", location, ...
                    "Numeric capture_group must be a positive scalar index.");
            end
            return
        end

        captureName = string(captureGroup);
        if numel(captureName) ~= 1 || ismissing(captureName) || strlength(captureName) == 0
            addIssue("error", "PROFILE_INVALID_FIELD", location, ...
                "capture_group must be a positive numeric index or nonempty capture name.");
        elseif ~isempty(captureNames) && ~ismember(captureName, captureNames)
            addIssue("error", "PROFILE_INVALID_FIELD", location, ...
                "capture_group references a name not declared by the regex: " + captureName + ".");
        end
    end

    function validateCaptureMap(captures, captureNames, levels, membershipLevels, location)
        captureFields = string(fieldnames(captures));
        for captureIndex = 1:numel(captureFields)
            captureName = captureFields(captureIndex);
            captureLocation = location + "." + captureName;
            if ~isempty(captureNames) && ~ismember(captureName, captureNames)
                addIssue("error", "PROFILE_INVALID_FIELD", captureLocation, ...
                    "Capture mapping references a name not declared by the regex: " + captureName + ".");
            end

            declaration = captures.(char(captureName));
            if ~isstruct(declaration)
                addIssue("error", "PROFILE_INVALID_FIELD", captureLocation, ...
                    "Each capture declaration must be a mapping/object.");
                continue
            end

            targetLevel = optionalText(declaration, "target_level");
            membershipLevel = optionalText(declaration, "membership_level");
            if strlength(targetLevel) > 0 && ~ismember(targetLevel, levels)
                addIssue("error", "PROFILE_INVALID_FIELD", captureLocation + ".target_level", ...
                    "Capture target_level does not reference a declared hierarchy level: " + targetLevel + ".");
            end
            if strlength(membershipLevel) > 0 && ~ismember(membershipLevel, membershipLevels)
                addIssue("error", "PROFILE_INVALID_FIELD", captureLocation + ".membership_level", ...
                    "Capture membership_level does not reference a declared membership level: " + membershipLevel + ".");
            end
        end
    end

    function validateExtractorOutputProfile(entry, location)
        if ~requireMapping(entry, "extractor", location + ".extractor")
            return
        end
        requiredText(entry.extractor, "name", location + ".extractor.name");
        if requireMapping(entry.extractor, "version_scope", ...
                location + ".extractor.version_scope")
            requiredText(entry.extractor.version_scope, "preferred", ...
                location + ".extractor.version_scope.preferred");
        end

        if requireMapping(entry, "field_mapping_source", ...
                location + ".field_mapping_source")
            requiredText(entry.field_mapping_source, "artifact_key", ...
                location + ".field_mapping_source.artifact_key");
        end

        validateArtifactRegexes(entry, location);
        validateFieldMappings(entry, location);
    end

    function validateArtifactRegexes(entry, location)
        if ~hasField(entry, "artifact_discovery") || ...
                ~isstruct(entry.artifact_discovery) || ...
                ~hasField(entry.artifact_discovery, "artifacts")
            return
        end

        artifacts = normalizeSequence(entry.artifact_discovery.artifacts);
        for artifactIndex = 1:numel(artifacts)
            artifact = artifacts{artifactIndex};
            artifactLocation = location + ".artifact_discovery.artifacts(" + artifactIndex + ")";
            if ~isstruct(artifact)
                addIssue("error", "PROFILE_INVALID_FIELD", artifactLocation, ...
                    "Each artifact declaration must be a mapping/object.");
                continue
            end
            requiredText(artifact, "artifact_key", artifactLocation + ".artifact_key");
            if hasField(artifact, "include") && isstruct(artifact.include)
                validateRegexSequenceField(artifact.include, "path_regex", ...
                    artifactLocation + ".include.path_regex");
                validatePathSemanticsAgainstRegex(artifact, artifactLocation);
            end
        end
    end

    function validateRegexSequenceField(container, field, location)
        if ~hasField(container, field)
            return
        end
        patterns = normalizeTextSequence(container.(char(field)));
        for patternIndex = 1:numel(patterns)
            validateRegex(patterns(patternIndex), location + "(" + patternIndex + ")");
        end
    end

    function validatePathSemanticsAgainstRegex(artifact, artifactLocation)
        if ~hasField(artifact, "path_semantics") || ~isstruct(artifact.path_semantics) || ...
                ~hasField(artifact, "include") || ~isstruct(artifact.include) || ...
                ~hasField(artifact.include, "path_regex")
            return
        end
        patterns = normalizeTextSequence(artifact.include.path_regex);
        captureNames = strings(0, 1);
        for patternIndex = 1:numel(patterns)
            captureNames = [captureNames; regexCaptureNames(patterns(patternIndex))]; %#ok<AGROW>
        end
        semanticFields = string(fieldnames(artifact.path_semantics));
        for semanticIndex = 1:numel(semanticFields)
            semanticName = semanticFields(semanticIndex);
            if ~isempty(captureNames) && ~ismember(semanticName, unique(captureNames))
                addIssue("error", "PROFILE_INVALID_FIELD", ...
                    artifactLocation + ".path_semantics." + semanticName, ...
                    "path_semantics key does not reference a declared path_regex capture: " + semanticName + ".");
            end
        end
    end

    function validateFieldMappings(entry, location)
        if ~hasField(entry, "field_mappings")
            addIssue("error", "PROFILE_MISSING_FIELD", location + ".field_mappings", ...
                "Extractor-output profiles must declare field_mappings.");
            return
        end

        mappings = normalizeSequence(entry.field_mappings);
        if isempty(mappings)
            addIssue("error", "PROFILE_INVALID_FIELD_MAPPINGS", location + ".field_mappings", ...
                "field_mappings must be a nonempty sequence of mappings.");
            return
        end

        for mappingIndex = 1:numel(mappings)
            mapping = mappings{mappingIndex};
            mappingLocation = location + ".field_mappings(" + mappingIndex + ")";
            if ~isstruct(mapping)
                addIssue("error", "PROFILE_INVALID_FIELD_MAPPINGS", mappingLocation, ...
                    "field_mappings entries must be mapping/objects.");
                continue
            end
            requiredText(mapping, "source_field", mappingLocation + ".source_field");
            requiredText(mapping, "target_level", mappingLocation + ".target_level");
            requiredText(mapping, "canonical_field", mappingLocation + ".canonical_field");
            requiredText(mapping, "data_type", mappingLocation + ".data_type");
            transform = optionalText(mapping, "transform");
            if strlength(transform) > 0 && isempty(regexp(char(transform), ...
                    '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
                addIssue("error", "PROFILE_INVALID_FIELD", mappingLocation + ".transform", ...
                    "Transform keys must be simple registry identifiers: " + transform + ".");
            end
        end
    end

    function captureNames = validateRegex(pattern, location)
        captureNames = regexCaptureNames(pattern);
        syntaxMessage = basicRegexSyntaxMessage(pattern);
        if strlength(syntaxMessage) > 0
            addIssue("error", "PROFILE_INVALID_REGEX", location, syntaxMessage);
            return
        end

        validationPattern = matlabRegexPattern(pattern);
        try
            regexp("", char(validationPattern), "once");
        catch exception
            addIssue("error", "PROFILE_INVALID_REGEX", location, ...
                "Regex is not valid for MATLAB regexp: " + string(exception.message));
            return
        end

        if contains(string(pattern), "(?P<")
            addIssue("warning", "PROFILE_REGEX_PYTHON_NAMED_CAPTURE_COMPATIBILITY", ...
                location, ...
                "Python-style named capture syntax is validated through a deterministic MATLAB named-capture translation for the prototype.");
        end
    end

    function versionLabel = profileVersionLabel(entry, profile, kind, location)
        versionLabel = optionalText(profile, "profile_version");
        if strlength(versionLabel) > 0
            return
        end

        if kind == "extractor_output" && hasField(entry, "extractor") && ...
                isstruct(entry.extractor) && hasField(entry.extractor, "version_scope") && ...
                isstruct(entry.extractor.version_scope)
            preferred = optionalText(entry.extractor.version_scope, "preferred");
            if strlength(preferred) > 0
                versionLabel = preferred;
                addIssue("warning", "PROFILE_VERSION_DERIVED_FROM_EXTRACTOR", ...
                    location + ".profile.profile_version", ...
                    "profile.profile_version is absent; extractor.version_scope.preferred is used as the prototype compatibility version label.");
                return
            end
        end

        addIssue("warning", "PROFILE_VERSION_MISSING", ...
            location + ".profile.profile_version", ...
            "profile.profile_version is absent; no profile-content version label was declared.");
    end

    function validateTopLevelKeys(entry, kind, location)
        switch kind
            case "project_input"
                allowed = ["profile", "source", "hierarchy", "mappings", ...
                    "validation", "example_paths"];
            case "extractor_output"
                allowed = ["profile", "extractor", "mapping_policy", ...
                    "level_mappings", "artifact_discovery", "recording_linkage", ...
                    "event_identity", "field_mapping_source", "field_mappings", ...
                    "settings_capture", "validation", "provenance", ...
                    "consilience_defaults", "native_processing_notes", "sequence_policy"];
            otherwise
                allowed = "profile";
        end

        names = string(fieldnames(entry));
        for nameIndex = 1:numel(names)
            name = names(nameIndex);
            if ~ismember(name, allowed)
                addIssue("warning", "PROFILE_UNKNOWN_TOP_LEVEL_KEY", ...
                    location + "." + name, ...
                    "Unknown top-level key is preserved but not interpreted by the prototype loader: " + name + ".");
            end
        end
    end

    function validateUnsupportedInheritance(value, location)
        fields = findUnsupportedInheritanceFields(value, location);
        for fieldIndex = 1:numel(fields)
            addIssue("error", "PROFILE_INHERITANCE_UNSUPPORTED", fields(fieldIndex), ...
                "Profile inheritance/override declarations are not supported by the prototype source_mapping loader.");
        end
    end

    function fields = findUnsupportedInheritanceFields(value, location)
        fields = strings(0, 1);
        if iscell(value)
            for cellIndex = 1:numel(value)
                fields = [fields; findUnsupportedInheritanceFields(value{cellIndex}, ...
                    location + "{" + cellIndex + "}")]; %#ok<AGROW>
            end
            return
        end
        if ~isstruct(value)
            return
        end

        if numel(value) > 1
            for structIndex = 1:numel(value)
                fields = [fields; findUnsupportedInheritanceFields( ...
                    value(structIndex), location + "(" + structIndex + ")")]; %#ok<AGROW>
            end
            return
        end

        names = string(fieldnames(value));
        unsupported = ["inherit", "inherits", "extends", "override", "overrides"];
        for nameIndex = 1:numel(names)
            name = names(nameIndex);
            fieldLocation = location + "." + name;
            if ismember(name, unsupported)
                fields(end + 1, 1) = fieldLocation; %#ok<AGROW>
            else
                childValue = value.(char(name));
                fields = [fields; findUnsupportedInheritanceFields( ...
                    childValue, fieldLocation)]; %#ok<AGROW>
            end
        end
    end

    function [entries, locations] = profileEntries(value)
        entries = {};
        locations = strings(0, 1);

        if hasField(value, "profiles")
            entries = normalizeSequence(value.profiles);
            if isempty(entries)
                addIssue("error", "PROFILE_INVALID_DOCUMENT", "profiles", ...
                    "Top-level profiles must be a nonempty sequence.");
                return
            end
            locations = strings(numel(entries), 1);
            for entryIndex = 1:numel(entries)
                locations(entryIndex, 1) = "profiles(" + entryIndex + ")";
            end
        elseif hasField(value, "profile")
            entries = {value};
            locations = "profile_document";
        else
            addIssue("error", "PROFILE_MISSING_FIELD", "document.profile", ...
                "Profile YAML must contain either top-level profile or profiles.");
        end
    end

    function appendProfileMetadata(profileId, kind, schemaVersion, versionLabel)
        report.profile_ids(end + 1, 1) = string(profileId);
        report.profile_kinds(end + 1, 1) = string(kind);
        report.profile_schema_versions(end + 1, 1) = string(schemaVersion);
        report.profile_version_labels(end + 1, 1) = string(versionLabel);
    end

    function ok = requireMapping(container, field, location)
        ok = requireField(container, field, location);
        if ok && ~isstruct(container.(char(field)))
            ok = false;
            addIssue("error", "PROFILE_INVALID_FIELD", location, ...
                "Expected a mapping/object.");
        end
    end

    function ok = requireField(container, field, location)
        ok = hasField(container, field);
        if ~ok
            addIssue("error", "PROFILE_MISSING_FIELD", location, ...
                "Missing required profile field.");
        end
    end

    function [text, ok] = requiredText(container, field, location)
        text = "";
        ok = requireField(container, field, location);
        if ~ok
            return
        end

        try
            text = string(container.(char(field)));
        catch
            ok = false;
            addIssue("error", "PROFILE_INVALID_FIELD", location, ...
                "Expected a nonempty text scalar.");
            return
        end

        if numel(text) ~= 1 || ismissing(text) || strlength(text) == 0
            ok = false;
            addIssue("error", "PROFILE_INVALID_FIELD", location, ...
                "Expected a nonempty text scalar.");
        else
            text = text(1);
        end
    end

    function text = optionalText(container, field)
        text = "";
        if ~hasField(container, field)
            return
        end
        try
            raw = string(container.(char(field)));
        catch
            return
        end
        if isscalar(raw) && ~ismissing(raw) && strlength(raw) > 0
            text = raw(1);
        end
    end

    function addIssue(severity, code, profileLocation, message)
        issue = struct( ...
            severity=string(severity), ...
            code=string(code), ...
            profile_location=string(profileLocation), ...
            message=string(message));
        report.issues(end + 1) = issue;
    end
end

function report = emptyReport(sourcePath)
report = struct();
report.source_path = string(sourcePath);
report.profile_count = 0;
report.profile_ids = strings(0, 1);
report.profile_kinds = strings(0, 1);
report.profile_schema_versions = strings(0, 1);
report.profile_version_labels = strings(0, 1);
report.supported_profile_schema_versions = "0.1-draft";
report.deferred_checks = "transform_registry_existence";
report.issues = struct("severity", {}, "code", {}, "profile_location", {}, "message", {});
report.issue_table = emptyIssueTable();
report.warning_count = 0;
report.error_count = 0;
report.is_valid = false;
end

function report = finalizeReport(report)
report.issue_table = issuesToTable(report.issues);
if isempty(report.issue_table)
    severities = strings(0, 1);
else
    severities = string(report.issue_table.severity);
end
report.warning_count = sum(severities == "warning");
report.error_count = sum(severities == "error");
report.is_valid = report.error_count == 0;
end

function tableValue = issuesToTable(issues)
if isempty(issues)
    tableValue = emptyIssueTable();
else
    tableValue = struct2table(issues);
end
end

function tableValue = emptyIssueTable()
tableValue = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["severity", "code", "profile_location", "message"]);
end

function items = normalizeSequence(rawValue)
if iscell(rawValue)
    items = rawValue(:);
elseif isstruct(rawValue)
    items = num2cell(rawValue(:));
else
    items = {};
end
end

function values = normalizeTextSequence(rawValue)
if iscell(rawValue)
    values = strings(numel(rawValue), 1);
    for index = 1:numel(rawValue)
        values(index) = string(rawValue{index});
    end
elseif isstring(rawValue) || ischar(rawValue) || iscellstr(rawValue)
    values = string(rawValue(:));
else
    values = strings(0, 1);
end
values(ismissing(values)) = "";
values = values(strlength(values) > 0);
end

function tf = hasField(container, field)
tf = isstruct(container) && isfield(container, char(field)) && ...
    ~isempty(container.(char(field)));
end

function names = regexCaptureNames(pattern)
pattern = char(string(pattern));
pythonTokens = regexp(pattern, '\(\?P<([A-Za-z][A-Za-z0-9_]*)>', 'tokens');
matlabTokens = regexp(pattern, '\(\?<([A-Za-z][A-Za-z0-9_]*)>', 'tokens');
names = tokenCellsToStrings([pythonTokens(:); matlabTokens(:)]);
if ~isempty(names)
    names = unique(names, "stable");
end
end

function values = tokenCellsToStrings(tokens)
values = strings(numel(tokens), 1);
for index = 1:numel(tokens)
    values(index) = string(tokens{index}{1});
end
values = values(strlength(values) > 0);
end

function pattern = matlabRegexPattern(pattern)
pattern = string(pattern);
pattern = regexprep(pattern, '\(\?P<([A-Za-z][A-Za-z0-9_]*)>', '(?<$1>');
end

function message = basicRegexSyntaxMessage(pattern)
message = "";
pattern = char(string(pattern));

for tokenPattern = {'\(\?<([^>)]*)>', '\(\?P<([^>)]*)>'}
    tokens = regexp(pattern, tokenPattern{1}, 'tokens');
    for index = 1:numel(tokens)
        name = string(tokens{index}{1});
        if isempty(regexp(char(name), '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
            message = "Regex named capture has an invalid name: " + name + ".";
            return
        end
    end
end

escaped = false;
inCharacterClass = false;
groupDepth = 0;
for index = 1:numel(pattern)
    character = pattern(index);
    if escaped
        escaped = false;
        continue
    end
    if character == '\'
        escaped = true;
        continue
    end
    if character == '[' && ~inCharacterClass
        inCharacterClass = true;
        continue
    end
    if character == ']' && inCharacterClass
        inCharacterClass = false;
        continue
    end
    if inCharacterClass
        continue
    end
    if character == '('
        groupDepth = groupDepth + 1;
    elseif character == ')'
        groupDepth = groupDepth - 1;
        if groupDepth < 0
            message = "Regex contains an unmatched closing parenthesis.";
            return
        end
    end
end

if inCharacterClass
    message = "Regex contains an unclosed character class.";
elseif groupDepth > 0
    message = "Regex contains an unclosed parenthesized group.";
elseif escaped
    message = "Regex ends with an unfinished escape sequence.";
end
end
