function plan = matchingBuildPlan(conn, recordingRef, runPair, matchSpec, repoRoot)
%MATCHINGBUILDPLAN Resolve and classify one deterministic candidate analysis.

repoRoot = resolveRepoRoot(repoRoot);
plan = struct();
plan.context = validateMatchSpec(matchSpec);
plan.specification = matchingLoadSpec(plan.context.profile_path, repoRoot);
plan.recording = resolveRecording(conn, recordingRef);
plan.run_pair = resolveRunPair(conn, plan.recording, runPair);

runA = detectionGeometry(conn, plan.recording.recording_id, ...
    plan.run_pair.run_a.extraction_run_id, "run_a");
runB = detectionGeometry(conn, plan.recording.recording_id, ...
    plan.run_pair.run_b.extraction_run_id, "run_b");
plan.detections = struct(run_a=runA, run_b=runB);
[plan.candidates, plan.unmatched] = matchingGenerateCandidates( ...
    runA, runB, plan.run_pair, plan.specification.min_temporal_iou);
[plan.groups, plan.group_members, plan.consensus_events, ...
    plan.consensus_event_members] = matchingBuildGroups( ...
    runA, runB, plan.candidates);

plan.configuration = resolveConfiguration(conn, plan.recording.project_id, ...
    plan.specification);
plan.analysis = resolveAnalysis(conn, plan);
plan = matchingResolveDerivedGraph(conn, plan);
plan.conflicts = strings(0, 1);
plan = appendConflict(plan, plan.configuration.conflict_message);
plan = appendConflict(plan, plan.analysis.conflict_message);
plan.has_conflicts = ~isempty(plan.conflicts);
end

function context = validateMatchSpec(matchSpec)
if ~isfield(matchSpec, "run_key")
    error("vawlume:matching:MatchSpecInvalid", ...
        "matchSpec.run_key is required and identifies the immutable analysis.");
end
context = struct( ...
    run_key=scalarText(matchSpec.run_key, "matchSpec.run_key"), ...
    run_label=optionalText(matchSpec, "run_label"), ...
    vawlume_version=optionalText(matchSpec, "vawlume_version"), ...
    source_commit=optionalText(matchSpec, "source_commit"), ...
    notes=optionalText(matchSpec, "notes"), ...
    profile_path=optionalText(matchSpec, "profile_path"));
if strlength(context.run_key) == 0
    error("vawlume:matching:MatchSpecInvalid", ...
        "matchSpec.run_key must be a nonempty scalar text value.");
end
end

function recording = resolveRecording(conn, recordingRef)
hasId = isfield(recordingRef, "recording_id");
hasPortable = isfield(recordingRef, "project_key") && ...
    isfield(recordingRef, "source_relative_path");
if hasId == hasPortable
    error("vawlume:matching:RecordingRefInvalid", ...
        "recordingRef must contain exactly one selector: recording_id, or " + ...
        "project_key plus source_relative_path.");
end
if hasId
    id = scalarPositiveInteger(recordingRef.recording_id, "recording_id");
    rows = fetch(conn, "SELECT r.recording_id, r.project_id, p.project_key, " + ...
        "IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
        "IFNULL(sf.relative_path,'') AS source_relative_path " + ...
        "FROM recordings r JOIN projects p ON p.project_id=r.project_id " + ...
        "JOIN source_files sf ON sf.source_file_id=r.source_file_id " + ...
        "WHERE r.recording_id=" + string(id));
else
    projectKey = scalarText(recordingRef.project_key, "project_key");
    relativePath = scalarText(recordingRef.source_relative_path, ...
        "source_relative_path");
    rows = fetch(conn, "SELECT r.recording_id, r.project_id, p.project_key, " + ...
        "IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
        "IFNULL(sf.relative_path,'') AS source_relative_path " + ...
        "FROM recordings r JOIN projects p ON p.project_id=r.project_id " + ...
        "JOIN source_files sf ON sf.source_file_id=r.source_file_id " + ...
        "WHERE p.project_key=" + sqlText(projectKey) + ...
        " AND sf.relative_path=" + sqlText(relativePath));
end
if isempty(rows) || height(rows) == 0
    error("vawlume:matching:RecordingNotFound", ...
        "No established recording matches recordingRef.");
