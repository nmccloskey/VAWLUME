function [values, segmentIndex] = evaluateSegments(segments, times)
%EVALUATESEGMENTS Apply a segmented transform at given source times.
%
% [VALUES, SEGMENTINDEX] = vawlume.alignment.internal.evaluateSegments(SEGMENTS, TIMES) selects the
% segment covering each source time and returns
%
%   value = scale * time + offset_s
%
% for that segment, preserving the shape of TIMES.
%
% **A segment covers [source_start, source_end).** A time exactly at a boundary
% belongs to the segment that begins there. The first segment's `source_start`
% and the last segment's `source_end` are NaN, meaning open, so every finite time
% falls in exactly one segment.
%
% This function exists so that the fitter and the applier cannot disagree about
% that rule. An off-by-one at a breakpoint is the defect most likely to survive
% review, and the only reliable defence is one implementation rather than two
% that happen to match today.
%
% SEGMENTS is a table of `segment_index`, `source_start`, `source_end`, `scale`
% and `offset_s`, ordered by `segment_index`. It is expected to tile the source
% axis; vawlume.alignment.internal.assertSegmentsTile checks that before any such table is stored.

arguments
    segments table
    times double
end

column = times(:);
segmentIndex = zeros(numel(column), 1);

starts = double(segments.source_start);
for index = 1:height(segments)
    lower = starts(index);
    if isnan(lower)
        % The first segment is open below.
        selected = true(numel(column), 1);
    else
        selected = column >= lower;
    end
    segmentIndex(selected) = index;
end

% A time below a finite first boundary would leave index 0. Tiled segments open
% the first one, so this can only happen if a caller hands over an untiled table.
if any(segmentIndex == 0)
    error("vawlume:alignment:SegmentTilingInvalid", ...
        ['Source time %g falls in no segment. Segments must tile the source ' ...
        'axis, with the first open below and the last open above.'], ...
        column(find(segmentIndex == 0, 1)));
end

values = double(segments.scale(segmentIndex)) .* column + ...
    double(segments.offset_s(segmentIndex));

values = reshape(values, size(times));
segmentIndex = reshape(segmentIndex, size(times));
end
