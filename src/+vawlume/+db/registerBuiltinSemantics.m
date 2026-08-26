function summary = registerBuiltinSemantics(conn, repoRoot, options)
%REGISTERBUILTINSEMANTICS Register shipped prototype semantic vocabulary.
%
% The registration derives extractor feature definitions from tracked mapping
% profiles. Existing rows are reused only when their projected definitions
% match exactly; conflicting rows raise an error and the transaction rolls back.

arguments
    conn
    repoRoot (1,1) string = ""
    options.ProfilePaths (1,:) string = strings(1, 0)
    options.PythonExecutable (1,1) string = ""
end

if strlength(repoRoot) == 0
    repoRoot = defaultRepoRoot();
else
    repoRoot = normalizePath(repoRoot);
end

profilePaths = options.ProfilePaths;
if isempty(profilePaths)
    profilePaths = [
        fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.yaml")
        fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", "mupet", "mupet_output_mapping_profile.yaml")
    ];
end

summary = emptySummary();
summary.repo_root = repoRoot;
summary.yaml_strategy = "External PyYAML subprocess selected because MATLAB R2026a has no built-in YAML reader and PyYAML cannot be safely imported in-process on this machine.";

oldAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
try
    execute(conn, "PRAGMA foreign_keys = ON");

    loadedProfiles = cell(numel(profilePaths), 1);
    for index = 1:numel(profilePaths)
        loadedProfiles{index} = vawlume.source_mapping.loadProfile( ...
            profilePaths(index), ...
            ExpectedKind="extractor_output", ...
            RepoRoot=repoRoot, ...
            PythonExecutable=options.PythonExecutable);
        summary.warnings = [summary.warnings; loadedProfiles{index}.warnings(:)];
    end

    registeredProfiles = cell(numel(loadedProfiles), 1);
    for index = 1:numel(loadedProfiles)
        [registeredProfiles{index}, summary] = registerProfileBundle(conn, loadedProfiles{index}, summary);
    end

    summary = registerProfileRelationships(conn, registeredProfiles, summary);
    if summary.inserted > 0
        commit(conn);
    end
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end

function [registered, summary] = registerProfileBundle(conn, loaded, summary)
profileDocument = loaded.document;
profile = profileDocument.profile;
extractor = profileDocument.extractor;

profileVersionLabel = getProfileVersionLabel(profileDocument);
profileKey = string(profile.id);
profileName = string(profile.name);
profileKind = string(profile.kind);
profileSchemaVersion = string(profile.profile_schema_version);
extractorName = string(extractor.name);
extractorKey = stableKey(extractorName);
extractorVersionLabel = string(extractor.version_scope.preferred);
implementationLanguage = optionalText(extractor, "implementation_language");

[profileId, summary] = upsertConfigProfile(conn, struct( ...
    profile_key=profileKey, ...
    profile_name=profileName, ...
    profile_kind=profileKind, ...
    is_builtin=1, ...
    description="Built-in " + extractorName + " extractor-output mapping profile."), summary);

[profileVersionId, summary] = upsertConfigProfileVersion(conn, struct( ...
    profile_id=profileId, ...
    version_label=profileVersionLabel, ...
    profile_schema_version=profileSchemaVersion, ...
    content_format=lower(string(fileExtension(loaded.source_path))), ...
    content_uri=loaded.relative_path, ...
    checksum_sha256=loaded.checksum_sha256, ...
    is_snapshot=1, ...
    notes="Registered from tracked profile source."), summary);

[extractorId, summary] = upsertExtractor(conn, struct( ...
    extractor_key=extractorKey, ...
    extractor_name=extractorName, ...
    description=extractorDescription(extractorName), ...
    source_repository=extractorRepository(extractorName)), summary);

[extractorVersionId, summary] = upsertExtractorVersion(conn, struct( ...
    extractor_id=extractorId, ...
    version_label=extractorVersionLabel, ...
    source_commit_or_tag="", ...
    build_identifier="", ...
    implementation_language=implementationLanguage, ...
    notes="Version scope registered from built-in output mapping profile " + profileKey + "."), summary);

