# The native estimation run

Added in Phase 6 (itinerary 6.9). The governing decisions are D1, D10, D13 and D16
of [`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md).
It composes doc 40 (geometry), docs 41–42 (call measurement, normalization and the
level difference) and doc 43 (the method).

`vawlume.estimator.attributeCallers` is the native estimator's one public entry
point. It runs the method over a set of target events and writes the result
into the canonical attribution tables. It writes **only** through
`vawlume.attribution.createRun`, `addCandidates` and `addEvidence`, the same
functions every other path uses. The estimator package contains no SQL write
statement, and a static test checks that.

```matlab
spec = struct(run_key="session01-native", ...
    settings_profile_version_id=estimatorVersionId, ...      % registered, see below
    target_set=struct(detection_ids=[1 3 5]), ...
    participating_entity_ids=[A B], ...
    clock=struct(clock_relation="alignment_run", ...
        reference_timebase_key="neural_native", audio_alignment_run_id=audioRun), ...
    tracking=struct(stream=struct(project_key="p", stream_name="arena_tracking"), ...
        alignment_run_id=videoRun, source_root=sessionFolder), ...
    normalization_runs=table([1;3;5], [n1;n3;n5], ...
        VariableNames=["detection_id", "analysis_run_id"]));
plan = vawlume.estimator.attributeCallers(conn, struct(recording_id=1), spec);
run  = vawlume.estimator.attributeCallers(conn, struct(recording_id=1), spec, Apply=true);
```

## Inputs are explicit references

Nothing is found by searching, because a query whose population can change
silently is the failure doc 28 designed against.

- **Settings.** A **registered** `attribution_estimator_settings` profile version.
  Register it once with `vawlume.db.registerProfileVersion`. Its file is read
  from the stored `content_uri` and must still match the stored checksum, so the
  profile that scores is the profile the run cites.
- **The clock.** `eventReferenceInstants`' declaration. The tracking stream
  names its own alignment run, or declares `same_clock`. Bodypart and the
  interpolation gap come from the profile and are refused in the run spec.
- **The acoustic inputs.** One `acoustic_call_level_normalization` run **per
  target**, because a call-measurement run, and so a normalization run, covers
  one event (doc 41). Which event a normalization run measured is read through
  its own lineage, its `call_window_measurement` parent, never assumed.

## What a run holds

- One native run with its four declared inputs (doc 43).
- One target per event.
- One candidate per participant per target. Each has the method's `score` and
  `score_semantics`, or `score` NULL with `notes = "no_score_reason=<code>"`. No
  candidate ever has a probability.
- Every input the method consumed, as its own evidence row (contract D10):

| Grain | Dimension | Kind | Value | Citation |
|---|---|---|---|---|
| target, per alignment run used | `temporal_alignment` | `call_clock_placement` | the bound at the primary instant (`s`), or `uncertainty_not_recorded` | `alignment_run_id` |
| target, per channel | `acoustic` | `call_band_power_normalized` | the normalized level | `derived_measurement_id`, `recording_channel_id` |
| target | `acoustic` | `normalized_level_difference` | ΔL in dB | `source_locator` naming both measurements |
| candidate | `visual_identity` | `track_entity_association_used` | text: track, rule step, time validity | `tracking_identity_association_id` |
| candidate, per channel and instant basis | `pose_localization` | `bodypoint_microphone_distance` | the distance, in the frame's unit | `tracking_identity_association_id`, `recording_channel_id` |
| candidate, per instant basis | `pose_localization` | `bodypoint_pose_confidence` | the bracket minimum | `tracking_identity_association_id` |

- **Rows exist only for values that exist.** A candidate whose identity swaps
  mid-call has no distance rows but keeps its association row, and its target
  keeps every acoustic and clock row.
- **Every `value_semantics` is a `key=value; …` list beginning with
  `producer=`.** It names the method, or the measurement and its policy, plus
  every basis a reader needs: instant basis, channel index, extrapolation flags
  and QC flags.
- **The two clocks get separate rows.** The audio→reference and
  tracking→reference bounds are never combined.
- **`addEvidence` requires `identity_statement_kind = identity_association` on
  every row that cites an association.** So the pose rows carry it too: the
  distance rests on that association.

## Reconstruction (condition 4)

`test_native_estimation_run/testEveryStoredScoreIsReconstructedFromStorage` is
the evidence for contract condition 4 and invariant 23. After `Apply`, it reads
**only** the database:

1. the run's stored settings profile version, whose file is reloaded and its
   checksum compared;
2. each target's stored per-channel `call_band_power_normalized` rows, and the
   measurement each cites (for the value and QC flags). From these it recomputes
   the level difference with `vawlume.acoustic.levelDifference`;
3. each candidate's stored `bodypoint_microphone_distance` rows on the primary
   instant basis, with their units and extrapolation flags parsed from the
   semantics;
4. each candidate's stored score and notes.

It then calls `vawlume.estimator.levelDifferenceConsistency` on those values.
Every stored score must be recomputed exactly (to 1e-12), and every unscored
candidate's stored reason must be returned again. Injection check: when the run
was changed to skip the primary-basis distance rows, this test failed.

## Apply writes one transaction

`Apply` writes the whole run, meaning the run, its declared inputs, targets,
candidates and every evidence row, in **one database transaction**:

1. Plan everything: every read, every method call, every row. `createRun` runs
   in plan mode as validation, and planning writes nothing.
2. Require AutoCommit on, then set it off: `attributeCallers` owns the
   transaction.
3. Call `createRun`, `addCandidates` and `addEvidence` with
   `Transaction="caller"`. Each joins the open transaction, and none commits or
   rolls back.
4. Commit once. On any error, roll the whole run back and rethrow the original
   error unchanged. AutoCommit is restored either way.

No row of a failed run survives, and its run key stays unused.
`test_native_estimation_run/testAFailureLateInTheRunLeavesNoRowOfIt` proves it:
a trigger aborts a pose-confidence evidence insert, which happens after the run
and its candidates were written, and every table the run writes is unchanged
afterwards. With the writers in their default mode and no outer transaction,
the same test fails, because the run, its targets, candidates, early evidence and
declared inputs survive.

`Transaction="caller"` is a public option of the three writers (itinerary
6.9a). It is refused under AutoCommit on (`vawlume:attribution:TransactionState`),
because there would be no transaction to join. Their default, `"own"`, is
unchanged for every other caller.

*History:* 6.9 could not share a transaction across the writers, and instead
rehearsed every apply on a disposable copy of the database file. 6.9a replaced
that mitigation with the transaction itself.

## Refusals, all before any write

| Refusal | Identifier |
|---|---|
| a run key already used | `vawlume:estimator:RunAlreadyApplied` |
| a profile of another kind | `vawlume:estimator:SettingsProfileKindInvalid` |
| a changed settings file | `vawlume:estimator:SettingsChecksumMismatch` |
| a tracking stream of another recording | `vawlume:estimator:InputRecordingMismatch` |
| a normalization run of another recording's event | `vawlume:estimator:InputRecordingMismatch` |
| a missing or wrong normalization run | `vawlume:estimator:NormalizationRunInvalid` |
| mixed event sets | `vawlume:attribution:TargetSetMixed`, from `createRun`'s planner |
| another recording's target | `vawlume:attribution:TargetSetCrossesRecording`, from `createRun`'s planner |
| a participant not linked to the recording | `vawlume:attribution:EntityNotInRecording`, from `createRun`'s planner |
| unconnected clocks | `vawlume:tracking:ClockDeclarationInvalid` (or the alignment layer's own refusal) |

## Deciding (6.10)

A native run is decided with `vawlume.attribution.decide`, as any other path's
run is, under the native policy
[`config/08_attribution_policies/native_level_difference_decision_policy.json`](../../config/08_attribution_policies/native_level_difference_decision_policy.json).
It uses rule `threshold_with_separation` (contract D11): `selection_threshold`
−3 dB and `separation_margin` 3 dB, both illustrative.

| Situation | Decision |
|---|---|
| One candidate fits within 3 dB of the observation, and the other is more than 3 dB worse | `assigned`, that candidate |
| Both fit, within 3 dB of each other (for example, both equidistant from the two microphones) | `ambiguous`, bound by `separation_margin`. **Never `simultaneous`** |
| Neither fits within 3 dB | `unassigned` |
| No candidate has a score (identity swap, tracking gap, clipped channel…) | `excluded`, reason "no candidate of this target carried a native score" |

A second policy version decides the same candidates again, beside the first,
and rewrites nothing.

## Reading it back

`vawlume.attribution.report` reads a native run through **the same field set**
as an imported or backend run. A test compares the top-level fields, the QC
fields, and the columns of targets, candidates, evidence, declared inputs and
decisions across all three paths.

- The **only** path branch is `qc_note`'s caveat prose. For a native run it
  says the scores are VAWLUME's own, uncalibrated, comparable within this
  recording only, and not a probability, and that equal scores are not evidence
  of two callers.
- `evidence.derived_measurement_id` shows the P4-3 citation.
  `candidates.notes` shows each unscored candidate's
  `no_score_reason=<code>`.
- `declared_inputs` holds four rows for a native run. An imported run holds
  none, because an undeclared dimension reads as *no row*.
- QC adds three path-agnostic facts:
  - `unscored_candidates_by_reason`: the reason each unscored candidate
    states, or `not_stated`;
  - `targets_without_scored_candidate`;
  - `settings_profile_statements`: the run's settings profile's own
    `calibration_status.state` and `scaling.comparability_scope`, read from the
    profile file only while it still matches its registered checksum.

  None is a verdict.
