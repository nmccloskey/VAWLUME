function tests = test_eda_visualization_layer
%TEST_EDA_VISUALIZATION_LAYER Table-only Part 14 plots and exports.
tests = functiontests({ ...
    @testEveryFigureFamilyRunsWithoutAConnection, ...
    @testDiagnosticGraphicsEqualTheirSourceValues, ...
    @testUndefinedPartialCellsAreExplicitAndNeverZero, ...
    @testScreeningGraphicsEqualTheirSourceValues, ...
    @testLeverageUnknownsRemainVisibleAndExtractorStyleMatches, ...
    @testSupportPatternGraphicsPreserveExactPatternsAndCoverage, ...
    @testDegenerateInputsRefuseOrDegradeExplicitly, ...
    @testFigureExportUsesRequestedResolutionAndVectorFormat, ...
    @testTableExportCarriesProvenanceCautionAndHostileText, ...
    @testRenderedLanguageHasNoUnqualifiedForbiddenVocabulary, ...
    @testPlotSourcesCallNoCoreOrDatabaseFunction});
end

function testEveryFigureFamilyRunsWithoutAConnection(testCase)
f = fixture();
figures = gobjects(0);
cleanup = onCleanup(@() closeAll(figures));

figures(end+1) = vawlume.eda.plotMetricDistribution(f.metrics, "metric_a");
figures(end+1) = vawlume.eda.plotMetricCorrelation(f.dependencies, "pearson");
figures(end+1) = vawlume.eda.plotMetricCorrelation(f.dependencies, "spearman");
figures(end+1) = vawlume.eda.plotMetricCorrelation(f.dependencies, "partial");
figures(end+1) = vawlume.eda.renderMetricCoverageTable(f.distributions);
figures(end+1) = vawlume.eda.plotMainEffects(f.categories, ...
    Response="agreement_groups_total", QualifierKind="extractor_key", ...
    Qualifier="usvseg", ValueKind="count");
figures(end+1) = vawlume.eda.plotSupportPatternResponses(f.responses);
figures(end+1) = vawlume.eda.plotConfigurationChanges(f.changes);
figures(end+1) = vawlume.eda.plotProbeConcordance(f.concordance);
figures(end+1) = vawlume.eda.plotSupportPatternSummary(f.patterns);
figures(end+1) = vawlume.eda.plotSupportFeatureDistributions( ...
    f.features, "vocalization_duration");

verifyEqual(testCase, numel(figures), 11);
verifyTrue(testCase, all(isgraphics(figures)));
verifyTrue(testCase, all(arrayfun(@(x) string(x.Visible) == "off", figures)));
clear cleanup
closeAll(figures);
end

function testDiagnosticGraphicsEqualTheirSourceValues(testCase)
f = fixture();
histogramFigure = vawlume.eda.plotMetricDistribution(f.metrics, "metric_a");
correlationFigure = vawlume.eda.plotMetricCorrelation(f.dependencies, "pearson");
coverageFigure = vawlume.eda.renderMetricCoverageTable(f.distributions);
cleanup = onCleanup(@() closeAll([histogramFigure correlationFigure ...
    coverageFigure]));

h = findall(histogramFigure, Tag="vawlume-metric-histogram");
verifyEqual(testCase, sort(h.Data(:)), sort(f.metrics.metric_a(isfinite( ...
    f.metrics.metric_a))));
imageHandle = findall(correlationFigure, Tag="vawlume-correlation-matrix");
verifyEqual(testCase, imageHandle.CData, f.dependencies.pearson);
ax = findall(correlationFigure, Tag="vawlume-eda-axes");
verifyEqual(testCase, colormap(ax), parula(256), AbsTol=eps);

tableHandle = findall(coverageFigure, Tag="vawlume-metric-coverage-table");
verifyEqual(testCase, tableHandle.Data.metric_name, ...
    f.distributions.metric_name);
verifyEqual(testCase, tableHandle.Data.supported, f.distributions.supported);
clear cleanup
closeAll([histogramFigure correlationFigure coverageFigure]);
end

function testUndefinedPartialCellsAreExplicitAndNeverZero(testCase)
f = fixture();
fig = vawlume.eda.plotMetricCorrelation(f.dependencies, "partial");
cleanup = onCleanup(@() closeAll(fig));
imageHandle = findall(fig, Tag="vawlume-correlation-matrix");
verifyTrue(testCase, all(isnan(imageHandle.CData), "all"));
verifyFalse(testCase, any(imageHandle.CData == 0, "all"));
cells = findall(fig, Tag="vawlume-undefined-cell");
reasons = findall(fig, Tag="vawlume-undefined-reason");
verifyEqual(testCase, numel(cells), 4);
verifyEqual(testCase, numel(reasons), 4);
for cellHandle = cells'
    verifyTrue(testCase, isnan(cellHandle.UserData.value));
    verifyEqual(testCase, string(cellHandle.UserData.reason), ...
        "insufficient_observations");
