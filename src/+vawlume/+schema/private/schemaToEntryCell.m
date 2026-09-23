function entries = schemaToEntryCell(value)
%SCHEMATOENTRYCELL Normalize a decoded JSON array of objects to a cell array.
%
% `jsondecode` returns a JSON array of objects as a struct array when every
% element has identical fields and as a cell array when they differ -- measured
% during Part 1, and both shapes occur in schema.json, whose table entries are
% heterogeneous (views carry `referenced_tables`, tables carry `indexes`).
% A single-element array decodes to a 1x1 struct, which is indistinguishable in
% shape from a scalar object.
%
% Code that assumes one shape fails on the other with "Dot indexing is not
% supported for variables of type cell", so every caller normalizes here first.

if iscell(value)
    entries = value(:);
elseif isstruct(value)
    entries = num2cell(value(:));
elseif isempty(value)
    entries = cell(0, 1);
else
    error("vawlume:schema:StructuralArtifactMissing", ...
        "Expected a JSON array of objects, got %s.", class(value));
end
end
