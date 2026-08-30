function report = preview(result, options)
%PREVIEW Build a readable, IR-only source-mapping dry-run report.
%
% REPORT = vawlume.source_mapping.preview(RESULT) returns inspectable report
% sections plus REPORT.text. Set Print=true to also write that text to the
% command window. This function performs no discovery, parsing, artifact
% reading, database access, or ingestion.

arguments
    result (1,1) struct
    options.Print (1,1) logical = false
    options.MaxIssueDetails (1,1) double {mustBeInteger, mustBeNonnegative} = 25
    options.ChecksumLength (1,1) double {mustBeInteger, mustBePositive} = 12
end

validateIntermediateRepresentation(result);

report = struct();
report.header = headerSection(result, options.ChecksumLength);
report.discovery = discoverySection(result);
[report.project_hierarchy, report.project_hierarchy_columns] = ...
    projectHierarchySection(result);
report.table_mapping = tableMappingSection(result);
report.external_streams = externalStreamSection(result);
report.anchor_mapping = anchorMappingSection(result);
report.issue_summary = issueSummarySection(result.issues);
detailCount = min(height(result.issues), options.MaxIssueDetails);
report.issue_details = result.issues(1:detailCount, :);
report.issue_detail_count = detailCount;
report.issue_details_truncated = height(result.issues) > detailCount;
report.verdict = verdictFor(result.valid_for_ingest);
report.ir_derived = true;
report.text = renderText(result, report);

if options.Print
    fprintf(1, "%s\n", char(report.text));
end
end

function validateIntermediateRepresentation(result)
required = ["ir_schema_version", "profile", "sources", "records", ...
    "values", "relationships", "streams", "events", "event_attributes", ...
    "coverage", "anchors", "anchor_observations", "anchor_fit_pairs", ...
    "issues", "summary", "valid_for_ingest"];
missing = required(~isfield(result, cellstr(required)));
if ~isempty(missing)
    error("vawlume:source_mapping:InvalidIntermediateRepresentation", ...
        "Preview requires the unified source-mapping IR; missing field(s): %s.", ...
        strjoin(missing, ", "));
end
tableFields = ["sources", "records", "values", "relationships", "streams", ...
    "events", "event_attributes", "coverage", "anchors", ...
    "anchor_observations", "anchor_fit_pairs", "issues"];
for index = 1:numel(tableFields)
    field = tableFields(index);
    if ~istable(result.(field))
        error("vawlume:source_mapping:InvalidIntermediateRepresentation", ...
            "IR field %s must be a table.", field);
    end
end
if ~islogical(result.valid_for_ingest) || ~isscalar(result.valid_for_ingest)
    error("vawlume:source_mapping:InvalidIntermediateRepresentation", ...
        "IR field valid_for_ingest must be a logical scalar.");
end
end

function header = headerSection(result, checksumLength)
profile = result.profile;
checksum = profileText(profile, "profile_checksum");
header = struct( ...
    ir_schema_version=string(result.ir_schema_version), ...
    profile_key=profileText(profile, "profile_key"), ...
    profile_kind=profileText(profile, "profile_kind"), ...
    profile_version=profileText(profile, "profile_version"), ...
    profile_checksum=checksum, ...
    profile_checksum_short=shortChecksum(checksum, checksumLength), ...
    source_context=sourceContext(result.sources), ...
    valid_for_ingest=result.valid_for_ingest);
end

function value = profileText(profile, field)
value = "";
if isstruct(profile) && isfield(profile, char(field))
    candidate = string(profile.(char(field)));
    if isscalar(candidate) && ~ismissing(candidate)
        value = candidate;
    end
end
end

function value = shortChecksum(checksum, checksumLength)
value = checksum;
if strlength(checksum) > checksumLength
    value = extractBefore(checksum, checksumLength + 1) + "...";
end
if strlength(value) == 0
    value = "not available";
end
end

function value = sourceContext(sources)
if isempty(sources)
    value = "no selected sources";
    return
end
types = sortedNonempty(sources.source_type);
value = strjoin(types, ", ") + " (" + height(sources) + " selected source(s))";
end

function discovery = discoverySection(result)
codes = string(result.issues.code);
discovery = struct( ...
    source_count=height(result.sources), ...
    selected_source_count=height(result.sources), ...
    ignored_source_count=NaN, ...
    ignored_source_count_note="not represented in the current IR", ...
    duplicate_discovery_warning_count=sum(codes == "SOURCE_DUPLICATE_DISCOVERY"), ...
    unmatched_count=sum(ismember(codes, ...
        ["REGEX_NO_MATCH", "OPTIONAL_REGEX_NO_MATCH", "SOURCE_NOT_FOUND"])), ...
    relative_paths=sortedNonempty(result.sources.relative_path));
