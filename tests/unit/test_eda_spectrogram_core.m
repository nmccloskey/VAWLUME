function tests = test_eda_spectrogram_core
%TEST_EDA_SPECTROGRAM_CORE The base-MATLAB spectrogram and its settings record.
%
% Unit tier: this is the one genuinely pure calculation in Part 12, and the one
% whose correctness a picture cannot reveal. A spectrogram computed with the
% wrong window, the wrong frame times or an unreproducible setting still looks
% like a spectrogram.
tests = functiontests({ ...
    @testTheSettingsRecordRegeneratesTheSameMatrix, ...
    @testPerturbingOneSettingChangesTheMatrix, ...
    @testASettingsRecordFromADifferentSampleRateIsRefused, ...
    @testAnIncompleteSettingsRecordIsRefused, ...
    @testTheWindowIsThePeriodicHannFromTheContract, ...
    @testNoSignalProcessingToolboxFunctionIsCalled, ...
    @testATonePeaksInItsOwnFrequencyBin, ...
    @testFrameTimesAreFrameCentresNotLeadingEdges, ...
    @testFramesPastTheEndAreDroppedNotZeroPadded, ...
    @testFrequencyLimitsNeverExceedNyquist, ...
    @testShortSignalsReportNoFramesRatherThanFailing, ...
    @testTheSettingsRecordCarriesEveryContractField, ...
    @testNothingIsDrawn});
end

% ------------------------------------------------------- reproducibility ---

function testTheSettingsRecordRegeneratesTheSameMatrix(testCase)
%TESTTHESETTINGSRECORDREGENERATES... Asserted numerically, not in prose.
%
% The record is what the example index carries. A reader holding an index row and
% the audio must be able to reproduce the picture; if the record were incomplete
% they could not, and nothing in the row would say so.
[samples, sampleRate] = chirpSamples();
first = vawlume.eda.spectrogramMatrix(samples, sampleRate);

second = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    Settings=first.settings);

verifyEqual(testCase, second.matrix, first.matrix);
verifyEqual(testCase, second.time_s, first.time_s);
verifyEqual(testCase, second.frequency_hz, first.frequency_hz);

% Bit-identical, not merely close: the same arithmetic on the same inputs.
verifyTrue(testCase, isequal(second.matrix, first.matrix), ...
    "The regenerated matrix differs from the original in some bit.");

% And a non-default configuration round-trips too, so the record is not just
% reproducing a set of defaults it never varied from.
custom = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    WindowLengthSamples=64, HopSamples=17, FftLength=128, ...
    Scaling="power", FrequencyLimitsHz=[1000 6000]);
verifyEqual(testCase, vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    Settings=custom.settings).matrix, custom.matrix);
end

function testPerturbingOneSettingChangesTheMatrix(testCase)
%TESTPERTURBINGONESETTING... Verified as a negative result, one field at a time.
%
% A reproducibility test passes trivially if the settings do not actually drive
% the computation - a record could be decorative and the test would not notice.
% Each computational field is perturbed on its own and asserted to change the
% result, which is what makes the round-trip above meaningful.
[samples, sampleRate] = chirpSamples();
baseline = vawlume.eda.spectrogramMatrix(samples, sampleRate);

perturbations = { ...
    "window_length_samples", 2 * baseline.settings.window_length_samples; ...
    "hop_samples",           baseline.settings.hop_samples + 3; ...
    "fft_length",            2 * baseline.settings.fft_length; ...
    "scaling",               "power"};

for index = 1:size(perturbations, 1)
    name = perturbations{index, 1};
    settings = baseline.settings;
    settings.(name) = perturbations{index, 2};
    perturbed = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
        Settings=settings);
    verifyFalse(testCase, isequal(perturbed.matrix, baseline.matrix), ...
        "Changing " + name + " left the matrix identical, so that field " + ...
        "does not drive the computation it claims to record.");
end

% The frequency limits change which bins survive rather than the arithmetic,
% and are asserted on the frequency vector for that reason.
settings = baseline.settings;
settings.frequency_limits_hz = [2000, 5000];
narrowed = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    Settings=settings);
verifyLessThan(testCase, numel(narrowed.frequency_hz), ...
    numel(baseline.frequency_hz));
end

