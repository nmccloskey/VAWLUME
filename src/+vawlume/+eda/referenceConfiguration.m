function reference = referenceConfiguration(options)
%REFERENCECONFIGURATION Identify the configuration characterization is computed at.
%
% REFERENCE = vawlume.eda.REFERENCECONFIGURATION() resolves contract §J's
% reference configuration - the tracked default matching specification - and
% returns its identity and its calibration status, which every Part 11, 12 and 13
% output must carry.
%
% Name-value options:
%   SpecPath    an explicit specification to use instead of the tracked default
%   RepoRoot    repository root, used to find the default
%
% NEVER CHOSEN FROM THE SCREEN'S RESULTS. This function takes a path or the
% tracked default and nothing else: there is deliberately no way to pass it a
% probe result, a design, or a leverage table. Selecting the configuration that
% maximizes three-way support and then describing three-way support would be
% circular, and the way to make that impossible is to give the resolver no access
% to the quantity it would have to optimize.
%
% THE IDENTITY TRAVELS BECAUSE THE FIGURE WILL NOT. A support-pattern plot
% separated from its run has to be able to say what it was computed at, so the
% profile key, version label and file checksum are returned here and copied into
% every summary downstream rather than being looked up again where they are
% needed.
%
% USING A FILE AS THE REFERENCE DOES NOT MAKE IT CALIBRATED. The tracked
% specification declares `calibration_status.state` as `illustrative_prototype`
% and says in its own words that every numeric threshold is a demonstration
% value. That block is carried verbatim, not summarized and not softened: a
% reader who sees "reference configuration" and no status will assume the
% thresholds mean something. Running a sensitivity probe around it does not make
% it calibrated either.
%
% This function reads one file. It opens no database connection and writes
% nothing.

arguments
    options.SpecPath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
end

path = resolvePath(options);
if ~isfile(path)
    error("vawlume:eda:ReferenceConfigurationNotFound", ...
        "The reference configuration '%s' does not exist. Contract §J names " + ...
        "the tracked default; pass SpecPath to use another deliberately.", ...
        path);
end

document = readDocument(path);
profile = profileIdentity(document, path);
calibration = calibrationStatus(document);

reference = struct( ...
    status="resolved", ...
    source=sourceOf(options), ...
    specification_path=string(path), ...
    profile_key=profile.key, ...
    profile_name=profile.name, ...
    profile_kind=profile.kind, ...
    version_label=profile.version, ...
    profile_schema_version=profile.schema_version, ...
    checksum_sha256=edaSha256OfFile(path), ...
    calibration_status=calibration, ...
    identity_line=identityLine(profile, calibration), ...
    selection_rule="the tracked default, or a path the caller supplied; " + ...
        "never chosen from the screen's results, because selecting the " + ...
        "configuration that maximizes an outcome and then describing that " + ...
        "outcome would be circular", ...
    calibration_note="This configuration is a REFERENCE, not a calibrated " + ...
        "setting. Its own calibration_status declares state '" + ...
        calibration.state + "'. Using it to anchor characterization does " + ...
        "not calibrate it, and running a sensitivity probe around it does " + ...
        "not either. No threshold reported here is optimal or recommended.", ...
    caution=edaCautionNote());
end

% ---------------------------------------------------------------- resolve ---

function path = resolvePath(options)
if strlength(options.SpecPath) > 0
    path = options.SpecPath;
    return
end
root = options.RepoRoot;
if strlength(root) == 0
    % src/+vawlume/+eda/referenceConfiguration.m -> four levels to the root,
    % the same walk materializeConfigurations uses for the same default.
    root = string(fileparts(fileparts(fileparts(fileparts( ...
        mfilename("fullpath"))))));
end
path = fullfile(root, "config", "05_matching_profiles", ...
    "prototype_matching_consilience_spec.json");
end

function value = sourceOf(options)
if strlength(options.SpecPath) > 0
    value = "caller_supplied";
    return
end
value = "tracked_default";
end

function document = readDocument(path)
try
    document = jsondecode(fileread(path));
catch exception
    error("vawlume:eda:ReferenceConfigurationInvalid", ...
        "The reference configuration '%s' is not readable JSON: %s", ...
        path, exception.message);
end
if ~isstruct(document)
    error("vawlume:eda:ReferenceConfigurationInvalid", ...
        "The reference configuration '%s' does not decode to an object.", path);
end
end

% --------------------------------------------------------------- identity ---

function value = profileIdentity(document, path)
%PROFILEIDENTITY The three fields analysis identity is built from.
%
% Required rather than defaulted. An analysis's identity includes its
% specification's profile key, version label and checksum, so a reference whose
% key or version is missing cannot be cited in an output that claims to say what
% it was computed at - and a blank in that line reads as "unknown" only if
% someone notices it.
if ~isfield(document, "profile") || ~isstruct(document.profile)
    error("vawlume:eda:ReferenceConfigurationInvalid", ...
        "The reference configuration '%s' declares no profile block.", path);
end
profile = document.profile;
value = struct( ...
    key=requiredText(profile, "id", path), ...
    version=requiredText(profile, "profile_version", path), ...
    name=optionalText(profile, "name"), ...
    kind=optionalText(profile, "kind"), ...
    schema_version=optionalText(profile, "profile_schema_version"));
end

function value = calibrationStatus(document)
%CALIBRATIONSTATUS Carried verbatim, never paraphrased.
%
% The specification's own words about its thresholds are more careful than any
% summary this function would write, and they are what a reader needs to see
% beside a number. A missing block is reported as unknown rather than as
% calibrated: the absence of a disclaimer is not a claim of calibration, and
% treating it as one is the failure this field exists to prevent.
if ~isfield(document, "calibration_status") || ...
        ~isstruct(document.calibration_status)
    value = struct( ...
        state="unknown", ...
        meaning="This specification declares no calibration_status block. " + ...
            "Absence of a statement is not evidence of calibration; treat " + ...
            "its thresholds as uncalibrated unless documented otherwise.", ...
        evidence_basis="", ...
        calibration_requires="", ...
        is_declared=false);
    return
end
block = document.calibration_status;
value = struct( ...
    state=optionalText(block, "state"), ...
    meaning=optionalText(block, "meaning"), ...
    evidence_basis=optionalText(block, "evidence_basis"), ...
    calibration_requires=optionalText(block, "calibration_requires"), ...
    is_declared=true);
if strlength(value.state) == 0
    value.state = "unknown";
end
end

function value = identityLine(profile, calibration)
%IDENTITYLINE One line a figure caption can carry unedited.
%
% The checksum is deliberately absent: this is the line a human reads, and a
% sixty-four character digest in it would be skipped. The full checksum travels
% in its own field for the machine.
value = profile.key + " " + profile.version + " (" + ...
    calibration.state + ")";
end

% -------------------------------------------------------------- plumbing ---

function value = requiredText(source, name, path)
value = optionalText(source, name);
if strlength(value) == 0
    error("vawlume:eda:ReferenceConfigurationInvalid", ...
        "The reference configuration '%s' declares no profile.%s, so it " + ...
        "cannot be cited as the configuration an output was computed at.", ...
        path, name);
end
end

function value = optionalText(source, name)
value = "";
if isfield(source, name)
    value = strtrim(string(source.(name)));
    if ismissing(value)
        value = "";
    end
end
end
