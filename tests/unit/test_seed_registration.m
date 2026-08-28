function tests = test_seed_registration
tests = functiontests({ ...
    @testRegisterBuiltinSemanticsIsIdempotent, ...
    @testRegisterBuiltinSemanticsRejectsConflicts, ...
    @testSameVersionChangedProfileBytesRejectAsConflict, ...
    @testDeliberateProfileVersionRevisionCanCoexist});
end

function testRegisterBuiltinSemanticsIsIdempotent(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

first = vawlume.db.registerBuiltinSemantics(conn, repoRoot);
countsAfterFirst = semanticCounts(conn);
second = vawlume.db.registerBuiltinSemantics(conn, repoRoot);
countsAfterSecond = semanticCounts(conn);

verifyEqual(testCase, countsAfterFirst, countsAfterSecond);
verifyGreaterThan(testCase, first.inserted, 0);
verifyTrue(testCase, contains(first.configuration_strategy, "jsondecode"));
verifyEqual(testCase, second.inserted, 0);
verifyGreaterThan(testCase, second.reused_existing, 0);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

verifyEqual(testCase, countsAfterFirst.config_profiles, 2);
verifyEqual(testCase, countsAfterFirst.config_profile_versions, 2);
verifyEqual(testCase, countsAfterFirst.extractors, 2);
verifyEqual(testCase, countsAfterFirst.extractor_versions, 2);
verifyEqual(testCase, countsAfterFirst.canonical_features, 20);
verifyEqual(testCase, countsAfterFirst.extractor_features, 26);
verifyEqual(testCase, countsAfterFirst.feature_mappings, 26);
verifyEqual(testCase, countsAfterFirst.feature_relationships, 9);

verifyProfileChecksums(testCase, conn, repoRoot);
verifyExtractorIdentities(testCase, conn);
verifyRepresentativeFeatureSemantics(testCase, conn);
verifyPairwiseRelationships(testCase, conn);

clear cleanupPath cleanupDb first second
end

function testRegisterBuiltinSemanticsRejectsConflicts(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
countsBeforeConflict = semanticCounts(conn);

sourceProfile = fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.json");
conflictingProfile = fullfile(tempdir, "deepsqueak_output_mapping_profile_conflict.json");
text = fileread(sourceProfile);
text = replace(text, ...
    '"name": "DeepSqueak v3.2 extractor-output mapping"', ...
    '"name": "Conflicting DeepSqueak profile name"');
writeText(conflictingProfile, text);
cleanupProfile = onCleanup(@() deleteIfExists(conflictingProfile));

verifyError(testCase, ...
    @() vawlume.db.registerBuiltinSemantics(conn, repoRoot, ProfilePaths=conflictingProfile), ...
    "vawlume:db:SemanticConflict");
verifyEqual(testCase, semanticCounts(conn), countsBeforeConflict);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM config_profiles " + ...
    "WHERE profile_key = 'vawlume.deepsqueak.output.v3_2' " + ...
    "AND profile_name = 'DeepSqueak v3.2 extractor-output mapping'"), 1);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupPath cleanupDb cleanupProfile
end

function testSameVersionChangedProfileBytesRejectAsConflict(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

sourceProfile = fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.json");
temporaryProfile = string(tempname) + ".json";
writeText(temporaryProfile, fileread(sourceProfile));
cleanupProfile = onCleanup(@() deleteIfExists(temporaryProfile));

vawlume.db.registerBuiltinSemantics(conn, repoRoot, ProfilePaths=temporaryProfile);
countsBeforeConflict = semanticCounts(conn);
versionBefore = profileVersionRows(conn, "vawlume.deepsqueak.output.v3_2");

text = fileread(temporaryProfile);
text = replace(text, ...
    '"operational_definition": "median frequency of the DeepSqueak contour"', ...
    '"operational_definition": "changed test definition for checksum conflict"');
writeText(temporaryProfile, text);

verifyError(testCase, ...
    @() vawlume.db.registerBuiltinSemantics(conn, repoRoot, ProfilePaths=temporaryProfile), ...
    "vawlume:db:SemanticConflict");
verifyEqual(testCase, semanticCounts(conn), countsBeforeConflict);
verifyEqual(testCase, profileVersionRows(conn, "vawlume.deepsqueak.output.v3_2"), versionBefore);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupPath cleanupDb cleanupProfile
end

function testDeliberateProfileVersionRevisionCanCoexist(testCase)
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));
cleanupPath = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

[conn, dbFile] = createDisposableDatabase(repoRoot);
cleanupDb = onCleanup(@() cleanupDatabase(conn, dbFile));

sourceProfile = fullfile(repoRoot, "config", "01_mapping_profiles", "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.json");
temporaryProfile = string(tempname) + ".json";
writeText(temporaryProfile, fileread(sourceProfile));
cleanupProfile = onCleanup(@() deleteIfExists(temporaryProfile));

vawlume.db.registerBuiltinSemantics(conn, repoRoot, ProfilePaths=temporaryProfile);
countsAfterFirst = semanticCounts(conn);

text = fileread(temporaryProfile);
text = replace(text, '"profile_version": "0.1.0"', '"profile_version": "0.1.1"');
writeText(temporaryProfile, text);

