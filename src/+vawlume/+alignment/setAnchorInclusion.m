function result = setAnchorInclusion(conn, anchorObservationRef, included, options)
%SETANCHORINCLUSION Withhold an anchor observation from fits, or restore it.
%
% RESULT = vawlume.alignment.setAnchorInclusion(CONN, OBSERVATIONID, INCLUDED,
% Reason=WHY) records a decision about whether one anchor reading may influence
% a transform's coefficients, and returns what changed.
%
% OBSERVATIONID may be a positive `anchor_observation_id`. Prefer a structured
% selector in user code so the decision remains readable without a preliminary
% SQL query:
%
%   struct(run_key="session-alignment", anchor_key="sync04", ...
%          timebase_key="audio_native", observation_role="primary")
%
% Use `alignment_set_id` instead of `run_key` when convenient, and add
% `project_key` when a run key is not globally unique. `observation_role` is
% optional only when the remaining selector resolves one row.
%
% Exclusion is a **declared human decision**, and this function is how it is
% declared. VAWLUME performs no automatic outlier rejection: there is no robust
% regression, no iterative reweighting, no sigma clipping, and no rule anywhere
% that drops an anchor because its residual looked large. A fit's
% leave-one-out diagnostics say how much it leans on a reading; deciding that a
% reading should not count is a judgement this function records rather than
% makes.
%
% A reason is **required in both directions**. Withholding evidence and
% restoring it both change which readings produced a fit, and a later reader
% needs to see not just that the anchor set moved but why.
%
% It touches exactly three columns: `included_in_fit`, `observation_role`, and
% `notes`. **No timestamp, clock, event link, uncertainty, or provenance column
% is writable here.** An anchor's observed time is evidence; whether it counts
% is a decision, and only the decision is editable.
%
% The decision is appended to `notes` rather than overwriting it, so the column
% reads as a log of what was decided about this reading.
%
% Name-value arguments:
%   Reason  why the anchor is being withheld or restored (required)
%   Role    `observation_role` to set explicitly. Defaults to `excluded` when
%           withholding, and to `primary` when restoring a reading currently
%           marked `excluded`.
%
% An anchor withheld this way is still **evaluated**: it receives a residual
% against the transform it did not help produce, marked `included_in_fit = 0`
% with a reason, so a held-out anchor can be inspected without having
% influenced the coefficients.
%
% Errors:
%   :AnchorObservationRefInvalid    malformed structured selector
%   :AnchorObservationNotFound     no such observation
%   :ExclusionReasonRequired       a decision was made without stating why
%   :ObservationRoleUnsupported    role outside the schema's vocabulary
%   :AnchorObservationAmbiguous    restoring would give one anchor two included
%                                  readings on one clock, which would silently
%                                  become two statistical anchors
%
% See also VAWLUME.ALIGNMENT.FIT, VAWLUME.ALIGNMENT.REPORT.

arguments
    conn
    anchorObservationRef
    included (1,1) logical
    options.Reason (1,1) string = ""
    options.Role (1,1) string = ""
end

anchorObservationId = resolveObservationId(conn, anchorObservationRef);

reason = strtrim(options.Reason);
if strlength(reason) == 0
    error("vawlume:alignment:ExclusionReasonRequired", ...
        ['Changing whether an anchor observation counts requires a stated ' ...
        'reason. Withholding evidence and restoring it both change which ' ...
        'readings produced a fit, and an unexplained change is not auditable.']);
end

current = readObservation(conn, anchorObservationId);
role = resolveRole(options.Role, included, current.observation_role);

result = struct( ...
    anchor_observation_id=anchorObservationId, ...
    alignment_anchor_id=current.alignment_anchor_id, ...
    timebase_id=current.timebase_id, ...
    previous_included_in_fit=current.included_in_fit, ...
    previous_observation_role=current.observation_role, ...
    included_in_fit=double(included), ...
    observation_role=role, ...
    reason=reason, ...
    action="unchanged", ...
    note_appended="");

if current.included_in_fit == double(included) && current.observation_role == role
    return
end

if included
    assertNoCompetingInclusion(conn, current, anchorObservationId);
end

stamp = decisionStamp(included, reason);
notes = appendNote(current.notes, stamp);

execute(conn, "UPDATE alignment_anchor_observations SET included_in_fit=" + ...
    string(double(included)) + ", observation_role=" + sqlText(role) + ...
    ", notes=" + sqlText(notes) + " WHERE anchor_observation_id=" + ...
    string(anchorObservationId));

if included
    result.action = "restored";
else
    result.action = "withheld";
end
result.note_appended = stamp;
end

% ---------------------------------------------------------------- reading ---

function value = resolveObservationId(conn, ref)
if isnumeric(ref)
    validateattributes(ref, {'double'}, {'scalar', 'finite', 'positive', ...
        'integer'}, mfilename, 'anchorObservationRef');
    value = double(ref);
    return
end
if ~isstruct(ref) || ~isscalar(ref)
    error("vawlume:alignment:AnchorObservationRefInvalid", ...
        "anchorObservationRef must be a positive id or a scalar selector struct.");
end

hasSetId = isfield(ref, "alignment_set_id");
hasRunKey = isfield(ref, "run_key");
if hasSetId == hasRunKey || ~isfield(ref, "anchor_key") || ...
        ~isfield(ref, "timebase_key")
    error("vawlume:alignment:AnchorObservationRefInvalid", ...
        ['A selector must contain anchor_key, timebase_key, and exactly one ' ...
        'of alignment_set_id or run_key.']);
