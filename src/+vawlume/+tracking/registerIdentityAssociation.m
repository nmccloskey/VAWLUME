function result = registerIdentityAssociation(conn, streamRef, associationSpec)
%REGISTERIDENTITYASSOCIATION Record evidence relating a native track to an entity.
%
%   result = VAWLUME.TRACKING.REGISTERIDENTITYASSOCIATION(conn, streamRef, spec)
%
% An association is an interval-scoped, provenance-bearing **claim** that a
% native trajectory corresponds to a canonical experimental entity. It is never
% a property of the trajectory: the same track may be one entity before a
% crossing, ambiguous during it, and a different entity after.
%
% ASSOCIATIONSPEC requires:
%
%   native_track_id     the upstream trajectory label
%   start_time_native   interval start, in the stream's native units
%   end_time_native     interval end
%   assignment_state    candidate | assigned | ambiguous | unresolved | rejected
%   evidence_kind       what KIND of evidence this is, free text
%
% and optionally accepts entity_id or entity_native_id, identity_value,
% identity_value_semantics, calibration_status, review_state, method,
% analysis_run_id, source_file_id, mapping_profile_version_id, source_locator,
% and notes.
%
% UNRESOLVED IS A STATEMENT, NOT A GAP. Omit the entity and pass
% assignment_state="unresolved" to record that nothing known identifies the
% animal over that interval. That is different from not recording anything, and
% different again from a weak candidate. The schema enforces the pairing: an
% entity without 'unresolved', or 'unresolved' without an entity, is refused.
%
% A NUMBER IS NEVER INVENTED. identity_value stays missing unless the source
% supplied one. A manual assertion, or an upstream tracker that emits only a
% label, records no value at all - never 1.0. When a value IS given,
% identity_value_semantics must state what it means, because a re-identification
% similarity, an upstream likelihood and a calibrated probability are different
% quantities that must not be compared as though they were one.
%
% SEVERAL CANDIDATES MAY COVER ONE INTERVAL. Registering entity A and entity B
% over the same crossing is the supported way to express ambiguity. What cannot
% be registered twice is the identical candidate for the identical interval.
%
% This function performs no re-identification, trains nothing, and corrects no
% upstream output. It records evidence somebody else produced.
%
% See also VAWLUME.TRACKING.IDENTITYCANDIDATES, VAWLUME.TRACKING.READWINDOW

arguments
    conn
    streamRef (1,1) struct
    associationSpec (1,1) struct
end

stream = trackingResolveStream(conn, streamRef);
declared = normalizeSpec(associationSpec);
assertTrackExists(conn, stream, declared.native_track_id);

entityId = resolveEntity(conn, stream, declared);
assertStatePairing(declared, entityId);
assertNotAlreadyAsserted(conn, stream, declared, entityId);

values = struct( ...
    external_stream_id=stream.external_stream_id, ...
    native_track_id=declared.native_track_id, ...
    start_time_native=declared.start_time_native, ...
    end_time_native=declared.end_time_native, ...
    assignment_state=declared.assignment_state, ...
    evidence_kind=declared.evidence_kind, ...
    identity_value_semantics=declared.identity_value_semantics, ...
    calibration_status=declared.calibration_status, ...
    review_state=declared.review_state, ...
    method=declared.method, ...
    source_locator=declared.source_locator, ...
    notes=declared.notes);
if ~isnan(entityId)
    values.entity_id = entityId;
end
if ~isnan(declared.identity_value)
    values.identity_value = declared.identity_value;
end
for field = ["analysis_run_id", "source_file_id", "mapping_profile_version_id"]
    if ~isnan(declared.(field))
        values.(field) = declared.(field);
    end
end

id = trackingInsertRow(conn, "tracking_identity_associations", values, ...
    "tracking_identity_association_id");

result = struct( ...
    tracking_identity_association_id=id, ...
    external_stream_id=stream.external_stream_id, ...
    native_track_id=declared.native_track_id, ...
    entity_id=entityId, ...
    interval=[declared.start_time_native declared.end_time_native], ...
    assignment_state=declared.assignment_state, ...
    evidence_kind=declared.evidence_kind, ...
    identity_value=declared.identity_value, ...
    identity_value_semantics=declared.identity_value_semantics, ...
    action="created");
