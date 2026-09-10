function context = usvsegValidateRunContext(recordingRef, runSpec)
%USVSEGVALIDATERUNCONTEXT Normalize caller evidence without inference.
context = struct(recording_ref=validateRecording(recordingRef), ...
    run=validateRun(runSpec), settings=validateSettings(runSpec));
for unsupported = ["model","classification","native_artifact"]
    if isfield(runSpec,unsupported) && ~isempty(runSpec.(unsupported))
        error("vawlume:ingest:UsvsegRunSpecInvalid", ...
            "runSpec.%s is unsupported for the USVSEG importer.", unsupported);
    end
end
end

function ref = validateRecording(value)
ref=struct(mode="",recording_id=NaN,project_key="",source_relative_path="");
hasId=isfield(value,"recording_id"); hasPortable=isfield(value,"project_key")||isfield(value,"source_relative_path");
if hasId && hasPortable, invalid("recordingRef must use exactly one resolution mode."); end
if hasId
    id=value.recording_id;
    if ~isnumeric(id)||~isscalar(id)||~isfinite(id)||fix(id)~=id, invalid("recording_id must be an integer."); end
    ref.mode="recording_id"; ref.recording_id=double(id); return
end
if ~hasPortable, invalid("recordingRef must declare recording_id or project_key with source_relative_path."); end
ref.mode="portable_source"; ref.project_key=required(value,"project_key");
ref.source_relative_path=replace(required(value,"source_relative_path"),"\","/");
end

function run = validateRun(value)
run=struct(run_key=required(value,"run_key"),extractor_version=optional(value,"extractor_version"), ...
    run_label=optional(value,"run_label"),notes=optional(value,"notes"), ...
    started_at_utc=optional(value,"started_at_utc"),completed_at_utc=optional(value,"completed_at_utc"), ...
    status=optional(value,"status"));
if strlength(run.status)==0, run.status="imported"; end
if ~ismember(run.status,["planned","running","completed","imported","failed"])
    invalid("runSpec.status is outside the schema's allowed statuses.");
end
end

function settings = validateSettings(value)
settings=struct(mode="none",status="unavailable",artifact_path="",relative_path="", ...
    native_type="USVSEG saved parameter structure",evidence_strength="weak_not_run_scoped");
if ~isfield(value,"settings")||isempty(value.settings), return, end
declared=value.settings;
if ~isstruct(declared)||~isscalar(declared)||~isfield(declared,"artifact_path")
    invalid("runSpec.settings must be a scalar struct with artifact_path.");
end
settings.mode="artifact"; settings.status="captured_weak";
settings.artifact_path=required(declared,"artifact_path"); settings.relative_path=optional(declared,"relative_path");
end

function value=required(container,field), value=optional(container,field); if strlength(value)==0, invalid("Required field '"+field+"' is missing or empty."); end, end
function value=optional(container,field)
value=""; if ~isstruct(container)||~isfield(container,char(field))||isempty(container.(char(field))), return, end
try candidate=string(container.(char(field))); catch, return, end
if isscalar(candidate)&&~ismissing(candidate), value=strtrim(candidate); end
end
function invalid(message), error("vawlume:ingest:UsvsegRunSpecInvalid","%s",message); end
