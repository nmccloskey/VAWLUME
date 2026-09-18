function result = materializeConfigurations(design, options)
%MATERIALIZECONFIGURATIONS Write one matching specification per design configuration.
%
% RESULT = vawlume.eda.MATERIALIZECONFIGURATIONS(DESIGN) derives one
% matching-specification JSON file from the base specification for every
% configuration in a vawlume.eda.screeningDesign, and returns an index a runner
% can execute from without guessing a path.
%
% Name-value options:
%   BaseSpecPath        the specification to derive from; defaults to the tracked
%                       reference configuration under RepoRoot
%   RepoRoot            repository root, used to find the default base
%   OutputRoot          runtime workspace root; defaults to a tempdir-based
%                       directory
%   ExplorationRunKey   identifies this exploration run; defaults to a value
%                       derived deterministically from the design
%   Overwrite           rewrite an existing file, default true
%
% ONLY THE ACTIVE FACTORS ARE OVERRIDDEN. Algorithm key and version, assignment
% model, consensus policy, feature eligibility and the manual-QC rule are copied
% unchanged. That is what makes a response attributable to the design rather than
% to an incidental difference, and it is the same discipline the sensitivity
% reporter enforces when it refuses to compare analyses that differ in more than
% the varied parameter.
%
% SERIALIZATION IS DETERMINISTIC AND BYTE-EXACT. The same configuration written
% twice produces identical bytes, because the specification checksum is the
% analysis identity: field reordering, floating-point formatting drift or an
% embedded timestamp would change the checksum and make an honest rerun look like
% a conflict. Files are written in binary mode so a platform's line-ending
% translation cannot alter them either.
%
% Generated files are RUNTIME ARTIFACTS. They are written under the output root,
% never into the tracked configuration directory: they are one exploration's
% working state, not repository configuration.
%
% WHAT THIS FUNCTION DOES NOT DO. It does not validate the base specification
% against the matching contract. That interpretation belongs to the matcher's own
% loader, which is private to its package, and duplicating it here would create
% the second configuration code path the boundaries forbid. This function checks
% only that the fields it is about to override exist and are shaped as expected,
% and refuses otherwise. The real validation happens when the matcher loads a
% generated file; an integration test exercises exactly that.
%
% No database connection is opened here.

arguments
    design (1,1) struct
    options.BaseSpecPath (1,1) string = ""
    options.RepoRoot (1,1) string = ""
    options.OutputRoot (1,1) string = ""
    options.ExplorationRunKey (1,1) string = ""
    options.Overwrite (1,1) logical = true
end

requireFields(design, ["configurations", "factors", "design_type"]);
basePath = resolveBasePath(options);
[document, baseIdentity] = readBase(basePath);
factors = design.factors;
configurations = design.configurations;

[runKey, runKeySource] = resolveRunKey(design, options);
outputRoot = resolveOutputRoot(options);
specDirectory = fullfile(outputRoot, "exploration", runKey, "specs");
if ~isfolder(specDirectory)
    mkdir(specDirectory);
end

rows = height(configurations);
specPath = strings(rows, 1);
checksum = strings(rows, 1);
profileVersion = strings(rows, 1);

for index = 1:rows
    configurationId = configurations.configuration_id(index);
    values = zeros(1, height(factors));
    for column = 1:height(factors)
        values(column) = configurations.(factors.factor_name(column))(index);
    end
    generated = applyConfiguration(document, factors.factor_name, values, ...
        baseIdentity.profile_version, configurationId);
    profileVersion(index) = string(generated.profile.profile_version);
    specPath(index) = fullfile(specDirectory, ...
        configurationId + "_matching_spec.json");
    writeSpecification(specPath(index), generated, options.Overwrite);
    verifyWritten(specPath(index), factors.factor_name, values, configurationId);
    checksum(index) = edaSha256OfFile(specPath(index));
end

assertDistinctChecksums(configurations.configuration_id, checksum);

index = configurations;
index.profile_version = profileVersion;
index.specification_path = specPath;
index.checksum_sha256 = checksum;

