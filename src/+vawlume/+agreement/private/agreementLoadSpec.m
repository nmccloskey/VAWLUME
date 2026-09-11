function specification = agreementLoadSpec(profilePath, repoRoot)
%AGREEMENTLOADSPEC Read and validate an arbitrary-N agreement policy.
%
% The policy states composition rules only. It must not introduce a threshold of
% its own: the candidate universe is already bounded by the versioned matching
% specification each source analysis recorded, and a second threshold authority
% here could silently re-filter evidence the pairwise layer already decided. A
% file that declares one is refused rather than partially honoured.

if strlength(profilePath) == 0
    profilePath = fullfile(repoRoot, "config", "07_agreement_profiles", ...
        "prototype_multi_extractor_agreement_spec.json");
elseif ~java.io.File(char(profilePath)).isAbsolute()
    profilePath = fullfile(repoRoot, profilePath);
end
profilePath = canonicalPath(profilePath);
if ~isfile(profilePath)
    error("vawlume:agreement:SpecificationNotFound", ...
        "Agreement policy does not exist: %s", profilePath);
end
try
    document = jsondecode(fileread(profilePath));
catch exception
    error("vawlume:agreement:SpecificationInvalid", ...
        "Could not decode agreement policy %s: %s", profilePath, exception.message);
end

requiredStruct(document, "profile");
requiredStruct(document, "algorithm");
requiredStruct(document, "source_analyses");
requiredStruct(document, "edge_universe");
requiredStruct(document, "composition");
requiredStruct(document, "non_filtering_contract");
requiredStruct(document, "analysis_identity");

profile = document.profile;
sourceRules = document.source_analyses;
edges = document.edge_universe;
composition = document.composition;

profileKind = requiredText(profile, "kind");
if profileKind ~= "consilience_policy"
    error("vawlume:agreement:UnexpectedSpecificationKind", ...
        "Agreement policy profile.kind must be 'consilience_policy', not '%s'.", ...
        profileKind);
end

assertNoThresholdDeclared(document, profilePath);
requiredTrue(edges, "defines_no_temporal_threshold");
requiredTrue(edges, "second_threshold_forbidden");
if requiredText(edges, "source") ~= ...
        "stored_candidate_pairs_of_declared_source_analyses"
    error("vawlume:agreement:SpecificationInvalid", ...
        "edge_universe.source must be the stored candidate pairs of the declared source analyses.");
end

requiredTrue(sourceRules, "require_distinct_extractor_per_run");
requiredTrue(sourceRules, "require_single_recording");
requiredTrue(sourceRules, "require_identical_matching_specification_version");
requiredTrue(sourceRules, "sources_are_evidence_not_children");
minimumSources = requiredPositiveInteger(sourceRules, "minimum_source_analyses");

if requiredText(composition, "component_rule") ~= ...
        "connected_components_over_supporting_edges"
    error("vawlume:agreement:SpecificationInvalid", ...
        "composition.component_rule must be 'connected_components_over_supporting_edges'.");
end
requiredTrue(composition, "singleton_inclusion");
requiredFalse(composition, "feature_support_is_admission_criterion");
if requiredText(composition, "clique_completeness") ~= "reported_not_required"
    error("vawlume:agreement:SpecificationInvalid", ...
        "composition.clique_completeness must be 'reported_not_required'.");
end
% Pinned for the same reason as its two siblings above. The composition records
% every edge's pairwise topology and never uses it to exclude a member, so a
% specification declaring any other propagation rule would be loaded, stored as
% run provenance, and then silently ignored.
if requiredText(composition, "ambiguity_propagation") ~= ...
        "recorded_per_edge_never_used_to_exclude"
    error("vawlume:agreement:SpecificationInvalid", ...
        "composition.ambiguity_propagation must be " + ...
        "'recorded_per_edge_never_used_to_exclude'.");
end

