function manifest = alignmentLoadManifest(manifestPath, repoRoot, sourceRoot)
%ALIGNMENTLOADMANIFEST Read and validate one session alignment manifest.
%
% The manifest is concrete session evidence, not a reusable semantic profile. It
% names which clocks participate, which reference they are expressed in, and
% where each event and anchor table plus its mapping profile lives. It never
% embeds event rows.
%
% Loading is MATLAB-native (fileread + jsondecode) and the file is hashed
% byte-exactly, so the exact request can be reconstructed later.

manifestPath = alignmentResolvePath(manifestPath, repoRoot);
if ~isfile(manifestPath)
    error("vawlume:ingest:AlignmentManifestNotFound", ...
        "Alignment manifest does not exist: %s", manifestPath);
end
try
    document = jsondecode(fileread(manifestPath));
catch exception
    error("vawlume:ingest:AlignmentManifestInvalid", ...
        "Could not decode alignment manifest %s: %s", manifestPath, exception.message);
end

requiredStruct(document, "manifest");
requiredStruct(document, "session");
header = document.manifest;
session = document.session;

manifest = struct( ...
    document=document, ...
    source_path=string(manifestPath), ...
    checksum_sha256=sha256OfFile(manifestPath), ...
    content_uri=alignmentPortableUri(manifestPath, repoRoot), ...
    filename=string(alignmentFilenameOf(manifestPath)), ...
    manifest_schema_version=requiredText(header, "manifest_schema_version"), ...
    manifest_version=optionalText(header, "manifest_version"), ...
    alignment_key=requiredText(header, "alignment_key"), ...
    label=optionalText(header, "label"), ...
    notes=optionalText(header, "notes"), ...
    project_key=requiredText(session, "project_key"), ...
    recording=recordingSelector(session), ...
    reference_timebase_key=requiredText(document, "reference_timebase"), ...
    method=methodOf(document), ...
    timebases=timebaseDeclarations(document), ...
    streams=streamDeclarations(document, repoRoot, sourceRoot), ...
    anchors=anchorDeclaration(document, repoRoot, sourceRoot));

if manifest.manifest_schema_version ~= "0.1-draft"
    error("vawlume:ingest:AlignmentManifestUnsupported", ...
        "Alignment manifest schema version '%s' is not supported; expected 0.1-draft.", ...
        manifest.manifest_schema_version);
end

declared = [manifest.timebases.timebase_key];
if ~ismember(manifest.reference_timebase_key, declared)
    error("vawlume:ingest:AlignmentReferenceUndeclared", ...
        "Reference timebase '%s' is not declared in manifest.timebases.", ...
        manifest.reference_timebase_key);
end
if numel(unique(declared)) ~= numel(declared)
    error("vawlume:ingest:AlignmentTimebaseDuplicated", ...
        "manifest.timebases declares the same timebase_key more than once.");
end
native = declared([manifest.timebases.recording_native]);
if numel(native) > 1
    error("vawlume:ingest:AlignmentNativeTimebaseAmbiguous", ...
        "More than one manifest timebase declares recording_native.");
end

for index = 1:numel(manifest.streams)
    if ~ismember(manifest.streams(index).timebase_key, declared)
        error("vawlume:ingest:AlignmentStreamTimebaseUndeclared", ...
            "Stream '%s' names timebase '%s', which manifest.timebases does not declare.", ...
            manifest.streams(index).stream_key, manifest.streams(index).timebase_key);
    end
end
end

% --------------------------------------------------------------- sections ---

function value = recordingSelector(session)
%RECORDINGSELECTOR Exactly one way to name the VAWLUME recording being aligned.
requiredStruct(session, "recording");
recording = session.recording;
hasNative = isfield(recording, "native_recording_id");
hasPath = isfield(recording, "source_relative_path");
if hasNative == hasPath
    error("vawlume:ingest:AlignmentRecordingSelectorInvalid", ...
        "session.recording must contain exactly one of native_recording_id " + ...
        "or source_relative_path.");
end
if hasNative
    value = struct(mode="native_recording_id", ...
        value=requiredText(recording, "native_recording_id"));
else
    value = struct(mode="source_relative_path", ...
        value=requiredText(recording, "source_relative_path"));
end
end

function value = methodOf(document)
value = "offset";
if isfield(document, "method")
    value = requiredText(document, "method");
end
supported = ["offset", "affine", "piecewise_affine"];
if ~ismember(value, supported)
    error("vawlume:ingest:AlignmentMethodUnsupported", ...
        "Alignment method '%s' is not one of %s.", value, strjoin(supported, ", "));
end
end

function value = timebaseDeclarations(document)
items = listOf(document, "timebases");
if isempty(items)
    error("vawlume:ingest:AlignmentTimebasesMissing", ...
        "The manifest must declare at least one timebase.");
