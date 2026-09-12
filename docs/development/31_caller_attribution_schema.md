# Caller attribution schema

Introduced at schema version `0.9-draft` (`PRAGMA user_version = 9`). The `0.8`
alignment slice is unchanged except for two corrections carried with this bump,
described under "Phase 3 debts closed here".

The design reasoning lives in
[`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md).
This document is the data dictionary: what each table holds, what the schema
enforces, and — the section worth reading twice — what it does not.

## The boundary this slice is built on

A `detections` row asserts that **an extractor reported acoustic energy** it
classified as a vocalization over an interval. An `imported_attribution_windows`
row asserts that **an attribution system claims a caller produced a vocalization**
around a time. Different claims, different authorities, different failure modes.

They are separate tables, and that is not a stylistic choice.
[`22_phase1_correspondence_boundaries.md`](22_phase1_correspondence_boundaries.md)
required it in Phase 1: *"correspondence evidence and attribution evidence must
not share a table."* The operational reason is that `detections` feeds
`candidate_pairs`, `match_groups`, `consensus_events`, `agreement_groups` and
every agreement denominator in the schema. An attribution window inserted there
would silently enter extractor-agreement statistics, describing a population that
includes claims no extractor made — invisibly, and unrecoverably.

## Tables

### `attribution_runs`

One reproducible attribution analysis: its path, method, settings profile,
recording, analysis-run parent, and optional parent attribution run.

Immutable once complete. Change the method, the settings, the policy or the target
set and it is a different run — the alignment layer's rule for a completed
transform, applied here for the same reason.

`attribution_path` is `imported`, `backend` or `native_estimate`. Only `imported`
is written by any code today; the other two are present because Phases 5 and 6 land
in this same table and a vocabulary admitting one value would force a version bump
to add a string.

`vawlume.attribution.createRun` creates the `analysis_runs` parent, its
`attribution_settings` profile link, the event-set input lineage, this row, and
all targets in one transaction. Detection target sets cite their extraction run
through `analysis_run_extraction_inputs`; consensus and agreement target sets cite
their source analysis through `analysis_run_sources`. The attribution row remains
`planned` and the analysis parent remains `started` until the later candidate and
decision layers finish the run.

Schema `0.9-draft` has no run-to-source-file, run-to-artifact,
run-to-external-stream, or run-to-participating-entity junction table. The public
writer therefore retains those exact identifiers in `notes` as a canonical
`vawlume.attribution.run_provenance.v1` JSON envelope, alongside the target-set
kind/source and any user note. It snapshots:

- direct source file, artifact, external-stream, and source-analysis-run IDs;
- participating entity IDs and the `recording_entity_links` rows that admitted
  them;
- target kind, source extraction/analysis run, selected target IDs, and any
  agreement extent method.

This is structured provenance, not narrative text, when the row comes from the
public API. Its limitation is equally explicit: JSON identifiers have no foreign
keys. The writer validates their scope and an identical rerun compares the whole
envelope, but direct SQL can delete a cited row without a relational RESTRICT edge.
Adding four speculative junction tables after Phase 4's schema bump would be a
larger and less reviewable correction; the closure gate should decide whether the
first imported workflow justifies normalizing any of them.

### `attribution_targets`

The vocal event attribution applies to. Exactly one of `detection_id`,
`consensus_event_id`, `agreement_group_id`, enforced by CHECK.

There is **no `target_kind` column**. Which column is non-null is the
discriminator; a second copy of that fact would be a second thing that can
contradict the row. `manual_reviews` and `consilience_assessments` express the same
pattern the same way.

Match groups are not targetable — a match group is a proposed correspondence
between detections, not an event.

`agreement_extent_method` is **required for an agreement-group target and refused
for any other**. See the extent view below for why.

### `attribution_candidates`

One candidate caller per entity per target. `UNIQUE(attribution_target_id,
entity_id)` — per target *and entity*, deliberately not per target. Several
candidates for one target is the ordinary case, and a constraint admitting one
would reintroduce the single `caller_id` this model exists to avoid.

`score` is unconstrained; `probability` is constrained to `[0, 1]`. Each requires
its semantics whenever present. Nothing converts between them.

`candidate_status` is `candidate`, `selected` or `rejected`. `candidate_rank` is a
presentation of score, not a second opinion about it.

`vawlume.attribution.addCandidates` is the public plan-then-apply writer. It
accepts a batch for one explicit target, checks every entity against the run's
snapshotted participant set, and atomically inserts all new rows. The Phase 4.5
writer only creates status `candidate`; selection and rejection belong to the
decision layer. An identical `(target, entity)` row is reused, while different
content conflicts rather than overwriting the earlier imported claim.

Ranks are supplied, never generated. The writer treats rank 1 as strongest and
checks only for contradiction with a higher-is-stronger score: a higher score
must have a lower rank, and equal scores must share a rank. It neither fills rank
gaps nor breaks a tie. For a score whose native ordering has another meaning,
retain the raw score and omit rank.

### `attribution_evidence`

Long-form evidence supporting a candidate, or the target as a whole.

`evidence_dimension` is a **closed** vocabulary — `temporal_alignment`,
`pose_localization`, `visual_identity`, `acoustic`, `correspondence`,
`imported_composite`. `evidence_kind` is **free text**. The asymmetry is
deliberate: the phase's separation claim is only checkable if the dimensions are
enumerable, while a closed *kind* would force an unfamiliar upstream system into
the wrong category — the reasoning
[`25_visual_identity_association.md`](25_visual_identity_association.md) gives for
its own open vocabularies.

`imported_composite` is how somebody else's already-combined score is stored
without VAWLUME computing one.

`identity_statement_kind` closes **A-1**. An evidence row derived from an identity
statement names whether it rests on a `declared_entity_link` (the user-declared
`external_events.entity_id` lookup, carrying no evidence kind, semantics,
calibration or review state) or an `identity_association` (a
`tracking_identity_associations` row, which carries all of those), and points at
the row it read.

`vawlume.attribution.addEvidence` appends one atomic batch at target or candidate
scope. Its public contract is intentionally stricter than the nullable storage
shape: every row has exactly one of `value_real` or `value_text`, nonempty units
and semantics, and at least one source identifier or `source_locator`. Relational
source IDs are checked against the run's recording/project. Candidate-level
identity statements must identify that same candidate in that same recording.

Evidence has no natural key or uniqueness constraint. An apply therefore means
"append these observations" and is not idempotent; rerunning one accidentally
duplicates the evidence. This differs from candidate rows, whose target/entity
key supports exact reuse.

The schema has direct evidence FKs for an alignment run, source file, mapping
profile, external event and tracking identity association. It has no evidence FK
for a general analysis run, artifact, or external stream. Those sources use a
stable `source_locator` today. The first real attribution exporter in 4.8 must
report whether that loses a source identity it needs; the closure gate should not
infer a junction design before then.

### `attribution_decisions` and `attribution_decision_candidates`

The derived decision, and the candidates it selected.

A decision selects a **set**. That is what makes `simultaneous` representable at
all; a single winning-candidate column would have made "two animals called"
unsayable.

| Status | Selected candidates | Claim |
|---|---|---|
| `assigned` | exactly 1 | this entity called |
| `simultaneous` | 2 or more | these entities called |
| `ambiguous` | 0, with candidates present | we cannot tell which |
| `unassigned` | 0 | no candidate was supportable |
| `excluded` | 0 | QC removed this target, with a reason |

`policy_profile_version_id` is `NOT NULL`. `applied_threshold` is stored *as well*,
because a policy may declare several thresholds and the profile alone does not say
which one bound this decision.

`UNIQUE(attribution_target_id, policy_profile_version_id)` is what makes "a
completed decision is never rewritten in place" true. A different policy is a
different row and both stay readable.

### `imported_attribution_windows`

The imported system's own vocal windows. Times are **native and never
overwritten**; expressing them on a VAWLUME clock produces a correspondence row,
not an edit. `source_caller_label` is stored verbatim and resolved only by declared
mapping.

### `attribution_window_correspondences`

Links an imported window to a target across differing clocks and IDs.

`iou_basis` is `native` or `aligned`, and an `aligned` basis must name its
`alignment_run_id`. The column exists because **aligned duration is not native
duration** under a piecewise clock: an IoU computed on aligned intervals is not the
IoU of the native ones when a breakpoint falls between them.

Ambiguity is preserved — one window may correspond to several targets, and nothing
here chooses.

## `v_agreement_group_extent`

An agreement group is a set of member detections. It has **no interval of its
own**, and there is more than one defensible way to derive one.

Rather than impose a choice, the view computes every reasonable extent and records
which was used on whatever consumes it. Which extent is scientifically right
depends on the question, and that judgement belongs to the analyst.

One row per `(agreement_group_id, extent_method)`:

| `extent_method` | Interval | When it is the right question |
|---|---|---|
| `union_boundary_of_members` | `[min(start), max(end)]` | *Anything any extractor called a vocalization.* The most inclusive reading; matches the `union_boundary_of_members` consensus rule already used for ambiguous pairwise topologies |
| `intersection_boundary_of_members` | `[max(start), min(end)]` | *Only what every extractor agreed was vocalization.* The most conservative reading. **May be empty** |
| `mean_boundary_of_members` | `[mean(start), mean(end)]` | A central-tendency estimate; matches the `mean_boundary_of_members` consensus rule used for one-to-one topologies |
| `longest_member_boundary` | the single longest member's interval | *What the most inclusive single detector called.* Keeps a real detector's boundaries rather than a synthetic average |
| `shortest_member_boundary` | the single shortest member's interval | *What the most conservative single detector called.* Same, at the other end |

The two `*_member_boundary` methods report `representative_detection_id`, so the
detection whose boundaries were used is recoverable. Ties are broken by lowest
`detection_id`, which makes them deterministic rather than arbitrary.

Every row also carries `member_count`, `extractor_count`, `onset_spread_s` and
`offset_spread_s` — the disagreement itself, which is often the quantity of
interest. `extractor_count` is what answers consilience-criterion questions like
*"groups where all three extractors agree"* without a separate join.

**Median was considered and is not offered.** SQLite has no median aggregate, and
implementing one in a view would cost readability for a statistic that coincides
with the mean at the two-member case and is bracketed by the longest/shortest pair
at larger ones.

**A designated-extractor representative is not offered either**, because it needs a
designation the view cannot carry. Join it yourself:

```sql
SELECT m.agreement_group_id, d.start_time_s, d.end_time_s
FROM agreement_group_members m
JOIN detections d ON d.detection_id = m.detection_id
JOIN extraction_runs er ON er.extraction_run_id = d.extraction_run_id
JOIN extractor_versions ev ON ev.extractor_version_id = er.extractor_version_id
JOIN extractors e ON e.extractor_id = ev.extractor_id
WHERE e.extractor_key = 'deepsqueak';
```

### The empty intersection

Members that do not all overlap have no common interval. That row reports
`extent_is_empty = 1`, `start_time_s` and `end_time_s` **NULL**, and `gap_s` — a
positive number saying how far the members are from agreeing.

A reversed interval was rejected: storing `end < start` would be consumable by a
naive reader as a real interval. NULL forces the question.

**Reading it from MATLAB needs a real-valued sentinel.** See the platform note
below; this is the exact shape that bites.

## What the schema enforces

- exactly one event set per target, and an agreement-group target declares its
  extent;
- a score, probability, evidence value or applied threshold present implies its
  semantics present;
- a probability lies in `[0, 1]`; a score is unconstrained;
- a candidate entity is linked to the run's recording;
- a target's event, an imported window, and a correspondence all belong to the
  run's own recording and run;
- a decision names its policy, and `assigned` / `simultaneous` / the rest select
  exactly one / two or more / no candidates;
- an excluded decision gives a reason, and a failed run gives a failure code;
- a second decision for one target under one policy is refused;
- an `aligned` correspondence names the transform it used;
- an identity-derived evidence row names the kind of statement it rests on and
  points at that row;
- no status anywhere means `validated`.

## What the schema does **not** enforce

This is the half that stops a later reader assuming a guarantee that was never
there.

- **Nothing checks that a score means what its semantics string says.** The string
  is free text and unvalidated. Two runs can use the same words for different
  quantities.
- **Nothing prevents a caller from storing a combined value.** The
  `imported_composite` dimension exists for somebody else's combination; the schema
  cannot tell whether VAWLUME computed one. That invariant is held by code review
  and by the closure gate's scan, not by a constraint.
- **`candidate_rank` is not checked against `score`.** A rank that contradicts the
  scores will be stored.
- **Nothing verifies that an imported value equals its source file.** Bit-identity
  is an intake obligation, not a constraint.
- **Cross-table scope is enforced on INSERT only**, following the repository-wide
  convention documented in the trigger section of `schema/schema.sql`. A direct
  `UPDATE` outside the public API can still move a row across a boundary.
  `PRAGMA foreign_key_check` will not see it.
- **The decision cardinality rule is enforced on the link table's INSERT and on the
  decision's status UPDATE**, but deleting a selection does not re-check the
  status. An `assigned` decision whose only selection is deleted becomes an
  `assigned` decision selecting nobody.
- **`agreement_extent_method` is not checked against the view.** A target may name
  an extent method for a group whose members were since deleted.
- **Nothing constrains `evidence_kind`, `method`, or any semantics string** to a
  vocabulary. That openness is deliberate and its cost is that spelling is a
  convention, not a guarantee.

## Phase 3 debts closed here

**E-1.** `trg_anchor_observation_event_timebase` fired on INSERT only. Repointing
`external_event_id` or `timebase_id` on an existing observation changes which event
the reading claims to be *of* — meaning, not filing — so it now has the UPDATE twin
that the trigger convention reserves for exactly that case.

**P3-1.** `alignment_anchor_observations.uncertainty_s` and
`aligned_external_events.uncertainty_s` stored a number whose meaning lived only in
prose, while `alignment_segments` enforced its own by CHECK. Both now carry
`uncertainty_semantics` and the same CHECK. The rule — *a stored number declares its
semantics* — is now applied uniformly rather than in one place out of three.

Closing it had a consequence worth naming, because it is what the CHECK was for:
**three existing writers were storing a bare number.** The Phase 1 fixture wrote
`0.002` into both tables with no statement of what it was, and alignment intake
copied a manifest's `uncertainty_s` field through the same way. All three now
declare `declared_anchor_reading_uncertainty_s` — the anchor reading uncertainty as
declared by whoever wrote the manifest or built the fixture — which is distinct from
the `max_contributing_anchor_uncertainty_s` that `alignment_segments` carries after
a fit. Those are different quantities and were previously indistinguishable.

The fixture and the intake path were fixed; the constraint was not relaxed. A test
that fails because a fixture stored an unlabelled number is the constraint working.

## Platform notes

**A BEFORE trigger fires ahead of the row's CHECK constraints.** An unguarded scope
trigger will therefore abort a malformed row before the constraint that actually
describes the problem gets a chance to, and the user sees a misleading message.
`trg_attribution_target_recording` is guarded against this: it only tests scope
once a target is actually named. If you add a scope trigger, check what it masks.

**An integer `IFNULL` sentinel truncates real values on fetch.** The MATLAB
Database Toolbox types a fetched column from its first row. Reading a nullable REAL
column as `IFNULL(x, -1)` returns integers for *every* row when the first row is
NULL — so `0.4` comes back as `0`, silently. Use a real-valued sentinel:

```sql
IFNULL(gap_s, -999.0)     -- correct
IFNULL(gap_s, -999)       -- truncates every real value in the column
```

This is the same family as the known "Unexpected NULL" trap, and it is the more
dangerous half: the NULL trap raises, this one returns a wrong number.

## Related documents

- [`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md) — the decisions and their reasons
- [`22_phase1_correspondence_boundaries.md`](22_phase1_correspondence_boundaries.md) — the orientation document and the layer separation this slice inherits
- [`25_visual_identity_association.md`](25_visual_identity_association.md) — identity evidence, A-1, and the open-vocabulary reasoning
- [`11_temporal_alignment_schema.md`](11_temporal_alignment_schema.md) — the alignment data dictionary this one is modelled on
- [`16_multi_extractor_agreement_schema.md`](16_multi_extractor_agreement_schema.md) — agreement groups, whose extent the view derives