function testASettingsRecordFromADifferentSampleRateIsRefused(testCase)
[samples, sampleRate] = chirpSamples();
record = vawlume.eda.spectrogramMatrix(samples, sampleRate).settings;

verifyError(testCase, @() vawlume.eda.spectrogramMatrix(samples, ...
    2 * sampleRate, Settings=record), ...
    "vawlume:eda:SpectrogramSampleRateMismatch");
end

function testAnIncompleteSettingsRecordIsRefused(testCase)
[samples, sampleRate] = chirpSamples();
record = vawlume.eda.spectrogramMatrix(samples, sampleRate).settings;
record = rmfield(record, "hop_samples");

verifyError(testCase, @() vawlume.eda.spectrogramMatrix(samples, ...
    sampleRate, Settings=record), ...
    "vawlume:eda:SpectrogramSettingsIncomplete");
end

% --------------------------------------------------------- the toolbox rule ---

function testTheWindowIsThePeriodicHannFromTheContract(testCase)
%TESTTHEWINDOWISTHEPERIODICHANN... Periodic, not symmetric, and it matters.
%
% The symmetric window divides by N-1 and has w(0) = w(N-1) = 0; the periodic one
% divides by N and has w(N-1) > 0. `hann(N)` returns the symmetric form - and is
% a toolbox function besides. Contract §M fixes the periodic form because
% consecutive frames then tile without a seam.
%
% The window is verified through its effect rather than by reading the source: a
% single impulse at sample k, framed from the start, is scaled by exactly w(k),
% so the transform of that frame is flat at |w(k)|.
n = 16;
sampleRate = 1000;
expected = 0.5 * (1 - cos(2 * pi * (0:(n - 1))' / n));

for k = [1 4 8 12]
    samples = zeros(n, 1);
    samples(k + 1) = 1;
    result = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
        WindowLengthSamples=n, HopSamples=n, FftLength=n, ...
        Scaling="power");
    verifyEqual(testCase, result.frame_count, 1);
    % A windowed impulse transforms to a constant-magnitude spectrum.
    verifyEqual(testCase, sqrt(result.matrix(:, 1)), ...
        repmat(expected(k + 1), size(result.matrix, 1), 1), ...
        "The window value at sample " + k + " is not the periodic Hann one.", ...
        AbsTol=1e-12);
end

% The periodic window's last sample is nonzero; the symmetric one's is zero.
% This is the assertion that fails if someone substitutes hann(N).
verifyGreaterThan(testCase, expected(end), 0);
samples = zeros(n, 1);
samples(n) = 1;
tail = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    WindowLengthSamples=n, HopSamples=n, FftLength=n, Scaling="power");
verifyGreaterThan(testCase, max(tail.matrix(:)), 0, ...
    "The final window sample is zero, which is the symmetric Hann window.");
end

function testNoSignalProcessingToolboxFunctionIsCalled(testCase)
%TESTNOSIGNALPROCESSINGTOOLBOX... Asserted by inspection, per the itinerary.
%
% The repository depends on the Database Toolbox and nothing else. Adding a
% Signal Processing dependency for an illustration would make the entire
% exploratory workflow unavailable to a base-MATLAB user, which is a steep price
% for a window function that is one line of arithmetic.
forbidden = ["spectrogram(", "stft(", "hann(", "hamming(", "blackman(", ...
    "kaiser(", "pwelch(", "periodogram(", "bandpass(", "lowpass(", ...
    "highpass(", "resample(", "envelope(", "findpeaks("];
root = repoRootPath();
files = ["src/+vawlume/+eda/spectrogramMatrix.m", ...
    "src/+vawlume/+eda/prepareExample.m", ...
    "src/+vawlume/+eda/sampleExamples.m", ...
    "src/+vawlume/+eda/private/edaMemberAnnotations.m"];

for name = files
    source = codeOnly(fileread(fullfile(root, name)));
    for token = forbidden
        verifyEqual(testCase, numel(strfind(source, token)), 0, ...
            name + " calls '" + token + "', a Signal Processing Toolbox " + ...
            "function.");
    end
    % The one permitted spectral call, and the only one.
    verifyEqual(testCase, numel(strfind(source, "spectrogram(")), 0);
end

