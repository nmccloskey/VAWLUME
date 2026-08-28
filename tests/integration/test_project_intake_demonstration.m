function tests = test_project_intake_demonstration
tests = functiontests({@testAllProfilesRunThroughDemonstration});
end

function testAllProfilesRunThroughDemonstration(testCase)
repoRoot = repoRootForTest();
examplePath = fullfile(repoRoot, "examples");
addpath(examplePath);
cleanupPath = onCleanup(@() rmpath(examplePath));

demonstration = project_intake_demo(Print=false, RepoRoot=repoRoot);

verifyTrue(testCase, demonstration.profile_bundle.validation_valid);
verifyEqual(testCase, demonstration.profile_bundle.validation_error_count, 0);
verifyEqual(testCase, demonstration.profile_bundle.profile_count, 3);
verifyEqual(testCase, height(demonstration.profile_summary), 3);
verifyTrue(testCase, all(demonstration.profile_summary.profile_valid));
verifyEqual(testCase, demonstration.profile_summary.preview_verdict, ...
    repmat("READY FOR INGEST", 3, 1));
verifyEqual(testCase, demonstration.profile_summary.intake_status, ...
    ["completed"; "completed_with_warnings"; "completed"]);
verifyEqual(testCase, demonstration.profile_summary.source_count, [1; 1; 1]);
verifyEqual(testCase, demonstration.profile_summary.recording_count, [1; 1; 1]);
verifyEqual(testCase, demonstration.profile_summary.participant_count, [1; 1; 2]);
verifyEqual(testCase, demonstration.profile_summary.context_count, [1; 1; 1]);

dyad = demonstration.recording_context( ...
    demonstration.recording_context.project_key == "demo_social_dyad", :);
participants = dyad(string(dyad.link_type) == "participant", :);
verifyEqual(testCase, string(participants.entity_native_id), ["F031"; "M012"]);
verifyEqual(testCase, string(participants.role_label), ...
    ["female_partner"; "male_partner"]);
verifyEqual(testCase, numel(unique(double(dyad.recording_id))), 1);

verifyEqual(testCase, height(demonstration.intake_provenance), 3);
verifyEqual(testCase, string( ...
    demonstration.intake_provenance.mapping_profile_key), ...
    demonstration.profile_summary.profile_key);
verifyTrue(testCase, all(strlength(string( ...
    demonstration.intake_provenance.mapping_profile_checksum)) == 64));
verifyEqual(testCase, height(demonstration.acquisition_profiles), 2);
verifyEqual(testCase, string( ...
    demonstration.acquisition_profiles.profile_kind), ...
    ["experimental_setup"; "recording_device"]);
verifyEqual(testCase, unique(string( ...
    demonstration.acquisition_profiles.inheritance_source)), ...
    "project_default");

verifyTrue(testCase, demonstration.idempotency.semantic_graph_unchanged);
verifyTrue(testCase, demonstration.idempotency.source_ids_unchanged);
verifyTrue(testCase, demonstration.idempotency.recording_ids_unchanged);
verifyEqual(testCase, demonstration.idempotency.ingestion_run_increment, 1);
verifyNotEqual(testCase, ...
    demonstration.idempotency.first_ingestion_run_id, ...
    demonstration.idempotency.second_ingestion_run_id);

verifyTrue(testCase, demonstration.relocation.runtime_roots_differ);
verifyTrue(testCase, demonstration.relocation.runtime_paths_differ);
verifyTrue(testCase, demonstration.relocation.portable_ir_equal);
verifyTrue(testCase, demonstration.relocation.preview_equal);
verifyTrue(testCase, demonstration.relocation.semantic_graph_unchanged);
verifyTrue(testCase, demonstration.relocation.source_ids_unchanged);
verifyTrue(testCase, demonstration.relocation.recording_ids_unchanged);
verifyEqual(testCase, demonstration.relocation.ingestion_run_increment, 1);

verifyEqual(testCase, inventoryCount(demonstration, "projects"), 3);
verifyEqual(testCase, inventoryCount(demonstration, "source_files"), 3);
verifyEqual(testCase, inventoryCount(demonstration, "recordings"), 3);
verifyEqual(testCase, inventoryCount(demonstration, ...
    "recording_entity_links"), 7);
verifyEqual(testCase, inventoryCount(demonstration, "ingestion_runs"), 5);
verifyEqual(testCase, inventoryCount(demonstration, "ingestion_files"), 5);
verifyEqual(testCase, inventoryCount(demonstration, "extraction_runs"), 0);
verifyEqual(testCase, inventoryCount(demonstration, "detections"), 0);
verifyEmpty(testCase, demonstration.foreign_key_violations);
verifyTrue(testCase, demonstration.temporary_artifacts_removed);
verifyFalse(testCase, isfolder(demonstration.workspace_root));
verifyFalse(testCase, isfile(demonstration.database_path));

clear cleanupPath
end

function value = inventoryCount(demonstration, tableName)
match = demonstration.database_inventory.table_name == tableName;
value = demonstration.database_inventory.row_count(match);
end

function repoRoot = repoRootForTest()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
