# 48. QC facts for a native run

`vawlume.estimator.qcFacts(conn, runRef)` reports, per target of a native run,
how the observed level difference sits against the candidates' predictions
under the method's spreading assumption. Built at itinerary 7.10. Contract 07
D8 is the design.

```matlab
facts = vawlume.estimator.qcFacts(conn, struct(attribution_run_id=nativeRunId));
facts.targets      % one row per target
facts.candidates   % one row per (target, candidate) with facts
```

The output joins on `attribution_target_id` with `report`, `compare` and the
sensitivity summaries. It is not part of `report`: a native-only computation
there would be a path branch, which breaks invariant 16.

## Read-only, from storage, through the method itself

- **Reads:**
  - the run, through `vawlume.attribution.report`;
  - the run's registered settings profile version, whose file must still match
    its checksum (`SettingsChecksumMismatch` otherwise).
- **Rebuilds the method's inputs** from the stored evidence, as the
  reconstruction test does:
  - the two per-channel `call_band_power_normalized` rows, recombined with
    `vawlume.acoustic.levelDifference`;
  - each candidate's two `bodypoint_microphone_distance` rows on the primary
    instant basis.
- **Calls the pure method**, `levelDifferenceConsistency`, so the predictions
  are the method's own (invariant 23).
- **Reads no audio, tracking artifact or alignment**, and writes nothing. A
  test checks that `PRAGMA data_version`, `total_changes()` and every stored
  score and decision are unchanged. A static guard, verified by injection,
  refuses any audio, tracking or alignment reader in the function.
- **One home for the arithmetic.** The prediction `20*log10(d_b/d_a)` was
  factored out of the method into `+estimator/private/estimatorPredictedDifferenceDb`,
  with identical floating-point operations. Fixtures built before and after
  store identical scores. The positional margin inverts it in
  `estimatorDistanceForPrediction`. Both live where the method lives.
- **Refused:** a run that is not `native_estimate`
  (`vawlume:estimator:QcFactsNotNative`).

## The facts

**Per target** (`targets`):

| Column | Meaning |
|---|---|
| `status`, `reason` | `facts`, or `no_facts` with the first stored no-score reason (no two scored candidates) |
| `observed_db` | The stored `normalized_level_difference` |
| `prediction_gap_db` | The absolute difference between the two candidates' predictions |
| `tolerance_db` | Half the gap: the largest unmodelled level bias that leaves the ranking unchanged |
| `ranking_boundary_db` | The midpoint of the predictions |
| `acoustic_margin_db` | The distance of the observation from the boundary. A bias larger than this, toward the other prediction, reverses the ranking |
| `observed_outside_predictions`, `outside_by_db` | Whether the observation lies outside the interval the predictions span, and by how much |
| `no_candidate_within_tolerance` | No candidate's discrepancy is within `tolerance_db` |
| `predictions_coincide` | The predictions are equal, so they span no interval and the method cannot rank. The two facts above are then not stated (false); `outside_by_db` still reports the distance |
| `undetectable_failure_class` | The statement below, on every row |

**Per candidate** (`candidates`):

- `predicted_db` and `discrepancy_db`, the method's intermediates;
- `within_tolerance`;
- the two distances and their unit;
- `positional_margin_a` and `positional_margin_b`: the change in this
  candidate's distance to channel a (holding b), or to channel b (holding a),
  that would move its prediction to the ranking boundary, in the frame's unit.

Positional error enters the sensitivity summaries as this margin
(`positional_error`, `reported_elsewhere`).

## What it cannot detect

Every target row carries this text, verbatim from contract 07 D8:

> A wrong animal that fits well is not detectable from these facts. When an
> unmodelled bias moves the observed difference toward the wrong candidate's
> prediction by more than `acoustic_margin_db` and less than the gap, the wrong
> animal scores best and every fact here looks ordinary.

The facts make the margin visible. They do not flag the failure. Nothing here
issues a verdict, changes a score or decision, or gates, weights or decides
anything. That would be a new method version.

## On the 7.3 fixture (synthetic)

| Scene | Facts |
|---|---|
| Separable | Gap 12.3 dB. Nothing fires. A fits within tolerance |
| Symmetric | Gap 0, `predictions_coincide`. No failure stated |
| Unfittable (observation −8 dB against predictions 0 and 12.3 dB) | `observed_outside_predictions`, outside by 8.0 dB, and `no_candidate_within_tolerance` |
| Model mismatch (B fits; A generated the call) | Observed 2.3 dB inside [0, 12.3]. Margin 3.8 dB. **Nothing fires**: the undetectable class |
| Coverage gap, identity swap, out of bracket | `no_facts`, each with its stored reason |

The out-of-range case is 7.3's unfittable scene, so the fixture needed no new
scene.

## An aggregate is not built

A recording-level residual distribution might expose the mismatch class in
aggregate. This would be one candidate's systematic bias across calls, which no
single call shows. Building it would need a model of how residuals should be
distributed, and that is a calibration claim. It is recorded as a v3 idea and
not built (itinerary 7.10, out of scope).
