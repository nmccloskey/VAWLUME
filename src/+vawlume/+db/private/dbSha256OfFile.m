function hash = dbSha256OfFile(path)
%DBSHA256OFFILE Lowercase SHA-256 digest of a registered profile's exact bytes.
%
% The checksum is what makes a profile version immutable in practice: a stored
% decision or imported window cites a version by ID, and the checksum is how a
% later reader confirms the file they are holding is the one that was registered.

fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:db:ProfileReadFailed", ...
        "Could not open profile for hashing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
digest = java.security.MessageDigest.getInstance("SHA-256");
while true
    bytes = fread(fileId, 4 * 1024 * 1024, "*uint8");
    if isempty(bytes)
        break
    end
    digest.update(typecast(bytes(:)', "int8"));
end
hashBytes = typecast(digest.digest(), "uint8");
hash = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
delete(cleaner);
end
