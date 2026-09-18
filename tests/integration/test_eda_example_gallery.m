function tests = test_eda_example_gallery
%TEST_EDA_EXAMPLE_GALLERY Real-WAV overlay and resilient batch export.
tests = functiontests({@setupOnce, @teardownOnce, ...
    @testRealMixedExampleRendersMeasuredGeometryOnly, ...
    @testBatchRecordsAFailureAndCompletes, ...
    @testASecondExportRequiresExplicitOverwrite});
end

function setupOnce(testCase)
[fixture, cleanup] = setUpFixture();
testCase.TestData.fixture = fixture;
testCase.TestData.cleanup = cleanup;
testCase.TestData.context = referenceRun(fixture);
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
end

function testRealMixedExampleRendersMeasuredGeometryOnly(testCase)
fixture = testCase.TestData.fixture;
context = testCase.TestData.context;
prepared = vawlume.eda.prepareExample(fixture.conn, ...
    context.three_way_example, SourceRoot=fixture.source_root);
rendered = vawlume.eda.renderExample(prepared, ...
    ReferenceConfigurationId=context.reference_configuration_id, ...
    Visible=false);
cleanup = onCleanup(@() closeIfOpen(rendered.figure));

verifyEqual(testCase, numel(findall(rendered.axes, ...
    Tag="vawlume-example-annotation")), 3);
verifyEqual(testCase, numel(findall(rendered.axes, ...
    Tag="vawlume-measured-band")), 2);

groups = findall(rendered.axes, Tag="vawlume-example-annotation");
usvseg = gobjects(0);
for group = groups'
    if string(group.UserData.extractor_key) == "usvseg"
        usvseg = group;
    end
end
verifyEqual(testCase, numel(usvseg), 1);
verifyEmpty(testCase, findall(usvseg, Type="rectangle"));
verifyEqual(testCase, numel(findall(usvseg, ...
    Tag="vawlume-frequency-marker")), 2);

legendText = string(rendered.legend.String);
verifyTrue(testCase, any(contains(legendText, ...
    "deepsqueak — measured band edges")));
verifyTrue(testCase, any(contains(legendText, ...
    "mupet — measured band edges")));
verifyTrue(testCase, any(contains(legendText, ...
    "usvseg — no measured band")));
end

function testBatchRecordsAFailureAndCompletes(testCase)
fixture = testCase.TestData.fixture;
context = testCase.TestData.context;
sample = context.sample;
good = context.three_way_example;
broken = good;
broken.example_id = "broken:/example?";
broken.agreement_group_id = 999999;
sample.examples = [good; broken];

gallery = fullfile(fixture.scratch, "gallery-with-failure");
result = vawlume.eda.exportExampleGallery(fixture.conn, sample, gallery, ...
    ExplorationRunKey=context.exploration_run_key, ...
    ReferenceConfigurationId=context.reference_configuration_id, ...
    SourceRoot=fixture.source_root, ResolutionDpi=96);

verifyEqual(testCase, result.status, "complete_with_failures");
verifyEqual(testCase, result.example_count, 2);
verifyEqual(testCase, result.success_count, 1);
verifyEqual(testCase, result.failure_count, 1);
verifyEqual(testCase, height(result.index), 2);
verifyEqual(testCase, result.index.render_status, ["ok"; "failed"]);
verifySubstring(testCase, result.index.render_failure_reason(2), ...
    "ExampleGroupNotFound");
verifyTrue(testCase, isfile(result.index_path));
verifyTrue(testCase, isfile(result.caution_path));

goodImage = fullfile(gallery, replace(result.index.image_path(1), "/", filesep));
failedImage = fullfile(gallery, replace(result.index.image_path(2), "/", filesep));
verifyTrue(testCase, isfile(goodImage));
verifyFalse(testCase, isfile(failedImage));
verifyEqual(testCase, result.index.reference_configuration_id, ...
    repmat(context.reference_configuration_id, 2, 1));
verifyGreaterThan(testCase, ...
    strlength(result.index.spectrogram_settings_json(1)), 20);
