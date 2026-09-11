function [tbl, artifact] = trackingOpenArtifact(conn, stream, sourceRoot)
%TRACKINGOPENARTIFACT Resolve and read the registered artifact behind a stream.
%
% The reader opens the artifact VAWLUME registered, never an arbitrary table a
% caller happens to hold. The registered checksum is recomputed and compared, so
% a file swapped since registration is reported rather than silently trusted:
% the stream's trace inventory, sample count and coverage were all derived from
% the bytes that were there at registration time.
%
% A mismatch is a warning carried in the result rather than an error, because
% the samples are still readable and the caller may legitimately be working with
% a regenerated export. What is not acceptable is not knowing.

rows = fetch(conn, "SELECT sf.source_file_id, sf.path_or_uri, " + ...
    "IFNULL(sf.relative_path,'') AS relative_path, " + ...
    "IFNULL(sf.filename,'') AS filename, " + ...
    "IFNULL(sf.checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM external_stream_sources ess " + ...
    "JOIN source_files sf ON sf.source_file_id=ess.source_file_id " + ...
    "WHERE ess.external_stream_id=" + string(stream.external_stream_id) + ...
    " ORDER BY ess.external_stream_source_id");

if isempty(rows) || height(rows) == 0
    error("vawlume:tracking:ArtifactUnregistered", ...
        "Tracking stream '%s' has no registered source file, so there is no " + ...
        "artifact to read.", stream.stream_name);
end
if height(rows) > 1
    % One file per tracking stream is the current registration contract. A
    % multi-file stream needs a deliberate ordering rule, not a silent choice.
    error("vawlume:tracking:ArtifactAmbiguous", ...
        "Tracking stream '%s' has %d registered source files. Reading a " + ...
        "stream composed of several exports is not implemented.", ...
        stream.stream_name, height(rows));
end

registeredPath = trackingPresentText(rows.path_or_uri(1));
artifact = struct( ...
    source_file_id=double(rows.source_file_id(1)), ...
    path_or_uri=registeredPath, ...
    relative_path=trackingPresentText(rows.relative_path(1)), ...
    filename=trackingPresentText(rows.filename(1)), ...
    registered_checksum_sha256=trackingPresentText(rows.checksum_sha256(1)), ...
    observed_checksum_sha256="", ...
    checksum_status="unverified");

path = resolvePath(registeredPath, artifact.relative_path, sourceRoot);
if ~isfile(path)
    error("vawlume:tracking:ArtifactNotFound", ...
        "The registered tracking artifact '%s' does not exist. Supply " + ...
        "SourceRoot if the project moved since registration.", path);
end
artifact.runtime_path = string(path);

try
    tbl = readtable(path, TextType="string", VariableNamingRule="preserve");
catch exception
    error("vawlume:tracking:ArtifactUnreadable", ...
        "The registered tracking artifact '%s' could not be read: %s", ...
        path, exception.message);
end

artifact.observed_checksum_sha256 = trackingSha256OfFile(path);
if strlength(artifact.registered_checksum_sha256) == 0
    artifact.checksum_status = "unregistered";
elseif artifact.observed_checksum_sha256 == artifact.registered_checksum_sha256
    artifact.checksum_status = "verified";
else
    artifact.checksum_status = "changed";
end
end

function path = resolvePath(registeredPath, relativePath, sourceRoot)
%RESOLVEPATH Prefer the registered absolute path, fall back to SourceRoot.
path = string(registeredPath);
if isfile(path)
    return
end
if strlength(sourceRoot) > 0 && strlength(relativePath) > 0
    candidate = string(fullfile(sourceRoot, relativePath));
    if isfile(candidate)
        path = candidate;
        return
    end
end
if strlength(sourceRoot) > 0
    [~, stem, extension] = fileparts(path);
    candidate = string(fullfile(sourceRoot, stem + extension));
    if isfile(candidate)
        path = candidate;
    end
end
end
