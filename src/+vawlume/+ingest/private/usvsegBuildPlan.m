function plan = usvsegBuildPlan(conn, export, recordingRef, runSpec, roots)
%USVSEGBUILDPLAN Build a deterministic read-only USVSEG import plan.
plan=struct(context=usvsegValidateRunContext(recordingRef,runSpec),export=export, ...
    warnings=strings(0,1),conflicts=strings(0,1));
assertReady(export); plan=appendWarnings(plan,export); plan=assertVersion(plan,export);
plan.recording=extractorResolveRecording(conn,plan.context.recording_ref,"Usvseg");
plan.output_profile=extractorResolveOutputProfile(conn,export.ir.profile,"Usvseg");
plan.extractor=extractorResolveIdentity(conn,export.ir.profile,plan.context.run.extractor_version,"Usvseg");
plan.warnings=[plan.warnings;plan.extractor.warnings];
none=struct(mode="none",status="not_applicable",profile_path="",profile_key="", ...
    version_label="",description="",required_format="",required_kind="");
plan.settings_profile=extractorResolveSettingsProfile(conn,plan.recording.project_id,none,"Usvseg");
plan.artifacts=usvsegResolveArtifacts(conn,plan.recording.project_id,export,plan.context,roots);
plan.run=extractorResolveRun(conn,plan,["event_measurement_export","extractor_settings"]);
plan.run_artifacts=extractorRunArtifactPlan(conn,plan);
plan=appendEvents(conn,plan,export);
if plan.context.settings.mode=="artifact", plan.settings_status="captured_weak"; else, plan.settings_status="unavailable"; end
if plan.settings_status=="unavailable"
    plan.warnings(end+1,1)="USVSEG_SETTINGS_UNAVAILABLE: import permitted because USVSEG does not emit run-scoped settings evidence.";
else
    plan.warnings(end+1,1)="USVSEG_SETTINGS_WEAK_EVIDENCE: usvseg_prm.mat is application-scoped and not verified as this run's configuration.";
end
plan=collectConflicts(plan); plan.has_conflicts=~isempty(plan.conflicts);
end

function plan=appendEvents(conn,plan,export)
plan.feature_dictionary=extractorFeatureDictionary(conn,plan.extractor.feature_version_id,plan.output_profile.profile_version_id);
plan.routed=extractorRouteEventValues(export.ir,plan.feature_dictionary,string(export.artifact.artifact_key));
if ~isempty(plan.routed.unregistered_fields)
    error("vawlume:ingest:UsvsegFeatureUnregistered", ...
        "Mapped fields lack registered features or routing roles: %s.",strjoin(plan.routed.unregistered_fields,", "));
end
plan.routed=extractorAttachUnmappedSourceValues(plan.routed,export.ir,export.table);
plan.validation=extractorValidateEvents(plan.routed,export.profile_document,"syllable");
plan.warnings=[plan.warnings;plan.validation.warnings];
if ~plan.validation.is_valid
    error("vawlume:ingest:UsvsegEventValidationFailed", ...
        "The USVSEG export failed event validation:%s",newline+strjoin(plan.validation.errors,newline));
end
plan.events=usvsegResolveEvents(conn,plan,plan.routed);
plan.conflicts=[plan.conflicts;plan.events.conflicts];
end

function assertReady(export)
if export.ir.valid_for_ingest&&export.adapter_error_count==0, return, end
codes=unique(string(export.ir.issues.code(export.ir.issues.affects_validity)));
error("vawlume:ingest:UsvsegIRNotValid","The USVSEG export is not ingestible (%s).",strjoin(codes,", "));
end
function plan=appendWarnings(plan,export)
if isempty(export.issues), return, end
rows=export.issues(export.issues.severity=="warning",:);
for i=1:height(rows), plan.warnings(end+1,1)=string(rows.code(i))+": "+string(rows.message(i)); end
end
function plan=assertVersion(plan,export)
a=export.extractor_version; declared=plan.context.run.extractor_version;
if a.declared_version~=declared, error("vawlume:ingest:UsvsegVersionInconsistent","Adapter and runSpec versions differ."); end
switch a.status
    case "missing_required", error("vawlume:ingest:UsvsegVersionRequired","runSpec.extractor_version is required for USVSEG database ingest.");
    case "incompatible", error("vawlume:ingest:UsvsegVersionIncompatible","Declared USVSEG version '%s' is outside profile scope '%s'.",declared,a.preferred_scope);
    case "compatible_family", plan.warnings(end+1,1)=a.message;
end
end
function plan=collectConflicts(plan)
messages=[string(plan.output_profile.conflict_message);string(plan.extractor.conflict_message); ...
    string(plan.settings_profile.conflict_message);string(plan.run.conflict_message);string(plan.artifacts.conflict_message)];
plan.conflicts=[plan.conflicts;messages(strlength(messages)>0)];
end
