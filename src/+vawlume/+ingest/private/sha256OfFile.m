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
bytes = fread(fileId, Inf, "*uint8")';

digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(bytes, "int8"));
hashBytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
delete(cleaner);
end
