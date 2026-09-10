function events = usvsegResolveEvents(conn, plan, routed)
%USVSEGRESOLVEEVENTS Classify syllables and refuse unsupported annotations.
assertNoAnnotations(routed);
scope=struct(extraction_run_id=plan.run.existing_extraction_run_id, ...
    recording_id=plan.recording.recording_id,source_artifact_id=exportArtifactId(plan), ...
    mapping_profile_version_id=plan.output_profile.profile_version_id);
[detections,conflicts]=extractorClassifyDetections(conn,scope,routed,"syllable");
for i=1:numel(detections), detections{i}.unmapped_values=routed.rows{i}.unmapped_values; end
[detections,unmappedConflicts]=extractorClassifyUnmappedSourceValues(conn,scope,detections,"syllable");
events=struct(detections={detections},conflicts=[conflicts;unmappedConflicts], ...
    curation=struct(present=false,planned_rows=0,reason="USVSEG exports no curation_state role"), ...
    classification=struct(present=false,planned_rows=0,reason="USVSEG exports no class-label role"));
events.counts=summarize(detections);
end

function assertNoAnnotations(routed)
review=strings(0,1); labels=strings(0,1);
for i=1:numel(routed.rows)
    if routed.rows{i}.review_present, review(end+1,1)=routed.rows{i}.native_event_id; end %#ok<AGROW>
    if routed.rows{i}.label_present, labels(end+1,1)=routed.rows{i}.native_event_id; end %#ok<AGROW>
end
if ~isempty(review)||~isempty(labels)
    error("vawlume:ingest:UsvsegUnsupportedEventEvidence", ...
        "The profile routed review or class evidence that the USVSEG importer cannot silently discard.");
end
end
function counts=summarize(detections)
counts=struct(detections_create=0,detections_reuse=0,detections_conflict=0, ...
    measurements_create=0,measurements_reuse=0,measurements_conflict=0, ...
    unmapped_values_create=0,unmapped_values_reuse=0,unmapped_values_conflict=0, ...
    curation_rows_expected=0,classification_rows_expected=0);
for i=1:numel(detections)
    d=detections{i}; counts=bump(counts,"detections_"+d.action);
    for j=1:height(d.measurements), counts=bump(counts,"measurements_"+string(d.measurements.action(j))); end
    for j=1:height(d.unmapped_values), counts=bump(counts,"unmapped_values_"+string(d.unmapped_values.action(j))); end
end
end
function counts=bump(counts,name), name=char(name); if isfield(counts,name), counts.(name)=counts.(name)+1; end, end
function id=exportArtifactId(plan), row=plan.artifacts(plan.artifacts.role=="event_measurement_export",:); id=double(row.existing_artifact_id(1)); end
