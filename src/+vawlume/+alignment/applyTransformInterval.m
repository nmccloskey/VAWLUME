function [intervals, transform] = applyTransformInterval(conn, alignmentRunId, ...
        startTimes, endTimes, options)
%APPLYTRANSFORMINTERVAL Express native source intervals on the reference clock.
%
% INTERVALS = vawlume.alignment.applyTransformInterval(CONN, ALIGNMENTRUNID,
% STARTTIMES, ENDTIMES) transforms each interval's endpoints through the stored
% transform and returns a table describing what happened to it.
%
% [INTERVALS, TRANSFORM] = ... also returns the transform of record, as
% VAWLUME.ALIGNMENT.APPLYTRANSFORM does.
%
% This is a separate function rather than a mode of APPLYTRANSFORM because an
% interval is a different question with a different answer shape, and a single
% entry point switching on its arguments is how two contracts start sharing one
% name.
%
% **Endpoints transform independently, so the aligned duration is not the native
% duration.** Under a piecewise transform whose segments differ in scale, an
% interval that crosses a breakpoint is stretched by one factor at its start and
% another at its end. That is correct rather than a defect: it is what a clock
% that changed rate means. A caller who assumes duration is preserved will be
% wrong exactly when drift matters most, so the change is reported rather than
% left to be noticed.
%
% An open interval — NaN or Inf end — is legal and stays open. An interval whose
% end precedes its start is refused.
%
% Columns of INTERVALS:
%
%   start_native, end_native
%   start_aligned, end_aligned
%   start_segment_index, end_segment_index
%   segments_crossed        how many segments the interval spans, 1 when it lies
%                           inside one; NaN for an open interval
%   crosses_breakpoint      true when its endpoints fall in different segments
%   start_extrapolated, end_extrapolated
%   native_duration_s, aligned_duration_s, duration_change_s
%   uncertainty_s           the larger endpoint bound, uncalibrated; see
%                           APPLYTRANSFORM
%
% Name-value arguments:
%   ErrorOnExtrapolation  raise instead of flagging (default false)
%
% See also VAWLUME.ALIGNMENT.APPLYTRANSFORM.

arguments
    conn
    alignmentRunId (1,1) double {mustBePositive, mustBeInteger}
    startTimes double
    endTimes double
    options.ErrorOnExtrapolation (1,1) logical = false
end

start = startTimes(:);
finish = endTimes(:);
if numel(start) ~= numel(finish)
    error("vawlume:alignment:AnchorPairMismatch", ...
        "Received %d interval starts and %d ends; they must be paired.", ...
        numel(start), numel(finish));
end

closed = isfinite(finish);
if any(finish(closed) < start(closed))
    error("vawlume:alignment:AlignedIntervalInvalid", ...
        "An interval ends before it starts; %d of %d are reversed.", ...
        nnz(finish(closed) < start(closed)), numel(start));
end

[startAligned, transform] = vawlume.alignment.applyTransform(conn, ...
    alignmentRunId, start, ErrorOnExtrapolation=options.ErrorOnExtrapolation);
startSegment = transform.segment_index;
startExtrapolated = transform.extrapolated;
startUncertainty = transform.uncertainty_s;

endAligned = finish;
endSegment = nan(size(finish));
endExtrapolated = false(size(finish));
endUncertainty = nan(size(finish));
if any(closed)
    [values, endTransform] = vawlume.alignment.applyTransform(conn, ...
        alignmentRunId, finish(closed), ...
        ErrorOnExtrapolation=options.ErrorOnExtrapolation);
    endAligned(closed) = values;
    endSegment(closed) = endTransform.segment_index;
    endExtrapolated(closed) = endTransform.extrapolated;
    endUncertainty(closed) = endTransform.uncertainty_s;
end

segmentsCrossed = nan(size(start));
segmentsCrossed(closed) = endSegment(closed) - startSegment(closed) + 1;
crossesBreakpoint = false(size(start));
crossesBreakpoint(closed) = endSegment(closed) > startSegment(closed);

nativeDuration = finish - start;
alignedDuration = endAligned - startAligned;

intervals = table(start, finish, startAligned, endAligned, ...
    startSegment, endSegment, segmentsCrossed, crossesBreakpoint, ...
    startExtrapolated, endExtrapolated, ...
    nativeDuration, alignedDuration, alignedDuration - nativeDuration, ...
    max(startUncertainty, endUncertainty), ...
    VariableNames=["start_native", "end_native", "start_aligned", "end_aligned", ...
    "start_segment_index", "end_segment_index", "segments_crossed", ...
    "crosses_breakpoint", "start_extrapolated", "end_extrapolated", ...
    "native_duration_s", "aligned_duration_s", "duration_change_s", ...
    "uncertainty_s"]);
end