end
value = repmat(emptyTimebase(), numel(items), 1);
for index = 1:numel(items)
    item = items{index};
    value(index) = struct( ...
        timebase_key=requiredText(item, "timebase_key"), ...
        timebase_kind=requiredText(item, "timebase_kind"), ...
        recording_native=logicalField(item, "recording_native", false), ...
        native_unit=optionalTextOr(item, "native_unit", "s"), ...
        nominal_rate_hz=numericField(item, "nominal_rate_hz"), ...
        origin_description=optionalText(item, "origin_description"), ...
        clock_identifier=optionalText(item, "clock_identifier"), ...
        notes=optionalText(item, "notes"));
end
end

function value = streamDeclarations(document, repoRoot, sourceRoot)
items = listOf(document, "streams");
value = repmat(emptyStream(), numel(items), 1);
for index = 1:numel(items)
    item = items{index};
    value(index) = struct( ...
        stream_key=requiredText(item, "stream_key"), ...
        timebase_key=requiredText(item, "timebase_key"), ...
        source_path=alignmentResolvePath(requiredText(item, "source"), sourceRoot), ...
        declared_source=requiredText(item, "source"), ...
        mapping_profile_path=alignmentResolvePath( ...
            requiredText(item, "mapping_profile"), repoRoot), ...
        mapping_profile_id=optionalText(item, "mapping_profile_id"), ...
        source_role=optionalTextOr(item, "source_role", "events"), ...
        file_role=optionalTextOr(item, "file_role", "external_event_table"));
end
if numel(items) > 0 && numel(unique([value.stream_key])) ~= numel(items)
    error("vawlume:ingest:AlignmentStreamDuplicated", ...
        "manifest.streams declares the same stream_key more than once.");
end
end

function value = anchorDeclaration(document, repoRoot, sourceRoot)
value = struct(declared=false, source_path="", declared_source="", ...
    mapping_profile_path="", mapping_profile_id="", ...
    file_role="alignment_anchor_table");
if ~isfield(document, "anchors")
    return
end
item = document.anchors;
if ~isstruct(item) || ~isscalar(item)
    error("vawlume:ingest:AlignmentManifestInvalid", ...
        "manifest.anchors must be a single object.");
end
value.declared = true;
value.declared_source = requiredText(item, "source");
value.source_path = alignmentResolvePath(value.declared_source, sourceRoot);
value.mapping_profile_path = alignmentResolvePath( ...
    requiredText(item, "mapping_profile"), repoRoot);
value.mapping_profile_id = optionalText(item, "mapping_profile_id");
value.file_role = optionalTextOr(item, "file_role", "alignment_anchor_table");
end

% ---------------------------------------------------------------- shaping ---

function value = emptyTimebase()
value = struct(timebase_key="", timebase_kind="", recording_native=false, ...
    native_unit="s", nominal_rate_hz=NaN, origin_description="", ...
    clock_identifier="", notes="");
end

function value = emptyStream()
value = struct(stream_key="", timebase_key="", source_path="", ...
    declared_source="", mapping_profile_path="", mapping_profile_id="", ...
    source_role="events", file_role="external_event_table");
end

function items = listOf(container, field)
items = {};
if ~isfield(container, field)
    return
end
raw = container.(field);
if isstruct(raw)
    items = num2cell(raw);
    return
end
if iscell(raw)
    items = raw(:);
    return
end
error("vawlume:ingest:AlignmentManifestInvalid", ...
    "manifest.%s must be a list of objects.", field);
end

function requiredStruct(container, field)
if ~isstruct(container) || ~isfield(container, field) || ...
        ~isstruct(container.(field)) || ~isscalar(container.(field))
    error("vawlume:ingest:AlignmentManifestInvalid", ...
        "Alignment manifest requires object '%s'.", field);
end
end

function value = requiredText(container, field)
if ~isfield(container, field)
    error("vawlume:ingest:AlignmentManifestInvalid", ...
        "Alignment manifest requires text field '%s'.", field);
end
try
    value = string(container.(field));
catch
    value = "";
end
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:ingest:AlignmentManifestInvalid", ...
        "Alignment manifest field '%s' must be nonempty scalar text.", field);
end
value = strtrim(value);
end

function value = optionalText(container, field)
value = optionalTextOr(container, field, "");
end

function value = optionalTextOr(container, field, fallback)
value = fallback;
if ~isfield(container, field)
    return
end
try
    candidate = string(container.(field));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate) && strlength(strtrim(candidate)) > 0
    value = strtrim(candidate);
end
end

function value = logicalField(container, field, fallback)
value = fallback;
if ~isfield(container, field)
    return
end
candidate = container.(field);
if islogical(candidate) && isscalar(candidate)
    value = candidate;
end
end

function value = numericField(container, field)
value = NaN;
if ~isfield(container, field)
    return
end
candidate = container.(field);
if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
    value = double(candidate);
end
end
