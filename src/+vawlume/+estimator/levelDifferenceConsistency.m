function result = levelDifferenceConsistency(entities, geometry, difference, settings)
%LEVELDIFFERENCECONSISTENCY Score each candidate by how well its position explains the level difference.
%
%   result = VAWLUME.ESTIMATOR.LEVELDIFFERENCECONSISTENCY(entities, geometry, ...
%       difference, settings)
%
% THE ONE HOME OF COMBINATION (contract 06 D7, revised invariant 5). Method key
% vawlume.estimator.level_difference_consistency, version 1.0.0. It combines
% acoustic evidence (the observed level difference) with pose/location evidence
% (two distances), through visual-identity evidence (which track the distances
% belong to) and temporal alignment (which instant). Its licence is SETTINGS,
% the profile from vawlume.estimator.loadSettings, which states the five
% conditions.
%
% PURE: values in, scores and reasons out. It reads no database, opens no file
% and writes nothing. vawlume.estimator.attributeCallers composes it (6.9).
%
% INPUTS
%   entities    candidateGeometry(...).entities: one row per participant, with
%               entity_id, has_geometry and reason (and, when present,
%               native_track_id and tracking_identity_association_id)
%   geometry    candidateGeometry(...).geometry: rows per (entity, channel,
%               instant basis) with distance, unit, status, reason,
%               event_extrapolated and bracket_extrapolated
%   difference  vawlume.acoustic.levelDifference(sideA, sideB,
%               settings.parameters.refuse_clipped_channels), for the ordered
%               pair settings.parameters.channel_pair
%   settings    vawlume.estimator.loadSettings(...)
%
% FOR EACH CANDIDATE with usable geometry and a computed difference, on
% settings.parameters.primary_instant_basis, with (a, b) the declared pair:
%
%   predicted   = 20*log10(d_b / d_a)   dB   (spherical spreading: power ~ 1/d^2)
%   observed    = difference.value      dB   (10*log10(P_a/P_b), the same
%                                             orientation: nearer a is positive)
%   discrepancy = observed - predicted  dB
%   score       = -abs(discrepancy)     dB, higher_is_stronger, at most 0
%
% Every intermediate is returned. The distances enter only as their ratio, so
% the score is unchanged by any uniform rescaling of the frame (D17).
%
% OTHERWISE NO SCORE, NEVER A DEFAULT ONE. Every applicable reason is listed in
% no_score_reasons, in this order, and the first is no_score_reason:
%   identity_*                 from entities.reason (D9)
%   track_not_covered          a side has no position; position_missing and
%                              z_missing, the primitive's own words, are kept
%                              in geometry_reason_detail
%   track_covered_empty, bodypart_missing
%   alignment_extrapolated     event or bracket extrapolated, when
%                              refuse_extrapolated_alignment is true
%   channel_unplaced
%   frame_unit_not_accepted    the frame's unit is not in accepted_frame_units
%   distance_degenerate        a distance below min_distance, in frame units
%   acoustic_unavailable       the level difference was refused for a missing
%                              or non-positive side
%   acoustic_clipped           it was refused for a clipped side
% A gate that fails gives a reason, not a lowered score. Pose confidence and the
% alignment bound are recorded as evidence and gate nothing (D4, D5).
%
% SCOPE (D2): exactly settings.scope.candidate_count candidates and the declared
% ordered channel pair. Anything else raises vawlume:estimator:ScopeUnsupported
% or vawlume:estimator:ChannelPairMismatch; the method does not generalize.
%
% THE NUMBER IS A SCORE, NOT A PROBABILITY. No probability is returned. Its
% semantics string, score_semantics, names the method and version, the unit
% and orientation, says uncalibrated, gives the comparability scope
% (within_recording), and says it is not a probability.

arguments
    entities table
    geometry table
    difference (1,1) struct
    settings (1,1) struct
end

parameters = settings.parameters;
assertScope(entities, settings);
pair = parameters.channel_pair;
observed = readObserved(difference, pair, parameters);
semantics = scoreSemantics(settings);

rows = cell(height(entities), 1);
for index = 1:height(entities)
    rows{index} = scoreOne(entities(index, :), geometry, observed, pair, parameters, semantics);
end
candidates = vertcat(rows{:});

result = struct( ...
    method_key=settings.method_key, ...
    method_version=settings.method_version, ...
    settings_profile_key=settings.profile_key, ...
    settings_profile_version=settings.version_label, ...
    score_unit="dB", ...
    score_orientation="higher_is_stronger", ...
    calibration_status=settings.calibration_status.state, ...
    comparability_scope=settings.scaling.comparability_scope, ...
    score_semantics=semantics, ...
    channel_pair=pair, ...
    instant_basis=parameters.primary_instant_basis, ...
    observed=observed, ...
    candidates=candidates);
