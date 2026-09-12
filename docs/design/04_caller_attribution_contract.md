# Caller Attribution Contract

## Status

Design contract for **Phase 4 — caller-attribution representation and the generic
imported path**. Written by itinerary 4.1 before any Phase 4 code exists, so that
the decisions below are made once rather than negotiated by each later itinerary.

Written against schema `0.8-draft` (`PRAGMA user_version = 8`). Itinerary 4.2
applied Phase 4's single bump, so the live schema is now `0.9-draft`
(`PRAGMA user_version = 9`). D1 was revised at 4.2 on user direction; the revision
is marked where it appears.

This contract governs what caller attribution **means** in VAWLUME and what its
representation must keep distinguishable. It does not describe an estimator.
VAWLUME does not estimate callers in Phase 4 and this document should not be read
as preparation for doing so casually.

**The phase's one-sentence position:** VAWLUME can hold somebody else's claim about
who called, with that claim's provenance intact and its uncertainty unmerged, and
can say honestly when it does not know.

## What this phase is for

Plan §18 requires the canonical attribution model be proven with **imported**
results before any backend or native estimator exists. The reasoning is worth
restating because it constrains everything below: a representation designed around
an estimator that does not exist yet will fit that estimator and nothing else.

So Phase 4 builds the model and then tries to break it by importing a result it did
not produce. What the imported path cannot hold is the phase's most valuable
output.

## Core vocabulary

These distinctions are the contract. Everything in §D follows from them.

### A detection is not an attribution claim

This is the phase's foundational boundary and the one most expensive to get wrong.

A `detections` row asserts: *an extractor, given this recording, reported acoustic
energy it classified as a vocalization over this interval.* Its authority is an
extractor's output file.

An imported attribution window asserts: *a system claims a caller produced a
vocalization around here.* Its authority is somebody's attribution pipeline, which
may never have run a detector at all.

These are different claims, with different provenance, different failure modes, and
different denominators. VAWLUME represents them in **separate tables** (D4).

The concrete cost of conflating them is not abstract. `detections` feeds
`candidate_pairs`, `match_groups`, `consensus_events`, `agreement_groups` and every
agreement denominator in the repository. An attribution window inserted as a
detection would silently enter extractor-agreement statistics, and those numbers
would then describe a population that includes claims no extractor made. The
corruption would be invisible and unrecoverable.

`docs/development/22_phase1_correspondence_boundaries.md` anticipated this in
Phase 1 and stated it as a requirement before any attribution code existed:

> correspondence evidence and attribution evidence must not share a table. A high
> temporal IoU between two extractors says nothing about which animal called, and a
> schema that let one stand in for the other would make the distinction
> unrecoverable.

That requirement is inherited, not re-derived.

### A candidate is not a decision

A candidate caller is *evidence about* an entity with respect to a target. A
decision is a *derived conclusion* about the target, produced by applying a declared
policy to those candidates.

Keeping them separate is what makes a decision re-derivable, makes two policies
comparable over the same evidence, and makes Phase 7's sensitivity analysis
possible at all. A decision layer that edited candidates would destroy all three.

### A score is not a probability

A score is a number some system produced on some scale. A probability is a claim
about a distribution. They are stored in different columns, constrained
differently, and nothing converts between them (D3).

Plan §15.9 is explicit: do not equate a normalized evidence score with a calibrated
probability without justification. A value that happens to lie in `[0, 1]` is not
thereby a probability.

### Ambiguous is not simultaneous

Both leave several candidates standing, and they are opposite claims:

- **simultaneous** — *more than one animal called.* A statement about the world.
- **ambiguous** — *we cannot tell which one called.* A statement about the
  evidence.

Plan §9.2 requires both be representable. A schema that cannot separate them has
failed that requirement regardless of what its status column is named. D7 makes the
difference structural rather than lexical.

### A target names its event set

The same recording can carry native detections, pairwise consensus events, and
arbitrary-N agreement groups over the same acoustic material. These are three event
sets with three different denominators. An attribution result that does not say
which one it targeted cannot be compared with anything (D1).

