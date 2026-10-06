function value = attributionProducerLabel(systemName, systemVersion)
%ATTRIBUTIONPRODUCERLABEL How a producing system is named inside a semantics string.
%
% The version joins the name only when one was actually declared. The shipped
% templates default to the literal "unknown", and rendering "Example System
% unknown" would put a disclaimer where a reader expects a version -- worse than
% emitting nothing, because it reads like a version somebody chose.
value = strtrim(string(systemName));
version = strtrim(string(systemVersion));
if strlength(value) == 0
    value = "";
    return
end
if strlength(version) > 0 && lower(version) ~= "unknown"
    value = value + " " + version;
end
end
