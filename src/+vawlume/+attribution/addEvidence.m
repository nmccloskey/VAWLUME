function result = addEvidence(conn, ref, evidence, options)
%ADDEVIDENCE Plan or atomically append separate attribution evidence rows.
%
% RESULT = VAWLUME.ATTRIBUTION.ADDEVIDENCE(CONN, REF, EVIDENCE) previews
% a batch and writes nothing. Apply=true appends the full batch atomically.
%
% REF names either a target (the same forms accepted by addCandidates) or one
% candidate through attribution_candidate_id. EVIDENCE is a table or struct
% array. Every row requires evidence_dimension, evidence_kind, and a source
% pointer or source_locator. Every row except a source_localization row also
% requires exactly one of value_real/value_text, value_units and value_semantics.
%
% evidence_dimension is one of temporal_alignment, pose_localization,
% visual_identity, acoustic, source_localization, correspondence, or
% imported_composite. The first five are separate evidence dimensions and remain
% separate rows; nothing here combines any two of them. imported_composite
% stores a value another system already combined; this function computes no
% value from evidence.
%
% SOURCE_LOCALIZATION -- where a sound originated, per an external estimate; not
% where a bodypart is, which is pose_localization. A source_localization row
% cites a stored estimate through attribution_localization_estimate_id and
% carries no value_real, value_text or value_units of its own: the estimate's
% position, confidence, frame and semantics are the authority. The row must
% also declare coordinate_system_key, the frame the caller is reasoning in, and
% is refused unless:
%
%   the key names a declared frame        vawlume:attribution:LocalizationFrameUnknown
%   ...of this run's project              vawlume:attribution:LocalizationFrameScopeMismatch
%   it is the estimate's own frame, and   vawlume:geometry:CoordinateSystemMismatch
%   every source_localization row on the  (through vawlume.geometry.assertCompatible;
%   target is in that one frame           identity, never structural similarity)
%   the estimate belongs to this run      vawlume:attribution:LocalizationEstimateNotInRun
%   its window has a stored correspondence vawlume:attribution:LocalizationNotCorresponded
%     to this target
%   a claim-tied estimate supports only   vawlume:attribution:LocalizationCallerMismatch
%     the caller its producer tied it to
%
% Nothing is transformed between frames and no distance is computed.
%
% recording_channel_id names the recording channel per-channel evidence came
% from, on any dimension; it must belong to the run's recording
% (vawlume:attribution:EvidenceChannelScopeMismatch). A channel index is the
% producer's assertion about the acquisition, and nothing inspects audio to
% confirm it.
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
