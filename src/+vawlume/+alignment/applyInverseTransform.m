function [native, transform] = applyInverseTransform(conn, alignmentRunId, referenceTimes, options)
%APPLYINVERSETRANSFORM Express reference-clock times on a source's native clock.
%
% NATIVE = vawlume.alignment.applyInverseTransform(CONN, ALIGNMENTRUNID, REFERENCETIMES)
% inverts the stored transform of one pairwise alignment run: for each reference
% time it selects the segment whose IMAGE on the reference clock covers it and
% returns
%
%   native = (reference - offset_s) / scale
%
% for that segment, preserving the shape of REFERENCETIMES.
%
% [NATIVE, TRANSFORM] = ... also returns the transform of record, with the same
% fields VAWLUME.ALIGNMENT.APPLYTRANSFORM returns, its per-element fields
% describing these inverted times, and direction = "reference_to_native".
%
% Development plan section 4.3 assigns "reference -> native transforms when
% mathematically supported" to this package. A reader that must choose which
% source samples to read for an instant known on the reference clock - tracking
% samples around a call, say - needs exactly this, and computing it anywhere else
% would be transform arithmetic outside +alignment/.
%
% **The forward transform is the authority, unchanged.** This function asks
% APPLYTRANSFORM to describe the run (status, stored segments, anchored range)
% and inverts those coefficients. It never refits, and the forward functions are
% not modified to support it.
%
% **Invertible only when monotone and continuous.** Every segment must have a
% positive scale, and adjacent segments must meet at their breakpoints. A fitted
% piecewise transform is continuous by construction (see
% docs/development/13_transform_fitting_and_alignment_qc.md); a stored transform
% that is not - a hand-built one, say - maps some reference times to two native
% times or to none, and is refused (vawlume:alignment:TransformNotInvertible)
% rather than inverted region by region. Meeting is judged to within
% max(1e-9 s, 1e-12 x |reference time|), which absorbs floating-point rounding
% in the stored coefficients and nothing a clock could plausibly do.
%
% **Segment selection mirrors the forward rule.** A segment's image covers
% [its image start, the next segment's image start), the first open below. A
% reference time exactly at an image breakpoint belongs to the segment beginning
% there - the same segment the forward transform assigns the native breakpoint
% to, so a native -> reference -> native round trip at a breakpoint returns the
% breakpoint.
%
% **Extrapolation is flagged on the native side, as the forward function flags
% it.** A reference time whose native image lies outside the range the anchors
% covered is still inverted, and marked in TRANSFORM.extrapolated.
% ErrorOnExtrapolation=true escalates it to vawlume:alignment:ExtrapolatedTime.
%
% **Uncertainty is the stored segment bound, on the reference clock**, exactly as
% APPLYTRANSFORM reports it: uncalibrated, not a confidence interval, a standard
% error, or a probability, and NaN where no contributing anchor recorded one. It
% is not rescaled to the native clock; doing that would be a new derived quantity
% nobody has validated.
%
% Name-value arguments:
%   ErrorOnExtrapolation  raise instead of flagging (default false)
%
% See also VAWLUME.ALIGNMENT.APPLYTRANSFORM, VAWLUME.ALIGNMENT.APPLYTRANSFORMINTERVAL

arguments
    conn
    alignmentRunId (1,1) double {mustBePositive, mustBeInteger}
    referenceTimes double = double.empty(0, 1)
    options.ErrorOnExtrapolation (1,1) logical = false
end

% The forward function owns status checks, segment reading and tiling checks,
% and the anchored range. Called with no times it describes the run.
[~, transform] = vawlume.alignment.applyTransform(conn, alignmentRunId);
segments = transform.segments;
assertInvertible(segments, alignmentRunId);

column = referenceTimes(:);
if any(~isfinite(column))
    error("vawlume:alignment:ReferenceTimeInvalid", ...
        "Reference times must be finite to be inverted.");
end

scale = double(segments.scale);
offset = double(segments.offset_s);
imageStarts = scale .* double(segments.source_start) + offset;   % NaN when open

segmentIndex = zeros(numel(column), 1);
for index = 1:height(segments)
    if isnan(imageStarts(index))
        selected = true(numel(column), 1);
    else
        selected = column >= imageStarts(index);
    end
    segmentIndex(selected) = index;
end
if any(segmentIndex == 0)
    error("vawlume:alignment:ReferenceTimeOutsideTransform", ...
        ['Reference time %g lies below the image of this bounded transform; ' ...
        'no segment maps any native time there.'], column(find(segmentIndex == 0, 1)));
end

values = (column - offset(segmentIndex)) ./ scale(segmentIndex);

extrapolated = false(size(values));
if transform.anchored_range_known && ~isempty(values)
    extrapolated = values < transform.anchored_range_start | ...
        values > transform.anchored_range_end;
end
if options.ErrorOnExtrapolation && any(extrapolated)
    outside = values(extrapolated);
    error("vawlume:alignment:ExtrapolatedTime", ...
        ['Reference time maps to source time %g, outside the range the anchors ' ...
        'covered, [%g, %g]. The inverse still evaluates there, but the transform ' ...
        'was never anchored there; pass ErrorOnExtrapolation=false to accept ' ...
        'the extrapolation and read the flag instead.'], ...
        outside(1), transform.anchored_range_start, transform.anchored_range_end);
end

native = reshape(values, size(referenceTimes));
transform.direction = "reference_to_native";
transform.segment_index = reshape(segmentIndex, size(referenceTimes));
transform.extrapolated = reshape(extrapolated, size(referenceTimes));
if isempty(segmentIndex)
    transform.uncertainty_s = double.empty(size(referenceTimes));
    transform.uncertainty_semantics = strings(size(referenceTimes));
else
    transform.uncertainty_s = reshape(double(segments.uncertainty_s(segmentIndex)), ...
        size(referenceTimes));
    transform.uncertainty_semantics = reshape( ...
        string(segments.uncertainty_semantics(segmentIndex)), size(referenceTimes));
end
transform.source = "inverse of the stored alignment_segments coefficients; not refitted";
end

function assertInvertible(segments, alignmentRunId)
scale = double(segments.scale);
if any(~(scale > 0))
    error("vawlume:alignment:TransformNotInvertible", ...
        ['Transform run %d has a segment with non-positive scale (%g). A clock ' ...
        'that stands still or runs backwards cannot be inverted: some reference ' ...
        'times would map to no native time or to several.'], ...
        alignmentRunId, scale(find(~(scale > 0), 1)));
end
offset = double(segments.offset_s);
for index = 1:height(segments) - 1
    breakpoint = double(segments.source_start(index + 1));
    leftEnd = scale(index) * breakpoint + offset(index);
    rightStart = scale(index + 1) * breakpoint + offset(index + 1);
    tolerance = max(1e-9, 1e-12 * abs(rightStart));
    if abs(leftEnd - rightStart) > tolerance
        error("vawlume:alignment:TransformNotInvertible", ...
            ['Transform run %d is discontinuous at source time %g: segment %d ' ...
            'ends at reference %.12g and segment %d starts at %.12g. A ' ...
            'discontinuous transform maps some reference times to two native ' ...
            'times or to none, so it is not inverted.'], alignmentRunId, ...
            breakpoint, index, leftEnd, index + 1, rightStart);
    end
end
end
