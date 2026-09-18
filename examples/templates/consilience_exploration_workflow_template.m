%% VAWLUME — extractor-consilience exploration workflow
%
% Copy this file, edit section 1, and run the sections in order.
%
% This is a TEMPLATE: it shows how the workflow is used and contains no
% implementation logic of its own. Every line below either sets a value you
% choose or calls one public VAWLUME function. If you find yourself adding
% computation here, it belongs in a function instead.
%
% For a runnable, self-contained version over a synthetic fixture, see
% examples/consilience_exploration_demo.m. For what the outputs mean and what
% they do not, see docs/development/35_consilience_exploration_workflow.md.
%
% NOTHING HERE IS CALIBRATED. The workflow explores how cross-extractor
% correspondence responds to matching assumptions in one dataset. It selects no
% threshold, recommends none, and produces no score that ranks configurations.


%% 1. USER CONFIGURATION
% Everything you choose is in this block. You do not define a parameter grid:
% which threshold dimensions are screened, at what values, how large the subset
% is and which metadata field it is stratified on are decided by the workflow
% and written into its provenance record.

repoRoot     = string(pwd);                        % the VAWLUME repository root
databasePath = "C:\path\to\my_project.sqlite";     % an existing VAWLUME database
projectKey   = "my_project";                       % the project to explore
sourceRoot   = "C:\path\to\audio_root";            % resolves recording audio
outputRoot   = fullfile(tempdir, "vawlume_exploration");

% The scientific configuration. `seed` is the only field most runs set; leave it
% empty and the workflow derives one from dataset identity and records it.
explorationConfiguration = struct( ...
    enabled      = true, ...
    seed         = 20260918, ...
    subset_size  = [], ...   % recordings in the richer probe; [] = the default
    threshold_ranges  = struct(), ...   % per-factor [low high] overrides
    disabled_factors  = strings(0, 1)); % factors to leave out of the screen

% Budgets. The configuration ceilings bound the DESIGN; the analysis ceiling
% bounds the WORK, and it is the one that binds on a real dataset: for three
% extractors every configuration costs four analyses per recording. Setting
% `analysis_budget` in the configuration struct above overrides `analysisCeiling`.
screenConfigurationCeiling = 128;
subsetConfigurationCeiling = 256;
analysisCeiling            = 2500;

addpath(fullfile(repoRoot, "src"));
conn = sqlite(char(databasePath));
cleanupConnection = onCleanup(@() close(conn));

options  = vawlume.eda.explorationOptions(explorationConfiguration);
selector = struct(project_key = projectKey);

commonArguments = { ...
    "Options", options, "RepoRoot", repoRoot, "OutputRoot", outputRoot, ...
    "SourceRoot", sourceRoot, ...
    "MaximumConfigurations", screenConfigurationCeiling, ...
    "SubsetMaximumConfigurations", subsetConfigurationCeiling, ...
    "MaximumAnalyses", analysisCeiling};


%% 2. RUN FULL-DATASET DIAGNOSTICS
% Cheap, and worth doing before you spend any budget on threshold sweeps. The
% diagnostics read stored candidate pairs, so this stage first applies the
% tracked reference configuration to supply them; nothing is screened yet.

diagnosticsRun = vawlume.eda.runExploration(conn, selector, ...
    commonArguments{:}, Stages = "diagnostics");

disp(diagnosticsRun.diagnostics.distributions.distributions)
disp(diagnosticsRun.diagnostics.dependencies.redundancy)

% An undefined partial correlation is reported with its reason rather than
% regularized into a finite-looking number. Read the reason before the value.
disp(diagnosticsRun.diagnostics.dependencies.observation_policy)


%% 3. BUILD AND PRICE THE BOUNDED WHOLE-DATASET SCREEN
% Apply=false builds every design and reports what executing them would cost. No
% analysis, export or provenance record is written. Run this before committing to
% a long probe.
%
% DiagnosticAnalyses is needed here and only here: probe values are anchored on
% observed candidate-pair distributions, so a run that writes nothing has to be
% told where to find pairs that already exist. Section 2 applied the reference
% configuration, so naming the project is enough.

plannedRun = vawlume.eda.runExploration(conn, selector, ...
    commonArguments{:}, Apply = false, ...
    DiagnosticAnalyses = struct(project_key = projectKey));

disp(plannedRun.screen.design.alias.alias_table)
disp(plannedRun.screen.cost)

% If the design is a fraction rather than a full factorial, some effects are
% aliased and the screen cannot separate them. That is disclosed here, in
% `alias_table` and in `alias.resolution`, and it travels into the leverage
% report — it is not something you have to remember to check.


%% 4. RUN THE WHOLE WORKFLOW
% One call: reference configuration, diagnostics, probe values, whole-dataset
% screen, stratified subset, richer probe, concordance, support-pattern
% characterization, spectrogram gallery, exports and provenance.

exploration = vawlume.eda.runExploration(conn, selector, commonArguments{:});

disp(exploration.stages)
disp(exploration.probe.resolution.factors)   % every value the workflow chose


%% 5. DRAW STRATIFIED RECORDING SUBSET
% The subset is where the extra search budget is spent; the full dataset gets
% the compact screen. Stratification happens automatically when a recording-level
% field qualifies, and the workflow says which field it used and why it rejected
% the others.

disp(exploration.subset.subset.stratification_statement)
disp(exploration.subset.subset.fields_considered)
disp(exploration.subset.subset.allocation)

% An under-full stratum is reported short with its actual count. It is never
% padded from a neighbouring stratum: a stratified sample whose strata are
% secretly unequal reads as balanced and is not.


%% 6. RUN RICHER SUBSET PROBE
% The richer design covers the same factors as the screen so the two can be
% compared, and it usually affords the full factorial the screen could not.

disp(exploration.subset.design.screen_comparison)
disp(exploration.subset.leverage.category_counts)


%% 7. COMPARE PROBE RESULTS
% A table, per factor per response — never a score. Disagreement between the
% probes is informative, not an error: they differ in design and in dataset.

disp(exploration.concordance.comparison)
disp(exploration.concordance.category_contingency)
disp(exploration.concordance.calibration_note)


%% 8. CHARACTERIZE EXACT SUPPORT PATTERNS
% At the reference configuration, never at a configuration chosen from the
% screen. Agreement is recording-scoped, so there is one profile per recording.

disp(exploration.support_patterns.index)
disp(exploration.support_patterns.primary.patterns)
disp(exploration.support_patterns.primary.features)

% Only features registered as comparable across EVERY participating extractor
% may go on a cross-pattern axis. Ask before plotting, and the answer is a
% refusal rather than a flag when the feature is extractor-restricted.
disp(exploration.support_patterns.comparable_features)


%% 9. GENERATE REPRESENTATIVE SPECTROGRAM EXAMPLES
% Illustrative images, not a review pool: there is no verdict column, no notes
% column and no re-import path. A frequency band is drawn only where both band
% edges were measured; everything else shows a time extent and measured markers.

disp(exploration.examples.gallery.index)
disp(exploration.examples.sample.short_patterns)   % reported, never padded
fprintf("Gallery: %s\n", exploration.examples.gallery.gallery_directory);


%% 10. EXPORT TABLES, FIGURES, EXAMPLE INDEX, AND PROVENANCE
% Written by the run itself. Every CSV carries a provenance and caution header
% line; the provenance record carries every automatic choice.

disp(exploration.exports.tables)
disp(exploration.exports.figures)
fprintf("Provenance: %s\n", exploration.exports.provenance_path);
fprintf("%s\n", strjoin(string(exploration.caution), newline));
