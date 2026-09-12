# Integrated multimodal demonstration

[`examples/multimodal_integration_demo.m`](../../examples/multimodal_integration_demo.m)
exercises the whole Phase 2 multimodal input layer as one synthetic workflow:
coordinate systems, microphone placement, external tracking registration and
bounded reads, time-varying visual-identity evidence including an ambiguous
crossing, optional acoustic references, bounded audio access, per-channel
reference-response measurements, and one aggregated response/QC profile with
exact supporting lineage.

It is the cross-module proof for the phase. Every capability it claims is
asserted by
[`tests/integration/test_multimodal_integration_demonstration.m`](../../tests/integration/test_multimodal_integration_demonstration.m),
so the numbers the example prints are checked rather than merely observed.

The example assigns no caller. It does not multiply visual and acoustic evidence
into a caller score, rank channels, compute an animal-to-microphone distance, or
suggest that a nearer animal produced a detected call.

## What the workflow covers

| Step | Public API |
| --- | --- |
| Declare a 2D arena frame | `vawlume.geometry.registerCoordinateSystem` |
| Locate two microphones in it | `vawlume.geometry.registerChannelPlacement` |
| Read frames and placements back | `vawlume.geometry.readCoordinateSystems`, `readChannelPlacements` |
| Register an external tracking artifact | `vawlume.tracking.register` |
| Read bounded tracking windows | `vawlume.tracking.readWindow` |
| Validate coordinate compatibility | `vawlume.tracking.assertGeometryCompatible` |
| Record native-track to entity evidence | `vawlume.tracking.registerIdentityAssociation` |
| Query identity candidates over a window | `vawlume.tracking.identityCandidates` |
| Declare acoustic references | `vawlume.acoustic.registerReference` |
| Read them back with provenance | `vawlume.acoustic.readReferences` |
| Read bounded audio windows | `vawlume.acoustic.readAudioWindow` |
| Measure one reference on one channel | `vawlume.acoustic.measureReferenceResponse` |
| Aggregate an exact measurement set | `vawlume.acoustic.estimateChannelResponse` |
| Audit the profile and its lineage | `vawlume.acoustic.readChannelResponse` |

Two setup steps are written as direct SQL rather than through a public function,
and the example says so where it does it:

- the project, source file, recording, channels, entities, and the recording's
  native video clock, because no public path establishes recording channels, and
  project intake is already demonstrated by `project_intake_demo`;
- one solved offset clock transform, because fitting belongs to the alignment
  layer that `temporal_alignment_demo` demonstrates. Here the transform is
  fixture material whose only job is to show that alignment QC arrives beside
  pose confidence and identity evidence without touching either.

## The synthetic session

One 10 s two-channel recording at 4 kHz. Channel 2 is written at exactly half of
channel 1, so the measured response difference is known in advance.

| Object | Native span | Content |
| --- | --- | --- |
| `tone-1`, `tone-2` | `[1,2)`, `[3,4)` | 100 Hz sinusoid, target RMS 0.40 |
| `noise-1`, `noise-2` | `[7,8)`, `[9,10)` | 200 + 500 Hz, target RMS 0.36 |
| tracking stream | `[0,10]` | three native trajectories at 2 Hz |
| crossing | `[4,6]` | pose confidence drops to 0.34 |

Each reference interval spans an integer number of cycles of every component it
contains, so its RMS is exact and both intervals of a family carry the identical
waveform. The repeats agree because the signal does, not because the aggregation
smoothed anything. Every reference declares the same band, 80-620 Hz, so the two
families are grouped and compared on equal terms.

The crossing sits between the two reference families deliberately. The example
asserts no relationship between a visual crossing and an acoustic reference, and
overlapping them would invite one.

## The crossing, and what a track label is worth

Three native trajectories are registered: `mouse_a`, `mouse_b`, and `mouse_c`.
Two canonical entities exist, spelled `mouse_a` and `mouse_b`. The spelling
collision is the point.

| Interval | `mouse_a` track | `mouse_b` track | `mouse_c` track |
| --- | --- | --- | --- |
| before `[0,4]` | assigned `mouse_a` | assigned `mouse_b` | no evidence |
| during `[4,6]` | ambiguous: `mouse_a` **and** `mouse_b` | unresolved | no evidence |
| after `[6,10]` | assigned **`mouse_b`** | assigned **`mouse_a`** | no evidence |

Before the crossing the evidence agrees with the labels. After it the evidence
names the other animal while the labels stay exactly where they were. A
session-global track-to-entity column could not express this at all, and a label
taken as identity would now be confidently wrong.