featureRecords = buildFeatureRecords(loaded, extractorVersionId, profileVersionId);
registered = struct();
registered.profile_key = profileKey;
registered.extractor_name = extractorName;
registered.extractor_version_id = extractorVersionId;
registered.profile_version_id = profileVersionId;
registered.features = featureRecords;

for index = 1:numel(featureRecords)
    record = featureRecords{index};
    [canonicalFeatureId, summary] = upsertCanonicalFeature(conn, record.canonical, summary);
    [extractorFeatureId, summary] = upsertExtractorFeature(conn, record.extractor, summary);
    record.mapping.extractor_feature_id = extractorFeatureId;
    record.mapping.canonical_feature_id = canonicalFeatureId;
    [~, summary] = upsertFeatureMapping(conn, record.mapping, summary);
    record.extractor_feature_id = extractorFeatureId;
    record.canonical_feature_id = canonicalFeatureId;
    featureRecords{index} = record;
end

registered.features = featureRecords;
end

function records = buildFeatureRecords(loaded, extractorVersionId, profileVersionId)
document = loaded.document;
sourceArtifactType = string(document.field_mapping_source.artifact_key);
mappings = loaded.field_mappings;
records = {};

for index = 1:numel(mappings)
    mapping = mappings{index};
    if optionalText(mapping, "target_level") ~= "event_measurement"
        continue
    end

    canonicalName = optionalText(mapping, "canonical_field");
    nativeName = optionalText(mapping, "source_field");
    canonicalUnit = optionalText(mapping, "canonical_unit");
    valueType = profileValueType(optionalText(mapping, "data_type"));
    [featureDomain, definition] = canonicalFeatureDescription(canonicalName);
    relationshipPhrase = optionalText(mapping, "cross_extractor_relationship");

    canonical = struct( ...
        canonical_name=canonicalName, ...
        feature_domain=featureDomain, ...
        value_type=valueType, ...
        canonical_unit=canonicalUnit, ...
        definition=definition, ...
        is_vawlume_derived=0);

    extractorFeature = struct( ...
        extractor_version_id=extractorVersionId, ...
        native_name=nativeName, ...
        native_unit=optionalText(mapping, "native_unit"), ...
        value_type=valueType, ...
        native_definition=optionalText(mapping, "operational_definition"), ...
        source_artifact_type=sourceArtifactType, ...
        derivation_stage=optionalText(mapping, "derivation_stage"), ...
        measurement_method="", ...
        operational_variant=optionalText(mapping, "operational_variant"), ...
        equivalence_class=optionalText(mapping, "equivalence_class"), ...
        source_reference=loaded.relative_path + "#field_mappings:" + nativeName, ...
        notes=featureNotes(mapping));

    featureMapping = struct( ...
        extractor_feature_id=NaN, ...
        canonical_feature_id=NaN, ...
        mapping_profile_version_id=profileVersionId, ...
        mapping_type=projectMappingType(mapping), ...
        transform_key=optionalText(mapping, "transform"), ...
        preserve_raw=logicalToInteger(optionalLogical(mapping, "preserve_raw", true)), ...
        notes=mappingNotes(mapping));

    records{end + 1, 1} = struct( ...
        canonical=canonical, ...
        extractor=extractorFeature, ...
        mapping=featureMapping, ...
        source_field=nativeName, ...
        canonical_name=canonicalName, ...
        equivalence_class=optionalText(mapping, "equivalence_class"), ...
        cross_extractor_relationship=relationshipPhrase, ...
        consilience_role=optionalText(mapping, "consilience_role"), ...
        extractor_feature_id=NaN, ...
        canonical_feature_id=NaN); %#ok<AGROW>
end
end

function summary = registerProfileRelationships(conn, registeredProfiles, summary)
if numel(registeredProfiles) < 2
    return
end

deepSqueak = findRegisteredProfile(registeredProfiles, "DeepSqueak");
mupet = findRegisteredProfile(registeredProfiles, "MUPET");
if isempty(deepSqueak) || isempty(mupet)
    summary.warnings(end + 1, 1) = "Pairwise feature relationships require both DeepSqueak and MUPET profiles.";
    return
end

summary = registerSharedEquivalenceRelationships(conn, deepSqueak, mupet, summary);
summary = registerRelatedPowerRelationships(conn, deepSqueak, mupet, summary);
end