end

function declared = normalizeSpec(spec)
declared = struct();
declared.native_track_id = trackingRequiredText(spec, "native_track_id");
declared.assignment_state = trackingRequiredText(spec, "assignment_state");
declared.evidence_kind = trackingRequiredText(spec, "evidence_kind");
declared.start_time_native = requiredFiniteReal(spec, "start_time_native");
declared.end_time_native = requiredFiniteReal(spec, "end_time_native");
if declared.end_time_native < declared.start_time_native
    error("vawlume:tracking:IdentityIntervalInvalid", ...
        "An identity association's interval ends before it starts: [%g %g].", ...
        declared.start_time_native, declared.end_time_native);
end

declared.identity_value = optionalFiniteReal(spec, "identity_value");
declared.identity_value_semantics = trackingOptionalText(spec, ...
    "identity_value_semantics");
if ~isnan(declared.identity_value) && ...
        strlength(declared.identity_value_semantics) == 0
    % An uninterpreted number is worse than no number: it invites comparison
    % with values that mean something else entirely.
    error("vawlume:tracking:IdentityValueSemanticsRequired", ...
        "identity_value was supplied without identity_value_semantics. A " + ...
        "re-identification similarity, an upstream likelihood and a " + ...
        "calibrated probability are different quantities; the number must " + ...
        "say which it is.");
end

declared.calibration_status = trackingOptionalText(spec, "calibration_status");
declared.review_state = trackingOptionalText(spec, "review_state");
declared.method = trackingOptionalText(spec, "method");
declared.source_locator = trackingOptionalText(spec, "source_locator");
declared.notes = trackingOptionalText(spec, "notes");
declared.entity_native_id = trackingOptionalText(spec, "entity_native_id");
declared.entity_id = optionalPositiveInteger(spec, "entity_id");
declared.analysis_run_id = optionalPositiveInteger(spec, "analysis_run_id");
declared.source_file_id = optionalPositiveInteger(spec, "source_file_id");
declared.mapping_profile_version_id = optionalPositiveInteger(spec, ...
    "mapping_profile_version_id");
end

function assertTrackExists(conn, stream, trackId)
%ASSERTTRACKEXISTS Associate only trajectories the stream actually contains.
%
% Registering identity for a track the artifact never produced would create
% evidence about nothing, and would not be caught by any later query.
rows = fetch(conn, "SELECT COUNT(*) AS n FROM tracking_series " + ...
    "WHERE external_stream_id=" + string(stream.external_stream_id) + ...
    " AND native_track_id=" + trackingSqlText(trackId));
if double(rows.n(1)) == 0
    error("vawlume:tracking:NativeTrackNotFound", ...
        "Tracking stream '%s' contains no native track '%s'. Identity " + ...
        "evidence is recorded about trajectories the stream actually has.", ...
        stream.stream_name, trackId);
end
end

function value = resolveEntity(conn, stream, declared)
%RESOLVEENTITY The caller names the entity; nothing is inferred from a label.
%
% entity_native_id is a convenience for addressing an EXISTING entity by its own
% identifier. It is a lookup the caller asked for, not an inference from the
% track label - the track label is never consulted here.
value = declared.entity_id;
if ~isnan(value)
    rows = fetch(conn, "SELECT project_id FROM experimental_entities " + ...
        "WHERE entity_id=" + string(value));
    if isempty(rows) || height(rows) == 0
        error("vawlume:tracking:EntityNotFound", ...
            "No experimental entity has id %d.", value);
    end
    return
end

if strlength(declared.entity_native_id) == 0
    return
end
rows = fetch(conn, "SELECT entity_id FROM experimental_entities " + ...
    "WHERE project_id=" + string(stream.project_id) + ...
    " AND native_id=" + trackingSqlText(declared.entity_native_id));