end
if height(rows) ~= 1
    error("vawlume:matching:RecordingAmbiguous", ...
        "recordingRef matched %d recordings; exactly one is required.", height(rows));
end
recording = struct( ...
    recording_id=double(rows.recording_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    project_key=presentText(rows.project_key(1)), ...
    native_recording_id=presentText(rows.native_recording_id(1)), ...
    source_relative_path=presentText(rows.source_relative_path(1)));
end

function pair = resolveRunPair(conn, recording, runPair)
if ~isfield(runPair, "run_a") || ~isfield(runPair, "run_b")
    error("vawlume:matching:RunPairInvalid", ...
        "runPair must explicitly contain run_a and run_b.");
end
pair = struct( ...
    run_a=resolveRun(conn, recording, runPair.run_a, "run_a"), ...
    run_b=resolveRun(conn, recording, runPair.run_b, "run_b"));
if pair.run_a.extraction_run_id == pair.run_b.extraction_run_id
    error("vawlume:matching:SameExtractionRun", ...
        "run_a and run_b must be different extraction runs.");
end
if pair.run_a.extractor_id == pair.run_b.extractor_id
    error("vawlume:matching:SameExtractor", ...
        "run_a and run_b must come from different extractors for Phase 6.");
end
end

function run = resolveRun(conn, recording, reference, role)
[mode, value] = normalizeRunRef(reference, role);
if mode == "id"
    predicate = "er.extraction_run_id=" + string(value);
else
    predicate = "er.run_key=" + sqlText(value);
end
rows = fetch(conn, "SELECT er.extraction_run_id, er.project_id, er.run_key, " + ...
    "ev.extractor_version_id, ev.extractor_id, ev.version_label, " + ...
    "e.extractor_key, e.extractor_name " + ...
    "FROM extraction_runs er " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id=er.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id=ev.extractor_id " + ...
    "WHERE er.project_id=" + string(recording.project_id) + " AND " + predicate);
if isempty(rows) || height(rows) == 0
    error("vawlume:matching:ExtractionRunNotFound", ...
        "%s does not resolve to an extraction run in project '%s'.", ...
        role, recording.project_key);
end
if height(rows) ~= 1
    error("vawlume:matching:ExtractionRunAmbiguous", ...
        "%s resolved to %d extraction runs; exactly one is required.", role, height(rows));
end
runId = double(rows.extraction_run_id(1));
input = fetch(conn, "SELECT COUNT(*) AS n FROM extraction_run_inputs " + ...
    "WHERE extraction_run_id=" + string(runId) + ...
    " AND recording_id=" + string(recording.recording_id));
if double(input.n(1)) == 0
    error("vawlume:matching:RunRecordingMismatch", ...
        "%s extraction run %d does not analyze recording %d.", ...
        role, runId, recording.recording_id);
end
run = struct( ...
    input_role=role, ...
    extraction_run_id=runId, ...
    run_key=presentText(rows.run_key(1)), ...
    extractor_id=double(rows.extractor_id(1)), ...
    extractor_key=presentText(rows.extractor_key(1)), ...
    extractor_name=presentText(rows.extractor_name(1)), ...
    extractor_version_id=double(rows.extractor_version_id(1)), ...
    extractor_version=presentText(rows.version_label(1)));
end

function [mode, value] = normalizeRunRef(reference, role)
if isstruct(reference)
    hasId = isfield(reference, "extraction_run_id");
    hasKey = isfield(reference, "run_key");
    if hasId == hasKey
        error("vawlume:matching:RunPairInvalid", ...
            "%s struct must contain exactly one of extraction_run_id and run_key.", role);
    end
    if hasId
        mode = "id";
        value = scalarPositiveInteger(reference.extraction_run_id, ...
            role + ".extraction_run_id");
    else
        mode = "key";
        value = scalarText(reference.run_key, role + ".run_key");
    end
elseif isnumeric(reference)
    mode = "id";
    value = scalarPositiveInteger(reference, role);
elseif isstring(reference) || ischar(reference)
    mode = "key";
    value = scalarText(reference, role);
else
    error("vawlume:matching:RunPairInvalid", ...
        "%s must be a run_key, extraction_run_id, or scalar reference struct.", role);
end
if mode == "key" && strlength(value) == 0
    error("vawlume:matching:RunPairInvalid", "%s run_key is empty.", role);
end
end

function geometry = detectionGeometry(conn, recordingId, runId, role)
geometry = fetch(conn, "SELECT detection_id, native_event_id, start_time_s, " + ...
    "end_time_s, duration_s FROM v_detection_core " + ...
    "WHERE recording_id=" + string(recordingId) + ...
    " AND extraction_run_id=" + string(runId) + " ORDER BY detection_id");
if isempty(geometry)
    geometry = table(zeros(0, 1), strings(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), VariableNames=["detection_id", ...
        "native_event_id", "start_time_s", "end_time_s", "duration_s"]);
    return
end
startS = double(geometry.start_time_s);
endS = double(geometry.end_time_s);
durationS = double(geometry.duration_s);
invalid = ~isfinite(startS) | ~isfinite(endS) | ~isfinite(durationS) | ...
    startS < 0 | endS <= startS | durationS <= 0;
if any(invalid)
    ids = string(double(geometry.detection_id(invalid)));
    error("vawlume:matching:InvalidGeometry", ...
        "%s contains detections without finite, positive boundary-derived " + ...
        "geometry in v_detection_core: %s.", role, strjoin(ids, ", "));
end
geometry.detection_id = double(geometry.detection_id);
geometry.native_event_id = presentText(geometry.native_event_id);
geometry.start_time_s = startS;
geometry.end_time_s = endS;
geometry.duration_s = durationS;
end

function configuration = resolveConfiguration(conn, projectId, specification)
configuration = struct( ...
    profile_action="create", version_action="create", ...
    profile_id=NaN, profile_version_id=NaN, ...
    profile_key=specification.profile_key, ...
    profile_name=specification.profile_name, ...
    profile_kind=specification.profile_kind, ...
    version_label=specification.version_label, ...
    profile_schema_version=specification.profile_schema_version, ...
    content_format="json", content_uri=specification.content_uri, ...
    checksum_sha256=specification.checksum_sha256, conflict_message="");
rows = fetch(conn, "SELECT profile_id, profile_kind FROM config_profiles " + ...
    "WHERE project_id=" + string(projectId) + ...
    " AND profile_key=" + sqlText(configuration.profile_key));
if isempty(rows) || height(rows) == 0
    return
end
configuration.profile_id = double(rows.profile_id(1));
configuration.profile_action = "reuse";
if presentText(rows.profile_kind(1)) ~= "consilience_policy"
    configuration.profile_action = "conflict";
    configuration.version_action = "conflict";
    configuration.conflict_message = "Project profile key '" + ...
        configuration.profile_key + "' is registered with kind '" + ...
        presentText(rows.profile_kind(1)) + "', not consilience_policy.";
    return
end
versions = fetch(conn, "SELECT profile_version_id, " + ...
    "IFNULL(checksum_sha256,'') AS checksum_sha256 FROM config_profile_versions " + ...
    "WHERE profile_id=" + string(configuration.profile_id) + ...
    " AND version_label=" + sqlText(configuration.version_label));
if isempty(versions) || height(versions) == 0
    return
end
configuration.profile_version_id = double(versions.profile_version_id(1));
configuration.version_action = "reuse";
stored = presentText(versions.checksum_sha256(1));
if stored ~= configuration.checksum_sha256
    configuration.version_action = "conflict";
    configuration.conflict_message = "Matching specification '" + ...
        configuration.profile_key + "' version '" + configuration.version_label + ...
        "' is registered with checksum " + stored + ...
        " but the supplied file has checksum " + configuration.checksum_sha256 + ".";
end
end

function analysis = resolveAnalysis(conn, plan)
analysis = struct(action="create", analysis_run_id=NaN, ...
    run_type="cross_extractor_matching", run_key=plan.context.run_key, ...
    conflict_message="");
rows = fetch(conn, "SELECT analysis_run_id, run_type, status FROM analysis_runs " + ...
    "WHERE project_id=" + string(plan.recording.project_id) + ...
    " AND run_key=" + sqlText(plan.context.run_key));
if isempty(rows) || height(rows) == 0
    return
end
analysis.analysis_run_id = double(rows.analysis_run_id(1));
analysis.action = "reuse";
if presentText(rows.run_type(1)) ~= analysis.run_type || ...
        presentText(rows.status(1)) ~= "completed"
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' exists with incompatible run_type or status.";
    return
end
if plan.configuration.version_action ~= "reuse"
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' exists but the supplied matching specification version is not reusable.";
    return
end
profiles = fetch(conn, "SELECT profile_version_id, assignment_role " + ...
    "FROM analysis_run_profiles WHERE analysis_run_id=" + ...
    string(analysis.analysis_run_id));
inputs = fetch(conn, "SELECT extraction_run_id, input_role " + ...
    "FROM analysis_run_extraction_inputs WHERE analysis_run_id=" + ...
    string(analysis.analysis_run_id));
profileOkay = height(profiles) == 1 && ...
    double(profiles.profile_version_id(1)) == plan.configuration.profile_version_id && ...
    presentText(profiles.assignment_role(1)) == "matching_spec";
inputOkay = height(inputs) == 2 && inputPresent(inputs, ...
    plan.run_pair.run_a.extraction_run_id, "run_a") && inputPresent(inputs, ...
    plan.run_pair.run_b.extraction_run_id, "run_b");
if ~profileOkay || ~inputOkay
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' is linked to a different matching specification or ordered run pair.";
    return
end
[compatible, reason] = candidatesCompatible(conn, analysis.analysis_run_id, ...
    plan.candidates);
if ~compatible
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' has different persisted candidate evidence: " + reason;
end
end

function value = inputPresent(rows, runId, role)
value = any(double(rows.extraction_run_id) == runId & ...
    presentText(rows.input_role) == role);
end

function [compatible, reason] = candidatesCompatible(conn, analysisRunId, expected)
stored = fetch(conn, "SELECT detection_a_id, detection_b_id, temporal_overlap_s, " + ...
    "temporal_iou, onset_difference_s, offset_difference_s, " + ...
    "duration_difference_s, candidate_score, candidate_status, details_json " + ...
    "FROM candidate_pairs WHERE analysis_run_id=" + string(analysisRunId) + ...
    " ORDER BY detection_a_id, detection_b_id");
if isempty(stored)
    stored = table();
end
if height(stored) ~= height(expected)
    compatible = false;
    reason = "candidate count differs";
    return
end
if height(expected) == 0
    compatible = true;
    reason = "";
    return
end
expected = sortrows(expected, ["detection_a_id", "detection_b_id"]);
idOkay = all(double(stored.detection_a_id) == expected.detection_a_id) && ...
    all(double(stored.detection_b_id) == expected.detection_b_id);
numericNames = ["temporal_overlap_s", "temporal_iou", ...
    "onset_difference_s", "offset_difference_s", ...
    "duration_difference_s", "candidate_score"];
numericOkay = true;
for name = numericNames
    numericOkay = numericOkay && all(abs(double(stored.(name)) - ...
        expected.(name)) <= 1e-12);
end
textOkay = all(presentText(stored.candidate_status) == ...
    expected.candidate_status) && all(presentText(stored.details_json) == ...
    expected.details_json);
compatible = idOkay && numericOkay && textOkay;
if compatible
    reason = "";
else
    reason = "pair identity, metrics, status, or directional details differ";
end
end

function plan = appendConflict(plan, message)
if strlength(message) > 0
    plan.conflicts(end + 1, 1) = message;
end
end

function root = resolveRepoRoot(root)
if strlength(root) == 0
    root = fileparts(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath"))))));
end
root = canonicalPath(root);
end

function value = optionalText(container, field)
value = "";
if isfield(container, field)
    value = scalarText(container.(field), "matchSpec." + field);
end
end

function value = scalarText(raw, label)
try
    value = string(raw);
catch
    error("vawlume:matching:InvalidText", "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value)
    error("vawlume:matching:InvalidText", "%s must be scalar text.", label);
end
value = strtrim(value);
end

function value = scalarPositiveInteger(raw, label)
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || ...
        raw < 1 || fix(raw) ~= raw
    error("vawlume:matching:InvalidIdentifier", ...
        "%s must be a positive integer.", label);
end
value = double(raw);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function value = sqlText(raw)
value = "'" + replace(string(raw), "'", "''") + "'";
end

function value = canonicalPath(value)
try
    value = string(java.io.File(char(value)).getCanonicalPath());
catch
    value = string(value);
end
end