### An upstream label is not an entity

Plan §15.12, and `docs/development/25_visual_identity_association.md` throughout: a
name in somebody else's file is a string until a declared mapping resolves it.
VAWLUME never infers the resolution from string similarity, and never creates an
entity to accommodate an unrecognized label (D3, D8).

---

## Decisions

### D1. A target names exactly one event, from a named event set

An attribution target carries three nullable foreign keys — `detection_id`,
`consensus_event_id`, `agreement_group_id` — with an exclusive CHECK:

```sql
CHECK ((detection_id IS NOT NULL) + (consensus_event_id IS NOT NULL)
     + (agreement_group_id IS NOT NULL) = 1)
```

This is not a new pattern. `manual_reviews` already targets one native detection, a
match group, or a consensus event with exactly this construction, under a comment
reading *"These are deliberately separate evidentiary layers."* Attribution is
another such layer and should look like one.

**A generic `(target_table, target_id)` pair is rejected.** It defeats foreign keys,
has no precedent in this schema, and makes every consumer parse a discriminator
string.

**No redundant `target_kind` column.** Itinerary 4.1's own recommendation proposed
one; the live repository argues against it and the repository wins. Which column is
non-null *is* the discriminator, and a second copy of that fact is a second thing to
keep consistent and a new way for a row to contradict itself. `manual_reviews` and
`consilience_assessments` both omit it.

**Match groups are not targetable.** A match group is a proposed correspondence
between detections, not an event. Attribution targets events.

**Agreement-group targeting is supported, and the target names which extent it
used.** `agreement_groups` has **no time columns**: its extent is derived from its
members, and there is more than one defensible derivation.

This contract's first draft deferred the whole question, reasoning that choosing
one derivation with no consumer to test it against would freeze a guess into the
schema. That reasoning was sound about *choosing*, and wrong about the alternative
being deferral. **Revised at 4.2 on user direction:** VAWLUME exists to enable
analytical opportunities without imposing decisions, and where several derivations
are each defensible, the program computes all reasonable ones, documents what each
means, and lets the analyst pick the one whose scientific meaning fits the question
being asked.

So `v_agreement_group_extent` computes five extents per group — union,
intersection, mean, longest member, shortest member — and
`attribution_targets.agreement_extent_method` records which one a target used,
required for a group target and refused for any other. The extent method is part of
naming the denominator, exactly as the event set is: two attribution runs over the
same groups under different extents are answering different questions, and a result
that did not say which would be uncomparable.

The view is derived and never stored, following the repository's rule that a
quantity recomputable from its authority does not get a second home.

**This generalizes.** Where VAWLUME faces a choice among several scientifically
defensible derivations of the same underlying rows, the default is to compute and
document the alternatives rather than to pick one or to defer. The limit is
usefulness, not completeness: an option nobody could state a reason for preferring
is noise, and the documentation must say what each option is *for*. The consilience
layer's existing shape is the model — it generates the labels and quantities that
let a user ask how a result moves across criteria, instead of answering at one
criterion and calling it the answer.

### D2. An attribution run is immutable once complete

A run is identified by its method/path, its settings profile version, its policy,
its target event set, and its inputs. **Change any of them and it is a different
run**, with a new identity — never a rewrite of the existing one.

This is Phase 3's rule (*"a completed transform is never rewritten in place"*)
applied to a new object, and for the same reason: a result whose inputs can change
under it cannot be cited.

A run may name an optional **parent attribution run**, per plan §13, for a run
derived from another — most obviously the same candidates re-decided under a
different policy. That relationship is what lets Phase 7 compare two decisions
without duplicating the evidence beneath them.

### D3. Every stored number declares its semantics, and a label is not a number

`score` and `probability` are separate nullable columns. A `probability` is
constrained to `[0, 1]`; a `score` is not constrained, because it is somebody else's
scale and VAWLUME does not know its range.

Whenever either is present, its semantics are required — following the Phase 3
precedent, enforced in the schema rather than in prose. Phase 3 closed with **P3-1**
open precisely because that rule was enforced in one table and left to prose in two
others; the attribution tables are new and have no legacy to accommodate, so they
enforce it uniformly.

