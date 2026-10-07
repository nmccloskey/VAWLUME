# Integrated native-estimator demonstration

[`examples/native_estimator_demo.m`](../../examples/native_estimator_demo.m)
runs the whole Phase 6 native path as one synthetic workflow. It covers:

- a two-animal, two-microphone recording whose channels have deliberately
  different gains;
- reference responses and call-level normalization;
- tracking on its own clock, related to the recording's through a piecewise
  audio transform;
- identity associations, including a swap;
- one native estimation run, previewed and then applied;
- the settings profile's five conditions, read back from the stored version;
- every candidate's score or its reason for none, and every evidence row with
  its citation;
- one score recomputed from read-back rows;
- decisions under the native policy;
- the full read-back.

It is the cross-module proof for Phase 6. Every claim it prints is asserted by
[`tests/integration/test_native_estimator_demonstration.m`](../../tests/integration/test_native_estimator_demonstration.m).

The example is VAWLUME's own caller score at work, and nothing more. The score
is uncalibrated, in dB, comparable within this recording only, and not a
probability. Two of its six scenes are generated from the method's own
spreading assumption, so they show **self-consistency, not accuracy**. One scene
is generated to break that assumption, and it shows the method assigning the
wrong animal.

## What the workflow covers

| Step | Public API |
| --- | --- |
| Register clocks and anchors; fit a piecewise audio transform and an affine video one | `vawlume.ingest.alignment`, `vawlume.alignment.fit` |
| Declare the arena frame (shared by microphones and tracking) and a second, camera frame | `vawlume.geometry.registerCoordinateSystem` |
| Establish the channels and place the microphones | `vawlume.geometry.registerRecordingChannel`, `registerChannelPlacement` |
| Register the tracking stream and the identity associations | `vawlume.tracking.register`, `registerIdentityAssociation` |
| Register the estimator settings profile | `vawlume.estimator.loadSettings`, `vawlume.db.registerProfileVersion` |
| Measure reference noise and estimate each channel's response | `vawlume.acoustic.registerReference`, `measureReferenceResponse`, `estimateChannelResponse`, `readChannelResponse` |
| Measure each call window and normalize it | `vawlume.acoustic.measureCallWindow`, `normalizeCallLevels` |
| Preview, then apply, the native run | `vawlume.estimator.attributeCallers` |
| Decide under the native policy | `vawlume.attribution.decide` |
| Read the run back | `vawlume.attribution.report` |
| Recompute one score from read-back rows | `vawlume.acoustic.levelDifference`, `vawlume.estimator.levelDifferenceConsistency` |

## The synthetic session

The session is the recipe of the Phase 6 integration tests
(`test_native_estimation_run.m`), copied rather than shared, so the phases look
alike.

- **Recording.** `REC_SESSION_01`: 1000 Hz, 24-bit, two channels.
- **Microphones.** `mic_a` at (0, 0) and `mic_b` at (100, 0) cm, in `arena_2d`.
  Channel b hears every source at **half channel a's amplitude**, which is 6.02
  dB in power.
- **Animals.** Participants A and B.
- **Clocks.** The audio clock is piecewise affine with a knot at 900 s. The
  video clock, which the tracking uses, is affine. Both are fitted to a neural
  reference through anchors.
- **Tracking.** Samples exist in three regions only, around 300.5 s, 700 s and
  1100 s of audio time. Between them the tracker recorded nothing.
- **References.** Two reference windows of a noise family: four in-band
  sinusoids at 220, 240, 260 and 280 Hz. The shipped normalization policy
  requires a noise family. Each channel's response is the median of its two
  band powers: 0.005 for a and 0.00125 for b.
- **Calls.** 250 Hz tones, one per scene.

Seeded directly: the project, recordings, source files, entities and their
links, and the extraction run and its detections. Each has its own
demonstration. Every Phase 6 object is created through a public function.

## The six scenes

The level differences are channel a over channel b, in dB. "Raw" is the
call-band-power ratio before normalization, computed by the example for display
only (see *could not show*). "Normalized" is the difference the method observed.

