function design = subsetDesign(resolution, screenDesign, subsetDataset, options)
%SUBSETDESIGN The richer design the recording subset buys, over the same factors.
%
% DESIGN = vawlume.eda.SUBSETDESIGN(RESOLUTION, SCREENDESIGN, SUBSETDATASET)
% builds the second sensitivity view's design: Part 6's construction over the
% SAME factors as the whole-dataset screen, under the subset probe's larger
% configuration budget, sized against the recordings that actually survived.
%
% RESOLUTION is the vawlume.eda.probeParameters record the screen used;
% SCREENDESIGN is the whole-dataset vawlume.eda.screeningDesign; SUBSETDATASET is
% vawlume.eda.resolveDataset over Part 9's selected recording ids.
%
% Name-value options:
%   Subset                  the Part 9 subset record, carried into the sizing
%                           report so requested and realized counts travel
%   WarnAtConfigurations    default 64   (contract §F, Part 10 row)
%   MaximumConfigurations   default 256  (contract §F, Part 10 row)
%   AllowExceedingMaximum   default false
%   WarnAtAnalyses / MaximumAnalyses / AllowExceedingAnalyses
%                           the analysis ceiling, checked against the REALIZED
%                           recording count
%
% THE RETURN IS A SCREENINGDESIGN, with subset-probe fields added. Everything
% downstream - materializeConfigurations, runScreen, screenResponses,
% mainEffects - consumes it unchanged, because a second design shape would mean a
% second code path through four layers and the two probes would eventually differ
% for reasons that have nothing to do with the data.
%
% SAME FACTORS, OR REFUSE. A factor present in one probe and absent from the
% other has no concordance row at all, and the concordance table would simply be
% short - a design failure that reads as a finding about the data. This is
% checked against the screen's own factor list and raised on, not warned about.
%
% THE FULL FACTORIAL IS THE POINT. If the whole-dataset screen used a fraction
% because the full dataset was expensive, the subset's larger budget may afford
% the full factorial, which DE-ALIASES exactly the interactions the screen could
% not separate. That is the single most valuable thing the subset can buy, and
% Part 6's construction already prefers it whenever it fits - so this function
% raises the ceiling and reports whether it was enough, rather than implementing
% a second preference rule.
%
% SIZED AGAINST THE REALIZED SUBSET COUNT, NEVER THE REQUESTED ONE. Part 9's
% subset can come back short of its request - an under-full stratum, or a frame
% smaller than the request - and Part 9's own record says so. A design sized
% against the requested count would be a budget overrun that only appears when
% the probe is already running. The realized count used here is
% SUBSETDATASET.recording_count, which can be smaller again than Part 9's
% realized size because resolveDataset excludes a recording that cannot form a
% pair; both numbers are reported side by side.
%
% This function is pure. It opens no connection and writes no file.

arguments
    resolution (1,1) struct
    screenDesign (1,1) struct
    subsetDataset (1,1) struct
    options.Subset struct = struct([])
    options.WarnAtConfigurations (1,1) double {mustBePositive} = 64
    options.MaximumConfigurations (1,1) double {mustBePositive} = 256
    options.AllowExceedingMaximum (1,1) logical = false
    options.WarnAtAnalyses (1,1) double {mustBePositive} = 250
    options.MaximumAnalyses (1,1) double {mustBePositive} = 2500
    options.AllowExceedingAnalyses (1,1) logical = false
end

requireFields(screenDesign, ["factors", "design_type", "alias", ...
    "configurations"]);
requireFields(subsetDataset, ["recordings", "pairs", "recording_count", ...
    "extractor_keys"]);

if subsetDataset.recording_count < 1
    error("vawlume:eda:SubsetProbeEmpty", ...
        "The subset dataset holds no recording, so there is nothing for the " + ...
        "second sensitivity view to run on.");
end

design = vawlume.eda.screeningDesign(resolution, ...
    WarnAtConfigurations=options.WarnAtConfigurations, ...
    MaximumConfigurations=options.MaximumConfigurations, ...
    AllowExceedingMaximum=options.AllowExceedingMaximum);

