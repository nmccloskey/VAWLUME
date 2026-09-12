function result = estimateChannelResponse(conn, recordingRef, measurementIds, options)
%ESTIMATECHANNELRESPONSE Aggregate exact reference-response evidence.
%
%   result = VAWLUME.ACOUSTIC.ESTIMATECHANNELRESPONSE(conn, recordingRef, ids)
%   result = VAWLUME.ACOUSTIC.ESTIMATECHANNELRESPONSE(..., Apply=true, ...
%       RunKey="session-response-profile")
%
% IDS are explicit derived_measurement_id values produced by acoustic
% reference-response runs. Estimates remain separate by channel, metric,
% reference_type, and declared frequency band. The initial aggregation is a
% median with transparent descriptive statistics and declared QC policy.
%
% This operation produces uncalibrated response/QC evidence. It does not apply
% a gain correction, normalize call windows, select a channel, or infer callers.

arguments
    conn
    recordingRef (1,1) struct
    measurementIds double
    options.RequiredReferenceTypes (1,:) string = strings(1, 0)
    options.MinReferences (1,1) double = 2
    options.DivergenceRelativeThreshold (1,1) double = 0.25
    options.IncludeWarningSources (1,1) logical = false
    options.IncludeFailedSources (1,1) logical = false
    options.AggregationMethod (1,1) string = "median"
    options.SettingsProfileVersionId (1,1) double = NaN
    options.Apply (1,1) logical = false
    options.RunKey (1,1) string = ""
    options.RunLabel (1,1) string = ""
    options.VawlumeVersion (1,1) string = ""
    options.SourceCommit (1,1) string = ""
    options.Notes (1,1) string = ""
end

validatePolicy(measurementIds, options);
recording = acousticResolveRecording(conn, recordingRef);
settingsProfile = resolveSettingsProfile(conn, recording.project_id, ...
    options.SettingsProfileVersionId);
sourceRows = resolveMeasurements(conn, recording.recording_id, measurementIds);
[estimates, excluded] = aggregateMeasurements(sourceRows, options, settingsProfile);
profileStatus = profileRunStatus(estimates);

analysisRunId = NaN;
estimateIds = zeros(0, 1);
action = "planned";
if options.Apply
    if ismissing(options.RunKey) || strlength(options.RunKey) == 0
        error("vawlume:acoustic:ResponseRunKeyRequired", ...
            "RunKey is required when Apply=true.");
    end
    [analysisRunId, estimateIds, action] = persistProfile(conn, recording, ...
        estimates, profileStatus, settingsProfile, options);
end

result = struct( ...
    analysis_run_id=analysisRunId, ...
    recording_id=recording.recording_id, ...
    status=profileStatus, ...
    qc_flags=profileQcFlags(estimates), ...
    estimates=estimateTable(estimates), ...
    source_measurements=sourceRows, ...
    excluded_measurements=excluded, ...
    aggregation_method="median", ...
    aggregation_version="1.0.0", ...
    settings_profile_version_id=settingsProfile.profile_version_id, ...
    channel_response_estimate_ids=estimateIds, ...
    action=action);
end

function validatePolicy(ids, options)
if isempty(ids) || ~isvector(ids) || any(~isfinite(ids)) || any(ids < 1) || any(ids ~= floor(ids)) || ...
        numel(unique(ids)) ~= numel(ids)
    error("vawlume:acoustic:ResponseMeasurementsInvalid", ...
        "measurementIds must be a nonempty vector of unique positive integers.");
end
if options.AggregationMethod ~= "median"
    error("vawlume:acoustic:AggregationMethodUnsupported", ...
        "Phase 2.7 supports only the transparent median aggregation method.");
end
if ~isfinite(options.MinReferences) || options.MinReferences < 1 || ...
        options.MinReferences ~= floor(options.MinReferences)
    error("vawlume:acoustic:ResponsePolicyInvalid", ...
        "MinReferences must be a positive integer.");
end
if ~isfinite(options.DivergenceRelativeThreshold) || ...
        options.DivergenceRelativeThreshold < 0
    error("vawlume:acoustic:ResponsePolicyInvalid", ...
        "DivergenceRelativeThreshold must be finite and nonnegative.");
