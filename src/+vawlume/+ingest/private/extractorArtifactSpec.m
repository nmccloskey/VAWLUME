function spec = extractorArtifactSpec(profileDocument, artifactKey, errorToken)
%EXTRACTORARTIFACTSPEC Read profile-declared file mechanics for one artifact.

arguments
    profileDocument (1,1) struct
    artifactKey (1,1) string
    errorToken (1,1) string
end

if strlength(artifactKey) == 0
    artifactKey = "";
    if isfield(profileDocument, "field_mapping_source")
        artifactKey = profileText(profileDocument.field_mapping_source, "artifact_key");
    end
end
identifier = "vawlume:ingest:" + errorToken + "ArtifactUnsupported";
if strlength(artifactKey) == 0
    error(identifier, "Profile declares no field_mapping_source.artifact_key to read.");
end

items = declaredArtifacts(profileDocument);
match = [];
for index = 1:numel(items)
    if profileText(items{index}, "artifact_key") == artifactKey
        match = items{index};
        break
    end
end
if isempty(match)
    error(identifier, "Profile declares no artifact with artifact_key '%s'.", artifactKey);
end

spec = struct(artifact_key=artifactKey, ...
    file_format=lower(profileText(match, "format")), ...
    native_artifact_type=profileText(match, "native_artifact_type"), ...
    canonical_artifact_type=profileText(match, "canonical_artifact_type"), ...
    row_level=profileText(match, "row_level"), ...
    sheet_selector="first_sheet", header_row=1, delimiter=",");
if isfield(match, "table") && isstruct(match.table)
    selector = profileText(match.table, "sheet_selector");
    if strlength(selector) > 0, spec.sheet_selector = selector; end
    number = profileNumber(match.table, "header_row");
    if ~isnan(number), spec.header_row = number; end
    delimiter = profileText(match.table, "delimiter");
    if strlength(delimiter) > 0, spec.delimiter = delimiter; end
end
if spec.header_row < 1 || fix(spec.header_row) ~= spec.header_row
    error(identifier, "Profile declares an unsupported header_row for artifact '%s': %s.", ...
        artifactKey, string(spec.header_row));
end
end

function items = declaredArtifacts(document)
items = {};
if ~isfield(document, "artifact_discovery") || ...
        ~isfield(document.artifact_discovery, "artifacts"), return, end
raw = document.artifact_discovery.artifacts;
if iscell(raw), items = raw(:)';
elseif isstruct(raw), items = arrayfun(@(item) item, raw(:)', UniformOutput=false);
end
end

function value = profileText(container, field)
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
    value = candidate;
end
end

function value = profileNumber(container, field)
value = NaN;
if isstruct(container) && isfield(container, char(field))
    candidate = container.(char(field));
    if isnumeric(candidate) && isscalar(candidate), value = double(candidate); end
end
end
