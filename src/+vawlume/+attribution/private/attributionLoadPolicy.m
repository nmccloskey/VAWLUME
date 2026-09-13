function policy = attributionLoadPolicy(profilePath, repoRoot)
%ATTRIBUTIONLOADPOLICY Read and validate a caller-attribution decision policy.
%
% The policy is an input, not a constant. Its identity, version, checksum and
% every threshold it applied are recoverable from the stored decision, so a
% decision read back years later is interpretable without this code.

if strlength(profilePath) == 0
    profilePath = fullfile(repoRoot, "config", "08_attribution_policies", ...
        "prototype_attribution_decision_policy.json");
elseif ~java.io.File(char(profilePath)).isAbsolute()
    profilePath = fullfile(repoRoot, profilePath);
end
profilePath = canonicalPath(profilePath);
if ~isfile(profilePath)
    error("vawlume:attribution:PolicyNotFound", ...
        "Attribution decision policy does not exist: %s", profilePath);
end
try
    document = jsondecode(fileread(profilePath));
catch exception
    error("vawlume:attribution:PolicyInvalid", ...
        "Could not decode attribution decision policy %s: %s", ...
        profilePath, exception.message);
end

requiredStruct(document, "profile");
requiredStruct(document, "calibration_status");
requiredStruct(document, "decision_rule");
requiredStruct(document, "thresholds");

profile = document.profile;
rule = document.decision_rule;
thresholds = document.thresholds;

policy = struct();
policy.profile_path = profilePath;
policy.profile_key = requiredText(profile, "id");
policy.profile_name = requiredText(profile, "name");
policy.profile_kind = requiredText(profile, "kind");
policy.profile_schema_version = requiredText(profile, "profile_schema_version");
policy.version_label = requiredText(profile, "profile_version");
policy.checksum_sha256 = attributionSha256OfFile(profilePath);

if policy.profile_kind ~= "attribution_policy"
    error("vawlume:attribution:PolicyInvalid", ...
        "Policy profile kind must be attribution_policy, not %s.", policy.profile_kind);
end

% A shipped threshold that did not say it was illustrative would be the one
% thing this prototype must never publish.
policy.calibration_state = requiredText(document.calibration_status, "state");
policy.calibration_meaning = requiredText(document.calibration_status, "meaning");
if policy.calibration_state == "calibrated"
    error("vawlume:attribution:PolicyNotIllustrative", ...
        "No calibrated attribution policy ships with this prototype. " + ...
        "A policy claiming calibration must name the evidence that calibrated it.");
end

policy.rule_key = requiredText(rule, "key");
policy.rule_version = requiredText(rule, "version");
policy.reads = requiredText(rule, "reads");
if ~ismember(policy.reads, ["score", "probability"])
    error("vawlume:attribution:PolicyInvalid", ...
        "decision_rule.reads must be score or probability, not %s.", policy.reads);
end
policy.ordering = requiredText(rule, "ordering");
if policy.ordering ~= "higher_is_stronger"
    error("vawlume:attribution:PolicyInvalid", ...
        "Only higher_is_stronger ordering is implemented; policy declares %s.", ...
        policy.ordering);
end
policy.requires_value_semantics = requiredLogical(rule, "requires_value_semantics");

policy.selection_threshold = requiredNumber(thresholds, "selection_threshold");
policy.separation_margin = requiredNumber(thresholds, "separation_margin");
policy.co_occurrence_threshold = requiredNumber(thresholds, "co_occurrence_threshold");

if policy.separation_margin < 0
    error("vawlume:attribution:PolicyInvalid", ...
        "separation_margin must be non-negative.");
end
% A co-occurrence bar below the selection bar would let this policy claim two
% animals called on evidence too weak to assign one of them.
if policy.co_occurrence_threshold < policy.selection_threshold
    error("vawlume:attribution:PolicyInvalid", ...
        "co_occurrence_threshold (%g) must not be below selection_threshold (%g).", ...
        policy.co_occurrence_threshold, policy.selection_threshold);
end

policy.exclude_when_no_readable_value = false;
policy.no_readable_value_reason = "";
if isfield(document, "exclusion_rules") && isstruct(document.exclusion_rules) && ...
        isfield(document.exclusion_rules, "no_readable_value")
    branch = document.exclusion_rules.no_readable_value;
    policy.exclude_when_no_readable_value = requiredLogical(branch, "enabled");
    if policy.exclude_when_no_readable_value
        policy.no_readable_value_reason = requiredText(branch, "reason");
    end
end

policy.permits_caller_exclusions = true;
if isfield(document, "caller_declared_exclusions") && ...
        isstruct(document.caller_declared_exclusions)
    policy.permits_caller_exclusions = requiredLogical( ...
        document.caller_declared_exclusions, "permitted");
end
end

% ---------------------------------------------------------------- helpers ---

function requiredStruct(document, field)
if ~isfield(document, field) || ~isstruct(document.(field))
    error("vawlume:attribution:PolicyInvalid", ...
        "Attribution policy requires a %s object.", field);
end
end

function value = requiredText(document, field)
if ~isfield(document, field) || ~(ischar(document.(field)) || isstring(document.(field)))
    error("vawlume:attribution:PolicyInvalid", ...
        "Attribution policy requires text field %s.", field);
end
value = strtrim(string(document.(field)));
if strlength(value) == 0
    error("vawlume:attribution:PolicyInvalid", ...
        "Attribution policy field %s must not be empty.", field);
end
end

function value = requiredNumber(document, field)
if ~isfield(document, field) || ~isnumeric(document.(field)) || ...
        ~isscalar(document.(field)) || ~isfinite(document.(field))
    error("vawlume:attribution:PolicyInvalid", ...
        "Attribution policy requires finite numeric field %s.", field);
end
value = double(document.(field));
end

function value = requiredLogical(document, field)
if ~isfield(document, field) || ~(islogical(document.(field)) || isnumeric(document.(field))) ...
        || ~isscalar(document.(field))
    error("vawlume:attribution:PolicyInvalid", ...
        "Attribution policy requires boolean field %s.", field);
end
value = logical(document.(field));
end

function value = canonicalPath(path)
resolved = java.io.File(char(path)).getCanonicalPath();
value = string(resolved);
end
