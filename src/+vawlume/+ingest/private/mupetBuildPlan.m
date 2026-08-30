function plan = mupetBuildPlan(conn, export, recordingRef, runSpec, roots)
%MUPETBUILDPLAN Build the read-only MUPET provenance graph for Pass 3.

plan = struct(context=mupetValidateRunContext(recordingRef, runSpec), ...
    export=export, warnings=strings(0,1), conflicts=strings(0,1));
assertReady(export, plan.context);
plan = appendWarnings(plan, export);
plan = assertVersion(plan, export);
plan.recording = extractorResolveRecording(conn, plan.context.recording_ref, "Mupet");
plan.output_profile = extractorResolveOutputProfile(conn, export.ir.profile, "Mupet");
plan.extractor = extractorResolveIdentity(conn, export.ir.profile, ...
    plan.context.run.extractor_version, "Mupet");
plan.warnings = [plan.warnings; plan.extractor.warnings];

% Native config.csv is represented by its raw role-bearing artifact. Its
% structured faithful capture lives in artifact metadata, because the current
% schema has no truthful source-artifact lineage edge for a synthesized
% config_profile_versions row. No profile row is fabricated.
settingsDeclaration = struct(mode="none", status="not_applicable", ...
    profile_path="", profile_key="", version_label="", description="", ...
    required_format="", required_kind="");
if plan.context.settings.mode == "profile"
    settingsDeclaration.mode = "profile";
    settingsDeclaration.status = "captured";
    settingsDeclaration.profile_path = plan.context.settings.profile_path;
    settingsDeclaration.profile_key = plan.context.settings.profile_key;
    settingsDeclaration.version_label = plan.context.settings.version_label;
    settingsDeclaration.description = plan.context.settings.description;
    settingsDeclaration.required_format = "json";
    settingsDeclaration.required_kind = "extractor_settings";
end
plan.settings_profile = extractorResolveSettingsProfile(conn, ...
    plan.recording.project_id, settingsDeclaration, "Mupet");
plan.artifacts = mupetResolveArtifacts(conn, plan.recording.project_id, ...
    export, plan.context, roots);
roles = ["event_measurement_export", "extractor_settings", "native_processed_recording"];
plan.run = extractorResolveRun(conn, plan, roles);
plan.run_artifacts = extractorRunArtifactPlan(conn, plan);
plan = appendEventPlan(conn, plan, export);
plan.extractor_objects = table(strings(0,1), strings(0,1), strings(0,1), ...
    VariableNames=["native_level", "native_id", "action"]);
plan.settings_status = settingsStatus(plan);
plan.provenance_complete = plan.settings_status == "captured";
if ~plan.provenance_complete
    plan.warnings(end+1,1) = "MUPET_SETTINGS_REQUIRED_FOR_APPLY: Supply native config.csv or a VAWLUME settings JSON before apply.";
end
plan = collectConflicts(plan);
plan.has_conflicts = ~isempty(plan.conflicts);
plan.ready_for_event_apply = plan.provenance_complete && ~plan.has_conflicts;
end

function plan = appendEventPlan(conn, plan, export)
%APPENDEVENTPLAN Route, validate, and classify the MUPET syllable population.
%
% The dictionary is read against the profile's registered feature scope rather
% than the run's exact extractor version, because seed registration attached
% extractor_features to the scope row. Routing and validation are the shared
% extractor core: nothing here restates a MUPET field name or unit.

plan.feature_dictionary = extractorFeatureDictionary(conn, ...
    plan.extractor.feature_version_id, plan.output_profile.profile_version_id);
plan.routed = extractorRouteEventValues(export.ir, plan.feature_dictionary, ...
    string(export.artifact.artifact_key));

if ~isempty(plan.routed.unregistered_fields)
    % A mapped column with no registered feature and no routing role means the
    % profile and the seeded vocabulary disagree. Manufacturing a dictionary row
    % from CSV text would paper over that, so it is refused.
    error("vawlume:ingest:MupetFeatureUnregistered", ...
        ['These mapped source fields have no registered extractor feature and ' ...
        'no routing role: %s. Re-run vawlume.db.registerBuiltinSemantics for ' ...
        'the current tracked profile.'], ...
        strjoin(plan.routed.unregistered_fields, ", "));
end

plan.validation = extractorValidateEvents(plan.routed, export.profile_document, "syllable");
plan.warnings = [plan.warnings; plan.validation.warnings];
if ~plan.validation.is_valid
    error("vawlume:ingest:MupetEventValidationFailed", ...
        ['The MUPET export failed profile-declared event validation, so no ' ...
        'rows were planned:%s'], ...
        newline + strjoin(plan.validation.errors, newline));
end

plan.events = mupetResolveEvents(conn, plan, plan.routed);
plan.conflicts = [plan.conflicts; plan.events.conflicts];
end

function assertReady(export, context)
if ~export.ir.valid_for_ingest
    codes = unique(string(export.ir.issues.code(export.ir.issues.affects_validity)));
    error("vawlume:ingest:MupetIRNotValid", ...
        "The MUPET export did not produce ingestible IR (%s).", strjoin(codes, ", "));
end
if context.settings.mode == "config_csv" && ~export.settings.complete
    codes = string(export.settings.issues.code(export.settings.issues.severity == "error"));
    error("vawlume:ingest:MupetSettingsInvalid", ...
        "The supplied MUPET config.csv is incomplete or ambiguous (%s).", strjoin(codes, ", "));
end
if export.adapter_error_count > 0
    error("vawlume:ingest:MupetIRNotValid", ...
        "The MUPET adapter reported %d validity-affecting errors.", export.adapter_error_count);
end
end

function plan = appendWarnings(plan, export)
if isempty(export.issues) || height(export.issues) == 0, return, end
rows = export.issues(export.issues.severity == "warning",:);
for index = 1:height(rows)
    code = string(rows.code(index));
    if code == "MUPET_SETTINGS_NOT_SUPPLIED" && plan.context.settings.mode ~= "none"
        continue
    end
    plan.warnings(end+1,1) = code + ": " + string(rows.message(index));
end
end

function plan = assertVersion(plan, export)
assessment = export.extractor_version;
declared = plan.context.run.extractor_version;
if assessment.declared_version ~= declared
    error("vawlume:ingest:MupetVersionInconsistent", ...
        "The adapter version '%s' differs from runSpec version '%s'.", ...
        assessment.declared_version, declared);
end
switch assessment.status
    case "missing_required"
        error("vawlume:ingest:MupetVersionRequired", ...
            "runSpec.extractor_version is required for MUPET database ingest.");
    case "incompatible"
        error("vawlume:ingest:MupetVersionIncompatible", ...
            "Declared MUPET version '%s' is outside profile scope '%s'.", ...
            declared, assessment.preferred_scope);
    case "compatible_family"
        plan.warnings(end+1,1) = assessment.message;
end
end

function value = settingsStatus(plan)
switch plan.context.settings.mode
    case "config_csv"
        if plan.export.settings.complete, value = "captured"; else, value = "incomplete"; end
    case "profile"
        value = "captured";
    otherwise
        value = "not_supplied";
end
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
if strlength(message) > 0, plan.conflicts(end+1,1) = message; end
end
