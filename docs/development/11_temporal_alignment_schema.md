# Temporal alignment schema

## Scope

This document is the data dictionary for VAWLUME's temporal-alignment relational
grammar: what each table means, which table is authoritative for what, and which
invariants the database enforces versus which are left to application code.

It describes the relational structure. External event and anchor table source
mapping now exists as a database-free IR layer; manifest orchestration, database
registration, transform fitting, aligned-timestamp generation, and timeline
construction do not yet exist. The
governing design contract is
[`../design/02_temporal_alignment_contract.md`](../design/02_temporal_alignment_contract.md).

Schema version `0.4-draft`, `PRAGMA user_version = 4`. The only `0.3` to `0.4`
DDL change is the addition of `alignment_anchor_mapping` to the closed
`config_profiles.profile_kind` vocabulary, so anchor mapping profiles can later
be registered without misclassifying them as event-stream profiles.

## The eight distinct concepts

The single most important property of this schema is that these are eight
different things, not four things wearing different hats:

```text
timebase            a clock
stream              a logical series of records on one clock
event               one record in a stream
coverage            when a stream was actually being observed
alignment set       one user-facing alignment operation, with a reference clock
transform           one source clock expressed in that reference
anchor              the identity of a coordinating event
observation         one clock's reading of that anchor
```

The draft schema this replaced collapsed anchor and observation into a single
`(source_time, target_time)` row, which made "one anchor seen on three clocks"
literally unrepresentable, and it had no concept of coverage or of an alignment
set at all.

## Timebases

`timebases` defines a clock: an audio file's sample clock, a video's frame clock,
an operant controller, a neural acquisition system.

`timebase_kind` is deliberately free text. VAWLUME does not own a vocabulary of
acquisition devices, and a closed list would push users toward miscategorizing an
unfamiliar clock rather than describing it.

The one property alignment genuinely needs is a resolvable audio clock per
recording, carried by `is_recording_native`:

- `is_recording_native = 1` marks the clock a recording's detections are in;
- a CHECK requires `recording_id` to be present on such a row;
- a partial unique index permits at most one per recording.

**Detections carry no `timebase_id`.** They inherit their clock through
`recording_id`. Adding the column to every detection row would duplicate a fact
the recording already determines, and create the possibility of contradicting it.

**Reference status is not stored here.** Being the reference is a property of one
alignment set, not of a clock: the same neural clock may be the reference in one
alignment and a source in another. It lives on
`alignment_sets.reference_timebase_id`.

### Name uniqueness

Timebase and stream names are unique within their scope via **partial unique
indexes**, not table-level UNIQUE constraints:

```sql
CREATE UNIQUE INDEX idx_timebases_recording_name
    ON timebases(recording_id, timebase_name) WHERE recording_id IS NOT NULL;
CREATE UNIQUE INDEX idx_timebases_project_name
    ON timebases(project_id, timebase_name) WHERE recording_id IS NULL;
```

The reason is specific and easy to get wrong: SQLite treats NULLs as distinct in
a UNIQUE index, so the previous `UNIQUE(project_id, recording_id, timebase_name)`
enforced nothing at all for project-scoped rows, where `recording_id` is NULL.
`external_streams` had the same defect through a nullable `source_file_id` and is
fixed the same way.

## Streams, sources, events, attributes, coverage

`external_streams` is a **logical** object — "the behaviour scoring for this
session" — not "this CSV". It names the stream, its kind, its modality, and the
clock its records are stated in.

`external_stream_sources` holds where the records came from. Exactly one of
`source_file_id` / `artifact_id` identifies each row (CHECK-enforced), and several
rows per stream are legal, because one logical stream may span several exports or
be re-exported later.

> **One authority.** The former direct `source_file_id`, `artifact_id`, and
> `mapping_profile_version_id` columns on `external_streams` were removed rather
> than kept alongside the junction. Keeping both would have created two competing
> provenance answers for the same question. `external_stream_sources` is the only
> path.

