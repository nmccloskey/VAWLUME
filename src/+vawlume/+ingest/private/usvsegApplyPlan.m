function [plan,counts] = usvsegApplyPlan(conn,plan)
%USVSEGAPPLYPLAN Atomically apply provenance and the complete event population.
if plan.has_conflicts, error("vawlume:ingest:UsvsegPlanConflict","A conflicting USVSEG plan cannot be applied."); end
old=string(conn.AutoCommit);
if old~="on", error("vawlume:ingest:TransactionState","USVSEG import requires AutoCommit enabled."); end
counts=emptyCounts(); conn.AutoCommit="off";
try
    [plan,counts]=extractorApplyProvenance(conn,plan,counts, ...
        ExtractorVersionNote="Exact extractor version declared for a USVSEG import.", ...
        RunNotes=runNotes(plan));
    scope=struct(extraction_run_id=plan.run.existing_extraction_run_id, ...
        recording_id=plan.recording.recording_id,source_artifact_id=exportArtifactId(plan), ...
        mapping_profile_version_id=plan.output_profile.profile_version_id, ...
        event_subtype="vocalization_detection",timing_basis="profile_selected_event_geometry");
    [plan.events.detections,counts]=extractorApplyEvents(conn,scope,plan.events.detections,counts);
    if inserted(counts)>0, commit(conn); end
catch exception
    try rollback(conn); catch, end
    conn.AutoCommit=old; rethrow(exception)
end
conn.AutoCommit=old;
end
function value=runNotes(plan)
statement="settings="+plan.settings_status+"; settings_evidence_strength=weak_not_run_scoped";
if plan.settings_status=="unavailable", statement="settings=unavailable; settings_evidence_strength=none"; end
if strlength(plan.run.notes)>0, value=plan.run.notes+" ["+statement+"]"; else, value=statement; end
end
function id=exportArtifactId(plan), row=plan.artifacts(plan.artifacts.role=="event_measurement_export",:); id=double(row.existing_artifact_id(1)); if isnan(id), error("vawlume:ingest:UsvsegArtifactUnresolved","Event artifact unresolved."); end, end
function n=inserted(c), n=c.config_profiles+c.config_profile_versions+c.extractor_versions+c.artifacts+c.extraction_runs+c.extraction_run_inputs+c.extraction_run_artifacts+c.detections+c.event_measurements+c.unmapped_source_values; end
function c=emptyCounts()
c=struct(config_profiles=0,config_profile_versions=0,extractor_versions=0,artifacts=0, ...
    extraction_runs=0,extraction_run_inputs=0,extraction_run_artifacts=0,detections=0, ...
    event_measurements=0,unmapped_source_values=0,reused_config_profiles=0, ...
    reused_config_profile_versions=0,reused_extractor_versions=0,reused_artifacts=0, ...
    reused_extraction_runs=0,reused_extraction_run_inputs=0,reused_extraction_run_artifacts=0, ...
    reused_detections=0,reused_event_measurements=0,reused_unmapped_source_values=0);
end