end

function [summary, columns] = projectHierarchySection(result)
projectSources = result.sources(string(result.sources.source_type) == "project_file", :);
summary = table(string(projectSources.source_key), string(projectSources.relative_path), ...
    VariableNames=["source_key", "relative_path"]);
columns = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["variable_name", "canonical_concept", "role_label"]);
if isempty(projectSources)
    return
end

projectRecords = result.records(ismember(string(result.records.source_key), ...
    string(projectSources.source_key)), :);
concept = string(projectRecords.canonical_level);
concept(strlength(concept) == 0) = string(projectRecords.native_level(strlength(concept) == 0));
roles = string(projectRecords.role_label);
labels = concept;
hasRole = strlength(roles) > 0;
labels(hasRole) = labels(hasRole) + "__" + roles(hasRole);
labels = unique(labels(strlength(labels) > 0), "stable");

for labelIndex = 1:numel(labels)
    label = labels(labelIndex);
    variableName = validConceptName(label);
    values = strings(height(projectSources), 1);
    for sourceIndex = 1:height(projectSources)
        rowLabels = concept + "__" + roles;
        rowLabels(~hasRole) = concept(~hasRole);
        matches = string(projectRecords.source_key) == string(projectSources.source_key(sourceIndex)) & ...
            rowLabels == label;
        values(sourceIndex) = joinValues(projectRecords.native_identifier(matches));
    end
    summary.(char(variableName)) = values;
    role = "";
    canonical = label;
    separator = strfind(label, "__");
    if ~isempty(separator)
        canonical = extractBefore(label, separator(1));
        role = extractAfter(label, separator(1) + 1);
    end
    columns(end + 1, :) = {variableName, canonical, role}; %#ok<AGROW>
end
end

function name = validConceptName(label)
name = lower(regexprep(string(label), "[^A-Za-z0-9_]", "_"));
if strlength(name) == 0 || ~isletter(extractBefore(name, 2))
    name = "concept_" + name;
end
end

function summary = tableMappingSection(result)
tableSources = result.sources(string(result.sources.source_type) == "extractor_table", :);
summary = table(strings(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), strings(0, 1), strings(0, 1), NaN(0, 1), ...
    VariableNames=["source_key", "source_rows", "mapped_records", "mapped_values", ...
    "fields_found", "fields_missing", "canonical_fields", "transforms_applied", ...
    "missing_value_normalizations"]);
for sourceIndex = 1:height(tableSources)
    sourceKey = string(tableSources.source_key(sourceIndex));
    sourceValues = result.values(string(result.values.source_key) == sourceKey, :);
    sourceIssues = result.issues(string(result.issues.source_key) == sourceKey, :);
    missingCodes = ismember(string(sourceIssues.code), ...
        ["COLUMN_MISSING", "OPTIONAL_COLUMN_MISSING"]);
    transforms = sortedNonempty(sourceValues.transform_key);
    canonicalFields = sortedNonempty(sourceValues.canonical_field);
    summary(end + 1, :) = {sourceKey, tableSources.source_row_count(sourceIndex), ...
        sum(string(result.records.source_key) == sourceKey), height(sourceValues), ...
        numel(sortedNonempty(sourceValues.actual_source_field)), sum(missingCodes), ...
        strjoin(canonicalFields, ", "), strjoin(transforms, ", "), ...
        sum(string(sourceValues.normalized_value_type) == "missing")}; %#ok<AGROW>
end
end

