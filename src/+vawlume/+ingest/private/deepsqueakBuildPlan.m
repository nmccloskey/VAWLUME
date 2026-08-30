function plan = deepsqueakBuildPlan(conn, export, recordingRef, runSpec, roots)
%DEEPSQUEAKBUILDPLAN Build the deterministic DeepSqueak import plan.
%
% Planning is read-only. Every resolution is classified as create, reuse, or
% conflict before any mutation is contemplated, so a caller can inspect exactly
% what an apply would do without running it.

arguments
    conn
    export (1,1) struct
    recordingRef (1,1) struct
    runSpec (1,1) struct
    roots (1,:) string
end

plan = struct();
plan.context = deepsqueakValidateRunContext(recordingRef, runSpec);
plan.export = export;
plan.warnings = strings(0, 1);
plan.conflicts = strings(0, 1);

assertReadyForIngest(export);
plan = appendAdapterWarnings(plan, export);
plan = assertExtractorVersionAgreement(plan, export);

plan.recording = deepsqueakResolveRecording(conn, plan.context.recording_ref);
plan.output_profile = deepsqueakResolveOutputProfile(conn, export.ir.profile);
plan.extractor = deepsqueakResolveExtractor(conn, export.ir.profile, ...
    plan.context.run.extractor_version);
plan.warnings = [plan.warnings; plan.extractor.warnings];

plan.settings_profile = deepsqueakResolveSettingsProfile(conn, ...
    plan.recording.project_id, plan.context.settings);
plan.artifacts = deepsqueakResolveArtifacts(conn, plan.recording.project_id, ...
    export, plan.context, roots);
plan.run = deepsqueakResolveRun(conn, plan);
plan.run_artifacts = extractorRunArtifactPlan(conn, plan);

plan = appendEventPlan(conn, plan, export);

plan.settings_status = settingsStatus(plan);
plan.model_status = modelStatus(plan);
plan = collectConflicts(plan);
plan.has_conflicts = ~isempty(plan.conflicts);
end

function assertReadyForIngest(export)
if export.ir.valid_for_ingest && export.adapter_error_count == 0
    return
end
% A source-mapping error, malformed artifact, or adapter failure must prevent
% target-table writes entirely rather than importing part of a call population.
codes = unique(string(export.ir.issues.code( ...
    export.ir.issues.affects_validity)));
detail = "adapter errors: " + string(export.adapter_error_count);
if ~isempty(codes)
    detail = detail + "; IR errors: " + strjoin(codes, ", ");
end
error("vawlume:ingest:DeepSqueakIRNotValid", ...
    ['The DeepSqueak export did not produce ingestible IR, so no import plan ' ...
    'was built (%s). Inspect vawlume.source_mapping.preview for details.'], detail);
end

function plan = appendAdapterWarnings(plan, export)
if isempty(export.issues) || height(export.issues) == 0
    return
end
warningRows = export.issues(export.issues.severity == "warning", :);
for index = 1:height(warningRows)
    plan.warnings(end + 1, 1) = string(warningRows.code(index)) + ": " + ...
        string(warningRows.message(index));
end
end

function plan = assertExtractorVersionAgreement(plan, export)
% Pass 2 permits reading a workbook without version evidence so an export can be
% inspected. Database ingest is stricter: the tracked profile declares
% extractor.version_required_at_ingest, and an incompatible version means the
% profile's field semantics were not written for this software.
assessment = export.extractor_version;
declared = plan.context.run.extractor_version;

if assessment.declared_version ~= declared
    % The adapter was given different version evidence than the run declares.
    error("vawlume:ingest:DeepSqueakVersionInconsistent", ...
        ['The export was read with extractor version ''%s'' but runSpec ' ...
        'declares ''%s''. Read the export with the same version it is imported under.'], ...
        assessment.declared_version, declared);
end

switch assessment.status
    case "missing_required"
        error("vawlume:ingest:DeepSqueakVersionRequired", ...
            ['The output mapping profile declares ' ...
            'extractor.version_required_at_ingest, so runSpec.extractor_version ' ...
            'must state the DeepSqueak version that produced this export.']);
    case "incompatible"
        error("vawlume:ingest:DeepSqueakVersionIncompatible", ...
            ['Declared extractor version ''%s'' is outside every scope the ' ...
            'output mapping profile declares (preferred %s, compatible family %s). ' ...
            'Importing would attribute this profile''s field semantics to software ' ...
            'it was not written for.'], ...
            declared, assessment.preferred_scope, assessment.compatible_family);
    case "compatible_family"
        plan.warnings(end + 1, 1) = assessment.message;
end
end

function plan = appendEventPlan(conn, plan, export)
%APPENDEVENTPLAN Route, validate, and classify the event population.
%
% The dictionary is read against the profile's registered feature scope rather
% than the run's exact extractor version, because seed registration attached
% extractor_features to the scope row.

plan.feature_dictionary = extractorFeatureDictionary(conn, ...
    plan.extractor.feature_version_id, plan.output_profile.profile_version_id);
plan.routed = extractorRouteEventValues(export.ir, plan.feature_dictionary, ...
    string(export.artifact.artifact_key));

if ~isempty(plan.routed.unregistered_fields)
    % A mapped column with no registered feature and no routing role means the
    % profile and the seeded vocabulary disagree. Manufacturing a dictionary row
    % from workbook text would paper over that, so it is refused.
    error("vawlume:ingest:DeepSqueakFeatureUnregistered", ...
        ['These mapped source fields have no registered extractor feature and ' ...
        'no routing role: %s. Re-run vawlume.db.registerBuiltinSemantics for ' ...
        'the current tracked profile.'], ...
        strjoin(plan.routed.unregistered_fields, ", "));
end

plan.validation = extractorValidateEvents(plan.routed, export.profile_document, "call");
plan.warnings = [plan.warnings; plan.validation.warnings];
if ~plan.validation.is_valid
    error("vawlume:ingest:DeepSqueakEventValidationFailed", ...
        ['The DeepSqueak export failed profile-declared event validation, so ' ...
        'no rows were planned:%s'], ...
        newline + strjoin(plan.validation.errors, newline));
end

plan.events = deepsqueakResolveEvents(conn, plan, plan.routed);
plan.conflicts = [plan.conflicts; plan.events.conflicts];
end

function status = settingsStatus(plan)
switch plan.context.settings.mode
    case "profile"
        status = "captured_profile";
    case "artifact"
        status = "captured_artifact";
    otherwise
        % DeepSqueak settings are always conceptually applicable, so an absent
        % settings_profile_version_id is unambiguous evidence that they were not
        % recoverable. No default configuration is substituted.
        status = "not_recoverable";
end
end

function status = modelStatus(plan)
if plan.context.model.mode == "artifact"
    status = "captured";
    return
end
% A detector model is never inferred from the DeepSqueak version, from the
% machine's default network, or from the export's score column.
status = "not_recoverable";
end

function plan = collectConflicts(plan)
plan = appendConflict(plan, plan.output_profile.conflict_message);
plan = appendConflict(plan, plan.extractor.conflict_message);
plan = appendConflict(plan, plan.settings_profile.conflict_message);
plan = appendConflict(plan, plan.run.conflict_message);
for index = 1:height(plan.artifacts)
    plan = appendConflict(plan, string(plan.artifacts.conflict_message(index)));
end
end

function plan = appendConflict(plan, message)
if strlength(message) > 0
    plan.conflicts(end + 1, 1) = message;
end
end
