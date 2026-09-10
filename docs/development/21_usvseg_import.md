# USVSEG import

`vawlume.ingest.usvseg` is the database-facing boundary for one USVSEG
segmentation pass. It is the third extractor importer and deliberately the
thinnest: it shares the extractor-neutral core with DeepSqueak and MUPET and
adds only what the USVSEG artifact genuinely requires.

The database-free half is
[`15_usvseg_export_adapter.md`](15_usvseg_export_adapter.md).

## Public call

```matlab
plan   = vawlume.ingest.usvseg(conn, csvPath, recordingRef, runSpec)
result = vawlume.ingest.usvseg(conn, csvPath, recordingRef, runSpec, ...
    Apply=true)
```

`recordingRef` selects an already-established recording by `recording_id`, or
by `project_key` plus `source_relative_path`. USVSEG names every output after
its input file's stem, but that is a naming convention rather than recorded
provenance, so the importer never infers a recording from the CSV basename.

`runSpec` requires `run_key` and `extractor_version`, and accepts optional
`run_label` and `settings`.

Planning is read-only. `Apply=true` commits the run and its complete syllable
population in one transaction, so an extraction run never exists without the
syllables it produced.

The runnable example is
[`examples/usvseg_import_demo.m`](../../examples/usvseg_import_demo.m).

## Version is caller evidence

USVSEG writes no version string into any output file. `extractor_version` is
therefore a caller assertion assessed against the profile's declared
`extractor.version_scope`, and the profile sets
`version_required_at_ingest: true`.

| Condition | Identifier |
|---|---|
| No `extractor_version` supplied | `vawlume:ingest:UsvsegVersionRequired` |
| Version outside the profile's scope | `vawlume:ingest:UsvsegVersionIncompatible` |

This differs from DeepSqueak, where a workbook at least carries fields whose
shape varies by release, and from MUPET, whose `config.csv` is genuinely
run-scoped.

## Settings are optional and explicitly weak

This is the sharpest contrast with MUPET import, where settings evidence is
*required* to apply.

USVSEG writes `usvseg_prm.mat` when the application closes, holding whatever
parameters were active at that moment. It is application-scoped, not
run-scoped, and it is not written beside the CSV it may or may not correspond
to. Requiring it would refuse ordinary correct USVSEG output.

| Caller supplies | `result.settings.status` | Effect |
|---|---|---|
| nothing | `unavailable` | Warning `USVSEG_SETTINGS_UNAVAILABLE`; run applies |
| `settings.artifact_path` to a valid `usvseg_prm.mat` | `captured_weak` | Artifact hashed and registered with `evidence_strength = weak_not_run_scoped` |
| a path that does not exist | — | `vawlume:ingest:UsvsegSettingsNotFound` |
| a `.mat` without a `prm` variable | — | `vawlume:ingest:UsvsegSettingsInvalid` |

Captured parameters never become the run's `settings_profile_version_id`. That
column stays NULL, the evidence lives on the artifact row's metadata, and
`extraction_runs.notes` records `captured_weak`. Absent settings are recorded
as unavailable rather than filled from published USVSEG defaults: a documented
default is a contextual reference value, not an observation about a run.

## What is created, and what is deliberately absent

One detection per source row, with native timing preserved under
`timing_basis = profile_selected_event_geometry`, plus seven event measurements
per detection:

| Native column | Canonical field | Native unit | Canonical unit |
|---|---|---|---|
| `start` | `call_start_time` | s | s |
| `end` | `call_end_time` | s | s |
| `duration` | `call_duration` | ms | s |
| `maxfreq` | `peak_frequency` | kHz | Hz |
| `maxamp` | `peak_amplitude` | dB | dB |
| `meanfreq` | `frequency_center` | kHz | Hz |
| `cvfreq` | `frequency_cv` | ratio | ratio |

`duration` is exactly the printed onset/offset difference, so it is redundant
with `start` and `end` up to two different print precisions. It is preserved as
a native measurement rather than dropped, and it is never the timing authority.

Nothing is created for:

- `curation_events` — USVSEG exports no review state;
- `classification_*` — it exports no class or manual label;
- `detections.detection_score` — it exports no detector score;
- frequency minimum, maximum, and bandwidth — it exports no frequency bounds.

None of these may be synthesized from the columns USVSEG does export, and the
profile makes that a hard validation rule rather than a convention.

## Unexpected columns are preserved or refused, never discarded

A source column the profile does not claim is written row by row to
`unmapped_source_values` with its native field name, raw token, and source
locator. Retaining the value is the point: an unrecognized column is evidence
whose meaning is not yet mapped, not noise.

An unexpected column carrying *curation or classification* evidence is a
different matter and raises
`vawlume:ingest:UsvsegUnsupportedEventEvidence`. USVSEG exports no such
evidence, so a column of that kind means the artifact is not what this profile
describes, and silently routing it would invent extractor state.

## Zero-detection runs and reruns

A header-only CSV is a valid result. It commits the extraction run and its
artifact with zero detections, because a segmentation pass that found nothing
is an observation rather than a failed export.

An unchanged rerun under the same `run_key` reuses the run, artifacts,
detections, measurements, and unmapped values, and adds no scientific row.
Changed stored content under an existing identity is a conflict reported by
the plan, never an overwrite.

## Relationship to the other importers

Import creates no cross-extractor result. USVSEG detections become comparable
to DeepSqueak and MUPET detections only through
[`07_matching_candidate_generation.md`](07_matching_candidate_generation.md)
and the arbitrary-N agreement layer above it; see
[`22_phase1_correspondence_boundaries.md`](22_phase1_correspondence_boundaries.md)
for where each boundary sits.

`tests/integration/test_usvseg_import.m` covers the plan/apply contract and
includes an explicit check that the importer's sources mention neither MUPET
nor DeepSqueak, so extractor-specific code stays as thin as the format
requires.
