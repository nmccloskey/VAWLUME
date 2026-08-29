function spec = deepsqueakExportArtifactSpec(profileDocument, artifactKey)
%DEEPSQUEAKEXPORTARTIFACTSPEC Read one artifact's declared file mechanics.
%
% Only file-format mechanics are extracted here: format, sheet selection rule,
% and header row. Field semantics stay in the profile's field_mappings and are
% interpreted by VAWLUME.SOURCE_MAPPING, never by this adapter.

arguments
    profileDocument (1,1) struct
    artifactKey (1,1) string
end

if strlength(artifactKey) == 0
    artifactKey = declaredFieldMappingArtifactKey(profileDocument);
end

declared = declaredArtifacts(profileDocument);
match = [];
for index = 1:numel(declared)
    if profileText(declared{index}, "artifact_key") == artifactKey
        match = declared{index};
        break
    end
end

if isempty(match)
    error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
        "Profile declares no artifact with artifact_key '%s'.", artifactKey);
end

spec = struct();
spec.artifact_key = artifactKey;
spec.file_format = lower(profileText(match, "format"));
spec.native_artifact_type = profileText(match, "native_artifact_type");
spec.canonical_artifact_type = profileText(match, "canonical_artifact_type");
spec.row_level = profileText(match, "row_level");
spec.sheet_selector = "first_sheet";
spec.header_row = 1;

if isfield(match, "table") && isstruct(match.table)
    selector = profileText(match.table, "sheet_selector");
    if strlength(selector) > 0
        spec.sheet_selector = selector;
    end
    headerRow = profileNumber(match.table, "header_row");
    if ~isnan(headerRow)
        spec.header_row = headerRow;
    end
end

if spec.header_row < 1 || fix(spec.header_row) ~= spec.header_row
    error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
        "Profile declares an unsupported header_row for artifact '%s': %s.", ...
        artifactKey, string(spec.header_row));
end
end

function artifactKey = declaredFieldMappingArtifactKey(profileDocument)
artifactKey = "";
if isfield(profileDocument, "field_mapping_source")
    artifactKey = profileText(profileDocument.field_mapping_source, "artifact_key");
end
if strlength(artifactKey) == 0
    error("vawlume:ingest:DeepSqueakArtifactUnsupported", ...
        "Profile declares no field_mapping_source.artifact_key to read.");
end
end

function items = declaredArtifacts(profileDocument)
items = {};
if ~isfield(profileDocument, "artifact_discovery")
    return
end
discovery = profileDocument.artifact_discovery;
if ~isstruct(discovery) || ~isfield(discovery, "artifacts")
    return
end

raw = discovery.artifacts;
if iscell(raw)
    items = raw(:)';
elseif isstruct(raw)
    items = arrayfun(@(item) item, raw(:)', UniformOutput=false);
end
end

function value = profileText(container, field)
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
    value = candidate;
end
end

function value = profileNumber(container, field)
value = NaN;
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
candidate = container.(char(field));
if isnumeric(candidate) && isscalar(candidate)
    value = double(candidate);
end
end
