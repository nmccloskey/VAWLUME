function assessment = extractorVersionCompatibility(profileDocument, declaredVersion)
%EXTRACTORVERSIONCOMPATIBILITY Compare declared version to profile scope.

arguments
    profileDocument (1,1) struct
    declaredVersion (1,1) string
end

scope = declaredScope(profileDocument);
assessment = struct(declared_version=strtrim(declaredVersion), ...
    preferred_scope=scope.preferred, compatible_family=scope.compatible_family, ...
    required_at_ingest=scope.required_at_ingest, severity="info");

if strlength(assessment.declared_version) == 0
    if scope.required_at_ingest
        assessment.status = "missing_required";
        assessment.severity = "warning";
        assessment.message = "Profile declares extractor.version_required_at_ingest, but no " + ...
            "extractor version was supplied. Reading is permitted for inspection; database ingest must reject this.";
    else
        assessment.status = "missing_optional";
        assessment.message = "No extractor version was supplied and the profile does not require one at ingest.";
    end
elseif matchesScope(assessment.declared_version, scope.preferred)
    assessment.status = "preferred";
    assessment.message = "Declared extractor version " + assessment.declared_version + ...
        " is inside the profile's preferred scope " + scope.preferred + ".";
elseif matchesScope(assessment.declared_version, scope.compatible_family)
    assessment.status = "compatible_family";
    assessment.message = "Declared extractor version " + assessment.declared_version + ...
        " is outside the preferred scope " + scope.preferred + ...
        " but inside the compatible family " + scope.compatible_family + ".";
else
    assessment.status = "incompatible";
    assessment.severity = "warning";
    assessment.message = "Declared extractor version " + assessment.declared_version + ...
        " is outside every scope declared by this profile (preferred " + ...
        scope.preferred + ", compatible family " + scope.compatible_family + ").";
end
end

function scope = declaredScope(document)
scope = struct(preferred="", compatible_family="", required_at_ingest=false);
if ~isfield(document, "extractor") || ~isstruct(document.extractor), return, end
extractor = document.extractor;
scope.required_at_ingest = profileFlag(extractor, "version_required_at_ingest");
if ~isfield(extractor, "version_scope") || ~isstruct(extractor.version_scope), return, end
scope.preferred = profileText(extractor.version_scope, "preferred");
scope.compatible_family = profileText(extractor.version_scope, "compatible_family");
end

function tf = matchesScope(version, pattern)
tf = false;
if strlength(pattern) == 0, return, end
if version == pattern, tf = true; return, end
scopeParts = split(pattern, ".");
versionParts = split(version, ".");
if numel(versionParts) < numel(scopeParts) && ~any(lower(scopeParts) == "x"), return, end
for index = 1:numel(scopeParts)
    part = strtrim(scopeParts(index));
    if lower(part) == "x" || part == "*", tf = true; return, end
    if index > numel(versionParts) || strtrim(versionParts(index)) ~= part, return, end
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