function summary = registerSharedEquivalenceRelationships(conn, deepSqueak, mupet, summary)
eligibleClasses = [
    "vocalization_start_time"
    "vocalization_end_time"
    "vocalization_duration"
    "vocalization_frequency_min"
    "vocalization_frequency_max"
    "vocalization_frequency_bandwidth"
    "vocalization_frequency_center"
];

for className = eligibleClasses'
    deepSqueakFeature = findFeatureByEquivalenceClass(deepSqueak.features, className);
    mupetFeature = findFeatureByEquivalenceClass(mupet.features, className);
    if isempty(deepSqueakFeature) || isempty(mupetFeature)
        continue
    end

    relationshipType = combineRelationshipType( ...
        deepSqueakFeature.cross_extractor_relationship, ...
        mupetFeature.cross_extractor_relationship);
    defaultRole = defaultRelationshipRole(deepSqueakFeature.consilience_role, mupetFeature.consilience_role);

    relationship = relationshipRecord( ...
        deepSqueakFeature.extractor_feature_id, ...
        mupetFeature.extractor_feature_id, ...
        relationshipType, ...
        comparisonMethodForClass(className), ...
        "canonical_unit", ...
        1, ...
        defaultRole, ...
        "Registered from matching equivalence_class " + className + " in both built-in extractor-output profiles.", ...
        deepSqueak.profile_key + " and " + mupet.profile_key);
    [~, summary] = upsertFeatureRelationship(conn, relationship, summary);
end
end

function summary = registerRelatedPowerRelationships(conn, deepSqueak, mupet, summary)
deepSqueakPower = findFeatureByCanonicalName(deepSqueak.features, "mean_power_spectral_density");
if isempty(deepSqueakPower)
    return
end

for canonicalName = ["total_energy", "peak_amplitude"]
    mupetFeature = findFeatureByCanonicalName(mupet.features, canonicalName);
    if isempty(mupetFeature)
        continue
    end
    relationship = relationshipRecord( ...
        deepSqueakPower.extractor_feature_id, ...
        mupetFeature.extractor_feature_id, ...
        "related", ...
        "", ...
        "", ...
        0, ...
        "none_by_default", ...
        "Power, energy, and amplitude measures are related acoustic domains but are not equivalent or consilience-eligible by default.", ...
        deepSqueak.profile_key + " and " + mupet.profile_key);
    [~, summary] = upsertFeatureRelationship(conn, relationship, summary);
end
end

function profile = findRegisteredProfile(registeredProfiles, extractorName)
profile = [];
for index = 1:numel(registeredProfiles)
    if registeredProfiles{index}.extractor_name == extractorName
        profile = registeredProfiles{index};
        return
    end
end
end

function feature = findFeatureByEquivalenceClass(features, equivalenceClass)
feature = [];
for index = 1:numel(features)
    current = features{index};
    if current.equivalence_class == equivalenceClass
        feature = current;
        return
    end
end
end

function feature = findFeatureByCanonicalName(features, canonicalName)
feature = [];
for index = 1:numel(features)
    current = features{index};
    if current.canonical_name == canonicalName
        feature = current;
        return
    end
end
end

function [id, summary] = upsertConfigProfile(conn, expected, summary)
rows = readConfigProfiles(conn);
match = rows(strcmp(string(rows.profile_key), expected.profile_key) & rows.project_id == -1, :);
expectedCompare = expected;
if isempty(match)
    id = insertRow(conn, "config_profiles", expected, "profile_id");
    summary.profiles_inserted = summary.profiles_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.profile_id(1));
    assertNoConflict(match(1, :), expectedCompare, ...
        ["profile_name", "profile_kind", "is_builtin", "description"], ...
        "config_profiles:" + expected.profile_key);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.profiles_registered = summary.profiles_registered + 1;
end

function [id, summary] = upsertConfigProfileVersion(conn, expected, summary)
rows = readConfigProfileVersions(conn);
match = rows(rows.profile_id == expected.profile_id & strcmp(string(rows.version_label), expected.version_label), :);
if isempty(match)
    id = insertRow(conn, "config_profile_versions", expected, "profile_version_id");
    summary.profile_versions_inserted = summary.profile_versions_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.profile_version_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["profile_schema_version", "content_format", "content_uri", "checksum_sha256", "is_snapshot", "notes"], ...
        "config_profile_versions:" + expected.version_label);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.profile_versions_registered = summary.profile_versions_registered + 1;
