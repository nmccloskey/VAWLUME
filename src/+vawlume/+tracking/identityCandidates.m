function result = identityCandidates(conn, streamRef, interval, options)
%IDENTITYCANDIDATES Which entities each native track may represent over a window.
%
%   result = VAWLUME.TRACKING.IDENTITYCANDIDATES(conn, streamRef, [start end])
%   result = VAWLUME.TRACKING.IDENTITYCANDIDATES(..., NativeTrackIds="track0")
%
% Answers, for a requested tracking interval: which native tracks are present,
% which canonical entities each may represent, what evidence and score semantics
% apply, whether identity is assigned, ambiguous, unresolved or manually
% reviewed, and what produced the evidence.
%
% **It returns candidates. It never forces one entity.** A track with two
% overlapping candidates comes back with two rows, and a caller that wants one
% answer has to decide that for itself, with the evidence in front of it.
%
% `result.tracks` summarizes each native track present in the window:
%
%   candidate_count      how many distinct entities are proposed
%   resolution           resolved | ambiguous | unresolved | none
%   has_numeric_evidence whether any candidate carries a number at all
%
% `resolution` is derived from what is stored and is not a decision:
%
%   resolved     exactly one candidate entity, none of them rejected
%   ambiguous    more than one candidate entity over the window
%   unresolved   an explicit statement that identity is unknown
%   none         no identity evidence was ever recorded for this track
%
% **`unresolved` and `none` are different findings.** One is a recorded claim
% that nobody knows; the other is that nobody looked. Collapsing them would let
% an unexamined track pass for an examined one.
%
% NO NUMBER IS INVENTED. `identity_value` is NaN wherever the source supplied
% none, and `identity_value_semantics` says what any present number means. A
% manual assertion carries no value, and this function never substitutes one.
%
% POSE CONFIDENCE DOES NOT APPEAR HERE. Whether a keypoint was well localized is
% a different question from which animal a trajectory follows, and the two are
% never derived from one another. Compose this with
% `vawlume.tracking.readWindow` to have both, side by side and still separate.
%
% ALIGNMENT IS NOT CONSULTED. Identity evidence is stated in the tracking
% stream's own native units, and nothing here transforms clocks. A caller
% relating an audio event to identity resolves the clock question through the
% alignment layer, then asks here, so the two uncertainties stay separable.
%
% See also VAWLUME.TRACKING.REGISTERIDENTITYASSOCIATION, VAWLUME.TRACKING.READWINDOW

arguments
    conn
    streamRef (1,1) struct
    interval (1,2) double {mustBeFinite}
    options.NativeTrackIds (1,:) string = string.empty
    options.IncludeRejected (1,1) logical = false
end

if interval(2) < interval(1)
    error("vawlume:tracking:WindowInvalid", ...
        "The requested window ends before it starts: [%g %g].", ...
        interval(1), interval(2));
end

stream = trackingResolveStream(conn, streamRef);

predicates = "ia.external_stream_id=" + string(stream.external_stream_id) + ...
    " AND ia.start_time_native <= " + string(interval(2)) + ...
    " AND ia.end_time_native >= " + string(interval(1));
if ~options.IncludeRejected
    predicates = predicates + " AND ia.assignment_state <> 'rejected'";
end
if ~isempty(options.NativeTrackIds)
    quoted = arrayfun(@trackingSqlText, options.NativeTrackIds);
    predicates = predicates + " AND ia.native_track_id IN (" + ...
        strjoin(quoted, ",") + ")";
end

rows = fetch(conn, "SELECT ia.tracking_identity_association_id, " + ...
    "ia.native_track_id, IFNULL(ia.entity_id, -1) AS entity_id, " + ...
    "IFNULL(e.native_id,'') AS entity_native_id, " + ...
    "ia.start_time_native, ia.end_time_native, ia.assignment_state, " + ...
    "ia.evidence_kind, IFNULL(ia.identity_value, 1e308) AS identity_value, " + ...
    "IFNULL(ia.identity_value_semantics,'') AS identity_value_semantics, " + ...
    "IFNULL(ia.calibration_status,'') AS calibration_status, " + ...
    "IFNULL(ia.review_state,'') AS review_state, " + ...
    "IFNULL(ia.method,'') AS method, " + ...
    "IFNULL(ia.source_file_id, -1) AS source_file_id, " + ...
    "IFNULL(ia.analysis_run_id, -1) AS analysis_run_id " + ...
    "FROM tracking_identity_associations ia " + ...
    "LEFT JOIN experimental_entities e ON e.entity_id=ia.entity_id " + ...
    "WHERE " + predicates + ...
    " ORDER BY ia.native_track_id, ia.start_time_native, ia.entity_id");

