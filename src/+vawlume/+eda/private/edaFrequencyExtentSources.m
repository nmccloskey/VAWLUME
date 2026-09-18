function value = edaFrequencyExtentSources()
%EDAFREQUENCYEXTENTSOURCES Contract §L's frequency-extent vocabulary.
%
% One value per member detection, saying what the extractor actually measured and
% therefore what may be drawn:
%
%   band_edges       both min and max registered and measured   -> rectangle
%   center_only      centre only                                -> time extent + marker
%   peak_only        peak only                                  -> time extent + marker
%   center_and_peak  both, no band edges                        -> time extent + two markers
%   unavailable      no frequency measurement                   -> time extent only
%
% THE VOCABULARY IS THE WHOLE POINT OF THE PART. A rectangle asserts that an
% extractor measured a lower and an upper frequency bound; every other value
% asserts that it did not. USVSEG registers `meanfreq`, `maxfreq` and `cvfreq`
% and no band edges at all, so its annotation is `center_and_peak` and must never
% acquire a rectangle. Synthesizing one from the centre, the peak, the
% coefficient of variation, a fixed offset, or assumed call geometry would be
% indistinguishable from a measured extent in the image - and showing what each
% extractor actually reported is the image's entire purpose.
%
% `unavailable` is not an error state. An extractor that reports timing and no
% frequency has still reported something, and a time extent spanning the
% displayed axis is the honest rendering of it.
value = [ ...
    "band_edges"
    "center_only"
    "peak_only"
    "center_and_peak"
    "unavailable"];
end