end
clear cleanup
closeAll(fig);
end

function testScreeningGraphicsEqualTheirSourceValues(testCase)
f = fixture();
mainFigure = vawlume.eda.plotMainEffects(f.categories, ...
    Response="agreement_groups_total", QualifierKind="extractor_key", ...
    Qualifier="usvseg", ValueKind="count");
responseFigure = vawlume.eda.plotSupportPatternResponses(f.responses);
changeFigure = vawlume.eda.plotConfigurationChanges(f.changes);
concordanceFigure = vawlume.eda.plotProbeConcordance(f.concordance);
cleanup = onCleanup(@() closeAll([mainFigure responseFigure changeFigure ...
    concordanceFigure]));

bars = findall(mainFigure, Tag="vawlume-main-effects");
verifyEqual(testCase, bars.YData(:), sortrows(f.categories, ...
    "factor_name").main_effect);

lines = findall(responseFigure, Tag="vawlume-support-pattern-response");
for lineHandle = lines'
    pattern = string(lineHandle.DisplayName);
    rows = sortrows(f.responses(f.responses.qualifier == pattern, :), ...
        "configuration_id");
    verifyEqual(testCase, lineHandle.YData(:), rows.value);
end

changeBars = findall(changeFigure, Tag="vawlume-configuration-changes");
verifyEqual(testCase, sum([changeBars.YData], "all"), sum(f.changes.value));
contingency = findall(concordanceFigure, Tag="vawlume-probe-contingency");
verifyEqual(testCase, sum(contingency.CData, "all"), ...
    sum(f.concordance.category_contingency.factor_response_pairs));
clear cleanup
closeAll([mainFigure responseFigure changeFigure concordanceFigure]);
end

function testLeverageUnknownsRemainVisibleAndExtractorStyleMatches(testCase)
f = fixture();
fig = vawlume.eda.plotMainEffects(f.categories, ...
    Response="agreement_groups_total", QualifierKind="extractor_key", ...
    Qualifier="usvseg", ValueKind="count");
cleanup = onCleanup(@() closeAll(fig));

labels = string({findall(fig, Tag="vawlume-leverage-category").String});
verifyTrue(testCase, any(contains(labels, "interaction_suspected")));
verifyTrue(testCase, any(contains(labels, "insufficient_information")));
style = vawlume.eda.exampleStyles("usvseg");
bars = findall(fig, Tag="vawlume-main-effects");
verifyEqual(testCase, bars.FaceColor, ...
    [style.color_r style.color_g style.color_b], AbsTol=eps);
verifyEqual(testCase, string(bars.LineStyle), style.line_style);
clear cleanup
closeAll(fig);
end

function testSupportPatternGraphicsPreserveExactPatternsAndCoverage(testCase)
f = fixture();
responseFigure = vawlume.eda.plotSupportPatternResponses(f.responses);
summaryFigure = vawlume.eda.plotSupportPatternSummary(f.patterns, ...
    Measure="group_proportion");
featureFigure = vawlume.eda.plotSupportFeatureDistributions( ...
    f.features, "vocalization_duration");
cleanup = onCleanup(@() closeAll([responseFigure summaryFigure featureFigure]));

legendHandle = findall(responseFigure, Type="legend");
verifyEqual(testCase, sort(string(legendHandle.String(:))), ...
    sort(unique(f.responses.qualifier)));
summaryBars = findall(summaryFigure, Tag="vawlume-support-pattern-summary");
sortedPatterns = sortrows(f.patterns, ["extractor_count", "extractor_set_key"]);
verifyEqual(testCase, summaryBars.YData(:), sortedPatterns.group_proportion);
summaryAxes = findall(summaryFigure, Tag="vawlume-eda-axes");
verifyTrue(testCase, contains(string(summaryAxes.YLabel.String), ...
    "denominator=5"));

coverage = findall(featureFigure, Tag="vawlume-coverage-annotation");
verifyEqual(testCase, numel(coverage), height(f.features));
coverageText = string({coverage.String});
verifyTrue(testCase, any(contains(coverageText, "n=3/4")));
verifyTrue(testCase, any(contains(coverageText, "n=1/2")));
medians = findall(featureFigure, Tag="vawlume-feature-median");
verifyEqual(testCase, numel(medians), 1);
verifyEqual(testCase, medians.YData, 0.045);
verifyEqual(testCase, numel(findall(featureFigure, ...
    Tag="vawlume-feature-undefined")), 1);
