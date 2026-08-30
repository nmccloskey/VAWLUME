# Alignment intake and registration

## Scope

This document is the contract for the transactional boundary that turns a
session alignment manifest plus validated source-mapping IR into database-resident
timebase, stream, event, coverage, anchor, and alignment-set records.

**It registers. It does not fit.** No `alignment_segments` row, no
`alignment_anchor_residual`, no `aligned_external_events` row, and no scale or
offset is produced here. Transform fitting is the next stage's work.

Relational targets are documented in
[`11_temporal_alignment_schema.md`](11_temporal_alignment_schema.md); the IR this
layer consumes is documented in
[`03_source_mapping_intermediate_representation.md`](03_source_mapping_intermediate_representation.md);
the governing design contract is
[`../design/02_temporal_alignment_contract.md`](../design/02_temporal_alignment_contract.md).

## Public API

```matlab
bundle = vawlume.ingest.alignmentManifest(manifestPath, ...)
plan   = vawlume.ingest.alignment(conn, manifestPath, ...)
result = vawlume.ingest.alignment(conn, manifestPath, ..., Apply=true)
```

`alignmentManifest` is database-free. It reads the manifest, resolves the tables
it names, maps each through its declared profile, and returns the IRs plus
manifest, source, and profile checksums. `alignment` plans against a database by
default and commits a conflict-free plan under `Apply=true`.

This mirrors the adapter/importer split the extractor paths already use:
`deepsqueakExport` / `deepsqueak`, `mupetExport` / `mupet`.

Options: `RepoRoot` for repository-relative profile paths, `SourceRoot` for
manifest-relative data paths (defaulting to the manifest's own directory so a
session folder is self-contained), `Tables` to supply in-memory tables instead of
files, and `RunSpec` for `run_key`, `run_label`, `vawlume_version`,
`source_commit`.

## The manifest

A manifest is **concrete session evidence, not a reusable semantic profile**. It
is registered as a `source_files` row with its SHA-256 and linked to the
alignment set through `alignment_sets.manifest_source_file_id`. No
`alignment_manifest` profile kind exists, and none should be added: reusable
mapping rules are profiles, and one session's description is not reusable.

It points at data rather than embedding it:

```json
{
  "manifest": {
    "manifest_schema_version": "0.1-draft",
    "alignment_key": "synthetic_session_01_alignment"
  },
  "session": {
    "project_key": "...",
    "recording": { "native_recording_id": "REC_SESSION_01" }
  },
  "reference_timebase": "neural_native",
  "method": "affine",
  "timebases": [ { "timebase_key": "...", "timebase_kind": "...", "recording_native": true } ],
  "streams":   [ { "stream_key": "...", "timebase_key": "...", "source": "...", "mapping_profile": "..." } ],
  "anchors":     { "source": "...", "mapping_profile": "..." }
}
```

The tracked illustrative example is
[`config/06_alignment_manifests/synthetic_session_alignment_manifest.json`](../../config/06_alignment_manifests/synthetic_session_alignment_manifest.json).
No synthetic filename is hard-coded anywhere in product logic.

Validation is strict and happens before any database work: the schema version
must be supported, the reference timebase must be among the declared timebases,
timebase and stream keys must be unique, at most one timebase may claim
`recording_native`, every stream's timebase must be declared, the recording must
be named exactly one way, and the method must be in the closed vocabulary.

A manifest declares clock metadata — kind, nominal rate, origin, clock identifier
— because no mapping profile owns it. A profile describes how to read a table;
it does not know a camera runs at 30 Hz.

### Manifest and profile must agree

A stream declaration names both `stream_key` and `timebase_key`, and the mapping
profile states the same two. A disagreement raises rather than being resolved:
one of the two documents is wrong about which clock a stream is on, and guessing
which would silently produce a defensible-looking alignment against the wrong
timebase.

## The recording-native audio timebase

Alignment **ensures** the recording has one native audio clock rather than
assuming it. Every recording created before this capability existed has none, and
requiring manual SQL to align one would make each fresh test database a special
case.

The rule is:

- if the recording already resolves a clock with `is_recording_native = 1`, reuse
  it, whatever it is named;
- otherwise create one from the manifest's `recording_native` declaration,
  inheriting `nominal_rate_hz` from `recordings.sample_rate_hz` when the manifest
  does not state one, and defaulting the origin to recording file time zero.

A second alignment over the same recording therefore reuses the clock. A second
native clock is never created — the schema's partial unique index would refuse it
anyway, and the point is not to reach that refusal.

Project intake was **not** changed to create the clock at recording creation. Its
Phase 3 identity and transaction contract are stable and tested, alignment is the
only consumer that needs the clock, and pre-Phase-7 recordings would still have
needed an ensurer.

## Timebase scope

A clock declared `recording_native` is scoped to its recording. Every other
declared clock is project-scoped, registered by `timebase_name` under
`recording_id IS NULL`.

Two streams may therefore share one `neural_native` clock, which is the common
case for a neural file carrying several event series. Registering an existing
project clock with a different `timebase_kind` raises rather than rewriting the
earlier declaration.

