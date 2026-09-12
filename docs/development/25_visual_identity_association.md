# Visual identity association and uncertainty

Added at schema version `0.7-draft` (`PRAGMA user_version = 7`), alongside the
spatial foundation (`23_`) and the tracking input contract (`24_`). The `0.6` to
`0.7` change is one draft version covering all three; no further bump is expected
within Phase 2.

Design rationale lives in
[`../design/03_multimodal_input_contract.md`](../design/03_multimodal_input_contract.md).
This document is the implementation-facing reference.

## Three identities, not one

```text
native track identity      the upstream trajectory label: 'track0', 'mouse_a'
canonical entity identity  the VAWLUME experimental subject
visual identity evidence   a claim that the first corresponds to the second,
                           over an interval, from a stated source
```

A tracker may emit a stable-looking label while still permitting identity swaps,
ambiguous crossings, and uncalibrated identity evidence. **A track label is not
proof of canonical identity**, and `tracking_series` therefore carries no entity
column at all — see `24_tracking_input_contract.md`.

## `tracking_identity_associations`

One row is one interval-scoped, provenance-bearing claim.

| Column | Meaning |
| --- | --- |
| `external_stream_id` + `native_track_id` | which trajectory the claim is about |
| `start_time_native`, `end_time_native` | the interval it applies to |
| `entity_id` | the candidate entity, or NULL for an explicit unresolved statement |
| `assignment_state` | `candidate`, `assigned`, `ambiguous`, `unresolved`, `rejected` |
| `evidence_kind` | what kind of evidence this is — always required |
| `identity_value` | the number, when the source supplied one |
| `identity_value_semantics` | what that number means — required whenever there is one |
| `calibration_status`, `review_state`, `method` | how much the number can be trusted, and by whom |
| `analysis_run_id`, `source_file_id`, `mapping_profile_version_id`, `source_locator` | provenance |

### Keyed on the track, not the trace

The key is `(stream, native_track_id, interval)` and **not**
`tracking_series_id`. Identity belongs to a trajectory over time, not to one
`(track, bodypart)` trace: when two animals cross and their labels swap, every
bodypart of that track is affected at once.

### Several rows may cover one interval

That is the ambiguity model, not a defect. During an uncertain crossing a track
may be compatible with entity A *and* entity B, and both candidates are kept.
Nothing forces one entity per track per interval, and no query may assume it.

What cannot be recorded twice is the **identical** candidate for the identical
interval — that would double the evidence without adding any, and would look
like corroboration it is not. `vawlume:tracking:IdentityAssociationDuplicate`.

### Unresolved is a statement; no evidence is not

`entity_id IS NULL` with `assignment_state = 'unresolved'` records that **nothing
known identifies the animal** over that interval. Somebody looked and could not
tell.

That is different from no row at all, which means nobody looked. The query
surfaces the distinction as `resolution = "unresolved"` versus `"none"`, and
collapsing them would let an unexamined track pass for an examined one.

A trigger pair keeps the pairing honest on insert and update: an entity without
`unresolved`, or `unresolved` with an entity, is refused. Two partial unique
indexes close both halves of the duplicate rule, because SQLite treats NULLs as
distinct and two `unresolved` rows would otherwise slip past a plain `UNIQUE`.

## Score semantics

**A missing numeric confidence stays missing.** A manual assertion, or an
upstream tool that emits only a label, records `identity_value` NULL — never
`1.0`. Converting a name into certainty is the specific failure this table exists
to prevent.

**A number without stated semantics is refused**
(`vawlume:tracking:IdentityValueSemanticsRequired`, and a schema `CHECK`). A
re-identification cosine similarity, an upstream per-frame likelihood and a
calibrated posterior are different quantities; a number that does not say which
it is invites comparison with values that mean something else.

`evidence_kind` and `identity_value_semantics` are **free text**. A closed
vocabulary would force an unfamiliar upstream system into the wrong category or
block it entirely — the same reasoning that keeps `timebase_kind` and
`reference_type` open. Values seen so far include `manual_assertion`,
`manual_review`, and `reidentification_score`.

## Dense identity policy

Frame-by-frame identity probabilities are **not** materialized into SQLite, under
the same policy as dense tracking samples. What is persisted is interval-level
association, review state, and the provenance needed to reproduce it —
`source_file_id` and `mapping_profile_version_id` per claim, because different
intervals legitimately come from different sources (an upstream tool for most of
a session, manual review over a crossing).

Windowed access to a dense identity trace is **not implemented**. When a real
upstream tool produces one, it should reuse the tracking reader's shape rather
than growing a second access path.

### Provenance is validated, not merely stored

Every reference a claim can cite — `entity_id`, `analysis_run_id`,
`source_file_id`, `mapping_profile_version_id` — must exist **and belong to the
stream's project**, and a cited mapping profile must be of kind
`tracking_input_mapping` or `external_stream_mapping`. Those are the two kinds
identity evidence actually arrives through: the tracking artifact itself, or a
separate reviewed table read through the event-mapping path.

