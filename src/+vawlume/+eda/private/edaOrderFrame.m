function frame = edaOrderFrame(frame)
%EDAORDERFRAME Put a sampling frame into the one stated deterministic order.
%
% Applied both by the resolver and again by the sampler. The second application
% is not redundant: it is what makes the drawn set independent of the order the
% caller happened to hand the rows in, which is the property the frame-shuffle
% test asserts. A sampler that trusted its input order would pass a determinism
% test and still return a different subset for a caller who had sorted their
% table differently.
%
% See edaFrameOrderingKey for why the native identifier leads.

arguments
    frame table
end

frame = sortrows(frame, ["native_recording_id", "recording_id"]);
end
