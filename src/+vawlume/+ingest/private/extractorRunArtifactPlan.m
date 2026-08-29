function runArtifacts = extractorRunArtifactPlan(conn, plan)
%EXTRACTORRUNARTIFACTPLAN Classify role links for a resolved run and artifacts.

runArtifacts = table(strings(0,1), strings(0,1), ...
    VariableNames=["artifact_role", "action"]);
if height(plan.artifacts) == 0, return, end
existing = table();
if plan.run.action == "reuse" && ~isnan(plan.run.existing_extraction_run_id)
    rows = fetch(conn, "SELECT artifact_role, artifact_id FROM extraction_run_artifacts " + ...
        "WHERE extraction_run_id = " + string(plan.run.existing_extraction_run_id));
    if ~isempty(rows) && height(rows) > 0, existing = rows; end
end
for index = 1:height(plan.artifacts)
    role = string(plan.artifacts.role(index));
    artifactId = double(plan.artifacts.existing_artifact_id(index));
    if plan.run.action == "conflict" || string(plan.artifacts.action(index)) == "conflict"
        action = "conflict";
    elseif plan.run.action == "reuse"
        exact = false;
        if ~isempty(existing) && height(existing) > 0 && ~isnan(artifactId)
            exact = nnz(string(existing.artifact_role) == role & ...
                double(existing.artifact_id) == artifactId) == 1;
        end
        if exact, action = "reuse"; else, action = "conflict"; end
    else
        action = "create";
    end
    runArtifacts(end+1,:) = {role, action}; %#ok<AGROW>
end
end