| Scene | Detection | Built how | Raw | Normalized | Scores (A, B) | Decision |
|---|---|---|---|---|---|---|
| separable | 1 | A near mic a, B far; the call generated from A's own distances under spherical spreading | 17.29 | 11.27 | −0.000, −11.27 | `assigned` (A) |
| symmetric | 7 | both animals on the microphones' perpendicular bisector; equal level at both | 6.02 | 0.00 | −0.000, −0.000 | `ambiguous` |
| model mismatch | 11 | A's spherical prediction **minus 9 dB of directivity at mic a** | 8.29 | 2.27 | −9.00, −2.27 | `assigned` (**B**) |
| unfittable | 10 | 8 dB louder at mic b, which neither position predicts | −1.98 | −8.00 | −19.27, −8.00 | `unassigned` |
| coverage gap | 3 | identity clear; no tracking sample during the call | 6.02 | 0.00 | no score: `track_covered_empty` | `excluded` |
| identity swap | 5 | the two tracks swap identities mid-call | 6.02 | −0.00 | no score: `identity_changes_within_window` | `excluded` |

In every row, raw minus normalized is 6.02 dB, which is the gain difference the
normalization removes.

The separable scene is labelled self-consistency wherever it is printed. It
shows that the path delivers the method's arithmetic intact. It does not show
that the method is right.

`simultaneous` never appears, by design. The native policy's rule
(`threshold_with_separation`) never reaches it. Equal scores mean the geometry
cannot separate the candidates, and the decision says `ambiguous`, bound by
`separation_margin`.

## The model-mismatch scene

This scene is the only evidence this phase produces about how the method fails.
What the demonstration prints:

- **Setup.** A generated the call. Spherical spreading predicts 11.27 dB from
  A's position and 0.00 dB from B's.
- **The mismatch.** A −9 dB directivity bias at microphone a, a head turned
  away from it, makes the observation 2.27 dB.
- **Scores.** A −9.00 dB; B −2.27 dB. **B ranks first and is `assigned`**: it is
  within the −3 dB selection threshold and more than 3 dB ahead of A.
- **Why.** The method's tolerance to unmodelled directivity is half the gap
  between the two candidates' predictions, here 5.63 dB. A bias larger than
  that moves the observation nearer the other animal's prediction. The other
  animal then fits **well**. Its score looks like any good fit, no QC fact flags
  it, and nothing in the run says it is wrong.

The example prints this and explains it. It does not assert that the result is
correct. The test pins only that the demonstration says what happened: the
generating animal did not rank first, and the boundary list says so.

## Five conditions, from the stored profile

The example reads the run's `settings_profile_version_id` back from `report`,
reloads the profile file from that version's stored `content_uri`, and compares
its checksum with the registered one before printing anything. The printed
dimensions, score meaning, scaling, readability statement and calibration status
are the profile's own text. None of them is a string in the example.

## Reconstruction, in front of the reader

The example recomputes the separable target's two scores from `report`'s rows
only:

1. the two per-channel `call_band_power_normalized` evidence rows, and the QC
   flags of the measurements they cite (`derived_measurement_id`);
2. each candidate's `bodypoint_microphone_distance` rows on the primary instant
   basis (midpoint), with their extrapolation flags from `value_semantics`;
3. the stored profile, reloaded as above.

It then calls the same pure method the run used. The recomputed scores
(−3.1e−06 and −11.272 dB) equal the stored ones exactly.

## Evidence, one dimension per row

The separable target holds 33 of the run's 144 evidence rows:

- two `call_clock_placement` rows (the audio and the tracking alignment run,
  each its own bound);
- two per-channel normalized levels;
- one level difference;
- per candidate: one identity-association row, ten distances (five instant
  bases × two channels) and three pose-confidence rows.

Every row names its producer, and the example prints them all. The QC table
counts evidence by dimension, with no total and no combined value.

## Refusals, beside the successes

Captured by a harness that **fails the example if any of them stops refusing**:

| Attempted | Refused as |
|---|---|
| a second apply of the same native run key | `vawlume:estimator:RunAlreadyApplied` |
| a native run whose settings profile is an imported mapping | `vawlume:attribution:NativeRunProfileRequired` |
| an estimator settings profile without its `calibration_status` block | `vawlume:estimator:SettingsBlockMissing` |
| a distance between a microphone in `arena_2d` and a point in `camera_2d` | `vawlume:geometry:CoordinateSystemMismatch` |
| a call normalized against another recording's response estimate | `vawlume:acoustic:NormalizationRecordingMismatch` |

