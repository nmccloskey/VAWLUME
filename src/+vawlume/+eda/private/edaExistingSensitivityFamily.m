function value = edaExistingSensitivityFamily(conn, projectId, key, designSha)
%EDAEXISTINGSENSITIVITYFAMILY Is FAMILY_KEY already recorded, and with this design?
%
% found=false when no analysis run has the key. found=true when an
% attribution_sensitivity run with the same design SHA-256 has it, so a re-apply
% is reported "reused". Any other holder of the key is a conflict
% (vawlume:eda:SensitivityFamilyConflict).
rows = fetch(conn, "SELECT analysis_run_id, run_type, IFNULL(notes,'') AS notes " + ...
    "FROM analysis_runs WHERE project_id=" + string(projectId) + " AND run_key='" + ...
    replace(key, "'", "''") + "'");
value = struct(found=false, analysis_run_id=NaN);
if isempty(rows) || height(rows) == 0
    return
end
if string(rows.run_type(1)) ~= "attribution_sensitivity" || ...
        ~contains(string(rows.notes(1)), "design_sha256=" + designSha)
    error("vawlume:eda:SensitivityFamilyConflict", ...
        "family_key %s already names a %s record with another design.", key, ...
        string(rows.run_type(1)));
end
value = struct(found=true, analysis_run_id=double(rows.analysis_run_id(1)));
end
