function joined = schemaJoinColumns(columns)
%SCHEMAJOINCOLUMNS Render an endpoint's column list as one comparable string.
%
% Relationship endpoints are stored as arrays so a composite foreign key needs
% no grammar change. Measured during Part 1: the schema currently has ZERO
% composite foreign keys, so every list is length one today.
%
% Order is significant and is preserved: (a, b) and (b, a) are different
% endpoints, so the join must not sort.

arguments
    columns (:,1) string
end

joined = strjoin(columns, ";");
if joined == ""
    joined = string(missing);
end
end
