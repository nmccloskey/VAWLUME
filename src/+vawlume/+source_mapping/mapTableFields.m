function mapped = mapTableFields(tbl, profileInput, options)
%MAPTABLEFIELDS Map an already-loaded MATLAB table through profile rules.
%
% This is a generic table-field interpreter for extractor-output profiles. It
% does not read extractor artifacts and does not write database rows.

arguments
    tbl table
    profileInput
    options.ProfileId (1,1) string = ""
    options.SourceKey (1,1) string = ""
    options.ArtifactKey (1,1) string = ""
end

[profileEntry, profileLocation] = selectExtractorOutputProfile(profileInput, options.ProfileId);
fieldMappings = normalizeMappingSequence(profileEntry.field_mappings);
sourceArtifactType = mappingArtifactKey(profileEntry, options.ArtifactKey);
rowCount = height(tbl);

records = repmat(blankMappedFieldRecord(), max(rowCount * numel(fieldMappings), 1), 1);
recordCount = 0;
issues = emptyIssueArray();

for mappingIndex = 1:numel(fieldMappings)
    mapping = fieldMappings{mappingIndex};
    mappingLocation = profileLocation + ".field_mappings(" + mappingIndex + ")";
    [actualField, resolutionStatus, columnIssue] = resolveSourceColumn(tbl, mapping, mappingLocation);
    if ~isempty(columnIssue)
        issues = appendIssue(issues, columnIssue);
        continue
    end

    for rowIndex = 1:rowCount
        rawValue = tableValue(tbl, actualField, rowIndex);
        [record, rowIssues] = mapOneValue(rawValue, profileEntry, mapping, mappingIndex, ...
            mappingLocation, rowIndex, sourceArtifactType, options.SourceKey, ...
            actualField, resolutionStatus);
        recordCount = recordCount + 1;
        records(recordCount) = record;
        issues = appendIssues(issues, rowIssues);
    end
end
records = records(1:recordCount);

mapped = struct();
mapped.profile_id = string(profileEntry.profile.id);
mapped.profile_kind = string(profileEntry.profile.kind);
mapped.extractor_name = optionalText(profileEntry.extractor, "name");
mapped.source_key = string(options.SourceKey);
mapped.source_artifact_type = sourceArtifactType;
mapped.row_count = rowCount;
mapped.mapped_record_count = numel(records);
mapped.records = records;
mapped.record_table = mappedRecordsToTable(records);
mapped.issues = issues;
mapped.issue_table = sourceMappingIssuesToTable(issues);
mapped.error_count = issueCount(issues, "error");
mapped.warning_count = issueCount(issues, "warning");
mapped.info_count = issueCount(issues, "info");
mapped.is_valid = mapped.error_count == 0;
mapped.column_resolution_policy = "exact_source_field_then_declared_aliases_only";
mapped.transform_registry = supportedTransformKeys();
end

function [record, issues] = mapOneValue(rawValue, profileEntry, mapping, mappingIndex, ...
        mappingLocation, rowIndex, sourceArtifactType, sourceKey, actualField, resolutionStatus)
issues = emptyIssueArray();
record = baseMappedFieldRecord(profileEntry, mapping, mappingIndex, mappingLocation, ...
    rowIndex, sourceArtifactType, sourceKey, actualField, resolutionStatus, rawValue);

[isMissingValue, missingCode] = isExplicitMissing(rawValue, mapping);
if isMissingValue
    record.status = "missing";
    record.native_value_type = "missing";
    record.canonical_value_type = "missing";
    record.transform_status = "not_run_missing";
    issues = appendIssue(issues, makeIssue("info", missingCode, mappingLocation, ...
        "Source value is explicitly missing; raw token was preserved."));
    return
end

[record, nativeOk, nativeIssue] = assignNativeValue(record, rawValue, mapping, mappingLocation);
if ~nativeOk
    record.status = "invalid";
    record.canonical_value_type = "invalid";
    issues = appendIssue(issues, nativeIssue);
    return
end

[mappedByValue, mappingValue, valueMappingIssue] = declaredValueMapping(record.native_raw_token, mapping, mappingLocation);
if ~isempty(valueMappingIssue)
    record.status = "invalid";
    record.canonical_value_type = "invalid";
    issues = appendIssue(issues, valueMappingIssue);
    return
