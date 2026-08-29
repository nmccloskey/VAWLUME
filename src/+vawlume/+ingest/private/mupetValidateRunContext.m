function context = mupetValidateRunContext(recordingRef, runSpec)
%MUPETVALIDATERUNCONTEXT Normalize explicit MUPET run provenance.

arguments
    recordingRef (1,1) struct
    runSpec (1,1) struct
end

if isfield(runSpec, "model")
    error("vawlume:ingest:MupetRunSpecInvalid", ...
        "runSpec.model is not part of the MUPET extraction contract and must not be supplied.");
end
if isfield(runSpec, "classification")
    error("vawlume:ingest:MupetRunSpecInvalid", ...
        "runSpec.classification is not part of the MUPET extraction contract and must not be supplied.");
end
context = struct(recording_ref=validateRecordingRef(recordingRef), ...
    run=validateRun(runSpec), settings=validateSettings(runSpec), ...
    native_artifact=validateNative(runSpec), dataset=validateDataset(runSpec));
end

function ref = validateRecordingRef(value)
ref = struct(mode="", recording_id=NaN, project_key="", source_relative_path="");
hasId = isfield(value, "recording_id");
hasPortable = isfield(value, "project_key") || isfield(value, "source_relative_path");
if hasId && hasPortable
    error("vawlume:ingest:MupetRecordingRefInvalid", ...
        "recordingRef must use recording_id or project_key with source_relative_path, not both.");
elseif hasId
    id = value.recording_id;
    if ~isnumeric(id) || ~isscalar(id) || ~isfinite(id) || fix(id) ~= id
        error("vawlume:ingest:MupetRecordingRefInvalid", ...
            "recordingRef.recording_id must be a scalar integer.");
    end
    ref.mode = "recording_id";
    ref.recording_id = double(id);
elseif hasPortable
    ref.mode = "portable_source";
    ref.project_key = requiredText(value, "project_key");
    ref.source_relative_path = replace(requiredText(value, "source_relative_path"), "\", "/");
else
    error("vawlume:ingest:MupetRecordingRefInvalid", ...
        "recordingRef must declare recording_id, or project_key with source_relative_path.");
end
end

function run = validateRun(spec)
run = struct(run_key=requiredText(spec, "run_key"), ...
    extractor_version=optionalText(spec, "extractor_version"), ...
    run_label=optionalText(spec, "run_label"), notes=optionalText(spec, "notes"), ...
    started_at_utc=optionalText(spec, "started_at_utc"), ...
    completed_at_utc=optionalText(spec, "completed_at_utc"), ...
    status=optionalText(spec, "status"));
if strlength(run.status) == 0, run.status = "imported"; end
if ~ismember(run.status, ["planned", "running", "completed", "imported", "failed"])
    error("vawlume:ingest:MupetRunSpecInvalid", ...
        "runSpec.status '%s' is outside the schema's allowed statuses.", run.status);
end
end

function settings = validateSettings(spec)
settings = struct(mode="none", status="not_supplied", config_path="", ...
    profile_path="", profile_key="", version_label="", description="", ...
    relative_path="", native_type="");
if ~isfield(spec, "settings") || isempty(spec.settings), return, end
value = spec.settings;
if ~isstruct(value) || ~isscalar(value)
    error("vawlume:ingest:MupetRunSpecInvalid", "runSpec.settings must be a scalar struct.");
end
hasConfig = isfield(value, "config_path");
hasJson = isfield(value, "json_path") || isfield(value, "profile_path");
if hasConfig == hasJson
    error("vawlume:ingest:MupetRunSpecInvalid", ...
        "runSpec.settings must declare exactly one of config_path or json_path/profile_path.");
end
if isfield(value, "json_path") && isfield(value, "profile_path")
    error("vawlume:ingest:MupetRunSpecInvalid", ...
        "runSpec.settings must not declare both json_path and its profile_path alias.");
end
if isfield(value, "native_type")
    error("vawlume:ingest:MupetRunSpecInvalid", ...
        "runSpec.settings.native_type is fixed by the MUPET settings source contract.");
end
settings.relative_path = optionalText(value, "relative_path");
if hasConfig
    settings.mode = "config_csv";
    settings.status = "captured";
    settings.config_path = requiredText(value, "config_path");
else
    if strlength(settings.relative_path) > 0
        error("vawlume:ingest:MupetRunSpecInvalid", ...
            "relative_path and native_type apply only to native config.csv settings artifacts.");
    end
    settings.mode = "profile";
    settings.status = "captured";
    if isfield(value, "json_path")
        settings.profile_path = requiredText(value, "json_path");
    else
        settings.profile_path = requiredText(value, "profile_path");
    end
    settings.profile_key = optionalText(value, "profile_key");
    settings.version_label = optionalText(value, "version_label");
    settings.description = optionalText(value, "description");
end
end

function native = validateNative(spec)
native = struct(mode="none", artifact_path="", relative_path="", native_type="");
if ~isfield(spec, "native_artifact") || isempty(spec.native_artifact), return, end
value = spec.native_artifact;
if ~isstruct(value) || ~isscalar(value)
    error("vawlume:ingest:MupetRunSpecInvalid", "runSpec.native_artifact must be a scalar struct.");
end
native.mode = "artifact";
native.artifact_path = requiredText(value, "artifact_path");
native.relative_path = optionalText(value, "relative_path");
native.native_type = optionalText(value, "native_type");
if strlength(native.native_type) == 0
    native.native_type = "MUPET per-recording processed MATLAB state";
end
end

function dataset = validateDataset(spec)
dataset = struct(status="not_supplied", workspace_name="", dataset_name="", native_dataset_path="");
if ~isfield(spec, "dataset") || isempty(spec.dataset), return, end
value = spec.dataset;
if ~isstruct(value) || ~isscalar(value)
    error("vawlume:ingest:MupetRunSpecInvalid", "runSpec.dataset must be a scalar struct.");
end
dataset.status = "captured_provenance_only";
dataset.workspace_name = optionalText(value, "workspace_name");
dataset.dataset_name = optionalText(value, "dataset_name");
dataset.native_dataset_path = optionalText(value, "native_dataset_path");
end

function value = requiredText(container, field)
value = optionalText(container, field);
if strlength(value) == 0
    error("vawlume:ingest:MupetRunSpecInvalid", "Required field '%s' is missing or empty.", field);
end
end
function value = optionalText(container, field)
value = "";
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
try
    candidate = string(container.(char(field)));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = strtrim(candidate);
end
end
