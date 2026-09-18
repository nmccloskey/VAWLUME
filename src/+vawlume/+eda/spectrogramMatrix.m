function result = spectrogramMatrix(samples, sampleRateHz, options)
%SPECTROGRAMMATRIX A short-time spectrum in base MATLAB, with a settings record.
%
% RESULT = vawlume.eda.SPECTROGRAMMATRIX(SAMPLES, SAMPLERATEHZ) returns the
% time-frequency matrix, its time and frequency vectors, and a settings record
% that regenerates the same matrix from the same samples.
%
% Name-value options:
%   WindowLengthSamples  frame length; default the power of two nearest 4 ms
%   HopSamples           advance between frames; default 50% overlap
%   FftLength            transform length; default the window length
%   Scaling              "power_db" (default) or "power"
%   FrequencyLimitsHz    [low high] retained band; default [0 Nyquist]
%   FloorDb              lower clamp for power_db, default -120
%   PaddingPreS / PaddingPostS / ChannelIndex
%                        carried into the record for the example index; they do
%                        not affect the matrix
%   Settings             a previously returned settings record, which overrides
%                        every computational option above
%
% NO SIGNAL PROCESSING TOOLBOX FUNCTION IS CALLED. `spectrogram`, `stft`, `hann`
% and `hamming` all live in that toolbox, and the repository does not depend on
% it: the only other spectral computation in `src/` is `fft` at
% measureReferenceResponse.m:153, which writes its method out rather than
% reaching for a toolbox. Adding the dependency for an illustration would make
% the entire exploratory workflow unavailable to a base-MATLAB user, which is a
% high price for a window function that is one line:
%
%   w(n) = 0.5 * (1 - cos(2*pi*n/N)),  n = 0 .. N-1
%
% That is the PERIODIC Hann window, not the symmetric one. The distinction
% matters and is easy to get wrong: `hann(N)` returns the symmetric window with
% `w(0) = w(N-1) = 0`, while the periodic form divides by N rather than N-1 and
% is the correct choice for spectral analysis because consecutive frames then
% tile without a seam. Contract §M fixes the periodic form explicitly.
%
% THE SETTINGS RECORD MUST REGENERATE THE MATRIX, and that is tested numerically
% rather than asserted in prose. Pass the returned record back as Settings= and
% the same samples, and the matrix is identical to the last bit. The record is
% what the example index carries, so a reader holding an index row and the audio
% can reproduce the picture; if the record were incomplete they could not, and
% nothing in the row would reveal it.
%
% THIS FUNCTION DRAWS NOTHING. It creates no figure, no axes and no image file -
% boundary 10 puts the line here, because a function returning a figure cannot be
% asserted on cheaply and a renderer that also computes cannot be tested apart
% from its rendering.
%
% Samples are consumed exactly as `readAudioWindow` returns them: audioread
% normalized full-scale ratios, with no calibration, normalization, detrending or
% filtering applied here or anywhere upstream.

arguments
    samples double {mustBeVector(samples, "allow-all-empties")}
    sampleRateHz (1,1) double {mustBePositive}
    options.WindowLengthSamples double = []
    options.HopSamples double = []
    options.FftLength double = []
    options.Scaling (1,1) string ...
        {mustBeMember(options.Scaling, ["power_db", "power"])} = "power_db"
    options.FrequencyLimitsHz double = []
    options.FloorDb (1,1) double = -120
    options.PaddingPreS (1,1) double = NaN
    options.PaddingPostS (1,1) double = NaN
    options.ChannelIndex (1,1) double = NaN
    options.Settings struct = struct([])
end

options = applySettings(options, sampleRateHz);
plan = resolvePlan(samples, sampleRateHz, options);

[matrix, timeS] = transform(samples(:), plan);
[matrix, frequencyHz] = restrictBand(matrix, plan);
matrix = scaleMatrix(matrix, plan);

result = struct( ...
    status=statusOf(plan, matrix), ...
    status_note=statusNote(plan, matrix), ...
    matrix=matrix, ...
    time_s=timeS, ...
    frequency_hz=frequencyHz, ...
    frame_count=size(matrix, 2), ...
    bin_count=size(matrix, 1), ...
    sample_count=numel(samples), ...
    settings=settingsRecord(plan, options), ...
    sample_semantics="MATLAB audioread normalized full-scale ratio; no " + ...
        "calibration, normalization, detrending or filtering is applied", ...
    window_definition="periodic Hann, w(n) = 0.5*(1 - cos(2*pi*n/N)) for " + ...
        "n = 0..N-1, computed inline", ...
    toolbox_note="computed with base MATLAB fft only; no Signal Processing " + ...
        "Toolbox function is called", ...
    draws_nothing="this function returns values and creates no figure, axes " + ...
        "or image file");