clear cleanup
closeAll([responseFigure summaryFigure featureFigure]);
end

function testDegenerateInputsRefuseOrDegradeExplicitly(testCase)
f = fixture();
oneValue = table(1, VariableNames="metric_a");
verifyError(testCase, @() vawlume.eda.plotMetricDistribution( ...
    oneValue, "metric_a"), "vawlume:eda:PlotDistributionDegenerate");

oneConfiguration = f.responses(f.responses.configuration_id == "cfg-a", :);
verifyError(testCase, @() vawlume.eda.plotSupportPatternResponses( ...
    oneConfiguration), "vawlume:eda:PlotConfigurationDegenerate");

emptyCoverage = f.distributions([], :);
verifyError(testCase, @() vawlume.eda.renderMetricCoverageTable( ...
    emptyCoverage), "vawlume:eda:PlotSelectionEmpty");

% One factor and one exact pattern remain honest single-category displays.
singleFactor = f.categories(1, :);
factorFigure = vawlume.eda.plotMainEffects(singleFactor, ...
    Response="agreement_groups_total", QualifierKind="extractor_key", ...
    Qualifier="usvseg", ValueKind="count");
singlePattern = f.patterns(1, :);
patternFigure = vawlume.eda.plotSupportPatternSummary(singlePattern);
cleanup = onCleanup(@() closeAll([factorFigure patternFigure]));
verifyEqual(testCase, numel(findall(factorFigure, ...
    Tag="vawlume-main-effects")), 1);
verifyEqual(testCase, numel(findall(patternFigure, ...
    Tag="vawlume-support-pattern-summary")), 1);
clear cleanup
closeAll([factorFigure patternFigure]);
end

function testFigureExportUsesRequestedResolutionAndVectorFormat(testCase)
f = fixture();
pngPath = string(tempname) + ".png";
svgPath = string(tempname) + ".svg";
cleanupFiles = onCleanup(@() deleteFiles([pngPath svgPath]));
fig = vawlume.eda.plotMetricDistribution(f.metrics, "metric_a", ...
    ExportPath=pngPath, ResolutionDpi=100, FigureSizeInches=[4 3]);
cleanupFigure = onCleanup(@() closeAll(fig));
verifyTrue(testCase, isfile(pngPath));
info = imfinfo(pngPath);
verifyEqual(testCase, [info.Width info.Height], [400 300], AbsTol=2);
returned = vawlume.eda.exportFigure(fig, svgPath, SizeInches=[4 3]);
verifyEqual(testCase, returned, fig);
verifyTrue(testCase, isfile(svgPath));
verifyGreaterThan(testCase, dir(svgPath).bytes, 100);
clear cleanupFigure cleanupFiles
closeAll(fig);
deleteFiles([pngPath svgPath]);
end

function testTableExportCarriesProvenanceCautionAndHostileText(testCase)
path = string(tempname) + ".csv";
cleanup = onCleanup(@() deleteFiles(path));
table0 = table([1;2], ["comma, value"; "μ-call ""quoted"""], ...
    VariableNames=["id", "label"]);
provenance = struct(exploration_run_key="exp-test", ...
    reference_configuration_id="ref-test");
verifyError(testCase, @() vawlume.eda.writeTableExport(table0, path, ...
    Provenance=struct()), "vawlume:eda:TableExportProvenanceRequired");
result = vawlume.eda.writeTableExport(table0, path, ...
    Provenance=provenance);
verifyEqual(testCase, result.row_count, 2);
lines = readlines(path);
verifyTrue(testCase, startsWith(lines(1), result.header_prefix));
header = jsondecode(extractAfter(lines(1), result.header_prefix));
verifyEqual(testCase, string(header.provenance.exploration_run_key), ...
    "exp-test");
verifyEqual(testCase, numel(header.caution), 4);
verifyTrue(testCase, contains(string(header.caution(1)), ...
    "methodological evidence, not ground truth"));
roundTrip = readtable(path, NumHeaderLines=1, TextType="string");
verifyEqual(testCase, roundTrip.id, table0.id);
verifyEqual(testCase, roundTrip.label, table0.label);
clear cleanup
deleteFiles(path);
end