| Refusal | Raised when |
| --- | --- |
| `vawlume:tracking:EntityScopeMismatch` | the entity belongs to another project |
| `vawlume:tracking:SourceFileNotFound` / `SourceFileScopeMismatch` | the artifact does not exist, or is another project's |
| `vawlume:tracking:AnalysisRunNotFound` / `AnalysisRunScopeMismatch` | the run does not exist, or is another project's |
| `vawlume:tracking:MappingProfileNotFound` / `MappingProfileKindInvalid` / `MappingProfileScopeMismatch` | the profile version does not exist, is the wrong kind, or is another project's |

A foreign key would prove only that some row exists somewhere. Since
`evidence_kind` is required precisely so that every claim has a stated basis, a
stated basis pointing at an unrelated experiment is worse than none: it reads as
auditable. Built-in profiles carry `project_id` NULL and remain citable from any
project, matching the allowance `vawlume.acoustic.registerReference` makes.

## Query API

```matlab
result = vawlume.tracking.identityCandidates(conn, streamRef, [start end]);
```

`result.associations` is one row per claim overlapping the window.
`result.tracks` is one row per native track **present in the stream**, including
tracks with no evidence:

| `resolution` | Meaning |
| --- | --- |
| `resolved` | exactly one candidate entity |
| `ambiguous` | more than one candidate over the window |
| `unresolved` | an explicit statement that identity is unknown |
| `none` | no identity evidence was ever recorded |

**It returns candidates and never forces one entity.** A caller that wants a
single answer must decide that itself, with the evidence in front of it.

## What stays separate

**Pose confidence is not identity confidence.** Whether a keypoint was well
localized is a different question from which animal a trajectory follows, and
neither is derived from the other. The identity result carries no pose column at
all; read pose confidence from `vawlume.tracking.readWindow` and compose the two.

All four combinations are valid and representable: high pose confidence with
ambiguous identity, low pose confidence with a manually verified identity, both
uncertain, or either absent.

**Alignment is not consulted.** Identity evidence is stated in the tracking
stream's own native units, and this layer transforms no clocks. A caller relating
an audio event to identity resolves the clock question through the alignment
layer and then asks here, so alignment uncertainty and identity uncertainty stay
separable all the way down to caller attribution.

Device-level synchronization evidence is unaffected by identity uncertainty.
**Phase 3 implemented the identity-dependent case**, and the rule this section
anticipated is the rule it follows: an anchor derived from an identity-dependent
biological event keeps its identity uncertainty in that anchor's own evidence
and QC, where it qualifies the anchor and never reaches the clock fit.

The link is one-directional and read-only from this layer's point of view.
Alignment cites an association; it creates none, rewrites none, and reweights
none. See `13_transform_fitting_and_alignment_qc.md`, "Identity-dependent
anchors".

## Not the same thing as `external_events.entity_id`

`external_events` also carries a nullable `entity_id`, and alignment intake
populates it by matching a source table's subject column against
`experimental_entities.native_id` — a direct lookup, silently skipped when no
entity matches. That link carries **no** `evidence_kind`, no value semantics, no
calibration status, no review state, and no interval of its own beyond the
event's.

It is a **user-declared attribution**: the person who scored the behaviour said
this event was about this animal, and VAWLUME recorded the name they used. For a
behaviour scoring sheet that is reasonable. It is not the same kind of object as a
row in this table, which is a claim with a stated basis that may be ambiguous,
unresolved, or numerically qualified.

The two must not be unioned as though they were one kind of claim. A later
consumer asking "which entity was this observation about" will find both, and the
weaker one looks deceptively like the stronger one because both reduce to an
`entity_id`. When caller attribution consumes identity evidence it has to decide
explicitly how much a declared event link is worth relative to a reviewed
interval-scoped association — that decision belongs there, not here, and neither
representation should be changed to look like the other in the meantime.

## Identity evidence can outlive the trace it names

Associations are keyed on `native_track_id`, not on a `tracking_series_id` — see
[Keyed on the track, not the trace](#keyed-on-the-track-not-the-trace). There is
therefore no foreign key from an association to the trace rows that declare the
track.

`vawlume.tracking.registerIdentityAssociation` checks that the stream actually
contains the track (`vawlume:tracking:NativeTrackNotFound`), but nothing
maintains that afterwards. Deleting the last `tracking_series` row for a track by
hand leaves its associations in place, and `PRAGMA foreign_key_check` reports
nothing because no key is violated. `identityCandidates` will then return that
claim in `associations` while the track is absent from `tracks`, since the track
summary is built from `tracking_series`.

No public function deletes a series row, and deleting a stream cascades both
tables, so this state is only reachable through direct SQL. It is recorded here
because the asymmetry is a consequence of a deliberate keying decision rather
than an accident, and because a future deletion API would need to address it.

## What is not here

- Image-based re-identification of any kind.
- Correcting, smoothing or stitching upstream tracker output.
- Training or fitting an identity classifier.
- Caller attribution, or multiplying identity evidence by acoustic evidence.
- Converting a similarity or likelihood into a calibrated probability.
- Windowed access to dense framewise identity traces.
