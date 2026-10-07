function plan = attributionBuildEvidencePlan(conn, ref, inputEvidence)
%ATTRIBUTIONBUILDEVIDENCEPLAN Validate separate, source-bearing evidence rows.

[plan.target, plan.run, plan.candidate] = ...
    attributionResolveEvidenceRef(conn, ref);
assertWritableRun(plan.run);
plan.evidence = normalizeEvidence(inputEvidence, ...
    plan.target.attribution_target_id, ...
    plan.candidate.attribution_candidate_id);
plan = validateSources(conn, plan);
plan.has_conflicts = false;
plan.conflicts = strings(0, 1);
end

function assertWritableRun(run)
if run.status ~= "planned" || run.analysis_status ~= "started"
    error("vawlume:attribution:RunNotWritable", ...
        "Evidence may only be appended while attribution status is planned and analysis status is started.");
end
end

function evidence = normalizeEvidence(raw, targetId, candidateId)
rows = rowTable(raw);
if height(rows) == 0
    error("vawlume:attribution:EvidenceSetEmpty", ...
        "At least one evidence row is required.");
end
allowed = ["evidence_dimension", "evidence_kind", "value_real", ...
    "value_text", "value_units", "value_semantics", ...
    "identity_statement_kind", "tracking_identity_association_id", ...
    "external_event_id", "alignment_run_id", "source_file_id", ...
    "mapping_profile_version_id", "source_locator", "notes", ...
    "attribution_localization_estimate_id", "coordinate_system_key", ...
    "recording_channel_id", "derived_measurement_id"];
unknown = setdiff(string(rows.Properties.VariableNames), allowed);
if ~isempty(unknown)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "Unknown evidence fields: %s.", strjoin(unknown, ", "));
end
required = ["evidence_dimension", "evidence_kind"];
for name = required
    if ~ismember(name, string(rows.Properties.VariableNames))
        error("vawlume:attribution:EvidenceSpecInvalid", ...
            "Every evidence row requires %s.", name);
    end
end
count = height(rows);
dimensions = textColumn(rows, "evidence_dimension", strings(count, 1));
kinds = textColumn(rows, "evidence_kind", strings(count, 1));
% Five separated evidence dimensions -- temporal_alignment, pose_localization,
% visual_identity, acoustic and source_localization -- plus two members that are
% not dimensions. source_localization was widened in deliberately at 0.12-draft:
% where a SOUND originated per an external estimate, not where a bodypart is.
allowedDimensions = ["temporal_alignment", "pose_localization", ...
    "visual_identity", "acoustic", "correspondence", ...
    "imported_composite", "source_localization"];
if any(~ismember(dimensions, allowedDimensions))
    error("vawlume:attribution:EvidenceDimensionInvalid", ...
        "evidence_dimension must use the closed attribution vocabulary.");
end
if any(strlength(kinds) == 0)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "evidence_kind must be nonempty free text.");
end
isLocalization = dimensions == "source_localization";

realValues = numericColumn(rows, "value_real", NaN(count, 1));
textValues = rawTextColumn(rows, "value_text", strings(count, 1));
hasReal = ~isnan(realValues);
hasText = strlength(strtrim(textValues)) > 0;
if any(hasReal & ~isfinite(realValues))
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "value_real must be finite when present.");
end
units = textColumn(rows, "value_units", strings(count, 1));
semantics = textColumn(rows, "value_semantics", strings(count, 1));
% A source_localization row CITES its estimate and copies nothing. Its position,
% confidence, frame and their semantics live on the estimate, and a second copy
% here would be a second authority that could drift from the first.
if any(isLocalization & (hasReal | hasText | strlength(units) > 0))
    error("vawlume:attribution:EvidenceValueInvalid", ...
        "A source_localization row cites its estimate and carries no value " + ...
        "or units of its own; the estimate is their authority.");
end
if any(~isLocalization & (hasReal == hasText))
    error("vawlume:attribution:EvidenceValueInvalid", ...
        "Every evidence row must contain exactly one of value_real or value_text.");