elseif mappedByValue
    record.status = "mapped";
    record.canonical_value_type = "text";
    record.canonical_value_text = mappingValue;
    record.transform_status = "value_mapping";
    return
end

transformKey = optionalText(mapping, "transform");
if strlength(transformKey) == 0
    record.status = "mapped";
    record.transform_status = "not_declared";
    record = copyNativeToCanonical(record);
    return
end

[canonicalValue, transformReport] = vawlume.source_mapping.applyTransform(nativeScalar(record), transformKey);
record.transform_status = transformReport.status;
issues = appendIssues(issues, transformReport.issues);
if ~transformReport.is_valid
    record.status = "invalid";
    record.canonical_value_type = "invalid";
    return
end

record.status = "mapped";
record = assignCanonicalValue(record, canonicalValue, canonicalTypeFor(record));
end

function record = baseMappedFieldRecord(profileEntry, mapping, mappingIndex, mappingLocation, ...
        rowIndex, sourceArtifactType, sourceKey, actualField, resolutionStatus, rawValue)
record = blankMappedFieldRecord();
record.source_key = string(sourceKey);
record.source_artifact_type = string(sourceArtifactType);
record.source_row = rowIndex;
record.profile_id = string(profileEntry.profile.id);
record.extractor_name = optionalText(profileEntry.extractor, "name");
record.mapping_index = mappingIndex;
record.mapping_rule_id = "field_mappings(" + string(mappingIndex) + ")";
record.profile_location = mappingLocation;
record.native_field_name = string(mapping.source_field);
record.actual_source_field = string(actualField);
record.column_resolution = string(resolutionStatus);
record.target_level = string(mapping.target_level);
record.canonical_field = string(mapping.canonical_field);
record.data_type = optionalText(mapping, "data_type");
record.native_unit = optionalText(mapping, "native_unit");
record.canonical_unit = optionalText(mapping, "canonical_unit");
record.native_raw_token = rawToken(rawValue);
record.transform_key = optionalText(mapping, "transform");
record.derivation_stage = optionalText(mapping, "derivation_stage");
record.operational_variant = optionalText(mapping, "operational_variant");
record.operational_definition = optionalText(mapping, "operational_definition");
record.equivalence_class = optionalText(mapping, "equivalence_class");
record.cross_extractor_relationship = optionalText(mapping, "cross_extractor_relationship");
record.consilience_role = optionalText(mapping, "consilience_role");
record.semantic_role = optionalText(mapping, "semantic_role");
record.preserve_raw = mappingPreserveRaw(mapping);
record.status = "not_mapped";
end

function [record, ok, issue] = assignNativeValue(record, rawValue, mapping, mappingLocation)
ok = true;
issue = [];
dataType = optionalText(mapping, "data_type");
switch dataType
    case {"float", "float_or_missing"}
        [number, numberOk, message] = coerceDouble(rawValue);
        if ~numberOk
            ok = false;
            issue = makeIssue("error", "FIELD_VALUE_COERCION_FAILED", ...
                mappingLocation + ".data_type", message);
            record.native_value_type = "invalid";
        else
            record.native_value_type = "real";
            record.native_value_real = number;
        end
    case "integer"
        [integerValue, integerOk, message] = coerceInteger(rawValue);
        if ~integerOk
            ok = false;
            issue = makeIssue("error", "FIELD_VALUE_COERCION_FAILED", ...
                mappingLocation + ".data_type", message);
            record.native_value_type = "invalid";
        else
            record.native_value_type = "integer";
            record.native_value_integer = integerValue;
        end
    case "string"
        record.native_value_type = "text";
        record.native_value_text = rawToken(rawValue);
    otherwise
        ok = false;
        issue = makeIssue("error", "FIELD_MAPPING_UNSUPPORTED_DATA_TYPE", ...
            mappingLocation + ".data_type", ...
            "Unsupported field mapping data_type: " + dataType + ".");
        record.native_value_type = "invalid";
end
end

function [number, ok, message] = coerceDouble(value)
ok = true;
message = "";
if isnumeric(value) || islogical(value)
    number = double(value);
elseif isstring(value) || ischar(value) || iscellstr(value)
    number = str2double(string(value));
else
    number = NaN;