end

function [id, summary] = upsertExtractor(conn, expected, summary)
rows = readExtractors(conn);
match = rows(strcmp(string(rows.extractor_key), expected.extractor_key), :);
if isempty(match)
    id = insertRow(conn, "extractors", expected, "extractor_id");
    summary.extractors_inserted = summary.extractors_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.extractor_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["extractor_name", "description", "source_repository"], ...
        "extractors:" + expected.extractor_key);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.extractors_registered = summary.extractors_registered + 1;
end

function [id, summary] = upsertExtractorVersion(conn, expected, summary)
rows = readExtractorVersions(conn);
match = rows(rows.extractor_id == expected.extractor_id & ...
    strcmp(string(rows.version_label), expected.version_label) & ...
    strcmp(normalizeTextColumn(rows.source_commit_or_tag), expected.source_commit_or_tag), :);
if isempty(match)
    id = insertRow(conn, "extractor_versions", expected, "extractor_version_id");
    summary.versions_inserted = summary.versions_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.extractor_version_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["build_identifier", "implementation_language", "notes"], ...
        "extractor_versions:" + expected.version_label);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.versions_registered = summary.versions_registered + 1;
end

function [id, summary] = upsertCanonicalFeature(conn, expected, summary)
rows = readCanonicalFeatures(conn);
match = rows(strcmp(string(rows.canonical_name), expected.canonical_name), :);
if isempty(match)
    id = insertRow(conn, "canonical_features", expected, "canonical_feature_id");
    summary.canonical_features_inserted = summary.canonical_features_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.canonical_feature_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["feature_domain", "value_type", "canonical_unit", "definition", "is_vawlume_derived"], ...
        "canonical_features:" + expected.canonical_name);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.canonical_features_registered = summary.canonical_features_registered + 1;
end

function [id, summary] = upsertExtractorFeature(conn, expected, summary)
rows = readExtractorFeatures(conn);
match = rows(rows.extractor_version_id == expected.extractor_version_id & ...
    strcmp(string(rows.native_name), expected.native_name) & ...
    strcmp(normalizeTextColumn(rows.source_artifact_type), expected.source_artifact_type) & ...
    strcmp(normalizeTextColumn(rows.derivation_stage), expected.derivation_stage) & ...
    strcmp(normalizeTextColumn(rows.operational_variant), expected.operational_variant), :);
if isempty(match)
    id = insertRow(conn, "extractor_features", expected, "extractor_feature_id");
    summary.extractor_features_inserted = summary.extractor_features_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.extractor_feature_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["native_unit", "value_type", "native_definition", "measurement_method", ...
         "equivalence_class", "source_reference", "notes"], ...
        "extractor_features:" + expected.native_name);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.extractor_features_registered = summary.extractor_features_registered + 1;
end

function [id, summary] = upsertFeatureMapping(conn, expected, summary)
rows = readFeatureMappings(conn);
match = rows(rows.extractor_feature_id == expected.extractor_feature_id & ...
    rows.canonical_feature_id == expected.canonical_feature_id & ...
    rows.mapping_profile_version_id == expected.mapping_profile_version_id, :);
if isempty(match)
    id = insertRow(conn, "feature_mappings", expected, "feature_mapping_id");
    summary.feature_mappings_inserted = summary.feature_mappings_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.feature_mapping_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["mapping_type", "transform_key", "preserve_raw", "notes"], ...
        "feature_mappings:" + expected.extractor_feature_id + "->" + expected.canonical_feature_id);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.feature_mappings_registered = summary.feature_mappings_registered + 1;
end

function [id, summary] = upsertFeatureRelationship(conn, expected, summary)
expected = orderRelationshipFeatures(expected);
rows = readFeatureRelationships(conn);
match = rows(rows.feature_a_id == expected.feature_a_id & rows.feature_b_id == expected.feature_b_id, :);
if isempty(match)
    id = insertRow(conn, "feature_relationships", expected, "feature_relationship_id");
    summary.feature_relationships_inserted = summary.feature_relationships_inserted + 1;
    summary.inserted = summary.inserted + 1;
