function tests = test_deepsqueak_import_integration
tests = functiontests({ ...
    @testFullChainFromProjectIntakeThroughDeepSqueakImport, ...
    @testProvenanceIsCompleteForEveryImportedDetection, ...
    @testCompatibleRerunAndRelocationAreStable, ...
    @testSameBasenameDifferentContentIsNotConflated, ...
    @testChangedScientificContentUnderOneRunIdentityConflicts, ...
    @testMalformedInputIsClassifiedAtTheCorrectLayer, ...
    @testTransactionOwnershipAndConnectionContract, ...
    @testPhase3ProjectGraphIsUnaffectedByExtractorImport, ...
    @testImporterDoesNotDuplicateSourceMappingSemantics});
end

function testFullChainFromProjectIntakeThroughDeepSqueakImport(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>

% Phase 3 established the project graph through the real public path, with
% tracked device and setup linkage. Nothing below recreates any of it.
verifyEqual(testCase, fixture.intake.status, "completed");
verifyTrue(testCase, fixture.intake.committed);
verifyEqual(testCase, countOf(fixture.conn, "recordings"), 1);

result = importExport(fixture, fixture.export_path, defaultRunSpec(), true);

verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.recording.recording_id, fixture.recording_id);
verifyEqual(testCase, result.applied_counts.extraction_runs, 1);
verifyEqual(testCase, result.applied_counts.detections, 3);
verifyEqual(testCase, result.applied_counts.event_measurements, 42);
verifyEqual(testCase, result.applied_counts.curation_events, 3);
verifyEqual(testCase, result.applied_counts.classification_assignments, 3);

% The whole supported workflow is one public call. No caller stitches private
% plan or apply helpers together.
verifyEqual(testCase, countOf(fixture.conn, "detections"), 3);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

% Warnings, conflicts, counts, and identifiers are all readable from the result
% rather than from console output.
verifyTrue(testCase, istable(result.diagnostics));
verifyEmpty(testCase, result.conflicts);
verifyGreaterThan(testCase, result.extraction_run.extraction_run_id, 0);
verifyEqual(testCase, height(result.events), 3);

clear cleanup
end

