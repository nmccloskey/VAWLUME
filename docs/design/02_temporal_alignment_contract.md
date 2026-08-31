# Temporal Alignment and Sequence-Ready Timeline Contract

## Status

**Implementation checkpoint.** The normalized relational grammar, the
database-free external-event/anchor source-mapping layer, session-manifest intake
and registration, and source-to-reference transform fitting with residual QC are
implemented. **Common-time projection of events and regularized timelines remain
design targets.**

This document is the governing contract for VAWLUME's first external-stream
temporal-alignment implementation. It defines vocabulary, invariants, schema
direction, the input/output boundary, and exit criteria, and it records an audit
of what the inherited draft schema already supports.

The original pairwise alignment draft has been replaced by timebases, logical
streams and sources, events and attributes, coverage, alignment sets, logical
anchors and observations, pairwise transforms, and per-anchor residual evidence.
Versioned JSON mapping profiles normalize synthetic external event and long/wide
anchor tables into one validated IR; a compact session manifest registers that IR
transactionally; and offset and affine transforms are fitted from explicit
logical anchors, recovering known synthetic parameters to within floating-point
noise. Fits are recorded as `estimated`, never `validated`.

No VAWLUME code yet materializes an aligned event timestamp or builds a
regularized timeline. `vawlume.alignment.applyTransform` derives aligned times on
demand from the stored transform, which remains the authority.

Read this document before changing anything under the alignment tables. Read
`07_matching_and_consensus.md` in `docs/development/` for what the correspondence
layer beneath it already guarantees.

## Emphasis: alignment first

This phase is an **alignment phase**, not a sequence-analysis phase.

The goal is to make heterogeneous event streams expressible on a user-selected
reference timebase while preserving native timestamps, source provenance, anchor
evidence, and fit diagnostics — plus the minimum regularized-timeline foundation
needed to prove that aligned vocalization, behavioral, and neural events can be
coordinated in common bins.

The following are **explicitly deferred to a later phase** and must not be
pre-implemented here: transition matrices, transition entropy, n-grams, motif
discovery, edit distance, string alignment, sequence clustering, NLP- or
bioinformatics-style sequence methods, broad bout analysis, hierarchy-aware
inference, and machine learning.

This is a deliberate reframing of what the Phase 6 exit documentation called
"one compact sequence/alignment analysis." Sequence analysis over vocalization
events is only meaningful once those events and the behavioral or neural events
they are being related to share a defensible common clock. Building the ordering
machinery first would mean ordering events whose relative timing is not yet
established. Alignment is therefore the prerequisite, and it is large enough to
own a phase.

## Motivating workflow

```text
VAWLUME vocalization detections / consensus events
+ external behavioral event table(s)
+ external neural event / TTL table(s)
+ optional video event / annotation table(s)
+ a session-specific alignment manifest
+ explicit cross-stream anchor observations
                    ↓
source mapping / registration
                    ↓
VAWLUME operational ontology
    timebases
    external streams
    events + attributes + coverage
    logical anchors + observations
                    ↓
temporal alignment
    user-selected reference timebase
    source → reference transforms
    residuals / QC evidence
                    ↓
common-time event views
    native timestamps preserved
    aligned timestamps derived
                    ↓
regularized timeline view
    explicit bin width / origin / rules
    event absent ≠ not observed
```

## Core vocabulary

### Reference timebase, not ground truth

The user chooses a **reference timebase** for an alignment set, and VAWLUME
expresses the participating source clocks relative to it. The designation is a
coordinate choice. It does not assert that the reference device is physically
perfect or scientifically privileged, and nothing in the implementation may
treat it as more correct than the clocks aligned to it.

Vocabulary stays at the timebase level rather than the modality level. A neural
file may contain several event streams sharing one device clock; a video file
may contain annotations and sync-light events sharing another. Alignment
operates on clocks, not on file types, extractor names, or modality labels.

### Synchronization anchor versus experimental event

A **synchronization anchor** establishes a relationship between clocks. An
**experimental event** occurs on one of those clocks. These are different kinds
of object and must not be conflated.

A light/tone/TTL combination used to coordinate streams is an alignment anchor
even when it happens to fire near a scientifically interesting transition. If a
`female_entry` event is scored separately from video, it is an experimental
event and must not be forced to equal the synchronization edge that happened to
occur nearby.

### Logical anchor versus anchor observation

One **logical anchor** may be **observed** on several timebases:

```text
sync_03
  audio observation    t = 12.004
  video observation    t = 11.876
  neural observation   t = 302.551
```

It may also carry redundant observations on a single timebase. Those
observations are preserved rather than prematurely averaged, because the spread
between them is evidence about synchronization quality.

