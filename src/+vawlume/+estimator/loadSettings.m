function settings = loadSettings(profilePath, options)
%LOADSETTINGS Read and validate a native-estimator settings profile.
%
%   settings = VAWLUME.ESTIMATOR.LOADSETTINGS()
%   settings = VAWLUME.ESTIMATOR.LOADSETTINGS(profilePath, RepoRoot=root)
%
% With no path, reads the shipped profile,
% config/10_estimator_settings/native_level_difference_estimator_v1.json.
%
% The profile is the method's licence to combine evidence dimensions (contract
% 06 D2). It must state the five conditions, and this loader REFUSES, by name,
% a profile that omits any of them:
%
%   condition 1  dimensions          used / not_used and a role for each of
%                                    temporal_alignment, pose_localization,
%                                    visual_identity, acoustic; source_localization
%                                    not_used with its reason
%   condition 2  score               unit dB, higher_is_stronger, meaning, and a
%                                    what_this_is_not list headed "not a probability"
%   condition 3  scaling             how inputs are scaled; comparability_scope
%                                    within_recording, with its justification
%   condition 4  readability         the evidence rows each input becomes
%   condition 5  calibration_status  uncalibrated, evidence_basis,
%                                    calibration_requires
%
% plus the profile, method, scope and parameters blocks. EVERY METHOD PARAMETER
% MUST BE STATED; none has a default here, because a code default would be a
% second, unversioned copy of the method. A stated null is a statement; an
% absent field is refused.
%
% Errors (all vawlume:estimator:...): SettingsNotFound, SettingsBlockMissing,
% SettingsDimensionUndeclared, SettingsParameterMissing,
% SettingsGateNotImplemented, SettingsInvalid.
%
% The result carries declared_inputs: the four (input_dimension, declaration,
% notes) rows that vawlume.attribution.createRun stores for a native run, built
% from this same profile so the declaration and the profile version that
% declares it cannot disagree (contract 06 D16).
%
% Read with fileread and jsondecode, as every non-source-mapping settings
% profile is (config/README.md); registered by vawlume.db.registerProfileVersion
% with profile_kind attribution_estimator_settings. This function reads the file
% and nothing else: no database.

arguments
    profilePath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
repoRoot = canonicalPath(repoRoot);
if strlength(profilePath) == 0
    profilePath = fullfile(repoRoot, "config", "10_estimator_settings", ...
        "native_level_difference_estimator_v1.json");
elseif ~java.io.File(char(profilePath)).isAbsolute()
    profilePath = fullfile(repoRoot, profilePath);
end
profilePath = canonicalPath(profilePath);
if ~isfile(profilePath)
    error("vawlume:estimator:SettingsNotFound", ...
        "Estimator settings profile does not exist: %s", profilePath);
end
try
    document = jsondecode(fileread(profilePath));
catch exception
    invalid("could not decode %s: %s", profilePath, exception.message);
end

for block = ["profile", "method", "scope", "dimensions", "score", "scaling", ...
        "readability", "calibration_status", "parameters"]
    if ~isstruct(document) || ~isfield(document, block)
        error("vawlume:estimator:SettingsBlockMissing", ...
            "Estimator settings profile has no '%s' block. Every block is required.", block);
    end
end

settings = struct();
settings.path = profilePath;
settings.content_uri = portableUri(profilePath, repoRoot);
settings.checksum_sha256 = estimatorSha256OfFile(profilePath);
settings.profile_key = requiredText(document.profile, "id", "profile");
settings.profile_name = requiredText(document.profile, "name", "profile");
settings.profile_kind = requiredText(document.profile, "kind", "profile");
settings.profile_schema_version = requiredText(document.profile, "profile_schema_version", "profile");
settings.version_label = requiredText(document.profile, "profile_version", "profile");
settings.description = requiredText(document.profile, "description", "profile");
if settings.profile_kind ~= "attribution_estimator_settings"
    invalid("profile.kind must be attribution_estimator_settings, not %s", ...
        settings.profile_kind);
end

settings.method_key = requiredText(document.method, "key", "method");
settings.method_version = requiredText(document.method, "version", "method");
if settings.method_key ~= "vawlume.estimator.level_difference_consistency" || ...
        settings.method_version ~= "1.0.0"
    invalid("method %s %s is not implemented; this version implements " + ...
        "vawlume.estimator.level_difference_consistency 1.0.0", ...
        settings.method_key, settings.method_version);
end