`external_events` carries both vocabularies:

| Column | Meaning |
| --- | --- |
| `native_event_id` | the source's own row identifier |
| `native_event_label` | the source's own term, preserved verbatim |
| `event_type` | the normalized operational key VAWLUME queries |

When no mapping profile supplies a normalization, `event_type` may simply repeat
the native label. Neither is a universal behavioural or neural taxonomy, and
normalization never overwrites the native term.

`external_event_attributes` holds arbitrary mapped fields — actor, cell id,
confidence, prominence — in long form, following the `entity_attributes`
typed-value convention already used elsewhere in the schema. Missingness is
explicit through `value_type = 'missing'` with the raw token retained in
`native_raw_token`, rather than being coerced to `0` or `''`.

`external_stream_coverage` records when a stream was actually being observed, in
its own native clock. This is what allows a regularized timeline to distinguish

```text
event absent      the stream was observed here and nothing happened
not observed      nothing establishes that anyone was watching here
```

Multiple segments per stream are the point: a dropout, a paused camera, or a
scorer who annotated two windows must not be flattened into one continuous
interval. The prototype stores only `observed` intervals; any span outside every
segment of a stream is unknown, not empty. The status vocabulary is deliberately
one value wide, and any addition should stay small and be defined here.

## Alignment sets and transforms

An **alignment set** is one user-facing multimodal operation: "express this
session's clocks relative to the neural clock." It owns

- the `analysis_run_id` identity (UNIQUE — the set is the analysis),
- the chosen `reference_timebase_id`,
- and the exact manifest evidence, through `manifest_source_file_id` **or**
  `manifest_artifact_id` (at most one, CHECK-enforced, and optional while the set
  is still being assembled).

Manifest provenance reuses the existing `source_files` / `artifacts` registries
rather than adding a parallel one, and no `alignment_manifest` profile kind was
introduced: a session manifest is evidence, not a reusable semantic profile.