## What one apply registers

In one transaction:

| Target | Notes |
| --- | --- |
| `source_files` | manifest plus each declared data file, with SHA-256 |
| `config_profiles` / `config_profile_versions` | each mapping profile, checksum-bearing |
| `analysis_run_profiles` | profile versions linked to the alignment analysis |
| `timebases` | declared clocks, native one ensured |
| `analysis_runs` | one row, `run_type = 'temporal_alignment'` |
| `alignment_sets` | one row, `status = 'draft'`, manifest linked |
| `external_streams` | one logical stream per declaration |
| `external_stream_sources` | file and mapping-profile provenance per stream |
| `external_stream_coverage` | observed segments from the IR |
| `external_events` | native ID and label plus normalized `event_type` |
| `external_event_attributes` | declared attributes, missingness explicit |
| `alignment_anchors` | logical anchors, no timestamps |
| `alignment_anchor_observations` | one row per clock reading |
| `time_alignment_runs` | one `registered` row per non-reference clock observed |

Nothing is written to `alignment_segments`, `alignment_anchor_residuals`, or
`aligned_external_events`.

### Event identity

A native event ID supplied by the source is preserved. When the source supplies
none, the column is left NULL and the row is identified by its surrogate key. **No
synthetic native ID is invented**, because a fabricated identifier would later be
indistinguishable from one the source actually provided.

Anchor observations that cite an event resolve it by stream-scoped native ID,
because native IDs are unique only within their own source.

### Entity links

An event naming a subject is linked to an existing `experimental_entities` row
when one matches. An unmatched name is left unlinked. Experimental hierarchy
belongs to project intake, and inventing a subject from a behaviour table would
fabricate exactly the metadata this project exists to keep honest.

### Reused streams

A logical stream belongs to its recording, not to one alignment set. A second
alignment over the same session reuses the existing stream and does **not**
re-insert its coverage, events, or attributes; it resolves the already-registered
events for anchor references instead.

## Fit readiness

`n_anchors_used` on a registered run, and the `fit_ready_anchors` table in the
result, come from the IR's `anchor_fit_pairs`: a logical anchor counts only when
exactly one valid included observation exists on both clocks.

Unresolved duplicate observations are **kept, not discarded**. The IR marks
inclusion `NaN` when a duplicate group has no explicit resolution and raises
`ANCHOR_PRIMARY_AMBIGUOUS`, which makes the bundle not ready, so apply refuses.
The evidence stays available for correction rather than being silently averaged
or resolved by row order.

A registered observation whose inclusion could not be resolved is stored with
`included_in_fit = 0`. It is never promoted into the fit by default.

## Transactions, idempotency, and conflict

Apply requires an AutoCommit connection, disables AutoCommit, writes everything,
marks the analysis run completed, and commits. Any exception rolls back and
restores the original AutoCommit state before rethrowing. A failure part way
through leaves no analysis run, no alignment set, and no partial stream or anchor
population.

Rerunning an identical manifest returns `status = "reused"` and writes nothing.

Conflicts are explicit and never repaired in place:

| Situation | Behaviour |
| --- | --- |
| Same alignment key, different reference timebase | plan conflict |
| Same alignment key, different manifest | plan conflict |
| Existing run key with a different `run_type` | plan conflict |
| Declared source file changed content | raises `AlignmentSourceChanged` |
| Mapping profile version changed content | raises `AlignmentProfileChanged` |
| Declared source missing | raises `AlignmentSourceNotFound` |
| Anchor observes an undeclared clock | raises `AlignmentTimebaseUndeclared` |
| Existing project clock with a different kind | raises `AlignmentTimebaseConflict` |
| Mapped inputs not ready | raises `AlignmentNotReady` on apply |

Every one of these is detected during planning, before the transaction opens, so
a rejected registration writes nothing at all.

## Read-back

The result reports logical keys beside database identities so a caller never has
to query raw surrogate IDs: manifest summary with checksum, project and
recording, analysis and alignment-set identity, reference timebase, registered
timebases, streams with event/attribute/coverage counts, source and profile
provenance, anchor and observation counts, observations by timebase, fit-ready
anchors per source→reference pair, registered transform runs, and the structured
issues from mapping.

`transforms_fitted` is present and always `false` at this stage.

## Limitations

- The manifest reads delimited text tables (`.csv`, `.tsv`, `.txt`). Other formats
  must be supplied through the `Tables` option.
- Every column is read as text and left as written; type interpretation belongs to
  the mapping profile, which knows which column is a timestamp and in what unit.
- Coverage comes from the profile's declared segments. Mapping a separate
  coverage-segment table is not implemented.
- A stream supplied as an in-memory table has no file identity, so no
  `external_stream_sources` row is created for it.
- One source file maps to one logical stream per declaration. Several files
  composing one stream is representable in the schema but not yet driven from a
  manifest.
- All inputs exercised so far are synthetic. Nothing here has been run against a
  real paired session.