settings.scope = readScope(document.scope);
[settings.dimensions, settings.declared_inputs] = readDimensions(document.dimensions);
settings.score = readScore(document.score);
settings.scaling = readScaling(document.scaling);
settings.readability = readReadability(document.readability);
settings.calibration_status = readCalibration(document.calibration_status);
settings.parameters = readParameters(document.parameters);
end

% ----------------------------------------------------------------- blocks ---

function scope = readScope(raw)
scope = struct(candidate_count=number(raw, "candidate_count", "scope"), ...
    channel_count=number(raw, "channel_count", "scope"), ...
    target_event_sets=textList(raw, "target_event_sets", "scope"));
if scope.candidate_count ~= 2 || scope.channel_count ~= 2
    invalid("scope must be candidate_count 2 and channel_count 2; v1 implements " + ...
        "no other count (contract 06 D7)");
end
end

function [dimensions, declared] = readDimensions(raw)
upstream = ["temporal_alignment", "pose_localization", "visual_identity", "acoustic"];
dimensions = struct();
notes = strings(numel(upstream), 1);
declarations = strings(numel(upstream), 1);
for index = 1:numel(upstream)
    name = upstream(index);
    if ~isfield(raw, name)
        error("vawlume:estimator:SettingsDimensionUndeclared", ...
            "dimensions.%s is not declared. A native run may leave no dimension " + ...
            "undeclared (condition 1).", name);
    end
    declaration = requiredText(raw.(name), "declaration", "dimensions." + name);
    if ~ismember(declaration, ["used", "not_used"])
        invalid("dimensions.%s.declaration must be used or not_used", name);
    end
    role = requiredText(raw.(name), "role", "dimensions." + name);
    dimensions.(name) = struct(declaration=declaration, role=role);
    declarations(index) = declaration;
    notes(index) = role;
end
if ~isfield(raw, "source_localization")
    error("vawlume:estimator:SettingsDimensionUndeclared", ...
        "dimensions.source_localization is not declared; it must be not_used, " + ...
        "with its reason.");
end
if requiredText(raw.source_localization, "declaration", "dimensions.source_localization") ~= "not_used"
    invalid("dimensions.source_localization must be not_used: the native path " + ...
        "consumes no backend output (contract 06 invariant 25)");
end
dimensions.source_localization = struct(declaration="not_used", ...
    reason=requiredText(raw.source_localization, "reason", "dimensions.source_localization"));
declared = table(upstream(:), declarations, notes, ...
    VariableNames=["input_dimension", "declaration", "notes"]);
end

function score = readScore(raw)
score = struct(unit=requiredText(raw, "unit", "score"), ...
    orientation=requiredText(raw, "orientation", "score"), ...
    meaning=requiredText(raw, "meaning", "score"), ...
    what_this_is_not=textList(raw, "what_this_is_not", "score"));
if score.unit ~= "dB" || score.orientation ~= "higher_is_stronger"
    invalid("score must be unit dB and orientation higher_is_stronger (contract 06 D7)");
end
if score.what_this_is_not(1) ~= "not a probability"
    invalid("score.what_this_is_not must begin with ""not a probability""");
end
end

function scaling = readScaling(raw)
scaling = struct(acoustic=requiredText(raw, "acoustic", "scaling"), ...
    pose_localization=requiredText(raw, "pose_localization", "scaling"), ...
    comparability_scope=requiredText(raw, "comparability_scope", "scaling"), ...
    comparability_justification=requiredText(raw, "comparability_justification", "scaling"));
if scaling.comparability_scope ~= "within_recording"
    invalid("scaling.comparability_scope must be within_recording (contract 06 D8)");
end
end

function readability = readReadability(raw)
% The rows contract 06 D10 names, so the profile itself says how a score is
% reconstructed.
readability = struct();
for name = ["temporal_alignment", "acoustic_per_channel", "acoustic_difference", ...
        "visual_identity", "pose_localization_distance", ...
        "pose_localization_confidence", "reconstruction"]
    readability.(name) = requiredText(raw, name, "readability");
end
end

function calibration = readCalibration(raw)
calibration = struct(state=requiredText(raw, "state", "calibration_status"), ...
    evidence_basis=requiredText(raw, "evidence_basis", "calibration_status"), ...
    calibration_requires=requiredText(raw, "calibration_requires", "calibration_status"));
if calibration.state ~= "uncalibrated"
    invalid("calibration_status.state must be uncalibrated; nothing in this " + ...
        "prototype could justify '%s'", calibration.state);
