function result = runExploration(conn, selector, options)
%RUNEXPLORATION Run the extractor-consilience exploration workflow end to end.
%
% RESULT = vawlume.eda.RUNEXPLORATION(CONN, SELECTOR) carries one dataset from
% the reference configuration through full-dataset diagnostics, a bounded
% whole-dataset screen, a richer seeded-subset probe, probe concordance, exact
% support-pattern characterization and a representative spectrogram gallery, and
% writes the tables, figures, example index and provenance beside each other.
%
% SELECTOR is vawlume.eda.resolveDataset's selector:
%
%   struct(project_key="my-project")
%   struct(project_key="...", recording_ids=[1 2 3])
%
% Name-value options:
%   Options          a vawlume.eda.explorationOptions struct - the light
%                    scientific configuration: enabled, seed, analysis budget,
%                    subset size, threshold overrides, disabled factors
%   Stages           which stages to run; "all" by default. Prerequisites of a
%                    requested stage are included automatically
%   Apply            write analyses, default true. Apply=false plans every
%                    design and reports its cost: no analysis, no export and no
%                    provenance record is written. The generated matching
%                    specifications still are, under the output root, because
%                    they are what the reported cost is a cost of
%   RepoRoot         repository root
%   OutputRoot       where generated specifications and exports are written;
%                    defaults to a tempdir-based workspace
%   SourceRoot       root for resolving recording audio, for the gallery
%   Figures          render and export the figure families, default true
%   Overwrite        replace existing exports, default false
%   Print            print stage progress and cost, default true
%
% IT ORCHESTRATES; IT DOES NOT COMPUTE. Every stage is one or more calls to a
% function that owns that calculation. This function sequences them, threads
% options, reports cost and progress, and attaches the context a failure needs.
% It defines no metric, estimates no effect, selects no threshold, and computes
% no summary of its own - if a number appears in RESULT, some other function
% produced it.
%
% THE REFERENCE CONFIGURATION RUNS FIRST, and that ordering is not cosmetic. The
% diagnostic battery reads stored candidate pairs, and probe values are anchored
% on quantiles of those same observed metrics, so both require that some matching
% analysis has already been applied to this dataset. Applying the reference
% configuration first supplies them, and it is the same run the support-pattern
% characterization and the example gallery are computed at. A caller who already
% has matching analyses can point the diagnostics elsewhere with
% DiagnosticAnalyses.
%
% STAGES ARE INDIVIDUALLY RUNNABLE. Stages="diagnostics" runs the dataset,
% reference and diagnostic stages and stops; it never builds a design or executes
% a probe. Every stage a run did not perform appears in RESULT.stages with the
% reason, so a partial result cannot be mistaken for a complete one.
%
% A STAGE FAILURE CARRIES ITS FRAME. A failure is re-raised as
% vawlume:eda:ExplorationStageFailed naming the stage, the project, and the
% exploration run, with the original exception as its cause - rather than a
% low-level message from three layers down with nothing to locate it.
%
% NOTHING HERE OPTIMIZES. No configuration is selected, ranked, or recommended,
% no objective is maximized, and no composite score is formed. The deliverable is
% several transparent views of how correspondence responds to matching
% assumptions in one dataset.

arguments
    conn
    selector (1,1) struct
    options.Options (1,1) struct = vawlume.eda.explorationOptions()
    options.Stages (1,:) string = "all"
    options.Apply (1,1) logical = true
    options.RepoRoot (1,1) string = ""
    options.OutputRoot (1,1) string = ""
    options.SourceRoot (1,1) string = ""
    options.ExplorationRunKey (1,1) string = ""
    options.DiagnosticAnalyses = []
    options.WarnAtConfigurations (1,1) double {mustBePositive} = 32
    options.MaximumConfigurations (1,1) double {mustBePositive} = 128
    options.SubsetWarnAtConfigurations (1,1) double {mustBePositive} = 64
    options.SubsetMaximumConfigurations (1,1) double {mustBePositive} = 256
    options.WarnAtAnalyses (1,1) double {mustBePositive} = 250
    options.MaximumAnalyses (1,1) double {mustBePositive} = 2500
    options.AllowExceedingMaximum (1,1) logical = false
    options.OnIncompleteDesign (1,1) string ...
        {mustBeMember(options.OnIncompleteDesign, ["refuse", "label"])} = "refuse"
    options.ExamplesPerPattern (1,1) double = 3
    options.ExampleRecordingId (1,1) double = NaN
    options.Figures (1,1) logical = true
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
    options.Overwrite (1,1) logical = false
    options.Print (1,1) logical = true
end

explorationOptions = vawlume.eda.explorationOptions(options.Options);
requested = edaExplorationStages(options.Stages);

% The light configuration surface offers an analysis budget, so it has to bind
% something. It is the ceiling on ANALYSES rather than on configurations,
% because that is the one a user asking for a budget means: the work, not the
% size of the design. A field that looked configured and changed nothing would
% be the same defect the option validator refuses an unknown field to prevent.
budgetSource = "default";
if isfinite(explorationOptions.analysis_budget)
    options.MaximumAnalyses = explorationOptions.analysis_budget;
    budgetSource = "user";
end