`mouse_c` is the third finding. It carries a plausible animal name, matches no
canonical entity, and has no identity evidence, so it resolves as `none` — which
is distinct from the explicit `unresolved` statement recorded for the `mouse_b`
track. Both have zero candidates; conflating them would let an unexamined track
pass for an examined one.

The two ambiguous candidates carry upstream similarity scores of 0.55 and 0.52
with `identity_value_semantics` set to
`cosine_similarity_of_appearance_embeddings` and `calibration_status`
`uncalibrated`. The manual assertions before and after the crossing carry **no**
number at all: a reviewer who is certain has still measured nothing, and nothing
becomes `1.0`.

VAWLUME performs no image-based re-identification. The scores are synthetic
stand-ins for what an upstream tool would supply.

## Four uncertainty components, none combined

The `uncertainty` field of the result puts them side by side, and the numbers
differ so that no substitution can hide:

| Dimension | Queried from | Value in this session |
| --- | --- | --- |
| pose/localization | `readWindow` `samples.pose_confidence` | 0.98, dropping to 0.34 over the crossing |
| visual identity | `identityCandidates` `associations.identity_value` | 0.55 / 0.52, or missing |
| temporal alignment | `readWindow` `transform.rmse_s` | 0.001 s, status `estimated` |
| acoustic channel response | `estimateChannelResponse` `estimates.relative_range` | 0 across family repeats |

No row combines them and no caller confidence is derived from them. Phase 2
preserves these components for later attribution work; combining them is not its
job.

The clock case is shown twice. With no stored transform the reader reports
`reference_time_status = "no_transform"`, leaves every reference time missing,
and leaves native times and pose confidence untouched. With a transform stored,
the status becomes `applied` and the fit's residual evidence arrives beside the
samples rather than folded into their confidence.

## Coverage, in both modalities

Tracking windows demonstrate three states: `covered`, `partial` past the end of
declared coverage, and `uncovered` with no rows at all. Zero rows in an
uncovered window means nothing established that anyone was observing — not that
the tracker saw nothing.

Audio windows demonstrate the same distinction against the artifact's real
duration: `covered_populated`, `partial_populated` for a window running past the
end of the file, and `not_covered` beyond it. A silent stretch inside coverage
reads as silence, with RMS 0.

Six `tracking_series` rows are registered and **zero** tracking samples are
written to SQLite. Positions, frames, and confidences stay in the artifact and
are read window-wise on demand.

## The response profile

Twenty-four `derived_measurements` rows exist — three metrics for each of four
references on each of two channels. Only the eight
`acoustic_rms_amplitude` rows are aggregated, selected by exact identifier, so
the population of the profile is visible in the call rather than dependent on
what a later query happens to return.

The profile holds four estimates, not two:

| Reference family | Channel 1 | Channel 2 |
| --- | --- | --- |
| `tone` | 0.40 | 0.20 |
| `noise` | 0.36 | 0.18 |

Averaging the families would give 0.38 on channel 1 — a plausible-looking number
describing neither family. It appears nowhere, and the test asserts its absence.
Each estimate cites its two supporting measurements through
`channel_response_estimate_sources`, and each of the eight source runs is
registered in `analysis_run_sources` with role
`reference_response_measurement`.

A second, read-only estimate requires a third family, `impulse`, for which no
evidence exists. It produces two explicit NULL-valued rows with
`qc_status = "insufficient_evidence"` rather than disappearing, because a
required family that simply vanished from the result would leave a caller unable
to tell it was ever expected.

## Boundaries the example does not cross

- Raw video is not ingested and no pose estimation is performed.
- No image-based re-identification is performed.
- A native track label never becomes canonical animal identity.
- Coordinate compatibility is declaration and validation, never transformation;
  the shared frame licenses comparison and the example computes no distance.
- Acoustic references are optional, and no reference type is privileged.
- Channel-response estimates are uncalibrated response/QC evidence, not gain
  corrections, normalized call values, preferred channels, or caller
  probabilities.
- No caller is assigned and no combined confidence is produced.

## Validation limitation

Everything here is synthetic. The arithmetic is exact because the fixture was
built to make it exact, which says nothing about real acquisition hardware, real
tracker behaviour, or real re-identification performance. Every threshold the
example passes — the divergence threshold, the minimum reference count, the
confidence values — is an illustrative demonstration value, not a calibrated
recommendation.

## See also

- [`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md)
- [`24_tracking_input_contract.md`](24_tracking_input_contract.md)
- [`25_visual_identity_association.md`](25_visual_identity_association.md)
- [`26_acoustic_reference_registration.md`](26_acoustic_reference_registration.md)
- [`27_audio_window_and_response_measurement.md`](27_audio_window_and_response_measurement.md)
- [`28_channel_response_estimates.md`](28_channel_response_estimates.md)
- [`../design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md)
