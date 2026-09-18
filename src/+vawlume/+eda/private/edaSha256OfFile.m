function digest = edaSha256OfFile(path)
%EDASHA256OFFILE Lowercase SHA-256 digest of a file's exact bytes.
%
% Reported for convenience beside each generated specification, so a caller can
% see that two configurations differ without opening them. It mirrors the
% matcher's own file hash, over the same bytes with the same algorithm, so the
% two values agree by construction.
%
% THE MATCHER'S HASH REMAINS AUTHORITATIVE for analysis identity. This one is a
% report. An integration test asserts the two agree on a real generated file
% rather than leaving that as an assumption.
fileId = fopen(path, "rb");
if fileId < 0
    error("vawlume:eda:SpecificationUnreadable", ...
        "Could not open generated specification for hashing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
engine = java.security.MessageDigest.getInstance("SHA-256");
while true
    block = fread(fileId, 4 * 1024 * 1024, "*uint8");
    if isempty(block)
        break
    end
    engine.update(typecast(block(:)', "int8"));
end
raw = typecast(engine.digest(), "uint8");
digest = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
delete(cleaner);
end
