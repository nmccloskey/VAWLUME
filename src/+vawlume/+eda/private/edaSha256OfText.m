function digest = edaSha256OfText(text)
%EDASHA256OFTEXT Lowercase SHA-256 hex digest of one UTF-8 encoded string.
%
% Used to derive configuration identifiers from their parameter values. This is
% a digest over TEXT, not over a file: the repository's specification checksum
% remains the matcher's own file hash, and the two are deliberately different
% things. A configuration identifier names a point in the design; a specification
% checksum names the exact bytes a matching analysis ran under.
%
% java.security.MessageDigest, matching how the rest of the repository hashes,
% so no toolbox is required.
bytes = unicode2native(char(text), "UTF-8");
engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(typecast(uint8(bytes(:))', "int8"));
raw = typecast(engine.digest(), "uint8");
digest = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
end
