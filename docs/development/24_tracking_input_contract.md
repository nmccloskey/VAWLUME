# Tracking input contract and registration

Added at schema version `0.7-draft` (`PRAGMA user_version = 7`), alongside the
spatial foundation in
[`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md). The `0.6` to
`0.7` change is one draft version covering both; no further bump is expected
within Phase 2.

Design rationale lives in
[`../design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md).
This document is the implementation-facing reference.

## The one rule

**No tracking sample is ever written to SQLite.**

Positions, frames and confidences stay in the registered artifact and are read
window-wise on demand. There is no `tracking_samples` table, and registration
has no code path that could create one. An itinerary that wants one has left the
multimodal input contract and needs an explicit decision, not a migration.

What *is* stored is metadata: the logical stream, the traces it contains, the
column contract that resolves its artifact, its observed span, and its
provenance. A million-row export produces one `tracking_streams` row, a handful
of `tracking_series` rows, and one coverage segment.

## Tracking is an external stream

`external_streams`, `external_stream_sources`, `external_stream_coverage` and
`timebases` already express everything a tracking stream shares with a
behavioural or neural stream. Tracking reuses all four unchanged.

`stream_kind` gains `tracking`. The existing `continuous` value was considered
and rejected: a pose trace is not a continuous signal the way a photometry trace
is, and conflating them would blur the distinction the coverage and
window-reading semantics depend on.

`tracking_streams` is a **1:1 subtype** keyed by `external_stream_id`, adding
only what tracking has:

| Column | Meaning |
| --- | --- |
| `coordinate_system_id` | the declared frame its coordinates are in |
| `native_time_basis` | `time`, `frame`, or `both` |
| `nominal_frame_rate_hz` | required when the basis is frame-only |
| `has_confidence` | whether the upstream tracker emitted any |
| `declared_sample_count` | what the artifact held at registration |

`tracking_series` names one `(entity, bodypart)` trace. Native labels are
preserved verbatim; `canonical_bodypart_role` is optional and additive;
`entity_id` is nullable because an unlinked series is honest and a fabricated
link is not.

## The mapping contract

Profile kind `tracking_input_mapping`, mapping-profile schema version
`0.3-draft`, shipped example at
`config/01_mapping_profiles/tracking/generic_tracking_mapping_profile.json`.

**The contract names roles, never vendor columns.** DeepLabCut, SLEAP, MoSeq and
hand-scored output all reach VAWLUME through the same declaration by pointing
each role at whatever the exporting tool happened to call it. Nothing in the
validator, the mapper, or the schema knows any tool's layout.

| Role | Required |
| --- | --- |
| `position_x`, `position_y` | always — the irreducible content of a tracking row |
| `entity_label`, `bodypart_label` | always — identity, without which a sample cannot be attributed |
| `native_time` | when the basis is `time` or `both` |
| `native_frame` | when the basis is `frame` or `both` |
| `position_z`, `confidence` | never |

Shape is **long form**: one row per `(time, entity, bodypart)`. A wide export
with one column per bodypart is a different shape and needs its own profile. The
first implementation is deliberately narrow rather than guessing at a universal
reshaper.

Validation refuses, among others: a missing position or identity column, a
declared column absent from the actual table, a basis outside
`time`/`frame`/`both`, a frame-only profile with no frame rate, and one native
bodypart label assigned two canonical roles.

## The IR carries no samples

`mapTableToIR` gains a tracking branch that is deliberately unlike its event and
anchor siblings. Those emit one IR row per source row, because an external event
*is* the record. A tracking artifact's records are samples, so the mapper emits:

```text
tracking_streams   one row   the stream, clock, frame, basis, span facts
tracking_series    per trace the distinct (entity, bodypart) pairs
tracking_columns   per role  which artifact column resolved each role
coverage           one row   the artifact's own observed native span
```

The table is scanned to derive the trace inventory and the time span, which are
summaries of size O(series) and O(1). Nothing of size O(samples) is produced,
and `events`, `values` and `records` all stay empty.

Reading the artifact into MATLAB memory is expected and is **not** what the
dense-data policy forbids. The policy is about SQLite.

`ir_schema_version` stays `0.2-draft`. Adding IR tables has not bumped it
before — the alignment work added five without a bump — and the profile language
version (`0.3-draft`) is what carries the additive distinction. See the IR
contract document.

`+source_mapping` remains **database-free**, and a test asserts it.

## Registration

`vawlume.tracking.register(conn, recordingRef, trackingSpec, Apply=...)`.

Plan/apply with conflict classification, matching the extractor importers and
alignment intake. Without `Apply` it resolves every reference and reads the
artifact, so a dry run shows the real registration rather than a guess.

It **invents nothing**:

- the coordinate system must already be declared for the project — creating one
  implicitly would let an import choose its own units and dimensionality;
- the timebase must already exist for the recording or its project;
- an entity is linked only when `native_entity_label` matches an established
  `experimental_entities.native_id`; otherwise the series stays unlinked.

Compatibility is checked through `vawlume.geometry.assertCompatible` rather than
by comparing identifiers locally, so the identity-not-similarity rule has one
implementation.

Re-registering identical content reuses the stream. Re-registering a stream name
whose frame, clock, basis, sample count, or confidence availability differs
reports a conflict and writes nothing: coverage and later window reads already
cite the stored stream.

Everything commits in one transaction — stream, subtype, traces, coverage,
artifact provenance and profile version — or not at all.

## What is not here

- Window reading. That is the tracking reader's job, and it is where bounded
  access, coverage states and QC live.
- Interpolation, smoothing, gap filling, or any modification of tracking values.
- Raw video, pose estimation, or any pixel processing.
- Spatial caller evidence of any kind.
- Wide-form exports, multi-file streams, and dropout-segment inference from
  sample spacing — the last would be a guess about upstream tool behaviour.

## A recurring trap

The Database Toolbox can return an empty TEXT column as `<missing>` **even when
the SELECT wraps it in `IFNULL`**, and `<missing>` propagates silently through
string concatenation and comparison. Every read of a nullable tracking column —
`canonical_bodypart_role` in particular — must go through a `presentText`-style
normalizer before being compared or concatenated.