end
if ~isscalar(number) || isnan(number)
    ok = false;
    message = "Source value could not be converted to a numeric scalar: " + rawToken(value) + ".";
end
end

function [integerValue, ok, message] = coerceInteger(value)
[number, ok, message] = coerceDouble(value);
integerValue = NaN;
if ~ok
    return
end
if fix(number) ~= number
    ok = false;
    message = "Source value could not be converted to an integer scalar: " + rawToken(value) + ".";
else
    integerValue = number;
end
end

function [isMissingValue, code] = isExplicitMissing(value, mapping)
code = "FIELD_VALUE_MISSING";
isMissingValue = isMatlabMissing(value);
if isMissingValue
    return
end

if ~(hasProfileField(mapping, "missing_value_policy") || optionalText(mapping, "data_type") == "float_or_missing")
    return
end

token = lower(strtrim(rawToken(value)));
sentinels = ["", "na", "n/a", "nan", "missing", "null", "none"];
isMissingValue = ismember(token, sentinels);
if isMissingValue
    code = "FIELD_VALUE_EXPLICIT_MISSING";
end
end

function tf = isMatlabMissing(value)
tf = false;
if isempty(value)
    tf = true;
    return
end
try
    missingMask = ismissing(value);
    tf = isscalar(missingMask) && missingMask;
catch
end
if ~tf && isnumeric(value) && isscalar(value)
    tf = isnan(value);
end
end

function [mappedByValue, mappingValue, issue] = declaredValueMapping(nativeRawToken, mapping, mappingLocation)
mappedByValue = false;
mappingValue = "";
issue = [];
if ~hasProfileField(mapping, "value_mapping") || ~isstruct(mapping.value_mapping)
    return
end

fieldName = valueMappingField(nativeRawToken);
if isfield(mapping.value_mapping, fieldName)
    mappedByValue = true;
    mappingValue = string(mapping.value_mapping.(fieldName));
else
    issue = makeIssue("error", "FIELD_VALUE_MAPPING_UNMATCHED", ...
        mappingLocation + ".value_mapping", ...
        "Source value has no declared value_mapping entry: " + nativeRawToken + ".");
end
end

function fieldName = valueMappingField(value)
value = string(value);
number = str2double(value);
if ~isnan(number) && fix(number) == number
    fieldName = "x" + string(number);
else
    fieldName = matlab.lang.makeValidName(char(value));
end
fieldName = char(fieldName);
end

function scalar = nativeScalar(record)
switch record.native_value_type
    case "real"
        scalar = record.native_value_real;
    case "integer"
        scalar = record.native_value_integer;
    case "text"
        scalar = record.native_value_text;
    otherwise
        scalar = [];
end
end

function record = copyNativeToCanonical(record)
switch record.native_value_type
    case "real"
        record.canonical_value_type = "real";
        record.canonical_value_real = record.native_value_real;
    case "integer"
        record.canonical_value_type = "integer";
        record.canonical_value_integer = record.native_value_integer;
    case "text"
        record.canonical_value_type = "text";
        record.canonical_value_text = record.native_value_text;
    otherwise
        record.canonical_value_type = record.native_value_type;
end
end

function type = canonicalTypeFor(record)
if record.native_value_type == "integer" && record.transform_key == "identity"
    type = "integer";
else
    type = "real";
end
end

function record = assignCanonicalValue(record, value, valueType)
record.canonical_value_type = valueType;
switch valueType
    case "integer"
        record.canonical_value_integer = double(value);
    case "real"
        record.canonical_value_real = double(value);
    case "text"
        record.canonical_value_text = string(value);
end
end

function [actualField, status, issue] = resolveSourceColumn(tbl, mapping, mappingLocation)
actualField = "";
status = "";
issue = [];
variableNames = string(tbl.Properties.VariableNames);
sourceField = string(mapping.source_field);
exactMatch = variableNames(variableNames == sourceField);
if ~isempty(exactMatch)
    actualField = exactMatch(1);
    status = "exact";
    return
end

aliases = strings(0, 1);
if hasProfileField(mapping, "aliases")
    aliases = normalizeTextSequence(mapping.aliases);
end
aliasMatches = variableNames(ismember(variableNames, aliases));
if isscalar(aliasMatches)
    actualField = aliasMatches(1);
    status = "alias";
