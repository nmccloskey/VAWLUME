function result = normalizeCallLevels(conn, callRunRef, responseRunRef, options)
%NORMALIZECALLLEVELS Divide call-window levels by their channel's own response.
%
%   result = VAWLUME.ACOUSTIC.NORMALIZECALLLEVELS(conn, ...
%       struct(analysis_run_id=callRun), struct(analysis_run_id=responseRun))
%   result = VAWLUME.ACOUSTIC.NORMALIZECALLLEVELS(..., ...
%       PolicyPath="config/09_acoustic_normalization_policies/....json", ...
%       Apply=true, RunKey="stable-run-key")
%
% CALLRUNREF names one acoustic_call_window_response run (measureCallWindow).
% RESPONSERUNREF names one acoustic_channel_response_estimate run
% (estimateChannelResponse), by analysis_run_id or by project_key plus run_key.
%
% The fixed method vawlume.acoustic.call_level_normalization version 1.0.0
% (contract 06 D6) computes, per (event, channel, declared pair):
%
%   normalized = measured / response
%
% where RESPONSE is the value of the one estimate for the same recording
% channel, the pair's response metric, the pair's reference_type and the
% identical band. The quotient is dimensionless, stored in the unit
% ratio_to_channel_response. Every matching rule, and what each response
% qc_status does, is read from the versioned policy; the policy is required to
% declare all of them.
%
% This is the one place a channel-response estimate changes a number. The
% estimates stay uncalibrated: the result is relative to the channel's own
% reference response within one recording, and is not an absolute level, a
% hardware calibration, or comparable across recordings.
%
% Refused for the whole run: a call run of another type, a response estimate
% from another recording (vawlume:acoustic:NormalizationRecordingMismatch), and
% a policy that is invalid or claims calibration. Per channel, with a reason
% and no value: no source measurement, no estimate, a metric, family or band
% mismatch, an estimate the policy excludes by qc_status, and a response value
% that is not positive. Source clipping and partial coverage propagate as flags
% and are not repaired.
%
% It compares no channel with another; see VAWLUME.ACOUSTIC.LEVELDIFFERENCE.
%
% Apply=false (default) is read-only. Apply=true creates, or exactly reuses,
% one analysis run of type acoustic_call_level_normalization, linked to the
% policy (role call_level_normalization_policy) and to both parent runs
% (roles call_window_measurement and channel_response_estimate), with one
% derived_measurements row per normalized value.

arguments
    conn
    callRunRef (1,1) struct
    responseRunRef (1,1) struct
    options.PolicyPath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.Apply (1,1) logical = false
    options.RunKey (1,1) string = ""
    options.RunLabel (1,1) string = ""
    options.VawlumeVersion (1,1) string = ""
    options.SourceCommit (1,1) string = ""
    options.Notes (1,1) string = ""
end

repoRoot = resolveRepoRoot(options.RepoRoot);
policy = acousticLoadNormalizationPolicy(options.PolicyPath, repoRoot);
source = resolveCallRun(conn, callRunRef);
response = vawlume.acoustic.readChannelResponse(conn, responseRunRef);
assertSameRecording(source, response);

outcomes = emptyOutcomes();
for pair = policy.pairs
    for channel = source.channels'
        outcomes = [outcomes; normalizeOne(source, response, policy, pair, channel)]; %#ok<AGROW>
    end
end
status = runStatus(outcomes);

analysisRunId = NaN;
action = "planned";
if options.Apply
    if ismissing(options.RunKey) || strlength(options.RunKey) == 0
        error("vawlume:acoustic:RunKeyRequired", ...
            "RunKey is required when Apply=true.");
    end
    [analysisRunId, outcomes, action] = persistNormalization(conn, source, ...
        response, policy, outcomes, status, options, repoRoot);
end