end
types = options.RequiredReferenceTypes;
if any(ismissing(types) | strlength(types) == 0) || ...
        numel(unique(types)) ~= numel(types)
    error("vawlume:acoustic:ResponsePolicyInvalid", ...
        "RequiredReferenceTypes must contain unique nonempty values.");
end
if ~isnan(options.SettingsProfileVersionId) && ...
        (~isfinite(options.SettingsProfileVersionId) || ...
         options.SettingsProfileVersionId < 1 || ...
         options.SettingsProfileVersionId ~= floor(options.SettingsProfileVersionId))
    error("vawlume:acoustic:ResponsePolicyInvalid", ...
        "SettingsProfileVersionId must be a positive integer when supplied.");
end
end

function profile = resolveSettingsProfile(conn, projectId, profileVersionId)
profile = struct(profile_version_id=NaN, profile_key="", version_label="", ...
    content_uri="", checksum_sha256="");
if isnan(profileVersionId)
    return
end
rows = fetch(conn, "SELECT cpv.profile_version_id, cp.profile_key, " + ...
    "cp.profile_kind, IFNULL(cp.project_id,-1) AS project_id, cpv.version_label, " + ...
    "cpv.content_uri, IFNULL(cpv.checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM config_profile_versions cpv JOIN config_profiles cp " + ...
    "ON cp.profile_id=cpv.profile_id WHERE cpv.profile_version_id=" + ...
    string(profileVersionId));
if isempty(rows) || height(rows) == 0
    error("vawlume:acoustic:ResponseSettingsProfileNotFound", ...
        "No settings profile version %d exists.", profileVersionId);
end
if acousticPresentText(rows.profile_kind(1)) ~= "analysis_settings"
    error("vawlume:acoustic:ResponseSettingsProfileKindInvalid", ...
        "Settings profile version %d has kind '%s', not analysis_settings.", ...
        profileVersionId, acousticPresentText(rows.profile_kind(1)));
end
profileProject = double(rows.project_id(1));
if profileProject >= 0 && profileProject ~= projectId
    error("vawlume:acoustic:ResponseSettingsProfileScopeMismatch", ...
        "Settings profile version %d belongs to another project.", profileVersionId);
end
profile = struct(profile_version_id=double(rows.profile_version_id(1)), ...
    profile_key=acousticPresentText(rows.profile_key(1)), ...
    version_label=acousticPresentText(rows.version_label(1)), ...
    content_uri=acousticPresentText(rows.content_uri(1)), ...
    checksum_sha256=acousticPresentText(rows.checksum_sha256(1)));
end

function rows = resolveMeasurements(conn, recordingId, ids)
idList = strjoin(string(sort(ids(:))), ",");
rows = fetch(conn, "SELECT dm.derived_measurement_id, dm.metric_definition_id, " + ...
    "md.metric_key, IFNULL(md.canonical_unit,'') AS canonical_unit, " + ...
    "dm.value_real, IFNULL(dm.unit,'') AS unit, " + ...
    "IFNULL(dm.derivation_details_json,'') AS derivation_details_json, " + ...
    "dm.recording_channel_id, rc.channel_index, " + ...
    "IFNULL(rc.channel_label,'') AS channel_label, ar.acoustic_reference_id, " + ...
    "ar.reference_key, ar.reference_type, ar.start_time_s, ar.end_time_s, " + ...
    "IFNULL(ar.frequency_min_hz,-1) AS frequency_min_hz, " + ...
    "IFNULL(ar.frequency_max_hz,-1) AS frequency_max_hz, ar.recording_id, " + ...
    "sr.analysis_run_id AS source_analysis_run_id, sr.run_key AS source_run_key, " + ...
    "sr.run_type AS source_run_type, sr.status AS source_run_status " + ...
    "FROM derived_measurements dm " + ...
    "JOIN metric_definitions md ON md.metric_definition_id=dm.metric_definition_id " + ...
    "JOIN acoustic_references ar ON ar.acoustic_reference_id=dm.acoustic_reference_id " + ...
    "JOIN recording_channels rc ON rc.recording_channel_id=dm.recording_channel_id " + ...
    "JOIN analysis_runs sr ON sr.analysis_run_id=dm.analysis_run_id " + ...
    "WHERE dm.derived_measurement_id IN (" + idList + ...
    ") ORDER BY dm.derived_measurement_id");
