function hash = consilienceSha256OfFile(path)
%CONSILIENCESHA256OFFILE Lowercase SHA-256 digest of exact specification bytes.

fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:consilience:SpecificationReadFailed", ...
        "Could not open matching specification for hashing: %s", path);
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
