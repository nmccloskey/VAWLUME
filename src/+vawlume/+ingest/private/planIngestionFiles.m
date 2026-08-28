function ingestionFiles = planIngestionFiles(ir, sources)
%PLANINGESTIONFILES Preserve structured per-source parse state for Pass 5.
%
% An ingestion_files row requires an ingestion_run, whose mapping-profile
% registration and transaction contract belong to Pass 5. This plan keeps
% the exact source IDs and structured IR diagnostics ready for that boundary.

count = height(sources);
actions = repmat("defer", count, 1);
actions(ismember(sources.action, ["conflict", "skip"])) = "skip";
parseStatus = strings(count, 1);
warningCounts = zeros(count, 1);
errorCounts = zeros(count, 1);
parserMessages = strings(count, 1);

for index = 1:count
    parseStatus(index) = sourceParseStatus(sources.source_status(index));
    issues = sourceIssues(ir, sources.source_key(index));
    if isempty(issues)
        continue
    end
    warningCounts(index) = sum(string(issues.severity) == "warning");
    errorCounts(index) = sum(ismember(string(issues.severity), ...
        ["error", "fatal"]));
    messages = unique(string(issues.message), "stable");
    messages = messages(strlength(messages) > 0);
    parserMessages(index) = strjoin(messages, " | ");
end

ingestionFiles = table( ...
    sources.source_key, actions, NaN(count, 1), ...
    sources.existing_source_file_id, parseStatus, warningCounts, ...
    errorCounts, parserMessages, ...
    VariableNames=["source_key", "action", "ingestion_run_id", ...
    "source_file_id", "parse_status", "warning_count", "error_count", ...
    "parser_message"]);
end

function value = sourceParseStatus(sourceStatus)
switch string(sourceStatus)
    case "mapped"
        value = "parsed";
    case "mapped_with_warnings"
        value = "parsed_with_warnings";
    case "invalid"
        value = "failed";
    otherwise
        value = "pending";
end
end

function issues = sourceIssues(ir, sourceKey)
issues = table();
if ~isfield(ir, "issues") || ~istable(ir.issues) || isempty(ir.issues) || ...
        ~all(ismember(["source_key", "severity", "message"], ...
        string(ir.issues.Properties.VariableNames)))
    return
end
issues = ir.issues(string(ir.issues.source_key) == sourceKey, :);
end
