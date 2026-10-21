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
%
% VALUES is a numeric vector (one number per name), or a cell array with one
% entry per name (contract 07 D6, itinerary 7.8). In a cell, a number is
% formatted %.17g exactly as in the numeric form, a numeric vector is its
% elements' %.17g joined by ",", and text enters VERBATIM (an instant basis, a
% reference type). A numeric call's identity is bit-identical to what it was
% before text was admitted; a test pins it.
names = string(names(:));
if iscell(values)
    values = values(:);
    texts = strings(numel(values), 1);
    for index = 1:numel(values)
        texts(index) = valueText(values{index});
    end
else
    values = double(values(:));
    texts = strings(numel(values), 1);
    for index = 1:numel(values)
        texts(index) = string(sprintf("%.17g", values(index)));
    end
end
if numel(names) ~= numel(texts)
    error("vawlume:eda:ConfigurationIdentityInvalid", ...
        "Each parameter name needs exactly one value.");
end
[sortedNames, order] = sort(names);
sortedTexts = texts(order);
parts = strings(numel(sortedNames), 1);
for index = 1:numel(sortedNames)
    parts(index) = sortedNames(index) + "=" + sortedTexts(index);
end
payload = strjoin(parts, ";");
digest = edaSha256OfText(payload);
identity = struct( ...
    configuration_id="cfg-" + extractBefore(digest, 11), ...
    identity_payload=payload, ...
    digest_sha256=digest);
end

function text = valueText(value)
if isnumeric(value) || islogical(value)
    value = double(value(:))';
    parts = strings(1, numel(value));
    for k = 1:numel(value)
        parts(k) = string(sprintf("%.17g", value(k)));
    end
    text = strjoin(parts, ",");
elseif (isstring(value) || ischar(value)) && isscalar(string(value))
    text = string(value);
else
    error("vawlume:eda:ConfigurationIdentityInvalid", ...
        "A configuration value must be a number, a numeric vector or one text value.");
end
end