implementation = codeOnly(fileread(fullfile(root, files(1))));
verifyGreaterThan(testCase, numel(strfind(implementation, "fft(")), 0, ...
    "The implementation does not call fft, so it is computing the " + ...
    "spectrum some other way.");
end

% ------------------------------------------------------------ correctness ---

function testATonePeaksInItsOwnFrequencyBin(testCase)
%TESTATONEPEAKSINITSOWNBIN... The transform is a transform.
%
% Without this the suite could pass against an implementation that returns a
% plausible matrix of the right shape and the wrong contents.
sampleRate = 8000;
n = 4096;
toneHz = 1000;
t = (0:(n - 1))' / sampleRate;
samples = sin(2 * pi * toneHz * t);

result = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    WindowLengthSamples=256, HopSamples=128, FftLength=256, ...
    Scaling="power");

[~, peakBin] = max(mean(result.matrix, 2));
verifyEqual(testCase, result.frequency_hz(peakBin), toneHz, AbsTol=sampleRate / 256);

% A second tone moves the peak, so the peak is about the signal.
higher = sin(2 * pi * 3000 * t);
shifted = vawlume.eda.spectrogramMatrix(higher, sampleRate, ...
    WindowLengthSamples=256, HopSamples=128, FftLength=256, Scaling="power");
[~, shiftedBin] = max(mean(shifted.matrix, 2));
verifyEqual(testCase, shifted.frequency_hz(shiftedBin), 3000, ...
    AbsTol=sampleRate / 256);
end

function testFrameTimesAreFrameCentresNotLeadingEdges(testCase)
%TESTFRAMETIMESAREFRAMECENTRES... Half a window of displacement is invisible.
%
% A reader compares an annotation's onset against the image. Labelling frames by
% their leading edge displaces every feature by half a window - which on a 4 ms
% frame is 2 ms, about a tenth of a mouse call, and looks exactly like a timing
% disagreement between extractors.
sampleRate = 1000;
windowLength = 100;
hop = 50;
samples = zeros(500, 1);

result = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    WindowLengthSamples=windowLength, HopSamples=hop, Scaling="power");

expectedFirst = ((windowLength - 1) / 2) / sampleRate;
verifyEqual(testCase, result.time_s(1), expectedFirst, AbsTol=1e-12);
verifyEqual(testCase, diff(result.time_s(1:2)), hop / sampleRate, ...
    AbsTol=1e-12);
verifyEqual(testCase, result.settings.frame_time_convention, "frame centre");
end

function testFramesPastTheEndAreDroppedNotZeroPadded(testCase)
%TESTFRAMESPASTTHEENDAREDROPPED... A padded frame invents a broadband edge.
%
% Zero-padding the final frame produces a step at the signal's end, which
% transforms to a broadband vertical stripe indistinguishable from a click. An
% illustration that stops a few milliseconds early is better than one that
% fabricates a transient.
sampleRate = 1000;
windowLength = 64;
hop = 32;
sampleCount = 200;
samples = ones(sampleCount, 1);

result = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    WindowLengthSamples=windowLength, HopSamples=hop, Scaling="power");

expectedFrames = numel(1:hop:(sampleCount - windowLength + 1));
verifyEqual(testCase, result.frame_count, expectedFrames);

% Every frame lies wholly inside the signal.
lastFrameStart = (result.time_s(end) * sampleRate) - (windowLength - 1) / 2;
verifyLessThanOrEqual(testCase, lastFrameStart + windowLength, sampleCount + 1);
verifySubstring(testCase, result.settings.partial_frame_policy, ...
    "never zero-padded");
end

function testFrequencyLimitsNeverExceedNyquist(testCase)
sampleRate = 1000;
samples = randnLike(2000);

result = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    FrequencyLimitsHz=[0, 50000]);

verifyLessThanOrEqual(testCase, max(result.frequency_hz), sampleRate / 2);
verifyEqual(testCase, result.settings.frequency_limits_hz(2), sampleRate / 2);

verifyError(testCase, @() vawlume.eda.spectrogramMatrix(samples, ...
    sampleRate, FrequencyLimitsHz=[NaN 100]), ...
    "vawlume:eda:SpectrogramLimitsInvalid");
end

