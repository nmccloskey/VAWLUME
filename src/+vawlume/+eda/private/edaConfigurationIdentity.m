function identity = edaConfigurationIdentity(names, values)
%EDACONFIGURATIONIDENTITY Stable identifier for one point in the design.
%
% The governing contract fixes the derivation: SHA-256 over the name-sorted,
% %.17g-formatted active parameter values joined "name=value" with ";", prefixed
% "cfg-" and truncated to ten hex characters.
%
% NAME-SORTED so the identifier does not depend on the order the design happened
% to list its factors. %.17g so two doubles that differ in the last bit get
% different identifiers: a shorter format could collapse two genuinely different
% probe values onto one identity, and the identifier is what joins responses back
% to the configuration that produced them.
%
% The identifier is a HANDLE, never the record of what was run. The full
% parameter values travel beside it in every table that uses it.
names = string(names(:));
values = double(values(:));
if numel(names) ~= numel(values)
    error("vawlume:eda:ConfigurationIdentityInvalid", ...
        "Each parameter name needs exactly one value.");
end
[sortedNames, order] = sort(names);
sortedValues = values(order);
parts = strings(numel(sortedNames), 1);
for index = 1:numel(sortedNames)
    parts(index) = sortedNames(index) + "=" + ...
        string(sprintf("%.17g", sortedValues(index)));
end
payload = strjoin(parts, ";");
digest = edaSha256OfText(payload);
identity = struct( ...
    configuration_id="cfg-" + extractBefore(digest, 11), ...
    identity_payload=payload, ...
    digest_sha256=digest);
end