result = struct( ...
    target_kind=source.target_kind, ...
    detection_id=source.detection_id, ...
    consensus_event_id=source.consensus_event_id, ...
    recording_id=source.recording_id, ...
    source_analysis_run_id=source.analysis_run_id, ...
    response_analysis_run_id=response.analysis.analysis_run_id, ...
    policy=struct(profile_key=policy.profile_key, version=policy.version_label, ...
        content_uri=policy.content_uri, checksum_sha256=policy.checksum_sha256, ...
        calibration_status=policy.calibration_state, ...
        comparability_scope=policy.comparability_scope), ...
    status=status, ...
    outcomes=outcomes, ...
    method_key=policy.method_key, ...
    method_version=policy.method_version, ...
    run_type=runType(), ...
    analysis_run_id=analysisRunId, ...
    action=action);
end

function value = runType()
value = "acoustic_call_level_normalization";
end

% ------------------------------------------------------------ resolution ---

function source = resolveCallRun(conn, ref)
names = string(fieldnames(ref));
if isequal(names, "analysis_run_id")
    id = double(ref.analysis_run_id);
    if ~isscalar(id) || ~isfinite(id) || id < 1 || id ~= floor(id)
        error("vawlume:acoustic:NormalizationSourceRefInvalid", ...
            "callRunRef.analysis_run_id must be a positive integer.");
    end
    predicate = "ar.analysis_run_id=" + string(id);
elseif isequal(sort(names), ["project_key"; "run_key"])
    predicate = "p.project_key=" + acousticSqlText(string(ref.project_key)) + ...
        " AND ar.run_key=" + acousticSqlText(string(ref.run_key));
else
    error("vawlume:acoustic:NormalizationSourceRefInvalid", ...
        "callRunRef must contain only analysis_run_id, or project_key plus run_key.");
end
runs = fetch(conn, "SELECT ar.analysis_run_id, ar.project_id, ar.run_type, ar.run_key " + ...
    "FROM analysis_runs ar JOIN projects p ON p.project_id=ar.project_id WHERE " + predicate);
if isempty(runs) || height(runs) == 0
    error("vawlume:acoustic:NormalizationSourceNotFound", ...
        "No analysis run matches callRunRef.");
end
if acousticPresentText(runs.run_type(1)) ~= "acoustic_call_window_response"
    error("vawlume:acoustic:NormalizationSourceKindInvalid", ...
        "Analysis run %d is '%s', not acoustic_call_window_response.", ...
        runs.analysis_run_id(1), acousticPresentText(runs.run_type(1)));
end
runId = double(runs.analysis_run_id(1));
rows = fetch(conn, "SELECT dm.derived_measurement_id, md.metric_key, " + ...
    "IFNULL(dm.detection_id,-1) AS detection_id, " + ...
    "IFNULL(dm.consensus_event_id,-1) AS consensus_event_id, " + ...
    "dm.recording_channel_id, rc.channel_index, rc.recording_id, dm.value_real, " + ...
    "IFNULL(dm.unit,'') AS unit, dm.derivation_details_json " + ...
    "FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "JOIN recording_channels rc ON rc.recording_channel_id=dm.recording_channel_id " + ...
    "WHERE dm.analysis_run_id=" + string(runId) + ...
    " ORDER BY rc.channel_index, md.metric_key");
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:NormalizationSourceEmpty", ...
        "Call-measurement run %d holds no measurements (every channel failed); " + ...
        "there is nothing to normalize.", runId);
end
for name = ["derived_measurement_id", "detection_id", "consensus_event_id", ...
        "recording_channel_id", "channel_index", "recording_id", "value_real"]
    rows.(name) = double(rows.(name));
end
for name = ["metric_key", "unit", "derivation_details_json"]
    rows.(name) = string(rows.(name));
end

details = jsondecode(char(rows.derivation_details_json(1)));
source = struct(analysis_run_id=runId, project_id=double(runs.project_id(1)), ...
    run_key=acousticPresentText(runs.run_key(1)), ...
    recording_id=rows.recording_id(1), target_kind=string(details.target_kind), ...
    detection_id=NaN, consensus_event_id=NaN, target_column="", target_id=NaN, ...
    rows=rows, channels=[]);
if rows.detection_id(1) > 0
    source.detection_id = rows.detection_id(1);
    source.target_column = "detection_id";
    source.target_id = rows.detection_id(1);
else
    source.consensus_event_id = rows.consensus_event_id(1);
    source.target_column = "consensus_event_id";
    source.target_id = rows.consensus_event_id(1);