For the prototype, fitting requires an explicit primary or included observation
wherever duplicates would otherwise make the correspondence ambiguous.
Replicates remain QC evidence.

### Native events versus normalized operational labels

Phase 7 does not create a universal behavioral or neural ontology. It needs a
domain-agnostic operational representation carrying:

- stream and timebase identity;
- native event identity and label;
- optional normalized project event key;
- native start and end time;
- optional entity/subject link;
- optional scalar value;
- extensible attributes;
- source location and mapping provenance.

Native labels stay inspectable even when a mapping profile supplies a normalized
key. This is the same additive rule the extractor layers already follow:
normalization never destroys the native record.

## Timebase contract

Every VAWLUME audio recording resolves **one unambiguous native recording
timebase**. Vocalization detections and consensus-event times inherit that clock
through the recording. They must not gain redundant `timebase_id` columns.

External streams reference their timebase explicitly.

## Alignment-set contract

A user-facing multimodal alignment operation is an **alignment set**:

```text
alignment set
  reference timebase = neural_native
  source audio-native timebase
  source video-native timebase
  logical anchors + observations
  audio → neural transform
  video → neural transform
```

The set is associated with one analysis-run identity and with the exact
manifest and configuration evidence used. **Pairwise transforms are children of
the set, not independent user-facing analyses.** This mirrors the parent/child
analysis pattern Phase 6 already established between a matching analysis and its
agreement child.

## Source-mapping and manifest boundary

Two distinct responsibilities.

### Reusable mapping profiles

Versioned JSON profiles explain how to interpret user tables: timestamp column,
optional end-time column, native event ID column, native label/type column,
normalized event mapping, units, attribute columns, coverage declarations,
anchor ID column, stream/timebase column, and wide-versus-long anchor layout.

`+source_mapping` extends its validated, provenance-bearing IR as needed and
**remains database-write-free**.

### Session-specific alignment manifest

The manifest identifies one concrete alignment operation:

```json
{
  "recording_key": "synthetic_session_01",
  "reference_timebase": "neural_native",
  "streams": [...],
  "anchor_source": {...},
  "method": "affine"
}
```

A manifest is not a reusable semantic profile. It is treated as a
provenance-bearing source/artifact linked to the alignment set, while reusable
external-stream and anchor mapping rules remain versioned mapping profiles.

No `alignment_manifest` profile kind is added merely to force a session-specific
file into the reusable-profile ontology. The audit below confirms this is
unnecessary: `config_profiles.profile_kind` already offers
`external_stream_mapping` for the reusable half, and `artifacts` / `source_files`
already carry path plus SHA-256 for the session-specific half.

A manifest designates a reference timebase and participating sources. It does
not embed table data.

## Supported transform scope

Only transparent models.

### Offset-only

```text
t_ref = t_source + offset
```

Scale is fixed at 1. With several included anchors, the least-squares offset is
the mean of target minus source.

### Affine shift and scale

```text
t_ref = scale * t_source + offset
```

Two distinct included anchors identify an exact affine solution; three or more
permit residual assessment. Fitting is transparent ordinary least squares.

**Not in this phase:** robust regression, automatic outlier rejection, dynamic
time warping, nonlinear warping, learned synchronization.

### Piecewise affine

The schema may retain representability for piecewise-affine segments, but
**fitting piecewise transforms is deferred.** If a caller requests it through the
Phase 7 API, the implementation fails clearly rather than silently degrading to
a single affine fit.

## Anchor-selection rule

VAWLUME must not silently infer anchor correspondence by nearest timestamp or by
pulse order when the user has supplied explicit anchor identities or a
crosswalk. Implicit nearest-neighbour correspondence is exactly the kind of
convenient guess that produces a confident, wrong alignment.

For each source → reference fit, an included logical anchor resolves to one
included source observation and one included reference observation. Where
duplicate observations make the pair ambiguous, explicit resolution or exclusion
is required, and all observations are preserved for auditing.

## QC contract

**The transform is authoritative. Aligned timestamp materializations are derived
caches.**

Each fit preserves at least:

- method;
- scale and offset;
- number of anchors used;
- per-anchor observed source and reference times;
- predicted reference time;
- residual in seconds;
- RMSE;
- maximum absolute residual;
- inclusion/exclusion status and reason;
- manifest, profile, and analysis provenance.

No threshold is described as calibrated unless it is. Any validation tolerance
shipped in a synthetic example is clearly labelled illustrative — the same rule
Phase 6 applies to its matching thresholds.

## Coverage and regularized-timeline semantics

A regularized timeline distinguishes three states, and conflating the second
with the third is the specific failure this section exists to prevent:

1. **event present** — one or more relevant events occurred in the bin;
2. **event absent** — the stream is known to have been observed across the bin,
   and no relevant event occurred;