result = struct();
result.status = "running";
result.applied = options.Apply;
result.exploration_run_key = "";
result.output_root = "";
result.project_key = "";
result.requested_stages = requested;
result.stage_vocabulary = edaExplorationStages("all");
result.options = explorationOptions;
result.analysis_budget = struct( ...
    maximum_analyses=options.MaximumAnalyses, ...
    warn_at_analyses=options.WarnAtAnalyses, ...
    source=budgetSource, ...
    bounds="analyses, not configurations");
result.warnings = strings(0, 1);
result.caution = edaCautionNote();
state = struct();
stages = emptyStageTable();

if ~explorationOptions.enabled
    result.status = "disabled";
    result.stages = stages;
    result.disabled_reason = "explorationOptions.enabled is false, so no " + ...
        "stage was run. Nothing was read and nothing was written.";
    printLine(options, "Exploration is disabled by configuration; no stage ran.");
    return
end

context = struct(project="(unresolved)", run="(unassigned)");

% ---------------------------------------------------------------- dataset ---
[result, stages, state] = stage(result, stages, state, "dataset", requested, ...
    options, context, @() datasetStage(conn, selector, options));
if isfield(state, "dataset")
    result.dataset = state.dataset;
    result.project_key = state.dataset.project_key;
    context.project = state.dataset.project_key;
    printLine(options, "Dataset: %d recording(s), %d extractor(s), %d pair(s) " + ...
        "per recording.", state.dataset.recording_count, ...
        state.dataset.extractor_count, state.dataset.pairs_per_recording);
    if height(state.dataset.excluded_recordings) > 0
        result.warnings(end + 1, 1) = string(height( ...
            state.dataset.excluded_recordings)) + " recording(s) were " + ...
            "excluded from the dataset; see dataset.excluded_recordings. An " + ...
            "exclusion narrows what every later stage can say.";
    end
end

% -------------------------------------------------------------- reference ---
[result, stages, state] = stage(result, stages, state, "reference", requested, ...
    options, context, @() referenceStage(conn, state, options));
if isfield(state, "reference")
    result.reference = state.reference;
    result.exploration_run_key = state.reference.materialized.exploration_run_key;
    result.output_root = state.reference.output_root;
    context.run = result.exploration_run_key;
end

% ------------------------------------------------------------ diagnostics ---
[result, stages, state] = stage(result, stages, state, "diagnostics", ...
    requested, options, context, @() diagnosticsStage(conn, state, options));
if isfield(state, "diagnostics")
    result.diagnostics = state.diagnostics;
end

% -------------------------------------------------------------- probe ------
[result, stages, state] = stage(result, stages, state, "probe", requested, ...
    options, context, @() probeStage(state, explorationOptions));
if isfield(state, "probe")
    result.probe = state.probe;
    result.warnings = [result.warnings; string(state.probe.resolution.warnings(:))];
end

% ----------------------------------------------------------------- screen ---
[result, stages, state] = stage(result, stages, state, "screen", requested, ...
    options, context, @() screenStage(conn, state, options));
if isfield(state, "screen")
    result.screen = state.screen;
end

% ----------------------------------------------------------------- subset ---
[result, stages, state] = stage(result, stages, state, "subset", requested, ...
    options, context, @() subsetStage(conn, state, options));
if isfield(state, "subset")
    result.subset = state.subset;
end

% ------------------------------------------------------------ concordance ---
[result, stages, state] = stage(result, stages, state, "concordance", ...
    requested, options, context, @() concordanceStage(state));
if isfield(state, "concordance")
    result.concordance = state.concordance;
end

% -------------------------------------------------------- support patterns ---
[result, stages, state] = stage(result, stages, state, "support_patterns", ...
    requested, options, context, @() supportPatternStage(conn, state));
if isfield(state, "support_patterns")
    result.support_patterns = state.support_patterns;
end

% --------------------------------------------------------------- examples ---
[result, stages, state] = stage(result, stages, state, "examples", requested, ...
    options, context, @() exampleStage(conn, state, options));
if isfield(state, "examples")
    result.examples = state.examples;
end

% ---------------------------------------------------------------- exports ---
[result, stages, state] = stage(result, stages, state, "exports", requested, ...
    options, context, @() exportStage(state, options, result));
if isfield(state, "exports")
    result.exports = state.exports;
end

result.stages = stages;
result.status = overallStatus(stages, options.Apply);
result.provenance = provenanceRecord(result, state, options);
if isfield(state, "exports")
    % Written last, because the record accounts for the whole run - including
    % which stages ran, which is not known until they have.
    result.exports.provenance_path = writeProvenance(state.exports.root, ...
        result.provenance, options);
end
printSummary(options, result);
end

% =========================================================================== %
% Stage sequencing
% =========================================================================== %

function [result, stages, state] = stage(result, stages, state, name, ...
    requested, options, context, body)
%STAGE Run one stage, or record precisely why it did not run.
%
% A skipped stage gets a row with its reason for the same reason an absent
% support pattern gets a zero row: an omitted stage and a stage that ran and
% produced nothing look identical in a result struct and mean different things.
if ~ismember(name, requested)
    stages = addStage(stages, name, "not_requested", ...
        "The stage was not among the requested stages.", 0);
    return