elseif numel(aliasMatches) > 1
    issue = makeIssue("error", "FIELD_MAPPING_COLUMN_AMBIGUOUS", ...
        mappingLocation + ".aliases", ...
        "Multiple declared aliases are present for source field " + sourceField + ": " + ...
        strjoin(aliasMatches, ", ") + ".");
else
    issue = missingColumnIssue(mapping, mappingLocation, sourceField);
end
end

function issue = missingColumnIssue(mapping, mappingLocation, sourceField)
severity = "error";
code = "FIELD_MAPPING_COLUMN_MISSING";
if hasProfileField(mapping, "required")
    try
        if ~logical(mapping.required)
            severity = "info";
            code = "FIELD_MAPPING_OPTIONAL_COLUMN_MISSING";
        end
    catch
    end
end
issue = makeIssue(severity, code, mappingLocation + ".source_field", ...
    "Mapped source field is absent from the supplied table: " + sourceField + ".");
end

function value = tableValue(tbl, columnName, rowIndex)
column = tbl.(char(columnName));
if iscell(column)
    value = column{rowIndex};
else
    value = column(rowIndex, :);
end
if iscategorical(value)
    value = string(value);
end
end

function token = rawToken(value)
if isempty(value)
    token = "";
elseif iscell(value)
    token = rawToken(value{1});
elseif isstring(value) || ischar(value) || iscellstr(value)
    token = string(value);
    if ~isscalar(token)
        token = strjoin(token, " ");
    end
elseif isnumeric(value) || islogical(value)
    if isscalar(value)
        token = string(sprintf("%.15g", double(value)));
    else
        token = string(mat2str(double(value)));
    end
elseif iscategorical(value)
    token = string(value);
else
    try
        token = string(value);
    catch
        token = "<unsupported>";
    end
end
if ismissing(token)
    token = "";
end
end

function artifactKey = mappingArtifactKey(profileEntry, override)
artifactKey = string(override);
if strlength(artifactKey) > 0
    return
end
artifactKey = optionalText(profileEntry.field_mapping_source, "artifact_key");
end

function tf = mappingPreserveRaw(mapping)
tf = true;
if hasProfileField(mapping, "preserve_raw")
    try
        tf = logical(mapping.preserve_raw);
    catch
    end
end
end

function issues = appendIssues(issues, newIssues)
for index = 1:numel(newIssues)
    issues = appendIssue(issues, newIssues(index));
end
end

function issues = appendIssue(issues, issue)
if isempty(issue)
    return
end
if isempty(issues)
    issues = issue;
else
    issues(numel(issues) + 1) = issue;
end
end

function count = issueCount(issues, severity)
count = 0;
for index = 1:numel(issues)
    if string(issues(index).severity) == severity
        count = count + 1;
    end
end
end

function tableValue = mappedRecordsToTable(records)
if isempty(records)
    tableValue = struct2table(repmat(blankMappedFieldRecord(), 0, 1));
else
    tableValue = struct2table(records);
end
end

function record = blankMappedFieldRecord()
record = struct( ...
    source_key="", ...
    source_artifact_type="", ...
    source_row=NaN, ...
    profile_id="", ...
    extractor_name="", ...
    mapping_index=NaN, ...
    mapping_rule_id="", ...
    profile_location="", ...
    native_field_name="", ...
    actual_source_field="", ...
    column_resolution="", ...
    target_level="", ...
    canonical_field="", ...
    data_type="", ...
    native_unit="", ...
    canonical_unit="", ...
    native_raw_token="", ...
    native_value_type="", ...
    native_value_real=NaN, ...
    native_value_integer=NaN, ...
    native_value_text="", ...
    native_value_boolean=NaN, ...
    canonical_value_type="", ...
    canonical_value_real=NaN, ...
    canonical_value_integer=NaN, ...
    canonical_value_text="", ...
    canonical_value_boolean=NaN, ...
    transform_key="", ...
    transform_status="", ...
    derivation_stage="", ...
    operational_variant="", ...
    operational_definition="", ...
    equivalence_class="", ...
    cross_extractor_relationship="", ...
    consilience_role="", ...
    semantic_role="", ...
    preserve_raw=true, ...
    status="");
end
