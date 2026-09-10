function plan = agreementBuildPlan(conn, recordingRef, sources, agreementSpec, repoRoot)
%AGREEMENTBUILDPLAN Resolve one arbitrary-N agreement run and compose it.
%
% Two halves. The analysis boundary: which pairwise analyses are being consumed,
% which extraction runs they cover, whether the pairwise coverage is complete,
% which policy version governs the derivation. And the composition itself: the
% detection node set, the exact support edges, and the components they form.
%
% Nothing is written. Every derived row is classified create, reuse, or conflict
% against what is already stored, so a rerun over the same evidence resolves to
% the same components rather than adding a second copy.

repoRoot = resolveRepoRoot(repoRoot);
plan = struct();
plan.context = validateAgreementSpec(agreementSpec);
plan.specification = agreementLoadSpec(plan.context.profile_path, repoRoot);
plan.recording = resolveRecording(conn, recordingRef);
plan.sources = agreementResolveSources(conn, plan.recording, sources, ...
    plan.specification);
[plan.extractor_runs, plan.coverage] = agreementValidateCoverage(plan.sources, ...
    plan.specification);
plan.graph = agreementResolveGraph(conn, plan.recording, plan.sources, ...
    plan.extractor_runs);
[plan.groups, plan.members, plan.support_edges] = ...
    agreementBuildComponents(plan.graph, plan.specification);
plan.configuration = resolveConfiguration(conn, plan.recording.project_id, ...
    plan.specification);
plan.analysis = resolveAnalysis(conn, plan);
plan = agreementResolveDerivedGraph(conn, plan);
plan.conflicts = strings(0, 1);
plan = appendConflict(plan, plan.configuration.conflict_message);
plan = appendConflict(plan, plan.analysis.conflict_message);
plan.has_conflicts = ~isempty(plan.conflicts);
end

function context = validateAgreementSpec(agreementSpec)
if ~isfield(agreementSpec, "run_key")
    error("vawlume:agreement:AgreementSpecInvalid", ...
        "agreementSpec.run_key is required and identifies the immutable analysis.");
end
context = struct( ...
    run_key=scalarText(agreementSpec.run_key, "agreementSpec.run_key"), ...
    run_label=optionalText(agreementSpec, "run_label"), ...
    vawlume_version=optionalText(agreementSpec, "vawlume_version"), ...
    source_commit=optionalText(agreementSpec, "source_commit"), ...
    notes=optionalText(agreementSpec, "notes"), ...
    profile_path=optionalText(agreementSpec, "profile_path"));
if strlength(context.run_key) == 0
    error("vawlume:agreement:AgreementSpecInvalid", ...
        "agreementSpec.run_key must be a nonempty scalar text value.");
end
end

function recording = resolveRecording(conn, recordingRef)
hasId = isfield(recordingRef, "recording_id");
hasPortable = isfield(recordingRef, "project_key") && ...
    isfield(recordingRef, "source_relative_path");
if hasId == hasPortable
    error("vawlume:agreement:RecordingRefInvalid", ...
        "recordingRef must contain exactly one selector: recording_id, or " + ...
        "project_key plus source_relative_path.");
end
columns = "SELECT r.recording_id, r.project_id, p.project_key, " + ...
    "IFNULL(r.native_recording_id,'') AS native_recording_id, " + ...
    "IFNULL(sf.relative_path,'') AS source_relative_path " + ...
    "FROM recordings r JOIN projects p ON p.project_id=r.project_id " + ...
    "JOIN source_files sf ON sf.source_file_id=r.source_file_id WHERE ";
if hasId
    id = scalarPositiveInteger(recordingRef.recording_id, "recording_id");
    rows = fetch(conn, columns + "r.recording_id=" + string(id));
else
    projectKey = scalarText(recordingRef.project_key, "project_key");
    relativePath = scalarText(recordingRef.source_relative_path, ...
        "source_relative_path");
    rows = fetch(conn, columns + "p.project_key=" + sqlText(projectKey) + ...
        " AND sf.relative_path=" + sqlText(relativePath));
end
if isempty(rows) || height(rows) == 0
    error("vawlume:agreement:RecordingNotFound", ...
        "No established recording matches recordingRef.");
end
if height(rows) ~= 1
    error("vawlume:agreement:RecordingAmbiguous", ...
        "recordingRef matched %d recordings; exactly one is required.", height(rows));
