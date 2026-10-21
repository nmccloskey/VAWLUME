function familyId = edaRecordSensitivityFamily(conn, projectId, familyKey, ...
        referenceRunId, variantRunIds, record, outDir, repoRoot)
%EDARECORDSENSITIVITYFAMILY Write one sensitivity family record (contract 07 D2).
%
% One analysis_runs row (run_type attribution_sensitivity, run_key FAMILYKEY,
% notes "design_sha256=<RECORD.design_sha256>"), analysis_run_sources rows
% sensitivity_reference (REFERENCERUNID's analysis run) and sensitivity_variant
% (each of VARIANTRUNIDS), and RECORD written as JSON under OUTDIR, registered as
% an analysis_settings profile version and linked with assignment_role
% sensitivity_design. The record holds no result. One transaction for the rows.
path = fullfile(outDir, familyKey + "_design_record.json");
fid = fopen(path, "w");
fwrite(fid, char(jsonencode(record, PrettyPrint=true)));
fclose(fid);
registered = vawlume.db.registerProfileVersion(conn, struct(project_id=projectId), ...
    struct(profile_key="vawlume.eda.sensitivity_design." + familyKey, ...
    profile_name="Sensitivity design " + familyKey, version_label="1", ...
    content_path=path, profile_kind="analysis_settings"), RepoRoot=repoRoot);
% sqlwrite opens the transaction when AutoCommit is off (execute would not).
previous = string(conn.AutoCommit);
conn.AutoCommit = "off";
try
    sqlwrite(conn, "analysis_runs", table(projectId, ...
        {'attribution_sensitivity'}, {char(familyKey)}, {'completed'}, ...
        {char(string(datetime("now", TimeZone="UTC", Format="yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")))}, ...
        {char("design_sha256=" + string(record.design_sha256))}, VariableNames=["project_id", ...
        "run_type", "run_key", "status", "completed_at_utc", "notes"]));
    id = fetch(conn, "SELECT last_insert_rowid() AS id");
    familyId = double(id.id(1));
    sources = [analysisRunOf(conn, referenceRunId), "sensitivity_reference"];
    runs = unique(variantRunIds(~isnan(variantRunIds) & variantRunIds ~= referenceRunId));
    for k = 1:numel(runs)
        sources(end + 1, :) = [analysisRunOf(conn, runs(k)), "sensitivity_variant"]; %#ok<AGROW>
    end
    sqlwrite(conn, "analysis_run_sources", table(repmat(familyId, size(sources, 1), 1), ...
        double(sources(:, 1)), cellstr(sources(:, 2)), VariableNames=["analysis_run_id", ...
        "source_analysis_run_id", "dependency_role"]));
    sqlwrite(conn, "analysis_run_profiles", table(familyId, ...
        double(registered.profile_version_id), {'sensitivity_design'}, ...
        VariableNames=["analysis_run_id", "profile_version_id", "assignment_role"]));
    commit(conn);
catch failure
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = previous;
    rethrow(failure);
end
conn.AutoCommit = previous;
end

function id = analysisRunOf(conn, attributionRunId)
row = fetch(conn, "SELECT analysis_run_id FROM attribution_runs WHERE attribution_run_id=" + ...
    string(attributionRunId));
id = string(double(row.analysis_run_id(1)));
end
