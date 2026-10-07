function policy = acousticLoadNormalizationPolicy(policyPath, repoRoot)
%ACOUSTICLOADNORMALIZATIONPOLICY Read and validate a call-level normalization policy.
%
% The policy is an input, not a constant. Every rule the normalization applies
% is read from it, and a policy that leaves one undeclared is refused rather
% than completed by a code default: a default here would be a second,
% unversioned copy of the policy.

if strlength(policyPath) == 0
    policyPath = fullfile(repoRoot, "config", "09_acoustic_normalization_policies", ...
        "band_matched_noise_reference_v1.json");
elseif ~java.io.File(char(policyPath)).isAbsolute()
    policyPath = fullfile(repoRoot, policyPath);
end
policyPath = canonicalPath(policyPath);
if ~isfile(policyPath)
    error("vawlume:acoustic:NormalizationPolicyNotFound", ...
        "Normalization policy does not exist: %s", policyPath);
end
try
    document = jsondecode(fileread(policyPath));
catch exception
    invalid("could not decode %s: %s", policyPath, exception.message);
end

for block = ["profile", "method", "operation", "pairs", "response_qc_status_handling", ...
        "source_measurement_handling", "extractor_reported_power", ...
        "calibration_status", "comparability", "what_this_is_not"]
    if ~isfield(document, block)
        invalid("required block '%s' is missing", block);
    end
end

profile = document.profile;
policy = struct();
policy.path = policyPath;
policy.profile_key = requiredText(profile, "id");
policy.profile_name = requiredText(profile, "name");
policy.profile_kind = requiredText(profile, "kind");
policy.profile_schema_version = requiredText(profile, "profile_schema_version");
policy.version_label = requiredText(profile, "profile_version");
policy.description = requiredText(profile, "description");
policy.checksum_sha256 = acousticSha256OfFile(policyPath);
policy.content_uri = portableUri(policyPath, repoRoot);
if policy.profile_kind ~= "analysis_settings"
    invalid("profile kind must be analysis_settings (contract 06 D6), not %s", ...
        policy.profile_kind);
end

policy.method_key = requiredText(document.method, "key");
policy.method_version = requiredText(document.method, "version");
if policy.method_key ~= "vawlume.acoustic.call_level_normalization" || ...
        policy.method_version ~= "1.0.0"
    invalid("method %s %s is not implemented; this function implements " + ...
        "vawlume.acoustic.call_level_normalization 1.0.0", ...
        policy.method_key, policy.method_version);
end
policy.formula = requiredText(document.operation, "formula");
if policy.formula ~= "normalized = measured / response"
    invalid("operation formula '%s' is not the implemented division", policy.formula);
end

policy.pairs = readPairs(document.pairs);
policy.qc_handling = readQcHandling(document.response_qc_status_handling);

if requiredText(document.extractor_reported_power, "state") ~= "not_used"
    invalid("extractor_reported_power.state must be not_used in v1 (contract 06 D6)");
end
policy.calibration_state = requiredText(document.calibration_status, "state");
if policy.calibration_state ~= "uncalibrated"
    invalid("calibration_status.state must be uncalibrated; nothing in this " + ...
        "prototype could justify '%s'", policy.calibration_state);
end
policy.comparability_scope = requiredText(document.comparability, "scope");
if policy.comparability_scope ~= "within_recording"
    invalid("comparability.scope must be within_recording (contract 06 D8)");
end
notList = string(document.what_this_is_not);
if isempty(notList) || any(strlength(notList) == 0)
    invalid("what_this_is_not must list what the normalized value is not");
end
end

function pairs = readPairs(raw)
if ~isstruct(raw) || isempty(raw)
    invalid("pairs must be a nonempty list");
end
pairs = repmat(struct(call_metric="", response_metric="", normalized_metric="", ...
    reference_type="", band_match=""), 1, numel(raw));
for index = 1:numel(raw)
    item = raw(index);
    for field = ["call_metric", "response_metric", "normalized_metric", ...
            "reference_type", "band_match"]
        pairs(index).(field) = requiredText(item, field);
    end
    if pairs(index).band_match ~= "identical"
        invalid("pair %d: band_match must be identical", index);
    end
end
if numel(unique([pairs.call_metric])) ~= numel(pairs)
    invalid("each call metric may be named by at most one pair");
end
end

function handling = readQcHandling(raw)
% Every status in doc 28's closed vocabulary must be declared. A status missing
% from the policy would otherwise be handled by whatever this code did by
% default, which is exactly what the policy exists to prevent.
statuses = ["ok", "divergent", "source_qc_warning", "insufficient_evidence", ...
    "not_comparable"];
handling = struct();
for status = statuses
    if ~isfield(raw, status)
        invalid("response_qc_status_handling does not declare '%s'", status);
    end
    item = raw.(status);
    action = requiredText(item, "action");
    entry = struct(action=action, flag="", reason_code="");
    switch action
        case "use"
        case "use_with_flag"
            entry.flag = requiredText(item, "flag");
        case "exclude_channel"
            entry.reason_code = requiredText(item, "reason_code");
        case "refuse_run"
        otherwise
            invalid("'%s' action '%s' is not one of use, use_with_flag, " + ...
                "exclude_channel, refuse_run", status, action);
    end
    handling.(status) = entry;
end
end

function value = requiredText(container, field)
field = char(field);
if ~isstruct(container) || ~isfield(container, field)
    invalid("required field '%s' is missing", field);
end
value = string(container.(field));
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    invalid("field '%s' must be nonempty text", field);
end
end

function invalid(varargin)
error("vawlume:acoustic:NormalizationPolicyInvalid", ...
    "Normalization policy: " + varargin{1} + ".", varargin{2:end});
end

function value = portableUri(path, repoRoot)
path = replace(string(path), "\", "/");
root = strip(replace(string(repoRoot), "\", "/"), "right", "/");
prefix = root + "/";
if startsWith(lower(path), lower(prefix))
    value = extractAfter(path, strlength(prefix));
else
    value = path;
end
end

function value = canonicalPath(path)
try
    value = string(java.io.File(char(path)).getCanonicalPath());
catch
    value = string(path);
end
end
