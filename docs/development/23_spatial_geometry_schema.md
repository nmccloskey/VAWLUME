# Spatial coordinate systems and channel placement schema

Introduced at schema version `0.7-draft` (`PRAGMA user_version = 7`). The `0.6`
to `0.7` change adds the spatial foundation the multimodal layer needs:
`coordinate_systems`, `channel_placements`, three integrity triggers, and one
index. No existing table, trigger, view, or index changed.

The design rationale lives in
[`../design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md)
and is not repeated here. This document is the implementation-facing reference:
what the tables are, what is enforced where, and what deliberately is not.

## The two tables

```text
coordinate_systems   a declared spatial frame: key, name, dimensionality, unit
channel_placements   where one recording channel's microphone was, in one frame
```

`coordinate_systems` is project-scoped shared reference data. Placement cites it
now; canonicalized tracking streams will cite the same table, which is the point
— both sides of a spatial comparison name one frame.

`channel_placements` attaches to `recording_channel_id`, not to a device, a setup
profile, or a recording. A microphone reaches VAWLUME as a recording channel, and
a channel belongs to exactly one recording, so a placement row is
session-specific by construction and cannot claim a position outliving the
session it was measured in.

## Compatibility is identity

Two spatial facts are compatible **if and only if they cite the same
`coordinate_system_id`**.

Structural similarity is never sufficient. Two frames that both declare
`dimensionality = 2` and `unit = 'cm'` may have different origins, different axis
directions, or describe different arenas. `vawlume.geometry.assertCompatible`
compares identifiers and nothing else, and is the primitive later spatial work
composes.

**No transformation between frames exists anywhere in VAWLUME.**
`origin_description` and `orientation_description` are human-readable provenance,
never machine-applied. If two frames genuinely describe one space, the fix is
upstream — produce the data in one frame.

This is deliberately narrower than the temporal layer, which does fit and apply
clock transforms. Clock transforms are identifiable from explicit anchor
observations that users supply; no equivalent spatial anchor evidence exists in
the motivating workflows.

## What the schema enforces

| Rule | Mechanism |
| --- | --- |
| Dimensionality is 2 or 3 | `CHECK` on `coordinate_systems` |
| Frame keys are unique within a project | `UNIQUE(project_id, coordinate_system_key)` |
| At most one placement per channel | `UNIQUE` on `recording_channel_id` |
| `z` only under a 3D frame | `trg_channel_placement_dimensionality` (insert) and `…_update` |
| A placement's frame belongs to its channel's project | `trg_channel_placement_project_scope` |
| A cited frame cannot be deleted | `ON DELETE RESTRICT` on `coordinate_system_id` |
| Deleting a recording removes its placements | `ON DELETE CASCADE` through `recording_channels` |

The dimensionality rules are triggers rather than `CHECK` constraints because the
dimensionality lives on another table and SQLite `CHECK` cannot reference one.

**Both insert and update are guarded.** Without the update trigger a row could be
inserted legally and then given a `z`, or have its frame repointed at a 2D
system, reaching exactly the state the insert guard exists to prevent.

`ON DELETE RESTRICT` on the frame is deliberate: a placement whose coordinate
system vanished would carry coordinates in no declared space, which is worse than
refusing the delete.

## What the schema does not enforce

- **That the numbers are right.** VAWLUME confirms two facts cite one declared
  frame; it cannot confirm the user measured them in one.
- **Unit meaning.** `unit` is free text and is never interpreted or converted. A
  `px` frame is legal and supports no real-distance computation — a later phase
  needing metric distance must require a metric unit or an explicit
  provenance-bearing scale, and must never treat pixels as centimetres.
- **Intra-recording movement.** One placement per channel. A microphone moved
  mid-session is unrepresentable and needs an explicit time-bounded model, not a
  nullable interval added quietly.
- **Non-audio objects.** Cameras and arena landmarks are not placed. The frame
  exists; a later phase may add its own placement table citing it.

## Provenance, not authority

`config/02_device_profiles/…` carries a `placement` block and
`config/03_setup_profiles/…` carries `recording_geometry.microphone_positions`.
Both are **reusable** profiles applied to many sessions, so neither can answer
"where was this microphone during this recording".

They remain useful as authoring input and human documentation. A registration
call may read a setup profile and write per-recording placement rows, recording
the originating `config_profile_versions` row in
`channel_placements.source_profile_version_id`. The database then holds exactly
one answer per channel.

A two-level model — reusable setup geometry plus per-recording override — was
considered and rejected for creating two competing answers to one question, the
failure the alignment layer corrected when it replaced the direct source columns
on `external_streams` with `external_stream_sources`.

## MATLAB API

`+vawlume/+geometry/` owns these tables:

| Function | Purpose |
| --- | --- |
| `registerCoordinateSystem` | declare a frame; idempotent, never redefines |
| `registerChannelPlacement` | locate one channel's microphone; idempotent |
| `readCoordinateSystems` | frames of one project |
| `readChannelPlacements` | placements of one recording, with unit and dimensionality |
| `assertCompatible` | require a set of frames to be one frame |

Registration is idempotent: identical content reuses, different content raises
`CoordinateSystemConflict` or `PlacementConflict` rather than rewriting. A stored
frame is never redefined in place because placements already cite it and were
validated against its stored dimensionality.

Neither function creates what it references. A placement cites a frame that must
already exist and a channel that must already exist; inventing either would let a
placement choose its own units or assert geometry for audio that was never
recorded.

Selectors follow the existing convention — `recording_id`, or `project_key` plus
`source_relative_path`, never both — so a caller who can address a recording for
matching or agreement can address it here unchanged.

`assertCompatible` performs no spatial arithmetic. It answers whether relating a
set of frames is declared legal, and is the shared primitive tracking window
access uses before relating a tracking stream to channel geometry.