assertSameFactors(screenDesign, design);

sizing = sizeAgainstRealized(design, subsetDataset, options);
comparison = compareToScreen(screenDesign, design);

design.probe_role = "subset";
design.sizing = sizing;
design.screen_comparison = comparison;
design.factor_parity = struct( ...
    factor_names=sort(design.factors.factor_name)', ...
    matches_screen=true, ...
    rule="the subset probe screens exactly the whole-dataset screen's " + ...
        "factors; a factor in one probe and not the other has no " + ...
        "concordance row, which is a design failure rather than a finding");
design.effect_estimation = struct( ...
    applies="two-level difference of means, unchanged from the screen", ...
    level_count=2, ...
    note="both probes are two-level designs, so Part 8's effect arithmetic " + ...
        "applies to each unchanged and the two probes' estimates are the " + ...
        "same quantity. A multi-level grid would not be, and would have to " + ...
        "state its own estimator here.");
end

% ------------------------------------------------------------ factor parity ---

function assertSameFactors(screenDesign, subset)
%ASSERTSAMEFACTORS Refuse a design that cannot be compared, rather than warn.
screenNames = sort(string(screenDesign.factors.factor_name(:)));
subsetNames = sort(string(subset.factors.factor_name(:)));
if isequal(screenNames, subsetNames)
    return
end
onlyScreen = setdiff(screenNames, subsetNames);
onlySubset = setdiff(subsetNames, screenNames);
error("vawlume:eda:ProbeFactorsDiffer", ...
    "The subset probe screens a different factor set from the " + ...
    "whole-dataset screen, so the two probes cannot be compared factor by " + ...
    "factor.%s%s Build both designs from the same probeParameters " + ...
    "resolution, and if a budget binds reduce the fraction rather than " + ...
    "dropping a factor.", ...
    listPart(" Only in the screen: ", onlyScreen), ...
    listPart(" Only in the subset probe: ", onlySubset));
end

function value = listPart(prefix, names)
value = "";
if isempty(names)
    return
