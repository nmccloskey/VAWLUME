function result = positionAtInstants(sampleTimes, positions, queryTimes, options)
%POSITIONATINSTANTS Position of one tracked trace at declared instants, or why not.
%
%   result = VAWLUME.GEOMETRY.POSITIONATINSTANTS(sampleTimes, positions, ...
%       queryTimes, MaxGapS=0.1)
%   result = VAWLUME.GEOMETRY.POSITIONATINSTANTS(..., PoseConfidence=conf)
%
% SAMPLETIMES is one (track, bodypart) trace's sample times, N-by-1, on ONE
% clock. POSITIONS is N-by-2 or N-by-3 (x, y, optional z), all in one frame.
% QUERYTIMES are the instants wanted, on the same clock. POSECONFIDENCE is an
% optional N-by-1 upstream keypoint confidence.
%
% PURE. No database, no file, and no clock. The caller places the instants and
% the samples on one clock first, through the alignment layer; this function
% never sees a clock reference, so it cannot become transform arithmetic under
% another name. It is one of the three places spatial arithmetic may occur, all
% in +geometry/.
%
% THE POLICY (docs/design/06_native_estimator_contract.md D4):
%
%   observed      a query time equal to a sample time returns that sample.
%                 Equality is exact; there is no tolerance to choose.
%   interpolated  a query time strictly between two usable samples whose gap is
%                 at most MaxGapS is linearly interpolated between them.
%   not_covered   anything else, with a reason:
%                   no_samples           the trace has no usable sample
%                   before_first_sample  no extrapolation backwards
%                   after_last_sample    no extrapolation forwards
%                   gap_exceeds_max      the bracketing samples are too far apart
%
% There is NO extrapolation and NO nearest-sample fallback. A position the
% tracker did not observe and cannot be bracketed closely is not an estimate.
%
% A SAMPLE WITH A MISSING x OR y IS NOT A SAMPLE. It is dropped before
% bracketing, so a run of dropped frames becomes a gap the MaxGapS rule judges,
% rather than a bracket that silently spans it. A missing z (in 3D) stays a
% missing z: an interpolated z exists only when both brackets have one.
%
% INPUT IS REFUSED, NOT REPAIRED. Sample times must be finite and strictly
% increasing (vawlume:geometry:SampleTimesInvalid). Sorting quietly would hide a
% tracker export with a problem the caller should see.
%
% MAXGAPS IS REQUIRED. It is the policy's one parameter, and a code default
% would be a second, unversioned copy of a setting that belongs in the caller's
% versioned profile (vawlume:geometry:MaxGapRequired).
%
% POSE CONFIDENCE TRAVELS BESIDE THE POSITION, NEVER INTO IT. Both bracketing
% samples' confidences are returned, and pose_confidence_min_bracket is their
% minimum. If either bracket has none, the minimum is NaN: absence is not
% imputed by taking whichever value happens to exist.
%
% RESULT is a table with one row per query time:
%   query_time, x, y, z, basis, reason,
%   bracket_before_time, bracket_after_time, gap_s,
%   pose_confidence_before, pose_confidence_after, pose_confidence_min_bracket
%
% See also VAWLUME.GEOMETRY.DISTANCE, VAWLUME.GEOMETRY.SUMMARIZEDISTANCES

arguments
    sampleTimes double
    positions double
    queryTimes double
    options.MaxGapS (1,1) double = NaN
    options.PoseConfidence double = []
end

if ~isfinite(options.MaxGapS) || options.MaxGapS < 0
    error("vawlume:geometry:MaxGapRequired", ...
        "MaxGapS is required: the largest gap, in the clock's seconds, across " + ...
        "which a position may be interpolated. It must be finite and nonnegative.");
end
sampleTimes = sampleTimes(:);
queryTimes = queryTimes(:);
validateSamples(sampleTimes, positions);
if any(~isfinite(queryTimes))
    error("vawlume:geometry:QueryTimesInvalid", "Query times must be finite.");
