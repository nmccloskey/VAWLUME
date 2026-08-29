function hash = sha256OfFile(path)
%SHA256OFFILE Lowercase hex SHA-256 digest of a file's exact bytes.
%
% Artifact provenance uses content identity rather than runtime location, so
% the digest is taken over the raw bytes without newline or encoding
% normalization.

fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:ingest:FileReadFailed", ...
        "Could not open file for hashing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
digest = java.security.MessageDigest.getInstance("SHA-256");
chunkBytes = 4 * 1024 * 1024;
while true
    bytes = fread(fileId, chunkBytes, "*uint8");
    if isempty(bytes)
        break
    end
    digest.update(typecast(bytes(:)', "int8"));
end
hashBytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
delete(cleaner);
end
