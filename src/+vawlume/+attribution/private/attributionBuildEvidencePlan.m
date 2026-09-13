function plan = attributionBuildEvidencePlan(conn, ref, inputEvidence)
%ATTRIBUTIONBUILDEVIDENCEPLAN Validate separate, source-bearing evidence rows.

[plan.target, plan.run, plan.candidate] = ...
    attributionResolveEvidenceRef(conn, ref);
assertWritableRun(plan.run);
plan.evidence = normalizeEvidence(inputEvidence, ...
    plan.target.attribution_target_id, ...
    plan.candidate.attribution_candidate_id);
validateSources(conn, plan);
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
    "mapping_profile_version_id", "source_locator", "notes"];
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
allowedDimensions = ["temporal_alignment", "pose_localization", ...
    "visual_identity", "acoustic", "correspondence", ...
    "imported_composite"];
if any(~ismember(dimensions, allowedDimensions))
    error("vawlume:attribution:EvidenceDimensionInvalid", ...
        "evidence_dimension must use the closed attribution vocabulary.");
end
if any(strlength(kinds) == 0)
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "evidence_kind must be nonempty free text.");
end

realValues = numericColumn(rows, "value_real", NaN(count, 1));
textValues = rawTextColumn(rows, "value_text", strings(count, 1));
hasReal = ~isnan(realValues);
hasText = strlength(strtrim(textValues)) > 0;
if any(hasReal & ~isfinite(realValues))
    error("vawlume:attribution:EvidenceSpecInvalid", ...
        "value_real must be finite when present.");
end
if any(hasReal == hasText)
    error("vawlume:attribution:EvidenceValueInvalid", ...
        "Every evidence row must contain exactly one of value_real or value_text.");
end
units = textColumn(rows, "value_units", strings(count, 1));
semantics = textColumn(rows, "value_semantics", strings(count, 1));
if any(strlength(units) == 0)
    error("vawlume:attribution:EvidenceUnitsRequired", ...
        "Every evidence value requires explicit units; use 'unitless' or 'category' when appropriate.");
end
if any(strlength(semantics) == 0)
    error("vawlume:attribution:EvidenceSemanticsRequired", ...
        "Every evidence value requires value_semantics.");
end

identityKinds = textColumn(rows, "identity_statement_kind", strings(count, 1));
associationIds = numericColumn(rows, ...
    "tracking_identity_association_id", NaN(count, 1));
externalEventIds = numericColumn(rows, "external_event_id", NaN(count, 1));
alignmentIds = numericColumn(rows, "alignment_run_id", NaN(count, 1));
sourceFileIds = numericColumn(rows, "source_file_id", NaN(count, 1));
profileIds = numericColumn(rows, "mapping_profile_version_id", NaN(count, 1));
for values = {associationIds, externalEventIds, alignmentIds, ...
        sourceFileIds, profileIds}
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
    repmat("create", count, 1), ...
    VariableNames=["attribution_evidence_id", "attribution_target_id", ...
    "attribution_candidate_id", "evidence_ordinal", "evidence_dimension", ...
    "evidence_kind", "value_real", "value_text", "value_units", ...
    "value_semantics", "identity_statement_kind", ...
    "tracking_identity_association_id", "external_event_id", ...
    "alignment_run_id", "source_file_id", "mapping_profile_version_id", ...
    "source_locator", "notes", "action"]);
end

function validateSources(conn, plan)
for index = 1:height(plan.evidence)
    row = plan.evidence(index, :);
    validateSourceFile(conn, row.source_file_id, plan.run.project_id);
    validateProfile(conn, row.mapping_profile_version_id, plan.run.project_id);
    validateAlignment(conn, row.alignment_run_id, plan.run.recording_id);
    validateAssociation(conn, row.tracking_identity_association_id, ...
        plan.run.recording_id, plan.candidate.entity_id);
    validateExternalEvent(conn, row.external_event_id, ...
        plan.run.recording_id, plan.candidate.entity_id);
end
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