end

[ready, reason] = prerequisitesMet(name, state, options);
if ~ready
    stages = addStage(stages, name, "skipped", reason, 0);
    result.warnings(end + 1, 1) = "Stage '" + name + "' was skipped: " + reason;
    printLine(options, "[skip] %-17s %s", name, reason);
    return
end

printLine(options, "[run ] %s", name);
started = tic;
try
    value = body();
catch exception
    failure = MException("vawlume:eda:ExplorationStageFailed", ...
        "Exploration stage '%s' failed on project '%s' (exploration run " + ...
        "'%s'): %s", name, context.project, context.run, exception.message);
    throw(addCause(failure, exception));
end
elapsed = toc(started);
state.(name) = value;
stages = addStage(stages, name, "completed", "", elapsed);
printLine(options, "[done] %-17s %.1f s", name, elapsed);
end

function [ready, reason] = prerequisitesMet(name, state, options)
ready = true;
reason = "";
required = edaExplorationStages("prerequisites", name);
missingNames = required(~isfield(state, required));
if ~isempty(missingNames)
    ready = false;
    reason = "requires stage(s) " + strjoin(missingNames, ", ") + ...
        ", which did not run.";
    return
end
if ~options.Apply && name == "diagnostics" && isempty(options.DiagnosticAnalyses)
    % A dry run over a database nothing has matched yet has no candidate pair to
    % read, so it prices the reference run and stops. A caller who names an
    % analysis source with DiagnosticAnalyses is asserting that one exists, and
    % the diagnostics, the probe values and both designs can then all be planned
    % without writing anything.
    ready = false;
    reason = "Apply=false and no DiagnosticAnalyses was named, so no " + ...
        "candidate pair is available to diagnose.";
    return
end
if ~options.Apply && ismember(name, ["concordance", "support_patterns", ...
        "examples"])
    ready = false;
    reason = "Apply=false, so no analysis was written and this stage has " + ...
        "nothing stored to read.";
    return
end
if ~options.Apply && name == "exports"
    % A plan writes nothing at all. Exporting a plan's design tables would also
    % put files where the real run's exports belong, and the real run would then
    % refuse to overwrite them - so a dry run would break the run it was meant
    % to price.
    ready = false;
    reason = "Apply=false, so the run wrote nothing and there is nothing to " + ...
        "export.";
end
end

function stages = emptyStageTable()
stages = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    VariableNames=["stage", "status", "reason", "elapsed_seconds"]);
end

function stages = addStage(stages, name, status, reason, elapsed)
stages(end + 1, :) = {string(name), string(status), string(reason), elapsed};
end

function value = overallStatus(stages, applied)
if any(stages.status == "failed")
    value = "failed";
elseif ~applied
    value = "planned";
elseif any(stages.status == "skipped")
    value = "completed_with_skips";
else
    value = "completed";
end
end

% =========================================================================== %
% Stages
% =========================================================================== %

function value = datasetStage(conn, selector, options)
value = vawlume.eda.resolveDataset(conn, selector);
if value.recording_count == 0
    error("vawlume:eda:ExplorationDatasetEmpty", ...
        "No usable recording remains after validation, so there is " + ...
        "nothing to explore.");
end
if options.Print && height(value.excluded_recordings) > 0
    disp(value.excluded_recordings);
end
end

function value = referenceStage(conn, state, options)
%REFERENCESTAGE Apply the tracked reference configuration.
%
% This is the anchor for everything that follows: the candidate pairs the
% diagnostics read, the distributions the probe values are anchored on, and the
% agreement analyses the support-pattern profile and the gallery are computed at.
reference = vawlume.eda.referenceConfiguration(RepoRoot=options.RepoRoot);
design = vawlume.eda.referenceDesign(reference);
materialized = materialize(design, options, options.ExplorationRunKey);
cost = reportCost(state.dataset, design.configuration_count, options, ...
    "reference configuration");
run = vawlume.eda.runScreen(conn, state.dataset, materialized, ...
    RepoRoot=options.RepoRoot, Apply=options.Apply, ProbeRole="reference", ...
    WarnAtAnalyses=options.WarnAtAnalyses, ...
    MaximumAnalyses=options.MaximumAnalyses, ...
    AllowExceedingMaximum=options.AllowExceedingMaximum);

value = struct();
value.configuration = reference;
value.design = design;
value.materialized = materialized;
value.cost = cost;
value.run = run;
value.configuration_id = design.configurations.configuration_id(1);
value.output_root = outputRoot(options, materialized);
value.matching_run_keys = usableRunKeys(run.manifest, "matching");
value.agreement = usableUnits(run.manifest, "agreement");
value.identity_line = reference.identity_line;
value.calibration_note = reference.calibration_note;
end

function value = diagnosticsStage(conn, state, options)
refs = options.DiagnosticAnalyses;
source = "the reference configuration's matching analyses";
if isempty(refs)
    refs = state.reference.matching_run_keys;
else
    source = "an explicitly supplied analysis selection";
end
if isempty(refs)
    error("vawlume:eda:ExplorationDiagnosticsUnavailable", ...
        "No usable matching analysis is available, so the candidate-metric " + ...
        "surface would be empty. The diagnostic battery reads stored " + ...
        "candidate pairs; it does not run matching.");
