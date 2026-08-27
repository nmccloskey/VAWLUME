function result = finalizeIntermediateRepresentation(result)
%FINALIZEINTERMEDIATERESULT Consolidate evidence, sort, and derive validity.

[result.values, conflictIssues] = consolidateValues(result.values);
if ~isempty(conflictIssues)
    result.issues = [result.issues; conflictIssues];
end

result.sources = stableSort(result.sources, "source_key");
result.records = stableSort(result.records, "record_key");
result.values = stableSort(result.values, "value_key");
result.relationships = stableSort(result.relationships, "relationship_key");
result.issues = sortIssues(result.issues);

errorCount = sum(result.issues.severity == "error");
fatalCount = sum(result.issues.severity == "fatal");
warningCount = sum(result.issues.severity == "warning");
infoCount = sum(result.issues.severity == "info");
conflictCount = sum(result.issues.code == "VALUE_CONFLICT");

result.summary = struct( ...
    source_count=height(result.sources), ...
    record_count=height(result.records), ...
    value_count=height(result.values), ...
    relationship_count=height(result.relationships), ...
    issue_count=height(result.issues), ...
    info_count=infoCount, ...
    warning_count=warningCount, ...
    error_count=errorCount, ...
    fatal_count=fatalCount, ...
    conflict_count=conflictCount);
result.valid_for_ingest = errorCount == 0 && fatalCount == 0;
end

function [values, issues] = consolidateValues(values)
issues = emptyIntermediateRepresentation(struct()).issues;
if isempty(values)
    return
end

groups = unique(values.evidence_group_key, "stable");
for groupIndex = 1:numel(groups)
    groupKey = groups(groupIndex);
    rows = find(values.evidence_group_key == groupKey);
    values.evidence_count(rows) = numel(rows);
    if isscalar(rows)
        values.consolidation_status(rows) = "unique";
        continue
    end

    signatures = strings(numel(rows), 1);
    for rowIndex = 1:numel(rows)
        signatures(rowIndex) = normalizedSignature(values(rows(rowIndex), :));
    end
    uniqueSignatures = unique(signatures);
    if isscalar(uniqueSignatures)
        values.consolidation_status(rows) = "corroborated";
    else
        values.consolidation_status(rows) = "conflict";
        sourceKey = values.source_key(rows(1));
        recordKeys = unique(values.record_key(rows));
        recordKey = "";
        if isscalar(recordKeys)
            recordKey = recordKeys;
        end
        issue = emptyIntermediateRepresentation(struct()).issues;
        issue(1, :) = {"", "error", "VALUE_CONFLICT", sourceKey, recordKey, ...
            "values", groupKey, ...
            "Conflicting normalized candidates were preserved for evidence group " + groupKey + ".", ...
            true};
        issues = [issues; issue]; %#ok<AGROW>
    end
end
end

function signature = normalizedSignature(row)
type = string(row.normalized_value_type);
switch type
    case "real"
        payload = string(sprintf("%.17g", row.normalized_value_real));
    case "integer"
        payload = string(sprintf("%.17g", row.normalized_value_integer));
    case "text"
        payload = string(row.normalized_value_text);
    case "boolean"
        payload = string(row.normalized_value_boolean);
    case "missing"
        payload = "<missing>";
    otherwise
        payload = "<" + type + ">";
end
signature = type + "|" + payload;
end

function value = stableSort(value, key)
if ~isempty(value)
    value = sortrows(value, key);
end
end

function issues = sortIssues(issues)
if isempty(issues)
    return
end
issues = sortrows(issues, ["source_key", "location", "code", "message"]);
issues.issue_key = "issue:" + compose("%06d", (1:height(issues))');
end
