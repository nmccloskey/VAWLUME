# Transform fitting and alignment QC

## Scope

This document is the contract for estimating source-to-reference time transforms
from registered anchor observations, persisting the mathematics and the residual
evidence behind it, and applying a stored transform.

It follows registration, documented in
[`12_alignment_intake_and_registration.md`](12_alignment_intake_and_registration.md),
over the schema documented in
[`11_temporal_alignment_schema.md`](11_temporal_alignment_schema.md).

**It fits. It does not project.** No `aligned_external_events` row is written and
no timeline is regularized here; a caller asks for aligned times explicitly.

## Public API

```matlab
result = vawlume.alignment.solveTransform(method, sourceTimes, referenceTimes, Breakpoints=knots)
plan   = vawlume.alignment.fit(conn, alignmentRef)
result = vawlume.alignment.fit(conn, alignmentRef, Apply=true)
value  = vawlume.alignment.report(conn, alignmentRef)
[aligned, transform] = vawlume.alignment.applyTransform(conn, alignmentRunId, nativeTimes)
outcome = vawlume.alignment.setAnchorInclusion(conn, observationId, included, Reason=why)
```

`solveTransform` is deliberately public and database-free. The mathematics of an
alignment is the part a researcher most needs to be able to check, so it can be
called on two vectors and audited without a database, a manifest, or a schema.

`fit` plans by default and commits under `Apply=true`. `report` reads back what is
persisted. `applyTransform` uses stored coefficients and never refits.

`setAnchorInclusion` records a decision about whether one reading may influence
a transform. It is the only supported way to withhold an anchor, and it exists
because the decision previously required raw SQL.

## The models

### Offset only

```text
reference = source + offset
```

One anchor gives `offset = reference - source`. Several give the ordinary
least-squares solution under a fixed scale, which is the mean of the pairwise
differences. Scale is stored as exactly 1.

**One anchor never estimates a scale.** A single point cannot determine a slope,
and assuming 1 while calling the result affine would report an offset fit under
the wrong name.

### Affine

```text
reference = scale * source + offset
```

Solved by plain MATLAB least squares:

```matlab
design = [source, ones(numel(source), 1)];
coefficients = design \ reference;
```

No optimizer, no toolbox, no robust regression, no automatic outlier rejection,
no iterative refinement. Requirements:

- at least two included anchors;
- at least two distinct source times.

Both are enforced with named errors (`InsufficientAnchors`, `DegenerateAnchors`)
rather than being left to the pseudo-inverse to resolve quietly.

Choosing the method matters. Over a 1500 s session a scale of 0.9992 displaces
the far end by more than a second, so fitting such a clock with an offset-only
model leaves residuals three orders of magnitude larger. The method is a declared
property of the transform, not something inferred from the data.

### Piecewise affine

```text
reference = scale_j * source + offset_s_j        for source in segment j
```

One affine segment per declared interval, **continuous at the breakpoints**.

**Breakpoints are declared, never estimated.** VAWLUME does not search for them,
and there is no option that asks it to. A breakpoint is a claim that something
happened to a clock — a restart, a dropped buffer, a drift regime change — and
choosing one from the residuals would be model selection this prototype has no
basis for performing. A piecewise request with no breakpoints raises
`BreakpointsRequired` rather than falling back to affine.

**Continuity is a constraint on the fit, not a hope.** A discontinuity would map
one source instant to two reference times, leaving both application and interval
transformation undefined at exactly the point of interest. A clock that genuinely
jumps is a gap in coverage, or two alignment identities, not one transform with a
step in it.

Continuity costs nothing mathematically. With the knots declared, a continuous
piecewise-linear fit is one ordinary least-squares problem in a hinge basis:

```text
reference = a0 + a1 * source + SUM_k b_k * max(0, source - knot_k)
```

Per-segment coefficients follow by accumulation —
`scale_j = scale_{j-1} + b_{j-1}` and
`offset_j = offset_{j-1} - b_{j-1} * knot_{j-1}` — so `alignment_segments` stores
exactly what it stored before and the solve stays `X \ y`. No optimizer, no
toolbox, no robust regression, no iterative refinement.

**A segment covers `[source_start, source_end)`.** An anchor exactly at a
breakpoint belongs to the segment that begins there. The first segment is open
below and the last open above, reported as `NaN` bounds and stored as SQL NULL,
so every finite source time falls in exactly one segment. This rule is stated
once because the fitter and the applier must not disagree about it.

The scalar `scale` and `offset_s` are **NaN** for a piecewise result. A piecewise
transform has no single slope, and returning the first segment's would be a
plausible-looking number for a question nobody asked.

Requirements, each with a named error rather than a quiet pseudo-inverse:

