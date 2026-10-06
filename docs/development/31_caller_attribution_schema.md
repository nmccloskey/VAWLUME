# Caller attribution schema

Introduced at schema version `0.9-draft` (`PRAGMA user_version = 9`). The `0.8`
alignment slice is unchanged except for two corrections carried with this bump,
described under "Phase 3 debts closed here".

Added at schema version `0.10-draft`: `imported_attribution_claims` and
`v_attribution_window_correspondences`, and the removal of
`imported_attribution_windows.source_caller_label`.

Added at schema version `0.12-draft`: the backend/localization slice.
`attribution_localization_estimates`, `attribution_native_attributes`
and `attribution_run_declared_inputs` are new. `attribution_evidence` gains
the `source_localization` dimension, `recording_channel_id` and
`attribution_localization_estimate_id`, and `config_profiles.profile_kind` gains
`attribution_backend_mapping`. See
[The backend/localization slice](#the-backendlocalization-slice).

Added at schema version `0.13-draft`, for the native estimator:
`attribution_evidence.derived_measurement_id`, with
`trg_attribution_evidence_measurement_scope` and its `_update` twin, and the
`config_profiles.profile_kind` member `attribution_estimator_settings`. See
[`attribution_evidence`](#attribution_evidence).

The design reasoning lives in
[`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md),
extended for the backend path by
[`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md).
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

Schema `0.10-draft` has no run-to-source-file, run-to-artifact,
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

`evidence_dimension` is a **closed** vocabulary: `temporal_alignment`,
`pose_localization`, `visual_identity`, `acoustic`, `correspondence`,
`imported_composite`, and `source_localization`, the last added at
`0.12-draft`. `evidence_kind` is **free text**. The asymmetry is
deliberate: the phase's separation claim is only checkable if the dimensions are
enumerable, while a closed *kind* would force an unfamiliar upstream system into
the wrong category — the reasoning
[`25_visual_identity_association.md`](25_visual_identity_association.md) gives for
its own open vocabularies.

`imported_composite` is how somebody else's already-combined score is stored
without VAWLUME computing one.

`source_localization` means **where a sound originated**, as an external
spatial-acoustic system estimated it. It is not `pose_localization`, which means
where a tracked bodypart is. How close a sound source lies to a snout is the
hypothesis an attribution analysis tests, and storing one quantity as the other
would make that hypothesis look like its own evidence. It is not `acoustic`
either, which is a measurement rather than a position.

**There are therefore five separated evidence dimensions** (temporal alignment,
pose localization, visual identity, acoustic, and source localization), while
the upstream *uncertainty sources* of plan §4.6 stay four. `correspondence` and
`imported_composite` are not dimensions. Nothing combines any of the five.

A `source_localization` row **cites** its estimate through
`attribution_localization_estimate_id` and copies nothing: `value_real` and
`value_text` stay NULL, because the estimate is the authority. A two-way CHECK
requires the citation on a `source_localization` row and forbids it on every
other dimension. `trg_attribution_evidence_localization_scope` and its `_update`
twin require the estimate to come from the same attribution run as the row's
target.

`recording_channel_id` names the channel per-channel evidence came from, as
`derived_measurements.recording_channel_id` does. It is `ON DELETE CASCADE`,
because the channel is part of what the row *is*.
`trg_attribution_evidence_channel_scope` and its `_update` twin require the
channel to belong to the run's recording.

`identity_statement_kind` closes **A-1**. **Required whenever
`evidence_dimension` is `visual_identity`** (4.7): that dimension rests on an
identity statement by definition, and a row that did not say which kind left a
user-declared label lookup indistinguishable from real identity evidence.
`vawlume:attribution:EvidenceIdentityRequired` refuses it. The rule is never
"prefer the stronger one" -- it is never use either silently. An evidence row derived from an identity
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
profile, external event, tracking identity association, recording channel,
localization estimate, and, from `0.13-draft`, derived measurement. It has no
evidence FK for a general analysis run, artifact, or external stream. Those
sources use a stable `source_locator`.

**P4-3 is closed at `0.13-draft`, in the form its first real consumer needed**
(native estimator contract D13). It was declined for `0.12-draft` (backend/
localization contract D8), which predicted that the native estimator might need
a different citation from the analysis-run column first sketched. It did.
`derived_measurement_id` cites the derived measurement an evidence row reports,
such as a call's per-channel level. That is what lets a computed score be
reconstructed from storage instead of re-found by a query whose population can
change.

It is `ON DELETE RESTRICT`, unlike every other evidence citation, because a
native score is *computed* from the measurements its evidence cites: deleting
one would leave a stored score that can no longer be reconstructed. Delete the
attribution run first. `channel_response_estimate_sources` follows the same rule.
`trg_attribution_evidence_measurement_scope` and its `_update` twin require the
measurement's recording, resolved through its target as
`trg_derived_measurement_channel_scope` resolves it, to be the run's recording.
A measurement whose recording cannot be established is refused. Both triggers
test scope only once the measurement and the target exist, so a dangling
identifier still reaches the foreign-key error. Whether the measurement is about
the *same event* and *same channel* as the row is a write-path rule, not a
schema one.

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


#### The public decision path (Phase 4.6)

`vawlume.attribution.decide` is the only writer. The caller never names a
selection: the policy chooses it, which makes a decision whose status contradicts
its selection set unreachable through the public API rather than merely refused.
The schema triggers remain the backstop for direct SQL.

The shipped rule, in order. Every branch records the threshold that actually
bound it, because a policy declares several and the profile alone does not say
which one decided a given row.

| Order | Condition | Status | Threshold recorded |
|---|---|---|---|
| 1 | caller declared a QC exclusion with a reason | `excluded` | none; the reason is the record |
| 2 | no candidate carries the column the policy reads | `excluded` | none |
| 3 | the strongest value is below `selection_threshold` | `unassigned` | `selection_threshold` |
| 4 | exactly one candidate lies within `separation_margin` of the top | `assigned` | `separation_margin` |
| 5 | several contenders, each at or above `co_occurrence_threshold` | `simultaneous` | `co_occurrence_threshold` |
| 6 | several contenders, not each that strong | `ambiguous` | `co_occurrence_threshold` |

Two distinctions in that table carry the layer's whole claim.

**Rows 2 and 3 are not the same outcome.** Row 3 means the rule ran and nothing
passed. Row 2 means the rule could not run at all. Collapsing them would report
an absence of evidence as evidence of absence.

**Rows 5 and 6 are opposite claims about different things.** Both leave several
contenders. `simultaneous` says more than one animal called — a claim about the
world. `ambiguous` says the evidence cannot separate them — a claim about the
evidence. The policy separates them by asking whether each contender is
*independently* strong, not merely close to the others.

**Row 4 is why a threshold cannot manufacture confidence.** Clearing
`selection_threshold` is never sufficient on its own; a candidate is assigned only
when nothing else is indistinguishable from it.

Candidate `rank` is not read. Rank is caller-supplied presentation of a score,
not independent evidence, and a policy that read it would be deciding on a
presentation choice.

#### Completion freezes evidence, not decisions

When every target of a run has a decision, `decide` sets the attribution run to
`complete` and its analysis parent to `completed` in the same transaction.

After that, `addCandidates` and `addEvidence` refuse with `RunNotWritable` — but
`decide` does not. The asymmetry is deliberate: freezing the evidence is what
makes a later policy comparable against the same candidates, and freezing the
decision set would foreclose the comparison that separating the layers exists to
permit.

### `imported_attribution_windows`

The imported system's own vocal windows, and **a statement about time only**. Times
are **native and never overwritten**; expressing them on a VAWLUME clock produces a
correspondence row, not an edit.

Which caller was claimed over a window is `imported_attribution_claims`.

**"Imported" means produced outside VAWLUME and brought in through a mapping
profile.** It does not mean "written by the imported path". A localization
backend's own segmentation has that property and lands in this table too. Which
kind of external system produced a run is `attribution_runs.attribution_path`.

### `imported_attribution_claims`

One row per *(window, claimed caller)* — the shape the source has, since the
generic profile declares a long table with one row per claim.

| Column | Holds |
|---|---|
| `source_caller_label` | the label as the file spelled it, **one label per row** |
| `entity_id` | the entity the profile's declared map resolved it to |
| `score`, `score_semantics` | the exporter's number, and what it meant *there* |
| `probability`, `probability_semantics` | same, bounded to `[0,1]` |
| `claim_ordinal`, `source_locator` | where in the source the claim came from |

The number discipline is `attribution_candidates`' discipline, deliberately
identical: `score` unconstrained because it is somebody else's scale, `probability`
bounded because the word means something, nothing converting between them, and a
CHECK refusing either without its semantics.

**Absence is NULL.** A claim whose source carried no number stores NULL for both,
because a label with no number is a legitimate import and converting a name into
certainty is the specific failure the profile's
`require_one_of_score_or_probability: false` refuses.

`entity_id` is nullable. Under the shipped `declared_only` /
`unresolved_label_policy: refuse` policy intake resolves every label or refuses the
import by name, so nothing writes NULL — but resolution is a *policy*, and a future
profile permitting an unresolved label needs somewhere honest to put one rather
than forcing the importer to invent an entity.

`UNIQUE(window, source_caller_label)` — one caller claimed twice over one window is
the same assertion twice, possibly with two different numbers, and keeping the
first is how a score disappears silently.

**A claim is not a candidate**, and correspondence does not promote it into one.
That would require deciding which correspondence is good enough to carry a claim
onto a target — a policy question that would collapse preserved ambiguity if
answered in storage.

### `attribution_window_correspondences`

Links an imported window to a target across differing clocks and IDs.

`iou_basis` is `native` or `aligned`, and an `aligned` basis must name its
`alignment_run_id`. The column exists because **aligned duration is not native
duration** under a piecewise clock: an IoU computed on aligned intervals is not the
IoU of the native ones when a breakpoint falls between them.

Ambiguity is preserved — one window may correspond to several targets, and nothing
here chooses.

## The backend/localization slice

Added at schema version `0.12-draft`, for the backend path. The governing
decisions are in
[`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md).
None of these tables or columns is named after a backend, and a backend run uses
every table above unchanged.

### Two grains, and nothing crosses between them implicitly

A producer's output arrives at **window grain**: its caller scores are about
(window, claimed caller) and its localization estimates are about (window,
optionally a claimed caller). Attribution works at **target grain**: candidates
are about (target, entity), and evidence is about a target or a candidate. Which
event a window refers to is correspondence, decided later.

So a backend's caller scores land in `imported_attribution_claims`, exactly as
an imported exporter's do, and its estimates land in
`attribution_localization_estimates`. A claim becomes a candidate only through
`vawlume.attribution.addCandidates`. An estimate reaches a target only through an
explicitly written `source_localization` evidence row that cites it. The schema
holds both grains and promotes nothing.

### `attribution_localization_estimates`

One position a producer estimated a sound came from, keyed to the window it was
computed over.

| Column | Holds |
|---|---|
| `imported_attribution_window_id` | the producer's window (required) |
| `imported_attribution_claim_id` | the claimed caller the producer tied this estimate to, if any; it must be a claim over the same window |
| `estimate_ordinal`, `native_estimate_id` | the producer's own order and identifier; `UNIQUE(window, estimate_ordinal)`. Several estimates per window coexist and nothing ranks them |
| `coordinate_system_id` | the declared frame (**required**, `ON DELETE RESTRICT`) |
| `position_x`, `position_y` | required, exactly as reported, in the frame's unit |
| `position_z` | only under a 3D frame; NULL for a 2D estimate, **never `0`** |
| `position_semantics` | required: what point this is and who computed it |
| `confidence`, `confidence_semantics` | the producer's localization confidence on its own unbounded scale, with its semantics required whenever present. **Not a caller probability** |
| `source_file_id`, `mapping_profile_version_id`, `source_locator`, `notes` | provenance, as on the windows |

**The frame is part of the coordinate.** Compatibility with any other spatial
fact is identity of `coordinate_system_id`, never matching units or
dimensionality ([`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md)).
Nothing in VAWLUME transforms an estimate between frames or computes a distance
from it.

**A row is a window-level summary.** A time-resolved localization track is dense
data and stays in the registered artifact. Positional uncertainty richer than
one scalar, such as a covariance or a per-axis error, is preserved as native
attributes of the estimate, not as canonical columns.

### `attribution_native_attributes`

A producer's own fields, preserved where its mapping profile asked. They are
kept apart from every canonical column, so a producer's `conf_v2` cannot be read
as a canonical confidence.

- **Exactly one owner**: a window, a claim, or an estimate. This uses the
  exclusive CHECK construction `attribution_targets` uses.
- **Typed** like `external_event_attributes`: `value_type` is `text`, `real`,
  `integer`, `boolean` or `missing`, with exactly one value column filled unless
  the type is `missing`. **There is no `json` type.** P4-2 is the ledger item
  created by choosing JSON once. A structured field is preserved as several
  named scalars, or verbatim in `native_raw_token`.
- **One value per (owner, `attribute_name`)**, enforced by three partial unique
  indexes, because a UNIQUE across nullable owner columns constrains nothing in
  SQLite.

### `attribution_run_declared_inputs`

What a producer declared it had already consumed, per upstream uncertainty
source. This closes the gap the Phase 4 contract's 4.12a correction recorded:
nothing used to say whether an exporter's score already consumed evidence that
VAWLUME also holds.

- `input_dimension` is one of the **four uncertainty sources**:
  `temporal_alignment`, `pose_localization`, `visual_identity`, or `acoustic`.
  It is not one of the five evidence dimensions, because `source_localization`
  is a producer's output, not one of its inputs.
- `declaration` is `used` or `not_used`. **No row means undeclared**, which is
  unknown and is never `not_used`.
- `declared_by_profile_version_id` is required and `ON DELETE RESTRICT`.
- The primary key is `(attribution_run_id, input_dimension)`.

## `v_attribution_window_correspondences`

One row per stored correspondence and window claim, joined to the window, the
target, and the claims the window carries. A window with several claims repeats
its correspondence once per claim, and a window with none gives one row with NULL
claim columns, so count correspondences by `attribution_window_correspondence_id`
rather than by rows. It exists so no caller composes that join by hand.

It carries **two bases that must not be confused**:

| Column | Says |
|---|---|
| `iou_basis` | whether the IoU was computed on `native` or `aligned` intervals |
| `target_extent_basis` | which of the five derivations supplied an agreement group's interval — NULL for a detection or consensus event, which carry their own |

A reader who conflated them would read a drift artefact as an extent choice.

The extent basis is **not** stored on `attribution_window_correspondences`. It is
already declared on `attribution_targets`, one join away and unambiguous, and a
second copy would be a second place for one fact to be wrong.

**A run may hold one agreement group under several bases.** Each *(group, basis)*
is its own `attribution_targets` row — no UNIQUE prevents it, and the two have
different intervals, so they are genuinely different targets. This is what lets an
analyst compare union against intersection without a second attribution run. The
consequence for target identity: an `agreement_group_id` alone no longer
necessarily identifies one target in a run, so `attributionResolveTarget` requires
`agreement_extent_method` as a disambiguator and raises
`vawlume:attribution:TargetAmbiguous` without it — machinery 4.2 built before
anything needed it.

Claim columns are NULL where a window carries no claim, and a NULL `claim_score` is
an absent number rather than a zero one.

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
  exactly one / two or more / no candidates. That holds when a selection is
  added, when the status changes, and, added at schema version `0.11-draft`, when
  a selection is removed, whether directly or by deleting the selected
  candidate. Removing the decision, its target, or its run removes the set with
  it;
- an excluded decision gives a reason, and a failed run gives a failure code;
- a second decision for one target under one policy is refused;
- an `aligned` correspondence names the transform it used;
- an identity-derived evidence row names the kind of statement it rests on and
  points at that row;
- no status anywhere means `validated`.

Added at schema version `0.12-draft`, for the backend/localization slice:

- a localization estimate names its frame, its position and its position
  semantics; a confidence implies its semantics; a `z` requires a 3D frame, on
  insert and on update; and the frame belongs to the project of the window's
  recording;
- an estimate tied to a claim is tied to a claim over its own window;
- a `source_localization` evidence row cites an estimate, no other dimension may,
  and the estimate comes from the evidence row's own run (on insert and on
  update);