end
confidence = NaN(numel(sampleTimes), 1);
if ~isempty(options.PoseConfidence)
    if numel(options.PoseConfidence) ~= numel(sampleTimes)
        error("vawlume:geometry:PoseConfidenceInvalid", ...
            "PoseConfidence needs one value per sample (%d), not %d.", ...
            numel(sampleTimes), numel(options.PoseConfidence));
    end
    confidence = options.PoseConfidence(:);
end
if size(positions, 2) == 2
    positions = [positions, NaN(size(positions, 1), 1)];
end

usable = ~any(isnan(positions(:, 1:2)), 2);
times = sampleTimes(usable);
points = positions(usable, :);
confidence = confidence(usable);

count = numel(queryTimes);
result = table(queryTimes, NaN(count, 1), NaN(count, 1), NaN(count, 1), ...
    repmat("not_covered", count, 1), strings(count, 1), NaN(count, 1), ...
    NaN(count, 1), NaN(count, 1), NaN(count, 1), NaN(count, 1), NaN(count, 1), ...
    VariableNames=["query_time", "x", "y", "z", "basis", "reason", ...
    "bracket_before_time", "bracket_after_time", "gap_s", ...
    "pose_confidence_before", "pose_confidence_after", ...
    "pose_confidence_min_bracket"]);

for k = 1:count
    t = queryTimes(k);
    if isempty(times)
        result.reason(k) = "no_samples";
        continue
    end
    hit = find(times == t, 1);
    if ~isempty(hit)
        result{k, ["x", "y", "z"]} = points(hit, :);
        result.basis(k) = "observed";
        result{k, ["bracket_before_time", "bracket_after_time"]} = [t t];
        result.gap_s(k) = 0;
        result{k, ["pose_confidence_before", "pose_confidence_after", ...
            "pose_confidence_min_bracket"]} = repmat(confidence(hit), 1, 3);
        continue
    end
    if t < times(1)
        result.reason(k) = "before_first_sample";
        continue
    end
    if t > times(end)
        result.reason(k) = "after_last_sample";
        continue
    end
    after = find(times > t, 1);
    before = after - 1;
    gap = times(after) - times(before);
    result{k, ["bracket_before_time", "bracket_after_time"]} = ...
        [times(before) times(after)];
    result.gap_s(k) = gap;
    result{k, ["pose_confidence_before", "pose_confidence_after"]} = ...
        [confidence(before) confidence(after)];
    if gap > options.MaxGapS
        result.reason(k) = "gap_exceeds_max";
        continue
    end
    weight = (t - times(before)) / gap;
    result{k, ["x", "y", "z"]} = points(before, :) + ...
        weight * (points(after, :) - points(before, :));
    result.basis(k) = "interpolated";
    result.pose_confidence_min_bracket(k) = ...
        minimumOrMissing(confidence(before), confidence(after));
end
end

function validateSamples(sampleTimes, positions)
if ~ismatrix(positions) || ~ismember(size(positions, 2), [2 3]) || ...
        size(positions, 1) ~= numel(sampleTimes)
    error("vawlume:geometry:PositionDimensionalityInvalid", ...
        "Positions must be N-by-2 or N-by-3 with one row per sample time.");
end
if any(~isfinite(sampleTimes))
    error("vawlume:geometry:SampleTimesInvalid", "Sample times must be finite.");
end
if any(diff(sampleTimes) <= 0)
    error("vawlume:geometry:SampleTimesInvalid", ...
        "Sample times must be strictly increasing. Unsorted or duplicated " + ...
        "times are refused rather than sorted: a trace that emitted them has " + ...
        "a problem the caller should see.");
end
end

function value = minimumOrMissing(first, second)
if isnan(first) || isnan(second)
    value = NaN;
else
    value = min(first, second);
end
end