`time_alignment_runs` is a **child** of the set — one source clock expressed in
the set's reference — not an independent user-facing analysis. `UNIQUE(alignment_set_id,
source_timebase_id)` gives one answer per source clock per set.

`target_timebase_id` is retained on the run for readable joins, but it is
redundant with the parent's reference and a trigger enforces equality on insert
and update. It is a convenience column, never an independent authority.

Method vocabulary is closed: `offset`, `affine`, `piecewise_affine`.
`piecewise_affine` is representable here and in `alignment_segments`; **fitting**
it is deliberately deferred, and the fitting API must fail clearly rather than
silently degrading to a single affine segment.

There are no `identity` runs for the reference clock. The reference is already in
its own clock, and a row asserting `t = t` would be noise.

## Anchors, observations, residuals

An `alignment_anchors` row is a **logical** synchronization anchor: an identity
and a type, with no timestamps at all. The timestamps live on observations,
because the whole point is that one anchor is read separately on each clock.

> A synchronization anchor is not an experimental event. A TTL pulse fired near a
> female-introduction transition is an anchor; the separately scored
> `female_entry` event is an experimental event in `external_events`, and must not
> be forced to equal the pulse.

`alignment_anchor_observations` is one clock's reading of one anchor.

- Several observations per anchor per clock are legal — redundant TTL channels
  and duplicate marker readings are real, and their spread is evidence about
  synchronization quality.
- A partial unique index permits **at most one `included_in_fit = 1` observation
  per (anchor, timebase)**. Redundancy is preserved; redundancy silently becoming
  two statistical anchors is prevented.
- `external_event_id` is optional, so a manually identified marker edge with only
  a timestamp is legal. When supplied, a trigger requires that event to belong to
  a stream on the same timebase the observation claims.
- `observation_role` is a compact vocabulary (`primary`, `replicate`, `excluded`)
  and a CHECK keeps `excluded` from also claiming to be in the fit. It is
  deliberately not over-specified before real synthetic examples exist.

`alignment_anchor_residuals` is per-anchor fit evidence. A residual belongs to one
pairwise transform, not to the logical anchor, because the same anchor yields a
different residual under every fit it participates in. Both observations are named
explicitly rather than inferred, so a reader can see exactly which two readings
produced the number, and a trigger requires that

- both observations belong to the named anchor,
- the anchor and the run belong to the same alignment set,
- the source observation sits on the run's source clock, and
- the reference observation sits on the run's target clock.

Excluding a residual requires an `exclusion_reason` (CHECK-enforced), so an
exclusion is never silent.

## What is authoritative

```text
authoritative:  native timestamp + the transform in alignment_segments
cache:          aligned_external_events
```

`alignment_segments` holds the mathematics, unchanged from the draft:

```text
target_time = scale * source_time + offset_s
```

`aligned_external_events` exists so downstream joins and audits can read an
aligned time without evaluating a transform. It may be regenerated or discarded
at any time. **Nothing in VAWLUME may require a row there in order to align an
event**, and there is deliberately no `aligned_detections` counterpart: detections
already live on their recording's native clock, and materializing a second copy of
their timing would create exactly the competing authority this rule prevents.

## What the schema enforces, and what it does not

Enforced by the database, each with a probe in
[`tests/unit/test_alignment_schema.m`](../../tests/unit/test_alignment_schema.m):

| Invariant | Mechanism |
| --- | --- |
| At most one native audio clock per recording | partial unique index |
| Native status requires a recording | CHECK |
| Timebase/stream names unique within scope | partial unique indexes |
| A stream source names exactly one of file/artifact | CHECK |
| Event and coverage intervals never end before they start | CHECK |
| Coverage status vocabulary | CHECK |
| Attribute missingness is explicit and exclusive | CHECK |
| One attribute name per event | UNIQUE |
| One alignment set per analysis run | UNIQUE |
| At most one manifest reference per set | CHECK |
| Anchor keys unique within a set | UNIQUE |
| At most one included observation per anchor and clock | partial unique index |
| An excluded observation is not in the fit | CHECK |
| An observation's event lives on the same clock | trigger |
| One transform per source clock per set | UNIQUE |
| A run's target equals its set's reference | trigger (insert and update) |
| Closed transform-method vocabulary | CHECK |
| A clock is not aligned to itself | CHECK |
| A residual stays inside its run, anchor, and clocks | trigger |
| One residual per anchor per run | UNIQUE |
| An excluded residual states why | CHECK |

**Left to application code**, and stated here so nothing pretends otherwise:

- that a set's source transforms cover every stream the manifest named;
- that `n_anchors_used`, `fit_rmse_s`, and `max_error_s` agree with the stored
  residuals — the schema stores both but cannot compute one from the other;
- that `alignment_segments` for a `piecewise_affine` run tile the source range
  without gaps or overlaps;
- that an anchor observed on a clock with no transform in the set is either
  intentional or an error;
- that a cached `aligned_external_events` row still matches its transform.

Each of these gets a regression test in the pass that implements the behaviour
concerned, not a speculative trigger now.

## Sequence tables

`sequences`, `sequence_members`, `bouts`, and `bout_members` are **untouched** by
this work. They remain the original draft, are still unused by any code, and are
deliberately not redesigned in anticipation of a later sequence phase. Any pain
they cause is deferred Phase 8 work.

## Phase 1 fixture

The Phase 1 synthetic fixture continues to seed this grammar as a schema example
rather than a workflow demonstration: two clocks, one stream with one source and
one observed coverage window, two events, one alignment set, one `offset`
transform, two logical anchors each observed on both clocks, and two residuals.

Its transform is exactly `target = source + 0.55`, and both anchors are consistent
with it, so every residual is zero and the recorded fit error is zero. Observation
`uncertainty_s` stays 0.002 because stated measurement uncertainty is a different
quantity from fit residual.