end
value = prefix + strjoin(names', ", ") + ".";
end

% ----------------------------------------------------------------- sizing ---

function sizing = sizeAgainstRealized(design, subsetDataset, options)
%SIZEAGAINSTREALIZED The analysis cost at the recordings that actually survived.
realized = subsetDataset.recording_count;
cost = vawlume.eda.probeCost(subsetDataset, design.configuration_count, ...
    WarnAtAnalyses=options.WarnAtAnalyses, ...
    MaximumAnalyses=options.MaximumAnalyses, ...
    AllowExceedingMaximum=options.AllowExceedingAnalyses);

requested = NaN;
subsetRealized = NaN;
shortfall = "";
if ~isempty(fieldnames(options.Subset))
    subset = options.Subset;
    if isfield(subset, "requested_size")
        requested = double(subset.requested_size);
    end
    if isfield(subset, "realized_size")
        subsetRealized = double(subset.realized_size);
    end
    shortfall = shortfallNote(requested, subsetRealized, realized);
end

sizing = struct( ...
    sized_against="realized", ...
    subset_requested_size=requested, ...
    subset_realized_size=subsetRealized, ...
    dataset_recording_count=realized, ...
    excluded_after_subset=excludedCount(subsetDataset), ...
    shortfall_note=shortfall, ...
    configuration_count=design.configuration_count, ...
    analysis_cost=cost, ...
    rule="the design's cost is computed at the subset dataset's own " + ...
        "recording count, which is what will actually be executed; the " + ...
        "requested subset size is reported beside it and is never the " + ...
        "basis of the sizing");
end

function value = shortfallNote(requested, subsetRealized, datasetCount)
parts = strings(0, 1);
if isfinite(requested) && isfinite(subsetRealized) && subsetRealized < requested
    parts(end + 1) = "Part 9 realized " + string(subsetRealized) + ...
        " of a requested " + string(requested) + ".";
end
if isfinite(subsetRealized) && datasetCount < subsetRealized
    parts(end + 1) = "resolveDataset then excluded " + ...
        string(subsetRealized - datasetCount) + " of those, leaving " + ...
        string(datasetCount) + ".";
end
if isempty(parts)
    value = "";
    return
end
value = strjoin(parts, " ") + " The design is sized against " + ...
    string(datasetCount) + ".";
end

function value = excludedCount(subsetDataset)
value = 0;
if isfield(subsetDataset, "excluded_recordings")
    value = height(subsetDataset.excluded_recordings);
end
end

% ------------------------------------------------------ screen comparison ---

function comparison = compareToScreen(screenDesign, subset)
%COMPARETOSCREEN What the subset's budget actually bought, stated plainly.
%
% The interesting quantity is not "is it bigger" but "which effects does it
% separate that the screen could not". That is the difference in alias structure,
% so it is reported as the effects whose attribution improved.
screenAlias = screenDesign.alias;
subsetAlias = subset.alias;

deAliased = strings(0, 1);
if isfield(screenAlias, "alias_table") && isfield(subsetAlias, "alias_table")
    screenTable = screenAlias.alias_table;
    subsetTable = subsetAlias.alias_table;
    for index = 1:height(screenTable)
        effect = screenTable.effect(index);
        if screenTable.is_uniquely_attributable(index)
            continue
        end
        match = subsetTable.effect == effect;
        if any(match) && subsetTable.is_uniquely_attributable(find(match, 1))
            deAliased(end + 1) = effect; %#ok<AGROW>
        end
    end
end

comparison = struct( ...
    screen_design_type=string(screenDesign.design_type), ...
    subset_design_type=string(subset.design_type), ...
    screen_configuration_count=screenDesign.configuration_count, ...
    subset_configuration_count=subset.configuration_count, ...
    screen_resolution_label=string(screenAlias.resolution_label), ...
    subset_resolution_label=string(subsetAlias.resolution_label), ...
    full_factorial_affordable=subset.design_type == "full_factorial", ...
    effects_de_aliased_by_the_subset=deAliased(:)', ...
    de_aliased_count=numel(deAliased), ...
    shared_configuration_ids=sharedConfigurations(screenDesign, subset), ...
    note=comparisonNote(screenDesign, subset, deAliased));
end

function value = sharedConfigurations(screenDesign, subset)
%SHAREDCONFIGURATIONS Points both probes evaluate, which must agree exactly.
%
% `configuration_id` is a hash of the active parameter values, so a configuration
% common to both designs is the SAME configuration. On a shared exploration run
% key its analyses are reused rather than recomputed, which is what makes a
% concordance disagreement attributable to design and dataset rather than to
% numerical drift between two executions of the same thing.
value = intersect(string(screenDesign.configurations.configuration_id), ...
    string(subset.configurations.configuration_id))';
end

function value = comparisonNote(screenDesign, subset, deAliased)
if subset.design_type == "full_factorial" && ...
        screenDesign.design_type ~= "full_factorial"
    value = "The subset budget afforded the FULL FACTORIAL where the " + ...
        "whole-dataset screen could not. " + string(numel(deAliased)) + ...
        " effect(s) that the screen could only report as an aliased sum are " + ...
        "uniquely attributable in the subset probe. This is the strongest " + ...
        "interaction claim available in this MVP, and it is available only " + ...
        "on the subset's recordings.";
    return
end
if subset.configuration_count > screenDesign.configuration_count
    value = "The subset probe runs " + ...
        string(subset.configuration_count) + " configurations against the " + ...
        "screen's " + string(screenDesign.configuration_count) + ", but " + ...
        "both designs are fractions. Interaction estimates in both remain " + ...
        "aliased sums where the alias table says so.";
    return
end
value = "The subset probe uses the same design as the whole-dataset screen, " + ...
    "so it separates nothing the screen could not. Any concordance " + ...
    "disagreement is then about the RECORDINGS, not about the design.";
end

% -------------------------------------------------------------- plumbing ---

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:SubsetDesignInputInvalid", ...
        "A required input is missing field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
