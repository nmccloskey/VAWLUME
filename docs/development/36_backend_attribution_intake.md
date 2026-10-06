# Localization-backend attribution intake

Path B of the development plan: an external **localization backend** reports
its own call windows and, optionally, where each sound came from, which animal
it attributes the sound to, per-microphone evidence, and video-track
associations. VAWLUME maps that export into the same canonical attribution
representation the imported path uses. Nothing in it is named after a backend.

The design decisions are in
[`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md);
the tables are in [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md).
The imported path this mirrors is [`32_imported_attribution_intake.md`](32_imported_attribution_intake.md).

The adapter has two halves, split at the persistence line:

| Half | What it does | Status |
|---|---|---|
| **Mapping** | backend export + profile → a database-free IR, with a dry-run preview | Implemented (this document, below) |
| **Intake** | IR → database: resolves keys, writes rows in one transaction | Implemented (itinerary 5.4) |

A backend export can be mapped and previewed without a database, then imported.

## The mapping profile

`profile_kind` is `attribution_backend_mapping`, profile language `0.3-draft`.
The shipped template is
[`generic_backend_attribution_profile.json`](../../config/01_mapping_profiles/attribution/generic_backend_attribution_profile.json).
It names roles and never vendor columns: any backend reaches VAWLUME by pointing
each role at whatever it called that field.

| Block | Declares | Required? |
|---|---|---|
| `context` | window timebase key, native time unit, producing system and version; optionally the `coordinate_system_key` and the `tracking_stream_key` | yes |
| `columns` | `native_window_id`, `window_start`, `window_end`; optionally `caller_label`, `score`, `probability`, `native_track_id` | window columns only |
| `localization` | `position_x`, `position_y`, optionally `position_z`, `confidence`, `native_estimate_id`, `estimate_ordinal`, a per-row `coordinate_system` field, `confidence_range`, and `attachment` (`window` or `claim`) | no |
| `channel_evidence` | `declared_channel_indices` and entries, each naming a value field, an evidence kind, units, semantics, and **either** a fixed `channel_index` **or** a per-row `channel_index_field` | no |
| `native_attributes` | producer fields to preserve: name, source field, owner (`window`, `claim` or `estimate`), and value type (`text`, `real`, `integer`, `boolean`; **no `json`**) | no |
| `value_semantics` | what `score`, `probability`, `position` and `confidence` meant where they came from; required for each one declared | yes |
| `declared_inputs` | per upstream uncertainty source, `used` or `not_used` | no |
| `caller_label_resolution` | `declared_only` label-to-entity map | when `caller_label` is declared |
| `correspondence` | attribution's own eligibility rule, the same grammar as the imported profile | no |
| `mapping_policy` | `preserve_source_values`, which cannot be set to false | no |

**Every element plan §10 lists is optional except the backend's own window.**
A backend that only localizes, one that only scores callers, and one that only
segments all map. The window is not optional because everything else attaches
to it, and a backend reporting no interval has nothing the canonical model can
hold (contract D14). An echoed VAWLUME detection ID in `native_window_id` is
stored verbatim and never treated as a VAWLUME key.

**A declared position needs a declared frame.** A profile with a `localization`
block and neither `context.coordinate_system_key` nor
`localization.coordinate_system` is refused at load
(`PROFILE_COORDINATE_SYSTEM_UNDECLARED`). A per-row frame field that is empty on
a row refuses that row.

**Declared inputs have three states.** A source declared `used` or `not_used` is
recorded. A source left out is **undeclared**, meaning unknown, which is never
recorded as `not_used`. The shipped template declares nothing, because a
template cannot know.

The score, probability, position, confidence and channel-evidence semantics are
**rendered** with the producer's name: `{producer}` is substituted from
`context.exporting_system` (and its version when one is declared), and
`; producer=<name>` is appended when the rendered string does not already name
it. The rendering is the imported path's, shared rather than copied.

## The IR

```matlab
loaded = vawlume.source_mapping.loadProfile(profilePath);
ir     = vawlume.source_mapping.mapTableToIR(tbl, loaded, SourceKey="source:export");
report = vawlume.source_mapping.preview(ir, Print=true);   % writes nothing
```

Everything is at **window grain**. Nothing names a VAWLUME event:

| IR table | One row per |
|---|---|
| `attribution_windows` | distinct backend window |
| `attribution_claims` | (window, claimed caller) |
| `attribution_localization_estimates` | distinct estimate |
| `attribution_channel_evidence` | (window, channel, evidence kind) |
| `attribution_track_references` | claim the backend tied to a video track |
| `attribution_native_attributes` | (owner, declared attribute) |
| `attribution_declared_inputs` | declared uncertainty source |

**Declared keys are carried, not resolved.** `coordinate_system_key`,
`channel_index`, `tracking_stream_key` with `native_track_id`, and the claim's
`entity_native_id` are what the profile and file said. Turning each into a
database identifier, or refusing it, is intake's job.

**Numbers are copied, not interpreted.** A numeric cell passes through
unchanged; a text cell is parsed once (`str2double`) and the double it denotes is
stored exactly. No rescaling, clamping, unit conversion, frame transformation,
or promotion of a score or a confidence to a probability. Absent values are
`NaN`, never `0` and never `1.0`: a 2D estimate has `position_z = NaN`, and a
label with no number has `score = NaN`.

**Estimate identity.** An estimate is keyed by the backend's
`native_estimate_id` when declared, else by its declared `estimate_ordinal`,
else by its exact position in its frame. So one position repeated across a
window's caller rows is one estimate, and two different positions are two
estimates that are both kept and neither preferred. With `attachment: claim`,
each claim owns its own estimate. An ordinal the backend did not declare is
assigned in source order and marked `ordinal_source = "source_order"`.

**A row is all or nothing.** Everything a row contributes is staged and
committed only if nothing in it is refused, so a refused row leaves no orphan
window, claim or estimate behind.

## What the mapper refuses

Every refused row becomes an error issue naming the row and the reason, and
makes the IR not ready for ingest. Nothing is dropped silently.

| Code | Row refused because |
|---|---|
| `ATTRIBUTION_WINDOW_ID_MISSING` | no window identifier |
| `ATTRIBUTION_WINDOW_BOUNDS_MISSING` | no usable start or end |
| `ATTRIBUTION_WINDOW_REVERSED` | the window ends before it starts |
| `BACKEND_WINDOW_CONFLICT` | a repeated window gives other bounds |
| `ATTRIBUTION_CALLER_LABEL_UNDECLARED` | the caller label is not in the declared map |
| `ATTRIBUTION_PROBABILITY_OUT_OF_RANGE` | a probability outside `[0,1]`, refused rather than clamped |
| `BACKEND_NUMBER_WITHOUT_CALLER` | a score, probability or track with no caller to attach it to |
| `BACKEND_CLAIM_CONFLICT` | a repeated caller over one window with other numbers |
| `BACKEND_TRACK_CONFLICT` | one claim tied to two different tracks |
| `BACKEND_COORDINATE_AXIS_MISSING` | one horizontal coordinate without the other |
| `BACKEND_COORDINATE_FRAME_MISSING` | a position with no declared coordinate system |
| `BACKEND_CONFIDENCE_WITHOUT_POSITION` | a height or confidence with no position |
| `BACKEND_CONFIDENCE_OUT_OF_RANGE` | a confidence outside the profile's declared range, refused rather than clamped |
| `BACKEND_ESTIMATE_CLAIM_MISSING` | estimates attach to claims and the row has no caller |
| `BACKEND_ESTIMATE_ORDINAL_INVALID` | a declared ordinal that is not an integer ≥ 1 |
| `BACKEND_ESTIMATE_CONFLICT` | a repeated estimate with another position, frame or confidence, or a reused ordinal |
| `BACKEND_CHANNEL_VALUE_INVALID` | a channel value that is not a finite number |
| `BACKEND_CHANNEL_UNDECLARED` | a channel index the profile does not declare |
| `BACKEND_CHANNEL_EVIDENCE_CONFLICT` | repeated channel evidence with another value |
| `BACKEND_ATTRIBUTE_TYPE_INVALID` | a native value that is not its declared type |
| `BACKEND_ATTRIBUTE_CONFLICT` | a repeated native value that differs |

One warning, `BACKEND_ATTRIBUTE_OWNER_ABSENT`, is non-blocking: a claim- or
estimate-owned native field on a row with no claim or estimate is reported and
not preserved, and the row is otherwise kept.

**A disagreement is refused, never resolved by keeping the first.** A long export
repeats window, estimate and channel values across a window's rows; when the
repeats disagree, keeping either would silently discard what the other said.

## Intake

Added at itinerary 5.4.

```matlab
plan   = vawlume.ingest.backendAttribution(conn, runRef, "data/backend_export.csv");
result = vawlume.ingest.backendAttribution(conn, runRef, sourcePath, Apply=true);
```

Planning is the default and writes nothing. `Apply=true` commits a
conflict-free plan in **one transaction**: the source file, the mapping-profile
version, the windows, the claims, the estimates, the native fields and the
declared inputs. A failure anywhere rolls all of it back. The run must be
`planned`, with `attribution_path = 'backend'`; `createRun` admits it since 5.4.

**Every column is read as text.** The mapper performs the only text-to-double
parse, so a stored coordinate, confidence or score is the exact double its source
text denotes, tested as a bit pattern.

### What intake resolves, and refuses by name

| IR key | Resolved to | Refusal |
|---|---|---|
| `coordinate_system_key` | `coordinate_system_id` in the run's project | `vawlume:attribution:LocalizationFrameUnknown` when no frame has the key; `LocalizationFrameScopeMismatch` when only another project's frame does |
| a `z` with its frame | the frame's dimensionality | `LocalizationDimensionMismatch`, before any write rather than as a trigger error |
| claim `entity_native_id` | `entity_id`, against the run's **participant snapshot** in its provenance | `CallerLabelUnresolved`, listing every offender |
| channel `channel_index` | a `recording_channels` row of the run's recording | `ChannelIndexUndeclared` |
| `tracking_stream_key` | a tracking stream of the run's recording or project | `TrackingStreamUnknown` |
| (stream, `native_track_id`) | at least one existing `tracking_identity_associations` row | `IdentityAssociationNotFound`; an importer never creates one |

Also refused: a run whose path is not `backend` (`RunPathMismatch`), a profile of
another kind (`ProfileKindInvalid`), a run with no v1 provenance snapshot
(`RunProvenanceInvalid`), a declared native attribute using a reserved name
prefix (`NativeAttributeNameReserved`), an export with no mappable window
(`ImportEmpty`), and a second apply (`ImportAlreadyApplied`).

**Which identity association applies at a window's time is not decided.** The
window is on the backend's clock and the association on the tracking stream's.
Relating them is correspondence and alignment work, and intake performs no
clock arithmetic.

### What is written, and where

| IR table | Stored as |
|---|---|
| `attribution_windows` | `imported_attribution_windows` (source file, profile version, locator) |
| `attribution_claims` | `imported_attribution_claims`, with the resolved `entity_id`; an unscored claim stores NULL |
| `attribution_localization_estimates` | `attribution_localization_estimates`, with the resolved frame, the claim when claim-attached, NULL `position_z` / `confidence` when absent, and source file and profile version |
| `attribution_native_attributes` | `attribution_native_attributes`, owned by the window, claim or estimate |
| `attribution_channel_evidence` | **window-owned native attributes**: `channel:<index>:<kind>` (real value, unit, raw token) and `channel:<index>:<kind>:semantics` (the rendered semantics) |
| `attribution_track_references` | a **claim-owned native attribute** `track_reference:<stream key>` holding the native track id |
| `attribution_declared_inputs` | `attribution_run_declared_inputs`, citing the mapping-profile version |

**Per-channel evidence and track references have no window-grain relational
home** (finding F5.3-1). The schema cites a recording channel or an identity
association only on `attribution_evidence`, which is about a VAWLUME target, and
intake has no target. They are therefore preserved as native fields under the
reserved prefixes above, **after** intake has verified that the channel and the
association exist. They become relational citations when explicit promotion
writes target-grain evidence through `vawlume.attribution.addEvidence`, added
at itinerary 5.5:

- a channel value is written as an ordinary evidence row with its value, units
  and the `...:semantics` text, naming `recording_channel_id`, which is
  scope-guarded to the run's recording (`EvidenceChannelScopeMismatch`);
- a track reference is written as `visual_identity` evidence citing a
  `tracking_identity_association_id` the caller chooses. Choosing the association
  valid at the call's time is the caller's declared act, because intake compares
  no clocks;
- a localization estimate is written as a `source_localization` row citing it,
  declaring its frame, refused across frames by `vawlume.geometry.assertCompatible`,
  and refused unless the estimate's window corresponds to the target.

### What intake does not write

No `attribution_candidates`, no `attribution_evidence`, and no
`attribution_window_correspondences` row. A claim is not a candidate and an
estimate is not evidence until explicitly promoted, and a backend window is
related to no VAWLUME event until correspondence relates it. The result's
`not_written` field names all three.

## A second backend shape, and what a backend can provide that VAWLUME cannot hold

Not yet written. Itinerary 5.8 owns these sections.

## Related documents

- [`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md) — the decisions
- [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md) — the tables
- [`32_imported_attribution_intake.md`](32_imported_attribution_intake.md) — the imported path, whose rules carry over
- [`03_source_mapping_intermediate_representation.md`](03_source_mapping_intermediate_representation.md) — the IR contract
- [`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md) — coordinate systems; compatibility is identity
