function specification = consilienceLoadSpec(conn, analysis, repoRoot)
%CONSILIENCELOADSPEC Read the exact specification the matching analysis used.
%
% The specification is not supplied by the caller. It is resolved from the
% config_profile_versions row the matching analysis linked, and its file is
% re-checksummed and compared against the stored value. An agreement summary
% therefore cannot silently be computed under a specification different from the
% one that produced the groups it summarizes.

repoRoot = resolveRepoRoot(repoRoot);
rows = fetch(conn, "SELECT cpv.profile_version_id, cp.profile_key, " + ...
    "cp.profile_kind, cpv.version_label, cpv.content_uri, " + ...
    "IFNULL(cpv.checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM analysis_run_profiles arp " + ...
    "JOIN config_profile_versions cpv ON cpv.profile_version_id=arp.profile_version_id " + ...
    "JOIN config_profiles cp ON cp.profile_id=cpv.profile_id " + ...
    "WHERE arp.analysis_run_id=" + string(analysis.analysis_run_id) + ...
    " AND arp.assignment_role='matching_spec'");
if isempty(rows) || height(rows) == 0
    error("vawlume:consilience:SpecificationNotLinked", ...
        "Matching analysis '%s' has no linked matching_spec profile version.", ...
        analysis.run_key);
end
if height(rows) ~= 1
    error("vawlume:consilience:SpecificationAmbiguous", ...
        "Matching analysis '%s' links %d matching_spec profile versions.", ...
        analysis.run_key, height(rows));
end

profileKey = presentText(rows.profile_key(1));
versionLabel = presentText(rows.version_label(1));
contentUri = presentText(rows.content_uri(1));
storedChecksum = presentText(rows.checksum_sha256(1));

sourcePath = contentUri;
if ~isAbsolutePath(sourcePath)
    sourcePath = fullfile(repoRoot, sourcePath);
end
if ~isfile(sourcePath)
    error("vawlume:consilience:SpecificationNotFound", ...
        "The specification registered for '%s' is not readable at %s.", ...
        analysis.run_key, sourcePath);