3. **not observed / unavailable** — stream coverage does not establish
   observation for the bin.

Phase 7 therefore represents stream coverage explicitly, using an interval
representation able to express more than one observed segment. Assuming every
source covers one uninterrupted interval forever would silently convert
unavailable bins into absent ones.

The regularized timeline is a **derived working representation**, normally a
MATLAB table or timetable. Millions of blank bins are not persisted as canonical
SQLite evidence.

Every regularization records and returns its specification: reference timebase,
start/end window, bin width, bin origin and edge convention, source event sets,
aggregation rule (`onset_count`, `any_overlap`, and so on), and the handling of
uncovered bins.

## Non-goals

Not in this phase:

- full continuous neural-signal ingestion;
- sample-by-sample photometry or miniscope storage in SQLite;
- acquisition-system synchronization control;
- automatic anchor detection from waveform or video pixels;
- nearest-pulse automatic cross-stream matching;
- nonlinear time warping;
- automatic scientific interpretation of event labels;
- a universal behaviour ontology;
- full sequence persistence redesign;
- transition matrices, transition entropy, n-grams, motifs, edit distance,
  string alignment, sequence clustering, or NLP/bioinformatics experiments;
- broad bout analysis;
- hierarchy-aware inference or machine learning;
- GUI or manual annotation tooling;
- use of real pilot data as a tracked fixture.

## Inherited schema audit

The eleven draft tables were inspected against this contract. The audit is
recorded here because it is the direct input to the schema pass, and because
"the tables already exist" is misleading: several represent a **pairwise,
single-observation** model that structurally cannot express what this contract
requires.

### Concept coverage

| Concept required | Current representation | Verdict |
|---|---|---|
| Timebase | `timebases` | Present; needs a constrained kind vocabulary and a working uniqueness rule |
| Logical stream | `external_streams` | Present, but fused with its source |
| Stream source | fused into `external_streams` (`source_file_id`, `artifact_id`, `mapping_profile_version_id`) | Not separated |
| External event | `external_events` | Present; no normalized project key, no attributes |
| Event attributes | — | **Missing** |
| Stream coverage | — | **Missing** |
| Logical anchor identity | — | **Missing** |
| Anchor observation | — | **Missing** |
| Alignment set | — | **Missing** |
| Pairwise transform | `time_alignment_runs` + `alignment_segments` | Partial; scale/offset live only in segments |
| Per-anchor residual evidence | — | **Missing** |
| Aligned event materialization | `aligned_external_events` | Present |

### Specific findings

1. **`alignment_anchors` cannot express a multi-timebase anchor.** Each row is a
   flat `(source_time, target_time)` pair scoped to one pairwise run. There is no
   logical anchor entity, so one anchor observed on three timebases is
   unrepresentable except as unrelated pairwise rows, and redundant observations
   on one timebase cannot be distinguished from separate anchors. The row also
   carries no predicted time, residual, inclusion status, or exclusion reason.
   This blocks definition-of-done items 7 and 9.

2. **There is no alignment set.** `time_alignment_runs.analysis_run_id` is
   `NOT NULL UNIQUE`, which forces every pairwise transform to be its own
   analysis run. That directly contradicts the alignment-set contract, under
   which pairwise transforms are children of one reference-bearing set.

3. **There is no coverage representation**, so `absent` cannot be distinguished
   from `unavailable`. This blocks item 12 and therefore item 13.

4. **`timebases UNIQUE(project_id, recording_id, timebase_name)` does not
   constrain project-scoped timebases.** SQLite treats NULLs as distinct in a
   UNIQUE index, so rows with `recording_id IS NULL` can be duplicated freely.
   `external_streams UNIQUE(project_id, stream_name, source_file_id)` has the
   same defect for streams with no source file.

5. **Nothing guarantees one native audio timebase per recording.**
   `timebase_kind` is unconstrained TEXT with no vocabulary and no uniqueness on
   the native-audio role, so item 2's "one unambiguous native recording
   timebase" is currently a convention rather than an invariant.

6. **`external_events` has `event_type` only.** There is no place for a
   normalized project event key alongside the native label, and no attributes
   table, so the operational representation above is not yet expressible.

7. **Transform parameters live only in `alignment_segments`.** An offset-only or
   global affine fit has to be encoded as a single segment row. Workable, but the
   schema pass should decide deliberately whether a global fit is first-class or
   always a one-segment case, rather than leaving it implicit.

8. **The schema header comment says `Version: 0.1-draft` while `schema_info`
   seeds `0.2-draft`** (with `PRAGMA user_version = 2`). Pre-existing
   inconsistency; worth correcting when the version is next bumped.

