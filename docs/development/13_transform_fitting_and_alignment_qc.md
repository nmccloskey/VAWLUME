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
plan   = vawlume.alignment.fit(conn, alignmentRef, Breakpoints=knots, SourceTimebase=key)
result = vawlume.alignment.fit(conn, alignmentRef, Apply=true)
value  = vawlume.alignment.report(conn, alignmentRef)
[aligned, transform] = vawlume.alignment.applyTransform(conn, alignmentRunId, nativeTimes)
intervals            = vawlume.alignment.applyTransformInterval(conn, alignmentRunId, starts, ends)
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

`vawlume:alignment:MethodNotImplemented` and
`vawlume:alignment:PiecewiseNotImplemented` are both **retired**. With the
declared path implemented in the solver, the fitter and the applier, and
estimation refused rather than deferred, no request reaches either. Neither
identifier appears anywhere in the source or the tests; both are recorded here
so they do not become folklore.

What replaced the applier's refusal is narrower and more useful:
`SegmentTilingInvalid` when a stored segmentation gaps or overlaps, because a
gap is a real defect where several segments are not.

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

## Persisting a piecewise fit

`fit` takes the breakpoints with `Breakpoints=`, and **`SourceTimebase` must name
the transform they belong to**. A breakpoint is a claim about one clock;
broadcasting one caller's set across every piecewise transform in a set would
attribute a drift regime to clocks that never showed it.

Apply persists the declared set in `alignment_run_breakpoints`, so the fit stays
reconstructable from the database alone: the same anchors under a different
segmentation give a different answer, which makes the set part of what produced
the coefficients. A later `fit` on the same transform **reuses the stored
declaration** and needs no restatement.

Segments are written one row per segment with their bounds, per-segment `rmse_s`,
and a per-segment uncertainty bound. Offset and affine write one segment open at
both ends, so the table has one shape whatever the method was.

### Tiling is enforced on write

`vawlume.alignment.internal.assertSegmentsTile` refuses any segmentation that
gaps, overlaps, misnumbers its segments, or bounds its first or last segment.
Nothing reaches `alignment_segments` without passing it.

`11_temporal_alignment_schema.md` lists tiling as an obligation the database
cannot express across rows. It is still not database-enforced — it is
application-enforced, in one place, with a regression test that fails if the
guard is removed.

`vawlume.alignment.internal.evaluateSegments` is the single implementation of
segment selection. The fitter predicts anchors through it and the applier reads
through it, so the two cannot disagree about which segment owns a breakpoint
instant. They are an internal package rather than `private/` because MATLAB
refuses a private directory on the path, which would leave both untestable.

### Refit identity, with breakpoints

| Situation | Behaviour |
| --- | --- |
| No stored breakpoints, none declared | `failed` with `BreakpointsRequired` |
| Stored breakpoints, none declared | the stored set is reused |
| Stored breakpoints, the same set declared | reuse |
| Stored breakpoints, a different set declared | conflict; needs a new alignment identity |
| Stored segments differ in number or coefficients from the refit | conflict |

## Failures are recorded, not merely reported

A **conflict** is a disagreement with what is already stored. It blocks the whole
apply, because writing over it would rewrite history.

A **failure** is one transform's own outcome: it was attempted and could not be
honoured. It is recorded on that transform as `status = 'failed'` with a
`failure_code` and `failure_reason`, and it leaves the other transforms alone, so
one clock's missing evidence does not take a session down with it.

Without this a run that was tried and could not be fitted would be
indistinguishable from one nobody attempted: both would sit at `registered` with
no segments.

A set is `fitted` only when every one of its transforms is `estimated`. A set
holding a failed transform stays `draft`, because a partial outcome that reads as
a complete one is exactly the distinction the status vocabulary exists to keep.

## Transactions

Fit apply requires an AutoCommit connection, disables AutoCommit, writes the
segments, breakpoints and residuals, sets the run and set statuses, then commits.
Any exception rolls back the inserted rows and restores the original AutoCommit
state before rethrowing.

**Status updates are not covered by that transaction, and this is a real
limitation rather than a simplification.** Under the MATLAB `sqlite` interface an
UPDATE issued through `execute` runs outside the transaction `sqlwrite` opens: it
takes effect immediately, and a rollback does not undo it. An explicit `BEGIN` is
refused by the driver, which reports that a transaction is already in progress.