function testRenderedLanguageHasNoUnqualifiedForbiddenVocabulary(testCase)
f = fixture();
figures = [ ...
    vawlume.eda.plotMetricDistribution(f.metrics, "metric_a"), ...
    vawlume.eda.plotMetricCorrelation(f.dependencies, "pearson"), ...
    vawlume.eda.renderMetricCoverageTable(f.distributions), ...
    vawlume.eda.plotMainEffects(f.categories, ...
        Response="agreement_groups_total", QualifierKind="extractor_key", ...
        Qualifier="usvseg", ValueKind="count"), ...
    vawlume.eda.plotSupportPatternResponses(f.responses), ...
    vawlume.eda.plotConfigurationChanges(f.changes), ...
    vawlume.eda.plotProbeConcordance(f.concordance), ...
    vawlume.eda.plotSupportPatternSummary(f.patterns), ...
    vawlume.eda.plotSupportFeatureDistributions( ...
        f.features, "vocalization_duration")];
cleanup = onCleanup(@() closeAll(figures));
for fig = figures
    textValue = lower(nonCautionText(fig));
    for forbidden = ["optimal", "validated", "true call set", "best threshold"]
        verifyFalse(testCase, contains(textValue, forbidden), ...
            "Rendered non-caution text contains forbidden wording: " + forbidden);
    end
    cautionBox = findall(fig, Tag="vawlume-eda-caution");
    verifyEqual(testCase, numel(cautionBox), 1);
    verifyTrue(testCase, contains(strjoin(string(cautionBox.String), " "), ...
        "methodological evidence, not ground truth"));
end
clear cleanup
closeAll(figures);
end

function testPlotSourcesCallNoCoreOrDatabaseFunction(testCase)
root = repoRootPath();
files = ["plotMetricDistribution.m", "plotMetricCorrelation.m", ...
    "renderMetricCoverageTable.m", "plotMainEffects.m", ...
    "plotSupportPatternResponses.m", "plotConfigurationChanges.m", ...
    "plotProbeConcordance.m", "plotSupportPatternSummary.m", ...
    "plotSupportFeatureDistributions.m"];
for file = files
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", file)));
    for forbidden = ["candidateMetrics(", "metricDistributions(", ...
            "metricDependencies(", "screenResponses(", "mainEffects(", ...
            "leverageCategories(", "probeConcordance(", ...
            "supportPatternProfile(", "crossPatternComparison(", ...
            "sqlite(", "fetch(", "execute("]
        verifyFalse(testCase, contains(source, forbidden), ...
            file + " calls forbidden core/database function " + forbidden);
    end
    verifyFalse(testCase, contains(source, "conn"), ...
        file + " mentions a database connection.");
end

% Check the opposite call direction as well: computational entry points must
% not acquire a dependency on the visualization layer.
packageFolder = fullfile(root, "src", "+vawlume", "+eda");
packageFiles = dir(fullfile(packageFolder, "*.m"));
plotCalls = ["plotMetricDistribution(", "plotMetricCorrelation(", ...
    "renderMetricCoverageTable(", "plotMainEffects(", ...
    "plotSupportPatternResponses(", "plotConfigurationChanges(", ...
    "plotProbeConcordance(", "plotSupportPatternSummary(", ...
    "plotSupportFeatureDistributions("];
for index = 1:numel(packageFiles)
    file = string(packageFiles(index).name);
    if startsWith(file, "plot") || startsWith(file, "render")
        continue
    end
    source = codeOnly(fileread(fullfile(packageFolder, file)));
    for plotCall = plotCalls
        verifyFalse(testCase, contains(source, plotCall), ...
            file + " calls visualization function " + plotCall);
    end
end
end

function f = fixture()
f.metrics = table([0.10; 0.20; NaN; 0.40], [1; 2; 3; 4], ...
    VariableNames=["metric_a", "metric_b"]);
names = ["metric_a"; "metric_b"];
f.dependencies = struct(metric_names=names, ...
    pearson=[1 0.5; 0.5 1], spearman=[1 0.4; 0.4 1], ...
    correlation_observations=[3 3; 3 4], ...
    correlation_undefined_reason=strings(2), ...
    partial=struct(matrix=nan(2), ...
        undefined_reason=repmat("insufficient_observations", 2)));
f.distributions = table(names, [3;4], [0;0], [0;0], [0;0], [1;0], ...
    [4;4], ["computed";"computed"], ...
    VariableNames=["metric_name", "supported", "not_eligible", ...
    "not_measured", "not_comparable_topology", "non_finite", "total", ...
    "statistics_status"]);

