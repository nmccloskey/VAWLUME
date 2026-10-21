function result = declareInputs(conn, runRef, declarations, options)
%DECLAREINPUTS Plan or write one attribution run's declared inputs.
%
% RESULT = VAWLUME.ATTRIBUTION.DECLAREINPUTS(CONN, RUNREF, DECLARATIONS,
% DeclaredBy=PROFILEVERSIONID) validates a run's statement of which upstream
% input dimensions it consumed and writes nothing. Apply=true stores it in
% attribution_run_declared_inputs.
%
% This is the ONE writer of attribution_run_declared_inputs (P6-1). Two paths
% call it, each inside its own transaction:
%
%   native_estimate  vawlume.attribution.createRun, declared by the run's
%                    attribution_estimator_settings profile version
%   backend          vawlume.ingest.backendAttribution, declared by the
%                    attribution_backend_mapping profile version its intake
%                    registers (which exists only once intake runs, so the
%                    declarations cannot travel with createRun)
%
% An imported run declares nothing: no row is not "not used", it is unknown.
%
% RUNREF contains attribution_run_id, or project_key plus run_key. The run must
% be planned with its analysis parent started. DECLARATIONS is a table or struct
% array of input_dimension (temporal_alignment, pose_localization,
% visual_identity or acoustic), declaration (used or not_used) and optional
% notes. Rows are stored in the order given. DeclaredBy is the profile version
% that makes the declaration.
%
% REFUSED BY NAME, BEFORE ANY WRITE:
%   an imported run                          vawlume:attribution:DeclaredInputsNotAccepted
%   a run that is not writable               vawlume:attribution:RunNotWritable
%   a run that already has declarations      vawlume:attribution:DeclaredInputsInvalid
%   an unknown dimension or declaration, a
%   repeated dimension, or a declarer that
%   is not the path's (native: the run's
%   settings profile version; backend: an
%   attribution_backend_mapping version)    vawlume:attribution:DeclaredInputsInvalid
%   a native run missing a dimension         vawlume:attribution:DeclaredInputsIncomplete
%
% Declarations are written once and never rewritten.
%
% Transaction="own" (default) commits here. Transaction="caller" joins the
% caller's open transaction (AutoCommit off, set by the caller) and leaves
% commit and rollback to it; with AutoCommit on it is refused
% (vawlume:attribution:TransactionState). See VAWLUME.ATTRIBUTION.CREATERUN.
%
% See also VAWLUME.ATTRIBUTION.CREATERUN, VAWLUME.INGEST.BACKENDATTRIBUTION

arguments
    conn
    runRef (1,1) struct
    declarations
    options.DeclaredBy (1,1) double {mustBeInteger, mustBePositive}
    options.Apply (1,1) logical = false
    options.Transaction (1,1) string {mustBeMember(options.Transaction, ...
        ["own", "caller"])} = "own"
end

run = attributionResolveRun(conn, runRef);
assertDeclarable(conn, run, options.DeclaredBy);
rows = normalizeDeclarations(declarations, run.attribution_path);
result = struct(status="planned", committed=false, ...
    attribution_run_id=run.attribution_run_id, ...
    declared_by_profile_version_id=options.DeclaredBy, ...
    declared_inputs=rows, applied_count=0);
if ~options.Apply
    return
end
if options.Transaction == "caller"
    attributionRequireCallerTransaction(conn, "Declared-input apply");
    writeRows(conn, run.attribution_run_id, rows, options.DeclaredBy);
else
    writeOwn(conn, run.attribution_run_id, rows, options.DeclaredBy);
end
result.status = "created";
result.committed = true;
result.applied_count = height(rows);
end

function assertDeclarable(conn, run, declaredBy)
if run.attribution_path == "imported"
    error("vawlume:attribution:DeclaredInputsNotAccepted", ...
        "An imported run declares no inputs; an input it never declared is " + ...
        "unknown, not unused.");
end
if run.status ~= "planned" || run.analysis_status ~= "started"
    error("vawlume:attribution:RunNotWritable", ...
        "Declared inputs may only be written while attribution status is planned " + ...
        "and analysis status is started.");
end
existing = fetch(conn, "SELECT COUNT(*) AS n FROM attribution_run_declared_inputs " + ...
    "WHERE attribution_run_id=" + string(run.attribution_run_id));
if double(existing.n(1)) > 0
    error("vawlume:attribution:DeclaredInputsInvalid", ...
        "Run %s already declares its inputs; declarations are written once.", ...
        run.run_key);
end
if run.attribution_path == "native_estimate"
    if declaredBy ~= run.settings_profile_version_id
        error("vawlume:attribution:DeclaredInputsInvalid", ...
            "A native run's inputs are declared by the settings profile version " + ...
            "it cites (%d), not %d.", run.settings_profile_version_id, declaredBy);
    end
    return
end
kind = fetch(conn, "SELECT cp.profile_kind FROM config_profile_versions cpv " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE cpv.profile_version_id=" + string(declaredBy));
if isempty(kind) || height(kind) == 0 || ...
        string(kind.profile_kind(1)) ~= "attribution_backend_mapping"
    error("vawlume:attribution:DeclaredInputsInvalid", ...
        "A backend run's inputs are declared by an attribution_backend_mapping " + ...
        "profile version; %d is not one.", declaredBy);
end
end

function rows = normalizeDeclarations(raw, path)
if isstruct(raw)
    raw = struct2table(raw(:), AsArray=true);
end
if ~istable(raw) || ~all(ismember(["input_dimension", "declaration"], ...
        string(raw.Properties.VariableNames)))
    error("vawlume:attribution:DeclaredInputsInvalid", ...
        "Declarations must be a table of input_dimension, declaration and optional notes.");
end
dimensions = strtrim(string(raw.input_dimension(:)));
values = strtrim(string(raw.declaration(:)));
if ismember("notes", string(raw.Properties.VariableNames))
    notes = string(raw.notes(:));
    notes(ismissing(notes)) = "";
else
    notes = strings(height(raw), 1);
end
known = ["temporal_alignment", "pose_localization", "visual_identity", "acoustic"];
if any(~ismember(dimensions, known)) || any(~ismember(values, ["used", "not_used"]))
    error("vawlume:attribution:DeclaredInputsInvalid", ...
        "Every input_dimension must be one of %s, and every declaration used or not_used.", ...
        strjoin(known, ", "));
end
if numel(unique(dimensions)) ~= numel(dimensions)
    error("vawlume:attribution:DeclaredInputsInvalid", ...
        "A run declares each input dimension at most once.");
end
if path == "native_estimate" && ~all(ismember(known, dimensions))
    error("vawlume:attribution:DeclaredInputsIncomplete", ...
        "A native_estimate run must declare each of %s exactly once.", ...
        strjoin(known, ", "));
end
rows = table(dimensions, values, notes, ...
    VariableNames=["input_dimension", "declaration", "notes"]);
end

function writeOwn(conn, runId, rows, declaredBy)
oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:attribution:TransactionState", ...
        "Declared-input apply requires a connection with AutoCommit enabled.");
end
conn.AutoCommit = "off";
try
    writeRows(conn, runId, rows, declaredBy);
    commit(conn);
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

function writeRows(conn, runId, rows, declaredBy)
for index = 1:height(rows)
    attributionInsertRow(conn, "attribution_run_declared_inputs", struct( ...
        attribution_run_id=runId, input_dimension=rows.input_dimension(index), ...
        declaration=rows.declaration(index), ...
        declared_by_profile_version_id=declaredBy, notes=rows.notes(index)));
end
end
