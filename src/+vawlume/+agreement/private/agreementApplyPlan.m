function [plan, counts] = agreementApplyPlan(conn, plan)
%AGREEMENTAPPLYPLAN Atomically persist the agreement run and its components.
%
% One transaction covers the analysis boundary and the composition: the policy
% profile version, the derived analysis run, its participating extraction inputs,
% its many-parent lineage, its policy linkage, then the agreement groups, their
% native detection members, and one row per exact supporting candidate pair.
%
% The run reaches status 'completed' only once its components exist. A boundary
% applied by an earlier pass with composition pending is status 'started', and
% composing into it completes it rather than creating a second run.
%
% Schema write order is not incidental: members must precede supporting edges,
% because the supporting-edge trigger requires both endpoint detections to
% already be members of the group the edge supports.

if plan.has_conflicts
    error("vawlume:agreement:PlanConflict", ...
        "An agreement plan with identity conflicts cannot be applied.");
end
counts = emptyCounts();
if plan.analysis.action == "reuse" && plan.analysis.graph_action == "reuse"
    counts = reuseCounts(plan, counts);
    return
end

oldAutoCommit = string(conn.AutoCommit);
if oldAutoCommit ~= "on"
    error("vawlume:agreement:TransactionState", ...
        "Agreement apply requires a connection with AutoCommit enabled.");
end
conn.AutoCommit = "off";
try
    if plan.analysis.action == "create"
        [plan, counts] = applyConfiguration(conn, plan, counts);
        [plan, counts] = applyAnalysis(conn, plan, counts);
    else
        counts = reuseCounts(plan, counts);
    end
    [plan, counts] = applyComponents(conn, plan, counts);
    execute(conn, "UPDATE analysis_runs SET status='completed', " + ...
        "completed_at_utc=strftime('%Y-%m-%dT%H:%M:%fZ','now'), " + ...
        "notes=" + sqlText(completedNotes(plan)) + " " + ...
        "WHERE analysis_run_id=" + string(plan.analysis.analysis_run_id));
    plan.analysis.status = "completed";
    commit(conn);
catch exception
    try
        rollback(conn);
    catch
    end
    conn.AutoCommit = oldAutoCommit;
    rethrow(exception);
end
conn.AutoCommit = oldAutoCommit;
end

function [plan, counts] = applyConfiguration(conn, plan, counts)
configuration = plan.configuration;
if configuration.profile_action == "create"
    configuration.profile_id = agreementInsertRow(conn, "config_profiles", struct( ...
        project_id=plan.recording.project_id, ...
        profile_key=configuration.profile_key, ...
        profile_name=configuration.profile_name, ...
        profile_kind=configuration.profile_kind, is_builtin=0, ...
        description="Versioned arbitrary-N extractor-agreement composition policy."), ...
        "profile_id");
    counts.config_profiles = 1;
else
    counts.reused_config_profiles = 1;
end
if configuration.version_action == "create"
    configuration.profile_version_id = agreementInsertRow(conn, ...
        "config_profile_versions", struct(profile_id=configuration.profile_id, ...
        version_label=configuration.version_label, ...
        profile_schema_version=configuration.profile_schema_version, ...
        content_format=configuration.content_format, ...
        content_uri=configuration.content_uri, ...
        checksum_sha256=configuration.checksum_sha256, is_snapshot=1, ...
        notes="Exact agreement policy used by a derived arbitrary-N analysis."), ...
        "profile_version_id");
    counts.config_profile_versions = 1;
else
    counts.reused_config_profile_versions = 1;
end
plan.configuration = configuration;
end

function [plan, counts] = applyAnalysis(conn, plan, counts)
roles = agreementRoles();
plan.analysis.analysis_run_id = agreementInsertRow(conn, "analysis_runs", struct( ...
    project_id=plan.recording.project_id, ...
    run_type=plan.analysis.run_type, run_key=plan.context.run_key, ...
    run_label=plan.context.run_label, ...
    vawlume_version=plan.context.vawlume_version, ...
    source_commit=plan.context.source_commit, ...
    status="started", notes=analysisNotes(plan)), "analysis_run_id");
plan.analysis.status = "started";
counts.analysis_runs = 1;

agreementInsertRow(conn, "analysis_run_profiles", struct( ...
    analysis_run_id=plan.analysis.analysis_run_id, ...
    profile_version_id=plan.configuration.profile_version_id, ...
    assignment_role=roles.specification));
counts.analysis_run_profiles = 1;

for index = 1:height(plan.extractor_runs)
    agreementInsertRow(conn, "analysis_run_extraction_inputs", struct( ...
        analysis_run_id=plan.analysis.analysis_run_id, ...
        extraction_run_id=plan.extractor_runs.extraction_run_id(index), ...
        input_role=roles.extraction_input));