else
    id = double(match.feature_relationship_id(1));
    assertNoConflict(match(1, :), expected, ...
        ["relationship_type", "comparison_method", "unit_normalization", ...
         "consilience_eligible", "default_role", "justification", "source_reference"], ...
        "feature_relationships:" + expected.feature_a_id + "<->" + expected.feature_b_id);
    summary.reused_existing = summary.reused_existing + 1;
end
summary.feature_relationships_registered = summary.feature_relationships_registered + 1;
end

function id = insertRow(conn, tableName, values, idColumn)
insertValues = stripEmptyOptionalFields(values);
names = fieldnames(insertValues);
rowStruct = struct();
for index = 1:numel(names)
    value = insertValues.(names{index});
    if isstring(value) || ischar(value) || iscellstr(value)
        rowStruct.(names{index}) = {char(normalizeText(value))};
    elseif islogical(value)
        value = value(:);
        rowStruct.(names{index}) = double(value(1));
    else
        value = value(:);
        rowStruct.(names{index}) = double(value(1));
    end
end
row = struct2table(rowStruct, "AsArray", true);
sqlwrite(conn, char(tableName), row);
result = fetch(conn, "SELECT last_insert_rowid() AS " + idColumn);
id = double(result.(idColumn)(1));
end

function values = stripEmptyOptionalFields(values)
names = string(fieldnames(values));
for name = names'
    value = values.(name);
    if (isstring(value) || ischar(value)) && strlength(string(value)) == 0
        values = rmfield(values, char(name));
    end
end
end

function assertNoConflict(row, expected, fields, identityLabel)
for field = fields
    actual = comparableValue(row, field);
    target = comparableValue(expected, field);
    if ~isequal(actual, target)
        error("vawlume:db:SemanticConflict", ...
            "Conflicting semantic registration for %s field %s. Existing value: %s. Requested value: %s.", ...
            identityLabel, field, valueToMessage(actual), valueToMessage(target));
    end
end
end

function value = comparableValue(container, field)
field = char(field);
if istable(container)
    raw = container.(field)(1);
else
    if isfield(container, field)
        raw = container.(field);
    else
        raw = "";
    end
end

if isstring(raw) || ischar(raw) || iscellstr(raw)
    value = normalizeText(raw);
elseif islogical(raw)
    value = double(raw);
else
    value = double(raw);
end
end

function text = normalizeText(raw)
text = string(raw);
if isempty(text) || ismissing(text)
    text = "";
else
    text = text(1);
end
end

function text = normalizeTextColumn(raw)
text = string(raw);
text(ismissing(text)) = "";
end

function text = valueToMessage(value)
text = string(value);
if strlength(text) == 0
    text = "<empty>";
end
end

function rows = readConfigProfiles(conn)
rows = fetch(conn, ...
    "SELECT profile_id, IFNULL(project_id, -1) AS project_id, profile_key, profile_name, " + ...
    "profile_kind, is_builtin, IFNULL(description, '') AS description FROM config_profiles");
end

function rows = readConfigProfileVersions(conn)
rows = fetch(conn, ...
    "SELECT profile_version_id, profile_id, version_label, " + ...
    "IFNULL(profile_schema_version, '') AS profile_schema_version, content_format, " + ...
    "content_uri, IFNULL(checksum_sha256, '') AS checksum_sha256, is_snapshot, " + ...
    "IFNULL(notes, '') AS notes FROM config_profile_versions");
end

function rows = readExtractors(conn)
rows = fetch(conn, ...
    "SELECT extractor_id, extractor_key, extractor_name, IFNULL(description, '') AS description, " + ...
    "IFNULL(source_repository, '') AS source_repository FROM extractors");
end

function rows = readExtractorVersions(conn)
rows = fetch(conn, ...
    "SELECT extractor_version_id, extractor_id, version_label, " + ...
    "IFNULL(source_commit_or_tag, '') AS source_commit_or_tag, " + ...
    "IFNULL(build_identifier, '') AS build_identifier, " + ...
    "IFNULL(implementation_language, '') AS implementation_language, " + ...
    "IFNULL(notes, '') AS notes FROM extractor_versions");