The semantics string records what the number is, what produced it, and what it is
not — the pattern `applyTransform` established for propagated uncertainty, which
states in its own returned value that it is *"uncalibrated: not a confidence
interval, a standard error, or a probability"*.

**A caller label with no number stores NULL, never 1.0.** This is the sharpest rule
in the section and it is inherited verbatim in spirit from
`25_visual_identity_association.md`:

> A manual assertion, or an upstream tool that emits only a label, records
> `identity_value` NULL — never `1.0`. Converting a name into certainty is the
> specific failure this table exists to prevent.

An imported file that names a caller and supplies no confidence has told us a name
and nothing about certainty. Recording `1.0` would manufacture the one thing the
exporter declined to claim.

**Nothing converts between score and probability**, in either direction, at any
layer. An imported probability is a probability because the exporting system said
so, and the semantics string attributes that claim to its source rather than
laundering it into VAWLUME's own.

### D4. Imported attribution windows live in their own table

Settled by the vocabulary section above, and by doc 22's inherited requirement.

The rejected alternative deserves recording because it is genuinely attractive:
representing imported windows as `detections` of a pseudo-extraction-run would reuse
`candidate_pairs`, `match_groups` and `matching.compare` wholesale, at almost no
implementation cost. It is rejected because it would make `detections` mean two
different things, and because plan §14 separates detector-to-detector matching from
caller-estimate-to-call matching by name.

The cost of the rejection is that attribution needs its own correspondence path
(4.9), which is what D5 pays for.

An imported window keeps **its own timing basis and its own clock**, untransformed,
exactly as ingested. Expressing it on a VAWLUME clock is 4.9's job and produces a
correspondence, not an edit.

### D5. Interval comparison is extracted; `+matching/` is refactored onto it

Plan §14 lists interval comparison, temporal IoU, onset/offset distance and duration
comparison under "generalize". They currently live inline in
`matchingGenerateCandidates.m`'s private `candidateRecord`, interleaved with
detection IDs and matching-specific `details_json`.

**Extract them** into `vawlume.interval.relation(startA, endA, startB, endB)`,
returning intersection, union, temporal IoU, onset difference, offset difference and
duration difference, and nothing else. The name avoids collision with
`matching.compare`, which does something far larger; `vawlume.interval.compare` was
considered and rejected for exactly that reason.

**Refactor `+matching/` onto it**, with **bit-identical behaviour** as the bar and a
before/after comparison as the proof — not a passing suite.

The reason to refactor rather than duplicate is Phase 3's closing finding. **P3-2**
records that the `[start, end)` boundary rule ended up implemented twice, that the
two implementations were measured bit-identical, and that the agreement was
therefore maintained by duplication rather than by construction — invisible until
someone edited one copy. Creating a second such pair deliberately, one phase after
recording the first as a problem, would be indefensible.

**The eligibility rule is not extracted.** `positive_overlap_and_min_temporal_iou`
is matching's domain rule. Attribution will have its own (4.9). A shared function
with a mode flag selecting between them is the UniversalMatcher plan §14 forbids —
the primitive computes, the domain decides.

### D6. A decision selects a set of candidates, and retains the policy that chose them

Decision statuses: `assigned`, `unassigned`, `ambiguous`, `simultaneous`,
`excluded`.

A decision does not carry a single winning candidate reference. It selects a **set**,
through a decision-to-candidate link. This is what makes D7 structural:

| Status | Selected candidates | Claim |
|---|---|---|
| `assigned` | exactly 1 | this entity called |
| `simultaneous` | 2 or more | these entities called |
| `ambiguous` | 0, with candidates present | we cannot tell which |
| `unassigned` | 0 | no candidate was supportable |
| `excluded` | 0 | QC removed this target, with a reason |

A single `winning_candidate_id` column would have made `simultaneous` unrepresentable
and quietly reintroduced the one-caller-per-event assumption plan §15.8 forbids.

