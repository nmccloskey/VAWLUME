function result = runScreen(conn, dataset, materialized, options)
%RUNSCREEN Execute a screening design against a resolved dataset.
%
% RESULT = vawlume.eda.RUNSCREEN(CONN, DATASET, MATERIALIZED) plans every unit of
% a probe and writes nothing. Planning is the default, deliberately: it is how a
% caller checks a twenty-recording probe before committing to it.
%
% RESULT = vawlume.eda.RUNSCREEN(..., Apply=true) applies, for every
% configuration and every recording, one pairwise matching analysis per unordered
% extractor pair and then one agreement analysis composed over them, and records
% one exploration-run row linking the result together.
%
% Name-value options:
%   Apply                   write, default false
%   RepoRoot                repository root
%   AgreementSpecPath       agreement policy; defaults to the tracked one
%   ProbeRole               "whole_dataset" (default) or "subset". Tags this
%                           probe in the provenance so the two probes of one
%                           exploration run are distinguishable
%   StopOnFailure           abandon the probe at the first failed unit,
%                           default false
%   WarnAtAnalyses / MaximumAnalyses / AllowExceedingMaximum
%                           the analysis ceiling, enforced before any write
%
% THIS FUNCTION OWNS EVERY DATABASE WRITE IN THE EXPLORATORY WORKFLOW. Nothing
% downstream of it writes at all.
%
% It is RESUMABLE because its run keys are derived rather than generated. A rerun
% finds each analysis under the key it would have written and reuses it, so a
% probe interrupted halfway resumes rather than duplicating. A REUSE IS REPORTED
% AS ITS OWN STATUS, not folded into success, so a rerun's manifest shows what
% was actually new.
%
% A CONFLICT IS NEVER RESOLVED BY REWRITING. It means an analysis exists under
% this run key with different inputs or a different specification checksum, which
% almost always means the dataset or the reference specification changed beneath
% a stable key. The unit is reported with the conflict text and the stored
% analysis is left exactly as it was.
%
% AN AGREEMENT COMPOSITION IS NEVER ATTEMPTED OVER AN INCOMPLETE PAIRWISE SET. If
% any pair failed or conflicted for a recording, that recording's composition is
% marked skipped with the reason, rather than left for the composer to reject
% with a less specific message.
%
% A PARTIALLY EXECUTED PROBE IS AN UNBALANCED DESIGN, and the result says so.
% Effect estimation assumes every design row was evaluated on the same
% recordings; RESULT.design_completeness carries that judgement in a form the
% estimation layer can check before computing anything.
%
% The runner returns statuses and identifiers. It computes no response summary,
% deliberately: a response computed while an analysis is in hand and one computed
% later from stored rows are two implementations that will diverge.

arguments
    conn
    dataset (1,1) struct
    materialized (1,1) struct
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
    options.AgreementSpecPath (1,1) string = ""
    options.ProbeRole (1,1) string ...
        {mustBeMember(options.ProbeRole, ["whole_dataset", "subset"])} = "whole_dataset"
    options.StopOnFailure (1,1) logical = false
    options.WarnAtAnalyses (1,1) double {mustBePositive} = 250
    options.MaximumAnalyses (1,1) double {mustBePositive} = 2500
    options.AllowExceedingMaximum (1,1) logical = false
end

requireFields(dataset, ["recordings", "pairs", "project_key"]);
requireFields(materialized, ["index", "exploration_run_key"]);

configurations = materialized.index;
cost = vawlume.eda.probeCost(dataset, height(configurations), ...
    WarnAtAnalyses=options.WarnAtAnalyses, ...
    MaximumAnalyses=options.MaximumAnalyses, ...
    AllowExceedingMaximum=options.AllowExceedingMaximum);

agreementSpecPath = resolveAgreementSpec(options);
manifest = emptyManifest();
started = tic;
abandoned = false;

for configurationIndex = 1:height(configurations)
    configuration = configurations(configurationIndex, :);
    for recordingIndex = 1:height(dataset.recordings)
        recording = dataset.recordings(recordingIndex, :);
        [manifest, pairStatuses] = runPairs(conn, dataset, materialized, ...
            configuration, recording, manifest, options);
        manifest = runAgreement(conn, dataset, materialized, configuration, ...
            recording, pairStatuses, manifest, agreementSpecPath, options);
        if options.StopOnFailure && any(manifest.status == "failed")
            abandoned = true;
            break
        end
    end
    if abandoned
        break
    end