### Already correct — preserve

- **`detections` carries no `timebase_id`.** Item 2's "without redundant
  timebase FKs on every detection" already holds structurally. `detections` has a
  free-text `timing_basis` and inherits its clock through `recording_id`.
- **`analysis_runs` supports the set/child pattern.** `run_type` is free text and
  `parent_analysis_run_id` exists, with the Phase 6 matching → agreement
  parent/child relationship as working precedent.
- **`config_profiles.profile_kind` already included `external_stream_mapping`.**
  Pass 3 added `alignment_anchor_mapping` because long/wide anchor layout and
  required observation identity are materially different from event-stream
  rules. No `alignment_manifest` kind was added.
- **`artifacts` and `source_files` carry `path_or_uri` plus `checksum_sha256`.**
  A session manifest can be registered as provenance-bearing evidence without
  inventing an `alignment_manifest` profile kind.
- **`+source_mapping` is verified database-free.** It exposes no connection
  argument and calls no SQLite, `fetch`, `execute`, or `sqlwrite` API. This
  invariant must survive the phase.
- **`mapTableToIR` already accepts an arbitrary MATLAB table plus a profile** and
  returns the validated IR, so external event and anchor tables need a profile
  kind and validation rules rather than a new entry point. Its documented
  vocabulary now includes `external_stream_mapping` and
  `alignment_anchor_mapping` beside the inherited two kinds.
- **`external_streams.stream_kind`** already permits `event`, `annotation`,
  `video`, `ttl`, `continuous`, and `other`, covering the motivating workflow.
- **`sequences`, `sequence_members`, `bouts`, and `bout_members` are entirely
  unused** — no fixture rows, no tests beyond a view-name check. They can be left
  untouched while sequence analytics is deferred.

### Compatibility constraint

The Phase 1 synthetic fixture populates `timebases`, `external_streams`,
`external_events`, `time_alignment_runs`, `alignment_anchors`,
`alignment_segments`, and `aligned_external_events`, and acceptance query **Q12
("External event alignment")** reads `v_external_events_aligned`. Any schema
change must keep the fixture and Q12 working, or update both deliberately and
say so.

The fixture's transform — `scale = 1`, `offset = 0.55 s`, two anchors, RMSE
0.001 s — is exactly the shape the transform-fitting pass will fit, which makes
it a natural regression target rather than an obstacle.

## Definition of done

Phase 7 passes only when all of the following hold:

1. the schema cleanly distinguishes timebases, logical streams, stream sources,
   events, anchor identities, anchor observations, alignment sets, pairwise
   transforms, and residual evidence;
2. every VAWLUME recording resolves one native audio timebase without redundant
   timebase FKs on every detection;
3. external event and anchor tables can be mapped through versioned JSON mapping
   rules while preserving native values, labels, and source provenance;
4. `+source_mapping` remains database-write-free;
5. a session-specific manifest can designate a reference timebase and
   participating sources without embedding table data;
6. source mapping and ingest can register at least synthetic audio,
   video/behavioural, and neural/TTL clocks and events plus anchor observations;
7. one logical anchor can have observations on three or more timebases and can
   preserve redundant observations without pretending they are independent
   logical anchors;
8. offset-only and affine source → reference transforms are fitted
   deterministically from explicit anchors;
9. fit diagnostics and per-anchor residuals are stored and read back with
   provenance;
10. native event and detection timestamps are never overwritten by alignment;
11. calls/consensus events and external events can be projected into one
    reference-time representation through authoritative transforms;
12. stream coverage permits `absent` to be distinguished from `unavailable` in a
    regularized timeline;
13. a small configurable regularization demonstrates aligned vocalization plus
    external events in common bins without making the dense timeline canonical
    SQLite storage;
14. an end-to-end synthetic demonstration reconstructs known transforms and
    produces auditable aligned event and timeline output;
15. upstream Phase 1–6 behaviour remains passing;
16. durable documentation describes the new capability without claiming complete
    multimodal synchronization or broad sequence analytics.

## Pass sequence

```text
contract  (this document)
        ↓
alignment schema and timebase ontology
        ↓
external-stream and anchor source mapping
        ↓
alignment intake and registration
        ↓
transform fitting and alignment QC
        ↓
common-time views and regularized-timeline demonstration
        ↓
integration review and exit gate
```

Each pass leaves a reviewable checkpoint and a handoff recording files changed,
tests and results, Git state, decisions, assumptions, unresolved issues, and
minimum next-pass context.

## Inherited regression floor

The state this phase builds on:

```text
265 tests passing, 0 failed, 0 incomplete
checkcode clean across the repository
PRAGMA foreign_key_check clean
```

No Phase 6 limitation blocks this phase.
