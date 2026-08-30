function events = mupetResolveEvents(conn, plan, routed)
%MUPETRESOLVEEVENTS Classify the MUPET syllable population against existing rows.
%
% MUPET's per-syllable CSV exports events and measurements and nothing else. It
% carries no row-level review state and no class label, so this resolver adds no
% curation or classification layer on top of the shared detection core. That
% absence is the point: surviving MUPET's programmatic duration, energy, and
% amplitude filtering is not a reviewed state, and the filter thresholds are
% recorded once as run-level settings provenance rather than restated as a fake
% per-syllable accept flag.
%
% The absence is verified rather than assumed. If a future MUPET profile revision
% declares a curation or label role, the routed evidence will carry it and this
% function refuses the import instead of silently discarding it.

arguments
    conn
    plan (1,1) struct
    routed (1,1) struct
end

assertNoUnsupportedAnnotationEvidence(routed);

scope = struct( ...
    extraction_run_id=plan.run.existing_extraction_run_id, ...
    recording_id=plan.recording.recording_id, ...
    source_artifact_id=exportArtifactId(plan));
[detections, conflicts] = extractorClassifyDetections(conn, scope, routed, "syllable");

events = struct();
events.detections = detections;
events.conflicts = conflicts;
events.curation = struct(present=false, planned_rows=0, ...
    reason="the MUPET per-syllable CSV declares no curation_state role");
events.classification = struct(present=false, planned_rows=0, ...
    reason="the MUPET per-syllable CSV declares no class-label role");
events.counts = summarize(events);
end

function assertNoUnsupportedAnnotationEvidence(routed)
%ASSERTNOUNSUPPORTEDANNOTATIONEVIDENCE Refuse evidence this importer cannot store.
%
% The shared router populates review and label fields only when a profile
% declares those roles. Reaching this point with either present means the tracked
% MUPET profile now exports evidence the MUPET importer has no destination for.
% Dropping it quietly would lose extractor evidence, so the import stops.
withReview = strings(0, 1);
withLabel = strings(0, 1);
for index = 1:numel(routed.rows)
    row = routed.rows{index};
    if row.review_present
        withReview(end + 1, 1) = row.native_event_id; %#ok<AGROW>
    end
    if row.label_present
        withLabel(end + 1, 1) = row.native_event_id; %#ok<AGROW>
    end
end

if ~isempty(withReview)
    error("vawlume:ingest:MupetUnsupportedEventEvidence", ...
        ['The MUPET output profile now declares a curation_state role, but the ' ...
        'MUPET importer creates no curation evidence (syllables: %s). Extend ' ...
        'the importer deliberately rather than discarding extractor evidence.'], ...
        strjoin(unique(withReview), ", "));
end
if ~isempty(withLabel)
    error("vawlume:ingest:MupetUnsupportedEventEvidence", ...
        ['The MUPET output profile now declares a class-label role, but the ' ...
        'MUPET importer creates no classification evidence (syllables: %s). ' ...
        'Extend the importer deliberately rather than discarding extractor evidence.'], ...
        strjoin(unique(withLabel), ", "));
end
end

function counts = summarize(events)
%SUMMARIZE Planned dispositions, including the two deliberate zeros.
counts = struct( ...
    detections_create=0, detections_reuse=0, detections_conflict=0, ...
    measurements_create=0, measurements_reuse=0, measurements_conflict=0, ...
    curation_rows_expected=0, classification_rows_expected=0);

for index = 1:numel(events.detections)
    detection = events.detections{index};
    counts = bump(counts, "detections_" + detection.action);
    for m = 1:height(detection.measurements)
        counts = bump(counts, "measurements_" + string(detection.measurements.action(m)));
    end
end
end

function counts = bump(counts, name)
name = char(name);
if isfield(counts, name)
    counts.(name) = counts.(name) + 1;
end
end

function id = exportArtifactId(plan)
rows = plan.artifacts(plan.artifacts.role == "event_measurement_export", :);
id = double(rows.existing_artifact_id(1));
end