end

% Every channel the measurement run was asked for, so a requested channel that
% failed is reported rather than silently absent.
requested = double(details.requested_channel_indices(:));
declared = fetch(conn, "SELECT recording_channel_id, channel_index FROM " + ...
    "recording_channels WHERE recording_id=" + string(source.recording_id));
channels = table(requested, NaN(numel(requested), 1), ...
    VariableNames=["channel_index", "recording_channel_id"]);
for index = 1:height(channels)
    match = double(declared.channel_index) == channels.channel_index(index);
    if any(match)
        channels.recording_channel_id(index) = double(declared.recording_channel_id(match));
    end
end
source.channels = table2struct(channels);
end

function assertSameRecording(source, response)
if response.analysis.project_id ~= source.project_id
    recordingMismatch(source.recording_id, NaN);
end
if ~isempty(response.estimates) && height(response.estimates) > 0
    recordings = unique(response.estimates.recording_id);
    if ~isequal(recordings, source.recording_id)
        recordingMismatch(source.recording_id, recordings(1));
    end
end
end

function recordingMismatch(callRecording, responseRecording)
error("vawlume:acoustic:NormalizationRecordingMismatch", ...
    "Response estimates must come from the call's own recording %d (found %s). " + ...
    "Normalization is within one recording only (contract 06 D8).", ...
    callRecording, string(responseRecording));
end

% ---------------------------------------------------------- normalization ---

function outcome = normalizeOne(source, response, policy, pair, channel)
outcome = blankOutcome(source, pair, channel);
rows = source.rows;
sourceMask = rows.channel_index == channel.channel_index & ...
    rows.metric_key == pair.call_metric;
if ~any(sourceMask)
    outcome.reason = "source_measurement_absent";
    return
end
row = rows(find(sourceMask, 1), :);
details = jsondecode(char(row.derivation_details_json));
outcome.source_derived_measurement_id = row.derived_measurement_id;
outcome.source_value = row.value_real;
outcome.source_unit = row.unit;
band = double(details.frequency_band_hz(:))';
outcome.source_band_hz = {band};
outcome.source_qc_flags = {jsonList(details.qc_flags)};

[estimate, reason] = matchEstimate(response.estimates, pair, channel, band);
if strlength(reason) > 0
    outcome.reason = reason;
    return
end
outcome.channel_response_estimate_id = estimate.channel_response_estimate_id;
outcome.response_value = estimate.value_real;
outcome.response_unit = estimate.unit;
outcome.response_qc_status = estimate.qc_status;
outcome.response_details = string(estimate.details_json);

handling = policy.qc_handling.(char(estimate.qc_status));
outcome.response_qc_action = handling.action;
switch handling.action
    case "refuse_run"
        error("vawlume:acoustic:NormalizationRefusedByPolicy", ...
            "The policy refuses the run when a matched response estimate is '%s'.", ...
            estimate.qc_status);
    case "exclude_channel"
        outcome.reason = handling.reason_code;
        return
end
if ~(isfinite(estimate.value_real) && estimate.value_real > 0)
    outcome.reason = "response_value_not_positive";
    return
end
if outcome.source_unit ~= estimate.unit
    outcome.reason = "response_unit_mismatch";
    return
end

flags = outcome.source_qc_flags{1};
if handling.action == "use_with_flag"
    flags(end + 1, 1) = handling.flag;
end
outcome.qc_flags = {unique(flags, "stable")};
outcome.value = row.value_real / estimate.value_real;
outcome.unit = "ratio_to_channel_response";
outcome.status = "normalized";
end

function values = jsonList(raw)
% jsondecode gives [] for an empty list, char for one string, cell for several.
if isempty(raw)
    values = strings(0, 1);
elseif ischar(raw)
    values = string(raw);
else
    values = string(raw(:));
end
end

function [estimate, reason] = matchEstimate(estimates, pair, channel, band)
% Metric, then family, then band: the first rule that leaves nothing names the
% mismatch. No neighbouring band, other family or other metric is substituted.
estimate = [];
reason = "";
if isempty(estimates) || height(estimates) == 0 || isnan(channel.recording_channel_id)
    reason = "no_response_estimate";
    return