end
counts.analysis_run_extraction_inputs = height(plan.extractor_runs);

% Every pairwise parent, in canonical order. This is the claim
% parent_analysis_run_id cannot make.
for index = 1:height(plan.sources)
    agreementInsertRow(conn, "analysis_run_sources", struct( ...
        analysis_run_id=plan.analysis.analysis_run_id, ...
        source_analysis_run_id=plan.sources.analysis_run_id(index), ...
        dependency_role=roles.source_analysis, ...
        notes="Pairwise analysis '" + plan.sources.run_key(index) + ...
            "' covering extractor pair " + plan.sources.pair_label(index) + "."));
end
counts.analysis_run_sources = height(plan.sources);
plan.analysis.action = "create";
end

function value = analysisNotes(plan)
value = "algorithm=" + plan.specification.algorithm_key + "@" + ...
    plan.specification.algorithm_version + ...
    "; composition_pending=true; sources=" + ...
    strjoin(plan.sources.run_key', ",");
if strlength(plan.context.notes) > 0
    value = plan.context.notes + " [" + value + "]";
end
end

function value = completedNotes(plan)
%COMPLETEDNOTES Audit text only. Derived identity is group_key, never a note.
value = "algorithm=" + plan.specification.algorithm_key + "@" + ...
    plan.specification.algorithm_version + "; component_rule=" + ...
    plan.specification.component_rule + "; sources=" + ...
    strjoin(plan.sources.run_key', ",");
if strlength(plan.context.notes) > 0
    value = plan.context.notes + " [" + value + "]";
end
end

function [plan, counts] = applyComponents(conn, plan, counts)
if plan.analysis.graph_action == "reuse"
    counts = reuseComponentCounts(plan, counts);
    return
end
for index = 1:height(plan.groups)
    row = plan.groups(index, :);
    groupId = agreementInsertRow(conn, "agreement_groups", struct( ...
        analysis_run_id=plan.analysis.analysis_run_id, ...
        recording_id=plan.recording.recording_id, ...
        group_key=row.group_key, ...
        derivation_method=row.derivation_method), "agreement_group_id");
    plan.groups.agreement_group_id(index) = groupId;
    plan.members.agreement_group_id( ...
        plan.members.component_ordinal == row.component_ordinal) = groupId;
    plan.support_edges.agreement_group_id( ...
        plan.support_edges.component_ordinal == row.component_ordinal) = groupId;
end
counts.agreement_groups = height(plan.groups);

% Members before edges: the supporting-edge trigger requires both endpoints to
% already be members of the group the edge supports.
for index = 1:height(plan.members)
    row = plan.members(index, :);
    agreementInsertRow(conn, "agreement_group_members", struct( ...
        agreement_group_id=row.agreement_group_id, ...
        detection_id=row.detection_id, member_role=row.member_role));
end
counts.agreement_group_members = height(plan.members);

for index = 1:height(plan.support_edges)
    row = plan.support_edges(index, :);
    agreementInsertRow(conn, "agreement_supporting_edges", struct( ...
        agreement_group_id=row.agreement_group_id, ...
        candidate_pair_id=row.candidate_pair_id));
end
counts.agreement_supporting_edges = height(plan.support_edges);
end

function counts = reuseCounts(plan, counts)
counts.reused_config_profiles = 1;
counts.reused_config_profile_versions = 1;
counts.reused_analysis_runs = 1;
counts.reused_analysis_run_profiles = 1;
counts.reused_analysis_run_extraction_inputs = height(plan.extractor_runs);
counts.reused_analysis_run_sources = height(plan.sources);
if plan.analysis.graph_action == "reuse"
    counts = reuseComponentCounts(plan, counts);
end
end

function counts = reuseComponentCounts(plan, counts)
counts.reused_agreement_groups = height(plan.groups);
counts.reused_agreement_group_members = height(plan.members);
counts.reused_agreement_supporting_edges = height(plan.support_edges);
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end

function counts = emptyCounts()
counts = struct(config_profiles=0, config_profile_versions=0, ...
    analysis_runs=0, analysis_run_profiles=0, ...
    analysis_run_extraction_inputs=0, analysis_run_sources=0, ...
    agreement_groups=0, agreement_group_members=0, ...
    agreement_supporting_edges=0, ...
    reused_config_profiles=0, reused_config_profile_versions=0, ...
    reused_analysis_runs=0, reused_analysis_run_profiles=0, ...
    reused_analysis_run_extraction_inputs=0, reused_analysis_run_sources=0, ...
    reused_agreement_groups=0, reused_agreement_group_members=0, ...
    reused_agreement_supporting_edges=0);
end