end
end

function parameters = readParameters(raw)
required = ["spreading_assumption", "primary_instant_basis", "bodypart", ...
    "channel_pair", "max_interpolation_gap_s", "accepted_frame_units", ...
    "min_distance", "refuse_extrapolated_alignment", "refuse_clipped_channels", ...
    "pose_confidence_gate", "temporal_uncertainty_gate_s", "normalization_policy"];
for name = required
    if ~isfield(raw, name)
        error("vawlume:estimator:SettingsParameterMissing", ...
            "parameters.%s is not stated. No method parameter has a default.", name);
    end
end
parameters = struct();
parameters.spreading_assumption = requiredText(raw, "spreading_assumption", "parameters");
if parameters.spreading_assumption ~= "spherical"
    invalid("parameters.spreading_assumption '%s' is not implemented; v1 implements spherical", ...
        parameters.spreading_assumption);
end
parameters.primary_instant_basis = requiredText(raw, "primary_instant_basis", "parameters");
if ~ismember(parameters.primary_instant_basis, ...
        ["onset", "midpoint", "offset", "window_median", "window_min"])
    invalid("parameters.primary_instant_basis '%s' is not an instant basis", ...
        parameters.primary_instant_basis);
end
parameters.bodypart = requiredText(raw, "bodypart", "parameters");
pair = double(raw.channel_pair(:)');
if numel(pair) ~= 2 || any(~isfinite(pair)) || any(pair < 1) || ...
        any(pair ~= floor(pair)) || pair(1) == pair(2)
    invalid("parameters.channel_pair must be two distinct positive channel indices");
end
parameters.channel_pair = pair;
parameters.max_interpolation_gap_s = positive(raw, "max_interpolation_gap_s");
parameters.accepted_frame_units = textList(raw, "accepted_frame_units", "parameters");
parameters.min_distance = positive(raw, "min_distance");
parameters.refuse_extrapolated_alignment = flag(raw, "refuse_extrapolated_alignment");
parameters.refuse_clipped_channels = flag(raw, "refuse_clipped_channels");
% Contract 06 D4 and D5: pose confidence and the alignment bound are recorded,
% not gated on. The parameters exist so the profile says so; a value would be a
% gate this version does not implement.
for name = ["pose_confidence_gate", "temporal_uncertainty_gate_s"]
    if ~isempty(raw.(name))
        error("vawlume:estimator:SettingsGateNotImplemented", ...
            "parameters.%s must be null in v1: the dimension is recorded as " + ...
            "evidence and not used to gate (contract 06 D4, D5).", name);
    end
    parameters.(name) = [];
end
policy = raw.normalization_policy;
parameters.normalization_policy = struct( ...
    profile_key=requiredText(policy, "profile_key", "parameters.normalization_policy"), ...
    version=requiredText(policy, "version", "parameters.normalization_policy"), ...
    path=requiredText(policy, "path", "parameters.normalization_policy"));
end

% ---------------------------------------------------------------- helpers ---

function value = requiredText(container, field, where)
field = char(field);
if ~isstruct(container) || ~isfield(container, field)
    invalid("%s.%s is required", where, field);
end
value = string(container.(field));
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    invalid("%s.%s must be nonempty text", where, field);
end
end

function values = textList(container, field, where)
field = char(field);
if ~isstruct(container) || ~isfield(container, field) || isempty(container.(field))
    invalid("%s.%s must be a nonempty list", where, field);
end
values = string(container.(field));
values = values(:)';
if any(ismissing(values) | strlength(values) == 0)
    invalid("%s.%s must contain nonempty text", where, field);
end
end

function value = number(container, field, where)
field = char(field);
if ~isfield(container, field) || ~isnumeric(container.(field)) || ...
        ~isscalar(container.(field)) || ~isfinite(container.(field))
    invalid("%s.%s must be a finite number", where, field);
end
value = double(container.(field));
end

function value = positive(container, field)
value = number(container, field, "parameters");
if value <= 0
    invalid("parameters.%s must be positive", field);
end
end

function value = flag(container, field)
value = container.(field);
if ~islogical(value) || ~isscalar(value)
    invalid("parameters.%s must be true or false", field);
end
end

function invalid(varargin)
error("vawlume:estimator:SettingsInvalid", ...
    "Estimator settings profile: " + varargin{1} + ".", varargin{2:end});
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
