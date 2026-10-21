function result = correspondenceSensitivity(conn, familySpec, options)
%CORRESPONDENCESENSITIVITY Plan or apply one matching-side sensitivity family.
%
% RESULT = VAWLUME.EDA.CORRESPONDENCESENSITIVITY(CONN, FAMILYSPEC) plans how
% attribution moves when the correspondence layer beneath it changes, and writes
% nothing. It prints every configuration, its factor values, its deterministic
% configuration id and its cost before anything runs. Apply=true runs the plan
% and records the family (contract 07 D3, D7).
%
% SENSITIVITY SELECTS NOTHING. The reference configuration is declared in
% FAMILYSPEC (the tracked matching specification unless a path is given) before
% any result exists. A configuration says how conclusions move under one
% declared change to the matching specification, never which is right; no
% configuration is ranked, and "optimal", "best", "recommended" or "validated"
% appear in no output. A reference configuration is not a calibrated one.
%
% FAMILYSPEC fields:
%   family_key        project-scoped key of the family record
%   output_root       folder for generated specifications (never under config/)
%   recording_id      the one recording (the synthetic fixture only in Phase 7)
%   extraction_runs   run keys of the extraction runs to match, e.g.
%                     ["p7-ds", "p7-mupet", "p7-usvseg"]; every pair is matched
%   consensus_pair    the two run keys whose matching analysis supplies the
%                     consensus events that are attributed
%   reference         the declared reference configuration:
%                       specification_path  optional; the tracked matching
%                                           specification by default
%                                           (vawlume.eda.referenceConfiguration)
%                       run_spec            the native attributeCallers runSpec
%                                           fields shared by every configuration:
%                                           settings_profile_version_id,
%                                           participating_entity_ids, clock,
%                                           tracking (no run_key, target_set or
%                                           normalization_runs: those are built)
%                       decision_policy     the decision-policy file
%                       measurement         channels, band_hz, source_root (the
%                                           audio root) and response_run_id: how
%                                           each consensus event's call window is
%                                           measured and normalized
%   variants          struct array of handle and value:
%     matching_temporal   min_temporal_iou (plausibility_rule)
%     matching_spectral   relative_tolerance (every feature_support.
%                         discrepancy_tolerance entry)
%
% PER CONFIGURATION (the reference included), through existing functions only:
%   1. vawlume.matching.compare for every extraction-run pair, and
%      vawlume.agreement.compose over them. An applied analysis over the same
%      runs and recording whose specification checksum is identical is REUSED
%      (contract 07 D7); otherwise a new analysis is written beside it.
%      Nothing is replaced.
%   2. For every consensus event of the consensus pair's analysis:
%      vawlume.acoustic.measureCallWindow (this READS AUDIO) and
%      normalizeCallLevels against the declared response run.
%   3. vawlume.estimator.attributeCallers over those consensus events, then
%      vawlume.attribution.decide under the reference decision policy.
% Configurations are then compared with the reference by
% VAWLUME.EDA.SENSITIVITYSUMMARY through vawlume.attribution.compare, joining
% consensus events by their stored shared member detections.
%
% A generated specification is a byte copy of the reference with only the
% varied values and the version label "<version>+sens.<configuration_id>"
% changed, written under output_root; the tracked specification is never edited.
% (vawlume.eda.materializeConfigurations is not used: it overrides only
% plausibility_rule fields, so it cannot make a spectral variant, and it expects
% a full screening design.)
%
% COST. The plan prints the analyses (the consilience formula: N(N-1)/2 matching
% plus one agreement per configuration, minus those reused), the attribution
% runs, and the consensus events to measure, estimated from the reference
% analysis's count where it already exists: a configuration's own count is known
% only after its matching runs. Apply measures the wall time per configuration.
% EXP-050 is the warning: analysis counts did not predict wall time on real data.
% No real-data run of this orchestrator happens in Phase 7 (contract 07 D7).
%
% The family record is the same as vawlume.eda.attributionSensitivity's, with
% family_kind "correspondence" in the design record.
%
% REFUSED BY NAME: SensitivityReferenceRequired, SensitivityHandleNotVariable,
% SensitivityHandleUnknown, SensitivityFamilyConflict (vawlume:eda:*).
%
% Name-value options: Apply (false), Print (true), RepoRoot.
%
% See also VAWLUME.EDA.SENSITIVITYSUMMARY, VAWLUME.EDA.ATTRIBUTIONSENSITIVITY,
% VAWLUME.EDA.REFERENCECONFIGURATION

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
catalog = edaSensitivityHandles("correspondence");
spec = validateSpec(familySpec);
context = resolveContext(conn, spec, repoRoot);
configurations = planConfigurations(conn, spec, context, catalog);
design = struct(family_kind="correspondence", family_key=spec.family_key, ...
    recording_id=context.recording_id, extraction_runs=spec.extraction_runs, ...
    consensus_pair=spec.consensus_pair, ...
    reference_specification=context.reference_identity, ...
    configurations=configurations(:, ["handle", "configuration_id", "identity_payload", ...
        "handle_value", "specification_checksum"]));
