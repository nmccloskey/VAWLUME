# Call-level normalization and the observed level difference

Added in Phase 6 (itinerary 6.7). The governing decisions are D6 and D8 of
[`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md).
Inputs come from [`41_call_window_measurement.md`](41_call_window_measurement.md)
(call measurements) and [`28_channel_response_estimates.md`](28_channel_response_estimates.md)
(response estimates).

Development plan §11.1 step 3 is *apply/reference acoustic normalization and
QC*. Two public functions in `+acoustic/` do that, and nothing more:

| Function | Answers | Persists? |
|---|---|---|
| `vawlume.acoustic.normalizeCallLevels` | How loud was this call on each channel, relative to that channel's own response to the declared reference? | Yes, with `Apply=true` |
| `vawlume.acoustic.levelDifference` | For an ordered channel pair, how many dB louder was the call on channel a than on channel b? | Never |

Neither takes a position, distance, entity or candidate. Relating a level
difference to where an animal was is combination, which belongs to the
native method in `+estimator/` (contract D7). A test reads every `+acoustic/`
function's declared inputs and fails if one of them names any of those.

## The policy

The policy is a versioned, checksum-bearing artifact:
[`config/09_acoustic_normalization_policies/band_matched_noise_reference_v1.json`](../../config/09_acoustic_normalization_policies/band_matched_noise_reference_v1.json),
profile kind `analysis_settings`. The function reads every rule from it. The
loader refuses a policy that:

- leaves any of the five response `qc_status` values undeclared;
- claims any `calibration_status.state` other than `uncalibrated`;
- declares a method, formula, comparability scope or extractor-power use that
  this version does not implement.

| Block | What it fixes |
|---|---|
| `operation` | `normalized = measured / response`. Both operands share a canonical unit, so the quotient is dimensionless and stored as `ratio_to_channel_response` |
| `pairs` | `call_band_power` ÷ `acoustic_band_power`, family `noise`, band `identical`, written as `call_band_power_normalized`. RMS and peak are not paired in v1 |
| `response_qc_status_handling` | one action per status (below) |
| `source_measurement_handling` | clipping and partial coverage propagate as flags. A failed measurement has no row and gets `source_measurement_absent` |
| `extractor_reported_power` | `not_used` (contract D6) |
| `calibration_status`, `comparability`, `what_this_is_not` | uncalibrated, within one recording, and what the number is not |

### What each response `qc_status` does

| `qc_status` | Action | Why |
|---|---|---|
| `ok` | use | every aggregation check passed |
| `divergent` | use, flag `response_divergent` | a median exists and is the declared response; the disagreement travels with the value so a consumer can refuse it |
| `source_qc_warning` | use, flag `response_source_qc_warning` | the estimate deliberately kept warned sources, a choice recorded when it was built; this policy carries it rather than silently reversing it |
| `insufficient_evidence` | exclude the channel, reason `response_insufficient_evidence` | a divisor the aggregation itself called insufficient is not a divisor |
| `not_comparable` | exclude the channel, reason `response_not_comparable` | dividing by responses measured against different references would make channels less comparable, not more |

`refuse_run` is in the action vocabulary but used for no status in this
version.

## `normalizeCallLevels`

```matlab
preview = vawlume.acoustic.normalizeCallLevels(conn, ...
    struct(analysis_run_id=callRun), struct(analysis_run_id=responseRun));

stored = vawlume.acoustic.normalizeCallLevels(conn, ...
    struct(analysis_run_id=callRun), struct(analysis_run_id=responseRun), ...
    Apply=true, RunKey="session01-d12-normalized");
```

`callRun` is one `acoustic_call_window_response` run, so one event. `responseRun`
is one `acoustic_channel_response_estimate` run. Either may also be named by
`project_key` plus `run_key`. `PolicyPath` defaults to the shipped policy.

**Refused for the whole run**, by identifier:

| Identifier | When |
|---|---|
| `NormalizationRecordingMismatch` | the response estimates belong to another recording or project. Condition 3 is within one recording, and this is where that is enforced |
| `NormalizationSourceKindInvalid` | the call run is not a call-window run |
| `NormalizationSourceEmpty` | the call run holds no rows, because every channel failed |
| `NormalizationPolicyInvalid` | the policy is invalid |
| `NormalizationRefusedByPolicy` | a status's action is `refuse_run` |

**Per channel, no value and a reason.** One outcome row is produced per
**requested** channel per pair, so a failed channel is reported rather than
skipped. Matching runs metric, then family, then band. The first rule that
leaves nothing names the mismatch, and nothing is substituted:

| `reason` | Meaning |
|---|---|
| `source_measurement_absent` | the requested channel has no source row for the call metric (failed, unreadable, or no band power) |
| `no_response_estimate` | the response run has no estimate for the channel |
| `response_metric_mismatch` | estimates exist, but none for `acoustic_band_power` |
| `response_family_mismatch` | none of the declared `reference_type` |
| `response_band_mismatch` | none with the identical band |
| `response_insufficient_evidence`, `response_not_comparable` | excluded by `qc_status` |
| `response_value_not_positive` | the response value is zero, negative or absent |
| `response_unit_mismatch` | the source and response units differ |

An unnormalized channel has `value = NaN` and an **empty** unit. It is never
labelled as normalized.

**Flags.** A normalized row's `qc_flags` are the source row's flags
(`clipped_samples`, `incomplete_audio_coverage`) plus any flag the response's
status adds. Nothing is repaired. A clipped channel is normalized and flagged,
and the refusal belongs to the level difference.

**Persistence** follows the measurement methods. One `analysis_runs` row of type
`acoustic_call_level_normalization`. The policy is registered through
`vawlume.db.registerProfileVersion` and linked by `analysis_run_profiles` with
role `call_level_normalization_policy`. Both parents go in
`analysis_run_sources`: the call run as `call_window_measurement` and the
response run as `channel_response_estimate`. There is one `derived_measurements`
row per normalized value, under `call_band_power_normalized`, targeting the
same event with the channel as qualifier. Re-applying identical inputs reuses
the run. Changed provenance, a different policy version or checksum, different
parents or different values raises `NormalizationRunConflict`.

Each row's method evidence names **its exact parents**:
`source_derived_measurement_id`, `channel_response_estimate_id`, both parent
run identifiers, both values and units, the band, `reference_type`,
`response_qc_status` and the action taken, the source and final QC flags, and
the policy's key, version, URI and checksum. The schema has no column linking a
derived measurement to a response estimate, so that link lives in the evidence
and at run level in `analysis_run_sources`. A test proves every stored value
equals the source row divided by the named estimate. Because the row-level link
is not a foreign key, only the run-level one protects it: deleting a parent
*run* is refused (`analysis_run_sources` restricts it), while nothing stops a
direct deletion of a single estimate row that a normalized row names.

## `levelDifference`

```matlab
d = vawlume.acoustic.levelDifference(outcomes(1,:), outcomes(2,:), refuseClipped);
```

- **Formula:** `10*log10(P_a / P_b)` dB, for an **ordered** pair of normalized
  power values of one event.
- **Sign:** positive when channel a is louder. Swapping the pair negates it
  exactly. The native method's prediction `20*log10(d_b/d_a)` (D7) has the same
  orientation: a source nearer microphone a gives a positive prediction.
- **`refuseClipped` is required and has no default.** Whether a clipped side is
  fatal is the estimator profile's declared parameter.
- **Refusals** (`status = "refused"`, `value = NaN`), with every applicable reason
  listed in `reasons` and the first in `reason`: `a_missing`, `a_nonpositive`,
  `a_clipped`, then the same for `b`. A missing side's own reason is in
  `reason_a` / `reason_b`.
- **Misuse raises** `LevelDifferenceInputInvalid`: the same channel twice, two
  events, two different quantities, or a raw (unnormalized) metric.
- Other flags are carried in `flags` as `a:<flag>` / `b:<flag>`.

It is pure and is **not persisted** (D6, Q6(b)). It is reconstructible exactly
from the two cited normalized rows. `derived_measurement_id_a` and `_b` name
them, and a test recomputes the value from the stored rows.

## What a test demonstrates

The suite's recording gives channel 2 half channel 1's amplitude for every
source. The same call then differs by 6.02 dB raw, and by 0 dB after
normalization against the noise family. That is what normalization claims to
do. Because the gain difference is synthetic and identical for reference and
call, the test shows the operation is self-consistent. It says nothing about
whether a real microphone's response to a noise reference matches its response
to a call.