- channel-cited evidence names a channel of its run's recording (on insert and on
  update);
- a native attribute has exactly one owner, a declared type, no JSON, and one
  value per owner and name;
- a declared input is one of the four uncertainty sources, is `used` or
  `not_used`, names the profile version that declared it, and appears at most
  once per run.

Added at schema version `0.13-draft`, for the native estimator:

- a cited derived measurement is about the run's recording, and a measurement
  whose recording cannot be established is not citable (on insert and on update);
- a cited derived measurement cannot be deleted while an evidence row cites it;
- `attribution_estimator_settings` is a declared profile kind.

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
  `PRAGMA foreign_key_check` will not see it. The `0.12-draft` exceptions are
  estimate dimensionality and evidence channel and localization scope, which
  carry `_update` twins; an estimate's frame project and claim scope do not.
  The `0.13-draft` measurement scope also carries one.
- **`agreement_extent_method` is not checked against the view.** A target may name
  an extent method for a group whose members were since deleted.
- **Nothing constrains `evidence_kind`, `method`, or any semantics string** to a
  vocabulary. That openness is deliberate and its cost is that spelling is a
  convention, not a guarantee.

For the backend/localization slice (`0.12-draft`):

- **Nothing confirms that a coordinate was measured in the frame it cites.**
  VAWLUME confirms that two facts name one declared frame. It cannot confirm
  that the producer and the tracker actually used it. A `px` frame is legal and
  supports no real-distance claim.
