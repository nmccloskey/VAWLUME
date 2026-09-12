function result = linkAnchorIdentityEvidence(conn, anchorObservationId, ...
        identityAssociationId, options)
%LINKANCHORIDENTITYEVIDENCE Attach visual-identity evidence to an anchor reading.
%
% RESULT = vawlume.alignment.linkAnchorIdentityEvidence(CONN, OBSERVATIONID,
% ASSOCIATIONID) records that one anchor observation is qualified by one Phase 2
% identity association, and returns what the link now says.
%
% **Device-level anchors are identity-independent, and their transforms must stay
% that way.** A TTL, light, or tone edge does not depend on which animal was
% present. An anchor derived from an identity-dependent biological event is
% admissible; an anchor whose identity uncertainty has been silently discarded is
% not, and this function is how that uncertainty stays attached.
%
% Three things stay apart, and nothing here merges them:
%
%   the observation's timestamp    a number on a clock
%   the observation's evidence class   device_level or identity_dependent
%   the identity evidence         which canonical entity the event concerned,
%                                 with its own declared value semantics,
%                                 calibration status and review state
%
% **The fitter never reads this table.** The separation is structural: identity
% evidence lives in its own table, which the anchor-pairing query does not join.
% SQLite cannot forbid a join, so the boundary is held by test — the fitted
% coefficients must be bit-identical with and without identity evidence attached,
% across confident, weak, ambiguous and unresolved cases.
%
% **Several links per observation are legal.** An anchor qualified by `ambiguous`
% identity evidence has more than one candidate entity, and refusing that would
% push the ambiguity out of the record rather than represent it.
%
% This creates no identity evidence. It links evidence that already exists,
% invents no entity, track, interval, or score, and computes nothing.
%
% `external_events.entity_id` is deliberately not usable here. It is a declared
% label lookup carrying no evidence kind, no value semantics, no calibration
% status and no review state; treating it as identity evidence would make an
% unverified guess indistinguishable from a reviewed assertion.
%
% Name-value arguments:
%   Notes   free text recorded on the link
%
% Errors:
%   :AnchorObservationNotFound       no such observation
%   :IdentityAssociationNotFound     no such association
%   :EvidenceClassRequired           the observation is not declared
%                                    identity_dependent
%   :IdentityEvidenceAlreadyLinked   this association already qualifies it
%
% See also VAWLUME.ALIGNMENT.REPORT, VAWLUME.TRACKING.IDENTITYCANDIDATES.

arguments
    conn
    anchorObservationId (1,1) double {mustBeInteger, mustBePositive}
    identityAssociationId (1,1) double {mustBeInteger, mustBePositive}
    options.Notes (1,1) string = ""
end

observation = readObservation(conn, anchorObservationId);
association = readAssociation(conn, identityAssociationId);

if observation.evidence_class ~= "identity_dependent"
    declared = observation.evidence_class;
    if strlength(declared) == 0
        declared = "undeclared";
    end
    error("vawlume:alignment:EvidenceClassRequired", ...
        ['Anchor observation %d is %s. Identity evidence qualifies an anchor ' ...
        'the fitter must treat as identity-dependent; attaching it to a ' ...
        'device-level or unexamined reading would leave visual-identity ' ...
        'uncertainty where nothing would ever weigh it.'], ...
        anchorObservationId, declared);
end

if isLinked(conn, anchorObservationId, identityAssociationId)
    error("vawlume:alignment:IdentityEvidenceAlreadyLinked", ...
        "Association %d already qualifies anchor observation %d.", ...
        identityAssociationId, anchorObservationId);
end

values = struct( ...
    anchor_observation_id=anchorObservationId, ...
    tracking_identity_association_id=identityAssociationId);
if strlength(strtrim(options.Notes)) > 0
    values.notes = strtrim(options.Notes);
end
alignmentInsertRow(conn, "alignment_anchor_identity_evidence", values, ...
    "alignment_anchor_identity_evidence_id");