The other recording, `REC_OTHER`, exists only for the last refusal. Its audio is
a copy of the session's, with its own references and response estimate.

## Boundaries the example does not cross

- No transformation between frames.
- No combination of dimensions outside `+estimator/`.
- No probability.
- No calibrated threshold.
- No imported claim or backend estimate as an input.
- No comparison with an imported or backend run (Phase 7).

## What the demonstration could not show

Each item is covered elsewhere or is a known limit. They are where a sweep
should look first.

**About the model-mismatch scene:**

- **One directivity, one geometry, one sign.** The bias is a flat −9 dB at
  microphone a only, on one call, with A 24 cm from mic a and 89 cm from mic b.
  The scene shows the direction of failure for that case. It shows nothing about
  the failure rate for real animals, about frequency-dependent directivity, or
  about bias toward the other microphone.
- **A bias below the tolerance.** At, say, −5 dB, A would still rank first, with
  a worse score. The example shows only the flipped case. 6.8 found the crossover
  at the midpoint between predictions, −8.11 dB in its own scene. That sweep is
  not repeated here.
- **Reflection, reverberation or occlusion.** Only directivity is modelled. A
  reflection would bias the difference in a way that depends on room geometry,
  and nothing here constructs one.
- **Detecting the mismatch.** Nothing in the run, its QC or its decision
  signals that the assumption failed, and the example cannot show a signal that
  does not exist. A good fit to the wrong animal is indistinguishable from a
  good fit to the right one.

**Unscored states the example does not reach.** The run reaches
`track_covered_empty` and `identity_changes_within_window` only. The states
below are covered by `test_identity_candidate_geometry.m`,
`test_event_window_tracking_retrieval.m`, `test_level_difference_consistency.m`
and, for a missing response estimate, `test_call_level_normalization.m`:

- `track_not_covered`;
- `identity_no_track`, `identity_multiple_tracks` and
  `identity_partial_window`;
- an extrapolated clock placement, refused under
  `refuse_extrapolated_alignment`;
- a clipped channel;
- a missing response estimate or placement;
- a frame unit the profile does not accept.

**Other limits:**

- **A call across the clock knot.** Every call lies inside one segment of the
  piecewise audio transform. The swap scene uses the second segment, and the
  others use the first.
- **A raw level difference read back from VAWLUME.** VAWLUME stores per-channel
  raw and normalized measurements, but no raw *difference*. The raw column is
  the example's own `10*log10` of the two stored `call_band_power` values. It is
  for display, and nothing reads it.
- **Every target's reconstruction.** One target is reconstructed in front of the
  reader. `test_native_estimation_run.m` reconstructs every stored score and
  recovers every stored reason.
- **A second policy version.** One policy decides once. A second version
  deciding the same candidates beside the first is
  `test_native_estimation_run.m`'s.
- **Simultaneous calling.** A mixture of two callers yields one observed
  difference, which the method scores as if one animal produced it. No mixture
  is built, because the result would only restate that limit.
- **Consensus-event targets.** Only detection targets are used.
- **More than two animals or two microphones.** Profile v1's `scope` refuses
  them.
- **Broadband noise references.** The noise family is four sinusoids in band.
  It satisfies the policy's band match. It is not acoustic noise.
- **A real session.** Every recording, track, placement, reference and number
  was written by this repository.

## Validation limitation

Everything here is synthetic and written by this repository to exercise a
branch. The demonstration proves that the native path composes, refuses by name,
stores every input beside its score, and reads back coherently. It proves
nothing about accuracy, calibration, or who called.

## See also

- [`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md): the decisions
- [`43_native_estimator_method.md`](43_native_estimator_method.md): the method and its settings profile
- [`44_native_estimation_run.md`](44_native_estimation_run.md): the run, its evidence rows, deciding and reading back
- [`41_call_window_measurement.md`](41_call_window_measurement.md) and [`42_call_level_normalization.md`](42_call_level_normalization.md): the acoustic chain
- [`37_integrated_backend_localization_demonstration.md`](37_integrated_backend_localization_demonstration.md): the Phase 5 demonstration this one follows