end
if any(~isLocalization & strlength(units) == 0)
    error("vawlume:attribution:EvidenceUnitsRequired", ...
        "Every evidence value requires explicit units; use 'unitless' or 'category' when appropriate.");
end
if any(~isLocalization & strlength(semantics) == 0)
    error("vawlume:attribution:EvidenceSemanticsRequired", ...
        "Every evidence value requires value_semantics.");
end

estimateIds = numericColumn(rows, "attribution_localization_estimate_id", NaN(count, 1));
frameKeys = textColumn(rows, "coordinate_system_key", strings(count, 1));
channelIds = numericColumn(rows, "recording_channel_id", NaN(count, 1));
if any(isLocalization & isnan(estimateIds))
    error("vawlume:attribution:LocalizationEstimateRequired", ...
        "A source_localization row must cite the localization estimate it rests on.");
end
if any(~isLocalization & ~isnan(estimateIds))
    error("vawlume:attribution:LocalizationEstimateMisplaced", ...
        "Only a source_localization row may cite a localization estimate. A " + ...
        "sound-source position cited as another dimension would make it read as " + ...
        "something it is not.");
end
% The frame is part of the coordinate, so the caller says which frame they are
% reasoning in. It is checked against the estimate's stored frame; it is never
% used to convert anything.
if any(isLocalization & strlength(frameKeys) == 0)
    error("vawlume:attribution:LocalizationFrameRequired", ...
        "A source_localization row must declare coordinate_system_key: the frame " + ...
        "its estimate is expressed in. A position without a frame is not a position.");
end
if any(~isLocalization & strlength(frameKeys) > 0)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "coordinate_system_key applies only to source_localization rows.");
end

identityKinds = textColumn(rows, "identity_statement_kind", strings(count, 1));
associationIds = numericColumn(rows, ...
    "tracking_identity_association_id", NaN(count, 1));
externalEventIds = numericColumn(rows, "external_event_id", NaN(count, 1));
alignmentIds = numericColumn(rows, "alignment_run_id", NaN(count, 1));
sourceFileIds = numericColumn(rows, "source_file_id", NaN(count, 1));
profileIds = numericColumn(rows, "mapping_profile_version_id", NaN(count, 1));
measurementIds = numericColumn(rows, "derived_measurement_id", NaN(count, 1));
for values = {associationIds, externalEventIds, alignmentIds, ...
        sourceFileIds, profileIds, estimateIds, channelIds, measurementIds}
    value = values{1};
    if any(~isnan(value) & (~isfinite(value) | value < 1 | fix(value) ~= value))
        error("vawlume:attribution:EvidenceSpecInvalid", ...
            "Evidence provenance identifiers must be positive integers.");
    end
end
validIdentity = identityKinds == "" | ...
    identityKinds == "declared_entity_link" | ...
    identityKinds == "identity_association";
if any(~validIdentity)
    error("vawlume:attribution:EvidenceIdentityInvalid", ...
        "identity_statement_kind must be declared_entity_link or identity_association.");
end
for index = 1:count
    hasAssociation = ~isnan(associationIds(index));
    hasEvent = ~isnan(externalEventIds(index));
    kind = identityKinds(index);
    correctAssociation = kind == "identity_association" && ...
        hasAssociation && ~hasEvent;
    correctDeclared = kind == "declared_entity_link" && ...
        hasEvent && ~hasAssociation;
    noIdentity = kind == "" && ~hasAssociation && ~hasEvent;
    if ~(correctAssociation || correctDeclared || noIdentity)
        error("vawlume:attribution:EvidenceIdentityInvalid", ...
            "Identity evidence must name exactly the statement row it rests on.");
    end
    if kind ~= "" && isnan(candidateId)
        error("vawlume:attribution:EvidenceIdentityInvalid", ...
            "Identity-derived evidence must support a candidate, not an unnamed target-level entity.");
    end
    % A-1, closed at 4.7. Visual-identity evidence rests on an identity
    % statement by definition, so it names which kind. An `external_events`
    % entity link is a user-declared label lookup carrying no evidence kind,
    % semantics, calibration or review state; a `tracking_identity_associations`
    % row carries all of them. Both may legitimately support a claim, and the
    % rule is not "prefer the stronger one" -- it is never use either silently.
    % Without this, a weak declared link and real identity evidence were
    % indistinguishable at the point attribution consumes them, which is exactly
    % the confusion A-1 was raised about.
    if dimensions(index) == "visual_identity" && kind == ""
        error("vawlume:attribution:EvidenceIdentityRequired", ...
            "visual_identity evidence must declare identity_statement_kind " + ...
            "(declared_entity_link or identity_association) and name the row " + ...
            "it rests on. A declared entity link and an identity association " + ...
            "are different strengths of claim and must not be indistinguishable.");
    end