designSha = edaSha256OfText(string(jsonencode(design)));
existing = edaExistingSensitivityFamily(conn, context.project_id, spec.family_key, designSha);

result = struct(status="planned", committed=false, family_key=spec.family_key, ...
    design_sha256=designSha, reference_specification=context.reference_identity, ...
    configurations=configurations, reported=catalog.reported, ...
    predicted=totals(configurations, context), executed=struct(), ...
    family_analysis_run_id=existing.analysis_run_id);
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
for k = 1:height(configurations)
    started = tic;
    configurations(k, :) = applyConfiguration(conn, configurations(k, :), spec, context, repoRoot);
    configurations.wall_seconds(k) = toc(started);
end
result.configurations = configurations;
reference = configurations(configurations.handle == "reference", :);
record = design;
record.reference_attribution_run_id = reference.attribution_run_id;
record.reference_policy_profile_version_id = reference.policy_profile_version_id;
record.variants = configurations(:, ["handle", "configuration_id", "identity_payload", ...
    "handle_value", "variant_kind", "run_key", "attribution_run_id", ...
    "policy_profile_version_id", "consensus_analysis_run_id", "matching_analysis_run_ids", ...
    "agreement_analysis_run_id", "consensus_event_count", "wall_seconds"]);
record.reported = catalog.reported;
record.design_sha256 = designSha;
result.family_analysis_run_id = edaRecordSensitivityFamily(conn, context.project_id, ...
    spec.family_key, reference.attribution_run_id, configurations.attribution_run_id, ...
    record, context.out_dir, repoRoot);
result.executed = executedCounts(before, counts(conn));
result.status = "applied";
result.committed = true;
end

% ------------------------------------------------------------------ spec ---

function spec = validateSpec(raw)
if ~isfield(raw, "reference") || ~isstruct(raw.reference) || ...
        ~all(isfield(raw.reference, ["run_spec", "decision_policy", "measurement"]))
    error("vawlume:eda:SensitivityReferenceRequired", ...
        "A family declares its reference configuration before any result exists: " + ...
        "reference.run_spec, reference.decision_policy and reference.measurement " + ...
        "are required (reference.specification_path defaults to the tracked one).");
end
for name = ["family_key", "output_root", "recording_id", "extraction_runs", ...
        "consensus_pair", "variants"]
    if ~isfield(raw, name)
        error("vawlume:eda:SensitivitySpecInvalid", "familySpec.%s is required.", name);
    end
