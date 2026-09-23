function tf = schemaIsPlainIdentifier(names)
%SCHEMAISPLAINIDENTIFIER Whether each name is a plain SQL/MATLAB identifier.
%
% Measured during Part 1: all 107 object names and all 1,155 column names in
% the schema satisfy this, none exceeds MATLAB's 63-character name limit, and
% none collides with a MATLAB keyword.
%
% The check is not decoration. `jsondecode` maps JSON object keys to struct
% field names and MANGLES any key that is not a valid identifier -- measured,
% "col with space" decodes to `colWithSpace` and "2start" to `x2start`. A
% mangled key would then fail to match its structural counterpart with a
% confusing "unknown object" message. Refusing the name outright says what is
% actually wrong.

arguments
    names string
end

tf = ~cellfun(@isempty, regexp(cellstr(names), "^[A-Za-z][A-Za-z0-9_]*$", "once")) ...
    & strlength(names) <= namelengthmax;
tf = reshape(tf, size(names));
end