result = struct();
result.stream = struct( ...
    external_stream_id=stream.external_stream_id, ...
    stream_name=stream.stream_name, ...
    project_key=stream.project_key);
result.timebase = struct( ...
    timebase_id=stream.timebase_id, ...
    timebase_name=stream.timebase_name);
result.requested_interval = interval;
result.associations = buildAssociations(rows);
result.tracks = summarizeTracks(conn, stream, result.associations, ...
    interval, options);

result.identity_boundary = "Candidates, not decisions. A native track may " + ...
    "have several candidate entities over one interval, and an unresolved " + ...
    "statement is not the same as no evidence.";
result.pose_confidence_note = "Pose/localization confidence is not part of " + ...
    "identity evidence and is never derived from it. Read it from " + ...
    "vawlume.tracking.readWindow.";
end

function value = buildAssociations(rows)
if isempty(rows) || height(rows) == 0
    value = emptyAssociations();
    return
end

entityId = double(rows.entity_id);
entityId(entityId < 0) = NaN;
identityValue = double(rows.identity_value);
identityValue(identityValue == 1e308) = NaN;
sourceFileId = double(rows.source_file_id);
sourceFileId(sourceFileId < 0) = NaN;
analysisRunId = double(rows.analysis_run_id);
analysisRunId(analysisRunId < 0) = NaN;

value = table( ...
    double(rows.tracking_identity_association_id), ...
    trackingPresentText(rows.native_track_id), entityId, ...
    trackingPresentText(rows.entity_native_id), ...
    double(rows.start_time_native), double(rows.end_time_native), ...
    trackingPresentText(rows.assignment_state), ...
    trackingPresentText(rows.evidence_kind), identityValue, ...
    trackingPresentText(rows.identity_value_semantics), ...
    trackingPresentText(rows.calibration_status), ...
    trackingPresentText(rows.review_state), ...
    trackingPresentText(rows.method), sourceFileId, analysisRunId, ...
    VariableNames=associationVariableNames());
end

function tracks = summarizeTracks(conn, stream, associations, interval, options)
%SUMMARIZETRACKS One row per native track present in the window.
%
% Every track the stream contains is listed, including those with no identity
% evidence at all, because "nobody looked" is a finding a caller needs to see.
% Restricting the summary to tracks that happen to have evidence would hide it.
present = fetch(conn, "SELECT DISTINCT native_track_id FROM tracking_series " + ...
    "WHERE external_stream_id=" + string(stream.external_stream_id) + ...
    " ORDER BY native_track_id");
trackIds = trackingPresentText(present.native_track_id);
if ~isempty(options.NativeTrackIds)
    trackIds = trackIds(ismember(trackIds, options.NativeTrackIds));
end

count = numel(trackIds);
candidateCount = zeros(count, 1);
resolution = strings(count, 1);
hasNumeric = false(count, 1);
statePattern = strings(count, 1);

for index = 1:count
    selected = associations(associations.native_track_id == trackIds(index), :);
    entities = unique(selected.entity_id(~isnan(selected.entity_id)));
    candidateCount(index) = numel(entities);
    hasNumeric(index) = any(~isnan(selected.identity_value));
    statePattern(index) = strjoin(unique(selected.assignment_state)', "|");

    if height(selected) == 0
        % No evidence was ever recorded. Distinct from an explicit unresolved
        % statement, and the distinction is load-bearing.
        resolution(index) = "none";
    elseif numel(entities) > 1
        resolution(index) = "ambiguous";
    elseif isscalar(entities)
        resolution(index) = "resolved";
    else
        resolution(index) = "unresolved";
    end
end

tracks = table(trackIds, candidateCount, resolution, hasNumeric, statePattern, ...
    repmat(interval(1), count, 1), repmat(interval(2), count, 1), ...
    VariableNames=["native_track_id", "candidate_count", "resolution", ...
    "has_numeric_evidence", "assignment_states", "window_start_native", ...
    "window_end_native"]);
end

function value = emptyAssociations()
names = associationVariableNames();
types = repmat("double", 1, numel(names));
types(ismember(names, ["native_track_id", "entity_native_id", ...
    "assignment_state", "evidence_kind", "identity_value_semantics", ...
    "calibration_status", "review_state", "method"])) = "string";
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end

function names = associationVariableNames()
names = ["tracking_identity_association_id", "native_track_id", "entity_id", ...
    "entity_native_id", "start_time_native", "end_time_native", ...
    "assignment_state", "evidence_kind", "identity_value", ...
    "identity_value_semantics", "calibration_status", "review_state", ...
    "method", "source_file_id", "analysis_run_id"];
end
