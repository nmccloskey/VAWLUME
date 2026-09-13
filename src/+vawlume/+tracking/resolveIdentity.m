function result = resolveIdentity(conn, streamRef, interval, options)
%RESOLVEIDENTITY Ask for ONE identity answer, and get the reasoning with it.
%
%   result = VAWLUME.TRACKING.RESOLVEIDENTITY(conn, streamRef, [start end])
%   result = VAWLUME.TRACKING.RESOLVEIDENTITY(..., NativeTrackIds="track0")
%
% VAWLUME.TRACKING.IDENTITYCANDIDATES returns every overlapping claim and never
% chooses. That is correct for a query layer: a storage or query layer that
% invented precedence would hide evidence. But a consumer that must act — an
% attribution run asking which animal a track represents — needs one answer, and
% making every such consumer invent its own rule would produce several
% incompatible rules and no record of any of them.
%
% So the rule lives here, is invoked explicitly, and reports itself.
%
% THE RULE, applied per native track, in order:
%
%   1. A claim whose assignment_state is 'rejected' is never chosen.
%   2. State precedence: assigned > candidate > ambiguous > unresolved.
%   3. Among claims still tied, the NARROWEST interval covering the query wins.
%   4. Still tied: no selection. The tied claims are reported.
%
% Step 3 is the substantive one. It answers the case this rule exists for — a
% session-long weak candidate beside a precise manual correction over a crossing
% — because a narrower interval is the structural signal that somebody looked
% harder at that moment.
%
% THE RULE KEYS ONLY ON CLOSED VOCABULARY AND INTERVAL GEOMETRY, deliberately.
% evidence_kind, identity_value_semantics, review_state and method are free text
% by design, so that an unfamiliar upstream system is not forced into the wrong
% category. A precedence rule reading them would work for the strings seen so far
% and fail silently on the first unfamiliar one. The association table carries no
% creation timestamp, so recency is unavailable and is not used.
%
% IDENTITY_VALUE IS NOT READ. A higher similarity score does not outrank a lower
% one here: the scores are free-text-semantics numbers from different upstream
% systems on different scales, and nothing establishes they are comparable. That
% refusal is the same one the alignment layer makes about anchor uncertainty.
%
% RESULT fields:
%
%   resolutions   one row per requested track: entity_id (NaN when unresolved),
%                 decided_by_step, reason, considered_count, set_aside_count
%   set_aside     every claim not chosen, with why_not
%   candidates    the IDENTITYCANDIDATES result this read, rejected claims
%                 included
%   rule          the rule's own statement of what it did and did not use
%
% A resolution is not evidence that the chosen entity is correct. It is a record
% of which stored claim a stated rule selected. Attribution evidence derived from
% one must cite the association it rests on.
%
% See also VAWLUME.TRACKING.IDENTITYCANDIDATES,
% VAWLUME.TRACKING.REGISTERIDENTITYASSOCIATION

arguments
    conn
    streamRef (1,1) struct
    interval (1,2) double {mustBeFinite}
    options.NativeTrackIds (1,:) string = string.empty
end

% Read through the query layer rather than around it, so the two can never
% disagree about what claims exist.
%
% IncludeRejected is deliberately on. `identityCandidates` omits rejected claims
% by default, which is right for a query; here it would make step 1 of the rule
% invisible, so a reader could not tell whether a rejected claim existed at all
% or whether the rule had declined to use one. The claims come in, and the ones
% the rule refuses are reported as set aside with the reason.
%
% `result.candidates` therefore contains rejected rows that a default
% `identityCandidates` call would not return.
candidates = vawlume.tracking.identityCandidates(conn, streamRef, interval, ...
    NativeTrackIds=options.NativeTrackIds, IncludeRejected=true);

associations = candidates.associations;
trackIds = unique(string(candidates.tracks.native_track_id), "stable");

resolutions = emptyResolutions();
setAside = emptySetAside();
for index = 1:numel(trackIds)
    trackId = trackIds(index);
    claims = associations(string(associations.native_track_id) == trackId, :);
    [resolution, rejected] = resolveOneTrack(trackId, claims, interval);
    resolutions = [resolutions; resolution]; %#ok<AGROW>
    setAside = [setAside; rejected]; %#ok<AGROW>
end

result = struct();
result.stream = candidates.stream;
result.requested_interval = interval;
result.resolutions = resolutions;
result.set_aside = setAside;
result.candidates = candidates;
result.rule = struct( ...
    key="state_precedence_then_interval_specificity", ...
    version="0.1.0", ...
    steps=["rejected claims are never chosen"; ...
        "assigned > candidate > ambiguous > unresolved"; ...
        "narrowest interval covering the query wins"; ...
        "still tied: no selection"], ...
    uses=["assignment_state"; "interval geometry"], ...
    does_not_use=["identity_value"; "evidence_kind"; "review_state"; ...
        "method"; "recency"], ...
    why_not="Those are free text or unavailable. A rule keyed on them would " + ...
        "work for the strings seen so far and fail silently on the first " + ...
        "unfamiliar one.");
result.boundary = "A resolution records which stored claim a stated rule " + ...
    "selected. It is not evidence that the entity is correct, and it does " + ...
    "not become identity evidence in its own right.";
