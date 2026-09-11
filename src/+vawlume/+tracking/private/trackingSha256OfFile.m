function hash = trackingSha256OfFile(path)
%TRACKINGSHA256OFFILE Lowercase SHA-256 digest of exact artifact bytes.
%
% This is what makes a later window read verifiable: it identifies the exact
% file whose traces and span were summarized at registration, so a silently
% replaced export is detectable rather than assumed equivalent.

fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:tracking:ArtifactUnreadable", ...
        "Could not open tracking artifact for hashing: %s", path);
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