end
locators = rawTextColumn(rows, "source_locator", strings(count, 1));
hasPointer = ~isnan(associationIds) | ~isnan(externalEventIds) | ...
    ~isnan(alignmentIds) | ~isnan(sourceFileIds) | ~isnan(profileIds) | ...
    ~isnan(estimateIds) | ~isnan(measurementIds) | ...
    strlength(strtrim(locators)) > 0;
if any(~hasPointer)
    error("vawlume:attribution:EvidenceSourceRequired", ...
        "Every evidence row must retain a source identifier or source_locator.");
end

evidence = table(NaN(count, 1), repmat(targetId, count, 1), ...
    repmat(candidateId, count, 1), (1:count)', dimensions, kinds, ...
    realValues, textValues, units, semantics, identityKinds, ...
    associationIds, externalEventIds, alignmentIds, sourceFileIds, ...
    profileIds, locators, rawTextColumn(rows, "notes", strings(count, 1)), ...
    estimateIds, frameKeys, NaN(count, 1), channelIds, measurementIds, ...
    repmat("create", count, 1), ...
    VariableNames=["attribution_evidence_id", "attribution_target_id", ...
    "attribution_candidate_id", "evidence_ordinal", "evidence_dimension", ...
    "evidence_kind", "value_real", "value_text", "value_units", ...
    "value_semantics", "identity_statement_kind", ...
    "tracking_identity_association_id", "external_event_id", ...
    "alignment_run_id", "source_file_id", "mapping_profile_version_id", ...
    "source_locator", "notes", "attribution_localization_estimate_id", ...
    "coordinate_system_key", "coordinate_system_id", "recording_channel_id", ...
    "derived_measurement_id", "action"]);
end

function plan = validateSources(conn, plan)
for index = 1:height(plan.evidence)
    row = plan.evidence(index, :);
    validateSourceFile(conn, row.source_file_id, plan.run.project_id);
    validateProfile(conn, row.mapping_profile_version_id, plan.run.project_id);
    validateAlignment(conn, row.alignment_run_id, plan.run.recording_id);
    validateAssociation(conn, row.tracking_identity_association_id, ...
        plan.run.recording_id, plan.candidate.entity_id);
    validateExternalEvent(conn, row.external_event_id, ...
        plan.run.recording_id, plan.candidate.entity_id);
    validateChannel(conn, row.recording_channel_id, plan.run.recording_id);
    validateMeasurement(conn, row, plan);
    if row.evidence_dimension == "source_localization"
        plan.evidence.coordinate_system_id(index) = validateLocalization(conn, plan, row);
    end
end
assertOneFramePerTarget(conn, plan);
end

function validateChannel(conn, id, recordingId)
% A channel index is the caller's assertion about the acquisition; this checks
% only that the channel exists on the run's recording. Nothing inspects audio to
% confirm the producer's numbering.
if isnan(id), return, end
rows = fetch(conn, "SELECT recording_id FROM recording_channels " + ...
    "WHERE recording_channel_id=" + string(id));
if isempty(rows) || height(rows) == 0
    sourceError("recording_channel_id", id, "does not exist");
end
if double(rows.recording_id(1)) ~= recordingId
    error("vawlume:attribution:EvidenceChannelScopeMismatch", ...
        "recording_channel_id %d belongs to a different recording than the run's.", id);
end
end