Writes are therefore ordered so that the rows a status claims exist are inserted
before the status is set. The worst reachable failure mode is a run still marked
`registered` beside rows that describe it — visible and repairable — rather than
a run claiming a fit whose evidence was rolled back out from under it.

## Applying a transform

```matlab
[aligned, transform] = vawlume.alignment.applyTransform(conn, runId, nativeTimes)
[~, transform]       = vawlume.alignment.applyTransform(conn, runId)
```

- reads stored `alignment_segments` coefficients; **never refits**;
- accepts scalars and vectors and preserves shape;
- selects a segment per time through
  `vawlume.alignment.internal.evaluateSegments`, the same implementation the
  fitter predicts anchors with, so the two cannot disagree about a boundary;
- returns the coefficients, clocks, method, fit summary, status, and per-element
  segment index, extrapolation flag and uncertainty bound;
- raises on a `registered` (unfitted), `rejected`, or `failed` run rather than
  returning a plausible-looking number;
- raises `SegmentTilingInvalid` when the stored segmentation gaps or overlaps;
- writes nothing.

Called with no times it returns the transform's description with empty
per-element arrays. Use that to inspect a transform rather than passing a dummy
instant, which asks where an arbitrary moment lands and gets an answer.

For a segmented transform the scalar `scale` and `offset_s` are **NaN**, as they
are in a piecewise `solveTransform` result. Offset and affine keep theirs, so a
caller written before segments existed reads exactly what it always did.

Native timestamps on detections, external events, coverage, and anchor
observations are never modified. An aligned time is derived on demand from the
transform of record.

### Extrapolation is flagged, not hidden

The anchored range is the span of source times the included anchors covered, read
back from the residuals. A time outside it is still transformed, using the
terminal segment, and marked in `transform.extrapolated`.

Refusing would break the promise of a value per input, which `commonTime` and
`readWindow` both depend on. Returning an unmarked number would be worse.
`ErrorOnExtrapolation=true` escalates it, mirroring `ErrorOnOutsideCoverage`.

**Coverage and extrapolation are different statements.** Coverage says the stream
was observed; extrapolation says the transform was not anchored there. A bin can
be covered and extrapolated, or anchored and unobserved.

A transform with no stored residuals leaves the range unknown.
`anchored_range_known` is then false and nothing is flagged, because the applier
cannot tell where the fit was anchored and does not guess.

### Intervals

```matlab
intervals = vawlume.alignment.applyTransformInterval(conn, runId, starts, ends)
```

A separate function, not a mode of `applyTransform`: an interval is a different
question with a different answer shape, and one entry point switching on its
arguments is how two contracts start sharing a name.

**Endpoints transform independently, so the aligned duration is not the native
duration.** An interval crossing a breakpoint is stretched by one factor at its
start and another at its end. That is what a clock that changed rate means, and
the change is reported — `native_duration_s`, `aligned_duration_s`,
`duration_change_s` — rather than left to be noticed.

Each row also carries the segment each endpoint fell in, how many segments the
interval crossed, whether it crossed a breakpoint at all, and each endpoint's
extrapolation flag. An open interval stays open. An interval ending before it
starts raises `AlignedIntervalInvalid`.

`commonTime` projects through this function. Two call sites transforming
endpoints separately is interval transformation implemented twice, and the second
copy is the one that drifts.

### Propagated uncertainty

`transform.uncertainty_s` carries the segment's stored bound — the largest
recorded anchor uncertainty among the anchors that determined it, on the
reference clock — with `uncertainty_semantics` beside it.

It is **uncalibrated**: not a confidence interval, a standard error, or a
probability. A segment whose anchors recorded none yields NaN, never 0, because
absence is not perfect knowledge. It is **never combined with `rmse_s`**: how
well the model describes the anchors and how well each anchor was read are
different quantities, and both are reported separately.

`aligned_external_events.uncertainty_s` has no semantics column of its own. That
table is an optional regenerable cache that nothing populates, and any value in
it would inherit the semantics of the segment it came from. A column duplicating
that string on a cache nothing writes would be storage looking for a purpose;
add it if and when a refresh API exists.

