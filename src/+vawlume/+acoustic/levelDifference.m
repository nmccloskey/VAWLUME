function difference = levelDifference(sideA, sideB, refuseClippedChannels)
%LEVELDIFFERENCE Observed inter-channel level difference of one event, in dB.
%
%   difference = VAWLUME.ACOUSTIC.LEVELDIFFERENCE(sideA, sideB, refuseClipped)
%
% For an ORDERED channel pair (a, b) of normalized power values of one event:
%
%   value = 10 * log10(P_a / P_b)   [dB]
%
% POSITIVE WHEN CHANNEL a IS LOUDER than channel b, relative to each channel's
% own reference response; 0 dB when they are equal; swapping a and b negates it
% exactly. Contract 06 D6 fixes this convention, and the native method (D7)
% compares its predicted 20*log10(d_b/d_a) against exactly this quantity.
%
% SIDEA and SIDEB are one row each of normalizeCallLevels' outcomes table (or
% structs with the same fields): target_kind, target_id, channel_index,
% normalized_metric, unit, status, reason, value, qc_flags and
% derived_measurement_id. REFUSECLIPPEDCHANNELS is required and has no
% default: whether a clipped side is fatal is the estimator profile's
% declared parameter (parameters.refuse_clipped_channels), not this code's.
%
% This function compares two acoustic measurements of ONE quantity -- the same
% normalized metric, on two channels, for one event. It combines no evidence
% dimensions, takes no position, distance, entity or candidate, and says
% nothing about who called. Relating the difference to a candidate's position
% is the native method's job (+estimator/).
%
% It is pure: nothing is read from or written to the database, and the result
% is NOT persisted as a measurement. It is reconstructible exactly from the two
% cited per-channel rows (contract 06 D6, itinerary Q6(b)).
%
% Refusal (status "refused", value NaN), checked side a then side b, every
% applicable reason listed in REASONS and the first in REASON:
%   a_missing / b_missing          the side has no normalized value (its own
%                                  reason, e.g. source_measurement_absent, is
%                                  in reason_a / reason_b)
%   a_nonpositive / b_nonpositive  the value is not positive, so its log is
%                                  undefined
%   a_clipped / b_clipped          the side carries clipped_samples and
%                                  refuseClippedChannels is true. A clipped
%                                  level is a lower bound, so the difference
%                                  would be biased in a known direction
%
% Misuse raises vawlume:acoustic:LevelDifferenceInputInvalid: a missing field,
% the same channel twice, two different events, different metrics or units, or
% a metric that is not a normalized one.
%
% Every other flag on either side (partial coverage, a divergent response) is
% carried in FLAGS as "a:<flag>" or "b:<flag>", never repaired.

arguments
    sideA
    sideB
    refuseClippedChannels (1,1) logical
end

a = readSide(sideA, "sideA");
b = readSide(sideB, "sideB");
if a.channel_index == b.channel_index
    invalid("The two sides are the same channel (%d).", a.channel_index);
end
if a.target_kind ~= b.target_kind || a.target_id ~= b.target_id
    invalid("The two sides belong to different events.");
end
if a.normalized_metric ~= b.normalized_metric || a.unit ~= b.unit
    invalid("The two sides are different quantities (%s %s, %s %s).", ...
        a.normalized_metric, a.unit, b.normalized_metric, b.unit);
end
if a.unit ~= "ratio_to_channel_response" || ~endsWith(a.normalized_metric, "_normalized")
    invalid("A level difference is defined on normalized values only, not %s in %s.", ...
        a.normalized_metric, a.unit);
end

reasons = [sideReasons(a, "a", refuseClippedChannels); ...
    sideReasons(b, "b", refuseClippedChannels)];
flags = [prefixed(a.qc_flags, "a"); prefixed(b.qc_flags, "b")];

difference = struct( ...
    status="refused", ...
    reason="", ...
    reasons=reasons, ...
    value=NaN, ...
    unit="dB", ...
    formula="10*log10(P_a/P_b)", ...
    sign_convention="positive when channel a is louder than channel b", ...
    metric_key=a.normalized_metric, ...
    target_kind=a.target_kind, ...
    target_id=a.target_id, ...
    channel_index_a=a.channel_index, ...
    channel_index_b=b.channel_index, ...
    value_a=a.value, ...
    value_b=b.value, ...
    derived_measurement_id_a=a.derived_measurement_id, ...
    derived_measurement_id_b=b.derived_measurement_id, ...
    reason_a=a.reason, ...
    reason_b=b.reason, ...
    flags=flags, ...
    refuse_clipped_channels=refuseClippedChannels);
if isempty(reasons)
    difference.status = "computed";
    difference.value = 10 * log10(a.value / b.value);
else
    difference.reason = reasons(1);
end
end

function reasons = sideReasons(side, label, refuseClipped)
reasons = strings(0, 1);
if side.status ~= "normalized" || ~isfinite(side.value)
    reasons(end + 1, 1) = label + "_missing";
    return
end
if side.value <= 0
    reasons(end + 1, 1) = label + "_nonpositive";
end
if refuseClipped && any(side.qc_flags == "clipped_samples")
    reasons(end + 1, 1) = label + "_clipped";
end
end

function side = readSide(raw, label)
if istable(raw)
    if height(raw) ~= 1
        invalid("%s must be exactly one outcome row.", label);
    end
    raw = table2struct(raw);
end
if ~isstruct(raw) || ~isscalar(raw)
    invalid("%s must be one outcome row or a scalar struct.", label);
end
required = ["target_kind", "target_id", "channel_index", "normalized_metric", ...
    "unit", "status", "reason", "value", "qc_flags", "derived_measurement_id"];
missing = required(~isfield(raw, required));
if ~isempty(missing)
    invalid("%s is missing %s.", label, strjoin(missing, ", "));
end
flags = raw.qc_flags;
if iscell(flags)
    flags = flags{1};
end
side = struct(target_kind=string(raw.target_kind), target_id=double(raw.target_id), ...
    channel_index=double(raw.channel_index), ...
    normalized_metric=string(raw.normalized_metric), unit=string(raw.unit), ...
    status=string(raw.status), reason=string(raw.reason), value=double(raw.value), ...
    qc_flags=string(flags(:)), derived_measurement_id=double(raw.derived_measurement_id));
if strlength(side.unit) == 0 && side.status ~= "normalized"
    % An unnormalized side carries no unit; it is still the declared quantity.
    side.unit = "ratio_to_channel_response";
end
end

function values = prefixed(flags, label)
values = label + ":" + flags(:);
if isempty(flags)
    values = strings(0, 1);
end
end

function invalid(varargin)
error("vawlume:acoustic:LevelDifferenceInputInvalid", varargin{:});
end
