# DeepSqueak Import

## Purpose and status

DeepSqueak import is the transactional boundary between a DeepSqueak Excel
call-statistics export and VAWLUME's relational extraction-run, artifact,
detection, measurement, review, and label model.

It is the first real extractor importer. It is a proof of the architecture, not
a licence to make the relational model DeepSqueak-shaped: everything
extractor-specific lives in the tracked mapping profile and the seeded semantic
vocabulary, and the importer reads those rather than restating them.

The supported flow is:

```text
DeepSqueak call-statistics .xlsx
        |
        v
vawlume.ingest.deepsqueakExport          (adapter: workbook mechanics only)
        |
        v
vawlume.source_mapping.mapTableToIR      (profile-driven field semantics)
        |
        +--> vawlume.source_mapping.preview   (read-only readiness)
        |
        v
vawlume.ingest.deepsqueak                (plan or atomically apply)
        |
        v
SQLite extraction-run and event graph
```

## Public API

```matlab
result = vawlume.ingest.deepsqueak(conn, artifactPath, recordingRef, runSpec)
result = vawlume.ingest.deepsqueak(..., Apply=true)
result = vawlume.ingest.deepsqueak(..., RepoRoot=, ArtifactRoot=, RelativePath=, ...
    ProfilePath=, Profile=, Sheet=)
```

Planning is the default and writes nothing. `Apply=true` commits a
conflict-free plan in one transaction; on a conflicting plan it returns the
conflict and writes nothing.

A read-only adapter entry point is also public:

```matlab
export = vawlume.ingest.deepsqueakExport(artifactPath, RepoRoot=repoRoot)
```

It performs no database access and is useful for inspecting a workbook before
importing it. All other Phase 4 helpers are package-private under
`src/+vawlume/+ingest/private/` and are implementation details.

A runnable demonstration is at `examples/deepsqueak_import_demo.m`.

## Supported artifact scope

| Supported | Not supported |
|---|---|
| DeepSqueak Excel call-statistics export (`event_stats_excel`) | native `.mat` detection containers as a data source |
| the tracked `vawlume.deepsqueak.output.v3_2` profile, version scope 3.2.x preferred within family 3.x | arbitrary workbook shapes, or every DeepSqueak version |
| registering a native `.mat`, settings file, or detector model as provenance | parsing any of them |
| extractor-native labels as opaque evidence | DeepSqueak classifier or clustering workflows |

MUPET event population, cross-extractor matching, and consensus are not part of
this importer. The separate MUPET CSV adapter and read-only provenance planner
are documented in `06_mupet_import.md`.

## Layer responsibilities

```text
adapter          file-format mechanics: readability, sheet selection, header row,
                 name-preserving read, artifact checksum
source_mapping   field semantics: canonical names, units, transforms, value maps,
                 missing-value policy, declared aliases
importer         relational identity, provenance, and atomic application
```

The adapter holds no canonical feature name, no native column dictionary, and
no unit conversion. The importer holds neither. Both facts are enforced by
tests, not only by convention.

Two authorities decide where mapped evidence lands, and neither is a list in
importer code:

- the **registered feature dictionary**, because seed registration promoted
  exactly the profile's `event_measurement` mappings into `extractor_features`;
- the profile's **`semantic_role`**, carried through the IR.

Detection geometry is selected by profile-declared **`equivalence_class`**
(`vocalization_start_time`, `vocalization_end_time`), which is the
extractor-independent vocabulary the profiles and seeded feature relationships
already share.

## `recordingRef` and `runSpec`

A DeepSqueak import attaches to a recording that project intake already
established. It never creates a project, source file, recording, entity, or
participant link.

```matlab
recordingRef = struct(recording_id=42)
recordingRef = struct(project_key="proj", source_relative_path="audio/day1/REC_A.wav")
```

Exactly one mode; declaring both is an error. The workbook basename, the
export's `File` column, and folder conventions are never used to infer the
recording.

`runSpec` declares only what a call-statistics export cannot state about itself:

| Field | Required | Meaning |
|---|---|---|
| `run_key` | yes | stable identity of this extraction run, unique within the project |
| `extractor_version` | by profile | required because the tracked profile declares `extractor.version_required_at_ingest` |
| `run_label`, `notes`, `status` | no | descriptive |
| `started_at_utc`, `completed_at_utc` | no | recorded only when genuinely known; never inferred from file timestamps |
| `settings` | no | `struct(profile_path=...)` for a VAWLUME settings profile, or `struct(artifact_path=...)` for an external native settings file |
| `model` | no | `struct(artifact_path=..., model_label=...)` |
| `native_artifact` | no | `struct(artifact_path=...)`; registered, not parsed |
| `classification` | no | `struct(method=..., run_label=...)` when the labelling method is actually known |