end
spec = raw;
spec.family_key = string(raw.family_key);
spec.output_root = string(raw.output_root);
spec.extraction_runs = string(raw.extraction_runs(:))';
spec.consensus_pair = string(raw.consensus_pair(:))';
root = lower(strrep(spec.output_root, "\", "/"));
if contains(root, "/config/") || endsWith(root, "/config")
    error("vawlume:eda:SensitivitySpecInvalid", ...
        "output_root must be outside config/: generated specifications are runtime artifacts.");
end
if numel(spec.consensus_pair) ~= 2 || ~all(ismember(spec.consensus_pair, spec.extraction_runs))
    error("vawlume:eda:SensitivitySpecInvalid", ...
        "consensus_pair must name two of the extraction runs.");
end
end

function context = resolveContext(conn, spec, repoRoot)
specPath = "";
if isfield(spec.reference, "specification_path")
    specPath = string(spec.reference.specification_path);
end
reference = vawlume.eda.referenceConfiguration(SpecPath=specPath, RepoRoot=repoRoot);
recording = fetch(conn, "SELECT r.recording_id, r.project_id FROM recordings r " + ...
    "WHERE r.recording_id=" + string(double(spec.recording_id)));
if isempty(recording) || height(recording) == 0
    error("vawlume:eda:SensitivitySpecInvalid", "Recording %d does not exist.", spec.recording_id);
end
runs = fetch(conn, "SELECT extraction_run_id, run_key FROM extraction_runs WHERE run_key IN ('" + ...
    strjoin(spec.extraction_runs, "','") + "')");
extraction = containers.Map(cellstr(string(runs.run_key)), num2cell(double(runs.extraction_run_id)));
missing = spec.extraction_runs(~isKey(extraction, cellstr(spec.extraction_runs)));
if ~isempty(missing)
    error("vawlume:eda:SensitivitySpecInvalid", "Unknown extraction runs: %s.", strjoin(missing, ", "));
end
pairs = nchoosek(1:numel(spec.extraction_runs), 2);
policy = string(spec.reference.decision_policy);
if ~java.io.File(char(policy)).isAbsolute()
    policy = fullfile(repoRoot, policy);
end
context = struct(recording_id=double(recording.recording_id(1)), ...
    project_id=double(recording.project_id(1)), reference_identity=identityOf(reference), ...
    reference_path=string(reference.specification_path), extraction=extraction, ...
    pairs=[spec.extraction_runs(pairs(:, 1))', spec.extraction_runs(pairs(:, 2))'], ...
    consensus_pair=spec.consensus_pair, policy_path=policy, ...
    out_dir=fullfile(spec.output_root, spec.family_key));
end

function value = identityOf(reference)
value = struct(profile_key=string(reference.profile_key), ...
    version_label=string(reference.version_label), ...
    checksum_sha256=string(reference.checksum_sha256), ...
    specification_path=string(reference.specification_path), ...
    calibration_state=string(reference.calibration_status.state));
end

% ---------------------------------------------------------------- plan ---

function configurations = planConfigurations(conn, spec, context, catalog)
configurations = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), cell(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    cell(0, 1), NaN(0, 1), NaN(0, 1), NaN(0, 1), ...
    VariableNames=["handle", "configuration_id", "identity_payload", "handle_value", ...
    "variant_kind", "run_key", "factors", "specification_path", "specification_checksum", ...
    "predicted_matching_analyses", "predicted_agreement_analyses", ...
    "predicted_attribution_runs", "predicted_consensus_events", "attribution_run_id", ...
    "policy_profile_version_id", "consensus_analysis_run_id", "matching_analysis_run_ids", ...
    "agreement_analysis_run_id", "consensus_event_count", "wall_seconds"]);
configurations(end + 1, :) = planned(conn, spec, context, "reference", "reference", ...
    "reference specification " + context.reference_identity.version_label, struct(), ...
    context.reference_path, context.reference_identity.checksum_sha256);
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
            "Unknown matching-side handle %s; the handles are %s.", handle, ...
            strjoin([catalog.variable.handle; catalog.reported.handle]', ", "));
    end
    names = string(fieldnames(item.value))';
    if isempty(names) || ~isempty(setdiff(names, row.factors{1}))
        error("vawlume:eda:SensitivityHandleUnknown", "Handle %s takes %s.", handle, ...
            strjoin(row.factors{1}, ", "));
    end
    names = sort(names);
    values = cellfun(@(n) item.value.(n), cellstr(names), UniformOutput=false);
    identity = edaConfigurationIdentity(handle + "." + names, values);
    path = fullfile(context.out_dir, "matching_spec_" + identity.configuration_id + ".json");
    configurations(end + 1, :) = planned(conn, spec, context, handle, ...
        identity.configuration_id, strjoin(strsplit(identity.identity_payload, ";"), "; "), ...
        cell2struct(values(:), cellstr(names(:)), 1), path, ""); %#ok<AGROW>
    configurations.identity_payload(end) = identity.identity_payload;
end
if numel(unique(configurations.configuration_id)) ~= height(configurations)
    error("vawlume:eda:SensitivitySpecInvalid", "Two configurations are the same.");
end
end

function row = planned(conn, spec, context, handle, configurationId, value, factors, ...
        path, checksum)
% A planned configuration: what it will write, and its predicted cost.
matching = height(context.pairs);
agreement = 1;
if handle == "reference"
    reused = arrayfun(@(k) reusableMatching(conn, context, context.pairs(k, :), checksum), ...
        1:height(context.pairs));
    matching = nnz(isnan(reused));
    if matching == 0 && ~isnan(reusableAgreement(conn, reused))
        agreement = 0;
    end
end
estimate = referenceConsensusCount(conn, context);
row = {handle, configurationId, "", value, "configuration", ...
    spec.family_key + "." + configurationId, {factors}, string(path), string(checksum), ...
    matching, agreement, 1, estimate, NaN, NaN, NaN, {zeros(1, 0)}, NaN, NaN, NaN};
end

function value = referenceConsensusCount(conn, context)
% Consensus events the reference analysis stored, where it exists: the estimate
% of each configuration's measurements. The real count is known after matching.
id = reusableMatching(conn, context, consensusPairRow(context), ...
    context.reference_identity.checksum_sha256);
value = NaN;
if ~isnan(id)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM consensus_events WHERE analysis_run_id=" + ...
        string(id) + " AND recording_id=" + string(context.recording_id));
    value = double(rows.n(1));
end
end

function pair = consensusPairRow(context)
pair = context.pairs(all(ismember(context.pairs, context.consensus_pair), 2), :);
end

function value = totals(configurations, context)
value = struct( ...
    configurations=height(configurations), ...
    matching_analyses=sum(configurations.predicted_matching_analyses), ...
    agreement_analyses=sum(configurations.predicted_agreement_analyses), ...
    attribution_runs=sum(configurations.predicted_attribution_runs), ...
    consensus_events_estimated=sum(configurations.predicted_consensus_events), ...
    reads_audio=true, family_records=1, ...
    note=sprintf("%d configurations on recording %d: %d matching pairs each (the " + ...
        "consilience formula), one agreement each, one native run each; each " + ...
        "consensus event is measured from audio and normalized. Wall time is " + ...
        "measured during apply; at real-data scale it is not predicted by these " + ...
        "counts (EXP-050).", height(configurations), context.recording_id, ...
        height(context.pairs)));
end

function printPlan(result)
fprintf("Matching-side sensitivity family %s (%s), reference specification %s %s\n", ...
    result.family_key, result.status, result.reference_specification.profile_key, ...
    result.reference_specification.version_label);
for k = 1:height(result.configurations)
    c = result.configurations(k, :);
    fprintf("  %-18s %-14s %s\n      cost: %d matching, %d agreement, %d run, ~%g " + ...
        "consensus events measured from audio\n", c.handle, c.configuration_id, ...
        c.handle_value, c.predicted_matching_analyses, c.predicted_agreement_analyses, ...
        c.predicted_attribution_runs, c.predicted_consensus_events);
end
fprintf("  total: %s\n", result.predicted.note);
fprintf("  not varied: %s\n", strjoin(result.reported.handle + " (" + ...
    result.reported.status + ")", ", "));
end

% ---------------------------------------------------------------- apply ---

function row = applyConfiguration(conn, row, spec, context, repoRoot)
if ~isfolder(context.out_dir), mkdir(context.out_dir); end
path = row.specification_path;
checksum = row.specification_checksum;
if row.handle ~= "reference"
    factors = row.factors{1};
    name = string(fieldnames(factors));
    if row.handle == "matching_temporal"
        scope = "plausibility_rule";
        everyMatch = false;
    else
        scope = "discrepancy_tolerance";
        everyMatch = true;
    end
    edaWriteProfileVariant(context.reference_path, path, ...
        struct(name, sprintf("%.17g", double(factors.(name)))), row.configuration_id, ...
        Scope=scope, AllMatches=everyMatch);
    checksum = edaSha256OfFile(path);
end
recordingRef = struct(recording_id=context.recording_id);
ids = zeros(1, height(context.pairs));
keys = strings(1, height(context.pairs));
for k = 1:height(context.pairs)
    pair = context.pairs(k, :);
    existing = reusableMatching(conn, context, pair, checksum);
    if ~isnan(existing)
        ids(k) = existing;
    else
        applied = vawlume.matching.compare(conn, recordingRef, ...
            struct(run_a=pair(1), run_b=pair(2)), ...
            struct(run_key=row.run_key + ".m." + pair(1) + "-" + pair(2), ...
            profile_path=string(path)), RepoRoot=repoRoot, Apply=true);
        ids(k) = double(applied.analysis.analysis_run_id);
    end
    keys(k) = runKeyOf(conn, ids(k));
end
row.matching_analysis_run_ids = {ids};
row.agreement_analysis_run_id = agreementFor(conn, context, ids, keys, row.run_key + ".a", ...
    repoRoot);
consensusAnalysis = ids(all(ismember(context.pairs, spec.consensus_pair), 2));
row.consensus_analysis_run_id = consensusAnalysis;
events = fetch(conn, "SELECT consensus_event_id FROM consensus_events WHERE analysis_run_id=" + ...
    string(consensusAnalysis) + " AND recording_id=" + string(context.recording_id) + ...
    " ORDER BY consensus_event_id");
events = double(events.consensus_event_id);
row.consensus_event_count = numel(events);
m = spec.reference.measurement;
normalization = zeros(numel(events), 1);
for k = 1:numel(events)
    call = vawlume.acoustic.measureCallWindow(conn, struct(consensus_event_id=events(k)), ...
        double(m.channels), BandHz=double(m.band_hz), SourceRoot=string(m.source_root), ...
        Apply=true, RunKey=row.run_key + ".call." + events(k));
    normalized = vawlume.acoustic.normalizeCallLevels(conn, ...
        struct(analysis_run_id=call.analysis_run_id), ...
        struct(analysis_run_id=double(m.response_run_id)), RepoRoot=repoRoot, ...
        Apply=true, RunKey=row.run_key + ".norm." + events(k));
    normalization(k) = double(normalized.analysis_run_id);
end
runSpec = spec.reference.run_spec;
runSpec.run_key = row.run_key + ".native";
runSpec.target_set = struct(consensus_event_ids=events');
runSpec.normalization_runs = table(events, normalization, ...
    VariableNames=["consensus_event_id", "analysis_run_id"]);
applied = vawlume.estimator.attributeCallers(conn, recordingRef, runSpec, ...
    Apply=true, RepoRoot=repoRoot);
row.attribution_run_id = applied.attribution_run_id;
decided = vawlume.attribution.decide(conn, struct(attribution_run_id=applied.attribution_run_id), ...
    context.policy_path, Apply=true, RepoRoot=repoRoot);
row.policy_profile_version_id = double(decided.policy_profile_version_id);
row.specification_checksum = checksum;
end

function id = reusableMatching(conn, context, pair, checksum)
% An applied cross_extractor_matching analysis over exactly this (run_a, run_b)
% on this recording, whose specification file checksum is CHECKSUM. NaN if none.
id = NaN;
if strlength(checksum) == 0
    return
end
a = context.extraction(char(pair(1)));
b = context.extraction(char(pair(2)));
rows = fetch(conn, "SELECT ar.analysis_run_id FROM analysis_runs ar " + ...
    "JOIN analysis_run_extraction_inputs ia ON ia.analysis_run_id=ar.analysis_run_id " + ...
    "AND ia.input_role='run_a' AND ia.extraction_run_id=" + string(a) + " " + ...
    "JOIN analysis_run_extraction_inputs ib ON ib.analysis_run_id=ar.analysis_run_id " + ...
    "AND ib.input_role='run_b' AND ib.extraction_run_id=" + string(b) + " " + ...
    "JOIN analysis_run_profiles p ON p.analysis_run_id=ar.analysis_run_id " + ...
    "JOIN config_profile_versions v ON v.profile_version_id=p.profile_version_id " + ...
    "WHERE ar.run_type='cross_extractor_matching' AND ar.status IN " + ...
    "('completed','completed_with_warnings') AND v.checksum_sha256='" + checksum + "' " + ...
    "AND EXISTS (SELECT 1 FROM match_groups g WHERE g.analysis_run_id=ar.analysis_run_id " + ...
    "AND g.recording_id=" + string(context.recording_id) + ") ORDER BY ar.analysis_run_id");
if ~isempty(rows) && height(rows) > 0
    id = double(rows.analysis_run_id(1));
end
end

function id = reusableAgreement(conn, matchingIds)
% An agreement analysis composed over exactly these pairwise analyses, or NaN.
id = NaN;
rows = fetch(conn, "SELECT s.analysis_run_id, s.source_analysis_run_id FROM " + ...
    "analysis_run_sources s JOIN analysis_runs a ON a.analysis_run_id=s.analysis_run_id " + ...
    "WHERE a.run_type='multi_extractor_agreement' AND s.dependency_role='pairwise_source'");
if isempty(rows) || height(rows) == 0
    return
end
for candidate = unique(double(rows.analysis_run_id))'
    sources = sort(double(rows.source_analysis_run_id(double(rows.analysis_run_id) == candidate)));
    if isequal(sources(:)', sort(matchingIds(:))')
        id = candidate;
        return
    end
end
end

function id = agreementFor(conn, context, matchingIds, matchingKeys, runKey, repoRoot)
% Reuse an agreement analysis composed over exactly these pairwise analyses;
% otherwise compose one.
id = reusableAgreement(conn, matchingIds);
if ~isnan(id)
    return
end
composed = vawlume.agreement.compose(conn, struct(recording_id=context.recording_id), ...
    matchingKeys, struct(run_key=runKey, run_label="Sensitivity agreement " + runKey), ...
    RepoRoot=repoRoot, Apply=true);
id = double(composed.analysis.analysis_run_id);
end

function key = runKeyOf(conn, id)
row = fetch(conn, "SELECT run_key FROM analysis_runs WHERE analysis_run_id=" + string(id));
key = string(row.run_key(1));
end

function value = counts(conn)
q = @(sql) double(table2array(fetch(conn, sql)));
value = struct( ...
    matching_analyses=q("SELECT COUNT(*) FROM analysis_runs WHERE run_type='cross_extractor_matching'"), ...
    agreement_analyses=q("SELECT COUNT(*) FROM analysis_runs WHERE run_type='multi_extractor_agreement'"), ...
    attribution_runs=q("SELECT COUNT(*) FROM attribution_runs"), ...
    call_window_runs=q("SELECT COUNT(*) FROM analysis_runs WHERE run_type='acoustic_call_window_response'"), ...
    family_records=q("SELECT COUNT(*) FROM analysis_runs WHERE run_type='attribution_sensitivity'"));
end

function value = executedCounts(before, after)
value = struct();
for name = string(fieldnames(before))'
    value.(name) = after.(name) - before.(name);
end
end