end

% ------------------------------------------------------------------- plan ---

function options = applySettings(options, sampleRateHz)
%APPLYSETTINGS A returned record overrides every computational option.
%
% All or nothing, deliberately. Letting a caller supply a record AND override one
% field would produce a matrix that no record describes, which is precisely the
% failure the record exists to prevent.
if isempty(fieldnames(options.Settings))
    return
end
settings = options.Settings;
required = ["window_length_samples", "hop_samples", "fft_length", ...
    "sample_rate_hz", "scaling", "frequency_limits_hz"];
missingNames = required(~isfield(settings, required));
if ~isempty(missingNames)
    error("vawlume:eda:SpectrogramSettingsIncomplete", ...
        "The supplied settings record is missing field(s): %s. A record " + ...
        "that cannot regenerate its matrix is not a settings record.", ...
        strjoin(missingNames, ", "));
end
if double(settings.sample_rate_hz) ~= sampleRateHz
    error("vawlume:eda:SpectrogramSampleRateMismatch", ...
        "The settings record was made at %.17g Hz and the samples are at " + ...
        "%.17g Hz, so regenerating would silently rescale every frequency.", ...
        double(settings.sample_rate_hz), sampleRateHz);
end
options.WindowLengthSamples = double(settings.window_length_samples);
options.HopSamples = double(settings.hop_samples);
options.FftLength = double(settings.fft_length);
options.Scaling = string(settings.scaling);
options.FrequencyLimitsHz = double(settings.frequency_limits_hz);
if isfield(settings, "floor_db")
    options.FloorDb = double(settings.floor_db);
end
end

function plan = resolvePlan(samples, sampleRateHz, options)
count = numel(samples);
windowLength = options.WindowLengthSamples;
if isempty(windowLength)
    windowLength = defaultWindowLength(sampleRateHz);
end
% NOT clamped to the sample count. Shrinking the window to fit a short signal
% would change the frequency resolution without saying so - a three-sample window
% on a 384 kHz recording gives 128 kHz bins, which is a meaningless spectrum
% returned under a `computed` status. A signal shorter than its window yields no
% frames and says why, and the caller widens the snippet or narrows the window
% deliberately.
windowLength = max(round(windowLength), 2);

hop = options.HopSamples;
if isempty(hop)
    hop = max(1, floor(windowLength / 2));
end
hop = max(1, round(hop));

fftLength = options.FftLength;
if isempty(fftLength)
    fftLength = windowLength;
end
fftLength = max(round(fftLength), windowLength);

limits = options.FrequencyLimitsHz;
if isempty(limits)
    limits = [0, sampleRateHz / 2];
end
limits = clampLimits(limits, sampleRateHz);

plan = struct( ...
    window_length=windowLength, ...
    hop=hop, ...
    fft_length=fftLength, ...
    sample_rate=sampleRateHz, ...
    scaling=options.Scaling, ...
    limits=limits, ...
    floor_db=options.FloorDb, ...
    sample_count=count);
end

function value = defaultWindowLength(sampleRateHz)
%DEFAULTWINDOWLENGTH About 4 ms, rounded to a power of two.
%
% A mouse ultrasonic call is tens of milliseconds, so a 4 ms frame resolves its
% frequency contour without smearing the onset. The power of two is for the FFT,
% not for the physics. This is a DEFAULT, recorded in the settings like every
% other choice, not a calibrated value.
target = 0.004 * sampleRateHz;
value = 2 ^ max(1, round(log2(max(target, 2))));
end

function value = clampLimits(limits, sampleRateHz)
%CLAMPLIMITS Nothing above Nyquist, and low below high.
%
% A limit above Nyquist is not an error worth refusing - a caller derives limits
% from measured call frequencies and a low-rate recording simply cannot show them
% - but silently returning bins that do not exist would be. Clamped, and the
% caller's own record says what was requested.
if numel(limits) ~= 2 || any(~isfinite(limits))
    error("vawlume:eda:SpectrogramLimitsInvalid", ...
        "FrequencyLimitsHz must be a finite two-element [low high].");
end
nyquist = sampleRateHz / 2;
value = [max(min(limits), 0), min(max(limits), nyquist)];
if value(2) <= value(1)
    value = [0, nyquist];
end
end

% -------------------------------------------------------------- transform ---

function [matrix, timeS] = transform(samples, plan)
%TRANSFORM Frame, window, and transform - base MATLAB throughout.
%
% Frames that would run past the end of the signal are DROPPED rather than
% zero-padded. A zero-padded final frame shows a spurious broadband edge that
% looks like a click, and an illustration that invents a transient is worse than
% one that stops a few milliseconds early.
count = plan.sample_count;
starts = 1:plan.hop:max(count - plan.window_length + 1, 0);
if isempty(starts) || count < plan.window_length
    matrix = zeros(floor(plan.fft_length / 2) + 1, 0);
    timeS = zeros(1, 0);
    return
