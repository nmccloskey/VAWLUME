# Event-window tracking retrieval and the inverse clock transform

Added in Phase 6 (itinerary 6.4). The governing decisions are D4 and D5 of
[`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md).

The question this layer answers: **for one vocal event, where was each native
track's bodypoint at the call's onset, midpoint and offset?** It answers in
three steps, each with one owner:

| Step | Function | Package |
|---|---|---|
| The event's instants, on the reference clock | `vawlume.estimator.eventReferenceInstants` | `+estimator/` |
| Reference instants → the tracking stream's native clock | `vawlume.alignment.applyInverseTransform` | `+alignment/` |
| Per-track positions at those instants | `vawlume.tracking.positionsAtInstants` | `+tracking/` |

It reads only. Nothing here writes to the database, and the result contains **no
entity**. Which entity a track represents is a separate, later question.

## Why an inverse transform was needed

`applyTransform` and `applyTransformInterval` map a source clock's **native**
times onto the **reference** clock. `readWindow` takes its interval in the
tracking stream's **native** units. Choosing which tracking samples to read for a
call known on the reference clock therefore needs the reverse direction. Plan
§4.3 assigned that ("reference → native transforms when mathematically
supported") to `+alignment/`, and it had not been built.

### `vawlume.alignment.applyInverseTransform`

```matlab
[native, transform] = vawlume.alignment.applyInverseTransform(conn, runId, referenceTimes);
```

- **Additive.** It asks `applyTransform` to describe the run (status, stored
  segments, anchored range) and inverts those coefficients. The forward functions
  were **not edited**, so their behaviour is unchanged by construction.
- **Invertible only when monotone and continuous.** Every segment must have
  positive scale, and adjacent segments must meet at their breakpoint (within
  `max(1e-9 s, 1e-12 × |t|)`, which absorbs rounding in the stored coefficients).
  A fitted piecewise transform is continuous by construction (doc 13). A stored
  transform that is not, such as a hand-edited one, is refused with
  `TransformNotInvertible`, never inverted region by region.
- **The same boundary rule.** A segment's image covers [its image start, the next
  segment's image start). A reference time at an image breakpoint belongs to the
  segment beginning there, which is the segment the forward transform assigns the
  native breakpoint to. A native → reference → native round trip at the breakpoint
  returns the breakpoint, and a test proves it.
- **Extrapolation is flagged on the native side**, as in the forward function,
  and `ErrorOnExtrapolation=true` escalates it.
- **The uncertainty is the stored segment bound, verbatim**: on the reference
  clock and uncalibrated. It is not rescaled to the native clock.
- A reference time below a bounded transform's image is refused
  (`ReferenceTimeOutsideTransform`).

## `vawlume.estimator.eventReferenceInstants`

```matlab
instants = vawlume.estimator.eventReferenceInstants(conn, struct(detection_id=12), ...
    struct(clock_relation="alignment_run", reference_timebase_key="neural_native", ...
           audio_alignment_run_id=7));
```

- **Events:** a detection or a consensus event. An agreement group is refused
  (`EventSetUnsupported`), because it has no intrinsic interval (contract D6).
- **Instants:** onset, midpoint and offset. The midpoint is the **native**
  midpoint placed on the reference clock, not the average of the transformed
  endpoints. Under a piecewise transform those are different instants.
- **The clock is declared:**
  - `alignment_run` with a named run, which must transform exactly the
    recording's `is_recording_native` timebase to exactly the reference. A run
    that does not is refused.
  - `alignment_run` with no run, allowed only when the reference **is** the
    recording's own clock. Supplying a run anyway is refused as a contradiction.
  - `same_clock`, an explicit declaration that nothing verifies. The result says
    it was declared.
- Returns each instant's segment, extrapolation flag and uncertainty bound with
  its semantics. It also reports whether the call's interval crosses a breakpoint
  and how much its duration changed (from `applyTransformInterval`).

## `vawlume.tracking.positionsAtInstants`

```matlab
result = vawlume.tracking.positionsAtInstants(conn, streamRef, referenceTimes, ...
    ReferenceTimebaseKey="neural_native", AlignmentRunId=9, Bodypart="snout", ...
    MaxGapS=0.05, InstantLabels=["onset";"midpoint";"offset"], ...
    CallWindow=instants.reference_interval);
```

1. The reference span covering the instants (and the call window), padded by
   `MaxGapS` on each side, is mapped to the stream's native clock with
   `applyInverseTransform`.
2. `readWindow` reads that native window for the declared bodypart.
3. Samples are mapped to the reference clock with `applyTransform`.
4. Per native track, `vawlume.geometry.positionAtInstants` gives each instant's
   position, under its policy: observed, interpolated within `MaxGapS`, or
   `not_covered` with a reason, and never extrapolated.

### The tracking clock is declared, not discovered

`readWindow`'s own `ReferenceTimebaseKey` option is **not used**. It selects the
newest qualifying alignment run by itself (`ORDER BY alignment_run_id DESC`), a
query whose answer changes when a run is added. A caller that must cite the
transform it used names it: `AlignmentRunId` (validated to transform this
stream's clock to the reference), `SameClock=true`, or neither, but only when the
stream's own clock is the reference. Contract D5 step 4 named `readWindow(...,
ReferenceTimebaseKey=)`. This departs from that wording to keep the transform
explicit, and every conversion still goes through the alignment layer.

### States that stay distinct

| Where | Values | Meaning |
|---|---|---|
| `status` | `read`, `bodypart_missing`, `uncovered` | No track carries the bodypart (no other bodypart is substituted), or declared coverage establishes no observation over the read span |
| `coverage_status` | `covered`, `partial`, `uncovered` | readWindow's three states, over the read span |
| `sample_status` | `populated`, `empty`, `uncovered` | **`empty` under coverage is a QC finding**, not an absence of animals |
| `positions.coverage_state` | `covered`, `uncovered` | whether *this instant's* native time lies in declared coverage |
| `positions.basis` / `reason` | from `positionAtInstants` | observed / interpolated / not_covered, with `no_samples`, `before_first_sample`, `after_last_sample`, or `gap_exceeds_max` |
| `has_pose_confidence` | true / false | when false, every confidence is NaN, never 1 |

Each position row also carries its bracketing sample times, `gap_s`,
`bracket_extrapolated` (whether either bracketing sample was placed by an
extrapolated transform), and `clock_uncertainty_s` with its semantics. That bound
is the tracking clock's at that instant, kept **beside** pose confidence and
never combined with it.

`window_samples` lists the samples observed inside `CallWindow` (half-open, on
the reference clock) for window summaries, which use observed samples only.

## What this layer does not do

- resolve which entity a track represents (`vawlume.tracking.identityOverWindow`
  and the estimator's candidate geometry, itinerary 6.5);
- compute distances (`vawlume.geometry.distance`, composed in 6.5);
- write anything;
- fall back to another bodypart, the nearest sample, or a looked-up alignment run.

## Related documents

- [`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md): D4, D5
- [`13_transform_fitting_and_alignment_qc.md`](13_transform_fitting_and_alignment_qc.md): continuity of fitted transforms; the forward boundary rule
- [`24_tracking_input_contract.md`](24_tracking_input_contract.md): three-state coverage; the identity boundary
- [`38_spatial_primitives.md`](38_spatial_primitives.md): the interpolation policy
