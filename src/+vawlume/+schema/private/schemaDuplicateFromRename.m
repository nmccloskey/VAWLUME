function name = schemaDuplicateFromRename(candidates, present)
%SCHEMADUPLICATEFROMRENAME Recover the original name behind a jsondecode rename.
%
% `jsondecode` renames a repeated JSON member to `<name>_1`, `<name>_2`, and so
% on rather than dropping it -- measured during Part 1. Given a candidate that
% is not a recognized name, this reports the base name when that base is also
% present, which is the signature of a duplicate rather than of a typo.
%
% Both conditions are required. `<name>_1` alone could be a real identifier;
% `<name>_1` alongside `<name>` in one JSON object could not, because a decoded
% object cannot contain two members of the same name by any other route.
%
% Measured: no VAWLUME object or column name ends in an underscore followed by
% digits -- 0 of 618 distinct identifiers -- so this cannot misread a real name
% in the current schema.

arguments
    candidates (:,1) string
    present (:,1) string
end

name = "";

for k = 1:numel(candidates)
    token = regexp(candidates(k), "^(.+)_\d+$", "tokens", "once");
    if isempty(token)
        continue
    end
    base = string(token{1});
    if ismember(base, present)
        name = base;
        return
    end
end
end