| Requirement | Error when unmet |
| --- | --- |
| breakpoints declared | `BreakpointsRequired` |
| strictly increasing, finite, and strictly inside the anchored span | `BreakpointsInvalid` |
| no breakpoints on a method that has one segment | `BreakpointsInvalid` |
| every segment holds at least one anchor | `SegmentUnderdetermined` |
| at least as many anchors as parameters (segments + 1) | `InsufficientAnchors` |
| at least two distinct source times, and a full-rank design | `DegenerateAnchors` |
| every derived segment scale above zero | `NonPositiveTransformScale` |

A breakpoint at or beyond an end of the anchored span is refused because it
leaves a segment whose slope no observation determines — the single anchor
sitting on its own boundary contributes nothing, since both segments already
agree there.

`vawlume:alignment:MethodNotImplemented` is **retired**: with the declared path
implemented and estimation refused rather than deferred, no request reaches it.
`applyTransform` still raises `PiecewiseNotImplemented` when it finds more than
one stored segment; retiring that is the applier's pass, not this one.

### Segments are reported for every method

`solveTransform` returns a `segments` table — `segment_index`, `source_start`,
`source_end`, `scale`, `offset_s`, `anchor_count` — plus a per-anchor
`segment_index`, for **every** method. Offset and affine return one open-ended
segment.

A caller therefore reads one shape regardless of method, and the database sees
one row per segment either way. The alternative — special-casing the single
segment at every call site — is how two code paths for one concept begin.

### Determinism

Anchors are sorted by source time before solving, so coefficients are a property
of the anchor set rather than of the order rows arrived in. Residuals are
returned in the caller's original order, so each stays attached to its own anchor.

## Anchor pairing

Pairing is by **logical anchor identity**. There is no nearest-timestamp search,
no pulse-order matching, and no averaging anywhere in the fitter.

For one source → reference transform, each logical anchor in the alignment set is
resolved to observations on the two clocks:

| Situation | Outcome |
| --- | --- |
| Exactly one included observation on each clock | included in the fit |
| Exactly one observation on each clock, at least one not included | evaluated, residual stored, `included_in_fit = 0` with a reason |
| No observation on one clock | dropped; never nearest-matched |
| Several observations on a clock, none included | dropped; which one is meant is genuinely unknown |
| Several included observations on one clock | impossible — the schema's partial unique index forbids it |

The middle row is the useful one: an anchor deliberately held out for validation
still gets a residual against the transform it did not help produce.

Redundant replicate observations stay in the database untouched. The fitter
selects the included one and reports `source_observation_count` and
`reference_observation_count` so a reader can see that redundancy existed and that
exactly one reading was used.

## Anchor QC

Three kinds of evidence are derived at fit time and returned beside the
coefficients. **None of them is stored**, because each is a pure function of
rows the database already holds; persisting them would create a second place to
look for the same number and a second thing to keep current when an observation
changes.

### Replicate dispersion

Redundant readings of one marker on one clock are preserved with
`included_in_fit = 0` and reported, per anchor and clock, as:

| Field | Meaning |
| --- | --- |
| `source_observation_count` / `reference_observation_count` | how many readings exist |
| `source_spread_s` / `reference_spread_s` | the full range across all readings, in seconds |
| `source_max_deviation_s` / `reference_max_deviation_s` | the largest gap between any reading and the one used |

**An anchor read once has no dispersion.** That is reported as `NaN`, not as
zero: one reading agreeing with itself is an absence of evidence, not evidence
of agreement.

A replicate never enters the design matrix, never becomes an independent anchor,
and is never averaged with the included reading.

### Anchor configuration

Per transform: how many anchors paired, how many were included, how many were
withheld, how many could not pair at all, the range and span of the included
anchors on the source clock, and the largest gap between consecutive anchors as
a fraction of that span.

The span and gap matter because anchors clustered at one end of a session
support an offset far better than a slope, and a fit summary alone cannot show
that. **These are numbers for a reader to judge.** None is a threshold or a
grade, and nothing in the repository compares them against a criterion.

### Leave-one-out influence

Per included anchor: how far `scale` and `offset_s` move when that anchor alone
is dropped and the model is refitted.

It **mixes residual with leverage**, and conflating those is the easy mistake. An
anchor at the end of a session moves a slope more than one in the middle does,
however well it was read. A large delta means this reading matters to the answer,
not that it is wrong.

An anchor whose removal leaves too few readings to determine the model has no
influence number, because the counterfactual fit does not exist.

## Exclusion is declared, never automatic

There is no robust regression, no iterative reweighting, no sigma clipping, and
no rule anywhere that drops an anchor because its residual looked large.

Exclusion lives on the observation, in `included_in_fit` and `observation_role`,
which is where the schema puts it and where it is auditable.
`vawlume.alignment.setAnchorInclusion` is how a caller declares it:

- **a reason is required in both directions.** Withholding evidence and restoring
  it both change which readings produced a fit;
- the decision is **appended** to the observation's `notes`, so that column reads
  as a log of what was decided about this reading;
- it touches exactly three columns. No timestamp, clock, event link, uncertainty,
  or provenance column is writable through it. An anchor's observed time is
  evidence; whether it counts is a decision, and only the decision is editable;
