function result = exportExampleGallery(conn, sample, galleryDirectory, options)
%EXPORTEXAMPLEGALLERY Render a sampled gallery and its fixed example index.
%
% A failure preparing or rendering one example is recorded in that example's
% index row and does not abandon the batch. A non-empty destination is refused
% unless Overwrite=true; explicit overwrite replaces colliding generated files
% but does not delete unrelated or stale files.

arguments
    conn
    sample (1,1) struct
    galleryDirectory (1,1) string
    options.ExplorationRunKey (1,1) string = ""
    options.ReferenceConfigurationId (1,1) string = ""
    options.ProjectKey (1,1) string = ""
    options.SourceRoot (1,1) string = ""
    options.ChannelIndex double = []
    options.PaddingPreS (1,1) double {mustBeNonnegative} = 0.05
    options.PaddingPostS (1,1) double {mustBeNonnegative} = 0.05
    options.FrequencyMarginHz (1,1) double {mustBeNonnegative} = 10000
    options.DefaultFrequencyLimitsHz (1,2) double = [20000 120000]
    options.ResolutionDpi (1,1) double {mustBePositive} = 300
    options.Overwrite (1,1) logical = false
end

requireSample(sample);
if strlength(options.ExplorationRunKey) == 0
    error("vawlume:eda:ExplorationRunKeyMissing", ...
        "ExplorationRunKey is required so every index row identifies its run.");
end
assertDestination(galleryDirectory, options.Overwrite);
if ~isfolder(galleryDirectory)
    mkdir(galleryDirectory);
end
imagesDirectory = fullfile(galleryDirectory, "images");
if ~isfolder(imagesDirectory)
    mkdir(imagesDirectory);
end

referenceId = options.ReferenceConfigurationId;
if strlength(referenceId) == 0
    checksum = string(sample.reference_configuration.checksum_sha256);
    if strlength(checksum) < 10
        error("vawlume:eda:ReferenceChecksumInvalid", ...
            "A reference configuration id cannot be derived from the sample.");
    end
    referenceId = "ref-" + extractBefore(checksum, 11);
end

styles = vawlume.eda.exampleStyles(extractorKeys(sample.examples));
index = emptyIndex();
for at = 1:height(sample.examples)
    example = sample.examples(at, :);
    filename = vawlume.eda.exampleFilename(example.example_id, at);
    relativePath = "images/" + filename;
    outputPath = fullfile(imagesDirectory, filename);
    row = baseRow(conn, example, sample, options, referenceId, relativePath);
    rendered = struct([]);
    try
        prepared = vawlume.eda.prepareExample(conn, example, ...
            "PaddingPreS", options.PaddingPreS, ...
            "PaddingPostS", options.PaddingPostS, ...
            "ChannelIndex", options.ChannelIndex, ...
            "SourceRoot", options.SourceRoot, ...
            "FrequencyMarginHz", options.FrequencyMarginHz, ...
            "DefaultFrequencyLimitsHz", options.DefaultFrequencyLimitsHz);
        row = populatePrepared(row, prepared);
        rendered = vawlume.eda.renderExample(prepared, Styles=styles, ...
            ReferenceConfigurationId=referenceId, Visible=false);
        exportgraphics(rendered.figure, outputPath, ...
            Resolution=options.ResolutionDpi);
        close(rendered.figure);
        row.render_status = "ok";
        row.render_failure_reason = "";
    catch exception
        if ~isempty(rendered) && isfield(rendered, "figure") && ...
                isgraphics(rendered.figure)
            close(rendered.figure);
        end
        row.render_status = "failed";
        row.render_failure_reason = failureText(exception);
    end
    index = [index; row]; %#ok<AGROW>
end

indexPath = fullfile(galleryDirectory, "example_index.csv");
writeResult = vawlume.eda.writeExampleIndex(index, indexPath, ...
    Overwrite=options.Overwrite);
cautionPath = fullfile(galleryDirectory, "example_index_caution.txt");
writelines(strjoin(string(sample.caution), ...
    string(newline) + string(newline)), cautionPath, ...
    Encoding="UTF-8");