function validateMeasurement(conn, row, plan)
%VALIDATEMEASUREMENT The API half of the P4-3 citation (contract 06 D13, D15).
%
% The schema refuses a citation whose measurement is in another recording. These
% are the claims it cannot check: that the measurement is ABOUT this row's
% target event, and that it is the channel the row says it reports. A citation
% that passed only the schema could name a real measurement of a different call.
id = row.derived_measurement_id;
if isnan(id), return, end
rows = fetch(conn, "SELECT IFNULL(dm.detection_id,-1) AS detection_id, " + ...
    "IFNULL(dm.consensus_event_id,-1) AS consensus_event_id, " + ...
    "IFNULL(dm.recording_channel_id,-1) AS recording_channel_id, " + ...
    "IFNULL(COALESCE(" + ...
    "(SELECT d.recording_id FROM detections d WHERE d.detection_id=dm.detection_id), " + ...
    "(SELECT c.recording_id FROM consensus_events c WHERE c.consensus_event_id=dm.consensus_event_id), " + ...
    "(SELECT a.recording_id FROM acoustic_references a WHERE a.acoustic_reference_id=dm.acoustic_reference_id), " + ...
    "dm.recording_id), -1) AS recording_id " + ...
    "FROM derived_measurements dm WHERE dm.derived_measurement_id=" + string(id));
if isempty(rows) || height(rows) == 0
    error("vawlume:attribution:EvidenceMeasurementNotFound", ...
        "derived_measurement_id %d does not exist.", id);
end
if double(rows.recording_id(1)) ~= plan.run.recording_id
    error("vawlume:attribution:EvidenceMeasurementScopeMismatch", ...
        "derived_measurement_id %d is not a measurement of the run's recording.", id);
end
detection = absent(rows.detection_id(1));
consensus = absent(rows.consensus_event_id(1));
sameEvent = isequaln(detection, plan.target.detection_id) && ...
    isequaln(consensus, plan.target.consensus_event_id) && ...
    isnan(plan.target.agreement_group_id);
if ~sameEvent || (isnan(detection) && isnan(consensus))
    error("vawlume:attribution:EvidenceMeasurementTargetMismatch", ...
        "derived_measurement_id %d does not measure this evidence row's target " + ...
        "event (attribution target %d).", id, plan.target.attribution_target_id);
end
if ~isequaln(absent(rows.recording_channel_id(1)), row.recording_channel_id)
    error("vawlume:attribution:EvidenceMeasurementChannelMismatch", ...
        "derived_measurement_id %d reports a different channel from the row's " + ...
        "recording_channel_id.", id);
end
end

function value = absent(raw)
value = double(raw);
if value < 0
    value = NaN;
end
end

function frameId = validateLocalization(conn, plan, row)
%VALIDATELOCALIZATION Promote one stored estimate onto this target, or refuse.
%
% The schema refuses an estimate from another run. These are the refusals it
% cannot express: the frame the caller declares must be the estimate's frame,
% the estimate's window must already correspond to this target, and an estimate
% the producer tied to a claimed caller may support only that caller.
estimateId = row.attribution_localization_estimate_id;
rows = fetch(conn, "SELECT le.coordinate_system_id AS frame, " + ...
    "le.imported_attribution_window_id AS window_id, " + ...
    "IFNULL(le.imported_attribution_claim_id,-1) AS claim_id, " + ...
    "w.attribution_run_id AS run_id " + ...
    "FROM attribution_localization_estimates le " + ...
    "JOIN imported_attribution_windows w " + ...
    "ON w.imported_attribution_window_id = le.imported_attribution_window_id " + ...
    "WHERE le.attribution_localization_estimate_id=" + string(estimateId));
if isempty(rows) || height(rows) == 0
    sourceError("attribution_localization_estimate_id", estimateId, "does not exist");
end
if double(rows.run_id(1)) ~= plan.run.attribution_run_id
    error("vawlume:attribution:LocalizationEstimateNotInRun", ...
        "Localization estimate %d belongs to another attribution run.", estimateId);
end

declaredFrame = resolveDeclaredFrame(conn, row.coordinate_system_key, ...
    plan.run.project_id);