end

elapsed = toc(started);
completeness = designCompleteness(manifest, dataset, configurations, abandoned);
exploration = struct(status="not_applied", analysis_run_id=NaN, ...
    run_key=materialized.exploration_run_key);
if options.Apply && ~abandoned
    exploration = recordExploration(conn, dataset, materialized, manifest, ...
        cost, completeness, options);
end

result = struct( ...
    status=overallStatus(options.Apply, abandoned, manifest), ...
    applied=options.Apply, ...
    abandoned=abandoned, ...
    exploration_run_key=materialized.exploration_run_key, ...
    probe_role=options.ProbeRole, ...
    exploration_run=exploration, ...
    project_key=dataset.project_key, ...
    cost=cost, ...
    manifest=manifest, ...
    status_counts=statusCounts(manifest), ...
    design_completeness=completeness, ...
    elapsed_seconds=elapsed, ...
    unit_status_vocabulary=edaUnitStatuses()', ...
    pair_ordering=dataset.pair_ordering, ...
    signed_difference_direction=dataset.signed_difference_direction, ...
    agreement_specification_path=agreementSpecPath, ...
    run_key_template=materialized.run_key_template, ...
    caution=edaCautionNote());
end

% ------------------------------------------------------------- execution ---

function [manifest, statuses] = runPairs(conn, dataset, materialized, ...
    configuration, recording, manifest, options)
pairs = dataset.pairs(dataset.pairs.recording_id == recording.recording_id, :);
statuses = strings(height(pairs), 1);
for index = 1:height(pairs)
    pair = pairs(index, :);
    keys = edaRunKeys(materialized.exploration_run_key, ...
        configuration.configuration_id, recording.recording_id, ...
        [pair.run_a_extractor_key, pair.run_b_extractor_key]);
    [status, detail, analysisId] = applyMatching(conn, recording, pair, ...
        keys.matching, configuration.specification_path, options);
    statuses(index) = status;
    manifest(end + 1, :) = {materialized.exploration_run_key, ...
        configuration.configuration_id, recording.recording_id, ...
        recording.native_recording_id, "matching", pair.extractor_pair_key, ...
        keys.matching, analysisId, status, detail, ...
        configuration.checksum_sha256}; %#ok<AGROW>
end
end

function [status, detail, analysisId] = applyMatching(conn, recording, pair, ...
    runKey, specPath, options)
analysisId = NaN;
try
    outcome = vawlume.matching.compare(conn, ...
        struct(recording_id=recording.recording_id), ...
        struct(run_a=pair.run_a_key, run_b=pair.run_b_key), ...
        struct(run_key=runKey, profile_path=specPath), ...
        RepoRoot=options.RepoRoot, Apply=options.Apply);
catch exception
    status = "failed";
    detail = string(exception.identifier) + ": " + string(exception.message);
    return
end
[status, detail, analysisId] = interpret(outcome, options.Apply);
end

function manifest = runAgreement(conn, dataset, materialized, configuration, ...
    recording, pairStatuses, manifest, agreementSpecPath, options)
keys = edaRunKeys(materialized.exploration_run_key, ...
    configuration.configuration_id, recording.recording_id);
usable = ismember(pairStatuses, ["committed", "reused", "planned"]);
if ~all(usable)
    % Never compose over an incomplete pairwise set. The composer would refuse
    % it, but with a message about missing coverage rather than about the pair
    % that actually failed.
    manifest(end + 1, :) = {materialized.exploration_run_key, ...
        configuration.configuration_id, recording.recording_id, ...
        recording.native_recording_id, "agreement", "", keys.agreement, NaN, ...
        "skipped", "Pairwise set incomplete: " + string(nnz(~usable)) + ...
        " of " + string(numel(pairStatuses)) + " pair(s) did not succeed.", ...
        configuration.checksum_sha256};
    return
end

sources = matchingRunKeys(materialized, configuration, recording, dataset);
analysisId = NaN;
if ~options.Apply
    % Planning cannot compose: the composer resolves its sources from stored
    % analyses, and in a dry run none has been written. Reporting the unit as
    % planned is honest; claiming it was validated would not be.
    status = "planned";
    detail = "Agreement composition is not planned in a dry run because its " + ...
        "source analyses do not exist yet.";