failureCount = sum(index.render_status == "failed");
result = struct(status=statusOf(failureCount), ...
    gallery_directory=galleryDirectory, images_directory=imagesDirectory, ...
    index_path=indexPath, caution_path=cautionPath, index=index, styles=styles, ...
    example_count=height(index), success_count=height(index)-failureCount, ...
    failure_count=failureCount, index_write=writeResult, ...
    layout="<gallery>/images/*.png, <gallery>/example_index.csv, and " + ...
        "<gallery>/example_index_caution.txt", ...
    overwrite_note="Overwrite=true replaces colliding generated files but " + ...
        "does not delete unrelated or stale files.", ...
    caution=sample.caution);
end

function requireSample(sample)
required = ["examples", "reference_configuration", "caution"];
missingNames = required(~isfield(sample, required));
if ~isempty(missingNames)
    error("vawlume:eda:ExampleSampleIncomplete", ...
        "The sample is missing field(s): %s.", strjoin(missingNames, ", "));
end
end

function assertDestination(path, overwrite)
if ~isfolder(path) || overwrite
    return
end
entries = dir(path);
entries = entries(~ismember({entries.name}, {'.', '..'}));
if ~isempty(entries)
    error("vawlume:eda:GalleryNotEmpty", ...
        "Gallery directory '%s' is not empty. Pass Overwrite=true only when " + ...
        "replacing its generated artifacts is intentional.", path);
end
end

function keys = extractorKeys(examples)
keys = strings(0, 1);
for value = examples.extractor_set_key'
    keys = [keys; split(value, "|")]; %#ok<AGROW>
end
keys = unique(keys(strlength(keys) > 0));
end

function row = baseRow(conn, example, sample, options, referenceId, imagePath)
row = emptyIndex();
row(1, :) = {"1.0", string(example.example_id), ...
    options.ExplorationRunKey, referenceId, ...
    string(sample.reference_configuration.version_label), ...
    resolveProjectKey(conn, example, options.ProjectKey), ...
    double(example.recording_id), string(example.native_recording_id), ...
    string(example.supported_extractor_pair_pattern), "", "", "", "", ...
    NaN, NaN, NaN, NaN, NaN, "{}", imagePath, "failed", ...
    "the example was not attempted"};
end

function key = resolveProjectKey(conn, example, supplied)
if strlength(supplied) > 0
    key = supplied;
    return
end
rows = fetch(conn, "SELECT IFNULL(p.project_key,'') AS project_key " + ...
    "FROM recordings r JOIN projects p ON p.project_id=r.project_id " + ...
    "WHERE r.recording_id=" + string(double(example.recording_id)));
key = "";
if ~isempty(rows) && height(rows) > 0
    key = string(rows.project_key(1));
end
end

function row = populatePrepared(row, prepared)
members = prepared.annotations;
row.member_detection_ids = joinNumbers(members.detection_id);
row.member_extractor_keys = strjoin(members.extractor_key', "|");
row.member_native_event_ids = strjoin(members.native_event_id', "|");
row.frequency_extent_sources = strjoin( ...
    members.frequency_extent_source', "|");
row.group_start_time_s = prepared.group_extent.start_time_s;
row.group_end_time_s = prepared.group_extent.end_time_s;
row.snippet_window_start_s = prepared.window.actual_start_s;
row.snippet_window_end_s = prepared.window.actual_end_s;
row.snippet_channel_index = prepared.channel.channel_index;
if isfield(prepared.spectrogram, "settings")
    row.spectrogram_settings_json = string(jsonencode( ...
        prepared.spectrogram.settings));
end
end

function value = joinNumbers(numbers)
value = strjoin(compose("%.0f", double(numbers(:)))', "|");
end

function value = failureText(exception)
value = string(exception.identifier) + ": " + ...
    replace(string(exception.message), [newline, char(13)], " ");
value = strtrim(value);
end

function value = statusOf(failureCount)
value = "complete";
if failureCount > 0
    value = "complete_with_failures";
end
end

function value = emptyIndex()
value = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=edaExampleIndexColumns());
end
