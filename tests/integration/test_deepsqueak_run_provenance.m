function tests = test_deepsqueak_run_provenance
tests = functiontests({ ...
    @testPlanIsReadOnlyAndFullyInspectable, ...
    @testApplyCreatesRunProvenanceGraph, ...
    @testRecordingResolutionModesAndFailures, ...
    @testSeededExtractorAndOutputProfileAreResolvedNotCreated, ...
    @testExtractorVersionRequirementComesFromProfile, ...
    @testCompatibleRerunReusesEverything, ...
    @testRelocatedExportReusesArtifactAndRun, ...
    @testDifferentPortableExportIdentityConflicts, ...
    @testChangedContentUnderSameIdentityConflicts, ...
    @testDistinctRunOverSameRecordingCoexists, ...
    @testSettingsProvenanceIsCapturedOrExplicitlyAbsent, ...
    @testModelProvenanceIsNeverFabricated, ...
    @testIdentityDefiningOptionalArtifactsCannotChangeOnRerun, ...
    @testInvalidProvenanceRollsBackCompletely, ...
    @testRelationalReadBacksAnswerProvenanceQuestions});
end

function testPlanIsReadOnlyAndFullyInspectable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

before = tableCounts(fixture.conn);
result = plan(fixture, defaultRunSpec());
after = tableCounts(fixture.conn);

% Planning must not touch the database at all.
verifyEqual(testCase, after, before);
verifyEqual(testCase, result.status, "planned");
verifyFalse(testCase, result.committed);
verifyFalse(testCase, result.has_conflicts);

% Every disposition is readable from the result rather than from console output.
verifyEqual(testCase, result.recording.recording_id, fixture.recording_a);
verifyEqual(testCase, result.output_profile.action, "reuse");
verifyEqual(testCase, result.extraction_run.action, "create");
verifyEqual(testCase, result.extraction_run.input_action, "create");
verifyEqual(testCase, string(result.artifacts.action(1)), "create");
verifyEqual(testCase, result.settings.status, "not_recoverable");
verifyEqual(testCase, result.model.status, "not_recoverable");

% The event population is planned in the same pass and applied in the same
% transaction, so planning reports it without writing any of it.
verifyEqual(testCase, result.detections.planned, 2);
verifyEqual(testCase, result.detections.detections_create, 2);

clear cleanup
end

function testApplyCreatesRunProvenanceGraph(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

result = apply(fixture, defaultRunSpec());

verifyEqual(testCase, result.status, "committed");
verifyTrue(testCase, result.committed);
verifyEqual(testCase, result.applied_counts.extraction_runs, 1);
verifyEqual(testCase, result.applied_counts.extraction_run_inputs, 1);
verifyEqual(testCase, result.applied_counts.extraction_run_artifacts, 1);
verifyEqual(testCase, result.applied_counts.artifacts, 1);

verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 1);
verifyEqual(testCase, countOf(fixture.conn, "extraction_run_inputs"), 1);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);

% The event population is written by the same atomic apply, so an extraction run
% never exists without the calls it produced.
verifyEqual(testCase, countOf(fixture.conn, "detections"), 2);
verifyEqual(testCase, countOf(fixture.conn, "event_measurements"), 28);

% Extractor import must not recreate any part of the project graph.
verifyEqual(testCase, countOf(fixture.conn, "projects"), 2);
verifyEqual(testCase, countOf(fixture.conn, "source_files"), 2);
verifyEqual(testCase, countOf(fixture.conn, "recordings"), 2);

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