if height(rows) ~= numel(ids)
    error("vawlume:acoustic:ResponseMeasurementNotFound", ...
        "Every measurement ID must resolve to acoustic-reference/channel evidence.");
end
numeric = ["derived_measurement_id", "metric_definition_id", "value_real", ...
    "recording_channel_id", "channel_index", "acoustic_reference_id", ...
    "start_time_s", "end_time_s", "frequency_min_hz", ...
    "frequency_max_hz", "recording_id", "source_analysis_run_id"];
for name = numeric
    rows.(name) = double(rows.(name));
end
for name = ["frequency_min_hz", "frequency_max_hz"]
    rows.(name)(rows.(name) < 0) = NaN;
end
textNames = ["metric_key", "canonical_unit", "unit", ...
    "derivation_details_json", "channel_label", "reference_key", ...
    "reference_type", "source_run_key", "source_run_type", "source_run_status"];
for name = textNames
    rows.(name) = string(rows.(name));
end
if any(rows.recording_id ~= recordingId)
    error("vawlume:acoustic:ResponseMeasurementScopeMismatch", ...
        "All measurements must belong to the selected recording.");
end
if any(rows.source_run_type ~= "acoustic_reference_response")
    error("vawlume:acoustic:ResponseMeasurementKindInvalid", ...
        "All source measurements must come from acoustic_reference_response runs.");
end
if any(rows.unit ~= rows.canonical_unit)
    error("vawlume:acoustic:ResponseMeasurementUnitInvalid", ...
        "Every source measurement unit must equal its registered canonical unit.");
end
rows.method_signature = strings(height(rows), 1);
for index = 1:height(rows)
    rows.method_signature(index) = measurementMethodSignature( ...
        rows.derivation_details_json(index));
end
end

function signature = measurementMethodSignature(detailsJson)
try
    details = jsondecode(detailsJson);
    required = ["method_key", "method_version", "sample_semantics", ...
        "interval_semantics"];
    values = strings(1, numel(required));
    for index = 1:numel(required)
        field = char(required(index));
        if ~isfield(details, field)
            error("missing");
        end
        values(index) = string(details.(field));
    end
    signature = strjoin(values, "|");
catch
    error("vawlume:acoustic:ResponseMeasurementProvenanceInvalid", ...
        "Every source measurement must contain readable Phase 2.6 method provenance.");
end
end

function [estimates, excluded] = aggregateMeasurements(rows, options, settingsProfile)
activeMask = rows.source_run_status == "completed" | ...
    (options.IncludeWarningSources & rows.source_run_status == "completed_with_warnings") | ...
    (options.IncludeFailedSources & rows.source_run_status == "failed");
excluded = rows(~activeMask, :);
active = rows(activeMask, :);

scope = unique(rows(:, ["recording_channel_id", "channel_index", ...
    "channel_label", "metric_definition_id", "metric_key", "unit", ...
    "frequency_min_hz", "frequency_max_hz"]), "rows", "stable");
scope = sortrows(scope, ["channel_index", "metric_key", ...
    "frequency_min_hz", "frequency_max_hz"]);
