function specification = matchingLoadSpec(profilePath, repoRoot)
%MATCHINGLOADSPEC Read and validate a temporal matching specification.

if strlength(profilePath) == 0
    profilePath = fullfile(repoRoot, "config", "05_matching_profiles", ...
        "prototype_matching_consilience_spec.json");
elseif ~java.io.File(char(profilePath)).isAbsolute()
    profilePath = fullfile(repoRoot, profilePath);
end
profilePath = canonicalPath(profilePath);
if ~isfile(profilePath)
    error("vawlume:matching:SpecificationNotFound", ...
        "Matching specification does not exist: %s", profilePath);
end
try
    document = jsondecode(fileread(profilePath));
catch exception
    error("vawlume:matching:SpecificationInvalid", ...
        "Could not decode matching specification %s: %s", ...
        profilePath, exception.message);
end

requiredStruct(document, "profile");
requiredStruct(document, "algorithm");
requiredStruct(document, "run_pair");
requiredStruct(document, "candidate_generation");
requiredStruct(document.candidate_generation, "plausibility_rule");
requiredStruct(document, "candidate_scoring");
requiredStruct(document, "assignment");
requiredStruct(document, "consensus");
requiredStruct(document.consensus, "by_topology");
profile = document.profile;
algorithm = document.algorithm;
pair = document.run_pair;
generation = document.candidate_generation;
rule = generation.plausibility_rule;
scoring = document.candidate_scoring;
assignment = document.assignment;
consensus = document.consensus.by_topology;

profileKey = requiredText(profile, "id");
profileName = requiredText(profile, "name");
profileKind = requiredText(profile, "kind");
schemaVersion = requiredText(profile, "profile_schema_version");
versionLabel = requiredText(profile, "profile_version");
algorithmKey = requiredText(algorithm, "key");
algorithmVersion = requiredText(algorithm, "version");
if profileKind ~= "consilience_policy"
    error("vawlume:matching:UnexpectedSpecificationKind", ...
        "Matching specification profile.kind must be 'consilience_policy', not '%s'.", ...
        profileKind);
end
requiredTrue(pair, "require_same_recording");
requiredTrue(pair, "require_distinct_extraction_runs");
requiredTrue(pair, "require_distinct_extractors");
requiredTrue(generation, "exhaustive_within_rule");
requiredTrue(rule, "require_positive_overlap");
if requiredText(scoring, "candidate_score_definition") ~= "temporal_iou"
    error("vawlume:matching:SpecificationInvalid", ...
        "candidate_score_definition must be 'temporal_iou'.");
end
if ~isfield(scoring, "combined_scalar_score") || ...
        ~islogical(scoring.combined_scalar_score) || scoring.combined_scalar_score
    error("vawlume:matching:SpecificationInvalid", ...
        "combined_scalar_score must be false for the Phase 6 contract.");
end
if ~isfield(rule, "min_temporal_iou") || ...
        ~isnumeric(rule.min_temporal_iou) || ~isscalar(rule.min_temporal_iou) || ...
        ~isfinite(rule.min_temporal_iou) || rule.min_temporal_iou < 0 || ...
        rule.min_temporal_iou > 1
    error("vawlume:matching:SpecificationInvalid", ...
        "plausibility_rule.min_temporal_iou must be a finite scalar in [0, 1].");
end
plausibilityRule = struct();
plausibilityRule.min_temporal_iou = double(rule.min_temporal_iou);
plausibilityRule.max_abs_onset_difference_s = optionalMagnitudeBound(rule, ...
    "max_abs_onset_difference_s", ...
    "vawlume:matching:MaxAbsOnsetDifferenceInvalid");
plausibilityRule.max_abs_offset_difference_s = optionalMagnitudeBound(rule, ...
    "max_abs_offset_difference_s", ...
    "vawlume:matching:MaxAbsOffsetDifferenceInvalid");
plausibilityRule.max_abs_duration_difference_s = optionalMagnitudeBound(rule, ...
    "max_abs_duration_difference_s", ...
    "vawlume:matching:MaxAbsDurationDifferenceInvalid");
if requiredText(assignment, "model") ~= ...
        "connected_components_over_candidate_edges"
    error("vawlume:matching:SpecificationInvalid", ...
        "assignment.model must be 'connected_components_over_candidate_edges'.");
end
requiredFalse(assignment, "force_one_to_one");
expectedTopology = ["one_to_one"; "one_to_many"; "many_to_one"; ...
    "many_to_many"; "unmatched"];
if ~isfield(assignment, "topology_vocabulary") || ...
        ~isequal(string(assignment.topology_vocabulary(:)), expectedTopology)
    error("vawlume:matching:SpecificationInvalid", ...
        "assignment.topology_vocabulary does not match the Phase 6 contract.");