## Reading a set back

`vawlume.alignment.report` returns what is persisted, for the whole set. It is
read-only, refits nothing, and is the counterpart to the planning mode of
`fit`: planning recomputes coefficients from anchors, this reports the fit of
record, which is what downstream work must use.

| Field | Contents |
| --- | --- |
| `transforms` | one row per source clock, with status, segment count, and failure code |
| `segments` | one row per stored segment, with bounds and per-segment QC |
| `breakpoints` | the declared segmentation of each piecewise transform |
| `residuals` | per-anchor fit evidence, including withheld anchors and their reasons |
| `anchor_dispersion` | replicate spread per anchor and clock, **derived on read** |
| `anchor_diagnostics` | counts, anchored span, and largest gap, **derived on read** |
| `failures` | every transform attempted and not fitted |
| `clocks_without_transform` | clocks carrying readings no transform in the set can use |

Dispersion and diagnostics are derived rather than stored, for the reason the
contract gives: each is a pure function of evidence the database already holds,
and a stored copy would be a second thing to keep current. They are computed
from the same residuals the fitter used, so the read side and the plan side
agree without a second authority.

For a segmented transform `transforms.scale` and `offset_s` are **NaN**. The
query aggregates the segment rows, and reporting that aggregate would be a
number belonging to no part of the clock; `segments` carries the real ones.

## Several source clocks, one reference

An alignment set expresses **one or more source clocks in one chosen reference
frame**. `UNIQUE(alignment_set_id, source_timebase_id)` gives one transform per
source clock, and a trigger holds each run's target equal to the set's
reference.

**The reference timebase is a coordinate choice, not a claim that one device's
clock is correct.** Nothing in the fitting or reading path ranks the clocks,
treats the reference as ground truth, or propagates error from it. Choosing a
neural acquisition clock as the reference for a session says where the analysis
is expressed, not which hardware keeps better time.

Clocks fit **independently**. Each transform has its own method, its own
anchors, and its own outcome:

- one clock failing leaves the others fitted and stored;
- a set is `fitted` only when every transform is `estimated`, so a set holding
  a failure stays `draft` rather than reading as complete;
- a clock carrying anchor readings that no transform in the set can use is
  reported in `clocks_without_transform`, not raised. Registering a clock
  before its transform is legal, and a manifest that named a stream and forgot
  its transform looks identical from the database.

The set's reference clock is never listed as a clock without a transform: every
anchor is read on it by definition, and it needs no transform of its own.

## Coverage under a transform

A regularized timeline distinguishes event-present, event-absent, and
not-observed. Projection adds a fourth thing that must not be folded into the
third:

```text
observation_status   the stream's own statement: it was observed here
projection_status    the transform's: anchored, or extrapolated
```

Both are reported on every projected coverage row, and every projected event
carries `aligned_extrapolated`.

**Coverage and extrapolation are different statements.** A segment can be
observed and extrapolated at once — the stream was recording, but the transform
placing it on the reference clock was never anchored that far out. A reader who
treats the second as the first calls a well-anchored gap in the recording an
artefact of the fit, or calls an extrapolated projection observed fact.

Coverage intervals project through `applyTransformInterval` like any other
interval, so an interval crossing a breakpoint is stretched by one factor at its
start and another at its end.

## Limitations

- Offset, affine, and continuous piecewise affine over **declared** breakpoints.
  Breakpoint estimation is refused rather than deferred; nonlinear warping is not
  implemented at all.
- Piecewise segments are continuous by construction. A clock discontinuity has no
  representation here.
- Breakpoints reach `fit` only as a call argument. A session manifest cannot yet
  declare them.
- Extrapolation is flagged only when the anchored range is known, which needs
  stored residuals. A hand-built transform without them is never flagged.
- An interval's uncertainty is the larger of its endpoint bounds. Nothing
  accumulates uncertainty along an interval that crosses several segments.
- `projection_status` is per coverage interval, not per bin. A regularized bin
  inherits it from the interval it falls in.
- A set's status is `draft` or `fitted`. There is no status meaning 'fitted
  except for one clock'; the failed transform carries that fact instead.
- Run and set status updates are outside the apply transaction; see Transactions.
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