estimates = repmat(emptyEstimate(), 0, 1);
nextIndex = 0;
for scopeIndex = 1:height(scope)
    scopeMaskAll = matchesScope(rows, scope(scopeIndex, :));
    presentTypes = sort(unique(rows.reference_type(scopeMaskAll)));
    if isempty(options.RequiredReferenceTypes)
        types = presentTypes;
    else
        types = sort(options.RequiredReferenceTypes(:));
    end
    for typeIndex = 1:numel(types)
        nextIndex = nextIndex + 1;
        type = types(typeIndex);
        allMask = scopeMaskAll & rows.reference_type == type;
        activeMaskForGroup = matchesScope(active, scope(scopeIndex, :)) & ...
            active.reference_type == type;
        groupAll = rows(allMask, :);
        group = active(activeMaskForGroup, :);
        item = emptyEstimate();
        item.estimate_key = "estimate-" + compose("%04d", nextIndex);
        item.recording_channel_id = double(scope.recording_channel_id(scopeIndex));
        item.channel_index = double(scope.channel_index(scopeIndex));
        item.channel_label = string(scope.channel_label(scopeIndex));
        item.metric_definition_id = double(scope.metric_definition_id(scopeIndex));
        item.metric_key = string(scope.metric_key(scopeIndex));
        item.reference_type = type;
        item.frequency_min_hz = double(scope.frequency_min_hz(scopeIndex));
        item.frequency_max_hz = double(scope.frequency_max_hz(scopeIndex));
        item.unit = string(scope.unit(scopeIndex));
        item.aggregation_method = "median";
        item.aggregation_version = "1.0.0";
        item.source_measurement_ids = double(group.derived_measurement_id(:))';
        item.source_analysis_run_ids = double(group.source_analysis_run_id(:))';
        item.source_reference_ids = double(group.acoustic_reference_id(:))';
        item.excluded_measurement_ids = double(setdiff( ...
            groupAll.derived_measurement_id, group.derived_measurement_id, "stable"))';
        values = double(group.value_real);
        item.n_measurements = numel(values);
        item.n_references = numel(unique(group.acoustic_reference_id));
        item.qc_flags = strings(0, 1);
        if isempty(groupAll)
            item.qc_flags(end + 1, 1) = "missing_reference_family";
        elseif isempty(group)
            item.qc_flags(end + 1, 1) = "all_sources_excluded";
        end
        if item.n_references < options.MinReferences
            item.qc_flags(end + 1, 1) = "insufficient_reference_count";
        end
        if ~isempty(group) && ~isscalar(unique(group.method_signature))
            item.qc_flags(end + 1, 1) = "incompatible_measurement_methods";
        end
        if any(group.source_run_status ~= "completed")
            item.qc_flags(end + 1, 1) = "included_source_qc_warning";
        end
        if any(group.source_run_status == "failed")
            item.qc_flags(end + 1, 1) = "included_failed_source";
        end
        if ~isempty(values)
            item.value_real = median(values);
            item.mean_value = mean(values);
            if numel(values) > 1
                item.standard_deviation = std(values, 0);
            else
                item.standard_deviation = 0;
            end
            item.minimum_value = min(values);
            item.maximum_value = max(values);
            item.relative_range = relativeSpread(values);
            if item.relative_range > options.DivergenceRelativeThreshold
                item.qc_flags(end + 1, 1) = "within_family_divergence";
            end
        end
        estimates(end + 1, 1) = item; %#ok<AGROW>
    end
end

estimates = markUnpairedChannels(estimates);
estimates = markReferenceTypeDivergence(estimates, ...
    options.DivergenceRelativeThreshold);
for index = 1:numel(estimates)
    estimates(index).qc_flags = unique(estimates(index).qc_flags, "stable");
    estimates(index).qc_status = qcStatus(estimates(index).qc_flags);
    estimates(index).details_json = estimateDetails(estimates(index), options, ...
        settingsProfile);
end
end

function mask = matchesScope(rows, scope)
if isempty(rows)
    mask = false(0, 1);
    return
end
mask = rows.recording_channel_id == double(scope.recording_channel_id(1)) & ...
    rows.metric_definition_id == double(scope.metric_definition_id(1)) & ...
    rows.unit == string(scope.unit(1)) & ...
    sameNullable(rows.frequency_min_hz, double(scope.frequency_min_hz(1))) & ...
    sameNullable(rows.frequency_max_hz, double(scope.frequency_max_hz(1)));
end

function mask = sameNullable(values, target)
mask = values == target | (isnan(values) & isnan(target));
end