**The policy is retained two ways, on purpose.** The decision references the policy's
**config profile version**, which is immutable and checksum-bearing, so the full
policy is always recoverable. It *also* stores the **threshold value actually
applied**. A policy may declare several thresholds and the profile alone does not say
which one bound this decision; without the applied value, "why did this come out
ambiguous" is not answerable from the stored row.

`config_profiles.profile_kind` is a closed vocabulary and needs a new member for
attribution policy. `consilience_policy` is the precedent for a policy-shaped kind.

**No calibrated threshold ships.** Whatever default policy ships declares itself
illustrative in its own output, as the matching specification does with
`calibration_status.state = "illustrative_prototype"`. No status in any Phase 4
vocabulary is equivalent to `validated`.

**A completed decision is never rewritten in place.** A different policy over the
same candidates is a new decision, and both remain readable — that is precisely
what Phase 7 needs.

### D7. Simultaneous and ambiguous differ by how many candidates the decision selects

Covered by D6's table. The distinction lives in the decision, not in the candidate,
because *"two animals called"* is a statement about the target and not about either
animal individually.

Candidate status stays minimal and local: `candidate`, `selected`, `rejected`. A
candidate does not know whether it is one of two simultaneous callers or one of two
indistinguishable ones; the decision knows.

This makes the distinction machine-checkable rather than a naming convention, which
was the requirement.

### D8. Attribution evidence always records which kind of identity statement it rests on

**This closes A-1**, carried since Phase 2 close.

`external_events.entity_id` is populated by alignment intake matching a source
table's subject column against `experimental_entities.native_id`. Doc 11 states what
it is: *"a user-declared attribution: whoever scored the behaviour said this event
was about this animal. It carries no evidence kind, no value semantics, no
calibration status, and no review state."*

A `tracking_identity_associations` row is the opposite: evidence kind required,
value semantics required whenever a value is present, calibration status, review
state, method, and full provenance.

Both may legitimately support an attribution claim. The rule is **not** "prefer the
stronger one" — it is *never use either one silently*. Every attribution evidence row
derived from an identity statement names which kind it rests on and which row, and
the read surface (4.10) shows it.

A weak link used knowingly and recorded as weak is honest evidence. A weak link
presented as identity evidence is not.

Doc 22's related warning applies unchanged: hierarchy linkage is **context, not
attribution**. A `recording_entity_links` row says an animal was present, never that
it called.

### D9. Identity precedence is an explicit helper, and it refuses ties

**This closes P2-13**, deferred three times — each time correctly, because a storage
layer inventing precedence would have hidden evidence.

`identityCandidates` **does not change.** It continues returning every overlapping
claim. A caller that needs one answer asks for one:

The resolution helper takes the overlapping claims for a track at an instant or over
an interval and applies, in order:

1. **`assignment_state = 'rejected'` is never chosen**, at any step.
2. **State precedence:** `assigned` outranks `candidate`, which outranks `ambiguous`,
   which outranks `unresolved`.
3. **Interval specificity:** among claims still tied, the one with the **narrowest
   interval** covering the query wins.
4. **Still tied → no choice.** The helper returns no selection and reports the tied
   claims.

Step 3 answers P2-13's motivating example directly — the 2.4a handoff described *"a
session-long weak candidate beside a precise manual correction"*, and a narrower
interval is the structural signal that someone looked harder at that moment.

**The rule keys only on closed vocabularies and interval geometry, deliberately.**
`evidence_kind`, `identity_value_semantics`, `review_state` and `method` are all free
text by design — doc 25 explains that a closed vocabulary would force an unfamiliar
upstream system into the wrong category. A precedence rule that keyed on free text
would work for the strings we happen to have seen and fail silently on the first
unfamiliar one. The table also carries no creation timestamp, so recency is not
available and is not used.

The helper returns the chosen claim, the claims it set aside, and **which step
decided** — never a bare entity ID. A precedence rule whose reasoning is not returned
is a silent rule with extra steps.

### D10. `vawlume.geometry.registerRecordingChannel` creates channel rows