end
surface = vawlume.eda.candidateMetrics(conn, refs, RepoRoot=options.RepoRoot);
distributions = vawlume.eda.metricDistributions(surface);
dependencies = vawlume.eda.metricDependencies(surface);

value = struct();
value.analysis_source = source;
value.surface = surface;
value.distributions = distributions;
value.dependencies = dependencies;
end

function value = probeStage(state, explorationOptions)
resolution = vawlume.eda.probeParameters(state.diagnostics.surface, ...
    explorationOptions, ...
    ReferenceSpecPath=state.reference.configuration.specification_path, ...
    RedundancyFindings=state.diagnostics.dependencies.redundancy);

value = struct();
value.resolution = resolution;
value.seed = resolution.seed;
value.active_factor_names = resolution.active_factor_names;
end

function value = screenStage(conn, state, options)
resolution = state.probe.resolution;
design = vawlume.eda.screeningDesign(resolution, ...
    WarnAtConfigurations=options.WarnAtConfigurations, ...
    MaximumConfigurations=options.MaximumConfigurations);
cost = reportCost(state.dataset, design.configuration_count, options, ...
    "whole-dataset screen");
materialized = materialize(design, options, ...
    state.reference.materialized.exploration_run_key);
run = vawlume.eda.runScreen(conn, state.dataset, materialized, ...
    RepoRoot=options.RepoRoot, Apply=options.Apply, ...
    ProbeRole="whole_dataset", WarnAtAnalyses=options.WarnAtAnalyses, ...
    MaximumAnalyses=options.MaximumAnalyses, ...
    AllowExceedingMaximum=options.AllowExceedingMaximum);

value = struct();
value.design = design;
value.cost = cost;
value.materialized = materialized;
value.run = run;
if ~options.Apply
    return
end
value.responses = vawlume.eda.screenResponses(conn, run, design);
value.effects = vawlume.eda.mainEffects(value.responses, design, ...
    OnIncompleteDesign=options.OnIncompleteDesign);
value.leverage = vawlume.eda.leverageCategories(value.effects, design, ...
    Resolution=resolution);
end

function value = subsetStage(conn, state, options)
%SUBSETSTAGE The second sensitivity view, on a seeded sample of recordings.
%
% The subset is where extra search budget is spent; the full dataset gets the
% compact screen. Both probes share one exploration run key, so a configuration
% common to both is one analysis rather than two executions of the same thing.
resolution = state.probe.resolution;
strata = vawlume.eda.resolveStrata(conn, ...
    state.dataset.recordings.recording_id);
subset = vawlume.eda.sampleRecordings(strata, Seed=state.probe.seed, ...
    Size=sizeOverride(resolution));
subsetDataset = vawlume.eda.resolveDataset(conn, ...
    struct(project_key=state.dataset.project_key, ...
    recording_ids=subset.selected_recording_ids));
design = vawlume.eda.subsetDesign(resolution, state.screen.design, ...
    subsetDataset, Subset=subset, ...
    WarnAtConfigurations=options.SubsetWarnAtConfigurations, ...
    MaximumConfigurations=options.SubsetMaximumConfigurations);
cost = reportCost(subsetDataset, design.configuration_count, options, ...
    "richer subset probe");
materialized = materialize(design, options, ...
    state.reference.materialized.exploration_run_key);
run = vawlume.eda.runScreen(conn, subsetDataset, materialized, ...
    RepoRoot=options.RepoRoot, Apply=options.Apply, ProbeRole="subset", ...
    WarnAtAnalyses=options.WarnAtAnalyses, ...
    MaximumAnalyses=options.MaximumAnalyses, ...
    AllowExceedingMaximum=options.AllowExceedingMaximum);

value = struct();
value.strata = strata;
value.subset = subset;
value.dataset = subsetDataset;
value.design = design;
value.cost = cost;
value.materialized = materialized;
value.run = run;
if ~options.Apply
    return
end
value.responses = vawlume.eda.screenResponses(conn, run, design);
value.effects = vawlume.eda.mainEffects(value.responses, design, ...
    OnIncompleteDesign=options.OnIncompleteDesign);
value.leverage = vawlume.eda.leverageCategories(value.effects, design, ...
    Resolution=resolution);
end

function value = concordanceStage(state)
value = vawlume.eda.probeConcordance(state.screen.leverage, ...
    state.subset.leverage, ScreenResponses=state.screen.responses, ...
    SubsetResponses=state.subset.responses);
end

function value = supportPatternStage(conn, state)
%SUPPORTPATTERNSTAGE Characterize exact support patterns at the reference.
%
% The agreement layer is recording-scoped, so a reference run over R recordings
% produces R agreement analyses and the profiler takes one at a time. Every one
% is profiled and reported under its own recording; they are never pooled here,
% because pooling them would be a calculation this layer does not own.
agreement = state.reference.agreement;
if height(agreement) == 0
    error("vawlume:eda:ExplorationSupportPatternsUnavailable", ...
        "The reference run produced no usable agreement analysis, so there " + ...
        "is no population to characterize.");
end
threshold = struct([]);
if isfield(state, "concordance")
    threshold = state.concordance;
