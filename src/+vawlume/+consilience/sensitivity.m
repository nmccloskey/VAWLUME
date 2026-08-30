function report = sensitivity(conn, analysisRefs, options)
%SENSITIVITY Compare several matching configurations over the same inputs.
%
% REPORT = vawlume.consilience.sensitivity(CONN, ANALYSISREFS) summarizes two or
% more already-applied matching analyses side by side and returns a comparison
% table plus the exact configuration provenance behind each row.
%
% ANALYSISREFS is a string array of matching `run_key` values, or a struct array
% of the references `vawlume.consilience.summarize` accepts.
%
% This function is read-only and writes nothing. It does not create analyses: the
% caller applies each configuration through `vawlume.matching.compare` with its
% own specification file, so each configuration already carries its own profile
% key, version label, and checksum in the database. Sensitivity then reads them
% back rather than re-deriving thresholds from anywhere else.
%
% What it reports per configuration:
%
%   min_temporal_iou, specification profile key / version / checksum
%   candidate count
%   one_to_one, one_to_many, many_to_one, many_to_many, unmatched group counts
%   unmatched detections per extractor
%   feature-supported and feature-discrepant group counts
%   manual reference agreement where a reference subset exists
%
% The analyses must share one recording, one ordered extraction-run pair, and one
% agreement algorithm version, so that differences in the table are attributable
% to the varied threshold. A mismatch raises rather than producing a table whose
% rows are not comparable.
%
% **No configuration is selected as best.** Under a synthetic fixture the table
% shows how outcomes move with an uncalibrated threshold; it is not evidence that
% any value is optimal, validated, or calibrated. Doing that requires real paired
% extractor output and real annotation.

arguments
    conn
    analysisRefs
    options.RepoRoot (1,1) string = ""
end

references = normalizeReferences(analysisRefs);
if numel(references) < 2
    error("vawlume:consilience:SensitivityNeedsConfigurations", ...
        "Sensitivity requires at least two matching analyses to compare.");
end

rows = emptyRows();
detail = cell(numel(references), 1);
baseline = [];
for index = 1:numel(references)
    summary = vawlume.consilience.summarize(conn, references{index}, ...
        RepoRoot=options.RepoRoot);
    detail{index} = summary;
    context = comparableContext(summary);
    if isempty(baseline)
        baseline = context;
    else
        assertComparable(baseline, context, summary.analysis.run_key);
    end
    rows(end + 1, :) = configurationRow(conn, summary); %#ok<AGROW>
end

report = struct( ...
    status="reported", ...
    configuration_count=numel(references), ...
    varied_parameter="candidate_generation.plausibility_rule.min_temporal_iou", ...
    held_constant=heldConstant(), ...
    recording_id=baseline.recording_id, ...
    run_a=baseline.run_a, ...
    run_b=baseline.run_b, ...
    comparison=sortrows(rows, "min_temporal_iou"), ...
    summaries={detail}, ...
    caution=cautionNote());
end

% ------------------------------------------------------------------- rows ---

function row = configurationRow(conn, summary)
counts = fetch(conn, "SELECT COUNT(*) AS n FROM candidate_pairs " + ...
    "WHERE analysis_run_id=" + string(summary.analysis.analysis_run_id));
topology = summary.topology;
statuses = summary.consilience_status_counts;
manual = summary.manual_qc;

if manual.reference_available && height(manual.per_run) == 2
    referenceSupported = sum(summary.manual_qc.contingency.reference_supported);
    precisionA = manual.per_run.precision(1);
    precisionB = manual.per_run.precision(2);
    recallA = manual.per_run.recall(1);
    recallB = manual.per_run.recall(2);
else
    referenceSupported = NaN;
    precisionA = NaN;
    precisionB = NaN;
    recallA = NaN;
    recallB = NaN;
end

