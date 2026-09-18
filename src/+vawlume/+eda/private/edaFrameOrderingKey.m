function value = edaFrameOrderingKey()
%EDAFRAMEORDERINGKEY The stated ordering key a sampling frame is drawn from.
%
% A sample is reproducible only if the row order it indexes into is reproducible,
% so the frame is sorted before any random key is assigned and the key is stated
% in the subset record.
%
% `native_recording_id` first, `recording_id` second. The surrogate key alone
% would be simpler and is the wrong choice: `recordings.recording_id` is assigned
% by insertion order, so re-ingesting the same audio in a different order gives
% the same study a different frame and therefore a different subset under the
% same seed. The native identifier travels with the data, so two databases built
% from the same recordings order their frames identically. The surrogate key
% breaks ties, because `native_recording_id` is nullable and not declared unique.
value = "ascending native_recording_id, ties broken by ascending recording_id";
end