- restoring a reading while another is already included for that anchor and clock
  raises, rather than letting one anchor become two statistical anchors;
- repeating a decision already in force writes nothing.

A withheld anchor is still evaluated and still receives a residual it did not
influence.

## Anchors the fit never saw

Two cases were previously invisible and are now reported rather than skipped:

- **unpaired anchors** — an anchor observed on only one of the two clocks, or
  observed several times on one clock with none included, cannot pair. It is
  returned in `unpaired_anchors` with the count on each clock and the reason,
  instead of being dropped in silence;
- **clocks with anchors but no transform** — readings registered on a clock the
  set does not align. This is legal, and it is equally often a manifest that named
  a stream and forgot its transform, so it is reported in
  `anchors_without_transform` rather than raised or ignored. The set's reference
  clock is never listed: every anchor is read on it by definition.

## Residual evidence

For every evaluated anchor:

```text
predicted_reference = scale * observed_source + offset
residual_s          = observed_reference - predicted_reference
```

Summaries stored on the run:

```text
fit_rmse_s   = sqrt(mean(residual_s .^ 2))     over included anchors
max_error_s  = max(abs(residual_s))            over included anchors
```

Each `alignment_anchor_residuals` row names **both** observations it was computed
from, plus the observed source and reference times and the prediction, so a fit
can be recomputed by hand rather than trusted because a summary number looked
small.

## Status semantics

```text
registered  →  estimated
```

A successful fit sets `estimated`. **It never sets `validated`.** Solving is not
validating: this prototype ships no calibrated acceptance threshold, and a small
residual on synthetic anchors is a statement about the fixture, not about a
device. `validated` remains reachable only through an explicit rule that does not
yet exist.

The alignment set moves from `draft` to `fitted` once none of its runs is still
`registered`.

Deriving a threshold from the synthetic fixture and presenting it as a default
would be exactly the error this project keeps refusing elsewhere.

## Uncertainty

Anchor `uncertainty_s` is preserved through registration, carried into the QC
result, and reported per anchor — **and is not used as a fit weight**.

The fit is unweighted ordinary least squares. Weighting anchors by a recorded
uncertainty is a different estimator, and nothing here establishes that the
recorded values are comparable across devices or correctly scaled. No confidence
interval or formal precision claim is produced.

## Identity and refitting

A completed transform is never rewritten in place.

| Situation | Behaviour |
| --- | --- |
| Run is `registered` with no segment | fit and store |
| Run is fitted, refit gives the same coefficients | `reused`, nothing written |
| Run is fitted, refit gives different coefficients | conflict; needs a new alignment identity |
| Run has a non-`registered` status but no segment | conflict; refitting would invent a history |
| Run stores several segments | conflict; piecewise is not fitted or refitted |

Changing which anchors are included changes the answer, and that is a different
alignment rather than a correction to this one. The fit result is reconstructable
from the alignment analysis run, the set, the two clocks, the method, the manifest
and mapping-profile checksums registration recorded, and the specific observation
IDs named in each residual row.

## Transactions

Fit apply requires an AutoCommit connection, disables AutoCommit, writes every
segment, residual, run summary, and the set status, then commits. Any exception
rolls back and restores the original AutoCommit state before rethrowing. A
failure part way through leaves no segment, no residual, and every run still
`registered`.

## Applying a transform

```matlab
[aligned, transform] = vawlume.alignment.applyTransform(conn, runId, nativeTimes)
```

- reads stored `alignment_segments` coefficients; **never refits**;
- accepts scalars and vectors and preserves shape;
- returns the coefficients, clocks, method, fit summary, and status actually
  used, so a caller can record what produced a number;
- raises on a `registered` (unfitted), `rejected`, or `failed` run rather than
  returning a plausible-looking number;
- raises on multiple segments;
- writes nothing.

Native timestamps on detections, external events, coverage, and anchor
observations are never modified. An aligned time is derived on demand from the
transform of record.

## Limitations

- Offset, affine, and continuous piecewise affine over **declared** breakpoints.
  Breakpoint estimation is refused rather than deferred; nonlinear warping is not
  implemented at all.
- Piecewise segments are continuous by construction. A clock discontinuity has no
  representation here.
- Unweighted least squares; recorded uncertainty is not a weight.
- No outlier detection, and no automatic exclusion of a badly fitting anchor.
  Exclusion is a human decision, recorded on the observation and declared
  through `setAnchorInclusion`.
- Diagnostics are reported, never judged. Dispersion, anchor configuration and
  leave-one-out influence describe an anchor set; nothing decides from them.
- Leave-one-out influence conflates residual with leverage and should not be
  read as a measure of anchor quality.
- No confidence intervals, standard errors, or p-values.
- Residual size is reported, not judged. Nothing here decides whether a fit is
  good enough for a scientific purpose.
- Every transform exercised so far was fitted from synthetic anchors generated
  from a known transform. Recovering those parameters demonstrates that the
  arithmetic is correct; it says nothing about real device clocks.