end
mask = estimates.recording_channel_id == channel.recording_channel_id;
if ~any(mask)
    reason = "no_response_estimate";
    return
end
mask = mask & estimates.metric_key == pair.response_metric;
if ~any(mask)
    reason = "response_metric_mismatch";
    return
end
mask = mask & estimates.reference_type == pair.reference_type;
if ~any(mask)
    reason = "response_family_mismatch";
    return
end
if numel(band) ~= 2
    reason = "response_band_mismatch";
    return
end
mask = mask & estimates.frequency_min_hz == band(1) & ...
    estimates.frequency_max_hz == band(2);
if ~any(mask)
    reason = "response_band_mismatch";
    return
end
if sum(mask) ~= 1
    error("vawlume:acoustic:NormalizationEstimateAmbiguous", ...
        "Response run holds %d estimates for one channel, metric, family and band.", ...
        sum(mask));
end
estimate = table2struct(estimates(mask, :));
end

function status = runStatus(outcomes)
normalized = outcomes.status == "normalized";
clean = normalized & cellfun(@isempty, outcomes.qc_flags);
if ~any(normalized)
    status = "failed";
elseif all(clean)
    status = "completed";
else
    status = "completed_with_warnings";
end
end

function outcome = blankOutcome(source, pair, channel)
% One row per (channel, pair). List-valued columns are cells, so rows with
% different flag counts concatenate.
outcome = table(string(source.target_kind), source.target_id, ...
    channel.channel_index, channel.recording_channel_id, ...
    string(pair.call_metric), string(pair.normalized_metric), ...
    string(pair.response_metric), string(pair.reference_type), ...
    "not_normalized", "", NaN, "", NaN, NaN, "", {zeros(1, 0)}, {strings(0, 1)}, ...
    NaN, NaN, "", "", "", "", {strings(0, 1)}, NaN, VariableNames=[ ...
    "target_kind", "target_id", "channel_index", "recording_channel_id", ...
    "call_metric", "normalized_metric", "response_metric", "reference_type", ...
    "status", "reason", "value", "unit", "source_derived_measurement_id", ...
    "source_value", "source_unit", "source_band_hz", "source_qc_flags", ...
    "channel_response_estimate_id", "response_value", "response_unit", ...
    "response_qc_status", "response_qc_action", "response_details", ...
    "qc_flags", "derived_measurement_id"]);
end

function outcomes = emptyOutcomes()
outcomes = blankOutcome(struct(target_kind="", target_id=NaN), ...
    struct(call_metric="", normalized_metric="", response_metric="", ...
    reference_type=""), struct(channel_index=NaN, recording_channel_id=NaN));
outcomes(1, :) = [];
end

% -------------------------------------------------------------- evidence ---

function details = derivationDetails(source, response, policy, outcome)
details = struct( ...
    method_key=policy.method_key, ...
    method_version=policy.method_version, ...
    operation=policy.formula, ...
    policy_profile_key=policy.profile_key, ...
    policy_version=policy.version_label, ...
    policy_content_uri=policy.content_uri, ...
    policy_checksum_sha256=policy.checksum_sha256, ...
    calibration_status=policy.calibration_state, ...
    comparability_scope=policy.comparability_scope, ...
    target_kind=source.target_kind, ...
    detection_id=source.detection_id, ...
    consensus_event_id=source.consensus_event_id, ...
    recording_id=source.recording_id, ...
    recording_channel_id=outcome.recording_channel_id, ...
    channel_index=outcome.channel_index, ...
    call_metric=outcome.call_metric, ...
    normalized_metric=outcome.normalized_metric, ...
    source_analysis_run_id=source.analysis_run_id, ...
    source_derived_measurement_id=outcome.source_derived_measurement_id, ...
    source_value=outcome.source_value, ...
    source_unit=outcome.source_unit, ...
    source_band_hz=outcome.source_band_hz{1}, ...
    source_qc_flags=outcome.source_qc_flags{1}(:)', ...
    response_analysis_run_id=response.analysis.analysis_run_id, ...
    channel_response_estimate_id=outcome.channel_response_estimate_id, ...
    response_metric=outcome.response_metric, ...
    reference_type=outcome.reference_type, ...
    response_band_hz=outcome.source_band_hz{1}, ...
    response_value=outcome.response_value, ...
    response_unit=outcome.response_unit, ...
    response_qc_status=outcome.response_qc_status, ...
    response_qc_action=outcome.response_qc_action, ...
    qc_flags=outcome.qc_flags{1}(:)', ...
    unit=outcome.unit);