## Durable identity

| Object | Identity |
|---|---|
| extraction run | project plus explicit `run_key` |
| artifact | project plus portable `path_or_uri`, with checksum comparison |
| detection | extraction run, recording, source artifact, and native call ID |
| event measurement | detection plus registered extractor feature |
| curation event | detection plus action type |
| classification assignment | detection plus classification run |

Artifact identity requires a **portable** path, derived from an explicit
`RelativePath`, or from `ArtifactRoot`, or from `RepoRoot`. An absolute runtime
path is never durable identity, because relocating the same content would then
duplicate it. When no portable path can be derived the import is refused rather
than falling back.

An explicit `RelativePath` must itself be root-independent: drive-qualified,
rooted, and parent-traversing (`..`) values are refused rather than persisted
under a portable label.

The stored `path_or_uri` is the portable path first registered. A later rerun
from a different location reports its runtime path diagnostically and does not
rewrite that provenance.

Row order is never identity. The workbook row survives as provenance in
`detections.notes` and in each measurement's `source_locator`.

## Extractor version and feature scope

Two distinct version concepts are both recorded:

- **run version**: the exact DeepSqueak version the caller declares, stored as
  `extraction_runs.extractor_version_id`;
- **feature scope version**: the profile's declared compatibility scope, which
  seed registration attached `extractor_features` to.

They coincide only when the caller declares the scope label itself. Both are
reported on the result, so the exact software version and the feature semantics
each stay answerable. Measurements resolve their feature identity against the
scope row.

## Rerun, relocation, and conflict

| Scenario | Outcome |
|---|---|
| identical rerun | every row reused; nothing written; still reports committed |
| same content under a different absolute root | run and artifact reused; no duplication |
| same run key, changed export content | explicit conflict; nothing written |
| same basename at a different portable path | a distinct artifact; never conflated by filename |
| a different run key over the same recording | a distinct run with its own detections, reusing native call IDs |
| same run key, changed/added/omitted settings, model, or native artifact | explicit provenance conflict; nothing written |

A changed export under one run identity is a conflict even when native call IDs
match, and existing scientific rows are never updated in place. Resolving such a
conflict requires an explicit migration workflow, which does not exist yet.

A new run key does not rescue a conflicting artifact identity, because artifacts
are project-scoped rather than run-scoped.

Every identity-bearing run artifact is compared by role, portable identity,
type, and checksum. One portable identity cannot be declared for two different
roles in the same plan. Supplied files are hashed with streaming SHA-256, so
large native containers and detector models retain content identity without
being loaded wholly into memory.

Reordering a workbook's rows changes its bytes and therefore its checksum, so it
is reported as a content change. That strictness is deliberate: the checksum is
the honest record of what was imported.

## Field destinations

| Export column | Declared role | Destination |
|---|---|---|
| `ID` | `identifier` | `detections.native_event_id` |
| `Begin Time (s)`, `End Time (s)` | event geometry by equivalence class | `detections.start_time_s` / `end_time_s`, **and** `event_measurements` |
| `Score` | `detector_model_score` | `detections.detection_score`, **and** `event_measurements` |
| 14 registered features | registered `extractor_features` | `event_measurements` |
| `Accepted` | `curation_state` | `curation_events` |
| `Label` | `native_class_or_manual_label` | `classification_*` (see below) |
| `File` | `artifact_locator` | provenance corroboration only |

Native values, native units, canonical values, canonical units, transform keys,
operational variants, and raw lexical tokens are all preserved on every
measurement. A blank cell becomes explicit missingness with no typed payload and
no fabricated zero.

## Review and label semantics

`Accepted` is DeepSqueak's own review state, not biological ground truth. It
becomes a `curation_events` row with `actor_type = 'extractor'` and the profile's
canonical `accepted` / `rejected` vocabulary, with the native token retained. No
human reviewer is invented, because the export states only a state. Rejected
calls are still imported: review state is evidence, not a filter.

`Label` is preserved through `classification_runs`, `classification_classes`, and
`classification_assignments`, because that is the only schema surface that can
answer "what label evidence exists". A DeepSqueak label may be manual,
supervised, or clustering-derived and the export does not say which, so the run
is recorded with `method = 'native_label_unspecified_provenance'`,
`model_artifact_id` NULL, and `canonical_class_label` NULL. The native token is
preserved exactly and acquires no biological meaning. A caller who knows the
method can declare it through `runSpec.classification`.

