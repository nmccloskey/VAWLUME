function value = edaConfigurationId(versionLabel)
%EDACONFIGURATIONID Recover a probe configuration identifier from a version label.
%
% The governing contract gives a generated probe specification the version label
% "<base version>+exp.<configuration_id>", so a human reading analysis_runs can
% identify the configuration without recomputing a checksum. This recovers that
% suffix.
%
% An analysis produced from a tracked specification rather than a generated
% probe one carries no such suffix and gets "". That is the ordinary case before
% the screening layer exists, and it is reported as absent rather than
% substituted with the version label, because a configuration identifier that is
% sometimes a hash and sometimes a version string cannot be grouped on.
value = "";
label = string(versionLabel);
if ~isscalar(label) || ismissing(label)
    return
end
marker = "+exp.";
if ~contains(label, marker)
    return
end
value = extractAfter(label, marker);
end
