# Imported-window to VAWLUME-event correspondence

Added at Phase 4.9. Intake ([`32_imported_attribution_intake.md`](32_imported_attribution_intake.md))
lands imported windows with their native timing and relates them to nothing. This
is where they are related to the events VAWLUME knows about.

```matlab
plan   = vawlume.attribution.correspondWindows(conn, runRef, SameClock=true)
result = vawlume.attribution.correspondWindows(conn, runRef, ...
    AlignmentRun=7, Apply=true)
```

## The question this asks, and the one it does not

**Does an imported attribution claim refer to a call VAWLUME knows about?**

That is not the question pairwise matching asks. Two detectors disagreeing about
a boundary is a measurement difference between tools doing the same job. An
attribution system's window disagreeing with a VAWLUME event may mean the two
systems were segmenting different things: one delimiting a vocalization, the other
bracketing a region wide enough to localize a caller in.

So this layer shares the interval **primitive** with matching —
`vawlume.interval.relation` computes the arithmetic for both — and shares no rule,
no threshold, and no eligibility function. `+matching/` knows nothing about
attribution, and a test asserts it.

## The clock question is answered by the caller, or refused

An imported window carries the exporting system's own native times, and intake
resolves them against no timebase. The caller must say how the clocks relate:

| Argument | Meaning | `iou_basis` |
|---|---|---|
| `AlignmentRun = <id>` | transform through a stored fit | `aligned` |
| `SameClock = true` | assert the exporter used the recording's clock | `native` |

Exactly one is required. Passing neither — or both — raises
`vawlume:attribution:ClockRelationUndeclared`.

There is deliberately no default. A correspondence computed on incomparable
clocks is a plausible number and a wrong one, and nothing downstream could tell:
the IoU would look ordinary, the row would store cleanly, and the error would
surface as a caller attributed to the wrong call.

**All clock arithmetic goes through `vawlume.alignment.applyTransformInterval`.**
No local offset, no scale applied by hand, and nothing outside `+alignment/` reads
`alignment_segments`.

**A correspondence may only rest on a fitted transform.** An alignment run whose
status is not `estimated` raises `vawlume:attribution:TransformNotUsable` — resting
on a registered-but-unfitted run would produce a plausible number from no fit.

## Two consequences of transforming, handled rather than discovered

**Aligned duration is not native duration** under a piecewise clock. An IoU
computed on aligned intervals is therefore not the IoU of the native ones. Every
stored row records `iou_basis`, and the evidence row's semantics say so in words,
because the number alone cannot.

**An extrapolated endpoint survives into storage.** A window endpoint outside the
transform's anchored range comes back flagged, and the flag is written to
`start_extrapolated` / `end_extrapolated` rather than consumed and dropped. A
correspondence resting on an extrapolated endpoint is weaker evidence, and a
reader has to be able to see that.

## The eligibility rule

Declared in the attribution mapping profile's `correspondence` block, and read
from the profile version **the import registered** — so a stored correspondence
names a rule that still exists and still says what it meant.

| Field | Shipped value | Meaning |
|---|---|---|
| `eligibility_rule` | `positive_overlap_and_min_temporal_iou_on_declared_basis` | the rule's name, stored on every row |
| `require_positive_overlap` | `true` | touching intervals have zero intersection and do not correspond |
| `min_temporal_iou` | `0.05` | the floor, on whichever basis the row declares |
| `preserve_ambiguity` | `true` | a profile **cannot** set this false |

**The floor is lower than the matching specification's `0.10`, deliberately and
independently.** An attribution window often brackets a call loosely, so a floor
tuned for detector-to-detector agreement would discard true correspondences whose
only fault is a generous window. The two coinciding would be a coincidence rather
than a shared calibration, and neither layer may be tuned by changing the other.
A test asserts they differ, which guards against a later pass harmonizing them.

It is illustrative and uncalibrated, like every other threshold in this prototype.

**Two zero-duration intervals at one instant** have no overlap fraction — the
primitive returns `NaN` rather than 1 — and are treated as ineligible rather than
as a perfect match.

## Ambiguity is preserved

A window plausibly referring to two events produces **two** correspondences, both
stored with their own scores. Nothing here chooses.

This inherits the pairwise matching layer's reasoning: a correspondence layer that
picked a winner would destroy the evidence a reviewer needs, and the reviewer is
the only one who can weigh it. `result.ambiguous_window_count` reports how many
windows are in that state so the ambiguity is visible rather than merely present.

A window that corresponds to nothing is reported in
`windows_without_correspondence`. That is a finding, not a failure: an attribution
system may have emitted a window for a call no extractor found.

## What is stored

One `attribution_window_correspondences` row per eligible (window, target) pair,
carrying the aligned interval when one was computed, the overlap, IoU and signed
onset/offset differences, the basis, the transform run, the extrapolation flags,
and the rule and floor that admitted it.

One `attribution_evidence` row per correspondence, at **target level** — a
correspondence is a statement about the event and the window rather than about any
one candidate caller. Its `evidence_dimension` is `correspondence`, which combines
with nothing, and its semantics carry the basis, the floor, the uncalibrated
caveat, the aligned-duration warning where it applies, and the extrapolation note
where it applies.

## Refusals

| Identifier | Cause |
|---|---|
| `vawlume:attribution:ClockRelationUndeclared` | neither or both of `AlignmentRun` and `SameClock` |
| `vawlume:attribution:TransformNotFound` | the named alignment run does not exist |
| `vawlume:attribution:TransformNotUsable` | the transform is not `estimated` |
| `vawlume:attribution:NoImportedWindows` | the run carries no imported windows |
| `vawlume:attribution:TargetSetEmpty` | the run has no targets |
| `vawlume:attribution:CorrespondenceCrossesRecording` | windows and targets span more than one recording |
| `vawlume:attribution:CorrespondenceRuleUndeclared` | the mapping profile declares no correspondence block |

## What this layer cannot express

Phase 5's backend candidates arrive with localization geometry rather than
windows, and will test whether this generalizes. It does not, in these ways:

- **It compares intervals and nothing else.** A backend producing a position
  estimate, a bearing, or a likelihood surface has no interval to compare, and
  this layer has no place to put one.
- **It has no notion of partial correspondence.** A window overlapping the first
  half of an event scores the same as one overlapping the second half; the signed
  onset and offset differences are stored but the rule does not read them.
- **It cannot express "this window refers to a call VAWLUME missed."** A window
  with no correspondence is counted, but there is no row asserting that the
  absence is itself a finding rather than a failure to match.
- **It compares one window to one event.** A system emitting one window for a bout
  that VAWLUME represents as several events produces several correspondences with
  no way to say they are one claim.
- **Spectral correspondence is not implemented.** No Phase 4 consumer needs it.

## Related documents

- [`32_imported_attribution_intake.md`](32_imported_attribution_intake.md) — how the windows got here
- [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md) — the correspondence table
- [`22_phase1_correspondence_boundaries.md`](22_phase1_correspondence_boundaries.md) — the layer list this adds to
- [`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md) — D4 and D5