function estimates = markUnpairedChannels(estimates)
for index = 1:numel(estimates)
    peers = find(arrayfun(@(item) ...
        item.metric_definition_id == estimates(index).metric_definition_id && ...
        item.reference_type == estimates(index).reference_type && ...
        sameScalar(item.frequency_min_hz, estimates(index).frequency_min_hz) && ...
        sameScalar(item.frequency_max_hz, estimates(index).frequency_max_hz), estimates));
    channels = unique([estimates(peers).recording_channel_id]);
    if numel(channels) < 2
        continue
    end
    baseline = sort(unique(estimates(peers(1)).source_reference_ids));
    comparable = true;
    for peer = peers(:)'
        if ~isequal(sort(unique(estimates(peer).source_reference_ids)), baseline)
            comparable = false;
            break
        end
    end
    if ~comparable
        for peer = peers(:)'
            estimates(peer).qc_flags(end + 1, 1) = "unpaired_channel_references";
        end
    end
end
end

function estimates = markReferenceTypeDivergence(estimates, threshold)
for index = 1:numel(estimates)
    peers = find(arrayfun(@(item) ...
        item.recording_channel_id == estimates(index).recording_channel_id && ...
        item.metric_definition_id == estimates(index).metric_definition_id && ...
        sameScalar(item.frequency_min_hz, estimates(index).frequency_min_hz) && ...
        sameScalar(item.frequency_max_hz, estimates(index).frequency_max_hz) && ...
        ~isnan(item.value_real), estimates));
    types = unique(string({estimates(peers).reference_type}));
    if numel(types) > 1 && relativeSpread([estimates(peers).value_real]) > threshold
        for peer = peers(:)'
            estimates(peer).qc_flags(end + 1, 1) = "reference_type_divergence";
        end
    end
end
end

function value = relativeSpread(values)
values = double(values(:));
if isempty(values) || isscalar(values)
    value = 0;
    return
end
denominator = median(abs(values));
rangeValue = max(values) - min(values);
if denominator == 0
    if rangeValue == 0
        value = 0;
    else
        value = Inf;
    end
else
    value = rangeValue / denominator;
end
end

function tf = sameScalar(a, b)
tf = (a == b) || (isnan(a) && isnan(b));
end

function status = qcStatus(flags)
if any(flags == "incompatible_measurement_methods") || ...
        any(flags == "unpaired_channel_references")
    status = "not_comparable";
elseif any(flags == "included_source_qc_warning")
    status = "source_qc_warning";
elseif any(flags == "missing_reference_family") || ...
        any(flags == "all_sources_excluded") || ...
        any(flags == "insufficient_reference_count")
    status = "insufficient_evidence";
elseif any(flags == "within_family_divergence") || ...
        any(flags == "reference_type_divergence")
    status = "divergent";
else
    status = "ok";
end
end