- **Nothing confirms a channel's numbering.** The scope guard confirms the
  channel exists on the run's recording. Whether the producer's channel 2 is
  the recording's channel 2 is a caller assertion.
- **Nothing in the schema requires that a cited estimate's window corresponds to
  the evidence row's target**, or that an estimate tied to a claimed caller
  supports only that caller's candidate. Those are write-path refusals: the
  schema refuses false claims, and the API refuses unsupported ones.
- **Nothing checks that a native attribute means what its name suggests**, or
  that a declared input is true. Both are the producer's statements, recorded
  with their provenance.

For the native-estimator change (`0.13-draft`):

- **Nothing in the schema requires a cited measurement to be about the evidence
  row's own event or channel.** Those are write-path refusals in `addEvidence`.
- **Nothing checks that an `attribution_estimator_settings` profile states
  anything.** The kind names a contract. Validating that a profile meets it is
  the loader's job.

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
- [`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md) — the backend/localization decisions behind the `0.12-draft` slice
- [`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md) — the native-estimator decisions behind the `0.13-draft` change
- [`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md) — coordinate systems, and why compatibility is identity
- [`22_phase1_correspondence_boundaries.md`](22_phase1_correspondence_boundaries.md) — the orientation document and the layer separation this slice inherits
- [`25_visual_identity_association.md`](25_visual_identity_association.md) — identity evidence, A-1, and the open-vocabulary reasoning
- [`11_temporal_alignment_schema.md`](11_temporal_alignment_schema.md) — the alignment data dictionary this one is modelled on
- [`16_multi_extractor_agreement_schema.md`](16_multi_extractor_agreement_schema.md) — agreement groups, whose extent the view derives