% Identity of the declared frame, never structural similarity: the existing
% geometry primitive decides, and nothing is converted to make them agree.
vawlume.geometry.assertCompatible(conn, [declaredFrame, double(rows.frame(1))], ...
    Context="source_localization evidence for estimate " + string(estimateId));
frameId = double(rows.frame(1));

corresponded = fetch(conn, "SELECT COUNT(*) AS n FROM attribution_window_correspondences " + ...
    "WHERE imported_attribution_window_id=" + string(double(rows.window_id(1))) + ...
    " AND attribution_target_id=" + string(plan.target.attribution_target_id));
if double(corresponded.n(1)) == 0
    error("vawlume:attribution:LocalizationNotCorresponded", ...
        "Localization estimate %d was computed over a window with no stored " + ...
        "correspondence to target %d. Relate the window first with " + ...
        "vawlume.attribution.correspondWindows; evidence about a different " + ...
        "sound is not evidence about this one.", estimateId, ...
        plan.target.attribution_target_id);
end

claimId = double(rows.claim_id(1));
if claimId > 0 && ~isnan(plan.candidate.entity_id)
    claim = fetch(conn, "SELECT IFNULL(entity_id,-1) AS entity_id " + ...
        "FROM imported_attribution_claims WHERE imported_attribution_claim_id=" + ...
        string(claimId));
    if double(claim.entity_id(1)) ~= plan.candidate.entity_id
        error("vawlume:attribution:LocalizationCallerMismatch", ...
            "Localization estimate %d was tied by its producer to another claimed " + ...
            "caller, so it cannot support candidate %d.", estimateId, ...
            plan.candidate.attribution_candidate_id);
    end
end
end

function frameId = resolveDeclaredFrame(conn, key, projectId)
% An unknown frame and another project's frame are different problems with
% different fixes, so they are different errors.
rows = fetch(conn, "SELECT coordinate_system_id, project_id FROM coordinate_systems " + ...
    "WHERE coordinate_system_key='" + replace(key, "'", "''") + "'");
if isempty(rows) || height(rows) == 0
    error("vawlume:attribution:LocalizationFrameUnknown", ...
        "coordinate_system_key '%s' names no declared frame.", key);
end
own = find(double(rows.project_id) == projectId, 1);
if isempty(own)
    error("vawlume:attribution:LocalizationFrameScopeMismatch", ...
        "coordinate_system_key '%s' names a frame declared only for another project.", key);
end
frameId = double(rows.coordinate_system_id(own));
end

function assertOneFramePerTarget(conn, plan)
% Source-localization evidence on one target is compared by anyone who reads it
% together, so it must all be in one declared frame: the rows in this batch and
% any already stored. Refused through the geometry primitive, never reconciled.
newFrames = plan.evidence.coordinate_system_id( ...
    plan.evidence.evidence_dimension == "source_localization");
if isempty(newFrames)
    return
end
stored = fetch(conn, "SELECT le.coordinate_system_id AS frame " + ...
    "FROM attribution_evidence ev JOIN attribution_localization_estimates le " + ...
    "ON le.attribution_localization_estimate_id = ev.attribution_localization_estimate_id " + ...
    "WHERE ev.attribution_target_id=" + string(plan.target.attribution_target_id));
