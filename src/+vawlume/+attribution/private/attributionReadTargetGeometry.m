function targets = attributionReadTargetGeometry(conn, attributionRunId)
%ATTRIBUTIONREADTARGETGEOMETRY Each target's interval on the recording's clock.
%
% A target names one event from one event set, and the three event sets carry
% their extent differently:
%
%   detection        its own start_time_s and end_time_s
%   consensus event  its own start_time_s and end_time_s
%   agreement group  NO interval of its own. The extent is derived, and the
%                    target declares WHICH derivation it meant through
%                    agreement_extent_method, read from v_agreement_group_extent.
%
% An agreement-group target whose declared extent is empty -- members that do not
% all overlap, under the intersection method -- has no interval, and is returned
% with NaN bounds rather than a fabricated one. A caller comparing against it must
% see that rather than receive a plausible number.

rows = fetch(conn, "SELECT t.attribution_target_id AS target_id, " + ...
    "IFNULL(t.detection_id,-1) AS detection_id, " + ...
    "IFNULL(t.consensus_event_id,-1) AS consensus_event_id, " + ...
    "IFNULL(t.agreement_group_id,-1) AS agreement_group_id, " + ...
    "IFNULL(t.agreement_extent_method,'') AS agreement_extent_method, " + ...
    "IFNULL(d.start_time_s, IFNULL(c.start_time_s, IFNULL(g.start_time_s, 1e308))) AS start_time_s, " + ...
    "IFNULL(d.end_time_s, IFNULL(c.end_time_s, IFNULL(g.end_time_s, 1e308))) AS end_time_s, " + ...
    "IFNULL(d.recording_id, IFNULL(c.recording_id, IFNULL(g.recording_id, -1))) AS recording_id, " + ...
    "IFNULL(g.extent_is_empty, 0) AS extent_is_empty " + ...
    "FROM attribution_targets t " + ...
    "LEFT JOIN detections d ON d.detection_id = t.detection_id " + ...
    "LEFT JOIN consensus_events c ON c.consensus_event_id = t.consensus_event_id " + ...
    "LEFT JOIN (SELECT ag.agreement_group_id, ag.recording_id, " + ...
    "    e.extent_method, e.start_time_s, e.end_time_s, e.extent_is_empty " + ...
    "  FROM agreement_groups ag " + ...
    "  JOIN v_agreement_group_extent e " + ...
    "    ON e.agreement_group_id = ag.agreement_group_id) g " + ...
    "  ON g.agreement_group_id = t.agreement_group_id " + ...
    " AND g.extent_method = t.agreement_extent_method " + ...
    "WHERE t.attribution_run_id=" + string(attributionRunId) + ...
    " ORDER BY t.attribution_target_id");

count = height(rows);
targets = table(NaN(count, 1), strings(count, 1), strings(count, 1), ...
    NaN(count, 1), NaN(count, 1), NaN(count, 1), false(count, 1), ...
    VariableNames=["attribution_target_id", "target_kind", ...
    "target_extent_basis", "recording_id", ...
    "start_time_s", "end_time_s", "extent_is_empty"]);
if count == 0
    return
end

targets.attribution_target_id = double(rows.target_id);
% Which derivation supplied this target's interval. Empty for a detection or a
% consensus event, which carry their own. Carried out of here rather than left
% behind, because a consumer comparing two bases must be able to say which
% result rests on which.
targets.target_extent_basis = presentText(rows.agreement_extent_method);
targets.recording_id = nullableNumber(double(rows.recording_id));
targets.start_time_s = nullableNumber(double(rows.start_time_s));
targets.end_time_s = nullableNumber(double(rows.end_time_s));
targets.extent_is_empty = double(rows.extent_is_empty) == 1;

kind = strings(count, 1);
kind(double(rows.detection_id) > 0) = "detection";
kind(double(rows.consensus_event_id) > 0) = "consensus_event";
kind(double(rows.agreement_group_id) > 0) = "agreement_group";
targets.target_kind = kind;

% An empty agreement extent has no interval to compare against. Reporting NaN
% keeps that visible instead of letting a reversed or invented interval through.
targets.start_time_s(targets.extent_is_empty) = NaN;
targets.end_time_s(targets.extent_is_empty) = NaN;
end

function value = nullableNumber(value)
value(value >= 1e308 | value < 0) = NaN;
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