function summary = externalStreamSection(result)
summary = table(strings(0, 1), strings(0, 1), strings(0, 1), NaN(0, 1), ...
    NaN(0, 1), NaN(0, 1), strings(0, 1), NaN(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    VariableNames=["source_key", "stream_key", "timebase_key", "event_count", ...
    "time_start_s", "time_end_s", "coverage_status", "coverage_segment_count", ...
    "native_labels", "normalized_event_keys", "attribute_fields"]);
for streamIndex = 1:height(result.streams)
    stream = result.streams(streamIndex, :);
    sourceKey = string(stream.source_key);
    streamKey = string(stream.stream_key);
    events = result.events(result.events.source_key == sourceKey & ...
        result.events.stream_key == streamKey, :);
    coverage = result.coverage(result.coverage.source_key == sourceKey & ...
        result.coverage.stream_key == streamKey, :);
    attributes = result.event_attributes(result.event_attributes.source_key == sourceKey, :);
    startTime = NaN;
    endTime = NaN;
    validStarts = events.start_time_s(isfinite(events.start_time_s));
    validEnds = events.end_time_s(isfinite(events.end_time_s));
    if ~isempty(validStarts)
        startTime = min(validStarts);
    end
    if ~isempty(validEnds)
        endTime = max(validEnds);
    end
    coverageStatus = "not_declared";
    if ~isempty(coverage)
        coverageStatus = "declared_observed_segments";
        if any(coverage.status == "invalid")
            coverageStatus = "invalid";
        end
    end
    summary(end + 1, :) = {sourceKey, streamKey, string(stream.timebase_key), ...
        height(events), startTime, endTime, coverageStatus, height(coverage), ...
        strjoin(sortedNonempty(events.native_event_label), ", "), ...
        strjoin(sortedNonempty(events.normalized_event_key), ", "), ...
        strjoin(sortedNonempty(attributes.attribute_name), ", ")}; %#ok<AGROW>
end
end

function summary = anchorMappingSection(result)
timebases = sortedNonempty(result.anchor_observations.timebase_key);
counts = NaN(numel(timebases), 1);
for index = 1:numel(timebases)
    counts(index) = sum(result.anchor_observations.timebase_key == timebases(index));
end
byTimebase = table(timebases, counts, ...
    VariableNames=["timebase_key", "observation_count"]);
summary = struct( ...
    logical_anchor_count=height(result.anchors), ...
    observation_count=height(result.anchor_observations), ...
    observations_by_timebase=byTimebase, ...
    ambiguous_primary_count=sum(result.issues.code == "ANCHOR_PRIMARY_AMBIGUOUS"), ...
    unresolved_event_reference_count=sum(result.issues.code == "EVENT_REFERENCE_UNRESOLVED"), ...
    fit_pairs=result.anchor_fit_pairs, ...
    ready=result.valid_for_ingest && ~isempty(result.anchors));
end

function summary = issueSummarySection(issues)
summary = table(strings(0, 1), strings(0, 1), NaN(0, 1), ...
    VariableNames=["severity", "code", "count"]);
if isempty(issues)
    return
end
severityOrder = ["fatal", "error", "warning", "info"];
observed = unique(string(issues.severity));
severityOrder = [severityOrder(ismember(severityOrder, observed)), ...
    transpose(sort(observed(~ismember(observed, severityOrder))))];
for severityIndex = 1:numel(severityOrder)
    severity = severityOrder(severityIndex);
    codes = sort(unique(string(issues.code(string(issues.severity) == severity))));
    for codeIndex = 1:numel(codes)
        code = codes(codeIndex);
        summary(end + 1, :) = {severity, code, ...
            sum(string(issues.severity) == severity & string(issues.code) == code)}; %#ok<AGROW>
    end
end
end

function text = renderText(result, report)
header = report.header;
version = displayOr(header.profile_version, "not declared");
lines = [ ...
    "VAWLUME SOURCE-MAPPING DRY RUN"
    "Profile: " + displayOr(header.profile_key, "not available") + ...
        " [" + displayOr(header.profile_kind, "unknown kind") + "] version " + version
    "Checksum: " + header.profile_checksum_short
    "Source context: " + header.source_context
    "IR valid_for_ingest: " + lower(string(header.valid_for_ingest))
    ""
    "DISCOVERY"
    "Sources found: " + report.discovery.source_count
    "Sources selected: " + report.discovery.selected_source_count
    "Sources ignored: n/a (" + report.discovery.ignored_source_count_note + ")"
    "Duplicate discovery warnings: " + report.discovery.duplicate_discovery_warning_count
    "Unmatched sources/rules: " + report.discovery.unmatched_count];

if ~isempty(report.project_hierarchy)
    lines(end + 1) = "";
    lines(end + 1) = "PROJECT HIERARCHY / VALUES";
    lines = [lines; hierarchyLines(result)];
end
if ~isempty(report.table_mapping)
    lines(end + 1) = "";
    lines(end + 1) = "TABLE MAPPING";
    lines = [lines; tableMappingLines(report.table_mapping)];
end
if ~isempty(report.external_streams)
    lines(end + 1) = "";
    lines(end + 1) = "EXTERNAL EVENT STREAMS";
    for index = 1:height(report.external_streams)
        row = report.external_streams(index, :);
        lines(end + 1) = "Stream " + row.stream_key + " on " + row.timebase_key + ...
            ": events=" + row.event_count + ", time range s=[" + ...
            numberText(row.time_start_s) + ", " + numberText(row.time_end_s) + ...
            "], coverage=" + row.coverage_status + " (" + ...
            row.coverage_segment_count + " segment(s)), native labels={" + ...
            displayOr(row.native_labels, "none") + "}, normalized keys={" + ...
            displayOr(row.normalized_event_keys, "none") + "}, attributes={" + ...
            displayOr(row.attribute_fields, "none") + "}"; %#ok<AGROW>
    end
end
if report.anchor_mapping.logical_anchor_count > 0 || ...
        report.anchor_mapping.observation_count > 0
    lines(end + 1) = "";
    lines(end + 1) = "ALIGNMENT ANCHORS";
    lines(end + 1) = "Logical anchors: " + report.anchor_mapping.logical_anchor_count;
    lines(end + 1) = "Observations: " + report.anchor_mapping.observation_count;
    for index = 1:height(report.anchor_mapping.observations_by_timebase)
        row = report.anchor_mapping.observations_by_timebase(index, :);
        lines(end + 1) = "Observations on " + row.timebase_key + ": " + ...
            row.observation_count; %#ok<AGROW>
    end
    lines(end + 1) = "Ambiguous primary groups: " + ...
        report.anchor_mapping.ambiguous_primary_count;
    for index = 1:height(report.anchor_mapping.fit_pairs)
        row = report.anchor_mapping.fit_pairs(index, :);
        lines(end + 1) = "Fit pair " + row.source_timebase_key + " -> " + ...
            row.reference_timebase_key + ": eligible anchors=" + ...
            row.fit_eligible_anchor_count + " [" + row.status + "]"; %#ok<AGROW>
    end
end

lines(end + 1) = "";
lines(end + 1) = "ISSUES";
if isempty(report.issue_summary)
    lines(end + 1) = "None";
else
    for index = 1:height(report.issue_summary)
        row = report.issue_summary(index, :);
        lines(end + 1) = "[" + upper(string(row.severity)) + "] " + ...
            string(row.code) + ": " + row.count; %#ok<AGROW>
    end
    for index = 1:height(report.issue_details)
        row = report.issue_details(index, :);
        location = displayOr(string(row.location), "IR");
        lines(end + 1) = "- [" + upper(string(row.severity)) + "] " + ...
            string(row.code) + " at " + location + ": " + string(row.message); %#ok<AGROW>
    end
    if report.issue_details_truncated
        lines(end + 1) = "- Additional issue details omitted from text view.";
    end
end

lines = [lines
    ""
    "VERDICT: " + report.verdict
    "IR readiness only; no database ingestion was attempted or inferred."];
text = strjoin(lines, newline);
end

function lines = hierarchyLines(result)
lines = strings(0, 1);
projectSources = result.sources(string(result.sources.source_type) == "project_file", :);
for sourceIndex = 1:height(projectSources)
    sourceKey = string(projectSources.source_key(sourceIndex));
    relativePath = displayOr(string(projectSources.relative_path(sourceIndex)), sourceKey);
    lines(end + 1, 1) = "Source: " + relativePath; %#ok<AGROW>
    rows = result.records(string(result.records.source_key) == sourceKey, :);
    for rowIndex = 1:height(rows)
        row = rows(rowIndex, :);
        concept = displayOr(string(row.canonical_level), string(row.native_level));
        role = "";
        if strlength(string(row.role_label)) > 0
            role = " [role=" + string(row.role_label) + "]";
        end
        lines(end + 1, 1) = "  " + concept + role + ": " + ...
            displayOr(string(row.native_identifier), "<unresolved>"); %#ok<AGROW>
    end
end
end

function lines = tableMappingLines(summary)
lines = strings(height(summary), 1);
for index = 1:height(summary)
    row = summary(index, :);
    fields = displayOr(string(row.canonical_fields), "none");
    transforms = displayOr(string(row.transforms_applied), "none");
    lines(index) = "Source " + string(row.source_key) + ": rows=" + row.source_rows + ...
        ", records=" + row.mapped_records + ", values=" + row.mapped_values + ...
        ", fields found=" + row.fields_found + ", fields missing=" + row.fields_missing + ...
        ", canonical fields={" + fields + "}, transforms={" + transforms + ...
        "}, missing normalizations=" + row.missing_value_normalizations;
end
end

function value = joinValues(values)
value = strjoin(sortedNonempty(values), " | ");
end

function values = sortedNonempty(values)
values = string(values);
values = values(~ismissing(values) & strlength(values) > 0);
values = sort(unique(values));
values = values(:);
end

function value = displayOr(value, fallback)
value = string(value);
if ismissing(value) || strlength(value) == 0
    value = string(fallback);
end
end

function value = numberText(number)
if isfinite(number)
    value = string(sprintf("%.15g", number));
else
    value = "n/a";
end
end

function verdict = verdictFor(validForIngest)
if validForIngest
    verdict = "READY FOR INGEST";
else
    verdict = "NOT READY FOR INGEST";
end
end
