# The native estimator method, its settings, and native runs

Added in Phase 6 (itinerary 6.8). The governing decisions are D1, D2, D7, D10, D12,
D15 and D16 of
[`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md),
and its section "The five conditions, answered".

This pass adds the one place in VAWLUME where evidence dimensions are combined.
It also adds the profile that licenses that, and the two admissions that let the
canonical attribution layer accept the result:

| Piece | Where |
|---|---|
| Settings profile | [`config/10_estimator_settings/native_level_difference_estimator_v1.json`](../../config/10_estimator_settings/native_level_difference_estimator_v1.json), kind `attribution_estimator_settings` |
| Loader | `vawlume.estimator.loadSettings` |
| The method | `vawlume.estimator.levelDifferenceConsistency`, key `vawlume.estimator.level_difference_consistency`, version `1.0.0` |
| Native runs | `vawlume.attribution.createRun` with `attribution_path = "native_estimate"` |
| The P4-3 citation | `vawlume.attribution.addEvidence` accepts `derived_measurement_id` |

The method is pure. 6.9's `attributeCallers` composes it with
`candidateGeometry` (doc 40), `normalizeCallLevels` and `levelDifference`
(doc 42), and the canonical write layer.

## The settings profile states the five conditions

`loadSettings` reads the profile with `fileread` and `jsondecode`, as every
non-source-mapping settings profile is read. It refuses, **by name**, a profile
that is missing any of these blocks, any dimension, or any parameter:

| Block | Condition | Content |
|---|---|---|
| `dimensions` | 1 | `used` / `not_used` and a one-sentence role for each of `temporal_alignment`, `pose_localization`, `visual_identity` and `acoustic`. `source_localization` is `not_used`, with its reason. The roles say which inputs are only gates (identity) and which are only recorded (pose confidence, the alignment bound) |
| `score` | 2 | `dB`, `higher_is_stronger`, its meaning, and `what_this_is_not`, headed "not a probability" |
| `scaling` | 3 | how each input is scaled; `comparability_scope = within_recording`, with its justification |
| `readability` | 4 | the evidence rows each input becomes (contract D10), and how a score is reconstructed |
| `calibration_status` | 5 | `uncalibrated`, `evidence_basis`, `calibration_requires` |

It also needs `profile`, `method`, `scope` (2 candidates, 2 channels) and
`parameters`.

| Error | When |
|---|---|
| `SettingsBlockMissing` | a block is missing |
| `SettingsDimensionUndeclared` | a dimension is undeclared |
| `SettingsDimensionMisdeclared` | an upstream dimension is declared `not_used`. Method 1.0.0 uses all four to compute every score, so the declaration would be stored with the run as a false statement of condition 1 (added at 6.12a; the 6.12 sweep showed such a profile was accepted and scored from the acoustic input regardless). The `not_used` vocabulary stays for a later method version that leaves a dimension out |
| `SettingsParameterMissing` | a parameter is missing; **no parameter has a code default** |
| `SettingsGateNotImplemented` | `pose_confidence_gate` or `temporal_uncertainty_gate_s` is not null, because v1 records those dimensions and gates nothing on them (contract D4, D5) |
| `SettingsInvalid` | a claim this version cannot support: `calibrated`, a scope other than 2/2, another spreading assumption, another comparability scope, or a `source_localization` that is used |

The parameters are `spreading_assumption`, `primary_instant_basis`, `bodypart`,
`channel_pair`, `max_interpolation_gap_s`, `accepted_frame_units`,
`min_distance`, `refuse_extrapolated_alignment`, `refuse_clipped_channels`, the
two gates, and `normalization_policy` (key, version and path of doc 42's policy).
Each is explained in the profile's `parameter_meanings`.

The result's `declared_inputs` table is what `createRun` stores, so the
declaration and the profile version that makes it come from one file.

## The method

```matlab
settings = vawlume.estimator.loadSettings();
d = vawlume.acoustic.levelDifference(outcomes(1,:), outcomes(2,:), ...
    settings.parameters.refuse_clipped_channels);
result = vawlume.estimator.levelDifferenceConsistency( ...
    geometry.entities, geometry.geometry, d, settings);
```

For each candidate with usable geometry and a computed difference, with
`(a, b) = settings.parameters.channel_pair`, on the primary instant basis:

```text
predicted   = 20*log10(d_b / d_a)      dB   spherical spreading: power falls as 1/d^2
observed    = 10*log10(P_a / P_b)      dB   positive when channel a is louder
discrepancy = observed - predicted     dB
score       = -|discrepancy|           dB   higher_is_stronger, 0 = perfect agreement
```

A source nearer microphone a gives a positive value on both sides, so the two
conventions agree. Only the ratio `d_b / d_a` enters, so the score does not
change under a uniform rescaling of the frame. A test scores the same scene in cm
and in mm.

**Output.** `result.candidates` has one row per candidate:

- `entity_id`, `status` (`scored` / `unscored`), `score` and `score_semantics`;
- `no_score_reason`, plus every applicable reason in `no_score_reasons`, and
  `geometry_reason_detail`;
- `native_track_id` and `tracking_identity_association_id`;
- `instant_basis` and `channel_index_a/_b`;
- `distance_a/_b`, `distance_unit` and `distance_ratio_b_over_a`;
- `predicted_difference_db`, `observed_difference_db` and `discrepancy_db`.

There is no probability field. `result` also carries the method key and version,
the unit and orientation, `calibration_status`, `comparability_scope` and the
`observed` difference with its state.

**No score, never a default one.** The reasons come in contract D10's order:

- the `identity_*` reasons;
- `track_not_covered`, `track_covered_empty`, `bodypart_missing`;
- `alignment_extrapolated`, `channel_unplaced`;
- `frame_unit_not_accepted`, `distance_degenerate`;
- `acoustic_unavailable`, `acoustic_clipped`.

The distance primitive's own `position_missing` and `z_missing` are reported as
`track_not_covered`, because the instant has no usable position. The original
word is kept in `geometry_reason_detail`.

**Refused by name, not generalized:** any candidate count other than the
profile's 2 (`ScopeUnsupported`), and a level difference for any pair other
than the declared ordered pair (`ChannelPairMismatch`). A difference computed
with a clipping setting other than the profile's, or geometry missing a row for
the declared pair, raises `MethodInputInvalid`.

**Pure.** The method's code contains no database call and no file read. A test
checks that.

### What the tests show, and what they do not

- **Self-consistency, not accuracy.** The observed difference is generated from
  the true candidate's position under the method's own assumption, so that
  candidate scores exactly 0 and ranks first.
- **Symmetric geometry.** When both candidates are equidistant from both
  microphones, each predicts 0 dB, and their scores are equal whatever was
  observed. The method does not claim to separate them.
- **Model mismatch (a finding).** The scene has microphones at (0,0) and (100,0)
  cm. The true caller A is at (20,10) and predicts 11.14 dB; B is at (70,30) and
  predicts −5.08 dB. The observed difference has a directivity bias that
  spherical spreading does not model:

  | Bias | Score A (true) | Score B | Ranked first |
  |---|---|---|---|
  | 0 dB | 0.00 | −16.22 | A |
  | +6 dB | −6.00 | −22.22 | A |
  | −6 dB | −6.00 | −10.22 | A |
  | −8 dB | −8.00 | −8.22 | A |
  | −9 dB | −9.00 | −7.22 | **B** |
  | −12 dB | −12.00 | −4.22 | **B** |

  The ranking flips once the bias passes the midpoint between the two
  predictions (−8.11 dB here), and nothing in the score warns that it has. A bias
  *toward* the nearer microphone never flips this scene; a bias *away from* it
  does. The two candidates' predicted separation is therefore the margin the
  method has against unmodelled directivity, and that margin is smallest exactly
  when the animals are close together or near the perpendicular bisector.

## Native runs

```matlab
spec = struct(run_key="session01-native", attribution_path="native_estimate", ...
    method="vawlume.estimator.level_difference_consistency 1.0.0", ...
    settings_profile_version_id=estimatorProfileVersionId, ...
    target_set=struct(detection_ids=ids), participating_entity_ids=[1 2], ...
    sources=struct(source_file_ids=audioFileId), ...
    declared_inputs=settings.declared_inputs);
run = vawlume.attribution.createRun(conn, recordingRef, spec, Apply=true);
```

| Error | When |
|---|---|
| `NativeRunProfileRequired` | a native run's profile is not of kind `attribution_estimator_settings` |
| `EstimatorProfileOnNonNativeRun` | that kind is used on an imported or backend run |
| `DeclaredInputsRequired` | a native run has no `declared_inputs` |
| `DeclaredInputsIncomplete` | `declared_inputs` does not name each of the four dimensions exactly once |
| `DeclaredInputsInvalid` | a declaration is not `used` or `not_used` |
| `DeclaredInputsNotAccepted` | another path supplies `declared_inputs`, because a backend run's declarations come from its intake profile |
| `RunSpecInvalid` | any other path |

The four rows are written in the run's transaction with
`declared_by_profile_version_id` set to the run's profile version, and
re-applying compares them. Imported and backend run creation is unchanged: a
before/after snapshot of results and rows was identical.

## The P4-3 citation

`addEvidence` accepts `derived_measurement_id` on any dimension. It counts as the
row's source pointer, and is refused when the measurement:

| Error | When |
|---|---|
| `EvidenceMeasurementNotFound` | does not exist |
| `EvidenceMeasurementScopeMismatch` | is not of the run's recording |
| `EvidenceMeasurementTargetMismatch` | does not measure the row's target event (the same detection or consensus event) |
| `EvidenceMeasurementChannelMismatch` | reports a different channel from the row's `recording_channel_id`; both present and equal, or both absent |

The row keeps its own value. The citation is an identifier.

## Revised invariant 5, and its guard

> Evidence dimensions are combined only inside `src/+vawlume/+estimator/`, by a
> method whose settings profile states the five conditions.

`tests/unit/test_combination_package_boundary.m` reads every `.m` file under
`src/`, strips strings and comments, and lists two kinds of hit:

- any line that does arithmetic over identifiers from two or more of the
  dimension vocabularies (acoustic: level difference, band power…; pose: distance,
  position…; identity; temporal alignment);
- any function whose declared inputs span two vocabularies, whether in the
  signature or the `arguments` block.

`+estimator/` is the one permitted package. Anywhere else, a hit fails. The
guard was injection-verified with a scratch function under `+attribution/` that
takes a distance and a level difference.

It also checks that it **does** see the method's own combination line. That
check found a blind spot while it was being written: the first version of the
method computed `observed.value - row.predicted_difference_db`, which names no
vocabulary. The method now names its operands (`acousticObservedDb -
distancePredictedDb`), so the line says what it combines. A combination written
entirely in names that belong to no vocabulary would still pass the guard;
reading the code is the remaining defence.

`+attribution/`'s read and write surface still has no combined field. The
native score is a candidate column (`attribution_candidates.score`), not a
report or evidence field.