end
checksum = consilienceSha256OfFile(sourcePath);
if strlength(storedChecksum) > 0 && checksum ~= storedChecksum
    error("vawlume:consilience:SpecificationChanged", ...
        ['The specification file at %s has checksum %s but matching analysis ' ...
        '''%s'' was produced under checksum %s. Agreement must be computed ' ...
        'under the specification that produced the groups.'], ...
        sourcePath, extractBefore(checksum, 13), analysis.run_key, ...
        extractBefore(storedChecksum, 13));
end

try
    document = jsondecode(fileread(sourcePath));
catch exception
    error("vawlume:consilience:SpecificationInvalid", ...
        "Could not decode matching specification %s: %s", ...
        sourcePath, exception.message);
end

requiredStruct(document, "detection_agreement");
requiredStruct(document, "feature_agreement");
requiredStruct(document, "feature_support");
detection = document.detection_agreement;
feature = document.feature_agreement;
support = document.feature_support;

denominator = requiredText(detection, "denominator");
if requiredText(feature, "scope") ~= "eligible feature pairs on one_to_one groups only"
    error("vawlume:consilience:SpecificationInvalid", ...
        "feature_agreement.scope must restrict comparison to one_to_one groups.");
end
requiredTrue(support, "require_consilience_eligible");
requiredTrue(support, "forbid_canonical_name_only_join");
if requiredText(support, "comparison_unit") ~= "canonical_unit"
    error("vawlume:consilience:SpecificationInvalid", ...
        "feature_support.comparison_unit must be 'canonical_unit'.");
end
restrict = string(support.restrict_to_match_type(:));
if ~isequal(restrict, "one_to_one")
    error("vawlume:consilience:SpecificationInvalid", ...
        "feature_support.restrict_to_match_type must be exactly one_to_one.");
end

requiredStruct(feature, "icc");
if ~isfield(feature.icc, "enabled") || ~islogical(feature.icc.enabled) || ...
        ~isscalar(feature.icc.enabled)
    error("vawlume:consilience:SpecificationInvalid", ...
        "feature_agreement.icc.enabled must be a logical scalar.");
end
if feature.icc.enabled
    error("vawlume:consilience:IccNotImplemented", ...
        ['The specification enables ICC, which this prototype deliberately ' ...
        'does not implement. Choosing an ICC form, establishing that the ' ...
        'matched events are independent, and validating an implementation ' ...
        'require real paired data. Disable it or extend the implementation ' ...
        'deliberately rather than reporting an uninterpreted coefficient.']);
end

specification = struct( ...
    profile_version_id=double(rows.profile_version_id(1)), ...
    profile_key=profileKey, ...
    profile_kind=presentText(rows.profile_kind(1)), ...
    version_label=versionLabel, ...
    content_uri=contentUri, ...
    source_path=string(sourcePath), ...
    checksum_sha256=checksum, ...
    document=document, ...
    denominator=denominator, ...
    primary_temporal_classes=textList(support, ...
        "timing_classes_reserved_as_primary_evidence"), ...
    supporting_classes=textList(support, "supporting_equivalence_classes"), ...
    tolerances=toleranceMap(support), ...
    secondary_minimum_n=numericField(feature, "secondary_minimum_n", 10), ...
    icc_enabled=false, ...
    icc_reason=optionalText(feature.icc, "reason"));
end

function value = toleranceMap(support)
value = table(strings(0, 1), zeros(0, 1), ...
    VariableNames=["equivalence_class", "relative_tolerance"]);
if ~isfield(support, "discrepancy_tolerance")
    return
end
items = support.discrepancy_tolerance;
if isstruct(items)
    items = num2cell(items);
end
for index = 1:numel(items)
    item = items{index};
    if ~isstruct(item) || ~isfield(item, "equivalence_class") || ...
            ~isfield(item, "relative_tolerance")
        continue
    end
    value(end + 1, :) = {string(item.equivalence_class), ...
        double(item.relative_tolerance)}; %#ok<AGROW>
end
end

function value = textList(container, field)
value = strings(0, 1);
if ~isfield(container, field)
    return
end
value = string(container.(field));
value = value(:);
end

function value = numericField(container, field, fallback)
value = fallback;
if ~isfield(container, field)
    return
end
candidate = container.(field);
if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
    value = double(candidate);
end
end

function root = resolveRepoRoot(root)
if strlength(root) > 0
    return
end
root = string(fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath")))))));
end

function value = isAbsolutePath(path)
try
    value = java.io.File(char(path)).isAbsolute();
catch
    value = false;
end
end

function requiredStruct(container, field)
if ~isstruct(container) || ~isfield(container, field) || ...
        ~isstruct(container.(field)) || ~isscalar(container.(field))
    error("vawlume:consilience:SpecificationInvalid", ...
        "Matching specification requires object '%s'.", field);
end
end

function value = requiredText(container, field)
if ~isfield(container, field)
    error("vawlume:consilience:SpecificationInvalid", ...
        "Matching specification requires text field '%s'.", field);
end
try
    value = string(container.(field));
catch
    value = "";
end
if ~isscalar(value) || ismissing(value) || strlength(strtrim(value)) == 0
    error("vawlume:consilience:SpecificationInvalid", ...
        "Matching specification field '%s' must be nonempty scalar text.", field);
end
value = strtrim(value);
end

function requiredTrue(container, field)
if ~isfield(container, field) || ~islogical(container.(field)) || ...
        ~isscalar(container.(field)) || ~container.(field)
    error("vawlume:consilience:SpecificationInvalid", ...
        "Matching specification field '%s' must be true.", field);
end
end

function value = optionalText(container, field)
value = "";
if ~isfield(container, field)
    return
end
try
    candidate = string(container.(field));
catch
    return
end
if isscalar(candidate) && ~ismissing(candidate)
    value = strtrim(candidate);
end
end

function value = presentText(value)
value = string(value);
value(ismissing(value)) = "";
end
