function assessment = deepsqueakVersionCompatibility(profileDocument, declaredVersion)
%DEEPSQUEAKVERSIONCOMPATIBILITY Compare caller-declared extractor version to scope.
%
% The comparison is driven entirely by the profile's declared
% extractor.version_scope strings, so no extractor release list is hard-coded
% here. A trailing "x" component in a declared scope matches any value in that
% position, which is how the shipped scopes ("3.2.x", "3.x") are written.
%
% ASSESSMENT.status is one of:
%   preferred          - inside extractor.version_scope.preferred
%   compatible_family  - outside preferred but inside compatible_family
%   incompatible       - outside both declared scopes
%   missing_required   - not supplied while the profile requires it at ingest
%   missing_optional   - not supplied and the profile does not require it
%
% This adapter never invents a version. The workbook does not encode a
% trustworthy extractor version, so evidence must come from the caller.

arguments
    profileDocument (1,1) struct
    declaredVersion (1,1) string
end

scope = declaredScope(profileDocument);

assessment = struct();
assessment.declared_version = strtrim(declaredVersion);
assessment.preferred_scope = scope.preferred;
assessment.compatible_family = scope.compatible_family;
assessment.required_at_ingest = scope.required_at_ingest;
assessment.severity = "info";

if strlength(assessment.declared_version) == 0
    if scope.required_at_ingest
        assessment.status = "missing_required";
        assessment.severity = "warning";
        assessment.message = ...
            "Profile declares extractor.version_required_at_ingest, but no " + ...
            "extractor version was supplied. Reading is permitted for " + ...
            "inspection; database ingest must reject this.";
    else
        assessment.status = "missing_optional";
        assessment.message = ...
            "No extractor version was supplied and the profile does not " + ...
            "require one at ingest.";
    end
    return
end

if matchesScope(assessment.declared_version, scope.preferred)
    assessment.status = "preferred";
    assessment.message = "Declared extractor version " + ...
        assessment.declared_version + " is inside the profile's preferred " + ...
        "scope " + scope.preferred + ".";
elseif matchesScope(assessment.declared_version, scope.compatible_family)
    assessment.status = "compatible_family";
    assessment.message = "Declared extractor version " + ...
        assessment.declared_version + " is outside the preferred scope " + ...
        scope.preferred + " but inside the compatible family " + ...
        scope.compatible_family + ".";
else
    assessment.status = "incompatible";
    assessment.severity = "warning";
    assessment.message = "Declared extractor version " + ...
        assessment.declared_version + " is outside every scope declared by " + ...
        "this profile (preferred " + scope.preferred + ", compatible family " + ...
        scope.compatible_family + ").";
end
end

function scope = declaredScope(profileDocument)
scope = struct(preferred="", compatible_family="", required_at_ingest=false);
if ~isfield(profileDocument, "extractor") || ~isstruct(profileDocument.extractor)
    return
end
extractor = profileDocument.extractor;
scope.required_at_ingest = profileFlag(extractor, "version_required_at_ingest");
if ~isfield(extractor, "version_scope") || ~isstruct(extractor.version_scope)
    return
end
scope.preferred = profileText(extractor.version_scope, "preferred");
scope.compatible_family = profileText(extractor.version_scope, "compatible_family");
end

function tf = matchesScope(version, scopePattern)
tf = false;
if strlength(scopePattern) == 0
    return
end
if version == scopePattern
    tf = true;
    return
end

scopeParts = split(scopePattern, ".");
versionParts = split(version, ".");
if numel(versionParts) < numel(scopeParts) && ~any(lower(scopeParts) == "x")
    return
end

for index = 1:numel(scopeParts)
    scopePart = strtrim(scopeParts(index));
    if lower(scopePart) == "x" || scopePart == "*"
        % A wildcard component ends the comparison: everything after it is
        % unconstrained by the declared scope.
        tf = true;
        return
    end
    if index > numel(versionParts)
        return
    end
    if strtrim(versionParts(index)) ~= scopePart
        return
    end
end

tf = true;
end

function value = profileText(container, field)
value = "";
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
try
    candidate = string(container.(char(field)));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = strtrim(candidate);
end
end

function tf = profileFlag(container, field)
tf = false;
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
try
    tf = logical(container.(char(field)));
catch
    tf = false;
end
if ~isscalar(tf)
    tf = false;
end
end
