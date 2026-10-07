function result = attributeCallers(conn, recordingRef, runSpec, options)
%ATTRIBUTECALLERS Plan or apply one native caller-attribution run.
%
%   result = VAWLUME.ESTIMATOR.ATTRIBUTECALLERS(conn, recordingRef, runSpec)
%   result = VAWLUME.ESTIMATOR.ATTRIBUTECALLERS(..., Apply=true)
%
% The native estimator's entry point (contract 06 D1). For every target event
% it composes, and computes nothing itself:
%
%   vawlume.estimator.candidateGeometry      identity-resolved distances (6.4, 6.5)
%   the stored normalized levels             of an explicit normalization run (6.7)
%   vawlume.acoustic.levelDifference         the observed difference (6.7)
%   vawlume.estimator.levelDifferenceConsistency   the method (6.8)
%
% and writes the result ONLY through vawlume.attribution.createRun,
% addCandidates and addEvidence. The estimator package writes no SQL.
%
% RUNSPEC (every input is an explicit reference; nothing is looked up as "the
% latest" of anything):
%
%   run_key                       project-scoped identity of the native run
%   settings_profile_version_id   a REGISTERED attribution_estimator_settings
%                                 profile version. Its file is read from the
%                                 stored content_uri and must match the stored
%                                 checksum
%   target_set                    createRun's target_set: detection_ids or
%                                 consensus_event_ids
%   participating_entity_ids      exactly the profile's candidate count (2)
%   clock                         vawlume.estimator.eventReferenceInstants' clock
%                                 declaration (alignment_run or same_clock)
%   tracking                      struct with stream (a stream reference), and
%                                 alignment_run_id or same_clock=true; optional
%                                 source_root. Bodypart and the interpolation gap
%                                 come from the profile, never from here
%   normalization_runs            one acoustic_call_level_normalization run per
%                                 target: a table (or struct of columns) with
%                                 detection_id (or consensus_event_id) and
%                                 analysis_run_id
%
%   optional: run_label, vawlume_version, source_commit, notes
%
% WHAT IS WRITTEN (contract 06 D10). One native run with its four declared
% inputs; one target per event; one candidate per participant per target, with
% the method's score and score_semantics, or no score and
% notes = "no_score_reason=<code>", and never a probability; and every input the
% method consumed as its own evidence row with its citation:
%
%   target     temporal_alignment  call_clock_placement        per alignment run used
%   target     acoustic            call_band_power_normalized  per channel, citing derived_measurement_id
%   target     acoustic            normalized_level_difference one, reconstructible from the two above
%   candidate  visual_identity     track_entity_association_used
%   candidate  pose_localization   bodypoint_microphone_distance  per channel and instant basis
%   candidate  pose_localization   bodypoint_pose_confidence      per instant basis, where present
%
% Rows exist only for values that exist: an unscored candidate keeps every row
% its available evidence supports. Every value_semantics names its producer and
% is a "key=value; ..." list, so a reader can recover each value's basis.
%
% PLANNING IS THE DEFAULT AND WRITES NOTHING. The plan holds every row that
% would be written.
%
% APPLY. The canonical writers each commit their own transaction, so a run
% cannot be written in ONE transaction through them (recorded as a finding in
% docs/development/44_native_estimation_run.md). To keep a failure from leaving
% a partial run, Apply first REHEARSES the identical sequence of public calls on
% a disposable copy of the database file, and writes to the real database only
% if every call succeeded there. A failure in the rehearsal raises
% vawlume:estimator:RehearsalFailed and the real database is untouched.
%
% REFUSED BY NAME, BEFORE ANY WRITE:
%   a run key that already names a run   vawlume:estimator:RunAlreadyApplied
%   a settings profile of another kind   vawlume:estimator:SettingsProfileKindInvalid
%   a changed settings file              vawlume:estimator:SettingsChecksumMismatch
%   a tracking stream of another recording, or a normalization run whose
%   measured event is in another recording   vawlume:estimator:InputRecordingMismatch
%   a target without a normalization run, or a run that is not one, or that
%   measures another event               vawlume:estimator:NormalizationRunInvalid
%   createRun's own refusals (event sets, recording, participants), raised by
%   createRun's planner
%   clocks that are not connected        vawlume:tracking:ClockDeclarationInvalid,
%                                        or the alignment layer's own refusal
%
% See also VAWLUME.ESTIMATOR.LEVELDIFFERENCECONSISTENCY,
% VAWLUME.ESTIMATOR.CANDIDATEGEOMETRY, VAWLUME.ATTRIBUTION.CREATERUN

arguments
    conn
    recordingRef (1,1) struct
    runSpec (1,1) struct
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
spec = validateSpec(runSpec);
settings = loadRegisteredSettings(conn, spec.settings_profile_version_id, repoRoot);
runPlan = planRun(conn, recordingRef, spec, settings);
recordingId = runPlan.recording.recording_id;
assertStreamRecording(conn, spec.tracking.stream, recordingId);

targets = runPlan.targets;
eventColumn = targetColumn(targets);
plans = cell(height(targets), 1);
for index = 1:height(targets)
    eventId = targets.(eventColumn)(index);
    plans{index} = planTarget(conn, eventColumn, eventId, recordingId, spec, ...
        settings, repoRoot);
end
plans = vertcat(plans{:});

result = struct(status="planned", committed=false, rehearsal="not_run", ...
    run_key=spec.run_key, recording_id=recordingId, ...
    settings=struct(profile_version_id=spec.settings_profile_version_id, ...
        profile_key=settings.profile_key, version=settings.version_label, ...
        checksum_sha256=settings.checksum_sha256, method_key=settings.method_key, ...
        method_version=settings.method_version), ...
    create_run_spec=runPlan.create_spec, targets=plans, ...
    planned_counts=countRows(plans), attribution_run_id=NaN);
if ~options.Apply
    return
end

rehearse(conn, recordingRef, runPlan.create_spec, plans);
result.rehearsal = "passed";
[plans, runId] = writeRun(conn, recordingRef, runPlan.create_spec, plans);
result.targets = plans;
result.attribution_run_id = runId;
result.status = "applied";
result.committed = true;
end

% ------------------------------------------------------------------ spec ---

function spec = validateSpec(runSpec)
required = ["run_key", "settings_profile_version_id", "target_set", ...
    "participating_entity_ids", "clock", "tracking", "normalization_runs"];
for name = required
    if ~isfield(runSpec, name)
        error("vawlume:estimator:RunSpecInvalid", "runSpec.%s is required.", name);
    end
end
spec = runSpec;
spec.run_key = string(runSpec.run_key);
for name = ["run_label", "vawlume_version", "source_commit", "notes"]
    if ~isfield(spec, name)
        spec.(name) = "";
    end
end
tracking = runSpec.tracking;
if ~isstruct(tracking) || ~isfield(tracking, "stream")
    error("vawlume:estimator:RunSpecInvalid", "runSpec.tracking.stream is required.");
end
for name = ["bodypart", "max_gap_s"]
    if isfield(tracking, name)
        error("vawlume:estimator:RunSpecInvalid", ...
            "runSpec.tracking.%s comes from the settings profile, not the run spec.", name);
    end
end
normalization = runSpec.normalization_runs;
if isstruct(normalization)
    normalization = struct2table(structfun(@(v) v(:), normalization, ...
        UniformOutput=false));
end
if ~istable(normalization) || ~ismember("analysis_run_id", ...
        string(normalization.Properties.VariableNames))
    error("vawlume:estimator:RunSpecInvalid", ...
        "runSpec.normalization_runs must name an analysis_run_id per target event.");
end
spec.normalization_runs = normalization;
end

function settings = loadRegisteredSettings(conn, versionId, repoRoot)
rows = fetch(conn, "SELECT cp.profile_kind, cpv.content_uri, " + ...
    "IFNULL(cpv.checksum_sha256,'') AS checksum FROM config_profile_versions cpv " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE cpv.profile_version_id=" + string(double(versionId)));
if isempty(rows) || height(rows) == 0
    error("vawlume:estimator:SettingsProfileNotFound", ...
        "Settings profile version %d is not registered.", versionId);
end
if string(rows.profile_kind(1)) ~= "attribution_estimator_settings"
    error("vawlume:estimator:SettingsProfileKindInvalid", ...
        "Settings profile version %d is of kind %s, not attribution_estimator_settings.", ...
        versionId, string(rows.profile_kind(1)));
end
settings = vawlume.estimator.loadSettings(string(rows.content_uri(1)), RepoRoot=repoRoot);
if settings.checksum_sha256 ~= string(rows.checksum(1))
    error("vawlume:estimator:SettingsChecksumMismatch", ...
        "The settings file at %s no longer matches registered version %d.", ...
        string(rows.content_uri(1)), versionId);
end
end

function runPlan = planRun(conn, recordingRef, spec, settings)
% createRun's own planner validates the target set, the recording, the
% participants and the profile kind, and writes nothing.
analysisRunIds = unique(double(spec.normalization_runs.analysis_run_id(:)))';
createSpec = struct(run_key=spec.run_key, attribution_path="native_estimate", ...
    method=settings.method_key + " " + settings.method_version, ...
    settings_profile_version_id=double(spec.settings_profile_version_id), ...
    target_set=spec.target_set, ...
    participating_entity_ids=double(spec.participating_entity_ids), ...
    sources=struct(analysis_run_ids=analysisRunIds), ...
    declared_inputs=settings.declared_inputs, run_label=spec.run_label, ...
    vawlume_version=spec.vawlume_version, source_commit=spec.source_commit, ...
    notes=spec.notes);
planned = vawlume.attribution.createRun(conn, recordingRef, createSpec);
if planned.analysis.action ~= "create" || planned.run.action ~= "create"
    error("vawlume:estimator:RunAlreadyApplied", ...
        "Run key '%s' already names a run. A native run is written once; use a " + ...
        "new run key.", spec.run_key);
end
runPlan = struct(create_spec=createSpec, recording=planned.recording, ...
    targets=planned.targets);
end

function column = targetColumn(targets)
if any(~isnan(targets.detection_id))
    column = "detection_id";
elseif any(~isnan(targets.consensus_event_id))
    column = "consensus_event_id";
else
    error("vawlume:estimator:EventSetUnsupported", ...
        "The native estimator targets detections or consensus events only.");
end
end

function assertStreamRecording(conn, streamRef, recordingId)
if isfield(streamRef, "external_stream_id")
    where = "es.external_stream_id=" + string(double(streamRef.external_stream_id));
else
    where = "p.project_key='" + replace(string(streamRef.project_key), "'", "''") + ...
        "' AND es.stream_name='" + replace(string(streamRef.stream_name), "'", "''") + "'";
end
rows = fetch(conn, "SELECT IFNULL(es.recording_id,-1) AS recording_id FROM external_streams es " + ...
    "JOIN projects p ON p.project_id=es.project_id WHERE " + where);
if isempty(rows) || height(rows) ~= 1
    error("vawlume:estimator:RunSpecInvalid", ...
        "runSpec.tracking.stream names no single tracking stream.");
end
if double(rows.recording_id(1)) ~= recordingId
    error("vawlume:estimator:InputRecordingMismatch", ...
        "The tracking stream belongs to another recording than the run's (%d).", recordingId);
end
end

% ---------------------------------------------------------------- target ---

function plan = planTarget(conn, eventColumn, eventId, recordingId, spec, settings, repoRoot)
parameters = settings.parameters;
pair = parameters.channel_pair;
eventRef = struct();
eventRef.(eventColumn) = eventId;
kind = extractBefore(eventColumn, "_id");

tracking = spec.tracking;
tracking.bodypart = parameters.bodypart;
tracking.max_gap_s = parameters.max_interpolation_gap_s;
if ~isfield(tracking, "repo_root")
    tracking.repo_root = repoRoot;
end
geometry = vawlume.estimator.candidateGeometry(conn, eventRef, spec.clock, ...
    tracking, double(spec.participating_entity_ids), pair);

normalization = readNormalization(conn, spec.normalization_runs, eventColumn, ...
    eventId, kind, recordingId, pair);
difference = vawlume.acoustic.levelDifference(normalization.sides(1), ...
    normalization.sides(2), parameters.refuse_clipped_channels);
method = vawlume.estimator.levelDifferenceConsistency(geometry.entities, ...
    geometry.geometry, difference, settings);

plan = struct();
plan.event_kind = string(kind);
plan.event_id = eventId;
plan.attribution_target_id = NaN;
plan.normalization_run_id = normalization.run_id;
plan.method = method;
plan.difference = difference;
plan.candidates = candidateRows(method);
plan.target_evidence = targetEvidence(geometry, normalization, difference, parameters);
plan.candidate_evidence = candidateEvidence(geometry, settings);
plan.candidate_ids = table(zeros(0, 1), zeros(0, 1), ...
    VariableNames=["entity_id", "attribution_candidate_id"]);
end

function normalization = readNormalization(conn, runs, eventColumn, eventId, kind, ...
        recordingId, pair)
if ~ismember(eventColumn, string(runs.Properties.VariableNames))
    error("vawlume:estimator:NormalizationRunInvalid", ...
        "runSpec.normalization_runs has no %s column.", eventColumn);
end
match = double(runs.(eventColumn)) == eventId;
if sum(match) ~= 1
    error("vawlume:estimator:NormalizationRunInvalid", ...
        "Target %s %d needs exactly one normalization run; %d were given.", ...
        kind, eventId, sum(match));
end
runId = double(runs.analysis_run_id(match));
run = fetch(conn, "SELECT run_type FROM analysis_runs WHERE analysis_run_id=" + string(runId));
if isempty(run) || height(run) == 0 || ...
        string(run.run_type(1)) ~= "acoustic_call_level_normalization"
    error("vawlume:estimator:NormalizationRunInvalid", ...
        "Analysis run %d is not an acoustic_call_level_normalization run.", runId);
end
% Which event the run measured, through its own lineage: its call-window parent.
measured = fetch(conn, "SELECT DISTINCT IFNULL(dm.detection_id,-1) AS detection_id, " + ...
    "IFNULL(dm.consensus_event_id,-1) AS consensus_event_id, " + ...
    "COALESCE((SELECT d.recording_id FROM detections d WHERE d.detection_id=dm.detection_id), " + ...
    "(SELECT c.recording_id FROM consensus_events c WHERE c.consensus_event_id=dm.consensus_event_id), " + ...
    "-1) AS recording_id FROM analysis_run_sources ars " + ...
    "JOIN derived_measurements dm ON dm.analysis_run_id=ars.source_analysis_run_id " + ...
    "WHERE ars.analysis_run_id=" + string(runId) + ...
    " AND ars.dependency_role='call_window_measurement'");
if isempty(measured) || height(measured) ~= 1
    error("vawlume:estimator:NormalizationRunInvalid", ...
        "Normalization run %d does not trace to exactly one measured event.", runId);
end
if double(measured.recording_id(1)) ~= recordingId
    error("vawlume:estimator:InputRecordingMismatch", ...
        "Normalization run %d measured an event of another recording.", runId);
end
if double(measured.(eventColumn)(1)) ~= eventId
    error("vawlume:estimator:NormalizationRunInvalid", ...
        "Normalization run %d measured another event than %s %d.", runId, kind, eventId);
end

rows = fetch(conn, "SELECT dm.derived_measurement_id, dm.recording_channel_id, " + ...
    "rc.channel_index, dm.value_real, IFNULL(dm.unit,'') AS unit, " + ...
    "dm.derivation_details_json FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "JOIN recording_channels rc ON rc.recording_channel_id=dm.recording_channel_id " + ...
    "WHERE dm.analysis_run_id=" + string(runId) + ...
    " AND md.metric_key='call_band_power_normalized'");
channels = fetch(conn, "SELECT recording_channel_id, channel_index FROM recording_channels " + ...
    "WHERE recording_id=" + string(recordingId));
sides = repmat(emptySide(), 1, 2);
for k = 1:2
    side = emptySide();
    side.target_kind = string(kind);
    side.target_id = eventId;
    side.channel_index = pair(k);
    declared = double(channels.recording_channel_id(double(channels.channel_index) == pair(k)));
    if ~isempty(declared)
        side.recording_channel_id = declared(1);
    end
    if ~isempty(rows) && height(rows) > 0
        hit = find(double(rows.channel_index) == pair(k), 1);
    else
        hit = [];
    end
    if isempty(hit)
        side.reason = "not_normalized_in_run";
    else
        details = jsondecode(char(rows.derivation_details_json(hit)));
        side.status = "normalized";
        side.value = double(rows.value_real(hit));
        side.unit = string(rows.unit(hit));
        side.derived_measurement_id = double(rows.derived_measurement_id(hit));
        side.qc_flags = jsonList(details.qc_flags);
        side.producer = string(details.method_key) + " " + string(details.method_version);
        side.policy = string(details.policy_profile_key) + " " + string(details.policy_version);
    end
    sides(k) = side;
end
normalization = struct(run_id=runId, sides=sides);
end

function side = emptySide()
side = struct(target_kind="", target_id=NaN, channel_index=NaN, ...
    recording_channel_id=NaN, normalized_metric="call_band_power_normalized", ...
    unit="", status="not_normalized", reason="", value=NaN, ...
    qc_flags=strings(0, 1), derived_measurement_id=NaN, producer="", policy="");
end

% ------------------------------------------------------------------ rows ---

function rows = candidateRows(method)
c = method.candidates;
notes = strings(height(c), 1);
unscored = c.status ~= "scored";
notes(unscored) = "no_score_reason=" + c.no_score_reason(unscored);
semantics = c.score_semantics;
semantics(unscored) = "";
rows = table(c.entity_id, c.score, semantics, notes, ...
    VariableNames=["entity_id", "score", "score_semantics", "notes"]);
end

function rows = targetEvidence(geometry, normalization, difference, parameters)
rows = emptyEvidence();
instants = geometry.event.instants;
primary = instants(instants.instant_basis == parameters.primary_instant_basis, :);
if ~isnan(geometry.event.alignment_run_id) && height(primary) == 1
    rows = [rows; clockRow(geometry.event.alignment_run_id, "audio_to_reference", ...
        primary.uncertainty_s, primary.uncertainty_semantics, primary.extrapolated, ...
        parameters.primary_instant_basis)];
end
trackingRun = geometry.tracking_clock.alignment_run_id;
if ~isnan(trackingRun)
    g = geometry.geometry;
    at = g(g.instant_basis == parameters.primary_instant_basis & g.status == "computed", :);
    if height(at) > 0
        rows = [rows; clockRow(trackingRun, "tracking_to_reference", ...
            at.clock_uncertainty_s(1), at.clock_uncertainty_semantics(1), ...
            any(at.bracket_extrapolated), parameters.primary_instant_basis)];
    end
end
for side = normalization.sides
    if side.status ~= "normalized"
        continue
    end
    rows = [rows; evidenceRow("acoustic", "call_band_power_normalized", ...
        value_real=side.value, value_units=side.unit, ...
        value_semantics=semanticsText(["producer", side.producer; ...
            "policy", side.policy; "metric", side.normalized_metric; ...
            "channel_index", string(side.channel_index); ...
            "qc_flags", strjoin(side.qc_flags, ",")]), ...
        derived_measurement_id=side.derived_measurement_id, ...
        recording_channel_id=side.recording_channel_id)]; %#ok<AGROW>
end
if difference.status == "computed"
    rows = [rows; evidenceRow("acoustic", "normalized_level_difference", ...
        value_real=difference.value, value_units="dB", ...
        value_semantics=semanticsText(["producer", "vawlume.acoustic.levelDifference"; ...
            "formula", difference.formula; "sign", difference.sign_convention; ...
            "metric", difference.metric_key; ...
            "channel_index_a", string(difference.channel_index_a); ...
            "channel_index_b", string(difference.channel_index_b); ...
            "derived_measurement_id_a", string(difference.derived_measurement_id_a); ...
            "derived_measurement_id_b", string(difference.derived_measurement_id_b); ...
            "flags", strjoin(difference.flags, ",")]), ...
        source_locator="vawlume.acoustic.levelDifference(derived_measurement_id " + ...
            string(difference.derived_measurement_id_a) + ", " + ...
            string(difference.derived_measurement_id_b) + ")")];
end
end

function row = clockRow(runId, direction, bound, boundSemantics, extrapolated, basis)
pairs = ["producer", "vawlume.alignment.applyTransform"; ...
    "direction", direction; "instant_basis", basis; ...
    "extrapolated", string(logical(extrapolated)); ...
    "bound_semantics", string(boundSemantics); ...
    "calibration", "uncalibrated; not a confidence interval, a standard error, or a probability"];
if isnan(bound)
    row = evidenceRow("temporal_alignment", "call_clock_placement", ...
        value_text="uncertainty_not_recorded", value_units="s", ...
        value_semantics=semanticsText(pairs), alignment_run_id=runId);
else
    row = evidenceRow("temporal_alignment", "call_clock_placement", ...
        value_real=bound, value_units="s", value_semantics=semanticsText(pairs), ...
        alignment_run_id=runId);
end
end

function evidence = candidateEvidence(geometry, settings)
entities = geometry.entities;
g = geometry.geometry;
evidence = repmat(struct(entity_id=NaN, rows=emptyEvidence()), height(entities), 1);
for k = 1:height(entities)
    entityId = entities.entity_id(k);
    rows = emptyEvidence();
    association = entities.tracking_identity_association_id(k);
    if ~isnan(association)
        rows = [rows; evidenceRow("visual_identity", "track_entity_association_used", ...
            value_text=semanticsText(["native_track_id", string(entities.native_track_id(k)); ...
                "decided_by_step", string(entities.decided_by_step(k)); ...
                "time_validity", string(entities.time_validity(k))]), ...
            value_units="text", ...
            value_semantics=semanticsText(["producer", ...
                "vawlume.tracking.identityOverWindow via vawlume.estimator.candidateGeometry"; ...
                "statement", "the stored association this candidate's track was resolved through"]), ...
            identity_statement_kind="identity_association", ...
            tracking_identity_association_id=association)]; %#ok<AGROW>
    end
    mine = g(g.entity_id == entityId & g.status == "computed", :);
    for r = 1:height(mine)
        rows = [rows; evidenceRow("pose_localization", "bodypoint_microphone_distance", ...
            value_real=mine.distance(r), value_units=mine.unit(r), ...
            value_semantics=semanticsText(["producer", ...
                "vawlume.geometry.distance via vawlume.estimator.candidateGeometry"; ...
                "instant_basis", mine.instant_basis(r); ...
                "distance_basis", mine.distance_basis(r); ...
                "position_basis", mine.position_basis(r); ...
                "channel_index", string(mine.channel_index(r)); ...
                "bodypart", settings.parameters.bodypart; ...
                "event_extrapolated", string(mine.event_extrapolated(r)); ...
                "bracket_extrapolated", string(mine.bracket_extrapolated(r))]), ...
            identity_statement_kind="identity_association", ...
            tracking_identity_association_id=mine.tracking_identity_association_id(r), ...
            recording_channel_id=mine.recording_channel_id(r))]; %#ok<AGROW>
    end
    confidence = mine(mine.channel_index == settings.parameters.channel_pair(1) & ...
        ~isnan(mine.pose_confidence_min_bracket), :);
    for r = 1:height(confidence)
        rows = [rows; evidenceRow("pose_localization", "bodypoint_pose_confidence", ...
            value_real=confidence.pose_confidence_min_bracket(r), ...
            value_units="upstream_score", ...
            value_semantics=semanticsText(["producer", ...
                "upstream tracker via vawlume.estimator.candidateGeometry"; ...
                "instant_basis", confidence.instant_basis(r); ...
                "statistic", "minimum of the two bracketing samples' pose confidence"; ...
                "meaning", "where the bodypoint was; not identity confidence"]), ...
            identity_statement_kind="identity_association", ...
            tracking_identity_association_id= ...
                confidence.tracking_identity_association_id(r))]; %#ok<AGROW>
    end
    evidence(k) = struct(entity_id=entityId, rows=rows);
end
end

function row = evidenceRow(dimension, kind, values)
arguments
    dimension (1,1) string
    kind (1,1) string
    values.value_real (1,1) double = NaN
    values.value_text (1,1) string = ""
    values.value_units (1,1) string = ""
    values.value_semantics (1,1) string = ""
    values.identity_statement_kind (1,1) string = ""
    values.tracking_identity_association_id (1,1) double = NaN
    values.alignment_run_id (1,1) double = NaN
    values.source_locator (1,1) string = ""
    values.recording_channel_id (1,1) double = NaN
    values.derived_measurement_id (1,1) double = NaN
end
row = table(dimension, kind, values.value_real, values.value_text, ...
    values.value_units, values.value_semantics, values.identity_statement_kind, ...
    values.tracking_identity_association_id, values.alignment_run_id, ...
    values.source_locator, values.recording_channel_id, ...
    values.derived_measurement_id, VariableNames=evidenceColumns());
end

function rows = emptyEvidence()
rows = table(strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), VariableNames=evidenceColumns());
end

function names = evidenceColumns()
names = ["evidence_dimension", "evidence_kind", "value_real", "value_text", ...
    "value_units", "value_semantics", "identity_statement_kind", ...
    "tracking_identity_association_id", "alignment_run_id", "source_locator", ...
    "recording_channel_id", "derived_measurement_id"];
end

function text = semanticsText(pairs)
text = strjoin(pairs(:, 1) + "=" + pairs(:, 2), "; ");
end

function values = jsonList(raw)
if isempty(raw)
    values = strings(0, 1);
elseif ischar(raw)
    values = string(raw);
else
    values = string(raw(:));
end
end

function counts = countRows(plans)
candidates = 0;
targetRows = 0;
candidateRowsCount = 0;
for k = 1:numel(plans)
    candidates = candidates + height(plans(k).candidates);
    targetRows = targetRows + height(plans(k).target_evidence);
    for e = 1:numel(plans(k).candidate_evidence)
        candidateRowsCount = candidateRowsCount + height(plans(k).candidate_evidence(e).rows);
    end
end
counts = struct(attribution_runs=1, attribution_targets=numel(plans), ...
    attribution_candidates=candidates, target_evidence=targetRows, ...
    candidate_evidence=candidateRowsCount, ...
    attribution_evidence=targetRows + candidateRowsCount, ...
    attribution_run_declared_inputs=4);
end

% ----------------------------------------------------------------- write ---

function [plans, runId] = writeRun(conn, recordingRef, createSpec, plans)
% The whole write, through the canonical public API only.
created = vawlume.attribution.createRun(conn, recordingRef, createSpec, Apply=true);
if created.status ~= "created"
    error("vawlume:estimator:RunAlreadyApplied", ...
        "createRun reported '%s' for run key '%s'.", created.status, createSpec.run_key);
end
runId = created.run.attribution_run_id;
targets = created.targets;
for k = 1:numel(plans)
    column = plans(k).event_kind + "_id";
    targetId = targets.attribution_target_id(targets.(column) == plans(k).event_id);
    plans(k).attribution_target_id = targetId;
    candidates = vawlume.attribution.addCandidates(conn, ...
        struct(attribution_target_id=targetId), plans(k).candidates, Apply=true);
    ids = candidates.candidates(:, ["entity_id", "attribution_candidate_id"]);
    plans(k).candidate_ids = ids;
    if height(plans(k).target_evidence) > 0
        vawlume.attribution.addEvidence(conn, struct(attribution_target_id=targetId), ...
            plans(k).target_evidence, Apply=true);
    end
    for e = 1:numel(plans(k).candidate_evidence)
        block = plans(k).candidate_evidence(e);
        if height(block.rows) == 0
            continue
        end
        candidateId = ids.attribution_candidate_id(ids.entity_id == block.entity_id);
        vawlume.attribution.addEvidence(conn, ...
            struct(attribution_candidate_id=candidateId), block.rows, Apply=true);
    end
end
end

function rehearse(conn, recordingRef, createSpec, plans)
% The canonical writers commit one call at a time. Replaying the identical calls
% on a disposable copy first means any refusal they would raise is raised before
% the real database is touched.
source = string(conn.Database);
if strlength(source) == 0 || ~isfile(source)
    error("vawlume:estimator:RehearsalUnavailable", ...
        "Apply needs a file-backed database to rehearse on; '%s' is not one.", source);
end
copyPath = string(tempname) + ".sqlite";
copyfile(source, copyPath);
rehearsal = sqlite(char(copyPath), "connect");
cleaner = onCleanup(@() closeAndDelete(rehearsal, copyPath));
foreignKeys = fetch(conn, "PRAGMA foreign_keys");
if double(foreignKeys{1, 1}) == 1
    execute(rehearsal, "PRAGMA foreign_keys = ON");
end
try
    writeRun(rehearsal, recordingRef, createSpec, plans);
catch failure
    cause = MException("vawlume:estimator:RehearsalFailed", ...
        "The run failed in rehearsal and nothing was written to the database: %s", ...
        failure.message);
    cause = addCause(cause, failure);
    throw(cause);
end
clear cleaner
end

function closeAndDelete(connection, path)
if isopen(connection)
    close(connection);
end
if isfile(path)
    delete(path);
end
end