if isempty(rows) || height(rows) == 0
    error("vawlume:tracking:EntityNotFound", ...
        "No experimental entity '%s' exists in project '%s'. Identity " + ...
        "evidence cites established entities; it does not create them.", ...
        declared.entity_native_id, stream.project_key);
end
value = double(rows.entity_id(1));
end

function assertNotAlreadyAsserted(conn, stream, declared, entityId)
%ASSERTNOTALREADYASSERTED The same claim must not be recorded twice.
%
% A partial unique index enforces this in the schema, but a raw SQLite
% constraint error would tell the caller nothing about which claim collided or
% why it matters. Asserting the identical candidate twice is almost always a
% re-run, not new evidence - and evidence that silently doubles would look like
% corroboration it is not.
%
% A DIFFERENT candidate over the same interval is not a duplicate. That is the
% ambiguity model and is allowed.
predicate = "external_stream_id=" + string(stream.external_stream_id) + ...
    " AND native_track_id=" + trackingSqlText(declared.native_track_id) + ...
    " AND start_time_native=" + string(declared.start_time_native) + ...
    " AND end_time_native=" + string(declared.end_time_native);
if isnan(entityId)
    predicate = predicate + " AND entity_id IS NULL";
    description = "an unresolved statement";
else
    predicate = predicate + " AND entity_id=" + string(entityId);
    description = "candidate entity " + string(entityId);
end

rows = fetch(conn, "SELECT COUNT(*) AS n FROM tracking_identity_associations " + ...
    "WHERE " + predicate);
if double(rows.n(1)) > 0
    error("vawlume:tracking:IdentityAssociationDuplicate", ...
        "Track '%s' already has %s over [%g %g]. Recording it again would " + ...
        "double the evidence without adding any. A different candidate over " + ...
        "the same interval is allowed and is how ambiguity is expressed.", ...
        declared.native_track_id, description, ...
        declared.start_time_native, declared.end_time_native);
end
end

function assertStatePairing(declared, entityId)
%ASSERTSTATEPAIRING Unresolved and a named candidate are exclusive statements.
%
% The schema enforces this too. The check here names the problem in VAWLUME's
% vocabulary rather than SQLite's, because getting it wrong is a modelling
% mistake rather than a typo.
isUnresolved = declared.assignment_state == "unresolved";
hasEntity = ~isnan(entityId);
if isUnresolved && hasEntity
    error("vawlume:tracking:IdentityStateInconsistent", ...
        "assignment_state 'unresolved' cannot name a candidate entity. " + ...
        "Unresolved records that nothing known identifies the animal; a " + ...
        "weak candidate is 'candidate' or 'ambiguous' instead.");
end
if ~isUnresolved && ~hasEntity
    error("vawlume:tracking:IdentityStateInconsistent", ...
        "assignment_state '%s' requires a candidate entity. To record that " + ...
        "identity is unknown over this interval, use 'unresolved'.", ...
        declared.assignment_state);
end
end

function value = requiredFiniteReal(spec, name)
if ~isfield(spec, name)
    error("vawlume:tracking:SpecificationInvalid", ...
        "associationSpec.%s is required.", name);
end
value = spec.(name);
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    error("vawlume:tracking:SpecificationInvalid", ...
        "associationSpec.%s must be a finite scalar number.", name);
end
value = double(value);
end

function value = optionalFiniteReal(spec, name)
value = NaN;
if ~isfield(spec, name)
    return
end
candidate = spec.(name);
if isnumeric(candidate) && isscalar(candidate) && isnan(candidate)
    return
end
value = requiredFiniteReal(spec, name);
end

function value = optionalPositiveInteger(spec, name)
value = NaN;
if ~isfield(spec, name)
    return
end
candidate = spec.(name);
if isnumeric(candidate) && isscalar(candidate) && isnan(candidate)
    return
end
if ~isnumeric(candidate) || ~isscalar(candidate) || ~isfinite(candidate) || ...
        candidate <= 0 || candidate ~= floor(candidate)
    error("vawlume:tracking:SpecificationInvalid", ...
        "associationSpec.%s must be a positive integer when supplied.", name);
end
value = double(candidate);
end