end
validateConsensus(consensus, "one_to_one", true, ...
    "mean_boundary_of_members");
validateConsensus(consensus, "one_to_many", true, ...
    "union_boundary_of_members");
validateConsensus(consensus, "many_to_one", true, ...
    "union_boundary_of_members");
validateConsensus(consensus, "many_to_many", false, "");
validateConsensus(consensus, "unmatched", false, "");

specification = struct( ...
    document=document, ...
    source_path=profilePath, ...
    content_uri=portableUri(profilePath, repoRoot), ...
    checksum_sha256=matchingSha256OfFile(profilePath), ...
    profile_key=profileKey, ...
    profile_name=profileName, ...
    profile_kind=profileKind, ...
    profile_schema_version=schemaVersion, ...
    version_label=versionLabel, ...
    algorithm_key=algorithmKey, ...
    algorithm_version=algorithmVersion, ...
    min_temporal_iou=plausibilityRule.min_temporal_iou, ...
    plausibility_rule=plausibilityRule);
end

function value = optionalMagnitudeBound(container, field, identifier)
%OPTIONALMAGNITUDEBOUND Validate one optional plausibility bound in seconds.
%
% The bound constrains the magnitude of a signed evidence field returned by
% vawlume.interval.relation, so a pair at -0.05 s is excluded exactly as one at
% +0.05 s. The max_abs_ prefix carries that meaning in the field name itself.
%
% Absent means unconstrained and is returned as NaN, which no declared value can
% take because a declared bound must be finite. The field is optional rather
% than defaulted because matchingSha256OfFile hashes exact file bytes: requiring
% it would change every tracked specification's checksum and so invalidate the
% identity of every matching analysis already stored against one.
value = NaN;
if ~isfield(container, field)
    return
end
raw = container.(field);
if ~isnumeric(raw) || ~isscalar(raw) || ~isreal(raw) || ~isfinite(raw) || raw < 0
    error(identifier, ...
        "plausibility_rule.%s must be a finite real scalar >= 0 in seconds " + ...
        "when present. Omit the field to leave the dimension unconstrained.", ...
        field);
end
value = double(raw);
end

function requiredFalse(container, field)
if ~isfield(container, field) || ~islogical(container.(field)) || ...
        ~isscalar(container.(field)) || container.(field)
    error("vawlume:matching:SpecificationInvalid", ...
        "Matching specification field '%s' must be false.", field);
end
end

function validateConsensus(container, topology, expectedEmit, expectedMethod)
requiredStruct(container, topology);
policy = container.(topology);
if ~isfield(policy, "emit") || ~islogical(policy.emit) || ...
        ~isscalar(policy.emit) || policy.emit ~= expectedEmit
    error("vawlume:matching:SpecificationInvalid", ...
        "consensus.by_topology.%s.emit differs from the Phase 6 contract.", ...
        topology);
end
if expectedEmit && requiredText(policy, "derivation_method") ~= expectedMethod
    error("vawlume:matching:SpecificationInvalid", ...
        "consensus.by_topology.%s.derivation_method is unsupported.", topology);
end
end

function requiredStruct(container, field)
if ~isstruct(container) || ~isfield(container, field) || ...
        ~isstruct(container.(field)) || ~isscalar(container.(field))
    error("vawlume:matching:SpecificationInvalid", ...
        "Matching specification requires object '%s'.", field);
end
end

function value = requiredText(container, field)
if ~isfield(container, field)
    error("vawlume:matching:SpecificationInvalid", ...
        "Matching specification requires text field '%s'.", field);
end
try
    value = string(container.(field));
catch
    value = "";
end
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:matching:SpecificationInvalid", ...
        "Matching specification field '%s' must be nonempty scalar text.", field);
end
value = strtrim(value);
end

function requiredTrue(container, field)
if ~isfield(container, field) || ~islogical(container.(field)) || ...
        ~isscalar(container.(field)) || ~container.(field)
    error("vawlume:matching:SpecificationInvalid", ...
        "Matching specification field '%s' must be true.", field);
end
end

function value = portableUri(path, repoRoot)
path = replace(canonicalPath(path), "\", "/");
root = strip(replace(canonicalPath(repoRoot), "\", "/"), "right", "/");
prefix = root + "/";
if startsWith(lower(path), lower(prefix))
    value = extractAfter(path, strlength(prefix));
else
    value = path;
end
end

function value = canonicalPath(value)
try
    value = string(java.io.File(char(value)).getCanonicalPath());
catch
    value = string(value);
end
end