function json = estimateDetails(item, options, settingsProfile)
details = struct( ...
    profile_method="vawlume.acoustic.channel_response_estimate", ...
    profile_version="1.0.0", ...
    aggregation_method=item.aggregation_method, ...
    aggregation_version=item.aggregation_version, ...
    min_references=options.MinReferences, ...
    divergence_relative_threshold=options.DivergenceRelativeThreshold, ...
    include_warning_sources=options.IncludeWarningSources, ...
    include_failed_sources=options.IncludeFailedSources, ...
    required_reference_types=options.RequiredReferenceTypes(:)', ...
    settings_profile_version_id=settingsProfile.profile_version_id, ...
    settings_profile_key=settingsProfile.profile_key, ...
    settings_profile_version=settingsProfile.version_label, ...
    settings_profile_content_uri=settingsProfile.content_uri, ...
    settings_profile_checksum_sha256=settingsProfile.checksum_sha256, ...
    metric_key=item.metric_key, ...
    reference_type=item.reference_type, ...
    frequency_band_hz=[item.frequency_min_hz item.frequency_max_hz], ...
    n_measurements=item.n_measurements, ...
    n_references=item.n_references, ...
    median_value=item.value_real, ...
    mean_value=item.mean_value, ...
    standard_deviation=item.standard_deviation, ...
    minimum_value=item.minimum_value, ...
    maximum_value=item.maximum_value, ...
    relative_range=item.relative_range, ...
    source_measurement_ids=item.source_measurement_ids, ...
    source_reference_ids=item.source_reference_ids, ...
    excluded_measurement_ids=item.excluded_measurement_ids, ...
    qc_flags=item.qc_flags(:)');
json = string(jsonencode(details));
end

function status = profileRunStatus(estimates)
statuses = string({estimates.qc_status});
if any(statuses == "not_comparable")
    status = "failed";
elseif all(statuses == "ok")
    status = "completed";
else
    status = "completed_with_warnings";
end
end

function flags = profileQcFlags(estimates)
flags = strings(0, 1);
for index = 1:numel(estimates)
    flags = [flags; estimates(index).qc_flags(:)]; %#ok<AGROW>
end
flags = unique(flags, "stable");
end

function [runId, estimateIds, action] = persistProfile(conn, recording, ...
        estimates, status, settingsProfile, options)
oldAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
try
    existing = fetch(conn, "SELECT analysis_run_id, run_type, status, " + ...
        "IFNULL(run_label,'') AS run_label, IFNULL(vawlume_version,'') AS vawlume_version, " + ...
        "IFNULL(source_commit,'') AS source_commit, IFNULL(notes,'') AS notes " + ...
        "FROM analysis_runs WHERE project_id=" + string(recording.project_id) + ...
        " AND run_key=" + acousticSqlText(options.RunKey));
    if isempty(existing) || height(existing) == 0
        runId = acousticInsertRow(conn, "analysis_runs", struct( ...
            project_id=recording.project_id, ...
            run_type="acoustic_channel_response_estimate", ...
            run_key=options.RunKey, run_label=options.RunLabel, ...
            vawlume_version=options.VawlumeVersion, ...
            source_commit=options.SourceCommit, status=status, ...
            completed_at_utc=currentTimestamp(), notes=options.Notes), ...
            "analysis_run_id");
        if ~isnan(settingsProfile.profile_version_id)
            insertJunction(conn, "analysis_run_profiles", struct( ...
                analysis_run_id=runId, ...
                profile_version_id=settingsProfile.profile_version_id, ...
                assignment_role="response_aggregation_policy"));
        end
        sourceRunIds = profileSourceRunIds(estimates);
        for sourceRunId = sourceRunIds
            insertJunction(conn, "analysis_run_sources", struct( ...
                analysis_run_id=runId, source_analysis_run_id=sourceRunId, ...
                dependency_role="reference_response_measurement"));
        end
        estimateIds = insertEstimates(conn, runId, recording.recording_id, estimates);
        commit(conn);
        action = "created";
    else
        runId = double(existing.analysis_run_id(1));
        assertRunCompatible(existing(1, :), status, options);
        assertProfileAssignmentCompatible(conn, runId, settingsProfile);
        assertSourceRunsCompatible(conn, runId, estimates);
        estimateIds = assertEstimatesCompatible(conn, runId, recording.recording_id, estimates);
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

function ids = profileSourceRunIds(estimates)
ids = zeros(1, 0);
for index = 1:numel(estimates)
    ids = [ids estimates(index).source_analysis_run_ids]; %#ok<AGROW>
end
ids = sort(unique(ids));
end

function ids = insertEstimates(conn, runId, recordingId, estimates)
ids = zeros(numel(estimates), 1);
for index = 1:numel(estimates)
    item = estimates(index);
    values = struct(analysis_run_id=runId, recording_id=recordingId, ...
        recording_channel_id=item.recording_channel_id, ...
        metric_definition_id=item.metric_definition_id, ...
        estimate_key=item.estimate_key, reference_type=item.reference_type, ...
        aggregation_method=item.aggregation_method, ...
        aggregation_version=item.aggregation_version, ...
        qc_status=item.qc_status, unit=item.unit, ...
        details_json=item.details_json);
    if ~isnan(item.frequency_min_hz)
        values.frequency_min_hz = item.frequency_min_hz;
    end
    if ~isnan(item.frequency_max_hz)
        values.frequency_max_hz = item.frequency_max_hz;
    end
    if ~isnan(item.value_real)
        values.value_real = item.value_real;
    end
    ids(index) = acousticInsertRow(conn, "channel_response_estimates", ...
        values, "channel_response_estimate_id");
    for measurementId = item.source_measurement_ids
        insertJunction(conn, "channel_response_estimate_sources", struct( ...
            channel_response_estimate_id=ids(index), ...
            derived_measurement_id=measurementId));
    end
end
end

function insertJunction(conn, tableName, values)
names = fieldnames(values);
row = struct();
for index = 1:numel(names)
    value = values.(names{index});
    if isstring(value) || ischar(value)
        row.(names{index}) = {char(string(value))};
    else
        row.(names{index}) = double(value);
    end
end
sqlwrite(conn, char(tableName), struct2table(row, "AsArray", true));
end

function assertRunCompatible(row, status, options)
actual = [acousticPresentText(row.run_type(1)), acousticPresentText(row.status(1)), ...
    acousticPresentText(row.run_label(1)), acousticPresentText(row.vawlume_version(1)), ...
    acousticPresentText(row.source_commit(1)), acousticPresentText(row.notes(1))];
expected = ["acoustic_channel_response_estimate", status, options.RunLabel, ...
    options.VawlumeVersion, options.SourceCommit, options.Notes];
if ~isequal(actual, expected)
    profileConflict(options.RunKey);
end
end

function assertProfileAssignmentCompatible(conn, runId, settingsProfile)
rows = fetch(conn, "SELECT profile_version_id FROM analysis_run_profiles " + ...
    "WHERE analysis_run_id=" + string(runId) + ...
    " AND assignment_role='response_aggregation_policy'");
if isnan(settingsProfile.profile_version_id)
    compatible = isempty(rows) || height(rows) == 0;
else
    compatible = height(rows) == 1 && ...
        double(rows.profile_version_id(1)) == settingsProfile.profile_version_id;
end
if ~compatible
    error("vawlume:acoustic:ResponseProfileConflict", ...
        "The existing response profile has a different settings-profile assignment.");
end
end

function assertSourceRunsCompatible(conn, runId, estimates)
rows = fetch(conn, "SELECT source_analysis_run_id, dependency_role FROM " + ...
    "analysis_run_sources WHERE analysis_run_id=" + string(runId) + ...
    " ORDER BY source_analysis_run_id");
expected = profileSourceRunIds(estimates);
if isempty(rows)
    actual = zeros(1, 0);
    rolesMatch = isempty(expected);
else
    actual = sort(double(rows.source_analysis_run_id(:)))';
    rolesMatch = all(string(rows.dependency_role) == ...
        "reference_response_measurement");
end
if ~isequal(actual, expected) || ~rolesMatch
    error("vawlume:acoustic:ResponseProfileConflict", ...
        "The existing response profile has different source-analysis lineage.");
end
end

function ids = assertEstimatesCompatible(conn, runId, recordingId, estimates)
rows = fetch(conn, "SELECT channel_response_estimate_id, estimate_key, " + ...
    "recording_id, recording_channel_id, metric_definition_id, reference_type, " + ...
    "aggregation_method, aggregation_version, IFNULL(frequency_min_hz,-1) AS frequency_min_hz, " + ...
    "IFNULL(frequency_max_hz,-1) AS frequency_max_hz, qc_status, " + ...
    "IFNULL(value_real,-1.7976931348623157e308) AS value_real, unit, details_json " + ...
    "FROM channel_response_estimates WHERE analysis_run_id=" + string(runId) + ...
    " ORDER BY estimate_key");
if height(rows) ~= numel(estimates)
    profileConflict("");
end
ids = zeros(numel(estimates), 1);
for index = 1:numel(estimates)
    item = estimates(index);
    row = rows(index, :);
    actualValue = double(row.value_real(1));
    if actualValue == -realmax
        actualValue = NaN;
    end
    actualMin = nullableStored(row.frequency_min_hz(1));
    actualMax = nullableStored(row.frequency_max_hz(1));
    compatible = double(row.recording_id(1)) == recordingId && ...
        double(row.recording_channel_id(1)) == item.recording_channel_id && ...
        double(row.metric_definition_id(1)) == item.metric_definition_id && ...
        acousticPresentText(row.estimate_key(1)) == item.estimate_key && ...
        acousticPresentText(row.reference_type(1)) == item.reference_type && ...
        acousticPresentText(row.aggregation_method(1)) == item.aggregation_method && ...
        acousticPresentText(row.aggregation_version(1)) == item.aggregation_version && ...
        isequaln(actualMin, item.frequency_min_hz) && ...
        isequaln(actualMax, item.frequency_max_hz) && ...
        acousticPresentText(row.qc_status(1)) == item.qc_status && ...
        isequaln(actualValue, item.value_real) && ...
        acousticPresentText(row.unit(1)) == item.unit && ...
        acousticPresentText(row.details_json(1)) == item.details_json;
    if ~compatible
        profileConflict("");
    end
    id = double(row.channel_response_estimate_id(1));
    sources = fetch(conn, "SELECT derived_measurement_id FROM " + ...
        "channel_response_estimate_sources WHERE channel_response_estimate_id=" + ...
        string(id) + " ORDER BY derived_measurement_id");
    if isempty(sources)
        actualSources = zeros(1, 0);
    else
        actualSources = sort(double(sources.derived_measurement_id(:)))';
    end
    if ~isequal(actualSources, sort(item.source_measurement_ids))
        profileConflict("");
    end
    ids(index) = id;
end
end

function profileConflict(runKey)
if strlength(runKey) > 0
    message = "RunKey '" + runKey + "' already identifies a different response profile.";
else
    message = "The existing response profile differs from the requested deterministic result.";
end
error("vawlume:acoustic:ResponseProfileConflict", "%s", message);
end

function value = nullableStored(raw)
value = double(raw);
if value < 0
    value = NaN;
end
end

function value = currentTimestamp()
value = string(char(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")));
end

function tableValue = estimateTable(estimates)
n = numel(estimates);
tableValue = table(Size=[n 20], VariableTypes=[ ...
    "string", "double", "double", "string", "double", "string", "string", ...
    "double", "double", "string", "string", "string", "double", "double", ...
    "double", "double", "double", "double", "cell", "cell"], ...
    VariableNames=["estimate_key", "recording_channel_id", "channel_index", ...
    "channel_label", "metric_definition_id", "metric_key", "reference_type", ...
    "frequency_min_hz", "frequency_max_hz", "unit", "qc_status", ...
    "aggregation_method", "value_real", "n_measurements", "n_references", ...
    "standard_deviation", "relative_range", "mean_value", "qc_flags", ...
    "source_measurement_ids"]);
for index = 1:n
    item = estimates(index);
    for name = ["estimate_key", "recording_channel_id", "channel_index", ...
            "channel_label", "metric_definition_id", "metric_key", "reference_type", ...
            "frequency_min_hz", "frequency_max_hz", "unit", "qc_status", ...
            "aggregation_method", "value_real", "n_measurements", "n_references", ...
            "standard_deviation", "relative_range", "mean_value"]
        tableValue.(name)(index) = item.(name);
    end
    tableValue.qc_flags{index} = item.qc_flags;
    tableValue.source_measurement_ids{index} = item.source_measurement_ids;
end
end

function item = emptyEstimate()
item = struct( ...
    estimate_key="", recording_channel_id=NaN, channel_index=NaN, ...
    channel_label="", metric_definition_id=NaN, metric_key="", ...
    reference_type="", frequency_min_hz=NaN, frequency_max_hz=NaN, ...
    unit="", aggregation_method="median", aggregation_version="1.0.0", ...
    qc_status="", value_real=NaN, mean_value=NaN, standard_deviation=NaN, ...
    minimum_value=NaN, maximum_value=NaN, relative_range=NaN, ...
    n_measurements=0, n_references=0, source_measurement_ids=zeros(1, 0), ...
    source_analysis_run_ids=zeros(1, 0), ...
    source_reference_ids=zeros(1, 0), excluded_measurement_ids=zeros(1, 0), ...
    qc_flags=strings(0, 1), details_json="");
end