**This closes P2-15**, the only important-severity carried issue.

Placement, bounded audio reads and response measurement all require
`recording_channels` rows; project intake creates none; and usage guide §7.5 has
carried a raw-SQL workaround since Phase 2.8.

`+geometry/` is the owner, because that is where the workaround already lives —
§7.5 is *"Declare geometry, register tracking, and record identity evidence"* — and
because `registerChannelPlacement` and `registerCoordinateSystem` are its immediate
siblings. Acoustic *consumes* channels; geometry *declares* them.

The workaround is **deleted** rather than annotated. A documented workaround that
outlives its need becomes a second recommended path.

### D11. E-1 and P3-1 ride with the version bump

Both are Phase 3 debts blocked on exactly one thing: the schema being open. It opens
once in Phase 4, at 4.2.

- **E-1** — `trg_anchor_observation_event_timebase` fires only on INSERT and should
  also fire on UPDATE.
- **P3-1** — `alignment_anchor_observations.uncertainty_s` and
  `aligned_external_events.uncertainty_s` declare their semantics only in prose,
  while `alignment_segments` enforces its own by CHECK.

Carrying them costs a few lines inside a bump that is happening anyway. Deferring
them a fourth time costs a future version bump of their own.

This is the one decision in this document that a later itinerary may reverse cheaply:
if 4.2 finds either change entangles with attribution DDL in a way that risks the
phase, it may re-defer, provided it names the specific opening it is waiting for.

---

## The uncertainty position

The Phase 3 closure handoff grants Phase 4 a permission:

> Phase 4 is the first phase permitted to combine any of them, and only where its
> method explicitly says how.

**Phase 4 declines it.** VAWLUME computes no combination of temporal-alignment,
pose/localization, visual-identity and acoustic evidence in this phase.

The reason is specific to the imported path. An imported score is somebody else's
combination, already performed, by a method VAWLUME did not run and cannot inspect.
Recomputing or re-weighting it would destroy the only property that makes an imported
result auditable — that it is still the number the exporting system produced. Storing
it beside VAWLUME's own four dimensions, unmerged, lets a reader see exactly which
evidence the exporter used and which VAWLUME merely has.

So a Phase 4 attribution result carries **both**: the imported score with its
provenance, and the four dimensions separately. Neither is derived from the other.

### What a later phase must state to exercise the permission

Recorded here so Phase 6 inherits a usable standard rather than a prohibition nobody
lifted. A method that combines dimensions must state:

1. **Which dimensions it uses**, and which it ignores — an unused dimension is a
   modelling choice, not an oversight to be discovered later.
2. **What the resulting number means**, on what scale, and explicitly what it is not.
   By default it is not a probability.
3. **How each input was scaled**, and on what basis those scales were considered
   comparable across devices and sessions. This is the step Phase 3 refused for
   anchor uncertainty — *"nothing establishes that those values are comparable across
   devices or correctly scaled"* — and the refusal stands until something does
   establish it.
4. **That the inputs remain separately readable afterwards.** A combination never
   replaces its inputs.
5. **Its calibration status**, which is `uncalibrated` unless something outside
   VAWLUME calibrated it.

A method that cannot state all five keeps the dimensions separate and says so. That
is a legitimate outcome, and Phase 4 is an instance of it.

---

## Phase 4 non-goals

- estimating a caller from VAWLUME's own acoustic, pose, or identity evidence
  (Phase 6);
- localization backends, USVCAM integration, or a backend-specific schema (Phase 5,
  and §15.3);
- computing any combination of the four uncertainty dimensions;
- presenting a normalized evidence score as a calibrated probability;
- a calibrated acceptance threshold, or any status meaning `validated`;
- forcing one caller per event, or a single `caller_id` column;
- a UniversalMatcher, or merging detector-to-detector matching with
  caller-estimate-to-call matching;
- spectral correspondence, which no Phase 4 consumer needs;
- cross-path comparison or sensitivity analysis over attribution results (Phase 7);
- raw-video ingestion, pose estimation, or image-based re-identification;
- dense tracking-sample or dense identity materialization;
- overwriting native timestamps or native scores with canonical values;
- a parser suite for any named commercial attribution system (§15.11).

