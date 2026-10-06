# Spatial primitives

Added in Phase 6 (itinerary 6.3), as the first spatial arithmetic in VAWLUME.
The governing decisions are D3, D4 and D17 of
[`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md).
This document is the implementation-facing reference.

Three pure functions in `+geometry/`:

| Function | Answers |
|---|---|
| `vawlume.geometry.distance` | How far apart are these positions, in their one shared frame? |
| `vawlume.geometry.positionAtInstants` | Where was this tracked trace at these instants, or why can't that be said? |
| `vawlume.geometry.summarizeDistances` | What do the observed distances inside one window summarize to? |

**Pure** means they read no database, no file and no clock. They take values and
return values. That is what lets their policy be tested on its own, and it is why
none of them takes a connection or a clock reference.

## One home for spatial arithmetic

Phase 5 refused to compute any distance, because nothing yet needed one. Phase 6
lifts that refusal for one package only. **Revised invariant 19**, enforced by
`testNoSourceComputesADistanceAngleOrTransform` in
`tests/integration/test_localization_evidence.m`:

> Spatial arithmetic (distance, norm, angle, and position interpolation) occurs
> only in `src/+vawlume/+geometry/`. A distance is computed only between positions
> whose frames pass the shared identity rule. No coordinate is transformed,
> rescaled or converted between frames anywhere in `src/`.

`+geometry/` already owns frames, placements and `assertCompatible`. Making it the
only home for spatial arithmetic means the package that decides whether two
frames may be related is the only one that relates them. This mirrors
`+alignment/` as the only home of clock-transform arithmetic.

### The identity rule has one implementation

`assertCompatible` needs a database connection, because it returns the frame's
row. The pure primitives cannot take one. Rather than giving them a second id
comparison, the comparison itself was extracted into the private function
`geometryAssertSameFrame`. `assertCompatible` and `distance` both call it.
`assertCompatible`'s return values, error identifiers and messages were compared
before and after the extraction across fifteen cases, and are identical.

## `distance`

```matlab
mic = struct(coordinate_system_id=1, dimensionality=2, unit="cm");
result = vawlume.geometry.distance([12 30], mic, snoutPositions, mic);
```

Positions are N-by-2 or N-by-3. Either side may be a single row, which is paired
with every row of the other side. A frame descriptor carries
`coordinate_system_id`, `dimensionality` and `unit`, the fields
`readChannelPlacements` and `readCoordinateSystems` return.

| Situation | Result |
|---|---|
| Different `coordinate_system_id` | Refused: `vawlume:geometry:CoordinateSystemMismatch`, the identity rule's own error |
| One frame id, but descriptors disagree on dimensionality or unit | Refused: `FrameDescriptorConflict` |
| 2D frame | Planar distance, basis `planar`. A third column is accepted only if it is all NaN, as a 2D placement reads back. A real `z` is refused (`PositionDimensionalityInvalid`) |
| 3D frame, both `z` present | 3D distance, basis `spatial_3d` |
| 3D frame, a `z` missing | **Not computed**, reason `z_missing`. Never computed in the plane with `z` as 0 |
| 3D frame, `PlanarIn3D=true` | Planar distance, basis `planar_declared`. An opt-in, labelled so it can never pass for a 3D distance |
| `x` or `y` missing | Not computed, reason `position_missing`; NaN, never 0 |

**The unit is carried, not interpreted.** A `px` frame's distance is returned in
`px`. Whether a unit may be treated as uniform in scale is the consumer's
declared decision. The native estimator makes that declaration in its versioned
profile (contract 06 D17).

## `positionAtInstants`

```matlab
result = vawlume.geometry.positionAtInstants(sampleTimes, xy, [onset mid offset], ...
    MaxGapS=0.1, PoseConfidence=conf);
```

Input is one (track, bodypart) trace, with samples and query instants already on
**one clock**. Placing a call and a tracking stream on one clock is the alignment
layer's job, so this function never sees a clock reference.

| Basis | When | Reason |
|---|---|---|
| `observed` | a query time equals a sample time (exactly; no tolerance) | |
| `interpolated` | strictly between two usable samples whose gap is at most `MaxGapS` (inclusive) | |
| `not_covered` | the trace has no usable sample | `no_samples` |
| `not_covered` | before the first sample | `before_first_sample` |
| `not_covered` | after the last sample | `after_last_sample` |
| `not_covered` | the bracketing samples are more than `MaxGapS` apart | `gap_exceeds_max` |

- **No extrapolation, and no nearest-sample fallback.**
- **`MaxGapS` has no default.** It is refused if absent (`MaxGapRequired`),
  because it belongs in the caller's versioned profile and a code default would
  be a second, unversioned copy.
- **A sample with a missing `x` or `y` is dropped before bracketing.** A run of
  dropped frames therefore becomes a gap the `MaxGapS` rule judges, not a bracket
  that silently spans it.
- **A missing `z` stays missing.** An interpolated `z` exists only when both
  brackets have one.
- **Unsorted or duplicate sample times are refused** (`SampleTimesInvalid`), not
  sorted. A trace that emitted them has a problem the caller should see.
- **Pose confidence travels beside the position, never into it.** Both brackets'
  values are returned, and `pose_confidence_min_bracket` is their minimum, or NaN
  if either bracket has none. Taking the minimum while ignoring a missing value
  would invent a confidence for the bracket that had none.

Every row also reports its bracketing sample times and `gap_s`, so a reader can
see what an interpolated value rests on.

## `summarizeDistances`

```matlab
summary = vawlume.geometry.summarizeDistances(distances, bases);
```

Window summaries are over **observed samples only**. Any basis other than
`observed` is refused (`SummaryBasisInvalid`), so the interpolation policy cannot
leak into a quantity that claims to describe what the tracker saw.

Both `window_median` and `window_min` are returned and labelled, because both
are defensible. A consumer records which one it used (plan §4.7). **An empty
window is not a zero:** with no computed distance the status is `not_covered`,
both summaries are NaN, and the reason distinguishes `no_samples` from
`no_computed_distance`.

## What the arithmetic guard can and cannot see

The guard strips string literals and comments, then matches named operations:
`sqrt`, `hypot`, `norm`, `vecnorm`, `pdist`, `dot`, `cross`, the trig family and
its degree variants, `deg2rad`/`rad2deg`, `interp1/2/3/n`, gridded and scattered
interpolants, and rotation/quaternion conversions. Hits in `+geometry/` are
permitted as a package. Every other hit is a named per-line exemption with its
non-spatial reason (an RMS amplitude, a clock-fit RMSE, a partial correlation, a
sample quantile, a Hann window).

**Three ways the Phase 5 guard was blind, fixed at 6.3:**

- **`\b` is not a word boundary in MATLAB `regexp`** (MATLAB uses `\<` and `\>`).
  The Phase 5 pattern's `\bnorm`, `\bdot`, `\bacos`, `\basin` and `\batan`
  therefore never matched anything. A search with working boundaries at 6.3 found
  no spatial use those terms had hidden. Phase 5's invariant 19 held in substance,
  but its evidence did not cover them.
- **Comments were stripped before strings**, so a `%` inside a string hid the
  code after it on that line (F5.10-8). The scanner now removes string literals
  first, distinguishing a char-array quote from a transpose by the character
  before it, and treats text after `...` as a comment.
- **The trig family and interpolation functions were absent** (F5.10-8).

`testTheArithmeticScannerSeesWhatItShould` holds each of these as a regression.
The guard also asserts that it finds arithmetic *in* `+geometry/`, so a pattern
that stopped matching anything would fail rather than pass vacuously.

**What it cannot see:** spatial arithmetic written without any named function,
such as a hand-written interpolation `p0 + w*(p1-p0)` in another package. The
package boundary is enforced for named operations; the rest relies on review and
on the phase-end sweep reading code.

## Related documents

- [`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md): D3 (home), D4 (instants and interpolation), D17 (units)
- [`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md): frames, placements, and compatibility as identity
- [`24_tracking_input_contract.md`](24_tracking_input_contract.md): the tracking samples these primitives are given