end
recording = struct( ...
    recording_id=double(rows.recording_id(1)), ...
    project_id=double(rows.project_id(1)), ...
    project_key=presentText(rows.project_key(1)), ...
    native_recording_id=presentText(rows.native_recording_id(1)), ...
    source_relative_path=presentText(rows.source_relative_path(1)));
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
if presentText(rows.profile_kind(1)) ~= specification.profile_kind
    configuration.profile_action = "conflict";
    configuration.version_action = "conflict";
    configuration.conflict_message = "Project profile key '" + ...
        configuration.profile_key + "' is registered with kind '" + ...
        presentText(rows.profile_kind(1)) + "', not " + ...
        specification.profile_kind + ".";
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
    configuration.conflict_message = "Agreement policy '" + ...
        configuration.profile_key + "' version '" + configuration.version_label + ...
        "' is registered with checksum " + stored + ...
        " but the supplied file has checksum " + configuration.checksum_sha256 + ".";
end
end

function analysis = resolveAnalysis(conn, plan)
%RESOLVEANALYSIS Decide create, reuse, or conflict for the derived run.
%
% An applied agreement run that carries lineage but no composed groups is left
% with status 'started', so 'started' is a reusable state here rather than a
% broken one. A failed run is not reusable: its provenance may be partial.
analysis = struct(action="create", graph_action="create", ...
    analysis_run_id=NaN, run_type="multi_extractor_agreement", ...
    run_key=plan.context.run_key, status="", conflict_message="");
rows = fetch(conn, "SELECT analysis_run_id, run_type, status FROM analysis_runs " + ...
    "WHERE project_id=" + string(plan.recording.project_id) + ...
    " AND run_key=" + sqlText(plan.context.run_key));
if isempty(rows) || height(rows) == 0
    return
end
analysis.analysis_run_id = double(rows.analysis_run_id(1));
analysis.status = presentText(rows.status(1));
analysis.action = "reuse";
if presentText(rows.run_type(1)) ~= analysis.run_type || ...
        ~ismember(analysis.status, ["started", "completed"])
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' exists with run_type '" + presentText(rows.run_type(1)) + ...
        "' and status '" + analysis.status + "', which this agreement run " + ...
        "cannot reuse.";
    return
end
if plan.configuration.version_action ~= "reuse"
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' exists but the supplied agreement policy version is not reusable.";
    return
end
profiles = fetch(conn, "SELECT profile_version_id, assignment_role " + ...
    "FROM analysis_run_profiles WHERE analysis_run_id=" + ...
    string(analysis.analysis_run_id));
if height(profiles) ~= 1 || ...
        double(profiles.profile_version_id(1)) ~= plan.configuration.profile_version_id || ...
        presentText(profiles.assignment_role(1)) ~= agreementRoles().specification
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' is linked to a different agreement policy version.";
    return
end
inputs = fetch(conn, "SELECT extraction_run_id, input_role " + ...
    "FROM analysis_run_extraction_inputs WHERE analysis_run_id=" + ...
    string(analysis.analysis_run_id));
expectedRuns = sort(plan.extractor_runs.extraction_run_id);
storedRuns = sort(double(inputs.extraction_run_id));
if height(inputs) ~= numel(expectedRuns) || ~isequal(storedRuns(:), expectedRuns(:)) || ...
        ~all(presentText(inputs.input_role) == agreementRoles().extraction_input)
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' declares different participating extraction runs.";
    return
end
stored = fetch(conn, "SELECT source_analysis_run_id, dependency_role " + ...
    "FROM analysis_run_sources WHERE analysis_run_id=" + ...
    string(analysis.analysis_run_id));
expectedSources = sort(plan.sources.analysis_run_id);
storedSources = sort(double(stored.source_analysis_run_id));
if height(stored) ~= numel(expectedSources) || ...
        ~isequal(storedSources(:), expectedSources(:)) || ...
        ~all(presentText(stored.dependency_role) == agreementRoles().source_analysis)
    analysis.action = "conflict";
    analysis.conflict_message = "Analysis run_key '" + analysis.run_key + ...
        "' is composed from a different set of source pairwise analyses.";
end
end

function plan = appendConflict(plan, message)
if strlength(message) > 0
    plan.conflicts(end + 1, 1) = message;
end
end

function value = resolveRepoRoot(repoRoot)
if strlength(repoRoot) > 0
    value = repoRoot;
    return
end
value = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end

function value = scalarText(raw, label)
try
    value = string(raw);
catch
    error("vawlume:agreement:InvalidText", "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value)
    error("vawlume:agreement:InvalidText", "%s must be scalar text.", label);
end
value = strtrim(value);
end

function value = optionalText(container, field)
value = "";
if isfield(container, field)
    value = scalarText(container.(field), field);
end
end

function value = scalarPositiveInteger(raw, label)
if ~isnumeric(raw) || ~isscalar(raw) || ~isfinite(raw) || raw <= 0 || ...
        raw ~= floor(raw)
    error("vawlume:agreement:InvalidIdentifier", ...
        "%s must be a positive integer.", label);
end
value = double(raw);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end
