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

## A second backend shape

Added at itinerary 5.8. One adapter cannot distinguish "general" from "fitted
to the first backend it met"; two structurally different ones can. Two templates
ship, and **neither is a real product's format**: both were written by this
repository. That is the limit of what follows.

### The two shapes

| Axis | `generic_backend_attribution_profile.json` | `generic_array_backend_attribution_profile.json` |
|---|---|---|
| Row shape | long by caller: one row per (window, candidate caller) | long by **measurement**: a row is either one localized source or one channel level |
| Callers | labels and scores, declared label map | **none**: localization only; no caller column, no score, no label map |
| Estimates per window | one, repeated across the window's caller rows | **several**, with the producer's `source_id` and declared `source_rank` |
| Dimensionality, unit | 2D, `cm` | **3D**, `mm`, with `z` reported |
| Frame | one key in `context` | **named per row** (`localization.coordinate_system`) |
| Positional uncertainty | one scalar confidence | **covariance terms**, with no scalar confidence |
| Channel evidence | wide: one column per microphone, fixed indices | **long**: a `mic` column and a `level_db` column |
| Window identity | the backend's own segment ids | **re-used VAWLUME event ids**, with the backend's own times |
| Track references | yes | none |

### Mapping audit

Every element of the second shape is held by machinery that already existed.
**No code, schema or profile-language change was needed.**

| Second-shape element | Held by | Note |
|---|---|---|
| `event_ref` (an echoed event id) | `imported_attribution_windows.native_window_id`, verbatim | never a key: correspondence relates the window by its times (tested with an id that names a *different* event) |
| `t_on`, `t_off` | native window times | |
| `source_id`, `source_rank` | `native_estimate_id`, `estimate_ordinal` (`ordinal_source = declared`) | ranks are the producer's, and nothing prefers rank 1 |
| `frame` per row | resolved per row to `coordinate_system_id` | a `z` under a 2D frame is refused before writing |
| `x_mm`, `y_mm`, `z_mm` | `position_x/y/z`, exactly as written | |
| `var_x`, `var_y`, `var_z`, `cov_xy` | estimate-owned native attributes, unit `mm^2` | contract D15: no canonical column, and no scalar derived from them |
| `mic`, `level_db` | window-owned `channel:<mic>:array_channel_level` (+ `:semantics`) | `channel_index_field` grammar; the index is resolved against the recording |
| (no callers) | no claims | a decision over such a run needs candidates someone else names; with no numbers, the shipped policy reports `excluded` |

Both runs coexist in one database over one recording with separate profile
versions, checksums and source files. `vawlume.attribution.report` returns the
same fields and the same table columns for both, with no per-backend branch
(`tests/integration/test_backend_second_shape.m`).

### Deliberately not expressible: wide caller columns

One row per window with a score column per candidate (`score_A`, `score_B`, …)
is a different shape. As in the imported profile, the backend profile language
has no grammar for it: a block attempting one is reported as an unknown key and
never interpreted. Supporting it would mean a profile-declared reshape from
column names to caller labels, which is the guesswork about which column means
which animal that declared-only resolution exists to prevent. Reshape upstream.

## What a backend can provide that VAWLUME cannot hold

The section that ages best: things a localization backend may report that have
no home, or only a non-relational one.

| Backend output | What happens | Why |
|---|---|---|
| A localization with **no reported interval** (an event reference only) | **Not holdable**: a window requires native times | Contract D14. An echoed id is not a key, so an interval is the only bridge to an event |
| A **time-resolved** localization track (a position per frame within a call) | Not stored; only window-level summaries | Dense data stays in the artifact, under the multimodal storage policy |
| **Covariance / per-axis error / error ellipses** | Preserved as native attributes, term by term; no canonical column, and nothing derives a confidence | D15. Legible and queryable by name, but any consumer must know the producer's convention |
| **Per-channel values** before promotion | Window-owned native attributes (`channel:` prefix); relational `recording_channel_id` only after explicit promotion to evidence | The schema cites a channel only at target grain (F5.3-1) |
| **Video-track associations** before promotion | Claim-owned native attributes (`track_reference:` prefix); the association is checked to exist, never chosen by time | Choosing one would compare the backend's clock with the tracker's (F5.4-2) |
| **Wide caller columns** | Not expressible | Above |
| A **transform between frames** the backend applied, or wants applied | Not held, and never performed | VAWLUME has no frame transforms; produce data in one frame upstream |
| A backend's **own decision** ("the caller is A") | Only as a claim with its number; never as a VAWLUME decision | A decision in VAWLUME is a declared policy over candidates |
| A **combined** caller-and-location confidence | As a claim score with its semantics (an imported composite), never split into dimensions | Nothing decomposes somebody else's combination |
| Whether the **estimate's ordinal was declared** | Lost at intake: `estimate_ordinal` is stored, `ordinal_source` is not | F5.4-4, minor |

## Related documents

- [`../design/05_backend_localization_contract.md`](../design/05_backend_localization_contract.md) — the decisions
- [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md) — the tables
- [`32_imported_attribution_intake.md`](32_imported_attribution_intake.md) — the imported path, whose rules carry over
- [`03_source_mapping_intermediate_representation.md`](03_source_mapping_intermediate_representation.md) — the IR contract
- [`23_spatial_geometry_schema.md`](23_spatial_geometry_schema.md) — coordinate systems; compatibility is identity
