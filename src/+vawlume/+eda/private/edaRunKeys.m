function keys = edaRunKeys(explorationRunKey, configurationId, recordingId, pairKeys)
%EDARUNKEYS The contract's run-key template, in one place.
%
% Derived, never generated: no timestamp, no counter, no random suffix. A
% non-deterministic key would make a rerun indistinguishable from new work and
% would defeat resumability entirely - the runner reuses an analysis by finding
% it under the key it would have written, so the key has to be a function of what
% is being run.
%
%   matching    <run>/<configuration>/m/r<recording>/<key_a>-<key_b>
%   agreement   <run>/<configuration>/a/r<recording>
%
% PAIRKEYS is [lowerExtractorKey, higherExtractorKey] in ascending order, which
% is the workflow's one pair-ordering rule and the direction every signed
% difference is expressed in.
prefix = explorationRunKey + "/" + configurationId;
keys = struct( ...
    agreement=prefix + "/a/r" + string(recordingId), ...
    matching="");
if nargin >= 4 && ~isempty(pairKeys)
    keys.matching = prefix + "/m/r" + string(recordingId) + "/" + ...
        pairKeys(1) + "-" + pairKeys(2);
end
end
