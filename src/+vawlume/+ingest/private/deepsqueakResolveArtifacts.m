function artifacts = deepsqueakResolveArtifacts(conn, projectId, export, context, roots)
%DEEPSQUEAKRESOLVEARTIFACTS Classify every artifact this import registers.
%
% Artifact identity follows the schema's UNIQUE(project_id, path_or_uri) with a
% portable path in path_or_uri. Relocating unchanged content therefore reuses the
% existing row instead of creating a second one, while the same portable path
% carrying different content is an explicit conflict rather than a silent
% overwrite.
%
% The recording's raw audio keeps the Phase 3 source_files identity and is never
% re-registered here as though it were extractor output.

arguments
    conn
    projectId (1,1) double
    export (1,1) struct
    context (1,1) struct
    roots (1,:) string
end

candidates = {};
candidates{end + 1} = exportCandidate(export);

if context.native_artifact.mode == "artifact"
    candidates{end + 1} = optionalCandidate(context.native_artifact, roots, ...
        "native_detection_container", "native_detection_container", true, ...
        "DeepSqueak native detection container");
end
if context.settings.mode == "artifact"
    candidates{end + 1} = optionalCandidate(context.settings, roots, ...
        "extractor_settings", "extractor_settings", false, ...
        "External DeepSqueak settings artifact; not a validated VAWLUME settings profile");
end
if context.model.mode == "artifact"
    candidates{end + 1} = optionalCandidate(context.model, roots, ...
        "detector_model", "detector_network", true, ...
        modelDescription(context.model));
end

existing = existingArtifacts(conn, projectId);
artifacts = emptyArtifactTable();
for index = 1:numel(candidates)
    artifacts = [artifacts; classify(candidates{index}, existing)]; %#ok<AGROW>
end
end

function candidate = exportCandidate(export)
provenance = export.artifact;
assertPortable(provenance.relative_path, provenance.runtime_path, ...
    "the DeepSqueak call-statistics export", ...
    "Supply ArtifactRoot, RepoRoot, or RelativePath.");

candidate = struct( ...
    role="event_measurement_export", ...
    artifact_type="extractor_event_export", ...
    native_artifact_type=provenance.native_artifact_type, ...
    file_format=provenance.file_format, ...
    is_native=false, ...
    path_or_uri=provenance.relative_path, ...
    runtime_path=provenance.runtime_path, ...
    checksum_sha256=provenance.checksum_sha256, ...
    checksum_status="computed", ...
    description="DeepSqueak call-statistics export imported by VAWLUME");
end

function candidate = optionalCandidate(declared, roots, artifactType, role, isNative, description)
artifactPath = declared.artifact_path;
if ~isfile(artifactPath)
    error("vawlume:ingest:DeepSqueakArtifactNotFound", ...
        "Declared %s artifact does not exist: %s", role, artifactPath);
end

location = deepsqueakPortableLocation(artifactPath, declared.relative_path, roots);
assertPortable(location.relative_path, location.runtime_path, ...
    "the declared " + role + " artifact", ...
    "Supply ArtifactRoot, RepoRoot, or a relative_path in runSpec.");

[checksum, checksumStatus] = optionalChecksum(artifactPath);
candidate = struct( ...
    role=role, ...
    artifact_type=artifactType, ...
    native_artifact_type=declared.native_type, ...
    file_format=location.extension, ...
    is_native=isNative, ...
    path_or_uri=location.relative_path, ...
    runtime_path=location.runtime_path, ...
    checksum_sha256=checksum, ...
    checksum_status=checksumStatus, ...
    description=description);
end

function description = modelDescription(model)
description = "DeepSqueak detector model (" + model.evidence_source + ")";
if strlength(model.model_label) > 0
    description = description + ": " + model.model_label;
end
end

function [checksum, status] = optionalChecksum(artifactPath)
% Detection containers and detector networks can be large. Content identity is
% still preferred, so hashing is the default and is skipped only above a
% documented ceiling, with the omission reported rather than hidden.
maximumHashBytes = 512 * 1024 * 1024;
info = dir(artifactPath);
if ~isempty(info) && double(info(1).bytes) > maximumHashBytes
    checksum = "";
    status = "skipped_large_file";
    return
end
checksum = sha256OfFile(artifactPath);
status = "computed";
end

function assertPortable(relativePath, runtimePath, subject, remedy)
if strlength(relativePath) > 0
    return
end
error("vawlume:ingest:DeepSqueakArtifactNotPortable", ...
    ['No portable path could be derived for %s (%s). An absolute runtime path ' ...
    'is not durable artifact identity, because relocating the same content ' ...
    'would create a duplicate artifact. %s'], subject, runtimePath, remedy);
end

function existing = existingArtifacts(conn, projectId)
existing = fetch(conn, ...
    "SELECT artifact_id, path_or_uri, artifact_type, " + ...
    "IFNULL(native_artifact_type, '') AS native_artifact_type, " + ...
    "IFNULL(file_format, '') AS file_format, " + ...
    "IFNULL(checksum_sha256, '') AS checksum_sha256, is_native " + ...
    "FROM artifacts WHERE project_id = " + string(projectId));
end

function row = classify(candidate, existing)
action = "create";
conflictMessage = "";
artifactId = NaN;

if ~isempty(existing) && height(existing) > 0
    matches = string(existing.path_or_uri) == candidate.path_or_uri;
    if any(matches)
        stored = existing(find(matches, 1), :);
        artifactId = double(stored.artifact_id(1));
        [action, conflictMessage] = compareStored(candidate, stored);
    end
end

row = table(candidate.role, candidate.artifact_type, ...
    candidate.native_artifact_type, candidate.file_format, ...
    candidate.is_native, candidate.path_or_uri, candidate.runtime_path, ...
    candidate.checksum_sha256, candidate.checksum_status, ...
    candidate.description, action, artifactId, conflictMessage, ...
    VariableNames=artifactVariableNames());
end

function [action, conflictMessage] = compareStored(candidate, stored)
action = "reuse";
conflictMessage = "";

storedChecksum = string(stored.checksum_sha256(1));
if strlength(storedChecksum) > 0 && strlength(candidate.checksum_sha256) > 0 && ...
        storedChecksum ~= candidate.checksum_sha256
    action = "conflict";
    conflictMessage = "Artifact '" + candidate.path_or_uri + ...
        "' is registered with checksum " + storedChecksum + ...
        " but the supplied file has checksum " + candidate.checksum_sha256 + ".";
    return
end

storedType = string(stored.artifact_type(1));
if storedType ~= candidate.artifact_type
    action = "conflict";
    conflictMessage = "Artifact '" + candidate.path_or_uri + ...
        "' is registered as artifact_type '" + storedType + ...
        "' but this import treats it as '" + candidate.artifact_type + "'.";
end
end

function names = artifactVariableNames()
names = ["role", "artifact_type", "native_artifact_type", "file_format", ...
    "is_native", "path_or_uri", "runtime_path", "checksum_sha256", ...
    "checksum_status", "description", "action", "existing_artifact_id", ...
    "conflict_message"];
end

function value = emptyArtifactTable()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    false(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), NaN(0, 1), strings(0, 1), ...
    VariableNames=artifactVariableNames());
end
