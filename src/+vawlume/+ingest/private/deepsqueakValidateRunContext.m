function context = deepsqueakValidateRunContext(recordingRef, runSpec)
%DEEPSQUEAKVALIDATERUNCONTEXT Normalize the explicit caller-supplied run context.
%
% Only information that cannot be truthfully recovered from a call-statistics
% export belongs here. Nothing in this function inspects the exported table, and
% nothing is inferred from filesystem metadata: an extraction timestamp is
% recorded only when the caller states it, because a file's modified time is
% file metadata rather than evidence about when DeepSqueak ran.

arguments
    recordingRef (1,1) struct
    runSpec (1,1) struct
end

context = struct();
context.recording_ref = validateRecordingRef(recordingRef);
context.run = validateRunSpec(runSpec);
context.settings = validateSettings(runSpec);
context.model = validateModel(runSpec);
context.native_artifact = validateNativeArtifact(runSpec);
end

function ref = validateRecordingRef(recordingRef)
ref = struct(mode="", recording_id=NaN, project_key="", source_relative_path="");

hasId = isfield(recordingRef, "recording_id");
hasPortable = isfield(recordingRef, "project_key") || ...
    isfield(recordingRef, "source_relative_path");

if hasId && hasPortable
    error("vawlume:ingest:DeepSqueakRecordingRefInvalid", ...
        ['recordingRef must use exactly one resolution mode: either ' ...
        'recording_id, or project_key with source_relative_path.']);
end

if hasId
    value = recordingRef.recording_id;
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || fix(value) ~= value
        error("vawlume:ingest:DeepSqueakRecordingRefInvalid", ...
            "recordingRef.recording_id must be a scalar integer.");
    end
    ref.mode = "recording_id";
    ref.recording_id = double(value);
    return
end

if ~hasPortable
    error("vawlume:ingest:DeepSqueakRecordingRefInvalid", ...
        ['recordingRef must declare recording_id, or project_key with ' ...
        'source_relative_path. A DeepSqueak import attaches to a recording ' ...
        'that project intake already established.']);
end

ref.mode = "portable_source";
ref.project_key = requiredText(recordingRef, "project_key", ...
    "vawlume:ingest:DeepSqueakRecordingRefInvalid");
