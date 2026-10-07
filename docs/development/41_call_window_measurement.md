# Call-window acoustic measurement

Added in Phase 6 (itinerary 6.6). The governing decision is D6 of
[`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md).
The model is the reference-response method in
[`27_audio_window_and_response_measurement.md`](27_audio_window_and_response_measurement.md).

Development plan §11.1 steps 1–2 ask VAWLUME to *identify the audio window* of a
vocal event and *obtain comparable channel measurements*. One function does
that, and only that:

```matlab
preview = vawlume.acoustic.measureCallWindow(conn, struct(detection_id=12), ...
    [1 2], BandHz=[30000 90000], SourceRoot=sessionFolder);

stored = vawlume.acoustic.measureCallWindow(conn, struct(detection_id=12), ...
    [1 2], BandHz=[30000 90000], SourceRoot=sessionFolder, ...
    Apply=true, RunKey="session01-d12-calls", VawlumeVersion="prototype-v2");
```

It **normalizes nothing and compares no channels**. A normalized level, a level
difference and anything built on them belong to later operations (contract D6,
"Normalization" and "The level difference").

## One core, two methods

Reference measurement and call measurement share one private function,
`+acoustic/private/acousticWindowMetrics.m`. It holds doc 27's conventions once:
RMS, peak absolute amplitude, and two-sided rectangular-bin DFT band power
normalized by `N²`, with no detrending, window function, calibration or gain.
It returns neutral metric names, and each method adds its own keys.

When the core was extracted, reference measurement was proven **bit-identical**
before and after: the same results, rows and method evidence, compared as raw
IEEE bits, on the reference-measurement test fixture, a random-noise fixture
covering every band branch, and the multimodal demonstration's 24
measurements. The integration suite also checks that a reference and a call
over the same interval, channel and band give bit-identical numbers.

## The method

`vawlume.acoustic.call_window_response`, version `1.0.0`.

| Metric key | Unit | Definition |
| --- | --- | --- |
| `call_rms_amplitude` | `full_scale_ratio` | square root of the mean squared samples |
| `call_peak_abs_amplitude` | `full_scale_ratio` | maximum absolute sample |
| `call_band_power` | `full_scale_ratio_squared` | two-sided rectangular-bin DFT power within the declared band |

These are built-in `metric_definitions` with `derivation_family =
acoustic_call_window_response`. They are distinct from the `acoustic_*`
reference metrics even though the arithmetic is the same: a call's RMS and a
reference tone's RMS are measurements of different things.

- **Target.** `struct(detection_id=…)` or `struct(consensus_event_id=…)`. An
  `agreement_group_id` is refused by name
  (`vawlume:acoustic:AgreementGroupTargetUnsupported`), because
  `derived_measurements` has no agreement-group target. Measure a member
  detection or a consensus event instead.
- **Window.** The event's own `[start_time_s, end_time_s)`, on the
  recording-native audio clock. There is no padding and no clock transform,
  because the audio and the event share a timebase.
- **Band.** Declared, never inferred. `BandHz=[min max]` is the only source of a
  band. The event's own frequency bounds are never read, because extractor
  frequency fields are not interchangeable (contract D6, "the band is explicit
  only"). With no `BandHz` there is no band power, and `band_state` is
  `not_declared`.
- **Channels.** Each requested channel is measured independently, in the order
  requested. A channel that cannot be read (not declared on the recording, absent
  from the file, or a failed sample read) is that channel's failure: `status =
  "failed"`, `coverage_status = "unreadable"`, flag `channel_unreadable`, and the
  reader's error identifier and message. The other channels are still measured.
  A broken recording link (a missing or unsupported artifact, a metadata
  mismatch, or a relative path with no `SourceRoot`) would fail every channel
  alike, so it is raised instead.

## QC states

Doc 27's reader states carry through unchanged, per channel:

| State | Value? | Channel status |
|---|---|---|
| `covered_populated` | yes | `completed`, unless another flag applies |
| `partial_populated` (flag `incomplete_audio_coverage`) | yes, over the covered part only; `covered_interval_s` says which | `completed_with_warnings` |
| `covered_empty`, including a zero-length window (flags `zero_length_window`, `empty_window`) | **no metric at all** | `failed` |
| `not_covered` (flag `empty_window`) | **no metric at all** | `failed` |
| `clipped_samples` | yes, and **a lower bound** | `completed_with_warnings` |

Band states (`band_state`) are `computed`, `not_declared`, `incomplete` (flag
`incomplete_call_band`), `invalid` (flag `invalid_call_band`), `above_nyquist`
(flag `call_band_above_nyquist`), `no_samples` (empty window; the band was not
examined) and `not_examined` (unreadable channel). Only `computed` has band
power.

**Clipping matters more for calls than for references.** A clipped channel's
level is a lower bound, so a level difference computed from it is wrong in a
known direction. The flag, and `clipped_sample_count`, are in the result and in
every persisted row's method evidence, so normalization and the method can refuse
to rely on that channel. This function withholds nothing on its own account.

The run's status is `failed` when every channel failed, `completed` when every
channel completed cleanly, and `completed_with_warnings` otherwise.

## Persistence

Persistence follows `measureReferenceResponse` exactly:

- planning (`Apply=false`, the default) is read-only;
- `Apply=true` requires a stable `RunKey`, and creates one `analysis_runs` row of
  `run_type = acoustic_call_window_response`;
- one `derived_measurements` row per (event, channel, metric), targeting
  `detection_id` or `consensus_event_id`, with `recording_channel_id` as the
  qualifier. `trg_derived_measurement_channel_scope` and its update twin refuse a
  channel from another recording;
- **one event per run.** A run key names one event's measurement on one
  requested channel set;
- re-applying an identical result reuses the run and its rows. A changed result
  under the same key raises `vawlume:acoustic:MeasurementRunConflict`: changed
  provenance or status, a different band, a different channel set, a different
  event, or a key that already names a reference-response run.

Each row's `derivation_details_json` holds: method key and version; sample,
interval and window semantics; the band-power convention; target kind and the
event's identifier and interval; recording, channel and channel index; the
requested channel indices; source file identifier, paths and checksum;
requested, covered and read intervals and `coverage_status`; first and last
sample, count and rate; `band_source` (`explicit` or `none`), the declared band
and `band_state`; `clipped_sample_count`; and the QC flags.

Because the rows record the **requested** channel indices, a channel that was
requested and failed is visible as requested but absent, rather than never
requested.

### Selecting one run's measurements for one event

```sql
SELECT dm.derived_measurement_id, dm.recording_channel_id, md.metric_key,
       dm.value_real, dm.unit, dm.derivation_details_json
FROM derived_measurements dm
JOIN metric_definitions md ON md.metric_definition_id = dm.metric_definition_id
WHERE dm.analysis_run_id = :run
  AND dm.detection_id = :event          -- or dm.consensus_event_id
  AND md.derivation_family = 'acoustic_call_window_response';
```

### Limits

- **Duplicate prevention is in code, not schema.** The partial unique index
  `idx_derived_measurements_acoustic_unique` covers reference targets only. No
  index prevents two identical call rows in one run. The only writer creates rows
  inside a new run and reuses an existing one, so it cannot duplicate them. A
  hand-written insert could.
- **A run in which every channel failed holds no rows**, and so does not record
  its target. Re-using its key for another all-failed event is not detected as a
  conflict. Reference measurement has the same property.