specification = struct( ...
    document=document, ...
    source_path=profilePath, ...
    content_uri=portableUri(profilePath, repoRoot), ...
    checksum_sha256=agreementSha256OfFile(profilePath), ...
    profile_key=requiredText(profile, "id"), ...
    profile_name=requiredText(profile, "name"), ...
    profile_kind=profileKind, ...
    profile_schema_version=requiredText(profile, "profile_schema_version"), ...
    version_label=requiredText(profile, "profile_version"), ...
    algorithm_key=requiredText(document.algorithm, "key"), ...
    algorithm_version=requiredText(document.algorithm, "version"), ...
    required_run_type=requiredText(sourceRules, "required_run_type"), ...
    required_status=requiredText(sourceRules, "required_status"), ...
    pairwise_coverage=requiredText(sourceRules, "pairwise_coverage"), ...
    minimum_source_analyses=minimumSources, ...
    require_distinct_extractor_per_run=true, ...
    require_identical_matching_specification_version=true, ...
    component_rule=requiredText(composition, "component_rule"), ...
    clique_completeness=requiredText(composition, "clique_completeness"), ...
    singleton_inclusion=true, ...
    ambiguity_propagation=requiredText(composition, "ambiguity_propagation"), ...
    feature_support_is_admission_criterion=false);
end

function assertNoThresholdDeclared(document, profilePath)
%ASSERTNOTHRESHOLDDECLARED Refuse a second threshold authority anywhere in the file.
%
% Checked by field name across the whole document rather than at the two places
% a threshold would most plausibly be added, because the invariant is that this
% policy owns no numeric evidence bound at all.
forbidden = ["min_temporal_iou", "max_temporal_iou", "temporal_iou_threshold", ...
    "min_overlap_s", "min_temporal_overlap_s", "relative_tolerance", ...
    "minimum_supporting_comparisons", "discrepancy_tolerance"];
found = forbiddenFields(document, forbidden);
if ~isempty(found)
    error("vawlume:agreement:SpecificationDeclaresThreshold", ...
        "Agreement policy %s declares threshold field(s) %s. Thresholds " + ...
        "belong to the versioned matching specification recorded by each " + ...
        "source analysis, not to this policy.", profilePath, ...
        strjoin("'" + unique(found(:))' + "'", ", "));
end
end

function found = forbiddenFields(value, forbidden)
found = strings(0, 1);
if isstruct(value)
    for element = value(:)'
        names = string(fieldnames(element));
        found = [found; intersect(names, forbidden)]; %#ok<AGROW>
        for name = names'
            found = [found; forbiddenFields(element.(name), forbidden)]; %#ok<AGROW>
        end
    end
    return
end
if iscell(value)
    for index = 1:numel(value)
        found = [found; forbiddenFields(value{index}, forbidden)]; %#ok<AGROW>
    end
end
end

function requiredStruct(container, field)
if ~isstruct(container) || ~isfield(container, field) || ...
        ~isstruct(container.(field)) || ~isscalar(container.(field))
    error("vawlume:agreement:SpecificationInvalid", ...
        "Agreement policy requires object '%s'.", field);
end
end

function value = requiredText(container, field)
if ~isfield(container, field)
    error("vawlume:agreement:SpecificationInvalid", ...
        "Agreement policy requires text field '%s'.", field);
end
try
    value = string(container.(field));
catch
    value = "";
end
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:agreement:SpecificationInvalid", ...
        "Agreement policy field '%s' must be nonempty scalar text.", field);
end
value = strtrim(value);
end

function requiredTrue(container, field)
if ~isfield(container, field) || ~islogical(container.(field)) || ...
        ~isscalar(container.(field)) || ~container.(field)
    error("vawlume:agreement:SpecificationInvalid", ...
        "Agreement policy field '%s' must be true.", field);
end
end

function requiredFalse(container, field)
if ~isfield(container, field) || ~islogical(container.(field)) || ...
        ~isscalar(container.(field)) || container.(field)
    error("vawlume:agreement:SpecificationInvalid", ...
        "Agreement policy field '%s' must be false.", field);
end
end

function value = requiredPositiveInteger(container, field)
if ~isfield(container, field) || ~isnumeric(container.(field)) || ...
        ~isscalar(container.(field)) || ~isfinite(container.(field)) || ...
        container.(field) < 1 || container.(field) ~= floor(container.(field))
    error("vawlume:agreement:SpecificationInvalid", ...
        "Agreement policy field '%s' must be a positive integer.", field);
end
value = double(container.(field));
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