verifyEqual(testCase, result.index.spectrogram_settings_json(2), "{}");

caution = string(fileread(result.caution_path));
for paragraph = string(sample.caution)'
    verifyTrue(testCase, contains(caution, paragraph));
end
end

function testASecondExportRequiresExplicitOverwrite(testCase)
fixture = testCase.TestData.fixture;
context = testCase.TestData.context;
sample = context.sample;
sample.examples = context.three_way_example;
gallery = fullfile(fixture.scratch, "protected-gallery");

first = vawlume.eda.exportExampleGallery(fixture.conn, sample, gallery, ...
    ExplorationRunKey=context.exploration_run_key, ...
    ReferenceConfigurationId=context.reference_configuration_id, ...
    SourceRoot=fixture.source_root, ResolutionDpi=96);
verifyEqual(testCase, first.failure_count, 0);

verifyError(testCase, @() vawlume.eda.exportExampleGallery( ...
    fixture.conn, sample, gallery, ...
    ExplorationRunKey=context.exploration_run_key, ...
    ReferenceConfigurationId=context.reference_configuration_id, ...
    SourceRoot=fixture.source_root, ResolutionDpi=96), ...
    "vawlume:eda:GalleryNotEmpty");
end

function context = referenceRun(fixture)
reference = vawlume.eda.referenceConfiguration(RepoRoot=fixture.repo_root);
design = vawlume.eda.referenceDesign(reference);
materialized = vawlume.eda.materializeConfigurations(design, ...
    RepoRoot=fixture.repo_root, OutputRoot=fixture.scratch);
dataset = vawlume.eda.resolveDataset(fixture.conn, ...
    struct(project_key="phase1_synthetic_fixture"));
run = vawlume.eda.runScreen(fixture.conn, dataset, materialized, ...
    RepoRoot=fixture.repo_root, Apply=true, ProbeRole="reference");
agreement = run.manifest.run_key(run.manifest.unit_kind == "agreement" & ...
    ismember(run.manifest.status, ["committed", "reused"]));
sample = vawlume.eda.sampleExamples(fixture.conn, ...
    struct(run_key=agreement(1)), reference, Seed=5);
threeWay = sample.examples(sample.examples.extractor_set_key == ...
    "deepsqueak|mupet|usvseg", :);
context = struct(reference=reference, sample=sample, ...
    exploration_run_key=materialized.exploration_run_key, ...
    reference_configuration_id=design.configurations.configuration_id(1), ...
    three_way_example=threeWay(1, :));
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "examples.sqlite");
copyfile(fixtureTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch));

sampleRate = 192000;
toneHz = 62000;
execute(conn, "UPDATE recordings SET sample_rate_hz=" + string(sampleRate) + ...
    " WHERE recording_id=1");
sourceRoot = fullfile(scratch, "source");
audioPath = fullfile(sourceRoot, "synthetic", "recordings", ...
    "session_social_dyad_01.wav");
mkdir(fileparts(audioPath));
writeToneWav(audioPath, sampleRate, toneHz);

fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    source_root=string(sourceRoot));
end

function writeToneWav(path, sampleRate, toneHz)
durationS = 10.2;
n = round(durationS * sampleRate);
t = (0:(n - 1))' / sampleRate;
samples = zeros(n, 1);
burst = t >= 9.98 & t <= 10.09;
local = t(burst) - 9.98;
taper = sin(pi * local / (local(end) - local(1))) .^ 2;
samples(burst) = 0.7 * taper .* sin(2 * pi * toneHz * t(burst));
audiowrite(char(path), samples, sampleRate, BitsPerSample=16);
end

function path = fixtureTemplate(repoRoot)
persistent value
if isempty(value) || ~isfile(value)
    value = string(tempname) + ".sqlite";
    [conn, ~] = vawlume.db.createPhase1FixtureDatabase(value, repoRoot);
    close(conn);
end
path = value;
end

function tearDown(conn, scratch)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
end

function root = repoRootPath()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function closeIfOpen(handle)
if isgraphics(handle)
    close(handle);
end
end

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end