row = {summary.analysis.run_key, summary.specification.profile_key, ...
    summary.specification.version_label, ...
    extractBefore(summary.specification.checksum_sha256 + "000000000000", 13), ...
    summary.specification.min_temporal_iou, double(counts.n(1)), ...
    topologyValue(topology, "one_to_one"), ...
    topologyValue(topology, "one_to_many"), ...
    topologyValue(topology, "many_to_one"), ...
    topologyValue(topology, "many_to_many"), ...
    topologyValue(topology, "unmatched"), ...
    summary.detection_agreement.unmatched_detections(1), ...
    summary.detection_agreement.unmatched_detections(2), ...
    statusValue(statuses, "matched_feature_supported"), ...
    statusValue(statuses, "matched_feature_discrepant"), ...
    statusValue(statuses, "temporally_matched"), ...
    statusValue(statuses, "single_extractor"), ...
    statusValue(statuses, "ambiguous_split_merge"), ...
    referenceSupported, precisionA, precisionB, recallA, recallB};
end

function value = topologyValue(topology, matchType)
selected = string(topology.match_type) == matchType;
if ~any(selected)
    value = 0;
    return
end
value = topology.group_count(find(selected, 1));
end

function value = statusValue(statuses, status)
selected = string(statuses.status) == status;
if ~any(selected)
    value = 0;
    return
end
value = statuses.group_count(find(selected, 1));
end

% --------------------------------------------------------- comparability ---

function context = comparableContext(summary)
context = struct( ...
    recording_id=summary.analysis.recording_id, ...
    run_a=summary.analysis.run_a.extraction_run_id, ...
    run_b=summary.analysis.run_b.extraction_run_id, ...
    algorithm_version=summary.algorithm.version, ...
    reference_set_key=summary.manual_qc.reference_set_key);
end

function assertComparable(baseline, context, runKey)
%ASSERTCOMPARABLE Refuse a table whose rows are not attributable to one variable.
fields = ["recording_id", "run_a", "run_b", "algorithm_version", ...
    "reference_set_key"];
for name = fields
    if ~isequal(baseline.(name), context.(name))
        error("vawlume:consilience:SensitivityInputsDiffer", ...
            ['Matching analysis ''%s'' differs from the others in %s. ' ...
            'Sensitivity varies one threshold over identical inputs; ' ...
            'otherwise the differences in the table are not attributable ' ...
            'to the threshold.'], runKey, name);
    end
end
end

function value = heldConstant()
value = [ ...
    "input extraction runs and recording"; ...
    "agreement algorithm key and version"; ...
    "assignment model and consensus policy"; ...
    "feature eligibility and declared tolerances"; ...
    "manual reference set and the detection-to-reference rule"];
end

function value = cautionNote()
value = [ ...
    "This table shows how outcomes move with an uncalibrated threshold."; ...
    "No configuration here is optimal, validated, or calibrated, and none " + ...
        "should be described that way."; ...
    "Selecting the configuration with the best synthetic manual agreement " + ...
        "would be fitting a threshold to a fixture."; ...
    "Calibration requires real paired extractor output and real independent " + ...
        "annotation."];
end

% --------------------------------------------------------------- plumbing ---

function references = normalizeReferences(analysisRefs)
if isstring(analysisRefs) || ischar(analysisRefs) || iscellstr(analysisRefs)
    keys = string(analysisRefs);
    references = cell(numel(keys), 1);
    for index = 1:numel(keys)
        references{index} = struct(run_key=keys(index));
    end
    return
end
if isstruct(analysisRefs)
    references = cell(numel(analysisRefs), 1);
    for index = 1:numel(analysisRefs)
        references{index} = analysisRefs(index);
    end
    return
end
if iscell(analysisRefs)
    references = analysisRefs(:);
    return
end
error("vawlume:consilience:SensitivityRefsInvalid", ...
    "analysisRefs must be run keys or analysis reference structs.");
end

function value = emptyRows()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["run_key", "profile_key", "version_label", "checksum", ...
    "min_temporal_iou", "candidate_count", "one_to_one_groups", ...
    "one_to_many_groups", "many_to_one_groups", "many_to_many_groups", ...
    "unmatched_groups", "run_a_unmatched_detections", ...
    "run_b_unmatched_detections", "feature_supported_groups", ...
    "feature_discrepant_groups", "temporally_matched_groups", ...
    "single_extractor_groups", "ambiguous_groups", ...
    "groups_with_reference_support", "run_a_precision", "run_b_precision", ...
    "run_a_recall", "run_b_recall"]);
end
