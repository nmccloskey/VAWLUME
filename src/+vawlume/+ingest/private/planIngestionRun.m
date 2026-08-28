function ingestionRun = planIngestionRun(ir, project, mappingProfile)
%PLANINGESTIONRUN Plan one immutable audit row for this intake attempt.

[warningCount, errorCount] = issueCounts(ir);
status = "completed";
if warningCount > 0
    status = "completed_with_warnings";
end
action = "create";
if project.action == "conflict" || ...
        ismember(mappingProfile.version_action, ["conflict", "skip"])
    action = "skip";
end

ingestionRun = struct( ...
    action=action, existing_ingestion_run_id=NaN, ...
    project_id=project.existing_project_id, ...
    mapping_profile_version_id= ...
    mappingProfile.existing_profile_version_id, ...
    run_label="", vawlume_version="", source_commit="", ...
    status=status, warning_count=warningCount, error_count=errorCount, ...
    notes="Project intake from validated source-mapping IR.");
end

function [warningCount, errorCount] = issueCounts(ir)
warningCount = 0;
errorCount = 0;
if ~isfield(ir, "issues") || ~istable(ir.issues) || isempty(ir.issues) || ...
        ~ismember("severity", string(ir.issues.Properties.VariableNames))
    return
end
severities = string(ir.issues.severity);
warningCount = sum(severities == "warning");
errorCount = sum(ismember(severities, ["error", "fatal"]));
end
