function facts = trackingProfileFacts(irProfile, spec, repoRoot)
%TRACKINGPROFILEFACTS Identity and checksum of the profile that interpreted the artifact.
%
% Taken from the IR's own profile provenance rather than re-derived from the
% bundle, so the version registered is necessarily the exact document the mapper
% used. Re-resolving it here could disagree with what was actually applied.

facts = struct();
facts.profile_key = profileText(irProfile, "profile_key");
facts.profile_name = profileText(irProfile, "profile_name");
facts.profile_schema_version = profileText(irProfile, "profile_schema_version");
facts.version_label = profileText(irProfile, "profile_version");
if strlength(facts.version_label) == 0
    error("vawlume:tracking:ProfileVersionRequired", ...
        "Tracking profile '%s' declares no profile_version. A registration " + ...
        "records the exact profile version that interpreted its artifact, so " + ...
        "an undeclared version cannot be registered.", facts.profile_key);
end
facts.checksum_sha256 = profileText(irProfile, "profile_checksum");
facts.content_uri = profileText(irProfile, "profile_path");
if strlength(facts.content_uri) == 0
    facts.content_uri = trackingPortablePath(spec.profile_path, repoRoot);
end
facts.profile_id = NaN;
facts.profile_version_id = NaN;
end

function value = profileText(container, field)
value = "";
if ~isstruct(container) || ~isfield(container, char(field))
    return
end
candidate = string(container.(char(field)));
if isscalar(candidate) && ~ismissing(candidate)
    value = candidate;
end
end

function value = trackingPortablePath(path, repoRoot)
value = replace(string(path), "\", "/");
root = replace(string(repoRoot), "\", "/");
if strlength(root) == 0
    return
end
if ~endsWith(root, "/")
    root = root + "/";
end
if startsWith(value, root)
    value = extractAfter(value, strlength(root));
end
end