frames = newFrames(:)';
if ~isempty(stored) && height(stored) > 0
    frames = [frames, double(stored.frame)'];
end
vawlume.geometry.assertCompatible(conn, frames, ...
    Context="source_localization evidence on target " + ...
    string(plan.target.attribution_target_id));
end

function validateSourceFile(conn, id, projectId)
if isnan(id), return, end
rows = fetch(conn, "SELECT project_id FROM source_files WHERE source_file_id=" + string(id));
if isempty(rows) || height(rows) == 0
    sourceError("source_file_id", id, "does not exist");
end
if double(rows.project_id(1)) ~= projectId
    sourceError("source_file_id", id, "belongs to another project");
end
end

function validateProfile(conn, id, projectId)
if isnan(id), return, end
rows = fetch(conn, "SELECT IFNULL(cp.project_id,-1) AS project_id " + ...
    "FROM config_profile_versions cpv JOIN config_profiles cp " + ...
    "ON cp.profile_id=cpv.profile_id WHERE cpv.profile_version_id=" + string(id));
if isempty(rows) || height(rows) == 0
    sourceError("mapping_profile_version_id", id, "does not exist");
end
storedProject = double(rows.project_id(1));
if storedProject >= 0 && storedProject ~= projectId
    sourceError("mapping_profile_version_id", id, "belongs to another project");
end
end

function validateAlignment(conn, id, recordingId)
if isnan(id), return, end
rows = fetch(conn, "SELECT IFNULL(als.recording_id,-1) AS recording_id " + ...
    "FROM time_alignment_runs tar JOIN alignment_sets als " + ...
    "ON als.alignment_set_id=tar.alignment_set_id " + ...
    "WHERE tar.alignment_run_id=" + string(id));
if isempty(rows) || height(rows) == 0
    sourceError("alignment_run_id", id, "does not exist");
end
if double(rows.recording_id(1)) ~= recordingId
    sourceError("alignment_run_id", id, "belongs to another recording");
end
end

function validateAssociation(conn, id, recordingId, entityId)
if isnan(id), return, end
rows = fetch(conn, "SELECT es.recording_id, " + ...
    "IFNULL(tia.entity_id,-1) AS entity_id " + ...
    "FROM tracking_identity_associations tia JOIN external_streams es " + ...
    "ON es.external_stream_id=tia.external_stream_id " + ...
    "WHERE tia.tracking_identity_association_id=" + string(id));
if isempty(rows) || height(rows) == 0
    sourceError("tracking_identity_association_id", id, "does not exist");
end
if double(rows.recording_id(1)) ~= recordingId || ...
        double(rows.entity_id(1)) ~= entityId
    sourceError("tracking_identity_association_id", id, ...
        "does not identify this candidate in the run's recording");
end
end

function validateExternalEvent(conn, id, recordingId, entityId)
if isnan(id), return, end
rows = fetch(conn, "SELECT es.recording_id, IFNULL(ee.entity_id,-1) AS entity_id " + ...
    "FROM external_events ee JOIN external_streams es " + ...
    "ON es.external_stream_id=ee.external_stream_id " + ...
    "WHERE ee.external_event_id=" + string(id));
if isempty(rows) || height(rows) == 0
    sourceError("external_event_id", id, "does not exist");
end
if double(rows.recording_id(1)) ~= recordingId || ...
        double(rows.entity_id(1)) ~= entityId
    sourceError("external_event_id", id, ...
        "does not declare this candidate in the run's recording");
end
end

function sourceError(field, id, reason)
error("vawlume:attribution:EvidenceSourceInvalid", ...
    "%s %d %s.", field, id, reason);
end

function rows = rowTable(raw)
if istable(raw)
    rows = raw;
elseif isstruct(raw)
    try
        rows = struct2table(raw(:));
    catch
        error("vawlume:attribution:EvidenceSpecInvalid", ...
            "evidence must be a table or a scalar-valued struct array.");
    end
else
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "evidence must be a table or struct array.");
end
end

function value = numericColumn(rows, name, fallback)
if ~ismember(name, string(rows.Properties.VariableNames))
    value = fallback;
    return
end
value = rows.(name);
if ~isnumeric(value) || numel(value) ~= height(rows)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "%s must contain one numeric value per evidence row.", name);
end
value = double(value(:));
end

function value = textColumn(rows, name, fallback)
if ~ismember(name, string(rows.Properties.VariableNames))
    value = fallback;
    return
end
try
    value = strtrim(string(rows.(name)));
catch
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "%s must contain one text value per evidence row.", name);
end
if numel(value) ~= height(rows)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "%s must contain one text value per evidence row.", name);
end
value = value(:);
value(ismissing(value)) = "";
end

function value = rawTextColumn(rows, name, fallback)
if ~ismember(name, string(rows.Properties.VariableNames))
    value = fallback;
    return
end
try
    value = string(rows.(name));
catch
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "%s must contain one text value per evidence row.", name);
end
if numel(value) ~= height(rows)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "%s must contain one text value per evidence row.", name);
end
value = value(:);
value(ismissing(value)) = "";
end