end

profiles = cell(height(agreement), 1);
recordingIds = agreement.recording_id;
groupCounts = zeros(height(agreement), 1);
for index = 1:height(agreement)
    profiles{index} = vawlume.eda.supportPatternProfile(conn, ...
        struct(run_key=agreement.run_key(index)), ...
        state.reference.configuration, ThresholdContext=threshold);
    groupCounts(index) = sum(profiles{index}.patterns.group_count);
end

[~, primaryIndex] = max(groupCounts);
value = struct();
value.profiles = profiles;
value.recording_ids = recordingIds;
value.group_counts = groupCounts;
value.index = table(recordingIds, agreement.native_recording_id, ...
    agreement.run_key, groupCounts, ...
    VariableNames=["recording_id", "native_recording_id", ...
    "agreement_run_key", "group_count"]);
value.primary_index = primaryIndex;
value.primary_recording_id = recordingIds(primaryIndex);
value.primary = profiles{primaryIndex};
value.comparable_features = vawlume.eda.crossPatternComparison(value.primary);
value.scope_note = "The agreement layer is recording-scoped, so one profile " + ...
    "exists per recording and they are reported separately rather than " + ...
    "pooled. `primary` is the profile with the most groups, ties broken by " + ...
    "the first such recording; the figures are drawn from it and name it.";
end

function value = exampleStage(conn, state, options)
agreement = state.reference.agreement;
recordingId = agreement.recording_id(1);
if isfield(state, "support_patterns")
    recordingId = state.support_patterns.primary_recording_id;
end
if isfinite(options.ExampleRecordingId)
    recordingId = options.ExampleRecordingId;
