function [ir, projectSpec] = validateProjectInputs(ir, projectSpec)
%VALIDATEPROJECTINPUTS Validate only the intake boundary over interpreted IR.

requiredTopLevel = ["profile", "sources", "records", "relationships", ...
    "valid_for_ingest"];
requireStructFields(ir, requiredTopLevel, "IR");
if ~isscalar(ir.valid_for_ingest) || ~islogical(ir.valid_for_ingest)
    intakeError("InvalidIR", "IR valid_for_ingest must be a scalar logical value.");
end
if ~ir.valid_for_ingest
    intakeError("IntakeNotReady", ...
        "Project intake requires IR with valid_for_ingest equal to true.");
end

requiredProfile = ["profile_key", "profile_name", "profile_kind", ...
    "profile_version", "profile_schema_version", "profile_content_format", ...
    "profile_path", "profile_checksum"];
requireStructFields(ir.profile, requiredProfile, "IR profile");
profile = ir.profile;
requireText(profile.profile_key, "IR profile_key", "InvalidIR");
requireText(profile.profile_name, "IR profile_name", "InvalidIR");
requireText(profile.profile_kind, "IR profile_kind", "InvalidIR");
requireText(profile.profile_version, "IR profile_version", "InvalidIR");
requireText(profile.profile_schema_version, "IR profile_schema_version", "InvalidIR");
requireText(profile.profile_content_format, "IR profile_content_format", "InvalidIR");
requireText(profile.profile_path, "IR profile_path", "InvalidIR");
requireText(profile.profile_checksum, "IR profile_checksum", "InvalidIR");
if string(profile.profile_kind) ~= "project_input"
    intakeError("InvalidIR", ...
        "Project intake requires profile_kind 'project_input'; received '%s'.", ...
        string(profile.profile_kind));
end

projectSpec = normalizeProjectSpec(projectSpec);
validateTables(ir);
end

function projectSpec = normalizeProjectSpec(projectSpec)
if ~isstruct(projectSpec) || ~isscalar(projectSpec) || ...
        ~all(isfield(projectSpec, cellstr(["project_key", "project_name"])))
    intakeError("InvalidProjectSpec", ...
        "projectSpec requires project_key and project_name.");
end
projectSpec.project_key = requireText(projectSpec.project_key, ...
    "projectSpec.project_key", "InvalidProjectSpec");
projectSpec.project_name = requireText(projectSpec.project_name, ...
    "projectSpec.project_name", "InvalidProjectSpec");
if isfield(projectSpec, "description")
    projectSpec.description = optionalText(projectSpec.description, ...
        "projectSpec.description", "InvalidProjectSpec");
else
    projectSpec.description = "";
end
end

function validateTables(ir)
sourceFields = ["source_key", "runtime_path", "relative_path", "filename", ...
    "source_type", "artifact_type", "status", "checksum_sha256"];
recordFields = ["record_key", "source_key", "native_level", ...
    "canonical_level", "native_identifier", "record_scope", "role_label", ...
    "mapping_rule", "status"];
relationshipFields = ["relationship_key", "source_key", ...
    "from_record_key", "to_record_key", "native_relationship", ...
    "canonical_relationship", "role_label", "mapping_rule", "status"];
requireTableFields(ir.sources, sourceFields, "IR sources");
requireTableFields(ir.records, recordFields, "IR records");
requireTableFields(ir.relationships, relationshipFields, "IR relationships");

sourceKeys = requiredUniqueColumn(ir.sources.source_key, "IR source_key");
relativePaths = requiredUniqueColumn(ir.sources.relative_path, ...
    "IR source relative_path");
if any(contains(relativePaths, "\"))
    intakeError("InvalidIR", ...
        "IR source relative_path values must already use portable forward slashes.");
end

recordKeys = requiredUniqueColumn(ir.records.record_key, "IR record_key");
recordSourceKeys = string(ir.records.source_key);
if any(~ismember(recordSourceKeys, sourceKeys))
    intakeError("InvalidIR", "IR records reference unknown source keys.");
end
if any(strlength(string(ir.records.native_level)) == 0) || ...
        any(strlength(string(ir.records.canonical_level)) == 0) || ...
        any(strlength(string(ir.records.native_identifier)) == 0)
    intakeError("InvalidIR", "IR records lack logical identity required by intake.");
end
allowedScopes = ["entity", "membership", "source_recording"];
if any(~ismember(string(ir.records.record_scope), allowedScopes))
    intakeError("InvalidIR", ...
        "Project IR records contain unsupported record_scope values.");
end
if any(strlength(string(ir.relationships.canonical_relationship)) == 0)
    intakeError("InvalidIR", ...
        "IR relationships require canonical_relationship values.");
end

relationshipSourceKeys = string(ir.relationships.source_key);
if ~isempty(ir.relationships)
    requiredUniqueColumn(ir.relationships.relationship_key, ...
        "IR relationship_key");
end
if any(~ismember(relationshipSourceKeys, sourceKeys))
    intakeError("InvalidIR", "IR relationships reference unknown source keys.");
end
relationshipRecordKeys = [string(ir.relationships.from_record_key); ...
    string(ir.relationships.to_record_key)];
if any(~ismember(relationshipRecordKeys, recordKeys))
    intakeError("InvalidIR", "IR relationships reference unknown record keys.");
end

recordingRows = string(ir.records.record_scope) == "source_recording";
for sourceIndex = 1:numel(sourceKeys)
    matches = recordingRows & recordSourceKeys == sourceKeys(sourceIndex);
    if sum(matches) ~= 1
        intakeError("InvalidIR", ...
            "Each source must resolve to exactly one source_recording record; '%s' resolves to %d.", ...
            sourceKeys(sourceIndex), sum(matches));
    end
end
end

function requireStructFields(value, names, label)
if ~isstruct(value) || ~isscalar(value)
    intakeError("InvalidIR", "%s must be a scalar struct.", label);
end
missing = names(~isfield(value, cellstr(names)));
if ~isempty(missing)
    intakeError("InvalidIR", "%s is missing required fields: %s.", ...
        label, strjoin(missing, ", "));
end
end

function requireTableFields(value, names, label)
if ~istable(value)
    intakeError("InvalidIR", "%s must be a table.", label);
end
missing = names(~ismember(names, string(value.Properties.VariableNames)));
if ~isempty(missing)
    intakeError("InvalidIR", "%s is missing required columns: %s.", ...
        label, strjoin(missing, ", "));
end
end

function values = requiredUniqueColumn(values, label)
values = string(values);
if isempty(values)
    intakeError("InvalidIR", "%s must contain at least one value.", label);
end
if any(ismissing(values)) || any(strlength(values) == 0)
    intakeError("InvalidIR", "%s values must be nonempty.", label);
end
if numel(unique(values)) ~= numel(values)
    intakeError("InvalidIR", "%s values must be unique.", label);
end
end

function value = requireText(value, label, suffix)
value = optionalText(value, label, suffix);
if strlength(value) == 0
    intakeError(suffix, "%s must be nonempty.", label);
end
end

function value = optionalText(value, label, suffix)
try
    value = string(value);
catch
    intakeError(suffix, "%s must be scalar text.", label);
end
if ~isscalar(value) || ismissing(value)
    intakeError(suffix, "%s must be scalar text.", label);
end
end

function intakeError(suffix, message, varargin)
error("vawlume:ingest:" + suffix, message, varargin{:});
end