result = struct( ...
    anchor_observation_id=anchorObservationId, ...
    tracking_identity_association_id=identityAssociationId, ...
    evidence_class=observation.evidence_class, ...
    assignment_state=association.assignment_state, ...
    evidence_kind=association.evidence_kind, ...
    identity_value=association.identity_value, ...
    identity_value_semantics=association.identity_value_semantics, ...
    calibration_status=association.calibration_status, ...
    review_state=association.review_state, ...
    link_count=linkCount(conn, anchorObservationId), ...
    separation_note=separationNote());
end

% ---------------------------------------------------------------- reading ---

function value = readObservation(conn, anchorObservationId)
rows = fetch(conn, "SELECT IFNULL(evidence_class,'') AS evidence_class " + ...
    "FROM alignment_anchor_observations WHERE anchor_observation_id=" + ...
    string(anchorObservationId));
if isempty(rows) || height(rows) == 0
    error("vawlume:alignment:AnchorObservationNotFound", ...
        "No anchor observation with anchor_observation_id %d.", anchorObservationId);
end
value = struct(evidence_class=presentText(rows.evidence_class(1)));
end

function value = readAssociation(conn, identityAssociationId)
%READASSOCIATION The Phase 2 claim, read back with its semantics intact.
%
% Every nullable column is wrapped: the Database Toolbox raises while building a
% result set containing SQL NULL, and an association with no numeric score or no
% recorded review state is the ordinary case rather than the exception.
rows = fetch(conn, "SELECT assignment_state, evidence_kind, " + ...
    "IFNULL(identity_value, 1e308) AS identity_value, " + ...
    "IFNULL(identity_value_semantics,'') AS identity_value_semantics, " + ...
    "IFNULL(calibration_status,'') AS calibration_status, " + ...
    "IFNULL(review_state,'') AS review_state " + ...
    "FROM tracking_identity_associations " + ...
    "WHERE tracking_identity_association_id=" + string(identityAssociationId));
if isempty(rows) || height(rows) == 0
    error("vawlume:alignment:IdentityAssociationNotFound", ...
        ['No tracking identity association with id %d. This function links ' ...
        'evidence that already exists; it creates none.'], identityAssociationId);
end
value = struct( ...
    assignment_state=presentText(rows.assignment_state(1)), ...
    evidence_kind=presentText(rows.evidence_kind(1)), ...
    identity_value=sentinelNumber(rows.identity_value(1)), ...
    identity_value_semantics=presentText(rows.identity_value_semantics(1)), ...
    calibration_status=presentText(rows.calibration_status(1)), ...
    review_state=presentText(rows.review_state(1)));
end

function value = isLinked(conn, anchorObservationId, identityAssociationId)
rows = fetch(conn, "SELECT COUNT(*) AS n " + ...
    "FROM alignment_anchor_identity_evidence " + ...
    "WHERE anchor_observation_id=" + string(anchorObservationId) + ...
    " AND tracking_identity_association_id=" + string(identityAssociationId));
value = double(rows.n(1)) > 0;
end

function value = linkCount(conn, anchorObservationId)
rows = fetch(conn, "SELECT COUNT(*) AS n " + ...
    "FROM alignment_anchor_identity_evidence " + ...
    "WHERE anchor_observation_id=" + string(anchorObservationId));
value = double(rows.n(1));
end

% ---------------------------------------------------------------- helpers ---

function value = separationNote()
value = "Identity evidence qualifies this anchor and is never an input to the " + ...
    "transform. The fitter reads alignment_anchors and " + ...
    "alignment_anchor_observations only; coefficients are invariant to what is " + ...
    "linked here. Alignment residual and identity confidence are reported side " + ...
    "by side and never combined.";
end

function value = sentinelNumber(raw)
value = double(raw);
if value >= 1e307
    value = NaN;
end
end

function value = presentText(value)
value = string(value);
value(ismissing(value)) = "";
end