function testRecordingResolutionModesAndFailures(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

byPortable = plan(fixture, defaultRunSpec());
verifyEqual(testCase, byPortable.recording.recording_id, fixture.recording_a);
verifyEqual(testCase, byPortable.recording.resolution_mode, "portable_source");

byId = planWithRef(fixture, struct(recording_id=fixture.recording_a), defaultRunSpec());
verifyEqual(testCase, byId.recording.recording_id, fixture.recording_a);
verifyEqual(testCase, byId.recording.resolution_mode, "recording_id");
verifyEqual(testCase, byId.recording.project_id, byPortable.recording.project_id);

verifyError(testCase, ...
    @() planWithRef(fixture, struct(recording_id=99999), defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakRecordingNotFound");

% A portable path that exists, but under a different project, must not resolve.
verifyError(testCase, ...
    @() planWithRef(fixture, struct(project_key="proj-b", ...
    source_relative_path="audio/day1/REC_A.wav"), defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakRecordingNotFound");

verifyError(testCase, ...
    @() planWithRef(fixture, struct(project_key="proj-a"), defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakRecordingRefInvalid");

% Mixing the two modes is ambiguous rather than convenient.
verifyError(testCase, ...
    @() planWithRef(fixture, struct(recording_id=fixture.recording_a, ...
    project_key="proj-a", source_relative_path="audio/day1/REC_A.wav"), ...
    defaultRunSpec()), ...
    "vawlume:ingest:DeepSqueakRecordingRefInvalid");

clear cleanup
end

function testSeededExtractorAndOutputProfileAreResolvedNotCreated(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

extractorsBefore = countOf(fixture.conn, "extractors");
profilesBefore = countOf(fixture.conn, "config_profiles");
result = apply(fixture, defaultRunSpec());

% The extractor dictionary and the shipped output profile belong to the seed
% layer; an import resolves them and never inserts its own copy.
verifyEqual(testCase, countOf(fixture.conn, "extractors"), extractorsBefore);
verifyEqual(testCase, countOf(fixture.conn, "config_profiles"), profilesBefore);
verifyEqual(testCase, result.output_profile.action, "reuse");
verifyEqual(testCase, result.output_profile.profile_key, "vawlume.deepsqueak.output.v3_2");
verifyEqual(testCase, result.output_profile.version_label, "0.1.0");
verifyEqual(testCase, result.output_profile.profile_schema_version, "0.2-draft");
verifyMatches(testCase, result.output_profile.checksum_sha256, "^[0-9a-f]{64}$");

% The exact run version and the profile-registered feature scope are separate
% concepts and both stay answerable.
verifyEqual(testCase, result.extractor.extractor_name, "DeepSqueak");
verifyEqual(testCase, result.extractor.declared_version, "3.2.1");
verifyEqual(testCase, result.extractor.feature_scope_version_label, "3.2.x");
verifyFalse(testCase, result.extractor.version_matches_feature_scope);
verifyNotEqual(testCase, result.extractor.run_extractor_version_id, ...
    result.extractor.feature_extractor_version_id);
verifyTrue(testCase, any(contains(result.warnings, "feature scope")));

% Feature semantics remain reachable through the scope row.
featureCount = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM extractor_features WHERE extractor_version_id = " + ...
    string(result.extractor.feature_extractor_version_id));
verifyEqual(testCase, double(featureCount.n(1)), 14);

% Declaring the scope label itself collapses the two onto one row.
onScope = defaultRunSpec();
onScope.run_key = "ds-run-scope";
onScope.extractor_version = "3.2.x";
scopeResult = plan(fixture, onScope);
verifyTrue(testCase, scopeResult.extractor.version_matches_feature_scope);
verifyEqual(testCase, scopeResult.extractor.version_action, "reuse");

clear cleanup
end

function testExtractorVersionRequirementComesFromProfile(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The tracked profile declares extractor.version_required_at_ingest, so ingest
% refuses to guess even though Pass 2's reader tolerates an absent version.
noVersion = defaultRunSpec();
noVersion = rmfield(noVersion, "extractor_version");
verifyError(testCase, @() plan(fixture, noVersion), ...
    "vawlume:ingest:DeepSqueakVersionRequired");

% A version outside every declared scope would attribute this profile's field
% semantics to software it was not written for.
incompatible = defaultRunSpec();
incompatible.extractor_version = "2.9.0";
verifyError(testCase, @() plan(fixture, incompatible), ...
    "vawlume:ingest:DeepSqueakVersionIncompatible");

% Inside the compatible family is allowed, with the deviation reported.
family = defaultRunSpec();
family.extractor_version = "3.1.4";
familyResult = plan(fixture, family);
verifyFalse(testCase, familyResult.has_conflicts);
verifyTrue(testCase, any(contains(familyResult.warnings, "compatible family")));

verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 0);

clear cleanup
end

function testCompatibleRerunReusesEverything(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

first = apply(fixture, defaultRunSpec());
second = apply(fixture, defaultRunSpec());

verifyEqual(testCase, second.extraction_run.action, "reuse");
verifyEqual(testCase, second.extraction_run.extraction_run_id, ...
    first.extraction_run.extraction_run_id);
verifyEqual(testCase, second.applied_counts.extraction_runs, 0);
verifyEqual(testCase, second.applied_counts.artifacts, 0);
verifyEqual(testCase, second.applied_counts.extraction_run_artifacts, 0);
verifyEqual(testCase, second.applied_counts.reused_extraction_runs, 1);
verifyEqual(testCase, second.applied_counts.reused_artifacts, 1);

% A compatible rerun writes nothing at all. Unlike project intake, this importer
% records no per-attempt audit row, so no transaction is opened and the no-op
% must still report success rather than a commit failure.
verifyTrue(testCase, second.committed);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 1);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);
verifyEqual(testCase, countOf(fixture.conn, "extraction_run_inputs"), 1);

clear cleanup
end

function testRelocatedExportReusesArtifactAndRun(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

apply(fixture, defaultRunSpec());

% The same export content under a different absolute root keeps one portable
% identity, so relocation must not manufacture a second run or artifact.
relocatedRoot = fullfile(fixture.scratch, "relocated");
relocatedPath = fullfile(relocatedRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(relocatedPath);
copyfile(fixture.export_a, relocatedPath);

relocated = vawlume.ingest.deepsqueak(fixture.conn, relocatedPath, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=relocatedRoot, Apply=true);

verifyEqual(testCase, relocated.extraction_run.action, "reuse");
verifyEqual(testCase, string(relocated.artifacts.action(1)), "reuse");
verifyNotEqual(testCase, relocated.export.runtime_path, ...
    string(fixture.export_a));
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 1);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);

% An export outside every declared root has no durable identity, and an absolute
% runtime path is not an acceptable substitute.
orphanPath = fullfile(fixture.scratch, "orphan_Stats.xlsx");
copyfile(fixture.export_a, orphanPath);
verifyError(testCase, ...
    @() vawlume.ingest.deepsqueak(fixture.conn, orphanPath, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), defaultRunSpec(), ...
    ProfilePath=fixture.profile_path), ...
    "vawlume:ingest:DeepSqueakArtifactNotPortable");

clear cleanup
end

function testDifferentPortableExportIdentityConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

apply(fixture, defaultRunSpec());

% The same bytes at a different portable path are a distinct artifact. Reusing
% the run must not create that second artifact without linking it, nor silently
% substitute it for the export identity the run already records.
alternatePath = fullfile(fixture.artifact_root, "copies", "REC_A_Stats.xlsx");
makeParentFolder(alternatePath);
copyfile(fixture.export_a, alternatePath);

conflicted = vawlume.ingest.deepsqueak(fixture.conn, alternatePath, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root);
verifyEqual(testCase, conflicted.status, "conflict");
verifyTrue(testCase, any(contains(conflicted.conflicts, ...
    "event_measurement_export artifact identity differs")));

attempted = vawlume.ingest.deepsqueak(fixture.conn, alternatePath, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
verifyFalse(testCase, attempted.committed);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);
verifyEqual(testCase, countOf(fixture.conn, "extraction_run_artifacts"), 1);

clear cleanup
end

function testChangedContentUnderSameIdentityConflicts(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

apply(fixture, defaultRunSpec());

% Same run key, same portable artifact path, different content.
changedRoot = fullfile(fixture.scratch, "changed");
changedPath = fullfile(changedRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(changedPath);
writeExport(changedPath, exportCells(0.5));

conflicted = vawlume.ingest.deepsqueak(fixture.conn, changedPath, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=changedRoot);

verifyEqual(testCase, conflicted.status, "conflict");
verifyTrue(testCase, conflicted.has_conflicts);
verifyTrue(testCase, any(contains(conflicted.conflicts, "different checksum")));
verifyTrue(testCase, any(contains(conflicted.conflicts, "registered with checksum")));

% Requesting apply on a conflicting plan returns the conflict rather than
% throwing, exactly as project intake behaves, and writes nothing.
attempted = vawlume.ingest.deepsqueak(fixture.conn, changedPath, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=changedRoot, Apply=true);
verifyEqual(testCase, attempted.status, "conflict");
verifyFalse(testCase, attempted.committed);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 1);
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);

% Existing rows are never silently updated to match the new content.
storedChecksum = fetch(fixture.conn, ...
    "SELECT checksum_sha256 FROM artifacts WHERE path_or_uri = 'exports/REC_A_Stats.xlsx'");
verifyNotEqual(testCase, string(storedChecksum.checksum_sha256(1)), ...
    string(conflicted.artifacts.checksum_sha256(1)));

% The same run key pointed at a different recording is also a conflict.
otherRecording = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_a, ...
    portableRef("proj-a", "audio/day1/REC_B.wav"), defaultRunSpec(), ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root);
verifyEqual(testCase, otherRecording.status, "conflict");
verifyTrue(testCase, any(contains(otherRecording.conflicts, "different recording")));

clear cleanup
end

function testDistinctRunOverSameRecordingCoexists(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

first = apply(fixture, defaultRunSpec());

second = defaultRunSpec();
second.run_key = "ds-run-2";
second.run_label = "second detector pass";
secondResult = apply(fixture, second);

verifyEqual(testCase, secondResult.extraction_run.action, "create");
verifyNotEqual(testCase, secondResult.extraction_run.extraction_run_id, ...
    first.extraction_run.extraction_run_id);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 2);

% Both runs analysed the same recording and share the one export artifact.
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);
verifyEqual(testCase, countOf(fixture.conn, "extraction_run_inputs"), 2);
runs = fetch(fixture.conn, ...
    "SELECT er.run_key FROM extraction_runs er " + ...
    "JOIN extraction_run_inputs eri ON eri.extraction_run_id = er.extraction_run_id " + ...
    "WHERE eri.recording_id = " + string(fixture.recording_a) + " ORDER BY er.run_key");
verifyEqual(testCase, string(runs.run_key), ["ds-run-1"; "ds-run-2"]);

clear cleanup
end

function testSettingsProvenanceIsCapturedOrExplicitlyAbsent(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Absent settings stay absent. settings_profile_version_id IS NULL is the
% machine-readable statement, and no default configuration is substituted.
withoutSettings = apply(fixture, defaultRunSpec());
verifyEqual(testCase, withoutSettings.settings.status, "not_recoverable");
verifyTrue(testCase, isnan(withoutSettings.settings.profile_version_id));
stored = fetch(fixture.conn, ...
    "SELECT IFNULL(settings_profile_version_id, -1) AS settings_id FROM extraction_runs " + ...
    "WHERE run_key = 'ds-run-1'");
verifyEqual(testCase, double(stored.settings_id(1)), -1);

% A VAWLUME settings profile is registered against the project, not the built-in
% namespace, and is a different profile kind from the output mapping profile.
withProfile = defaultRunSpec();
withProfile.run_key = "ds-run-settings";
withProfile.settings = struct(profile_path=fixture.settings_profile_path);
profileResult = apply(fixture, withProfile);
verifyEqual(testCase, profileResult.settings.status, "captured_profile");
verifyEqual(testCase, profileResult.settings.profile_key, "lab.deepsqueak.settings.v1");
verifyEqual(testCase, profileResult.settings.version_label, "1.0.0");
verifyMatches(testCase, profileResult.settings.checksum_sha256, "^[0-9a-f]{64}$");

kinds = fetch(fixture.conn, ...
    "SELECT profile_kind, IFNULL(project_id, -1) AS project_id FROM config_profiles " + ...
    "WHERE profile_key = 'lab.deepsqueak.settings.v1'");
verifyEqual(testCase, string(kinds.profile_kind(1)), "extractor_settings");
verifyEqual(testCase, double(kinds.project_id(1)), profileResult.recording.project_id);

% The settings profile and the output mapping profile occupy distinct columns.
linked = fetch(fixture.conn, ...
    "SELECT settings_profile_version_id, output_mapping_profile_version_id " + ...
    "FROM extraction_runs WHERE run_key = 'ds-run-settings'");
verifyNotEqual(testCase, double(linked.settings_profile_version_id(1)), ...
    double(linked.output_mapping_profile_version_id(1)));

% An external native settings file is preserved as an artifact rather than
% presented as a validated VAWLUME profile.
withArtifact = defaultRunSpec();
withArtifact.run_key = "ds-run-settings-file";
withArtifact.settings = struct(artifact_path=fixture.settings_artifact_path);
artifactResult = apply(fixture, withArtifact);
verifyEqual(testCase, artifactResult.settings.status, "captured_artifact");
verifyTrue(testCase, isnan(artifactResult.settings.profile_version_id));
verifyTrue(testCase, any(artifactResult.artifacts.role == "extractor_settings"));

clear cleanup
end

function testModelProvenanceIsNeverFabricated(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% No model evidence means no model row, reported transparently. A detector is
% never inferred from the DeepSqueak version or from the export's score column.
withoutModel = apply(fixture, defaultRunSpec());
verifyEqual(testCase, withoutModel.model.status, "not_recoverable");
verifyFalse(testCase, any(withoutModel.artifacts.role == "detector_network"));
verifyEqual(testCase, countOf(fixture.conn, "artifacts"), 1);

withModel = defaultRunSpec();
withModel.run_key = "ds-run-model";
withModel.model = struct(artifact_path=fixture.model_path, ...
    model_label="rat_detector_v2");
withModel.native_artifact = struct(artifact_path=fixture.native_path);
modelResult = apply(fixture, withModel);

verifyEqual(testCase, modelResult.model.status, "captured");
verifyEqual(testCase, modelResult.model.model_label, "rat_detector_v2");
verifyEqual(testCase, modelResult.model.evidence_source, "caller_declared");

roles = sort(string(modelResult.artifacts.role));
verifyEqual(testCase, roles, sort(["event_measurement_export"; ...
    "native_detection_container"; "detector_network"]));

% The native detection container is registered, distinguished from the Excel
% export, and not parsed.
native = fetch(fixture.conn, ...
    "SELECT artifact_type, is_native FROM artifacts " + ...
    "WHERE path_or_uri = 'REC_A_deepsqueak.mat'");
verifyEqual(testCase, string(native.artifact_type(1)), "native_detection_container");
verifyEqual(testCase, double(native.is_native(1)), 1);

% The recording's raw audio keeps its Phase 3 source_files identity and is never
% re-registered as extractor output.
audioArtifacts = fetch(fixture.conn, ...
    "SELECT COUNT(*) AS n FROM artifacts WHERE path_or_uri LIKE '%REC_A.wav'");
verifyEqual(testCase, double(audioArtifacts.n(1)), 0);

clear cleanup
end

function testIdentityDefiningOptionalArtifactsCannotChangeOnRerun(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

full = defaultRunSpec();
full.run_key = "ds-run-complete-provenance";
full.settings = struct(artifact_path=fixture.settings_artifact_path);
full.model = struct(artifact_path=fixture.model_path, model_label="rat_detector_v2");
full.native_artifact = struct(artifact_path=fixture.native_path);

first = apply(fixture, full);
second = apply(fixture, full);
verifyTrue(testCase, second.committed);
verifyEqual(testCase, second.extraction_run.extraction_run_id, ...
    first.extraction_run.extraction_run_id);
verifyEqual(testCase, second.applied_counts.artifacts, 0);

withoutModel = rmfield(full, "model");
modelOmitted = plan(fixture, withoutModel);
verifyEqual(testCase, modelOmitted.status, "conflict");
verifyTrue(testCase, any(contains(modelOmitted.conflicts, ...
    "detector_network artifact provenance")));

withoutSettings = rmfield(full, "settings");
settingsOmitted = plan(fixture, withoutSettings);
verifyEqual(testCase, settingsOmitted.status, "conflict");
verifyTrue(testCase, any(contains(settingsOmitted.conflicts, ...
    "extractor_settings artifact provenance")));

withoutNative = rmfield(full, "native_artifact");
nativeOmitted = plan(fixture, withoutNative);
verifyEqual(testCase, nativeOmitted.status, "conflict");
verifyTrue(testCase, any(contains(nativeOmitted.conflicts, ...
    "native_detection_container artifact provenance")));

replacementPath = fullfile(fixture.artifact_root, "replacement_detector.mat");
writeText(replacementPath, "different synthetic detector network stand-in");
replacement = full;
replacement.model = struct(artifact_path=replacementPath, ...
    model_label="rat_detector_v3");
modelChanged = plan(fixture, replacement);
verifyEqual(testCase, modelChanged.status, "conflict");
verifyTrue(testCase, any(contains(modelChanged.conflicts, ...
    "detector_network artifact identity differs")));

% Adding model evidence later is also a provenance change, not an invitation to
% mutate an existing run in place.
withoutAnyModel = defaultRunSpec();
withoutAnyModel.run_key = "ds-run-no-model";
apply(fixture, withoutAnyModel);
withLateModel = withoutAnyModel;
withLateModel.model = struct(artifact_path=fixture.model_path);
added = plan(fixture, withLateModel);
verifyEqual(testCase, added.status, "conflict");
verifyTrue(testCase, any(contains(added.conflicts, ...
    "detector_network artifact provenance")));

collision = defaultRunSpec();
collision.run_key = "ds-run-artifact-collision";
collision.model = struct(artifact_path=fixture.native_path);
collision.native_artifact = struct(artifact_path=fixture.native_path);
collided = plan(fixture, collision);
verifyEqual(testCase, collided.status, "conflict");
verifyTrue(testCase, any(contains(collided.conflicts, ...
    "declared for more than one role")));

clear cleanup
end

function testInvalidProvenanceRollsBackCompletely(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

before = tableCounts(fixture.conn);

% Fail late, after the run and its artifacts would already have been written.
% extraction_run_artifacts.artifact_role is NOT NULL, so removing that column
% from the final insert aborts the last step of a transaction whose earlier
% steps succeeded.
failing = defaultRunSpec();
failing.run_key = "ds-run-rollback";
verifyError(testCase, ...
    @() applyWithInducedFailure(fixture, failing), ...
    "vawlume:ingest:InducedApplyFailure");

% Nothing from the aborted attempt survives: no run, no input, no artifact.
verifyEqual(testCase, tableCounts(fixture.conn), before);
verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

% The connection is usable and left in its original autocommit state.
verifyEqual(testCase, string(fixture.conn.AutoCommit), "on");
recovered = apply(fixture, defaultRunSpec());
verifyTrue(testCase, recovered.committed);
verifyEqual(testCase, countOf(fixture.conn, "extraction_runs"), 1);

clear cleanup
end

function testRelationalReadBacksAnswerProvenanceQuestions(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

full = defaultRunSpec();
full.run_key = "ds-run-full";
full.run_label = "Full provenance run";
full.settings = struct(profile_path=fixture.settings_profile_path);
full.model = struct(artifact_path=fixture.model_path, model_label="rat_detector_v2");
full.native_artifact = struct(artifact_path=fixture.native_path);
apply(fixture, full);

second = defaultRunSpec();
second.run_key = "ds-run-plain";
apply(fixture, second);

% Q1-Q3: run to recording, to extractor/version, to exact output mapping profile.
core = fetch(fixture.conn, ...
    "SELECT er.run_key, r.native_recording_id, e.extractor_name, " + ...
    "ev.version_label AS extractor_version, cp.profile_key, " + ...
    "cpv.version_label AS profile_version, cpv.checksum_sha256 " + ...
    "FROM extraction_runs er " + ...
    "JOIN extraction_run_inputs eri ON eri.extraction_run_id = er.extraction_run_id " + ...
    "JOIN recordings r ON r.recording_id = eri.recording_id " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id = er.output_mapping_profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "WHERE er.run_key = 'ds-run-full'");
verifyEqual(testCase, height(core), 1);
verifyEqual(testCase, string(core.native_recording_id(1)), "REC_A");
verifyEqual(testCase, string(core.extractor_name(1)), "DeepSqueak");
verifyEqual(testCase, string(core.extractor_version(1)), "3.2.1");
verifyEqual(testCase, string(core.profile_key(1)), "vawlume.deepsqueak.output.v3_2");
verifyEqual(testCase, string(core.profile_version(1)), "0.1.0");
verifyMatches(testCase, string(core.checksum_sha256(1)), "^[0-9a-f]{64}$");

% Q4 and Q6: export artifact with checksum, and model provenance.
artifacts = fetch(fixture.conn, ...
    "SELECT ra.artifact_role, a.artifact_type, a.path_or_uri, " + ...
    "IFNULL(a.checksum_sha256, '') AS checksum_sha256 " + ...
    "FROM extraction_runs er " + ...
    "JOIN extraction_run_artifacts ra ON ra.extraction_run_id = er.extraction_run_id " + ...
    "JOIN artifacts a ON a.artifact_id = ra.artifact_id " + ...
    "WHERE er.run_key = 'ds-run-full' ORDER BY ra.artifact_role");
verifyEqual(testCase, string(artifacts.artifact_role), ...
    ["detector_network"; "event_measurement_export"; "native_detection_container"]);
verifyTrue(testCase, all(strlength(string(artifacts.checksum_sha256)) == 64));

% Q5: settings provenance where supplied, explicitly absent where not.
settings = fetch(fixture.conn, ...
    "SELECT er.run_key, IFNULL(cp.profile_key, '<unavailable>') AS settings_profile " + ...
    "FROM extraction_runs er " + ...
    "LEFT JOIN config_profile_versions cpv ON cpv.profile_version_id = er.settings_profile_version_id " + ...
    "LEFT JOIN config_profiles cp ON cp.profile_id = cpv.profile_id " + ...
    "ORDER BY er.run_key");
verifyEqual(testCase, string(settings.run_key), ["ds-run-full"; "ds-run-plain"]);
verifyEqual(testCase, string(settings.settings_profile), ...
    ["lab.deepsqueak.settings.v1"; "<unavailable>"]);

% Q7: every DeepSqueak run over one recording.
byRecording = fetch(fixture.conn, ...
    "SELECT er.run_key FROM recordings r " + ...
    "JOIN extraction_run_inputs eri ON eri.recording_id = r.recording_id " + ...
    "JOIN extraction_runs er ON er.extraction_run_id = eri.extraction_run_id " + ...
    "WHERE r.recording_id = " + string(fixture.recording_a) + " ORDER BY er.run_key");
verifyEqual(testCase, string(byRecording.run_key), ["ds-run-full"; "ds-run-plain"]);

verifyEqual(testCase, height(fetch(fixture.conn, "PRAGMA foreign_key_check")), 0);

clear cleanup
end

% ---------------------------------------------------------------- helpers ---

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootForTest();
addpath(fullfile(repoRoot, "src"));

scratch = string(tempname);
mkdir(scratch);
dbFile = fullfile(scratch, "deepsqueak_provenance.sqlite");

% Applying the schema and registering built-in semantics costs several seconds,
% so it is done once and the resulting database is copied per test.
copyfile(seededTemplateDatabase(repoRoot), dbFile);
conn = sqlite(char(dbFile));

cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
seedProjectGraph(conn);

artifactRoot = fullfile(scratch, "deepsqueak");
exportPath = fullfile(artifactRoot, "exports", "REC_A_Stats.xlsx");
makeParentFolder(exportPath);
writeExport(exportPath, exportCells(0.9134));

fixture = struct();
fixture.conn = conn;
fixture.repo_root = repoRoot;
fixture.scratch = scratch;
fixture.artifact_root = artifactRoot;
fixture.export_a = exportPath;
fixture.recording_a = 1;
fixture.recording_b = 2;
fixture.profile_path = fullfile(repoRoot, "config", "01_mapping_profiles", ...
    "extractors", "deepsqueak", "deepsqueak_output_mapping_profile.json");

fixture.settings_profile_path = fullfile(artifactRoot, "lab_deepsqueak_settings.json");
writeText(fixture.settings_profile_path, jsonencode(struct( ...
    profile=struct(id="lab.deepsqueak.settings.v1", ...
    name="Laboratory DeepSqueak detection settings", ...
    kind="extractor_settings", profile_version="1.0.0"), ...
    detection=struct(score_threshold=0.5, frequency_range_khz=[15, 115]))));

fixture.settings_artifact_path = fullfile(artifactRoot, "native_settings.txt");
writeText(fixture.settings_artifact_path, "DeepSqueak native settings export");

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

function seedProjectGraph(conn)
% Stands in for a completed project intake. Extractor import consumes this graph
% and must never recreate any part of it.
execute(conn, "INSERT INTO projects(project_key, project_name) VALUES('proj-a','Project A')");
execute(conn, "INSERT INTO projects(project_key, project_name) VALUES('proj-b','Project B')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, relative_path, filename) " + ...
    "VALUES(1,'recording_audio','audio/day1/REC_A.wav','audio/day1/REC_A.wav','REC_A.wav')");
execute(conn, "INSERT INTO source_files(project_id, file_role, path_or_uri, relative_path, filename) " + ...
    "VALUES(1,'recording_audio','audio/day1/REC_B.wav','audio/day1/REC_B.wav','REC_B.wav')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, native_recording_id) VALUES(1,1,'REC_A')");
execute(conn, "INSERT INTO recordings(project_id, source_file_id, native_recording_id) VALUES(1,2,'REC_B')");
end

function spec = defaultRunSpec()
spec = struct(run_key="ds-run-1", extractor_version="3.2.1", ...
    run_label="DeepSqueak detection run 1");
end

function ref = portableRef(projectKey, relativePath)
ref = struct(project_key=projectKey, source_relative_path=relativePath);
end

function result = plan(fixture, runSpec)
result = planWithRef(fixture, portableRef("proj-a", "audio/day1/REC_A.wav"), runSpec);
end

function result = planWithRef(fixture, recordingRef, runSpec)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_a, ...
    recordingRef, runSpec, RepoRoot=fixture.repo_root, ...
    ArtifactRoot=fixture.artifact_root);
end

function result = apply(fixture, runSpec)
result = vawlume.ingest.deepsqueak(fixture.conn, fixture.export_a, ...
    portableRef("proj-a", "audio/day1/REC_A.wav"), runSpec, ...
    RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
end

function applyWithInducedFailure(fixture, runSpec)
% Drive the real apply path, then make its final statement fail. A trigger on
% extraction_run_artifacts raises after the run, its input, and its artifact have
% all been inserted inside the transaction.
execute(fixture.conn, ...
    "CREATE TRIGGER trg_induced_apply_failure " + ...
    "BEFORE INSERT ON extraction_run_artifacts FOR EACH ROW " + ...
    "BEGIN SELECT RAISE(ABORT, 'induced apply failure'); END");
restore = onCleanup(@() dropTrigger(fixture.conn));
try
    vawlume.ingest.deepsqueak(fixture.conn, fixture.export_a, ...
        portableRef("proj-a", "audio/day1/REC_A.wav"), runSpec, ...
        RepoRoot=fixture.repo_root, ArtifactRoot=fixture.artifact_root, Apply=true);
catch exception
    clear restore
    error("vawlume:ingest:InducedApplyFailure", ...
        "Induced apply failure surfaced as: %s", exception.message);
end
clear restore
error("vawlume:ingest:InducedApplyFailure", ...
    "The induced failure did not abort the apply.");
end

function dropTrigger(conn)
try
    execute(conn, "DROP TRIGGER IF EXISTS trg_induced_apply_failure");
catch
end
end

function cells = exportCells(score)
headers = {'File', 'ID', 'Label', 'Accepted', 'Score', 'Begin Time (s)', ...
    'End Time (s)', 'Call Length (s)', 'Principle Frequency (kHz)', ...
    'Low Freq (kHz)', 'High Freq (kHz)', 'Delta Freq (kHz)', ...
    'Frequency Standard Deviation (kHz)', 'Slope (kHz/s)', 'Sinuosity', ...
    'Mean Power (dB/Hz)', 'Tonality', 'Peak Freq (kHz)'};
detectionFile = 'C:\deepsqueak\detections\REC_A_deepsqueak.mat';
cells = [
    headers
    {detectionFile, 1, '22kHz-Call', 1, score, 10.000, 10.050, 0.050, ...
        62.4, 45.1, 80.2, 35.1, 3.2, -120.5, 1.12, -71.4, 0.78, 63.0}
    {detectionFile, 2, 'USV', 1, 0.8021, 20.000, 20.040, 0.040, ...
        61.0, 50.0, 72.0, 22.0, 2.1, 15.0, 1.05, -70.1, 0.72, 61.5}
];
end

function writeExport(path, cells)
if isfile(path)
    delete(path);
end
writecell(cells, path);
end

function counts = tableCounts(conn)
tables = ["projects", "source_files", "recordings", "config_profiles", ...
    "config_profile_versions", "extractors", "extractor_versions", ...
    "artifacts", "extraction_runs", "extraction_run_inputs", ...
    "extraction_run_artifacts", "detections", "event_measurements"];
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
