function surface = candidateMetrics(conn, analysisRefs, options)
%CANDIDATEMETRICS Assemble the candidate-level matching metrics of a dataset.
%
% SURFACE = vawlume.eda.CANDIDATEMETRICS(CONN, ANALYSISREFS) returns one tidy
% table of every candidate-level metric VAWLUME already computed, pooled across
% the selected cross-extractor matching analyses, together with honest coverage
% accounting for each metric.
%
% ANALYSISREFS selects the analyses to span:
%
%   "matching-v1"                        one matching run_key
%   ["ds-mupet", "ds-usvseg"]            several run_keys
%   struct(project_key="project-a")      every completed cross_extractor_matching
%                                        analysis in that project
%   struct(analysis_run_id=7)            an explicit reference, or an array of them
%
% The diagnostic battery is a full-dataset activity, so the project-wide form is
% the ordinary one and pooling across recordings and extractor pairs is expected.
%
% Name-value options:
%   RepoRoot                      repository root used to re-read each analysis's
%                                 matching specification
%   IncludeFeatureDiscrepancies   default true; false skips the feature half and
%                                 returns temporal metrics only
%
% NOTHING HERE DEFINES A METRIC. Temporal metrics are read from the stored
% candidate_pairs rows and are never recomputed from detection boundaries.
% Feature discrepancies come from vawlume.consilience.summarize's
% feature_comparisons, never from a fresh registry join. This function's
% contribution is assembly, direction, coverage and shape.
%
% Two conventions the result states rather than assumes:
%
% Pair ordering is ascending extractor_key, and every signed difference is
% higher key minus lower key. The stored differences are the caller's run_b
% minus the caller's run_a, and candidate_pairs orders its two detection columns
% by detection id to satisfy a schema CHECK, so neither the stored columns nor
% the schema can supply direction. It is resolved from
% analysis_run_extraction_inputs.input_role and cross-checked against each row's
% details_json. Without that, pooled signed differences would be bimodal for a
% reason that is not biological.
%
% The a/b in extractor_key_a and extractor_key_b means ascending extractor key.
% The a/b in detection_a_id and detection_b_id means ascending detection id.
% These are different orderings and are not aligned;
% lower_extractor_detection_id and higher_extractor_detection_id state the
% mapping so no caller has to infer it.
%
% SURFACE.metrics carries one row per stored candidate pair.
% SURFACE.coverage carries one row per metric, with counts in five disjoint
% categories that sum to the row count.
% SURFACE.gates carries the plausibility rule each analysis's rows were admitted
% under, so a distribution can be read against the threshold that produced it: a
% temporal_iou distribution with a hard left edge at 0.1 is a property of the
% gate, not of the data.
%
% This function is read-only and writes nothing. It does not run matching, does
% not choose probe values from the distributions it exposes, does not filter or
% delete a metric that looks redundant, and produces no figure.

arguments
    conn
    analysisRefs
    options.RepoRoot (1,1) string = ""
    options.IncludeFeatureDiscrepancies (1,1) logical = true
end

selection = edaResolveAnalyses(conn, analysisRefs);
analyses = selection.analyses;
[temporalNames, temporalIsAbsolute] = edaTemporalMetricNames();

perAnalysis = cell(height(analyses), 1);
featureResults = cell(height(analyses), 1);
gates = [];
for index = 1:height(analyses)
    analysis = table2struct(analyses(index, :));
    [rows, gate] = edaCandidateRows(conn, analysis);
    analyses.candidate_count(index) = height(rows);
    analyses.recording_id(index) = uniqueRecording(rows, analysis);
    perAnalysis{index} = rows;
    if options.IncludeFeatureDiscrepancies
        featureResults{index} = edaFeatureDiscrepancy(conn, analysis, rows, ...
            options.RepoRoot);
    else
        featureResults{index} = struct(classes=strings(0, 1), ...
            values=NaN(height(rows), 0), status=strings(height(rows), 0));
    end
    gates = [gates; gate]; %#ok<AGROW>
end

metrics = vertcat(perAnalysis{:});
[classes, classIsPrimaryTemporal] = unionOfClasses(featureResults);
[featureValues, featureStatus] = alignFeatureColumns(featureResults, ...
    perAnalysis, classes);
featureMetrics = featureMetricTable(classes, classIsPrimaryTemporal);

for index = 1:numel(classes)
    metrics.(featureMetrics.metric_name(index)) = featureValues(:, index);
end

coverage = edaCoverage(metrics, temporalNames, featureMetrics, featureStatus);

