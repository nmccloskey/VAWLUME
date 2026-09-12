# Temporal Alignment and Sequence-Ready Timeline Contract

## Status

**Implementation checkpoint.** The normalized relational grammar, the
database-free external-event/anchor source-mapping layer, session-manifest intake
and registration, source-to-reference transform fitting with residual QC,
common-time event projection, coverage projection, and the small regularized
timeline are implemented. **The Phase 7 integration and exit gate has passed** —
see [Phase 7 exit state](#phase-7-exit-state) below for the result and the
fifteen known limitations recorded at exit.

This document is the governing contract for VAWLUME's first external-stream
temporal-alignment implementation. It defines vocabulary, invariants, schema
direction, the input/output boundary, and exit criteria, and it records an audit
of what the inherited draft schema already supports.

The original pairwise alignment draft has been replaced by timebases, logical
streams and sources, events and attributes, coverage, alignment sets, logical
anchors and observations, pairwise transforms, and per-anchor residual evidence.
Versioned JSON mapping profiles normalize synthetic external event and long/wide
anchor tables into one validated IR; a compact session manifest registers that IR
transactionally; and offset and affine transforms are fitted from explicit
logical anchors, recovering known synthetic parameters to within floating-point
noise. Fits are recorded as `estimated`, never `validated`.

`vawlume.alignment.commonTime` derives aligned event timestamps on demand through
`applyTransform`, which reads the stored transform that remains the authority.
`vawlume.sequence.regularizeTimeline` builds a MATLAB-only dense working table;
neither API creates a second canonical timestamp or persists empty bins.

**Phase 3 is implemented.** It robustifies this layer rather than redesigning it:
piecewise-affine fitting, anchor QC and declared exclusion, interval
transformation, uncertainty propagation, and identity-dependent anchor evidence.
Its decisions and delivered implementation boundary are recorded in [Phase 3 —
alignment robustification](#phase-3--alignment-robustification) below.

Read this document before changing anything under the alignment tables. Read
`07_matching_and_consensus.md` in `docs/development/` for what the correspondence
layer beneath it already guarantees.

## Emphasis: alignment first

This phase is an **alignment phase**, not a sequence-analysis phase.

The goal is to make heterogeneous event streams expressible on a user-selected
reference timebase while preserving native timestamps, source provenance, anchor
evidence, and fit diagnostics — plus the minimum regularized-timeline foundation
needed to prove that aligned vocalization, behavioral, and neural events can be
coordinated in common bins.

The following are **explicitly deferred to a later phase** and must not be
pre-implemented here: transition matrices, transition entropy, n-grams, motif
discovery, edit distance, string alignment, sequence clustering, NLP- or
bioinformatics-style sequence methods, broad bout analysis, hierarchy-aware
inference, and machine learning.

This is a deliberate reframing of what the Phase 6 exit documentation called
"one compact sequence/alignment analysis." Sequence analysis over vocalization
events is only meaningful once those events and the behavioral or neural events
they are being related to share a defensible common clock. Building the ordering
machinery first would mean ordering events whose relative timing is not yet
established. Alignment is therefore the prerequisite, and it is large enough to
own a phase.

## Motivating workflow

```text
VAWLUME vocalization detections / consensus events
+ external behavioral event table(s)
+ external neural event / TTL table(s)
+ optional video event / annotation table(s)
+ a session-specific alignment manifest
+ explicit cross-stream anchor observations
                    ↓
source mapping / registration
                    ↓
VAWLUME operational ontology
    timebases
    external streams
    events + attributes + coverage
    logical anchors + observations
                    ↓
temporal alignment
    user-selected reference timebase
    source → reference transforms
    residuals / QC evidence
                    ↓
common-time event views
    native timestamps preserved
    aligned timestamps derived
                    ↓
regularized timeline view
    explicit bin width / origin / rules
    event absent ≠ not observed
```

## Core vocabulary

### Reference timebase, not ground truth

The user chooses a **reference timebase** for an alignment set, and VAWLUME
expresses the participating source clocks relative to it. The designation is a
coordinate choice. It does not assert that the reference device is physically
perfect or scientifically privileged, and nothing in the implementation may
treat it as more correct than the clocks aligned to it.

Vocabulary stays at the timebase level rather than the modality level. A neural
file may contain several event streams sharing one device clock; a video file
may contain annotations and sync-light events sharing another. Alignment
operates on clocks, not on file types, extractor names, or modality labels.

### Synchronization anchor versus experimental event

A **synchronization anchor** establishes a relationship between clocks. An
**experimental event** occurs on one of those clocks. These are different kinds
of object and must not be conflated.

A light/tone/TTL combination used to coordinate streams is an alignment anchor
even when it happens to fire near a scientifically interesting transition. If a
`female_entry` event is scored separately from video, it is an experimental
event and must not be forced to equal the synchronization edge that happened to
occur nearby.

### Logical anchor versus anchor observation

One **logical anchor** may be **observed** on several timebases:

```text
sync_03
  audio observation    t = 12.004
  video observation    t = 11.876
  neural observation   t = 302.551
```

It may also carry redundant observations on a single timebase. Those
observations are preserved rather than prematurely averaged, because the spread
between them is evidence about synchronization quality.

For the prototype, fitting requires an explicit primary or included observation
wherever duplicates would otherwise make the correspondence ambiguous.
Replicates remain QC evidence.

### Native events versus normalized operational labels

Phase 7 does not create a universal behavioral or neural ontology. It needs a
domain-agnostic operational representation carrying:

- stream and timebase identity;
- native event identity and label;
- optional normalized project event key;
- native start and end time;
- optional entity/subject link;
- optional scalar value;
- extensible attributes;
- source location and mapping provenance.

Native labels stay inspectable even when a mapping profile supplies a normalized
key. This is the same additive rule the extractor layers already follow:
normalization never destroys the native record.

## Timebase contract

Every VAWLUME audio recording resolves **one unambiguous native recording
timebase**. Vocalization detections and consensus-event times inherit that clock
through the recording. They must not gain redundant `timebase_id` columns.

External streams reference their timebase explicitly.

## Alignment-set contract

A user-facing multimodal alignment operation is an **alignment set**:

```text
alignment set
  reference timebase = neural_native
  source audio-native timebase
  source video-native timebase
  logical anchors + observations
  audio → neural transform
  video → neural transform
```

The set is associated with one analysis-run identity and with the exact
manifest and configuration evidence used. **Pairwise transforms are children of
the set, not independent user-facing analyses.** This mirrors the parent/child
analysis pattern Phase 6 already established between a matching analysis and its
agreement child.

## Source-mapping and manifest boundary

Two distinct responsibilities.

### Reusable mapping profiles

Versioned JSON profiles explain how to interpret user tables: timestamp column,
optional end-time column, native event ID column, native label/type column,
normalized event mapping, units, attribute columns, coverage declarations,
anchor ID column, stream/timebase column, and wide-versus-long anchor layout.

`+source_mapping` extends its validated, provenance-bearing IR as needed and
**remains database-write-free**.

### Session-specific alignment manifest

The manifest identifies one concrete alignment operation:

```json
{
  "recording_key": "synthetic_session_01",
  "reference_timebase": "neural_native",
  "streams": [...],
  "anchor_source": {...},
  "method": "affine"
}
```

A manifest is not a reusable semantic profile. It is treated as a
provenance-bearing source/artifact linked to the alignment set, while reusable
external-stream and anchor mapping rules remain versioned mapping profiles.

No `alignment_manifest` profile kind is added merely to force a session-specific
file into the reusable-profile ontology. The audit below confirms this is
unnecessary: `config_profiles.profile_kind` already offers
`external_stream_mapping` for the reusable half, and `artifacts` / `source_files`
already carry path plus SHA-256 for the session-specific half.

A manifest designates a reference timebase and participating sources. It does
not embed table data.

## Supported transform scope

Only transparent models.

### Offset-only

```text
t_ref = t_source + offset
```

Scale is fixed at 1. With several included anchors, the least-squares offset is
the mean of target minus source.

### Affine shift and scale

```text
t_ref = scale * t_source + offset
```

Two distinct included anchors identify an exact affine solution; three or more
permit residual assessment. Fitting is transparent ordinary least squares.

**Not in this phase:** robust regression, automatic outlier rejection, dynamic
time warping, nonlinear warping, learned synchronization.

### Piecewise affine

The schema retains representability for piecewise-affine segments.

**Fitting piecewise transforms was deferred in Phase 7**, and the implementation
failed clearly rather than silently degrading to a single affine fit. Degrading
silently would answer a different question than the caller asked, and that
refusal stays wherever the model is still unimplemented.

**Phase 3 implements the model**, in the layers named below. Its breakpoint,
continuity, tiling, and extrapolation decisions are D1 to D3 in [Phase 3 —
alignment robustification](#phase-3--alignment-robustification).

| Layer | State |
| --- | --- |
| `solveTransform` | **Implemented** (3.4). Continuous segments over declared breakpoints; every unsupportable configuration raises a named error and none falls back to affine |
| `fit` | **Implemented** (3.5). Declared breakpoints are persisted, segments tile on write, and an unsupportable request is recorded as `failed` with a code |
| `applyTransform` | **Implemented** (3.6). Segments are selected through one shared implementation, extrapolation is flagged, and intervals transform through `applyTransformInterval` |

A piecewise transform can therefore be solved, stored, and applied. Every
consumer reaching clock transforms through the shared API gained it without
modification, which is what the shared-use requirement was for.

## Anchor-selection rule

VAWLUME must not silently infer anchor correspondence by nearest timestamp or by
pulse order when the user has supplied explicit anchor identities or a
crosswalk. Implicit nearest-neighbour correspondence is exactly the kind of
convenient guess that produces a confident, wrong alignment.

For each source → reference fit, an included logical anchor resolves to one
included source observation and one included reference observation. Where
duplicate observations make the pair ambiguous, explicit resolution or exclusion
is required, and all observations are preserved for auditing.

## QC contract

**The transform is authoritative. Aligned timestamp materializations are derived
caches.**

Each fit preserves at least:

- method;
- scale and offset;
- number of anchors used;
- per-anchor observed source and reference times;
- predicted reference time;
- residual in seconds;
- RMSE;
- maximum absolute residual;
- inclusion/exclusion status and reason;
- manifest, profile, and analysis provenance.

No threshold is described as calibrated unless it is. Any validation tolerance
shipped in a synthetic example is clearly labelled illustrative — the same rule
Phase 6 applies to its matching thresholds.

## Coverage and regularized-timeline semantics

A regularized timeline distinguishes three states, and conflating the second
with the third is the specific failure this section exists to prevent:

1. **event present** — one or more relevant events occurred in the bin;
2. **event absent** — the stream is known to have been observed across the bin,
   and no relevant event occurred;
3. **not observed / unavailable** — stream coverage does not establish
   observation for the bin.

Phase 7 therefore represents stream coverage explicitly, using an interval
representation able to express more than one observed segment. Assuming every
source covers one uninterrupted interval forever would silently convert
unavailable bins into absent ones.

The regularized timeline is a **derived working representation**, normally a
MATLAB table or timetable. Millions of blank bins are not persisted as canonical
SQLite evidence.

Every regularization records and returns its specification: reference timebase,
start/end window, bin width, bin origin and edge convention, source event sets,
aggregation rule (`onset_count`, `any_overlap`, and so on), and the handling of
uncovered bins.

## Phase 3 — alignment robustification

**Status: implemented and integrated across Phase 3.2 to 3.9.** The owning
itinerary remains named on each decision so the implementation history stays
auditable.

Phase 3 implements what this contract already represents. It adds no table to
express a concept the schema can already hold, it introduces no second path from
a native time to a reference time, and it does not revisit the vocabulary above.
The reference timebase remains a coordinate choice, a synchronization anchor
remains distinct from the experimental event beside it, and a solved fit remains
`estimated`.

### What Phase 3 changes about the Phase 7 exit limitations

The fifteen limitations recorded at the Phase 7 exit are a frozen historical
record and are not edited. This table states which of them Phase 3 removes.

| # | Phase 7 limitation | Phase 3 disposition |
| --- | --- | --- |
| 1 | Validation is synthetic | **Unchanged.** Phase 3 validation is also synthetic, and recovering a known transform still says nothing about a real device clock |
| 4 | Offset and affine only | **Removed** for piecewise affine (3.4, 3.5, 3.6). Nonlinear warping remains unimplemented and out of scope |
| 5 | Replicates preserved but not pooled | **Partially changed.** Replicates are still never pooled into the fit; their spread becomes readable QC evidence (3.3) |
| 6 | Anchor uncertainty preserved but unweighted | **Partially changed.** Still never a weight; it propagates as a stated, uncalibrated bound (3.6) |
| 7 | No calibrated QC threshold | **Unchanged, deliberately.** Phase 3 adds diagnostics, not verdicts |
| 9 | A regularized zero depends on coverage | **Extended** to coverage expressed through a transform (3.7) |
| 2, 3, 8, 10 to 15 | — | **Unchanged.** None is in Phase 3 scope |

### D1. Breakpoints are declared, never estimated

A piecewise-affine fit takes its breakpoints from the caller. VAWLUME does not
search for them.

A breakpoint is a claim that something happened to a clock — a restart, a dropped
buffer, a drift regime change. Choosing one from the residuals is model selection,
and this prototype has no basis for preferring one segmentation over another.
Inferring a breakpoint would also make the fit depend on a decision no record
names, which the refit-identity rule below forbids.

**Breakpoints are therefore persisted as declared input**, not carried only as a
call option. A fit must be reconstructable from what the database holds: the
analysis run, the set, the two clocks, the method, the registration checksums, the
observation IDs in each residual row — and now the breakpoint set. Owned by 3.2
(representation) and 3.5 (declaration path).

Breakpoint **estimation** is not deferred pending a design; it is refused. If a
later phase adds it, it must be a separately named method with its own recorded
provenance, never a default, and never silently selected.

### D2. Segments are continuous at their breakpoints

A piecewise-affine transform is continuous. The segments meet.

A discontinuity would mean one source instant maps to two reference times, which
leaves `applyTransform` ambiguous at exactly the boundary and makes an interval
spanning the join ill-defined. A genuine clock discontinuity — a reset, a lost
buffer — is a different phenomenon: it is a gap in coverage, and where the clocks
truly diverge it is two alignment identities, not one transform with a jump.

Continuity is a constraint on the fit, not a property hoped for afterwards. With
knots declared, a continuous piecewise-linear fit is one ordinary least-squares
problem in a hinge basis:

```text
reference = a0 + a1 * source + SUM_k b_k * max(0, source - knot_k)
```

Per-segment `scale` and `offset_s` follow from the coefficients by accumulation,
so `alignment_segments` stores exactly what it stores today and no new column is
needed for the coefficients. The solve stays plain `X \ y`: no optimizer, no
toolbox, no robust regression, no iterative refinement.

Every derived segment scale must be positive. A clock does not run backwards, and
`vawlume:alignment:NonPositiveTransformScale` already exists to say so. Owned by
3.4.

### D3. Segments tile the line, and extrapolation is flagged rather than hidden

The segments of a `piecewise_affine` run tile the source axis with no gap and no
overlap. The first segment is open below (`source_start IS NULL`) and the last is
open above (`source_end IS NULL`), so every finite source time resolves to exactly
one segment.

**Boundary ownership: a segment covers `[source_start, source_end)`.** A
breakpoint instant belongs to the segment that begins at it. This is stated once,
here, because `fit` and `applyTransform` must not disagree about it and an
off-by-one at a breakpoint is the defect most likely to survive review.

Tiling is an application obligation — `11_temporal_alignment_schema.md` lists it
as such — and Phase 3 discharges it by enforcing tiling on write rather than by
adding a trigger that SQLite cannot express cleanly across rows. Owned by 3.5.

A time outside the **anchored source span** is still transformed, using the
terminal segment, and is **flagged as extrapolated in the result**. It is never
returned as though it were equally well supported.

Refusing to extrapolate would break the existing contract, under which
`applyTransform` returns a value for every input and preserves shape. Returning an
unmarked number would be worse. The flag therefore rides in the second output,
beside the segment index that produced each value, and an `ErrorOnExtrapolation`
option lets a caller escalate it — mirroring the existing `ErrorOnOutsideCoverage`
rather than inventing a second convention. Owned by 3.6.

Extrapolation and coverage are different statements and must not be conflated:
coverage says the stream was observed, extrapolation says the transform was not
anchored there.

### D4. Intervals transform endpoint-wise, and duration is not preserved

Interval transformation is a separate public function, not a mode of
`applyTransform`. The development plan's guidance against a single switch-laden
entry point applies to this layer as much as to matching.

An interval's endpoints transform independently. Under a piecewise-affine clock
with differing segment scales, **the aligned duration is not the native duration**,
and that is correct rather than a defect. A caller who assumes duration is
preserved will be wrong exactly when drift matters most, so the help text must say
so plainly.

An interval result reports, at minimum: aligned start and end; the segments the
interval crossed; the extrapolation flag for each endpoint; and the native and
aligned durations so the change is visible rather than inferred. An interval whose
end precedes its start is refused, reusing
`vawlume:alignment:AlignedIntervalInvalid`.

`commonTime` currently transforms an event's start and end with two separate
`applyTransform` calls. That is interval transformation implemented at a caller,
and once the interval function exists `commonTime` must use it — otherwise two
interval semantics will coexist, which is the duplication this contract exists to
prevent. Owned by 3.6, with the `commonTime` change in 3.6 or 3.7.

### D5. Anchor uncertainty propagates as a stated bound, and never as a weight

The fit stays unweighted ordinary least squares. Weighting by recorded
`uncertainty_s` is a different estimator, and nothing establishes that those
values are comparable across devices or correctly scaled. That refusal is
unchanged from Phase 7 and is not reopened.

What Phase 3 adds is propagation. Each segment carries a bound derived from the
anchors that determined it, stored in the `uncertainty_s` column
`alignment_segments` already has, beside a new column declaring its semantics.
`applyTransform` returns that bound for each transformed time.

The semantics are deliberately modest: the bound is the **largest recorded anchor
uncertainty among the anchors contributing to that segment**, expressed in
seconds. It is **not** a confidence interval, a standard error, a posterior, or a
probability, and every place it surfaces must say so.

Two rules make it honest:

- **Absence propagates as absence.** A segment whose contributing anchors recorded
  no uncertainty carries no bound — not zero, which would claim perfect knowledge.
  The fitter already represents a missing anchor uncertainty as `NaN` rather than
  `0`; that precedent is extended, not replaced.
- **The bound is never combined with the residual.** Fit residual and anchor
  reading precision are different quantities: one says how well the model
  describes the anchors, the other how well each anchor was read. Both are
  reported; neither is folded into the other, nor into a single "alignment
  confidence".

Following the Phase 2 precedent that a stored number without declared semantics is
not stored, the schema requires the semantics whenever the value is present.
Owned by 3.2 (column and constraint), 3.5 (population), 3.6 (propagation).

### D6. Replicate dispersion is derived, never stored

Redundant observations of one anchor on one clock are already preserved, already
excluded from the fit by a partial unique index, and already counted by the fitter
as `source_observation_count` and `reference_observation_count`.

Their spread is a **pure function of `alignment_anchor_observations`**, which is
the authority for those rows. Persisting it would create a second place to look
for the same number and a second thing to keep current when an observation is
added or re-included. It is therefore computed on read and surfaced through the
fit result and through `report`, and no table is added for it.

What is surfaced, per anchor and clock with more than one observation: the
observation count, the included observation's time, the full spread across all
observations, and the largest deviation of any other observation from the included
one — each in seconds, with declared semantics.

A replicate never enters the design matrix, never becomes an independent anchor,
and is never averaged with the included reading. Owned by 3.3.

### D7. Failure states are named, and a failure is distinguishable from an absence

The status vocabulary does not grow. `registered`, `estimated`, `validated`,
`rejected`, and `failed` remain the only run states, and `validated` remains
unreachable.

What Phase 3 adds is the **reason**. A run that failed for a nameable cause
records a machine-readable code and a human-readable reason, so a `failed` run is
distinguishable from one that was never attempted — today a run that could not be
fitted and a run nobody tried both sit at `registered` with no segments.

Conditions are classified as one of three things, and the classification is part
of the contract:

| Condition | Class |
| --- | --- |
| Piecewise requested with no declared breakpoints | raised error |
| Breakpoints unsorted, duplicated, non-finite, or outside the anchor span | raised error |
| A segment with too few anchors to determine its own coefficients | raised error |
| A derived segment scale at or below zero | raised error |
| Persisted segments that would gap or overlap | raised error, on write |
| Anchors on a clock that has no transform in the set | reported in the result and in `report` |
| A transformed time outside the anchored span | flagged in the result; raised only under `ErrorOnExtrapolation` |
| An anchor set that cannot support its declared model | persisted `failed` with a code |

Named identifiers extend the existing `vawlume:alignment:` family rather than
starting a parallel one, and the existing identifiers are reused wherever they
already say the right thing. Owned by 3.1 (vocabulary), 3.2 (persistence), 3.3
through 3.6 (each raises its own).

### D8. An identity-dependent anchor keeps its uncertainty, and the solver never sees it

Device-level anchors — TTL, light, tone — are identity-independent, and their
transforms must stay that way. An anchor derived from an identity-dependent
biological event is admissible; an anchor whose identity uncertainty has been
silently discarded is not.

Three things stay apart: the observation's timestamp, which is a number on a
clock; the observation's **evidence class**, which is `device_level` or
`identity_dependent`; and the **visual-identity evidence** for the entity the
event concerns, which Phase 2 already represents in
`tracking_identity_associations` with declared value semantics, calibration
status, review state, and representable ambiguity.

Decisions:

- The evidence class is **nullable**. An observation whose class was never
  declared must stay distinguishable from one declared `device_level`, because a
  default would convert an unexamined case into a confident one — the same rule
  Phase 2 applies to a missing identity confidence. An unrecognized class is
  refused, not coerced.
- Identity evidence is linked from the anchor observation to an existing
  `tracking_identity_associations` row. Phase 3 creates no identity evidence,
  invents no entity or track, and computes no score.
- **Several links per observation are legal.** An anchor qualified by `ambiguous`
  identity evidence is a real case; refusing it would push the ambiguity out of
  the record rather than represent it.
- `external_events.entity_id` is **not** the identity evidence.
  `11_temporal_alignment_schema.md` already documents it as a declared
  label-lookup link weaker than an identity association, and treating it as
  evidence here would deepen that known weakness rather than work around it.

The separation cannot be enforced by the database — SQLite cannot forbid a join —
so it is enforced by construction and held by test: the fitted coefficients must
be **bit-identical** with and without identity evidence attached, across
confident, weak, `ambiguous`, and `unresolved` cases. That test is the difference
between documenting a boundary and holding one.

**Implemented in 3.8.** The evidence class arrives through the ordinary anchor
mapping profile, `vawlume.alignment.linkAnchorIdentityEvidence` cites Phase 2
evidence without creating any, and `report` surfaces both beside the residuals.
The invariance test covers seven variations, including rewriting every identity
score and reclassifying every anchor; see
`13_transform_fitting_and_alignment_qc.md`, "Identity-dependent anchors".

VAWLUME does not down-weight an anchor for weak identity evidence, does not decide
whether an identity-dependent anchor should have been used, and does not detect
that an anchor was misidentified. Owned by 3.2 (representation) and 3.8
(behaviour and proof).

### D9. A diagnostic that can be recomputed is not stored

Phase 3 produces more evidence than Phase 7 did: replicate dispersion, anchor
span and distribution across the source range, per-anchor influence on the fitted
coefficients, and per-segment fit quality.

The rule governing all of it:

> Persist declared inputs and outcomes that would otherwise be lost. Derive
> anything that is a pure function of stored evidence.

So breakpoints are stored (a declared input), evidence class and identity links
are stored (declared inputs), failure codes are stored (an outcome that vanishes
otherwise), and per-segment coefficients and fit summaries are stored (outcomes).
Dispersion, anchor span, and leave-one-out influence are derived on read.

`alignment_anchor_residuals` remains the single authority for per-anchor fit
evidence. Nothing added in this phase becomes a second place to look for a number
that table already holds.

And a diagnostic is not a verdict. Reporting an influence measure is in scope;
deciding that a fit is good is not, and no column may encode that judgement.
Owned by 3.2 (what little is persisted) and 3.3 and 3.7 (what is derived and
surfaced).

### Phase 3 non-goals

Beyond the Phase 7 non-goals above, which all still hold:

- breakpoint estimation, changepoint detection, or automatic segmentation;
- weighting a fit by recorded uncertainty, in any form or under any name;
- robust regression, iterative reweighting, sigma clipping, or automatic anchor
  exclusion;
- confidence intervals, standard errors, or p-values presented as calibrated;
- any threshold that would let a fit become `validated`;
- rewriting a completed transform in place;
- discontinuous piecewise transforms;
- a second clock-correction path for any modality;
- caller attribution, caller probability, combined confidence, or `+attribution/`;
- declaring breakpoints from the session manifest — worth doing, deferred past
  Phase 3 so the fitting work stays bounded.

## Non-goals

Not in the first (Phase 7) alignment implementation:

- full continuous neural-signal ingestion;
- sample-by-sample photometry or miniscope storage in SQLite;
- acquisition-system synchronization control;
- automatic anchor detection from waveform or video pixels;
- nearest-pulse automatic cross-stream matching;
- nonlinear time warping;
- automatic scientific interpretation of event labels;
- a universal behaviour ontology;
- full sequence persistence redesign;
- transition matrices, transition entropy, n-grams, motifs, edit distance,
  string alignment, sequence clustering, or NLP/bioinformatics experiments;
- broad bout analysis;
- hierarchy-aware inference or machine learning;
- GUI or manual annotation tooling;
- use of real pilot data as a tracked fixture.

## Inherited schema audit

The eleven draft tables were inspected against this contract. The audit is
recorded here because it is the direct input to the schema pass, and because
"the tables already exist" is misleading: several represent a **pairwise,
single-observation** model that structurally cannot express what this contract
requires.

### Concept coverage

| Concept required | Current representation | Verdict |
|---|---|---|
| Timebase | `timebases` | Present; needs a constrained kind vocabulary and a working uniqueness rule |
| Logical stream | `external_streams` | Present, but fused with its source |
| Stream source | fused into `external_streams` (`source_file_id`, `artifact_id`, `mapping_profile_version_id`) | Not separated |
| External event | `external_events` | Present; no normalized project key, no attributes |
| Event attributes | — | **Missing** |
| Stream coverage | — | **Missing** |
| Logical anchor identity | — | **Missing** |
| Anchor observation | — | **Missing** |
| Alignment set | — | **Missing** |
| Pairwise transform | `time_alignment_runs` + `alignment_segments` | Partial; scale/offset live only in segments |
| Per-anchor residual evidence | — | **Missing** |
| Aligned event materialization | `aligned_external_events` | Present |

### Specific findings

1. **`alignment_anchors` cannot express a multi-timebase anchor.** Each row is a
   flat `(source_time, target_time)` pair scoped to one pairwise run. There is no
   logical anchor entity, so one anchor observed on three timebases is
   unrepresentable except as unrelated pairwise rows, and redundant observations
   on one timebase cannot be distinguished from separate anchors. The row also
   carries no predicted time, residual, inclusion status, or exclusion reason.
   This blocks definition-of-done items 7 and 9.

2. **There is no alignment set.** `time_alignment_runs.analysis_run_id` is
   `NOT NULL UNIQUE`, which forces every pairwise transform to be its own
   analysis run. That directly contradicts the alignment-set contract, under
   which pairwise transforms are children of one reference-bearing set.

3. **There is no coverage representation**, so `absent` cannot be distinguished
   from `unavailable`. This blocks item 12 and therefore item 13.

4. **`timebases UNIQUE(project_id, recording_id, timebase_name)` does not
   constrain project-scoped timebases.** SQLite treats NULLs as distinct in a
   UNIQUE index, so rows with `recording_id IS NULL` can be duplicated freely.
   `external_streams UNIQUE(project_id, stream_name, source_file_id)` has the
   same defect for streams with no source file.

5. **Nothing guarantees one native audio timebase per recording.**
   `timebase_kind` is unconstrained TEXT with no vocabulary and no uniqueness on
   the native-audio role, so item 2's "one unambiguous native recording
   timebase" is currently a convention rather than an invariant.

6. **`external_events` has `event_type` only.** There is no place for a
   normalized project event key alongside the native label, and no attributes
   table, so the operational representation above is not yet expressible.

7. **Transform parameters live only in `alignment_segments`.** An offset-only or
   global affine fit has to be encoded as a single segment row. Workable, but the
   schema pass should decide deliberately whether a global fit is first-class or
   always a one-segment case, rather than leaving it implicit.

8. **The schema header comment says `Version: 0.1-draft` while `schema_info`
   seeds `0.2-draft`** (with `PRAGMA user_version = 2`). Pre-existing
   inconsistency; worth correcting when the version is next bumped.

### Already correct — preserve

- **`detections` carries no `timebase_id`.** Item 2's "without redundant
  timebase FKs on every detection" already holds structurally. `detections` has a
  free-text `timing_basis` and inherits its clock through `recording_id`.
- **`analysis_runs` supports the set/child pattern.** `run_type` is free text and
  `parent_analysis_run_id` exists, with the Phase 6 matching → agreement
  parent/child relationship as working precedent.
- **`config_profiles.profile_kind` already included `external_stream_mapping`.**
  Pass 3 added `alignment_anchor_mapping` because long/wide anchor layout and
  required observation identity are materially different from event-stream
  rules. No `alignment_manifest` kind was added.
- **`artifacts` and `source_files` carry `path_or_uri` plus `checksum_sha256`.**
  A session manifest can be registered as provenance-bearing evidence without
  inventing an `alignment_manifest` profile kind.
- **`+source_mapping` is verified database-free.** It exposes no connection
  argument and calls no SQLite, `fetch`, `execute`, or `sqlwrite` API. This
  invariant must survive the phase.
- **`mapTableToIR` already accepts an arbitrary MATLAB table plus a profile** and
  returns the validated IR, so external event and anchor tables need a profile
  kind and validation rules rather than a new entry point. Its documented
  vocabulary now includes `external_stream_mapping` and
  `alignment_anchor_mapping` beside the inherited two kinds.
- **`external_streams.stream_kind`** already permits `event`, `annotation`,
  `video`, `ttl`, `continuous`, and `other`, covering the motivating workflow.
- **`sequences`, `sequence_members`, `bouts`, and `bout_members` are entirely
  unused** — no fixture rows, no tests beyond a view-name check. They can be left
  untouched while sequence analytics is deferred.

### Compatibility constraint

The Phase 1 synthetic fixture populates `timebases`, `external_streams`,
`external_events`, `time_alignment_runs`, `alignment_anchors`,
`alignment_segments`, and `aligned_external_events`, and acceptance query **Q12
("External event alignment")** reads `v_external_events_aligned`. Any schema
change must keep the fixture and Q12 working, or update both deliberately and
say so.

The fixture's transform — `scale = 1`, `offset = 0.55 s`, two anchors, RMSE
0.001 s — is exactly the shape the transform-fitting pass will fit, which makes
it a natural regression target rather than an obstacle.

## Definition of done

Phase 7 passes only when all of the following hold:

1. the schema cleanly distinguishes timebases, logical streams, stream sources,
   events, anchor identities, anchor observations, alignment sets, pairwise
   transforms, and residual evidence;
2. every VAWLUME recording resolves one native audio timebase without redundant
   timebase FKs on every detection;
3. external event and anchor tables can be mapped through versioned JSON mapping
   rules while preserving native values, labels, and source provenance;
4. `+source_mapping` remains database-write-free;
5. a session-specific manifest can designate a reference timebase and
   participating sources without embedding table data;
6. source mapping and ingest can register at least synthetic audio,
   video/behavioural, and neural/TTL clocks and events plus anchor observations;
7. one logical anchor can have observations on three or more timebases and can
   preserve redundant observations without pretending they are independent
   logical anchors;
8. offset-only and affine source → reference transforms are fitted
   deterministically from explicit anchors;
9. fit diagnostics and per-anchor residuals are stored and read back with
   provenance;
10. native event and detection timestamps are never overwritten by alignment;
11. calls/consensus events and external events can be projected into one
    reference-time representation through authoritative transforms;
12. stream coverage permits `absent` to be distinguished from `unavailable` in a
    regularized timeline;
13. a small configurable regularization demonstrates aligned vocalization plus
    external events in common bins without making the dense timeline canonical
    SQLite storage;
14. an end-to-end synthetic demonstration reconstructs known transforms and
    produces auditable aligned event and timeline output;
15. upstream Phase 1–6 behaviour remains passing;
16. durable documentation describes the new capability without claiming complete
    multimodal synchronization or broad sequence analytics.

## Pass sequence

```text
contract  (this document)
        ↓
alignment schema and timebase ontology
        ↓
external-stream and anchor source mapping
        ↓
alignment intake and registration
        ↓
transform fitting and alignment QC
        ↓
common-time views and regularized-timeline demonstration
        ↓
integration review and exit gate
```

Each pass leaves a reviewable checkpoint and a handoff recording files changed,
tests and results, Git state, decisions, assumptions, unresolved issues, and
minimum next-pass context.

## Inherited regression floor

The state this phase builds on:

```text
265 tests passing, 0 failed, 0 incomplete
checkcode clean across the repository
PRAGMA foreign_key_check clean
```

No Phase 6 limitation blocks this phase.

## Phase 7 exit state

The integration and exit gate passed. The regression floor leaving this phase:

```text
329 tests passing, 0 failed, 0 incomplete
checkcode clean across the repository
PRAGMA foreign_key_check clean
```

### Known limitations at exit

These are properties of the implementation, not oversights to be quietly fixed
later. Each is a place where the prototype deliberately stops short.

1. **Validation is synthetic.** Every transform exercised so far was fitted from
   anchors generated from a known transform. Recovering those parameters shows
   the arithmetic is correct; it says nothing about real device clocks.
2. **Only timestamped event streams are ingested.** Continuous neural,
   photometry, and video samples remain external files. VAWLUME registers events
   and coverage, not signals.
3. **Anchor identities are user-supplied.** There is no automatic anchor
   discovery from waveforms or pixels, and no nearest-pulse correspondence.
4. **Offset and affine only.** Piecewise-affine is representable in the schema
   and refused by the fitter and by `applyTransform`; nonlinear warps are not
   implemented at all.
5. **Replicate anchor observations are preserved but not pooled.** One included
   observation per clock enters a fit; redundant readings stay as QC evidence and
   are never averaged.
6. **Anchor uncertainty is preserved but unweighted.** The fit is unweighted
   ordinary least squares. No confidence interval, standard error, or formal
   uncertainty propagation is produced.
7. **No calibrated QC threshold exists.** Residuals are reported, never judged. A
   solved fit is recorded `estimated`, never `validated`, and nothing decides
   whether a fit is good enough for a scientific purpose.
8. **Event-label normalization is project configuration**, not a universal
   behavioural or neural ontology. Native labels always survive beside the
   normalized key.
9. **A regularized zero depends on coverage.** Zero means the stream was observed
   across the whole bin and nothing happened. Without valid coverage the bin is
   unavailable, and the distinction is only as good as the declared coverage.
10. **Sequence, bout, and hierarchy-aware analyses are deferred** to Step 11.

Discovered during the exit audit and specific to this implementation:

11. **Coverage comes only from profile-declared constant segments** or explicit
    manifest deferral; mapping a separate coverage-segment table is not
    implemented.
12. **Recording coverage is duration-derived.** A recording contributes
    `0 -> duration_s` when a duration exists, and contributes nothing when it does
    not. There is no multi-segment audio-dropout model analogous to external
    stream coverage.
13. **One source file per manifest stream declaration.** The schema and
    `external_stream_sources` can represent several files composing one logical
    stream, but no manifest drives that yet.
14. **An event spanning two adjacent coverage segments is rejected** unless one
    segment contains it completely. Merging demonstrably contiguous coverage may
    be worth adding; guessing across a gap is not.
15. **`aligned_external_events` has no public refresh API.** It remains an
    optional regenerable cache that no code path requires or populates.