## Settings and model provenance

Settings provenance is recorded where recoverable and left absent otherwise. It
is never fabricated:

| Supplied | Recorded | `settings.status` |
|---|---|---|
| a VAWLUME settings profile | `config_profiles` (kind `extractor_settings`, project-scoped) plus a version, linked on the run | `captured_profile` |
| an external native settings file | an `artifacts` row with role `extractor_settings` | `captured_artifact` |
| nothing | `settings_profile_version_id` stays NULL | `not_recoverable` |

An extractor **settings** profile and an extractor-**output mapping** profile are
never conflated; they occupy separate columns on `extraction_runs` and separate
`profile_kind` values.

A detector model row is created only from explicitly supplied model context. A
model is never inferred from the DeepSqueak version, the machine's defaults, or
the export's score column.

## Transaction semantics

One function owns one transaction for the whole import. Apply requires a
connection entering with autocommit enabled, then writes in schema-dependency
order:

```text
settings profile and version
extractor version (only if not already registered)
artifacts: export, native container, settings file, model
extraction run
extraction run inputs        <- required before any detection
extraction run artifacts
classification run and classes
detections
event measurements
curation events
classification assignments
```

Any failure rolls the whole thing back, restores autocommit, and rethrows, so an
extraction run never exists without the calls it produced. A compatible rerun
writes nothing at all, and no per-attempt audit row is recorded: unlike project
intake, a DeepSqueak import is all-or-nothing over one artifact, and
`extraction_runs.imported_at_utc` plus the export checksum already record what
was imported and when the run was created.

Reuse compares stored detection, measurement, curation, and native-label
evidence rather than checking only that a row exists. Missing, duplicated, or
changed scientific child rows are conflicts; the importer does not silently
repair or reinterpret an existing run.

## Validation and diagnostics

Profile-declared `validation.checks` decide which checks exist and how serious
each is. Error-severity checks run as preflight, so a bad export is refused
before any write rather than aborting mid-transaction:

| Check | Severity | Effect |
|---|---|---|
| `event_time_order` | error | blocks the import |
| `frequency_order` | error | blocks the import |
| `native_event_id_uniqueness` | error | blocks the import |
| `duration_consistency` | warning | reported; both values stored as exported |
| `bandwidth_consistency` | warning | reported; both values stored |

Timing is never repaired from another field. A duration disagreeing with end
minus start is reported, and both remain as the extractor wrote them.

`result.diagnostics` labels every non-fatal finding with the layer that raised
it: `adapter`, `source_mapping`, `preflight`, `identity`, or `apply`. Conditions
that make a plan untrustworthy are raised as exceptions with namespaced
identifiers instead, so an inspectable result always describes a genuinely
possible import. Identity conflicts are the deliberate exception and are
returned in `result.conflicts`.

## Relational read-back

Every imported detection has an unambiguous query path to its recording,
project and experimental context, the device and setup profiles the recording
inherited, the extraction run, the exact extractor version, the output mapping
profile version and checksum, the call-statistics artifact and checksum, any
settings and model provenance, its native call ID, native field values and
units, canonical mappings and transforms, and its review and label evidence.

`v_detection_core` answers run, recording, native ID, timing, and score
directly. `v_event_measurements_long` answers native and canonical measurement
detail; reading it by native call ID needs one join to `detections`.

## Current limitations

- Only the Excel call-statistics export is read. Native `.mat` containers,
  detector networks, and classifier models are registered as provenance but not
  parsed.
- No `extractor_objects` rows are created, because the profile's declared
  `hierarchy_emitted` for this artifact does not include a container object.
- Every mapped column is effectively required. The shipped profile marks none
  optional, so a genuine pre-v3.1 export lacking the `File` column cannot be
  imported even though the profile declares family 3.x compatibility.
- Undeclared source columns are reported as warnings but their per-row values
  are not yet preserved into `unmapped_source_values`.
- The profile's `review_status_domain` and `source_recording_linkage` checks are
  reported as unevaluated; a general evaluator for profile-declared check
  expressions does not exist. `source_recording_linkage` is enforced in practice
  by explicit recording resolution.
- Unparseable text in a numeric column is collapsed to a missing value by
  MATLAB's table reader, so it is diagnosed as missing rather than invalid. The
  import is still refused when a required value is affected.
- Conflicting existing scientific rows block re-import; an explicit migration or
  revision workflow is future work.
- No audio technical metadata is enriched during import.

None of these limits the demonstrated DeepSqueak contract or the MUPET boundary.