end

function rows = readCanonicalFeatures(conn)
rows = fetch(conn, ...
    "SELECT canonical_feature_id, canonical_name, IFNULL(feature_domain, '') AS feature_domain, " + ...
    "value_type, IFNULL(canonical_unit, '') AS canonical_unit, IFNULL(definition, '') AS definition, " + ...
    "is_vawlume_derived FROM canonical_features");
end

function rows = readExtractorFeatures(conn)
rows = fetch(conn, ...
    "SELECT extractor_feature_id, extractor_version_id, native_name, IFNULL(native_unit, '') AS native_unit, " + ...
    "value_type, IFNULL(native_definition, '') AS native_definition, " + ...
    "IFNULL(source_artifact_type, '') AS source_artifact_type, " + ...
    "IFNULL(derivation_stage, '') AS derivation_stage, " + ...
    "IFNULL(measurement_method, '') AS measurement_method, " + ...
    "IFNULL(operational_variant, '') AS operational_variant, " + ...
    "IFNULL(equivalence_class, '') AS equivalence_class, " + ...
    "IFNULL(source_reference, '') AS source_reference, IFNULL(notes, '') AS notes " + ...
    "FROM extractor_features");
end

function rows = readFeatureMappings(conn)
rows = fetch(conn, ...
    "SELECT feature_mapping_id, extractor_feature_id, canonical_feature_id, " + ...
    "IFNULL(mapping_profile_version_id, -1) AS mapping_profile_version_id, mapping_type, " + ...
    "IFNULL(transform_key, '') AS transform_key, preserve_raw, IFNULL(notes, '') AS notes " + ...
    "FROM feature_mappings");
end

function rows = readFeatureRelationships(conn)
rows = fetch(conn, ...
    "SELECT feature_relationship_id, feature_a_id, feature_b_id, relationship_type, " + ...
    "IFNULL(comparison_method, '') AS comparison_method, IFNULL(unit_normalization, '') AS unit_normalization, " + ...
    "consilience_eligible, IFNULL(default_role, '') AS default_role, " + ...
    "IFNULL(justification, '') AS justification, IFNULL(source_reference, '') AS source_reference " + ...
    "FROM feature_relationships");
end

function summary = emptySummary()
summary = struct();
summary.profiles_registered = 0;
summary.profile_versions_registered = 0;
summary.extractors_registered = 0;
summary.versions_registered = 0;
summary.canonical_features_registered = 0;
summary.extractor_features_registered = 0;
summary.feature_mappings_registered = 0;
summary.feature_relationships_registered = 0;
summary.profiles_inserted = 0;
summary.profile_versions_inserted = 0;
summary.extractors_inserted = 0;
summary.versions_inserted = 0;
summary.canonical_features_inserted = 0;
summary.extractor_features_inserted = 0;
summary.feature_mappings_inserted = 0;
summary.feature_relationships_inserted = 0;
summary.inserted = 0;
summary.reused_existing = 0;
summary.warnings = strings(0, 1);
end

function label = getProfileVersionLabel(document)
if isfield(document.profile, "profile_version") && ~isempty(document.profile.profile_version)
    label = string(document.profile.profile_version);
else
    label = string(document.extractor.version_scope.preferred);
end
end

function text = optionalText(value, field)
field = char(field);
if ~isstruct(value) || ~isfield(value, field) || isempty(value.(field))
    text = "";
    return
end
text = normalizeText(value.(field));
end

function value = optionalLogical(item, field, defaultValue)
field = char(field);
if ~isstruct(item) || ~isfield(item, field) || isempty(item.(field))
    value = defaultValue;
else
    value = logical(item.(field));
end
end

function value = logicalToInteger(value)
value = double(logical(value));
end

function valueType = profileValueType(dataType)
dataType = lower(string(dataType));
if contains(dataType, "float") || contains(dataType, "double") || contains(dataType, "real")
    valueType = "real";
elseif contains(dataType, "integer")
    valueType = "integer";
elseif contains(dataType, "string") || contains(dataType, "text")
    valueType = "text";
elseif contains(dataType, "boolean")
    valueType = "boolean";
else
    valueType = "json";
end
end

