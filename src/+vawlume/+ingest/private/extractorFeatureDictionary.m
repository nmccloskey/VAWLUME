function dictionary = extractorFeatureDictionary(conn, featureVersionId, mappingProfileVersionId)
%EXTRACTORFEATUREDICTIONARY Read the registered native/canonical feature vocabulary.
%
% An importer resolves measurement semantics from rows the semantic seed layer
% already registered. It never invents an extractor_features or
% canonical_features row from source text, so an exported column that the seed
% layer does not know about is a reportable fault rather than a new dictionary
% entry.
%
% Features are registered against the mapping profile's declared compatibility
% scope, which is why FEATUREVERSIONID is the scope row rather than the exact
% version an individual run recorded.
%
% Nothing here is extractor-specific: the query reads the same tables for every
% extractor, and the five-part registration identity is the shared vocabulary
% both built-in profiles are seeded against.

arguments
    conn
    featureVersionId (1,1) double
    mappingProfileVersionId (1,1) double
end

rows = fetch(conn, ...
    "SELECT xf.extractor_feature_id, xf.native_name, " + ...
    "IFNULL(xf.native_unit, '') AS native_unit, " + ...
    "IFNULL(xf.source_artifact_type, '') AS source_artifact_type, " + ...
    "IFNULL(xf.derivation_stage, '') AS derivation_stage, " + ...
    "IFNULL(xf.operational_variant, '') AS operational_variant, " + ...
    "IFNULL(fm.canonical_feature_id, -1) AS canonical_feature_id, " + ...
    "IFNULL(cf.canonical_name, '') AS canonical_name, " + ...
    "IFNULL(fm.transform_key, '') AS transform_key " + ...
    "FROM extractor_features xf " + ...
    "LEFT JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "AND fm.mapping_profile_version_id = " + string(mappingProfileVersionId) + " " + ...
    "LEFT JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE xf.extractor_version_id = " + string(featureVersionId));

dictionary = struct();
dictionary.extractor_version_id = featureVersionId;
dictionary.mapping_profile_version_id = mappingProfileVersionId;
dictionary.features = rows;
if isempty(rows) || height(rows) == 0
    dictionary.keys = strings(0, 1);
    return
end

dictionary.keys = featureKey(presentText(rows.native_name), ...
    presentText(rows.source_artifact_type), presentText(rows.derivation_stage), ...
    presentText(rows.operational_variant));
end

function key = featureKey(nativeName, sourceArtifactType, derivationStage, operationalVariant)
%FEATUREKEY The five-part registration identity, with absent parts normalized.
key = nativeName + "|" + sourceArtifactType + "|" + derivationStage + "|" + ...
    operationalVariant;
end

function text = presentText(column)
%PRESENTTEXT Normalize a fetched text column to comparable strings.
%
% MATLAB's SQLite fetch returns <missing> rather than "" for an empty text
% value, even one produced by IFNULL. Concatenating a missing element poisons the
% whole key, so identity components are normalized before any comparison.
text = string(column);
text(ismissing(text)) = "";
end