function testShortSignalsReportNoFramesRatherThanFailing(testCase)
%TESTSHORTSIGNALSREPORTNOFRAMES... An empty result is a state, not a crash.
result = vawlume.eda.spectrogramMatrix(zeros(3, 1), 1000, ...
    WindowLengthSamples=64);
verifyEqual(testCase, result.status, "no_frames");
verifyEqual(testCase, result.frame_count, 0);
verifyEqual(testCase, size(result.matrix, 2), 0);

empty = vawlume.eda.spectrogramMatrix(zeros(0, 1), 1000);
verifyEqual(testCase, empty.status, "no_frames");
end

% ------------------------------------------------------------ the record ---

function testTheSettingsRecordCarriesEveryContractField(testCase)
%TESTTHESETTINGSRECORDCARRIESEVERY... Contract §M's list, verbatim.
[samples, sampleRate] = chirpSamples();
record = vawlume.eda.spectrogramMatrix(samples, sampleRate, ...
    PaddingPreS=0.05, PaddingPostS=0.07, ChannelIndex=2).settings;

required = ["method_key", "method_version", "window_type", ...
    "window_length_samples", "hop_samples", "fft_length", "sample_rate_hz", ...
    "scaling", "frequency_limits_hz", "padding_pre_s", "padding_post_s", ...
    "channel_index"];
for name = required
    verifyTrue(testCase, isfield(record, name), ...
        "Contract §M requires settings field " + name + ".");
end

verifyEqual(testCase, record.method_key, "vawlume.eda.spectrogram");
verifyEqual(testCase, record.window_type, "periodic_hann");
verifyEqual(testCase, record.padding_pre_s, 0.05);
verifyEqual(testCase, record.padding_post_s, 0.07);
verifyEqual(testCase, record.channel_index, 2);
verifySubstring(testCase, record.window_formula, "0.5*(1 - cos(2*pi*n/N))");

% The whole record survives JSON, because the example index carries it as a
% JSON column and a record that cannot be serialized cannot be indexed.
encoded = jsonencode(record);
decoded = jsondecode(encoded);
verifyEqual(testCase, decoded.window_length_samples, ...
    record.window_length_samples);
verifyEqual(testCase, string(decoded.window_type), record.window_type);
end

function testNothingIsDrawn(testCase)
%TESTNOTHINGISDRAWN... Boundary 10, asserted rather than trusted.
before = findall(0, "Type", "figure");
[samples, sampleRate] = chirpSamples();
vawlume.eda.spectrogramMatrix(samples, sampleRate);
after = findall(0, "Type", "figure");
verifyEqual(testCase, numel(after), numel(before), ...
    "A figure was created by a function that computes values.");

root = repoRootPath();
forbidden = ["figure(", "axes(", "imagesc(", "pcolor(", "surf(", "plot(", ...
    "exportgraphics(", "saveas(", "print(", "imwrite("];
for name = ["spectrogramMatrix.m", "prepareExample.m", "sampleExamples.m"]
    source = codeOnly(fileread(fullfile(root, "src", "+vawlume", "+eda", name)));
    for token = forbidden
        verifyEqual(testCase, numel(strfind(source, token)), 0, ...
            name + " calls '" + token + "'.");
    end
end
end

% ---------------------------------------------------------------- helpers ---

function [samples, sampleRate] = chirpSamples()
%CHIRPSAMPLES A deterministic sweep, written out rather than synthesized.
%
% No `chirp` call: that is a Signal Processing Toolbox function too, and a test
% that reached for it to test a no-toolbox rule would be its own refutation.
sampleRate = 16000;
n = 4096;
t = (0:(n - 1))' / sampleRate;
instantaneous = 500 + (4000 - 500) * (t / t(end));
samples = 0.8 * sin(2 * pi * cumsum(instantaneous) / sampleRate);
end

function value = randnLike(n)
%RANDNLIKE Deterministic pseudo-noise from a local stream.
%
% A local RandStream rather than `randn`, so this test cannot be perturbed by
% another test's global seeding and cannot perturb one.
stream = RandStream("mt19937ar", Seed=1234);
value = randn(stream, n, 1);
end

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function value = codeOnly(source)
lines = splitlines(string(source));
value = strjoin(lines(~startsWith(strtrim(lines), "%")), newline);
end

function value = repoRootPath()
value = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