end

% ----------------------------------------------------------- persistence ---

function [runId, outcomes, action] = persistNormalization(conn, source, response, ...
        policy, outcomes, status, options, repoRoot)
metricRows = resolveNormalizedMetrics(conn, unique(outcomes.normalized_metric));
oldAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
try
    existing = fetch(conn, "SELECT analysis_run_id, run_type, status, " + ...
        "IFNULL(run_label,'') AS run_label, IFNULL(vawlume_version,'') AS vawlume_version, " + ...
        "IFNULL(source_commit,'') AS source_commit, IFNULL(notes,'') AS notes " + ...
        "FROM analysis_runs WHERE project_id=" + string(source.project_id) + ...
        " AND run_key=" + acousticSqlText(options.RunKey));
    if isempty(existing) || height(existing) == 0
        registered = vawlume.db.registerProfileVersion(conn, ...
            struct(project_id=source.project_id), struct( ...
            profile_key=policy.profile_key, profile_name=policy.profile_name, ...
            version_label=policy.version_label, content_path=policy.path, ...
            profile_kind=policy.profile_kind, ...
            profile_schema_version=policy.profile_schema_version, ...
            description=policy.description), RepoRoot=repoRoot);
        runId = acousticInsertRow(conn, "analysis_runs", struct( ...
            project_id=source.project_id, run_type=runType(), ...
            run_key=options.RunKey, run_label=options.RunLabel, ...
            vawlume_version=options.VawlumeVersion, ...
            source_commit=options.SourceCommit, status=status, ...
            completed_at_utc=currentTimestamp(), notes=options.Notes), ...
            "analysis_run_id");
        acousticInsertRow(conn, "analysis_run_profiles", struct( ...
            analysis_run_id=runId, ...
            profile_version_id=registered.profile_version_id, ...
            assignment_role="call_level_normalization_policy"), "inserted_rowid");
        for parent = parentRuns(source, response)'
            acousticInsertRow(conn, "analysis_run_sources", struct( ...
                analysis_run_id=runId, source_analysis_run_id=parent.id, ...
                dependency_role=parent.role), "inserted_rowid");
        end
        for index = find(outcomes.status == "normalized")'
            values = struct(analysis_run_id=runId, ...
                metric_definition_id=metricRows.metric_definition_id( ...
                    metricRows.metric_key == outcomes.normalized_metric(index)));
            values.(source.target_column) = source.target_id;
            values.recording_channel_id = outcomes.recording_channel_id(index);
            values.value_real = outcomes.value(index);
            values.unit = outcomes.unit(index);
            values.derivation_details_json = detailsJson(source, response, ...
                policy, outcomes(index, :));
            outcomes.derived_measurement_id(index) = acousticInsertRow(conn, ...
                "derived_measurements", values, "derived_measurement_id");
        end
        commit(conn);
        action = "created";
    else
        runId = double(existing.analysis_run_id(1));
        assertRunCompatible(existing(1, :), status, options);
        assertPolicyCompatible(conn, runId, policy);
        assertParentsCompatible(conn, runId, source, response);
        outcomes = assertRowsCompatible(conn, runId, source, response, policy, outcomes);
        action = "reused";
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

function parents = parentRuns(source, response)
parents = [struct(id=source.analysis_run_id, role="call_window_measurement"); ...
    struct(id=response.analysis.analysis_run_id, role="channel_response_estimate")];
end

function json = detailsJson(source, response, policy, outcome)
json = string(jsonencode(derivationDetails(source, response, policy, outcome)));
end