end

% ---------------------------------------------------------------- helpers ---

function [resolution, setAside] = resolveOneTrack(trackId, claims, interval)
setAside = emptySetAside();
consideredCount = height(claims);

if consideredCount == 0
    resolution = resolutionRow(trackId, NaN, "", 0, ...
        "no_claims", "No identity claim covers this track over the window.", ...
        0, 0);
    return
end

% Step 1. Rejected claims are out, at every step, and are reported as set aside
% rather than silently dropped.
isRejected = string(claims.assignment_state) == "rejected";
setAside = [setAside; setAsideRows(trackId, claims(isRejected, :), ...
    "assignment_state is rejected")];
live = claims(~isRejected, :);

if height(live) == 0
    resolution = resolutionRow(trackId, NaN, "", 0, "all_rejected", ...
        "Every claim over this window is rejected.", consideredCount, ...
        height(claims));
    return
end

% Step 2. State precedence over a closed vocabulary.
order = ["assigned", "candidate", "ambiguous", "unresolved"];
rank = NaN(height(live), 1);
for index = 1:height(live)
    match = find(order == string(live.assignment_state(index)), 1);
    if ~isempty(match)
        rank(index) = match;
    end
end
best = min(rank);
isBest = rank == best;
setAside = [setAside; setAsideRows(trackId, live(~isBest, :), ...
    "a stronger assignment_state is present")];
contenders = live(isBest, :);

if height(contenders) == 1
    resolution = resolveTo(trackId, contenders, "state_precedence", ...
        "Selected on assignment_state alone: " + ...
        string(contenders.assignment_state(1)) + " outranks every other claim " + ...
        "over this window.", consideredCount, height(setAside));
    return
end

% Step 3. Interval specificity. A narrower interval covering the query is the
% structural signal that somebody looked harder at that moment.
widths = double(contenders.end_time_native) - double(contenders.start_time_native);
narrowest = min(widths);
isNarrowest = widths == narrowest;
setAside = [setAside; setAsideRows(trackId, contenders(~isNarrowest, :), ...
    "a claim with a narrower interval covers the same window")];
finalists = contenders(isNarrowest, :);

if height(finalists) == 1
    resolution = resolveTo(trackId, finalists, "interval_specificity", ...
        sprintf("Tied on assignment_state; selected the narrowest covering " + ...
        "interval (%.6g s against %.6g s).", narrowest, max(widths)), ...
        consideredCount, height(setAside));
    return
end

% Step 4. Still tied. Refusing is the honest outcome: an arbitrary tiebreak here
% would be a silent rule, and the caller can see the tie and decide.
setAside = [setAside; setAsideRows(trackId, finalists, ...
    "tied with another claim on state and interval width")];
resolution = resolutionRow(trackId, NaN, "", 0, "tied", ...
    sprintf("%d claims tie on assignment_state and interval width. " + ...
    "No rule here separates them; the tie is reported rather than broken.", ...
    height(finalists)), consideredCount, height(setAside));
end

function resolution = resolveTo(trackId, chosen, step, reason, considered, setAsideCount)
resolution = resolutionRow(trackId, double(chosen.entity_id(1)), ...
    presentText(chosen.entity_native_id(1)), ...
    double(chosen.tracking_identity_association_id(1)), ...
    step, reason, considered, setAsideCount);
end

function row = resolutionRow(trackId, entityId, entityNativeId, associationId, ...
        step, reason, considered, setAsideCount)
row = table(string(trackId), entityId, string(entityNativeId), associationId, ...
    string(step), string(reason), considered, setAsideCount, ...
    VariableNames=["native_track_id", "entity_id", "entity_native_id", ...
    "tracking_identity_association_id", "decided_by_step", "reason", ...
    "considered_count", "set_aside_count"]);
end

function rows = setAsideRows(trackId, claims, whyNot)
rows = emptySetAside();
for index = 1:height(claims)
    rows = [rows; table(string(trackId), ...
        double(claims.tracking_identity_association_id(index)), ...
        double(claims.entity_id(index)), ...
        string(claims.assignment_state(index)), ...
        double(claims.start_time_native(index)), ...
        double(claims.end_time_native(index)), ...
        string(whyNot), ...
        VariableNames=["native_track_id", ...
        "tracking_identity_association_id", "entity_id", "assignment_state", ...
        "start_time_native", "end_time_native", "why_not"])]; %#ok<AGROW>
end
end

function value = emptyResolutions()
value = table('Size', [0 8], ...
    'VariableTypes', ["string", "double", "string", "double", "string", ...
    "string", "double", "double"], ...
    'VariableNames', ["native_track_id", "entity_id", "entity_native_id", ...
    "tracking_identity_association_id", "decided_by_step", "reason", ...
    "considered_count", "set_aside_count"]);
end

function value = emptySetAside()
value = table('Size', [0 7], ...
    'VariableTypes', ["string", "double", "double", "string", "double", ...
    "double", "string"], ...
    'VariableNames', ["native_track_id", ...
    "tracking_identity_association_id", "entity_id", "assignment_state", ...
    "start_time_native", "end_time_native", "why_not"]);
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