end

% ------------------------------------------------------------------ input ---

function assertScope(entities, settings)
for name = ["entity_id", "has_geometry", "reason"]
    if ~ismember(name, string(entities.Properties.VariableNames))
        inputInvalid("entities has no %s column.", name);
    end
end
count = height(entities);
if count ~= settings.scope.candidate_count
    error("vawlume:estimator:ScopeUnsupported", ...
        "This method is defined for exactly %d candidates; %d were given. " + ...
        "It does not generalize to other counts (contract 06 D7).", ...
        settings.scope.candidate_count, count);
end
if numel(unique(entities.entity_id)) ~= count
    inputInvalid("entities must name distinct entity_id values.");
end
end

function observed = readObserved(difference, pair, parameters)
for name = ["status", "reasons", "value", "unit", "channel_index_a", ...
        "channel_index_b", "refuse_clipped_channels"]
    if ~isfield(difference, name)
        inputInvalid("difference has no %s field; pass vawlume.acoustic.levelDifference's result.", name);
    end
end
if ~isequal([difference.channel_index_a difference.channel_index_b], pair)
    error("vawlume:estimator:ChannelPairMismatch", ...
        "The level difference is for channels (%d, %d); the profile declares the " + ...
        "ordered pair (%d, %d). Any other pair is refused, not reordered.", ...
        difference.channel_index_a, difference.channel_index_b, pair(1), pair(2));
end
if difference.unit ~= "dB"
    inputInvalid("The level difference must be in dB, not %s.", difference.unit);
end
if difference.refuse_clipped_channels ~= parameters.refuse_clipped_channels
    inputInvalid("The level difference was computed with refuse_clipped_channels=%d; " + ...
        "the profile declares %d.", difference.refuse_clipped_channels, ...
        parameters.refuse_clipped_channels);
end
observed = struct(status=string(difference.status), value=NaN, reason="", ...
    level_difference_reasons=string(difference.reasons(:)));
if observed.status == "computed"
    observed.value = double(difference.value);
elseif any(endsWith(observed.level_difference_reasons, "_clipped"))
    observed.reason = "acoustic_clipped";
else
    observed.reason = "acoustic_unavailable";
end
end

% ---------------------------------------------------------------- scoring ---

function row = scoreOne(entity, geometry, observed, pair, parameters, semantics)
row = blankRow(entity, pair, parameters.primary_instant_basis, observed.value);
reasons = strings(0, 1);
if ~entity.has_geometry
    reasons(end + 1, 1) = string(entity.reason);
else
    [sideA, sideB] = sides(geometry, entity.entity_id, pair, ...
        parameters.primary_instant_basis);
    row.distance_a = sideA.distance;
    row.distance_b = sideB.distance;
    row.distance_unit = sideA.unit;
    for side = [sideA, sideB]
        if side.status ~= "computed"
            [reason, detail] = geometryReason(side.reason);
            reasons(end + 1, 1) = reason; %#ok<AGROW>
            if strlength(detail) > 0
                row.geometry_reason_detail = detail;
            end
        end
        if parameters.refuse_extrapolated_alignment && ...
                (side.event_extrapolated || side.bracket_extrapolated)
            reasons(end + 1, 1) = "alignment_extrapolated"; %#ok<AGROW>
        end
    end
    computed = sideA.status == "computed" && sideB.status == "computed";
    if computed
        if sideA.unit ~= sideB.unit
            inputInvalid("Entity %d's distances are in two units (%s, %s); one frame is required.", ...
                entity.entity_id, sideA.unit, sideB.unit);
        end
        if ~ismember(sideA.unit, parameters.accepted_frame_units)
            reasons(end + 1, 1) = "frame_unit_not_accepted";
        elseif sideA.distance < parameters.min_distance || ...
                sideB.distance < parameters.min_distance
            reasons(end + 1, 1) = "distance_degenerate";
        end
    end
end
if observed.status ~= "computed"
    reasons(end + 1, 1) = observed.reason;
end
reasons = canonicalOrder(unique(reasons, "stable"));
row.no_score_reasons = {reasons};
if ~isempty(reasons)
    row.no_score_reason = reasons(1);
    return
end

% THE COMBINATION, named for what it combines so a reader and the package
% guard (test_combination_package_boundary) both see it: acoustic evidence
% minus the level difference pose/location evidence predicts.
ratio = row.distance_b / row.distance_a;
distancePredictedDb = 20 * log10(ratio);
acousticObservedDb = observed.value;
row.distance_ratio_b_over_a = ratio;
row.predicted_difference_db = distancePredictedDb;
row.discrepancy_db = acousticObservedDb - distancePredictedDb;
row.score = -abs(row.discrepancy_db);
row.status = "scored";
row.score_semantics = semantics;
end

