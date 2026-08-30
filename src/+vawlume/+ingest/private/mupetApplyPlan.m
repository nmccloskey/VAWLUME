function [plan, counts] = mupetApplyPlan(conn, plan)
%MUPETAPPLYPLAN Atomically apply the whole MUPET scientific graph.
%
% One function owns one transaction for the whole import: the settings profile,
% the exact extractor version, every artifact, the extraction run and its
% recording input, the run-artifact role links, and the complete syllable
% population with its measurements. A failure at any point rolls all of it back,
% so the invariant holds:
%
%   an extraction run exists  <=>  its intended syllables were imported
%
% Helpers called from here insert only; none starts, commits, or rolls back a
% transaction of its own. The provenance rows and the event population are both
% written by the shared extractor core, which DeepSqueak uses identically.
%
% Dependency order is fixed by the schema: extraction_run_inputs must exist
% before any detection, because trg_detection_requires_run_input rejects a
% detection whose recording is not a registered input to its run.
%
% No curation_events, classification_runs, classification_classes, or
% classification_assignments rows are written, because the MUPET per-syllable CSV
% exports no review state and no class label. That is a capability difference,
% not an omission.

arguments
    conn
    plan (1,1) struct
end

if plan.has_conflicts
    error("vawlume:ingest:MupetPlanConflict", ...
        "A MUPET import plan with conflicts cannot be applied.");
end

oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:ingest:TransactionState", ...
        "MUPET import requires a connection with AutoCommit enabled.");
end

counts = emptyCounts();
conn.AutoCommit = "off";
try
    [plan, counts] = extractorApplyProvenance(conn, plan, counts, ...
        SettingsDescription="MUPET extractor settings profile.", ...
        SettingsVersionNote="Extractor settings profile supplied with a MUPET import.", ...
        ExtractorVersionNote="Exact extractor version declared for a MUPET import.", ...
        RunNotes=runNotes(plan));
    [plan, counts] = applyEventPopulation(conn, plan, counts);
    if insertedRowCount(counts) > 0
        commit(conn);
    end
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end

function notes = runNotes(plan)
% MUPET's segmentation and filtering behaviour is settings-dependent, so the run
% states which settings source produced it and whether native processed evidence
% and extractor-native grouping were supplied at all.
statements = "settings=" + plan.settings_status + ...
    "; settings_source=" + plan.context.settings.mode + ...
    "; native_processed=" + plan.context.native_artifact.mode + ...
    "; dataset=" + plan.context.dataset.status;
if strlength(plan.run.notes) > 0
    notes = plan.run.notes + " [" + statements + "]";
else
    notes = statements;
end
end

function [plan, counts] = applyEventPopulation(conn, plan, counts)
% The export artifact's row id is read again here rather than taken from the
% plan. When the artifact is created by this same apply, the plan recorded it as
% unresolved, and writing that into detections would leave source_artifact_id
% NULL. Detection identity is UNIQUE(run, recording, source_artifact_id,
% native_event_id), and SQLite treats NULLs as distinct, so a NULL there would
% silently let every rerun insert a second copy of the whole population.
scope = struct( ...
    extraction_run_id=plan.run.existing_extraction_run_id, ...
    recording_id=plan.recording.recording_id, ...
    source_artifact_id=appliedExportArtifactId(plan), ...
    event_subtype="vocalization_detection", ...
    timing_basis="profile_selected_event_geometry");
[plan.events.detections, counts] = extractorApplyEvents(conn, scope, ...
    plan.events.detections, counts);
end

function id = appliedExportArtifactId(plan)
rows = plan.artifacts(plan.artifacts.role == "event_measurement_export", :);
id = double(rows.existing_artifact_id(1));
if isnan(id)
    error("vawlume:ingest:MupetArtifactUnresolved", ...
        "The event CSV artifact was not resolved before the syllable population.");
end
end

function total = insertedRowCount(counts)
%INSERTEDROWCOUNT Number of rows this apply actually wrote.
%
% A fully compatible rerun reuses every row and therefore writes nothing, which
% leaves SQLite with no open transaction to commit. This importer records no
% per-attempt audit row, so the no-write case is normal rather than exceptional
% and must not be reported as a commit failure.
total = counts.config_profiles + counts.config_profile_versions + ...
    counts.extractor_versions + counts.artifacts + counts.extraction_runs + ...
    counts.extraction_run_inputs + counts.extraction_run_artifacts + ...
    counts.detections + counts.event_measurements;
end

function counts = emptyCounts()
% curation_events and classification rows have no counter because this importer
% never writes one. A zero counter would suggest the rows were considered and
% found empty; their absence from the contract is the accurate statement.
counts = struct( ...
    config_profiles=0, ...
    config_profile_versions=0, ...
    extractor_versions=0, ...
    artifacts=0, ...
    extraction_runs=0, ...
    extraction_run_inputs=0, ...
    extraction_run_artifacts=0, ...
    detections=0, ...
    event_measurements=0, ...
    reused_config_profiles=0, ...
    reused_config_profile_versions=0, ...
    reused_extractor_versions=0, ...
    reused_artifacts=0, ...
    reused_extraction_runs=0, ...
    reused_extraction_run_inputs=0, ...
    reused_extraction_run_artifacts=0, ...
    reused_detections=0, ...
    reused_event_measurements=0);
end