else
    try
        outcome = vawlume.agreement.compose(conn, ...
            struct(recording_id=recording.recording_id), sources, ...
            struct(run_key=keys.agreement, profile_path=agreementSpecPath), ...
            RepoRoot=options.RepoRoot, Apply=true);
        [status, detail, analysisId] = interpret(outcome, true);
    catch exception
        status = "failed";
        detail = string(exception.identifier) + ": " + string(exception.message);
    end
end

manifest(end + 1, :) = {materialized.exploration_run_key, ...
    configuration.configuration_id, recording.recording_id, ...
    recording.native_recording_id, "agreement", "", keys.agreement, ...
    analysisId, status, detail, configuration.checksum_sha256};
end

function value = matchingRunKeys(materialized, configuration, recording, dataset)
pairs = dataset.pairs(dataset.pairs.recording_id == recording.recording_id, :);
value = strings(height(pairs), 1);
for index = 1:height(pairs)
    keys = edaRunKeys(materialized.exploration_run_key, ...
        configuration.configuration_id, recording.recording_id, ...
        [pairs.run_a_extractor_key(index), pairs.run_b_extractor_key(index)]);
    value(index) = keys.matching;
end
end

function [status, detail, analysisId] = interpret(outcome, applied)
analysisId = NaN;
detail = "";
if isfield(outcome, "analysis") && isfield(outcome.analysis, "analysis_run_id")
    analysisId = double(outcome.analysis.analysis_run_id);