function [sideA, sideB] = sides(geometry, entityId, pair, basis)
for name = ["entity_id", "channel_index", "instant_basis", "distance", "unit", ...
        "status", "reason", "event_extrapolated", "bracket_extrapolated"]
    if ~ismember(name, string(geometry.Properties.VariableNames))
        inputInvalid("geometry has no %s column.", name);
    end
end
sideA = oneSide(geometry, entityId, pair(1), basis);
sideB = oneSide(geometry, entityId, pair(2), basis);
end

function value = oneSide(geometry, entityId, channel, basis)
match = geometry.entity_id == entityId & geometry.channel_index == channel & ...
    string(geometry.instant_basis) == basis;
if sum(match) ~= 1
    inputInvalid("geometry has %d rows for entity %d, channel %d, instant basis %s; " + ...
        "exactly one is required. Request every channel of the declared pair.", ...
        sum(match), entityId, channel, basis);
end
row = geometry(match, :);
value = struct(distance=double(row.distance), unit=string(row.unit), ...
    status=string(row.status), reason=string(row.reason), ...
    event_extrapolated=logical(row.event_extrapolated), ...
    bracket_extrapolated=logical(row.bracket_extrapolated));
end

function [reason, detail] = geometryReason(raw)
% candidateGeometry's row reasons are D10's codes, except the distance
% primitive's own position_missing and z_missing. Both mean the instant has no
% usable position, which is what track_not_covered says; the original word is
% kept as detail rather than lost.
detail = "";
switch raw
    case {"position_missing", "z_missing"}
        reason = "track_not_covered";
        detail = raw;
    case {"track_not_covered", "track_covered_empty", "bodypart_missing", "channel_unplaced"}
        reason = raw;
    otherwise
        inputInvalid("geometry carries an unrecognized reason '%s'.", raw);
end
end

function ordered = canonicalOrder(reasons)
% Contract 06 D10's closed set, in its order.
order = ["identity_no_track", "identity_multiple_tracks", ...
    "identity_changes_within_window", "identity_partial_window", ...
    "identity_unresolved", "track_not_covered", "track_covered_empty", ...
    "bodypart_missing", "alignment_extrapolated", "channel_unplaced", ...
    "frame_unit_not_accepted", "distance_degenerate", "acoustic_unavailable", ...
    "acoustic_clipped"];
[known, position] = ismember(reasons, order);
if any(~known)
    inputInvalid("'%s' is not a no-score reason this method knows.", ...
        strjoin(reasons(~known), "', '"));
end
[~, sorted] = sort(position);
ordered = reasons(sorted);
ordered = ordered(:);
end

function row = blankRow(entity, pair, basis, observedValue)
trackId = "";
associationId = NaN;
if ismember("native_track_id", string(entity.Properties.VariableNames))
    trackId = string(entity.native_track_id);
end
if ismember("tracking_identity_association_id", string(entity.Properties.VariableNames))
    associationId = double(entity.tracking_identity_association_id);
end
row = table(double(entity.entity_id), "unscored", NaN, "", "", {strings(0, 1)}, "", ...
    trackId, associationId, basis, pair(1), pair(2), NaN, NaN, "", NaN, NaN, ...
    observedValue, NaN, VariableNames=["entity_id", "status", "score", ...
    "score_semantics", "no_score_reason", "no_score_reasons", ...
    "geometry_reason_detail", "native_track_id", "tracking_identity_association_id", ...
    "instant_basis", "channel_index_a", "channel_index_b", "distance_a", ...
    "distance_b", "distance_unit", "distance_ratio_b_over_a", ...
    "predicted_difference_db", "observed_difference_db", "discrepancy_db"]);
end

function value = scoreSemantics(settings)
p = settings.parameters;
value = sprintf("%s %s: score = -|observed - predicted| inter-channel level " + ...
    "difference in dB for the ordered channel pair (a=%d, b=%d); observed = " + ...
    "10*log10(P_a/P_b) of normalized band power, predicted = 20*log10(d_b/d_a) " + ...
    "under %s spreading at the %s instant of bodypart %s; unit dB; " + ...
    "higher_is_stronger, 0 is perfect agreement; %s; comparable %s only; " + ...
    "settings %s %s; not a probability", settings.method_key, ...
    settings.method_version, p.channel_pair(1), p.channel_pair(2), ...
    p.spreading_assumption, p.primary_instant_basis, p.bodypart, ...
    settings.calibration_status.state, settings.scaling.comparability_scope, ...
    settings.profile_key, settings.version_label);
value = string(value);
end

function inputInvalid(varargin)
error("vawlume:estimator:MethodInputInvalid", varargin{:});
end