end
selected = agreement(agreement.recording_id == recordingId, :);
if height(selected) == 0
    error("vawlume:eda:ExplorationExampleRecordingUnavailable", ...
        "Recording %g has no usable agreement analysis in the reference " + ...
        "run, so no example can be drawn from it. Recordings with one: %s.", ...
        recordingId, strjoin(string(agreement.recording_id(:))', ", "));
end
sample = vawlume.eda.sampleExamples(conn, ...
    struct(run_key=selected.run_key(1)), state.reference.configuration, ...
    Seed=state.probe.seed, TargetPerPattern=options.ExamplesPerPattern);

galleryDirectory = fullfile(state.reference.output_root, "gallery");
gallery = vawlume.eda.exportExampleGallery(conn, sample, galleryDirectory, ...
    ExplorationRunKey=state.reference.materialized.exploration_run_key, ...
    ReferenceConfigurationId=state.reference.configuration_id, ...
    ProjectKey=state.dataset.project_key, SourceRoot=options.SourceRoot, ...
    ResolutionDpi=options.ResolutionDpi, Overwrite=options.Overwrite);

value = struct();
value.recording_id = recordingId;
value.agreement_run_key = selected.run_key(1);
value.sample = sample;
value.gallery = gallery;
end

function value = exportStage(state, options, result)
root = exportRoot(state, options);
tablesRoot = fullfile(root, "tables");
figuresRoot = fullfile(root, "figures");
provenance = exportProvenance(state, result);

exports = emptyExportTable();
exports = exportTables(exports, state, tablesRoot, provenance, options);
figures = emptyExportTable();
if options.Figures
    figures = exportFigures(figures, state, figuresRoot, options);
end

value = struct();
value.root = string(root);
value.tables_root = string(tablesRoot);
value.figures_root = string(figuresRoot);
value.tables = exports;
value.figures = figures;
value.table_provenance = provenance;
value.provenance_path = "";
value.gallery_directory = galleryDirectory(state);
value.caution = edaCautionNote();
end

% =========================================================================== %
% Export helpers
% =========================================================================== %

function exports = exportTables(exports, state, root, provenance, options)
if isfield(state, "diagnostics")
    exports = writeOne(exports, root, "metric_distributions", ...
        state.diagnostics.distributions.distributions, provenance, options);
    exports = writeOne(exports, root, "metric_redundancy", ...
        state.diagnostics.dependencies.redundancy, provenance, options);
end
if isfield(state, "probe")
    exports = writeOne(exports, root, "probe_factors", ...
        state.probe.resolution.factors, provenance, options);
end
if isfield(state, "screen")
    exports = writeOne(exports, root, "screen_configurations", ...
        state.screen.design.configurations, provenance, options);
    exports = writeOne(exports, root, "screen_alias_table", ...
        state.screen.design.alias.alias_table, provenance, options);
    if isfield(state.screen, "responses")
        exports = writeOne(exports, root, "screen_responses", ...
            state.screen.responses.responses, provenance, options);
        exports = writeOne(exports, root, "screen_effects", ...
            state.screen.effects.effects, provenance, options);
        exports = writeOne(exports, root, "screen_leverage", ...
            state.screen.leverage.categories, provenance, options);
    end
end
if isfield(state, "subset")
    exports = writeOne(exports, root, "subset_allocation", ...
        state.subset.subset.allocation, provenance, options);
    exports = writeOne(exports, root, "subset_fields_considered", ...
        state.subset.subset.fields_considered, provenance, options);
    exports = writeOne(exports, root, "subset_configurations", ...
        state.subset.design.configurations, provenance, options);
    if isfield(state.subset, "responses")
        exports = writeOne(exports, root, "subset_responses", ...
            state.subset.responses.responses, provenance, options);
        exports = writeOne(exports, root, "subset_effects", ...
            state.subset.effects.effects, provenance, options);
        exports = writeOne(exports, root, "subset_leverage", ...
            state.subset.leverage.categories, provenance, options);
    end
end
if isfield(state, "concordance")
    exports = writeOne(exports, root, "probe_concordance", ...
        state.concordance.comparison, provenance, options);
    exports = writeOne(exports, root, "probe_concordance_contingency", ...
        state.concordance.category_contingency, provenance, options);
end
if isfield(state, "support_patterns")
    exports = writeOne(exports, root, "support_pattern_recordings", ...
        state.support_patterns.index, provenance, options);
    exports = writeOne(exports, root, "support_pattern_counts", ...
        state.support_patterns.primary.patterns, provenance, options);
    exports = writeOne(exports, root, "support_pattern_features", ...
        state.support_patterns.primary.features, provenance, options);
end
if isfield(state, "examples")
    exports = writeOne(exports, root, "example_index", ...
        state.examples.gallery.index, provenance, options);
end
end

function exports = writeOne(exports, root, name, value, provenance, options)
if ~istable(value) || height(value) == 0
    return
end
path = fullfile(root, name + ".csv");
vawlume.eda.writeTableExport(value, path, Provenance=provenance, ...
    Overwrite=options.Overwrite);
exports(end + 1, :) = {string(name), string(path)};
end

function figures = exportFigures(figures, state, root, options)
if ~isfolder(root)
    mkdir(root);
end
if isfield(state, "diagnostics")
    surface = state.diagnostics.surface;
    for metricName = screenedMetricNames(state)'
        if ~ismember(metricName, string(surface.metrics.Properties.VariableNames))
            continue
        end
        figures = drawOne(figures, root, "distribution_" + metricName, ...
            @(path) vawlume.eda.plotMetricDistribution(surface.metrics, ...
            metricName, ExportPath=path, ResolutionDpi=options.ResolutionDpi));
    end
    for kind = ["pearson", "spearman", "partial"]
        figures = drawOne(figures, root, "dependency_" + kind, ...
            @(path) vawlume.eda.plotMetricCorrelation( ...
            state.diagnostics.dependencies, kind, ExportPath=path, ...
            ResolutionDpi=options.ResolutionDpi));
    end
    figures = drawOne(figures, root, "metric_coverage", ...
        @(path) vawlume.eda.renderMetricCoverageTable( ...
        state.diagnostics.distributions.distributions, ExportPath=path, ...
        ResolutionDpi=options.ResolutionDpi));
end
if isfield(state, "screen") && isfield(state.screen, "responses")
    figures = drawOne(figures, root, "screen_main_effects", ...
        @(path) vawlume.eda.plotMainEffects(state.screen.leverage.categories, ...
        Response="agreement_groups_total", ExportPath=path, ...
        ResolutionDpi=options.ResolutionDpi));
    figures = drawOne(figures, root, "screen_support_pattern_responses", ...
        @(path) vawlume.eda.plotSupportPatternResponses( ...
        state.screen.responses.responses, ExportPath=path, ...
        ResolutionDpi=options.ResolutionDpi));
    figures = drawOne(figures, root, "screen_configuration_changes", ...
        @(path) vawlume.eda.plotConfigurationChanges( ...
        state.screen.responses.responses, ExportPath=path, ...
        ResolutionDpi=options.ResolutionDpi));
end
if isfield(state, "subset") && isfield(state.subset, "responses")
    figures = drawOne(figures, root, "subset_support_pattern_responses", ...
        @(path) vawlume.eda.plotSupportPatternResponses( ...
        state.subset.responses.responses, ExportPath=path, ...
        ResolutionDpi=options.ResolutionDpi));
end
if isfield(state, "concordance")
    figures = drawOne(figures, root, "probe_concordance", ...
        @(path) vawlume.eda.plotProbeConcordance(state.concordance, ...
        ExportPath=path, ResolutionDpi=options.ResolutionDpi));
end
if isfield(state, "support_patterns")
    profile = state.support_patterns.primary;
    % The profile's interpretation note is several paragraphs; the figure frame
    % renders ONE string, so it is joined here rather than handed over as an
    % array it would index into a single slot.
    note = strjoin(string(profile.interpretation_note(:))', ...
        string(newline) + string(newline));
    figures = drawOne(figures, root, "support_pattern_counts", ...
        @(path) vawlume.eda.plotSupportPatternSummary(profile.patterns, ...
        ExportPath=path, ResolutionDpi=options.ResolutionDpi, ...
        InterpretationNote=note));
    for className = string(state.support_patterns. ...
            comparable_features.cross_pattern_comparable)
        figures = drawOne(figures, root, "support_feature_" + className, ...
            @(path) vawlume.eda.plotSupportFeatureDistributions( ...
            profile.features, className, ExportPath=path, ...
            ResolutionDpi=options.ResolutionDpi, InterpretationNote=note));
    end
end
end

function figures = drawOne(figures, root, name, draw)
%DRAWONE Render one figure, and record a refusal rather than abandoning the set.
%
% Every plotting entry point refuses a degenerate input by design - a metric with
% one finite value, a screen with one configuration, a feature with no eligible
% pattern. On thin data those refusals are the honest answer, and a workflow that
% stopped at the first of them would export nothing at all.
path = fullfile(root, name + ".png");
try
    fig = draw(path);
    close(fig);
    figures(end + 1, :) = {string(name), string(path)};
catch exception
    figures(end + 1, :) = {string(name), ...
        "not drawn: " + string(exception.identifier)};
end
end

function value = emptyExportTable()
value = table(strings(0, 1), strings(0, 1), VariableNames=["name", "path"]);
end

function value = screenedMetricNames(state)
value = strings(0, 1);
if ~isfield(state, "probe")
    return
end
factors = state.probe.resolution.factors;
value = unique(string(factors.metric_name(factors.is_active)));
value = value(strlength(value) > 0);
end

function path = writeProvenance(root, provenance, options)
if ~isfolder(root)
    mkdir(root);
end
path = string(fullfile(root, "exploration_provenance.json"));
if isfile(path) && ~options.Overwrite
    error("vawlume:eda:ExplorationExportExists", ...
        "Provenance export '%s' exists. Pass Overwrite=true to replace it.", ...
        path);
end
fileId = fopen(path, "w", "n", "UTF-8");
if fileId < 0
    error("vawlume:eda:ExplorationExportOpenFailed", ...
        "Could not open '%s' for writing.", path);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, unicode2native(jsonencode(provenance, PrettyPrint=true), ...
    "UTF-8"));
clear cleanup
end

% =========================================================================== %
% Provenance
% =========================================================================== %

function value = exportProvenance(state, result)
%EXPORTPROVENANCE The identity every exported table carries in its header.
value = struct();
value.exploration_run_key = string(result.exploration_run_key);
value.project_key = string(result.project_key);
if isfield(state, "reference")
    value.reference_configuration_id = string( ...
        state.reference.configuration_id);
    value.reference_profile_key = string( ...
        state.reference.configuration.profile_key);
    value.reference_profile_version = string( ...
        state.reference.configuration.version_label);
    value.reference_calibration_state = string( ...
        state.reference.configuration.calibration_status.state);
end
if isfield(state, "probe")
    value.seed = state.probe.seed;
end
end

function value = provenanceRecord(result, state, options)
%PROVENANCERECORD What the run recorded about its own automatic choices.
%
% Most of the development plan's provenance list is already implied by the linked
% analyses and the registered design record; what is recorded explicitly here is
% what is not. There is no selected-threshold field, and there is not going to be
% one.
value = struct();
value.record_version = "1.0";
value.exploration_run_key = string(result.exploration_run_key);
value.project_key = string(result.project_key);
value.applied = options.Apply;
value.status = string(result.status);
value.analysis_budget = result.analysis_budget;
value.stage_status = stageStatusStruct(result.stages);
value.no_selected_threshold = "This workflow selects no threshold. No " + ...
    "configuration here is optimal, recommended, validated, or calibrated.";
value.caution = string(edaCautionNote());

if isfield(state, "dataset")
    value.dataset = struct( ...
        recording_count=state.dataset.recording_count, ...
        recording_ids=state.dataset.recordings.recording_id(:)', ...
        excluded_recording_count=height(state.dataset.excluded_recordings), ...
        extractor_keys=string(state.dataset.extractor_keys(:))', ...
        pairs_per_recording=state.dataset.pairs_per_recording, ...
        pair_ordering=string(state.dataset.pair_ordering));
end
if isfield(state, "reference")
    value.reference_configuration = struct( ...
        specification_path=string( ...
            state.reference.configuration.specification_path), ...
        profile_key=string(state.reference.configuration.profile_key), ...
        version_label=string(state.reference.configuration.version_label), ...
        checksum_sha256=string( ...
            state.reference.configuration.checksum_sha256), ...
        configuration_id=string(state.reference.configuration_id), ...
        calibration_state=string( ...
            state.reference.configuration.calibration_status.state), ...
        selection_rule=string( ...
            state.reference.configuration.selection_rule));
end
if isfield(state, "diagnostics")
    value.diagnostics = struct( ...
        analysis_source=string(state.diagnostics.analysis_source), ...
        candidate_count=state.diagnostics.surface.candidate_count, ...
        quantile_definition=string( ...
            state.diagnostics.distributions.quantile_definition), ...
        observation_policy=string( ...
            state.diagnostics.dependencies.observation_policy.mode), ...
        complete_case_n= ...
            state.diagnostics.dependencies.observation_policy.complete_case_n);
end
if isfield(state, "probe")
    resolution = state.probe.resolution;
    value.probe_values = struct( ...
        seed=resolution.seed, ...
        seed_source=string(resolution.seed_source), ...
        seed_basis=string(resolution.seed_basis), ...
        active_factor_names=string(resolution.active_factor_names(:))', ...
        inactive_factor_names=string(resolution.inactive_factor_names(:))', ...
        factors=table2struct(resolution.factors)');
end
if isfield(state, "screen")
    value.whole_dataset_screen = designProvenance(state.screen);
end
if isfield(state, "subset")
    value.subset_probe = designProvenance(state.subset);
    value.subset_sampling = struct( ...
        seed=state.subset.subset.seed, ...
        is_stratified=state.subset.subset.is_stratified, ...
        stratum_field=string(state.subset.subset.stratum_field), ...
        fallback_reason=string(state.subset.subset.fallback_reason), ...
        ordering_key=string(state.subset.subset.ordering_key), ...
        requested_size=state.subset.subset.requested_size, ...
        realized_size=state.subset.subset.realized_size, ...
        selected_recording_ids= ...
            state.subset.subset.selected_recording_ids(:)');
end
if isfield(state, "examples")
    value.examples = struct( ...
        seed=state.examples.sample.seed, ...
        recording_id=state.examples.recording_id, ...
        target_per_pattern=state.examples.sample.target_per_pattern, ...
        example_count=state.examples.gallery.example_count, ...
        failure_count=state.examples.gallery.failure_count, ...
        gallery_directory=string( ...
            state.examples.gallery.gallery_directory));
end
if isfield(state, "exports")
    value.exports = struct(root=string(state.exports.root), ...
        table_count=height(state.exports.tables), ...
        figure_count=height(state.exports.figures));
end
end

function value = designProvenance(probe)
value = struct( ...
    design_type=string(probe.design.design_type), ...
    configuration_count=probe.design.configuration_count, ...
    resolution=probe.design.alias.resolution, ...
    generators=string(probe.design.alias.generators(:))', ...
    defining_relation=string(probe.design.alias.defining_relation(:))', ...
    main_effects_clear_of_two_factor_interactions= ...
        probe.design.alias.main_effects_clear_of_two_factor_interactions, ...
    configuration_ids=string(probe.design.configurations.configuration_id(:))', ...
    predicted_analyses=probe.cost.total_analyses, ...
    executed_units=height(probe.run.manifest), ...
    probe_role=string(probe.run.probe_role));
end

function value = stageStatusStruct(stages)
value = struct();
for index = 1:height(stages)
    value.(stages.stage(index)) = string(stages.status(index));
end
end

% =========================================================================== %
% Small shared helpers
% =========================================================================== %

function value = materialize(design, options, runKey)
extra = {};
if strlength(runKey) > 0
    extra = {"ExplorationRunKey", runKey};
end
value = vawlume.eda.materializeConfigurations(design, ...
    "RepoRoot", options.RepoRoot, "OutputRoot", options.OutputRoot, extra{:});
end

function value = outputRoot(options, materialized)
if strlength(options.OutputRoot) > 0
    value = string(options.OutputRoot);
    return
end
% materializeConfigurations wrote the specifications under
% <root>/exploration/<run key>/specs, so the root it chose is two levels up.
value = string(fileparts(fileparts(fileparts( ...
    materialized.index.specification_path(1)))));
end

function value = exportRoot(state, options)
if isfield(state, "reference")
    value = fullfile(state.reference.output_root, "exports");
    return
end
value = fullfile(tempname, "exports");
if strlength(options.OutputRoot) > 0
    value = fullfile(options.OutputRoot, "exports");
end
end

function value = galleryDirectory(state)
value = "";
if isfield(state, "examples")
    value = string(state.examples.gallery.gallery_directory);
end
end

function value = sizeOverride(resolution)
value = [];
if isfield(resolution, "subset_size") && isfinite(resolution.subset_size)
    value = resolution.subset_size;
end
end

function cost = reportCost(dataset, configurationCount, options, label)
cost = vawlume.eda.probeCost(dataset, configurationCount, ...
    WarnAtAnalyses=options.WarnAtAnalyses, ...
    MaximumAnalyses=options.MaximumAnalyses, ...
    AllowExceedingMaximum=options.AllowExceedingMaximum);
printLine(options, "       %s: %d configuration(s) x %d recording(s) x %d " + ...
    "= %d analyses (%d matching, %d agreement)", label, ...
    cost.configuration_count, cost.recording_count, ...
    cost.analyses_per_configuration_per_recording, cost.total_analyses, ...
    cost.matching_analyses, cost.agreement_analyses);
for warning0 = string(cost.warnings(:))'
    printLine(options, "       ! %s", warning0);
end
end

function value = usableUnits(manifest, kind)
usable = manifest(manifest.unit_kind == kind & ...
    ismember(manifest.status, ["committed", "reused"]), :);
value = usable(:, ["recording_id", "native_recording_id", "run_key", ...
    "analysis_run_id", "configuration_id"]);
end

function value = usableRunKeys(manifest, kind)
value = unique(manifest.run_key(manifest.unit_kind == kind & ...
    ismember(manifest.status, ["committed", "reused"])));
end

function printLine(options, format, varargin)
if ~options.Print
    return
end
fprintf(string(format) + "\n", varargin{:});
end

function printSummary(options, result)
if ~options.Print
    return
end
fprintf("\nExploration run '%s' on project '%s': %s\n", ...
    result.exploration_run_key, result.project_key, result.status);
disp(result.stages);
for warning0 = string(result.warnings(:))'
    fprintf("  ! %s\n", warning0);
end
fprintf("%s\n", strjoin(string(result.caution), newline));
end
