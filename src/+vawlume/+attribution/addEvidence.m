function result = addEvidence(conn, ref, evidence, options)
%ADDEVIDENCE Plan or atomically append separate attribution evidence rows.
%
% RESULT = VAWLUME.ATTRIBUTION.ADDEVIDENCE(CONN, REF, EVIDENCE) previews
% a batch and writes nothing. Apply=true appends the full batch atomically.
%
% REF names either a target (the same forms accepted by addCandidates) or one
% candidate through attribution_candidate_id. EVIDENCE is a table or struct
% array. Every row requires evidence_dimension, evidence_kind, exactly one of
% value_real/value_text, value_units, value_semantics, and a source pointer or
% source_locator.
%
% evidence_dimension is one of temporal_alignment, pose_localization,
% visual_identity, acoustic, correspondence, or imported_composite. The first
% four remain separate rows. imported_composite stores a value another system
% already combined; this function computes no value from evidence.
%
% Candidate-level identity evidence may cite a declared_entity_link through
% external_event_id, or an identity_association through
% tracking_identity_association_id. The cited statement must identify the same
% candidate in the same recording.
%
% Evidence rows have no schema identity key. Each successful Apply deliberately
% appends new observations; callers should not repeat an apply accidentally.
%
% See also VAWLUME.ATTRIBUTION.ADDCANDIDATES

arguments
    conn
    ref (1,1) struct
    evidence
    options.Apply (1,1) logical = false
end

plan = attributionBuildEvidencePlan(conn, ref, evidence);
result = evidenceResult(plan);
if options.Apply
    [plan, inserted] = attributionApplyEvidencePlan(conn, plan);
    result = evidenceResult(plan);
    result.status = "created";
    result.committed = true;
    result.applied_count = inserted;
end
end

function result = evidenceResult(plan)
result = struct(status="planned", committed=false, ...
    has_conflicts=plan.has_conflicts, conflicts=plan.conflicts, ...
    run=plan.run, target=plan.target, candidate=plan.candidate, ...
    evidence_count=height(plan.evidence), evidence=plan.evidence, ...
    applied_count=0);
end
