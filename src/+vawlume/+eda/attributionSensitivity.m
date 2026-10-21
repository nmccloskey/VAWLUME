function result = attributionSensitivity(conn, familySpec, options)
%ATTRIBUTIONSENSITIVITY Plan or apply one attribution-side sensitivity family.
%
% RESULT = VAWLUME.EDA.ATTRIBUTIONSENSITIVITY(CONN, FAMILYSPEC) plans a family
% of variants of one native attribution run and writes nothing. It prints every
% variant, its handle value, its deterministic configuration id and its
% predicted cost before anything runs. Apply=true materializes and runs the
% plan, then records the family (contract 07 D1, D2, D6).
%
% SENSITIVITY SELECTS NOTHING. A variant says how a conclusion moves when one
% declared input changes. Nothing here, or in VAWLUME.EDA.SENSITIVITYSUMMARY,
% orders variants by outcome or names one as preferred. The reference is
% declared in FAMILYSPEC before any result exists, and declaring it says only
% that the others are compared with it.
%
% FAMILYSPEC fields:
%   family_key   project-scoped key of the family record
%   output_root  folder for generated profile files (never under config/)
%   reference    the declared reference variant:
%                  attribution_run_id  an applied native_estimate run
%                  run_spec            the vawlume.estimator.attributeCallers
%                                      runSpec that produced it (run_key and
%                                      settings_profile_version_id must match
%                                      the stored run)
%                  decision_policy     the decision-policy file the reference
%                                      run was decided under
%   variants     struct array of handle and value (a struct of factors):
%
%     decision_policy       selection_threshold, separation_margin,
%                           co_occurrence_threshold (where the rule has one)
%     estimator_settings    primary_instant_basis, max_interpolation_gap_s,
%                           min_distance, channel_pair
%     normalization_policy  reference_type (for example "tone")
%     alignment_run         audio_alignment_run_id or tracking_alignment_run_id
%                           (an already fitted, alternative alignment run)
%
% Each variant gets a configuration id by the exploration's rule (SHA-256 over
% the name-sorted "handle.factor=value" pairs; numbers %.17g, text verbatim).
% Generated profile files keep the reference's profile key and take the version
% label "<reference version>+sens.<configuration_id>". Only the varied values
% and the version label differ from the reference file. They are written under
% output_root and registered through vawlume.db.registerProfileVersion. No
% shipped profile is edited. The normalization alternative is a generated
% tone-family policy, not a shipped file (contract 07 D6).
%
% WHAT APPLY RUNS, through the existing producers only:
%   decision_policy       vawlume.attribution.decide on the reference run
%   estimator_settings    vawlume.estimator.attributeCallers, then decide under
%                         the reference policy
%   normalization_policy  vawlume.acoustic.normalizeCallLevels per target on the
%                         reference's call-window and response runs, then
%                         attributeCallers and decide
%   alignment_run         attributeCallers naming the alignment run, then decide
% No audio is re-read. Each producer owns its own transaction, so a failure
% part-way leaves the variants already applied; their run keys are
% deterministic, and a re-apply of the same design is reported "reused" only
% once the family record exists.
%
% THE FAMILY is one analysis_runs row (run_type attribution_sensitivity, run_key
% family_key), with analysis_run_sources rows sensitivity_reference (the
% reference run) and sensitivity_variant (each variant run). Its design record,
% the declared design plus every generated profile version, is registered as an
% analysis_settings profile version linked with assignment_role
% sensitivity_design. No comparison result is stored.
%
% Handles method 1.0.0 does not vary are reported, never omitted: the gates, the
% dimension declarations, positional error (a margin, vawlume.estimator.qcFacts),
% identity uncertainty (not measurable in v2) and the call band (re-measures
% audio; not exercised). See RESULT.reported.
%
% REFUSED BY NAME, BEFORE ANY WRITE:
%   no reference, or one that does not describe its stored run
%                              vawlume:eda:SensitivityReferenceRequired
%   a variant of a reported handle   vawlume:eda:SensitivityHandleNotVariable
%   an unknown handle or factor      vawlume:eda:SensitivityHandleUnknown
%   family_key already used by another design   vawlume:eda:SensitivityFamilyConflict
%
% Name-value options: Apply (false), Print (true), RepoRoot.
%
% See also VAWLUME.EDA.SENSITIVITYSUMMARY, VAWLUME.ATTRIBUTION.COMPARE