f.categories = table( ...
    repmat("agreement_groups_total",3,1), repmat("extractor_key",3,1), ...
    repmat("usvseg",3,1), strings(3,1), strings(3,1), ...
    repmat("count",3,1), ["factor_a";"factor_b";"factor_c"], ...
    [2;NaN;0.1], [4;NaN;4], ...
    ["interaction_suspected";"insufficient_information";"low_leverage"], ...
    VariableNames=["response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary", "value_kind", "factor_name", ...
    "main_effect", "response_range", "category"]);

configs = ["cfg-a";"cfg-a";"cfg-b";"cfg-b"];
patterns = ["a--b";"a--c";"a--b";"a--c"];
f.responses = table(repmat("exp",4,1), configs, nan(4,1), ...
    repmat("pooled",4,1), repmat("support_pattern_groups",4,1), ...
    repmat("support_pattern",4,1), patterns, strings(4,1), strings(4,1), ...
    [2;3;4;1], nan(4,1), repmat("count",4,1), ...
    VariableNames=["exploration_run_key", "configuration_id", ...
    "recording_id", "scope", "response", "qualifier_kind", "qualifier", ...
    "secondary_kind", "secondary", "value", "denominator", "value_kind"]);

changeConfigs = repelem(["cfg-a";"cfg-b"], 2);
changeClasses = repmat(["retained";"split"], 2, 1);
f.changes = table(repmat("exp",4,1), changeConfigs, nan(4,1), ...
    repmat("pooled",4,1), repmat("group_change_from",4,1), ...
    repmat("change_class",4,1), changeClasses, ...
    repmat("baseline_configuration_id",4,1), repmat("cfg-ref",4,1), ...
    [5;0;2;3], nan(4,1), repmat("count",4,1), ...
    VariableNames=f.responses.Properties.VariableNames);

vocabulary = ["insufficient_information";"interaction_suspected"; ...
    "high_leverage";"moderate_leverage";"low_leverage"];
f.concordance = struct(category_vocabulary=vocabulary, ...
    category_contingency=table( ...
        ["insufficient_information";"interaction_suspected";"not_observed"], ...
        ["low_leverage";"high_leverage";"insufficient_information"], ...
        [4;3;2], VariableNames=["screen_category", "subset_category", ...
        "factor_response_pairs"]), ...
    calibration_note="Probe convergence is exploratory and does not remove " + ...
        "the need for calibration.");

f.patterns = table(["a";"a|b"], ["a only";"a + b"], [1;2], ...
    [false;true], [false;true], [2;3], [0.4;0.6], [2;6], [0.25;0.75], ...
    [5;5], [8;8], [false;false], ...
    VariableNames=["extractor_set_key", "extractor_set_label", ...
    "extractor_count", "is_extractor_unique", "is_complete_support", ...
    "group_count", "group_proportion", "detection_count", ...
    "detection_proportion", "group_denominator", "detection_denominator", ...
    "is_absent"]);

f.features = table(["a";"a|b"], ["a only";"a + b"], ...
    repmat("vocalization_duration",2,1), repmat("s",2,1), [true;true], ...
    [2;4], [1;3], [0.5;0.75], ["low_coverage";"reported"], ...
    ["insufficient_observations";"computed"], ...
    [NaN;0.03], [NaN;0.04], [NaN;0.045], [NaN;0.05], [NaN;0.07], ...
    VariableNames=["extractor_set_key", "extractor_set_label", ...
    "equivalence_class", "canonical_unit", "is_cross_pattern_comparable", ...
    "pattern_population", "contributing_detections", "coverage_fraction", ...
    "coverage_label", "statistics_status", "minimum", "q25", "median", ...
    "q75", "maximum"]);
end

function value = nonCautionText(fig)
parts = strings(0,1);
objects = findall(fig);
for object = objects'
    if isprop(object, "Tag") && string(object.Tag) == "vawlume-eda-caution"
        continue
    end
    if isprop(object, "String")
        parts = [parts; string(object.String(:))]; %#ok<AGROW>
    end
    if isprop(object, "DisplayName") && strlength(string(object.DisplayName)) > 0
        parts(end+1) = string(object.DisplayName); %#ok<AGROW>
    end
    if isprop(object, "XTickLabel")
        parts = [parts; string(object.XTickLabel(:))]; %#ok<AGROW>
    end
    if isprop(object, "YTickLabel")
        parts = [parts; string(object.YTickLabel(:))]; %#ok<AGROW>
    end
end
value = strjoin(parts, " ");
end

function value = codeOnly(source)
lines = splitlines(string(source));
value = strjoin(lines(~startsWith(strtrim(lines), "%")), newline);
end

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function closeAll(figures)
for fig = figures
    if isgraphics(fig), close(fig); end
end
end

function deleteFiles(paths)
for path = paths
    if isfile(path), delete(path); end
end
end