ref.source_relative_path = replace(requiredText(recordingRef, "source_relative_path", ...
    "vawlume:ingest:DeepSqueakRecordingRefInvalid"), "\", "/");
end

function run = validateRunSpec(runSpec)
run = struct();
run.run_key = requiredText(runSpec, "run_key", ...
    "vawlume:ingest:DeepSqueakRunSpecInvalid");
% Whether a version must be stated is the profile's decision, declared through
% extractor.version_required_at_ingest, so it is enforced against the loaded
% profile rather than made unconditional here.
run.extractor_version = optionalText(runSpec, "extractor_version");
run.run_label = optionalText(runSpec, "run_label");
run.notes = optionalText(runSpec, "notes");
run.started_at_utc = optionalText(runSpec, "started_at_utc");
run.completed_at_utc = optionalText(runSpec, "completed_at_utc");
run.status = optionalText(runSpec, "status");
if strlength(run.status) == 0
    run.status = "imported";
end
if ~ismember(run.status, ["planned", "running", "completed", "imported", "failed"])
    error("vawlume:ingest:DeepSqueakRunSpecInvalid", ...
        "runSpec.status '%s' is outside the schema's allowed extraction-run statuses.", ...
        run.status);
end
end

function settings = validateSettings(runSpec)
settings = struct(mode="none", status="not_recoverable", profile_path="", ...
    profile_key="", version_label="", artifact_path="", native_type="", ...
    relative_path="", description="");
if ~isfield(runSpec, "settings") || isempty(runSpec.settings)
    return
end

declared = runSpec.settings;
if ~isstruct(declared) || ~isscalar(declared)
    error("vawlume:ingest:DeepSqueakRunSpecInvalid", ...
        "runSpec.settings must be a scalar struct when supplied.");
end

hasProfile = isfield(declared, "profile_path");
hasArtifact = isfield(declared, "artifact_path");
if hasProfile && hasArtifact
    error("vawlume:ingest:DeepSqueakRunSpecInvalid", ...
        ['runSpec.settings must declare either profile_path (a VAWLUME ' ...
        'extractor-settings profile) or artifact_path (an external native ' ...
        'settings file), not both.']);
end

if hasProfile
    settings.mode = "profile";
    settings.status = "captured";
    settings.profile_path = requiredText(declared, "profile_path", ...
        "vawlume:ingest:DeepSqueakRunSpecInvalid");
    settings.profile_key = optionalText(declared, "profile_key");
    settings.version_label = optionalText(declared, "version_label");
    settings.description = optionalText(declared, "description");
    return
end

if hasArtifact
    settings.mode = "artifact";
    settings.status = "captured_unvalidated";
    settings.artifact_path = requiredText(declared, "artifact_path", ...
        "vawlume:ingest:DeepSqueakRunSpecInvalid");
    settings.native_type = optionalText(declared, "native_type");
    if strlength(settings.native_type) == 0
        settings.native_type = "DeepSqueak detection settings";
    end
    settings.relative_path = optionalText(declared, "relative_path");
    return
end

error("vawlume:ingest:DeepSqueakRunSpecInvalid", ...
    "runSpec.settings declares neither profile_path nor artifact_path.");
end

function model = validateModel(runSpec)
model = struct(mode="none", status="not_recoverable", artifact_path="", ...
    model_label="", native_type="", relative_path="", evidence_source="");
if ~isfield(runSpec, "model") || isempty(runSpec.model)
    return
end

declared = runSpec.model;
if ~isstruct(declared) || ~isscalar(declared)
    error("vawlume:ingest:DeepSqueakRunSpecInvalid", ...
        "runSpec.model must be a scalar struct when supplied.");
end

model.mode = "artifact";
model.status = "captured";
model.artifact_path = requiredText(declared, "artifact_path", ...
    "vawlume:ingest:DeepSqueakRunSpecInvalid");
model.model_label = optionalText(declared, "model_label");
model.native_type = optionalText(declared, "native_type");
if strlength(model.native_type) == 0
    model.native_type = "DeepSqueak detector network";
end
model.relative_path = optionalText(declared, "relative_path");
% Provenance for the claim itself, so a later reader can tell caller assertion
% from artifact-derived evidence. A model is never inferred from the extractor
% version or from the export's score column.
model.evidence_source = optionalText(declared, "evidence_source");
if strlength(model.evidence_source) == 0
    model.evidence_source = "caller_declared";
end
end

function native = validateNativeArtifact(runSpec)
native = struct(mode="none", artifact_path="", native_type="", relative_path="");
if ~isfield(runSpec, "native_artifact") || isempty(runSpec.native_artifact)
    return
end

declared = runSpec.native_artifact;
if ~isstruct(declared) || ~isscalar(declared)
    error("vawlume:ingest:DeepSqueakRunSpecInvalid", ...
        "runSpec.native_artifact must be a scalar struct when supplied.");
end

native.mode = "artifact";
native.artifact_path = requiredText(declared, "artifact_path", ...
    "vawlume:ingest:DeepSqueakRunSpecInvalid");
native.native_type = optionalText(declared, "native_type");
if strlength(native.native_type) == 0
    native.native_type = "DeepSqueak detection file";
end
native.relative_path = optionalText(declared, "relative_path");
end

function value = requiredText(container, field, identifier)
value = optionalText(container, field);
if strlength(value) == 0
    error(identifier, "Required field '%s' is missing or empty.", field);
end
end

function value = optionalText(container, field)
value = "";
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
candidate = container.(char(field));
if isempty(candidate)
    return
end
try
    candidate = string(candidate);
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = strtrim(candidate);
end
end