arguments
    conn
    familySpec (1,1) struct
    options.Apply (1,1) logical = false
    options.Print (1,1) logical = true
    options.RepoRoot (1,1) string = ""
end

repoRoot = options.RepoRoot;
if strlength(repoRoot) == 0
    repoRoot = string(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
catalog = edaSensitivityHandles("attribution");
spec = validateSpec(familySpec);
reference = resolveReference(conn, spec, repoRoot);
variants = planVariants(spec, reference, catalog);
design = struct(family_key=spec.family_key, ...
    reference_attribution_run_id=reference.attribution_run_id, ...
    reference_run_key=reference.run_key, ...
    reference_settings_profile_version_id=reference.settings_version_id, ...
    reference_policy_profile_version_id=reference.policy_version_id, ...
    variants=variants(:, ["handle", "configuration_id", "identity_payload", ...
        "handle_value", "variant_kind", "run_key"]));
designSha = edaSha256OfText(string(jsonencode(design)));
existing = edaExistingSensitivityFamily(conn, reference.project_id, spec.family_key, designSha);

result = struct(status="planned", committed=false, family_key=spec.family_key, ...
    design_sha256=designSha, reference=reference, variants=variants, ...
    reported=catalog.reported, predicted=totals(variants, reference), ...
    executed=struct(), family_analysis_run_id=existing.analysis_run_id);
if existing.found
    result.status = "reused";
end
if options.Print
    printPlan(result);
end
if ~options.Apply || existing.found
    return
end

before = counts(conn);
outDir = fullfile(spec.output_root, spec.family_key);
if ~isfolder(outDir), mkdir(outDir); end
for k = 1:height(variants)
    variants(k, :) = applyVariant(conn, variants(k, :), reference, outDir, repoRoot);
end
result.variants = variants;
record = design;
record.family_kind = "attribution";
record.variants = variants(:, ["handle", "configuration_id", "identity_payload", ...
    "handle_value", "variant_kind", "run_key", "attribution_run_id", ...
    "policy_profile_version_id", "settings_profile_version_id"]);
record.reported = catalog.reported;
record.design_sha256 = designSha;
result.family_analysis_run_id = edaRecordSensitivityFamily(conn, reference.project_id, ...
    spec.family_key, reference.attribution_run_id, ...
    variants.attribution_run_id(variants.variant_kind == "run"), record, outDir, repoRoot);
result.executed = executedCounts(before, counts(conn));
result.status = "applied";
result.committed = true;
end

% ------------------------------------------------------------------ spec ---

function spec = validateSpec(raw)
if ~isfield(raw, "reference") || ~isstruct(raw.reference) || ...
        ~all(isfield(raw.reference, ["attribution_run_id", "run_spec", "decision_policy"]))
    error("vawlume:eda:SensitivityReferenceRequired", ...
        "A family declares its reference variant before any result exists: " + ...
        "reference.attribution_run_id, reference.run_spec and " + ...
        "reference.decision_policy are required.");
end
for name = ["family_key", "output_root", "variants"]
    if ~isfield(raw, name)
        error("vawlume:eda:SensitivitySpecInvalid", "familySpec.%s is required.", name);
    end
end
spec = raw;
spec.family_key = string(raw.family_key);
spec.output_root = string(raw.output_root);
if contains(lower(strrep(spec.output_root, "\", "/")), "/config/") || ...
        endsWith(lower(strrep(spec.output_root, "\", "/")), "/config")
    error("vawlume:eda:SensitivitySpecInvalid", ...
        "output_root must be outside config/: generated profiles are runtime artifacts.");
end
end

function reference = resolveReference(conn, spec, repoRoot)
ref = spec.reference;
r = vawlume.attribution.report(conn, struct(attribution_run_id=double(ref.attribution_run_id)), ...
    Tables=["targets", "decisions"]);
runSpec = ref.run_spec;
if r.attribution_path ~= "native_estimate" || ~isfield(runSpec, "run_key") || ...
        string(runSpec.run_key) ~= r.run_key || ...
        double(runSpec.settings_profile_version_id) ~= r.settings_profile_version_id
    error("vawlume:eda:SensitivityReferenceRequired", ...
        "reference.run_spec does not describe native run %d (%s): its run_key and " + ...
        "settings_profile_version_id must be the stored run's.", ...
        r.attribution_run_id, r.run_key);
end
policyPath = string(ref.decision_policy);
if ~java.io.File(char(policyPath)).isAbsolute()
    policyPath = fullfile(repoRoot, policyPath);
end
policy = jsondecode(fileread(policyPath));
decided = r.decisions(r.decisions.policy_profile_key == string(policy.profile.id) & ...
    r.decisions.policy_version_label == string(policy.profile.profile_version), :);
if height(decided) == 0
    error("vawlume:eda:SensitivityReferenceRequired", ...
        "Reference run %d was not decided under %s %s.", r.attribution_run_id, ...
        string(policy.profile.id), string(policy.profile.profile_version));
end
settings = fetch(conn, "SELECT content_uri FROM config_profile_versions WHERE " + ...
    "profile_version_id=" + string(r.settings_profile_version_id));
settingsPath = string(settings.content_uri(1));
if ~java.io.File(char(settingsPath)).isAbsolute()
    settingsPath = fullfile(repoRoot, settingsPath);
end
project = fetch(conn, "SELECT project_id FROM projects WHERE project_key='" + ...
    replace(r.project_key, "'", "''") + "'");
reference = struct(attribution_run_id=r.attribution_run_id, run_key=r.run_key, ...
    project_key=r.project_key, project_id=double(project.project_id(1)), ...
    recording_id=r.recording_id, run_spec=runSpec, ...
    settings_version_id=r.settings_profile_version_id, settings_path=settingsPath, ...
    policy_path=policyPath, policy_version_id=decided.policy_profile_version_id(1), ...
    target_count=height(r.targets));
end

% ---------------------------------------------------------------- plan ---

function variants = planVariants(spec, reference, catalog)
variants = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), cell(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    VariableNames=["handle", "configuration_id", "identity_payload", "handle_value", ...
    "variant_kind", "run_key", "factors", "predicted_attribution_runs", ...
    "predicted_decisions", "predicted_normalization_runs", ...
    "predicted_profile_versions", "predicted_decision_sets", "rereads_audio", ...
    "attribution_run_id", "policy_profile_version_id", "settings_profile_version_id"]);
for k = 1:numel(spec.variants)
    item = spec.variants(k);
    handle = string(item.handle);
    if ismember(handle, catalog.reported.handle)
        error("vawlume:eda:SensitivityHandleNotVariable", "%s is not varied: %s", ...
            handle, catalog.reported.reason(catalog.reported.handle == handle));
    end
    row = catalog.variable(catalog.variable.handle == handle, :);
    if height(row) == 0
        error("vawlume:eda:SensitivityHandleUnknown", ...
            "Unknown handle %s; the handles are %s.", handle, ...
            strjoin([catalog.variable.handle; catalog.reported.handle]', ", "));
    end
    factors = item.value;
    names = string(fieldnames(factors))';
    unknown = setdiff(names, row.factors{1});
    if isempty(names) || ~isempty(unknown)
        error("vawlume:eda:SensitivityHandleUnknown", ...
            "Handle %s takes %s; got %s.", handle, strjoin(row.factors{1}, ", "), ...
            strjoin(names, ", "));
    end
    names = sort(names);
    values = cell(1, numel(names));
    for f = 1:numel(names)
        values{f} = factors.(names(f));
    end
    identity = edaConfigurationIdentity(handle + "." + names, values);
    texts = strsplit(identity.identity_payload, ";");
    n = reference.target_count;
    switch handle
        case "decision_policy"
            cost = [0, n, 0, 1, 1];
        case "normalization_policy"
            cost = [1, n, n, 2, 1];
        case "estimator_settings"
            cost = [1, n, 0, 1, 1];
        otherwise
            cost = [1, n, 0, 0, 1];
    end
    variants(end + 1, :) = {handle, identity.configuration_id, identity.identity_payload, ...
        strjoin(texts, "; "), row.variant_kind, spec.family_key + "." + ...
        identity.configuration_id, {struct2cellPairs(names, values)}, cost(1), cost(2), ...
        cost(3), cost(4), cost(5), false, NaN, NaN, NaN}; %#ok<AGROW>
end
if numel(unique(variants.configuration_id)) ~= height(variants)
    error("vawlume:eda:SensitivitySpecInvalid", "Two variants have the same configuration.");
end
variants = sortrows(variants, ["handle", "handle_value"]);
end

function pairs = struct2cellPairs(names, values)
pairs = struct();
for f = 1:numel(names)
    pairs.(names(f)) = values{f};
end
end

function value = totals(variants, reference)
value = struct( ...
    attribution_runs=sum(variants.predicted_attribution_runs), ...
    decisions=sum(variants.predicted_decisions), ...
    normalization_runs=sum(variants.predicted_normalization_runs), ...
    profile_versions=sum(variants.predicted_profile_versions) + 1, ...
    family_records=1, rereads_audio=false, ...
    note=sprintf("%d variants of run %d (%d targets); the family's design record is " + ...
        "one profile version; tracking windows are re-read by each run variant, audio by none.", ...
        height(variants), reference.attribution_run_id, reference.target_count));
end

function printPlan(result)
fprintf("Sensitivity family %s (%s): reference run %d (%s)\n", result.family_key, ...
    result.status, result.reference.attribution_run_id, result.reference.run_key);
for k = 1:height(result.variants)
    v = result.variants(k, :);
    fprintf("  %-22s %s  %s\n      cost: %d run(s), %d decision(s), %d normalization run(s), " + ...
        "%d profile version(s), audio re-read: no\n", v.handle, v.configuration_id, ...
        v.handle_value, v.predicted_attribution_runs, v.predicted_decisions, ...
        v.predicted_normalization_runs, v.predicted_profile_versions);
end
fprintf("  total: %s\n", result.predicted.note);
fprintf("  not varied: %s\n", strjoin(result.reported.handle + " (" + ...
    result.reported.status + ")", ", "));
end

% ---------------------------------------------------------------- apply ---

function row = applyVariant(conn, row, reference, outDir, repoRoot)
factors = row.factors{1};
recordingRef = struct(recording_id=reference.recording_id);
runSpec = reference.run_spec;
runSpec.run_key = row.run_key;
policyPath = reference.policy_path;
switch row.handle
    case "decision_policy"
        path = fullfile(outDir, "policy_" + row.configuration_id + ".json");
        edits = struct();
        for name = string(fieldnames(factors))'
            edits.(name) = numberJson(factors.(name));
        end
        edaWriteProfileVariant(reference.policy_path, path, edits, row.configuration_id, ...
            Scope="thresholds");
        decided = vawlume.attribution.decide(conn, ...
            struct(attribution_run_id=reference.attribution_run_id), path, ...
            Apply=true, RepoRoot=repoRoot);
        row.policy_profile_version_id = double(decided.policy_profile_version_id);
        row.attribution_run_id = reference.attribution_run_id;
        return
    case "estimator_settings"
        edits = struct();
        for name = string(fieldnames(factors))'
            edits.(name) = valueJson(factors.(name));
        end
        runSpec.settings_profile_version_id = registerSettings(conn, reference, ...
            edits, outDir, row.configuration_id, repoRoot);
    case "normalization_policy"
        normalization = normalizationVariant(conn, reference, factors, outDir, ...
            row, repoRoot);
        runSpec.normalization_runs = normalization.runs;
        edits = struct(normalization_policy=normalization.settings_json);
        runSpec.settings_profile_version_id = registerSettings(conn, reference, ...
            edits, outDir, row.configuration_id, repoRoot);
    case "alignment_run"
        if isfield(factors, "audio_alignment_run_id")
            runSpec.clock.audio_alignment_run_id = double(factors.audio_alignment_run_id);
        end
        if isfield(factors, "tracking_alignment_run_id")
            runSpec.tracking.alignment_run_id = double(factors.tracking_alignment_run_id);
        end
end
applied = vawlume.estimator.attributeCallers(conn, recordingRef, runSpec, ...
    Apply=true, RepoRoot=repoRoot);
row.attribution_run_id = applied.attribution_run_id;
row.settings_profile_version_id = double(runSpec.settings_profile_version_id);
decided = vawlume.attribution.decide(conn, struct(attribution_run_id=applied.attribution_run_id), ...
    policyPath, Apply=true, RepoRoot=repoRoot);
row.policy_profile_version_id = double(decided.policy_profile_version_id);
end

function id = registerSettings(conn, reference, edits, outDir, configurationId, repoRoot)
path = fullfile(outDir, "estimator_settings_" + configurationId + ".json");
document = edaWriteProfileVariant(reference.settings_path, path, edits, configurationId, ...
    Scope="parameters");
registered = vawlume.db.registerProfileVersion(conn, struct(project_id=reference.project_id), ...
    struct(profile_key=string(document.profile.id), profile_name=string(document.profile.name), ...
    version_label=string(document.profile.profile_version), content_path=path, ...
    profile_kind=string(document.profile.kind), ...
    profile_schema_version=string(document.profile.profile_schema_version)), RepoRoot=repoRoot);
id = double(registered.profile_version_id);
end

function value = normalizationVariant(conn, reference, factors, outDir, row, repoRoot)
% A generated policy differing from the reference settings' normalization policy
% in reference_type only; the reference's call-window and response runs are
% re-normalized under it, one run per target.
settings = jsondecode(fileread(reference.settings_path));
source = string(settings.parameters.normalization_policy.path);
if ~java.io.File(char(source)).isAbsolute()
    source = fullfile(repoRoot, source);
end
path = fullfile(outDir, "normalization_policy_" + row.configuration_id + ".json");
document = edaWriteProfileVariant(source, path, struct(reference_type=valueJson(factors.reference_type)), ...
    row.configuration_id, Scope="pairs", AllMatches=true);
runs = reference.run_spec.normalization_runs;
if isstruct(runs)
    runs = struct2table(structfun(@(v) v(:), runs, UniformOutput=false));
end
eventColumn = string(runs.Properties.VariableNames(1));
created = runs;
for k = 1:height(runs)
    parents = fetch(conn, "SELECT source_analysis_run_id, dependency_role FROM " + ...
        "analysis_run_sources WHERE analysis_run_id=" + string(double(runs.analysis_run_id(k))));
    roles = string(parents.dependency_role);
    callRun = double(parents.source_analysis_run_id(roles == "call_window_measurement"));
    responseRun = double(parents.source_analysis_run_id(roles == "channel_response_estimate"));
    applied = vawlume.acoustic.normalizeCallLevels(conn, struct(analysis_run_id=callRun), ...
        struct(analysis_run_id=responseRun), PolicyPath=path, Apply=true, ...
        RunKey=row.run_key + ".norm." + string(runs.(eventColumn)(k)), RepoRoot=repoRoot);
    created.analysis_run_id(k) = double(applied.analysis_run_id);
end
value = struct(runs=created, settings_json=jsonencode(struct( ...
    profile_key=string(document.profile.id), version=string(document.profile.profile_version), ...
    path=string(path))));
end


function text = numberJson(value)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    error("vawlume:eda:SensitivitySpecInvalid", "A threshold variant takes one finite number.");
end
text = string(sprintf("%.17g", double(value)));
end

function text = valueJson(value)
if isnumeric(value) && isscalar(value)
    text = numberJson(value);
elseif isnumeric(value)
    text = "[" + strjoin(compose("%.17g", double(value(:)')), ", ") + "]";
else
    text = string(jsonencode(string(value)));
end
end

function value = counts(conn)
q = @(sql) double(table2array(fetch(conn, sql)));
value = struct( ...
    attribution_runs=q("SELECT COUNT(*) FROM attribution_runs"), ...
    decisions=q("SELECT COUNT(*) FROM attribution_decisions"), ...
    normalization_runs=q("SELECT COUNT(*) FROM analysis_runs WHERE run_type=" + ...
        "'acoustic_call_level_normalization'"), ...
    profile_versions=q("SELECT COUNT(*) FROM config_profile_versions"), ...
    family_records=q("SELECT COUNT(*) FROM analysis_runs WHERE run_type='attribution_sensitivity'"));
end

function value = executedCounts(before, after)
value = struct();
for name = string(fieldnames(before))'
    value.(name) = after.(name) - before.(name);
end
end
