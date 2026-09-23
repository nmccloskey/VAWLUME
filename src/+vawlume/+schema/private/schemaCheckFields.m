function schemaCheckFields(value, jsonPath, requiredFields, optionalFields)
%SCHEMACHECKFIELDS Require an exact field set on a decoded JSON object.
%
% Unknown fields are REJECTED rather than ignored. A misspelled "descripton"
% that is silently dropped produces an export package that advertises itself as
% self-describing while shipping a blank cell; a load failure naming the
% offending JSON path does not. Adding an optional field is a grammar change
% and a `metadata_version` bump, which is the point.
%
% This is also where duplicate JSON keys are caught. Measured during Part 1:
% `jsondecode` does not collapse a duplicate member, it RENAMES the second to
% `<name>_1`. So a duplicate arrives here as an unknown field whose name is a
% rename of a present one, and saying "duplicate" is more useful than saying
% "unknown".

arguments
    value
    jsonPath (1,1) string
    requiredFields (:,1) string
    optionalFields (:,1) string = strings(0, 1)
end

if ~isstruct(value) || ~isscalar(value)
    error("vawlume:schema:MetadataInvalidValue", ...
        "%s must be a JSON object.", jsonPath);
end

present = string(fieldnames(value));

missingFields = setdiff(requiredFields, present, "stable");
if ~isempty(missingFields)
    error("vawlume:schema:MetadataMissingField", ...
        "%s is missing required field(s): %s.", ...
        jsonPath, strjoin(missingFields, ", "));
end

unknown = setdiff(present, [requiredFields; optionalFields], "stable");
if isempty(unknown)
    return
end

duplicated = schemaDuplicateFromRename(unknown, present);
if duplicated ~= ""
    error("vawlume:schema:MetadataDuplicateEntry", ...
        "%s declares ""%s"" more than once. JSON objects may not repeat a " + ...
        "member; only the first occurrence would have been kept.", ...
        jsonPath, duplicated);
end

error("vawlume:schema:MetadataUnknownField", ...
    "%s has unrecognized field(s): %s. Allowed here: %s. " + ...
    "Adding a field is a grammar change and a metadata_version bump.", ...
    jsonPath, strjoin(unknown, ", "), ...
    strjoin(sort([requiredFields; optionalFields]), ", "));
end
