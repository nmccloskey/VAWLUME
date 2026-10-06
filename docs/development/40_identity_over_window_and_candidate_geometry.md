# Identity over a window, and candidate geometry

Added in Phase 6 (itinerary 6.5). The governing decisions are D9, D10 and D17 of
[`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md).
This closes ledger item **I-4**, the missing time-valid identity-association
helper.

Development plan §11.1 step 7 asks for *candidate-entity-to-microphone geometry
through the visual identity layer rather than assuming track label = subject*.
Two read-only functions do that:

| Function | Answers |
|---|---|
| `vawlume.tracking.identityOverWindow` | Which entity does each native track represent over this window, and is that true for the **whole** window? |
| `vawlume.estimator.candidateGeometry` | For one call: which track represents each participant, and how far was its bodypoint from each microphone, or why can't that be said? |

Neither writes anything.

## `identityOverWindow`

```matlab
identity = vawlume.tracking.identityOverWindow(conn, streamRef, [startNative endNative]);
```

The window is in the **tracking stream's native units**, as associations are.
The caller places a call on that clock through the alignment layer first.

It composes `vawlume.tracking.resolveIdentity` and **adds no precedence rule**.
Which claim each track resolves to, the step that decided it, and the claims set
aside all come from `resolveIdentity` unchanged, and a test proves the chosen
association is identical. What it adds is the question `resolveIdentity` does not
ask:

| `time_validity` | Meaning |
|---|---|
| `whole_window` | the chosen claim covers the whole window, and no other live claim names a different entity (or an explicit unresolved statement) over **part** of it |
| `changes_within_window` | some live claim for the track names a different entity, or none, starting or ending inside the window: a swap or a crossing during the call |
| `partial` | the chosen claim covers part of the window, and nothing contradicts it there |
| `none` | no claim was chosen |

A rival claim covering the **whole** window is not a change within it. It
competes over the same span, and `resolveIdentity`'s rule already chose between
them. Only a claim that begins or ends inside the window marks a change.

**A swap is never answered by the claim covering the midpoint.** A swap exactly
at the call's midpoint is `changes_within_window`, and a test holds that case.

`identity_status` distinguishes `resolved`, `unresolved` (the chosen claim is an
explicit statement that nobody can tell), `tied` (the rule would not break a
tie), `all_rejected`, and `none` (nobody looked).

`identity_value` is not read, and nothing is weighted or averaged.

## `candidateGeometry`

```matlab
geometry = vawlume.estimator.candidateGeometry(conn, struct(detection_id=12), ...
    eventClock, struct(stream=streamRef, bodypart="snout", max_gap_s=0.05, ...
    alignment_run_id=trackingRun), participantEntityIds, [1 2]);
```

It composes `eventReferenceInstants`, `positionsAtInstants`,
`identityOverWindow`, `readChannelPlacements` and `geometry.distance`.

**Participants are entity ids** from the run's participant snapshot. Each must be
linked to the recording (`ParticipantNotLinked`). A track label is never a
participant.

### Enumerate, never marginalize

A participant gets distances **only** when exactly one native track resolves to
it with `whole_window` validity. Otherwise it gets no distance and one reason:

| Reason | When |
|---|---|
| `identity_changes_within_window` | the entity is chosen by, or contradicts, a track whose identity changes during the call |
| `identity_multiple_tracks` | two or more tracks resolve to it. Not enumerated as separate pairings, because choosing between two scores for one candidate would be an unstated combination rule |
| `identity_partial_window` | its one track's claim covers only part of the call |
| `identity_unresolved` | no track resolves to it, and some track is unresolved, tied or all-rejected, so it *could* be this entity |
| `identity_no_track` | no track resolves to it, and no unresolved track could be it |

The reverse view (`result.tracks`) lists each track with its identity and whether
its entity is a participant. A track associated with no participant, or two
tracks on one participant, is QC information a reader needs.

### Per-row states, once a track is established

Rows are per (participant, channel, instant basis), where the bases are `onset`,
`midpoint`, `offset`, `window_median` and `window_min`.

| Reason | When |
|---|---|
| `bodypart_missing` | no track carries the bodypart; none is substituted |
| `track_not_covered` | the instant has no position: outside declared coverage, beyond the samples, or across a gap above `max_gap_s`. `position_reason` gives the primitive's detail |
| `track_covered_empty` | coverage is declared but the window holds no sample |
| `channel_unplaced` | the channel has no declared placement |

**Frames must be one frame.** The tracking frame and every placement's frame go
through `vawlume.geometry.distance`'s identity rule, so a placement in another
frame raises `CoordinateSystemMismatch`, and nothing is transformed. A `px`
distance comes back in `px`. Whether the estimator may use a unit is its
profile's declaration (contract D17), not this function's.

Each row also carries what 6.9 needs to write evidence with its citations:
`tracking_identity_association_id`, `decided_by_step`, `time_validity`,
`recording_channel_id`, the unit and distance basis, the pose confidences (kept
separate), and the timing evidence (`event_extrapolated`, `bracket_extrapolated`,
`clock_uncertainty_s` and semantics). Every reason above uses the native
estimator's closed no-score vocabulary (contract D10).

## Invariant 26, as a guard

*A track reaches an entity only through a cited `tracking_identity_associations`
row.* `testNoCodeComparesATrackLabelWithAnEntityIdentifier` (in
`tests/integration/test_identity_candidate_geometry.m`) searches `+estimator/`
and `+tracking/` for a comparison between a track-label token and an entity
native-identifier token. It looks in code outside string literals, and in single
SQL literals containing both tokens and an `=`. It was injection-verified with
both shapes. A track named exactly like an entity's `native_id` is shown not to
link to it.

## Related documents

- [`../design/06_native_estimator_contract.md`](../design/06_native_estimator_contract.md): D9, D10, D17
- [`25_visual_identity_association.md`](25_visual_identity_association.md): associations, `unresolved` versus none, the precedence rule
- [`39_event_window_tracking_retrieval.md`](39_event_window_tracking_retrieval.md): the positions this composes
- [`38_spatial_primitives.md`](38_spatial_primitives.md): distance and window summaries
