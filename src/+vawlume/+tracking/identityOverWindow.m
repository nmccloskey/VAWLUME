function result = identityOverWindow(conn, streamRef, interval, options)
%IDENTITYOVERWINDOW Which entity each native track represents, and whether for the WHOLE window.
%
%   result = VAWLUME.TRACKING.IDENTITYOVERWINDOW(conn, streamRef, [start end])
%   result = VAWLUME.TRACKING.IDENTITYOVERWINDOW(..., NativeTrackIds=["track0" "track1"])
%
% INTERVAL is in the tracking stream's NATIVE units, as identity associations
% are. A caller relating a vocal event to identity first places the call on the
% tracking clock through the alignment layer, then asks here; this function does
% no clock arithmetic.
%
% It composes vawlume.tracking.resolveIdentity and ADDS NO PRECEDENCE RULE. Which
% claim a track resolves to is resolveIdentity's answer, with its
% decided_by_step and its set-aside claims returned unchanged. What this adds is
% the question resolveIdentity does not ask: is that answer valid for the whole
% window, or does identity change inside it?
%
% TIME VALIDITY, per track (docs/design/06_native_estimator_contract.md D9):
%
%   whole_window           the chosen claim's interval covers the entire window,
%                          and no other live claim names a different entity (or
%                          an explicit unresolved statement) over part of it
%   changes_within_window  another live claim for the track names a different
%                          entity, or none, over PART of the window - an
%                          identity swap or a crossing during the call. Never
%                          answered by whichever claim covers the midpoint
%   partial                the chosen claim covers only part of the window, and
%                          nothing contradicts it there
%   none                   no claim was chosen: no evidence, all rejected, tied,
%                          or the chosen claim is itself an unresolved statement
%
% A competing claim that covers the WHOLE window is not a change within it: it
% is a rival over the same span, and resolveIdentity's rule already decided
% between them. Only a claim that starts or ends inside the window marks a change.
% Rejected claims never count.
%
% IDENTITY_STATUS, per track:
%   resolved      an entity was chosen
%   unresolved    the chosen claim is an explicit statement that identity is unknown
%   tied          resolveIdentity found a tie it would not break
%   all_rejected  every claim over the window was rejected
%   none          no claim at all: nobody looked
%
% IDENTITY_VALUE IS NOT READ, and nothing is weighted or averaged across claims.
% A resolution is a rule's choice, not identity evidence: evidence derived from
% it must cite tracking_identity_association_id.
%
% RESULT fields:
%   requested_interval
%   tracks          one row per track: native_track_id, identity_status, entity_id,
%                   entity_native_id, tracking_identity_association_id,
%                   decided_by_step, reason, time_validity,
%                   chosen_start_native, chosen_end_native, contradiction_count
%   contradictions  one row per live claim that marks a change within the window:
%                   native_track_id, tracking_identity_association_id, entity_id,
%                   assignment_state, start_time_native, end_time_native
%   set_aside, rule   from resolveIdentity, unchanged
%
% Read-only.
%
% See also VAWLUME.TRACKING.RESOLVEIDENTITY, VAWLUME.TRACKING.IDENTITYCANDIDATES

arguments
    conn
    streamRef (1,1) struct
    interval (1,2) double {mustBeFinite}
    options.NativeTrackIds (1,:) string = string.empty
end

resolved = vawlume.tracking.resolveIdentity(conn, streamRef, interval, ...
    NativeTrackIds=options.NativeTrackIds);
associations = resolved.candidates.associations;
live = associations(associations.assignment_state ~= "rejected", :);

tracks = emptyTracks();
contradictions = emptyContradictions();
for index = 1:height(resolved.resolutions)
    resolution = resolved.resolutions(index, :);
    trackId = resolution.native_track_id;
    trackClaims = live(live.native_track_id == trackId, :);
    associationId = double(resolution.tracking_identity_association_id);
    chosen = trackClaims(trackClaims.tracking_identity_association_id == associationId, :);

    status = identityStatus(resolution, chosen);
    chosenStart = NaN;
    chosenEnd = NaN;
    validity = "none";
    marks = emptyContradictions();
    if status == "resolved"
        chosenStart = double(chosen.start_time_native(1));
        chosenEnd = double(chosen.end_time_native(1));
        chosenEntity = double(chosen.entity_id(1));
        others = trackClaims(trackClaims.tracking_identity_association_id ~= associationId, :);
        differs = isnan(others.entity_id) | others.entity_id ~= chosenEntity;
        withinWindow = (others.start_time_native > interval(1)) | ...
            (others.end_time_native < interval(2));
        marking = others(differs & withinWindow, :);
        marks = table(marking.native_track_id, ...
            marking.tracking_identity_association_id, marking.entity_id, ...
            marking.assignment_state, marking.start_time_native, ...
            marking.end_time_native, VariableNames=emptyContradictions().Properties.VariableNames);
        coversWindow = chosenStart <= interval(1) && chosenEnd >= interval(2);
        if height(marks) > 0
            validity = "changes_within_window";
        elseif coversWindow
            validity = "whole_window";
        else
            validity = "partial";
        end
    end

    tracks = [tracks; table(trackId, status, double(resolution.entity_id), ...
        string(resolution.entity_native_id), associationId, ...
        string(resolution.decided_by_step), string(resolution.reason), validity, ...
        chosenStart, chosenEnd, height(marks), ...
        VariableNames=emptyTracks().Properties.VariableNames)]; %#ok<AGROW>
    contradictions = [contradictions; marks]; %#ok<AGROW>
end

result = struct(requested_interval=interval, tracks=tracks, ...
    contradictions=contradictions, set_aside=resolved.set_aside, ...
    rule=resolved.rule, ...
    boundary="A resolution records which stored claim a stated rule selected, " + ...
    "and time_validity whether that claim holds for the whole window. Neither " + ...
    "is evidence that the entity is correct.");
end

function status = identityStatus(resolution, chosen)
step = string(resolution.decided_by_step);
switch step
    case "no_claims"
        status = "none";
    case "all_rejected"
        status = "all_rejected";
    case "tied"
        status = "tied";
    otherwise
        if height(chosen) == 0 || isnan(double(chosen.entity_id(1)))
            status = "unresolved";
        else
            status = "resolved";
        end
end
end

function value = emptyTracks()
names = ["native_track_id", "identity_status", "entity_id", "entity_native_id", ...
    "tracking_identity_association_id", "decided_by_step", "reason", ...
    "time_validity", "chosen_start_native", "chosen_end_native", ...
    "contradiction_count"];
types = ["string", "string", "double", "string", "double", "string", "string", ...
    "string", "double", "double", "double"];
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end

function value = emptyContradictions()
names = ["native_track_id", "tracking_identity_association_id", "entity_id", ...
    "assignment_state", "start_time_native", "end_time_native"];
types = ["string", "double", "double", "string", "double", "double"];
value = table(Size=[0, numel(names)], VariableTypes=cellstr(types), ...
    VariableNames=cellstr(names));
end