end
predicate = "a.anchor_key=" + sqlText(requiredText(ref.anchor_key, "anchor_key")) + ...
    " AND t.timebase_name=" + ...
    sqlText(requiredText(ref.timebase_key, "timebase_key"));
if hasSetId
    validateattributes(ref.alignment_set_id, {'double'}, {'scalar', 'finite', ...
        'positive', 'integer'}, mfilename, 'alignment_set_id');
    predicate = predicate + " AND s.alignment_set_id=" + ...
        string(double(ref.alignment_set_id));
else
    predicate = predicate + " AND ar.run_key=" + ...
        sqlText(requiredText(ref.run_key, "run_key"));
    if isfield(ref, "project_key")
        predicate = predicate + " AND p.project_key=" + ...
            sqlText(requiredText(ref.project_key, "project_key"));
    end
end
if isfield(ref, "observation_role")
    predicate = predicate + " AND o.observation_role=" + ...
        sqlText(requiredText(ref.observation_role, "observation_role"));
end
rows = fetch(conn, "SELECT o.anchor_observation_id FROM " + ...
    "alignment_anchor_observations o JOIN alignment_anchors a " + ...
    "ON a.alignment_anchor_id=o.alignment_anchor_id JOIN timebases t " + ...
    "ON t.timebase_id=o.timebase_id JOIN alignment_sets s " + ...
    "ON s.alignment_set_id=a.alignment_set_id JOIN analysis_runs ar " + ...
    "ON ar.analysis_run_id=s.analysis_run_id JOIN projects p " + ...
    "ON p.project_id=ar.project_id WHERE " + predicate + ...
    " ORDER BY o.anchor_observation_id");
if isempty(rows) || height(rows) == 0
    error("vawlume:alignment:AnchorObservationNotFound", ...
        "No anchor observation matches the structured selector.");
end
if height(rows) ~= 1
    error("vawlume:alignment:AnchorObservationAmbiguous", ...
        ['The structured selector matched %d observations. Add ' ...
        'observation_role or use anchor_observation_id to name one reading.'], ...
        height(rows));
end
value = double(rows.anchor_observation_id(1));
end

function value = requiredText(raw, name)
try
    value = strtrim(string(raw));
catch
    value = "";
end
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("vawlume:alignment:AnchorObservationRefInvalid", ...
        "Selector field %s must be nonempty scalar text.", name);
end
end

function value = readObservation(conn, anchorObservationId)
rows = fetch(conn, "SELECT alignment_anchor_id, timebase_id, included_in_fit, " + ...
    "IFNULL(observation_role,'') AS observation_role, " + ...
    "IFNULL(notes,'') AS notes " + ...
    "FROM alignment_anchor_observations WHERE anchor_observation_id=" + ...
    string(anchorObservationId));
if isempty(rows) || height(rows) == 0
    error("vawlume:alignment:AnchorObservationNotFound", ...
        "No anchor observation with anchor_observation_id %d.", anchorObservationId);
end
value = struct( ...
    alignment_anchor_id=double(rows.alignment_anchor_id(1)), ...
    timebase_id=double(rows.timebase_id(1)), ...
    included_in_fit=double(rows.included_in_fit(1)), ...
    observation_role=presentText(rows.observation_role(1)), ...
    notes=presentText(rows.notes(1)));
end

function assertNoCompetingInclusion(conn, current, anchorObservationId)
%ASSERTNOCOMPETINGINCLUSION Two included readings on one clock is not evidence.
%
% The schema's partial unique index already forbids this. Checking first turns a
% constraint violation into a message that names the reading already in the fit.
rows = fetch(conn, "SELECT anchor_observation_id FROM alignment_anchor_observations " + ...
    "WHERE alignment_anchor_id=" + string(current.alignment_anchor_id) + ...
    " AND timebase_id=" + string(current.timebase_id) + ...
    " AND included_in_fit=1 AND anchor_observation_id<>" + ...
    string(anchorObservationId));
if ~isempty(rows) && height(rows) > 0
    error("vawlume:alignment:AnchorObservationAmbiguous", ...
        ['Observation %d is already included for this anchor on this clock. ' ...
        'Restoring observation %d would give one anchor two included readings ' ...
        'on one clock, which would silently become two statistical anchors. ' ...
        'Withhold the other reading first.'], ...
        double(rows.anchor_observation_id(1)), anchorObservationId);
end
end

% --------------------------------------------------------------- decision ---

function value = resolveRole(requested, included, currentRole)
supported = ["primary", "replicate", "excluded"];
if strlength(strtrim(requested)) > 0
    value = strtrim(requested);
    if ~ismember(value, supported)
        error("vawlume:alignment:ObservationRoleUnsupported", ...
            "Observation role '%s' is not one of %s.", value, ...
            strjoin(supported, ", "));
    end
    return
end
if ~included
    value = "excluded";
    return
end
% Restoring a reading that was marked excluded needs a role it can legally hold,
% since the schema forbids `excluded` from also claiming to be in the fit.
if currentRole == "excluded" || strlength(currentRole) == 0
    value = "primary";
else
    value = currentRole;
end
end

function value = decisionStamp(included, reason)
if included
    value = "restored_to_fit: " + reason;
else
    value = "withheld_from_fit: " + reason;
end
end

function value = appendNote(existing, stamp)
if strlength(strtrim(existing)) == 0
    value = stamp;
else
    value = strtrim(existing) + " | " + stamp;
end
end

% ---------------------------------------------------------------- helpers ---

function value = presentText(value)
value = string(value);
if ismissing(value)
    value = "";
end
end

function value = sqlText(text)
value = "'" + replace(string(text), "'", "''") + "'";
end