function mappingType = projectMappingType(mapping)
phrase = optionalText(mapping, "cross_extractor_relationship");
if strlength(phrase) == 0 && isfield(mapping, "cross_extractor_comparable_by_default") && ...
        isequal(mapping.cross_extractor_comparable_by_default, false)
    mappingType = "noncomparable";
    return
end
mappingType = projectRelationshipPhrase(phrase);
if mappingType == ""
    transform = optionalText(mapping, "transform");
    if transform ~= "" && transform ~= "identity"
        mappingType = "transform_equivalent";
    else
        mappingType = "conceptually_equivalent";
    end
end
end

function relationshipType = combineRelationshipType(leftPhrase, rightPhrase)
left = projectRelationshipPhrase(leftPhrase);
right = projectRelationshipPhrase(rightPhrase);
if left == "conceptually_equivalent" && right == "conceptually_equivalent"
    relationshipType = "conceptually_equivalent";
elseif any([left, right] == "related")
    relationshipType = "related";
elseif any([left, right] == "noncomparable")
    relationshipType = "noncomparable";
else
    relationshipType = "comparable";
end
end

function relationshipType = projectRelationshipPhrase(phrase)
phrase = string(phrase);
if strlength(phrase) == 0
    relationshipType = "";
elseif startsWith(phrase, "comparable_same_intended_construct")
    relationshipType = "conceptually_equivalent";
elseif startsWith(phrase, "comparable")
    relationshipType = "comparable";
elseif startsWith(phrase, "related")
    relationshipType = "related";
elseif startsWith(phrase, "no_direct") || startsWith(phrase, "no_clear_direct") || startsWith(phrase, "extractor_specific")
    relationshipType = "noncomparable";
else
    relationshipType = "related";
end
end

function notes = featureNotes(mapping)
parts = strings(0, 1);
for field = ["semantic_role", "consilience_role", "broader_canonical_concept", "cross_extractor_relationship"]
    value = optionalText(mapping, field);
    if strlength(value) > 0
        parts(end + 1, 1) = field + "=" + value; %#ok<AGROW>
    end
end
notes = strjoin(parts, "; ");
end

function notes = mappingNotes(mapping)
parts = strings(0, 1);
relationship = optionalText(mapping, "cross_extractor_relationship");
if strlength(relationship) > 0
    parts(end + 1, 1) = "profile_relationship=" + relationship;
end
role = optionalText(mapping, "consilience_role");
if strlength(role) > 0
    parts(end + 1, 1) = "consilience_role=" + role;
end
notes = strjoin(parts, "; ");
end

function [domain, definition] = canonicalFeatureDescription(name)
switch string(name)
    case "call_start_time"
        domain = "timing";
        definition = "Estimated start time of a vocalization event in recording-relative seconds.";
    case "call_end_time"
        domain = "timing";
        definition = "Estimated end time of a vocalization event in recording-relative seconds.";
    case "call_duration"
        domain = "timing";
        definition = "Estimated duration of a vocalization event.";
    case "inter_call_interval"
        domain = "timing";
        definition = "Interval between adjacent vocalization events in an event sequence.";
    case {"frequency_start", "frequency_end", "frequency_min", "frequency_max", "frequency_bandwidth", "frequency_center", "contour_median_frequency", "frequency_sd", "frequency_slope", "peak_frequency"}
        domain = "frequency";
        definition = frequencyDefinition(string(name));
    case {"mean_power_spectral_density", "total_energy"}
        domain = "power_energy";
        definition = powerDefinition(string(name));
    case "peak_amplitude"
        domain = "amplitude";
        definition = "Extractor-reported peak amplitude-like measurement for a vocalization event.";
    case {"contour_sinuosity", "tonality"}
        domain = "shape_quality";
        definition = shapeDefinition(string(name));
    case "native_detection_score"
        domain = "model_score";
        definition = "Extractor-native detection confidence or score value, not calibrated across extractors by default.";
    otherwise
        domain = "other";
        definition = "VAWLUME canonical feature derived from built-in extractor mapping profiles.";
end
end