surface = struct( ...
    status="assembled", ...
    analysis_count=height(analyses), ...
    candidate_count=height(metrics), ...
    analyses=analyses, ...
    excluded_analyses=selection.excluded, ...
    metrics=metrics, ...
    coverage=coverage, ...
    gates=gateTable(gates), ...
    feature_metrics=featureMetrics, ...
    metric_names=[temporalNames, featureMetrics.metric_name'], ...
    temporal_metric_names=temporalNames, ...
    absolute_metric_names=[temporalNames(temporalIsAbsolute), ...
        featureMetrics.metric_name'], ...
    signed_metric_names=["onset_difference_s", "offset_difference_s", ...
        "duration_difference_s"], ...
    feature_metric_names=featureMetrics.metric_name', ...
    coverage_categories=edaCoverageCategories()', ...
    conventions=conventions(options), ...
    caution=edaCautionNote());
end

function value = conventions(options)
value = struct( ...
    pair_ordering="ascending_extractor_key", ...
    signed_difference_direction= ...
        "higher_extractor_key_value_minus_lower_extractor_key_value", ...
    direction_source= ...
        "analysis_run_extraction_inputs.input_role, verified per row " + ...
        "against candidate_pairs.details_json", ...
    temporal_metric_source="stored candidate_pairs rows, never recomputed", ...
    feature_metric_source= ...
        "vawlume.consilience.summarize feature_comparisons", ...
    feature_discrepancy_definition= ...
        "absolute difference in the canonical unit, unsigned", ...
    detection_column_ordering= ...
        "detection_a_id < detection_b_id by schema CHECK; no run meaning", ...
    non_finite_includes_sql_null=true, ...
    feature_discrepancies_included=options.IncludeFeatureDiscrepancies);
end

function value = uniqueRecording(rows, analysis)
if height(rows) == 0
    value = NaN;
    return
end
found = unique(rows.recording_id);
if numel(found) ~= 1
    error("vawlume:eda:RecordingAmbiguous", ...
        "Matching analysis '%s' stores candidate rows spanning %d " + ...
        "recordings; matching is recording-scoped.", ...
        analysis.matching_run_key, numel(found));
end
value = found;
end

function [classes, isPrimaryTemporal] = unionOfClasses(featureResults)
classes = strings(0, 1);
flags = false(0, 1);
for index = 1:numel(featureResults)
    local = featureResults{index};
    classes = [classes; local.classes(:)]; %#ok<AGROW>
    if isfield(local, "primary_temporal")
        flags = [flags; local.primary_temporal(:)]; %#ok<AGROW>
    else
        flags = [flags; false(numel(local.classes), 1)]; %#ok<AGROW>
    end
end
[classes, first] = unique(classes);
isPrimaryTemporal = flags(first);
end

function [values, status] = alignFeatureColumns(featureResults, perAnalysis, classes)
%ALIGNFEATURECOLUMNS Place each analysis's classes into the dataset-wide column set.
%
% A class eligible for one extractor pair and not another is the ordinary case,
% not an error: for the pilot set, band edges are registered for DeepSqueak and
% MUPET and not for USVSEG. Rows of an analysis that cannot compare a class get
% not_eligible for it, which is a different fact from a missing measurement.
totalRows = 0;
for index = 1:numel(perAnalysis)
    totalRows = totalRows + height(perAnalysis{index});
end
values = NaN(totalRows, numel(classes));
status = repmat("not_eligible", totalRows, numel(classes));
offset = 0;
for index = 1:numel(featureResults)
    n = height(perAnalysis{index});
    if n == 0
        continue
    end
    local = featureResults{index};
    span = offset + (1:n);
    for localIndex = 1:numel(local.classes)
        target = find(classes == local.classes(localIndex), 1);
        values(span, target) = local.values(:, localIndex);
        status(span, target) = local.status(:, localIndex);
    end
    offset = offset + n;
end
end

function value = featureMetricTable(classes, isPrimaryTemporal)
%FEATUREMETRICTABLE Map each equivalence class to its column name, reversibly.
%
% An equivalence class is registry text and need not be a valid MATLAB variable
% name: consilienceFeatureAgreement emits "classA|classB" when a registered
% relationship's two features disagree on class. The mapping is returned so a
% reader can get back to the registry value rather than guessing at the column.
names = strings(numel(classes), 1);
for index = 1:numel(classes)
    names(index) = string(matlab.lang.makeValidName( ...
        "discrepancy_" + classes(index)));
end
if numel(unique(names)) ~= numel(names)
    error("vawlume:eda:FeatureColumnCollision", ...
        "Two equivalence classes reduce to the same column name.");
end
value = table(classes(:), names, logical(isPrimaryTemporal(:)), ...
    VariableNames=["equivalence_class", "metric_name", ...
    "is_primary_temporal_evidence"]);
end

function value = gateTable(gates)
if isempty(gates)
    value = table(zeros(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        VariableNames=["analysis_run_id", "eligibility_rule", ...
        "min_temporal_iou", edaGateBoundNames(), "candidate_rows"]);
    return
end
value = struct2table(gates, "AsArray", true);
value.eligibility_rule = string(value.eligibility_rule);
end