function testProvenanceIsCompleteForEveryImportedDetection(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>

runSpec = defaultRunSpec();
runSpec.settings = struct(profile_path=fixture.settings_profile_path);
runSpec.model = struct(artifact_path=fixture.model_path, model_label="rat_detector_v2");
runSpec.native_artifact = struct(artifact_path=fixture.native_path);
importExport(fixture, fixture.export_path, runSpec, true);

% Every element of the required provenance chain is reachable from a detection
% by an unambiguous relational path. Not all of it hangs off the detection row.
chain = fetch(fixture.conn, ...
    "SELECT d.detection_id, d.native_event_id, " + ...
    "p.project_key, IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
    "IFNULL(sf.relative_path,'') AS audio_source, " + ...
    "er.run_key, ev.version_label AS extractor_version, e.extractor_name, " + ...
    "ocp.profile_key AS output_profile, ocv.version_label AS output_profile_version, " + ...
    "ocv.checksum_sha256 AS output_profile_checksum, " + ...
    "scp.profile_key AS settings_profile, scv.checksum_sha256 AS settings_checksum " + ...
    "FROM detections d " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id " + ...
    "JOIN recordings r ON r.recording_id = d.recording_id " + ...
    "JOIN source_files sf ON sf.source_file_id = r.source_file_id " + ...
    "JOIN projects p ON p.project_id = r.project_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN config_profile_versions ocv ON ocv.profile_version_id = er.output_mapping_profile_version_id " + ...
    "JOIN config_profiles ocp ON ocp.profile_id = ocv.profile_id " + ...
    "JOIN config_profile_versions scv ON scv.profile_version_id = er.settings_profile_version_id " + ...
    "JOIN config_profiles scp ON scp.profile_id = scv.profile_id " + ...
    "ORDER BY CAST(d.native_event_id AS INTEGER)");
verifyEqual(testCase, height(chain), 3);
verifyEqual(testCase, unique(string(chain.project_key)), "demo_mouse_folder");
verifyEqual(testCase, unique(string(chain.extractor_name)), "DeepSqueak");
verifyEqual(testCase, unique(string(chain.extractor_version)), "3.2.1");
verifyEqual(testCase, unique(string(chain.output_profile)), "vawlume.deepsqueak.output.v3_2");
verifyMatches(testCase, string(chain.output_profile_checksum(1)), "^[0-9a-f]{64}$");
verifyMatches(testCase, string(chain.settings_checksum(1)), "^[0-9a-f]{64}$");

% Acquisition context is inherited from the recording that Phase 3 linked, and
% is reachable without the extractor import having touched it.
device = fetch(fixture.conn, ...
    "SELECT cp.profile_kind, cp.profile_key, rpa.inheritance_source " + ...
    "FROM detections d " + ...
    "JOIN recording_profile_assignments rpa ON rpa.recording_id = d.recording_id " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = rpa.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE d.native_event_id = '1' ORDER BY cp.profile_kind");
verifyEqual(testCase, string(device.profile_kind), ...
    ["experimental_setup"; "recording_device"]);

% Experimental context: the recording's participants, from project intake.
context = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM detections d " + ...
    "JOIN v_recording_entity_context ctx ON ctx.recording_id = d.recording_id " + ...
    "WHERE d.native_event_id = '1'");
verifyGreaterThan(testCase, double(context.n(1)), 0);

% Artifacts: the call-statistics export with its checksum, the native detection
% container, and the detector model.
artifacts = fetch(fixture.conn, ...
    "SELECT ra.artifact_role, a.artifact_type, " + ...
    "IFNULL(a.checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM detections d " + ...
    "JOIN extraction_run_artifacts ra ON ra.extraction_run_id = d.extraction_run_id " + ...
    "JOIN artifacts a ON a.artifact_id = ra.artifact_id " + ...
    "WHERE d.native_event_id = '1' ORDER BY ra.artifact_role");
verifyEqual(testCase, string(artifacts.artifact_role), ...
    ["detector_network"; "event_measurement_export"; "native_detection_container"]);
verifyTrue(testCase, all(strlength(string(artifacts.checksum_sha256)) == 64));

% Native field, value, unit, canonical mapping, and transform for one call.
measurement = fetch(fixture.conn, ...
    "SELECT xf.native_name, em.native_value_real, em.native_unit, " + ...
    "cf.canonical_name, em.canonical_value_real, em.canonical_unit, em.transform_key " + ...
    "FROM detections d " + ...
    "JOIN event_measurements em ON em.detection_id = d.detection_id " + ...
    "JOIN extractor_features xf ON xf.extractor_feature_id = em.extractor_feature_id " + ...
    "JOIN canonical_features cf ON cf.canonical_feature_id = em.canonical_feature_id " + ...
    "WHERE d.native_event_id = '1' AND xf.native_name = 'Low Freq (kHz)'");
verifyEqual(testCase, double(measurement.native_value_real(1)), 45.1, AbsTol=1e-9);
verifyEqual(testCase, string(measurement.native_unit(1)), "kHz");
verifyEqual(testCase, string(measurement.canonical_name(1)), "frequency_min");
verifyEqual(testCase, double(measurement.canonical_value_real(1)), 45100, AbsTol=1e-6);
verifyEqual(testCase, string(measurement.transform_key(1)), "kHz_to_Hz");

% Review and label evidence.
evidence = fetch(fixture.conn, ...
    "SELECT (SELECT COUNT(*) FROM curation_events) AS review_rows, " + ...
    "(SELECT COUNT(*) FROM classification_assignments) AS label_rows");
verifyEqual(testCase, double(evidence.review_rows(1)), 3);
verifyEqual(testCase, double(evidence.label_rows(1)), 3);

clear cleanup
end

function testCompatibleRerunAndRelocationAreStable(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>

first = importExport(fixture, fixture.export_path, defaultRunSpec(), true);
after = tableCounts(fixture.conn);

% Rerunning the identical import writes nothing at all. The importer records no
% per-attempt audit row, so a compatible rerun is a true no-op rather than a
% growing attempt log.
rerun = importExport(fixture, fixture.export_path, defaultRunSpec(), true);
verifyTrue(testCase, rerun.committed);
verifyEqual(testCase, tableCounts(fixture.conn), after);
verifyEqual(testCase, rerun.applied_counts.detections, 0);
verifyEqual(testCase, rerun.applied_counts.event_measurements, 0);
verifyEqual(testCase, rerun.detections.detections_reuse, 3);

% The same content under a different absolute root keeps one portable identity,
% so relocation creates no second run, artifact, or detection population.
relocatedRoot = fullfile(fixture.scratch, "relocated");
relocatedPath = fullfile(relocatedRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(relocatedPath);
copyfile(fixture.export_path, relocatedPath);

relocated = vawlume.ingest.deepsqueak(fixture.conn, relocatedPath, ...
    fixture.recording_ref, defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=relocatedRoot, Apply=true);
verifyTrue(testCase, relocated.committed);
verifyEqual(testCase, relocated.extraction_run.action, "reuse");
verifyEqual(testCase, string(relocated.artifacts.action(1)), "reuse");
verifyEqual(testCase, tableCounts(fixture.conn), after);

% The persisted artifact path is the portable one first registered; a rerun from
% a new location reports its runtime path diagnostically but does not rewrite
% historical provenance.
stored = fetch(fixture.conn, "SELECT path_or_uri FROM artifacts " + ...
    "WHERE artifact_type = 'extractor_event_export'");
verifyEqual(testCase, string(stored.path_or_uri(1)), "exports/REC_A_Stats.xlsx");
verifyNotEqual(testCase, relocated.export.runtime_path, first.export.runtime_path);

clear cleanup
end

function testSameBasenameDifferentContentIsNotConflated(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>
importExport(fixture, fixture.export_path, defaultRunSpec(), true);

% A second workbook with the same basename, a different relative location, and
% different content is a different artifact. Filenames never establish identity.
otherRoot = fullfile(fixture.scratch, "second_session");
otherPath = fullfile(otherRoot, "session2", "REC_A_Stats.xlsx");
makeParentFolder(otherPath);
writeExport(otherPath, variantExport(0.5));

secondRun = defaultRunSpec();
secondRun.run_key = "ds-run-session2";
result = vawlume.ingest.deepsqueak(fixture.conn, otherPath, ...
    fixture.recording_ref, secondRun, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=otherRoot, Apply=true);

verifyTrue(testCase, result.committed);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 2);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 2);
verifyEqual(testCase, countOf(fixture.conn, "detections"), 6);

paths = fetch(fixture.conn, ...
    "SELECT path_or_uri, checksum_sha256 FROM artifacts " + ...
    "WHERE artifact_type = 'extractor_event_export' ORDER BY path_or_uri");
verifyEqual(testCase, string(paths.path_or_uri), ...
    ["exports/REC_A_Stats.xlsx"; "session2/REC_A_Stats.xlsx"]);
verifyNotEqual(testCase, string(paths.checksum_sha256(1)), ...
    string(paths.checksum_sha256(2)));

clear cleanup
end

function testChangedScientificContentUnderOneRunIdentityConflicts(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>
importExport(fixture, fixture.export_path, defaultRunSpec(), true);
before = tableCounts(fixture.conn);

% Changing a call boundary, a mapped feature, the accepted state, or a label all
% change the workbook's bytes. Under the same declared run identity that is a
% different export, and the importer says so instead of accepting it as a
% compatible rerun just because the native call IDs still match.
names = ["boundary"; "feature"; "accepted"; "label"];
variants = {changedBoundaryExport(); variantExport(0.5); ...
    changedAcceptedExport(); changedLabelExport()};

for index = 1:numel(names)
    variantRoot = fullfile(fixture.scratch, "variant_" + names(index));
    variantPath = fullfile(variantRoot, "exports", "REC_A_Stats.xlsx");
    makeParentFolder(variantPath);
    writeExport(variantPath, variants{index});

    result = vawlume.ingest.deepsqueak(fixture.conn, variantPath, ...
        fixture.recording_ref, defaultRunSpec(), RepoRoot=fixture.repo_root, ...
        ArtifactRoot=variantRoot, Apply=true);

    verifyEqual(testCase, result.status, "conflict", ...
        "Variant '" + names(index) + "' should conflict.");
    verifyFalse(testCase, result.committed);
    verifyTrue(testCase, any(result.diagnostics.layer == "identity"));
    verifyEqual(testCase, tableCounts(fixture.conn), before);
end

% Reordering the same calls also changes the file's bytes and is reported the
% same way. Content identity is the file's checksum, not its row set.
reorderRoot = fullfile(fixture.scratch, "reordered");
reorderPath = fullfile(reorderRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(reorderPath);
cells = nominalExport();
writeExport(reorderPath, [cells(1, :); cells([4, 2, 3], :)]);
reordered = vawlume.ingest.deepsqueak(fixture.conn, reorderPath, ...
    fixture.recording_ref, defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=reorderRoot, Apply=true);
verifyEqual(testCase, reordered.status, "conflict");
verifyEqual(testCase, tableCounts(fixture.conn), before);

% A new run key does not rescue a conflicting artifact identity. Artifacts are
% project-scoped, so two different files cannot occupy one portable path even
% under different runs, and the conflict is reported rather than one silently
% overwriting the other.
distinct = defaultRunSpec();
distinct.run_key = "ds-run-reordered";
sameLocation = vawlume.ingest.deepsqueak(fixture.conn, reorderPath, ...
    fixture.recording_ref, distinct, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=reorderRoot, Apply=true);
verifyEqual(testCase, sameLocation.status, "conflict");
verifyTrue(testCase, any(contains(sameLocation.conflicts, "registered with checksum")));
verifyEqual(testCase, tableCounts(fixture.conn), before);

% Given its own portable location, the reordered export imports cleanly as a
% distinct run, and its calls are recognised by native identifier rather than by
% row order.
ownRoot = fullfile(fixture.scratch, "reordered_own");
ownPath = fullfile(ownRoot, "session_b", "REC_A_Stats.xlsx");
makeParentFolder(ownPath);
copyfile(reorderPath, ownPath);
accepted = vawlume.ingest.deepsqueak(fixture.conn, ownPath, ...
    fixture.recording_ref, distinct, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=ownRoot, Apply=true);
verifyTrue(testCase, accepted.committed);
verifyEqual(testCase, sort(string(accepted.events.native_event_id)), ["1"; "2"; "3"]);

clear cleanup
end

function testMalformedInputIsClassifiedAtTheCorrectLayer(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>
before = tableCounts(fixture.conn);

% Each failure names the layer that actually disagreed. None is collapsed into a
% generic import error, and none mutates the database.
cases = {
    "adapter",        "vawlume:ingest:DeepSqueakArtifactNotFound",     @() importPath(fixture, fullfile(fixture.scratch, "absent.xlsx"), defaultRunSpec())
    "adapter",        "vawlume:ingest:DeepSqueakArtifactUnreadable",   @() importPath(fixture, malformedWorkbook(fixture), defaultRunSpec())
    "adapter",        "vawlume:ingest:DeepSqueakArtifactUnsupported",  @() importSheet(fixture, "NoSuchSheet")
    "adapter",        "vawlume:ingest:DeepSqueakArtifactNotPortable",  @() importWithoutRoot(fixture)
    "source_mapping", "vawlume:ingest:DeepSqueakIRNotValid",           @() importVariant(fixture, "missingcolumn", missingColumnExport())
    "source_mapping", "vawlume:source_mapping:UnexpectedProfileKind",  @() importWrongProfileKind(fixture)
    "preflight",      "vawlume:ingest:DeepSqueakVersionRequired",      @() importPath(fixture, fixture.export_path, rmfield(defaultRunSpec(), "extractor_version"))
    "preflight",      "vawlume:ingest:DeepSqueakVersionIncompatible",  @() importPath(fixture, fixture.export_path, withVersion("2.9.0"))
    "preflight",      "vawlume:ingest:DeepSqueakRecordingNotFound",    @() importUnknownRecording(fixture)
    "preflight",      "vawlume:ingest:DeepSqueakRecordingRefInvalid",  @() importBadRef(fixture)
    "preflight",      "vawlume:ingest:DeepSqueakEventValidationFailed", @() importVariant(fixture, "duplicateid", duplicateIdExport())
    "preflight",      "vawlume:ingest:DeepSqueakEventValidationFailed", @() importVariant(fixture, "reversed", reversedTimeExport())
    "preflight",      "vawlume:ingest:DeepSqueakRunSpecInvalid",       @() importPath(fixture, fixture.export_path, rmfield(defaultRunSpec(), "run_key"))
    "preflight",      "vawlume:ingest:DeepSqueakSettingsNotFound",     @() importMissingSettings(fixture)
    "preflight",      "vawlume:ingest:DeepSqueakArtifactNotFound",     @() importMissingModel(fixture)
};

for index = 1:size(cases, 1)
    verifyError(testCase, cases{index, 3}, cases{index, 2}, ...
        "Expected " + cases{index, 1} + " layer failure " + cases{index, 2} + ".");
end
verifyEqual(testCase, tableCounts(fixture.conn), before);

% An unparseable value in a numeric column is refused, but at the preflight
% layer rather than as a coercion failure: readtable collapses non-numeric text
% in a numeric column to NaN, so the mapper sees an absent value rather than a
% bad one. The import is still blocked, because a required timing value is then
% missing, and no bad value can reach the database.
verifyError(testCase, @() importVariant(fixture, "badnumber", nonNumericExport()), ...
    "vawlume:ingest:DeepSqueakEventValidationFailed");

% An optional missing feature value is nonfatal and imports with an
% informational diagnostic rather than an error.
optional = importExport(fixture, fixture.export_path, defaultRunSpec(), false);
missingRows = optional.diagnostics(optional.diagnostics.code == "MISSING_TOKEN_NORMALIZED", :);
verifyEqual(testCase, height(missingRows), 1);
verifyEqual(testCase, string(missingRows.severity(1)), "info");
verifyEqual(testCase, string(missingRows.layer(1)), "source_mapping");
verifyEqual(testCase, optional.status, "planned");

% An extractor version inside the compatible family rather than the preferred
% scope is a warning, not a refusal.
family = importExport(fixture, fixture.export_path, withVersion("3.1.4"), false);
familyRows = family.diagnostics(family.diagnostics.layer == "preflight" & ...
    family.diagnostics.severity == "warning", :);
verifyGreaterThan(testCase, height(familyRows), 0);
verifyEqual(testCase, family.status, "planned");

clear cleanup
end

function testTransactionOwnershipAndConnectionContract(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>

% Exactly one function per import path in the ingest namespace owns a
% transaction: project intake's applier, the DeepSqueak applier, the MUPET
% applier, and the alignment-registration applier. No resolver or registrar
% commits independently, no shared helper opens a transaction of its own, and
% semantic seed registration is never called from inside an import transaction.
owners = transactionOwners(fixture.repo_root);
verifyEqual(testCase, sort(owners), ...
    sort(["applyEntityPlan.m"; "deepsqueakApplyPlan.m"; "mupetApplyPlan.m"; ...
    "alignmentApplyPlan.m"]));

importerText = readAll(fullfile(fixture.repo_root, "src", "+vawlume", "+ingest"));
verifyFalse(testCase, contains(importerText, "registerBuiltinSemantics("), ...
    "The importer must not invoke semantic seed registration inside its transaction.");

% Apply requires a connection entering with autocommit enabled, as project
% intake does, so the importer owns a complete transaction rather than joining
% someone else's.
fixture.conn.AutoCommit = "off";
restore = onCleanup(@() setAutoCommit(fixture.conn, "on"));
verifyError(testCase, ...
    @() importExport(fixture, fixture.export_path, defaultRunSpec(), true), ...
    "vawlume:ingest:TransactionState");
clear restore
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

% A failure on the last written table rolls back every scientific row from that
% apply and restores connection state. No partial run survives, and nothing is
% recorded as a completed import.
before = tableCounts(fixture.conn);
verifyError(testCase, @() applyWithInducedFailure(fixture), ...
    "vawlume:ingest:InducedApplyFailure");
verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 0);
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");

% The connection is still usable afterwards.
recovered = importExport(fixture, fixture.export_path, defaultRunSpec(), true);
verifyTrue(testCase, recovered.committed);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testPhase3ProjectGraphIsUnaffectedByExtractorImport(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>

phase3Before = phase3Snapshot(fixture.conn);
runSpec = defaultRunSpec();
runSpec.settings = struct(profile_path=fixture.settings_profile_path);
importExport(fixture, fixture.export_path, runSpec, true);
importExport(fixture, fixture.export_path, runSpec, true);

% Extractor import consumes the project graph and never writes to it: no entity,
% relationship, source file, recording, participant link, ingestion audit row, or
% device/setup assignment changes.
verifyEqual(testCase, phase3Snapshot(fixture.conn), phase3Before);

% The recording's identity is never re-derived from the workbook filename.
recording = fetch(fixture.conn, ...
    "SELECT sf.relative_path, sf.filename FROM recordings r " + ...
    "JOIN source_files sf ON sf.source_file_id = r.source_file_id");
verifyEqual(testCase, string(recording.filename(1)), "001_baseline_1.wav");
verifyFalse(testCase, contains(string(recording.relative_path(1)), "Stats"));

% The settings profile the importer registered is project-scoped and does not
% disturb the built-in profile namespace Phase 3 and the seed layer share.
builtins = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM config_profiles WHERE project_id IS NULL");
verifyEqual(testCase, double(builtins.n(1)), phase3Before.builtin_profiles);

% Project intake itself carries no DeepSqueak branch.
intakeText = readAll(fullfile(fixture.repo_root, "src", "+vawlume", "+ingest", ...
    "project.m"));
verifyFalse(testCase, contains(lower(intakeText), "deepsqueak"));
verifyFalse(testCase, contains(lower(intakeText), "extractor_output"));

clear cleanup
end

function testImporterDoesNotDuplicateSourceMappingSemantics(testCase)
[fixture, cleanup] = setUpChain(); %#ok<ASGLU>

text = readAll(fullfile(fixture.repo_root, "src", "+vawlume", "+ingest"));

% No canonical feature dictionary, no native column dictionary, and no
% importer-local unit conversion. Field semantics live in the tracked profile and
% the seeded vocabulary; the importer reads them.
for canonicalName = ["call_start_time", "call_end_time", "call_duration", ...
        "contour_median_frequency", "frequency_min", "frequency_max", ...
        "frequency_bandwidth", "frequency_sd", "frequency_slope", ...
        "peak_frequency", "contour_sinuosity", "tonality", ...
        "mean_power_spectral_density", "native_detection_score", ...
        "native_call_label"]
    verifyFalse(testCase, contains(text, """" + canonicalName + """"), ...
        "Canonical feature name " + canonicalName + " must not appear in the importer.");
end

for nativeLabel = ["Begin Time (s)", "End Time (s)", "Call Length (s)", ...
        "Principle Frequency (kHz)", "Low Freq (kHz)", "High Freq (kHz)", ...
        "Delta Freq (kHz)", "Slope (kHz/s)", "Mean Power (dB/Hz)", "Peak Freq (kHz)"]
    verifyFalse(testCase, contains(text, """" + nativeLabel + """"), ...
        "Native column label " + nativeLabel + " must not appear in the importer.");
end

for transformKey = ["kHz_to_Hz", "kHz_per_s_to_Hz_per_s", "1000"]
    verifyFalse(testCase, contains(text, """" + transformKey + """"), ...
        "Unit conversion belongs to the mapping profile's transform registry.");
end

% The mapping profile is decoded once by the source-mapping loader; the importer
% never re-reads or re-decodes it, and never rediscovers sources.
%
% The settings resolver is excluded from the JSON check on purpose. A
% caller-supplied extractor settings profile is an external tool's configuration,
% not a VAWLUME profile language, so the loader does not handle it and the
% resolver reads only its identity and checksum.
mappingText = deepsqueakSourceText(fixture.repo_root, "deepsqueakResolveSettingsProfile.m");
verifyFalse(testCase, contains(mappingText, "jsondecode"));
verifyTrue(testCase, contains(text, "vawlume.source_mapping.loadProfile"));

for forbidden = ["discoverSources", "parsePath", "source_mapping.parse", "regexp("]
    verifyFalse(testCase, contains(text, forbidden));
end

% Transforms come from the closed central registry, which the importer only
% records by key.
registryText = readAll(fullfile(fixture.repo_root, "src", "+vawlume", ...
    "+source_mapping", "private", "supportedTransformKeys.m"));
verifyTrue(testCase, contains(registryText, "kHz_to_Hz"));

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpChain()
%SETUPCHAIN Build the real Phase 1-3 chain, then stage a DeepSqueak export.
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));

scratch = string(tempname);
mkdir(scratch);
dbFile = fullfile(scratch, "deepsqueak_integration.sqlite");
copyfile(seededTemplateDatabase(repoRoot), dbFile);
conn = sqlite(char(dbFile));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));

% Phase 3, through the public path, with tracked device and setup linkage.
profilePath = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "project_inputs", "project_input_source_mapping_examples.json");
sourceRoot = fullfile(scratch, "project");
audioPath = fullfile(sourceRoot, "control", "mouse_001", "baseline", ...
    "001_baseline_1.wav");
makeParentFolder(audioPath);
writeText(audioPath, "synthetic audio stand-in");

ir = vawlume.source_mapping.parse(profilePath, sourceRoot, ...
    ProfileId="example.project.mouse_courtship.folder_driven", RepoRoot=repoRoot);
intake = vawlume.ingest.project(conn, ir, struct( ...
    project_key="demo_mouse_folder", ...
    project_name="Folder-driven mouse integration fixture", ...
    description="Phase 4 integration fixture."), Apply=true, ...
    ProfileLinkagePath=fullfile(repoRoot, "config", "04_examples", ...
    "profile_linkage_example.json"), RepoRoot=repoRoot);

recordings = fetch(conn, "SELECT recording_id, source_file_id FROM recordings");

artifactRoot = fullfile(scratch, "deepsqueak");
exportPath = fullfile(artifactRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(exportPath);
writeExport(exportPath, nominalExport());

fixture = struct();
fixture.conn = conn;
fixture.repo_root = repoRoot;
fixture.scratch = scratch;
fixture.artifact_root = artifactRoot;
fixture.export_path = exportPath;
fixture.intake = intake;
fixture.recording_id = double(recordings.recording_id(1));
fixture.recording_ref = struct(recording_id=fixture.recording_id);
fixture.profile_path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.json");
fixture.project_profile_path = profilePath;

fixture.settings_profile_path = fullfile(artifactRoot, "lab_settings.json");
writeText(fixture.settings_profile_path, jsonencode(struct( ...
    profile=struct(id="lab.deepsqueak.settings.v1", ...
    name="Laboratory DeepSqueak settings", kind="extractor_settings", ...
    profile_version="1.0.0"), detection=struct(score_threshold=0.5))));
fixture.model_path = fullfile(artifactRoot, "detector_network.mat");
writeText(fixture.model_path, "synthetic detector network stand-in");
fixture.native_path = fullfile(artifactRoot, "REC_A_deepsqueak.mat");
writeText(fixture.native_path, "synthetic native detection container stand-in");
end

function path = seededTemplateDatabase(repoRoot)
persistent templatePath
if ~isempty(templatePath) && isfile(templatePath)
    path = templatePath;
    return
end
templatePath = string(tempname) + ".sqlite";
conn = sqlite(char(templatePath), "create");
cleaner = onCleanup(@() close(conn));
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
vawlume.db.registerBuiltinSemantics(conn, repoRoot);
delete(cleaner);
path = templatePath;
end

function tearDown(conn, scratch, repoRoot)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function spec = defaultRunSpec()
spec = struct(run_key="ds-run-1", extractor_version="3.2.1", ...
    run_label="DeepSqueak integration run");
end

function spec = withVersion(version)
spec = defaultRunSpec();
spec.extractor_version = version;
end

function result = importExport(fixture, exportPath, runSpec, applyIt)
result = vawlume.ingest.deepsqueak(fixture.conn, exportPath, ...
    fixture.recording_ref, runSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root, Apply=applyIt);
end

function result = importPath(fixture, exportPath, runSpec)
result = vawlume.ingest.deepsqueak(fixture.conn, exportPath, ...
    fixture.recording_ref, runSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root, Apply=true);
end

function result = importVariant(fixture, name, cells)
variantRoot = fullfile(fixture.scratch, "bad_" + name);
variantPath = fullfile(variantRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(variantPath);
writeExport(variantPath, cells);
result = vawlume.ingest.deepsqueak(fixture.conn, variantPath, ...
    fixture.recording_ref, defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=variantRoot, Apply=true);
end

function result = importSheet(fixture, sheetName)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_path, ...
    fixture.recording_ref, defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root, Sheet=sheetName, Apply=true);
end

function result = importWithoutRoot(fixture)
orphanPath = fullfile(fixture.scratch, "orphan_Stats.xlsx");
copyfile(fixture.export_path, orphanPath);
result = vawlume.ingest.deepsqueak(fixture.conn, orphanPath, ...
    fixture.recording_ref, defaultRunSpec(), ProfilePath=fixture.profile_path, ...
    Apply=true);
end

function result = importUnknownRecording(fixture)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_path, ...
    struct(recording_id=99999), defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root, Apply=true);
end

function result = importBadRef(fixture)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_path, ...
    struct(project_key="demo_mouse_folder"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
end

function result = importWrongProfileKind(fixture)
% A project-input profile is not an extractor-output profile.
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_path, ...
    fixture.recording_ref, defaultRunSpec(), RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root, ProfilePath=fixture.project_profile_path, ...
    Apply=true);
end

function result = importMissingSettings(fixture)
runSpec = defaultRunSpec();
runSpec.settings = struct(profile_path=fullfile(fixture.scratch, "absent_settings.json"));
result = importPath(fixture, fixture.export_path, runSpec);
end

function result = importMissingModel(fixture)
runSpec = defaultRunSpec();
runSpec.model = struct(artifact_path=fullfile(fixture.scratch, "absent_model.mat"));
result = importPath(fixture, fixture.export_path, runSpec);
end

function path = malformedWorkbook(fixture)
path = fullfile(fixture.scratch, "malformed_Stats.xlsx");
writeText(path, "this is not a workbook");
end

function applyWithInducedFailure(fixture)
execute(fixture.conn, ...
    "CREATE TRIGGER trg_induced_integration_failure " + ...
    "BEFORE INSERT ON classification_assignments FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced integration failure'); END");
restore = onCleanup(@() dropTrigger(fixture.conn));
try
    importExport(fixture, fixture.export_path, defaultRunSpec(), true);
catch exception
    clear restore
    error("vawlume:ingest:InducedApplyFailure", ...
        "Induced apply failure surfaced as: %s", exception.message);
end
clear restore
error("vawlume:ingest:InducedApplyFailure", "The induced failure did not abort the apply.");
end

function dropTrigger(conn)
try
    execute(conn, "DROP TRIGGER IF EXISTS trg_induced_integration_failure");
catch
end
end

function setAutoCommit(conn, state)
try
    conn.AutoCommit = state;
catch
end
end

function owners = transactionOwners(repoRoot)
files = dir(fullfile(repoRoot, "src", "+vawlume", "+ingest", "**", "*.m"));
owners = strings(0, 1);
for index = 1:numel(files)
    text = string(fileread(fullfile(files(index).folder, files(index).name)));
    if contains(text, "conn.AutoCommit = ""off""")
        owners(end + 1, 1) = string(files(index).name); %#ok<AGROW>
    end
end
end

function snapshot = phase3Snapshot(conn)
% config_profile_versions is deliberately absent: a caller-supplied extractor
% settings profile legitimately adds one, and that row is extractor-run evidence
% rather than part of the Phase 3 project graph. The built-in profile namespace
% is checked separately and must not move.
tables = ["projects", "source_files", "recordings", "entity_types", ...
    "experimental_entities", "entity_relationships", "recording_entity_links", ...
    "ingestion_runs", "ingestion_files", "project_profile_assignments", ...
    "recording_profile_assignments"];
snapshot = struct();
for name = tables
    snapshot.(name) = countOf(conn, name);
end
rows = fetch(conn, "SELECT COUNT(*) AS n FROM config_profiles WHERE project_id IS NULL");
snapshot.builtin_profiles = double(rows.n(1));
end

function text = deepsqueakSourceText(repoRoot, excludedName)
%DEEPSQUEAKSOURCETEXT The DeepSqueak importer's own sources, by naming convention.
%
% Scoped to the DeepSqueak files so a guard on this importer does not accidentally
% assert something about project intake, which shares the ingest namespace.
text = "";
files = dir(fullfile(repoRoot, "src", "+vawlume", "+ingest", "**", "*.m"));
for index = 1:numel(files)
    name = string(files(index).name);
    if ~startsWith(name, "deepsqueak") || name == excludedName
        continue
    end
    text = text + newline + string(fileread(fullfile(files(index).folder, files(index).name)));
end
end

function text = readAll(target)
text = "";
if isfile(target)
    text = string(fileread(target));
    return
end
files = dir(fullfile(target, "**", "*.m"));
for index = 1:numel(files)
    text = text + newline + string(fileread(fullfile(files(index).folder, files(index).name)));
end
end

function headers = nominalHeaders()
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
end

function cells = nominalExport()
detectionFile = 'C:\deepsqueak\detections\REC_A_deepsqueak.mat';
cells = [
    nominalHeaders()
    {detectionFile, 1, '22kHz-Call', 1, 0.9134, 10.000, 10.050, 0.050, ...
        62.4, 45.1, 80.2, 35.1, 3.2, -120.5, 1.12, -71.4, 0.78, 63.0}
    {detectionFile, 2, 'USV', 1, 0.8021, 20.000, 20.040, 0.040, ...
        61.0, 50.0, 72.0, 22.0, 2.1, 15.0, 1.05, -70.1, [], 61.5}
    {detectionFile, 3, 'Noise', 0, 0.2107, 40.000, 40.100, 0.100, ...
        63.5, 42.0, 84.0, 42.0, 4.4, -8.25, 1.40, -69.3, 0.69, 64.2}
];
end

function cells = variantExport(score)
cells = nominalExport();
cells{2, 5} = score;
end

function cells = changedBoundaryExport()
cells = nominalExport();
cells{2, 7} = 10.075;
end

function cells = changedAcceptedExport()
cells = nominalExport();
cells{2, 4} = 0;
end

function cells = changedLabelExport()
cells = nominalExport();
cells{2, 3} = 'Trill';
end

function cells = duplicateIdExport()
cells = nominalExport();
cells{3, 2} = 1;
end

function cells = reversedTimeExport()
cells = nominalExport();
cells{2, 7} = 9.5;
end

function cells = missingColumnExport()
cells = nominalExport();
cells(:, strcmp(cells(1, :), 'Tonality')) = [];
end

function cells = nonNumericExport()
cells = nominalExport();
cells{2, 6} = 'not a number';
end

function writeExport(path, cells)
if isfile(path)
    delete(path);
end
writecell(cells, path);
end

function counts = tableCounts(conn)
tables = ["artifacts", "extraction_runs", "extraction_run_inputs", ...
    "extraction_run_artifacts", "detections", "event_measurements", ...
    "curation_events", "classification_runs", "classification_classes", ...
    "classification_assignments", "config_profiles", "config_profile_versions"];
counts = struct();
for name = tables
    counts.(name) = countOf(conn, name);
end
end

function value = countOf(conn, tableName)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + tableName);
value = double(rows.n(1));
end

function makeParentFolder(path)
parent = fileparts(path);
if ~isfolder(parent)
    mkdir(parent);
end
end

function writeText(path, text)
makeParentFolder(path);
fileId = fopen(path, "w");
assert(fileId >= 0, "Could not open %s for writing.", path);
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
delete(cleaner);
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