end

window = periodicHann(plan.window_length);
frameCount = numel(starts);
binCount = floor(plan.fft_length / 2) + 1;
matrix = zeros(binCount, frameCount);
for index = 1:frameCount
    first = starts(index);
    frame = samples(first:(first + plan.window_length - 1)) .* window;
    spectrum = fft(frame, plan.fft_length);
    matrix(:, index) = abs(spectrum(1:binCount)) .^ 2;
end

% The frame's time is its CENTRE, not its start. A reader comparing an
% annotation's onset against the image is comparing against the middle of
% whatever frame shows it, and labelling frames by their leading edge would
% displace every feature by half a window.
timeS = ((starts - 1) + (plan.window_length - 1) / 2) / plan.sample_rate;
end

function value = periodicHann(length)
%PERIODICHANN Contract §M's window, written out.
%
% PERIODIC, not symmetric: the divisor is N, not N-1. `hann(N)` returns the
% symmetric form and is a Signal Processing Toolbox function besides. The
% periodic form is the right one for spectral analysis because consecutive
% frames tile without a seam.
n = (0:(length - 1))';
value = 0.5 * (1 - cos(2 * pi * n / length));
end

function [matrix, frequencyHz] = restrictBand(matrix, plan)
binCount = size(matrix, 1);
frequencyHz = (0:(binCount - 1))' * (plan.sample_rate / plan.fft_length);
selected = frequencyHz >= plan.limits(1) & frequencyHz <= plan.limits(2);
if ~any(selected)
    % Keep the nearest single bin rather than returning an empty matrix: an
    % empty image and a narrow one are different failures, and the second is
    % recoverable by widening the limits.
    [~, nearest] = min(abs(frequencyHz - mean(plan.limits)));
    selected = false(binCount, 1);
    selected(nearest) = true;
end
matrix = matrix(selected, :);
frequencyHz = frequencyHz(selected);
end

function matrix = scaleMatrix(matrix, plan)
if plan.scaling == "power"
    return
end
% Power in decibels, floored. The floor is recorded: an unrecorded floor would
% make two images of the same audio differ in contrast for a reason neither
% carries.
matrix = 10 * log10(max(matrix, 0) + realmin);
matrix = max(matrix, plan.floor_db);
end

% ----------------------------------------------------------------- record ---

function value = settingsRecord(plan, options)
%SETTINGSRECORD Contract §M's fields, in the style of derivationDetails.
%
% `padding_pre_s`, `padding_post_s` and `channel_index` describe the WINDOW the
% samples came from rather than the transform applied to them, so they do not
% affect the matrix and are carried here because the example index needs one
% record rather than two. Everything above them does affect the matrix, and
% passing this record back reproduces it exactly.
value = struct( ...
    method_key="vawlume.eda.spectrogram", ...
    method_version="1.0.0", ...
    window_type="periodic_hann", ...
    window_length_samples=plan.window_length, ...
    hop_samples=plan.hop, ...
    overlap_samples=max(plan.window_length - plan.hop, 0), ...
    fft_length=plan.fft_length, ...
    sample_rate_hz=plan.sample_rate, ...
    scaling=plan.scaling, ...
    floor_db=plan.floor_db, ...
    frequency_limits_hz=plan.limits, ...
    padding_pre_s=options.PaddingPreS, ...
    padding_post_s=options.PaddingPostS, ...
    channel_index=options.ChannelIndex, ...
    window_formula="0.5*(1 - cos(2*pi*n/N)), n = 0..N-1", ...
    transform="base MATLAB fft; one-sided magnitude squared", ...
    frame_time_convention="frame centre", ...
    partial_frame_policy="frames past the end of the signal are dropped, " + ...
        "never zero-padded");
end

function value = statusOf(plan, matrix)
if plan.sample_count < plan.window_length || size(matrix, 2) == 0
    value = "no_frames";
    return
end
value = "computed";
end

function value = statusNote(plan, matrix)
if plan.sample_count < plan.window_length
    value = "the window is " + string(plan.window_length) + " samples and " + ...
        "the signal is " + string(plan.sample_count) + "; a shorter window " + ...
        "would change the frequency resolution silently, so none was " + ...
        "substituted. Widen the snippet or set WindowLengthSamples.";
    return
end
if size(matrix, 2) == 0
    value = "no frame fits wholly inside the signal at this window and hop.";
    return
end
value = "";
end
