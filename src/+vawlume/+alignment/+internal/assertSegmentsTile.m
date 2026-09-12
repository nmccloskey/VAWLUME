function assertSegmentsTile(segments, sourceTimebaseKey)
%ASSERTSEGMENTSTILE Refuse segments that gap or overlap, on write.
%
% `11_temporal_alignment_schema.md` lists segment tiling as an obligation the
% database cannot express and application code therefore owes. This is where that
% obligation stops being a promise: nothing reaches alignment_segments without
% passing here.
%
% The rules, which are the ones stated in the temporal-alignment contract:
%
%   * segment_index runs 1..n with no gaps;
%   * the first segment is open below and the last open above (NaN bounds);
%   * every interior boundary is finite;
%   * each segment's source_start equals the previous segment's source_end
%     exactly, so there is neither a gap nor an overlap between them;
%   * boundaries strictly increase, so no segment is empty.
%
% Exact equality is deliberate rather than a tolerance. Both numbers come from
% the same declared breakpoint, so they are the same double; if they ever differ,
% something derived one of them rather than carrying it, and that is worth
% failing on.

arguments
    segments table
    sourceTimebaseKey (1,1) string
end

count = height(segments);
prefix = "Transform for source timebase '" + sourceTimebaseKey + "' ";
if count == 0
    error("vawlume:alignment:SegmentTilingInvalid", ...
        "%swould store no segment.", prefix);
end

if ~isequal(double(segments.segment_index(:))', 1:count)
    error("vawlume:alignment:SegmentTilingInvalid", ...
        "%smust number its segments 1..%d in order.", prefix, count);
end

starts = double(segments.source_start);
ends = double(segments.source_end);

if ~isnan(starts(1))
    error("vawlume:alignment:SegmentTilingInvalid", ...
        ['%sbounds its first segment below at %g. The first segment is open, ' ...
        'so every source time before the first breakpoint has a segment.'], ...
        prefix, starts(1));
end
if ~isnan(ends(count))
    error("vawlume:alignment:SegmentTilingInvalid", ...
        ['%sbounds its last segment above at %g. The last segment is open, ' ...
        'so every source time after the last breakpoint has a segment.'], ...
        prefix, ends(count));
end

for index = 1:count - 1
    if ~isfinite(ends(index))
        error("vawlume:alignment:SegmentTilingInvalid", ...
            "%sleaves segment %d open above, but it is not the last segment.", ...
            prefix, index);
    end
    if ~isfinite(starts(index + 1))
        error("vawlume:alignment:SegmentTilingInvalid", ...
            "%sleaves segment %d open below, but it is not the first segment.", ...
            prefix, index + 1);
    end
    if starts(index + 1) ~= ends(index)
        error("vawlume:alignment:SegmentTilingInvalid", ...
            ['%sends segment %d at %.17g and begins segment %d at %.17g. ' ...
            'Segments must tile the source range: a gap leaves times with no ' ...
            'transform, and an overlap gives one time two.'], ...
            prefix, index, ends(index), index + 1, starts(index + 1));
    end
    if index > 1 && ends(index) <= starts(index)
        error("vawlume:alignment:SegmentTilingInvalid", ...
            "%sgives segment %d an empty or reversed range.", prefix, index);
    end
end
end