result = struct( ...
    status="materialized", ...
    exploration_run_key=runKey, ...
    exploration_run_key_source=runKeySource, ...
    output_root=string(outputRoot), ...
    specification_directory=string(specDirectory), ...
    configuration_count=rows, ...
    base_specification=baseIdentity, ...
    index=index, ...
    overridden_fields=factors.factor_name', ...
    preserved_fields_note="every field outside the overridden plausibility " + ...
        "bounds is copied from the base specification unchanged", ...
    serialization=struct( ...
        encoder="jsonencode with PrettyPrint", ...
        write_mode="binary, so line endings are not platform-translated", ...
        deterministic=true), ...
    run_key_template=runKeyTemplate(runKey), ...
    provenance=provenanceRecord(design, baseIdentity, runKey, specDirectory), ...
    caution=edaCautionNote());
end

% ----------------------------------------------------------------- inputs ---

function path = resolveBasePath(options)
if strlength(options.BaseSpecPath) > 0
    path = options.BaseSpecPath;
else
    root = options.RepoRoot;
    if strlength(root) == 0
        root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
    end
    path = fullfile(root, "config", "05_matching_profiles", ...
        "prototype_matching_consilience_spec.json");
end
if ~isfile(path)
    error("vawlume:eda:BaseSpecificationNotFound", ...
        "Base matching specification does not exist: %s", path);
end
end

function [document, identity] = readBase(path)
try
    document = jsondecode(fileread(path));
catch exception
    error("vawlume:eda:BaseSpecificationInvalid", ...
        "Could not decode base matching specification %s: %s", path, ...
        exception.message);
end
% A structural precondition check, not a validation of the matching contract.
% It asserts only that the fields about to be overridden exist and are shaped as
% expected, so a malformed base fails here with a clear message instead of
% producing files that fail deep inside a probe.
if ~isstruct(document) || ~isfield(document, "candidate_generation") || ...
        ~isstruct(document.candidate_generation) || ...
        ~isfield(document.candidate_generation, "plausibility_rule") || ...
        ~isstruct(document.candidate_generation.plausibility_rule)
    error("vawlume:eda:BaseSpecificationInvalid", ...
        "Base specification %s has no " + ...
        "candidate_generation.plausibility_rule object to override.", path);
end
if ~isfield(document, "profile") || ~isstruct(document.profile) || ...
        ~isfield(document.profile, "profile_version")
    error("vawlume:eda:BaseSpecificationInvalid", ...
        "Base specification %s declares no profile.profile_version to " + ...
        "extend with a configuration identifier.", path);
end
identity = struct( ...
    path=string(path), ...
    profile_key=textOf(document.profile, "id"), ...
    profile_version=string(document.profile.profile_version), ...
    checksum_sha256=edaSha256OfFile(path), ...
    calibration_state=calibrationState(document));
end

function value = calibrationState(document)
value = "";
if isfield(document, "calibration_status") && ...
        isstruct(document.calibration_status) && ...
        isfield(document.calibration_status, "state")
    value = string(document.calibration_status.state);
end
end

function value = textOf(container, name)
value = "";
if isfield(container, name)
    value = string(container.(name));
end
end

% ------------------------------------------------------------ generation ---

function generated = applyConfiguration(document, names, values, baseVersion, ...
    configurationId)
generated = document;
for index = 1:numel(names)
    generated.candidate_generation.plausibility_rule.(names(index)) = ...
        values(index);
end
% A distinct profile_version encoding the configuration identifier, so a human
% reading a stored analysis can name the configuration without recomputing a
% checksum.
generated.profile.profile_version = char(baseVersion + "+exp." + ...
    configurationId);
end

function writeSpecification(path, document, overwrite)
if isfile(path) && ~overwrite
    error("vawlume:eda:SpecificationExists", ...
        "Generated specification already exists and Overwrite is false: %s", ...
        path);
