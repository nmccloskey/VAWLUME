# Bounded audio windows and acoustic-reference response measurement

Phase 2.6 adds a narrow local-audio boundary and deterministic measurements for
one registered reference on one explicitly selected recording channel. It does
not introduce a DSP framework, normalize calls, rank channels, or infer callers.

## Bounded reader

`vawlume.acoustic.readAudioWindow` resolves the recording's authoritative
`recordings.source_file_id` through `source_files`. Absolute local paths work
directly; relative paths are resolved against the caller's `SourceRoot`. URI
sources, missing files, audio formats that MATLAB cannot inspect, database/file
sample-rate disagreement, and unsupported channel layouts fail explicitly.

```matlab
window = vawlume.acoustic.readAudioWindow(conn, ...
    struct(recording_id=12), 2, 15.0, 17.0, ...
    SourceRoot=sessionFolder);
```

The requested interval is half-open `[start,end)` in native audio seconds.
Seconds are converted to an inclusive `audioread` sample range only after the
request is intersected with file coverage, so the underlying API reads the
bounded sample span. The result separates requested, covered, and actual
sample-aligned read intervals and reports sample rate, sample indices, channel,
recording, source-file identity, linked paths/checksum, duration, and channel
count. Samples retain MATLAB `audioread` full-scale normalization. Raw bytes are
never written.

Reader statuses are `covered_populated`, `partial_populated`, `covered_empty`,
and `not_covered`. QC flags distinguish incomplete coverage, empty/zero-length
windows, and samples at the normalized clipping boundary.

## Measurements

`vawlume.acoustic.measureReferenceResponse` accepts only an
`acoustic_reference_id` and an explicit channel. A channel-specific reference
cannot be measured on a different channel; a recording-wide reference may be
measured independently on any declared channel.

The fixed method `vawlume.acoustic.reference_response` version `1.0.0` computes:

| Metric key | Unit | Definition |
| --- | --- | --- |
| `acoustic_rms_amplitude` | `full_scale_ratio` | square root of the mean squared samples |
| `acoustic_peak_abs_amplitude` | `full_scale_ratio` | maximum absolute sample |
| `acoustic_band_power` | `full_scale_ratio_squared` | two-sided rectangular-bin DFT power selected by folded absolute frequency |

Band power is produced only when both frequency bounds are present, the band has
positive width, and its maximum does not exceed Nyquist. No band is inferred.
The method applies no detrending, window function, calibration, gain correction,
or unit conversion. A full-band selection obeys Parseval under the stated
`sum(abs(fft(x)).^2) / N^2` convention.

The default is read-only planning:

```matlab
preview = vawlume.acoustic.measureReferenceResponse(conn, ...
    struct(acoustic_reference_id=41), 2, SourceRoot=sessionFolder);
```

Persistence is explicit and requires a stable run key:

```matlab
stored = vawlume.acoustic.measureReferenceResponse(conn, ...
    struct(acoustic_reference_id=41), 2, SourceRoot=sessionFolder, ...
    Apply=true, RunKey="session01-reference41-channel2", ...
    VawlumeVersion="prototype-v2", SourceCommit="...");
```

## Persistence and invariants

The built-in semantic seed owns the three `metric_definitions`. Each result is a
`derived_measurements` row whose single target is `acoustic_reference_id` and
whose `recording_channel_id` is a qualifier. Insert/update triggers reject a
qualifying channel from another recording. A partial unique index prevents the
same run/metric/reference/channel evidence from being duplicated.

Every stored row carries JSON method evidence: method/version, sample and
interval conventions, reference/recording/channel identity, source-file ID and
paths/checksum, requested/covered/read bounds, sample indices/count/rate,
explicit reference band, and QC flags. The owning `analysis_runs` row carries
the stable key, status, VAWLUME version, source commit, and caller notes.
Reapplying exactly the same result reuses it. Reusing a run key with changed
provenance, status, or values raises `MeasurementRunConflict`; evidence is never
silently rewritten.

An empty window produces no numeric metrics and a failed result. Partial audio,
clipping, an incomplete/invalid band, or a band above Nyquist is returned as an
explicit warning state. These measurements never overwrite extractor-reported
power or recording metadata and are not normalization factors or caller
evidence.