## Inherited schema audit

What Phase 4 builds on, and what it must not disturb.

### Already correct — preserve

- **`manual_reviews` and `consilience_assessments`** — the exclusive-target CHECK
  pattern D1 adopts.
- **`tracking_identity_associations`** — evidence kind always required, semantics
  required whenever a value is present, unresolved distinguishable from absent, and
  free-text vocabularies where a closed one would exclude. D3, D8 and D9 all build on
  it.
- **`config_profiles` / `config_profile_versions`** — immutable, checksum-bearing
  profile versions. D6's policy retention depends on that immutability.
- **`detections`, `candidate_pairs`, `match_groups`, `consensus_events`,
  `agreement_groups`** — the correspondence layers D4 keeps attribution out of.
- **`vawlume.alignment.applyTransform` / `applyTransformInterval`** — the only clock
  path. Attribution calls them and adds no clock arithmetic.

### Gaps Phase 4 must fill

| Gap | Owner |
|---|---|
| No attribution run, target, candidate, evidence or decision representation | 4.2 |
| No imported-attribution window representation | 4.2 |
| `profile_kind` has no attribution-mapping or attribution-policy member | 4.2 |
| Interval comparison is not extractable | 4.3 |
| No public function creates `recording_channels` (P2-15) | 4.7 |
| No identity precedence helper (P2-13) | 4.7 |
| Identity-statement kind not recorded where consumed (A-1) | 4.7 |

### Constraints inherited from elsewhere

- **`agreement_groups` carries no time extent** — D1's reason for deferring
  agreement-group targeting.
- **Free-text identity vocabularies** — D9's reason for keying precedence on closed
  vocabularies and interval geometry only.
- **The Database Toolbox raises on any SQL NULL in a result set**, including numeric
  columns and aggregates over empty sets. Every nullable attribution column needs the
  established `IFNULL(...)` sentinel treatment on read. This bit Phase 3 three times.

## Definition of done for Phase 4

The phase is complete when:

- several candidate callers coexist for one target through the public API, and the
  read surface shows all of them;
- no stored score or probability lacks declared semantics, enforced by the schema;
- an imported attribution result lands with its values **bit-identical** to its
  source, its provenance recoverable, and its caller labels resolved only by declared
  mapping;
- an imported window corresponds to a VAWLUME event across differing clocks and
  differing IDs, with extrapolation state preserved and ambiguity unresolved;
- `assigned`, `unassigned`, `ambiguous`, `simultaneous` and `excluded` are each
  reachable, and simultaneous is structurally distinguishable from ambiguous;
- changing a policy threshold changes the decision and leaves every candidate row
  untouched;
- the four uncertainty dimensions are separately readable on a result, and nothing in
  `src/` combines them;
- A-1, P2-13 and P2-15 are closed with evidence;
- `+matching/` behaves bit-identically to its Phase 3 state, or is unchanged;
- the whole path runs as one public demonstration on synthetic data, including at
  least one named refusal;
- the full gate passes on a committed candidate with a clean tree.

## Related documents

- [`../development/22_phase1_correspondence_boundaries.md`](../development/22_phase1_correspondence_boundaries.md) — the orientation document; where attribution attaches and what it must not share
- [`../development/25_visual_identity_association.md`](../development/25_visual_identity_association.md) — identity evidence, A-1, and the label-is-not-certainty rule
- [`../development/11_temporal_alignment_schema.md`](../development/11_temporal_alignment_schema.md) — `external_events.entity_id` as a declared link
- [`../development/13_transform_fitting_and_alignment_qc.md`](../development/13_transform_fitting_and_alignment_qc.md) — declared-semantics precedent and the uncalibrated-bound wording
- [`02_temporal_alignment_contract.md`](02_temporal_alignment_contract.md) — the contract this one is modelled on
- [`../development/30_repository_self_description.md`](../development/30_repository_self_description.md) — claim semantics, before the version bump