end
if isfield(outcome, "has_conflicts") && outcome.has_conflicts
    status = "conflict";
    detail = strjoin(string(outcome.conflicts(:))', " | ");
    return
end
if ~applied
    status = "planned";
    return
end
status = string(outcome.status);
if ~ismember(status, ["committed", "reused"])
    status = "failed";
    detail = "Unexpected apply status '" + string(outcome.status) + "'.";
end
end

% ------------------------------------------------------------ completeness ---

function value = designCompleteness(manifest, dataset, configurations, abandoned)
%DESIGNCOMPLETENESS Whether effect estimates may be computed at all.
%
% Effect estimation assumes every design row was evaluated on the same
% recordings. A probe with a missing unit is an unbalanced design, and an effect
% computed on it is not the quantity it claims to be. This is the machine-
% readable signal the estimation layer checks before computing anything: it is a
% field rather than a warning because a warning can be read past.
expectedAgreement = height(configurations) * height(dataset.recordings);
expectedMatching = expectedAgreement * dataset.pairs_per_recording;
agreement = manifest(manifest.unit_kind == "agreement", :);
matching = manifest(manifest.unit_kind == "matching", :);
succeeded = ["committed", "reused", "planned"];

completeAgreement = nnz(ismember(agreement.status, succeeded));
completeMatching = nnz(ismember(matching.status, succeeded));

% A recording is usable only where EVERY configuration produced an agreement
% analysis. A configuration missing on one recording unbalances the whole
% column, not just that cell.
usableRecordings = zeros(0, 1);
for index = 1:height(dataset.recordings)
    id = dataset.recordings.recording_id(index);
    selected = agreement(agreement.recording_id == id, :);
    if height(selected) == height(configurations) && ...
            all(ismember(selected.status, succeeded))
        usableRecordings(end + 1, 1) = id; %#ok<AGROW>
    end
end

isComplete = ~abandoned && completeAgreement == expectedAgreement && ...
    completeMatching == expectedMatching;
if isComplete
    note = "Every design row was evaluated on every recording, so effect " + ...
        "estimates over this probe rest on a balanced design.";
else
    note = "THIS DESIGN IS INCOMPLETE. " + ...
        string(expectedAgreement - completeAgreement) + " of " + ...
        string(expectedAgreement) + " agreement units and " + ...
        string(expectedMatching - completeMatching) + " of " + ...
        string(expectedMatching) + " matching units are missing. Effect " + ...
        "estimates assume every design row was evaluated on the same " + ...
        "recordings; over this probe they must be refused, or computed on " + ...
        "the balanced subset and labelled as such.";
end

value = struct( ...
    is_complete=isComplete, ...
    abandoned=abandoned, ...
    expected_matching_units=expectedMatching, ...
    completed_matching_units=completeMatching, ...
    expected_agreement_units=expectedAgreement, ...
    completed_agreement_units=completeAgreement, ...
    balanced_recording_ids=usableRecordings', ...
    balanced_recording_count=numel(usableRecordings), ...
    total_recording_count=height(dataset.recordings), ...
    configuration_count=height(configurations), ...
    note=note);
end

% -------------------------------------------------------------- provenance ---

function exploration = recordExploration(conn, dataset, materialized, ...
    manifest, cost, completeness, options)
%RECORDEXPLORATION One analysis_runs row linking the probe's agreement analyses.
%
% The design and resolution records are registered as a config profile version
% so the run's automatic choices are recoverable from the database rather than
% only from this session. Nothing here duplicates what
% analysis_run_extraction_inputs and analysis_run_profiles already hold on the
% individual analyses: a second copy is a second thing that can disagree.
%
% No final-threshold field exists, and none is added. The workflow selects no
% threshold, so a column for one would invite exactly the reading the conceptual
% specification forbids.
runKey = materialized.exploration_run_key;
existing = fetch(conn, "SELECT analysis_run_id, run_type, status " + ...
    "FROM analysis_runs WHERE project_id=" + string(dataset.project_id) + ...
    " AND run_key=" + edaSqlText(runKey));
if height(existing) == 1
    if edaPresentText(existing.run_type(1)) ~= "consilience_exploration"
        exploration = struct(status="conflict", ...
            analysis_run_id=double(existing.analysis_run_id(1)), ...
            run_key=runKey, ...
            detail="Run key exists with run_type '" + ...
                edaPresentText(existing.run_type(1)) + "'.");
        return
    end
    analysisId = double(existing.analysis_run_id(1));
    action = "reused";
else
    execute(conn, "INSERT INTO analysis_runs(project_id, run_type, run_key, " + ...
        "run_label, status, completed_at_utc) VALUES(" + ...
        string(dataset.project_id) + ", 'consilience_exploration', " + ...
        edaSqlText(runKey) + ", " + ...
        edaSqlText("Consilience exploration screen") + ", 'completed', " + ...
        "strftime('%Y-%m-%dT%H:%M:%fZ','now'))");
    rows = fetch(conn, "SELECT analysis_run_id FROM analysis_runs " + ...
        "WHERE project_id=" + string(dataset.project_id) + ...
        " AND run_key=" + edaSqlText(runKey));
    analysisId = double(rows.analysis_run_id(1));
    action = "created";
end

linked = linkSources(conn, analysisId, manifest, options.ProbeRole);
profile = registerDesignRecord(conn, dataset, materialized, analysisId, ...
    cost, completeness, options);

exploration = struct( ...
    status=action, ...
    analysis_run_id=analysisId, ...
    run_key=runKey, ...
    run_type="consilience_exploration", ...
    linked_source_analyses=linked, ...
    design_profile=profile, ...
    detail="");
end

function linked = linkSources(conn, analysisId, manifest, probeRole)
%LINKSOURCES Attach this probe's agreement analyses to the exploration run.
%
% The dependency role carries the probe role, so a reader can tell the two
% probes of one exploration run apart without re-deriving which configurations
% and recordings belonged to which.
%
% analysis_run_sources is keyed on (analysis_run_id, source_analysis_run_id), so
% one analysis carries ONE role. When the two probes share a configuration and a
% recording the analysis is genuinely the same one and is reused rather than
% rewritten, and it keeps the role of the probe that produced it first. That is
% truthful but incomplete: the membership a reader wants is recoverable from each
% probe's own design record, which lists its configurations and recordings.
agreement = manifest(manifest.unit_kind == "agreement" & ...
    ismember(manifest.status, ["committed", "reused"]), :);
linked = 0;
for index = 1:height(agreement)
    sourceId = agreement.analysis_run_id(index);
    if ~isfinite(sourceId) || sourceId == analysisId
        continue
    end
    existing = fetch(conn, "SELECT COUNT(*) AS n FROM analysis_run_sources " + ...
        "WHERE analysis_run_id=" + string(analysisId) + ...
        " AND source_analysis_run_id=" + string(sourceId));
    if double(existing.n(1)) > 0
        continue
    end
    execute(conn, "INSERT INTO analysis_run_sources(analysis_run_id, " + ...
        "source_analysis_run_id, dependency_role) VALUES(" + ...
        string(analysisId) + ", " + string(sourceId) + ", " + ...
        edaSqlText("exploration_agreement_" + probeRole) + ")");
    linked = linked + 1;
end
end

function profile = registerDesignRecord(conn, dataset, materialized, ...
    analysisId, cost, completeness, options)
%REGISTERDESIGNRECORD The design and its resolution, as a checksum-bearing version.
%
% profile_kind 'analysis_settings' and content_format 'json' are both already in
% the schema's vocabularies, so this needs no schema change.
payload = designPayload(materialized, dataset, cost, completeness, ...
    options.ProbeRole);
directory = fullfile(materialized.output_root, "exploration", ...
    materialized.exploration_run_key);
if ~isfolder(directory)
    mkdir(directory);
end
% The role is part of the filename and of the version label. Two probes of one
% exploration run share a run key - which is what makes an analysis common to
% both reused rather than duplicated - so an unqualified name would have the
% subset probe overwrite the whole-dataset probe's design record on disk and
% collide with it on config_profile_versions' UNIQUE(profile_id, version_label).
% The label is what a reader reads, so it carries the role rather than a counter.
label = materialized.exploration_run_key + "#" + options.ProbeRole;
path = fullfile(directory, "exploration_design_record_" + ...
    options.ProbeRole + ".json");
writeJson(path, payload);
checksum = edaSha256OfFile(path);

profileKey = "vawlume.eda.exploration_design." + ...
    materialized.exploration_run_key;
profileId = ensureProfile(conn, dataset.project_id, profileKey);
versionId = ensureVersion(conn, profileId, label, path, checksum, options);
ensureAssignment(conn, analysisId, versionId);

profile = struct(profile_key=profileKey, profile_id=profileId, ...
    profile_version_id=versionId, version_label=label, ...
    probe_role=options.ProbeRole, ...
    assignment_role="exploration_design", content_uri=string(path), ...
    checksum_sha256=checksum);
end

function id = ensureProfile(conn, projectId, profileKey)
rows = fetch(conn, "SELECT profile_id FROM config_profiles WHERE project_id=" + ...
    string(projectId) + " AND profile_key=" + edaSqlText(profileKey));
if height(rows) == 1
    id = double(rows.profile_id(1));
    return
end
execute(conn, "INSERT INTO config_profiles(project_id, profile_key, " + ...
    "profile_name, profile_kind) VALUES(" + string(projectId) + ", " + ...
    edaSqlText(profileKey) + ", " + ...
    edaSqlText("Consilience exploration design record") + ...
    ", 'analysis_settings')");
rows = fetch(conn, "SELECT profile_id FROM config_profiles WHERE project_id=" + ...
    string(projectId) + " AND profile_key=" + edaSqlText(profileKey));
id = double(rows.profile_id(1));
end

function id = ensureVersion(conn, profileId, versionLabel, path, checksum, options)
rows = fetch(conn, "SELECT profile_version_id, " + ...
    "IFNULL(checksum_sha256,'') AS checksum_sha256 " + ...
    "FROM config_profile_versions WHERE profile_id=" + string(profileId) + ...
    " AND version_label=" + edaSqlText(versionLabel));
if height(rows) == 1
    id = double(rows.profile_version_id(1));
    return
end
execute(conn, "INSERT INTO config_profile_versions(profile_id, " + ...
    "version_label, content_format, content_uri, checksum_sha256) VALUES(" + ...
    string(profileId) + ", " + edaSqlText(versionLabel) + ", 'json', " + ...
    edaSqlText(portableUri(path, options.RepoRoot)) + ", " + ...
    edaSqlText(checksum) + ")");
rows = fetch(conn, "SELECT profile_version_id FROM config_profile_versions " + ...
    "WHERE profile_id=" + string(profileId) + ...
    " AND version_label=" + edaSqlText(versionLabel));
id = double(rows.profile_version_id(1));
end

function ensureAssignment(conn, analysisId, versionId)
rows = fetch(conn, "SELECT COUNT(*) AS n FROM analysis_run_profiles " + ...
    "WHERE analysis_run_id=" + string(analysisId) + ...
    " AND profile_version_id=" + string(versionId) + ...
    " AND assignment_role='exploration_design'");
if double(rows.n(1)) > 0
    return
end
execute(conn, "INSERT INTO analysis_run_profiles(analysis_run_id, " + ...
    "profile_version_id, assignment_role) VALUES(" + string(analysisId) + ...
    ", " + string(versionId) + ", 'exploration_design')");
end

function value = designPayload(materialized, dataset, cost, completeness, probeRole)
provenance = materialized.provenance;
value = struct( ...
    record_version="1.0", ...
    exploration_run_key=materialized.exploration_run_key, ...
    probe_role=probeRole, ...
    project_key=dataset.project_key, ...
    recording_ids=dataset.recordings.recording_id', ...
    extractor_keys=dataset.extractor_keys, ...
    pair_ordering=dataset.pair_ordering, ...
    signed_difference_direction=dataset.signed_difference_direction, ...
    design_type=provenance.design_type, ...
    configuration_count=provenance.configuration_count, ...
    factor_count=provenance.factor_count, ...
    fraction_exponent=provenance.fraction_exponent, ...
    generators=provenance.generators, ...
    defining_relation=provenance.defining_relation, ...
    resolution_label=provenance.resolution_label, ...
    alias_note=provenance.alias_note, ...
    decision_path=provenance.decision_path, ...
    configuration_ids=materialized.index.configuration_id', ...
    specification_checksums=materialized.index.checksum_sha256', ...
    base_specification=provenance.base_specification, ...
    probe_resolution=strippedResolution(provenance.probe_resolution), ...
    estimated_analyses=cost.total_analyses, ...
    design_complete=completeness.is_complete, ...
    caution=edaCautionNote());
end

function value = strippedResolution(resolution)
%STRIPPEDRESOLUTION The resolver's choices, without the tables that repeat them.
value = struct( ...
    seed=resolution.seed, ...
    seed_source=resolution.seed_source, ...
    seed_basis=resolution.seed_basis, ...
    active_factor_names=resolution.active_factor_names, ...
    inactive_factor_names=resolution.inactive_factor_names, ...
    factor_name=resolution.factors.factor_name', ...
    is_active=resolution.factors.is_active', ...
    inactive_reason=resolution.factors.inactive_reason', ...
    low_value=resolution.factors.low_value', ...
    high_value=resolution.factors.high_value', ...
    low_quantile=resolution.factors.low_quantile', ...
    high_quantile=resolution.factors.high_quantile', ...
    value_source=resolution.factors.value_source', ...
    strictness_direction=resolution.factors.strictness_direction', ...
    reference_comparison=resolution.factors.reference_comparison');
end

% ---------------------------------------------------------------- plumbing ---

function path = resolveAgreementSpec(options)
if strlength(options.AgreementSpecPath) > 0
    path = options.AgreementSpecPath;
else
    root = options.RepoRoot;
    if strlength(root) == 0
        root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
    end
    path = fullfile(root, "config", "07_agreement_profiles", ...
        "prototype_multi_extractor_agreement_spec.json");
end
path = string(path);
if ~isfile(path)
    error("vawlume:eda:AgreementSpecificationNotFound", ...
        "Agreement policy does not exist: %s", path);
end
end

function writeJson(path, payload)
text = jsonencode(payload, PrettyPrint=true);
fileId = fopen(path, "wb");
if fileId < 0
    error("vawlume:eda:DesignRecordUnwritable", ...
        "Could not write the exploration design record: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, unicode2native(text, "UTF-8"), "uint8");
delete(cleaner);
end

function value = portableUri(path, repoRoot)
value = string(path);
if strlength(repoRoot) == 0
    return
end
root = strip(replace(string(repoRoot), "\", "/"), "right", "/") + "/";
candidate = replace(value, "\", "/");
if startsWith(lower(candidate), lower(root))
    value = extractAfter(candidate, strlength(root));
end
end

function value = statusCounts(manifest)
value = struct();
for status = edaUnitStatuses()'
    value.(status) = nnz(manifest.status == status);
end
end

function value = overallStatus(applied, abandoned, manifest)
if abandoned
    value = "abandoned";
elseif ~applied
    value = "planned";
elseif any(ismember(manifest.status, ["failed", "conflict", "skipped"]))
    value = "completed_with_problems";
else
    value = "completed";
end
end

function value = emptyManifest()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), ...
    VariableNames=["exploration_run_key", "configuration_id", "recording_id", ...
    "native_recording_id", "unit_kind", "extractor_pair_key", "run_key", ...
    "analysis_run_id", "status", "detail", "specification_checksum_sha256"]);
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:RunnerInputInvalid", ...
        "A required input is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