end
text = jsonencode(document, PrettyPrint=true);
fileId = fopen(path, "wb");
if fileId < 0
    error("vawlume:eda:SpecificationUnwritable", ...
        "Could not open generated specification for writing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, unicode2native(text, "UTF-8"), "uint8");
delete(cleaner);
end

function verifyWritten(path, names, values, configurationId)
%VERIFYWRITTEN Read the file back and confirm it says what it was meant to say.
%
% A specification that writes cleanly but reads back differently is the worst
% failure available here: it produces a plausible screen with silently wrong
% axes. This is a structural read-back, not the matcher's validation, and it is
% cheap enough to run on every file.
written = jsondecode(fileread(path));
rule = written.candidate_generation.plausibility_rule;
for index = 1:numel(names)
    if ~isfield(rule, names(index)) || ...
            ~isequal(double(rule.(names(index))), values(index))
        error("vawlume:eda:SpecificationRoundTripFailed", ...
            "Configuration %s wrote %s but read back a different value.", ...
            configurationId, names(index));
    end
end
end

function assertDistinctChecksums(identifiers, checksum)
if numel(unique(checksum)) == numel(checksum)
    return
end
[~, first] = unique(checksum, "stable");
duplicated = setdiff(1:numel(checksum), first);
error("vawlume:eda:SpecificationChecksumCollision", ...
    "Configurations %s produced identical specification checksums, so the " + ...
    "matcher would treat them as one analysis identity. Two design rows " + ...
    "that differ must differ on disk.", ...
    strjoin(identifiers(duplicated)', ", "));
end

% ----------------------------------------------------------- bookkeeping ---

function [runKey, source] = resolveRunKey(design, options)
if strlength(options.ExplorationRunKey) > 0
    runKey = options.ExplorationRunKey;
    source = "user";
    if ~isempty(regexp(runKey, "[^A-Za-z0-9._-]", "once"))
        error("vawlume:eda:ExplorationRunKeyInvalid", ...
            "ExplorationRunKey becomes a directory name and a run-key " + ...
            "prefix, so it must contain only letters, digits, dot, " + ...
            "underscore or hyphen; got '%s'.", runKey);
    end
    return
end
% Derived from what actually defines the run: the design's identity and the
% configurations it will execute. Deterministic, so rerunning writes the same
% files to the same place rather than accumulating parallel directories.
payload = design.design_type + "|" + string(design.factor_count) + "|" + ...
    string(design.fraction_exponent) + "|" + ...
    strjoin(sort(design.configurations.configuration_id)', ",");
runKey = "exp-" + extractBefore(edaSha256OfText(payload), 11);
source = "derived_from_design";
end

function root = resolveOutputRoot(options)
if strlength(options.OutputRoot) > 0
    root = options.OutputRoot;
    return
end
% A tempdir-based workspace, following the repository's demo convention, but
% with a fixed name rather than a random one: the per-run directory below it is
% already unique and deterministic, and a random root would scatter reruns of
% one design across directories that cannot be compared.
root = fullfile(tempdir, "VAWLUME exploration");
end

function value = runKeyTemplate(runKey)
value = struct( ...
    matching=runKey + "/<configuration_id>/m/r<recording_id>/<key_a>-<key_b>", ...
    agreement=runKey + "/<configuration_id>/a/r<recording_id>", ...
    pair_ordering="ascending extractor_key; run_a is the lower key", ...
    note="No timestamps, no counters, no random suffixes: a run key is " + ...
        "reproducible from the configuration and the recording alone.");
end

function value = provenanceRecord(design, baseIdentity, runKey, specDirectory)
value = struct( ...
    exploration_run_key=runKey, ...
    design_type=design.design_type, ...
    configuration_count=height(design.configurations), ...
    factor_count=design.factor_count, ...
    fraction_exponent=design.fraction_exponent, ...
    generators=design.alias.generators, ...
    defining_relation=design.alias.defining_relation, ...
    resolution=design.alias.resolution, ...
    resolution_label=design.alias.resolution_label, ...
    alias_note=design.alias.note, ...
    alias_table=design.alias.alias_table, ...
    generator_source=design.generator_source, ...
    decision_path=design.decision_path, ...
    row_order=design.row_order, ...
    coding_convention=design.coding_convention, ...
    randomization=design.randomization, ...
    factors=design.factors, ...
    probe_resolution=design.probe_resolution, ...
    base_specification=baseIdentity, ...
    specification_directory=string(specDirectory));
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:DesignInvalid", ...
        "The supplied design is missing required field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
