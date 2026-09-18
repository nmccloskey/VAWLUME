function cost = probeCost(dataset, configurationCount, options)
%PROBECOST What a screening probe will actually cost, in analyses.
%
% COST = vawlume.eda.PROBECOST(DATASET, CONFIGURATIONCOUNT) reports the number of
% analyses a probe will execute against a resolved dataset, and enforces the
% governing contract's ceiling against that number.
%
%   matching   = configurations x recordings x N(N-1)/2
%   agreement  = configurations x recordings
%
% Name-value options:
%   WarnAtAnalyses    default 250
%   MaximumAnalyses   default 2500
%   AllowExceedingMaximum   explicit opt-in past the ceiling, default false
%
% THE CEILING IS ON ANALYSES, NOT CONFIGURATIONS, and that distinction is the
% whole point of enforcing it here rather than at design time. For three
% extractors each configuration costs four analyses per recording, so a
% configuration count understates the real cost roughly fourfold - and that
% factor is exactly what turns a design that looked like a small screen into an
% overnight run. The design layer bounds configurations because it cannot see the
% dataset; this bounds the work.
%
% When the ceiling binds here, it binds because the DATASET turned out larger
% than the design assumed, not because the design was wrong. The remedy belongs
% to the caller - fewer recordings, a smaller configuration budget, or an
% explicit opt-in - and the refusal names all three rather than silently
% truncating the probe to fit.
%
% This function is pure arithmetic over a resolved dataset. It executes nothing.

arguments
    dataset (1,1) struct
    configurationCount (1,1) double {mustBeNonnegative}
    options.WarnAtAnalyses (1,1) double {mustBePositive} = 250
    options.MaximumAnalyses (1,1) double {mustBePositive} = 2500
    options.AllowExceedingMaximum (1,1) logical = false
end

requireFields(dataset, ["recording_count", "extractor_count", ...
    "pairs_per_recording"]);
recordings = dataset.recording_count;
pairsPer = dataset.pairs_per_recording;

matching = configurationCount * recordings * pairsPer;
agreement = configurationCount * recordings;
total = matching + agreement;

exceeded = total > options.MaximumAnalyses;
if exceeded && ~options.AllowExceedingMaximum
    error("vawlume:eda:ProbeExceedsAnalysisBudget", ...
        "This probe would run %d analyses (%d matching + %d agreement) " + ...
        "against %d recordings, above the ceiling of %d. The ceiling is on " + ...
        "analyses, not configurations: %d configurations cost %d analyses " + ...
        "each per recording here. Reduce the recording set, lower the " + ...
        "design's configuration budget, or pass AllowExceedingMaximum " + ...
        "deliberately.", total, matching, agreement, recordings, ...
        options.MaximumAnalyses, configurationCount, pairsPer + 1);
end

warnings = strings(0, 1);
if exceeded
    warnings(end + 1, 1) = "This probe exceeds the analysis ceiling of " + ...
        string(options.MaximumAnalyses) + " by explicit opt-in.";
end
if total >= options.WarnAtAnalyses
    warnings(end + 1, 1) = string(total) + " analyses is at or above the " + ...
        "warning threshold of " + string(options.WarnAtAnalyses) + ".";
end

cost = struct( ...
    status="estimated", ...
    configuration_count=configurationCount, ...
    recording_count=recordings, ...
    extractor_count=dataset.extractor_count, ...
    pairs_per_recording=pairsPer, ...
    analyses_per_configuration_per_recording=pairsPer + 1, ...
    matching_analyses=matching, ...
    agreement_analyses=agreement, ...
    total_analyses=total, ...
    detection_count=detectionCount(dataset), ...
    formula="configurations x recordings x N(N-1)/2 matching, plus " + ...
        "configurations x recordings agreement", ...
    warn_at_analyses=options.WarnAtAnalyses, ...
    maximum_analyses=options.MaximumAnalyses, ...
    exceeded_maximum_by_opt_in=exceeded, ...
    warnings=warnings);
end

function value = detectionCount(dataset)
value = NaN;
if isfield(dataset, "detection_count")
    value = dataset.detection_count;
end
end

function requireFields(value, names)
missingNames = names(~isfield(value, names));
if ~isempty(missingNames)
    error("vawlume:eda:DatasetInvalid", ...
        "The resolved dataset is missing required field(s): %s.", ...
        strjoin(missingNames, ", "));
end
end
