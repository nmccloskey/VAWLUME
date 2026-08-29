function spec = mupetExportArtifactSpec(profileDocument, artifactKey)
%MUPETEXPORTARTIFACTSPEC Extract profile-declared CSV file mechanics.

arguments
    profileDocument (1,1) struct
    artifactKey (1,1) string
end

if strlength(artifactKey) == 0
    artifactKey = profileText(profileDocument.field_mapping_source, "artifact_key");
end
artifacts = normalizeSequence(profileDocument.artifact_discovery.artifacts);
match = [];
for index = 1:numel(artifacts)
    if profileText(artifacts{index}, "artifact_key") == artifactKey
        match = artifacts{index};
        break
    end
end
if isempty(match)
    error("vawlume:ingest:MupetArtifactUnsupported", ...
        "Profile declares no artifact with artifact_key '%s'.", artifactKey);
end

spec = struct(artifact_key=artifactKey, ...
    file_format=lower(profileText(match, "format")), ...
    native_artifact_type=profileText(match, "native_artifact_type"), ...
    canonical_artifact_type=profileText(match, "canonical_artifact_type"), ...
    row_level=profileText(match, "row_level"), ...
    header_row=1, delimiter=",");
if isfield(match, "table") && isstruct(match.table)
    if isfield(match.table, "header_row")
        spec.header_row = double(match.table.header_row);
    end
    declaredDelimiter = profileText(match.table, "delimiter");
    if strlength(declaredDelimiter) > 0
        spec.delimiter = declaredDelimiter;
    end
end
if spec.file_format ~= "csv" || spec.header_row < 1 || ...
        fix(spec.header_row) ~= spec.header_row || strlength(spec.delimiter) ~= 1
    error("vawlume:ingest:MupetArtifactUnsupported", ...
        "Profile declares unsupported CSV mechanics for artifact '%s'.", artifactKey);
end
end

function items = normalizeSequence(raw)
if iscell(raw)
    items = raw(:)';
elseif isstruct(raw)
    items = arrayfun(@(item) item, raw(:)', UniformOutput=false);
else
    items = {};
end
end

function value = profileText(container, field)
value = "";
if isstruct(container) && isfield(container, char(field))
    candidate = string(container.(char(field)));
    if isscalar(candidate) && ~ismissing(candidate)
        value = candidate;
    end
end
end
