function result = createRun(conn, recordingRef, runSpec, options)
%CREATERUN Plan or atomically create an attribution run and its target set.
%
% RESULT = VAWLUME.ATTRIBUTION.CREATERUN(CONN, RECORDINGREF, RUNSPEC)
% resolves a reproducible caller-attribution run without writing. Use
% Apply=true to persist its analysis parent, settings-profile link, input
% lineage, attribution run, and complete target set in one transaction.
%
% RECORDINGREF contains exactly one selector: recording_id, or project_key
% plus source_relative_path.
%
% RUNSPEC requires:
%
%   run_key                     project-scoped immutable identity
%   attribution_path            currently "imported"
%   method                      free-text source system or method
%   settings_profile_version_id checksum-bearing registered profile version
%   target_set                  one explicit event-set specification
%   sources                     direct input source identifiers
%
% A target_set contains exactly one of detection_ids, consensus_event_ids, or
% agreement_group_ids. Agreement groups additionally require
% agreement_extent_method. All selected events must belong to one source event
% set and to RECORDINGREF.
%
% sources is a scalar struct containing one or more of source_file_ids,
% artifact_ids, external_stream_ids, or analysis_run_ids. Direct sources and
% the participating-entity/link snapshot are retained in the attribution-run
% provenance JSON; source analysis runs and target-set authorities also use the
% repository's relational analysis input links.
%
% Optional RUNSPEC fields are participating_entity_ids (defaults to every
% entity linked to the recording), parent_attribution_run_id, run_label,
% vawlume_version, source_commit, and notes.
%
% This pass creates no candidate, score, evidence, probability, or decision.
% The run remains status "planned" and its analysis parent remains "started"
% for the candidate and decision layers to complete.
%
% See also VAWLUME.ATTRIBUTION.RESOLVETARGETS

arguments
    conn
    recordingRef (1,1) struct
    runSpec (1,1) struct
    options.Apply (1,1) logical = false
end

plan = attributionBuildPlan(conn, recordingRef, runSpec);
if options.Apply && ~plan.has_conflicts
    [plan, counts] = attributionApplyPlan(conn, plan);
    result = attributionPlanResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    if plan.run.action == "reuse"
        result.status = "reused";
    else
        result.status = "created";
    end
    return
end

result = attributionPlanResult(plan);
end
