function diagnostics = deepsqueakDiagnostics(plan)
%DEEPSQUEAKDIAGNOSTICS Collect every non-fatal finding, labelled by its layer.
%
% A DeepSqueak import can fail or complain at five distinct layers, and
% collapsing them into one undifferentiated "import error" would hide which
% component actually disagreed:
%
%   adapter        workbook mechanics: readability, sheet, container format
%   source_mapping profile-driven field interpretation, reported through the IR
%   preflight      profile-declared event checks and extractor-version scope
%   identity       create/reuse/conflict classification against existing rows
%   apply          database constraint or transaction failure
%
% Findings that do not prevent a plan are returned here. Findings that do are
% raised as exceptions with namespaced identifiers, because a plan that cannot be
% trusted should never be handed back as if it were inspectable. Apply-layer
% failures likewise surface as exceptions after a full rollback.

arguments
    plan (1,1) struct
end

diagnostics = emptyDiagnostics();

diagnostics = appendIssueTable(diagnostics, "adapter", plan.export.issues);
diagnostics = appendIRIssues(diagnostics, plan.export.ir.issues);

for index = 1:numel(plan.extractor.warnings)
    diagnostics = append(diagnostics, "preflight", "warning", ...
        "EXTRACTOR_VERSION_SCOPE", plan.extractor.warnings(index));
end
for index = 1:numel(plan.validation.warnings)
    diagnostics = append(diagnostics, "preflight", "warning", ...
        checkCodeFrom(plan.validation.warnings(index)), ...
        plan.validation.warnings(index));
end
for index = 1:numel(plan.validation.unevaluated_checks)
    diagnostics = append(diagnostics, "preflight", "info", ...
        "CHECK_NOT_EVALUATED", ...
        "Profile-declared check '" + plan.validation.unevaluated_checks(index) + ...
        "' is not evaluated by the current implementation.");
end

for index = 1:numel(plan.conflicts)
    diagnostics = append(diagnostics, "identity", "error", "IDENTITY_CONFLICT", ...
        plan.conflicts(index));
end
end

function diagnostics = appendIssueTable(diagnostics, layer, issues)
if isempty(issues) || height(issues) == 0
    return
end
for index = 1:height(issues)
    diagnostics = append(diagnostics, layer, ...
        string(issues.severity(index)), string(issues.code(index)), ...
        string(issues.message(index)));
end
end

function diagnostics = appendIRIssues(diagnostics, issues)
if isempty(issues) || height(issues) == 0
    return
end
for index = 1:height(issues)
    diagnostics = append(diagnostics, "source_mapping", ...
        string(issues.severity(index)), string(issues.code(index)), ...
        string(issues.message(index)));
end
end

function code = checkCodeFrom(message)
%CHECKCODEFROM Recover the profile check id a warning was raised under.
code = "PROFILE_CHECK";
token = extractBetween(message, "[", "]");
if ~isempty(token)
    code = upper(string(token(1)));
end
end

function diagnostics = append(diagnostics, layer, severity, code, message)
diagnostics(end + 1, :) = {string(layer), string(severity), string(code), ...
    string(message)};
end

function value = emptyDiagnostics()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["layer", "severity", "code", "message"]);
end