function definition = frequencyDefinition(name)
switch name
    case "frequency_start"
        definition = "Frequency estimate near the start of a vocalization event.";
    case "frequency_end"
        definition = "Frequency estimate near the end of a vocalization event.";
    case "frequency_min"
        definition = "Extractor-estimated lower frequency extent of a vocalization event.";
    case "frequency_max"
        definition = "Extractor-estimated upper frequency extent of a vocalization event.";
    case "frequency_bandwidth"
        definition = "Extractor-estimated frequency span of a vocalization event.";
    case "frequency_center"
        definition = "Broad central-frequency construct for extractor-specific center-frequency measures.";
    case "contour_median_frequency"
        definition = "Median frequency of an extractor-derived vocalization contour.";
    case "frequency_sd"
        definition = "Extractor-estimated standard deviation of vocalization frequency.";
    case "frequency_slope"
        definition = "Extractor-estimated frequency change over event time.";
    case "peak_frequency"
        definition = "Extractor-estimated frequency associated with peak event power or amplitude.";
end
end

function definition = powerDefinition(name)
switch name
    case "mean_power_spectral_density"
        definition = "Extractor-reported mean power spectral density for a vocalization event.";
    case "total_energy"
        definition = "Extractor-reported total energy-like measurement for a vocalization event.";
end
end

function definition = shapeDefinition(name)
switch name
    case "contour_sinuosity"
        definition = "Extractor-reported contour sinuosity or path-shape measure.";
    case "tonality"
        definition = "Extractor-reported tonal quality measure for a vocalization event.";
end
end

function method = comparisonMethodForClass(className)
switch string(className)
    case {"vocalization_start_time", "vocalization_end_time", "vocalization_duration"}
        method = "absolute_difference_and_temporal_overlap";
    otherwise
        method = "absolute_difference_after_unit_normalization";
end
end

function role = defaultRelationshipRole(leftRole, rightRole)
roles = [string(leftRole), string(rightRole)];
if any(roles == "primary")
    role = "primary";
elseif any(roles == "primary_or_supporting")
    role = "primary_or_supporting";
elseif any(roles == "supporting")
    role = "supporting";
else
    role = "none_by_default";
end
end

function relationship = relationshipRecord(featureAId, featureBId, relationshipType, comparisonMethod, unitNormalization, eligible, defaultRole, justification, sourceReference)
relationship = struct( ...
    feature_a_id=featureAId, ...
    feature_b_id=featureBId, ...
    relationship_type=string(relationshipType), ...
    comparison_method=string(comparisonMethod), ...
    unit_normalization=string(unitNormalization), ...
    consilience_eligible=eligible, ...
    default_role=string(defaultRole), ...
    justification=string(justification), ...
    source_reference=string(sourceReference));
relationship = orderRelationshipFeatures(relationship);
end

function relationship = orderRelationshipFeatures(relationship)
if relationship.feature_a_id > relationship.feature_b_id
    previousA = relationship.feature_a_id;
    relationship.feature_a_id = relationship.feature_b_id;
    relationship.feature_b_id = previousA;
end
end

function extension = fileExtension(path)
[~, ~, extension] = fileparts(path);
extension = erase(string(extension), ".");
if extension == "yml"
    return
elseif extension == "yaml"
    return
end
extension = "other";
end

function key = stableKey(name)
key = lower(regexprep(string(name), "[^A-Za-z0-9]+", "_"));
key = regexprep(key, "^_+|_+$", "");
end

function description = extractorDescription(extractorName)
switch string(extractorName)
    case "DeepSqueak"
        description = "Deep learning-based ultrasonic vocalization detector and analysis workflow.";
    case "MUPET"
        description = "Mouse Ultrasonic Profile ExTraction signal-processing workflow.";
    otherwise
        description = "Extractor registered from a built-in output mapping profile.";
end
end

function repository = extractorRepository(extractorName)
switch string(extractorName)
    case "DeepSqueak"
        repository = "https://github.com/DrCoffey/DeepSqueak";
    case "MUPET"
        repository = "https://github.com/mvansegbroeck/mupet";
    otherwise
        repository = "";
end
end

function path = defaultRepoRoot()
dbDir = fileparts(mfilename("fullpath"));
vawlumeDir = fileparts(dbDir);
srcDir = fileparts(vawlumeDir);
path = normalizePath(fileparts(srcDir));
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
