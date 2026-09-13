# Imported caller-attribution intake

Added at Phase 4.8. The generic imported path — Path A in the development plan —
is the first thing to exercise the caller-attribution representation, and it
exists to be broken by real data before VAWLUME estimates anything itself.

```matlab
plan   = vawlume.ingest.attribution(conn, runRef, "path/to/caller_export.csv")
result = vawlume.ingest.attribution(conn, runRef, sourcePath, Apply=true)
```

The design reasoning is in
[`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md);
the representation is in
[`31_caller_attribution_schema.md`](31_caller_attribution_schema.md).

## What intake does, and the three things it refuses to do

Intake reads an external attribution table through a declared mapping profile,
maps it to the source-mapping IR, resolves caller labels against the run's
participating entities, and persists the imported windows with their provenance
in one transaction.

**It does not change the exporting system's numbers.** No rescaling, no
renormalization, no clamping, no promotion of a score to a probability because it
happened to fall in `[0,1]`. A re-normalized imported score is unauditable
forever: the original is gone. The profile cannot opt out of this — a profile
setting `mapping_policy.preserve_source_values` to false is refused.

**It does not infer what a caller label means.** A label is a string in somebody
else's file. Resolution is declared in the profile's `caller_label_resolution`
map or the row is refused; nothing matches on string similarity, case folding or
edit distance, and nothing creates an entity to accommodate an unrecognized
label. A label whose declared entity is not a participant of the run raises
`vawlume:attribution:CallerLabelUnresolved`, naming every offending label at once.

**It does not relate an imported window to a VAWLUME event.** Imported windows
land with their native timing intact, on the exporting system's own clock.
Associating them with a detection or consensus event is correspondence work with
its own eligibility rule and its own explicit transform. An import that quietly
matched windows to events would make every subsequent number rest on a
correspondence nobody declared.

## The mapping profile

`profile_kind` is `attribution_input_mapping`, schema version `0.3-draft`, and it
is registered and checksummed in `config_profile_versions` like every other
mapping profile. The shipped template is
[`generic_imported_attribution_profile.json`](../../config/01_mapping_profiles/attribution/generic_imported_attribution_profile.json).

| Block | What it declares |
|---|---|
| `context` | the window timebase key, the native time unit, and the exporting system's identity |
| `columns` | which source field carries `native_window_id`, `window_start`, `window_end`, `caller_label`, and optionally `score` and `probability` |
| `value_semantics` | what a `score` and a `probability` meant **where they came from** — required whenever the column is declared |
| `caller_label_resolution` | `policy: declared_only` and an explicit label-to-entity map |
| `mapping_policy` | `preserve_source_values`, and the unmappable-row policy |

The profile names roles, never vendor columns. Any attribution system reaches
VAWLUME through the same declaration by pointing each role at whatever it happened
to call it.

**The table shape is long: one row per (window, caller).** A system emitting one
row per window with several caller columns is a different shape and needs its own
profile. Guessing at a universal reshaper would silently mis-associate scores with
callers, which is the failure mode with no downstream symptom.

## The IR

Mapping produces two IR tables, and the split matters: a window is a statement
about **time**, a claim is a statement about an **animal**, and one window may
carry several claims.

| IR table | One row per |
|---|---|
| `attribution_windows` | distinct native window |
| `attribution_claims` | source row — a caller claim about one window |

No VAWLUME event key appears in either. A window is appended only once a claim
about it survives validation, so a refused claim never leaves an orphan window in
the plan — a time span nobody asserted anything about is not something the
exporting system said.

**Unmappable rows are reported, never dropped.** A reversed window, a missing
caller label, an undeclared label, and a probability outside `[0,1]` each produce
an issue naming the row and the reason. A preview that hides what it could not
read is worse than one that reads nothing.

## What is persisted

Planning is the default and writes nothing. `Apply=true` writes, in one
transaction:

- the source file with its **SHA-256 of the exact bytes**;
- the mapping profile version with its checksum;
- one `imported_attribution_windows` row per window, carrying native start and
  end, every caller label claimed over it verbatim, and pointers to the file and
  profile version.

An import applies **once per run**. Evidence is append-only and a second apply
would duplicate rather than reconcile, so a run already carrying imported windows
raises `vawlume:attribution:ImportAlreadyApplied`.

## What the schema cannot yet hold (P4-5)

This is the imported path doing its job, and it is the most useful thing this
itinerary produced.

**An imported claim's score has nowhere to be stored before correspondence
exists.**

- a **candidate** belongs to `(target, entity)`;
- an imported **claim** belongs to `(window, entity)`;
- mapping one onto the other requires knowing which window refers to which event.

Writing a candidate on every target of the run would assert that every window's
claim applies to every event, and would silently collapse two different scores for
one entity into whichever row happened to be written first. `imported_attribution_windows`
carries no `score` or `probability` column, and `attribution_evidence` requires a
target, so there is no third place to put it.

Intake therefore returns the claims in `result.claims` with their values intact
and stores none of them. The claims are not lost — they are re-derivable from the
source file, whose checksum is recorded — but they are not queryable until
correspondence runs.

The fix is either `score`/`probability`/`*_semantics` columns on
`imported_attribution_windows` keyed per caller, or a small
`imported_attribution_claims` table. Both need DDL, and the schema is at
`0.9-draft` with Phase 4's single bump spent.

## Refusals

| Identifier | Cause |
|---|---|
| `vawlume:attribution:SourceNotFound` | the named table does not exist |
| `vawlume:attribution:SourceUnreadable` | the table exists but cannot be read |
| `vawlume:attribution:ProfileKindInvalid` | the profile is not an `attribution_input_mapping` |
| `vawlume:attribution:ProfileInvalid` | the profile has validation errors |
| `vawlume:attribution:ProfileVersionConflict` | that profile version is registered with different content |
| `vawlume:attribution:RunPathMismatch` | the run's `attribution_path` is not `imported` |
| `vawlume:attribution:RunNotWritable` | the run is no longer `planned` |
| `vawlume:attribution:ImportAlreadyApplied` | the run already carries imported windows |
| `vawlume:attribution:CallerLabelUnresolved` | a declared label names no participating entity |
| `vawlume:attribution:ImportEmpty` | no row could be mapped; inspect the plan's issues |

## What an import proves

It proves that an external attribution table was read, and stored with enough
provenance to say where every value came from.

It proves nothing about whether any claimed caller called, whether the exporting
system's numbers are calibrated, or whether these windows refer to calls VAWLUME
detected. The last of those is the question the correspondence layer asks, and it
has not been asked yet.

## Related documents

- [`../design/04_caller_attribution_contract.md`](../design/04_caller_attribution_contract.md) — why imported windows are their own table
- [`31_caller_attribution_schema.md`](31_caller_attribution_schema.md) — the attribution data dictionary
- [`03_source_mapping_intermediate_representation.md`](03_source_mapping_intermediate_representation.md) — the IR and dry-run contract this reuses
- [`12_alignment_intake_and_registration.md`](12_alignment_intake_and_registration.md) — the importer this one is modelled on
- [`22_phase1_correspondence_boundaries.md`](22_phase1_correspondence_boundaries.md) — why attribution evidence and correspondence evidence stay apart