vawlume.db.registerBuiltinSemantics(conn, repoRoot, ProfilePaths=temporaryProfile);
countsAfterRevision = semanticCounts(conn);
versionRows = profileVersionRows(conn, "vawlume.deepsqueak.output.v3_2");

verifyEqual(testCase, string(versionRows.version_label), ["0.1.0"; "0.1.1"]);
verifyEqual(testCase, string(versionRows.content_format), ["json"; "json"]);
verifyEqual(testCase, string(versionRows.profile_schema_version), ["0.2-draft"; "0.2-draft"]);
verifyEqual(testCase, countsAfterRevision.config_profiles, countsAfterFirst.config_profiles);
verifyEqual(testCase, countsAfterRevision.extractors, countsAfterFirst.extractors);
verifyEqual(testCase, countsAfterRevision.extractor_versions, countsAfterFirst.extractor_versions);
verifyEqual(testCase, countsAfterRevision.canonical_features, countsAfterFirst.canonical_features);
verifyEqual(testCase, countsAfterRevision.extractor_features, countsAfterFirst.extractor_features);
verifyEqual(testCase, countsAfterRevision.config_profile_versions, countsAfterFirst.config_profile_versions + 1);
verifyEqual(testCase, countsAfterRevision.feature_mappings, countsAfterFirst.feature_mappings * 2);
verifyEqual(testCase, featureMappingCountForProfileVersion(conn, "vawlume.deepsqueak.output.v3_2", "0.1.0"), countsAfterFirst.feature_mappings);
verifyEqual(testCase, featureMappingCountForProfileVersion(conn, "vawlume.deepsqueak.output.v3_2", "0.1.1"), countsAfterFirst.feature_mappings);
verifyEqual(testCase, height(fetch(conn, "PRAGMA foreign_key_check")), 0);

clear cleanupPath cleanupDb cleanupProfile
end

function verifyProfileChecksums(testCase, conn, repoRoot)
profiles = [
    "vawlume.deepsqueak.output.v3_2", "config/01_mapping_profiles/extractors/deepsqueak/deepsqueak_output_mapping_profile.json"
    "vawlume.mupet.output.v2_1", "config/01_mapping_profiles/extractors/mupet/mupet_output_mapping_profile.json"
];

for index = 1:size(profiles, 1)
    profileKey = profiles(index, 1);
    relativePath = profiles(index, 2);
    rows = fetch(conn, ...
        "SELECT cpv.version_label, cpv.profile_schema_version, cpv.content_format, " + ...
        "cpv.content_uri, cpv.checksum_sha256 FROM config_profile_versions cpv " + ...
        "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
        "WHERE cp.profile_key = " + sqlText(profileKey));
    verifyEqual(testCase, height(rows), 1);
    verifyEqual(testCase, string(rows.version_label(1)), "0.1.0");
    verifyEqual(testCase, string(rows.profile_schema_version(1)), "0.2-draft");
    verifyEqual(testCase, string(rows.content_format(1)), "json");
    verifyEqual(testCase, string(rows.content_uri(1)), relativePath);
    verifyEqual(testCase, string(rows.checksum_sha256(1)), sha256File(fullfile(repoRoot, relativePath)));
    verifyEqual(testCase, strlength(string(rows.checksum_sha256(1))), 64);
end
end

function verifyExtractorIdentities(testCase, conn)
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractors WHERE extractor_key = 'deepsqueak' " + ...
    "AND extractor_name = 'DeepSqueak'"), 1);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractors WHERE extractor_key = 'mupet' " + ...
    "AND extractor_name = 'MUPET'"), 1);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractor_versions ev " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE e.extractor_name = 'DeepSqueak' AND ev.version_label = '3.2.x' " + ...
    "AND ev.implementation_language = 'MATLAB'"), 1);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractor_versions ev " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE e.extractor_name = 'MUPET' AND ev.version_label = '2.1' " + ...
    "AND ev.implementation_language = 'MATLAB'"), 1);
end

function verifyRepresentativeFeatureSemantics(testCase, conn)
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM canonical_features " + ...
    "WHERE canonical_name IN ('call_start_time', 'call_end_time', 'call_duration', " + ...
    "'frequency_min', 'frequency_center', 'contour_median_frequency', " + ...
    "'inter_call_interval', 'native_detection_score')"), 8);

verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE e.extractor_name = 'DeepSqueak' " + ...
    "AND xf.native_name = 'Principle Frequency (kHz)' " + ...
    "AND xf.native_unit = 'kHz' " + ...
    "AND xf.derivation_stage = 'contour_derived' " + ...
    "AND xf.equivalence_class = 'vocalization_frequency_center' " + ...
    "AND cf.canonical_name = 'contour_median_frequency' " + ...
    "AND cf.canonical_unit = 'Hz' " + ...
    "AND fm.mapping_type = 'comparable' " + ...
    "AND fm.transform_key = 'kHz_to_Hz'"), 1);

verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE e.extractor_name = 'MUPET' " + ...
    "AND xf.native_name = 'syllable duration (msec)' " + ...
    "AND xf.native_unit = 'ms' " + ...
    "AND xf.derivation_stage = 'pre_noise_reduction_onset_offset' " + ...
    "AND xf.operational_variant = 'pre_noise_reduction' " + ...
    "AND cf.canonical_name = 'call_duration' " + ...
    "AND cf.canonical_unit = 's' " + ...
    "AND fm.mapping_type = 'comparable' " + ...
    "AND fm.transform_key = 'ms_to_s'"), 1);

verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN feature_mappings fm ON fm.extractor_feature_id = xf.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = fm.canonical_feature_id " + ...
    "WHERE e.extractor_name = 'DeepSqueak' " + ...
    "AND xf.native_name = 'Score' " + ...
    "AND cf.canonical_name = 'native_detection_score' " + ...
    "AND fm.mapping_type = 'noncomparable'"), 1);
end

function verifyPairwiseRelationships(testCase, conn)
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM feature_relationships WHERE consilience_eligible = 1"), 7);
verifyEqual(testCase, scalar(conn, ...
    "SELECT COUNT(*) AS n FROM feature_relationships " + ...
    "WHERE relationship_type = 'related' AND consilience_eligible = 0"), 2);

verifyEqual(testCase, relationshipCount(conn, ...
    "Begin Time (s)", "DeepSqueak", ...
    "Syllable start time (sec)", "MUPET", ...
    "conceptually_equivalent", 1), 1);
verifyEqual(testCase, relationshipCount(conn, ...
    "Mean Power (dB/Hz)", "DeepSqueak", ...
    "total syllable energy (dB)", "MUPET", ...
    "related", 0), 1);
end

function n = relationshipCount(conn, nativeA, extractorA, nativeB, extractorB, relationshipType, eligible)
sql = ...
    "SELECT COUNT(*) AS n FROM feature_relationships fr " + ...
    "JOIN extractor_features fa ON fa.extractor_feature_id = fr.feature_a_id " + ...
    "JOIN extractor_versions eva ON eva.extractor_version_id = fa.extractor_version_id " + ...
    "JOIN extractors ea ON ea.extractor_id = eva.extractor_id " + ...
    "JOIN extractor_features fb ON fb.extractor_feature_id = fr.feature_b_id " + ...
    "JOIN extractor_versions evb ON evb.extractor_version_id = fb.extractor_version_id " + ...
    "JOIN extractors eb ON eb.extractor_id = evb.extractor_id " + ...
    "WHERE fr.relationship_type = " + sqlText(relationshipType) + ...
    " AND fr.consilience_eligible = " + string(double(eligible)) + ...
    " AND ((" + ...
    "ea.extractor_name = " + sqlText(extractorA) + " AND fa.native_name = " + sqlText(nativeA) + ...
    " AND eb.extractor_name = " + sqlText(extractorB) + " AND fb.native_name = " + sqlText(nativeB) + ...
    ") OR (" + ...
    "ea.extractor_name = " + sqlText(extractorB) + " AND fa.native_name = " + sqlText(nativeB) + ...
    " AND eb.extractor_name = " + sqlText(extractorA) + " AND fb.native_name = " + sqlText(nativeA) + ...
    "))";
n = scalar(conn, sql);
end

function [conn, dbFile] = createDisposableDatabase(repoRoot)
dbFile = string(tempname) + ".sqlite";
conn = sqlite(char(dbFile), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
end

function counts = semanticCounts(conn)
tables = [
    "config_profiles"
    "config_profile_versions"
    "extractors"
    "extractor_versions"
    "canonical_features"
    "extractor_features"
    "feature_mappings"
    "feature_relationships"
];
counts = struct();
for tableName = tables'
    counts.(tableName) = scalar(conn, "SELECT COUNT(*) AS n FROM " + tableName);
end
end

function rows = profileVersionRows(conn, profileKey)
rows = fetch(conn, ...
    "SELECT cpv.version_label, cpv.profile_schema_version, cpv.content_format, " + ...
    "cpv.content_uri, cpv.checksum_sha256 FROM config_profile_versions cpv " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE cp.profile_key = " + sqlText(profileKey) + ...
    " ORDER BY cpv.version_label");
end

function count = featureMappingCountForProfileVersion(conn, profileKey, versionLabel)
count = scalar(conn, ...
    "SELECT COUNT(*) AS n FROM feature_mappings fm " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = fm.mapping_profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE cp.profile_key = " + sqlText(profileKey) + ...
    " AND cpv.version_label = " + sqlText(versionLabel));
end

function value = scalar(conn, sql)
result = fetch(conn, sql);
value = double(result.n(1));
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end

function cleanupDatabase(conn, dbFile)
if isopen(conn)
    close(conn);
end
deleteIfExists(dbFile);
deleteIfExists(dbFile + "-journal");
deleteIfExists(dbFile + "-wal");
deleteIfExists(dbFile + "-shm");
end

function writeText(path, text)
fileId = fopen(path, "w");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
clear cleaner
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end

function hash = sha256File(path)
fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:test:FileReadFailed", "Could not open file for hashing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8")';

digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(bytes, "int8"));
hashBytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
delete(cleaner);
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