function rows = resolveNormalizedMetrics(conn, keys)
quoted = arrayfun(@acousticSqlText, keys);
rows = fetch(conn, "SELECT metric_definition_id, metric_key FROM metric_definitions " + ...
    "WHERE metric_key IN (" + strjoin(quoted, ",") + ")");
if height(rows) ~= numel(keys)
    error("vawlume:acoustic:MetricDefinitionsMissing", ...
        "Normalized metric definitions are missing; run vawlume.db.registerBuiltinSemantics first.");
end
rows.metric_definition_id = double(rows.metric_definition_id);
rows.metric_key = string(rows.metric_key);
end

function assertRunCompatible(row, status, options)
actual = [acousticPresentText(row.run_type(1)), acousticPresentText(row.status(1)), ...
    acousticPresentText(row.run_label(1)), acousticPresentText(row.vawlume_version(1)), ...
    acousticPresentText(row.source_commit(1)), acousticPresentText(row.notes(1))];
expected = [runType(), status, options.RunLabel, ...
    options.VawlumeVersion, options.SourceCommit, options.Notes];
if ~isequal(actual, expected)
    conflict("RunKey '" + options.RunKey + ...
        "' already identifies an analysis run with different provenance or status.");
end
end

function assertPolicyCompatible(conn, runId, policy)
rows = fetch(conn, "SELECT cp.profile_key, cpv.version_label, " + ...
    "IFNULL(cpv.checksum_sha256,'') AS checksum FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id=arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE arp.analysis_run_id=" + string(runId) + ...
    " AND arp.assignment_role='call_level_normalization_policy'");
if isempty(rows) || height(rows) ~= 1 || ...
        acousticPresentText(rows.profile_key(1)) ~= policy.profile_key || ...
        acousticPresentText(rows.version_label(1)) ~= policy.version_label || ...
        acousticPresentText(rows.checksum(1)) ~= policy.checksum_sha256
    conflict("The existing normalization run applied a different policy.");
end
end

function assertParentsCompatible(conn, runId, source, response)
rows = fetch(conn, "SELECT source_analysis_run_id, dependency_role FROM " + ...
    "analysis_run_sources WHERE analysis_run_id=" + string(runId) + ...
    " ORDER BY dependency_role");
expected = parentRuns(source, response);
if isempty(rows) || height(rows) ~= 2 || ...
        ~isequal(string(rows.dependency_role), ["call_window_measurement"; ...
            "channel_response_estimate"]) || ...
        ~isequal(double(rows.source_analysis_run_id), [expected.id]')
    conflict("The existing normalization run has different parent runs.");
end
end

function outcomes = assertRowsCompatible(conn, runId, source, response, policy, outcomes)
rows = fetch(conn, "SELECT dm.derived_measurement_id, md.metric_key, " + ...
    "dm.recording_channel_id, IFNULL(dm." + source.target_column + ",-1) AS target_id, " + ...
    "dm.value_real, IFNULL(dm.unit,'') AS unit, " + ...
    "IFNULL(dm.derivation_details_json,'') AS details FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "WHERE dm.analysis_run_id=" + string(runId));
normalized = find(outcomes.status == "normalized");
if height(rows) ~= numel(normalized)
    conflict("The existing normalization run holds different normalized values.");
end
for index = normalized'
    match = double(rows.recording_channel_id) == outcomes.recording_channel_id(index) & ...
        string(rows.metric_key) == outcomes.normalized_metric(index) & ...
        double(rows.target_id) == source.target_id;
    if sum(match) ~= 1 || ...
            ~isequal(double(rows.value_real(match)), outcomes.value(index)) || ...
            string(rows.unit(match)) ~= outcomes.unit(index) || ...
            string(rows.details(match)) ~= detailsJson(source, response, policy, ...
                outcomes(index, :))
        conflict("The existing normalization run holds different normalized values.");
    end
    outcomes.derived_measurement_id(index) = double(rows.derived_measurement_id(match));
end
end

function conflict(message)
error("vawlume:acoustic:NormalizationRunConflict", "%s", message);
end

function value = currentTimestamp()
value = string(char(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")));
end

function root = resolveRepoRoot(root)
root = string(root);
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
root = string(java.io.File(char(root)).getCanonicalPath());
end
