function artifacts = extractorClassifyArtifacts(conn, projectId, candidates)
%EXTRACTORCLASSIFYARTIFACTS Classify portable artifact identities read-only.
%
% CANDIDATES is a cell array of extractor-owned scalar structs. This neutral
% core owns only schema identity comparison; discovery and scientific meaning
% remain with each extractor adapter.

arguments
    conn
    projectId (1,1) double
    candidates (1,:) cell
end

existing = fetch(conn, "SELECT artifact_id, path_or_uri, artifact_type, " + ...
    "IFNULL(native_artifact_type, '') AS native_artifact_type, " + ...
    "IFNULL(file_format, '') AS file_format, IFNULL(checksum_sha256, '') AS checksum_sha256, " + ...
    "is_native FROM artifacts WHERE project_id = " + string(projectId));
artifacts = emptyArtifactTable();
for index = 1:numel(candidates)
    candidate = candidates{index};
    action = "create";
    conflict = "";
    artifactId = NaN;
    if ~isempty(existing) && height(existing) > 0
        matches = string(existing.path_or_uri) == string(candidate.path_or_uri);
        if any(matches)
            stored = existing(find(matches,1),:);
            artifactId = double(stored.artifact_id(1));
            [action, conflict] = compareStored(candidate, stored);
        end
    end
    metadata = "";
    if isfield(candidate, "metadata_json"), metadata = string(candidate.metadata_json); end
    artifacts(end+1,:) = {string(candidate.role), string(candidate.artifact_type), ...
        string(candidate.native_artifact_type), string(candidate.file_format), ...
        logical(candidate.is_native), string(candidate.path_or_uri), ...
        string(candidate.runtime_path), string(candidate.checksum_sha256), ...
        string(candidate.checksum_status), string(candidate.description), metadata, ...
        action, artifactId, conflict}; %#ok<AGROW>
end
artifacts = markCandidateIdentityCollisions(artifacts);
end

function [action, message] = compareStored(candidate, stored)
action = "reuse";
message = "";
storedChecksum = presentText(stored.checksum_sha256(1));
if strlength(storedChecksum) > 0 && strlength(candidate.checksum_sha256) > 0 && ...
        storedChecksum ~= string(candidate.checksum_sha256)
    action = "conflict";
    message = "Artifact '" + string(candidate.path_or_uri) + ...
        "' is registered with checksum " + storedChecksum + ...
        " but the supplied file has checksum " + string(candidate.checksum_sha256) + ".";
    return
end
if presentText(stored.artifact_type(1)) ~= string(candidate.artifact_type)
    action = "conflict";
    message = "Artifact '" + string(candidate.path_or_uri) + ...
        "' is registered as artifact_type '" + presentText(stored.artifact_type(1)) + ...
        "' but this import treats it as '" + string(candidate.artifact_type) + "'.";
    return
end
if presentText(stored.native_artifact_type(1)) ~= string(candidate.native_artifact_type)
    action = "conflict";
    message = "Artifact '" + string(candidate.path_or_uri) + ...
        "' has different native artifact type provenance.";
    return
end
if presentText(stored.file_format(1)) ~= string(candidate.file_format) || ...
        logical(stored.is_native(1)) ~= logical(candidate.is_native)
    action = "conflict";
    message = "Artifact '" + string(candidate.path_or_uri) + ...
        "' has different format or native-artifact provenance.";
end
end

function artifacts = markCandidateIdentityCollisions(artifacts)
if height(artifacts) < 2, return, end
paths = string(artifacts.path_or_uri);
for path = unique(paths)'
    matches = paths == path;
    if nnz(matches) < 2, continue, end
    message = "Portable artifact identity '" + path + ...
        "' is declared for more than one role in this import: " + ...
        strjoin(string(artifacts.role(matches)), ", ") + ".";
    artifacts.action(matches) = "conflict";
    artifacts.conflict_message(matches) = message;
end
end

function value = emptyArtifactTable()
value = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    false(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), NaN(0,1), strings(0,1), ...
    VariableNames=["role", "artifact_type", "native_artifact_type", "file_format", ...
    "is_native", "path_or_uri", "runtime_path", "checksum_sha256", ...
    "checksum_status", "description", "metadata_json", "action", ...
    "existing_artifact_id", "conflict_message"]);
end

function text = presentText(value)
text = string(value);
text(ismissing(text)) = "";
end
